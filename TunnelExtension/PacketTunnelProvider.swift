import NetworkExtension
import WireGuardKit
import os

private let log = Logger(subsystem: "com.untetheredcitizens.vpn.tunnel", category: "tunnel")

/// The packet-tunnel extension. It reads the profile's config from the
/// Keychain through the persistent reference in its protocol configuration
/// (D31) and runs it with WireGuardKit.
///
/// Logs name the step and the failure, never a key or a config value.
class PacketTunnelProvider: NEPacketTunnelProvider {

    private lazy var adapter = WireGuardAdapter(with: self) { level, message in
        // wireguard-go's messages can include peer addresses, so keep them private
        log.log(level: level == .error ? .error : .debug, "\(message, privacy: .private)")
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("Start requested")
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
                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("Stop requested, reason \(reason.rawValue)")
        adapter.stop { error in
            if let error { log.error("Adapter stop failed: \(String(describing: error), privacy: .public)") }
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
            throw LoadError(failure: .keychainUnreadable, profileID: info.profileID)
        }
        let config: WireGuardConfig
        do {
            config = try WireGuardConfig.parse(text).config
        } catch {
            // ConfigError messages name the section and setting, never a value
            log.error("Saved config invalid: \(error.message, privacy: .public)")
            throw LoadError(failure: .configInvalid, profileID: info.profileID)
        }
        guard let configuration = config.tunnelConfiguration(named: info.profileID.uuidString) else {
            log.error("Config conversion to WireGuardKit failed")
            throw LoadError(failure: .configInvalid, profileID: info.profileID)
        }
        return (configuration, info.profileID)
    }

    private func fail(_ failure: TunnelFailure, profileID: UUID?, completionHandler: (Error?) -> Void) {
        log.error("Start failed: \(String(describing: failure), privacy: .public)")
        if let profileID, let configuration = try? AppConfiguration.main(),
           let defaults = UserDefaults(suiteName: configuration.appGroupID) {
            TunnelFailureRecord.save(TunnelFailureRecord(failure: failure, profileID: profileID), to: defaults)
        }
        completionHandler(failure)
    }
}
