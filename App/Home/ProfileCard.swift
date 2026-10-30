import SwiftUI

/// The home screen when there's one profile: its name, server, status and
/// a line of stats, a big Connect/Disconnect button, and Details.
struct ProfileCard: View {
    let entry: TunnelManager.Entry
    let stats: LiveStats?
    let toggle: (TunnelManager.Entry) -> Void
    let details: (TunnelManager.Entry) -> Void
    let rename: (TunnelManager.Entry) -> Void
    let edit: (TunnelManager.Entry) -> Void
    let delete: (TunnelManager.Entry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.name)
                    .font(.utDisplay)
                Text("Server: \(entry.serverAddress)")
                    .foregroundStyle(UTColor.muted)
            }

            VStack(alignment: .leading, spacing: 16) {
                StatusLabel(status: entry.status)
                if entry.status == .connected {
                    StatsLine(stats: stats)
                }
                if entry.connectsAutomatically {
                    AutoConnectMarker()
                }
            }

            HStack(spacing: 40) {
                Button {
                    toggle(entry)
                } label: {
                    Text(entry.status.actionTitle)
                }
                .buttonStyle(.utHero)
                .disabled(entry.status == .disconnecting)
                .contextMenu {
                    Button("Details", systemImage: "info.circle") { details(entry) }
                    Button("Rename", systemImage: "character.cursor.ibeam") { rename(entry) }
                    Button("Edit Profile", systemImage: "pencil") { edit(entry) }
                    Button("Delete Profile", systemImage: "trash", role: .destructive) { delete(entry) }
                }

                Button {
                    details(entry)
                } label: {
                    Label("Details", systemImage: "info.circle")
                }
                .buttonStyle(.utSecondary)
            }

            Text("Details shows this connection's stats, and is where you rename, edit, export or delete the profile.")
                .font(.utCaption)
                .foregroundStyle(UTColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 1120, alignment: .leading)
        .utPanel(padding: 76)
    }
}

extension TunnelStatus {
    /// The button's title for a profile in this state.
    var actionTitle: String {
        switch self {
        case .connecting, .connected: "Disconnect"
        case .disconnecting: "Disconnecting…"
        case .disconnected, .failed: "Connect"
        }
    }
}
