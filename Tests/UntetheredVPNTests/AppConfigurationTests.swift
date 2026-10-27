import Foundation
import Testing
@testable import UntetheredVPN

struct AppConfigurationTests {

    @Test func readsAllIdentifiers() throws {
        let config = try AppConfiguration(infoDictionary: [
            "UVAppGroupID": "group.example.vpn",
            "UVKeychainGroup": "ABCDE12345.example.vpn.shared",
            "UVTunnelBundleID": "example.vpn.tunnel",
        ])
        #expect(config == AppConfiguration(
            appGroupID: "group.example.vpn",
            keychainGroup: "ABCDE12345.example.vpn.shared",
            tunnelBundleID: "example.vpn.tunnel"
        ))
    }

    @Test(arguments: ["UVAppGroupID", "UVKeychainGroup", "UVTunnelBundleID"])
    func missingOrEmptyKeyFails(key: String) {
        var info: [String: Any] = [
            "UVAppGroupID": "group.example.vpn",
            "UVKeychainGroup": "example.vpn.shared",
            "UVTunnelBundleID": "example.vpn.tunnel",
        ]
        info[key] = ""
        #expect(throws: AppConfiguration.LoadError.missingKey(key)) {
            try AppConfiguration(infoDictionary: info)
        }
        info[key] = nil
        #expect(throws: AppConfiguration.LoadError.missingKey(key)) {
            try AppConfiguration(infoDictionary: info)
        }
    }

    /// The built app carries the identifiers from Config.sample.xcconfig (or
    /// the developer's Config.xcconfig), and they fit together.
    @Test func builtAppIsConfigured() throws {
        let config = try AppConfiguration.main()
        let appID = try #require(Bundle.main.bundleIdentifier)
        #expect(config.appGroupID.hasPrefix("group."))
        #expect(config.tunnelBundleID.hasPrefix(appID + "."))
        #expect(config.keychainGroup.hasSuffix(".shared"))
    }
}
