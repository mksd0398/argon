import Foundation

// The `Cart` and `CartDeliveryGroups` fragments, the cart mutations' inputs, and what they return.

/// A line of the cart: one variant (lines of other merchandise are left out), with its quantity and line total.
struct CartLine: Equatable, Sendable {
    let id: String
    let quantity: Int
    let variantId: String
    let variantTitle: String
    let productHandle: String
    let productTitle: String
    let image: Img?
    let price: Money
    let total: Money
    var attributes: [CartAttribute] = []
    /// The discounts on this line, as amounts taken off.
    var discounts: [Money] = []
}

extension CartLine: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, quantity, attributes, cost, discountAllocations, merchandise
    }

    private enum MerchandiseKeys: String, CodingKey {
        case id, title, image, price, product
    }

    private struct LineCost: Decodable {
        let totalAmount: Money
    }

    private struct ProductRef: Decodable {
        let handle: String
        let title: String
    }

    private struct Allocation: Decodable {
        let discountedAmount: Money
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let variant = try c.nestedContainer(keyedBy: MerchandiseKeys.self, forKey: .merchandise)
        let product = try variant.decode(ProductRef.self, forKey: .product)
        let allocations = try c.decodeIfPresent([Allocation].self, forKey: .discountAllocations) ?? []
        try self.init(
            id: c.decode(String.self, forKey: .id),
            quantity: c.decode(Int.self, forKey: .quantity),
            variantId: variant.decode(String.self, forKey: .id),
            variantTitle: variant.decode(String.self, forKey: .title),
            productHandle: product.handle,
            productTitle: product.title,
            image: variant.decodeIfPresent(Img.self, forKey: .image),
            price: variant.decode(Money.self, forKey: .price),
            total: c.decode(LineCost.self, forKey: .cost).totalAmount,
            attributes: c.decodeIfPresent([CartAttribute].self, forKey: .attributes) ?? [],
            discounts: allocations.map { $0.discountedAmount }
        )
    }
}

/// A cart line node: a `CartLine` when its merchandise is a variant, else nil.
private struct LineNode: Decodable {
    let line: CartLine?

    private enum CodingKeys: String, CodingKey {
        case merchandise
    }

    private enum MerchandiseKeys: String, CodingKey {
        case typename = "__typename"
    }

    init(from decoder: Decoder) throws {
        let merchandise = try decoder.container(keyedBy: CodingKeys.self).nestedContainer(keyedBy: MerchandiseKeys.self, forKey: .merchandise)
        let isVariant = try merchandise.decode(String.self, forKey: .typename) == "ProductVariant"
        line = try isVariant ? CartLine(from: decoder) : nil
    }
}

struct Cart: Equatable, Sendable {
    let id: String
    let checkoutUrl: String
    let totalQuantity: Int
    let subtotal: Money
    let total: Money
    let lines: [CartLine]
    var note: String? = nil
    var attributes: [CartAttribute] = []
    var discountCodes: [CartDiscountCode] = []
    var giftCards: [AppliedGiftCard] = []
    var buyerIdentity: CartBuyerIdentity? = nil
    var deliveryAddresses: [CartSelectableAddress] = []
    /// Shipping options per delivery group: the Cart query and CartSelectedDeliveryOptionsUpdate only.
    var deliveryGroups: [CartDeliveryGroup] = []
    /// What Shopify changed or couldn't apply in the mutation that returned this cart (empty from the Cart query).
    var warnings: [CartWarning] = []
}

extension Cart: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, checkoutUrl, totalQuantity, note, attributes, discountCodes, appliedGiftCards, buyerIdentity, delivery, cost
        case lines, deliveryGroups
    }

    private struct Cost: Decodable {
        let subtotalAmount: Money
        let totalAmount: Money
    }

    private struct Delivery: Decodable {
        let addresses: [CartSelectableAddress]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cost = try c.decode(Cost.self, forKey: .cost)
        let lines: [LineNode] = try c.nodes(.lines)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            checkoutUrl: c.decode(String.self, forKey: .checkoutUrl),
            totalQuantity: c.decode(Int.self, forKey: .totalQuantity),
            subtotal: cost.subtotalAmount,
            total: cost.totalAmount,
            lines: lines.compactMap { $0.line },
            note: c.decodeIfPresent(String.self, forKey: .note),
            attributes: c.decodeIfPresent([CartAttribute].self, forKey: .attributes) ?? [],
            discountCodes: c.decodeIfPresent([CartDiscountCode].self, forKey: .discountCodes) ?? [],
            giftCards: c.decodeIfPresent([AppliedGiftCard].self, forKey: .appliedGiftCards) ?? [],
            buyerIdentity: c.decodeIfPresent(CartBuyerIdentity.self, forKey: .buyerIdentity),
            deliveryAddresses: c.decodeIfPresent(Delivery.self, forKey: .delivery)?.addresses ?? [],
            deliveryGroups: c.nodes(.deliveryGroups)
        )
    }
}

/// A cart or line attribute (and the AttributeInput a mutation takes).
struct CartAttribute: Codable, Equatable, Sendable {
    let key: String
    let value: String?
}

struct CartDiscountCode: Decodable, Equatable, Sendable {
    let code: String
    /// False when the code is valid but the cart doesn't qualify.
    let applicable: Bool
}

/// `id` is what `removeGiftCards` takes.
struct AppliedGiftCard: Decodable, Equatable, Sendable {
    let id: String
    let lastCharacters: String
    let amountUsed: Money
    let balance: Money
}

struct CartBuyerIdentity: Decodable, Equatable, Sendable {
    let email: String?
    let phone: String?
    let countryCode: String?
}

/// A delivery address on the cart; `address` is nil for an address type this app doesn't know.
struct CartSelectableAddress: Equatable, Sendable {
    let id: String
    let selected: Bool
    let oneTimeUse: Bool
    let address: CartDeliveryAddress?
}

extension CartSelectableAddress: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, selected, oneTimeUse, address
    }

    private enum AddressKeys: String, CodingKey {
        case typename = "__typename"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let typename = try c.nestedContainer(keyedBy: AddressKeys.self, forKey: .address).decode(String.self, forKey: .typename)
        try self.init(
            id: c.decode(String.self, forKey: .id),
            selected: c.decode(Bool.self, forKey: .selected),
            oneTimeUse: c.decode(Bool.self, forKey: .oneTimeUse),
            address: typename == "CartDeliveryAddress" ? c.decode(CartDeliveryAddress.self, forKey: .address) : nil
        )
    }
}

struct CartDeliveryAddress: Decodable, Equatable, Sendable {
    let firstName: String?
    let lastName: String?
    let address1: String?
    let address2: String?
    let city: String?
    let provinceCode: String?
    let zip: String?
    let countryCode: String?
    let phone: String?
}

/// The lines going to one address, the ways they can be delivered and the one chosen.
struct CartDeliveryGroup: Decodable, Equatable, Sendable {
    struct Address: Decodable, Equatable, Sendable {
        let formatted: [String]
    }

    let id: String
    let deliveryAddress: Address
    let selectedDeliveryOption: CartDeliveryOption?
    let deliveryOptions: [CartDeliveryOption]
}

/// `handle` is what `selectDeliveryOptions` takes. `description` and `deliveryMethodType` are nil on the selected option.
struct CartDeliveryOption: Decodable, Equatable, Sendable {
    let handle: String
    let title: String?
    var description: String? = nil
    var deliveryMethodType: String? = nil
    let estimatedCost: Money
}

/// Something Shopify changed or couldn't apply, though the mutation went through (a stock limit, an unknown discount code).
struct CartWarning: Decodable, Equatable, Sendable {
    let code: String
    let message: String
    let target: String
}

// MARK: - Inputs

struct CartLineInput: Encodable, Equatable, Sendable {
    let merchandiseId: String
    var quantity: Int = 1
    var sellingPlanId: String? = nil
    var attributes: [CartAttribute]? = nil
}

/// Changes one line; fields left nil stay as they are.
struct CartLineUpdateInput: Encodable, Equatable, Sendable {
    let id: String
    var quantity: Int? = nil
    var merchandiseId: String? = nil
    var sellingPlanId: String? = nil
    var attributes: [CartAttribute]? = nil
}

/// `customerAccessToken` is the Customer Account API access token: it attaches the signed-in customer.
struct CartBuyerIdentityInput: Encodable, Equatable, Sendable {
    var email: String? = nil
    var phone: String? = nil
    var countryCode: String? = nil
    var customerAccessToken: String? = nil
}

struct CartInput: Encodable, Equatable, Sendable {
    var lines: [CartLineInput] = []
    var attributes: [CartAttribute]? = nil
    var buyerIdentity: CartBuyerIdentityInput? = nil
    var discountCodes: [String]? = nil
    var giftCardCodes: [String]? = nil
    var note: String? = nil
}

struct CartDeliveryAddressInput: Encodable, Equatable, Sendable {
    var firstName: String? = nil
    var lastName: String? = nil
    var company: String? = nil
    var address1: String? = nil
    var address2: String? = nil
    var city: String? = nil
    var provinceCode: String? = nil
    var zip: String? = nil
    var countryCode: String? = nil
    var phone: String? = nil
}

private enum SelectableAddressKeys: String, CodingKey {
    case id, address, selected, oneTimeUse
}

private enum DeliveryAddressKeys: String, CodingKey {
    case deliveryAddress
}

/// A delivery address to add (Shopify allows 20, one selected).
struct CartSelectableAddressInput: Encodable, Equatable, Sendable {
    let address: CartDeliveryAddressInput
    var selected: Bool? = nil
    var oneTimeUse: Bool? = nil

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SelectableAddressKeys.self)
        var address = c.nestedContainer(keyedBy: DeliveryAddressKeys.self, forKey: .address)
        try address.encode(self.address, forKey: .deliveryAddress)
        try c.encodeIfPresent(selected, forKey: .selected)
        try c.encodeIfPresent(oneTimeUse, forKey: .oneTimeUse)
    }
}

/// Changes the delivery address `id`; fields left nil stay as they are.
struct CartSelectableAddressUpdateInput: Encodable, Equatable, Sendable {
    let id: String
    var address: CartDeliveryAddressInput? = nil
    var selected: Bool? = nil
    var oneTimeUse: Bool? = nil

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: SelectableAddressKeys.self)
        try c.encode(id, forKey: .id)
        if let address = address {
            var wrapper = c.nestedContainer(keyedBy: DeliveryAddressKeys.self, forKey: .address)
            try wrapper.encode(address, forKey: .deliveryAddress)
        }
        try c.encodeIfPresent(selected, forKey: .selected)
        try c.encodeIfPresent(oneTimeUse, forKey: .oneTimeUse)
    }
}

struct CartSelectedDeliveryOptionInput: Encodable, Equatable, Sendable {
    let deliveryGroupId: String
    let deliveryOptionHandle: String
}
