import SwiftUI

/// The Tunnel Log: recent lines from the app and the tunnel, newest first,
/// already redacted when they were written. A QR code carries the newest
/// lines for a phone to copy; Clear Log starts afresh.
struct TunnelLogView: View {
    let log: TunnelLog?

    @State private var lines: [TunnelLog.Line] = []
    @State private var confirmingClear = false

    var body: some View {
        HStack(alignment: .top, spacing: 72) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Tunnel Log")
                    .font(.utTitle2)
                    .accessibilityAddTraits(.isHeader)
                Text(TunnelLogText.explanation)
                    .font(.utCaption)
                    .foregroundStyle(UTColor.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if lines.isEmpty {
                    Text(log == nil ? TunnelLogText.unavailable : TunnelLogText.empty)
                        .foregroundStyle(UTColor.muted)
                        .padding(.top, 24)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                LogRow(line: line)
                            }
                        }
                        .padding(16)
                    }
                    .background(UTColor.panel, in: RoundedRectangle(cornerRadius: UTMetrics.cardRadius, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 24) {
                if !lines.isEmpty {
                    QRCodeTile(text: TunnelLogText.qrText(lines), size: 360,
                               failureText: "The code couldn't be drawn.",
                               accessibilityLabel: "QR code of the newest log lines")
                    Text(TunnelLogText.qrHint(TunnelLogText.qrLineCount(lines)))
                        .font(.utCaption)
                        .foregroundStyle(UTColor.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Clear Log", systemImage: "trash", role: .destructive) { confirmingClear = true }
                        .buttonStyle(.utDestructive)
                }
            }
            .frame(width: 400)
        }
        .padding(.vertical, 60)
        .utScreen()
        // New lines appear while the screen is open, for example while reconnecting
        .task {
            while !Task.isCancelled {
                lines = log?.lines() ?? []
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .confirmationDialog("Clear the Tunnel Log?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) {
                log?.clear()
                lines = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every line so far is removed from this Apple TV. New lines are added as the VPN runs.")
        }
    }
}

/// One log line: when, where from, and what. Each row can take focus so the
/// remote scrolls through the list.
private struct LogRow: View {
    let line: TunnelLog.Line
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            Text(line.date.formatted(date: .abbreviated, time: .standard))
                .foregroundStyle(focused ? UTColor.ink : UTColor.muted)
                .frame(width: 330, alignment: .leading)
            Text(line.source.rawValue)
                .foregroundStyle(focused ? UTColor.ink : UTColor.muted)
                .frame(width: 110, alignment: .leading)
            Text(line.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.utCaption.monospacedDigit())
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .utReadingHighlight(focused, radius: 12)
        .focusable()
        .focused($focused)
    }
}

/// The Tunnel Log's wording and the QR code's text.
enum TunnelLogText {

    static let explanation =
        "What the VPN did recently, newest first, from the app and the tunnel. Keys are shown as \(LogRedactor.hiddenKey), the server's address as \(LogRedactor.hiddenHost) and public IP addresses as \(LogRedactor.hiddenIP)."
    static let empty = "Nothing logged yet. Lines appear here when you connect, disconnect, or the network changes."
    static let unavailable = "This build can't keep a log: its App Group is missing. Rebuild it from Config.xcconfig as described in the README."

    static func qrHint(_ count: Int) -> String {
        "Holds the newest \(count) \(count == 1 ? "line" : "lines"). Scan with your iPhone's camera, then tap the small copy button beside the banner. Tapping the banner itself searches the web for the text."
    }

    /// At most this many bytes (about 25 typical lines), so the code still
    /// scans from across a room.
    static let qrMaxBytes = 1_200

    /// How many of the newest lines fit in the QR code.
    static func qrLineCount(_ lines: [TunnelLog.Line]) -> Int {
        var bytes = header.utf8.count
        var count = 0
        for line in lines {
            bytes += row(line).utf8.count
            guard bytes <= qrMaxBytes else { break }
            count += 1
        }
        return count
    }

    /// A heading, then the newest lines that fit, newest first.
    static func qrText(_ lines: [TunnelLog.Line]) -> String {
        header + lines.prefix(qrLineCount(lines)).map(row).joined()
    }

    private static let header = "Untethered VPN tunnel log, newest first\n"

    private static func row(_ line: TunnelLog.Line) -> String {
        "\(stamp.string(from: line.date)) \(line.source.rawValue): \(line.text)\n"
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
