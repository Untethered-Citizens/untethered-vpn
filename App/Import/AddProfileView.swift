import SwiftUI

/// Add Profile: choose between sending the config from a phone (the QR
/// import) and typing it in, then run that flow. Back from the import screen
/// returns here; Cancel anywhere closes Add Profile.
struct AddProfileView: View {
    enum Method {
        case phone(PhoneImport)
        case manual
    }

    let manager: TunnelManager
    let done: () -> Void
    @State var method: Method?

    var body: some View {
        switch method {
        case nil:
            choice
        case .phone(let phoneImport):
            PhoneImportView(manager: manager, phoneImport: phoneImport,
                            typeInstead: { method = .manual }, done: done)
                .onExitCommand { method = nil }
        case .manual:
            ProfileEditor(manager: manager, draft: ProfileDraft(), done: done)
        }
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 56) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a profile")
                    .font(.utTitle2)
                Text("A profile holds the settings from your WireGuard config. Choose how to bring them to this Apple TV.")
                    .foregroundStyle(UTColor.muted)
            }

            HStack(spacing: 60) {
                option("Use Your Phone", symbol: "ut.phone",
                       detail: "Scan a code on this screen, then paste your config or choose its file on the phone. Easiest for long keys.") {
                    method = .phone(PhoneImport())
                }
                option("Type It In", symbol: "ut.keyboard",
                       detail: "Enter each setting with the remote or your iPhone's keyboard.") {
                    method = .manual
                }
            }

            Button("Cancel", action: done)
                .buttonStyle(.utSecondary)
        }
        .padding(.vertical, 60)
        .utScreen()
    }

    private func option(_ title: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            OptionLabel(title: title, symbol: symbol, detail: detail)
        }
        .buttonStyle(.utCard)
    }
}

/// A choice card's content; the detail text dims less when focused, so it
/// stays readable on green.
private struct OptionLabel: View {
    let title: String
    let symbol: String
    let detail: String
    @Environment(\.utFocused) private var focused

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            UTSymbol(symbol, size: 84)
                .foregroundStyle(focused ? UTColor.onAccent : UTColor.green)
            Text(title)
                .font(.utHeadline)
            Text(detail)
                .font(.utCaption)
                .foregroundStyle(focused ? UTColor.onAccent : UTColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 640, height: 360, alignment: .topLeading)
        .padding(48)
    }
}

/// A request to open Add Profile, for `fullScreenCover(item:)`.
struct AddRequest: Identifiable {
    let id = UUID()
    var method: AddProfileView.Method?
}

#if DEBUG
extension AddRequest {

    /// Opens Add Profile at launch with
    /// `-sampleImport choose|live|waiting|received|timedOut|tooMany|noNetwork`.
    /// `live` runs the real import server, which works in the simulator on
    /// the Mac's own network.
    @MainActor static func debugSample() -> AddRequest? {
        guard let name = UserDefaults.standard.string(forKey: "sampleImport") else { return nil }
        switch name {
        case "choose": return AddRequest()
        case "live": return AddRequest(method: .phone(PhoneImport()))
        default: return PhoneImport.sample(name).map { AddRequest(method: .phone($0)) }
        }
    }
}
#endif
