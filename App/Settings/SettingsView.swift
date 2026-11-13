import SwiftUI

/// Settings, opened from the home screen's header: How It Works, the Tunnel
/// Log and About.
struct SettingsView: View {
    let log: TunnelLog?
    let done: () -> Void
    var startsOn: Page?

    @State private var path: [Page] = []

    enum Page: Hashable {
        case howItWorks, log, about
    }

    var body: some View {
        NavigationStack(path: $path) {
            HStack(spacing: 120) {
                VStack(spacing: 40) {
                    Image("UTMark")
                        .resizable()
                        .frame(width: 360, height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 72, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Untethered VPN")
                        .font(.utTitle2)
                }
                .frame(width: 520)

                VStack(alignment: .leading, spacing: 32) {
                    Text("Settings")
                        .font(.utTitle)

                    link(.howItWorks, "How It Works", "questionmark.circle",
                         "What you need, how to add a profile and connect, and tips for hotel Wi-Fi.")
                    link(.log, "Tunnel Log", "list.bullet.rectangle",
                         "What the VPN did recently, with keys and addresses hidden. Useful when something goes wrong.")
                    link(.about, "About Untethered VPN", "info.circle",
                         "The version, licences and the WireGuard trademark notice.")

                    Button("Done", action: done)
                        .buttonStyle(.utSecondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: 1050)
            }
            .padding(80)
            .frame(maxHeight: .infinity)
            .utScreen()
            .onExitCommand(perform: done)
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .howItWorks: TutorialView { path.removeAll() }
                        .toolbar(.hidden, for: .navigationBar)
                case .log: TunnelLogView(log: log)
                case .about: AboutView()
                }
            }
        }
        .onAppear { if let startsOn { path = [startsOn] } }
    }

    private func link(_ page: Page, _ title: String, _ image: String, _ detail: String) -> some View {
        NavigationLink(value: page) {
            UTRowLabel(title: title, subtitle: detail, systemImage: image)
        }
        .buttonStyle(.utRow)
    }
}

/// A request to open Settings, for `fullScreenCover(item:)`.
struct SettingsRequest: Identifiable {
    let id = UUID()
    var startsOn: SettingsView.Page?
}
