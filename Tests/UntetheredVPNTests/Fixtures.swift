import Foundation
@testable import UntetheredVPN

/// Synthetic test data. Keys are random bytes made at run time, so no
/// key-shaped text is ever committed; addresses use documentation ranges
/// (192.0.2.0/24, 2001:db8::/32) and example.com.
enum Fixtures {

    static func randomKeyText() -> String {
        Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
    }

    static func randomKey() -> WireGuardKey {
        WireGuardKey(base64: randomKeyText())!
    }

    /// A complete config with one peer. Pass extra lines to append to each
    /// section, or override a setting by passing it again.
    struct Config {
        let privateKey = Fixtures.randomKeyText()
        let publicKey = Fixtures.randomKeyText()
        let presharedKey = Fixtures.randomKeyText()

        func text(interfaceExtra: String = "", peerExtra: String = "") -> String {
            """
            [Interface]
            PrivateKey = \(privateKey)
            Address = 10.8.0.2/32
            DNS = 192.0.2.53
            \(interfaceExtra)

            [Peer]
            PublicKey = \(publicKey)
            PresharedKey = \(presharedKey)
            Endpoint = vpn.example.com:51820
            AllowedIPs = 0.0.0.0/0, ::/0
            \(peerExtra)
            """
        }
    }
}
