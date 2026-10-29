import Foundation
import NetworkExtension

/// Connect Automatically: tvOS's on-demand rules keep one profile connected
/// by itself, at startup, after sleep, on any network and after a drop,
/// without the app being opened. tvOS keeps one VPN configuration enabled at
/// a time, so only one profile can have it.
///
/// It isn't a kill switch: tvOS has no `includeAllNetworks` (D36), so traffic
/// can go out directly for a moment while the tunnel reconnects.
enum AutoConnect {

    /// Connect on every kind of network tvOS has: Wi-Fi and Ethernet.
    static func rules() -> [NEOnDemandRule] {
        let connect = NEOnDemandRuleConnect()
        connect.interfaceTypeMatch = .any
        return [connect]
    }

    /// The profiles whose Connect Automatically must go off when `id`
    /// connects or turns it on.
    static func othersToTurnOff(for id: UUID, automatic: [UUID]) -> [UUID] {
        automatic.filter { $0 != id }
    }

    /// Why Connect Automatically went off, for an alert.
    enum TurnedOff: Equatable {
        /// The profile was disconnected by hand.
        case disconnected(String)
        /// Another profile was connected or set to connect automatically.
        case replaced(String)

        static let title = "Connect Automatically is off"

        var message: String {
            switch self {
            case .disconnected(let name):
                "Connect Automatically is now off for “\(name)”, so it stays disconnected. To turn it back on, open Details."
            case .replaced(let name):
                "Connect Automatically is now off for “\(name)”, because only one profile can connect automatically."
            }
        }
    }
}
