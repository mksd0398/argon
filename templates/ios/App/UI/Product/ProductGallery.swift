import ArgonUI
import SwiftUI
import UIKit

// Block 1 of the product page: the image pager with its tags, and the full-screen viewer a tap opens.
// ponytail: images only (`Product.images`): a product's videos and 3D models are decoded but not shown. Upgrade: a page
// with a player for `Media.Content.video`.

/// Where `image` (a variant's own) sits among the product's `images`; nil when it isn't one of them. The CDN's size
/// parameters (after `?`) don't count.
func imageIndex(_ images: [Img], _ image: Img?) -> Int? {
    guard let url = image?.url.prefix(while: { $0 != "?" }) else { return nil }
    return images.firstIndex { $0.url.prefix(while: { $0 != "?" }) == url }
}

/// A tag over the gallery; `isSale` puts it on the sale colour.
struct GalleryTag: Equatable {
    let text: String
    var isSale = false
}

/// What the gallery says about `variant` at a glance: "Sale −20%", "Sold out", "Bundle", each only when it is true.
func galleryTags(_ variant: Variant?) -> [GalleryTag] {
    guard let variant = variant else { return [] }
    var tags: [GalleryTag] = []
    if let sale = saleTag(variant.price, variant.compareAt) { tags.append(GalleryTag(text: sale, isSale: true)) }
    if !variant.available { tags.append(GalleryTag(text: "Sold out")) }
    if variant.requiresComponents { tags.append(GalleryTag(text: "Bundle")) }
    return tags
}

// MARK: - Views

/// The product's `images`, edge to edge and 4:5, one per page with page dots under them, and `tags` over the top
/// corner. A tap calls `onOpen` with the page (the full-screen viewer). A product without images shows the quiet
/// placeholder. `page` is the caller's, so choosing an option can bring its variant's image into view.
@MainActor
struct ProductGallery: View {
    let images: [Img]
    let title: String
    @Binding var page: Int
    let tags: [GalleryTag]
    let onOpen: (_ page: Int) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            Color.clear
                .aspectRatio(0.8, contentMode: .fit)
                .overlay {
                    if images.isEmpty {
                        StoreImage(image: nil)
                    } else {
                        TabView(selection: $page) {
                            ForEach(images.indices, id: \.self) { index in
                                // the image's own alt text; the product's title when it has none
                                StoreImage(url: images[index].url, alt: images[index].alt ?? title)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onOpen(index) }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("View full screen")
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: theme.spacing.xs) {
                        ForEach(tags, id: \.text) { tag in LabelTag(text: tag.text, isSale: tag.isSale) }
                    }
                    .padding(theme.spacing.m)
                    // the tags sit over the pager: a tap or a swipe that starts on one still reaches it
                    .allowsHitTesting(false)
                }
                .clipped()
            if images.count > 1 { PageDots(count: images.count, current: page) }
        }
    }
}

/// One dot per image, the current one larger and in ink: the dots of `ArgonCarousel`, for a pager the page drives itself.
@MainActor
private struct PageDots: View {
    let count: Int
    let current: Int
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let position = "Image \(current + 1) of \(count)"
        HStack(spacing: theme.spacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? theme.colors.ink : theme.colors.border)
                    .frame(width: index == current ? 8 : 6, height: index == current ? 8 : 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityValue(position)
    }
}

/// The product's `images` over the whole screen, opened at page `start`: swipe between them, pinch or double-tap to
/// zoom, drag a zoomed image around. It is the content of `argonFullScreenModal`, whose Close button dismisses it.
@MainActor
struct GalleryViewer: View {
    let images: [Img]
    let title: String
    @State private var page: Int
    @Environment(\.argonTheme) private var theme

    init(images: [Img], title: String, start: Int) {
        self.images = images
        self.title = title
        _page = State(initialValue: min(max(start, 0), max(images.count - 1, 0)))
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(images.indices, id: \.self) { index in
                ZoomableImage(url: URL(string: images[index].url), label: images[index].alt ?? title).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(theme.colors.paper)
    }
}

private let maxZoom: CGFloat = 4
private let doubleTapZoom: CGFloat = 2.5

/// The image at `url` whole in its frame; pinch to zoom up to 4x, double-tap to zoom in and back out, drag while zoomed.
/// A zooming `UIScrollView`: at rest it has nothing to scroll, so one finger is the pager's swipe; zoomed, the drag is its
/// own and stops at the image's edges.
/// ponytail: the image is fetched once (from the URL cache the gallery filled, as a rule) and a failed fetch leaves the
/// page blank until the viewer is opened again. Upgrade: a retry, and a spinner while it loads.
private struct ZoomableImage: UIViewRepresentable {
    let url: URL?
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = maxZoom
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.delegate = context.coordinator
        let picture = context.coordinator.picture
        picture.contentMode = .scaleAspectFit
        picture.frame = scroll.bounds
        // as large as the scroll view at rest; zoomed, the scroll view scales it
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        picture.isAccessibilityElement = true
        picture.accessibilityTraits = .image
        picture.accessibilityLabel = label
        scroll.addSubview(picture)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        context.coordinator.load(url)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let picture = UIImageView()

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }

        @objc func toggleZoom(_ tap: UITapGestureRecognizer) {
            guard let scroll = tap.view as? UIScrollView else { return }
            scroll.setZoomScale(scroll.zoomScale > 1 ? 1 : doubleTapZoom, animated: true)
        }

        func load(_ url: URL?) {
            guard let url = url else { return }
            Task {
                guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                picture.image = UIImage(data: data)
            }
        }
    }
}
