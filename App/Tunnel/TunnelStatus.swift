import NetworkExtension

/// A profile's tunnel state, as the UI shows it.
enum TunnelStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    /// The tunnel stopped or failed to start; the message says why.
    case failed(String)

    init(_ status: NEVPNStatus) {
        switch status {
        case .connecting, .reasserting: self = .connecting
        case .connected: self = .connected
        case .disconnecting: self = .disconnecting
        case .invalid, .disconnected: self = .disconnected
        @unknown default: self = .disconnected
        }
    }

    /// True while the tunnel is up or on its way up.
    var isActive: Bool {
        self == .connecting || self == .connected
    }

    var label: String {
        switch self {
        case .disconnected: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting…"
        case .failed: "Couldn't connect"
        }
    }
}
