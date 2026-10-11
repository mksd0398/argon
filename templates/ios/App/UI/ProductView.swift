import SwiftUI
import UIKit

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

// ponytail: the Product query loads variants(first: 250), the Storefront API's page ceiling: a product with more
// variants shows "Unavailable" for the combinations that didn't load. Upgrade: paginate the variants, or query
// variantBySelectedOptions for each selection.
@MainActor
private func loadProduct(_ handle: String) async throws -> Product {
    guard let product = try await AppGraph.storefront.product(handle) else { throw NotFound(what: "Product") }
    return product
}

@MainActor
struct ProductView: View {
    let handle: String

    var body: some View {
        Loader(load: { try await loadProduct(handle) }) { product in
            ProductContent(product: product)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private struct ProductContent: View {
    let product: Product
    @State private var selection: [String: String]
    @State private var adding = false
    @State private var addError: String? = nil
    @State private var added = false
    // PDP_METAFIELDS, asked for apart from the product: a store whose token can't read them still shows the page
    @State private var metafields: [Metafield] = []

    init(product: Product) {
        self.product = product
        _selection = State(initialValue: initialSelection(product.variants))
    }

    var body: some View {
        let variant = Variants.match(product.variants, selection: selection)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Gallery(images: product.images)
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.title).font(.title2)
                            if !product.vendor.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text(product.vendor).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        WishlistHeart(productId: product.id)
                    }

                    if let variant = variant {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(variant.price.display()).font(.title3)
                            if let compare = variant.compareAt {
                                Text(compare.display()).strikethrough().foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Unavailable").font(.headline).foregroundStyle(.secondary)
                    }

                    ForEach(choices.indices, id: \.self) { index in
                        optionPicker(choices[index].name, choices[index].values)
                    }

                    Button { add(variant) } label: {
                        Text(buttonTitle(variant)).onBrand().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(variant?.available != true || adding)
                    if let addError = addError {
                        Text(addError).font(.subheadline).foregroundStyle(.red)
                    }
                    if added {
                        Text("Added to cart").font(.subheadline).foregroundStyle(.secondary)
                    }

                    HtmlText(html: product.descriptionHtml)

                    if !metafields.isEmpty {
                        Divider()
                        Text("Details").font(.headline)
                        // ponytail: values are shown as the store sends them (a rich-text or JSON metafield shows its raw text)
                        ForEach(metafields.indices, id: \.self) { index in
                            HStack(alignment: .top, spacing: 16) {
                                Text(detailLabel(metafields[index].key))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 110, alignment: .leading)
                                Text(metafields[index].value)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .task {
            let identifiers = metafieldIdentifiers(AppGraph.pdpMetafields)
            // a failure (a token without metafield access) just means no Details section
            metafields = (try? await AppGraph.storefront.productMetafields(handle: product.handle, identifiers: identifiers)) ?? []
        }
    }

    /// The options to choose from: a product without options still has Shopify's one "Title: Default Title"; nothing there.
    private var choices: [(name: String, values: [String])] {
        product.options
            .map { (name: $0.name, values: $0.optionValues.map { $0.name }) }
            .filter { !($0.name == "Title" && $0.values == ["Default Title"]) }
    }

    private func optionPicker(_ name: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.subheadline.weight(.medium))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        if selection[name] == value {
                            Button { selection[name] = value } label: { Text(value).onBrand() }.buttonStyle(.borderedProminent)
                        } else {
                            Button(value) { selection[name] = value }.buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func buttonTitle(_ variant: Variant?) -> String {
        guard let variant = variant else { return "Unavailable" }
        if !variant.available { return "Sold out" }
        return adding ? "Adding…" : "Add to cart"
    }

    private func detailLabel(_ key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + String(words.dropFirst())
    }

    private func add(_ variant: Variant?) {
        guard let id = variant?.id else { return }
        adding = true
        addError = nil
        // not tied to the screen: leaving right after the tap must not drop the add
        Task {
            do {
                try await AppGraph.cart.add(id, quantity: 1)
                adding = false
                added = true
                _ = try? await Task.sleep(nanoseconds: 2_000_000_000)
                added = false
            } catch {
                adding = false
                addError = error.localizedDescription
            }
        }
    }
}

/// Swipeable images with a "2 / 5" counter; a grey box when the product has none.
@MainActor
private struct Gallery: View {
    let images: [Img]
    @State private var page = 0

    var body: some View {
        Color.gray.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if !images.isEmpty {
                    TabView(selection: $page) {
                        ForEach(images.indices, id: \.self) { index in
                            StoreImage(image: images[index]).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if images.count > 1 {
                    Text(verbatim: "\(page + 1) / \(images.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.regularMaterial, in: Capsule())
                        .padding(12)
                }
            }
            .clipped()
    }
}
