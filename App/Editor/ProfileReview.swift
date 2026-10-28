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
    let done: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let hiddenKey = "•••••••• (hidden)"

    var body: some View {
        let interface = profile.config.interface
        VStack(alignment: .leading, spacing: 48) {
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
                    ("Name", profile.name),
                    ("Private Key", Self.hiddenKey),
                    ("Address", list(interface.addresses)),
                    ("DNS", list(interface.dnsServers + interface.dnsSearchDomains, empty: "None")),
                    ("MTU", interface.mtu.map(String.init) ?? "Automatic"),
                ])
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

            Text(isEditing
                 ? "If this profile is connected, the changes apply the next time you connect."
                 : "The first time you save a profile, tvOS asks whether Untethered VPN may add VPN configurations. Choose Allow.")
                .font(.body)
                .foregroundStyle(.secondary)

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
                .disabled(isSaving)
                Button(cancelTitle) {
                    if let cancel { cancel() } else { dismiss() }
                }
                .disabled(isSaving)
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Review “\(profile.name)”")
        .alert(
            "Not saved",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func group(_ title: String, rows: [(String, String)]) -> some View {
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
                try await manager.save(profile)
                done()
            } catch {
                errorMessage = "“\(profile.name)” couldn't be saved. \(error.localizedDescription)"
                isSaving = false
            }
        }
    }
}
