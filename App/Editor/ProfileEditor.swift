import SwiftUI

/// Adding or editing a profile: the form, then the review screen. The draft
/// lives here, so going Back from the review keeps what was typed.
struct ProfileEditor: View {
    let manager: TunnelManager
    let done: () -> Void

    @State private var draft: ProfileDraft
    @State private var path: [TunnelProfile]
    private let checksAll: Bool

    init(manager: TunnelManager, draft: ProfileDraft, reviewing: Bool = false, checksAll: Bool = false, done: @escaping () -> Void) {
        self.manager = manager
        self.done = done
        self.checksAll = checksAll
        var draft = draft
        draft.otherNames = manager.otherNames(excluding: draft.profileID)
        _draft = State(initialValue: draft)
        _path = State(initialValue: reviewing ? [draft.makeProfile()].compactMap { $0 } : [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            ProfileForm(draft: $draft, checksAll: checksAll, review: { path = [$0] }, cancel: done)
                .navigationDestination(for: TunnelProfile.self) { profile in
                    ProfileReview(manager: manager, profile: profile, isEditing: draft.isEditing, done: done)
                }
        }
    }
}

/// A request to open the editor, for `fullScreenCover(item:)`.
struct EditorRequest: Identifiable {
    let id = UUID()
    var draft: ProfileDraft
    var reviewing = false
    var checksAll = false
}

extension EditorRequest {
    /// Editing a saved profile. Throws if its config can't be read back.
    @MainActor
    init(editing entry: TunnelManager.Entry, manager: TunnelManager) throws {
        let profile = TunnelProfile(id: entry.id, name: entry.name, config: try manager.config(for: entry.id))
        self.init(draft: ProfileDraft(editing: profile))
    }

    /// What to say when `init(editing:manager:)` fails.
    static func failureMessage(for entry: TunnelManager.Entry) -> String {
        "“\(entry.name)” couldn't be opened for editing. Delete it and add it again."
    }
}

#if DEBUG
extension EditorRequest {

    /// Opens the editor at launch with `-sampleEditor add|filled|errors|review|edit`,
    /// to check its screens in the simulator. Keys are random and addresses
    /// are documentation ranges.
    static func debugSample() -> EditorRequest? {
        guard let name = UserDefaults.standard.string(forKey: "sampleEditor") else { return nil }
        var filled = ProfileDraft()
        filled.privateKey = randomKey()
        filled.address = "10.8.0.2/32"
        filled.dns = "192.0.2.53"
        filled.publicKey = randomKey()
        filled.endpoint = "vpn.example.com:51820"
        switch name {
        case "add":
            return EditorRequest(draft: ProfileDraft())
        case "filled":
            return EditorRequest(draft: filled)
        case "errors":
            var broken = filled
            broken.privateKey = String(broken.privateKey.dropFirst())
            broken.address = "10.8.0.2/33"
            broken.endpoint = "vpn.example.com"
            return EditorRequest(draft: broken, checksAll: true)
        case "review":
            return EditorRequest(draft: filled, reviewing: true)
        case "edit":
            filled.presharedKey = randomKey()
            guard let profile = filled.makeProfile() else { return nil }
            return EditorRequest(draft: ProfileDraft(editing: profile))
        default:
            return nil
        }
    }

    private static func randomKey() -> String {
        Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
    }
}
#endif
