import Foundation

public enum ZunoError: Error, Sendable, Equatable {
    /// The request was rejected before it was sent (bad argument).
    case invalidRequest(String)
    /// The server answered with a non-2xx status. `code` is the API's
    /// machine-readable `error` value when present (for example
    /// `rider_not_assigned`); `retryAfter` comes from the `Retry-After` header.
    case api(statusCode: Int, code: String?, message: String?, retryAfter: TimeInterval?)
    /// The response body did not match the expected shape.
    case decoding(String)
    /// The request never got an HTTP response.
    case network(URLError)

    public var statusCode: Int? {
        if case .api(let statusCode, _, _, _) = self { return statusCode }
        return nil
    }

    /// True when the same request may succeed if sent again later: rate
    /// limits, GhanaPostGPS outages (424), server errors and network failures.
    /// Order creation is only safe to retry with the same idempotency key.
    public var isRetryable: Bool {
        switch self {
        case .api(let statusCode, _, _, _):
            return statusCode == 424 || statusCode == 429 || statusCode >= 500
        case .network:
            return true
        case .invalidRequest, .decoding:
            return false
        }
    }
}

extension ZunoError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason):
            return "Invalid Zuno request: \(reason)"
        case .api(let statusCode, let code, let message, _):
            let detail = message ?? code ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            return "Zuno API error \(statusCode): \(detail)"
        case .decoding(let reason):
            return "Unexpected Zuno response: \(reason)"
        case .network(let error):
            return error.localizedDescription
        }
    }
}
