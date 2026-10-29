import SwiftUI

/// The last step before saving: every setting of the profile, with the
/// private and preshared keys masked, and anything the parser ignored.
/// Nothing is saved until Save.
struct ProfileReview: View {
    let manager: TunnelManager
    let profile: TunnelProfile
    let isEditing: Bool
    var warnings: [ConfigWarning] = []
    /// The second button: "Back" to the form by default; an import passes
    /// "Cancel" and an action that discards the profile.
    var cancelTitle = "Back"
    var cancel: (() -> Void)?
    /// Offers Rename here, for an import whose name came from the phone.
    var canRename = false
    let done: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var renamedTo: String?
    @State private var renaming = false

    private var name: String { renamedTo ?? profile.name }

    private var nameProblem: String? {
        ProfileName.problem(name, otherNames: manager.otherNames(excluding: profile.id))
    }

    private static let hiddenKey = "•••••••• (hidden)"

    var body: some View {
        let interface = profile.config.interface
        VStack(alignment: .leading, spacing: 40) {
            Text("Check these settings against your config. Keys stay hidden.")
                .font(.body)
                .foregroundStyle(.secondary)

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(alignment: .top, spacing: 80) {
                group("This Apple TV  ·  [Interface]", rows: [
                    ("Name", name),
                    ("Private Key", Self.hiddenKey),
                    ("Address", list(interface.addresses)),
                    ("DNS", list(interface.dnsServers + interface.dnsSearchDomains, empty: "None")),
                    ("MTU", interface.mtu.map(String.init) ?? "Automatic"),
                ], notes: nameProblem.map { ["Name": canRename ? "\($0) Select Rename to change it." : $0] } ?? [:])
                ForEach(Array(profile.config.peers.enumerated()), id: \.offset) { index, peer in
                    group(profile.config.peers.count == 1 ? "Your Server  ·  [Peer]" : "Peer \(index + 1)  ·  [Peer]", rows: [
                        ("Public Key", peer.publicKey.base64),
                        ("Preshared Key", peer.presharedKey == nil ? "None" : Self.hiddenKey),
                        ("Endpoint", peer.endpoint.description),
                        ("AllowedIPs", list(peer.allowedIPs)),
                        ("Persistent Keepalive", peer.persistentKeepalive.map { "\($0) seconds" } ?? "Off"),
                    ])
                }
            }

            // Left out while the name blocks Save, to leave room for its note
            if nameProblem == nil {
                Text(isEditing
                     ? "If this profile is connected, the changes apply the next time you connect."
                     : "The first time you save a profile, tvOS asks whether Untethered VPN may add VPN configurations. Choose Allow.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 40) {
                Button {
                    save()
                } label: {
                    HStack(spacing: 16) {
                        if isSaving { ProgressView() }
                        Text(isSaving ? "Saving…" : "Save").font(.title3.bold())
                    }
                    .frame(minWidth: 320)
                }
                .disabled(isSaving || nameProblem != nil)
                if canRename {
                    Button("Rename", systemImage: "character.cursor.ibeam") { renaming = true }
                        .disabled(isSaving)
                }
                Button(cancelTitle) {
                    if let cancel { cancel() } else { dismiss() }
                }
                .disabled(isSaving)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Review “\(name)”")
        .sheet(isPresented: $renaming) {
            RenameView(name: name, otherNames: manager.otherNames(excluding: profile.id),
                       save: { renamedTo = $0 },
                       done: { renaming = false })
        }
        .alert(
            "Not saved",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// A column of settings. A note shows in red under its row's value.
    private func group(_ title: String, rows: [(String, String)], notes: [String: String] = [:]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title3.bold())
            ForEach(rows, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.body)
                    if let note = notes[label] {
                        Label(note, systemImage: "exclamationmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ items: [some CustomStringConvertible], empty: String = "") -> String {
        items.isEmpty ? empty : items.map(\.description).joined(separator: ", ")
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await manager.save(TunnelProfile(id: profile.id, name: name, config: profile.config))
                done()
            } catch {
                errorMessage = "“\(name)” couldn't be saved. \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}
