import Foundation
import Testing
@testable import UntetheredVPN

struct WireGuardKeyTests {

    @Test func acceptsA32ByteBase64Key() {
        let text = Fixtures.randomKeyText()
        #expect(WireGuardKey(base64: text)?.base64 == text)
    }

    @Test(arguments: [
        "",
        "abc",
        String(repeating: "A", count: 44),                                  // no padding
        Data(count: 31).base64EncodedString(),                              // 31 bytes
        Data(count: 33).base64EncodedString(),                              // 33 bytes
        String(Data(count: 32).base64EncodedString().dropLast()) + "!",     // bad character
        " " + String(Data(count: 32).base64EncodedString().dropFirst()),    // leading space
    ])
    func rejectsMalformedKeys(text: String) {
        #expect(WireGuardKey(base64: text) == nil)
    }

    @Test func descriptionNeverShowsTheKey() {
        let key = Fixtures.randomKey()
        #expect("\(key)" == WireGuardKey.masked)
        #expect(String(reflecting: key) == "WireGuardKey(\(WireGuardKey.masked))")
        #expect(!"\(key)".contains(key.base64))
        #expect(!String(describing: [key]).contains(key.base64))
    }
}

struct CIDRRangeTests {

    @Test(arguments: [
        ("10.8.0.2/32", "10.8.0.2", 32, false),
        ("10.8.0.2", "10.8.0.2", 32, false),
        ("0.0.0.0/0", "0.0.0.0", 0, false),
        ("2001:db8::2/128", "2001:db8::2", 128, true),
        ("2001:db8::2", "2001:db8::2", 128, true),
        ("::/0", "::", 0, true),
        ("192.0.2.0/24", "192.0.2.0", 24, false),
    ])
    func accepts(text: String, address: String, prefix: Int, isIPv6: Bool) throws {
        let range = try #require(CIDRRange(text))
        #expect(range.address == address)
        #expect(range.prefixLength == prefix)
        #expect(range.isIPv6 == isIPv6)
    }

    @Test(arguments: [
        "", "/", "10.8.0.2/", "10.8.0.2/33", "2001:db8::/129", "10.8.0/24", "10.1/8",
        "0x7f.0.0.1/32", "010.0.0.1/32", "256.0.0.1/32", "10.8.0.2/-1", "10.8.0.2/+8",
        "10.8.0.2/24/1", "fe80::1%en0/64", "host.example.com/32", " 10.8.0.2/32",
    ])
    func rejects(text: String) {
        #expect(CIDRRange(text) == nil)
    }

    @Test func parsesLists() throws {
        let ranges = try #require(CIDRRange.list("10.8.0.2/32,  2001:db8::2/128"))
        #expect(ranges.map(\.description) == ["10.8.0.2/32", "2001:db8::2/128"])
    }

    @Test(arguments: ["", " ", ",", "10.8.0.2/32,", "10.8.0.2/32,,10.8.0.3/32", "10.8.0.2/32, nope"])
    func rejectsBadLists(text: String) {
        #expect(CIDRRange.list(text) == nil)
    }
}

struct PeerEndpointTests {

    @Test(arguments: [
        ("vpn.example.com:51820", "vpn.example.com", 51820),
        ("192.0.2.1:51820", "192.0.2.1", 51820),
        ("[2001:db8::1]:51820", "2001:db8::1", 51820),
        ("my-home.example.com.:1", "my-home.example.com.", 1),
        ("localhost:65535", "localhost", 65535),
    ])
    func accepts(text: String, host: String, port: UInt16) throws {
        let endpoint = try #require(PeerEndpoint(text))
        #expect(endpoint.host == host)
        #expect(endpoint.port == port)
        #expect(endpoint.description == text)
    }

    @Test(arguments: [
        "", "vpn.example.com", "vpn.example.com:", ":51820", "vpn.example.com:0",
        "vpn.example.com:65536", "vpn.example.com:51820x", "2001:db8::1:51820",
        "[2001:db8::1]51820", "[192.0.2.1]:51820", "[fe80::1%en0]:51820",
        "-bad.example.com:51820", "bad_name.example.com:51820", "1.2.3:51820",
        "vpn example.com:51820", "vpn.example.com:+5182",
    ])
    func rejects(text: String) {
        #expect(PeerEndpoint(text) == nil)
    }
}
