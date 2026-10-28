import Foundation
import Observation

/// Runs one import from the phone for the import screen: starts an
/// `ImportServer`, and turns its events into what the screen shows. The
/// server runs only while the screen is visible and the app is in the
/// foreground; the screen calls `start()` and `stop()` to keep it that way.
@MainActor @Observable
final class PhoneImport {

    enum Problem: Equatable {
        case timedOut
        case tooManyBadRequests
        case noNetwork

        var title: String {
            switch self {
            case .timedOut: "The code expired"
            case .tooManyBadRequests: "The import was stopped"
            case .noNetwork: "This Apple TV isn't on a network"
            }
        }

        var message: String {
            switch self {
            case .timedOut:
                "Nothing arrived within \(Int(ImportServer.sessionDuration / 60)) minutes, so the code stopped working. Start again for a new one."
            case .tooManyBadRequests:
                "Something on this network sent requests that didn't match the code, so the TV stopped listening to be safe. Start again for a new code."
            case .noNetwork:
                "Connect it to Wi-Fi or Ethernet in Settings → Network, then start again."
            }
        }
    }

    enum State: Equatable {
        case starting
        case waiting(url: URL, expires: Date)
        case received(ImportedProfile)
        case ended(Problem)
    }

    private(set) var state: State = .starting

    @ObservationIgnored private let binding: ImportServer.Binding
    @ObservationIgnored private var server: ImportServer?
    /// Events from a server that has since been replaced are ignored.
    @ObservationIgnored private var generation = 0
    #if DEBUG
    @ObservationIgnored private var isSample = false
    #endif

    init(binding: ImportServer.Binding = .localNetwork) {
        self.binding = binding
    }

    /// Starts a fresh session with a new token and key. Any earlier one stops.
    func start() {
        #if DEBUG
        if isSample { return }
        #endif
        stop()
        generation += 1
        let current = generation
        state = .starting
        let session = ImportSession(assets: ImportServer.bundledAssets())
        let server = ImportServer(session: session, binding: binding) { [weak self] event in
            Task { @MainActor in self?.handle(event, generation: current) }
        }
        self.server = server
        server.start()
    }

    /// Stops listening. The screen shows its current state until `start()`.
    func stop() {
        server?.stop()
        server = nil
        generation += 1
    }

    /// The app left the foreground or the screen went away: stop, and start
    /// again on return if a code was showing, since the old one is dead.
    var shouldRestartOnReturn: Bool {
        switch state {
        case .starting, .waiting: true
        case .received, .ended: false
        }
    }

    private func handle(_ event: ImportServer.Event, generation: Int) {
        guard generation == self.generation else { return }
        switch event {
        case .ready(let url, let expires):
            state = .waiting(url: url, expires: expires)
        case .ended(let ending):
            server = nil
            switch ending {
            case .imported(let profile): state = .received(profile)
            case .timedOut: state = .ended(.timedOut)
            case .tooManyBadRequests: state = .ended(.tooManyBadRequests)
            case .failed: state = .ended(.noNetwork)
            case .cancelled: break
            }
        }
    }

    /// "4 min 32 s left", "45 s left".
    static func timeLeft(until expires: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int((expires.timeIntervalSince(now)).rounded(.up)))
        return seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s left" : "\(seconds) s left"
    }
}

#if DEBUG
extension PhoneImport {

    /// A screen state for checking layouts in the simulator, with no server.
    /// Keys are random and addresses are documentation ranges.
    static func sample(_ name: String) -> PhoneImport? {
        let sample = PhoneImport()
        sample.isSample = true
        switch name {
        case "waiting":
            let session = ImportSession(assets: [:])
            sample.state = .waiting(url: session.url(host: "192.168.1.40", port: 52817),
                                    expires: Date().addingTimeInterval(ImportServer.sessionDuration))
        case "received":
            let key = { Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString() }
            let text = """
                [Interface]
                PrivateKey = \(key())
                Address = 10.8.0.2/32
                DNS = 192.0.2.53
                PostUp = echo hello

                [Peer]
                PublicKey = \(key())
                PresharedKey = \(key())
                Endpoint = vpn.example.com:51820
                AllowedIPs = 0.0.0.0/0, ::/0
                PersistentKeepalive = 25
                """
            guard let parsed = try? WireGuardConfig.parse(text) else { return nil }
            sample.state = .received(ImportedProfile(name: "Home", config: parsed.config, warnings: parsed.warnings))
        case "timedOut": sample.state = .ended(.timedOut)
        case "tooMany": sample.state = .ended(.tooManyBadRequests)
        case "noNetwork": sample.state = .ended(.noNetwork)
        default: return nil
        }
        return sample
    }
}
#endif
