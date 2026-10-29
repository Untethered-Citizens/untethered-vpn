import Foundation

/// What a running tunnel reports about itself: per peer, the last handshake,
/// bytes received and sent, and the endpoint wireguard-go is using. Nothing
/// secret: no keys of any kind, not even public ones.
///
/// The app asks for it with an app message (`request`); the extension reads
/// wireguard-go's runtime state and replies with this, JSON-encoded.
struct TunnelStats: Codable, Equatable, Sendable {

    struct Peer: Codable, Equatable, Sendable {
        /// The address and port in use, e.g. `203.0.113.5:51820`; nil before
        /// the endpoint is resolved.
        var endpoint: String?
        /// Nil until the first handshake.
        var lastHandshake: Date?
        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0
    }

    var peers: [Peer]

    /// The app message that asks the extension for its stats.
    static let request = Data("stats.v1".utf8)

    /// The settings read from wireguard-go's runtime state. Everything else,
    /// keys above all, is skipped without being stored.
    private static let readKeys: Set<Substring> = [
        "public_key", "endpoint", "last_handshake_time_sec", "last_handshake_time_nsec", "rx_bytes", "tx_bytes",
    ]

    /// Reads wireguard-go's runtime state (its `key=value` UAPI text). Each
    /// peer starts with a `public_key` line, which marks the boundary but
    /// isn't kept.
    init(runtimeConfiguration text: String) {
        var peers: [Peer] = []
        var seconds: Int64 = 0
        var nanoseconds: Int64 = 0

        func finishPeer() {
            guard !peers.isEmpty else { return }
            if seconds > 0 {
                peers[peers.count - 1].lastHandshake = Date(
                    timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000
                )
            }
            seconds = 0
            nanoseconds = 0
        }

        for line in text.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals]
            guard Self.readKeys.contains(key) else { continue }
            let value = line[line.index(after: equals)...]
            if key == "public_key" {
                finishPeer()
                peers.append(Peer())
                continue
            }
            guard !peers.isEmpty else { continue }
            switch key {
            case "endpoint": peers[peers.count - 1].endpoint = String(value)
            case "last_handshake_time_sec": seconds = Int64(value) ?? 0
            case "last_handshake_time_nsec": nanoseconds = Int64(value) ?? 0
            case "rx_bytes": peers[peers.count - 1].receivedBytes = UInt64(value) ?? 0
            case "tx_bytes": peers[peers.count - 1].sentBytes = UInt64(value) ?? 0
            default: break
            }
        }
        finishPeer()
        self.peers = peers
    }

    init(peers: [Peer]) {
        self.peers = peers
    }

    /// The most recent handshake with any peer.
    var lastHandshake: Date? { peers.compactMap(\.lastHandshake).max() }
    var receivedBytes: UInt64 { peers.reduce(0) { $0 + $1.receivedBytes } }
    var sentBytes: UInt64 { peers.reduce(0) { $0 + $1.sentBytes } }
    /// The first peer's endpoint, matching the server the home screen shows.
    var endpoint: String? { peers.first?.endpoint }
}
