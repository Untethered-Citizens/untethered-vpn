import Foundation

/// What the manual-entry form holds: one text value per setting, checked one
/// field at a time and turned into a profile once every field is valid.
/// One peer only (D30).
///
/// When editing, the saved private and preshared keys are kept here and used
/// when their fields are left blank, so a saved key never goes back on screen.
struct ProfileDraft: Equatable {

    enum Field: Hashable, CaseIterable {
        case name, privateKey, address, dns, mtu
        case publicKey, presharedKey, endpoint, allowedIPs, keepalive
    }

    static var maxNameLength: Int { ProfileName.maxLength }

    var name = "Home"
    var privateKey = ""
    var address = ""
    var dns = ""
    var mtu = ""
    var publicKey = ""
    var presharedKey = ""
    var endpoint = ""
    var allowedIPs = "0.0.0.0/0, ::/0"
    var keepalive = "25"

    /// The names of the other saved profiles, which this one mustn't repeat.
    var otherNames: [String] = []

    /// The profile being edited, or nil for a new one.
    private(set) var profileID: UUID?
    private(set) var savedPrivateKey: WireGuardKey?
    /// Set to nil to remove the saved preshared key.
    var savedPresharedKey: WireGuardKey?
    /// Settings the form doesn't show, kept as they are when editing:
    /// ListenPort and any peers after the first.
    private var listenPort: UInt16?
    private(set) var otherPeers: [WireGuardConfig.Peer] = []

    init() {}

    /// A draft for editing a saved profile. Key fields start blank.
    init(editing profile: TunnelProfile) {
        let interface = profile.config.interface
        profileID = profile.id
        name = profile.name
        savedPrivateKey = interface.privateKey
        address = interface.addresses.map(\.description).joined(separator: ", ")
        dns = (interface.dnsServers + interface.dnsSearchDomains).joined(separator: ", ")
        mtu = interface.mtu.map(String.init) ?? ""
        listenPort = interface.listenPort
        if let peer = profile.config.peers.first {
            publicKey = peer.publicKey.base64
            savedPresharedKey = peer.presharedKey
            endpoint = peer.endpoint.description
            allowedIPs = peer.allowedIPs.map(\.description).joined(separator: ", ")
            keepalive = peer.persistentKeepalive.map(String.init) ?? ""
            otherPeers = Array(profile.config.peers.dropFirst())
        }
    }

    var isEditing: Bool { profileID != nil }

    /// What's wrong with a field, in words for the screen, or nil if it's fine.
    func problem(in field: Field) -> String? {
        switch field {
        case .name:
            return ProfileName.problem(name, otherNames: otherNames)
        case .privateKey:
            return keyProblem(privateKey, saved: savedPrivateKey != nil, missing: "Enter the private key from your config's [Interface] section.")
        case .address:
            return rangesProblem(address, missing: "Enter this Apple TV's address in the tunnel, such as 10.8.0.2/32.")
        case .dns:
            if !trimmed(dns).isEmpty, WireGuardConfig.dnsEntries(trimmed(dns)) == nil {
                return "Use IP addresses or domain names, such as 192.0.2.53, separated by commas."
            }
        case .mtu:
            if !trimmed(mtu).isEmpty, WireGuardConfig.number(trimmed(mtu), in: WireGuardConfig.mtuRange) == nil {
                return "Use a number from \(WireGuardConfig.mtuRange.lowerBound) to \(WireGuardConfig.mtuRange.upperBound), or leave it blank for the usual size."
            }
        case .publicKey:
            return keyProblem(publicKey, saved: false, missing: "Enter the server's public key from your config's [Peer] section.")
        case .presharedKey:
            return keyProblem(presharedKey, saved: true, missing: "")
        case .endpoint:
            let endpoint = trimmed(endpoint)
            if endpoint.isEmpty { return "Enter the server's address and port, such as vpn.example.com:51820." }
            if PeerEndpoint(endpoint) == nil {
                return "Use a host name or IP address and a port, such as vpn.example.com:51820. Put an IPv6 address in brackets: [2001:db8::1]:51820."
            }
        case .allowedIPs:
            return rangesProblem(allowedIPs, missing: "Enter the addresses to send through the tunnel. 0.0.0.0/0, ::/0 sends everything.")
        case .keepalive:
            if !trimmed(keepalive).isEmpty, WireGuardConfig.number(trimmed(keepalive), in: 0...65535) == nil {
                return "Use a number of seconds from 0 to 65535, or leave it blank to turn it off."
            }
        }
        return nil
    }

    /// The fields that have a problem, in form order.
    var problemFields: [Field] {
        Field.allCases.filter { problem(in: $0) != nil }
    }

    /// The profile to save, or nil while any field has a problem.
    func makeProfile() -> TunnelProfile? {
        guard problemFields.isEmpty,
              let privateKey = key(privateKey) ?? savedPrivateKey,
              let publicKey = key(publicKey),
              let addresses = CIDRRange.list(trimmed(address)),
              let endpoint = PeerEndpoint(trimmed(endpoint)),
              let allowed = CIDRRange.list(trimmed(allowedIPs)) else {
            return nil
        }
        var interface = WireGuardConfig.Interface(privateKey: privateKey, addresses: addresses)
        if let dns = WireGuardConfig.dnsEntries(trimmed(dns)) {
            interface.dnsServers = dns.servers
            interface.dnsSearchDomains = dns.searchDomains
        }
        interface.mtu = WireGuardConfig.number(trimmed(mtu), in: WireGuardConfig.mtuRange)
        interface.listenPort = listenPort

        var peer = WireGuardConfig.Peer(publicKey: publicKey, presharedKey: key(presharedKey) ?? savedPresharedKey, endpoint: endpoint)
        peer.allowedIPs = allowed
        // 0 turns keepalive off, as in wg-quick
        let seconds = WireGuardConfig.number(trimmed(keepalive), in: 0...65535)
        peer.persistentKeepalive = seconds == 0 ? nil : seconds

        let config = WireGuardConfig(interface: interface, peers: [peer] + otherPeers)
        return TunnelProfile(id: profileID ?? UUID(), name: trimmed(name), config: config)
    }

    // MARK: - Helpers

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keys are pasted from a phone, so any spaces or line breaks inside are dropped.
    private func keyText(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private func key(_ text: String) -> WireGuardKey? {
        WireGuardKey(base64: keyText(text))
    }

    private func keyProblem(_ text: String, saved: Bool, missing: String) -> String? {
        let text = keyText(text)
        if text.isEmpty { return saved ? nil : missing }
        if WireGuardKey(base64: text) == nil {
            return "A key is 44 characters ending in “=”. Check for a missing or extra character."
        }
        return nil
    }

    private func rangesProblem(_ text: String, missing: String) -> String? {
        let text = trimmed(text)
        if text.isEmpty { return missing }
        if CIDRRange.list(text) == nil {
            return "Use IP addresses with a prefix, such as 10.8.0.2/32, separated by commas."
        }
        return nil
    }
}
