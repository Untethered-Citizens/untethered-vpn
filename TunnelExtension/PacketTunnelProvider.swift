import NetworkExtension
import WireGuardKit
import os

private let log = Logger(subsystem: "com.untetheredcitizens.vpn.tunnel", category: "tunnel")

/// The packet-tunnel extension. It links WireGuardKit so the build chain is in
/// place; starting a tunnel arrives in Phase 4.
class PacketTunnelProvider: NEPacketTunnelProvider {

    enum ProviderError: Error {
        case notImplemented
    }

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        log.info("Start requested; tunnels are not implemented yet")
        completionHandler(ProviderError.notImplemented)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("Stop requested, reason \(reason.rawValue)")
        completionHandler()
    }
}
