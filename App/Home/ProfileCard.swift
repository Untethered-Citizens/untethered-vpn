import SwiftUI

/// The home screen when there's one profile: its name, server and status,
/// and a big Connect/Disconnect button.
struct ProfileCard: View {
    let entry: TunnelManager.Entry
    let toggle: (TunnelManager.Entry) -> Void
    let edit: (TunnelManager.Entry) -> Void
    let delete: (TunnelManager.Entry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.name)
                    .font(.largeTitle.bold())
                Text("Server: \(entry.serverAddress)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            StatusLabel(status: entry.status)

            Button {
                toggle(entry)
            } label: {
                Text(entry.status.actionTitle)
                    .font(.title2.bold())
                    .frame(minWidth: 480)
                    .padding(.vertical, 12)
            }
            .disabled(entry.status == .disconnecting)
            .contextMenu {
                Button("Edit Profile", systemImage: "pencil") { edit(entry) }
                Button("Delete Profile", systemImage: "trash", role: .destructive) { delete(entry) }
            }

            Text("To edit or delete this profile, press and hold the button.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
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
