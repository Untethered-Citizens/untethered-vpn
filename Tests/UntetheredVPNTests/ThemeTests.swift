import Foundation
import Testing
import UIKit
@testable import UntetheredVPN

struct ThemeTests {

    /// A font name with no matching font falls back to the system font
    /// silently, so check each one the theme asks for.
    @Test(arguments: UTFont.allNames.sorted())
    func fontLoads(name: String) {
        #expect(UIFont(name: name, size: 20)?.fontName == name)
    }

    @Test func everyFontIsListed() throws {
        let listed = try #require(Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String])
        #expect(Set(listed) == Set(UTFont.allNames.map { "\($0).ttf" }))
    }

    /// A missing image draws nothing, so check every symbol the app names.
    @Test(arguments: [TunnelStatus.disconnected, .connecting, .connected, .disconnecting, .failed("")]
          .map(StatusLabel.symbol(for:)) + ["ut.phone", "ut.keyboard"])
    func symbolExists(name: String) {
        #expect(UIImage(named: name) != nil)
    }

    /// tvOS draws the launch screen from these names; a missing one shows nothing.
    @Test func launchScreenAssetsExist() throws {
        let launch = try #require(Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen") as? [String: String])
        #expect(UIColor(named: try #require(launch["UIColorName"])) != nil)
        #expect(UIImage(named: try #require(launch["UIImageName"])) != nil)
    }

    /// The asset catalog writes these when it finds the layered icon and Top Shelf images.
    @Test func iconAndTopShelfAreBuilt() throws {
        let icons = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        #expect(icons["CFBundlePrimaryIcon"] as? String == "App Icon")
        let topShelf = try #require(Bundle.main.object(forInfoDictionaryKey: "TVTopShelfImage") as? [String: String])
        #expect(topShelf["TVTopShelfPrimaryImage"] == "Top Shelf Image")
        #expect(topShelf["TVTopShelfPrimaryImageWide"] == "Top Shelf Image Wide")
    }

    @Test func licenceIsShown() throws {
        let licences = try #require(LicenceDocument.bundled())
        #expect(licences.blocks.contains(.heading("Barlow and Barlow Condensed")))
        #expect(licences.blocks.contains(.heading("SIL Open Font License 1.1 (Barlow)")))
    }
}
