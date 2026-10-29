import Foundation

/// A profile that arrived through the QR import, checked but not yet saved.
/// The import screen shows it for confirmation first.
struct ImportedProfile: Hashable, Sendable {
    let name: String
    let config: WireGuardConfig
    let warnings: [ConfigWarning]
}

/// What the import page sends, sealed with the session key: the profile
/// name and the `.conf` text as JSON, `{"name": "…", "config": "…"}`. The
/// POST body is the sealed bytes (nonce then box) in standard base64.
struct ImportSubmission: Codable, Equatable {
    let name: String
    let config: String
}

/// The rules of one import session, without any networking: which requests
/// are answered, how a submission is checked, and when the session is over.
/// `ImportServer` feeds it requests and carries out what it decides.
struct ImportSession {
    static let maxBadRequests = 10

    struct Asset: Sendable {
        let data: Data
        let contentType: String
    }

    enum Outcome: Equatable {
        /// Reply and carry on.
        case respond(HTTPResponse)
        /// Reply, then stop: a valid profile arrived.
        case imported(HTTPResponse, ImportedProfile)
        /// Reply, then stop: too many bad requests.
        case tooManyBadRequests(HTTPResponse)
    }

    let token: String
    let key: SecretBox.Key
    /// Files under the token path; the key "" is the page itself.
    private let assets: [String: Asset]
    private(set) var badRequests = 0
    private(set) var isOver = false

    init(token: String = ImportSession.makeToken(), key: SecretBox.Key = .random(), assets: [String: Asset]) {
        self.token = token
        self.key = key
        self.assets = assets
    }

    /// 128 random bits, base64url: 22 characters.
    static func makeToken() -> String {
        SecretBox.randomBytes(16).base64URLEncodedString()
    }

    /// The address the QR code shows. The key goes in the fragment, which
    /// browsers keep to themselves and never send to the server.
    func url(host: String, port: UInt16) -> URL {
        URL(string: "http://\(host):\(port)/\(token)/#\(key.base64URL)")!
    }

    mutating func handle(_ request: HTTPRequest) -> Outcome {
        guard !isOver else { return .respond(.plain(.notFound)) }
        if request.path == "/favicon.ico" { return .respond(.plain(.notFound)) }

        let segments = request.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        // segments[0] is the empty text before the leading slash.
        guard segments.count >= 2 else { return bad(.notFound) }
        let rest = segments[1].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard Self.constantTimeEqual(String(rest[0]), token) else { return bad(.notFound) }

        guard rest.count == 2 else {
            // "/<token>" without the slash: send the browser to "/<token>/",
            // keeping the fragment, so the page's relative links work.
            return .respond(HTTPResponse(status: .permanentRedirect, extraHeaders: [("Location", "/\(token)/")]))
        }
        let name = String(rest[1])

        switch request.method {
        case "GET", "HEAD":
            guard let asset = assets[name] else { return bad(.notFound) }
            let response = HTTPResponse(status: .ok, contentType: asset.contentType, body: asset.data)
            if request.method == "HEAD" {
                var head = HTTPResponse(status: .ok, contentType: asset.contentType)
                head.headers = response.headers
                return .respond(head)
            }
            return .respond(response)
        case "POST" where name.isEmpty:
            return submit(request.body)
        default:
            return bad(.methodNotAllowed)
        }
    }

    /// A request the parser refused (too large, malformed): counts as bad.
    mutating func rejected(_ status: HTTPStatus) -> Outcome {
        guard !isOver else { return .respond(.plain(status)) }
        return bad(status)
    }

    private mutating func submit(_ body: Data) -> Outcome {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sealed = Data(base64Encoded: text),
              let opened = SecretBox.open(sealed, key: key),
              let submission = try? JSONDecoder().decode(ImportSubmission.self, from: opened) else {
            // Only a page with this session's key can seal a submission, so
            // anything else is a stale page or someone else's request.
            return bad(.badRequest, error: "The TV couldn't read this. Scan the code on the TV again and resend.")
        }

        let name = submission.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return .respond(.json(.unprocessableContent, error: "Enter a name, such as Home."))
        }
        if name.count > ProfileName.maxLength {
            return .respond(.json(.unprocessableContent,
                                  error: "Use a name of \(ProfileName.maxLength) characters or fewer."))
        }
        let parsed: ParsedConfig
        do {
            parsed = try WireGuardConfig.parse(submission.config)
        } catch {
            // A real config with a mistake: say what, and stay open for a fix.
            return .respond(.json(.unprocessableContent, error: error.message))
        }

        isOver = true
        let profile = ImportedProfile(name: name, config: parsed.config, warnings: parsed.warnings)
        return .imported(.json(.ok), profile)
    }

    private mutating func bad(_ status: HTTPStatus, error: String? = nil) -> Outcome {
        badRequests += 1
        let response: HTTPResponse = error.map { .json(status, error: $0) } ?? .plain(status)
        if badRequests >= Self.maxBadRequests {
            isOver = true
            return .tooManyBadRequests(response)
        }
        return .respond(response)
    }

    /// Compares without stopping at the first difference, so response times
    /// say nothing about how much of a guessed token was right.
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
