import SwiftUI

/// A coloured dot and the status in words. A failure also shows its reason,
/// unless `compact`, where the reason is left to the row's width.
struct StatusLabel: View {
    let status: TunnelStatus
    var compact = false

    var body: some View {
        VStack(alignment: compact ? .trailing : .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: "circle.fill")
                    .font(compact ? .callout : .title3)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(status.label)
                    .font(compact ? .callout.bold() : .title2.bold())
            }
            if case .failed(let reason) = status {
                Text(reason)
                    .font(compact ? .callout : .title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(compact ? .trailing : .leading)
                    .frame(maxWidth: compact ? 520 : 900, alignment: compact ? .trailing : .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch status {
        case .connected: .green
        case .connecting, .disconnecting: .orange
        // A fixed grey: the system grey vanishes on a focused row in dark mode
        case .disconnected: Color(red: 0.56, green: 0.56, blue: 0.58)
        case .failed: .red
        }
    }
}
