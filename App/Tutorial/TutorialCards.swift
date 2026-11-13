import SwiftUI

/// The six How It Works cards, one idea each. The wording was agreed before
/// it was built; change it with care.
enum TutorialCard: Int, CaseIterable, Identifiable {
    case overview, server, peer, add, connect, away

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: "Your home network, anywhere"
        case .server: "You need your own WireGuard server"
        case .peer: "Give this Apple TV its own peer"
        case .add: "Add it to this Apple TV"
        case .connect: "Connect"
        case .away: "Away from home"
        }
    }

    /// SF Symbols the cards draw, so a test can check they exist.
    static let symbols = SetupDiagram.symbols + ["wifi.exclamationmark", "personalhotspot", "list.bullet.rectangle", "arrow.triangle.2.circlepath"]
}

/// One card's content, below its title.
struct TutorialCardContent: View {
    let card: TutorialCard

    var body: some View {
        switch card {
        case .overview: overview
        case .server: server
        case .peer: peer
        case .add: add
        case .connect: connect
        case .away: away
        }
    }

    // MARK: - 1

    private var overview: some View {
        VStack(alignment: .leading, spacing: 56) {
            Text("Untethered VPN connects this Apple TV to **your own WireGuard server**, usually at home. While you're away, your streaming apps reach the internet through your home connection, as if the Apple TV never left.")
                .frame(maxWidth: 1400, alignment: .leading)
            SetupDiagram()
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 2

    private var server: some View {
        HStack(alignment: .top, spacing: 96) {
            VStack(alignment: .leading, spacing: 28) {
                Text("This app is the Apple TV half. The server half isn't included: you set it up yourself, once, on equipment you control.")
                Text("A few popular ways to run one (there are many more):")
                VStack(alignment: .leading, spacing: 14) {
                    bullet("**LinuxServer.io's WireGuard container** for Docker, on a NAS or home server")
                    bullet("**wg-easy**, a Docker container with a web page for adding devices")
                    bullet("**PiVPN** on a Raspberry Pi")
                    bullet("A **router with WireGuard built in**")
                }
                Text("Already have one? Great, you're most of the way there.")
                    .foregroundStyle(UTColor.muted)
            }
            VStack(spacing: 24) {
                QRCodeTile(text: Tutorial.serverGuideURL.absoluteString, size: 300,
                           failureText: "Search for “Untethered VPN” on GitHub",
                           accessibilityLabel: "A QR code for the server setup guide on GitHub")
                Text("Scan with your phone for a short guide and links")
                    .font(.utCaption)
                    .foregroundStyle(UTColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(width: 364)
            }
        }
    }

    // MARK: - 3

    private var peer: some View {
        HStack(alignment: .top, spacing: 96) {
            VStack(alignment: .leading, spacing: 28) {
                Text("On your server, add a new peer just for this Apple TV, and get its config: a `.conf` file with `[Interface]` and `[Peer]` sections. Most server tools can show it as text or download it.")
                Text("Don't reuse another device's peer: two devices with the same keys knock each other off.")
            }
            sampleConfig
        }
    }

    /// What a config looks like, keys hidden as they are everywhere in the
    /// app. Documentation addresses only.
    private var sampleConfig: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                Text("[Interface]").foregroundStyle(UTColor.green)
                Text("PrivateKey = ••••••••")
                Text("Address = 192.0.2.2/32")
                Text("DNS = 192.0.2.1")
                Text(" ")
                Text("[Peer]").foregroundStyle(UTColor.green)
                Text("PublicKey = ••••••••")
                Text("Endpoint = vpn.example.com:51820")
                Text("AllowedIPs = 0.0.0.0/0, ::/0")
            }
            .font(.system(size: 28, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(width: 600, alignment: .leading)
        .utPanel(radius: UTMetrics.cardRadius, padding: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("An example config, with an Interface section and a Peer section. Keys are hidden.")
    }

    // MARK: - 4

    private var add: some View {
        HStack(alignment: .top, spacing: 96) {
            VStack(alignment: .leading, spacing: 28) {
                Text("Choose **Add Profile**, then:")
                VStack(alignment: .leading, spacing: 14) {
                    bullet("**Use Your Phone:** scan the code on the TV with your iPhone's camera, then paste the config or choose the `.conf` file. Your phone encrypts it before sending it to the TV.")
                    bullet("**Type It In:** enter each setting with the remote or your iPhone's keyboard.")
                }
                Text("Either way, you check what arrived, with keys hidden, before choosing **Save**. The first time, tvOS asks to allow VPN configurations: choose **Allow**.")
            }
            VStack(spacing: 32) {
                method("ut.phone", "Use Your Phone")
                method("ut.keyboard", "Type It In")
            }
            .accessibilityHidden(true)
        }
    }

    private func method(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 28) {
            UTSymbol(symbol, size: 72)
                .foregroundStyle(UTColor.green)
            Text(title).font(.utRowTitle)
        }
        .frame(width: 440, alignment: .leading)
        .utPanel(radius: UTMetrics.cardRadius, padding: 36)
    }

    // MARK: - 5

    private var connect: some View {
        HStack(alignment: .top, spacing: 96) {
            VStack(alignment: .leading, spacing: 28) {
                Text("Select your profile on the home screen and choose **Connect**. While connected, it shows the last handshake and the data sent and received.")
                Text("To stay connected without opening the app, turn on **Connect Automatically** in the profile's **Details**. The Apple TV then reconnects by itself after a restart, sleep or a network change. One profile at a time.")
            }
            VStack(spacing: 28) {
                UTSymbol("ut.tv.connected", size: 220)
                    .foregroundStyle(UTColor.green)
                Label("Connect Automatically", systemImage: "arrow.triangle.2.circlepath")
                    .font(.utRowTitle)
                    .foregroundStyle(UTColor.green)
            }
            .frame(width: 520)
            .accessibilityHidden(true)
        }
    }

    // MARK: - 6

    private var away: some View {
        VStack(alignment: .leading, spacing: 36) {
            tip("wifi.exclamationmark", "Sign-in pages", "Finish the hotel's Wi-Fi sign-in on this Apple TV before connecting.")
            tip("personalhotspot", "Phone can't reach the TV?", "Hotel Wi-Fi often keeps devices apart. Turn on your phone's Personal Hotspot, join it in Settings → Network, and try again. Or use **Type It In**.")
            tip("list.bullet.rectangle", "Something wrong?", "Settings → **Tunnel Log** shows what the tunnel is doing, with keys and addresses hidden.")
            Text("You can see this guide again from **Settings**.")
                .foregroundStyle(UTColor.muted)
                .padding(.top, 8)
        }
        .frame(maxWidth: 1400, alignment: .leading)
    }

    private func tip(_ symbol: String, _ title: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 32) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(UTColor.green)
                .frame(width: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.utRowTitle)
                Text(text)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text("•").foregroundStyle(UTColor.green)
                .accessibilityHidden(true)
            // Wrap rather than shrink
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
