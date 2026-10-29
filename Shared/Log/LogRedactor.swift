import Foundation
import Network

/// Hides what a log line mustn't carry before it's stored: anything shaped
/// like a key, the server's host name, and public IP addresses. Private and
/// tunnel addresses stay, since they help troubleshooting and reveal nothing.
struct LogRedactor: Sendable {
    /// The configured endpoints' host names, hidden wherever they appear.
    var hosts: [String] = []

    static let hiddenKey = WireGuardKey.masked
    static let hiddenHost = WireGuardConfig.maskedHost
    static let hiddenIP = "(public IP)"

    func redact(_ text: String) -> String {
        var text = text
        // Keys first: base64 (wg-quick) and hex (wireguard-go's UAPI)
        text = Self.replace(Self.base64Key, in: text) { _ in Self.hiddenKey }
        text = Self.replace(Self.hexKey, in: text) { _ in Self.hiddenKey }
        for host in hosts where !host.isEmpty && !IPAddressText.isIP(host) {
            text = text.replacingOccurrences(of: host, with: Self.hiddenHost, options: .caseInsensitive)
        }
        // IPv6 before IPv4, so an embedded IPv4 (::ffff:198.51.100.7) is left for the IPv4 pass
        text = Self.replace(Self.ipv6Candidate, in: text) { match in
            guard IPAddressText.isIPv6(match), let address = IPv6Address(match) else { return match }
            return Self.isPublic(address) ? Self.hiddenIP : match
        }
        text = Self.replace(Self.ipv4Candidate, in: text) { match in
            guard IPAddressText.isIPv4(match) else { return match }
            return Self.isPublicIPv4(match) ? Self.hiddenIP : match
        }
        return text
    }

    /// Whether an IPv4 address is reachable on the internet: not private,
    /// loopback, link-local, carrier-grade NAT, unspecified, multicast or broadcast.
    static func isPublicIPv4(_ text: String) -> Bool {
        let octets = text.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
        case (172, 16...31), (100, 64...127): return false
        case (224..., _): return false
        default: return true
        }
    }

    /// Whether an IPv6 address is reachable on the internet: not unspecified,
    /// loopback, link-local, unique local or multicast.
    static func isPublic(_ address: IPv6Address) -> Bool {
        let bytes = Array(address.rawValue)
        if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes[15] <= 1 { return false } // :: and ::1
        if bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80 { return false } // fe80::/10
        if bytes[0] & 0xfe == 0xfc { return false } // fc00::/7
        if bytes[0] == 0xff { return false } // multicast
        return true
    }

    private static let base64Key = pattern(#"(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{43}="#)
    private static let hexKey = pattern(#"(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])"#)
    private static let ipv4Candidate = pattern(#"(?<![0-9.])[0-9]{1,3}(?:\.[0-9]{1,3}){3}(?![0-9]|\.[0-9])"#)
    private static let ipv6Candidate =
        pattern(#"(?<![0-9A-Za-z:])[0-9A-Fa-f]{0,4}(?::[0-9A-Fa-f]{0,4}){2,7}(?![0-9A-Za-z:]|\.[0-9A-Za-z])"#)

    private static func pattern(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed, so a failure here is a programming error
        try! NSRegularExpression(pattern: pattern)
    }

    /// Replaces each match, working backwards so earlier ranges stay valid.
    private static func replace(_ regex: NSRegularExpression, in text: String, with replacement: (String) -> String) -> String {
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement(String(result[range])))
        }
        return result
    }
}

/// wireguard-go's routine messages: every handshake, keepalive, worker
/// start and stop, and settings update. Left out of the stored log so 500
/// lines cover days, not hours. Its errors are always kept.
enum RoutineMessages {
    static let phrases = [
        "Sending keepalive packet", "Receiving keepalive packet",
        "Sending handshake initiation", "Received handshake initiation",
        "Sending handshake response", "Received handshake response",
        "Routine: ", "UAPI: ",
    ]

    static func isRoutine(_ message: String) -> Bool {
        phrases.contains { message.contains($0) }
    }
}
