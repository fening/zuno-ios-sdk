import Foundation

/// Serves canned responses and records requests, so tests exercise the real
/// URLSession path without a network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data = Data()

        static func json(_ status: Int = 200, _ body: String, headers: [String: String] = [:]) -> Response {
            Response(
                status: status,
                headers: ["Content-Type": "application/json"].merging(headers) { $1 },
                body: Data(body.utf8))
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Response] = []
    nonisolated(unsafe) private static var captured: [URLRequest] = []

    static func enqueue(_ responses: Response...) {
        lock.withLock { queue.append(contentsOf: responses) }
    }

    static var requests: [URLRequest] { lock.withLock { captured } }

    static func reset() {
        lock.withLock {
            queue = []
            captured = []
        }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        // URLSession moves bodies into a stream; read it back for assertions.
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            recorded.httpBody = data
        }
        let next: Response? = Self.lock.withLock {
            Self.captured.append(recorded)
            return Self.queue.isEmpty ? nil : Self.queue.removeFirst()
        }
        guard let next else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: next.status, httpVersion: "HTTP/1.1",
            headerFields: next.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLRequest {
    var jsonBody: [String: Any]? {
        httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
