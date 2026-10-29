import SwiftUI

/// Settings, opened from the home screen's header. For now it holds About;
/// the tunnel log joins it later.
struct SettingsView: View {
    let done: () -> Void
    var startsOnAbout = false

    @State private var path: [Page] = []

    enum Page: Hashable {
        case about
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 40) {
                Text("Settings")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 20) {
                    NavigationLink(value: Page.about) {
                        Label("About Untethered VPN", systemImage: "info.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("The version, licences and the WireGuard trademark notice.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                case .about: AboutView()
                }
            }
        }
        .onAppear { if startsOnAbout { path = [.about] } }
    }
}

/// A request to open Settings, for `fullScreenCover(item:)`.
struct SettingsRequest: Identifiable {
    let id = UUID()
    var startsOnAbout = false
}
