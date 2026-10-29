import SwiftUI

/// One profile's screen: its status and live stats, Connect/Disconnect,
/// Rename, Edit, Export and Delete. Opened with Details from the home screen.
struct ProfileDetail: View {
    let manager: TunnelManager
    let id: UUID
    let done: () -> Void

    @State private var confirmingDelete = false
    @State private var editor: EditorRequest?
    @State private var renaming: RenameRequest?
    @State private var exporting: ExportRequest?
    @State private var errorMessage: String?
    @State private var autoConnectNotes: [AutoConnect.TurnedOff] = []

    var body: some View {
        Group {
            if let entry {
                content(entry)
            }
        }
        // tvOS draws the editor and export over this screen without a background of their own
        .opacity(editor == nil && exporting == nil ? 1 : 0)
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand(perform: done)
        .onChange(of: entry == nil) { _, gone in
            if gone { done() }
        }
        .sheet(item: $renaming) { request in
            RenameView(name: request.name, otherNames: manager.otherNames(excluding: request.id),
                       save: { try await manager.rename(request.id, to: $0) },
                       done: { renaming = nil })
        }
        .fullScreenCover(item: $exporting) { request in
            ExportView(export: request.export) { exporting = nil }
                .preferredColorScheme(UntetheredVPNApp.debugColorScheme)
        }
        .fullScreenCover(item: $editor) { request in
            ProfileEditor(manager: manager, draft: request.draft) { editor = nil }
                .preferredColorScheme(UntetheredVPNApp.debugColorScheme)
        }
        .autoConnectNotes($autoConnectNotes)
        #if DEBUG
        // Launch with `-sampleDetail YES -sampleExport YES` to open Export too
        .task {
            if UserDefaults.standard.bool(forKey: "sampleExport"), let entry { export(entry) }
        }
        #endif
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var entry: TunnelManager.Entry? {
        manager.entries.first { $0.id == id }
    }

    private func content(_ entry: TunnelManager.Entry) -> some View {
        let stats = entry.status == .connected ? manager.stats[id] : nil
        return VStack(alignment: .leading, spacing: 48) {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.name)
                    .font(.largeTitle.bold())
                Text("Server: \(StatsFormat.endpoint(configured: entry.serverAddress, inUse: stats?.tunnel?.endpoint))")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            StatusLabel(status: entry.status)

            statsSection(entry, stats)

            autoConnectSection(entry)

            HStack(spacing: 40) {
                Button {
                    toggle(entry)
                } label: {
                    Text(entry.status.actionTitle)
                        .font(.title2.bold())
                        .frame(minWidth: 340)
                        .padding(.vertical, 12)
                }
                .disabled(entry.status == .disconnecting)

                Button("Rename", systemImage: "character.cursor.ibeam") {
                    renaming = RenameRequest(id: entry.id, name: entry.name)
                }
                Button("Edit", systemImage: "pencil") { edit(entry) }
                Button("Export", systemImage: "square.and.arrow.up") { export(entry) }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
            .font(.title3)
        }
        .confirmationDialog(entry.deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(TunnelManager.Entry.deleteMessage)
        }
    }

    @ViewBuilder
    private func statsSection(_ entry: TunnelManager.Entry, _ stats: LiveStats?) -> some View {
        if let stats, let tunnel = stats.tunnel {
            VStack(alignment: .leading, spacing: 28) {
                Grid(alignment: .leading, horizontalSpacing: 48, verticalSpacing: 16) {
                    if let connected = stats.connectedFor {
                        row("Connected for", StatsFormat.duration(connected))
                    }
                    row("Last handshake", stats.handshakeAge.map { "\(StatsFormat.duration($0)) ago" } ?? "Never")
                    row("Received", StatsFormat.bytes(tunnel.receivedBytes))
                    row("Sent", StatsFormat.bytes(tunnel.sentBytes))
                }
                .font(.title3)

                if let silence = stats.silence {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        // Orange text is hard to read on the light background; the icon carries the colour
                        Text(silence.message)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.title3)
                    .frame(maxWidth: 1300, alignment: .leading)
                }
            }
        } else if entry.status == .connected {
            Text("Getting the connection's stats…")
                .font(.title3)
                .foregroundStyle(.secondary)
        } else {
            Text("While connected, this shows the last handshake and the data sent and received.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 1300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func autoConnectSection(_ entry: TunnelManager.Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { entry.connectsAutomatically }, set: { setAutomatic(entry, $0) })) {
                Label("Connect Automatically", systemImage: "arrow.triangle.2.circlepath")
                    .font(.title3)
            }
            .frame(maxWidth: 900)
            Text("When on, this Apple TV connects to this profile by itself: at startup, after sleep and when the network changes, without opening the app. One profile at a time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 1300, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setAutomatic(_ entry: TunnelManager.Entry, _ isOn: Bool) {
        Task {
            do {
                autoConnectNotes = try await manager.setConnectsAutomatically(entry.id, isOn)
            } catch {
                errorMessage = "Connect Automatically couldn't be changed for “\(entry.name)”. \(error.localizedDescription)"
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .bold()
                .monospacedDigit()
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

    private func edit(_ entry: TunnelManager.Entry) {
        do {
            editor = try EditorRequest(editing: entry, manager: manager)
        } catch {
            errorMessage = EditorRequest.failureMessage(for: entry)
        }
    }

    private func export(_ entry: TunnelManager.Entry) {
        do {
            exporting = ExportRequest(id: entry.id, export: ProfileExport(name: entry.name, config: try manager.config(for: entry.id)))
        } catch {
            errorMessage = "“\(entry.name)” couldn't be exported. Delete it and add it again."
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
}

/// A request to open a profile's detail screen, for `fullScreenCover(item:)`.
struct DetailRequest: Identifiable {
    let id: UUID
}

extension TunnelManager.Entry {
    static func connectFailureMessage(_ entry: Self, _ error: any Error) -> String {
        "“\(entry.name)” couldn't start. \(error.localizedDescription)"
    }

    var deleteTitle: String { "Delete “\(name)”?" }

    static let deleteMessage =
        "Its settings and keys are removed from this Apple TV. To use it again, you'll need to add the config again."
}
