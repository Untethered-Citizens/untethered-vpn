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

    @ObservationIgnored private let configuration: AppConfiguration
    @ObservationIgnored private let keychain: ConfigKeychain
    @ObservationIgnored private let sharedDefaults: UserDefaults?
    @ObservationIgnored private var managers: [UUID: NETunnelProviderManager] = [:]
    @ObservationIgnored private var statusObserver: (any NSObjectProtocol)?
    #if DEBUG
    /// Sample entries for checking layouts in the simulator, which can't run tunnels.
    @ObservationIgnored private var usesSamples = false
    #endif

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        keychain = ConfigKeychain(accessGroup: configuration.keychainGroup, service: configuration.tunnelBundleID)
        sharedDefaults = UserDefaults(suiteName: configuration.appGroupID)
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

    /// The saved config of a profile, for editing.
    func config(for id: UUID) throws -> WireGuardConfig {
        try WireGuardConfig.parse(keychain.text(for: id)).config
    }

    /// Deletes a profile and its Keychain item.
    func delete(_ id: UUID) async throws {
        #if DEBUG
        if usesSamples { entries.removeAll { $0.id == id }; return }
        #endif
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
    }
}

#if DEBUG
extension TunnelManager {

    /// Which sample entries to show, from the launch argument
    /// `-sampleProfiles one|several|failed|empty`.
    enum Samples: String {
        case one, several, failed, empty
    }

    /// Replaces the real profiles with sample entries. Connecting a sample
    /// pretends to succeed; nothing touches the system or the Keychain.
    func showSamples(_ samples: Samples) {
        usesSamples = true
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
    }

    private func sampleConnect(_ id: UUID) {
        for entry in entries where entry.id != id && entry.status.isActive {
            setStatus(.disconnected, for: entry.id)
        }
        setStatus(.connected, for: id)
    }
}
#endif
