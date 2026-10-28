import Foundation
import JavaScriptCore
import Testing
@testable import UntetheredVPN

/// Runs the bundled tweetnacl-js (the file the import page will use) in
/// JavaScriptCore, so the page's encryption is checked against the app's.
/// Keys, nonces and messages are random bytes made at run time.
@Suite("Secretbox")
struct SecretBoxTests {

    /// tweetnacl-js with its `nacl` object reachable from Swift.
    final class TweetNaClJS {
        let context: JSContext

        init() throws {
            let url = try #require(Bundle.main.url(forResource: "nacl", withExtension: "js"),
                                   "nacl.js should be in the app bundle")
            let source = try String(contentsOf: url, encoding: .utf8)
            context = try #require(JSContext())
            // The browser build hangs `nacl` on `self`, which a bare context lacks.
            context.evaluateScript("var self = this;")
            context.evaluateScript(source)
            try #require(context.exception == nil, "nacl.js should load: \(String(describing: context.exception))")
        }

        /// `nacl.secretbox(message, nonce, key)`: the box without the nonce.
        func seal(_ message: Data, nonce: Data, key: Data) -> Data? {
            call("nacl.secretbox", message, nonce, key)
        }

        /// `nacl.secretbox.open(box, nonce, key)`, or nil when it returns null.
        func open(_ box: Data, nonce: Data, key: Data) -> Data? {
            call("nacl.secretbox.open", box, nonce, key)
        }

        private func call(_ function: String, _ arguments: Data...) -> Data? {
            let script = """
                (function (a, b, c) {
                  var result = \(function)(new Uint8Array(a), new Uint8Array(b), new Uint8Array(c));
                  return result ? Array.from(result) : null;
                })
                """
            let result = context.evaluateScript(script).call(withArguments: arguments.map { [UInt8]($0) })
            guard context.exception == nil, let result, !result.isNull,
                  let numbers = result.toArray() as? [NSNumber] else {
                return nil
            }
            return Data(numbers.map(\.uint8Value))
        }
    }

    static let sizes = [0, 1, 31, 32, 33, 1_000, 16 * 1024]

    @Test("The page's encryption opens in the app", arguments: sizes)
    func javaScriptToSwift(size: Int) throws {
        let js = try TweetNaClJS()
        let key = SecretBox.Key.random()
        let nonce = SecretBox.randomBytes(SecretBox.nonceLength)
        let message = SecretBox.randomBytes(size)

        let box = try #require(js.seal(message, nonce: nonce, key: key.bytes))
        #expect(box.count == size + SecretBox.tagLength)
        #expect(SecretBox.open(nonce + box, key: key) == message)
    }

    @Test("The app's encryption opens in the page's library", arguments: sizes)
    func swiftToJavaScript(size: Int) throws {
        let js = try TweetNaClJS()
        let key = SecretBox.Key.random()
        let message = SecretBox.randomBytes(size)

        let sealed = SecretBox.seal(message, key: key)
        let nonce = sealed.prefix(SecretBox.nonceLength)
        let box = sealed.dropFirst(SecretBox.nonceLength)
        #expect(js.open(Data(box), nonce: Data(nonce), key: key.bytes) == message)
    }

    @Test("Both produce the same bytes for the same key and nonce")
    func identicalOutput() throws {
        let js = try TweetNaClJS()
        let key = SecretBox.Key.random()
        let nonce = SecretBox.randomBytes(SecretBox.nonceLength)
        let message = Data("[Interface]\nAddress = 10.8.0.2/32\n".utf8)

        let fromJS = try #require(js.seal(message, nonce: nonce, key: key.bytes))
        #expect(SecretBox.seal(message, key: key, nonce: nonce) == nonce + fromJS)
    }

    @Test("A wrong key is rejected")
    func wrongKey() {
        let sealed = SecretBox.seal(Data("hello".utf8), key: .random())
        #expect(SecretBox.open(sealed, key: .random()) == nil)
    }

    @Test("Any changed bit is rejected")
    func tampering() {
        let key = SecretBox.Key.random()
        let sealed = SecretBox.seal(SecretBox.randomBytes(64), key: key)
        // One flipped bit in the nonce, the tag and the ciphertext.
        for index in [0, SecretBox.nonceLength, sealed.count - 1] {
            var changed = sealed
            changed[index] ^= 0x01
            #expect(SecretBox.open(changed, key: key) == nil)
        }
    }

    @Test("Short or truncated input is rejected")
    func truncated() {
        let key = SecretBox.Key.random()
        let sealed = SecretBox.seal(Data("hello".utf8), key: key)
        #expect(SecretBox.open(Data(), key: key) == nil)
        #expect(SecretBox.open(sealed.prefix(SecretBox.nonceLength + SecretBox.tagLength - 1), key: key) == nil)
        #expect(SecretBox.open(sealed.dropLast(), key: key) == nil)
    }

    @Test("Keys must be 32 bytes")
    func keyLength() {
        #expect(SecretBox.Key(bytes: SecretBox.randomBytes(31)) == nil)
        #expect(SecretBox.Key(bytes: SecretBox.randomBytes(33)) == nil)
        #expect(SecretBox.Key(bytes: SecretBox.randomBytes(32)) != nil)
    }

    @Test("Keys survive the URL fragment as base64url")
    func base64URL() {
        for _ in 0..<50 {
            let key = SecretBox.Key.random()
            let text = key.base64URL
            #expect(text.count == 43)
            #expect(!text.contains { "+/=".contains($0) })
            #expect(SecretBox.Key(base64URL: text)?.bytes == key.bytes)
        }
        #expect(SecretBox.Key(base64URL: "") == nil)
        #expect(SecretBox.Key(base64URL: String(repeating: "A", count: 42)) == nil)
        #expect(SecretBox.Key(base64URL: String(repeating: "A", count: 42) + "=") == nil)
        #expect(SecretBox.Key(base64URL: String(repeating: "A", count: 42) + "+") == nil)
    }

    @Test("A key never prints its bytes")
    func masked() {
        let key = SecretBox.Key.random()
        #expect("\(key)" == WireGuardKey.masked)
        #expect(!String(reflecting: key).contains(key.base64URL))
    }
}
