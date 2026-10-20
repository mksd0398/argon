import ArgonUI
import ShopifyCheckoutSheetKit
import SwiftUI
import UserNotifications

// The target is named App (its module is ArgonStorefront); the qualified protocol keeps "App" unambiguous.
// This file imports Checkout Kit, whose public `Image` would clash with SwiftUI's: no unqualified `Image` here.
@main
struct ArgonApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(Launch.self) private var launch

    init() {
        // .web = the store's own checkout branding (Checkout Kit's default is a generic light/dark theme)
        ShopifyCheckoutSheetKit.configure {
            $0.colorScheme = .web
            $0.preloading.enabled = true
        }
        // the merchant's bar colours, before the first bar is drawn
        applyBarColors(AppGraph.navigation)
        // the merchant's fonts whose files are all on disk, before the first screen builds the theme
        let fonts = AppGraph.remote?.fonts
        ArgonFonts.use(heading: fonts?.heading.flatMap(AppGraph.fontStore.register), body: fonts?.body.flatMap(AppGraph.fontStore.register))
    }

    var body: some Scene {
        // light or dark: the merchant's choice (`appearance.mode`), else the device's
        WindowGroup { AppRoot().preferredColorScheme(AppGraph.appearance.colorScheme) }
    }
}

/// Builds `AppGraph.analytics` as the app finishes launching: that is when the providers' SDKs (Firebase, Meta, MoEngage)
/// ask to be started, which its sinks do. `ArgonApp.init` is too early for them: there is no `UIApplication` yet. Then
/// fetches the merchant's settings for the next launch, in the background. With push, it takes the notifications (taps and
/// banners) and, for a shopper who turned them on, registers again for the APNs token Firebase needs.
private final class Launch: NSObject, UIApplicationDelegate {
    // kept: the notification centre holds its delegate weakly
    private let presenter = PushPresenter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = AppGraph.analytics
        AppGraph.refreshSettings()
        if let push = AppGraph.push {
            UNUserNotificationCenter.current().delegate = presenter
            if push.optedIn { application.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pushRegistered(deviceToken)
    }
}

/// The tabs in the shop's colour, after the welcome on a first launch; or the setup screen when the app can't reach the
/// store.
@MainActor
struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // the app can't reach a real store without its Storefront token (mock.shop needs none)
        if AppGraph.storefrontToken.trimmingCharacters(in: .whitespaces).isEmpty && AppGraph.shopDomain != "mock.shop" {
            SetupView()
        } else if AppGraph.onboarding && !AppGraph.onboardingStore.done {
            OnboardingView { signIn in
                // the tabs open on Home, or on Account for the welcome's "Sign in"
                AppGraph.tabs.selected = signIn ? .account : .home
                AppGraph.onboardingStore.finish()
            }
            // Argon's own accent, not the shop's: over a photo the button is the light one
            .argonTheme(accentHex: nil)
        } else {
            Tabs()
                // A preloaded checkout shows the cart and the buyer as they were: a cart change (a product added, a stepper
                // tap), a sign-in or a sign-out makes it stale.
                .onChange(of: AppGraph.cart.cart) { ShopifyCheckoutSheetKit.invalidate() }
                .onChange(of: AppGraph.auth.signedIn) { ShopifyCheckoutSheetKit.invalidate() }
                // The B2B buyer follows the session: looked up at start (when there is a session), after sign-in and each
                // time the token changes (the Storefront API and the cart hold the token itself), dropped on sign-out.
                // The sample account shows its company the same way.
                .onChange(of: buyerSession, initial: true) { refreshBuyer() }
                // back in the foreground the token may have run out meanwhile: the refresh asks for a valid one
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { refreshBuyer() }
                }
                // Argon components read the theme (the screens that still draw native controls are tinted in `Tabs`)
                .argonTheme(accentHex: AppGraph.brand.value?.accent)
        }
    }

    /// Changes whenever the buyer may have: signed in or out, a new token, the sample account on or off.
    private var buyerSession: [Int] {
        [AppGraph.auth.signedIn ? 1 : 0, AppGraph.auth.tokenChanges, AppGraph.sampleAccount ? 1 : 0]
    }

    private func refreshBuyer() {
        // not tied to a view: a refresh under way must finish, or the buyer would be left half applied
        Task { await AppGraph.buyer.refresh() }
    }
}
