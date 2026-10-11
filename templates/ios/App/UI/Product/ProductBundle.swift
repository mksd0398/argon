import ArgonUI
import SwiftUI

/// Block 8 of the product page, from the selected variant in full. "This bundle includes": each part's image, product,
/// variant and "× n". "Also sold in": the bundles this variant is a part of, each opening its product (`onOpen`).
@MainActor
struct ProductBundle: View {
    let variant: Variant?
    let onOpen: (Route) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let parts = variant?.components ?? []
        let bundles = variant?.groupedBy ?? []
        if !parts.isEmpty || !bundles.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                if !parts.isEmpty {
                    SectionHeader(title: "This bundle includes")
                    ForEach(parts.indices, id: \.self) { index in
                        BundleRow(item: parts[index].variant) {
                            Text(verbatim: "× \(parts[index].quantity)").font(theme.type.label).foregroundStyle(theme.colors.ink)
                        }
                    }
                }
                if !bundles.isEmpty {
                    SectionHeader(title: "Also sold in")
                    ForEach(bundles, id: \.id) { bundle in
                        Button { onOpen(.product(bundle.product.handle)) } label: {
                            BundleRow(item: bundle) { ArgonIcon(name: .chevronRight, tint: theme.colors.muted) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.xl)
        }
    }
}

/// A part or a bundle: image, product title, variant title (not Shopify's "Default Title"), and `trailing` at the end.
@MainActor
private struct BundleRow<Trailing: View>: View {
    let item: ComponentVariant
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.argonTheme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.m) {
            StoreImage(url: item.image?.url, alt: item.image?.alt ?? item.product.title)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.s))
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(item.product.title).font(theme.type.label).foregroundStyle(theme.colors.ink).lineLimit(2)
                if item.title != "Default Title" {
                    Text(item.title).font(theme.type.caption).foregroundStyle(theme.colors.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .contentShape(Rectangle())
    }
}
