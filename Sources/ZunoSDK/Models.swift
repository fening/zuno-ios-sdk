import Foundation

// Wire models for the Zuno developer delivery API. Property names are the
// camelCase form of the JSON's snake_case keys; the client's coders convert.
// Fields the API may omit are optional so a missing key never fails a decode.

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct Address: Codable, Hashable, Sendable {
    /// Street address or GhanaPostGPS code shown to the driver.
    public var address: String
    public var latitude: Double
    public var longitude: Double

    public init(address: String, latitude: Double, longitude: Double) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: Quotes

public struct QuoteRequest: Codable, Hashable, Sendable {
    public var pickup: Coordinate
    public var dropoff: Coordinate
    public var serviceTier: ServiceTier
    public var vehicleRequirement: VehicleRequirement
    public var handlingAddons: [HandlingAddon]

    public init(
        pickup: Coordinate,
        dropoff: Coordinate,
        serviceTier: ServiceTier = .standard,
        vehicleRequirement: VehicleRequirement = .standard,
        handlingAddons: [HandlingAddon] = []
    ) {
        self.pickup = pickup
        self.dropoff = dropoff
        self.serviceTier = serviceTier
        self.vehicleRequirement = vehicleRequirement
        self.handlingAddons = handlingAddons
    }
}

public struct DeliveryQuote: Codable, Hashable, Sendable {
    public var serviceTier: ServiceTier
    public var distanceKm: Double
    public var total: Decimal
    public var currency: String
    public var estimatedTimeMinutes: Int
    public var handlingAddons: [HandlingAddon]?
    public var vehicleRequirement: VehicleRequirement
    /// Pass to `CreateOrderRequest.quoteToken` before `expiresAt`.
    public var quoteToken: String
    public var expiresAt: Date
}

// MARK: Orders

public struct PackageDetails: Codable, Hashable, Sendable {
    public var description: String
    public var packageType: PackageType
    /// Must match the tier the quote was priced with.
    public var serviceTier: ServiceTier
    /// Kilograms.
    public var weight: Double
    public var size: PackageSize
    public var quantity: Int
    public var isFragile: Bool?
    public var isPerishable: Bool?
    public var handlingAddons: [HandlingAddon]?
    public var vehicleRequirement: VehicleRequirement?
    /// Notes for the driver.
    public var instructions: String?

    public init(
        description: String,
        packageType: PackageType,
        serviceTier: ServiceTier,
        weight: Double,
        size: PackageSize,
        quantity: Int = 1,
        isFragile: Bool? = nil,
        isPerishable: Bool? = nil,
        handlingAddons: [HandlingAddon]? = nil,
        vehicleRequirement: VehicleRequirement? = nil,
        instructions: String? = nil
    ) {
        self.description = description
        self.packageType = packageType
        self.serviceTier = serviceTier
        self.weight = weight
        self.size = size
        self.quantity = quantity
        self.isFragile = isFragile
        self.isPerishable = isPerishable
        self.handlingAddons = handlingAddons
        self.vehicleRequirement = vehicleRequirement
        self.instructions = instructions
    }
}

public struct CreateOrderRequest: Codable, Hashable, Sendable {
    public var pickupAddress: Address
    public var deliveryAddress: Address
    public var packageDetails: PackageDetails
    public var quoteToken: String
    public var bookingMode: BookingMode?
    /// Future dispatch time; nil dispatches immediately.
    public var scheduledFor: Date?

    public init(
        pickupAddress: Address,
        deliveryAddress: Address,
        packageDetails: PackageDetails,
        quoteToken: String,
        bookingMode: BookingMode? = nil,
        scheduledFor: Date? = nil
    ) {
        self.pickupAddress = pickupAddress
        self.deliveryAddress = deliveryAddress
        self.packageDetails = packageDetails
        self.quoteToken = quoteToken
        self.bookingMode = bookingMode
        self.scheduledFor = scheduledFor
    }
}

public struct Order: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Shareable `KDA-…` number for `trackDelivery(trackingNumber:)`.
    public var trackingNumber: String
    public var merchantId: String?
    public var status: OrderStatus
    public var pickupAddress: Address
    public var deliveryAddress: Address
    public var packageDetails: PackageDetails?
    /// Kilometres.
    public var distance: Double
    public var total: Decimal
    public var currency: String
    /// Minutes.
    public var estimatedTime: Int
    public var bookingMode: BookingMode?
    public var scheduledFor: Date?
    /// When a Wait & Save hold ends and the driver search begins.
    public var dispatchAfter: Date?
    public var paymentStatus: String
    public var createdAt: Date
    public var updatedAt: Date
}

public struct OrderCreation: Hashable, Sendable {
    public var order: Order
    /// True when the idempotency key matched an earlier identical request:
    /// no second delivery or charge was created.
    public var replayed: Bool
}

public struct DriverAssignment: Codable, Hashable, Sendable {
    public var driverId: String
    public var driverName: String?
    /// Short-lived token for `driverContact(orderId:token:)`.
    public var driverContactToken: String?
    /// Short-lived token for `driverAvatar(orderId:token:)`.
    public var driverAvatarToken: String?
    public var driverAvatarExpiresAt: Date?
    /// 0–5; present only when `driverRatingCount` is positive.
    public var driverRatingAverage: Double?
    public var driverRatingCount: Int?
    public var vehicleType: String?
    public var vehicleColor: String?
    public var vehiclePlate: String?
    public var vehicleImageUrl: URL?
    public var assignedAt: Date?
    public var estimatedPickupAt: Date?
}

public struct OrderStatusSnapshot: Codable, Hashable, Sendable {
    public var orderId: String
    public var status: OrderStatus
    public var paymentStatus: String
    public var updatedAt: Date
    /// Increases with every committed lifecycle change; compare to discard
    /// stale webhook events or poll results.
    public var sequence: Int64
    public var assignment: DriverAssignment?
}

public struct DriverContact: Codable, Hashable, Sendable {
    public var driverPhone: String
    public var expiresAt: Date
}

public struct DriverAvatar: Hashable, Sendable {
    public var data: Data
    /// `image/jpeg`, `image/png` or `image/webp`.
    public var contentType: String
}

public struct Cancellation: Hashable, Sendable {
    public var orderId: String
    public var status: OrderStatus
    /// True while a funded fare is being released back to the tenant balance.
    public var refundPending: Bool
    public var refundStatus: String
    public var message: String
}

// MARK: Tracking

public struct DeliveryTracking: Codable, Hashable, Sendable {
    public var trackingNumber: String
    public var status: OrderStatus
    /// Minutes remaining, when known.
    public var estimatedTime: Int?
    public var scheduledFor: Date?
    public var updatedAt: Date
}

// MARK: Addresses

public struct DigitalAddress: Codable, Hashable, Sendable {
    /// GhanaPostGPS code, for example `GA-183-9124`.
    public var code: String?
    public var area: String?
    public var district: String?
    public var region: String?
    public var postCode: String?
    public var street: String?
    public var latitude: Double?
    public var longitude: Double?
}

// MARK: Messaging

public struct ChatMessage: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// Pass back to `markMessagesRead`.
    public var conversationId: String
    public var orderId: String
    /// Strictly increasing within the conversation; use as the `after` cursor.
    public var sequence: Int64
    public var body: String
    public var senderRole: SenderRole
    public var status: String
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, conversationId, orderId, body, senderRole, status, createdAt
        case sequence = "messageSequence"
    }
}

public struct ChatMessagePage: Codable, Hashable, Sendable {
    public var conversationId: String?
    public var messages: [ChatMessage]
    public var hasMore: Bool
    /// Pass as `after` to fetch the next page.
    public var nextAfter: Int64?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        // Go encodes an empty slice as null.
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        nextAfter = try container.decodeIfPresent(Int64.self, forKey: .nextAfter)
    }
}
