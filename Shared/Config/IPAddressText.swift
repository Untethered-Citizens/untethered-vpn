import Network

/// Strict checks for IP addresses written as text.
enum IPAddressText {

    /// Dotted-quad IPv4 only: four decimal parts 0–255 with no leading zeros.
    /// (The system parser also accepts shorthand such as `10.1` and hex, which
    /// a config should never contain.)
    static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard (1...3).contains(part.count), part.allSatisfy(\.isASCIIDigit),
                  part == "0" || !part.hasPrefix("0"),
                  let value = Int(part) else { return false }
            return value <= 255
        }
    }

    /// IPv6 without a zone suffix such as `%en0`.
    static func isIPv6(_ text: String) -> Bool {
        !text.contains("%") && text.contains(":") && IPv6Address(text) != nil
    }

    static func isIP(_ text: String) -> Bool {
        isIPv4(text) || isIPv6(text)
    }

    /// A DNS host name: dot-separated labels of letters, digits and hyphens,
    /// at most 253 characters. All-numeric names are refused, because they are
    /// almost always a mistyped IPv4 address.
    static func isHostName(_ text: String) -> Bool {
        let name = text.hasSuffix(".") ? String(text.dropLast()) : text
        guard !name.isEmpty, name.count <= 253 else { return false }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        let labelsValid = labels.allSatisfy { label in
            (1...63).contains(label.count)
                && label.allSatisfy { $0.isASCIILetter || $0.isASCIIDigit || $0 == "-" }
                && !label.hasPrefix("-") && !label.hasSuffix("-")
        }
        return labelsValid && !labels.allSatisfy { $0.allSatisfy(\.isASCIIDigit) }
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}
