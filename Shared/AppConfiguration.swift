import Foundation

/// Identifiers that both the app and the tunnel extension need, read from the
/// bundle's Info.plist. Their values come from `Config.xcconfig` at build time.
struct AppConfiguration: Equatable, Sendable {
    let appGroupID: String
    let keychainGroup: String
    let tunnelBundleID: String

    enum LoadError: Error, Equatable {
        case missingKey(String)
    }

    init(appGroupID: String, keychainGroup: String, tunnelBundleID: String) {
        self.appGroupID = appGroupID
        self.keychainGroup = keychainGroup
        self.tunnelBundleID = tunnelBundleID
    }

    /// Reads the identifiers from an Info.plist dictionary.
    init(infoDictionary: [String: Any]) throws {
        func value(_ key: String) throws -> String {
            guard let string = infoDictionary[key] as? String, !string.isEmpty else {
                throw LoadError.missingKey(key)
            }
            return string
        }
        try self.init(
            appGroupID: value("UVAppGroupID"),
            keychainGroup: value("UVKeychainGroup"),
            tunnelBundleID: value("UVTunnelBundleID")
        )
    }

    /// The configuration of the running app or extension.
    static func main() throws -> AppConfiguration {
        try AppConfiguration(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }
}
