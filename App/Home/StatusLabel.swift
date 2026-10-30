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
                UTSymbol(Self.symbol(for: status), size: compact ? 30 : 52)
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

    /// The app's own symbols, in Theme.xcassets.
    nonisolated static func symbol(for status: TunnelStatus) -> String {
        switch status {
        case .connected: "ut.status.connected"
        case .connecting, .disconnecting: "ut.status.connecting"
        case .disconnected: "ut.status.notconnected"
        case .failed: "ut.status.failed"
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
