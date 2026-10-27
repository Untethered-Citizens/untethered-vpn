/// A peer's endpoint: a host name or IP address and a UDP port.
/// IPv6 addresses are written in brackets: `[2001:db8::1]:51820`.
struct PeerEndpoint: Hashable, Sendable, CustomStringConvertible {
    let host: String
    let port: UInt16

    init?(_ text: String) {
        let host: Substring
        let portText: Substring
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]"),
                  text[text.index(after: close)...].hasPrefix(":") else { return nil }
            host = text[text.index(after: text.startIndex)..<close]
            portText = text[text.index(close, offsetBy: 2)...]
            guard IPAddressText.isIPv6(String(host)) else { return nil }
        } else {
            guard let colon = text.lastIndex(of: ":") else { return nil }
            host = text[..<colon]
            portText = text[text.index(after: colon)...]
            guard !host.contains(":"),
                  IPAddressText.isIPv4(String(host)) || IPAddressText.isHostName(String(host)) else { return nil }
        }
        guard (1...5).contains(portText.count), portText.allSatisfy(\.isASCIIDigit),
              let port = UInt16(portText), port > 0 else { return nil }
        self.host = String(host)
        self.port = port
    }

    var description: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}
