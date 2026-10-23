import AVKit
import ArgonUI
import SwiftUI

/// The first-launch welcome, shown once before the tabs (`AppGraph.onboarding`): full-screen pages to swipe through,
/// each a picture (or a muted, looping video) with a heading and a line of text over a bottom shade. The pages are the
/// `onboarding` screen's, read live (up to 3 s, on the welcome's dark background meanwhile: there are no cached settings
/// on a first launch), else `Onboarding.pages` in the settings' words; a screen that turns the welcome off ends it.
/// "Skip" and the last page's button end it; so does "Sign in" on the last page, offered when the store has sign-in set
/// up, which also asks for the Account tab (`onDone`'s `signIn`).
@MainActor
struct OnboardingView: View {
    let onDone: (_ signIn: Bool) -> Void
    @State private var page: Int? = 0
    /// The onboarding screen's welcome, once it has answered (or not, in time).
    @State private var screen: Welcome?? = nil
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Group {
            if let screen, screen != .off {
                pages(own: screen)
            } else {
                theme.colors.paper.ignoresSafeArea()
            }
        }
        // What sits on a photo uses the dark palette in light and dark mode alike: a dark shade, light text, a light
        // button. For the whole screen (and while it loads), so the status bar's content is light too.
        .preferredColorScheme(.dark)
        .task {
            let json = await withTaskGroup(of: String?.self) { group in
                group.addTask { try? await AppGraph.storefront.appScreen("onboarding")?.template }
                group.addTask {
                    try? await Task.sleep(for: .seconds(3))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            let welcome = Onboarding.fromScreen(json, template: AppGraph.homeTemplate)
            screen = .some(welcome)
            if welcome == .off { onDone(false) }
        }
    }

    private func pages(own: Welcome?) -> some View {
        // The shop's own name and words once it answers; the app's name until then, and when it can't be reached.
        let brand = AppGraph.brand.value ?? Brand(name: AppGraph.appName, logo: nil, cover: nil, accent: nil, hosts: [])
        let pages: [OnboardingPage]
        if case let .pages(list) = own {
            pages = list
        } else {
            pages = Onboarding.pages(brand: brand, template: AppGraph.homeTemplate, words: AppGraph.remote?.pages ?? [])
        }
        let canSignIn = AppGraph.canSignIn
        let current = page ?? 0
        let last = current == pages.count - 1
        return GeometryReader { proxy in
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
                ArgonButton(title: pages[current].button ?? (last ? "Get started" : "Next"), fullWidth: true) {
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
            if let video = page.video.flatMap(URL.init(string:)) { WelcomeVideo(url: video) }
        }.overlay {
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                if !page.heading.isEmpty { Text(page.heading).font(theme.type.display).accessibilityAddTraits(.isHeader) }
                if !page.text.isEmpty { Text(page.text).font(theme.type.body).lineLimit(3) }
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

/// A welcome page's video, filling the page over its picture: muted, looping, playing while the page is there.
@MainActor
private struct WelcomeVideo: View {
    let url: URL
    @State private var player: AVQueuePlayer? = nil
    @State private var looper: AVPlayerLooper? = nil

    var body: some View {
        VideoPlayer(player: player)
            .disabled(true)
            .onAppear {
                if let player {
                    player.play()
                    return
                }
                let queue = AVQueuePlayer()
                queue.isMuted = true
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
                queue.play()
            }
            .onDisappear { player?.pause() }
    }
}
