import Foundation
import NetworkExtension
import Testing
@testable import UntetheredVPN

struct TunnelProtocolInfoTests {

    private func profile() throws -> TunnelProfile {
        let parsed = try WireGuardConfig.parse(Fixtures.Config().text())
        return TunnelProfile(name: "Home", config: parsed.config)
    }

    @Test func roundTripsThroughTheProtocol() throws {
        let profile = try profile()
        let reference = Data((0..<20).map { _ in UInt8.random(in: .min ... .max) })
        let info = TunnelProtocolInfo(profile: profile, keychainReference: reference)
        let proto = info.makeProtocol(providerBundleID: "example.vpn.tunnel")

        #expect(proto.providerBundleIdentifier == "example.vpn.tunnel")
        #expect(proto.serverAddress == "vpn.example.com:51820")
        #expect(proto.passwordReference == reference)
        #expect(TunnelProtocolInfo(proto) == info)
    }

    @Test func protocolCarriesNoSecrets() throws {
        let fixture = Fixtures.Config()
        let config = try WireGuardConfig.parse(fixture.text()).config
        let info = TunnelProtocolInfo(profile: TunnelProfile(name: "Home", config: config), keychainReference: Data([1]))
        let proto = info.makeProtocol(providerBundleID: "example.vpn.tunnel")

        let dump = "\(proto.providerConfiguration ?? [:]) \(proto.serverAddress ?? "")"
        #expect(!dump.contains(fixture.privateKey))
        #expect(!dump.contains(fixture.presharedKey))
        #expect(proto.username == nil)
    }

    @Test func rejectsForeignOrNewerConfigurations() {
        let foreign = NETunnelProviderProtocol()
        foreign.passwordReference = Data([1])
        #expect(TunnelProtocolInfo(foreign) == nil)

        let newer = TunnelProtocolInfo(profileID: UUID(), keychainReference: Data([1]), serverAddress: "")
            .makeProtocol(providerBundleID: "example.vpn.tunnel")
        newer.providerConfiguration?["formatVersion"] = TunnelProtocolInfo.formatVersion + 1
        #expect(TunnelProtocolInfo(newer) == nil)

        let noReference = TunnelProtocolInfo(profileID: UUID(), keychainReference: Data([1]), serverAddress: "")
            .makeProtocol(providerBundleID: "example.vpn.tunnel")
        noReference.passwordReference = nil
        #expect(TunnelProtocolInfo(noReference) == nil)
    }
}

struct TunnelStatusTests {

    @Test func mapsSystemStatus() {
        #expect(TunnelStatus(.invalid) == .disconnected)
        #expect(TunnelStatus(.disconnected) == .disconnected)
        #expect(TunnelStatus(.connecting) == .connecting)
        #expect(TunnelStatus(.reasserting) == .connecting)
        #expect(TunnelStatus(.connected) == .connected)
        #expect(TunnelStatus(.disconnecting) == .disconnecting)
    }

    @Test func buttonTitleFollowsStatus() {
        #expect(TunnelStatus.disconnected.actionTitle == "Connect")
        #expect(TunnelStatus.failed("x").actionTitle == "Connect")
        #expect(TunnelStatus.connecting.actionTitle == "Disconnect")
        #expect(TunnelStatus.connected.actionTitle == "Disconnect")
        #expect(TunnelStatus.disconnecting.actionTitle == "Disconnecting…")
    }

    @Test func activeOnlyWhileUpOrComingUp() {
        #expect(TunnelStatus.connecting.isActive)
        #expect(TunnelStatus.connected.isActive)
        #expect(!TunnelStatus.disconnected.isActive)
        #expect(!TunnelStatus.disconnecting.isActive)
        #expect(!TunnelStatus.failed("x").isActive)
    }
}

struct TunnelFailureRecordTests {

    private func defaults() -> UserDefaults {
        let name = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func takenOnceForTheRightProfile() {
        let defaults = defaults()
        let profileID = UUID()
        TunnelFailureRecord.save(TunnelFailureRecord(failure: .endpointUnresolved, profileID: profileID), to: defaults)

        #expect(TunnelFailureRecord.take(for: UUID(), from: defaults) == nil)
        #expect(TunnelFailureRecord.take(for: profileID, from: defaults) == .endpointUnresolved)
        #expect(TunnelFailureRecord.take(for: profileID, from: defaults) == nil)
    }

    @Test func everyFailureHasAMessage() {
        for failure in TunnelFailure.allCases {
            #expect(!failure.message.isEmpty)
        }
    }
}

private let keychainAvailable: Bool = {
    let probe = [kSecClass: kSecClassGenericPassword, kSecAttrService: "probe"] as CFDictionary
    return SecItemCopyMatching(probe, nil) != errSecMissingEntitlement
}()

/// Uses the app's default Keychain group. A test host built without signing
/// (`CODE_SIGNING_ALLOWED=NO`) has no Keychain entitlement at all, so these
/// tests are skipped there; a signed build runs them, and the Apple TV check
/// proves the shared group.
@Suite(.serialized, .enabled(if: keychainAvailable, "the test host has no Keychain entitlement"))
struct ConfigKeychainTests {

    let keychain = ConfigKeychain(accessGroup: nil, service: "test.\(UUID().uuidString)")

    @Test func savesReadsReplacesAndDeletes() throws {
        let id = UUID()
        defer { try? keychain.delete(for: id) }

        let first = Fixtures.Config().text()
        let reference = try keychain.save(first, for: id)
        #expect(try keychain.text(for: id) == first)
        #expect(try ConfigKeychain.text(persistentReference: reference) == first)

        let second = Fixtures.Config().text()
        let sameReference = try keychain.save(second, for: id)
        #expect(try ConfigKeychain.text(persistentReference: sameReference) == second)

        try keychain.delete(for: id)
        #expect(throws: ConfigKeychain.Failure(status: errSecItemNotFound)) {
            try keychain.text(for: id)
        }
        try keychain.delete(for: id)
    }

    @Test func profilesAreSeparate() throws {
        let a = UUID(), b = UUID()
        defer { try? keychain.delete(for: a); try? keychain.delete(for: b) }
        let textA = Fixtures.Config().text(), textB = Fixtures.Config().text()
        _ = try keychain.save(textA, for: a)
        _ = try keychain.save(textB, for: b)
        #expect(try keychain.text(for: a) == textA)
        #expect(try keychain.text(for: b) == textB)
    }
}
