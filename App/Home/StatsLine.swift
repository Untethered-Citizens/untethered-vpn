import SwiftUI

/// One line of stats for the connected profile on the home screen, or a
/// short warning when the server has stopped answering.
struct StatsLine: View {
    let stats: LiveStats?
    var compact = false

    var body: some View {
        if let stats, stats.tunnel != nil {
            Group {
                if let silence = stats.silence {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(silence.shortMessage)
                    }
                } else {
                    Text(summary(stats))
                        .foregroundStyle(.secondary)
                }
            }
            .font(compact ? .callout : .title3)
        }
    }

    private func summary(_ stats: LiveStats) -> String {
        let handshake = stats.handshakeAge.map { "Last handshake \(StatsFormat.duration($0, short: true)) ago" }
            ?? "No handshake yet"
        let tunnel = stats.tunnel ?? TunnelStats(peers: [])
        return [
            handshake,
            "Received \(StatsFormat.bytes(tunnel.receivedBytes))",
            "Sent \(StatsFormat.bytes(tunnel.sentBytes))",
        ].joined(separator: " · ")
    }
}
