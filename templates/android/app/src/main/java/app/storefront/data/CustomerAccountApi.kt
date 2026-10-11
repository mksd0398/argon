package app.storefront.data

import kotlinx.serialization.json.JsonObject

private const val PAGE_SIZE = 20

/**
 * Every Customer Account API operation of the contract as a typed call, as the signed-in customer. [execute] runs a named
 * document with its variables and returns the response's `data` ([app.storefront.auth.AuthStore.customerQuery] in the
 * app: it sends the customer's access token). Every failure is an [ArgonApiError]; a mutation's `userErrors` are thrown.
 */
class CustomerAccountApi(private val execute: suspend (String, JsonObject) -> JsonObject) {
    private suspend inline fun <reified T> run(operation: String, variables: JsonObject, vararg path: String): T =
        decode(operation, execute(operation, variables), *path)

    /** Runs mutation [operation] and returns its payload's [field]; `userErrors` are thrown. */
    private suspend inline fun <reified T> mutate(operation: String, variables: JsonObject, field: String): T {
        val data = execute(operation, variables)
        val root = operation.replaceFirstChar { it.lowercase() }
        val errors = decode<List<UserError>?>(operation, data, root, "userErrors").orEmpty()
        if (errors.isNotEmpty()) throw ArgonApiError.UserErrors(errors)
        return decode(operation, data, root, field)
    }

    /** The profile (orders come from [orders]). */
    suspend fun customer(): Customer = run("Customer", vars(), "customer")

    /** Newest first. */
    suspend fun orders(after: String? = null): Page<OrderSummary> =
        run("Orders", vars("first" to PAGE_SIZE, "after" to after, "sortKey" to "PROCESSED_AT", "reverse" to true), "customer", "orders")

    suspend fun order(id: String): Order? = run("Order", vars("id" to id), "order")

    /** The address book; the default address has `isDefault`. */
    suspend fun addresses(after: String? = null): Page<CustomerAddress> {
        val data = execute("CustomerAddresses", vars("first" to PAGE_SIZE, "after" to after))
        val defaultId = decode<String?>("CustomerAddresses", data, "customer", "defaultAddress", "id")
        val page = decode<Page<CustomerAddress>>("CustomerAddresses", data, "customer", "addresses")
        return page.copy(items = page.items.map { it.copy(isDefault = it.id == defaultId) })
    }

    /** Name only: the API can't change the email or phone. A null part is left as it is. */
    suspend fun updateName(first: String?, last: String?): Customer =
        mutate("CustomerUpdate", vars("input" to vars("firstName" to first, "lastName" to last)), "customer")

    suspend fun createAddress(input: CustomerAddressInput, isDefault: Boolean = false): CustomerAddress =
        mutate("CustomerAddressCreate", vars("address" to encode(input), "defaultAddress" to isDefault), "customerAddress")

    /** [input] null changes only whether it is the default. Demoting the default fails: make another one the default instead. */
    suspend fun updateAddress(id: String, input: CustomerAddressInput? = null, isDefault: Boolean? = null): CustomerAddress =
        mutate("CustomerAddressUpdate", vars("addressId" to id, "address" to input?.let { encode(it) }, "defaultAddress" to isDefault), "customerAddress")

    /** Returns the deleted address's id. The default address can't be deleted (DELETING_CUSTOMER_DEFAULT_ADDRESS_NOT_ALLOWED). */
    suspend fun deleteAddress(id: String): String = mutate("CustomerAddressDelete", vars("addressId" to id), "deletedAddressId")

    suspend fun subscribeEmailMarketing(): CustomerEmailAddress = mutate("CustomerEmailMarketingSubscribe", vars(), "emailAddress")

    suspend fun unsubscribeEmailMarketing(): CustomerEmailAddress = mutate("CustomerEmailMarketingUnsubscribe", vars(), "emailAddress")

    /** The companies the customer buys for (B2B), each with its locations; none for a retail customer. */
    suspend fun companies(): List<CompanyContact> =
        run<List<CompanyContact>?>("CustomerCompanies", vars(), "customer", "companyContacts", "nodes").orEmpty()

    /** The customer's store credit, one account per currency; none when they have no credit. */
    suspend fun storeCredit(): List<StoreCreditAccount> =
        run<List<StoreCreditAccount>?>("CustomerStoreCredit", vars(), "customer", "storeCreditAccounts", "nodes").orEmpty()

    /** What can be returned (with the reasons to offer and the fees), and the order's returns so far. */
    suspend fun returnOptions(orderId: String): OrderReturnOptions? = run("OrderReturnOptions", vars("id" to orderId), "order")

    suspend fun requestReturn(orderId: String, lines: List<RequestedLineItemInput>): Return =
        mutate("OrderRequestReturn", vars("orderId" to orderId, "requestedLineItems" to encode(lines)), "return")
}
