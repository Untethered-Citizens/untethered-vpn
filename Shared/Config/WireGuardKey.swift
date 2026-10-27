import Foundation

/// A WireGuard key (private, public or preshared): 32 bytes, written as
/// 44 characters of base64.
///
/// Its description is always masked, so a key can't leak through string
/// interpolation, `print` or a log line by accident. Use `base64` only where
/// the real value is needed (the Keychain and the tunnel).
struct WireGuardKey: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    static let masked = "(hidden)"

    let base64: String

    /// Validates the text: exactly 44 base64 characters that decode to 32 bytes.
    init?(base64 text: String) {
        guard text.count == 44, text.hasSuffix("="),
              let data = Data(base64Encoded: text), data.count == 32 else {
            return nil
        }
        base64 = text
    }

    var description: String { Self.masked }
    var debugDescription: String { "WireGuardKey(\(Self.masked))" }
}
