import Foundation
import Security

/// Stores each profile's whole `wg-quick` text, keys included, as one
/// generic-password item in the Keychain (D31). The item never syncs to iCloud
/// and is readable after the first unlock, so the extension can start a tunnel
/// on its own.
///
/// The app writes items with an access group shared with the extension; the
/// extension reads them through the persistent reference stored in the
/// tunnel's protocol configuration.
struct ConfigKeychain: Sendable {

    struct Failure: Error, Equatable, CustomStringConvertible {
        let status: OSStatus
        var description: String { "Keychain error \(status)" }
    }

    /// The Keychain access group, or nil for the app's default group.
    let accessGroup: String?
    /// Groups this store's items; one item per profile ID within it.
    let service: String

    init(accessGroup: String?, service: String) {
        self.accessGroup = accessGroup
        self.service = service
    }

    /// Saves (or replaces) the config text for a profile and returns the item's
    /// persistent reference.
    func save(_ text: String, for profileID: UUID) throws(Failure) -> Data {
        let data = Data(text.utf8)
        var query = itemQuery(for: profileID)
        let update = [kSecValueData: data] as CFDictionary
        var status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecItemNotFound {
            query[kSecValueData] = data
            query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            query[kSecAttrLabel] = "Untethered VPN profile"
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return try persistentReference(for: profileID)
    }

    /// The persistent reference of a profile's item.
    func persistentReference(for profileID: UUID) throws(Failure) -> Data {
        var query = itemQuery(for: profileID)
        query[kSecReturnPersistentRef] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let reference = result as? Data else {
            throw Failure(status: status == errSecSuccess ? errSecInternalError : status)
        }
        return reference
    }

    /// Reads a profile's config text.
    func text(for profileID: UUID) throws(Failure) -> String {
        var query = itemQuery(for: profileID)
        query[kSecReturnData] = true
        return try readText(query)
    }

    /// Reads config text through a persistent reference. This is how the
    /// extension finds its config.
    static func text(persistentReference: Data) throws(Failure) -> String {
        try readText([
            kSecValuePersistentRef: persistentReference,
            kSecReturnData: true,
        ])
    }

    /// Deletes a profile's item. Deleting one that doesn't exist is not an error.
    func delete(for profileID: UUID) throws(Failure) {
        let status = SecItemDelete(itemQuery(for: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure(status: status)
        }
    }

    private func itemQuery(for profileID: UUID) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: profileID.uuidString,
            kSecAttrSynchronizable: false,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        return query
    }

    private static func readText(_ query: [CFString: Any]) throws(Failure) -> String {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
            throw Failure(status: errSecDecode)
        }
        return text
    }

    private func readText(_ query: [CFString: Any]) throws(Failure) -> String {
        try Self.readText(query)
    }
}
