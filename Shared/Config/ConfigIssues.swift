/// Where in a config a problem is. Peers are numbered from 1 in file order.
enum ConfigSection: Hashable, Sendable, CustomStringConvertible {
    case interface
    case peer(Int)

    var description: String {
        switch self {
        case .interface: "[Interface]"
        case .peer(let number): "[Peer] \(number)"
        }
    }
}

/// Why a config can't be used. Errors name the section, setting and line,
/// never a value, so they're safe to show on screen and to log.
enum ConfigError: Error, Hashable, Sendable {
    case empty
    /// The text arrived with its line breaks removed.
    case lineBreaksLost
    case textOutsideSection(line: Int)
    case unknownSection(line: Int)
    case invalidLine(line: Int)
    case multipleInterfaces(line: Int)
    case noInterface
    case noPeers
    case missingKey(ConfigSection, key: String)
    case invalidValue(ConfigSection, key: String, line: Int)
    case duplicateKey(ConfigSection, key: String, line: Int)

    var message: String {
        switch self {
        case .empty:
            "The config is empty."
        case .lineBreaksLost:
            "The line breaks were lost, so the config arrived as one long line. Copy it again and paste it so each setting is on its own line."
        case .textOutsideSection(let line):
            "Line \(line) comes before any [Interface] or [Peer] heading."
        case .unknownSection(let line):
            "Line \(line) has a heading other than [Interface] or [Peer]."
        case .invalidLine(let line):
            "Line \(line) isn't a heading or a \"Setting = value\" line."
        case .multipleInterfaces(let line):
            "Line \(line) starts a second [Interface] section; a config has only one."
        case .noInterface:
            "The config has no [Interface] section."
        case .noPeers:
            "The config has no [Peer] section."
        case .missingKey(let section, let key):
            "\(section) is missing \(key)."
        case .invalidValue(let section, let key, let line):
            "\(key) in \(section) (line \(line)) isn't valid. \(Self.expectedFormat(key))"
        case .duplicateKey(let section, let key, let line):
            "\(key) appears more than once in \(section) (line \(line))."
        }
    }

    private static func expectedFormat(_ key: String) -> String {
        switch key {
        case "PrivateKey", "PublicKey", "PresharedKey":
            "It should be a 44-character key ending in \"=\"."
        case "Address", "AllowedIPs":
            "It should be IP addresses with a prefix, such as 10.0.0.2/32, separated by commas."
        case "DNS":
            "It should be IP addresses or domain names, separated by commas."
        case "Endpoint":
            "It should be a host and port, such as vpn.example.com:51820."
        case "MTU":
            "It should be a number from \(WireGuardConfig.mtuRange.lowerBound) to \(WireGuardConfig.mtuRange.upperBound)."
        case "ListenPort":
            "It should be a port number from 0 to 65535."
        case "PersistentKeepalive":
            "It should be a number of seconds from 0 to 65535, or off."
        default:
            ""
        }
    }
}

/// Something in a config that was accepted but deserves a look on the review
/// screen.
struct ConfigWarning: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// A `wg-quick` directive the app can't honour, such as `PostUp`.
        case ignoredDirective(String)
        /// A setting the app doesn't know. The name is nil when the text before
        /// "=" doesn't look like a setting name, so it is never echoed.
        case unknownKey(String?, line: Int)
        /// AllowedIPs was missing, so all traffic goes through the tunnel.
        case defaultAllowedIPs
    }

    let section: ConfigSection
    let kind: Kind

    var message: String {
        switch kind {
        case .ignoredDirective(let key):
            "\(key) in \(section) was ignored. Apple TV can't run commands or change routing tables."
        case .unknownKey(let key?, let line):
            "\(key) in \(section) (line \(line)) isn't a setting this app uses, so it was ignored."
        case .unknownKey(nil, let line):
            "Line \(line) in \(section) isn't a setting this app uses, so it was ignored."
        case .defaultAllowedIPs:
            "\(section) has no AllowedIPs, so all traffic will go through the tunnel (0.0.0.0/0, ::/0)."
        }
    }
}
