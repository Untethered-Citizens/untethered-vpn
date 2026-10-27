import Foundation

/// A parsed config together with anything the user should know about it.
struct ParsedConfig: Hashable, Sendable {
    let config: WireGuardConfig
    let warnings: [ConfigWarning]
}

extension WireGuardConfig {

    /// Parses and validates the text of a `wg-quick` `.conf` file.
    static func parse(_ text: String) throws(ConfigError) -> ParsedConfig {
        var parser = WgQuickParser(text: text)
        return try parser.parse()
    }
}

/// Reads `wg-quick` text in two passes: first into sections of raw
/// `key = value` lines, then each section into validated values.
private struct WgQuickParser {

    private struct Line {
        let key: String      // as written
        let value: String
        let number: Int
    }

    private struct RawSection {
        let section: ConfigSection
        var lines: [Line] = []
    }

    static let interfaceKeys = ["PrivateKey", "Address", "DNS", "MTU", "ListenPort"]
    static let peerKeys = ["PublicKey", "PresharedKey", "Endpoint", "AllowedIPs", "PersistentKeepalive"]
    static let ignoredDirectives = ["PreUp", "PostUp", "PreDown", "PostDown", "Table", "SaveConfig", "FwMark"]

    let text: String
    private var warnings: [ConfigWarning] = []

    init(text: String) {
        self.text = text
    }

    mutating func parse() throws(ConfigError) -> ParsedConfig {
        let sections = try readSections()
        guard let interfaceSection = sections.first(where: { $0.section == .interface }) else {
            throw .noInterface
        }
        let interface = try readInterface(interfaceSection)
        var peers: [WireGuardConfig.Peer] = []
        for section in sections where section.section != .interface {
            peers.append(try readPeer(section))
        }
        guard !peers.isEmpty else { throw .noPeers }
        return ParsedConfig(config: WireGuardConfig(interface: interface, peers: peers), warnings: warnings)
    }

    // MARK: Pass 1: sections and lines

    private func readSections() throws(ConfigError) -> [RawSection] {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .empty }

        var sections: [RawSection] = []
        var peerCount = 0
        let rawLines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        for (index, rawLine) in rawLines.enumerated() {
            let number = index + 1
            let content = rawLine.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }
            if Self.looksLikeSeveralLines(content) { throw .lineBreaksLost }

            if content.hasPrefix("[") {
                guard content.hasSuffix("]") else { throw .unknownSection(line: number) }
                let name = content.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).lowercased()
                switch name {
                case "interface":
                    guard !sections.contains(where: { $0.section == .interface }) else {
                        throw .multipleInterfaces(line: number)
                    }
                    sections.append(RawSection(section: .interface))
                case "peer":
                    peerCount += 1
                    sections.append(RawSection(section: .peer(peerCount)))
                default:
                    throw .unknownSection(line: number)
                }
                continue
            }

            guard let equals = content.firstIndex(of: "=") else { throw .invalidLine(line: number) }
            guard !sections.isEmpty else { throw .textOutsideSection(line: number) }
            let key = content[..<equals].trimmingCharacters(in: .whitespaces)
            let value = content[content.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            sections[sections.count - 1].lines.append(Line(key: key, value: value, number: number))
        }
        return sections
    }

    /// True when one line holds what should be several: two or more headings
    /// or `Setting =` starts, which happens when line breaks are stripped.
    /// A setting only counts after whitespace or a heading, so the "=" at the
    /// end of a base64 key never matches.
    static func looksLikeSeveralLines(_ line: String) -> Bool {
        let knownKeys = Set((interfaceKeys + peerKeys).map { $0.lowercased() })
        let words = line.replacingOccurrences(of: "]", with: "] ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
        var starts = 0
        for (index, word) in words.enumerated() {
            if word == "[interface]" || word == "[peer]" {
                starts += 1
            } else if let equals = word.firstIndex(of: "=") {
                if knownKeys.contains(String(word[..<equals])) { starts += 1 }
            } else if knownKeys.contains(word), index + 1 < words.count, words[index + 1].hasPrefix("=") {
                starts += 1
            }
        }
        return starts >= 2
    }

    // MARK: Pass 2: values

    /// Sorts a section's lines by setting, warning about the ones that aren't
    /// used and refusing a repeated single-value setting.
    private mutating func group(
        _ raw: RawSection, known: [String], lists: Set<String>
    ) throws(ConfigError) -> [String: [Line]] {
        var grouped: [String: [Line]] = [:]
        for line in raw.lines {
            if let key = known.first(where: { $0.caseInsensitiveCompare(line.key) == .orderedSame }) {
                if grouped[key] != nil, !lists.contains(key) {
                    throw .duplicateKey(raw.section, key: key, line: line.number)
                }
                grouped[key, default: []].append(line)
            } else if let directive = Self.ignoredDirectives.first(where: { $0.caseInsensitiveCompare(line.key) == .orderedSame }) {
                let warning = ConfigWarning(section: raw.section, kind: .ignoredDirective(directive))
                if !warnings.contains(warning) { warnings.append(warning) }
            } else {
                let shown = Self.isSettingName(line.key) ? line.key : nil
                warnings.append(ConfigWarning(section: raw.section, kind: .unknownKey(shown, line: line.number)))
            }
        }
        return grouped
    }

    /// Letters only, short: safe to repeat back. Anything else might be part
    /// of a key pasted in the wrong place.
    private static func isSettingName(_ text: String) -> Bool {
        (1...32).contains(text.count) && text.allSatisfy(\.isASCIILetter)
    }

    private mutating func readInterface(_ raw: RawSection) throws(ConfigError) -> WireGuardConfig.Interface {
        let section = raw.section
        let lines = try group(raw, known: Self.interfaceKeys, lists: ["Address", "DNS"])

        guard let keyLine = lines["PrivateKey"]?.first else { throw .missingKey(section, key: "PrivateKey") }
        guard let privateKey = WireGuardKey(base64: keyLine.value) else {
            throw .invalidValue(section, key: "PrivateKey", line: keyLine.number)
        }

        var addresses: [CIDRRange] = []
        for line in lines["Address"] ?? [] {
            guard let ranges = CIDRRange.list(line.value) else {
                throw .invalidValue(section, key: "Address", line: line.number)
            }
            addresses += ranges
        }
        guard !addresses.isEmpty else { throw .missingKey(section, key: "Address") }

        var interface = WireGuardConfig.Interface(privateKey: privateKey, addresses: addresses)
        for line in lines["DNS"] ?? [] {
            guard let dns = WireGuardConfig.dnsEntries(line.value) else {
                throw .invalidValue(section, key: "DNS", line: line.number)
            }
            interface.dnsServers += dns.servers
            interface.dnsSearchDomains += dns.searchDomains
        }
        if let line = lines["MTU"]?.first {
            guard let mtu = WireGuardConfig.number(line.value, in: WireGuardConfig.mtuRange) else {
                throw .invalidValue(section, key: "MTU", line: line.number)
            }
            interface.mtu = mtu
        }
        if let line = lines["ListenPort"]?.first {
            guard let port = WireGuardConfig.number(line.value, in: 0...65535) else {
                throw .invalidValue(section, key: "ListenPort", line: line.number)
            }
            interface.listenPort = port
        }
        return interface
    }

    private mutating func readPeer(_ raw: RawSection) throws(ConfigError) -> WireGuardConfig.Peer {
        let section = raw.section
        let lines = try group(raw, known: Self.peerKeys, lists: ["AllowedIPs"])

        func key(_ name: String) throws(ConfigError) -> WireGuardKey? {
            guard let line = lines[name]?.first else { return nil }
            guard let key = WireGuardKey(base64: line.value) else {
                throw .invalidValue(section, key: name, line: line.number)
            }
            return key
        }

        guard let publicKey = try key("PublicKey") else { throw .missingKey(section, key: "PublicKey") }
        let presharedKey = try key("PresharedKey")

        guard let endpointLine = lines["Endpoint"]?.first else { throw .missingKey(section, key: "Endpoint") }
        guard let endpoint = PeerEndpoint(endpointLine.value) else {
            throw .invalidValue(section, key: "Endpoint", line: endpointLine.number)
        }

        var peer = WireGuardConfig.Peer(publicKey: publicKey, presharedKey: presharedKey, endpoint: endpoint)
        if let allowedLines = lines["AllowedIPs"] {
            var allowed: [CIDRRange] = []
            for line in allowedLines {
                guard let ranges = CIDRRange.list(line.value) else {
                    throw .invalidValue(section, key: "AllowedIPs", line: line.number)
                }
                allowed += ranges
            }
            peer.allowedIPs = allowed
        } else {
            warnings.append(ConfigWarning(section: section, kind: .defaultAllowedIPs))
        }

        if let line = lines["PersistentKeepalive"]?.first {
            if line.value.lowercased() == "off" {
                peer.persistentKeepalive = nil
            } else if let seconds = WireGuardConfig.number(line.value, in: 0...65535) {
                peer.persistentKeepalive = seconds == 0 ? nil : seconds
            } else {
                throw .invalidValue(section, key: "PersistentKeepalive", line: line.number)
            }
        }
        return peer
    }
}
