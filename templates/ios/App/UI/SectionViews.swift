import SwiftUI

/// One view per home section type.
@MainActor
struct SectionView: View {
    let section: Section

    var body: some View {
        switch section {
        case let .banner(style, image, heading, text, buttonLabel, link):
            BannerView(card: style == "card", image: image, heading: heading, text: text, buttonLabel: buttonLabel, link: link)
        case let .products(heading, style, items):
            ProductsView(heading: heading, grid: style == "grid", items: items)
        case let .collections(heading, items):
            CollectionsView(heading: heading, items: items)
        }
    }
}

@MainActor
private struct Heading: View {
    let text: String?

    var body: some View {
        if let text = text, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(text)
                .font(.title2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 12)
        }
    }
}

/// `hero`: full width, edge to edge. `card`: rounded and inset. Without an image the box is the accent colour.
@MainActor
private struct BannerView: View {
    let card: Bool
    let image: Img?
    let heading: String?
    let text: String?
    let buttonLabel: String?
    let link: Route?
    @Environment(Router.self) private var router

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = image {
                Color.clear
                    .aspectRatio(ratio(image), contentMode: .fit)
                    .overlay { RemoteImage(img: image) }
                    .overlay { LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom) }
            }
            VStack(alignment: .leading, spacing: 8) {
                if let heading = heading { Text(heading).font(.title2.bold()) }
                if let text = text { Text(text).font(.subheadline) }
                if let buttonLabel = buttonLabel, let link = link {
                    if image != nil {
                        Button(buttonLabel) { router.open(link) }.buttonStyle(.borderedProminent)
                    } else {
                        // on the accent box: a light button, not one the colour of the box
                        Button(buttonLabel) { router.open(link) }.buttonStyle(.bordered).tint(Color.white)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .bottomLeading)
        }
        .background(.tint) // shows only where there is no image
        .clipShape(RoundedRectangle(cornerRadius: card ? 16 : 0))
        .contentShape(Rectangle())
        .onTapGesture { if let link = link { router.open(link) } }
        .padding(card ? 16 : 0)
    }

    /// The image's own shape, kept between square and 2:1.
    private func ratio(_ image: Img) -> CGFloat {
        guard let width = image.width, let height = image.height, height > 0 else { return 1.5 }
        return min(max(CGFloat(width) / CGFloat(height), 1), 2)
    }
}

/// `carousel` scrolls sideways; `grid` is two columns.
@MainActor
private struct ProductsView: View {
    let heading: String?
    let grid: Bool
    let items: [ProductCard]
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            Heading(text: heading)
            if grid {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 16) {
                    ForEach(items, id: \.id) { card in
                        ProductCardView(card: card) { router.open(.product(card.handle)) }
                    }
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items, id: \.id) { card in
                            ProductCardView(card: card) { router.open(.product(card.handle)) }.frame(width: 160)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

@MainActor
private struct CollectionsView: View {
    let heading: String?
    let items: [CollectionCard]
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            Heading(text: heading)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items, id: \.id) { collection in
                        RemoteImage(img: collection.image)
                            .frame(width: 140, height: 140)
                            .overlay(alignment: .bottomLeading) {
                                Text(collection.title)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(collection.image != nil ? Color.white : Color.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(collection.image != nil ? Color.black.opacity(0.45) : Color.clear)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture { router.open(.collection(collection.handle)) }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
