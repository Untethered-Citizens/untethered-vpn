import SwiftUI

@main
struct UntetheredVPNApp: App {
    @State private var manager = Self.makeManager()

    var body: some Scene {
        WindowGroup {
            if let manager {
                HomeView(manager: manager)
                    .preferredColorScheme(Self.debugColorScheme)
            } else {
                // Only a broken build gets here: Info.plist lacks the identifiers
                ContentUnavailableView(
                    "This build can't start",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Its App Group and Keychain settings are missing. Rebuild it from Config.xcconfig as described in the README.")
                )
            }
        }
    }

    /// Launch with `-appearance light|dark` to check both, since the tvOS
    /// simulator can't switch its own appearance from the command line.
    static var debugColorScheme: ColorScheme? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "light": .light
        case "dark": .dark
        default: nil
        }
        #else
        nil
        #endif
    }

    private static func makeManager() -> TunnelManager? {
        guard let configuration = try? AppConfiguration.main() else { return nil }
        let manager = TunnelManager(configuration: configuration)
        #if DEBUG
        // Launch with `-sampleProfiles one|several|failed|empty` to check layouts,
        // and `-sampleStats live|stale|never` for what connected samples report
        if let name = UserDefaults.standard.string(forKey: "sampleProfiles"),
           let samples = TunnelManager.Samples(rawValue: name) {
            let stats = UserDefaults.standard.string(forKey: "sampleStats").flatMap(TunnelManager.SampleStats.init)
            manager.showSamples(samples, stats: stats ?? .live)
        }
        #endif
        return manager
    }
}
