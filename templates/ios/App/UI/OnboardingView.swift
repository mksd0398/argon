import ArgonUI
import SwiftUI

/// The first-launch welcome, shown once before the tabs (`AppGraph.onboarding`): three full-screen pages
/// (`Onboarding.pages`) to swipe through, each a picture with a heading and a line of text over a bottom shade. "Skip"
/// (pages 1 and 2) and "Get started" (page 3) end it; so does "Sign in" on page 3, offered when the store has sign-in
/// set up, which also asks for the Account tab (`onDone`'s `signIn`).
@MainActor
struct OnboardingView: View {
    let onDone: (_ signIn: Bool) -> Void
    @State private var page: Int? = 0
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // The shop's own name and words once it answers; the app's name until then, and when it can't be reached.
        let brand = AppGraph.brand.value ?? Brand(name: AppGraph.appName, logo: nil, cover: nil, accent: nil, hosts: [])
        let pages = Onboarding.pages(brand: brand, template: AppGraph.homeTemplate, words: AppGraph.remote?.pages ?? [])
        let canSignIn = AppGraph.canSignIn
        let current = page ?? 0
        let last = current == pages.count - 1
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            // a page is the whole screen, status bar and home indicator included
            let screen = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages.indices, id: \.self) { index in
                        // the words end where this page's controls begin
                        slide(pages[index], bottom: insets.bottom + controlsHeight(buttons: index == pages.count - 1 && canSignIn ? 2 : 1))
                            .frame(width: screen.width, height: screen.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            if !last {
                ArgonButton(title: "Skip", style: .tertiary, size: .s) { onDone(false) }.padding(.horizontal, theme.spacing.s)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: theme.spacing.m) {
                HStack(spacing: theme.spacing.xs) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(theme.colors.ink.opacity(index == current ? 1 : 0.4))
                            .frame(width: index == current ? 8 : 6, height: index == current ? 8 : 6)
                    }
                }
                .frame(height: 8)
                .accessibilityElement()
                .accessibilityLabel("Page \(current + 1) of \(pages.count)")
                ArgonButton(title: last ? "Get started" : "Next", fullWidth: true) {
                    if last {
                        onDone(false)
                    } else {
                        withAnimation { page = current + 1 }
                    }
                }
                if last && canSignIn {
                    ArgonButton(title: "Sign in", style: .secondary, fullWidth: true) { onDone(true) }
                }
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, theme.spacing.l)
            // "Sign in" joining on the last page moves the dots and the button up instead of jumping them
            .animation(.default, value: last)
        }
        .background(theme.colors.paper)
        // What sits on a photo uses the dark palette in light and dark mode alike: a dark shade, light text, a light
        // button. For the whole screen, so the status bar's content is light too.
        .preferredColorScheme(.dark)
        // the pages keep the app's name when the shop can't be reached
        .task { _ = try? await AppGraph.loadBrand() }
    }

    /// How much of a page's bottom the controls over it take: the page dots and `buttons` buttons, with their margins.
    private func controlsHeight(buttons: Int) -> CGFloat {
        theme.spacing.l + (48 + theme.spacing.m) * CGFloat(buttons) + 8 + theme.spacing.l
    }

    /// A page: its picture, with its heading and text at the bottom, `bottom` up from the edge, over the shade.
    private func slide(_ page: OnboardingPage, bottom: CGFloat) -> some View {
        let paper = theme.colors.paper
        // dark behind the status bar and "Skip", clear over the picture, then dark again where the words are
        let shade = LinearGradient(
            stops: [
                .init(color: paper.opacity(0.65), location: 0),
                .init(color: paper.opacity(0), location: 0.25),
                .init(color: paper.opacity(0), location: 0.45),
                .init(color: paper.opacity(0.92), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        return StoreImage(url: page.image).overlay {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                Text(page.heading).font(theme.type.display).accessibilityAddTraits(.isHeader)
                Text(page.text).font(theme.type.body).lineLimit(3)
            }
            .foregroundStyle(theme.colors.ink)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background(shade)
        }
    }
}
