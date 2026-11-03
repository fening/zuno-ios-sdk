import Foundation
import XCTest
@testable import ZunoSDK

final class ZunoClientTests: XCTestCase {
    private let backend = URL(string: "https://partner.example.com/zuno")!
    private let orderId = "6f1c1f9e-6c1a-4b7e-9a51-2b0f3c9d1e11"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func client(authorizer: ZunoRequestAuthorizer? = nil) -> ZunoClient {
        ZunoClient(configuration: ZunoConfiguration(
            backendURL: backend, environment: .sandbox, authorizer: authorizer,
            urlSession: StubURLProtocol.session()))
    }

    private static let orderJSON = """
    {"data":{"id":"6f1c1f9e-6c1a-4b7e-9a51-2b0f3c9d1e11","tracking_number":"KDA-24A7E3D1904B8F76C2A1",
    "status":"PENDING","pickup_address":{"address":"GA-183-9124","latitude":5.556,"longitude":-0.182},
    "delivery_address":{"address":"GA-492-0000","latitude":5.6052,"longitude":-0.1668},
    "package_details":{"description":"Documents","package_type":"document","service_tier":"standard",
    "weight":0.5,"size":"S","quantity":1},"distance":6.2,"total":32.50,"currency":"GHS","estimated_time":24,
    "payment_status":"PAID","created_at":"2026-11-02T10:00:00.123456Z","updated_at":"2026-11-02T10:00:01Z"}}
    """

    func testQuoteSendsSnakeCaseBodyToBackendAndDecodesEnvelope() async throws {
        StubURLProtocol.enqueue(.json(200, """
        {"data":{"service_tier":"express","distance_km":6.2,"total":41.25,"currency":"GHS",
        "estimated_time_minutes":18,"vehicle_requirement":"standard","quote_token":"qt_123",
        "expires_at":"2026-11-02T10:15:00Z"}}
        """))

        let quote = try await client().createQuote(QuoteRequest(
            pickup: Coordinate(latitude: 5.556, longitude: -0.182),
            dropoff: Coordinate(latitude: 5.6052, longitude: -0.1668),
            serviceTier: .express))

        XCTAssertEqual(quote.serviceTier, .express)
        XCTAssertEqual(quote.total, Decimal(string: "41.25"))
        XCTAssertEqual(quote.quoteToken, "qt_123")
        XCTAssertEqual(quote.expiresAt, ISO8601DateFormatter().date(from: "2026-11-02T10:15:00Z"))

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://partner.example.com/zuno/public/quotes")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
        let body = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(body["service_tier"] as? String, "express")
        XCTAssertEqual(body["vehicle_requirement"] as? String, "standard")
        XCTAssertEqual((body["pickup"] as? [String: Double])?["latitude"], 5.556)
    }

    func testAuthorizerRunsForBackendCalls() async throws {
        StubURLProtocol.enqueue(.json(200, Self.orderJSON))
        _ = try await client(authorizer: { request in
            request.setValue("Bearer user-session", forHTTPHeaderField: "Authorization")
        }).order(id: orderId)

        XCTAssertEqual(
            StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer user-session")
    }

    func testCreateOrderSendsIdempotencyKeyAndReportsReplay() async throws {
        StubURLProtocol.enqueue(
            .json(201, Self.orderJSON),
            .json(200, Self.orderJSON, headers: ["Idempotent-Replayed": "true"]))
        let request = CreateOrderRequest(
            pickupAddress: Address(address: "GA-183-9124", latitude: 5.556, longitude: -0.182),
            deliveryAddress: Address(address: "GA-492-0000", latitude: 5.6052, longitude: -0.1668),
            packageDetails: PackageDetails(
                description: "Documents", packageType: .document, serviceTier: .standard,
                weight: 0.5, size: .small),
            quoteToken: "qt_123",
            scheduledFor: ISO8601DateFormatter().date(from: "2027-01-15T14:30:00Z"))
        let key = ZunoIdempotencyKey.make()

        let first = try await client().createOrder(request, idempotencyKey: key)
        let retry = try await client().createOrder(request, idempotencyKey: key)

        XCTAssertFalse(first.replayed)
        XCTAssertTrue(retry.replayed)
        XCTAssertEqual(first.order.status, .pending)
        XCTAssertEqual(first.order.trackingNumber, "KDA-24A7E3D1904B8F76C2A1")
        XCTAssertEqual(first.order.packageDetails?.size, .small)
        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Idempotency-Key"), key)
        XCTAssertEqual(sent.url?.path, "/zuno/public/orders")
        let body = try XCTUnwrap(sent.jsonBody)
        XCTAssertEqual(body["quote_token"] as? String, "qt_123")
        XCTAssertEqual(body["scheduled_for"] as? String, "2027-01-15T14:30:00Z")
        XCTAssertNil(body["booking_mode"])
        XCTAssertEqual((body["package_details"] as? [String: Any])?["package_type"] as? String, "document")
    }

    func testCreateOrderRejectsBadIdempotencyKeyWithoutSending() async {
        do {
            _ = try await client().createOrder(
                CreateOrderRequest(
                    pickupAddress: Address(address: "a", latitude: 0, longitude: 0),
                    deliveryAddress: Address(address: "b", latitude: 0, longitude: 0),
                    packageDetails: PackageDetails(
                        description: "x", packageType: .other, serviceTier: .standard,
                        weight: 1, size: .medium),
                    quoteToken: "qt"),
                idempotencyKey: "short")
            XCTFail("expected invalidRequest")
        } catch {
            guard case ZunoError.invalidRequest = error else { return XCTFail("got \(error)") }
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testOrderStatusDecodesAssignmentAndUnknownStatus() async throws {
        StubURLProtocol.enqueue(.json(200, """
        {"data":{"order_id":"\(orderId)","status":"SOME_FUTURE_STATUS","payment_status":"PAID",
        "updated_at":"2026-11-02T10:05:00Z","sequence":7,"assignment":{"driver_id":"d1","driver_name":"Ama",
        "driver_contact_token":"ct","driver_avatar_token":"at","driver_rating_average":4.86,
        "driver_rating_count":120,"vehicle_plate":"GR-1234-24",
        "vehicle_image_url":"https://img.zunodelivery.com/v/1.png","assigned_at":"2026-11-02T10:04:00Z"}}}
        """))

        let snapshot = try await client().orderStatus(id: orderId)

        XCTAssertEqual(snapshot.status.rawValue, "SOME_FUTURE_STATUS")
        XCTAssertFalse(snapshot.status.isFinal)
        XCTAssertEqual(snapshot.sequence, 7)
        XCTAssertEqual(snapshot.assignment?.driverName, "Ama")
        XCTAssertEqual(snapshot.assignment?.driverRatingCount, 120)
        XCTAssertEqual(snapshot.assignment?.vehicleImageUrl?.host, "img.zunodelivery.com")
        XCTAssertEqual(
            StubURLProtocol.requests.first?.url?.path, "/zuno/orders/\(orderId)/status")
    }

    func testApiErrorCarriesCodeAndRetryAfter() async {
        StubURLProtocol.enqueue(.json(429, #"{"error":"rate_limited"}"#, headers: ["Retry-After": "12"]))
        do {
            _ = try await client().sendMessage(orderId: orderId, body: "  On my way down  ")
            XCTFail("expected error")
        } catch let error as ZunoError {
            XCTAssertEqual(error, .api(statusCode: 429, code: "rate_limited", message: "rate_limited", retryAfter: 12))
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("got \(error)")
        }
        let sent = StubURLProtocol.requests.first
        XCTAssertEqual(sent?.jsonBody?["body"] as? String, "On my way down")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Idempotency-Key")?.count, 36)
    }

    func testMessagesDecodeWireShape() async throws {
        StubURLProtocol.enqueue(.json(200, """
        {"data":{"conversation_id":"c1","messages":[{"id":"m1","conversation_id":"c1","order_id":"\(orderId)",
        "message_sequence":3,"body":"Here","sender_role":"driver","status":"delivered",
        "created_at":"2026-11-02T10:06:00.5Z"}],"has_more":true,"next_after":3}}
        """), .json(200, #"{"data":{"marked_count":1}}"#))

        let page = try await client().messages(orderId: orderId, after: 2, limit: 50)
        let marked = try await client().markMessagesRead(
            orderId: orderId, conversationId: "c1", messageIds: ["m1"])

        XCTAssertEqual(page.messages.first?.sequence, 3)
        XCTAssertEqual(page.messages.first?.senderRole, .driver)
        XCTAssertEqual(page.nextAfter, 3)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(marked, 1)
        let list = StubURLProtocol.requests[0].url
        XCTAssertEqual(list?.query, "after=2&limit=50")
        let read = StubURLProtocol.requests[1]
        XCTAssertEqual(read.url?.path, "/zuno/public/orders/\(orderId)/messages/read")
        XCTAssertEqual(read.jsonBody?["conversation_id"] as? String, "c1")
        XCTAssertEqual(read.jsonBody?["message_ids"] as? [String], ["m1"])
    }

    func testNullMessagesDecodeAsEmpty() async throws {
        StubURLProtocol.enqueue(.json(200, #"{"data":{"messages":null,"has_more":false}}"#))
        let page = try await client().messages(orderId: orderId)
        XCTAssertEqual(page.messages, [])
    }

    func testMessagesCanPageASpecificAssignmentConversation() async throws {
        StubURLProtocol.enqueue(.json(200, #"{"data":{"conversation_id":"c1","messages":[],"has_more":false}}"#))
        _ = try await client().messages(orderId: orderId, after: 3, limit: 20, conversationId: "c1")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.query, "after=3&limit=20&conversation_id=c1")
    }

    func testCancelOrderFlattensEnvelope() async throws {
        StubURLProtocol.enqueue(.json(200, """
        {"message":"Order cancelled","data":{"order_id":"\(orderId)","status":"CANCELLED",
        "refund_pending":true,"refund_status":"PENDING"}}
        """))
        let cancellation = try await client().cancelOrder(id: orderId)
        XCTAssertEqual(cancellation.status, .cancelled)
        XCTAssertTrue(cancellation.refundPending)
        XCTAssertEqual(cancellation.message, "Order cancelled")
        XCTAssertEqual(StubURLProtocol.requests.first?.httpMethod, "POST")
    }

    func testDriverAvatarSendsTokenHeaderAndReturnsBytes() async throws {
        StubURLProtocol.enqueue(StubURLProtocol.Response(
            status: 200, headers: ["Content-Type": "image/png"], body: Data([0x89, 0x50])))
        let avatar = try await client().driverAvatar(orderId: orderId, token: "avatar-token")
        XCTAssertEqual(avatar.data, Data([0x89, 0x50]))
        XCTAssertEqual(avatar.contentType, "image/png")
        XCTAssertEqual(
            StubURLProtocol.requests.first?.value(forHTTPHeaderField: "X-Zuno-Driver-Avatar-Token"),
            "avatar-token")
    }

    func testGhanaPostQueriesGoToBackend() async throws {
        StubURLProtocol.enqueue(
            .json(200, #"{"data":{"code":"GA-183-9124","latitude":5.556,"longitude":-0.182}}"#),
            .json(200, #"{"data":{"code":"GA-183-9124","region":"Greater Accra"}}"#))
        let resolved = try await client().resolveGhanaPostAddress(code: "GA-183-9124")
        let encoded = try await client().ghanaPostAddress(latitude: 5.556, longitude: -0.182)
        XCTAssertEqual(resolved.latitude, 5.556)
        XCTAssertEqual(encoded.region, "Greater Accra")
        XCTAssertEqual(StubURLProtocol.requests[0].url?.query, "code=GA-183-9124")
        XCTAssertEqual(StubURLProtocol.requests[1].url?.query, "lat=5.556&lng=-0.182")
    }

    func testTrackingGoesDirectlyToZunoWithoutAuthorizer() async throws {
        StubURLProtocol.enqueue(.json(200, """
        {"data":{"tracking_number":"KDA-24A7E3D1904B8F76C2A1","status":"DELIVERING",
        "estimated_time":6,"updated_at":"2026-11-02T10:20:00Z"}}
        """))
        let tracking = try await client(authorizer: { request in
            request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        }).trackDelivery(trackingNumber: "kda-24a7e3d1904b8f76c2a1")

        XCTAssertEqual(tracking.status, .delivering)
        XCTAssertEqual(tracking.estimatedTime, 6)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api-gateway-staging-6b3d.up.railway.app/api/orders/track/KDA-24A7E3D1904B8F76C2A1")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testStatusUpdatesYieldNewSequencesAndFinishAtFinalStatus() async throws {
        func status(_ value: String, _ sequence: Int) -> StubURLProtocol.Response {
            .json(200, """
            {"data":{"order_id":"\(orderId)","status":"\(value)","payment_status":"PAID",
            "updated_at":"2026-11-02T10:05:00Z","sequence":\(sequence)}}
            """)
        }
        StubURLProtocol.enqueue(
            status("PENDING", 1),
            status("PENDING", 1),
            .json(503, #"{"error":"unavailable"}"#),
            status("PICKED_UP", 4),
            status("DELIVERED", 6))

        var seen: [OrderStatus] = []
        for try await snapshot in client().orderStatusUpdates(id: orderId, every: 0) {
            seen.append(snapshot.status)
        }

        XCTAssertEqual(seen, [.pending, .pickedUp, .delivered])
        XCTAssertEqual(StubURLProtocol.requests.count, 5)
    }

    func testDateParsingAcceptsGoFormats() {
        XCTAssertNotNil(ZunoClient.parseDate("2026-11-02T10:00:00Z"))
        XCTAssertNotNil(ZunoClient.parseDate("2026-11-02T10:00:00.123456789Z"))
        XCTAssertNotNil(ZunoClient.parseDate("2026-11-02T10:00:00+00:00"))
        XCTAssertNil(ZunoClient.parseDate("yesterday"))
    }

    func testStaleFinalStatusDoesNotEndPolling() async throws {
        func status(_ value: String, _ sequence: Int) -> StubURLProtocol.Response {
            .json(200, """
            {"data":{"order_id":"\(orderId)","status":"\(value)","payment_status":"PAID",
            "updated_at":"2026-11-02T10:05:00Z","sequence":\(sequence)}}
            """)
        }
        StubURLProtocol.enqueue(status("DELIVERING", 7), status("CANCELLED", 6), status("DELIVERED", 8))
        var seen: [OrderStatus] = []
        for try await snapshot in client().orderStatusUpdates(id: orderId, every: 0) {
            seen.append(snapshot.status)
        }
        XCTAssertEqual(seen, [.delivering, .delivered])
        XCTAssertEqual(StubURLProtocol.requests.count, 3)
    }

    func testMessageLimitCountsUnicodeScalarsLikeTheServer() async {
        // Each visible flag has two Unicode scalars; Go counts runes, not graphemes.
        do {
            _ = try await client().sendMessage(orderId: orderId, body: String(repeating: "🇬🇭", count: 1001))
            XCTFail("expected invalidRequest")
        } catch {
            guard case ZunoError.invalidRequest = error else { return XCTFail("got \(error)") }
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testInvalidPollingIntervalsFailWithoutSending() async {
        for interval in [TimeInterval.nan, .infinity, .greatestFiniteMagnitude] {
            // A nonretryable response ensures the old implementation fails safely
            // rather than reaching its trapping floating-point-to-UInt64 conversion.
            StubURLProtocol.enqueue(.json(404, #"{"error":"not_found"}"#))
            do {
                for try await _ in client().orderStatusUpdates(id: orderId, every: interval) {}
                XCTFail("expected invalidRequest")
            } catch {
                guard case ZunoError.invalidRequest = error else {
                    XCTFail("got \(error)")
                    continue
                }
            }
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}
