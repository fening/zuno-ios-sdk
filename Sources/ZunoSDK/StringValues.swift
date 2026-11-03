import Foundation

/// A string-backed value whose set of cases the server may grow. Unknown
/// values decode instead of failing, so an app built today keeps working
/// when Zuno adds a status or tier tomorrow.
public protocol ZunoStringValue: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible where RawValue == String
{
    init(rawValue: String)
}

extension ZunoStringValue {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ServiceTier: ZunoStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let express = ServiceTier(rawValue: "express")
    public static let standard = ServiceTier(rawValue: "standard")
    /// Held (status `HOLDING`) for about 10 minutes after payment before the
    /// driver search starts.
    public static let waitSave = ServiceTier(rawValue: "wait_save")
}

public struct VehicleRequirement: ZunoStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let standard = VehicleRequirement(rawValue: "standard")
    public static let xl = VehicleRequirement(rawValue: "xl")
}

public struct HandlingAddon: ZunoStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let extraCare = HandlingAddon(rawValue: "extra_care")
}

public struct PackageType: ZunoStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let document = PackageType(rawValue: "document")
    public static let envelope = PackageType(rawValue: "envelope")
    public static let smallBox = PackageType(rawValue: "small_box")
    public static let mediumBox = PackageType(rawValue: "medium_box")
    public static let large = PackageType(rawValue: "large")
    public static let other = PackageType(rawValue: "other")
}

public struct PackageSize: ZunoStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let small = PackageSize(rawValue: "S")
    public static let medium = PackageSize(rawValue: "M")
    public static let large = PackageSize(rawValue: "L")
    public static let extraLarge = PackageSize(rawValue: "XL")
}

public struct BookingMode: ZunoStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The integrator is the sender.
    public static let send = BookingMode(rawValue: "send")
    /// The integrator is arranging collection from someone else.
    public static let receive = BookingMode(rawValue: "receive")
}

public struct OrderStatus: ZunoStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let awaitingPayment = OrderStatus(rawValue: "AWAITING_PAYMENT")
    public static let scheduled = OrderStatus(rawValue: "SCHEDULED")
    public static let holding = OrderStatus(rawValue: "HOLDING")
    public static let pending = OrderStatus(rawValue: "PENDING")
    public static let pendingDriver = OrderStatus(rawValue: "PENDING_DRIVER")
    public static let driverFound = OrderStatus(rawValue: "DRIVER_FOUND")
    public static let driverAssigned = OrderStatus(rawValue: "DRIVER_ASSIGNED")
    public static let accepted = OrderStatus(rawValue: "ACCEPTED")
    public static let arrivingPickup = OrderStatus(rawValue: "ARRIVING_PICKUP")
    public static let arrivedPickup = OrderStatus(rawValue: "ARRIVED_PICKUP")
    public static let pickedUp = OrderStatus(rawValue: "PICKED_UP")
    public static let delivering = OrderStatus(rawValue: "DELIVERING")
    public static let arrivedDelivery = OrderStatus(rawValue: "ARRIVED_DELIVERY")
    public static let delivered = OrderStatus(rawValue: "DELIVERED")
    public static let completed = OrderStatus(rawValue: "COMPLETED")
    public static let cancelled = OrderStatus(rawValue: "CANCELLED")

    /// No further lifecycle change is expected.
    public var isFinal: Bool {
        self == .delivered || self == .completed || self == .cancelled
    }
}

public struct SenderRole: ZunoStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let customer = SenderRole(rawValue: "customer")
    public static let driver = SenderRole(rawValue: "driver")
}
