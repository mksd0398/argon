import Foundation

// Typed models of contract/customer (Customer Account API 2026-10). Dates are ISO-8601 strings and statuses Shopify's enum
// values (PAID, FULFILLED, ...); the UI formats both.

/// `CustomerAddress` fragment. `formatted` is the address as display lines.
struct CustomerAddress: Decodable, Equatable, Sendable {
    let id: String
    let firstName: String?
    let lastName: String?
    let company: String?
    let address1: String?
    let address2: String?
    let city: String?
    let province: String?
    let zoneCode: String?
    let zip: String?
    let country: String?
    let countryCode: String?
    let phoneNumber: String?
    let formatted: [String]
    /// Set by `CustomerAccountAPI.addresses`: the customer's default address.
    var isDefault = false

    private enum CodingKeys: String, CodingKey {
        case id, firstName, lastName, company, address1, address2, city, province, zoneCode, zip, country, countryCode
        case phoneNumber, formatted
    }
}

struct CustomerEmailAddress: Decodable, Equatable, Sendable {
    let emailAddress: String?
    /// SUBSCRIBED, NOT_SUBSCRIBED, PENDING, UNSUBSCRIBED, ...
    let marketingState: String?
}

/// The signed-in customer. CustomerUpdate answers with the names only: the rest is nil there.
struct Customer: Equatable, Sendable {
    let id: String
    let firstName: String?
    let lastName: String?
    let displayName: String
    var imageUrl: String? = nil
    var emailAddress: CustomerEmailAddress? = nil
    var phone: String? = nil
    var defaultAddress: CustomerAddress? = nil

    /// "Ada Lovelace"; empty when neither name is set.
    var name: String { [firstName, lastName].compactMap { $0 }.joined(separator: " ") }

    var email: String? { emailAddress?.emailAddress }
}

extension Customer: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, firstName, lastName, displayName, imageUrl, emailAddress, phoneNumber, defaultAddress
    }

    private struct Phone: Decodable {
        let phoneNumber: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            firstName: c.decodeIfPresent(String.self, forKey: .firstName),
            lastName: c.decodeIfPresent(String.self, forKey: .lastName),
            displayName: c.decodeIfPresent(String.self, forKey: .displayName) ?? "",
            imageUrl: c.decodeIfPresent(String.self, forKey: .imageUrl),
            emailAddress: c.decodeIfPresent(CustomerEmailAddress.self, forKey: .emailAddress),
            phone: c.decodeIfPresent(Phone.self, forKey: .phoneNumber)?.phoneNumber,
            defaultAddress: c.decodeIfPresent(CustomerAddress.self, forKey: .defaultAddress)
        )
    }
}

private struct LineImage: Decodable {
    let image: Img?
}

/// An order in the customer's list (Orders).
struct OrderSummary: Equatable, Sendable {
    let id: String
    let name: String
    var number: Int? = nil
    let processedAt: String
    let financialStatus: String?
    var fulfillmentStatus: String? = nil
    var cancelledAt: String? = nil
    let total: Money
    /// The images of the first three lines (those that have one).
    var images: [Img] = []
}

extension OrderSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, number, processedAt, financialStatus, fulfillmentStatus, cancelledAt, totalPrice, lineItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lines: [LineImage] = try c.nodes(.lineItems)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            name: c.decode(String.self, forKey: .name),
            number: c.decodeIfPresent(Int.self, forKey: .number),
            processedAt: c.decode(String.self, forKey: .processedAt),
            financialStatus: c.decodeIfPresent(String.self, forKey: .financialStatus),
            fulfillmentStatus: c.decodeIfPresent(String.self, forKey: .fulfillmentStatus),
            cancelledAt: c.decodeIfPresent(String.self, forKey: .cancelledAt),
            total: c.decode(Money.self, forKey: .totalPrice),
            images: lines.compactMap { $0.image }
        )
    }
}

/// A discount on an order: an amount off, a percentage off, or a value type this app doesn't know (its `__typename`).
enum DiscountValue: Equatable, Sendable {
    case amount(Money)
    case percentage(Double)
    case other(String)
}

extension DiscountValue: Decodable {
    private enum Keys: String, CodingKey {
        case typename = "__typename"
        case percentage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .typename) {
        case "MoneyV2": self = try .amount(Money(from: decoder))
        case "PricingPercentageValue": self = try .percentage(c.decode(Double.self, forKey: .percentage))
        case let typename: self = .other(typename)
        }
    }
}

struct OrderLine: Equatable, Sendable {
    var id: String? = nil
    let title: String
    let variantTitle: String?
    let quantity: Int
    let image: Img?
    var productId: String? = nil
    var variantId: String? = nil
    /// One item's price.
    var price: Money? = nil
    /// The line's total.
    let total: Money?
}

extension OrderLine: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, variantTitle, quantity, image, productId, variantId, price, totalPrice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decodeIfPresent(String.self, forKey: .id),
            title: c.decode(String.self, forKey: .title),
            variantTitle: c.decodeIfPresent(String.self, forKey: .variantTitle),
            quantity: c.decode(Int.self, forKey: .quantity),
            image: c.decodeIfPresent(Img.self, forKey: .image),
            productId: c.decodeIfPresent(String.self, forKey: .productId),
            variantId: c.decodeIfPresent(String.self, forKey: .variantId),
            price: c.decodeIfPresent(Money.self, forKey: .price),
            total: c.decodeIfPresent(Money.self, forKey: .totalPrice)
        )
    }
}

struct TrackingInfo: Decodable, Equatable, Sendable {
    let company: String?
    let number: String?
    let url: String?
}

/// How many of order line `lineItemId` a fulfillment carries.
struct FulfillmentLine: Equatable, Sendable {
    let lineItemId: String
    let quantity: Int
}

/// A shipment: its status (SUCCESS once fulfilled), tracking, and the order lines it carries.
struct Fulfillment: Equatable, Sendable {
    let id: String
    let status: String?
    let createdAt: String?
    let estimatedDeliveryAt: String?
    let latestShipmentStatus: String?
    let tracking: [TrackingInfo]
    let lines: [FulfillmentLine]
}

extension Fulfillment: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, status, createdAt, estimatedDeliveryAt, latestShipmentStatus, trackingInformation, fulfillmentLineItems
    }

    private struct LineRef: Decodable {
        struct Item: Decodable {
            let id: String
        }

        let quantity: Int
        let lineItem: Item
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let refs: [LineRef] = try c.nodes(.fulfillmentLineItems)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            status: c.decodeIfPresent(String.self, forKey: .status),
            createdAt: c.decodeIfPresent(String.self, forKey: .createdAt),
            estimatedDeliveryAt: c.decodeIfPresent(String.self, forKey: .estimatedDeliveryAt),
            latestShipmentStatus: c.decodeIfPresent(String.self, forKey: .latestShipmentStatus),
            tracking: c.decodeIfPresent([TrackingInfo].self, forKey: .trackingInformation) ?? [],
            lines: refs.map { FulfillmentLine(lineItemId: $0.lineItem.id, quantity: $0.quantity) }
        )
    }
}

/// The Order query's order.
struct Order: Equatable, Sendable {
    let id: String
    let name: String
    let number: Int?
    let confirmationNumber: String?
    let processedAt: String
    let statusPageUrl: String?
    let financialStatus: String?
    let fulfillmentStatus: String?
    let cancelledAt: String?
    let cancelReason: String?
    let shippingAddress: CustomerAddress?
    let billingAddress: CustomerAddress?
    let subtotal: Money?
    let totalShipping: Money?
    let totalTax: Money?
    let total: Money
    let totalRefunded: Money?
    let discounts: [DiscountValue]
    let lines: [OrderLine]
    /// Empty until something has shipped.
    let fulfillments: [Fulfillment]
}

extension Order: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, number, confirmationNumber, processedAt, statusPageUrl, financialStatus, fulfillmentStatus, cancelledAt
        case cancelReason, shippingAddress, billingAddress, subtotal, totalShipping, totalTax, totalPrice, totalRefunded
        case discountApplications, lineItems, fulfillments
    }

    private struct Application: Decodable {
        let value: DiscountValue
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let applications: [Application] = try c.nodes(.discountApplications)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            name: c.decode(String.self, forKey: .name),
            number: c.decodeIfPresent(Int.self, forKey: .number),
            confirmationNumber: c.decodeIfPresent(String.self, forKey: .confirmationNumber),
            processedAt: c.decode(String.self, forKey: .processedAt),
            statusPageUrl: c.decodeIfPresent(String.self, forKey: .statusPageUrl),
            financialStatus: c.decodeIfPresent(String.self, forKey: .financialStatus),
            fulfillmentStatus: c.decodeIfPresent(String.self, forKey: .fulfillmentStatus),
            cancelledAt: c.decodeIfPresent(String.self, forKey: .cancelledAt),
            cancelReason: c.decodeIfPresent(String.self, forKey: .cancelReason),
            shippingAddress: c.decodeIfPresent(CustomerAddress.self, forKey: .shippingAddress),
            billingAddress: c.decodeIfPresent(CustomerAddress.self, forKey: .billingAddress),
            subtotal: c.decodeIfPresent(Money.self, forKey: .subtotal),
            totalShipping: c.decodeIfPresent(Money.self, forKey: .totalShipping),
            totalTax: c.decodeIfPresent(Money.self, forKey: .totalTax),
            total: c.decode(Money.self, forKey: .totalPrice),
            totalRefunded: c.decodeIfPresent(Money.self, forKey: .totalRefunded),
            discounts: applications.map { $0.value },
            lines: c.nodes(.lineItems),
            fulfillments: c.nodes(.fulfillments)
        )
    }
}

struct ReturnReason: Decodable, Equatable, Sendable {
    let id: String
    let handle: String
    let name: String
}

/// An order line that can still be returned, up to `quantity`, and the reasons to offer (their `id` goes in the request).
struct ReturnableItem: Equatable, Sendable {
    let lineItemId: String
    let title: String
    let image: Img?
    let quantity: Int
    let reasons: [ReturnReason]
}

extension ReturnableItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case quantity, lineItem
    }

    private enum LineKeys: String, CodingKey {
        case id, title, image, suggestedReturnReasonDefinitions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let line = try c.nestedContainer(keyedBy: LineKeys.self, forKey: .lineItem)
        try self.init(
            lineItemId: line.decode(String.self, forKey: .id),
            title: line.decode(String.self, forKey: .title),
            image: line.decodeIfPresent(Img.self, forKey: .image),
            quantity: c.decode(Int.self, forKey: .quantity),
            reasons: line.nodes(.suggestedReturnReasonDefinitions)
        )
    }
}

/// A return request. `status`: REQUESTED, OPEN, CLOSED, DECLINED, ...
struct OrderReturn: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let status: String
    var createdAt: String? = nil
}

/// What of an order can be returned, and the returns already requested.
struct ReturnOptions: Equatable, Sendable {
    let orderId: String
    let returnableItems: [ReturnableItem]
    let returns: [OrderReturn]
}

extension ReturnOptions: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, returnInformation, returns
    }

    private enum InformationKeys: String, CodingKey {
        case returnableLineItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let information = try c.nestedContainer(keyedBy: InformationKeys.self, forKey: .returnInformation)
        try self.init(
            orderId: c.decode(String.self, forKey: .id),
            returnableItems: information.nodes(.returnableLineItems),
            returns: c.nodes(.returns)
        )
    }
}

// MARK: - Inputs

/// An address to create, or the fields to change on one (nil fields are left out). `zoneCode` is the province or state code.
struct CustomerAddressInput: Encodable, Equatable, Sendable {
    var firstName: String? = nil
    var lastName: String? = nil
    var company: String? = nil
    var address1: String? = nil
    var address2: String? = nil
    var city: String? = nil
    var zoneCode: String? = nil
    var zip: String? = nil
    var countryCode: String? = nil
    var phoneNumber: String? = nil
}

/// A line to return: `returnReasonDefinitionId` is one of the line's `ReturnableItem.reasons`.
struct ReturnLineInput: Encodable, Equatable, Sendable {
    let lineItemId: String
    let quantity: Int
    var returnReasonDefinitionId: String? = nil
    var customerNote: String? = nil
}
