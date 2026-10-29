import Foundation

/// A profile written out for troubleshooting, safe to paste into an issue:
/// private and preshared keys and the server's host are hidden. The same
/// text is shown on screen and put in the QR code.
struct ProfileExport: Equatable {
    let name: String
    let text: String

    init(name: String, config: WireGuardConfig) {
        self.name = name
        text = """
            # Exported from Untethered VPN. Keys and the server's address are hidden.

            \(config.wgQuickText(maskingKeys: true, maskingEndpointHosts: true))
            """
    }

    static let hiddenNote =
        "Private and preshared keys are shown as \(WireGuardKey.masked), and the server's address as \(WireGuardConfig.maskedHost). The port, public keys, addresses and DNS are shown as saved."

    static let qrHint = "Scan with your phone's camera to copy this text, for example into a bug report."
}

/// A request to show a profile's export, for `sheet(item:)`.
struct ExportRequest: Identifiable {
    let id: UUID
    let export: ProfileExport
}
