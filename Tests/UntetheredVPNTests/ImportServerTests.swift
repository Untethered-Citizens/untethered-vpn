import Foundation
import Network
import Testing
@testable import UntetheredVPN

/// Runs the real server on 127.0.0.1 and talks raw HTTP to it, so malformed
/// and oversized requests can be sent too.
@Suite("Import server", .serialized, .timeLimit(.minutes(1)))
struct ImportServerTests {

    struct Reply {
        let status: Int
        let headers: String
        let body: Data
    }

    enum ClientError: Error { case closedWithoutReply, couldNotConnect }

    /// A started server and its events.
    final class Running {
        let server: ImportServer
        let session: ImportSession
        private var events: AsyncStream<ImportServer.Event>.Iterator
        private(set) var url: URL!

        init(sessionDuration: TimeInterval = 60, connectionTimeout: TimeInterval = 5) async throws {
            let (stream, continuation) = AsyncStream<ImportServer.Event>.makeStream()
            session = ImportSession(assets: ImportServer.bundledAssets())
            server = ImportServer(session: session, binding: .loopback,
                                  sessionDuration: sessionDuration, connectionTimeout: connectionTimeout) { event in
                continuation.yield(event)
            }
            events = stream.makeAsyncIterator()
            server.start()
            guard case .ready(let url, let expires) = await events.next() else {
                throw ClientError.couldNotConnect
            }
            #expect(expires > Date())
            self.url = url
        }

        var port: UInt16 { UInt16(url.port!) }
        var token: String { session.token }

        func nextEvent() async -> ImportServer.Event? { await events.next() }
    }

    /// Sends bytes on a fresh connection and reads until the server closes it.
    static func exchange(_ request: Data, port: UInt16) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            RawClient(port: port, request: request, continuation: continuation).start()
        }
    }

    /// One raw TCP exchange. Everything happens on its own serial queue.
    final class RawClient: @unchecked Sendable {
        private let connection: NWConnection
        private let request: Data
        private let queue = DispatchQueue(label: "test-client")
        private var continuation: CheckedContinuation<Data, Error>?
        private var received = Data()

        init(port: UInt16, request: Data, continuation: CheckedContinuation<Data, Error>) {
            connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            self.request = request
            self.continuation = continuation
        }

        func start() {
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !self.request.isEmpty {
                        self.connection.send(content: self.request, completion: .contentProcessed { _ in })
                    }
                    self.read()
                case .waiting, .failed:
                    self.finish(.failure(ClientError.couldNotConnect))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        private func read() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let data { self.received.append(data) }
                if isComplete || error != nil {
                    self.finish(.success(self.received))
                } else {
                    self.read()
                }
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            connection.cancel()
            continuation.resume(with: result)
        }
    }

    static func send(_ request: String, body: Data = Data(), port: UInt16) async throws -> Reply {
        let data = try await exchange(Data(request.utf8) + body, port: port)
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else { throw ClientError.closedWithoutReply }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        let status = Int(head.split(separator: " ")[1])!
        return Reply(status: status, headers: head, body: Data(data[end.upperBound...]))
    }

    static func post(_ body: Data, path: String, port: UInt16) async throws -> Reply {
        try await send("POST \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\n\r\n",
                       body: body, port: port)
    }

    @Test("A whole import: page, script, refusals, a fix, success, then nothing listening")
    func fullImport() async throws {
        let running = try await Running()
        let port = running.port, token = running.token

        let page = try await Self.send("GET /\(token)/ HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n", port: port)
        #expect(page.status == 200)
        #expect(page.headers.contains("Content-Security-Policy:"))
        #expect(page.headers.contains("Cache-Control: no-store"))
        #expect(String(decoding: page.body, as: UTF8.self).contains("Untethered VPN"))

        let script = try await Self.send("GET /\(token)/nacl.js HTTP/1.1\r\n\r\n", port: port)
        #expect(script.status == 200)
        #expect(String(decoding: script.body, as: UTF8.self).contains("secretbox"))

        #expect(try await Self.send("GET /\(ImportSession.makeToken())/ HTTP/1.1\r\n\r\n", port: port).status == 404)
        #expect(try await Self.send("POST /\(token)/ HTTP/1.1\r\nContent-Length: 20000\r\n\r\n", port: port).status == 413)

        let fixture = Fixtures.Config()
        let wrongKey = sealedSubmission(name: "Home", config: fixture.text(), key: .random())
        #expect(try await Self.post(wrongKey, path: "/\(token)/", port: port).status == 400)

        let broken = fixture.text().replacingOccurrences(of: "AllowedIPs = 0.0.0.0/0, ::/0", with: "AllowedIPs = everything")
        let invalid = try await Self.post(sealedSubmission(name: "Home", config: broken, key: running.session.key),
                                          path: "/\(token)/", port: port)
        #expect(invalid.status == 422)
        #expect(String(decoding: invalid.body, as: UTF8.self).contains("AllowedIPs"))

        let good = try await Self.post(sealedSubmission(name: "Home", config: fixture.text(), key: running.session.key),
                                       path: "/\(token)/", port: port)
        #expect(good.status == 200)

        guard case .ended(.imported(let profile)) = await running.nextEvent() else {
            Issue.record("expected the import to end the session")
            return
        }
        #expect(profile.name == "Home")
        #expect(profile.config.peers.first?.publicKey.base64 == fixture.publicKey)

        await #expect(throws: ClientError.self) {
            _ = try await Self.send("GET /\(token)/ HTTP/1.1\r\n\r\n", port: port)
        }
    }

    @Test("Ten bad requests stop the server")
    func tooManyBadRequests() async throws {
        let running = try await Running()
        for _ in 0..<ImportSession.maxBadRequests {
            #expect(try await Self.send("GET /guess HTTP/1.1\r\n\r\n", port: running.port).status == 404)
        }
        #expect(await running.nextEvent() == .ended(.tooManyBadRequests))
    }

    @Test("The session ends on its time limit")
    func timesOut() async throws {
        let running = try await Running(sessionDuration: 0.5)
        #expect(await running.nextEvent() == .ended(.timedOut))
    }

    @Test("Stop ends it as cancelled, once")
    func cancelled() async throws {
        let running = try await Running()
        running.server.stop()
        running.server.stop()
        #expect(await running.nextEvent() == .ended(.cancelled))
        await #expect(throws: ClientError.self) {
            _ = try await Self.send("GET / HTTP/1.1\r\n\r\n", port: running.port)
        }
    }

    @Test("An idle connection is closed without a reply")
    func idleConnection() async throws {
        let running = try await Running(connectionTimeout: 0.5)
        let started = Date()
        let data = try await Self.exchange(Data(), port: running.port)
        #expect(data.isEmpty)
        #expect(Date().timeIntervalSince(started) < 5)
        running.server.stop()
    }
}
