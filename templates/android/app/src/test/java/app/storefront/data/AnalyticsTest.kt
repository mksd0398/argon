package app.storefront.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import app.storefront.ui.screenName
import com.shopify.checkoutsheetkit.lifecycleevents.CartInfo
import com.shopify.checkoutsheetkit.lifecycleevents.CartLine as OrderLine
import com.shopify.checkoutsheetkit.lifecycleevents.Discount
import com.shopify.checkoutsheetkit.lifecycleevents.OrderDetails
import com.shopify.checkoutsheetkit.lifecycleevents.Price
import com.shopify.checkoutsheetkit.pixelevents.Checkout
import com.shopify.checkoutsheetkit.pixelevents.CustomPixelEvent
import com.shopify.checkoutsheetkit.pixelevents.MoneyV2
import com.shopify.checkoutsheetkit.pixelevents.StandardPixelEvent
import com.shopify.checkoutsheetkit.pixelevents.StandardPixelEventData
import java.io.File
import java.io.IOException
import java.util.logging.Handler
import java.util.logging.LogRecord
import java.util.logging.Logger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AnalyticsTest {
    @get:Rule val tmp = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After fun stop() = scope.cancel()

    private val cart = runBlocking { fixtureStorefront().cart("any")!! }
    private val line = cart.lines.single()

    /** The fixture cart's line as an item: [quantity] of the crewneck. */
    private fun crewneck(quantity: Int) = AnalyticsItem(
        productId = "7982905098262",
        variantId = "43696905224214",
        name = "Men's Crewneck",
        variant = "Small / Green",
        price = 120.0,
        quantity = quantity,
    )

    // The events

    @Test
    fun everyEventHasGoogleAnalyticsName() {
        val item = crewneck(1)
        val events = listOf(
            AnalyticsEvent.ScreenView("home"), AnalyticsEvent.ViewItemList("1", "Men", listOf(item)), AnalyticsEvent.ViewItem(item, "CAD"),
            AnalyticsEvent.Search("shoes"), AnalyticsEvent.AddToWishlist(item, "CAD"), AnalyticsEvent.AddToCart(item, "CAD"),
            AnalyticsEvent.RemoveFromCart(item, "CAD"), AnalyticsEvent.ViewCart(listOf(item), 120.0, "CAD"),
            AnalyticsEvent.BeginCheckout(listOf(item), 120.0, "CAD"), AnalyticsEvent.AddShippingInfo(120.0, "CAD"),
            AnalyticsEvent.AddPaymentInfo(120.0, "CAD"), AnalyticsEvent.Purchase("1", 120.0, "CAD", items = listOf(item)), AnalyticsEvent.Login,
        )
        assertEquals(
            listOf(
                "screen_view", "view_item_list", "view_item", "search", "add_to_wishlist", "add_to_cart", "remove_from_cart", "view_cart",
                "begin_checkout", "add_shipping_info", "add_payment_info", "purchase", "login",
            ),
            events.map { it.name },
        )
    }

    @Test
    fun paramsAreFlatAndLeaveOutWhatAnEventHasNoneOf() {
        assertEquals(mapOf("screen_name" to "home"), AnalyticsEvent.ScreenView("home").params)
        assertEquals(
            mapOf(
                "item_id" to "7982905098262", "variant_id" to "43696905224214", "item_name" to "Men's Crewneck",
                "item_variant" to "Small / Green", "price" to 120.0, "quantity" to 2, "currency" to "CAD",
            ),
            AnalyticsEvent.AddToCart(crewneck(2), "CAD").params,
        )
        assertEquals(
            mapOf("transaction_id" to "9", "value" to 324.0, "currency" to "CAD", "tax" to 0.0, "items" to listOf("7982905098262/43696905224214 x3", "5 x1")),
            AnalyticsEvent.Purchase("9", 324.0, "CAD", tax = 0.0, items = listOf(crewneck(3), AnalyticsItem(productId = "5", name = "Gift"))).params,
        )
        assertEquals(emptyMap<String, Any>(), AnalyticsEvent.Login.params)
    }

    // The mappers

    @Test
    fun idsAreTheNumericTailOfTheGid() {
        assertEquals("123", gidTail("gid://shopify/Product/123"))
        assertEquals("c1-4c87", gidTail("gid://shopify/Cart/c1-4c87?key=2921"))
        assertEquals("123", gidTail("123"))
    }

    @Test
    fun aCartLineIsAnItemAtItsUnitPrice() {
        assertEquals(crewneck(3), line.analyticsItem())
        assertEquals("a change of two is about two", crewneck(2), line.analyticsItem(2))
        val plain = line.copy(merchandise = line.merchandise.copy(title = "Default Title"))
        assertNull("a product without options has no variant worth naming", plain.analyticsItem().variant)
    }

    @Test
    fun aProductIsAnItemByTheVariantItsPageOpensOn() = runBlocking {
        val product = fixtureStorefront().product("men-crewneck")!!
        // mock.shop is every product's vendor; none has a product type
        assertEquals(crewneck(1).copy(brand = "Mock.shop"), product.analyticsItem())
        assertEquals("CAD", product.analyticsCurrency)

        val soldOut = product.copy(variants = product.variants.mapIndexed { i, variant -> variant.copy(available = i == 1) }, productType = "Tops")
        assertEquals("the first one that can be bought", gidTail(product.variants[1].id), soldOut.analyticsItem().variantId)
        assertEquals("Tops", soldOut.analyticsItem().category)

        val bare = product.copy(variants = emptyList())
        assertEquals("without variants: the product, from its lowest price", crewneck(1).copy(brand = "Mock.shop", variantId = null, variant = null), bare.analyticsItem())
        assertEquals("", bare.copy(priceRange = null).analyticsCurrency)
    }

    @Test
    fun aProductCardIsAnItemByTheVariantTheListShowsItBy() = runBlocking {
        val card = fixtureStorefront().collection("men")!!.products.items.first()
        assertEquals(
            AnalyticsItem(productId = "7982904639510", variantId = "43696903847958", name = "Hoodie", brand = "Mock.shop", price = 90.0),
            card.analyticsItem(),
        )
    }

    @Test
    fun aCustomerIsAUserByTheirNumericId() = runBlocking {
        val customer = CustomerAccountApi({ name, _ -> fixture(name) }).customer()
        assertEquals(AnalyticsUser("7000001", "ada@example.com", "+16135550123", "Ada", "Lovelace"), customer.analyticsUser())
    }

    @Test
    fun aChangeOfTheLinesIsAnAddOrARemoveOfEachDifference() {
        fun held(id: String, quantity: Int) = line.copy(id = id, quantity = quantity)
        assertEquals(
            listOf(
                AnalyticsEvent.AddToCart(crewneck(2), "CAD"), // a: 3, now 5
                AnalyticsEvent.AddToCart(crewneck(1), "CAD"), // c: new
                AnalyticsEvent.RemoveFromCart(crewneck(1), "CAD"), // d: 4, now 3
                AnalyticsEvent.RemoveFromCart(crewneck(2), "CAD"), // b: gone
            ),
            cartLineEvents(
                before = listOf(held("a", 3), held("b", 2), held("d", 4), held("e", 1)),
                after = listOf(held("a", 5), held("c", 1), held("d", 3), held("e", 1)),
            ),
        )
        assertEquals("nothing changed, nothing to report", emptyList<AnalyticsEvent>(), cartLineEvents(cart.lines, cart.lines))
    }

    @Test
    fun theCartIsViewedAndCheckedOutAtItsTotalWithTheCodesThatCount() {
        assertEquals(AnalyticsEvent.ViewCart(listOf(crewneck(3)), 324.0, "CAD"), viewCart(cart))
        // the fixture's WELCOME10 doesn't apply to it
        assertEquals(AnalyticsEvent.BeginCheckout(listOf(crewneck(3)), 324.0, "CAD", coupon = null), beginCheckout(cart))
        val codes = listOf(Cart.DiscountCode("VIP", applicable = true), Cart.DiscountCode("NOPE"), Cart.DiscountCode("TEN", applicable = true))
        assertEquals("VIP,TEN", beginCheckout(cart.copy(discountCodes = codes)).coupon)
    }

    @Test
    fun aCompletedOrderIsThePurchase() {
        fun cad(amount: Double) = MoneyV2(amount, "CAD")
        val bought = OrderLine(
            discounts = null,
            image = null,
            merchandiseId = "gid://shopify/ProductVariant/43696905224214",
            price = cad(120.0),
            productId = "gid://shopify/Product/7982905098262",
            quantity = 3,
            title = "Men's Crewneck",
        )
        fun order(price: Price, vararg lines: OrderLine) = OrderDetails(
            billingAddress = null,
            cart = CartInfo(lines = lines.toList(), price = price, token = "t"),
            deliveries = emptyList(),
            email = null,
            id = "gid://shopify/OrderIdentity/5800467808278",
            paymentMethods = emptyList(),
            phone = null,
        )

        val discounts = listOf(Discount(title = "WELCOME10"), Discount(title = "Summer sale"), Discount())
        val full = Price(discounts = discounts, shipping = cad(15.0), subtotal = cad(360.0), taxes = cad(42.12), total = cad(381.12))
        assertEquals(
            AnalyticsEvent.Purchase(
                orderId = "5800467808278",
                value = 381.12,
                currency = "CAD",
                tax = 42.12,
                shipping = 15.0,
                coupon = "WELCOME10,Summer sale",
                // the order's line has no variant title
                items = listOf(crewneck(3).copy(variant = null)),
            ),
            purchase(order(full, bought)),
        )

        // what an order may leave out: the ids of a line, and every amount but the line's own
        val bare = purchase(order(Price(), bought.copy(merchandiseId = null, productId = null)))
        assertEquals(
            AnalyticsEvent.Purchase("5800467808278", 0.0, "", items = listOf(AnalyticsItem(productId = "", name = "Men's Crewneck", price = 120.0, quantity = 3))),
            bare,
        )
    }

    @Test
    fun onlyTheShippingAndPaymentPixelEventsAreCheckoutSteps() {
        val priced = Checkout(currencyCode = "CAD", totalPrice = MoneyV2(324.0, "CAD"))
        fun standard(name: String, checkout: Checkout? = priced) = StandardPixelEvent(name = name, data = StandardPixelEventData(checkout))

        assertEquals(AnalyticsEvent.AddShippingInfo(324.0, "CAD"), checkoutStep(standard("checkout_shipping_info_submitted")))
        assertEquals(AnalyticsEvent.AddPaymentInfo(324.0, "CAD"), checkoutStep(standard("payment_info_submitted")))
        // the app reports these itself: begin_checkout as the sheet opens, the purchase from the completed order
        for (name in listOf("checkout_started", "checkout_completed", "checkout_contact_info_submitted", "page_viewed")) {
            assertNull(name, checkoutStep(standard(name)))
        }
        assertNull("a store's custom event", checkoutStep(CustomPixelEvent(name = "payment_info_submitted")))
        assertNull("no total to report", checkoutStep(standard("payment_info_submitted", checkout = null)))
        assertNull(checkoutStep(standard("payment_info_submitted", Checkout(currencyCode = "CAD"))))
        assertEquals(
            "the currency of the total when the checkout names none",
            AnalyticsEvent.AddPaymentInfo(324.0, "CAD"),
            checkoutStep(standard("payment_info_submitted", Checkout(totalPrice = MoneyV2(324.0, "CAD")))),
        )
    }

    @Test
    fun aScreenIsNamedByTheFirstPartOfItsRoute() {
        assertEquals(
            listOf("home", "product", "collection", "search", "order", "orders", "return", "policy"),
            listOf("home", "product/{handle}", "collection/{handle}", "search?q={q}", "order/{id}", "orders", "return/{orderId}", "policy/{handle}").map(::screenName),
        )
    }

    // The hub

    private val ada = AnalyticsUser("7000001", email = "ada@example.com")

    private class Recorder(private val attributes: Map<String, String> = emptyMap()) : AnalyticsSink {
        val events = mutableListOf<AnalyticsEvent>()
        val users = mutableListOf<AnalyticsUser?>()

        override fun track(event: AnalyticsEvent) {
            events += event
        }

        override fun identify(user: AnalyticsUser?) {
            users += user
        }

        override suspend fun cartAttributes() = attributes
    }

    @Test
    fun nothingIsReportedWhileTheShopperDoesNotAllowIt() = runBlocking {
        var allowed = false
        val sink = Recorder(mapOf("_ga_app_instance_id" to "abc"))
        val analytics = Analytics(listOf(sink)) { allowed }

        analytics.track(AnalyticsEvent.Login)
        analytics.identify(ada)
        assertEquals(emptyList<AnalyticsEvent>(), sink.events)
        assertEquals(emptyList<AnalyticsUser?>(), sink.users)
        assertEquals("nor does a new cart say whose it is", emptyMap<String, String>(), analytics.cartAttributes())

        allowed = true
        analytics.track(AnalyticsEvent.Search("shoes"))
        analytics.identify(ada)
        analytics.identify(null)
        assertEquals(listOf<AnalyticsEvent>(AnalyticsEvent.Search("shoes")), sink.events)
        assertEquals(listOf(ada, null), sink.users)
    }

    @Test
    fun aSinkThatThrowsIsSkippedAndTheOthersStillHearEverything() = runBlocking {
        val broken = object : AnalyticsSink {
            override fun track(event: AnalyticsEvent): Unit = throw IllegalStateException("sdk")
            override fun identify(user: AnalyticsUser?): Unit = throw IllegalStateException("sdk")
            override suspend fun cartAttributes(): Map<String, String> = throw IllegalStateException("sdk")
        }
        val sink = Recorder(mapOf("_meta_anon_id" to "xyz"))
        val analytics = Analytics(listOf(broken, sink)) { true }

        // nothing reaches the caller
        analytics.track(AnalyticsEvent.Login)
        analytics.identify(ada)
        assertEquals(listOf<AnalyticsEvent>(AnalyticsEvent.Login), sink.events)
        assertEquals(listOf<AnalyticsUser?>(ada), sink.users)
        assertEquals(mapOf("_meta_anon_id" to "xyz", "_argon_platform" to "android"), analytics.cartAttributes())
    }

    @Test
    fun aNewCartCarriesEverySinksAttributesAndThePlatform() = runBlocking {
        val both = Analytics(listOf(Recorder(mapOf("_ga_app_instance_id" to "abc")), Recorder(mapOf("_meta_anon_id" to "xyz", "_meta_tracking" to "1")))) { true }
        assertEquals(
            mapOf("_ga_app_instance_id" to "abc", "_meta_anon_id" to "xyz", "_meta_tracking" to "1", "_argon_platform" to "android"),
            both.cartAttributes(),
        )
        assertEquals("a sink with none of its own", mapOf("_argon_platform" to "android"), Analytics(listOf(LogSink())) { true }.cartAttributes())
        assertEquals("no sink: an order of the app's is nobody's to report", emptyMap<String, String>(), Analytics(emptyList()) { true }.cartAttributes())
    }

    @Test
    fun theLogWritesOneLinePerEventAndOfTheCustomerOnlyTheId() {
        val lines = mutableListOf<String>()
        val handler = object : Handler() {
            // logcat shows a record as "<its logger's name>: <its message>"
            override fun publish(record: LogRecord) {
                lines += "${record.loggerName}: ${record.message}"
            }

            override fun flush() {}

            override fun close() {}
        }
        val logger = Logger.getLogger("Analytics")
        logger.addHandler(handler)
        try {
            val log = LogSink()
            log.track(AnalyticsEvent.Search("shoes"))
            log.track(AnalyticsEvent.ViewCart(listOf(crewneck(3)), 324.0, "CAD"))
            log.track(AnalyticsEvent.Login)
            log.identify(ada)
            log.identify(null)
        } finally {
            logger.removeHandler(handler)
        }
        assertEquals(
            listOf(
                "Analytics: search {search_term=shoes}",
                "Analytics: view_cart {value=324.0, currency=CAD, items=[7982905098262/43696905224214 x3]}",
                "Analytics: login {}",
                "Analytics: identify 7000001",
                "Analytics: identify null",
            ),
            lines,
        )
    }

    // Consent

    private fun consent(on: CoroutineScope = scope) =
        AnalyticsConsentStore(PreferenceDataStoreFactory.create(scope = on) { File(tmp.root, "analytics.preferences_pb") }, on)

    /** Waits for [AnalyticsConsentStore.allowed] to be [expected]; null when it never is. */
    private fun AnalyticsConsentStore.becomes(expected: Boolean, millis: Long = 5_000) = runBlocking { withTimeoutOrNull(millis) { allowed.first { it == expected } } }

    @Test
    fun usageDataIsSharedUntilTheShopperTurnsItOffAndTheChoiceIsRemembered() = runBlocking {
        val first = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val s = consent(first)
        assertEquals("on by default", true, s.becomes(true))
        s.set(false)
        assertEquals(false, s.becomes(false))
        first.coroutineContext[Job]!!.cancelAndJoin() // the process ends: its DataStore is closed

        val again = consent()
        assertNull("still off once the file is read", again.becomes(true, millis = 500))
        again.set(true)
        assertEquals(true, again.becomes(true))
    }

    @Test
    fun unreadableStorageSharesByDefault() {
        assertEquals(true, AnalyticsConsentStore(failingStore(IOException("disk")), scope).becomes(true))
    }
}
