import CoreImage
import Foundation
import Testing
@testable import UntetheredVPN

struct ProfileExportTests {

    private func export(_ fixture: Fixtures.Config, endpoint: String) throws -> ProfileExport {
        let text = fixture.text().replacingOccurrences(of: "vpn.example.com:51820", with: endpoint)
        return ProfileExport(name: "Home", config: try WireGuardConfig.parse(text).config)
    }

    @Test(arguments: [
        ("vpn.example.com:51820", "vpn.example.com"),
        ("192.0.2.10:443", "192.0.2.10"),
        ("[2001:db8::10]:51820", "2001:db8::10"),
    ])
    func hidesKeysAndEndpointHost(endpoint: String, host: String) throws {
        let fixture = Fixtures.Config()
        let text = try export(fixture, endpoint: endpoint).text
        #expect(!text.contains(fixture.privateKey))
        #expect(!text.contains(fixture.presharedKey))
        #expect(!text.contains(host))
        #expect(text.contains("PrivateKey = \(WireGuardKey.masked)"))
        #expect(text.contains("PresharedKey = \(WireGuardKey.masked)"))
        let port = try #require(endpoint.split(separator: ":").last)
        #expect(text.contains("Endpoint = \(WireGuardConfig.maskedHost):\(port)"))
        // What troubleshooting needs stays
        #expect(text.contains(fixture.publicKey))
        #expect(text.contains("Address = 10.8.0.2/32"))
        #expect(text.contains("AllowedIPs = 0.0.0.0/0, ::/0"))
    }

    @Test func everyPeerIsHidden() throws {
        let fixture = Fixtures.Config()
        let second = Fixtures.randomKeyText()
        let text = fixture.text() + """

            [Peer]
            PublicKey = \(Fixtures.randomKeyText())
            PresharedKey = \(second)
            Endpoint = 198.51.100.7:51821
            AllowedIPs = 10.9.0.0/24
            """
        let exported = ProfileExport(name: "Home", config: try WireGuardConfig.parse(text).config).text
        #expect(!exported.contains(second))
        #expect(!exported.contains("198.51.100.7"))
        #expect(!exported.contains("vpn.example.com"))
        #expect(exported.contains("Endpoint = \(WireGuardConfig.maskedHost):51821"))
    }

    @Test func plainTextStillShowsTheEndpoint() throws {
        let config = try WireGuardConfig.parse(Fixtures.Config().text()).config
        #expect(config.wgQuickText(maskingKeys: true).contains("Endpoint = vpn.example.com:51820"))
    }

    /// The QR code carries exactly the hidden text, nothing more.
    @Test func qrCodeHoldsTheExportedText() throws {
        let fixture = Fixtures.Config()
        let exported = try export(fixture, endpoint: "vpn.example.com:51820")
        let image = try #require(QRCode.image(for: exported.text, scale: 8))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
        let features = detector.features(in: CIImage(cgImage: image)).compactMap { $0 as? CIQRCodeFeature }
        let decoded = try #require(features.first?.messageString)
        #expect(decoded == exported.text)
        #expect(!decoded.contains(fixture.privateKey))
        #expect(!decoded.contains(fixture.presharedKey))
        #expect(!decoded.contains("vpn.example.com"))
    }
}

struct AboutTests {

    @Test func versionIncludesTheBuildNumber() {
        #expect(About.version(["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"]) == "Version 0.1.0 (1)")
        #expect(About.version(["CFBundleShortVersionString": "0.1.0"]) == "Version 0.1.0")
    }

    @Test func noticesNameTheLicenceAndTrademark() {
        let notices = About.notices.joined(separator: " ")
        #expect(notices.contains("Apache License 2.0"))
        #expect(notices.contains("registered trademarks of Jason A. Donenfeld"))
    }

    @Test func parsesTheMarkdownTheLicencesFileUses() {
        let document = LicenceDocument(markdown: """
            # Title

            First line
            wrapped on.

            ## Section

            - **One:** a
            - Two

            ```
            Line 1
            Line 2

            Next paragraph
            ```
            """)
        #expect(document.blocks == [
            .title("Title"),
            .paragraph("First line wrapped on."),
            .heading("Section"),
            .bullets(["**One:** a", "Two"]),
            .verbatim("Line 1\nLine 2\n\nNext paragraph"),
        ])
    }

    /// The app shows the bundled copy, so it must be there and match the
    /// repository's file.
    @Test func bundledLicencesMatchTheRepository() throws {
        let url = try #require(Bundle.main.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "md"))
        let bundled = try String(contentsOf: url, encoding: .utf8)
        let source = try String(contentsOf: Self.repository.appending(path: "THIRD_PARTY_LICENSES.md"), encoding: .utf8)
        #expect(bundled == source)
        #expect(LicenceDocument.bundled() != nil)
    }

    /// Every vendored licence text appears in full, so About can't drift
    /// from the code it describes.
    @Test(arguments: [
        "Vendor/WireGuardKit/COPYING",
        "Vendor/WireGuardKit/Sources/WireGuardKitGo/vendor/golang.zx2c4.com/wireguard/LICENSE",
        "Vendor/WireGuardKit/Sources/WireGuardKitGo/vendor/golang.org/x/crypto/LICENSE",
        "Vendor/WireGuardKit/Sources/WireGuardKitGo/vendor/golang.org/x/net/LICENSE",
        "Vendor/WireGuardKit/Sources/WireGuardKitGo/vendor/golang.org/x/sys/LICENSE",
        "Vendor/TweetNaCl/JS/LICENSE",
    ])
    func licencesFileIncludesVendoredText(path: String) throws {
        func words(_ text: String) -> String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let licences = words(try String(contentsOf: Self.repository.appending(path: "THIRD_PARTY_LICENSES.md"), encoding: .utf8))
        var text = try String(contentsOf: Self.repository.appending(path: path), encoding: .utf8)
        // The copyright line is given once above the shared MIT text
        if text.hasPrefix("Copyright © 2018-2023 WireGuard LLC") {
            text = String(text.drop { $0 != "\n" })
            #expect(licences.contains("Copyright © 2018-2023 WireGuard LLC"))
        }
        #expect(licences.contains(words(text)))
    }

    private static let repository = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
