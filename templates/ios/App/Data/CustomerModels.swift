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
    /// The titles of the first three lines.
    var titles: [String] = []
    /// How many items the order holds, over all its lines.
    var itemCount: Int? = nil
    /// The newest shipment's status (IN_TRANSIT, OUT_FOR_DELIVERY, DELIVERED, ...); nil until something has shipped.
    var latestShipmentStatus: String? = nil
    /// When the newest shipment should arrive.
    var estimatedDeliveryAt: String? = nil
    /// When the newest shipment was delivered; nil until it was.
    var deliveredAt: String? = nil
}

extension OrderSummary: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, number, processedAt, financialStatus, fulfillmentStatus, cancelledAt, totalPrice, lineItems
        case fulfillments
    }

    private struct Line: Decodable {
        let title: String?
        let quantity: Int?
        let image: Img?
    }

    private struct Shipment: Decodable {
        let latestShipmentStatus: String?
        let estimatedDeliveryAt: String?
        let updatedAt: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lines: [Line] = try c.nodes(.lineItems)
        let shipments: [Shipment] = try c.nodes(.fulfillments)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            name: c.decode(String.self, forKey: .name),
            number: c.decodeIfPresent(Int.self, forKey: .number),
            processedAt: c.decode(String.self, forKey: .processedAt),
            financialStatus: c.decodeIfPresent(String.self, forKey: .financialStatus),
            fulfillmentStatus: c.decodeIfPresent(String.self, forKey: .fulfillmentStatus),
            cancelledAt: c.decodeIfPresent(String.self, forKey: .cancelledAt),
            total: c.decode(Money.self, forKey: .totalPrice),
            images: lines.prefix(3).compactMap { $0.image },
            titles: lines.prefix(3).compactMap { $0.title },
            // ponytail: sums the first 50 lines (Orders.graphql), so an order of more lines undercounts. Upgrade: page lineItems.
            itemCount: lines.reduce(0) { $0 + ($1.quantity ?? 0) },
            latestShipmentStatus: shipments.first?.latestShipmentStatus,
            estimatedDeliveryAt: shipments.first?.estimatedDeliveryAt,
            deliveredAt: shipments.first.flatMap { $0.latestShipmentStatus == "DELIVERED" ? $0.updatedAt : nil }
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
    var sku: String? = nil
    /// How many of the line can still be refunded.
    var refundableQuantity: Int? = nil
    /// The discounts taken off the line.
    var totalDiscount: Money? = nil
}

extension OrderLine: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, variantTitle, quantity, image, productId, variantId, price, totalPrice, sku, refundableQuantity
        case totalDiscount
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
            total: c.decodeIfPresent(Money.self, forKey: .totalPrice),
            sku: c.decodeIfPresent(String.self, forKey: .sku),
            refundableQuantity: c.decodeIfPresent(Int.self, forKey: .refundableQuantity),
            totalDiscount: c.decodeIfPresent(Money.self, forKey: .totalDiscount)
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

/// A step of a shipment's journey. `status`: CONFIRMED, IN_TRANSIT, OUT_FOR_DELIVERY, DELIVERED, ...
struct FulfillmentEvent: Decodable, Equatable, Sendable {
    let status: String
    let happenedAt: String?
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
    /// Collected in store rather than shipped.
    var isPickedUp = false
    /// The shipment's journey, in the order the API lists it.
    var events: [FulfillmentEvent] = []
}

extension Fulfillment: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, status, createdAt, estimatedDeliveryAt, latestShipmentStatus, trackingInformation, fulfillmentLineItems
        case isPickedUp, events
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
            lines: refs.map { FulfillmentLine(lineItemId: $0.lineItem.id, quantity: $0.quantity) },
            isPickedUp: c.decodeIfPresent(Bool.self, forKey: .isPickedUp) ?? false,
            events: c.nodes(.events)
        )
    }
}

/// The delivery method the shopper chose, and what it cost before discounts.
struct OrderShippingLine: Decodable, Equatable, Sendable {
    let title: String?
    let originalPrice: Money?
}

/// When an order on payment terms is due ("Net 30").
struct PaymentTerms: Decodable, Equatable, Sendable {
    let paymentTermsName: String?
    let nextDueAt: String?
    let overdue: Bool?
}

/// What of an order is paid. `paymentCollectionUrl` is where the customer pays what is outstanding.
struct OrderPaymentInformation: Decodable, Equatable, Sendable {
    let paymentStatus: String?
    let totalPaidAmount: Money?
    let totalOutstandingAmount: Money?
    let paymentCollectionUrl: String?
    let paymentTerms: PaymentTerms?
}

/// A payment or refund on an order. `kind`: SALE, REFUND, ...; `type`: CARD, GIFT_CARD, BANK, ... `cardBrand` and `last4` are
/// set for a card; `giftCardLast4` for a gift card.
struct OrderTransaction: Equatable, Sendable {
    let id: String
    var kind: String? = nil
    var status: String? = nil
    var type: String? = nil
    var processedAt: String? = nil
    var amount: Money? = nil
    var cardBrand: String? = nil
    var last4: String? = nil
    var giftCardLast4: String? = nil
}

extension OrderTransaction: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, status, type, processedAt, transactionAmount, paymentDetails, giftCardDetails
    }

    private struct Amount: Decodable {
        let presentmentMoney: Money?
    }

    // CardPaymentDetails; any other payment details type has neither field
    private struct Details: Decodable {
        let cardBrand: String?
        let last4: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let card = try c.decodeIfPresent(Details.self, forKey: .paymentDetails)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            kind: c.decodeIfPresent(String.self, forKey: .kind),
            status: c.decodeIfPresent(String.self, forKey: .status),
            type: c.decodeIfPresent(String.self, forKey: .type),
            processedAt: c.decodeIfPresent(String.self, forKey: .processedAt),
            amount: c.decodeIfPresent(Amount.self, forKey: .transactionAmount)?.presentmentMoney,
            cardBrand: card?.cardBrand,
            last4: card?.last4,
            giftCardLast4: c.decodeIfPresent(Details.self, forKey: .giftCardDetails)?.last4
        )
    }
}

/// Money given back on an order. `returnName` names the return it settled ("#1004-R1"), when it settled one.
struct OrderRefund: Decodable, Equatable, Sendable {
    let id: String
    let createdAt: String?
    let returnName: String?
    let totalRefunded: Money?
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
    /// Changed after it was placed.
    var edited = false
    var requiresShipping = true
    var note: String? = nil
    /// A B2B buyer's purchase order number.
    var poNumber: String? = nil
    /// The company and location the order was placed for; nil for a retail order.
    var purchasingCompany: PurchasingCompany? = nil
    var shippingLine: OrderShippingLine? = nil
    var paymentInformation: OrderPaymentInformation? = nil
    var transactions: [OrderTransaction] = []
    var refunds: [OrderRefund] = []
    var returns: [OrderReturn] = []
    /// Whether something can still be returned (`CustomerAccountAPI.returnOptions` says what).
    var hasReturnableItems = false
}

extension Order: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, number, confirmationNumber, processedAt, statusPageUrl, financialStatus, fulfillmentStatus, cancelledAt
        case cancelReason, shippingAddress, billingAddress, subtotal, totalShipping, totalTax, totalPrice, totalRefunded
        case discountApplications, lineItems, fulfillments
        case edited, requiresShipping, note, poNumber, purchasingEntity, shippingLine, paymentInformation, transactions
        case refunds, returns, returnInformation
    }

    private struct Application: Decodable {
        let value: DiscountValue
    }

    /// `purchasingEntity`: a PurchasingCompany has both parts; a Customer (a retail order) neither.
    private struct Purchaser: Decodable {
        let company: Company?
        let location: CompanyLocation?
    }

    private struct ReturnInformation: Decodable {
        struct Returnable: Decodable {
            let quantity: Int
        }

        let returnableLineItems: Nodes<Returnable>
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let applications: [Application] = try c.nodes(.discountApplications)
        let purchaser = try c.decodeIfPresent(Purchaser.self, forKey: .purchasingEntity)
        var purchasingCompany: PurchasingCompany? = nil
        if let company = purchaser?.company, let location = purchaser?.location {
            purchasingCompany = PurchasingCompany(company: company, location: location)
        }
        let returnable = try c.decodeIfPresent(ReturnInformation.self, forKey: .returnInformation)?.returnableLineItems.nodes ?? []
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
            fulfillments: c.nodes(.fulfillments),
            edited: c.decodeIfPresent(Bool.self, forKey: .edited) ?? false,
            requiresShipping: c.decodeIfPresent(Bool.self, forKey: .requiresShipping) ?? true,
            note: c.decodeIfPresent(String.self, forKey: .note),
            poNumber: c.decodeIfPresent(String.self, forKey: .poNumber),
            purchasingCompany: purchasingCompany,
            shippingLine: c.decodeIfPresent(OrderShippingLine.self, forKey: .shippingLine),
            paymentInformation: c.decodeIfPresent(OrderPaymentInformation.self, forKey: .paymentInformation),
            transactions: c.decodeIfPresent([OrderTransaction].self, forKey: .transactions) ?? [],
            refunds: c.decodeIfPresent([OrderRefund].self, forKey: .refunds) ?? [],
            returns: c.nodes(.returns),
            hasReturnableItems: returnable.contains { $0.quantity > 0 }
        )
    }
}

struct ReturnReason: Decodable, Equatable, Sendable {
    let id: String
    let handle: String
    let name: String
}

/// An order line that can still be returned, up to `quantity`, and the reasons to offer (their `id` goes in the request).
/// `productId` and `variantId` find the product to pick an exchange from.
struct ReturnableItem: Equatable, Sendable {
    let lineItemId: String
    let title: String
    let image: Img?
    let quantity: Int
    let reasons: [ReturnReason]
    var variantTitle: String? = nil
    var sku: String? = nil
    var productId: String? = nil
    var variantId: String? = nil
    /// One item's price.
    var price: Money? = nil
}

extension ReturnableItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case quantity, lineItem
    }

    private enum LineKeys: String, CodingKey {
        case id, title, image, suggestedReturnReasonDefinitions, variantTitle, sku, productId, variantId, price
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let line = try c.nestedContainer(keyedBy: LineKeys.self, forKey: .lineItem)
        try self.init(
            lineItemId: line.decode(String.self, forKey: .id),
            title: line.decode(String.self, forKey: .title),
            image: line.decodeIfPresent(Img.self, forKey: .image),
            quantity: c.decode(Int.self, forKey: .quantity),
            reasons: line.nodes(.suggestedReturnReasonDefinitions),
            variantTitle: line.decodeIfPresent(String.self, forKey: .variantTitle),
            sku: line.decodeIfPresent(String.self, forKey: .sku),
            productId: line.decodeIfPresent(String.self, forKey: .productId),
            variantId: line.decodeIfPresent(String.self, forKey: .variantId),
            price: line.decodeIfPresent(Money.self, forKey: .price)
        )
    }
}

/// An item going back on a return: `quantity` of an order line, and the reason given.
struct ReturnLine: Equatable, Sendable {
    let id: String
    let quantity: Int
    var reason: String? = nil
    var lineItemId: String? = nil
    var title: String? = nil
    var variantTitle: String? = nil
    var image: Img? = nil
}

extension ReturnLine: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, quantity, returnReasonDefinition, lineItem
    }

    private struct Reason: Decodable {
        let name: String?
    }

    private struct Line: Decodable {
        let id: String?
        let title: String?
        let variantTitle: String?
        let image: Img?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let line = try c.decodeIfPresent(Line.self, forKey: .lineItem)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            quantity: c.decode(Int.self, forKey: .quantity),
            reason: c.decodeIfPresent(Reason.self, forKey: .returnReasonDefinition)?.name,
            lineItemId: line?.id,
            title: line?.title,
            variantTitle: line?.variantTitle,
            image: line?.image
        )
    }
}

/// An item the store sends out in exchange on a return.
struct ExchangeLine: Decodable, Equatable, Sendable {
    let id: String
    let title: String
    let variantTitle: String?
    let quantity: Int
    let image: Img?
}

/// A return request. `status`: REQUESTED, OPEN, CLOSED, DECLINED, ... What follows `createdAt` comes with the Order query
/// only (OrderRequestReturn and OrderReturnOptions answer with the first fields).
struct OrderReturn: Equatable, Sendable {
    let id: String
    let name: String
    let status: String
    var createdAt: String? = nil
    var closedAt: String? = nil
    var lines: [ReturnLine] = []
    var exchangeLines: [ExchangeLine] = []
}

extension OrderReturn: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, status, createdAt, closedAt, returnLineItems, exchangeLineItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            name: c.decode(String.self, forKey: .name),
            status: c.decode(String.self, forKey: .status),
            createdAt: c.decodeIfPresent(String.self, forKey: .createdAt),
            closedAt: c.decodeIfPresent(String.self, forKey: .closedAt),
            lines: c.nodes(.returnLineItems),
            exchangeLines: c.nodes(.exchangeLineItems)
        )
    }
}

/// A fee a return costs the customer. `kind` is its type: ReturnShippingFee or RestockingFee.
struct ReturnFee: Equatable, Sendable {
    let kind: String
    let title: String?
    let amount: Money?
}

extension ReturnFee: Decodable {
    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case title, amountSet
    }

    private struct Amount: Decodable {
        let presentmentMoney: Money?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: c.decodeIfPresent(String.self, forKey: .typename) ?? "",
            title: c.decodeIfPresent(String.self, forKey: .title),
            amount: c.decodeIfPresent(Amount.self, forKey: .amountSet)?.presentmentMoney
        )
    }
}

/// What of an order can be returned (OrderReturnOptions): the items and reasons, what it costs and how the items go
/// back, and the returns already requested.
struct OrderReturnOptions: Equatable, Sendable {
    let orderId: String
    let returnableItems: [ReturnableItem]
    let returns: [OrderReturn]
    /// The order's name ("#1004").
    var orderName: String? = nil
    var hasRestockingFee = false
    var hasReturnShippingFee = false
    /// How the items go back: MERCHANT_PROVIDED_LABEL, CUSTOMER_PROVIDED_LABEL, ...
    var returnShippingMethods: [String] = []
    /// The store's words about sending the items back.
    var returnShippingMethodNote: String? = nil
    var fees: [ReturnFee] = []
    /// Why some of the order can't be returned.
    var nonReturnableSummary: String? = nil
}

extension OrderReturnOptions: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, returnInformation, returns
    }

    private enum InformationKeys: String, CodingKey {
        case returnableLineItems, hasRestockingFee, hasReturnShippingFee, returnShippingMethods, returnShippingMethodNote
        case returnFees, nonReturnableSummary
    }

    private struct Summary: Decodable {
        let nonReturnableReasons: [String]?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let information = try c.nestedContainer(keyedBy: InformationKeys.self, forKey: .returnInformation)
        let reasons = try information.decodeIfPresent(Summary.self, forKey: .nonReturnableSummary)?.nonReturnableReasons ?? []
        var notes: [String] = []
        for note in reasons.map(nonReturnableReason) where !notes.contains(note) { notes.append(note) }
        try self.init(
            orderId: c.decode(String.self, forKey: .id),
            returnableItems: information.nodes(.returnableLineItems),
            returns: c.nodes(.returns),
            orderName: c.decodeIfPresent(String.self, forKey: .name),
            hasRestockingFee: information.decodeIfPresent(Bool.self, forKey: .hasRestockingFee) ?? false,
            hasReturnShippingFee: information.decodeIfPresent(Bool.self, forKey: .hasReturnShippingFee) ?? false,
            returnShippingMethods: information.decodeIfPresent([String].self, forKey: .returnShippingMethods) ?? [],
            returnShippingMethodNote: information.decodeIfPresent(String.self, forKey: .returnShippingMethodNote),
            fees: information.decodeIfPresent([ReturnFee].self, forKey: .returnFees) ?? [],
            nonReturnableSummary: notes.isEmpty ? nil : notes.joined(separator: " ")
        )
    }
}

/// Why some of an order can't be returned, from one of Shopify's NonReturnableReason values.
func nonReturnableReason(_ reason: String) -> String {
    switch reason {
    case "RETURNED": return "Some items were already returned."
    case "FINAL_SALE": return "Final sale items can't be returned."
    case "RETURN_WINDOW_EXPIRED": return "The return window has closed."
    case "UNFULFILLED": return "Items that haven't shipped can't be returned yet."
    default: return "Some items can't be returned."
    }
}

/// A company the customer buys for, as one of its contacts (B2B). `title` is their role there.
struct CompanyContact: Equatable, Sendable {
    let id: String
    let title: String?
    let company: Company
}

/// Credit the store owes the customer, spent at checkout.
struct StoreCreditAccount: Decodable, Equatable, Sendable {
    let id: String
    let balance: Money
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
