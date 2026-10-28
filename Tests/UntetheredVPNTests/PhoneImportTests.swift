import CoreImage
import Foundation
import JavaScriptCore
import Testing
@testable import UntetheredVPN

@Suite("Import page script")
struct ImportPageScriptTests {

    /// The bundled nacl.js and import.js, as the phone runs them. A bare
    /// JavaScriptCore context has no `crypto`, so the test gives tweetnacl a
    /// random source from Swift.
    static func makeContext() throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript("var self = this;")
        for name in ["nacl", "import"] {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "js"))
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            try #require(context.exception == nil, "\(name).js should load: \(String(describing: context.exception))")
        }
        let random: @convention(block) (Int) -> [UInt8] = { [UInt8](SecretBox.randomBytes($0)) }
        context.setObject(random, forKeyedSubscript: "swiftRandom" as NSString)
        context.evaluateScript("""
            nacl.setPRNG(function (x, n) { var r = swiftRandom(n); for (var i = 0; i < n; i++) x[i] = r[i]; });
            """)
        return context
    }

    private static func seal(_ context: JSContext, name: String, config: String, key: String) -> String? {
        let function = context.evaluateScript("""
            (function (name, config, keyText) {
              var key = UntetheredImport.keyFromFragment(keyText);
              return key ? UntetheredImport.seal(name, config, key) : null;
            })
            """)
        let result = function?.call(withArguments: [name, config, key])
        guard let result, !result.isNull, context.exception == nil else { return nil }
        return result.toString()
    }

    @Test("What the page sends imports on the TV, accents and all")
    func pageToSession() throws {
        let context = try Self.makeContext()
        var session = ImportSession(assets: [:])
        let fixture = Fixtures.Config()
        let body = try #require(Self.seal(context, name: "Café Zoë", config: fixture.text(), key: session.key.base64URL))
        let request = HTTPRequest(method: "POST", path: "/\(session.token)/", headers: [:], body: Data(body.utf8))
        guard case .imported(_, let profile) = session.handle(request) else {
            Issue.record("expected the page's submission to import")
            return
        }
        #expect(profile.name == "Café Zoë")
        #expect(profile.config.interface.privateKey.base64 == fixture.privateKey)
    }

    @Test("The page's base64 reads on the TV for every padding case")
    func base64() throws {
        let context = try Self.makeContext()
        // Configs of 0–5 characters cover every base64 padding case.
        for length in 0..<6 {
            var session = ImportSession(assets: [:])
            let config = String(repeating: "x", count: length)
            let body = try #require(Self.seal(context, name: "Home", config: config, key: session.key.base64URL))
            #expect(Data(base64Encoded: body) != nil)
            let request = HTTPRequest(method: "POST", path: "/\(session.token)/", headers: [:], body: Data(body.utf8))
            // Not a valid config, but readable: a 422, not a 400.
            guard case .respond(let reply) = session.handle(request) else {
                Issue.record("expected a reply")
                continue
            }
            #expect(reply.status == .unprocessableContent)
        }
    }

    @Test("Only a complete 32-byte key from the fragment is accepted", arguments: [
        "", "abc", String(repeating: "A", count: 42), String(repeating: "A", count: 44),
        String(repeating: "A", count: 42) + "+", String(repeating: "A", count: 42) + "=",
    ])
    func badKeys(text: String) throws {
        let context = try Self.makeContext()
        #expect(Self.seal(context, name: "Home", config: "x", key: text) == nil)
    }
}

@Suite("Phone import screen", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct PhoneImportTests {

    private func waitWhileStarting(_ phoneImport: PhoneImport) async throws {
        for _ in 0..<250 where phoneImport.state == .starting {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Countdown text has units and never goes negative")
    func timeLeft() {
        let now = Date()
        #expect(PhoneImport.timeLeft(until: now.addingTimeInterval(300), now: now) == "5 min 0 s left")
        #expect(PhoneImport.timeLeft(until: now.addingTimeInterval(272), now: now) == "4 min 32 s left")
        #expect(PhoneImport.timeLeft(until: now.addingTimeInterval(59), now: now) == "59 s left")
        #expect(PhoneImport.timeLeft(until: now.addingTimeInterval(44.2), now: now) == "45 s left")
        #expect(PhoneImport.timeLeft(until: now.addingTimeInterval(45), now: now) == "45 s left")
        #expect(PhoneImport.timeLeft(until: now.addingTimeInterval(-3), now: now) == "0 s left")
    }

    @Test("Every problem explains itself and offers a way on")
    func problems() {
        for problem in [PhoneImport.Problem.timedOut, .tooManyBadRequests, .noNetwork] {
            #expect(!problem.title.isEmpty)
            #expect(problem.message.contains("start again") || problem.message.contains("Start again"))
        }
    }

    @Test("Start shows a code; a submission moves to the review; nothing is listening after")
    func flow() async throws {
        let phoneImport = PhoneImport(binding: .loopback)
        phoneImport.start()
        try await waitWhileStarting(phoneImport)
        guard case .waiting(let url, _) = phoneImport.state else {
            Issue.record("expected a code, got \(phoneImport.state)")
            return
        }
        let port = UInt16(url.port!)
        let token = url.pathComponents[1]
        let fragment = try #require(url.fragment)
        let key = try #require(SecretBox.Key(base64URL: fragment))

        let body = sealedSubmission(name: "Home", config: Fixtures.Config().text(), key: key)
        #expect(try await ImportServerTests.post(body, path: "/\(token)/", port: port).status == 200)
        for _ in 0..<250 {
            if case .received = phoneImport.state { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .received(let profile) = phoneImport.state else {
            Issue.record("expected the review, got \(phoneImport.state)")
            return
        }
        #expect(profile.name == "Home")
        #expect(!phoneImport.shouldRestartOnReturn)
        await #expect(throws: ImportServerTests.ClientError.self) {
            _ = try await ImportServerTests.send("GET /\(token)/ HTTP/1.1\r\n\r\n", port: port)
        }
    }

    @Test("Stopping kills the code; starting again makes a new one")
    func restart() async throws {
        let phoneImport = PhoneImport(binding: .loopback)
        phoneImport.start()
        try await waitWhileStarting(phoneImport)
        guard case .waiting(let first, _) = phoneImport.state else {
            Issue.record("expected a code")
            return
        }
        #expect(phoneImport.shouldRestartOnReturn)
        phoneImport.stop()
        try await Task.sleep(for: .milliseconds(100))
        await #expect(throws: ImportServerTests.ClientError.self) {
            _ = try await ImportServerTests.send("GET \(first.path)/ HTTP/1.1\r\n\r\n", port: UInt16(first.port!))
        }

        phoneImport.start()
        try await waitWhileStarting(phoneImport)
        guard case .waiting(let second, _) = phoneImport.state else {
            Issue.record("expected a new code")
            return
        }
        #expect(second.path != first.path)
        #expect(second.fragment != first.fragment)
        phoneImport.stop()
    }
}

@Suite("QR code")
struct QRCodeTests {

    @Test("The code reads back as the import address")
    func roundTrip() throws {
        let session = ImportSession(assets: [:])
        let text = session.url(host: "192.168.1.40", port: 52817).absoluteString
        let image = try #require(QRCode.image(for: text))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: image)).compactMap { $0 as? CIQRCodeFeature }
        #expect(features.first?.messageString == text)
    }

    @Test("The page and its files are all in the app bundle")
    func bundledAssets() {
        #expect(Set(ImportServer.bundledAssets().keys) == ["", "nacl.js", "import.js", "import.css"])
    }
}
