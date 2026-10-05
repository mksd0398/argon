import Foundation

// Lenient accessors over JSONSerialization output: a missing or null field reads as nil / empty.
// `string` is for fields the query guarantees.
extension Dictionary where Key == String, Value == Any {
    func obj(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }

    func str(_ key: String) -> String? { self[key] as? String }

    func string(_ key: String) throws -> String {
        guard let value = str(key) else {
            throw StorefrontException(messages: ["Missing \"\(key)\" in response"], status: nil)
        }
        return value
    }

    func int(_ key: String) -> Int? { self[key] as? Int }

    func bool(_ key: String) -> Bool { (self[key] as? Bool) == true }

    func objects(_ key: String) -> [[String: Any]] {
        guard let array = self[key] as? [Any] else { return [] }
        return array.compactMap { $0 as? [String: Any] }
    }

    func nodes(_ key: String) -> [[String: Any]] { obj(key)?.objects("nodes") ?? [] }
}

private func money(_ m: [String: Any]?) throws -> Money {
    guard let m = m else { throw StorefrontException(messages: ["Missing money in response"], status: nil) }
    return try Money(amount: m.string("amount"), currencyCode: m.string("currencyCode"))
}

func img(_ i: [String: Any]?) -> Img? {
    guard let i = i, let url = i.str("url") else { return nil }
    return Img(url: url, alt: i.str("altText"), width: i.int("width"), height: i.int("height"))
}

// Shopify reports "no compare-at" as null or 0.0; only a higher compare-at is a real discount.
private func compareAt(_ price: Money, _ compare: Money?) -> Money? {
    guard let compare = compare,
          let was = Decimal(string: compare.amount),
          let now = Decimal(string: price.amount),
          was > now else { return nil }
    return compare
}

// Broken references (null, or a `... on Product` that didn't match) arrive without an id and are skipped.
func cards(_ nodes: [[String: Any]]) throws -> [ProductCard] {
    try nodes.filter { $0["id"] != nil }.map { try parseProductCard($0) }
}

func parseProductCard(_ p: [String: Any]) throws -> ProductCard {
    let price = try money(p.obj("priceRange")?.obj("minVariantPrice"))
    let compareNode = p.obj("compareAtPriceRange")?.obj("minVariantPrice")
    let compare: Money? = try compareNode.map { try money($0) }
    return try ProductCard(
        id: p.string("id"),
        handle: p.string("handle"),
        title: p.string("title"),
        available: p.bool("availableForSale"),
        image: img(p.obj("featuredImage")),
        price: price,
        compareAt: compareAt(price, compare)
    )
}

func parseCollectionCard(_ c: [String: Any]) throws -> CollectionCard {
    try CollectionCard(id: c.string("id"), handle: c.string("handle"), title: c.string("title"), image: img(c.obj("image")))
}

func parseProduct(_ p: [String: Any]) throws -> Product {
    var options: [(name: String, values: [String])] = []
    for o in p.objects("options") {
        let name = try o.string("name")
        let values: [String] = try o.objects("optionValues").map { try $0.string("name") }
        options.append((name: name, values: values))
    }

    var variants: [Variant] = []
    for v in p.nodes("variants") {
        let price = try money(v.obj("price"))
        let compare: Money? = try v.obj("compareAtPrice").map { try money($0) }
        var selected: [String: String] = [:]
        for option in v.objects("selectedOptions") {
            let name = try option.string("name")
            selected[name] = try option.string("value")
        }
        let variant = try Variant(
            id: v.string("id"),
            title: v.string("title"),
            available: v.bool("availableForSale"),
            options: selected,
            price: price,
            compareAt: compareAt(price, compare),
            image: img(v.obj("image"))
        )
        variants.append(variant)
    }

    // identifiers with no value on this product come back as null entries
    var metafields: [(namespace: String, key: String, value: String)] = []
    for m in p.objects("metafields") {
        guard let value = m.str("value") else { continue }
        let namespace = try m.string("namespace")
        let key = try m.string("key")
        metafields.append((namespace: namespace, key: key, value: value))
    }

    return try Product(
        id: p.string("id"),
        handle: p.string("handle"),
        title: p.string("title"),
        vendor: p.str("vendor") ?? "",
        descriptionHtml: p.str("descriptionHtml") ?? "",
        images: p.nodes("media").compactMap { img($0.obj("image")) },
        options: options,
        variants: variants,
        metafields: metafields
    )
}

// `input` is a JSON scalar; Shopify sends it as a string of JSON.
private func jsonText(_ value: Any?) -> String {
    if let text = value as? String { return text }
    guard let value = value, JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value) else { return "null" }
    return String(decoding: data, as: UTF8.self)
}

/// `connection` is a product connection; `filtersKey` is `filters` (collection) or `productFilters` (search).
func parseProductPage(_ connection: [String: Any], filtersKey: String) throws -> ProductPage {
    var filters: [Filter] = []
    for f in connection.objects(filtersKey) {
        var values: [FilterValue] = []
        for v in f.objects("values") {
            let value = try FilterValue(id: v.string("id"), label: v.string("label"), count: v.int("count") ?? 0, input: jsonText(v["input"]))
            values.append(value)
        }
        let filter = try Filter(id: f.string("id"), label: f.string("label"), type: f.string("type"), values: values)
        filters.append(filter)
    }
    let pageInfo = connection.obj("pageInfo")
    return try ProductPage(
        items: cards(connection.objects("nodes")),
        filters: filters,
        endCursor: pageInfo?.str("endCursor"),
        hasNext: pageInfo?.bool("hasNextPage") == true
    )
}

func parseCart(_ cart: [String: Any]) throws -> Cart {
    var lines: [CartLine] = []
    for line in cart.nodes("lines") {
        guard let variant = line.obj("merchandise"), variant["id"] != nil else { continue }
        let product = variant.obj("product")
        let cartLine = try CartLine(
            id: line.string("id"),
            quantity: line.int("quantity") ?? 0,
            variantId: variant.string("id"),
            variantTitle: variant.string("title"),
            productHandle: product?.str("handle") ?? "",
            productTitle: product?.str("title") ?? "",
            image: img(variant.obj("image")),
            price: money(variant.obj("price")),
            total: money(line.obj("cost")?.obj("totalAmount"))
        )
        lines.append(cartLine)
    }
    return try Cart(
        id: cart.string("id"),
        checkoutUrl: cart.string("checkoutUrl"),
        totalQuantity: cart.int("totalQuantity") ?? 0,
        subtotal: money(cart.obj("cost")?.obj("subtotalAmount")),
        total: money(cart.obj("cost")?.obj("totalAmount")),
        lines: lines
    )
}

/// `Customer.graphql`'s `customer`.
func parseCustomer(_ c: [String: Any]) throws -> Customer {
    var orders: [OrderSummary] = []
    for o in c.nodes("orders") {
        let order = try OrderSummary(
            id: o.string("id"),
            name: o.string("name"),
            processedAt: o.string("processedAt"),
            financialStatus: o.str("financialStatus"),
            total: money(o.obj("totalPrice"))
        )
        orders.append(order)
    }
    return Customer(
        name: [c.str("firstName"), c.str("lastName")].compactMap { $0 }.joined(separator: " "),
        email: c.obj("emailAddress")?.str("emailAddress"),
        orders: orders
    )
}

/// `Order.graphql`'s `order`.
func parseOrder(_ o: [String: Any]) throws -> Order {
    var lines: [OrderLine] = []
    for l in o.nodes("lineItems") {
        let total: Money? = try l.obj("totalPrice").map { try money($0) }
        let line = try OrderLine(
            title: l.string("title"),
            variantTitle: l.str("variantTitle"),
            quantity: l.int("quantity") ?? 0,
            image: img(l.obj("image")),
            total: total
        )
        lines.append(line)
    }
    let subtotal: Money? = try o.obj("subtotal").map { try money($0) }
    return try Order(
        name: o.string("name"),
        processedAt: o.string("processedAt"),
        financialStatus: o.str("financialStatus"),
        fulfillments: o.nodes("fulfillments").compactMap { $0.str("status") },
        lines: lines,
        subtotal: subtotal,
        total: money(o.obj("totalPrice"))
    )
}

/// Menu items route through their linked resource, else through `Links`. Unroutable leaves are dropped.
func parseMenu(_ menu: [String: Any], hosts: [String]) throws -> [MenuItem] {
    var items: [MenuItem] = []
    for item in menu.objects("items") {
        let children = try parseMenu(item, hosts: hosts)
        let handle = item.obj("resource")?.str("handle")
        let type = item.str("type")
        var route: Route?
        if let handle = handle, type == "PRODUCT" {
            route = .product(handle)
        } else if let handle = handle, type == "COLLECTION" {
            route = .collection(handle)
        } else {
            route = Links.resolve(item.str("url"), hosts: hosts)
        }
        // ponytail: a pure header item (url "#") keeps its children behind a placeholder web route; the UI expands it
        if route == nil && !children.isEmpty { route = .web(item.str("url") ?? "") }
        guard let target = route else { continue }
        let title = try item.string("title")
        items.append(MenuItem(title: title, route: target, children: children))
    }
    return items
}

/// `configDomain` is SHOP_DOMAIN; together with the primary domain it decides which links stay in the app.
func parseBrand(_ shop: [String: Any], configDomain: String) throws -> Brand {
    let brand = shop.obj("brand")
    var hosts = [configDomain]
    if let primary = shop.obj("primaryDomain")?.str("host"), !hosts.contains(primary) { hosts.append(primary) }
    let colors = brand?.obj("colors")?.objects("primary") ?? []
    return try Brand(
        name: shop.string("name"),
        logo: img(brand?.obj("logo")?.obj("image")),
        cover: img(brand?.obj("coverImage")?.obj("image")),
        accent: colors.first?.str("background"),
        hosts: hosts
    )
}
