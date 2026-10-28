import Foundation
import Testing
@testable import UntetheredVPN

@Suite("HTTP request parser")
struct HTTPRequestParserTests {

    private func parse(_ text: String) -> HTTPRequestParser.Result {
        var parser = HTTPRequestParser()
        return parser.append(Data(text.utf8))
    }

    @Test("A GET without a body")
    func get() {
        let result = parse("GET /abc/?x=1 HTTP/1.1\r\nHost: 192.0.2.10:8080\r\nAccept: */*\r\n\r\n")
        #expect(result == .complete(HTTPRequest(
            method: "GET", path: "/abc/",
            headers: ["host": "192.0.2.10:8080", "accept": "*/*"], body: Data())))
    }

    @Test("A POST arriving in pieces")
    func postInPieces() {
        var parser = HTTPRequestParser()
        #expect(parser.append(Data("POST /t/ HTTP/1.1\r\nContent-Le".utf8)) == .incomplete)
        #expect(parser.append(Data("ngth: 5\r\n\r\nhel".utf8)) == .incomplete)
        let result = parser.append(Data("lo".utf8))
        guard case .complete(let request) = result else {
            Issue.record("expected a complete request, got \(result)")
            return
        }
        #expect(request.method == "POST")
        #expect(request.body == Data("hello".utf8))
    }

    @Test("A POST needs a length")
    func lengthRequired() {
        #expect(parse("POST /t/ HTTP/1.1\r\nHost: x\r\n\r\n") == .rejected(.lengthRequired))
    }

    @Test("Bodies over 16 KB are refused from the header alone")
    func tooLarge() {
        let limit = HTTPRequestParser.maxBodyBytes
        #expect(parse("POST /t/ HTTP/1.1\r\nContent-Length: \(limit + 1)\r\n\r\n") == .rejected(.contentTooLarge))
        #expect(parse("POST /t/ HTTP/1.1\r\nContent-Length: \(limit)\r\n\r\n") == .incomplete)
    }

    @Test("Headers over 8 KB are refused, with or without an end")
    func headersTooLarge() {
        let padding = String(repeating: "a", count: HTTPRequestParser.maxHeaderBytes)
        #expect(parse("GET / HTTP/1.1\r\nX-Pad: \(padding)") == .rejected(.headersTooLarge))
        #expect(parse("GET / HTTP/1.1\r\nX-Pad: \(padding)\r\n\r\n") == .rejected(.headersTooLarge))
    }

    @Test("Chunked bodies aren't supported")
    func chunked() {
        #expect(parse("POST /t/ HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") == .rejected(.notImplemented))
    }

    @Test("Malformed requests are refused", arguments: [
        "GET /\r\n\r\n",
        "GET / HTTP/1.1 extra\r\n\r\n",
        "get / HTTP/1.1\r\n\r\n",
        "GET abc HTTP/1.1\r\n\r\n",
        "GET / HTTP/1.1\r\nNo colon here\r\n\r\n",
        "POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
        "POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n",
    ])
    func malformed(text: String) {
        #expect(parse(text) == .rejected(.badRequest))
    }

    @Test("Only HTTP/1.x")
    func version() {
        #expect(parse("GET / HTTP/2\r\n\r\n") == .rejected(.versionNotSupported))
    }

    @Test("Every response says no caching, no referrer and close")
    func responseHeaders() {
        let response = HTTPResponse.plain(.notFound)
        let text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        #expect(response.header("Cache-Control") == "no-store")
        #expect(response.header("Referrer-Policy") == "no-referrer")
        #expect(response.header("Connection") == "close")
        #expect(response.header("Content-Length") == "10")
        #expect(response.header("Content-Security-Policy") == nil)
        #expect(HTTPResponse(status: .ok, contentType: HTTPResponse.html).header("Content-Security-Policy") != nil)
    }
}
