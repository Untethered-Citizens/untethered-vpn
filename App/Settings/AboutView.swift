import SwiftUI

/// About: the version, the app's licence, the WireGuard trademark notice and
/// the third-party licences. Every paragraph can take focus, so the Siri
/// Remote scrolls through the text a paragraph at a time.
struct AboutView: View {
    var licences = LicenceDocument.bundled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Untethered VPN")
                        .font(.largeTitle.bold())
                    Text("A client for WireGuard®")
                        .font(.title3)
                    Text(About.version(Bundle.main.infoDictionary ?? [:]))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)

                ForEach(About.notices, id: \.self) { notice in
                    FocusableBlock { Text(notice) }
                }

                if let licences {
                    ForEach(Array(licences.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                } else {
                    FocusableBlock {
                        Text("The third-party licences are missing from this build. They're in THIRD_PARTY_LICENSES.md in the source code.")
                    }
                }
            }
            .font(.callout)
            .frame(maxWidth: 1400, alignment: .leading)
            .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private func blockView(_ block: LicenceDocument.Block) -> some View {
        switch block {
        case .title(let text):
            Text(text)
                .font(.title2.bold())
                .padding(.top, 32)
        case .heading(let text):
            Text(text)
                .font(.headline)
                .padding(.top, 16)
        case .paragraph(let text):
            FocusableBlock { Text(markdown: text) }
        case .bullets(let items):
            FocusableBlock {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text("•")
                            Text(markdown: item)
                        }
                    }
                }
            }
        case .verbatim(let text):
            // One focus stop per paragraph, so a long licence never runs off screen
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                FocusableBlock {
                    Text(paragraph)
                        .font(.caption.monospaced())
                }
            }
        }
    }
}

/// What About says, apart from the bundled licences.
enum About {

    /// "Version 0.1.0 (1)", from the app's Info.plist.
    static func version(_ info: [String: Any]) -> String {
        let short = info["CFBundleShortVersionString"] as? String ?? "unknown"
        guard let build = info["CFBundleVersion"] as? String, !build.isEmpty else { return "Version \(short)" }
        return "Version \(short) (\(build))"
    }

    static let notices = [
        "Made by Untethered Citizens. Free and open source under the Apache License 2.0. The name \"Untethered VPN\", its icon and the Untethered Citizens branding aren't covered by the licence.",
        "Untethered VPN has no accounts, ads, analytics or tracking. The only network traffic is your tunnel and, while the import screen is open, the one-time import page on your local network.",
        "\"WireGuard\" and the \"WireGuard\" logo are registered trademarks of Jason A. Donenfeld. Untethered VPN is not affiliated with or endorsed by the WireGuard project.",
    ]
}

/// A block of text that can take focus, so ScrollView scrolls to it, with a
/// light highlight while focused.
private struct FocusableBlock<Content: View>: View {
    @ViewBuilder let content: Content
    @FocusState private var focused: Bool

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(focused ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 16))
            .focusable()
            .focused($focused)
    }
}

private extension Text {
    /// Inline Markdown (bold, code, links), or the plain text if it doesn't parse.
    init(markdown: String) {
        if let attributed = try? AttributedString(markdown: markdown) {
            self.init(attributed)
        } else {
            self.init(markdown)
        }
    }
}
