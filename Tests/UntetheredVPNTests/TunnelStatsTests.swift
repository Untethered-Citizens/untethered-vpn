import Foundation
import Testing
@testable import UntetheredVPN

struct TunnelStatsTests {

    /// wireguard-go's runtime state uses hex keys.
    static func randomHexKey() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    /// Runtime state in wireguard-go's UAPI format, with two peers. Keys are
    /// random; addresses are documentation ranges.
    struct Runtime {
        let privateKey = TunnelStatsTests.randomHexKey()
        let publicKeys = [TunnelStatsTests.randomHexKey(), TunnelStatsTests.randomHexKey()]
        let presharedKey = TunnelStatsTests.randomHexKey()

        var text: String {
            """
            private_key=\(privateKey)
            listen_port=51820
            public_key=\(publicKeys[0])
            preshared_key=\(presharedKey)
            protocol_version=1
            endpoint=203.0.113.5:51820
            last_handshake_time_sec=1793000000
            last_handshake_time_nsec=500000000
            tx_bytes=36000000
            rx_bytes=1400000000
            persistent_keepalive_interval=25
            allowed_ip=0.0.0.0/0
            public_key=\(publicKeys[1])
            protocol_version=1
            endpoint=[2001:db8::7]:51820
            last_handshake_time_sec=0
            last_handshake_time_nsec=0
            tx_bytes=100
            rx_bytes=0
            allowed_ip=10.9.0.0/24
            errno=0

            """
        }
    }

    @Test func readsEachPeer() throws {
        let stats = TunnelStats(runtimeConfiguration: Runtime().text)
        try #require(stats.peers.count == 2)
        #expect(stats.peers[0].endpoint == "203.0.113.5:51820")
        #expect(stats.peers[0].lastHandshake == Date(timeIntervalSince1970: 1_793_000_000.5))
        #expect(stats.peers[0].receivedBytes == 1_400_000_000)
        #expect(stats.peers[0].sentBytes == 36_000_000)
        #expect(stats.peers[1].endpoint == "[2001:db8::7]:51820")
        #expect(stats.peers[1].lastHandshake == nil)
    }

    @Test func combinesPeers() {
        let stats = TunnelStats(runtimeConfiguration: Runtime().text)
        #expect(stats.lastHandshake == Date(timeIntervalSince1970: 1_793_000_000.5))
        #expect(stats.receivedBytes == 1_400_000_000)
        #expect(stats.sentBytes == 36_000_100)
        #expect(stats.endpoint == "203.0.113.5:51820")
    }

    @Test func noKeyReachesTheReply() throws {
        let runtime = Runtime()
        let reply = try JSONEncoder().encode(TunnelStats(runtimeConfiguration: runtime.text))
        let text = try #require(String(data: reply, encoding: .utf8))
        for key in [runtime.privateKey, runtime.presharedKey] + runtime.publicKeys {
            #expect(!text.contains(key))
        }
        #expect(!text.contains("key"))
    }

    @Test func roundTripsAsJSON() throws {
        let stats = TunnelStats(runtimeConfiguration: Runtime().text)
        let decoded = try JSONDecoder().decode(TunnelStats.self, from: JSONEncoder().encode(stats))
        #expect(decoded == stats)
    }

    @Test(arguments: ["", "errno=0\n", "private_key=abc\nrx_bytes=5\n", "garbage\n=\n"])
    func emptyOrPeerlessStateHasNoPeers(text: String) {
        #expect(TunnelStats(runtimeConfiguration: text).peers.isEmpty)
    }
}

struct LiveStatsTests {

    let now = Date(timeIntervalSince1970: 1_793_000_000)

    func stats(handshakeAgo: TimeInterval?, connectedAgo: TimeInterval = 600, reported: Bool = true) -> LiveStats {
        let peer = TunnelStats.Peer(lastHandshake: handshakeAgo.map { now.addingTimeInterval(-$0) })
        return LiveStats(
            connectedSince: now.addingTimeInterval(-connectedAgo),
            tunnel: reported ? TunnelStats(peers: [peer]) : nil,
            fetchedAt: now
        )
    }

    @Test func measuresAgesFromWhenFetched() {
        let live = stats(handshakeAgo: 12, connectedAgo: 4_320)
        #expect(live.handshakeAge == 12)
        #expect(live.connectedFor == 4_320)
    }

    @Test func recentHandshakeIsFine() {
        #expect(stats(handshakeAgo: 180).silence == nil)
    }

    @Test func oldHandshakeIsSilence() {
        #expect(stats(handshakeAgo: 250).silence == .sinceHandshake(250))
    }

    @Test func noHandshakeCountsFromConnecting() {
        #expect(stats(handshakeAgo: nil, connectedAgo: 60).silence == nil)
        #expect(stats(handshakeAgo: nil, connectedAgo: 300).silence == .sinceConnecting(300))
    }

    @Test func noReplyFromTheExtensionIsntSilence() {
        #expect(stats(handshakeAgo: nil, connectedAgo: 300, reported: false).silence == nil)
    }

    @Test func silenceMessagesGiveTheTime() {
        #expect(LiveStats.Silence.sinceHandshake(250).message
            == "No reply from the server for 4 minutes. Check that it's running and reachable.")
        #expect(LiveStats.Silence.sinceHandshake(250).shortMessage == "No reply from the server for 4 min")
        #expect(LiveStats.Silence.sinceConnecting(300).message.hasPrefix("No reply from the server since connecting 5 minutes ago."))
    }
}

struct StatsFormatTests {

    @Test(arguments: [
        (0.0, "0 seconds", "0 s"),
        (1, "1 second", "1 s"),
        (12.7, "12 seconds", "12 s"),
        (60, "1 minute", "1 min"),
        (250, "4 minutes", "4 min"),
        (3_600, "1 hour", "1 h"),
        (4_320, "1 hour 12 minutes", "1 h 12 min"),
        (7_259, "2 hours", "2 h"),
        (183_600, "2 days 3 hours", "2 d 3 h"),
        (-5, "0 seconds", "0 s"),
    ])
    func durations(seconds: TimeInterval, long: String, short: String) {
        #expect(StatsFormat.duration(seconds) == long)
        #expect(StatsFormat.duration(seconds, short: true) == short)
    }

    @Test(arguments: [
        (UInt64(0), "0 bytes"),
        (1, "1 byte"),
        (999, "999 bytes"),
        (1_000, "1.0 KB"),
        (4_240, "4.2 KB"),
        (36_000_000, "36 MB"),
        (999_960, "1.0 MB"),
        (1_400_000_000, "1.4 GB"),
        (12_600_000_000_000, "13 TB"),
    ])
    func bytes(count: UInt64, text: String) {
        #expect(StatsFormat.bytes(count, locale: Locale(identifier: "en_US")) == text)
    }

    @Test(arguments: [
        ("vpn.example.com:51820", nil, "vpn.example.com:51820"),
        ("vpn.example.com:51820", "203.0.113.5:51820", "vpn.example.com:51820 (203.0.113.5)"),
        ("vpn.example.com:51820", "203.0.113.5:4500", "vpn.example.com:51820 (203.0.113.5:4500)"),
        ("203.0.113.5:51820", "203.0.113.5:51820", "203.0.113.5:51820"),
        ("vpn.example.com:51820", "[2001:db8::7]:51820", "vpn.example.com:51820 (2001:db8::7)"),
        ("[2001:db8::7]:51820", "[2001:db8::7]:51820", "[2001:db8::7]:51820"),
    ] as [(String, String?, String)])
    func endpoints(configured: String, inUse: String?, text: String) {
        #expect(StatsFormat.endpoint(configured: configured, inUse: inUse) == text)
    }
}
