import SwiftUI

extension Money {
    /// "$25.00": the amount in its currency, in `locale`; "5.0 XYZ" when the amount or the currency isn't known.
    func display(locale: Locale = .current) -> String {
        guard let value = Decimal(string: amount),
              Locale.Currency.isoCurrencies.contains(where: { $0.identifier == currencyCode }) else {
            return "\(amount) \(currencyCode)"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(amount) \(currencyCode)"
    }
}

/// `img` filling the space it's given (cropped), on a grey placeholder while it loads or when there is none.
@MainActor
struct RemoteImage: View {
    let img: Img?

    var body: some View {
        Color.gray.opacity(0.15)
            .overlay {
                AsyncImage(url: img.flatMap { URL(string: $0.url) }) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
            .clipped()
            .accessibilityHidden(img?.alt == nil)
            .accessibilityLabel(img?.alt ?? "")
    }
}

/// Heart toggle for the product with id `productId`: filled while it is in the wishlist.
@MainActor
struct WishlistHeart: View {
    let productId: String

    var body: some View {
        let saved = AppGraph.wishlist.contains(productId)
        let label: String = saved ? "Remove from wishlist" : "Save to wishlist"
        Button {
            Task { await AppGraph.wishlist.toggle(productId) }
        } label: {
            Image(systemName: saved ? "heart.fill" : "heart")
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .tint(saved ? nil : Color.primary)
        .accessibilityLabel(label)
    }
}

@MainActor
struct ProductCardView: View {
    let card: ProductCard
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(0.8, contentMode: .fit)
                .overlay { RemoteImage(img: card.image) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if !card.available {
                        Text("Sold out")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.background, in: RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    WishlistHeart(productId: card.id)
                        .background(.regularMaterial, in: Circle())
                        .padding(4)
                }
            Text(card.title).font(.subheadline).lineLimit(2)
            HStack(spacing: 8) {
                Text(card.price.display())
                if let compare = card.compareAt {
                    Text(compare.display()).strikethrough().foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .contentShape(Rectangle())
        // the heart is a button of its own and takes its taps before this one
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }
}
