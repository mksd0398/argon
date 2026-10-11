package app.storefront.ui.returns

import app.storefront.data.CustomerAccountApi
import app.storefront.data.Money
import app.storefront.data.OrderReturnOptions
import app.storefront.data.Product
import app.storefront.data.ProductOption
import app.storefront.data.ProductOptionValue
import app.storefront.data.RequestedLineItemInput
import app.storefront.data.ReturnFee
import app.storefront.data.ReturnableLineItem
import app.storefront.data.SelectedOption
import app.storefront.data.Variant
import app.storefront.data.fixture
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReturnLogicTest {
    // the contract fixture: what the sample order can send back (a crewneck and a T-shirt, one of each)
    private val options = runBlocking { CustomerAccountApi({ name, _ -> fixture(name) }).returnOptions("gid://shopify/Order/6001004")!! }
    private val crewneck = options.returnableLineItems[0]
    private val tshirt = options.returnableLineItems[1]
    private val tooSmall = "gid://shopify/ReturnReasonDefinition/1"

    // The exchange note

    @Test
    fun anExchangeNoteNamesTheProductTheVariantAndTheSku() {
        assertEquals("Exchange for: Men's Crewneck - Large / Olive (SKU MC-LO)", exchangeNote("Men's Crewneck", "Large / Olive", "MC-LO", ""))
    }

    @Test
    fun theSkuPartIsLeftOutWhenThereIsNone() {
        assertEquals("Exchange for: Men's Crewneck - Large / Olive", exchangeNote("Men's Crewneck", "Large / Olive", null, ""))
        assertEquals("Exchange for: Men's Crewneck - Large / Olive", exchangeNote("Men's Crewneck", "Large / Olive", "  ", ""))
    }

    @Test
    fun theShoppersNoteFollowsOnANewLine() {
        assertEquals(
            "Exchange for: Men's Crewneck - Large / Olive (SKU MC-LO)\nThe medium was tight at the shoulders.",
            exchangeNote("Men's Crewneck", "Large / Olive", "MC-LO", "  The medium was tight at the shoulders.\n"),
        )
        assertEquals("a blank note adds no line", "Exchange for: Gift box (SKU GB-1)", exchangeNote("Gift box", null, "GB-1", "   "))
    }

    @Test
    fun aProductWithoutOptionsHasNoVariantPart() {
        assertEquals("Gift box (SKU GB-1)", exchangeItem("Gift box", "Default Title", "GB-1"))
        assertEquals("Gift box", exchangeItem(" Gift box ", null, null))
    }

    @Test
    fun whatWasTypedInsteadOfPickedIsSentAsItIs() {
        assertEquals("Exchange for: the same in blue, size L\nThanks", exchangeNote(" the same in blue, size L ", "Thanks"))
    }

    // The request's lines

    @Test
    fun theRequestHasOneLinePerChosenItem() {
        val choices = mapOf(
            crewneck.lineItem.id to ReturnChoice(quantity = 1, exchange = true, reasonId = tooSmall, note = "Tight at the shoulders", wanted = "Men's Crewneck - Large / Olive"),
            tshirt.lineItem.id to ReturnChoice(quantity = 1, reasonId = "gid://shopify/ReturnReasonDefinition/4", note = "  "),
        )
        assertEquals(
            listOf(
                RequestedLineItemInput(
                    "gid://shopify/LineItem/5000001", 1, tooSmall,
                    "Exchange for: Men's Crewneck - Large / Olive\nTight at the shoulders",
                ),
                RequestedLineItemInput("gid://shopify/LineItem/5000003", 1, "gid://shopify/ReturnReasonDefinition/4", null),
            ),
            returnLines(options.returnableLineItems, choices),
        )
    }

    @Test
    fun itemsThatWereNotChosenAreLeftOut() {
        val choices = mapOf(
            crewneck.lineItem.id to ReturnChoice(quantity = 0, reasonId = tooSmall, note = "changed my mind about returning it"),
            tshirt.lineItem.id to ReturnChoice(quantity = 1, note = "Faded after one wash"),
            "gid://shopify/LineItem/unknown" to ReturnChoice(quantity = 1),
        )
        assertEquals(
            listOf(RequestedLineItemInput("gid://shopify/LineItem/5000003", 1, null, "Faded after one wash")),
            returnLines(options.returnableLineItems, choices),
        )
        assertEquals(emptyList<RequestedLineItemInput>(), returnLines(options.returnableLineItems, emptyMap()))
    }

    @Test
    fun aLineNeverAsksForMoreThanCanGoBackOrSaysMoreThanShopifyTakes() {
        val three = tshirt.copy(quantity = 3)
        val lines = returnLines(listOf(three), mapOf(three.lineItem.id to ReturnChoice(quantity = 5, exchange = true, wanted = "Large", note = "x".repeat(400))))
        assertEquals(3, lines.single().quantity)
        assertEquals(NOTE_LIMIT, lines.single().customerNote!!.length)
        assertEquals("the wanted item is what survives the cut", true, lines.single().customerNote!!.startsWith("Exchange for: Large\nxxx"))
        assertEquals("nothing can go back: no line", emptyList<RequestedLineItemInput>(), returnLines(listOf(tshirt.copy(quantity = 0)), mapOf(tshirt.lineItem.id to ReturnChoice(quantity = 1))))
    }

    @Test
    fun theNoteFieldLeavesRoomForTheWantedItem() {
        assertEquals(NOTE_LIMIT, noteLimit(ReturnChoice(quantity = 1, wanted = "ignored for a refund")))
        // "Exchange for: Large" is 19 characters, and the new line one more
        assertEquals(NOTE_LIMIT - 20, noteLimit(ReturnChoice(quantity = 1, exchange = true, wanted = "Large")))
        assertEquals(0, noteLimit(ReturnChoice(quantity = 1, exchange = true, wanted = "y".repeat(400))))
    }

    // Step 2

    @Test
    fun aChosenItemNeedsAReasonAndAnExchangeNeedsWhatIsWanted() {
        assertEquals("Choose a reason", choiceProblem(crewneck, ReturnChoice(quantity = 1)))
        assertNull(choiceProblem(crewneck, ReturnChoice(quantity = 1, reasonId = tooSmall)))
        assertEquals("Choose what you'd like instead", choiceProblem(crewneck, ReturnChoice(quantity = 1, reasonId = tooSmall, exchange = true, wanted = " ")))
        assertNull(choiceProblem(crewneck, ReturnChoice(quantity = 1, reasonId = tooSmall, exchange = true, wanted = "Large / Olive")))
        val noReasons = crewneck.copy(lineItem = crewneck.lineItem.copy(suggestedReturnReasonDefinitions = emptyList()))
        assertNull("a store that offers no reasons can't be given one", choiceProblem(noReasons, ReturnChoice(quantity = 1)))
    }

    @Test
    fun aStepIsLeftOnlyWhenItIsComplete() {
        val done = crewneck to ReturnChoice(quantity = 1, reasonId = tooSmall)
        val noReason = tshirt to ReturnChoice(quantity = 1)
        assertEquals("Choose at least one item", stepProblem(0, emptyList()))
        assertNull(stepProblem(0, listOf(noReason)))
        assertEquals("the first incomplete item's", "Choose a reason", stepProblem(1, listOf(done, noReason)))
        assertNull(stepProblem(1, listOf(done)))
        assertNull("the review has nothing left to ask", stepProblem(2, listOf(noReason)))
    }

    @Test
    fun anOrderLineIsOfferedOnceWithAllThatCanGoBack() {
        assertEquals(options.returnableLineItems, returnableItems(options))
        // the crewneck listed twice (2 and 1 of it), and the T-shirt with nothing left to return
        val listed = listOf(crewneck.copy(quantity = 2), tshirt.copy(quantity = 0), crewneck.copy(quantity = 1))
        val split = OrderReturnOptions("o", OrderReturnOptions.ReturnInformation(returnableLineItems = listed))
        assertEquals(listOf(crewneck.copy(quantity = 3)), returnableItems(split))
        assertEquals(emptyList<ReturnableLineItem>(), returnableItems(OrderReturnOptions("o")))
    }

    // Step 3

    @Test
    fun theReviewSaysWhatWasAskedForEachItem() {
        assertEquals(
            listOf("Medium / Olive", "Qty 1", "Exchange for: Men's Crewneck - Large / Olive", "Size was too small", "Tight"),
            reviewDetails(crewneck, ReturnChoice(quantity = 1, exchange = true, reasonId = tooSmall, note = " Tight ", wanted = "Men's Crewneck - Large / Olive")),
        )
        assertEquals(listOf("Large / Ocean", "Qty 1", "Refund"), reviewDetails(tshirt, ReturnChoice(quantity = 4)))
    }

    @Test
    fun feesShowWithTheirAmounts() {
        assertEquals(listOf("Return shipping" to "8.0 CAD"), feeRows(options) { "${it.amount} ${it.currencyCode}" })
        assertEquals("Restocking fee", feeLabel(ReturnFee("RestockingFee")))
        assertEquals("Return shipping", feeLabel(ReturnFee("ReturnShippingFee", title = " ")))
        assertEquals("Handling", feeLabel(ReturnFee("RestockingFee", title = "Handling")))
        assertEquals("Fee", feeLabel(ReturnFee()))
    }

    // The replacement picker

    private fun variant(id: String, size: String, color: String, available: Boolean = true, sku: String? = null) = Variant(
        id, "$size / $color", available, sku,
        selectedOptions = listOf(SelectedOption("Size", size), SelectedOption("Color", color)),
        price = Money("120.0", "CAD"),
    )

    private fun option(name: String, vararg values: String) = ProductOption(name = name, optionValues = values.map { ProductOptionValue(name = it) })

    private val product = Product(
        "p", "men-crewneck", "Men's Crewneck",
        options = listOf(option("Size", "Medium", "Large"), option("Color", "Olive", "Ocean")),
        variants = listOf(
            variant("m-olive", "Medium", "Olive", sku = "MC-MO"),
            variant("l-olive", "Large", "Olive", sku = "MC-LO"),
            variant("m-ocean", "Medium", "Ocean", available = false),
        ),
    )

    @Test
    fun thePickerStartsAtTheVariantBeingReturned() {
        assertEquals(mapOf("Size" to "Large", "Color" to "Olive"), startSelection(product, "l-olive"))
        assertEquals("a variant that is gone: the first available one", mapOf("Size" to "Medium", "Color" to "Olive"), startSelection(product, "gone"))
        assertEquals(emptyMap<String, String>(), startSelection(Product("p", "h", "T"), null))
    }

    @Test
    fun aSelectionIsWantedOnlyWhenItsVariantCanBeHad() {
        assertEquals("Men's Crewneck - Large / Olive (SKU MC-LO)", wantedVariant(product, mapOf("Size" to "Large", "Color" to "Olive")))
        assertEquals("sold out", "", wantedVariant(product, mapOf("Size" to "Medium", "Color" to "Ocean")))
        assertEquals("no such variant", "", wantedVariant(product, mapOf("Size" to "Large", "Color" to "Ocean")))
    }

    @Test
    fun aProductWithoutOptionsHasNothingToChoose() {
        assertEquals(listOf("Size", "Color"), choosableOptions(product).map { it.name })
        val plain = Product("p", "gift-box", "Gift box", options = listOf(option("Title", "Default Title")), variants = listOf(Variant("v", "Default Title", true, "GB-1", price = Money("9.0", "CAD"))))
        assertEquals(emptyList<ProductOption>(), choosableOptions(plain))
        assertEquals("its one variant is the replacement", "Gift box (SKU GB-1)", wantedVariant(plain, startSelection(plain, null)))
    }
}
