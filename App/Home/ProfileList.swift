import SwiftUI

/// The home screen when there are several profiles. Selecting a row connects
/// it (disconnecting any other) or, if it's already up, disconnects it.
struct ProfileList: View {
    let entries: [TunnelManager.Entry]
    let toggle: (TunnelManager.Entry) -> Void
    let delete: (TunnelManager.Entry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Select a profile to connect or disconnect it. To delete one, press and hold it.")
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
                        }
                        Spacer()
                        StatusLabel(status: entry.status, compact: true)
                    }
                    .padding(.vertical, 8)
                }
                .disabled(entry.status == .disconnecting)
                .contextMenu {
                    Button("Delete Profile", systemImage: "trash", role: .destructive) { delete(entry) }
                }
            }
        }
    }
}
