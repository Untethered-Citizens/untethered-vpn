import Foundation
import NetworkExtension
import Observation
import os

private let log = Logger(subsystem: "com.untetheredcitizens.vpn", category: "tunnel-manager")

/// Saves, lists and deletes profiles, and connects and disconnects their
/// tunnels. Each profile is one `NETunnelProviderManager` in the system's VPN
/// preferences, with its config in the Keychain (D31).
@MainActor @Observable
final class TunnelManager {

    /// A saved profile as the list shows it. The config itself stays in the
    /// Keychain until it's needed.
    struct Entry: Identifiable, Equatable {
        let id: UUID
        var name: String
        var serverAddress: String
        var status: TunnelStatus
    }

    private(set) var entries: [Entry] = []
    /// The latest stats of each connected profile that's been asked for.
    private(set) var stats: [UUID: LiveStats] = [:]

    @ObservationIgnored private let configuration: AppConfiguration
    @ObservationIgnored private let keychain: ConfigKeychain
    @ObservationIgnored private let sharedDefaults: UserDefaults?
    @ObservationIgnored private let lastUsed: LastUsedProfile
    @ObservationIgnored private var managers: [UUID: NETunnelProviderManager] = [:]
    @ObservationIgnored private var statusObserver: (any NSObjectProtocol)?
    #if DEBUG
    /// Sample entries for checking layouts in the simulator, which can't run tunnels.
    @ObservationIgnored private var usesSamples = false
    @ObservationIgnored private var sampleConfigs: [UUID: WireGuardConfig] = [:]
    @ObservationIgnored private var sampleConnectedAt: [UUID: Date] = [:]
    @ObservationIgnored private var sampleStats = SampleStats.live
    #endif

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        keychain = ConfigKeychain(accessGroup: configuration.keychainGroup, service: configuration.tunnelBundleID)
        sharedDefaults = UserDefaults(suiteName: configuration.appGroupID)
        lastUsed = LastUsedProfile(defaults: sharedDefaults)
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            let connectionID = ObjectIdentifier(connection)
            let status = connection.status
            MainActor.assumeIsolated { self?.connectionChanged(connectionID, status: status) }
        }
    }

    /// Loads the saved profiles from the system's VPN preferences.
    func load() async throws {
        #if DEBUG
        if usesSamples { return }
        #endif
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        var managers: [UUID: NETunnelProviderManager] = [:]
        var entries: [Entry] = []
        for manager in all {
            guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
                  let info = TunnelProtocolInfo(proto) else { continue }
            managers[info.profileID] = manager
            entries.append(Entry(
                id: info.profileID,
                name: manager.localizedDescription ?? "",
                serverAddress: info.serverAddress,
                status: TunnelStatus(manager.connection.status)
            ))
        }
        self.managers = managers
        self.entries = entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Saves a new profile or replaces an existing one with the same ID.
    func save(_ profile: TunnelProfile) async throws {
        #if DEBUG
        if usesSamples { sampleSave(profile); return }
        #endif
        let reference = try keychain.save(profile.config.wgQuickText(), for: profile.id)
        let info = TunnelProtocolInfo(profile: profile, keychainReference: reference)
        let manager = managers[profile.id] ?? NETunnelProviderManager()
        manager.protocolConfiguration = info.makeProtocol(providerBundleID: configuration.tunnelBundleID)
        manager.localizedDescription = profile.name
        if managers[profile.id] == nil { manager.isEnabled = true }
        do {
            try await manager.saveToPreferences()
        } catch {
            // A new profile the system refused shouldn't leave keys behind
            if managers[profile.id] == nil { try? keychain.delete(for: profile.id) }
            throw error
        }
        log.info("Saved a profile")
        try await load()
    }

    /// Renames a profile. Only the name in the system's VPN preferences
    /// changes; the config and keys are untouched. Throws `NameProblem` if
    /// the name breaks the rules, e.g. another profile already has it.
    func rename(_ id: UUID, to name: String) async throws {
        let name = ProfileName.cleaned(name)
        if let problem = ProfileName.problem(name, otherNames: otherNames(excluding: id)) {
            throw NameProblem(message: problem)
        }
        #if DEBUG
        if usesSamples { sampleRename(id, to: name); return }
        #endif
        guard let manager = managers[id] else { return }
        manager.localizedDescription = name
        try await manager.saveToPreferences()
        log.info("Renamed a profile")
        try await load()
    }

    struct NameProblem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The names of every saved profile except `id`, for the name rules.
    func otherNames(excluding id: UUID?) -> [String] {
        entries.filter { $0.id != id }.map(\.name)
    }

    /// Where the home screen's focus starts: the connected profile, else the
    /// one connected last, if it still exists.
    var preferredID: UUID? {
        entries.first { $0.status.isActive }?.id ?? lastUsed.id(among: entries.map(\.id))
    }

    /// The saved config of a profile, for editing.
    func config(for id: UUID) throws -> WireGuardConfig {
        #if DEBUG
        if usesSamples, let config = sampleConfigs[id] { return config }
        #endif
        return try WireGuardConfig.parse(keychain.text(for: id)).config
    }

    /// Deletes a profile and its Keychain item.
    func delete(_ id: UUID) async throws {
        #if DEBUG
        if usesSamples { entries.removeAll { $0.id == id }; return }
        #endif
        lastUsed.forget(id)
        if let manager = managers[id] {
            manager.connection.stopVPNTunnel()
            try await manager.removeFromPreferences()
        }
        try keychain.delete(for: id)
        log.info("Deleted a profile")
        try await load()
    }

    /// Connects a profile, disconnecting any other first.
    func connect(_ id: UUID) async throws {
        #if DEBUG
        if usesSamples { sampleConnect(id); return }
        #endif
        lastUsed.remember(id)
        guard let manager = managers[id] else { return }
        for (otherID, other) in managers where otherID != id && TunnelStatus(other.connection.status).isActive {
            other.connection.stopVPNTunnel()
        }
        if let sharedDefaults { TunnelFailureRecord.clear(from: sharedDefaults) }
        if !manager.isEnabled {
            // Enabling one configuration disables the app's others
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        }
        setStatus(.connecting, for: id)
        do {
            try manager.connection.startVPNTunnel()
        } catch {
            setStatus(.failed(error.localizedDescription), for: id)
            throw error
        }
    }

    /// Disconnects a profile.
    func disconnect(_ id: UUID) {
        #if DEBUG
        if usesSamples { setStatus(.disconnected, for: id); return }
        #endif
        managers[id]?.connection.stopVPNTunnel()
    }

    /// Disconnects a profile that's up or on its way up, and connects one
    /// that isn't. Does nothing while it's disconnecting.
    func toggle(_ entry: Entry) async throws {
        if entry.status.isActive {
            disconnect(entry.id)
        } else if entry.status != .disconnecting {
            try await connect(entry.id)
        }
    }

    /// Asks a connected profile's extension for its stats and stores them
    /// in `stats`. Called about once a second while a screen shows them.
    func refreshStats(_ id: UUID) async {
        #if DEBUG
        if usesSamples { sampleRefreshStats(id); return }
        #endif
        guard let manager = managers[id], let session = manager.connection as? NETunnelProviderSession,
              TunnelStatus(session.status) == .connected else { return }
        let connectedSince = session.connectedDate
        let reply: Data? = await withCheckedContinuation { continuation in
            do {
                try session.sendProviderMessage(TunnelStats.request) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(returning: nil)
            }
        }
        let tunnel = reply.flatMap { try? JSONDecoder().decode(TunnelStats.self, from: $0) }
        // The tunnel may have gone down while waiting
        guard entries.first(where: { $0.id == id })?.status == .connected else { return }
        stats[id] = LiveStats(connectedSince: connectedSince, tunnel: tunnel, fetchedAt: .now)
    }

    private func connectionChanged(_ connectionID: ObjectIdentifier, status: NEVPNStatus) {
        guard let id = managers.first(where: { ObjectIdentifier($0.value.connection) == connectionID })?.key else { return }
        var newStatus = TunnelStatus(status)
        if newStatus == .disconnected, let sharedDefaults,
           let failure = TunnelFailureRecord.take(for: id, from: sharedDefaults) {
            newStatus = .failed(failure.message)
        }
        setStatus(newStatus, for: id)
    }

    private func setStatus(_ status: TunnelStatus, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = status
        if status != .connected { stats[id] = nil }
    }
}

#if DEBUG
extension TunnelManager {

    /// Which sample entries to show, from the launch argument
    /// `-sampleProfiles one|several|failed|empty`.
    enum Samples: String {
        case one, several, failed, empty
    }

    /// What connected samples report, from `-sampleStats live|stale|never`.
    enum SampleStats: String {
        /// Handshakes every 2 minutes and steady traffic.
        case live
        /// The last handshake was over 4 minutes ago.
        case stale
        /// Connected 5 minutes, no handshake yet.
        case never
    }

    /// Replaces the real profiles with sample entries. Connecting a sample
    /// pretends to succeed; nothing touches the system or the Keychain.
    func showSamples(_ samples: Samples, stats: SampleStats = .live) {
        usesSamples = true
        sampleStats = stats
        func entry(_ name: String, _ server: String, _ status: TunnelStatus) -> Entry {
            Entry(id: UUID(), name: name, serverAddress: server, status: status)
        }
        entries = switch samples {
        case .one: [entry("Home", "vpn.example.com:51820", .disconnected)]
        case .several: [
            entry("Cottage", "198.51.100.7:51820", .disconnected),
            entry("Home", "vpn.example.com:51820", .connected),
            entry("Office", "office.example.net:443", .disconnected),
        ]
        case .failed: [entry("Home", "vpn.example.com:51820", .failed(TunnelFailure.endpointUnresolved.message))]
        case .empty: []
        }
        for entry in entries where entry.status == .connected {
            sampleConnectedAt[entry.id] = .now.addingTimeInterval(-4_330)
        }
    }

    /// Saving a sample keeps it in memory only.
    private func sampleSave(_ profile: TunnelProfile) {
        sampleConfigs[profile.id] = profile.config
        let entry = Entry(id: profile.id, name: profile.name,
                          serverAddress: profile.config.peers.first?.endpoint.description ?? "", status: .disconnected)
        if let index = entries.firstIndex(where: { $0.id == profile.id }) {
            entries[index].name = entry.name
            entries[index].serverAddress = entry.serverAddress
        } else {
            entries.append(entry)
        }
    }

    private func sampleConnect(_ id: UUID) {
        for entry in entries where entry.id != id && entry.status.isActive {
            setStatus(.disconnected, for: entry.id)
        }
        sampleConnectedAt[id] = .now
        setStatus(.connected, for: id)
    }

    private func sampleRename(_ id: UUID, to name: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].name = name
        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Made-up stats that grow with the time since the sample connected.
    private func sampleRefreshStats(_ id: UUID) {
        guard let connectedAt = sampleConnectedAt[id],
              entries.first(where: { $0.id == id })?.status == .connected else { return }
        let now = Date.now
        var connectedSince = connectedAt
        let elapsed = now.timeIntervalSince(connectedAt)
        let handshake: Date? = switch sampleStats {
        case .live: now.addingTimeInterval(-elapsed.truncatingRemainder(dividingBy: 120))
        case .stale: now.addingTimeInterval(-250)
        case .never: nil
        }
        if sampleStats == .never { connectedSince = now.addingTimeInterval(-300) }
        let peer = TunnelStats.Peer(
            endpoint: "203.0.113.5:51820",
            lastHandshake: handshake,
            receivedBytes: sampleStats == .never ? 0 : UInt64(elapsed * 330_000),
            sentBytes: UInt64(elapsed * 8_400)
        )
        stats[id] = LiveStats(connectedSince: connectedSince, tunnel: TunnelStats(peers: [peer]), fetchedAt: now)
    }
}
#endif
