import Foundation

/// The few HTTP status codes the import server sends.
enum HTTPStatus: Int, Sendable {
    case ok = 200
    case permanentRedirect = 308
    case badRequest = 400
    case notFound = 404
    case methodNotAllowed = 405
    case lengthRequired = 411
    case contentTooLarge = 413
    case unprocessableContent = 422
    case headersTooLarge = 431
    case notImplemented = 501
    case versionNotSupported = 505

    var reason: String {
        switch self {
        case .ok: "OK"
        case .permanentRedirect: "Permanent Redirect"
        case .badRequest: "Bad Request"
        case .notFound: "Not Found"
        case .methodNotAllowed: "Method Not Allowed"
        case .lengthRequired: "Length Required"
        case .contentTooLarge: "Content Too Large"
        case .unprocessableContent: "Unprocessable Content"
        case .headersTooLarge: "Request Header Fields Too Large"
        case .notImplemented: "Not Implemented"
        case .versionNotSupported: "HTTP Version Not Supported"
        }
    }
}

/// One HTTP/1.x request, as much of it as the import server cares about.
struct HTTPRequest: Equatable, Sendable {
    let method: String
    /// The request target without any query string.
    let path: String
    /// Header names in lower case.
    let headers: [String: String]
    let body: Data
}

/// Reads one request from bytes as they arrive, enforcing the import
/// server's limits before buffering more than they allow. No chunked bodies,
/// no keep-alive: one request per connection.
struct HTTPRequestParser {
    static let maxHeaderBytes = 8 * 1024
    static let maxBodyBytes = 16 * 1024

    enum Result: Equatable {
        case incomplete
        case complete(HTTPRequest)
        case rejected(HTTPStatus)
    }

    private var buffer = Data()

    mutating func append(_ data: Data) -> Result {
        buffer.append(data)
        guard let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > Self.maxHeaderBytes ? .rejected(.headersTooLarge) : .incomplete
        }
        guard end.lowerBound <= Self.maxHeaderBytes else { return .rejected(.headersTooLarge) }
        guard let head = String(data: buffer[..<end.lowerBound], encoding: .utf8) else {
            return .rejected(.badRequest)
        }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3 else { return .rejected(.badRequest) }
        let method = String(requestLine[0])
        let target = String(requestLine[1])
        guard requestLine[2].hasPrefix("HTTP/1.") else { return .rejected(.versionNotSupported) }
        guard !method.isEmpty, method.allSatisfy({ $0.isASCII && $0.isUppercase }),
              target.hasPrefix("/") else {
            return .rejected(.badRequest)
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .rejected(.badRequest) }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(" ") else { return .rejected(.badRequest) }
            if let earlier = headers[name], name == "content-length", earlier != value {
                return .rejected(.badRequest)
            }
            headers[name] = value
        }

        if headers["transfer-encoding"] != nil { return .rejected(.notImplemented) }
        let length: Int
        if let text = headers["content-length"] {
            guard let value = Int(text), value >= 0 else { return .rejected(.badRequest) }
            length = value
        } else {
            guard method != "POST" else { return .rejected(.lengthRequired) }
            length = 0
        }
        guard length <= Self.maxBodyBytes else { return .rejected(.contentTooLarge) }

        let bodyStart = end.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }
        let path = String(target.prefix { $0 != "?" })
        let body = Data(buffer[bodyStart ..< bodyStart + length])
        return .complete(HTTPRequest(method: method, path: path, headers: headers, body: body))
    }
}

/// A response with the headers every import-server reply carries: no
/// caching, no referrer (the URL holds the one-time token), no MIME sniffing,
/// and the connection closes afterwards.
struct HTTPResponse: Equatable, Sendable {
    static let html = "text/html; charset=utf-8"
    static let javaScript = "text/javascript; charset=utf-8"
    static let css = "text/css; charset=utf-8"
    static let json = "application/json"
    static let text = "text/plain; charset=utf-8"

    /// Page policy: only files from this server, nothing inline, no framing.
    static let contentSecurityPolicy = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"

    let status: HTTPStatus
    var headers: [(String, String)]
    let body: Data

    init(status: HTTPStatus, contentType: String = text, body: Data = Data(), extraHeaders: [(String, String)] = []) {
        self.status = status
        self.body = body
        headers = [
            ("Content-Type", contentType),
            ("Content-Length", String(body.count)),
            ("Cache-Control", "no-store"),
            ("Referrer-Policy", "no-referrer"),
            ("X-Content-Type-Options", "nosniff"),
            ("Connection", "close"),
        ] + extraHeaders
        if contentType == Self.html {
            headers.append(("Content-Security-Policy", Self.contentSecurityPolicy))
        }
    }

    /// A short plain-text reply that says nothing beyond the status.
    static func plain(_ status: HTTPStatus) -> HTTPResponse {
        HTTPResponse(status: status, body: Data("\(status.reason)\n".utf8))
    }

    /// A JSON reply for the import page: `{"ok":true}` or `{"error":"…"}`.
    static func json(_ status: HTTPStatus, error: String? = nil) -> HTTPResponse {
        let object: [String: Any] = error.map { ["error": $0] } ?? ["ok": true]
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: status, contentType: json, body: body)
    }

    func header(_ name: String) -> String? {
        headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }

    func serialized() -> Data {
        var head = "HTTP/1.1 \(status.rawValue) \(status.reason)\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    static func == (lhs: HTTPResponse, rhs: HTTPResponse) -> Bool {
        lhs.status == rhs.status && lhs.body == rhs.body
            && lhs.headers.map { "\($0.0): \($0.1)" } == rhs.headers.map { "\($0.0): \($0.1)" }
    }
}
