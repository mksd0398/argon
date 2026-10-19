import ArgonUI
import Observation
import os
import SwiftUI
import UIKit

// The product page: this file is its shell (top bar, the blocks in order, the sticky bar) and its state; the blocks are in
// UI/Product/, one file per group, each with the plain functions that decide what it shows.

/// `PDP_METAFIELDS` ("custom.material, custom.care") as the Storefront `metafields` identifiers. Each entry splits on its
/// first dot; blank entries and ones without a namespace and a key are skipped.
func metafieldIdentifiers(_ config: String) -> [MetafieldIdentifier] {
    var identifiers: [MetafieldIdentifier] = []
    for part in config.split(separator: ",") {
        let entry = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = entry.firstIndex(of: ".") else { continue }
        let namespace = String(entry[..<dot])
        let key = String(entry[entry.index(after: dot)...])
        if !namespace.isEmpty && !key.isEmpty { identifiers.append(MetafieldIdentifier(namespace: namespace, key: key)) }
    }
    return identifiers
}

/// The options of the first available variant, else of the first variant (a sold-out product still shows its options).
func initialSelection(_ variants: [Variant]) -> [String: String] {
    (variants.first { $0.available } ?? variants.first)?.options ?? [:]
}

/// What "Share" sends: the product's page on the web store, else its usual address on the shop's `domain`.
func shareUrl(_ product: Product, domain: String) -> String {
    if let url = product.onlineStoreUrl, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return url }
    return "https://\(domain)/products/\(product.handle)"
}

/// The selected variant in full (`variantBySelectedOptions`) with the `selection` it was asked for. `variant` is nil
/// when the store has no variant for it, or the call failed.
struct RichVariant: Equatable {
    let selection: [String: String]
    let variant: Variant?
}

/// Latest selection wins: `answer` is kept only when it is for the `selection` on screen now. One that arrives late, for
/// a selection the shopper has since changed, leaves `current` as it is.
func latestAnswer(_ current: RichVariant?, _ answer: RichVariant, selection: [String: String]) -> RichVariant? {
    answer.selection == selection ? answer : current
}

/// The variant the page shows for `selection`: the full one once it has answered this very selection; until then, and
/// when that call fails, the one in the product's own list. Nil: there is no such variant ("Unavailable").
func shownVariant(_ product: Product, _ selection: [String: String], _ rich: RichVariant?) -> Variant? {
    let full = rich?.selection == selection ? rich?.variant : nil
    return full ?? Variants.match(product.variants, selection: selection)
}

// MARK: - State

/// The page's blocks, top to bottom. Each one hides itself when it has nothing to show.
enum ProductBlock: Hashable {
    case gallery, title, price, options, availability, purchaseOptions, quantity, bundle, details, trust, reviews
    case pairsWith, alsoLike, recentlyViewed
}

/// How long the main button says "Added".
private let addedNanoseconds: UInt64 = 2_000_000_000

private let productLog = Logger(subsystem: "app.storefront", category: "ProductView")

@MainActor
private func loadProduct(_ handle: String) async throws -> Product {
    // The Product query loads variants(first: 250), the Storefront API's page ceiling. A selection past those is not in
    // the list: the page then goes by variantBySelectedOptions alone (ProductState.loadVariant).
    guard let product = try await AppGraph.storefront.product(handle) else { throw NotFound(what: "Product") }
    // once per load: coming back to a page that is kept is not another view
    AppGraph.analytics.track(.viewItem(product.analyticsItem(), currency: product.analyticsCurrency))
    return product
}

/// A product page's state: the product, what the shopper has chosen, and everything loaded around it. It is kept with the
/// loaded product (`Loader`), so the page is as it was after a trip to another screen.
///
/// Only the product itself can fail the page. Every other call (the full variant, metafields, policies, pickup, both
/// recommendation lists, recently viewed, reviews) loads on its own and fails quietly: it is logged, and its block stays
/// hidden. Reviews alone show a retry line.
@MainActor
@Observable
final class ProductState {
    let product: Product

    /// The chosen value of each option.
    private(set) var selection: [String: String]

    // the selected variant in full, with the selection it answers
    private var rich: RichVariant? = nil

    /// The variant on show (`shownVariant`); nil when the selection has none.
    var variant: Variant? { shownVariant(product, selection, rich) }

    /// Nothing to show for the selection yet and its full variant hasn't answered: the button waits, rather than say
    /// "Unavailable".
    var isResolving: Bool { variant == nil && rich?.selection != selection }

    var canBuy: Bool { variant?.available == true }

    /// The quantity as tapped; `quantity` is the one that counts.
    var chosenQuantity = 1

    /// The quantity to add: the tapped one, on the variant's quantity rule.
    var quantity: Int { clampedQuantity(chosenQuantity, variant?.quantityRule) }

    /// The chosen selling plan's id; nil: a one-time purchase.
    var planId: String? = nil

    /// The plan the variant is bought on (`chosenPlan`).
    var plan: SellingPlanAllocation? { chosenPlan(variant, requiresSellingPlan: product.requiresSellingPlan, planId: planId) }

    /// What one item costs as chosen (`chosenPrice`).
    var price: ChosenPrice? { variant.map { chosenPrice($0, quantity: quantity, plan: plan) } }

    private(set) var addPhase = AddPhase.idle

    /// "Buy now" is adding to the cart, or opening checkout.
    private(set) var isBuying = false

    /// No add is running or just done: the buttons can be tapped.
    var isIdle: Bool { addPhase == .idle && !isBuying }

    /// The titles of the expanded Details accordions.
    private(set) var openDetails: Set<String> = [descriptionTitle]

    /// The `PDP_METAFIELDS` the product has a value for; nil until loaded.
    private(set) var metafields: [Metafield]? = nil
    private(set) var policies: ShopPolicies? = nil

    // the name of a location the variant can be picked up at, with the variant id it answers
    private var pickupAnswer: (variantId: String, name: String?)? = nil

    /// Where the variant on show can be picked up (a location's name); nil when nowhere, or not known.
    var pickup: String? { pickupAnswer?.variantId == variant?.id ? pickupAnswer?.name : nil }

    /// "Pairs well with".
    private(set) var complementary: [ProductCard]? = nil

    /// "You may also like".
    private(set) var related: [ProductCard]? = nil

    /// "Recently viewed": the products opened before this one.
    private(set) var recent: [ProductCard]? = nil

    /// The product's reviews; without a Judge.me token their block shows only once it has some (`ReviewsState.isShown`).
    let reviews: ReviewsState

    /// The gallery's page: choosing an option brings its variant's image here.
    var galleryPage = 0

    /// "Buy now" has added and checkout is open: `checkout` is its URL, kept until the sheet has gone.
    var checkingOut = false
    var checkout: URL? = nil

    init(product: Product) {
        self.product = product
        selection = initialSelection(product.variants)
        reviews = ReviewsState(judgeMe: AppGraph.judgeMe, product: product)
    }

    func select(_ option: String, _ value: String) {
        selection[option] = value
    }

    func toggleDetails(_ title: String) {
        openDetails.formSymmetricDifference([title])
    }

    /// The result of `load`, or nil when it fails: a secondary call never breaks the page, it is only logged.
    private func quietly<T>(_ what: String, _ load: () async throws -> T) async -> T? {
        do {
            return try await load()
        } catch {
            // leaving the page cancels its loads: nothing worth a line in the log
            if !Task.isCancelled {
                productLog.warning("\(what, privacy: .public) not loaded: \(error.localizedDescription)")
            }
            return nil
        }
    }

    /// Asks for the selection's variant in full; run on every selection change. Latest wins (`latestAnswer`): an answer
    /// for an older selection is dropped. A failure is silent: the product's own variant stays.
    func loadVariant() async {
        let asked = selection
        if rich?.selection == asked { return }
        let answer = await quietly("variant") {
            try await AppGraph.storefront.variantBySelectedOptions(productHandle: product.handle, options: asked)
        }
        // a load cut short (a newer selection, or the page left) is no answer: it is asked again
        if Task.isCancelled { return }
        rich = latestAnswer(rich, RichVariant(selection: asked, variant: answer ?? nil), selection: selection)
    }

    /// Asks where the variant on show can be picked up; run when it changes.
    func loadPickup() async {
        guard let id = variant?.id, pickupAnswer?.variantId != id else { return }
        let name = await quietly("pickup") {
            try await AppGraph.storefront.storeAvailability(variantId: id).first { $0.available }?.location.name
        }
        if variant?.id == id, !Task.isCancelled { pickupAnswer = (id, name ?? nil) }
    }

    /// Everything else around the product, side by side, each on its own: metafields, policies, both recommendation
    /// lists, recently viewed, and the first page of reviews. What has loaded isn't asked for again; what failed is, the
    /// next time the page shows.
    func loadRest() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                if self.metafields != nil { return }
                self.metafields = await self.quietly("metafields") {
                    let identifiers = metafieldIdentifiers(AppGraph.pdpMetafields)
                    return try await AppGraph.storefront.productMetafields(handle: self.product.handle, identifiers: identifiers)
                }
            }
            group.addTask { @MainActor in
                if self.policies == nil { self.policies = await self.quietly("policies") { try await AppGraph.storefront.policies() } }
            }
            group.addTask { @MainActor in
                if self.complementary == nil {
                    self.complementary = await self.quietly("complementary products") { try await self.recommended(.complementary) }
                }
            }
            group.addTask { @MainActor in
                if self.related == nil {
                    self.related = await self.quietly("related products") { try await self.recommended(.related) }
                }
            }
            group.addTask { @MainActor in await self.loadRecent() }
            group.addTask { @MainActor in await self.reviews.loadFirst() }
        }
    }

    /// The products Shopify recommends beside this one, each once and never this one itself.
    private func recommended(_ intent: RecommendationIntent) async throws -> [ProductCard] {
        var seen: Set<String> = [product.id]
        return try await AppGraph.storefront.recommendations(productId: product.id, intent: intent).filter { seen.insert($0.id).inserted }
    }

    /// The products viewed before this one, newest first; then this one joins the list for the next page.
    private func loadRecent() async {
        if recent != nil { return }
        var seen: Set<String> = [product.id]
        let others = AppGraph.recentlyViewed.ids.filter { seen.insert($0).inserted }
        AppGraph.recentlyViewed.add(product.id)
        if others.isEmpty {
            recent = []
        } else {
            recent = await quietly("recently viewed") {
                var listed: Set<String> = []
                return try await AppGraph.storefront.productsByIds(others).filter { listed.insert($0.id).inserted }
            }
        }
    }

    /// Puts the chosen quantity of the variant on show in the cart, on the chosen plan. It runs on a task of its own, not
    /// the screen's: leaving right after the tap must not drop the add. The main button then says "Added" for a moment.
    /// With `thenCheckout` ("Buy now") it opens checkout instead, once the add is in. A refused add shows Shopify's
    /// message as a toast.
    func add(thenCheckout: Bool = false) {
        guard let id = variant.flatMap({ $0.available ? $0.id : nil }), isIdle else { return }
        let quantity = self.quantity
        let planId = plan?.sellingPlan.id
        if thenCheckout {
            isBuying = true
        } else {
            addPhase = .adding
        }
        Task {
            do {
                try await AppGraph.cart.add(id, quantity: quantity, sellingPlanId: planId)
                if thenCheckout {
                    // Shopify's checkout for the cart, opened as the cart screen opens it
                    if let url = try await checkoutToOpen() {
                        checkout = url
                        checkingOut = true
                    }
                } else {
                    addPhase = .added
                    try? await Task.sleep(nanoseconds: addedNanoseconds)
                }
            } catch {
                AppGraph.toast.show(error.localizedDescription)
            }
            addPhase = .idle
            isBuying = false
        }
    }
}

// MARK: - Views

@MainActor
struct ProductView: View {
    let handle: String
    // the top bar's actions need the product: nil until it has loaded
    @State private var loaded: ProductState? = nil
    @State private var sharing = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Loader(load: { ProductState(product: try await loadProduct(handle)) }, skeleton: .product) { state in
            ProductContent(state: state).onAppear { loaded = state }
        }
        .background(theme.colors.paper)
        .argonTopBar(title: "", trailing: actions)
        .sheet(isPresented: $sharing) {
            if let product = loaded?.product {
                ShareSheet(link: shareUrl(product, domain: AppGraph.shopDomain)).presentationDetents([.medium, .large])
            }
        }
    }

    /// Share and the wishlist heart once the product is here, and the cart with its count. Back is the navigation bar's own.
    private var actions: [ArgonTopBarAction] {
        var actions: [ArgonTopBarAction] = []
        if let product = loaded?.product {
            actions.append(ArgonTopBarAction(icon: .share, accessibilityLabel: "Share") { sharing = true })
            let saved = AppGraph.wishlist.contains(product.id)
            actions.append(ArgonTopBarAction(
                icon: saved ? .heartFilled : .heart,
                accessibilityLabel: saved ? "Remove from wishlist" : "Save to wishlist"
            ) {
                Task {
                    await AppGraph.wishlist.toggle(product.id, added: .addToWishlist(product.analyticsItem(), currency: product.analyticsCurrency))
                }
            })
        }
        let count = AppGraph.cart.cart?.totalQuantity ?? 0
        actions.append(ArgonTopBarAction(icon: .bag, accessibilityLabel: "Cart", badge: count > 0 ? count : nil) {
            AppGraph.tabs.selected = .cart
        })
        return actions
    }
}

/// The system's share sheet with the product's `link`.
private struct ShareSheet: UIViewControllerRepresentable {
    let link: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // a URL is shared as a link (with its preview); anything that isn't one, as the text it is
        let item: Any = URL(string: link).map { $0 as Any } ?? link
        return UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The blocks in one scrolling column, over the sticky bar, with the overlays they open (the image viewer, the review
/// sheet, checkout). The store's `app_screen` "product" (screens v2) puts its sections above and below the blocks, and
/// orders and hides the blocks (`main.blocks`); without one they are in `ProductPageBlock`'s order.
@MainActor
private struct ProductContent: View {
    @Bindable var state: ProductState
    // the page of the full-screen viewer; nil: closed
    @State private var viewerPage: Int? = nil
    @State private var writingReview = false
    @State private var reviewForm = ReviewForm()
    @State private var screen = ScreenSlot("product")
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let product = state.product
        let variant = state.variant
        let blocks = ScreenTemplate.productBlocks(screen.placement.main)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ScreenSections(slot: screen, part: .above, product: product, top: theme.spacing.l, bottom: theme.spacing.l)
                    ForEach(blocks, id: \.self) { block in
                        self.block(block, showReviews: { withAnimation { proxy.scrollTo(ProductBlock.reviews, anchor: .top) } })
                    }
                    ScreenSections(slot: screen, part: .below, product: product, top: theme.spacing.xl)
                }
                // the sticky bar sits under this column (the safe-area inset); the bottom padding is only breathing room
                .padding(.bottom, theme.spacing.xxl)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StickyAddBar(
                price: state.price,
                // a selection whose variant is still being asked for waits with a spinner; it isn't "Unavailable" yet
                label: state.isResolving ? "Add to cart" : addButtonLabel(variant, state.addPhase),
                isEnabled: state.canBuy && state.isIdle,
                isLoading: state.isResolving || state.addPhase == .adding,
                onAdd: { state.add() }
            )
        }
        .task { await state.loadRest() }
        .task { await screen.load(owner: .product(product.handle)) }
        .task(id: state.selection) { await state.loadVariant() }
        .task(id: variant?.id) { await state.loadPickup() }
        // on the page, not in a block: an overlay must not go away with the block that opened it
        .argonFullScreenModal(
            isPresented: Binding(get: { viewerPage != nil }, set: { if !$0 { viewerPage = nil } }),
            title: product.title
        ) {
            GalleryViewer(images: product.images, title: product.title, start: viewerPage ?? 0)
        }
        .argonBottomSheet(isPresented: $writingReview, detents: [.large]) {
            ReviewSheet(form: $reviewForm, onDismiss: { writingReview = false }, submit: { try await state.reviews.submit($0) })
        }
        .checkoutSheet(isPresented: $state.checkingOut, url: state.checkout) { failure in
            state.checkout = nil
            if let failure = failure { AppGraph.toast.show(failure) }
        }
    }

    private func open(_ route: Route) {
        router.open(route)
    }

    /// One block of the page; each hides itself when it has nothing to show.
    @ViewBuilder
    private func block(_ block: ProductPageBlock, showReviews: @escaping () -> Void) -> some View {
        let product = state.product
        let variant = state.variant
        switch block {
        case .gallery:
            ProductGallery(images: product.images, title: product.title, page: $state.galleryPage, tags: galleryTags(variant)) {
                viewerPage = $0
            }
        case .title:
            // the stars lead to the reviews, when the page has them
            ProductTitle(product: product, summary: state.reviews.summary, onRating: state.reviews.isShown ? showReviews : nil)
        case .price:
            ProductPrice(variant: variant, price: state.price, quantity: state.quantity, companyName: AppGraph.buyer.company?.companyName)
        case .options:
            ProductOptions(options: visibleOptions(product), selection: state.selection, variants: product.variants) { option, value in
                state.select(option, value)
                // a variant with an image of its own brings the gallery to it
                if let page = imageIndex(product.images, Variants.match(product.variants, selection: state.selection)?.image) {
                    withAnimation { state.galleryPage = page }
                }
            }
        case .purchase:
            // availability, purchase options, quantity with Buy now
            ProductAvailability(variant: variant, pickup: state.pickup)
            ProductPurchaseOptions(variant: variant, requiresSellingPlan: product.requiresSellingPlan, plan: state.plan) {
                state.planId = $0
            }
            if state.canBuy {
                ProductQuantity(
                    quantity: state.quantity,
                    rule: variant?.quantityRule,
                    canBuyNow: state.isIdle,
                    isBuying: state.isBuying,
                    onQuantity: { state.chosenQuantity = $0 },
                    onBuyNow: { state.add(thenCheckout: true) }
                )
            }
        case .bundle:
            ProductBundle(variant: variant, onOpen: open)
        case .details:
            // the details, and the trust row under them
            ProductDetails(
                descriptionHtml: product.descriptionHtml,
                metafields: state.metafields ?? [],
                policies: state.policies,
                open: state.openDetails
            ) {
                state.toggleDetails($0)
            }
            TrustRow(onOpen: open).padding(.horizontal, theme.spacing.l).padding(.top, theme.spacing.xl)
        case .reviews:
            let reviews = state.reviews
            if reviews.isShown {
                ProductReviews(reviews: reviews, onWrite: { writingReview = true }, onLoadMore: { Task { await reviews.loadMore() } })
                    .id(ProductBlock.reviews)
            }
        case .rails:
            ProductPageRail(title: "Pairs well with", cards: state.complementary ?? [], style: .compact, onOpen: open)
            ProductPageRail(title: "You may also like", cards: state.related ?? [], style: .standard, onOpen: open)
            ProductPageRail(title: "Recently viewed", cards: state.recent ?? [], style: .standard, onOpen: open)
        }
    }
}

/// Block 2: the vendor (when `AppGraph.showVendor`), the title, and the rating (`shownRating`); `onRating` makes the
/// stars a way to the reviews.
@MainActor
private struct ProductTitle: View {
    let product: Product
    let summary: ReviewSummary?
    let onRating: (() -> Void)?
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            if AppGraph.showVendor && !product.vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(product.vendor).font(theme.type.caption).foregroundStyle(theme.colors.muted).lineLimit(1)
            }
            Text(product.title).font(theme.type.title).foregroundStyle(theme.colors.ink).accessibilityAddTraits(.isHeader)
            if let rating = shownRating(summary, rating: product.rating, ratingCount: product.ratingCount) {
                if let onRating = onRating {
                    Button(action: onRating) {
                        // a row tall enough to tap
                        ArgonRating(value: rating.value, count: rating.count, size: .m)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Show reviews")
                } else {
                    ArgonRating(value: rating.value, count: rating.count, size: .m)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.l)
        .padding(.top, theme.spacing.l)
    }
}
