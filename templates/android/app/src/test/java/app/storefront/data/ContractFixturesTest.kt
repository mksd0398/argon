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
                assertNull("a retail cart", it.purchasingCompany)
                assertTrue("the Cart query has no warnings", it.warnings.isEmpty())
                assertTrue(it.deliveryGroups.isEmpty())
                val line = it.lines.single()
                assertNull("bought once, not on a selling plan", line.sellingPlanName)
                assertTrue("not a bundle", line.components.isEmpty())
                // mock.shop has no quantity rules: it sends 0 for the minimum and the increment
                assertEquals(QuantityRule(minimum = 0, maximum = null, increment = 0), line.merchandise.quantityRule)
                assertEquals(1, line.merchandise.quantityRule?.min)
                assertEquals(1, line.merchandise.quantityRule?.step)
                // 3 × 120.00, 150.00 each before, and an automatic discount on the line
                assertEquals(Money("360.0", "CAD"), line.subtotal)
                assertEquals(Money("324.0", "CAD"), line.total)
                assertEquals(Money("120.0", "CAD"), line.unitPrice)
                assertEquals(Money("150.0", "CAD"), line.compareAtUnitPrice)
                assertEquals(listOf(CartDiscount(Money("36.0", "CAD"), "Buy 3, save 10%")), line.discounts)
                assertEquals("gid://shopify/Product/7982905098262", line.productId)
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
                val line = it.lines.single()
                assertNull("no compare-at price on this line", line.compareAtUnitPrice)
                assertTrue("the code doesn't apply: no discount on the line", line.discounts.isEmpty())
                assertEquals(line.subtotal, line.total)
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
                val sneakers = it.items[0]
                assertEquals("gray-leather-sneakers", sneakers.handle)
                assertEquals(Money("1000.0", "CAD"), sneakers.price)
                assertEquals("Mock.shop", sneakers.vendor)
                assertFalse("every variant costs the same", sneakers.hasPriceRange)
                assertEquals(listOf("Size"), sneakers.options.map { o -> o.name })
                assertEquals(listOf("4", "5", "6"), sneakers.options[0].values)
                assertEquals("gid://shopify/ProductVariant/43696961355798", sneakers.firstVariant?.id)
                assertTrue(sneakers.firstVariant!!.available)
                assertNull("a size has to be chosen first", sneakers.quickAddVariantId)
                assertTrue("no colour option", sneakers.colors.isEmpty())
                assertNull("no reviews metafields", sneakers.rating)
                assertNull(sneakers.ratingCount)
                assertEquals(listOf("Green", "Olive", "Ocean"), it.items[1].colors.map { c -> c.name })
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
                assertEquals("#81a69b", it.products.items[0].colors[0].swatch?.color)
                assertEquals(1024, it.image?.width)
                val filters = it.products.filters
                assertEquals(listOf("Availability", "Price", "Color", "Size"), filters.map { f -> f.label })
                assertEquals(listOf("LIST", "PRICE_RANGE", "LIST", "LIST"), filters.map { f -> f.type })
                assertEquals(listOf("TEXT", "TEXT", "SWATCH", "TEXT"), filters.map { f -> f.presentation })
                val (green, olive, ocean) = filters[2].values
                assertEquals("#3F6B4F", green.swatch?.color)
                assertEquals(9, green.count)
                assertEquals("""{"variantOption":{"name":"color","value":"Green"}}""", green.input)
                val pattern = olive.swatch!!
                assertTrue("a pattern swatch is an image", pattern.image?.previewImage!!.url.endsWith(".jpg"))
                assertNull(pattern.color)
                assertNull(ocean.swatch)
            }
            "Collections" -> storefront.collections().let {
                assertEquals(listOf("men", "women", "unisex"), it.items.map { c -> c.handle })
                assertTrue(it.hasNextPage)
                assertTrue(it.items[0].description!!.startsWith("High-quality men's"))
            }
            "FallbackHome" -> storefront.fallbackHome().let {
                assertEquals(listOf("men", "women", "unisex"), it.map { c -> c.handle })
                assertTrue(it.all { c -> c.products.size == 3 })
                val sweatpants = it[2].products[1]
                assertEquals("sweatpants", sweatpants.handle)
                assertTrue("35 to 42: a From price", sweatpants.hasPriceRange)
                assertEquals(Money("42.0", "CAD"), sweatpants.priceRange.maxVariantPrice)
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
                assertEquals("v1_0:0-4,1:0-4,2:0-4,", it.encodedVariantExistence)
                assertEquals(listOf("men", "tops"), it.tags)
                assertNull("not published on the web store", it.onlineStoreUrl)
                assertNull("no reviews metafields", it.rating)
                assertNull(it.ratingCount)
                assertFalse(it.requiresSellingPlan)
                assertTrue("a product's own variants carry no stock, rules or plans", it.variants.all { v -> v.quantityRule == null && v.sellingPlanAllocations.isEmpty() })
            }
            "ProductMetafields" -> assertEquals(
                "the one it has a value for: the null is dropped",
                listOf(Metafield("custom", "material", "single_line_text_field", "100% organic cotton")),
                storefront.productMetafields("men-crewneck", listOf(MetafieldIdentifier("custom", "material"), MetafieldIdentifier("custom", "care"))),
            )
            "ProductRecommendations" -> storefront.recommendations("gid://shopify/Product/7982905098262").let {
                assertEquals(listOf("hoodie-old", "men-t-shirt", "sweatpants"), it.map { p -> p.handle })
                assertNull(it[0].compareAt)
            }
            "Products" -> storefront.productsByIds(listOf("gid://shopify/Product/7982905098262", "gid://shopify/Product/1", "gid://shopify/Product/7982856273942")).let {
                assertEquals("the id that is no product (a null node) is left out", listOf("men-crewneck", "sweatpants"), it.map { p -> p.handle })
                val crewneck = it[0]
                assertEquals(4.6, crewneck.rating!!, 0.0)
                assertEquals(128, crewneck.ratingCount)
                assertEquals(CardVariant("gid://shopify/ProductVariant/43696905224214", "CREW-S-GRN", true, QuantityRule(2, 40, 2)), crewneck.firstVariant)
                assertEquals(listOf("#3F6B4F", "#6B6B3A", "#2F6F8F"), crewneck.colors.map { c -> c.swatch?.color })
                assertNull("sizes and colours to choose from", crewneck.quickAddVariantId)
                assertNull(it[1].rating)
            }
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
                assertEquals("CREW-S-OLV", it.sku)
                assertNull(it.compareAt)
                assertEquals("0123456789012", it.barcode)
                assertEquals(4, it.quantityAvailable)
                assertFalse(it.currentlyNotInStock)
                assertEquals(Money("60.0", "CAD"), it.unitPrice)
                assertEquals(UnitPriceMeasurement("COUNT", "ITEM", 2.0, "ITEM", 1), it.unitPriceMeasurement)
                assertEquals(QuantityRule(2, 40, 2), it.quantityRule)
                assertEquals(listOf(10 to Money("108.0", "CAD"), 20 to Money("96.0", "CAD")), it.quantityPriceBreaks.map { b -> b.minimumQuantity to b.price })
                assertTrue("a bundle", it.requiresComponents)
                assertEquals(listOf("men-t-shirt", "sweatpants"), it.components.map { c -> c.variant.product.handle })
                assertEquals(1, it.components[0].quantity)
                assertEquals(Money("40.0", "CAD"), it.components[0].variant.price)
                assertTrue(it.components[0].variant.image!!.url.endsWith(".jpg"))
                val bundle = it.groupedBy.single()
                assertEquals("Weekend set", bundle.title)
                assertEquals("hoodie-old", bundle.product.handle)
                assertTrue("a bundle is shown by its product's image", bundle.image!!.url.endsWith(".jpg"))
                val plan = it.sellingPlanAllocations.single()
                assertEquals(SellingPlan("gid://shopify/SellingPlan/4400001", "Deliver every month"), plan.sellingPlan)
                assertEquals(Money("108.0", "CAD"), plan.priceAdjustments.single().price)
                assertEquals(Money("120.0", "CAD"), plan.priceAdjustments.single().compareAtPrice)
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
            "CustomerCompanies" -> account.companies().single().let {
                assertEquals("gid://shopify/CompanyContact/9000001", it.id)
                assertEquals("Purchasing lead", it.title)
                assertEquals("Analytical Engines Ltd", it.company.name)
                assertEquals(
                    listOf(CompanyLocation("gid://shopify/CompanyLocation/9200001", "Ottawa head office"), CompanyLocation("gid://shopify/CompanyLocation/9200002", "Toronto warehouse")),
                    it.company.locations,
                )
            }
            "CustomerStoreCredit" -> assertEquals(
                listOf(StoreCreditAccount("gid://shopify/StoreCreditAccount/9300001", Money("25.0", "CAD"))),
                account.storeCredit(),
            )
            "CustomerEmailMarketingSubscribe" -> assertEquals("SUBSCRIBED", account.subscribeEmailMarketing().marketingState)
            "CustomerEmailMarketingUnsubscribe" -> assertEquals("UNSUBSCRIBED", account.unsubscribeEmailMarketing().marketingState)
            "CustomerUpdate" -> assertEquals("Ada King", account.updateName("Ada", "King").displayName)
            "Order" -> account.order("gid://shopify/Order/6001004")!!.let {
                assertEquals("#1004", it.name)
                assertEquals(Money("271.9", "CAD"), it.total)
                assertEquals(Money("230.0", "CAD"), it.subtotal)
                assertEquals(Money("35.0", "CAD"), it.totalRefunded)
                assertEquals("PARTIALLY_REFUNDED", it.financialStatus)
                assertEquals("FULFILLED", it.fulfillmentStatus)
                assertFalse(it.edited)
                assertTrue(it.requiresShipping)
                assertEquals("Please leave the parcel at the front desk.", it.note)
                assertEquals(PricingValue.Percentage(10.0), it.discountApplications.single().value)
                assertEquals("Ottawa", it.shippingAddress?.city)
                assertEquals(OrderShippingLine("Standard shipping", Money("12.0", "CAD")), it.shippingLine)

                // B2B
                assertEquals("PO-2291", it.poNumber)
                assertEquals("Analytical Engines Ltd", it.purchasingCompany?.company?.name)
                assertEquals("Ottawa head office", it.purchasingCompany?.location?.name)

                // payment
                val payment = it.paymentInformation!!
                assertEquals("PARTIALLY_REFUNDED", payment.paymentStatus)
                assertEquals(Money("0.0", "CAD"), payment.totalOutstandingAmount)
                assertNull("nothing left to pay", payment.paymentCollectionUrl)
                assertEquals(PaymentTerms("Net 30", "2026-10-21T09:40:00Z", overdue = false), payment.paymentTerms)
                assertEquals(listOf("SALE", "REFUND"), it.transactions.map { t -> t.kind })
                assertEquals("visa", it.transactions[0].cardBrand)
                assertEquals("4242", it.transactions[0].last4)
                assertNull("paid by card, not with a gift card", it.transactions[0].giftCardLast4)
                assertEquals(Money("271.9", "CAD"), it.transactions[0].amount)

                assertEquals(listOf("Men's Crewneck", "Sweatpants", "Men's T-shirt"), it.lines.map { l -> l.title })
                val line = it.lines[1]
                assertEquals("SWEATPANTS-MG", line.sku)
                assertEquals(2, line.quantity)
                assertEquals("both were returned and refunded", 0, line.refundableQuantity)
                assertEquals(Money("70.0", "CAD"), line.total)
                assertEquals(Money("0.0", "CAD"), line.totalDiscount)

                val fulfillment = it.fulfillments.single()
                assertEquals("SUCCESS", fulfillment.status)
                assertEquals("DELIVERED", fulfillment.latestShipmentStatus)
                assertFalse(fulfillment.isPickedUp)
                assertEquals("Canada Post", fulfillment.trackingInformation.single().company)
                assertEquals(listOf("CONFIRMED", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED"), fulfillment.events.map { e -> e.status })
                assertEquals("2026-09-25T13:05:00Z", fulfillment.events.last().happenedAt)
                assertEquals(it.lines.map { l -> l.id }, fulfillment.fulfillmentLineItems.map { f -> f.lineItem.id })

                // refunds and returns
                assertEquals(OrderRefund("gid://shopify/Refund/7300001", "2026-10-02T10:15:00Z", "#1004-R1", Money("35.0", "CAD")), it.refunds.single())
                val returned = it.returns.single()
                assertEquals("#1004-R1", returned.name)
                assertEquals("CLOSED", returned.status)
                assertEquals("2026-10-02T10:15:00Z", returned.closedAt)
                assertNull(returned.decline)
                val returnedLine = returned.lines.single()
                assertEquals(2, returnedLine.quantity)
                assertEquals("Size was too small", returnedLine.reason)
                assertEquals("Sweatpants", returnedLine.title)
                assertEquals("Medium / Green", returnedLine.variantTitle)
                assertEquals(line.id, returnedLine.lineItemId)
                assertTrue(returnedLine.image!!.url.endsWith(".jpg"))
                val exchange = returned.exchangeLines.single()
                assertEquals("Sweatpants", exchange.title)
                assertEquals("Large / Green", exchange.variantTitle)
                assertEquals(1, exchange.quantity)
                assertTrue("an item can still be returned", it.hasReturnableItems)
            }
            "OrderRequestReturn" -> account.requestReturn("gid://shopify/Order/6001004", listOf(RequestedLineItemInput("gid://shopify/LineItem/5000001", 1))).let {
                assertEquals("REQUESTED", it.status)
                assertEquals("#1004-R2", it.name)
            }
            "OrderReturnOptions" -> account.returnOptions("gid://shopify/Order/6001004")!!.let {
                assertEquals("#1004", it.orderName)
                assertEquals(listOf("Men's Crewneck", "Men's T-shirt"), it.returnableLineItems.map { r -> r.lineItem.title })
                val item = it.returnableLineItems[0]
                assertEquals(1, item.quantity)
                assertEquals("Medium / Olive", item.lineItem.variantTitle)
                assertEquals("MENCREWNECK-MO", item.lineItem.sku)
                assertEquals("gid://shopify/Product/7982905098262", item.lineItem.productId)
                assertEquals("gid://shopify/ProductVariant/43696905224214", item.lineItem.variantId)
                assertEquals(Money("120.0", "CAD"), item.lineItem.price)
                assertEquals(
                    listOf("size-too-small", "size-too-large", "not-as-described", "changed-my-mind", "damaged"),
                    item.lineItem.suggestedReturnReasonDefinitions.map { r -> r.handle },
                )
                assertTrue(it.hasReturnShippingFee)
                assertFalse(it.hasRestockingFee)
                assertEquals(listOf("MERCHANT_PROVIDED_LABEL"), it.returnShippingMethods)
                assertEquals("We email a prepaid label once the return is approved.", it.returnShippingMethodNote)
                val fee = it.fees.single()
                assertEquals("ReturnShippingFee", fee.kind)
                assertEquals("Return shipping", fee.title)
                assertEquals(Money("8.0", "CAD"), fee.amount)
                assertEquals("Sweatpants were already returned.", it.nonReturnableSummary)
                assertEquals("#1004-R1", it.returns.single().name)
                assertTrue("the options' returns carry no lines", it.returns.single().lines.isEmpty())
            }
            "Orders" -> account.orders().let {
                assertEquals(listOf("#1005", "#1004", "#1003", "#1002"), it.items.map { o -> o.name })
                assertFalse(it.hasNextPage)
                assertEquals("eyJsYXN0X2lkIjoxMDAyfQ==", it.endCursor)
                val shipping = it.items[0]
                assertEquals(Money("158.9", "CAD"), shipping.total)
                assertEquals(4, shipping.itemCount)
                assertEquals(listOf("Half Zip", "Workout Shirt"), shipping.titles)
                assertEquals(2, shipping.images.size)
                assertTrue(shipping.images[0].url.endsWith(".jpg"))
                assertEquals("IN_TRANSIT", shipping.latestShipmentStatus)
                assertEquals("2026-10-14T18:00:00Z", shipping.estimatedDeliveryAt)
                assertNull("not delivered yet", shipping.latestFulfillmentDeliveryDate)
                assertEquals("2026-09-25T13:05:00Z", it.items[1].latestFulfillmentDeliveryDate)
                assertEquals("DELIVERED", it.items[1].latestShipmentStatus)
                assertNull("nothing shipped yet", it.items[2].latestShipmentStatus)
                assertEquals("2026-07-14T16:00:00Z", it.items[3].cancelledAt)
            }
            else -> fail("No facade call decodes $operation: add a case to ContractFixturesTest")
        }
    }
}
