import Foundation
import Testing
@testable import UntetheredVPN

/// Seals a submission the way the import page does: JSON, secretbox with the
/// session key, base64.
func sealedSubmission(name: String, config: String, key: SecretBox.Key) -> Data {
    let json = try! JSONEncoder().encode(ImportSubmission(name: name, config: config))
    return Data(SecretBox.seal(json, key: key).base64EncodedString().utf8)
}

@Suite("Import session")
struct ImportSessionTests {

    static let page = Data("<!doctype html><title>test</title>".utf8)
    static let script = Data("var nacl = {};".utf8)

    private func makeSession() -> ImportSession {
        ImportSession(assets: [
            "": .init(data: Self.page, contentType: HTTPResponse.html),
            "nacl.js": .init(data: Self.script, contentType: HTTPResponse.javaScript),
        ])
    }

    private func get(_ path: String) -> HTTPRequest {
        HTTPRequest(method: "GET", path: path, headers: [:], body: Data())
    }

    private func post(_ path: String, _ body: Data) -> HTTPRequest {
        HTTPRequest(method: "POST", path: path, headers: ["content-length": String(body.count)], body: body)
    }

    private func response(_ outcome: ImportSession.Outcome) -> HTTPResponse {
        switch outcome {
        case .respond(let r), .imported(let r, _), .tooManyBadRequests(let r): r
        }
    }

    private func error(_ outcome: ImportSession.Outcome) -> String? {
        let body = response(outcome).body
        return (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
    }

    @Test("Tokens are 22 characters of base64url and differ every time")
    func tokens() {
        let tokens = (0..<100).map { _ in ImportSession.makeToken() }
        #expect(Set(tokens).count == 100)
        #expect(tokens.allSatisfy { $0.count == 22 && Data(base64URL: $0)?.count == 16 })
    }

    @Test("The URL carries the token in the path and the key in the fragment")
    func url() {
        let session = makeSession()
        let url = session.url(host: "192.0.2.10", port: 52817)
        #expect(url.absoluteString == "http://192.0.2.10:52817/\(session.token)/#\(session.key.base64URL)")
        #expect(url.fragment == session.key.base64URL)
    }

    @Test("The page and its script are served under the token")
    func assets() {
        var session = makeSession()
        let page = response(session.handle(get("/\(session.token)/")))
        #expect(page.status == .ok && page.body == Self.page)
        #expect(page.header("Content-Type") == HTTPResponse.html)
        #expect(page.header("Content-Security-Policy") != nil)

        let script = response(session.handle(get("/\(session.token)/nacl.js")))
        #expect(script.status == .ok && script.body == Self.script)

        let head = response(session.handle(HTTPRequest(method: "HEAD", path: "/\(session.token)/", headers: [:], body: Data())))
        #expect(head.status == .ok && head.body.isEmpty)
        #expect(head.header("Content-Length") == String(Self.page.count))
        #expect(session.badRequests == 0)
    }

    @Test("The token without its slash redirects, keeping relative links working")
    func redirect() {
        var session = makeSession()
        let reply = response(session.handle(get("/\(session.token)")))
        #expect(reply.status == .permanentRedirect)
        #expect(reply.header("Location") == "/\(session.token)/")
        #expect(session.badRequests == 0)
    }

    @Test("Anything else is not found and counts as bad, except the favicon")
    func notFound() {
        var session = makeSession()
        let token = session.token
        for path in ["/", "/index.html", "/\(ImportSession.makeToken())/", "/\(token.dropLast())/", "/\(token)/other.js"] {
            #expect(response(session.handle(get(path))).status == .notFound)
        }
        #expect(session.badRequests == 5)
        #expect(response(session.handle(get("/favicon.ico"))).status == .notFound)
        #expect(session.badRequests == 5)
    }

    @Test("Ten bad requests end the session")
    func tooMany() {
        var session = makeSession()
        for _ in 1..<ImportSession.maxBadRequests {
            guard case .respond = session.handle(get("/nope")) else {
                Issue.record("ended too early")
                return
            }
        }
        guard case .tooManyBadRequests = session.handle(get("/nope")) else {
            Issue.record("expected the session to end")
            return
        }
        #expect(session.isOver)
        // Even the right request gets nothing now.
        #expect(response(session.handle(get("/\(session.token)/"))).status == .notFound)
    }

    @Test("Refused requests count as bad")
    func rejectedCounts() {
        var session = makeSession()
        #expect(response(session.rejected(.contentTooLarge)).status == .contentTooLarge)
        #expect(session.badRequests == 1)
    }

    @Test("A valid submission imports the profile and ends the session")
    func valid() throws {
        var session = makeSession()
        let fixture = Fixtures.Config()
        let body = sealedSubmission(name: "  Home  ", config: fixture.text(), key: session.key)
        let outcome = session.handle(post("/\(session.token)/", body))
        guard case .imported(let reply, let profile) = outcome else {
            Issue.record("expected an import, got \(outcome)")
            return
        }
        #expect(reply.status == .ok)
        #expect(String(decoding: reply.body, as: UTF8.self) == #"{"ok":true}"#)
        #expect(profile.name == "Home")
        #expect(profile.config.interface.privateKey.base64 == fixture.privateKey)
        #expect(session.isOver)
    }

    @Test("A submission sealed with another key is refused and counts as bad")
    func wrongKey() {
        var session = makeSession()
        let body = sealedSubmission(name: "Home", config: Fixtures.Config().text(), key: .random())
        let outcome = session.handle(post("/\(session.token)/", body))
        #expect(response(outcome).status == .badRequest)
        #expect(error(outcome)?.contains("Scan the code on the TV again") == true)
        #expect(session.badRequests == 1)
        #expect(!session.isOver)
    }

    @Test("Garbage bodies are refused and count as bad", arguments: ["", "not base64!", "aGVsbG8="])
    func garbage(body: String) {
        var session = makeSession()
        #expect(response(session.handle(post("/\(session.token)/", Data(body.utf8)))).status == .badRequest)
        #expect(session.badRequests == 1)
    }

    @Test("An invalid config is explained and the session stays open for a fix")
    func invalidThenFixed() {
        var session = makeSession()
        let fixture = Fixtures.Config()
        let broken = fixture.text().replacingOccurrences(of: "Endpoint = vpn.example.com:51820", with: "Endpoint = nowhere")
        let first = session.handle(post("/\(session.token)/", sealedSubmission(name: "Home", config: broken, key: session.key)))
        #expect(response(first).status == .unprocessableContent)
        #expect(error(first)?.contains("Endpoint") == true)
        #expect(error(first)?.contains("nowhere") == false)
        #expect(session.badRequests == 0)
        #expect(!session.isOver)

        let second = session.handle(post("/\(session.token)/", sealedSubmission(name: "Home", config: fixture.text(), key: session.key)))
        guard case .imported = second else {
            Issue.record("expected an import after the fix, got \(second)")
            return
        }
    }

    @Test("Names are checked like manual entry", arguments: ["", "   ", String(repeating: "x", count: 41)])
    func badName(name: String) {
        var session = makeSession()
        let outcome = session.handle(post("/\(session.token)/", sealedSubmission(name: name, config: Fixtures.Config().text(), key: session.key)))
        #expect(response(outcome).status == .unprocessableContent)
        #expect(session.badRequests == 0)
    }

    @Test("Wrong methods are refused")
    func methods() {
        var session = makeSession()
        let token = session.token
        #expect(response(session.handle(HTTPRequest(method: "PUT", path: "/\(token)/", headers: [:], body: Data()))).status == .methodNotAllowed)
        #expect(response(session.handle(post("/\(token)/nacl.js", Data()))).status == .methodNotAllowed)
        #expect(session.badRequests == 2)
    }

    @Test("Token comparison")
    func constantTime() {
        #expect(ImportSession.constantTimeEqual("abc", "abc"))
        #expect(!ImportSession.constantTimeEqual("abc", "abd"))
        #expect(!ImportSession.constantTimeEqual("abc", "abcd"))
        #expect(!ImportSession.constantTimeEqual("", "a"))
    }
}

@Suite("Local address")
struct LocalAddressTests {

    private func interface(_ name: String, _ address: String, up: Bool = true) -> LocalAddress.Interface {
        .init(name: name, address: address, isUp: up)
    }

    @Test("Ethernet or Wi-Fi, never the loopback or a VPN tunnel")
    func physicalOnly() {
        #expect(LocalAddress.choose(from: [
            interface("lo0", "127.0.0.1"),
            interface("utun3", "10.8.0.2"),
            interface("en1", "192.168.1.40"),
        ]) == "192.168.1.40")
        #expect(LocalAddress.choose(from: [interface("utun3", "10.8.0.2"), interface("lo0", "127.0.0.1")]) == nil)
    }

    @Test("Interfaces that are down or link-local are skipped")
    func skipped() {
        #expect(LocalAddress.choose(from: [
            interface("en0", "192.168.1.5", up: false),
            interface("en1", "169.254.10.20"),
        ]) == nil)
    }

    @Test("Private addresses first, then the lowest interface")
    func order() {
        #expect(LocalAddress.choose(from: [
            interface("en0", "203.0.113.7"),
            interface("en2", "172.20.10.3"),
            interface("en10", "10.0.0.9"),
        ]) == "172.20.10.3")
        #expect(LocalAddress.choose(from: [interface("en1", "10.0.0.2"), interface("en0", "10.0.0.1")]) == "10.0.0.1")
    }

    @Test("RFC 1918 ranges", arguments: [
        ("10.1.2.3", true), ("172.16.0.1", true), ("172.31.255.1", true), ("192.168.0.1", true),
        ("172.32.0.1", false), ("192.169.0.1", false), ("203.0.113.1", false), ("not an address", false),
    ])
    func privateRanges(address: String, expected: Bool) {
        #expect(LocalAddress.isPrivate(address) == expected)
    }

    @Test("The simulator's own interfaces give an answer or nothing, never a tunnel")
    func current() {
        if let address = LocalAddress.current() {
            #expect(!address.hasPrefix("127.") && !address.hasPrefix("169.254."))
        }
    }
}
