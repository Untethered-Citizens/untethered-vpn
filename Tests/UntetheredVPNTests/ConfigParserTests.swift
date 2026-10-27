import Testing
@testable import UntetheredVPN

struct ConfigParserTests {

    // MARK: Valid configs

    @Test func parsesATypicalConfig() throws {
        let fixture = Fixtures.Config()
        let parsed = try WireGuardConfig.parse(fixture.text(
            interfaceExtra: "MTU = 1420\nListenPort = 51000",
            peerExtra: "PersistentKeepalive = 25"
        ))
        #expect(parsed.warnings.isEmpty)

        let interface = parsed.config.interface
        #expect(interface.privateKey.base64 == fixture.privateKey)
        #expect(interface.addresses.map(\.description) == ["10.8.0.2/32"])
        #expect(interface.dnsServers == ["192.0.2.53"])
        #expect(interface.mtu == 1420)
        #expect(interface.listenPort == 51000)

        let peer = try #require(parsed.config.peers.first)
        #expect(parsed.config.peers.count == 1)
        #expect(peer.publicKey.base64 == fixture.publicKey)
        #expect(peer.presharedKey?.base64 == fixture.presharedKey)
        #expect(peer.endpoint == PeerEndpoint("vpn.example.com:51820"))
        #expect(peer.allowedIPs == CIDRRange.allTraffic)
        #expect(peer.persistentKeepalive == 25)
    }

    @Test func parsesMultiplePeers() throws {
        let second = Fixtures.randomKeyText()
        let parsed = try WireGuardConfig.parse(Fixtures.Config().text(peerExtra: """

            [Peer]
            PublicKey = \(second)
            Endpoint = [2001:db8::1]:51821
            AllowedIPs = 192.0.2.0/24
            """))
        #expect(parsed.config.peers.count == 2)
        #expect(parsed.config.peers[1].publicKey.base64 == second)
        #expect(parsed.config.peers[1].presharedKey == nil)
        #expect(parsed.config.peers[1].endpoint.port == 51821)
        #expect(parsed.config.peers[1].allowedIPs.map(\.description) == ["192.0.2.0/24"])
    }

    @Test func isLenientAboutLayout() throws {
        let key = Fixtures.randomKeyText()
        let peerKey = Fixtures.randomKeyText()
        let text = "\u{FEFF}# exported from my router\r\n"
            + "  [interface]  \r\n"
            + "privatekey=\(key)   # comment after a value\r\n"
            + "ADDRESS = 10.8.0.2/32\r\n"
            + "Address = 2001:db8::2/128\r\n"
            + "\r\n\r\n"
            + "[ Peer ]\r\n"
            + "publicKey =   \(peerKey)\r\n"
            + "endpoint = 192.0.2.1:51820\r\n"
            + "allowedips = 10.8.0.0/24\r\n"
            + "AllowedIPs = 2001:db8::/64\r\n"
        let parsed = try WireGuardConfig.parse(text)
        #expect(parsed.config.interface.privateKey.base64 == key)
        #expect(parsed.config.interface.addresses.map(\.description) == ["10.8.0.2/32", "2001:db8::2/128"])
        #expect(parsed.config.peers[0].allowedIPs.map(\.description) == ["10.8.0.0/24", "2001:db8::/64"])
        #expect(parsed.warnings.isEmpty)
    }

    @Test func splitsDNSIntoServersAndSearchDomains() throws {
        let fixture = Fixtures.Config()
        let text = fixture.text().replacingOccurrences(
            of: "DNS = 192.0.2.53", with: "DNS = 192.0.2.53, 2001:db8::53, home.example.com")
        let interface = try WireGuardConfig.parse(text).config.interface
        #expect(interface.dnsServers == ["192.0.2.53", "2001:db8::53"])
        #expect(interface.dnsSearchDomains == ["home.example.com"])
    }

    @Test(arguments: [("off", nil), ("0", nil), ("25", 25 as UInt16?)])
    func readsPersistentKeepalive(value: String, expected: UInt16?) throws {
        let parsed = try WireGuardConfig.parse(Fixtures.Config().text(peerExtra: "PersistentKeepalive = \(value)"))
        #expect(parsed.config.peers[0].persistentKeepalive == expected)
    }

    // MARK: Warnings

    @Test func missingAllowedIPsDefaultsToAllTrafficWithAWarning() throws {
        let text = Fixtures.Config().text().replacingOccurrences(of: "AllowedIPs = 0.0.0.0/0, ::/0\n", with: "")
        let parsed = try WireGuardConfig.parse(text)
        #expect(parsed.config.peers[0].allowedIPs == CIDRRange.allTraffic)
        #expect(parsed.warnings == [ConfigWarning(section: .peer(1), kind: .defaultAllowedIPs)])
    }

    @Test func ignoresWgQuickDirectivesWithAWarning() throws {
        let parsed = try WireGuardConfig.parse(Fixtures.Config().text(interfaceExtra: """
            PostUp = iptables -A FORWARD -i %i -j ACCEPT
            PostDown = iptables -D FORWARD -i %i -j ACCEPT
            postup = echo again
            Table = off
            SaveConfig = true
            """))
        #expect(parsed.warnings.map(\.kind) == [
            .ignoredDirective("PostUp"), .ignoredDirective("PostDown"),
            .ignoredDirective("Table"), .ignoredDirective("SaveConfig"),
        ])
    }

    @Test func ignoresUnknownSettingsWithAWarning() throws {
        let parsed = try WireGuardConfig.parse(Fixtures.Config().text(peerExtra: "Nickname = home"))
        #expect(parsed.warnings == [ConfigWarning(section: .peer(1), kind: .unknownKey("Nickname", line: 12))])
    }

    @Test func settingInTheWrongSectionIsIgnoredWithAWarning() throws {
        let parsed = try WireGuardConfig.parse(Fixtures.Config().text(interfaceExtra: "PersistentKeepalive = 25"))
        #expect(parsed.warnings.map(\.kind) == [.unknownKey("PersistentKeepalive", line: 5)])
    }

    /// A key pasted with ":" instead of " = " becomes the setting name; the
    /// warning must not repeat it.
    @Test func unknownSettingThatLooksLikeAKeyIsNotEchoed() throws {
        let secret = Fixtures.randomKeyText()
        let parsed = try WireGuardConfig.parse(Fixtures.Config().text(interfaceExtra: "OldKey: \(secret)"))
        #expect(parsed.warnings.map(\.kind) == [.unknownKey(nil, line: 5)])
        #expect(!parsed.warnings[0].message.contains(secret.prefix(20)))
    }

    // MARK: Errors

    @Test func emptyText() {
        #expect(throws: ConfigError.empty) { try WireGuardConfig.parse("") }
        #expect(throws: ConfigError.empty) { try WireGuardConfig.parse(" \n\t\n") }
    }

    /// The text of a config pasted somewhere that turned its line breaks into
    /// spaces (or nothing).
    @Test(arguments: [" ", "", "  "])
    func lineBreaksLost(separator: String) {
        let flattened = Fixtures.Config().text()
            .split(whereSeparator: \.isNewline)
            .joined(separator: separator)
        #expect(throws: ConfigError.lineBreaksLost) { try WireGuardConfig.parse(flattened) }
    }

    @Test func lineBreaksLostInOnlyOneSection() {
        let fixture = Fixtures.Config()
        let text = fixture.text().replacingOccurrences(of: "\nEndpoint", with: " Endpoint")
        #expect(throws: ConfigError.lineBreaksLost) { try WireGuardConfig.parse(text) }
    }

    @Test func aKeyEndingInSettingLikeLettersIsNotMistakenForLostLineBreaks() throws {
        // Base64 can end in a setting name right before "=", here "MTU=".
        let key = try #require(WireGuardKey(base64: String(repeating: "A", count: 40) + "MTU="))
        let text = Fixtures.Config().text().replacing(#/PrivateKey = .*/#, with: "PrivateKey = \(key.base64)")
        #expect(try WireGuardConfig.parse(text).config.interface.privateKey == key)
    }

    @Test(arguments: [
        ("Address = 10.8.0.2/32\n[Interface]", ConfigError.textOutsideSection(line: 1)),
        ("[Interface]\n[Wireguard]", .unknownSection(line: 2)),
        ("[Interface\n", .unknownSection(line: 1)),
        ("[Interface]\nthis is not a setting", .invalidLine(line: 2)),
        ("[Peer]\nEndpoint = vpn.example.com:51820", .noInterface),
    ])
    func structuralErrors(text: String, error: ConfigError) {
        #expect(throws: error) { try WireGuardConfig.parse(text) }
    }

    @Test func noPeers() {
        let text = "[Interface]\nPrivateKey = \(Fixtures.randomKeyText())\nAddress = 10.8.0.2/32\n"
        #expect(throws: ConfigError.noPeers) { try WireGuardConfig.parse(text) }
    }

    @Test func secondInterface() {
        let text = Fixtures.Config().text(peerExtra: "[Interface]")
        #expect(throws: ConfigError.multipleInterfaces(line: 12)) { try WireGuardConfig.parse(text) }
    }

    @Test(arguments: [
        ("PrivateKey", ConfigSection.interface),
        ("Address", .interface),
        ("PublicKey", .peer(1)),
        ("Endpoint", .peer(1)),
    ])
    func missingRequiredSetting(key: String, section: ConfigSection) {
        let text = Fixtures.Config().text()
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix(key + " =") }
            .joined(separator: "\n")
        #expect(throws: ConfigError.missingKey(section, key: key)) { try WireGuardConfig.parse(text) }
    }

    @Test(arguments: [
        ("PrivateKey = short", ConfigSection.interface, "PrivateKey", 2),
        ("Address = 10.8.0.300/32", .interface, "Address", 3),
        ("DNS = 192.0.2.53, not_a_name", .interface, "DNS", 4),
        ("PublicKey = short", .peer(1), "PublicKey", 8),
        ("PresharedKey = short", .peer(1), "PresharedKey", 9),
        ("Endpoint = vpn.example.com", .peer(1), "Endpoint", 10),
        ("AllowedIPs = 0.0.0.0/0,", .peer(1), "AllowedIPs", 11),
    ])
    func invalidValue(replacement: String, section: ConfigSection, key: String, line: Int) {
        let text = Fixtures.Config().text().replacing(try! Regex("(?m)^\(key) = .*$"), with: replacement)
        #expect(throws: ConfigError.invalidValue(section, key: key, line: line)) { try WireGuardConfig.parse(text) }
    }

    @Test(arguments: [
        ("MTU = 575", ConfigSection.interface, "MTU"),
        ("MTU = 65536", .interface, "MTU"),
        ("MTU = 1420.5", .interface, "MTU"),
        ("ListenPort = 70000", .interface, "ListenPort"),
        ("ListenPort = -1", .interface, "ListenPort"),
    ])
    func invalidNumbers(line: String, section: ConfigSection, key: String) {
        let text = Fixtures.Config().text(interfaceExtra: line)
        #expect(throws: ConfigError.invalidValue(section, key: key, line: 5)) { try WireGuardConfig.parse(text) }
    }

    @Test func invalidKeepalive() {
        let text = Fixtures.Config().text(peerExtra: "PersistentKeepalive = sometimes")
        #expect(throws: ConfigError.invalidValue(.peer(1), key: "PersistentKeepalive", line: 12)) {
            try WireGuardConfig.parse(text)
        }
    }

    @Test func duplicateSingleValueSetting() {
        let text = Fixtures.Config().text(peerExtra: "Endpoint = other.example.com:51820")
        #expect(throws: ConfigError.duplicateKey(.peer(1), key: "Endpoint", line: 12)) {
            try WireGuardConfig.parse(text)
        }
    }

    // MARK: Messages never leak values

    @Test func errorMessagesNeverContainTheKey() {
        let fixture = Fixtures.Config()
        // A private key one character short: invalid, but nearly the real thing.
        let almost = String(fixture.privateKey.dropLast(2)) + "="
        let text = fixture.text().replacingOccurrences(of: fixture.privateKey, with: almost)
        do {
            _ = try WireGuardConfig.parse(text)
            Issue.record("expected an error")
        } catch {
            #expect(error == .invalidValue(.interface, key: "PrivateKey", line: 2))
            #expect(!error.message.contains(almost.prefix(20)))
            #expect(!String(describing: error).contains(almost.prefix(20)))
        }
    }
}
