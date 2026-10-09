package app.storefront.data

import java.io.File
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** Operation [name]'s contract fixture (a response's `data`), copied into src/test/resources/fixtures by the CLI. */
internal fun fixture(name: String): JsonObject =
    json(ContractFixturesTest::class.java.getResource("/fixtures/$name.json")!!.readText())

internal fun json(text: String): JsonObject = Json.parseToJsonElement(text).jsonObject

/** A StorefrontApi that answers every operation with its fixture. */
internal fun fixtureStorefront() = StorefrontApi({ name, _ -> fixture(name) })

/**
 * Every fixture in contract/fixtures, decoded through the facade call that runs its operation, with its key fields checked.
 * A new fixture without a case here fails.
 */
@RunWith(Parameterized::class)
class ContractFixturesTest(private val operation: String) {
    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun operations(): List<String> = File(ContractFixturesTest::class.java.getResource("/fixtures")!!.toURI())
            .list()!!.filter { it.endsWith(".json") }.map { it.removeSuffix(".json") }.sorted()
    }

    private val ran = mutableListOf<String>()
    private val storefront = StorefrontApi({ name, _ -> ran += name; fixture(name) })
    private val account = CustomerAccountApi({ name, _ -> ran += name; fixture(name) })

    private val cartId = "gid://shopify/Cart/c1"
    private val discountWarning = "DISCOUNT_NOT_FOUND"

    @Test
    fun decodesThroughItsFacadeCall() = runBlocking {
        check()
        assertEquals("the facade call runs $operation", listOf(operation), ran)
    }

    private fun Cart.assertCrewneck(quantity: Int) {
        assertEquals(quantity, totalQuantity)
        val line = lines.single()
        assertEquals("Men's Crewneck", line.productTitle)
        assertEquals("Small / Green", line.variantTitle)
        assertEquals("gid://shopify/ProductVariant/43696905224214", line.merchandise.id)
        assertEquals(Money("120.0", "CAD"), line.merchandise.price)
        assertEquals("CAD", total.currencyCode)
    }

    private suspend fun check() {
        when (operation) {
            // Storefront API
            "Article" -> storefront.article("news", "making-liquid")!!.let {
                assertEquals("Making Liquid", it.title)
                assertEquals("Teddy Hwang", it.authorV2?.name)
                assertEquals("news", it.blog?.handle)
                assertTrue(it.contentHtml!!.startsWith("<p>"))
                assertNull(it.image)
            }
            "Articles" -> storefront.articles().let {
                assertEquals(3, it.items.size)
                assertFalse(it.hasNextPage)
                assertEquals("eyJjIjoiaWQiLCJ2IjozLCJpIjozfQ", it.endCursor)
                assertEquals("2023-02-07T15:45:04Z", it.items[0].publishedAt)
            }
            "Blog" -> storefront.blog("news")!!.let {
                assertEquals("News", it.title)
                assertEquals(listOf("making-liquid", "new-line-of-tennis-products", "liquidpeak-450"), it.articles!!.items.map { a -> a.handle })
            }
            "Blogs" -> assertEquals(listOf("news"), storefront.blogs().items.map { it.handle })
            "Cart" -> storefront.cart(cartId)!!.let {
                it.assertCrewneck(3)
                assertEquals("Gift wrap, please", it.note)
                assertEquals(listOf(Attribute("source", "app")), it.attributes)
                assertEquals(listOf(Cart.DiscountCode("WELCOME10", applicable = false)), it.discountCodes)
                assertEquals(Money("360.0", "CAD"), it.subtotal)
                assertEquals("CA", it.buyerIdentity?.countryCode)
                assertTrue("the Cart query has no warnings", it.warnings.isEmpty())
                assertTrue(it.deliveryGroups.isEmpty())
            }
            "CartAttributesUpdate" -> assertEquals(listOf(Attribute("source", "app")), storefront.updateAttributes(cartId, listOf(Attribute("source", "app"))).attributes)
            "CartBuyerIdentityUpdate" -> storefront.updateBuyerIdentity(cartId, CartBuyerIdentityInput(countryCode = "CA")).let {
                assertEquals("CA", it.buyerIdentity?.countryCode)
                assertEquals(listOf(discountWarning), it.warnings.map { w -> w.code })
            }
            "CartCreate" -> storefront.cartCreate(CartInput(lines = listOf(CartLineInput("gid://shopify/ProductVariant/43696905224214", 1)))).let {
                it.assertCrewneck(1)
                assertTrue(it.warnings.isEmpty())
            }
            "CartDeliveryAddressesAdd" -> {
                val address = CartDeliveryAddress(firstName = "Ada", address1 = "150 Elgin St", city = "Ottawa", countryCode = "CA")
                val cart = storefront.addDeliveryAddresses(cartId, listOf(CartSelectableAddressInput(CartAddressInput(address), selected = true)))
                val added = cart.delivery!!.addresses.single()
                assertTrue(added.selected)
                assertEquals("Ottawa", added.address.city)
                assertEquals("ON", added.address.provinceCode)
            }
            "CartDeliveryAddressesRemove" -> assertTrue(storefront.removeDeliveryAddresses(cartId, listOf("gid://shopify/CartSelectableAddress/9876543210")).delivery!!.addresses.isEmpty())
            "CartDeliveryAddressesUpdate" -> {
                val update = CartSelectableAddressUpdateInput("gid://shopify/CartSelectableAddress/9876543210", CartAddressInput(CartDeliveryAddress(address2 = "Suite 400")))
                assertEquals("Suite 400", storefront.updateDeliveryAddresses(cartId, listOf(update)).delivery!!.addresses.single().address.address2)
            }
            "CartDiscountCodesUpdate" -> storefront.updateDiscountCodes(cartId, listOf("WELCOME10")).let {
                assertEquals(listOf("WELCOME10"), it.discountCodes.map { d -> d.code })
                assertEquals("Enter a valid discount code", it.warnings.single().message)
            }
            "CartGiftCardCodesAdd" -> storefront.addGiftCards(cartId, listOf("GIFT")).let {
                assertTrue(it.appliedGiftCards.isEmpty())
                assertEquals(listOf(discountWarning), it.warnings.map { w -> w.code })
            }
            "CartGiftCardCodesRemove" -> assertTrue(storefront.removeGiftCards(cartId, listOf("gid://shopify/AppliedGiftCard/1")).appliedGiftCards.isEmpty())
            "CartLinesAdd" -> storefront.addLines(cartId, listOf(CartLineInput("gid://shopify/ProductVariant/43696905224214", 1))).assertCrewneck(2)
            "CartLinesRemove" -> storefront.removeLines(cartId, listOf("gid://shopify/CartLine/49959")).let {
                assertEquals(0, it.totalQuantity)
                assertTrue(it.lines.isEmpty())
                assertEquals("warnings come back with the cart", discountWarning, it.warnings.single().code)
                assertEquals(it.id, it.warnings.single().target)
            }
            "CartLinesUpdate" -> storefront.updateLines(cartId, listOf(CartLineUpdateInput("gid://shopify/CartLine/49959", 3))).assertCrewneck(3)
            "CartNoteUpdate" -> assertEquals("Gift wrap, please", storefront.updateNote(cartId, "Gift wrap, please").note)
            "CartSelectedDeliveryOptionsUpdate" -> {
                val cart = storefront.selectDeliveryOptions(cartId, listOf(CartSelectedDeliveryOptionInput("gid://shopify/CartDeliveryGroup/1", "a1b2c3d4-standard")))
                val group = cart.deliveryGroups.single()
                assertEquals("Standard", group.selectedDeliveryOption?.title)
                assertEquals(listOf("Standard", "Express"), group.deliveryOptions.map { it.title })
                assertEquals(Money("25.0", "CAD"), group.deliveryOptions[1].estimatedCost)
                assertEquals("SHIPPING", group.deliveryOptions[1].deliveryMethodType)
                assertEquals("Ada Lovelace", group.deliveryAddress?.formatted?.first())
            }
            "Catalog" -> storefront.products().let {
                assertEquals(3, it.items.size)
                assertTrue(it.hasNextPage)
                assertEquals("eyJjIjoicHJpY2UiLCJ2IjoiMTIwLjAiLCJpIjoxMX0", it.endCursor)
                assertEquals("gray-leather-sneakers", it.items[0].handle)
                assertEquals(Money("1000.0", "CAD"), it.items[0].price)
                assertTrue("a catalogue has no filters", it.filters.isEmpty())
            }
            "Collection" -> storefront.collection("men")!!.let {
                assertEquals("Men", it.title)
                assertTrue(it.description.startsWith("High-quality men's clothing"))
                assertEquals(3, it.products.items.size)
                assertTrue(it.products.hasNextPage)
                assertEquals("eyJjIjoicG9zaXRpb24iLCJ2Ijo0LCJpIjo4MjYwfQ", it.products.endCursor)
                assertEquals("hoodie-old", it.products.items[0].handle)
                assertNull("a 0.0 compare-at is no discount", it.products.items[0].compareAt)
                assertEquals(1024, it.image?.width)
            }
            "Collections" -> storefront.collections().let {
                assertEquals(listOf("men", "women", "unisex"), it.items.map { c -> c.handle })
                assertTrue(it.hasNextPage)
                assertTrue(it.items[0].description!!.startsWith("High-quality men's"))
            }
            "FallbackHome" -> storefront.fallbackHome().let {
                assertEquals(listOf("men", "women", "unisex"), it.map { c -> c.handle })
                assertTrue(it.all { c -> c.products.size == 3 })
            }
            "HomeScreen" -> storefront.homeScreen().let {
                assertEquals(listOf("mobile_banner", "mobile_products", "mobile_collections"), it.map { m -> m.type })
                val image = it[0].field("image")!!.reference as Reference.Image
                assertTrue(image.image!!.url.endsWith(".png"))
                val collection = it[1].field("collection")!!.reference as CollectionCard
                assertEquals("men", collection.handle)
                assertTrue(collection.products.isNotEmpty())
                assertTrue("an empty product list", it[1].field("products")!!.references.isEmpty())
                assertEquals(listOf("men", "women", "unisex"), it[2].field("collections")!!.references.map { r -> (r as CollectionCard).handle })
            }
            "Localization" -> storefront.localization().let {
                assertEquals("CA", it.country.isoCode)
                assertEquals("CAD", it.country.currency?.isoCode)
                assertEquals("EN", it.language.isoCode)
                assertEquals(listOf("EN"), it.availableCountries.single().availableLanguages.map { l -> l.isoCode })
                assertEquals("EN", it.availableCountries.single().defaultLanguage?.isoCode)
            }
            "Locations" -> storefront.locations().let {
                assertEquals(listOf("Ottawa Store", "Toronto Warehouse"), it.items.map { l -> l.name })
                assertEquals(45.4215, it.items[0].address.latitude!!, 0.0)
                assertEquals(listOf("150 Elgin St", "Ottawa ON K2P 1L4", "Canada"), it.items[0].address.formatted)
            }
            "Menu" -> storefront.menu("main-menu")!!.let {
                assertEquals("main-menu", it.handle)
                assertEquals(listOf("Men", "Women", "Unisex"), it.items.map { i -> i.title })
                assertEquals("COLLECTION", it.items[0].type)
                assertNull(it.items[0].resource)
            }
            "Metaobject" -> storefront.metaobject("mobile_banner", "new-season")!!.let {
                assertEquals("New season", it.field("heading")?.value)
                assertTrue((it.field("image")!!.reference as Reference.Image).image!!.url.endsWith(".png"))
                assertEquals("a reference the document selects only __typename of", Reference.Other("Collection"), it.field("collection")!!.reference)
                assertNull(it.field("link")!!.reference)
            }
            "Metaobjects" -> storefront.metaobjects("mobile_banner").let {
                assertEquals(listOf("new-season", "free-shipping"), it.items.map { m -> m.handle })
                assertEquals("card", it.items[1].field("style")?.value)
            }
            "Page" -> storefront.page("contact")!!.let {
                assertEquals("Contact", it.title)
                assertNull(it.seo?.title)
            }
            "Pages" -> assertEquals(listOf("contact", "liquid"), storefront.pages().items.map { it.handle })
            "PredictiveSearch" -> storefront.predictiveSearch("shirt").let {
                assertEquals(listOf("men-t-shirt", "women-t-shirt", "half-zip"), it.products.map { p -> p.handle })
                assertEquals(listOf(ResourceRef("tops", "Tops")), it.collections)
                assertTrue(it.queries.isEmpty())
            }
            "Product" -> storefront.product("men-crewneck")!!.let {
                assertEquals("Men's Crewneck", it.title)
                assertEquals(listOf("Size", "Color"), it.options.map { o -> o.name })
                assertEquals(listOf("Small", "Medium", "Large"), it.options[0].values)
                assertEquals(3, it.variants.size)
                assertEquals(mapOf("Size" to "Small", "Color" to "Green"), it.variants[0].options)
                assertEquals(it.variants[0], it.selectedOrFirstAvailableVariant)
                assertEquals(3, it.adjacentVariants.size)
                assertTrue(it.media.all { m -> m is Media.Image })
                assertEquals(3, it.images.size)
                assertTrue("unset metafields come back null and are dropped", it.metafields.isEmpty())
                assertEquals("v1_0:0-4,1:0-4,2:0-4,", it.encodedVariantExistence)
                assertTrue(it.sellingPlanGroups.isEmpty())
            }
            "ProductRecommendations" -> storefront.recommendations("gid://shopify/Product/7982905098262").let {
                assertEquals(listOf("hoodie-old", "men-t-shirt", "sweatpants"), it.map { p -> p.handle })
                assertNull(it[0].compareAt)
            }
            "Products" -> assertTrue(storefront.productsByIds(listOf("gid://shopify/Product/1")).isEmpty())
            "Search" -> storefront.search("shirt").let {
                assertEquals(3, it.items.size)
                assertTrue(it.items.all { r -> r is ProductCard })
                assertEquals("men-t-shirt", (it.items[0] as ProductCard).handle)
                assertFalse(it.hasNextPage)
                assertTrue(it.filters.isEmpty())
            }
            "Shop" -> storefront.shop().let {
                assertEquals("Mock.shop", it.name)
                assertEquals("demostore.hydrogen.mock.shop", it.primaryDomain?.host)
                assertTrue(it.brand?.logo?.image!!.url.endsWith(".png"))
                assertEquals("CAD", it.paymentSettings?.currencyCode)
                assertEquals(listOf("CAD"), it.paymentSettings?.enabledPresentmentCurrencies)
            }
            "ShopPolicies" -> storefront.policies().let {
                assertEquals("Privacy Policy", it.privacyPolicy?.title)
                assertEquals("https://demostore.hydrogen.mock.shop/policies/refund-policy", it.refundPolicy?.url)
                assertNull(it.termsOfSale)
                assertNull("the subscription policy may have no id", it.subscriptionPolicy?.id)
                assertEquals("subscription-policy", it.subscriptionPolicy?.handle)
            }
            "StoreAvailability" -> storefront.storeAvailability("gid://shopify/ProductVariant/43696905224214").let {
                assertEquals(listOf(true, false), it.map { a -> a.available })
                assertEquals(4, it[0].quantityAvailable)
                assertEquals("Ottawa Store", it[0].location.name)
                assertEquals("Usually ready in 2 hours", it[0].pickUpTime)
            }
            "VariantBySelectedOptions" -> storefront.variantBySelectedOptions("men-crewneck", mapOf("Size" to "Small", "Color" to "Olive"))!!.let {
                assertEquals("Small / Olive", it.title)
                assertEquals(mapOf("Size" to "Small", "Color" to "Olive"), it.options)
                assertNull(it.sku)
                assertNull(it.compareAt)
            }

            // Customer Account API
            "Customer" -> account.customer().let {
                assertEquals("Ada Lovelace", it.name)
                assertEquals("ada@example.com", it.email)
                assertEquals("SUBSCRIBED", it.emailAddress?.marketingState)
                assertEquals("+16135550123", it.phoneNumber?.phoneNumber)
                assertEquals("Ottawa", it.defaultAddress?.city)
            }
            "CustomerAddressCreate" -> assertEquals(
                "Analytical Engines Ltd",
                account.createAddress(CustomerAddressInput(company = "Analytical Engines Ltd", address1 = "1 Front St W", countryCode = "CA")).company,
            )
            "CustomerAddressDelete" -> {
                val e = assertThrows(ArgonApiError.UserErrors::class.java) { runBlocking { account.deleteAddress("gid://shopify/CustomerAddress/8000001") } }
                val error = e.errors.single()
                assertEquals("DELETING_CUSTOMER_DEFAULT_ADDRESS_NOT_ALLOWED", error.code)
                assertEquals(listOf("addressId"), error.field)
                assertEquals("Customer's default address cannot be deleted.", e.message)
            }
            "CustomerAddressUpdate" -> assertEquals(
                "Floor 3",
                account.updateAddress("gid://shopify/CustomerAddress/8000002", CustomerAddressInput(address2 = "Floor 3")).address2,
            )
            "CustomerAddresses" -> account.addresses().let {
                assertEquals(listOf(true, false), it.items.map { a -> a.isDefault })
                assertEquals("Toronto", it.items[1].city)
                assertFalse(it.hasNextPage)
                assertEquals("eyJsYXN0X2lkIjo4MDAwMDAyfQ==", it.endCursor)
            }
            "CustomerEmailMarketingSubscribe" -> assertEquals("SUBSCRIBED", account.subscribeEmailMarketing().marketingState)
            "CustomerEmailMarketingUnsubscribe" -> assertEquals("UNSUBSCRIBED", account.unsubscribeEmailMarketing().marketingState)
            "CustomerUpdate" -> assertEquals("Ada King", account.updateName("Ada", "King").displayName)
            "Order" -> account.order("gid://shopify/Order/6000002")!!.let {
                assertEquals("#1002", it.name)
                assertEquals(Money("130.0", "CAD"), it.total)
                assertEquals(Money("108.0", "CAD"), it.subtotal)
                assertEquals("FULFILLED", it.fulfillmentStatus)
                assertEquals(PricingValue.Percentage(10.0), it.discountApplications.single().value)
                val line = it.lines.single()
                assertEquals("Men's Crewneck", line.title)
                assertEquals(Money("108.0", "CAD"), line.total)
                val fulfillment = it.fulfillments.single()
                assertEquals("SUCCESS", fulfillment.status)
                assertEquals("Canada Post", fulfillment.trackingInformation.single().company)
                assertEquals(line.id, fulfillment.fulfillmentLineItems.single().lineItem.id)
                assertEquals("Ottawa", it.shippingAddress?.city)
            }
            "OrderRequestReturn" -> assertEquals(
                "REQUESTED",
                account.requestReturn("gid://shopify/Order/6000002", listOf(RequestedLineItemInput("gid://shopify/LineItem/5000001", 1))).status,
            )
            "OrderReturnOptions" -> account.returnOptions("gid://shopify/Order/6000002")!!.let {
                val item = it.returnableLineItems.single()
                assertEquals(1, item.quantity)
                assertEquals(listOf("size-too-small", "not-as-described"), item.lineItem.suggestedReturnReasonDefinitions.map { r -> r.handle })
                assertTrue(it.returns.isEmpty())
            }
            "Orders" -> account.orders().let {
                assertEquals(listOf("#1002", "#1001"), it.items.map { o -> o.name })
                assertTrue(it.hasNextPage)
                assertEquals("eyJsYXN0X2lkIjo2MDAwMDAxfQ==", it.endCursor)
                assertEquals(Money("70.0", "CAD"), it.items[1].total)
                assertEquals("2026-09-12T11:30:00Z", it.items[1].cancelledAt)
                assertNull(it.items[1].lineItems.single().image)
            }
            else -> fail("No facade call decodes $operation: add a case to ContractFixturesTest")
        }
    }
}
