import SwiftUI

/// The main screen: the saved profiles, their status, and Connect/Disconnect.
/// One profile gets a large card; several get a list.
struct HomeView: View {
    let manager: TunnelManager

    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingDelete: TunnelManager.Entry?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 56) {
            Label("Untethered VPN", systemImage: "network.badge.shield.half.filled")
                .font(.title2.bold())
                .foregroundStyle(.secondary)

            switch manager.entries.count {
            case 0:
                emptyState
            case 1:
                ProfileCard(entry: manager.entries[0], toggle: toggle, delete: { pendingDelete = $0 })
            default:
                ProfileList(entries: manager.entries, toggle: toggle, delete: { pendingDelete = $0 })
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: scenePhase) {
            if scenePhase == .active { await reload() }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its settings and keys are removed from this Apple TV. To use it again, you'll need to add the config again.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No profiles yet", systemImage: "network.slash")
        } description: {
            Text("A profile holds the settings for your own WireGuard server. Once you add one, you can connect this Apple TV to it from here.")
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
    }

    private func toggle(_ entry: TunnelManager.Entry) {
        if entry.status.isActive {
            manager.disconnect(entry.id)
        } else if entry.status != .disconnecting {
            Task {
                do {
                    try await manager.connect(entry.id)
                } catch {
                    errorMessage = "“\(entry.name)” couldn't start. \(error.localizedDescription)"
                }
            }
        }
    }

    private func delete(_ entry: TunnelManager.Entry) {
        Task {
            do {
                try await manager.delete(entry.id)
            } catch {
                errorMessage = "“\(entry.name)” couldn't be deleted. \(error.localizedDescription)"
            }
        }
    }

    private func reload() async {
        do {
            try await manager.load()
        } catch {
            errorMessage = "Your profiles couldn't be loaded. \(error.localizedDescription)"
        }
    }
}
