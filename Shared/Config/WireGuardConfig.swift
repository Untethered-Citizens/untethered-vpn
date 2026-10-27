import Foundation

/// A WireGuard client configuration: one interface and one or more peers.
/// Values in here have already been validated.
struct WireGuardConfig: Hashable, Sendable {
    var interface: Interface
    var peers: [Peer]

    struct Interface: Hashable, Sendable {
        var privateKey: WireGuardKey
        var addresses: [CIDRRange]
        var dnsServers: [String] = []
        var dnsSearchDomains: [String] = []
        var mtu: UInt16?
        var listenPort: UInt16?
    }

    struct Peer: Hashable, Sendable {
        var publicKey: WireGuardKey
        var presharedKey: WireGuardKey?
        var endpoint: PeerEndpoint
        var allowedIPs: [CIDRRange] = CIDRRange.allTraffic
        var persistentKeepalive: UInt16?
    }

    /// Valid MTU values. 576 is the smallest packet every IPv4 host must accept.
    static let mtuRange: ClosedRange<Int> = 576...65535

    /// Splits a `DNS` value into server addresses and search domains. Nil if
    /// the list is empty or any entry is neither.
    static func dnsEntries(_ text: String) -> (servers: [String], searchDomains: [String])? {
        let entries = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        var servers: [String] = []
        var searchDomains: [String] = []
        for entry in entries {
            if IPAddressText.isIP(entry) {
                servers.append(entry)
            } else if IPAddressText.isHostName(entry) {
                searchDomains.append(entry)
            } else {
                return nil
            }
        }
        return (servers, searchDomains)
    }

    /// A plain decimal number in range: digits only, no sign or spaces.
    static func number(_ text: String, in range: ClosedRange<Int>) -> UInt16? {
        guard (1...5).contains(text.count), text.allSatisfy(\.isASCIIDigit),
              let value = Int(text), range.contains(value) else { return nil }
        return UInt16(value)
    }
}

extension WireGuardConfig {

    /// The configuration as `wg-quick` text. With `maskingKeys`, private and
    /// preshared keys are replaced by a placeholder, for showing on screen.
    /// Public keys are not secret and are always shown.
    func wgQuickText(maskingKeys: Bool = false) -> String {
        func secret(_ key: WireGuardKey) -> String {
            maskingKeys ? WireGuardKey.masked : key.base64
        }
        func list(_ items: [some CustomStringConvertible]) -> String {
            items.map(\.description).joined(separator: ", ")
        }

        var lines = ["[Interface]"]
        lines.append("PrivateKey = \(secret(interface.privateKey))")
        lines.append("Address = \(list(interface.addresses))")
        let dns = interface.dnsServers + interface.dnsSearchDomains
        if !dns.isEmpty { lines.append("DNS = \(list(dns))") }
        if let mtu = interface.mtu { lines.append("MTU = \(mtu)") }
        if let port = interface.listenPort { lines.append("ListenPort = \(port)") }

        for peer in peers {
            lines.append("")
            lines.append("[Peer]")
            lines.append("PublicKey = \(peer.publicKey.base64)")
            if let psk = peer.presharedKey { lines.append("PresharedKey = \(secret(psk))") }
            lines.append("Endpoint = \(peer.endpoint)")
            lines.append("AllowedIPs = \(list(peer.allowedIPs))")
            if let keepalive = peer.persistentKeepalive { lines.append("PersistentKeepalive = \(keepalive)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
