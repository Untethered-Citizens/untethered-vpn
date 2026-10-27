import Foundation
import NetworkExtension

/// A saved tunnel: a name the user chose and a checked config.
struct TunnelProfile: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var config: WireGuardConfig

    init(id: UUID = UUID(), name: String, config: WireGuardConfig) {
        self.id = id
        self.name = name
        self.config = config
    }
}

/// What the tunnel's protocol configuration carries for a profile (D31):
/// a persistent reference to the Keychain item, the profile ID, a format
/// version, and the first peer's endpoint for display. Nothing secret.
struct TunnelProtocolInfo: Equatable, Sendable {
    static let formatVersion = 1

    private enum Key {
        static let profileID = "profileID"
        static let formatVersion = "formatVersion"
    }

    let profileID: UUID
    let keychainReference: Data
    let serverAddress: String

    init(profileID: UUID, keychainReference: Data, serverAddress: String) {
        self.profileID = profileID
        self.keychainReference = keychainReference
        self.serverAddress = serverAddress
    }

    init(profile: TunnelProfile, keychainReference: Data) {
        self.init(
            profileID: profile.id,
            keychainReference: keychainReference,
            serverAddress: profile.config.peers.first?.endpoint.description ?? ""
        )
    }

    /// Reads the info back. Nil for a configuration this app didn't write, or
    /// one written in a format it doesn't know.
    init?(_ proto: NETunnelProviderProtocol) {
        guard let info = proto.providerConfiguration,
              info[Key.formatVersion] as? Int == Self.formatVersion,
              let idText = info[Key.profileID] as? String,
              let profileID = UUID(uuidString: idText),
              let reference = proto.passwordReference else {
            return nil
        }
        self.init(profileID: profileID, keychainReference: reference, serverAddress: proto.serverAddress ?? "")
    }

    /// A protocol configuration for the given extension.
    func makeProtocol(providerBundleID: String) -> NETunnelProviderProtocol {
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleID
        proto.serverAddress = serverAddress
        proto.passwordReference = keychainReference
        proto.providerConfiguration = [
            Key.profileID: profileID.uuidString,
            Key.formatVersion: Self.formatVersion,
        ]
        return proto
    }
}
