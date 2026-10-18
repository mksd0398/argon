import ArgonUI
import SwiftUI

// `rich_text`, `image_with_text`, `countdown` and `spacer`.

/// `rich_text`: a heading over the merchant's simple HTML (`HtmlText`), at the start or centred.
@MainActor
struct RichTextSection: View {
    let settings: SectionSettings
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let centered = settings.choice("alignment", ["start", "center"], "start") == "center"
        let heading = scope.text(settings, "heading")
        let html = scope.text(settings, "text")
        if heading != nil || html != nil {
            VStack(alignment: centered ? .center : .leading, spacing: theme.spacing.s) {
                if let heading = heading {
                    Text(heading).font(theme.type.headline).foregroundStyle(theme.colors.ink).accessibilityAddTraits(.isHeader)
                }
                if let html = html { HtmlText(html: html) }
            }
            .multilineTextAlignment(centered ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.horizontal, theme.spacing.l)
        }
    }
}

/// `image_with_text`: the picture and the words side by side, the picture first (`start`) or last (`end`); the words
/// are a heading, simple HTML and a button that follows `link`.
@MainActor
struct ImageWithTextSection: View {
    let settings: SectionSettings
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let imageFirst = settings.choice("image_position", ["start", "end"], "start") == "start"
        let route = scope.route(settings.link("link"))
        HStack(alignment: .center, spacing: theme.spacing.l) {
            if imageFirst { picture }
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                if let heading = scope.text(settings, "heading") {
                    Text(heading).font(theme.type.headline).foregroundStyle(theme.colors.ink).accessibilityAddTraits(.isHeader)
                }
                if let html = scope.text(settings, "text") { HtmlText(html: html) }
                if let route = route, let label = scope.text(settings, "button_label") {
                    ArgonButton(title: label, style: .secondary, size: .s) { scope.open(route, nil) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !imageFirst { picture }
        }
        .padding(.horizontal, theme.spacing.l)
    }

    private var picture: some View {
        CategoryImage(image: settings.image("image"), ratio: 0.8).frame(maxWidth: .infinity)
    }
}

/// The days, hours, minutes and seconds from `now` to `end`; all 0 once it has passed.
func countdownParts(to end: Date, now: Date) -> (days: Int, hours: Int, minutes: Int, seconds: Int) {
    let left = max(Int(end.timeIntervalSince(now).rounded(.up)), 0)
    return (left / 86_400, left % 86_400 / 3_600, left % 3_600 / 60, left % 60)
}

/// `countdown`: a heading and a line of text over the time left to `ends_at`, ticking every second. Once it is over it
/// shows zeros, or nothing with `hide_when_over`. A tap follows `link`.
@MainActor
struct CountdownSection: View {
    let settings: SectionSettings
    let scope: SectionScope
    @Environment(\.argonTheme) private var theme

    var body: some View {
        if let end = settings.datetime("ends_at") {
            let hide = settings.boolean("hide_when_over", true)
            let route = scope.route(settings.link("link"))
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                if !(hide && timeline.date >= end) {
                    clock(countdownParts(to: end, now: timeline.date))
                        .contentShape(Rectangle())
                        .onTapGesture { if let route = route { scope.open(route, nil) } }
                        .accessibilityAddTraits(route != nil ? .isButton : [])
                }
            }
        }
    }

    private func clock(_ left: (days: Int, hours: Int, minutes: Int, seconds: Int)) -> some View {
        VStack(spacing: theme.spacing.s) {
            if let heading = scope.text(settings, "heading") {
                Text(heading).font(theme.type.headline).foregroundStyle(theme.colors.ink)
            }
            if let text = scope.text(settings, "text") {
                Text(text).font(theme.type.body).foregroundStyle(theme.colors.muted)
            }
            HStack(spacing: theme.spacing.s) {
                unit(left.days, "Days")
                unit(left.hours, "Hours")
                unit(left.minutes, "Min")
                unit(left.seconds, "Sec")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(theme.spacing.l)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.l))
        .padding(.horizontal, theme.spacing.l)
        .accessibilityElement(children: .combine)
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        VStack(spacing: theme.spacing.xxs) {
            Text(value < 10 ? "0\(value)" : "\(value)").font(theme.type.title).foregroundStyle(theme.colors.ink).monospacedDigit()
            Text(label).font(theme.type.caption).foregroundStyle(theme.colors.muted)
        }
        .frame(minWidth: 56)
    }
}

/// `spacer`: empty room `height` points tall, with a line across its middle when `divider`.
@MainActor
struct SpacerSection: View {
    let settings: SectionSettings
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let height = settings.number("height", 24, 4...120)
        ZStack {
            if settings.boolean("divider", false) { ArgonDivider().padding(.horizontal, theme.spacing.l) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}
