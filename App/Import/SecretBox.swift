import CTweetNaCl
import Foundation
import Security

/// NaCl's `secretbox` (XSalsa20 encryption with a Poly1305 tag), the same
/// construction as tweetnacl-js's `nacl.secretbox`, which the import page
/// uses on the phone. Backed by the vendored TweetNaCl C code
/// (`Vendor/TweetNaCl`).
///
/// A sealed message is the 24-byte nonce followed by the box (the 16-byte
/// tag and then the ciphertext), exactly as the page sends it.
enum SecretBox {
    static let keyLength = 32
    static let nonceLength = 24
    static let tagLength = 16

    /// Bytes NaCl's C API wants as zeros in front of a message (32) and in
    /// front of a box (16). tweetnacl-js adds and strips them for you.
    private static let zeroBytes = 32
    private static let boxZeroBytes = 16

    /// A 32-byte secretbox key. The import screen makes a fresh one for every
    /// session and hands it to the phone in the URL fragment as base64url.
    ///
    /// Its description is always masked, like `WireGuardKey`.
    struct Key: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
        let bytes: Data

        init?(bytes: Data) {
            guard bytes.count == SecretBox.keyLength else { return nil }
            self.bytes = bytes
        }

        /// Reads base64url without padding (43 characters for 32 bytes).
        init?(base64URL text: String) {
            guard let data = Data(base64URL: text) else { return nil }
            self.init(bytes: data)
        }

        static func random() -> Key {
            Key(bytes: SecretBox.randomBytes(SecretBox.keyLength))!
        }

        var base64URL: String { bytes.base64URLEncodedString() }

        var description: String { WireGuardKey.masked }
        var debugDescription: String { "SecretBox.Key(\(WireGuardKey.masked))" }
    }

    /// Encrypts `message` with a fresh random nonce. The app itself only
    /// opens messages; sealing is here for the tests and for symmetry.
    static func seal(_ message: Data, key: Key) -> Data {
        seal(message, key: key, nonce: randomBytes(nonceLength))
    }

    static func seal(_ message: Data, key: Key, nonce: Data) -> Data {
        precondition(nonce.count == nonceLength, "a secretbox nonce is 24 bytes")
        let padded = [UInt8](repeating: 0, count: zeroBytes) + message
        var box = [UInt8](repeating: 0, count: padded.count)
        let result = crypto_secretbox_xsalsa20poly1305_tweet(
            &box, padded, UInt64(padded.count), [UInt8](nonce), [UInt8](key.bytes))
        precondition(result == 0, "crypto_secretbox only fails on a short buffer")
        return nonce + box[boxZeroBytes...]
    }

    /// Decrypts a message made by `seal` or by `nacl.secretbox`, with the
    /// nonce in front. Returns nil if the key is wrong, any byte was changed,
    /// or it is too short to hold a nonce and a tag; it can't tell these apart,
    /// by design.
    static func open(_ sealed: Data, key: Key) -> Data? {
        guard sealed.count >= nonceLength + tagLength else { return nil }
        let bytes = [UInt8](sealed)
        let nonce = Array(bytes[..<nonceLength])
        let padded = [UInt8](repeating: 0, count: boxZeroBytes) + bytes[nonceLength...]
        var message = [UInt8](repeating: 0, count: padded.count)
        let result = crypto_secretbox_xsalsa20poly1305_tweet_open(
            &message, padded, UInt64(padded.count), nonce, [UInt8](key.bytes))
        guard result == 0 else { return nil }
        return Data(message[zeroBytes...])
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        // Carrying on without randomness would mean a guessable key.
        precondition(status == errSecSuccess, "the system random generator failed")
        return Data(bytes)
    }
}

extension Data {
    /// Base64url (RFC 4648 § 5) without padding, as used in URL fragments.
    init?(base64URL text: String) {
        guard text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              text.count % 4 != 1 else {
            return nil
        }
        var base64 = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
