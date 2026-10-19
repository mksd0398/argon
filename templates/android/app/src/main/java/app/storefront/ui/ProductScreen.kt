package app.storefront.ui

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonRating
import app.argon.ui.components.ArgonTopBar
import app.argon.ui.components.ArgonTopBarAction
import app.storefront.AppGraph
import app.storefront.data.AnalyticsEvent
import app.storefront.data.Metafield
import app.storefront.data.MetafieldIdentifier
import app.storefront.data.Product
import app.storefront.data.ProductCard
import app.storefront.data.ReviewSummary
import app.storefront.data.Route
import app.storefront.data.ScreenContext
import app.storefront.data.SellingPlanAllocation
import app.storefront.data.ShopPolicies
import app.storefront.data.Variant
import app.storefront.data.Variants
import app.storefront.data.analyticsCurrency
import app.storefront.data.analyticsItem
import app.storefront.data.productBlocks
import app.storefront.ui.product.AddPhase
import app.storefront.ui.product.ChosenPrice
import app.storefront.ui.product.DESCRIPTION
import app.storefront.ui.product.GalleryViewer
import app.storefront.ui.product.ProductAvailability
import app.storefront.ui.product.ProductBundle
import app.storefront.ui.product.ProductDetails
import app.storefront.ui.product.ProductGallery
import app.storefront.ui.product.ProductOptions
import app.storefront.ui.product.ProductPrice
import app.storefront.ui.product.ProductPurchaseOptions
import app.storefront.ui.product.ProductQuantity
import app.storefront.ui.product.ProductRail
import app.storefront.ui.product.ProductReviews
import app.storefront.ui.product.ReviewSheet
import app.storefront.ui.product.ReviewsState
import app.storefront.ui.product.StickyAddBar
import app.storefront.ui.product.addButtonLabel
import app.storefront.ui.product.chosenPlan
import app.storefront.ui.product.chosenPrice
import app.storefront.ui.product.clampedQuantity
import app.storefront.ui.product.galleryTags
import app.storefront.ui.product.imageIndex
import app.storefront.ui.product.shownRating
import app.storefront.ui.product.visibleOptions
import app.storefront.ui.sections.rememberScreenSections
import app.storefront.ui.sections.rememberSectionEnv
import app.storefront.ui.sections.sectionItems
import java.io.IOException
import java.util.logging.Logger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// The product page: this file is its shell (top bar, the list of blocks, the sticky bar) and its state; the blocks are in
// ui/product/, one file per group, each with the plain functions that decide what it shows.

/**
 * `PDP_METAFIELDS` ("custom.material, custom.care") as the Storefront `metafields` identifiers. Each entry splits on its
 * first dot; blank entries and ones without a namespace and a key are skipped.
 */
internal fun metafieldIdentifiers(config: String): List<MetafieldIdentifier> =
    config.split(",").map { it.trim() }.mapNotNull { entry ->
        val namespace = entry.substringBefore(".", "")
        val key = entry.substringAfter(".", "")
        if (namespace.isEmpty() || key.isEmpty()) null else MetafieldIdentifier(namespace, key)
    }

/** The options of the first available variant, else of the first variant (a sold-out product still shows its options). */
internal fun initialSelection(product: Product): Map<String, String> =
    (product.variants.firstOrNull { it.available } ?: product.variants.firstOrNull())?.options.orEmpty()

/** What "Share" sends: the product's page on the web store, else its usual address on the shop's [domain]. */
internal fun shareUrl(product: Product, domain: String): String =
    product.onlineStoreUrl?.takeIf { it.isNotBlank() } ?: "https://$domain/products/${product.handle}"

/**
 * The selected variant in full (`variantBySelectedOptions`) with the [selection] it was asked for. [variant] is null
 * when the store has no variant for it, or the call failed.
 */
internal data class RichVariant(val selection: Map<String, String>, val variant: Variant?)

/**
 * Latest selection wins: [answer] is kept only when it is for the [selection] on screen now. One that arrives late, for
 * a selection the shopper has since changed, leaves [current] as it is.
 */
internal fun latestAnswer(current: RichVariant?, answer: RichVariant, selection: Map<String, String>): RichVariant? =
    if (answer.selection == selection) answer else current

/**
 * The variant the page shows for [selection]: the full one once it has answered this very selection; until then, and
 * when that call fails, the one in the product's own list. Null: there is no such variant ("Unavailable").
 */
internal fun shownVariant(product: Product, selection: Map<String, String>, rich: RichVariant?): Variant? =
    rich?.takeIf { it.selection == selection }?.variant ?: Variants.match(product.variants, selection)

/** The page's blocks, top to bottom. Each one hides itself when it has nothing to show. */
internal enum class ProductBlock {
    Gallery, Title, Price, Options, Availability, PurchaseOptions, Quantity, Bundle, Details, Trust, Reviews, PairsWith, AlsoLike, RecentlyViewed,
}

/**
 * The page's blocks for the PDP block names of screens v2 (`main.blocks`, [productBlocks]), in that order: "purchase"
 * is availability, purchase options and quantity; "details" the details and the trust row; "rails" the three product
 * rails. All the names in their default order give [ProductBlock]'s own order.
 */
internal fun productBlockList(names: List<String>): List<ProductBlock> = names.flatMap { name ->
    when (name) {
        "gallery" -> listOf(ProductBlock.Gallery)
        "title" -> listOf(ProductBlock.Title)
        "price" -> listOf(ProductBlock.Price)
        "options" -> listOf(ProductBlock.Options)
        "purchase" -> listOf(ProductBlock.Availability, ProductBlock.PurchaseOptions, ProductBlock.Quantity)
        "bundle" -> listOf(ProductBlock.Bundle)
        "details" -> listOf(ProductBlock.Details, ProductBlock.Trust)
        "reviews" -> listOf(ProductBlock.Reviews)
        "rails" -> listOf(ProductBlock.PairsWith, ProductBlock.AlsoLike, ProductBlock.RecentlyViewed)
        else -> emptyList()
    }
}

/** How long the main button says "Added". */
private const val ADDED_MILLIS = 2000L

private suspend fun loadProduct(handle: String): Product {
    // The Product query loads variants(first: 250), the Storefront API's page ceiling. A selection past those is not in
    // the list: the page then goes by variantBySelectedOptions alone (ProductState.loadVariant).
    val product = AppGraph.storefront.product(handle) ?: error("Product not found")
    // once per load: coming back to a page that is kept is not another view
    AppGraph.analytics.track(AnalyticsEvent.ViewItem(product.analyticsItem(), product.analyticsCurrency))
    return product
}

/**
 * A product page's state: the product, what the shopper has chosen, and everything loaded around it. It is kept with the
 * loaded product ([Loader]), so the page is as it was after a trip to another screen.
 *
 * Only the product itself can fail the page. Every other call (the full variant, metafields, policies, pickup, both
 * recommendation lists, recently viewed, reviews) loads on its own and fails quietly: it is logged, and its block stays
 * hidden. Reviews alone show a retry line.
 */
@Stable
internal class ProductState(val product: Product) {
    // java.util.logging, as in the stores: it reaches logcat
    private val log = Logger.getLogger("ProductScreen")

    /** The chosen value of each option. */
    var selection by mutableStateOf(initialSelection(product))
        private set

    // the selected variant in full, with the selection it answers
    private var rich by mutableStateOf<RichVariant?>(null)

    /** The variant on show ([shownVariant]); null when the selection has none. */
    val variant: Variant? by derivedStateOf { shownVariant(product, selection, rich) }

    /** Nothing to show for the selection yet and its full variant hasn't answered: the button waits, rather than say "Unavailable". */
    val isResolving: Boolean get() = variant == null && rich?.selection != selection

    val canBuy: Boolean get() = variant?.available == true

    /** The quantity as tapped; [quantity] is the one that counts. */
    var chosenQuantity by mutableIntStateOf(1)

    /** The quantity to add: the tapped one, on the variant's quantity rule. */
    val quantity: Int get() = clampedQuantity(chosenQuantity, variant?.quantityRule)

    /** The chosen selling plan's id; null: a one-time purchase. */
    var planId by mutableStateOf<String?>(null)

    /** The plan the variant is bought on ([chosenPlan]). */
    val plan: SellingPlanAllocation? get() = chosenPlan(variant, product.requiresSellingPlan, planId)

    /** What one item costs as chosen ([chosenPrice]). */
    val price: ChosenPrice? get() = variant?.let { chosenPrice(it, quantity, plan) }

    var addPhase by mutableStateOf(AddPhase.Idle)
        private set

    /** "Buy now" is adding to the cart, or opening checkout. */
    var isBuying by mutableStateOf(false)
        private set

    /** No add is running or just done: the buttons can be tapped. */
    val isIdle: Boolean get() = addPhase == AddPhase.Idle && !isBuying

    /** The titles of the expanded Details accordions. */
    var openDetails by mutableStateOf(setOf(DESCRIPTION))
        private set

    /** The `PDP_METAFIELDS` the product has a value for; null until loaded. */
    var metafields by mutableStateOf<List<Metafield>?>(null)
        private set
    var policies by mutableStateOf<ShopPolicies?>(null)
        private set

    // the name of a location the variant can be picked up at, with the variant id it answers
    private var pickupAnswer by mutableStateOf<Pair<String, String?>?>(null)

    /** Where the variant on show can be picked up (a location's name); null when nowhere, or not known. */
    val pickup: String? get() = pickupAnswer?.takeIf { it.first == variant?.id }?.second

    /** "Pairs well with". */
    var complementary by mutableStateOf<List<ProductCard>?>(null)
        private set

    /** "You may also like". */
    var related by mutableStateOf<List<ProductCard>?>(null)
        private set

    /** "Recently viewed": the products opened before this one. */
    var recent by mutableStateOf<List<ProductCard>?>(null)
        private set

    /** The product's reviews; without a Judge.me token their block shows only once it has some ([ReviewsState.isShown]). */
    val reviews = ReviewsState(AppGraph.judgeMe, product)

    fun select(option: String, value: String) {
        selection = selection + (option to value)
    }

    fun toggleDetails(title: String) {
        openDetails = if (title in openDetails) openDetails - title else openDetails + title
    }

    /** The result of [load], or null when it fails: a secondary call never breaks the page, it is only logged. */
    private suspend fun <T> quietly(what: String, load: suspend () -> T): T? = try {
        load()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        log.warning("$what not loaded: ${e.message}")
        null
    }

    /**
     * Asks for the selection's variant in full; run on every selection change. Latest wins ([latestAnswer]): an answer
     * for an older selection is dropped. A failure is silent: the product's own variant stays.
     */
    suspend fun loadVariant() {
        val asked = selection
        if (rich?.selection == asked) return
        val answer = quietly("variant") { AppGraph.storefront.variantBySelectedOptions(product.handle, asked) }
        rich = latestAnswer(rich, RichVariant(asked, answer), selection)
    }

    /** Asks where the variant on show can be picked up; run when it changes. */
    suspend fun loadPickup() {
        val id = variant?.id ?: return
        if (pickupAnswer?.first == id) return
        val name = quietly("pickup") { AppGraph.storefront.storeAvailability(id).firstOrNull { it.available }?.location?.name }
        if (variant?.id == id) pickupAnswer = id to name
    }

    /**
     * Everything else around the product, side by side, each on its own: metafields, policies, both recommendation
     * lists, recently viewed, and the first page of reviews. What has loaded isn't asked for again; what failed is, the
     * next time the page shows.
     */
    suspend fun loadRest() {
        coroutineScope {
            launch {
                if (metafields == null) {
                    metafields = quietly("metafields") { AppGraph.storefront.productMetafields(product.handle, metafieldIdentifiers(AppGraph.pdpMetafields)) }
                }
            }
            launch { if (policies == null) policies = quietly("policies") { AppGraph.storefront.policies() } }
            launch { if (complementary == null) complementary = quietly("complementary products") { recommended("COMPLEMENTARY") } }
            launch { if (related == null) related = quietly("related products") { recommended("RELATED") } }
            launch { loadRecent() }
            launch { reviews.loadFirst() }
        }
    }

    private suspend fun recommended(intent: String): List<ProductCard> =
        AppGraph.storefront.recommendations(product.id, intent).filter { it.id != product.id }.distinctBy { it.id }

    /** The products viewed before this one, newest first; then this one joins the list for the next page. */
    private suspend fun loadRecent() {
        if (recent != null) return
        val others = AppGraph.recentlyViewed.ids.value.filter { it != product.id }.distinct()
        quietly("recently viewed (saving)") { AppGraph.recentlyViewed.add(product.id) }
        recent = if (others.isEmpty()) emptyList() else quietly("recently viewed") { AppGraph.storefront.productsByIds(others).distinctBy { it.id } }
    }

    /**
     * Puts the chosen quantity of the variant on show in the cart, on the chosen plan. It runs on the app's scope, not
     * the screen's: leaving right after the tap must not drop the add. The main button then says "Added" for a moment.
     * With [thenCheckout] ("Buy now") it opens checkout instead, once the add is in. A refused add shows Shopify's
     * message as a toast.
     */
    fun add(thenCheckout: (suspend () -> Unit)? = null) {
        val id = variant?.takeIf { it.available }?.id ?: return
        if (!isIdle) return
        val quantity = quantity
        val planId = plan?.sellingPlan?.id
        if (thenCheckout != null) isBuying = true else addPhase = AddPhase.Adding
        AppGraph.scope.launch {
            try {
                AppGraph.cart.add(id, quantity, planId)
                if (thenCheckout != null) {
                    thenCheckout()
                } else {
                    addPhase = AddPhase.Added
                    delay(ADDED_MILLIS)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                AppGraph.toast.show(e.message ?: "Couldn't update the cart")
            } finally {
                addPhase = AddPhase.Idle
                isBuying = false
            }
        }
    }
}

@Composable
fun ProductScreen(handle: String, nav: NavController) {
    // the top bar's actions and the sticky bar need the product: null until it has loaded
    var loaded by remember { mutableStateOf<ProductState?>(null) }
    Scaffold(
        topBar = { ProductTopBar(loaded?.product, nav) },
        bottomBar = {
            loaded?.let { state ->
                StickyAddBar(
                    state.price,
                    // a selection whose variant is still being asked for waits with a spinner; it isn't "Unavailable" yet
                    label = if (state.isResolving) "Add to cart" else addButtonLabel(state.variant, state.addPhase),
                    isEnabled = state.canBuy && state.isIdle,
                    isLoading = state.isResolving || state.addPhase == AddPhase.Adding,
                    onAdd = { state.add() },
                )
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            Loader({ ProductState(loadProduct(handle)) }, placeholder = { ProductSkeleton() }) { state ->
                LaunchedEffect(state) { loaded = state }
                ProductContent(state, nav)
            }
        }
    }
}

/** Back; then share and the wishlist heart once the product is here, and the cart with its count. */
@Composable
private fun ProductTopBar(product: Product?, nav: NavController) {
    val context = LocalContext.current
    val wishlist by AppGraph.wishlist.ids.collectAsState()
    val cartCount = AppGraph.cart.cart.collectAsState().value?.totalQuantity ?: 0
    val actions = buildList {
        if (product != null) {
            add(ArgonTopBarAction(ArgonIconName.Share, "Share") { share(context, product) })
            val saved = product.id in wishlist
            add(
                ArgonTopBarAction(if (saved) ArgonIconName.HeartFilled else ArgonIconName.Heart, if (saved) "Remove from wishlist" else "Save to wishlist") {
                    AppGraph.scope.launch {
                        // a failed write leaves the heart as it was; it must not crash the app
                        try {
                            AppGraph.wishlist.toggle(product.id, AnalyticsEvent.AddToWishlist(product.analyticsItem(), product.analyticsCurrency))
                        } catch (e: IOException) {
                            Log.w("Wishlist", "toggle failed", e)
                        }
                    }
                },
            )
        }
        add(ArgonTopBarAction(ArgonIconName.Bag, "Cart", badge = cartCount.takeIf { it > 0 }) { AppGraph.tabs.select(AppTab.Cart) })
    }
    ArgonTopBar("", leading = listOf(nav.backAction()), trailing = actions)
}

/** Hands the product's link to the system's share sheet. */
private fun share(context: Context, product: Product) {
    val send = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_SUBJECT, product.title)
        .putExtra(Intent.EXTRA_TEXT, shareUrl(product, AppGraph.shopDomain))
    // nothing to share with: nothing to open, and nothing to crash
    runCatching { context.startActivity(Intent.createChooser(send, null)) }
}

/** "Buy now", after the add: Shopify's checkout for the cart, opened as the cart screen opens it. */
private suspend fun openCheckout(host: ComponentActivity) {
    val url = AppGraph.cart.checkoutUrl() ?: return
    presentCheckout(url, host) { AppGraph.toast.show(it) }
}

/**
 * The blocks in one lazy list, in [ProductBlock]'s order (or the store's, screens v2, with its sections above and below
 * them), with the overlays they open (the image viewer, the review sheet).
 */
@Composable
private fun ProductContent(state: ProductState, nav: NavController) {
    val product = state.product
    val variant = state.variant
    val spacing = ArgonTheme.spacing
    val screen = rememberCoroutineScope()
    val activity = LocalActivity.current as? ComponentActivity
    val list = rememberLazyListState()
    val gallery = rememberPagerState { product.images.size }
    val company by AppGraph.buyer.company.collectAsState()
    var viewerPage by remember { mutableStateOf<Int?>(null) }
    var writingReview by remember { mutableStateOf(false) }
    val open: (Route) -> Unit = { nav.open(it) }
    // screens v2: the store's sections above and below the blocks, and the blocks in its order; without them, as ever
    val sections = rememberScreenSections("product", product = product.handle)
    val placement = sections?.placement
    val blocks = remember(placement) { productBlockList(productBlocks(placement?.main)) }
    val liquid = remember(product, sections) { ScreenContext.product(product, sections?.ownMetafields.orEmpty()) }
    val env = rememberSectionEnv(sections, open, product = liquid)
    val above = placement?.above.orEmpty().takeIf { env != null }.orEmpty()
    // the list's index of a block: the sections above come first
    fun indexOf(block: ProductBlock) = blocks.indexOf(block).takeIf { it >= 0 }?.plus(above.size)
    val showReviews: () -> Unit = { indexOf(ProductBlock.Reviews)?.let { screen.launch { list.animateScrollToItem(it) } } }
    val gutter = Modifier.padding(start = spacing.l, end = spacing.l, top = spacing.xl)

    LaunchedEffect(state) { state.loadRest() }
    LaunchedEffect(state, state.selection) { state.loadVariant() }
    LaunchedEffect(state, variant?.id) { state.loadPickup() }

    // the sticky bar sits under this list (the scaffold's padding); the bottom padding is only breathing room
    LazyColumn(Modifier.fillMaxSize(), state = list, contentPadding = PaddingValues(bottom = spacing.xxl)) {
        sectionItems(above, env, Modifier.padding(top = spacing.l), spacing.l)
        items(blocks, key = { it }, contentType = { it }) { block ->
            when (block) {
                ProductBlock.Gallery -> ProductGallery(product.images, product.title, gallery, galleryTags(variant)) { viewerPage = it }
                // the stars lead to the reviews, when the page has them
                ProductBlock.Title -> ProductTitle(product, state.reviews.summary, onRating = showReviews.takeIf { state.reviews.isShown })
                ProductBlock.Price -> ProductPrice(variant, state.price, state.quantity, company?.companyName)
                ProductBlock.Options -> ProductOptions(visibleOptions(product), state.selection, product.variants) { option, value ->
                    state.select(option, value)
                    // a variant with an image of its own brings the gallery to it: animated while the gallery is on screen
                    imageIndex(product.images, Variants.match(product.variants, state.selection)?.image)?.let { page ->
                        if (list.firstVisibleItemIndex == indexOf(ProductBlock.Gallery)) screen.launch { gallery.animateScrollToPage(page) } else gallery.requestScrollToPage(page)
                    }
                }
                ProductBlock.Availability -> ProductAvailability(variant, state.pickup)
                ProductBlock.PurchaseOptions -> ProductPurchaseOptions(variant, product.requiresSellingPlan, state.plan) { state.planId = it }
                ProductBlock.Quantity -> if (state.canBuy) {
                    ProductQuantity(
                        state.quantity,
                        variant?.quantityRule,
                        canBuyNow = state.isIdle,
                        isBuying = state.isBuying,
                        onQuantity = { state.chosenQuantity = it },
                        onBuyNow = { state.add(thenCheckout = { activity?.let { openCheckout(it) } }) },
                    )
                }
                ProductBlock.Bundle -> ProductBundle(variant, onOpen = open)
                ProductBlock.Details -> ProductDetails(product.descriptionHtml, state.metafields.orEmpty(), state.policies, state.openDetails) { state.toggleDetails(it) }
                ProductBlock.Trust -> TrustRow(open, gutter)
                ProductBlock.Reviews -> if (state.reviews.isShown) {
                    ProductReviews(state.reviews, onWrite = { writingReview = true }, onLoadMore = { screen.launch { state.reviews.loadMore() } })
                }
                ProductBlock.PairsWith -> ProductRail("Pairs well with", state.complementary.orEmpty(), ProductCardStyle.Compact, onOpen = open)
                ProductBlock.AlsoLike -> ProductRail("You may also like", state.related.orEmpty(), ProductCardStyle.Standard, onOpen = open)
                ProductBlock.RecentlyViewed -> ProductRail("Recently viewed", state.recent.orEmpty(), ProductCardStyle.Standard, onOpen = open)
            }
        }
        sectionItems(placement?.below.orEmpty(), env, Modifier.padding(top = spacing.xl), spacing.xl)
    }

    // outside the list: an overlay must not go away with the block that opened it
    GalleryViewer(product.images, product.title, viewerPage) { viewerPage = null }
    ReviewSheet(writingReview, { writingReview = false }, state.reviews::submit)
}

/** Block 2: the vendor, the title, and the rating ([shownRating]); [onRating] makes the stars a way to the reviews. */
@Composable
private fun ProductTitle(product: Product, summary: ReviewSummary?, onRating: (() -> Unit)?) {
    val spacing = ArgonTheme.spacing
    Column(
        Modifier.fillMaxWidth().padding(start = spacing.l, end = spacing.l, top = spacing.l),
        verticalArrangement = Arrangement.spacedBy(spacing.xs),
    ) {
        if (AppGraph.showVendor && product.vendor.isNotBlank()) {
            Text(product.vendor, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Text(product.title, Modifier.semantics { heading() }, style = ArgonTheme.type.title, color = ArgonTheme.colors.ink)
        shownRating(summary, product.rating, product.ratingCount)?.let { (value, count) ->
            if (onRating == null) {
                ArgonRating(value, count = count, size = ArgonSize.M)
            } else {
                // a row tall enough to tap
                Box(Modifier.heightIn(min = 44.dp).clickable(onClickLabel = "Show reviews", role = Role.Button, onClick = onRating), Alignment.CenterStart) {
                    ArgonRating(value, count = count, size = ArgonSize.M)
                }
            }
        }
    }
}
