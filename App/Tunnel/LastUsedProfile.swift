import Foundation

/// Remembers which profile was connected last, so the home screen can start
/// with focus on it. Only the profile's ID is stored, in the App Group's
/// defaults: nothing secret.
struct LastUsedProfile {
    static let key = "lastConnectedProfileID"

    let defaults: UserDefaults?

    func remember(_ id: UUID) {
        defaults?.set(id.uuidString, forKey: Self.key)
    }

    /// Forgets the profile if it's the remembered one, e.g. when it's deleted.
    func forget(_ id: UUID) {
        if storedID == id { defaults?.removeObject(forKey: Self.key) }
    }

    /// The remembered profile, if it's still one of `ids`.
    func id(among ids: [UUID]) -> UUID? {
        storedID.flatMap { ids.contains($0) ? $0 : nil }
    }

    private var storedID: UUID? {
        defaults?.string(forKey: Self.key).flatMap(UUID.init(uuidString:))
    }
}
