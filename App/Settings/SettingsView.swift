import SwiftUI

/// Settings, opened from the home screen's header: the Tunnel Log and About.
struct SettingsView: View {
    let log: TunnelLog?
    let done: () -> Void
    var startsOn: Page?

    @State private var path: [Page] = []

    enum Page: Hashable {
        case log, about
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 40) {
                Text("Settings")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 40) {
                    link(.log, "Tunnel Log", "list.bullet.rectangle",
                         "What the VPN did recently, with keys and addresses hidden. Useful when something goes wrong.")
                    link(.about, "About Untethered VPN", "info.circle",
                         "The version, licences and the WireGuard trademark notice.")
                }
                .frame(maxWidth: 1000)
                .font(.title3)

                Button("Done", action: done)
                    .font(.title3)
            }
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onExitCommand(perform: done)
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .log: TunnelLogView(log: log)
                case .about: AboutView()
                }
            }
        }
        .onAppear { if let startsOn { path = [startsOn] } }
    }

    private func link(_ page: Page, _ title: String, _ image: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(value: page) {
                Label(title, systemImage: image)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A request to open Settings, for `fullScreenCover(item:)`.
struct SettingsRequest: Identifiable {
    let id = UUID()
    var startsOn: SettingsView.Page?
}
