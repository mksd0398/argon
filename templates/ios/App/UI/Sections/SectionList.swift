import ArgonUI
import Foundation
import Observation
import os
import SwiftUI

// Screens v2: a screen's sections, loaded from its `app_screen` metaobject and drawn one under the other. The views of
// the section types are in this folder, one per type. The same on Android (ui/sections/).

private let screensLog = Logger(subsystem: "app.storefront", category: "Screens")

/// Whose metafields a screen's Liquid reads besides the shop's: the product or the collection on show (by handle).
enum MetafieldOwner: Equatable {
    case product(String)
    case collection(String)
}

/// A screen's template with everything its sections show: the products and collections (one SectionNodes call), the
/// shop and its metafields, the metafields of the screen's product or collection, and the customer when one is signed
/// in and the template reads `customer`.
struct LoadedScreen {
    let handle: String
    let title: String
    let template: ScreenTemplate
    var nodes: [String: Node] = [:]
    var shop: Shop? = nil
    var shopMetafields: [Metafield] = []
    var ownerMetafields: [Metafield] = []
    var customer: Customer? = nil

    /// The Liquid objects for this screen (`ScreenContext`), with its `product` or `collection`, and the cart as it is now.
    @MainActor
    func context(product: Product? = nil, collection: (title: String, handle: String, description: String)? = nil) -> [String: JSONValue] {
        ScreenContext.build(
            shop: shop,
            shopMetafields: shopMetafields,
            product: product,
            productMetafields: product == nil ? [] : ownerMetafields,
            collection: collection,
            collectionMetafields: collection == nil ? [] : ownerMetafields,
            customer: customer,
            cart: AppGraph.cart.cart
        )
    }

    var placement: SectionPlacement { template.placement(handle) }
}

/// The `app_screen` `handle` with what its sections show; nil when the store has none, its template isn't JSON, or it
/// can't be loaded: the screen is then as it always was. Only the template is needed: every other call fails quietly
/// (logged), and the sections draw what they can.
@MainActor
func loadScreen(_ handle: String, owner: MetafieldOwner? = nil) async -> LoadedScreen? {
    let api = AppGraph.storefront
    let screen: AppScreen?
    do {
        screen = try await api.appScreen(handle)
    } catch {
        if !Task.isCancelled { screensLog.warning("screen \(handle, privacy: .public) not loaded: \(error.localizedDescription)") }
        return nil
    }
    guard let found = screen, let template = ScreenTemplate.decode(found.template) else { return nil }
    var loaded = LoadedScreen(handle: handle, title: found.title, template: template)
    let ids = template.nodeIds
    async let nodes = quietly("sections", handle, [Node]()) { try await api.sectionNodes(ids) }
    async let shop = quietly("shop", handle, Shop?.none) { try await api.shop() }
    async let shopFields = quietly("shop metafields", handle, [Metafield]()) {
        try await api.shopMetafields(identifiers: template.metafieldIdentifiers("shop"))
    }
    async let ownerFields = quietly("metafields", handle, [Metafield]()) { () async throws -> [Metafield] in
        switch owner {
        case let .product(handle)?:
            return try await api.productMetafields(handle: handle, identifiers: template.metafieldIdentifiers("product"))
        case let .collection(handle)?:
            return try await api.collectionMetafields(handle: handle, identifiers: template.metafieldIdentifiers("collection"))
        case nil:
            return []
        }
    }
    // the customer only when the Liquid reads them: it is a Customer Account API call
    let readsCustomer = AppGraph.hasAccount && (found.template ?? "").contains("customer")
    async let customer = quietly("customer", handle, Customer?.none) { () async throws -> Customer? in
        guard readsCustomer else { return nil }
        return try await AppGraph.customerAccount.customer()
    }
    var byId: [String: Node] = [:]
    for node in await nodes {
        switch node {
        case let .product(card): byId[card.id] = node
        case let .collection(card): byId[card.id] = node
        default: break
        }
    }
    loaded.nodes = byId
    loaded.shop = await shop
    loaded.shopMetafields = await shopFields
    loaded.ownerMetafields = await ownerFields
    loaded.customer = await customer
    return loaded
}

/// The result of `load`, or `fallback` when it fails (logged): a screen's secondary calls never fail it.
@MainActor
private func quietly<T>(_ what: String, _ screen: String, _ fallback: T, _ load: @MainActor () async throws -> T) async -> T {
    do {
        return try await load()
    } catch {
        if !Task.isCancelled {
            screensLog.warning("\(what, privacy: .public) of screen \(screen, privacy: .public) not loaded: \(error.localizedDescription)")
        }
        return fallback
    }
}

/// A screen's `app_screen`, loaded once per visit (the view that keeps this in its state), quietly. `screen` stays nil
/// while it loads, and when there is none: the screen then shows what it always did.
@MainActor
@Observable
final class ScreenSlot {
    let handle: String
    private(set) var screen: LoadedScreen? = nil
    @ObservationIgnored private var started = false

    init(_ handle: String) {
        self.handle = handle
    }

    func load(owner: MetafieldOwner? = nil) async {
        if started { return }
        started = true
        let loaded = await loadScreen(handle, owner: owner)
        // a load cut short (the screen left) is asked again the next time it shows
        if Task.isCancelled {
            started = false
            return
        }
        screen = loaded
    }

    var placement: SectionPlacement { screen?.placement ?? SectionPlacement() }
}

// MARK: Views

/// What a section's view needs: its Liquid objects (`section` and, inside a slide, `block` included), the loaded
/// products and collections, and `open`, which follows a tap (and reports it as `select_promotion`).
@MainActor
struct SectionScope {
    let context: [String: JSONValue]
    let nodes: [String: Node]
    /// A route, and the id of the block it was tapped in (nil: the section's own).
    let open: (Route, String?) -> Void
    var block: SectionBlock? = nil

    /// The scope of a block inside the section: its Liquid has `block`.
    func with(_ block: SectionBlock) -> SectionScope {
        var context = self.context
        context["block"] = .object(["id": .string(block.id), "settings": .object(block.settings.values)])
        return SectionScope(context: context, nodes: nodes, open: open, block: block)
    }

    /// `text` with its Liquid evaluated; nil when that leaves it blank.
    func liquid(_ text: String?) -> String? {
        guard let text = text else { return nil }
        let rendered = Liquid.render(text, context)
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : rendered
    }

    /// A text setting through Liquid.
    func text(_ settings: SectionSettings, _ key: String) -> String? { liquid(settings.text(key)) }

    /// Where `link` (through Liquid) leads in the app (`Links.resolve`); nil when nowhere.
    func route(_ link: String?) -> Route? {
        guard let link = liquid(link) else { return nil }
        return Links.resolve(link, hosts: AppGraph.brand.value?.hosts ?? [AppGraph.shopDomain])
    }

    /// Follows `link`, when it leads somewhere.
    func follow(_ link: String?) {
        if let route = route(link) { open(route, block?.id) }
    }

    func product(_ id: String) -> ProductCard? { nodes[id]?.productCard }

    func collection(_ id: String) -> CollectionCard? { nodes[id]?.collectionCard }
}

/// `sections` of `screen` one under the other, in a lazy stack (so each reports `view_promotion` as it first comes into
/// view, once per visit), each with the full width: a section brings its own side margins. `context` is the screen's
/// Liquid objects (`LoadedScreen.context`).
@MainActor
struct SectionList: View {
    let sections: [ScreenSection]
    let screen: LoadedScreen
    let context: [String: JSONValue]
    @State private var seen: Set<String> = []
    @Environment(Router.self) private var router
    @Environment(\.argonTheme) private var theme

    var body: some View {
        LazyVStack(spacing: theme.spacing.xl) {
            ForEach(sections, id: \.id) { section in
                SectionView(section: section, scope: scope(section))
                    .onAppear {
                        if seen.insert(section.id).inserted { AppGraph.analytics.track(.viewPromotion(promotion(section))) }
                    }
            }
        }
    }

    private func promotion(_ section: ScreenSection, creative: String? = nil) -> Promotion {
        Promotion(id: section.id, name: section.promotionName, slot: "\(screen.handle):\(screen.template.index(of: section))", creative: creative)
    }

    private func scope(_ section: ScreenSection) -> SectionScope {
        var context = self.context
        context["section"] = .object(["id": .string(section.id), "settings": .object(section.settings.values)])
        return SectionScope(context: context, nodes: screen.nodes) { route, block in
            AppGraph.analytics.track(.selectPromotion(promotion(section, creative: block)))
            router.open(route)
        }
    }
}

/// One section, drawn by its type's view.
@MainActor
struct SectionView: View {
    let section: ScreenSection
    let scope: SectionScope

    var body: some View {
        switch section.type {
        case "banner": BannerSection(settings: section.settings, scope: scope)
        case "slideshow": SlideshowSection(section: section, scope: scope)
        case "products": ProductsSection(settings: section.settings, scope: scope)
        case "collections": CollectionsSection(settings: section.settings, scope: scope)
        case "rich_text": RichTextSection(settings: section.settings, scope: scope)
        case "image_with_text": ImageWithTextSection(settings: section.settings, scope: scope)
        case "video": VideoSection(settings: section.settings)
        case "countdown": CountdownSection(settings: section.settings, scope: scope)
        case "spacer": SpacerSection(settings: section.settings)
        case "custom": CustomSection(settings: section.settings, scope: scope)
        default: EmptyView()
        }
    }
}

/// The sections above or below a system screen's own content (`slot`'s placement), with the screen's Liquid objects,
/// `top` and `bottom` apart from what is around them; nothing (and no room) while there are none.
@MainActor
struct ScreenSections: View {
    enum Part {
        case above, below
    }

    let slot: ScreenSlot
    let part: Part
    var product: Product? = nil
    var collection: (title: String, handle: String, description: String)? = nil
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    var body: some View {
        if let screen = slot.screen {
            let placement = screen.placement
            let sections = part == .above ? placement.above : placement.below
            if !sections.isEmpty {
                SectionList(sections: sections, screen: screen, context: screen.context(product: product, collection: collection))
                    .padding(.top, top)
                    .padding(.bottom, bottom)
            }
        }
    }

    /// Whether there is anything to draw.
    static func has(_ slot: ScreenSlot, _ part: Part) -> Bool {
        let placement = slot.placement
        return !(part == .above ? placement.above : placement.below).isEmpty
    }
}
