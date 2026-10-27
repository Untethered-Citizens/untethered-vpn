import Foundation

/// An IP address with a prefix length, such as `10.0.0.2/32` or `::/0`.
/// Used for interface addresses and AllowedIPs.
struct CIDRRange: Hashable, Sendable, CustomStringConvertible {
    let address: String
    let prefixLength: Int
    let isIPv6: Bool

    /// Validates `address/prefix`. A bare address means a single host
    /// (`/32` for IPv4, `/128` for IPv6), as in `wg-quick`.
    init?(_ text: String) {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return nil }
        let address = String(parts[0])
        let isIPv6: Bool
        if IPAddressText.isIPv4(address) {
            isIPv6 = false
        } else if IPAddressText.isIPv6(address) {
            isIPv6 = true
        } else {
            return nil
        }
        let maxPrefix = isIPv6 ? 128 : 32
        var prefixLength = maxPrefix
        if parts.count == 2 {
            let prefix = parts[1]
            guard (1...3).contains(prefix.count), prefix.allSatisfy(\.isASCIIDigit),
                  let value = Int(prefix), value <= maxPrefix else { return nil }
            prefixLength = value
        }
        self.address = address
        self.prefixLength = prefixLength
        self.isIPv6 = isIPv6
    }

    /// Validates a comma-separated list, as in `Address` or `AllowedIPs`.
    /// Returns nil if any entry is invalid or the list is empty.
    static func list(_ text: String) -> [CIDRRange]? {
        let entries = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !entries.isEmpty, !entries.contains(where: \.isEmpty) else { return nil }
        var ranges: [CIDRRange] = []
        for entry in entries {
            guard let range = CIDRRange(entry) else { return nil }
            ranges.append(range)
        }
        return ranges
    }

    /// Everything, IPv4 and IPv6: `0.0.0.0/0, ::/0`.
    static let allTraffic = [CIDRRange("0.0.0.0/0")!, CIDRRange("::/0")!]

    var description: String { "\(address)/\(prefixLength)" }
}
