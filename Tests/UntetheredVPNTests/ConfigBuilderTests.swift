import Testing
@testable import UntetheredVPN

struct ConfigBuilderTests {

    @Test func roundTripsThroughText() throws {
        let original = try WireGuardConfig.parse(Fixtures.Config().text(
            interfaceExtra: "MTU = 1420\nDNS = home.example.com",
            peerExtra: "PersistentKeepalive = 25\n\n[Peer]\nPublicKey = \(Fixtures.randomKeyText())\nEndpoint = [2001:db8::1]:51820\nAllowedIPs = 2001:db8::/64"
        )).config
        let rebuilt = try WireGuardConfig.parse(original.wgQuickText())
        #expect(rebuilt.config == original)
        #expect(rebuilt.warnings.isEmpty)
    }

    @Test func writesCanonicalText() throws {
        let fixture = Fixtures.Config()
        let config = try WireGuardConfig.parse(fixture.text(peerExtra: "PersistentKeepalive = 25")).config
        #expect(config.wgQuickText() == """
            [Interface]
            PrivateKey = \(fixture.privateKey)
            Address = 10.8.0.2/32
            DNS = 192.0.2.53

            [Peer]
            PublicKey = \(fixture.publicKey)
            PresharedKey = \(fixture.presharedKey)
            Endpoint = vpn.example.com:51820
            AllowedIPs = 0.0.0.0/0, ::/0
            PersistentKeepalive = 25

            """)
    }

    @Test func maskingHidesPrivateAndPresharedKeysOnly() throws {
        let fixture = Fixtures.Config()
        let masked = try WireGuardConfig.parse(fixture.text()).config.wgQuickText(maskingKeys: true)
        #expect(!masked.contains(fixture.privateKey))
        #expect(!masked.contains(fixture.presharedKey))
        #expect(masked.contains("PrivateKey = \(WireGuardKey.masked)"))
        #expect(masked.contains("PresharedKey = \(WireGuardKey.masked)"))
        #expect(masked.contains(fixture.publicKey))
    }
}
