import SwiftUI

/// The main screen: the saved profiles, their status, and Connect/Disconnect.
/// One profile gets a large card; several get a list.
struct HomeView: View {
    let manager: TunnelManager

    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingDelete: TunnelManager.Entry?
    @State private var errorMessage: String?
    @State private var autoConnectNotes: [AutoConnect.TurnedOff] = []
    @State private var editor: EditorRequest?
    @State private var adding: AddRequest?
    @State private var detail: DetailRequest?
    @State private var renaming: RenameRequest?
    @State private var settings: SettingsRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 56) {
            HStack {
                Label("Untethered VPN", systemImage: "network.badge.shield.half.filled")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 40) {
                    if !manager.entries.isEmpty {
                        Button("Add Profile", systemImage: "plus", action: add)
                    }
                    Button("Settings", systemImage: "gearshape") { settings = SettingsRequest() }
                }
            }
            // The whole bar is a focus target, so swiping up from a profile on
            // the left still reaches Add Profile and Settings on the right
            .focusSection()

            Group {
                switch manager.entries.count {
                case 0:
                    emptyState
                case 1:
                    ProfileCard(entry: manager.entries[0], stats: manager.stats[manager.entries[0].id],
                                toggle: toggle, details: showDetails, rename: rename, edit: edit, delete: { pendingDelete = $0 })
                default:
                    ProfileList(entries: manager.entries, stats: manager.stats, preferredID: manager.preferredID,
                                toggle: toggle, details: showDetails, rename: rename, edit: edit, delete: { pendingDelete = $0 })
                }
            }
            // Full width, so swiping down from Add Profile on the right reaches
            // the profile's buttons on the left
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
        // tvOS draws the editor over the home screen without a background of its own
        .opacity(editor == nil && adding == nil && detail == nil && settings == nil ? 1 : 0)
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: scenePhase) {
            if scenePhase == .active { await reload() }
        }
        // Stats for the connected profile, about once a second while the app is in front
        .task(id: scenePhase == .active ? connectedID : nil) {
            guard let id = connectedID, scenePhase == .active else { return }
            while !Task.isCancelled {
                await manager.refreshStats(id)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(item: $renaming) { request in
            RenameView(name: request.name, otherNames: manager.otherNames(excluding: request.id),
                       save: { try await manager.rename(request.id, to: $0) },
                       done: { renaming = nil })
        }
        .fullScreenCover(item: $detail) { request in
            ProfileDetail(manager: manager, id: request.id) { detail = nil }
                .preferredColorScheme(UntetheredVPNApp.debugColorScheme)
        }
        .fullScreenCover(item: $editor) { request in
            ProfileEditor(manager: manager, draft: request.draft, reviewing: request.reviewing, checksAll: request.checksAll) {
                editor = nil
            }
            // A cover doesn't inherit the app's forced appearance
            .preferredColorScheme(UntetheredVPNApp.debugColorScheme)
        }
        .fullScreenCover(item: $settings) { request in
            SettingsView(done: { settings = nil }, startsOnAbout: request.startsOnAbout)
                .preferredColorScheme(UntetheredVPNApp.debugColorScheme)
        }
        .fullScreenCover(item: $adding) { request in
            AddProfileView(manager: manager, done: { adding = nil }, method: request.method)
                .preferredColorScheme(UntetheredVPNApp.debugColorScheme)
        }
        #if DEBUG
        .task {
            editor = EditorRequest.debugSample()
            adding = AddRequest.debugSample()
            // Launch with `-sampleDetail YES` to open Details for the connected
            // profile, or the first one if none is connected
            if UserDefaults.standard.bool(forKey: "sampleDetail"),
               let entry = manager.entries.first(where: { $0.status == .connected }) ?? manager.entries.first {
                detail = DetailRequest(id: entry.id)
            }
            // Launch with `-sampleSettings main|about` to open Settings or About
            switch UserDefaults.standard.string(forKey: "sampleSettings") {
            case "main": settings = SettingsRequest()
            case "about": settings = SettingsRequest(startsOnAbout: true)
            default: break
            }
            // Launch with `-sampleRename <name>` to open Rename for the first
            // profile with that name typed in
            if let name = UserDefaults.standard.string(forKey: "sampleRename"), let first = manager.entries.first {
                renaming = RenameRequest(id: first.id, name: name)
            }
        }
        #endif
        .confirmationDialog(
            pendingDelete?.deleteTitle ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(TunnelManager.Entry.deleteMessage)
        }
        .autoConnectNotes($autoConnectNotes)
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
        } actions: {
            Button("Add Profile", systemImage: "plus", action: add)
                .font(.title3.bold())
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
    }

    private func add() {
        adding = AddRequest()
    }

    /// The profile whose stats to keep fresh.
    private var connectedID: UUID? {
        manager.entries.first { $0.status == .connected }?.id
    }

    private func showDetails(_ entry: TunnelManager.Entry) {
        detail = DetailRequest(id: entry.id)
    }

    private func rename(_ entry: TunnelManager.Entry) {
        renaming = RenameRequest(id: entry.id, name: entry.name)
    }

    private func edit(_ entry: TunnelManager.Entry) {
        do {
            editor = try EditorRequest(editing: entry, manager: manager)
        } catch {
            errorMessage = EditorRequest.failureMessage(for: entry)
        }
    }

    private func toggle(_ entry: TunnelManager.Entry) {
        Task {
            do {
                autoConnectNotes = try await manager.toggle(entry)
            } catch {
                errorMessage = TunnelManager.Entry.connectFailureMessage(entry, error)
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
