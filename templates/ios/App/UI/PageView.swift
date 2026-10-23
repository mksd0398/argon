import ArgonUI
import SwiftUI

@MainActor
private func loadPage(_ handle: String) async throws -> StorePage {
    guard let page = try await AppGraph.storefront.page(handle) else { throw NotFound(what: "Page") }
    return page
}

/// An online store page (route `page/<handle>`, from a `/pages/<handle>` link): its title in the top bar, its body as
/// the product description is shown. A page with no body opens on the web instead.
@MainActor
struct PageView: View {
    let handle: String
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Loader(load: { try await loadPage(handle) }, skeleton: .text) { page in
            ScrollView {
                HtmlText(html: page.body ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(theme.spacing.l)
            }
            .argonTopBar(title: page.title)
            // a page whose content isn't its body (an Online Store 2.0 page of sections, a contact form) is the web's
            .task {
                if let web = webPage(page, domain: AppGraph.shopDomain) {
                    dismiss()
                    router.open(web)
                }
            }
        }
        .background(theme.colors.paper)
    }
}

/// Where `page` opens instead of the app's page: on the web (the shop's `domain`) when it has no body (an Online Store
/// 2.0 page of sections, a contact form), which the app can't draw; nil when the app draws it.
func webPage(_ page: StorePage, domain: String) -> Route? {
    let body = page.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return body.isEmpty ? .web("https://\(domain)/pages/\(page.handle)") : nil
}

/// A custom page of the store's own (route `screen/<handle>`, from an `app://screens/<handle>` link): the `app_screen`
/// with that handle, its title in the top bar and its sections. One the store doesn't have shows "Nothing to show yet."
/// Its template's `screen` sets its background, and with `top_bar` transparent lays the bar over the first section as
/// the home does (`SectionsUnderBar`): the title and the back button clear over it, in `top_bar_tint`.
@MainActor
struct CustomScreenView: View {
    let handle: String
    @State private var screen: LoadedScreen? = nil
    @State private var loaded = false
    // how solid the bar over the first section is: solid until that section is under it
    @State private var barSolid = 1.0
    @Environment(\.argonTheme) private var theme
    @Environment(\.isPresented) private var pushed
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let look = screen?.template.screen ?? ScreenLook()
        let underBar = look.transparent() && (screen?.template.opensWithPicture ?? false)
        // The system's back button takes the stack's tint, not the clear bar's colours: the bar draws its own.
        // ponytail: hiding the system button also drops the swipe back on these pages; bring it back with a
        // UIGestureRecognizerDelegate on the navigation controller if shoppers miss it.
        let back = underBar && pushed ? [ArgonTopBarAction(icon: .back, accessibilityLabel: "Back") { dismiss() }] : []
        Group {
            if let screen = screen, !screen.template.content.isEmpty {
                if underBar {
                    SectionsUnderBar(screen: screen, solid: $barSolid)
                } else {
                    ScrollView {
                        SectionList(sections: screen.template.content, screen: screen, context: screen.context())
                            .padding(.vertical, theme.spacing.l)
                    }
                }
            } else if loaded {
                EmptyNote()
            } else {
                ScreenSkeleton(.home)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.resolve(look.background) ?? theme.colors.paper)
        .argonTopBar(
            variant: underBar ? .overlay : .standard, title: screen?.title ?? "", leading: back,
            solid: barSolid, darkOverPicture: look.tint == "dark"
        )
        .navigationBarBackButtonHidden(!back.isEmpty)
        .task {
            if loaded { return }
            let found = await loadScreen(handle)
            if Task.isCancelled { return }
            screen = found
            loaded = true
        }
    }
}
