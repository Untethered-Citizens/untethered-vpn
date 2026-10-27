import Foundation

/// Why the extension couldn't start or keep a tunnel. The extension records
/// the latest one in the App Group, and the app shows its message when the
/// tunnel drops. Messages never contain a value from the config.
enum TunnelFailure: Int, Error, Sendable, CaseIterable {
    case missingConfiguration = 1
    case keychainUnreadable
    case configInvalid
    case endpointUnresolved
    case networkSettingsRejected
    case wireGuardFailed

    var message: String {
        switch self {
        case .missingConfiguration:
            "This profile is incomplete. Delete it and add it again."
        case .keychainUnreadable:
            "The profile's keys couldn't be read from the Keychain. Delete the profile and add it again."
        case .configInvalid:
            "The saved config is no longer valid. Delete the profile and add it again."
        case .endpointUnresolved:
            "The server's address couldn't be looked up. Check the internet connection and the Endpoint."
        case .networkSettingsRejected:
            "tvOS didn't accept the tunnel's network settings. Check Address, DNS and AllowedIPs."
        case .wireGuardFailed:
            "WireGuard couldn't start. Try again, or restart the Apple TV."
        }
    }
}

/// The last failure, kept in the App Group's defaults so the app can read
/// what the extension reported.
struct TunnelFailureRecord: Equatable, Sendable {
    private static let failureKey = "lastTunnelFailure"
    private static let profileKey = "lastTunnelFailureProfile"

    let failure: TunnelFailure
    let profileID: UUID

    static func save(_ record: TunnelFailureRecord, to defaults: UserDefaults) {
        defaults.set(record.failure.rawValue, forKey: failureKey)
        defaults.set(record.profileID.uuidString, forKey: profileKey)
    }

    /// Reads and clears the record for a profile. Nil if there is none, or it
    /// belongs to a different profile.
    static func take(for profileID: UUID, from defaults: UserDefaults) -> TunnelFailure? {
        guard defaults.string(forKey: profileKey) == profileID.uuidString,
              let failure = TunnelFailure(rawValue: defaults.integer(forKey: failureKey)) else {
            return nil
        }
        clear(from: defaults)
        return failure
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: failureKey)
        defaults.removeObject(forKey: profileKey)
    }
}
