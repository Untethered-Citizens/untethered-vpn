import Foundation

/// A connected profile's stats at one moment: when the tunnel came up, and
/// what the extension reported (nil if it didn't answer).
struct LiveStats: Equatable, Sendable {
    var connectedSince: Date?
    var tunnel: TunnelStats?
    /// When these were fetched; ages are measured from here.
    var fetchedAt: Date

    /// No handshake for this long while connected means the server probably
    /// isn't answering. With traffic or a keepalive, WireGuard handshakes at
    /// least every 2 minutes.
    static let staleAfter: TimeInterval = 180

    var handshakeAge: TimeInterval? {
        tunnel?.lastHandshake.map { max(0, fetchedAt.timeIntervalSince($0)) }
    }

    var connectedFor: TimeInterval? {
        connectedSince.map { max(0, fetchedAt.timeIntervalSince($0)) }
    }

    /// How long the server hasn't answered, once that's longer than
    /// `staleAfter`; nil while all is well. Before the first handshake it
    /// counts from when the tunnel came up.
    var silence: Silence? {
        if let age = handshakeAge {
            return age > Self.staleAfter ? .sinceHandshake(age) : nil
        }
        if tunnel != nil, let connected = connectedFor, connected > Self.staleAfter {
            return .sinceConnecting(connected)
        }
        return nil
    }

    enum Silence: Equatable, Sendable {
        case sinceHandshake(TimeInterval)
        case sinceConnecting(TimeInterval)

        /// The full hint, for the detail screen.
        var message: String {
            switch self {
            case .sinceHandshake(let age):
                "No reply from the server for \(StatsFormat.duration(age)). Check that it's running and reachable."
            case .sinceConnecting(let age):
                "No reply from the server since connecting \(StatsFormat.duration(age)) ago. Check that it's running and reachable, and that its keys match this profile."
            }
        }

        /// A few words, for the home screen.
        var shortMessage: String {
            switch self {
            case .sinceHandshake(let age), .sinceConnecting(let age):
                "No reply from the server for \(StatsFormat.duration(age, short: true))"
            }
        }
    }
}

/// Numbers with their units, as the screens show them.
enum StatsFormat {

    /// "12 seconds", "1 minute", "1 hour 12 minutes", "2 days 3 hours";
    /// short: "12 s", "1 min", "1 h 12 min", "2 d 3 h". Two units at most.
    static func duration(_ interval: TimeInterval, short: Bool = false) -> String {
        let total = Int(max(0, interval))
        let units: [(size: Int, long: String, short: String)] = [
            (86_400, "day", "d"), (3_600, "hour", "h"), (60, "minute", "min"), (1, "second", "s"),
        ]
        func part(_ count: Int, _ unit: (size: Int, long: String, short: String)) -> String {
            short ? "\(count) \(unit.short)" : "\(count) \(unit.long)\(count == 1 ? "" : "s")"
        }
        guard let first = units.firstIndex(where: { total >= $0.size }) else {
            return part(0, units[3])
        }
        let count = total / units[first].size
        var text = part(count, units[first])
        // Seconds alongside minutes would change every refresh; leave them out
        if first < 2 {
            let next = units[first + 1]
            let rest = (total % units[first].size) / next.size
            if rest > 0 { text += " " + part(rest, next) }
        }
        return text
    }

    /// "0 bytes", "512 bytes", "4.2 KB", "36 MB", "1.4 GB", in powers of 1,000
    /// like the rest of Apple's platforms. One decimal under 10, none above.
    static func bytes(_ count: UInt64, locale: Locale = .current) -> String {
        if count < 1_000 { return count == 1 ? "1 byte" : "\(count) bytes" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(count) / 1_000
        var index = 0
        while value >= 999.95, index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        let digits = value < 9.95 ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        return "\(number) \(units[index])"
    }

    /// The server as configured, with the address in use when it differs:
    /// `vpn.example.com:51820 (203.0.113.5)`. The port is left out of the
    /// address when it's the same as the configured one.
    static func endpoint(configured: String, inUse: String?) -> String {
        guard let inUse, !inUse.isEmpty, inUse != configured else { return configured }
        let (configuredHost, configuredPort) = split(configured)
        let (host, port) = split(inUse)
        if host == configuredHost { return configured }
        return "\(configured) (\(port == configuredPort ? host : inUse))"
    }

    /// `host:port` or `[v6]:port` into the host (without brackets) and port.
    private static func split(_ endpoint: String) -> (host: String, port: String) {
        guard let colon = endpoint.lastIndex(of: ":") else { return (endpoint, "") }
        var host = endpoint[..<colon]
        if host.hasPrefix("["), host.hasSuffix("]") { host = host.dropFirst().dropLast() }
        return (String(host), String(endpoint[endpoint.index(after: colon)...]))
    }
}
