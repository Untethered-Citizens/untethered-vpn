import SwiftUI

/// The home screen when there are several profiles. Selecting a row connects
/// it (disconnecting any other) or, if it's already up, disconnects it.
/// Pressing and holding offers Details, Rename, Edit and Delete. Focus
/// starts on `preferredID`: the connected profile, else the last one used.
struct ProfileList: View {
    let entries: [TunnelManager.Entry]
    let stats: [UUID: LiveStats]
    let preferredID: UUID?
    let toggle: (TunnelManager.Entry) -> Void
    let details: (TunnelManager.Entry) -> Void
    let rename: (TunnelManager.Entry) -> Void
    let edit: (TunnelManager.Entry) -> Void
    let delete: (TunnelManager.Entry) -> Void

    @FocusState private var focusedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Select a profile to connect or disconnect it. For its stats, or to rename, edit or delete it, press and hold it.")
                .font(.body)
                .foregroundStyle(.secondary)

            List(entries) { entry in
                Button {
                    toggle(entry)
                } label: {
                    HStack(spacing: 40) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.name)
                                .font(.title3.bold())
                            Text("Server: \(entry.serverAddress)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if entry.status == .connected {
                                StatsLine(stats: stats[entry.id], compact: true)
                            }
                            if entry.connectsAutomatically {
                                AutoConnectMarker(compact: true)
                            }
                        }
                        Spacer()
                        StatusLabel(status: entry.status, compact: true)
                    }
                    .padding(.vertical, 8)
                }
                .disabled(entry.status == .disconnecting)
                .focused($focusedID, equals: entry.id)
                .contextMenu {
                    Button("Details", systemImage: "info.circle") { details(entry) }
                    Button("Rename", systemImage: "character.cursor.ibeam") { rename(entry) }
                    Button("Edit Profile", systemImage: "pencil") { edit(entry) }
                    Button("Delete Profile", systemImage: "trash", role: .destructive) { delete(entry) }
                }
            }
            .defaultFocus($focusedID, preferredID)
            .onAppear {
                if let preferredID { focusedID = preferredID }
            }
        }
    }
}
