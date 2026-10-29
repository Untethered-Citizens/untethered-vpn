import Testing
@testable import UntetheredVPN

struct ProfileDraftTests {

    /// A new draft with every required field filled in.
    private func filledDraft() -> ProfileDraft {
        var draft = ProfileDraft()
        draft.privateKey = Fixtures.randomKeyText()
        draft.address = "10.8.0.2/32"
        draft.publicKey = Fixtures.randomKeyText()
        draft.endpoint = "vpn.example.com:51820"
        return draft
    }

    @Test func newDraftHasTheAgreedDefaults() {
        let draft = ProfileDraft()
        #expect(draft.name == "Home")
        #expect(draft.allowedIPs == "0.0.0.0/0, ::/0")
        #expect(draft.keepalive == "25")
        #expect(!draft.isEditing)
        #expect(draft.problemFields == [.privateKey, .address, .publicKey, .endpoint])
    }

    @Test func buildsTheProfileWithDefaults() throws {
        let draft = filledDraft()
        let profile = try #require(draft.makeProfile())
        let interface = profile.config.interface
        let peer = try #require(profile.config.peers.first)
        #expect(profile.name == "Home")
        #expect(interface.privateKey.base64 == draft.privateKey)
        #expect(interface.addresses.map(\.description) == ["10.8.0.2/32"])
        #expect(interface.dnsServers.isEmpty)
        #expect(interface.mtu == nil)
        #expect(peer.publicKey.base64 == draft.publicKey)
        #expect(peer.presharedKey == nil)
        #expect(peer.endpoint.description == "vpn.example.com:51820")
        #expect(peer.allowedIPs == CIDRRange.allTraffic)
        #expect(peer.persistentKeepalive == 25)
        #expect(profile.config.peers.count == 1)
    }

    @Test func readsOptionalFields() throws {
        var draft = filledDraft()
        draft.dns = "192.0.2.53, home.example.com"
        draft.mtu = "1420"
        draft.presharedKey = Fixtures.randomKeyText()
        draft.keepalive = ""
        let profile = try #require(draft.makeProfile())
        #expect(profile.config.interface.dnsServers == ["192.0.2.53"])
        #expect(profile.config.interface.dnsSearchDomains == ["home.example.com"])
        #expect(profile.config.interface.mtu == 1420)
        #expect(profile.config.peers[0].presharedKey?.base64 == draft.presharedKey)
        #expect(profile.config.peers[0].persistentKeepalive == nil)
    }

    @Test func zeroKeepaliveMeansOff() throws {
        var draft = filledDraft()
        draft.keepalive = "0"
        #expect(try #require(draft.makeProfile()).config.peers[0].persistentKeepalive == nil)
    }

    @Test func toleratesSpacesAndLineBreaksFromAPaste() throws {
        var draft = filledDraft()
        let key = draft.privateKey
        draft.privateKey = " \(key.prefix(20))\n\(key.dropFirst(20)) "
        draft.endpoint = " vpn.example.com:51820\n"
        draft.name = "  Cottage "
        let profile = try #require(draft.makeProfile())
        #expect(profile.config.interface.privateKey.base64 == key)
        #expect(profile.name == "Cottage")
    }

    @Test(arguments: [
        (ProfileDraft.Field.name, ""),
        (.name, String(repeating: "x", count: ProfileDraft.maxNameLength + 1)),
        (.privateKey, "abc"),
        (.address, "10.8.0.2/33"),
        (.address, "10.8.0.2/32,"),
        (.dns, "192.0.2.53,,"),
        (.mtu, "100"),
        (.mtu, "1420a"),
        (.publicKey, ""),
        (.presharedKey, "not a key"),
        (.endpoint, "vpn.example.com"),
        (.endpoint, "2001:db8::1:51820"),
        (.allowedIPs, ""),
        (.keepalive, "-1"),
    ])
    func reportsAProblem(field: ProfileDraft.Field, value: String) {
        var draft = filledDraft()
        switch field {
        case .name: draft.name = value
        case .privateKey: draft.privateKey = value
        case .address: draft.address = value
        case .dns: draft.dns = value
        case .mtu: draft.mtu = value
        case .publicKey: draft.publicKey = value
        case .presharedKey: draft.presharedKey = value
        case .endpoint: draft.endpoint = value
        case .allowedIPs: draft.allowedIPs = value
        case .keepalive: draft.keepalive = value
        }
        #expect(draft.problemFields == [field])
        #expect(draft.makeProfile() == nil)
    }

    @Test func problemsNeverRepeatTheValue() {
        var draft = filledDraft()
        let almostKey = String(Fixtures.randomKeyText().dropFirst())
        draft.privateKey = almostKey
        draft.presharedKey = almostKey
        for field in ProfileDraft.Field.allCases {
            #expect(!(draft.problem(in: field) ?? "").contains(almostKey))
        }
    }

    // MARK: - Editing

    private func savedProfile() throws -> TunnelProfile {
        var draft = filledDraft()
        draft.name = "Cottage"
        draft.presharedKey = Fixtures.randomKeyText()
        draft.mtu = "1380"
        return try #require(draft.makeProfile())
    }

    @Test func editingStartsWithKeysBlankAndOtherFieldsFilled() throws {
        let profile = try savedProfile()
        let draft = ProfileDraft(editing: profile)
        #expect(draft.isEditing)
        #expect(draft.privateKey.isEmpty)
        #expect(draft.presharedKey.isEmpty)
        #expect(draft.name == "Cottage")
        #expect(draft.publicKey == profile.config.peers[0].publicKey.base64)
        #expect(draft.mtu == "1380")
        #expect(draft.problemFields.isEmpty)
    }

    @Test func editingKeepsSavedKeysAndTheProfileID() throws {
        let profile = try savedProfile()
        var draft = ProfileDraft(editing: profile)
        draft.endpoint = "198.51.100.7:443"
        let edited = try #require(draft.makeProfile())
        #expect(edited.id == profile.id)
        #expect(edited.config.interface.privateKey == profile.config.interface.privateKey)
        #expect(edited.config.peers[0].presharedKey == profile.config.peers[0].presharedKey)
        #expect(edited.config.peers[0].endpoint.description == "198.51.100.7:443")
    }

    @Test func editingReplacesOrRemovesKeys() throws {
        let profile = try savedProfile()
        var draft = ProfileDraft(editing: profile)
        let newKey = Fixtures.randomKeyText()
        draft.privateKey = newKey
        draft.savedPresharedKey = nil
        let edited = try #require(draft.makeProfile())
        #expect(edited.config.interface.privateKey.base64 == newKey)
        #expect(edited.config.peers[0].presharedKey == nil)
    }

    @Test func editingKeepsSettingsTheFormDoesNotShow() throws {
        let fixture = Fixtures.Config()
        let config = try WireGuardConfig.parse(fixture.text(
            interfaceExtra: "ListenPort = 51000",
            peerExtra: "\n[Peer]\nPublicKey = \(Fixtures.randomKeyText())\nEndpoint = office.example.net:443\nAllowedIPs = 192.0.2.0/24"
        )).config
        let profile = TunnelProfile(name: "Two peers", config: config)
        let edited = try #require(ProfileDraft(editing: profile).makeProfile())
        #expect(edited.config == config)
    }
}

/// tvOS's keyboard screen shows only the placeholder, so each one names
/// the setting as the config writes it, and its section.
struct FieldPromptTests {

    @Test(arguments: [
        (ProfileDraft.Field.privateKey, "PrivateKey", "[Interface]"),
        (.address, "Address", "[Interface]"),
        (.dns, "DNS", "[Interface]"),
        (.mtu, "MTU", "[Interface]"),
        (.publicKey, "PublicKey", "[Peer]"),
        (.presharedKey, "PresharedKey", "[Peer]"),
        (.endpoint, "Endpoint", "[Peer]"),
        (.allowedIPs, "AllowedIPs", "[Peer]"),
        (.keepalive, "PersistentKeepalive", "[Peer]"),
    ])
    func namesTheSettingAndSection(field: ProfileDraft.Field, setting: String, section: String) {
        #expect(ProfileDraft.prompt(for: field).hasPrefix("\(setting) from \(section)"))
    }

    @Test func everyFieldHasItsOwnPrompt() {
        let prompts = ProfileDraft.Field.allCases.map { ProfileDraft.prompt(for: $0) }
        #expect(Set(prompts).count == prompts.count)
        #expect(ProfileDraft.prompt(for: .name).contains("Profile name"))
    }

    @Test func savedKeysSayTheyCanBeLeftBlank() {
        #expect(ProfileDraft.prompt(for: .privateKey, keySaved: true)
            == "PrivateKey from [Interface]. Leave blank to keep the saved one.")
        #expect(ProfileDraft.prompt(for: .presharedKey, keySaved: true).hasSuffix("Leave blank to keep the saved one."))
        #expect(!ProfileDraft.prompt(for: .privateKey).contains("Leave blank"))
    }
}
