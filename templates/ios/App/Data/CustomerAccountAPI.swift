import Foundation

/// Every Customer Account API operation in `queries/`, as typed calls for the signed-in customer. `transport` runs a named
/// operation and returns the response body: `AuthStore.customerQuery` in the app (the customer's token, refreshed on 401),
/// canned answers in tests. Lists come back as `Page`s. A mutation Shopify refuses throws its `userErrors`.
@MainActor
final class CustomerAccountAPI {
    private let transport: GraphQLTransport

    init(transport: @escaping GraphQLTransport) {
        self.transport = transport
    }

    func customer() async throws -> Customer {
        try await fetchField(transport, "Customer", [:], root: "customer")
    }

    /// The customer's orders, newest first.
    func orders(after: String? = nil, first: Int = 20) async throws -> Page<OrderSummary> {
        let customer: OrdersOwner = try await fetchField(transport, "Orders", list(first, after, ["reverse": true]), root: "customer")
        return customer.orders
    }

    /// Order `id` (an OrderSummary's); nil when the customer has no such order.
    func order(_ id: String) async throws -> Order? {
        try await fetchField(transport, "Order", ["id": id], root: "order")
    }

    /// The customer's addresses, the default one marked `isDefault`.
    func addresses(after: String? = nil, first: Int = 20) async throws -> Page<CustomerAddress> {
        let customer: AddressesOwner = try await fetchField(transport, "CustomerAddresses", list(first, after), root: "customer")
        let defaultId = customer.defaultAddress?.id
        let marked = customer.addresses.items.map { found -> CustomerAddress in
            var address = found
            address.isDefault = found.id == defaultId
            return address
        }
        return Page(items: marked, endCursor: customer.addresses.endCursor, hasNextPage: customer.addresses.hasNextPage)
    }

    /// Sets the customer's names; a nil one is left as it is. (Email and phone can't be changed through this API.)
    func updateName(first: String?, last: String?) async throws -> Customer {
        try await mutate("CustomerUpdate", ["input": jsonValue(NameInput(firstName: first, lastName: last))])
    }

    func createAddress(_ address: CustomerAddressInput, isDefault: Bool = false) async throws -> CustomerAddress {
        try await mutate("CustomerAddressCreate", ["address": jsonValue(address), "defaultAddress": isDefault])
    }

    /// Changes address `id`: the fields set in `address`, and/or whether it is the default.
    func updateAddress(_ id: String, _ address: CustomerAddressInput? = nil, isDefault: Bool? = nil) async throws -> CustomerAddress {
        var variables: [String: Any] = ["addressId": id]
        if let address = address { variables["address"] = try jsonValue(address) }
        if let isDefault = isDefault { variables["defaultAddress"] = isDefault }
        return try await mutate("CustomerAddressUpdate", variables)
    }

    /// Returns the deleted address's id. Shopify refuses to delete the default address: make another one default first.
    func deleteAddress(_ id: String) async throws -> String {
        try await mutate("CustomerAddressDelete", ["addressId": id])
    }

    func subscribeEmailMarketing() async throws -> CustomerEmailAddress {
        try await mutate("CustomerEmailMarketingSubscribe")
    }

    func unsubscribeEmailMarketing() async throws -> CustomerEmailAddress {
        try await mutate("CustomerEmailMarketingUnsubscribe")
    }

    /// What of order `orderId` can be returned, with the reasons to offer; nil when there is no such order.
    func returnOptions(_ orderId: String) async throws -> ReturnOptions? {
        try await fetchField(transport, "OrderReturnOptions", ["id": orderId], root: "order")
    }

    func requestReturn(_ orderId: String, lines: [ReturnLineInput]) async throws -> OrderReturn {
        try await mutate("OrderRequestReturn", ["orderId": orderId, "requestedLineItems": jsonValue(lines)])
    }

    /// Runs mutation `name`: its user errors are thrown, its one result field returned.
    private func mutate<Value: Decodable>(_ name: String, _ variables: [String: Any] = [:]) async throws -> Value {
        let payload: MutationPayload<Value> = try await fetchField(transport, name, variables, root: payloadField(name))
        if !payload.userErrors.isEmpty { throw ArgonAPIError.userErrors(payload.userErrors, cart: nil) }
        guard let value = payload.value else { throw ArgonAPIError.decoding(operation: name, detail: "result missing") }
        return value
    }

    private func list(_ first: Int, _ after: String?, _ more: [String: Any] = [:]) -> [String: Any] {
        var variables = more
        variables["first"] = first
        if let after = after { variables["after"] = after }
        return variables
    }
}

private struct NameInput: Encodable {
    let firstName: String?
    let lastName: String?
}

private struct OrdersOwner: Decodable {
    let orders: Page<OrderSummary>
}

private struct AddressesOwner: Decodable {
    struct DefaultAddress: Decodable {
        let id: String
    }

    let defaultAddress: DefaultAddress?
    let addresses: Page<CustomerAddress>
}

/// A mutation payload: `userErrors` and the one other field it selects, whatever its name (`customerAddress`, `return`, ...).
private struct MutationPayload<Value: Decodable>: Decodable {
    let value: Value?
    let userErrors: [UserError]

    private struct Key: CodingKey {
        let stringValue: String

        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let errors = Key(stringValue: "userErrors")
        userErrors = try c.decode([UserError].self, forKey: errors)
        let result = c.allKeys.first { $0.stringValue != errors.stringValue }
        value = try result.flatMap { try c.decodeIfPresent(Value.self, forKey: $0) }
    }
}
