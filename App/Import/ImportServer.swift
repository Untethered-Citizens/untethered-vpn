import Foundation
import Network
import os

private let log = Logger(subsystem: "com.untetheredcitizens.vpn", category: "import-server")

/// The one-time web server behind the QR import (brief § 5.3). It listens
/// only on the TV's local network address, answers one `ImportSession`, and
/// stops for good after a valid import, a cancel, the time limit, or too
/// many bad requests. It never logs a request, the token or the key.
///
/// All state lives on a private serial queue. Events arrive on that queue;
/// hop to the main actor before touching UI.
final class ImportServer: @unchecked Sendable {

    static let sessionDuration: TimeInterval = 5 * 60
    static let connectionTimeout: TimeInterval = 10
    static let maxConnections = 4

    enum Ending: Equatable, Sendable {
        case imported(ImportedProfile)
        case cancelled
        case timedOut
        case tooManyBadRequests
        /// The TV has no local network address, or listening failed.
        case failed
    }

    enum Event: Equatable, Sendable {
        /// Listening; show `url` as the QR code until `expires`.
        case ready(url: URL, expires: Date)
        /// Stopped; nothing is listening any more. Always the last event.
        case ended(Ending)
    }

    enum Binding: Sendable {
        /// The TV's address on Ethernet or Wi-Fi (`LocalAddress`).
        case localNetwork
        /// 127.0.0.1, for tests.
        case loopback
    }

    private let queue = DispatchQueue(label: "com.untetheredcitizens.vpn.import-server")
    private let binding: Binding
    private let sessionDuration: TimeInterval
    private let connectionTimeout: TimeInterval
    private let onEvent: @Sendable (Event) -> Void

    // Only touched on `queue`.
    private var session: ImportSession
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var hasEnded = false

    init(session: ImportSession,
         binding: Binding = .localNetwork,
         sessionDuration: TimeInterval = ImportServer.sessionDuration,
         connectionTimeout: TimeInterval = ImportServer.connectionTimeout,
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.session = session
        self.binding = binding
        self.sessionDuration = sessionDuration
        self.connectionTimeout = connectionTimeout
        self.onEvent = onEvent
    }

    /// The page and its scripts from the app bundle, keyed by their path
    /// under the token.
    static func bundledAssets(in bundle: Bundle = .main) -> [String: ImportSession.Asset] {
        let files: [(path: String, name: String, ext: String, type: String)] = [
            ("", "import", "html", HTTPResponse.html),
            ("nacl.js", "nacl", "js", HTTPResponse.javaScript),
        ]
        var assets: [String: ImportSession.Asset] = [:]
        for file in files {
            if let url = bundle.url(forResource: file.name, withExtension: file.ext),
               let data = try? Data(contentsOf: url) {
                assets[file.path] = ImportSession.Asset(data: data, contentType: file.type)
            }
        }
        return assets
    }

    func start() {
        queue.async { self.startOnQueue() }
    }

    /// Stops listening and closes every connection. Safe to call more than once.
    func stop() {
        queue.async { self.end(.cancelled) }
    }

    // MARK: - On the queue

    private func startOnQueue() {
        guard listener == nil, !hasEnded else { return }
        let host: String
        switch binding {
        case .loopback: host = "127.0.0.1"
        case .localNetwork:
            guard let address = LocalAddress.current() else {
                log.error("No local network address")
                return end(.failed)
            }
            host = address
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            log.error("Couldn't create the listener: \(error.localizedDescription, privacy: .public)")
            return end(.failed)
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let port = listener.port?.rawValue else { return self.end(.failed) }
                log.info("Listening")
                let expires = Date().addingTimeInterval(self.sessionDuration)
                self.queue.asyncAfter(deadline: .now() + self.sessionDuration) { [weak self] in
                    self?.end(.timedOut)
                }
                self.onEvent(.ready(url: self.session.url(host: host, port: port), expires: expires))
            case .failed(let error):
                log.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                self.end(.failed)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        guard !hasEnded, connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.connections[id] = nil
            default: break
            }
        }
        connection.start(queue: queue)
        // A connection that hasn't finished its request in time is closed,
        // so a slow or idle client can't hold one of the few slots.
        queue.asyncAfter(deadline: .now() + connectionTimeout) { [weak self] in
            if self?.connections[id] != nil { connection.cancel() }
        }
        receive(on: connection, parser: HTTPRequestParser())
    }

    private func receive(on connection: NWConnection, parser: HTTPRequestParser) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.hasEnded else { return connection.cancel() }
            var parser = parser
            let result = data.map { parser.append($0) } ?? .incomplete
            switch result {
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, parser: parser)
                }
            case .rejected(let status):
                self.carryOut(self.session.rejected(status), on: connection)
            case .complete(let request):
                self.carryOut(self.session.handle(request), on: connection)
            }
        }
    }

    private func carryOut(_ outcome: ImportSession.Outcome, on connection: NWConnection) {
        let response: HTTPResponse
        var ending: Ending?
        switch outcome {
        case .respond(let reply):
            response = reply
        case .imported(let reply, let profile):
            response = reply
            ending = .imported(profile)
        case .tooManyBadRequests(let reply):
            response = reply
            ending = .tooManyBadRequests
        }
        if response.status != .ok && response.status != .permanentRedirect {
            log.info("Refused a request: \(response.status.rawValue, privacy: .public)")
        }
        connection.send(content: response.serialized(), completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            if let ending { self?.end(ending) }
        })
    }

    private func end(_ ending: Ending) {
        guard !hasEnded else { return }
        hasEnded = true
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections = [:]
        log.info("Stopped: \(ending.logLabel, privacy: .public)")
        onEvent(.ended(ending))
    }
}

private extension ImportServer.Ending {
    /// A label without the imported profile, which must never be logged.
    var logLabel: String {
        switch self {
        case .imported: "imported"
        case .cancelled: "cancelled"
        case .timedOut: "timed out"
        case .tooManyBadRequests: "too many bad requests"
        case .failed: "failed"
        }
    }
}
