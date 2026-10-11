import ArgonUI
import SwiftUI

// The blocks the orders list, the order page, the account page and the returns flow share.

/// An order in a list: its name, date and status tag, up to three thumbnails (then "+N"), how many items, the total, and
/// "Arrives <date>" or "Delivered <date>" once it ships. `onOpen` opens the order.
@MainActor
struct OrderCard: View {
    let order: OrderSummary
    let onOpen: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let type = theme.type, colors = theme.colors
        ArgonCard(style: .elevated, onClick: onOpen) {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                HStack(spacing: theme.spacing.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(order.name).font(type.headline).foregroundStyle(colors.ink).lineLimit(1)
                        Text(displayDate(order.processedAt)).font(type.caption).foregroundStyle(colors.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ArgonTag(text: orderStatus(order), style: .info)
                }
                thumbnails
                HStack(spacing: theme.spacing.s) {
                    Text(order.itemCount.map(itemCountLabel) ?? "")
                        .font(type.label)
                        .foregroundStyle(colors.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(order.total.display()).font(type.headline).foregroundStyle(colors.ink).lineLimit(1).fixedSize()
                }
                if let note = deliveryNote(order) {
                    Text(note).font(type.label).foregroundStyle(colors.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing.l)
        }
    }

    /// The first three items' pictures, and how many items they leave out.
    @ViewBuilder private var thumbnails: some View {
        let shown = Array(order.images.prefix(3))
        // an order's titles and pictures pair up when every line has a picture: only then is a picture named
        let named = order.images.count == order.titles.count
        if !shown.isEmpty {
            HStack(spacing: theme.spacing.s) {
                ForEach(shown.indices, id: \.self) { index in
                    StoreImage(url: shown[index].url, alt: named ? order.titles[index] : nil)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.m))
                }
                let more = moreItems(itemCount: order.itemCount, shown: shown.count)
                if more > 0 {
                    Text(verbatim: "+\(more)").font(theme.type.label).foregroundStyle(theme.colors.muted).lineLimit(1)
                }
            }
        }
    }
}

/// An item of an order or a return: its thumbnail, `title`, the `details` under it (variant, SKU, quantity, ...), and
/// `trailing` at the end of the line (a price).
@MainActor
struct ItemRow: View {
    let image: Img?
    let title: String
    let details: [String]
    var trailing: String? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let type = theme.type, colors = theme.colors
        HStack(alignment: .top, spacing: theme.spacing.m) {
            // decorative: the title beside it says what it is
            StoreImage(url: image?.url)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.m))
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(title).font(type.label).foregroundStyle(colors.ink).lineLimit(2)
                ForEach(details.indices, id: \.self) { index in
                    Text(details[index]).font(type.caption).foregroundStyle(colors.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing = trailing {
                Text(trailing).font(type.label).foregroundStyle(colors.ink).lineLimit(1).fixedSize()
            }
        }
    }
}
