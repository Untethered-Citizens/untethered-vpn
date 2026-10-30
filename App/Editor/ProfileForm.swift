import SwiftUI

/// The manual-entry form: one peer, grouped into this Apple TV's settings
/// and the server's. Each field is checked once it has been changed, and
/// every field is checked when Review is selected.
struct ProfileForm: View {
    typealias Field = ProfileDraft.Field

    @Binding var draft: ProfileDraft
    let review: (TunnelProfile) -> Void
    let cancel: () -> Void

    @FocusState private var focused: Field?
    @State private var checked: Set<Field>
    @State private var showsSummary: Bool

    init(draft: Binding<ProfileDraft>, checksAll: Bool = false, review: @escaping (TunnelProfile) -> Void, cancel: @escaping () -> Void) {
        _draft = draft
        _checked = State(initialValue: checksAll ? Set(Field.allCases) : [])
        _showsSummary = State(initialValue: checksAll)
        self.review = review
        self.cancel = cancel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(draft.isEditing ? "Edit Profile" : "Add Profile")
                        .font(.utTitle2)
                        .accessibilityAddTraits(.isHeader)
                    Text(draft.isEditing
                         ? "Change any setting, then select Review. Saved keys stay unless you type new ones."
                         : "Copy these settings from your WireGuard config. To type with your iPhone, select a field and use the keyboard notification on the phone.")
                        .foregroundStyle(UTColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("Profile") {
                    row(.name, "Name", hint: "Shown on the home screen.")
                }

                section("This Apple TV  ·  [Interface]") {
                    row(.privateKey, "Private Key", keySaved: draft.savedPrivateKey != nil,
                        hint: "44 characters ending in =. Shown as dots once entered.", secure: true)
                    row(.address, "Address", hint: "This Apple TV's address in the tunnel.")
                    row(.dns, "DNS (optional)", hint: "Name servers to use while connected, separated by commas.")
                    row(.mtu, "MTU (optional)", hint: "Leave blank unless your config sets it.", numeric: true)
                }

                section("Your Server  ·  [Peer]") {
                    row(.publicKey, "Public Key", hint: "The server's public key: 44 characters ending in =.")
                    row(.presharedKey, "Preshared Key (optional)", keySaved: draft.savedPresharedKey != nil,
                        hint: "Only if your config has one. Shown as dots once entered.", secure: true)
                    if draft.isEditing, draft.savedPresharedKey != nil {
                        Button("Remove Saved Preshared Key", role: .destructive) {
                            draft.savedPresharedKey = nil
                        }
                        .buttonStyle(.utDestructive)
                    }
                    row(.endpoint, "Endpoint", hint: "The server's public address and port.")
                    row(.allowedIPs, "AllowedIPs", hint: "0.0.0.0/0, ::/0 sends all traffic through your server.")
                    row(.keepalive, "Persistent Keepalive (optional)",
                        hint: "Seconds between keepalive packets. 25 keeps the connection open through hotel routers.", numeric: true)
                }

                if !draft.otherPeers.isEmpty {
                    Text("This profile has \(draft.otherPeers.count) more \(draft.otherPeers.count == 1 ? "peer" : "peers"), which stay as they are.")
                        .foregroundStyle(UTColor.muted)
                }

                VStack(alignment: .leading, spacing: 24) {
                    if showsSummary, !draft.problemFields.isEmpty {
                        Label("Fix the settings marked in red, then select Review.", systemImage: "exclamationmark.circle.fill")
                            .font(.utHeadline)
                            .foregroundStyle(UTColor.plum)
                    }
                    HStack(spacing: 28) {
                        Button("Review", action: submit)
                            .buttonStyle(.utHero)
                        Button("Cancel", role: .cancel, action: cancel)
                            .buttonStyle(.utSecondary)
                    }
                }
            }
            .frame(maxWidth: 1400, alignment: .leading)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        // Rows lift when focused; don't clip them at the edges
        .scrollClipDisabled()
        .utScreen()
    }

    private func submit() {
        checked = Set(Field.allCases)
        if let profile = draft.makeProfile() {
            showsSummary = false
            review(profile)
        } else {
            showsSummary = true
            focused = draft.problemFields.first
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            Text(title)
                .font(.utHeadline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func row(_ field: Field, _ title: String, keySaved: Bool = false, hint: String, secure: Bool = false, numeric: Bool = false) -> some View {
        let prompt = ProfileDraft.prompt(for: field, keySaved: keySaved)
        let text = Binding {
            draft[keyPath: Self.keyPath(field)]
        } set: {
            draft[keyPath: Self.keyPath(field)] = $0
            checked.insert(field)
        }
        let problem = checked.contains(field) ? draft.problem(in: field) : nil

        return UTFieldRow(label: title, note: problem ?? hint, isProblem: problem != nil, focused: focused == field) {
            Group {
                if secure {
                    SecureField(title, text: text, prompt: Text(prompt))
                } else {
                    TextField(title, text: text, prompt: Text(prompt))
                        .keyboardType(numeric ? .numberPad : .asciiCapable)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused, equals: field)
        }
    }

    private static func keyPath(_ field: Field) -> WritableKeyPath<ProfileDraft, String> {
        switch field {
        case .name: \.name
        case .privateKey: \.privateKey
        case .address: \.address
        case .dns: \.dns
        case .mtu: \.mtu
        case .publicKey: \.publicKey
        case .presharedKey: \.presharedKey
        case .endpoint: \.endpoint
        case .allowedIPs: \.allowedIPs
        case .keepalive: \.keepalive
        }
    }
}
