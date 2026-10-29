import SwiftUI

/// The QR import screen: a code to scan, the address as text, a countdown,
/// and help for awkward networks. When a config arrives it shows the review
/// screen; nothing is saved until Save there.
struct PhoneImportView: View {
    let manager: TunnelManager
    @State var phoneImport: PhoneImport
    let typeInstead: () -> Void
    let done: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch phoneImport.state {
            case .starting:
                ProgressView("Starting…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .waiting(let url, let expires):
                waiting(url: url, expires: expires)
            case .received(let imported):
                NavigationStack {
                    ProfileReview(manager: manager,
                                  profile: TunnelProfile(name: imported.name, config: imported.config),
                                  isEditing: false,
                                  warnings: imported.warnings,
                                  cancelTitle: "Cancel",
                                  cancel: done,
                                  canRename: true,
                                  done: done)
                }
            case .ended(let problem):
                ended(problem)
            }
        }
        .onAppear { phoneImport.start() }
        .onDisappear { phoneImport.stop() }
        .onChange(of: scenePhase) { _, phase in
            // The server runs only while this screen is in front.
            if phase == .active {
                if phoneImport.shouldRestartOnReturn { phoneImport.start() }
            } else {
                phoneImport.stop()
            }
        }
    }

    // MARK: - Waiting for the phone

    private func waiting(url: URL, expires: Date) -> some View {
        VStack(alignment: .leading, spacing: 40) {
            Text("Add a profile from your phone")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 72) {
                VStack(spacing: 28) {
                    qrCode(url)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Label(PhoneImport.timeLeft(until: expires, now: context.date), systemImage: "timer")
                            .font(.title3.monospacedDigit())
                    }
                }

                VStack(alignment: .leading, spacing: 28) {
                    step(1, "Connect your phone to the same Wi-Fi as this Apple TV.")
                    step(2, "Point the phone's camera at the code and open the link.")
                    step(3, "Paste your WireGuard config or choose its file, then select Send.")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or type this address into the phone's browser:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(url.absoluteString)
                            .font(.callout.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 40) {
                        Button("Cancel", action: done)
                        Button("Type It In Instead", action: typeInstead)
                    }
                    .padding(.top, 8)
                }
            }

            help
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func qrCode(_ url: URL) -> some View {
        QRCodeTile(text: url.absoluteString, size: 420,
                   failureText: "The code couldn't be drawn. Type the address instead.",
                   accessibilityLabel: "QR code for the import page")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 36)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trouble connecting?")
                .font(.headline)
            Group {
                Text("Hotel and guest Wi-Fi often keeps devices apart. Turn on your phone's Personal Hotspot, join it from this Apple TV in Settings → Network, then scan again.")
                Text("If the network has a sign-in page, finish signing in on this Apple TV and on the phone first. The phone can't use mobile data to reach the TV.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Ended without a profile

    private func ended(_ problem: PhoneImport.Problem) -> some View {
        ContentUnavailableView {
            Label(problem.title, systemImage: problem == .noNetwork ? "wifi.slash" : "qrcode")
        } description: {
            Text(problem.message)
        } actions: {
            HStack(spacing: 40) {
                Button("Start Again") { phoneImport.start() }
                    .font(.title3.bold())
                    .fixedSize()
                Button("Cancel", action: done)
                    .fixedSize()
            }
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
