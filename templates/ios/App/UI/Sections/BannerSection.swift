import ArgonUI
import SwiftUI

// `banner` and `slideshow`: a picture with words and a button over it.

/// A banner's width to height for its `height` setting: a hero spans the screen, a card sits inside the margins.
func bannerRatio(_ height: String, hero: Bool) -> CGFloat {
    switch height {
    case "small": return hero ? 2 : 2.4
    case "medium": return hero ? 1.2 : 1.6
    default: return hero ? 0.8 : 1.1
    }
}

/// A picture in a box of `ratio`, with the heading, the text and the button over it at the bottom start, in `textColor`.
/// A tap anywhere follows `link`; the button is a button of its own.
@MainActor
struct SectionBanner: View {
    let image: Img?
    let heading: String?
    let text: String?
    let button: String?
    let textColor: String
    let ratio: CGFloat
    let rounded: Bool
    let onTap: (() -> Void)?
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let color = theme.colors.resolve(textColor) ?? .white
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { StoreImage(image: image) }
            .overlay {
                if heading != nil || text != nil || button != nil {
                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        if let heading = heading {
                            Text(heading).font(theme.type.title).foregroundStyle(color).lineLimit(3)
                        }
                        if let text = text {
                            Text(text).font(theme.type.body).foregroundStyle(color).lineLimit(3).layoutPriority(1)
                        }
                        if let button = button, let onTap = onTap {
                            ArgonButton(title: button, action: onTap).layoutPriority(1)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .padding(theme.spacing.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .background(shade)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: rounded ? theme.radius.l : 0))
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(onTap != nil ? .isButton : [])
    }

    /// Darker towards the bottom, where the words are, so light words stay readable on any picture.
    private var shade: LinearGradient {
        LinearGradient(
            stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(image == nil ? 0.25 : 0.55), location: 1)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// `banner`: `hero` spans the screen, `card` sits inside the page's margins with rounded corners.
@MainActor
struct BannerSection: View {
    let settings: SectionSettings
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let hero = settings.choice("style", ["hero", "card"], "hero") == "hero"
        let route = scope.route(settings.link("link"))
        SectionBanner(
            image: settings.image("image"),
            heading: scope.text(settings, "heading"),
            text: scope.text(settings, "text"),
            button: route == nil ? nil : scope.text(settings, "button_label"),
            textColor: settings.color("text_color", "#FFFFFF"),
            ratio: bannerRatio(settings.choice("height", ["small", "medium", "large"], "large"), hero: hero),
            rounded: !hero,
            onTap: route.map { route in { scope.open(route, nil) } }
        )
        .padding(.horizontal, hero ? 0 : theme.spacing.l)
    }
}

/// `slideshow`: its `slide` blocks as pages that turn by themselves every `interval` seconds while `autoplay`.
@MainActor
struct SlideshowSection: View {
    let section: ScreenSection
    let scope: SectionScope
    @State private var page = 0

    var body: some View {
        let settings = section.settings
        let slides = section.blocks.filter { $0.type == "slide" }
        let ratio = bannerRatio(settings.choice("height", ["small", "medium", "large"], "large"), hero: true)
        let autoplay = settings.boolean("autoplay", true)
        let interval = settings.number("interval", 5, 3...15)
        if !slides.isEmpty {
            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    let inner = scope.with(slide)
                    let s = slide.settings
                    let route = inner.route(s.link("link"))
                    SectionBanner(
                        image: s.image("image"),
                        heading: inner.text(s, "heading"),
                        text: inner.text(s, "text"),
                        button: route == nil ? nil : inner.text(s, "button_label"),
                        textColor: "#FFFFFF",
                        ratio: ratio,
                        rounded: false,
                        onTap: route.map { route in { inner.open(route, slide.id) } }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: slides.count > 1 ? .automatic : .never))
            .aspectRatio(ratio, contentMode: .fit)
            // a turn restarts the wait, so a slide the shopper swiped to gets its whole time
            .task(id: page) {
                guard autoplay, slides.count > 1 else { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if !Task.isCancelled { withAnimation { page = (page + 1) % slides.count } }
            }
        }
    }
}
