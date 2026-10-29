import Foundation
import Testing
@testable import UntetheredVPN

struct LogRedactorTests {

    private let redactor = LogRedactor(hosts: ["vpn.example.com"])

    @Test func hidesBase64AndHexKeys() {
        let base64 = Fixtures.randomKeyText()
        let hex = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).map { String(format: "%02x", $0) }.joined()
        let line = redactor.redact("private_key=\(hex) and \(base64) here")
        #expect(!line.contains(base64))
        #expect(!line.contains(hex))
        #expect(line == "private_key=\(LogRedactor.hiddenKey) and \(LogRedactor.hiddenKey) here")
    }

    @Test func hidesTheServerHostInAnyCase() {
        #expect(redactor.redact("Failed to resolve endpoint VPN.Example.com: no such host")
            == "Failed to resolve endpoint \(LogRedactor.hiddenHost): no such host")
    }

    @Test(arguments: [
        // WireGuardKit's DNS64 line names the host and the address it resolved to
        ("DNS64: mapped vpn.example.com to 203.0.113.5", "DNS64: mapped hidden.example to (public IP)"),
        ("Endpoint 198.51.100.7:51820 failed.", "Endpoint (public IP):51820 failed."),
        ("mapped to 2001:db8::10 now", "mapped to (public IP) now"),
        ("[2001:db8:1:2::5]:51820", "[(public IP)]:51820"),
        ("v4-mapped ::ffff:198.51.100.7", "v4-mapped ::ffff:(public IP)"),
        ("from 8.8.8.8, 1.1.1.1", "from (public IP), (public IP)"),
    ])
    func hidesPublicAddresses(line: String, expected: String) {
        #expect(redactor.redact(line) == expected)
    }

    @Test(arguments: [
        "Tunnel address 10.8.0.2 via 192.168.1.1",
        "LAN 172.16.4.20 and 172.31.255.255",
        "CGNAT 100.64.0.1, loopback 127.0.0.1, link-local 169.254.1.1",
        "IPv6 fd00::2, fe80::1, ::1 and ::",
        "AllowedIPs 0.0.0.0/0, ::/0",
        "at 18:42:13 after 15 seconds",
        "peer(AbCd…WxYz) - Retrying handshake because we stopped hearing back after 15 seconds",
        "Network change detected with satisfied route and interface order [en0]",
    ])
    func keepsWhatsSafe(line: String) {
        #expect(redactor.redact(line) == line)
    }

    @Test func publicIPv4Ranges() {
        #expect(LogRedactor.isPublicIPv4("203.0.113.5"))
        #expect(LogRedactor.isPublicIPv4("172.32.0.1"))
        #expect(!LogRedactor.isPublicIPv4("172.20.0.1"))
        #expect(!LogRedactor.isPublicIPv4("100.100.0.1"))
        #expect(!LogRedactor.isPublicIPv4("239.255.255.250"))
    }

    @Test(arguments: [
        ("peer(AbCd…WxYz) - Sending keepalive packet", true),
        ("peer(AbCd…WxYz) - Received handshake response", true),
        ("Routine: TUN reader - started", true),
        ("UAPI: Updating private key", true),
        ("peer(AbCd…WxYz) - Retrying handshake because we stopped hearing back after 15 seconds", false),
        ("Connectivity offline, pausing backend.", false),
        ("Interface state was Down, requested Up, now Up", false),
    ])
    func routineChatterIsLeftOut(message: String, routine: Bool) {
        #expect(RoutineMessages.isRoutine(message) == routine)
    }
}

struct TunnelLogTests {

    private let directory = FileManager.default.temporaryDirectory.appending(path: "TunnelLogTests-\(UUID().uuidString)")
    private let defaults = UserDefaults(suiteName: "TunnelLogTests-\(UUID().uuidString)")!

    private func log(_ source: TunnelLog.Source) -> TunnelLog {
        TunnelLog(directory: directory, defaults: defaults, source: source)
    }

    /// Nothing unredacted reaches the file on disk.
    @Test func storesOnlyRedactedText() throws {
        let tunnel = log(.tunnel)
        tunnel.setHosts(["vpn.example.com"])
        let key = Fixtures.randomKeyText()
        tunnel.add("DNS64: mapped vpn.example.com to 203.0.113.5 with \(key)")

        let stored = try String(contentsOf: directory.appending(path: "tunnel.log"), encoding: .utf8)
        #expect(!stored.contains("vpn.example.com"))
        #expect(!stored.contains("203.0.113.5"))
        #expect(!stored.contains(key))
        #expect(tunnel.lines().map(\.text) == ["DNS64: mapped hidden.example to (public IP) with \(LogRedactor.hiddenKey)"])
    }

    @Test func mergesSourcesNewestFirst() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        log(.app).add("Connect", date: start)
        log(.tunnel).add("Start requested", date: start.addingTimeInterval(1))
        log(.tunnel).add("Tunnel up", date: start.addingTimeInterval(2))
        log(.app).add("Disconnect", date: start.addingTimeInterval(3))

        let lines = log(.app).lines()
        #expect(lines.map(\.text) == ["Disconnect", "Tunnel up", "Start requested", "Connect"])
        #expect(lines.map(\.source) == [.app, .tunnel, .tunnel, .app])
    }

    @Test func keepsTheNewest500PerSource() {
        let tunnel = log(.tunnel)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        for index in 0..<(TunnelLog.limit + 20) {
            tunnel.add("Line \(index)", date: start.addingTimeInterval(Double(index)))
        }
        let lines = tunnel.lines()
        #expect(lines.count == TunnelLog.limit)
        #expect(lines.first?.text == "Line \(TunnelLog.limit + 19)")
        #expect(lines.last?.text == "Line 20")
    }

    @Test func linesAreOneRowEach() {
        let app = log(.app)
        app.add("first\nsecond\tthird")
        #expect(app.lines().map(\.text) == ["first second third"])
    }

    /// Clear hides every earlier line, including ones the other process
    /// writes back from an older copy of its file.
    @Test func clearHidesEarlierLines() {
        let start = Date.now.addingTimeInterval(-60)
        let app = log(.app)
        let tunnel = log(.tunnel)
        app.add("Connect", date: start)
        tunnel.add("Tunnel up", date: start.addingTimeInterval(1))

        app.clear(now: start.addingTimeInterval(10))
        #expect(app.lines().isEmpty)

        tunnel.add("Connectivity offline, pausing backend.", date: start.addingTimeInterval(20))
        #expect(app.lines().map(\.text) == ["Connectivity offline, pausing backend."])
    }
}

struct TunnelLogTextTests {

    private func lines(_ count: Int, text: String = "Tunnel up") -> [TunnelLog.Line] {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return (0..<count).map { TunnelLog.Line(date: start.addingTimeInterval(-Double($0)), source: .tunnel, text: "\(text) \($0)") }
    }

    @Test func qrCodeTakesWhatFitsUnderTheByteLimit() {
        #expect(TunnelLogText.qrLineCount(lines(3)) == 3)
        let many = lines(200)
        let count = TunnelLogText.qrLineCount(many)
        #expect((20..<200).contains(count))
        #expect(TunnelLogText.qrText(many).utf8.count <= TunnelLogText.qrMaxBytes)
        #expect(TunnelLogText.qrText(many).split(separator: "\n").count == count + 1)
    }

    @Test func qrTextHasTheNewestLinesFirst() {
        let text = TunnelLogText.qrText(lines(2))
        let rows = text.split(separator: "\n")
        #expect(rows.count == 3)
        #expect(rows[1].hasSuffix("Tunnel: Tunnel up 0"))
        #expect(rows[2].hasSuffix("Tunnel: Tunnel up 1"))
    }
}
