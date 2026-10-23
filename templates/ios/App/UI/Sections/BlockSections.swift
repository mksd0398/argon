import ArgonUI
import SwiftUI

// `marquee`, and the sections made of blocks: `faq`, `features` and `image_grid`. A tap on a question, a feature or a
// tile reports its block (`creative_name`), as a slide does.

/// The points a second a marquee's text moves at for its `speed`.
func marqueeSpeed(_ speed: String) -> Double {
    switch speed {
    case "slow": return 30
    case "fast": return 90
    default: return 60
    }
}

/// `marquee`: one line of text running from end to start without end, repeated to fill the strip (whose colour is the
/// section's background, the theme's `text` without one: `ScreenSection.background`). The whole strip follows `link`. Still with
/// Reduce Motion.
@MainActor
struct MarqueeSection: View {
    let settings: SectionSettings
    let scope: SectionScope
    // the width of one copy of the text with its gap, and of the strip: how far a loop runs, and how many copies fill it
    @State private var itemWidth: CGFloat = 0
    @State private var stripWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.argonTheme) private var theme

    var body: some View {
        if let text = scope.text(settings, "text") {
            let route = scope.route(settings.link("link"))
            let speed = marqueeSpeed(settings.choice("speed", ["slow", "medium", "fast"], "medium"))
            let item = Text(text)
                .font(theme.type.label)
                .foregroundStyle(theme.colors.resolve(settings.color("text_color", "background")) ?? theme.colors.paper)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, theme.spacing.xxl)
            let copies = itemWidth > 0 ? Int((stripWidth / itemWidth).rounded(.up)) + 1 : 1
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let moved = itemWidth > 0 && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate * speed : 0
                HStack(spacing: 0) {
                    ForEach(0..<copies, id: \.self) { _ in item }
                }
                // one copy along, the next is where the first was: the loop doesn't show
                .offset(x: itemWidth > 0 ? -CGFloat(moved.truncatingRemainder(dividingBy: Double(itemWidth))) : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, theme.spacing.s)
            .clipped()
            .background { item.hidden().onGeometryChange(for: CGFloat.self) { $0.size.width } action: { itemWidth = $0 } }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
            .contentShape(Rectangle())
            .onTapGesture { if let route = route { scope.open(route, nil) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(route != nil ? .isButton : [])
        }
    }
}

/// `faq`: a heading over its `question` blocks (up to 20) as an accordion, all closed; a question opens to its answer
/// (simple HTML).
@MainActor
struct FaqSection: View {
    let section: ScreenSection
    let scope: SectionScope
    @State private var opened: Set<String> = []
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let questions = Array(section.blocks.filter { $0.type == "question" }.prefix(20))
        VStack(alignment: .leading, spacing: 0) {
            if let heading = scope.text(section.settings, "heading") {
                SectionHeader(title: heading).padding(.bottom, theme.spacing.s)
            }
            ForEach(questions, id: \.id) { block in
                let inner = scope.with(block)
                if let question = inner.text(block.settings, "question") {
                    ArgonAccordion(title: question, isExpanded: opened.contains(block.id), onToggle: {
                        if opened.remove(block.id) == nil { opened.insert(block.id) }
                        inner.open(nil, block.id)
                    }) {
                        if let answer = inner.text(block.settings, "answer") { HtmlText(html: answer) }
                    }
                    ArgonDivider()
                }
            }
        }
        .padding(.horizontal, theme.spacing.l)
    }
}

/// The icons a feature can show (the contract's FEATURE_ICONS), each named as in Argon's icon set.
let featureIcons = ["truck", "returns", "lock", "leaf", "gift", "clock", "star", "heart", "globe", "check", "tag", "phone", "mail", "location", "info"]

/// A feature's `icon` setting as Argon's icon; `check` for one it doesn't know.
func featureIcon(_ settings: SectionSettings) -> ArgonIconName {
    ArgonIconName(rawValue: settings.choice("icon", featureIcons, "check")) ?? .check
}

/// `features`: a heading over its `feature` blocks (up to 8), each an icon above a heading and a line of text; in a row
/// that scrolls sideways when it doesn't fit (`row`), or two to a row (`grid`).
@MainActor
struct FeaturesSection: View {
    let section: ScreenSection
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let features = Array(section.blocks.filter { $0.type == "feature" }.prefix(8))
        let grid = section.settings.choice("layout", ["row", "grid"], "row") == "grid"
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            if let heading = scope.text(section.settings, "heading") {
                SectionHeader(title: heading).padding(.horizontal, theme.spacing.l)
            }
            if grid {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: theme.spacing.m), GridItem(.flexible())], spacing: theme.spacing.l) {
                    ForEach(features, id: \.id) { feature($0).frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, theme.spacing.l)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: theme.spacing.l) {
                        ForEach(features, id: \.id) { feature($0).frame(width: 136) }
                    }
                    .padding(.horizontal, theme.spacing.l)
                }
            }
        }
    }

    private func feature(_ block: SectionBlock) -> some View {
        let inner = scope.with(block)
        return VStack(spacing: theme.spacing.xs) {
            ArgonIcon(name: featureIcon(block.settings), size: 24, tint: theme.colors.ink)
                .padding(.bottom, theme.spacing.xs)
            if let heading = inner.text(block.settings, "heading") {
                Text(heading).font(theme.type.label).foregroundStyle(theme.colors.ink)
            }
            if let text = inner.text(block.settings, "text") {
                Text(text).font(theme.type.caption).foregroundStyle(theme.colors.muted)
            }
        }
        .multilineTextAlignment(.center)
        .contentShape(Rectangle())
        .onTapGesture { inner.open(nil, block.id) }
        .accessibilityElement(children: .combine)
    }
}

/// A grid tile's width to height for the section's `aspect`: `square` 1:1, `portrait` 4:5, `landscape` 4:3.
func tileRatio(_ aspect: String) -> CGFloat {
    switch aspect {
    case "portrait": return 0.8
    case "landscape": return 4.0 / 3.0
    default: return 1
    }
}

/// `image_grid`: a heading over its `tile` blocks (up to 12) in `columns` columns at `aspect`, each tile's heading under
/// its picture; a tap opens the tile's `link`. A tile without a picture is left out.
@MainActor
struct ImageGridSection: View {
    let section: ScreenSection
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let settings = section.settings
        let tiles = Array(section.blocks.filter { $0.type == "tile" && $0.settings.image("image") != nil }.prefix(12))
        let columns = settings.choice("columns", ["2", "3"], "2") == "3" ? 3 : 2
        let ratio = tileRatio(settings.choice("aspect", ["square", "portrait", "landscape"], "square"))
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                if let heading = scope.text(settings, "heading") { SectionHeader(title: heading) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.s), count: columns), spacing: theme.spacing.m) {
                    ForEach(tiles, id: \.id) { tile($0, ratio: ratio) }
                }
            }
            .padding(.horizontal, theme.spacing.l)
        }
    }

    private func tile(_ block: SectionBlock, ratio: CGFloat) -> some View {
        let inner = scope.with(block)
        let route = inner.route(block.settings.link("link"))
        return VStack(alignment: .leading, spacing: theme.spacing.xs) {
            CategoryImage(image: block.settings.image("image"), ratio: ratio)
            if let heading = inner.text(block.settings, "heading") {
                Text(heading).font(theme.type.label).foregroundStyle(theme.colors.ink).lineLimit(2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let route = route { inner.open(route, block.id) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(route != nil ? .isButton : [])
    }
}
