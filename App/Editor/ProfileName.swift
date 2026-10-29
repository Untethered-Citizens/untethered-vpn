import Foundation

/// The rules for a profile's name, shared by manual entry, Rename and the
/// QR import's review: not empty, not too long, and not already used by
/// another profile (ignoring case and surrounding spaces).
enum ProfileName {

    static let maxLength = 40

    /// The name as it's saved: without surrounding spaces.
    static func cleaned(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What's wrong with a name, in words for the screen, or nil if it's
    /// fine. `otherNames` are the names of every profile except the one
    /// being named.
    static func problem(_ name: String, otherNames: [String]) -> String? {
        let name = cleaned(name)
        if name.isEmpty { return "Enter a name, such as Home." }
        if name.count > maxLength { return "Use a name of \(maxLength) characters or fewer." }
        if otherNames.contains(where: { matches($0, name) }) {
            return "You already have a profile called “\(name)”. Choose another name."
        }
        return nil
    }

    /// Whether two names count as the same.
    static func matches(_ a: String, _ b: String) -> Bool {
        cleaned(a).compare(cleaned(b), options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }
}
