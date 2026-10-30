import SwiftUI

/// The status as symbol, word and colour, always together. A failure also
/// shows its reason, unless `compact`, where the reason is left to the row's
/// width. The large one sits in a capsule of `ground`.
struct StatusLabel: View {
    let status: TunnelStatus
    var compact = false
    var ground = UTColor.background

    @Environment(\.utFocused) private var focused

    var body: some View {
        VStack(alignment: compact ? .trailing : .leading, spacing: 12) {
            HStack(spacing: compact ? 12 : 20) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 28 : 46, weight: .semibold))
                    .accessibilityHidden(true)
                Text(status.label)
                    .font(compact ? .utStatusSmall : .utStatus)
            }
            .foregroundStyle(focused ? UTColor.onAccent : color)
            .padding(.leading, compact ? 0 : 26)
            .padding(.trailing, compact ? 0 : 36)
            .padding(.vertical, compact ? 0 : 16)
            .background { if !compact { Capsule().fill(ground) } }

            if case .failed(let reason) = status {
                Text(reason)
                    .font(compact ? .utCaption : .utBody)
                    .foregroundStyle(focused ? UTColor.onAccent : UTColor.muted)
                    .multilineTextAlignment(compact ? .trailing : .leading)
                    .frame(maxWidth: compact ? 520 : 900, alignment: compact ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // SF Symbols until the app's own status symbols are added
    private var symbol: String {
        switch status {
        case .connected: "record.circle"
        case .connecting, .disconnecting: "circle.dotted"
        case .disconnected: "circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch status {
        case .connected: UTColor.green
        case .connecting, .disconnecting: UTColor.ochreInk
        case .disconnected: UTColor.muted
        case .failed: UTColor.plum
        }
    }
}
