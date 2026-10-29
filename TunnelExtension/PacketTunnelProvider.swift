import NetworkExtension
import WireGuardKit
import os

private let log = Logger(subsystem: "com.untetheredcitizens.vpn.tunnel", category: "tunnel")

/// The packet-tunnel extension. It reads the profile's config from the
/// Keychain through the persistent reference in its protocol configuration
/// (D31) and runs it with WireGuardKit.
///
/// Logs name the step and the failure, never a key or a config value. The
/// same lines, redacted, go to the Tunnel Log the app shows (`note`).
class PacketTunnelProvider: NEPacketTunnelProvider {

    private let tunnelLog = (try? AppConfiguration.main()).flatMap { TunnelLog(configuration: $0, source: .tunnel) }

    private lazy var adapter = WireGuardAdapter(with: self) { [tunnelLog] level, message in
        // wireguard-go's messages can include peer addresses, so keep them private
        log.log(level: level == .error ? .error : .debug, "\(message, privacy: .private)")
        if level == .error || !RoutineMessages.isRoutine(message) {
            tunnelLog?.add(message)
        }
    }

    /// Adds a line to the Tunnel Log. The system log gets its own call, with
    /// its own privacy marking.
    private func note(_ text: String) {
        tunnelLog?.add(text)
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("Start requested")
        note(options?["is-on-demand"] != nil ? "Start requested by Connect Automatically" : "Start requested")
        let configuration: TunnelConfiguration
        let profileID: UUID?
        do {
            (configuration, profileID) = try loadConfiguration()
        } catch {
            fail(error.failure, profileID: error.profileID, completionHandler: completionHandler)
            return
        }
        adapter.start(tunnelConfiguration: configuration) { error in
            if let error {
                let failure: TunnelFailure = switch error {
                case .dnsResolution: .endpointUnresolved
                case .setNetworkSettings: .networkSettingsRejected
                default: .wireGuardFailed
                }
                self.fail(failure, profileID: profileID, completionHandler: completionHandler)
            } else {
                log.info("Tunnel up")
                self.note("Tunnel up")
                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("Stop requested, reason \(reason.rawValue)")
        note("Stop requested: \(reason.logDescription)")
        adapter.stop { error in
            if let error {
                log.error("Adapter stop failed: \(String(describing: error), privacy: .public)")
                self.note("Adapter stop failed: \(String(describing: error))")
            }
            completionHandler()
        }
    }

    /// Answers the app's stats request. wireguard-go's runtime state includes
    /// the private key, so only the fields `TunnelStats` reads leave here; the
    /// raw text is never logged or returned.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard messageData == TunnelStats.request else {
            completionHandler?(nil)
            return
        }
        adapter.getRuntimeConfiguration { text in
            let reply = text.flatMap { try? JSONEncoder().encode(TunnelStats(runtimeConfiguration: $0)) }
            completionHandler?(reply)
        }
    }

    private struct LoadError: Error {
        let failure: TunnelFailure
        let profileID: UUID?
    }

    private func loadConfiguration() throws(LoadError) -> (TunnelConfiguration, UUID) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let info = TunnelProtocolInfo(proto) else {
            throw LoadError(failure: .missingConfiguration, profileID: nil)
        }
        let text: String
        do {
            text = try ConfigKeychain.text(persistentReference: info.keychainReference)
        } catch {
            log.error("Keychain read failed: \(error.description, privacy: .public)")
            note("Keychain read failed: \(error.description)")
            throw LoadError(failure: .keychainUnreadable, profileID: info.profileID)
        }
        let config: WireGuardConfig
        do {
            config = try WireGuardConfig.parse(text).config
        } catch {
            // ConfigError messages name the section and setting, never a value
            log.error("Saved config invalid: \(error.message, privacy: .public)")
            note("Saved config invalid: \(error.message)")
            throw LoadError(failure: .configInvalid, profileID: info.profileID)
        }
        tunnelLog?.setHosts(config.peers.map(\.endpoint.host))
        guard let configuration = config.tunnelConfiguration(named: info.profileID.uuidString) else {
            log.error("Config conversion to WireGuardKit failed")
            note("Config conversion to WireGuardKit failed")
            throw LoadError(failure: .configInvalid, profileID: info.profileID)
        }
        return (configuration, info.profileID)
    }

    private func fail(_ failure: TunnelFailure, profileID: UUID?, completionHandler: (Error?) -> Void) {
        log.error("Start failed: \(String(describing: failure), privacy: .public)")
        note("Start failed: \(failure.message)")
        if let profileID, let configuration = try? AppConfiguration.main(),
           let defaults = UserDefaults(suiteName: configuration.appGroupID) {
            TunnelFailureRecord.save(TunnelFailureRecord(failure: failure, profileID: profileID), to: defaults)
        }
        completionHandler(failure)
    }
}

private extension NEProviderStopReason {
    /// Why tvOS stopped the tunnel, in words for the Tunnel Log.
    var logDescription: String {
        switch self {
        case .userInitiated: "disconnected from the app"
        case .providerFailed: "the tunnel failed"
        case .noNetworkAvailable: "no network"
        case .unrecoverableNetworkChange: "the network changed"
        case .providerDisabled: "the profile was turned off"
        case .configurationDisabled: "the configuration was turned off"
        case .configurationRemoved: "the profile was deleted"
        case .superceded: "another VPN started"
        case .userLogout: "user logged out"
        case .userSwitch: "user switched"
        case .connectionFailed: "the connection failed"
        case .sleep: "the Apple TV went to sleep"
        case .appUpdate: "the app was updated"
        case .internalError: "internal error"
        default: "reason \(rawValue)"
        }
    }
}
