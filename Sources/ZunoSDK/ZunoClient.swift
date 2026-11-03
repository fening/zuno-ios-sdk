import Foundation

/// Client for the Zuno developer delivery API.
///
/// Every call except `trackDelivery(trackingNumber:)` goes to the integrator
/// backend set in `ZunoConfiguration.backendURL`, which adds the tenant API
/// key and forwards to Zuno. The app never holds the API key.
public final class ZunoClient: Sendable {
    public let configuration: ZunoConfiguration

    public init(configuration: ZunoConfiguration) {
        self.configuration = configuration
    }

    public convenience init(
        backendURL: URL,
        environment: ZunoEnvironment = .production,
        authorizer: ZunoRequestAuthorizer? = nil
    ) {
        self.init(configuration: ZunoConfiguration(
            backendURL: backendURL, environment: environment, authorizer: authorizer))
    }

    // MARK: Deliveries

    /// Prices a delivery. The returned `quoteToken` is short-lived.
    public func createQuote(_ request: QuoteRequest) async throws -> DeliveryQuote {
        let urlRequest = try backendRequest("POST", ["public", "quotes"], body: request)
        return try await sendData(urlRequest, authorize: true)
    }

    /// Creates a delivery from an unexpired quote.
    ///
    /// Generate one `idempotencyKey` per logical delivery (see
    /// `ZunoIdempotencyKey.make()`), store it with your pending order, and
    /// reuse it only to retry this identical request. A retry returns the
    /// existing delivery with `replayed == true` instead of charging twice.
    public func createOrder(
        _ request: CreateOrderRequest, idempotencyKey: String
    ) async throws -> OrderCreation {
        try ZunoIdempotencyKey.validate(idempotencyKey)
        var urlRequest = try backendRequest("POST", ["public", "orders"], body: request)
        urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        let (data, response) = try await send(urlRequest, authorize: true)
        let order: Order = try Self.decode(DataEnvelope<Order>.self, from: data).data
        let replayed = response.statusCode == 200
            || response.value(forHTTPHeaderField: "Idempotent-Replayed")?.lowercased() == "true"
        return OrderCreation(order: order, replayed: replayed)
    }

    public func order(id: String) async throws -> Order {
        let urlRequest = try backendRequest("GET", ["orders", try Self.required(id, "order id")])
        return try await sendData(urlRequest, authorize: true)
    }

    /// The current lifecycle status and, once a driver is assigned, the
    /// driver and vehicle details.
    public func orderStatus(id: String) async throws -> OrderStatusSnapshot {
        let urlRequest = try backendRequest(
            "GET", ["orders", try Self.required(id, "order id"), "status"])
        return try await sendData(urlRequest, authorize: true)
    }

    /// Polls `orderStatus(id:)` and yields each new lifecycle change, then
    /// finishes once the order is delivered, completed or cancelled.
    /// Retryable failures (network, rate limit, 5xx) are skipped; any other
    /// error ends the stream. Prefer webhooks on your backend where you can.
    public func orderStatusUpdates(
        id: String, every interval: TimeInterval = 10
    ) -> AsyncThrowingStream<OrderStatusSnapshot, Error> {
        AsyncThrowingStream { continuation in
            guard interval.isFinite, interval < Double(UInt64.max) / 1_000_000_000 else {
                continuation.finish(throwing: ZunoError.invalidRequest("polling interval is out of range"))
                return
            }
            let delay = UInt64(max(interval, 1) * 1_000_000_000)
            let task = Task {
                var lastSequence: Int64?
                while !Task.isCancelled {
                    do {
                        let snapshot = try await self.orderStatus(id: id)
                        if lastSequence.map({ snapshot.sequence > $0 }) ?? true {
                            lastSequence = snapshot.sequence
                            continuation.yield(snapshot)
                            if snapshot.status.isFinal {
                                continuation.finish()
                                return
                            }
                        }
                    } catch let error as ZunoError where error.isRetryable {
                        // Try again on the next tick.
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                    try? await Task.sleep(nanoseconds: delay)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Cancels an eligible delivery. A funded fare cancelled before pickup is
    /// released back to the tenant balance.
    public func cancelOrder(id: String) async throws -> Cancellation {
        let urlRequest = try backendRequest(
            "POST", ["orders", try Self.required(id, "order id"), "cancel"])
        let (data, _) = try await send(urlRequest, authorize: true)
        let envelope = try Self.decode(CancellationEnvelope.self, from: data)
        return Cancellation(
            orderId: envelope.data.orderId,
            status: envelope.data.status,
            refundPending: envelope.data.refundPending,
            refundStatus: envelope.data.refundStatus,
            message: envelope.message ?? "")
    }

    /// Resolves `DriverAssignment.driverContactToken` to the assigned
    /// driver's phone number. Reassignment invalidates the token.
    public func driverContact(orderId: String, token: String) async throws -> DriverContact {
        let urlRequest = try backendRequest(
            "GET", ["orders", try Self.required(orderId, "order id"), "driver-contact"],
            query: [URLQueryItem(name: "token", value: try Self.required(token, "contact token"))])
        return try await sendData(urlRequest, authorize: true)
    }

    /// Fetches the assigned driver's approved photo using
    /// `DriverAssignment.driverAvatarToken`. Do not cache it beyond the
    /// assignment.
    public func driverAvatar(orderId: String, token: String) async throws -> DriverAvatar {
        var urlRequest = try backendRequest(
            "GET", ["orders", try Self.required(orderId, "order id"), "driver-avatar"])
        urlRequest.setValue(
            try Self.required(token, "avatar token"), forHTTPHeaderField: "X-Zuno-Driver-Avatar-Token")
        urlRequest.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(urlRequest, authorize: true)
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
        return DriverAvatar(data: data, contentType: contentType)
    }

    // MARK: Messaging

    /// Sends a customer message to the assigned driver. Reuse the same
    /// `idempotencyKey` when retrying so the driver sees it once.
    public func sendMessage(
        orderId: String, body: String, idempotencyKey: String = ZunoIdempotencyKey.make()
    ) async throws -> ChatMessage {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 2000 else {
            throw ZunoError.invalidRequest("message body must be 1–2000 characters")
        }
        try ZunoIdempotencyKey.validate(idempotencyKey)
        var urlRequest = try backendRequest(
            "POST", ["public", "orders", try Self.required(orderId, "order id"), "messages"],
            body: ["body": trimmed])
        urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        return try await sendData(urlRequest, authorize: true)
    }

    /// Messages with a sequence greater than `after`, oldest first. Cursors
    /// belong to one conversation. Pass its `conversationId` for pagination
    /// and history after the delivery ends. Omit both cursor and conversation
    /// to discover the current rider's conversation after reassignment.
    public func messages(
        orderId: String, after: Int64? = nil, limit: Int? = nil, conversationId: String? = nil
    ) async throws -> ChatMessagePage {
        if let limit, !(1...100).contains(limit) {
            throw ZunoError.invalidRequest("limit must be 1–100")
        }
        var query: [URLQueryItem] = []
        if let after { query.append(URLQueryItem(name: "after", value: String(after))) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let conversationId {
            query.append(URLQueryItem(name: "conversation_id", value: try Self.required(conversationId, "conversation id")))
        }
        let urlRequest = try backendRequest(
            "GET", ["public", "orders", try Self.required(orderId, "order id"), "messages"],
            query: query)
        return try await sendData(urlRequest, authorize: true)
    }

    /// Marks driver messages read. Returns how many were marked.
    @discardableResult
    public func markMessagesRead(
        orderId: String, conversationId: String, messageIds: [String]
    ) async throws -> Int {
        guard (1...100).contains(messageIds.count) else {
            throw ZunoError.invalidRequest("messageIds must hold 1–100 ids")
        }
        let urlRequest = try backendRequest(
            "POST",
            ["public", "orders", try Self.required(orderId, "order id"), "messages", "read"],
            body: MarkReadBody(
                conversationId: try Self.required(conversationId, "conversation id"),
                messageIds: messageIds))
        let result: MarkReadResult = try await sendData(urlRequest, authorize: true)
        return result.markedCount
    }

    // MARK: Addresses

    /// Converts a GhanaPostGPS code such as `GA-183-9124` into coordinates.
    public func resolveGhanaPostAddress(code: String) async throws -> DigitalAddress {
        let urlRequest = try backendRequest(
            "GET", ["public", "ghanapost", "resolve"],
            query: [URLQueryItem(name: "code", value: try Self.required(code, "code"))])
        return try await sendData(urlRequest, authorize: true)
    }

    /// Converts a map pin into its GhanaPostGPS code.
    public func ghanaPostAddress(latitude: Double, longitude: Double) async throws -> DigitalAddress {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw ZunoError.invalidRequest("coordinates out of range")
        }
        let urlRequest = try backendRequest(
            "GET", ["public", "ghanapost", "encode"],
            query: [
                URLQueryItem(name: "lat", value: String(latitude)),
                URLQueryItem(name: "lng", value: String(longitude)),
            ])
        return try await sendData(urlRequest, authorize: true)
    }

    // MARK: Tracking

    /// Recipient-safe status for a shareable `KDA-…` tracking number. Needs
    /// no API key, so it calls Zuno directly rather than the backend.
    public func trackDelivery(trackingNumber: String) async throws -> DeliveryTracking {
        let number = try Self.required(trackingNumber, "tracking number").uppercased()
        let urlRequest = try Self.makeRequest(
            base: configuration.environment.apiURL, "GET", ["orders", "track", number],
            timeout: configuration.timeout)
        return try await sendData(urlRequest, authorize: false)
    }

    // MARK: Transport

    private func backendRequest(
        _ method: String, _ path: [String], query: [URLQueryItem] = []
    ) throws -> URLRequest {
        try Self.makeRequest(
            base: configuration.backendURL, method, path, query: query,
            timeout: configuration.timeout)
    }

    private func backendRequest<Body: Encodable>(
        _ method: String, _ path: [String], body: Body
    ) throws -> URLRequest {
        var request = try backendRequest(method, path)
        do {
            request.httpBody = try Self.encoder.encode(body)
        } catch {
            throw ZunoError.invalidRequest("could not encode body: \(error)")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func makeRequest(
        base: URL, _ method: String, _ path: [String], query: [URLQueryItem] = [],
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw ZunoError.invalidRequest("invalid base URL \(base)")
        }
        var segmentCharacters = CharacterSet.urlPathAllowed
        segmentCharacters.remove("/")
        let basePath = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast()) : components.percentEncodedPath
        let encodedPath = path.map {
            $0.addingPercentEncoding(withAllowedCharacters: segmentCharacters) ?? $0
        }
        components.percentEncodedPath = basePath + "/" + encodedPath.joined(separator: "/")
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw ZunoError.invalidRequest("could not build URL for \(path.joined(separator: "/"))")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(ZunoSDKInfo.userAgent, forHTTPHeaderField: "X-Zuno-SDK")
        return request
    }

    private func sendData<T: Decodable>(_ request: URLRequest, authorize: Bool) async throws -> T {
        let (data, _) = try await send(request, authorize: authorize)
        return try Self.decode(DataEnvelope<T>.self, from: data).data
    }

    private func send(_ request: URLRequest, authorize: Bool) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if authorize, let authorizer = configuration.authorizer {
            try await authorizer(&request)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await configuration.urlSession.data(for: request)
        } catch let error as URLError {
            throw ZunoError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ZunoError.decoding("response is not HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.apiError(data: data, response: http)
        }
        return (data, http)
    }

    private static func apiError(data: Data, response: HTTPURLResponse) -> ZunoError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = object?["error"] as? String ?? object?["code"] as? String
        let message = object?["message"] as? String ?? code
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
            .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
        return .api(statusCode: response.statusCode, code: code, message: message, retryAfter: retryAfter)
    }

    private static func required(_ value: String, _ name: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ZunoError.invalidRequest("\(name) is required") }
        return trimmed
    }

    // MARK: Coding

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseDate(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not an RFC 3339 date: \(raw)")
        }
        return decoder
    }()

    /// Go writes RFC 3339 with or without fractional seconds.
    static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ZunoError.decoding(String(describing: error))
        }
    }
}

public enum ZunoSDKInfo {
    public static let version = "0.1.0"
    static let userAgent = "zuno-ios/\(version)"
}

public enum ZunoIdempotencyKey {
    /// A fresh random key suitable for `Idempotency-Key`.
    public static func make() -> String { UUID().uuidString.lowercased() }

    static func validate(_ key: String) throws {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")
        guard (16...128).contains(key.count),
              key.unicodeScalars.allSatisfy({ allowed.contains($0) })
        else {
            throw ZunoError.invalidRequest(
                "idempotency key must be 16–128 characters of A–Z, a–z, 0–9, . _ : -")
        }
    }
}

private struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

private struct CancellationEnvelope: Decodable {
    struct Body: Decodable {
        let orderId: String
        let status: OrderStatus
        let refundPending: Bool
        let refundStatus: String
    }
    let data: Body
    let message: String?
}

private struct MarkReadBody: Encodable {
    let conversationId: String
    let messageIds: [String]
}

private struct MarkReadResult: Decodable {
    let markedCount: Int
}
