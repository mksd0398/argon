package app.storefront.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AnalyticsProvidersTest {
    private val crewneck = AnalyticsItem(
        productId = "7982905098262",
        variantId = "43696905224214",
        name = "Men's Crewneck",
        brand = "Mock.shop",
        category = "Tops",
        variant = "Small / Green",
        price = 120.0,
        quantity = 2,
    )

    /** An item with nothing but what every item has. */
    private val gift = AnalyticsItem(productId = "5", name = "Gift")
    private val both = listOf(crewneck, gift)

    private val purchase = AnalyticsEvent.Purchase("5800467808278", 381.12, "CAD", tax = 42.12, shipping = 15.0, coupon = "WELCOME10", items = both)

    /** The four events about one product. */
    private val aboutOne = listOf(
        AnalyticsEvent.ViewItem(crewneck, "CAD"), AnalyticsEvent.AddToWishlist(crewneck, "CAD"), AnalyticsEvent.AddToCart(crewneck, "CAD"),
        AnalyticsEvent.RemoveFromCart(crewneck, "CAD"),
    )

    // Google Analytics 4

    private val crewneckItem = mapOf(
        "item_id" to "7982905098262", "item_name" to "Men's Crewneck", "item_brand" to "Mock.shop", "item_category" to "Tops",
        "item_variant" to "Small / Green", "price" to 120.0, "quantity" to 2,
    )
    private val giftItem = mapOf("item_id" to "5", "item_name" to "Gift", "quantity" to 1)

    @Test
    fun googleAnalyticsGetsEveryEventWithItsItemsAsAList() {
        assertEquals(mapOf("screen_name" to "home"), ga4Params(AnalyticsEvent.ScreenView("home")))
        assertEquals(
            mapOf("item_list_id" to "1", "item_list_name" to "Men", "items" to listOf(crewneckItem, giftItem)),
            ga4Params(AnalyticsEvent.ViewItemList("1", "Men", both)),
        )
        // worth the two of it
        for (event in aboutOne) assertEquals(event.name, mapOf("currency" to "CAD", "value" to 240.0, "items" to listOf(crewneckItem)), ga4Params(event))
        assertEquals(mapOf("search_term" to "shoes"), ga4Params(AnalyticsEvent.Search("shoes")))
        assertEquals(
            mapOf("value" to 240.0, "currency" to "CAD", "items" to listOf(crewneckItem, giftItem)),
            ga4Params(AnalyticsEvent.ViewCart(both, 240.0, "CAD")),
        )
        assertEquals(
            mapOf("value" to 240.0, "currency" to "CAD", "coupon" to "VIP", "items" to listOf(crewneckItem, giftItem)),
            ga4Params(AnalyticsEvent.BeginCheckout(both, 240.0, "CAD", coupon = "VIP")),
        )
        assertEquals(mapOf("value" to 240.0, "currency" to "CAD"), ga4Params(AnalyticsEvent.AddShippingInfo(240.0, "CAD")))
        assertEquals(mapOf("value" to 240.0, "currency" to "CAD"), ga4Params(AnalyticsEvent.AddPaymentInfo(240.0, "CAD")))
        assertEquals(emptyMap<String, Any>(), ga4Params(AnalyticsEvent.Login))

        assertEquals("no price, no value", mapOf("currency" to "CAD", "items" to listOf(giftItem)), ga4Params(AnalyticsEvent.ViewItem(gift, "CAD")))
        assertEquals("amounts are decimal", 59.97, ga4Params(AnalyticsEvent.AddToCart(crewneck.copy(price = 19.99, quantity = 3), "CAD"))!!["value"])
    }

    @Test
    fun googleAnalyticsPurchaseIsWorthTheOrderWithoutTaxAndShipping() {
        assertEquals(
            mapOf(
                "transaction_id" to "5800467808278", "value" to 324.0, "currency" to "CAD", "tax" to 42.12, "shipping" to 15.0,
                "coupon" to "WELCOME10", "items" to listOf(crewneckItem, giftItem),
            ),
            ga4Params(purchase),
        )
        assertEquals("only the one that is known", 366.12, ga4Params(purchase.copy(tax = null))!!["value"])
        assertEquals("neither: the total", 381.12, ga4Params(purchase.copy(tax = null, shipping = null))!!["value"])
    }

    @Test
    fun googleAnalyticsIsNotSentThePurchaseTheServerReports() {
        assertNull(ga4Params(purchase, serverPurchase = true))
        // everything else as before
        assertEquals(mapOf("value" to 240.0, "currency" to "CAD"), ga4Params(AnalyticsEvent.AddPaymentInfo(240.0, "CAD"), serverPurchase = true))
        for (event in aboutOne) assertEquals(event.name, ga4Params(event), ga4Params(event, serverPurchase = true))
    }

    // Meta

    private fun contents(id: String, content: String, count: Int) =
        mapOf("fb_content_id" to id, "fb_content" to content, "fb_content_type" to "product", "fb_currency" to "CAD", "fb_num_items" to count)

    /** By the variant where there is one: what a catalog synced from Shopify lists. */
    private val one = contents("43696905224214", """[{"id":"43696905224214","quantity":2}]""", 2)
    private val two = contents("""["43696905224214","5"]""", """[{"id":"43696905224214","quantity":2},{"id":"5","quantity":1}]""", 3)

    @Test
    fun metaGetsItsStandardEvents() {
        assertEquals(MetaEvent("fb_mobile_content_view", 240.0, one), metaEvent(AnalyticsEvent.ViewItem(crewneck, "CAD")))
        assertEquals(MetaEvent("fb_mobile_search", null, mapOf("fb_search_string" to "shoes")), metaEvent(AnalyticsEvent.Search("shoes")))
        assertEquals(MetaEvent("fb_mobile_add_to_wishlist", 240.0, one), metaEvent(AnalyticsEvent.AddToWishlist(crewneck, "CAD")))
        assertEquals(MetaEvent("fb_mobile_add_to_cart", 240.0, one), metaEvent(AnalyticsEvent.AddToCart(crewneck, "CAD")))
        assertEquals(
            MetaEvent("fb_mobile_initiated_checkout", 240.0, two),
            metaEvent(AnalyticsEvent.BeginCheckout(both, 240.0, "CAD", coupon = "VIP")),
        )
        assertEquals(MetaEvent("fb_mobile_add_payment_info", null, mapOf("fb_success" to 1)), metaEvent(AnalyticsEvent.AddPaymentInfo(240.0, "CAD")))
    }

    @Test
    fun metaPurchaseIsWorthTheOrdersTotalUnderTheIdTheServerSendsItBy() {
        assertEquals(MetaEvent("fb_mobile_purchase", 381.12, two + ("event_id" to "purchase-5800467808278")), metaEvent(purchase))
    }

    @Test
    fun metaIsNotSentWhatItHasNoStandardEventFor() {
        val others = listOf(
            AnalyticsEvent.ScreenView("home"), AnalyticsEvent.ViewItemList("1", "Men", both), AnalyticsEvent.RemoveFromCart(crewneck, "CAD"),
            AnalyticsEvent.ViewCart(both, 240.0, "CAD"), AnalyticsEvent.AddShippingInfo(240.0, "CAD"), AnalyticsEvent.Login,
        )
        for (event in others) assertNull(event.name, metaEvent(event))
    }

    @Test
    fun metaExtinfoIsTheSixteenTextsOfTheAndroidLayout() {
        assertEquals(
            """["a2","com.mockshop.demo","7","1.2","16","Pixel 9","en_CA","EDT","Bell","1080","2424","2.625","8","110","64","America/Toronto"]""",
            metaExtinfo(
                packageName = "com.mockshop.demo",
                versionCode = 7,
                versionName = "1.2",
                osVersion = "16",
                model = "Pixel 9",
                locale = "en_CA",
                timezoneAbbreviation = "EDT",
                carrier = "Bell",
                screenWidth = 1080,
                screenHeight = 2424,
                screenDensity = 2.625f,
                cores = 8,
                storageGb = 110,
                freeStorageGb = 64,
                timezone = "America/Toronto",
            ),
        )
    }

    // MoEngage

    @Test
    fun moEngageGetsEveryEventUnderItsShopifyIntegrationsNames() {
        val product = mapOf(
            "Product ID" to "7982905098262", "Product Title" to "Men's Crewneck", "Variation ID" to "43696905224214",
            "Variation Title" to "Small / Green", "Vendor Name" to "Mock.shop", "Price" to 120.0, "Currency" to "CAD", "Quantity" to 2,
        )
        // the gift has no variant, price or vendor to list
        val products = mapOf(
            "Product IDs" to listOf("7982905098262", "5"), "Product Titles" to listOf("Men's Crewneck", "Gift"),
            "Variation IDs" to listOf("43696905224214"), "Product Prices" to listOf(120.0), "Product Quantities" to listOf(2, 1),
            "Vendor Names" to listOf("Mock.shop"),
        )
        val total = mapOf("Total Price" to 240.0, "Currency" to "CAD")

        assertEquals("Screen Viewed" to mapOf("Screen Name" to "home"), moEngageEvent(AnalyticsEvent.ScreenView("home")))
        assertEquals(
            "Product List Viewed" to mapOf("List ID" to "1", "List Name" to "Men") + products,
            moEngageEvent(AnalyticsEvent.ViewItemList("1", "Men", both)),
        )
        assertEquals(
            listOf("Product Viewed" to product, "Wishlist Added" to product, "Add to Cart" to product, "Removed From Cart" to product),
            aboutOne.map(::moEngageEvent),
        )
        assertEquals("Product Searched" to mapOf("Search String" to "shoes"), moEngageEvent(AnalyticsEvent.Search("shoes")))
        assertEquals("Cart Viewed" to total + products, moEngageEvent(AnalyticsEvent.ViewCart(both, 240.0, "CAD")))
        assertEquals(
            "Checkout Started" to mapOf("Total Price" to 240.0, "currency" to "CAD", "Coupon" to "VIP") + products,
            moEngageEvent(AnalyticsEvent.BeginCheckout(both, 240.0, "CAD", coupon = "VIP")),
        )
        assertEquals("Shipping Info Added" to total, moEngageEvent(AnalyticsEvent.AddShippingInfo(240.0, "CAD")))
        assertEquals("Payment Info Added" to total, moEngageEvent(AnalyticsEvent.AddPaymentInfo(240.0, "CAD")))
        assertEquals(
            "Order Placed" to mapOf(
                "Order ID" to "5800467808278", "Total Price" to 381.12, "Currency" to "CAD", "Tax" to 42.12, "Shipping" to 15.0, "Coupon" to "WELCOME10",
            ) + products,
            moEngageEvent(purchase),
        )
        assertEquals("Customer Logged In" to emptyMap<String, Any>(), moEngageEvent(AnalyticsEvent.Login))

        assertEquals(
            "only what the item has, and no list no item has anything for",
            "Product List Viewed" to mapOf("List Name" to "Search results", "Product IDs" to listOf("5"), "Product Titles" to listOf("Gift"), "Product Quantities" to listOf(1)),
            moEngageEvent(AnalyticsEvent.ViewItemList(null, "Search results", listOf(gift))),
        )
    }
}
