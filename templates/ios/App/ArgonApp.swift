import ShopifyCheckoutSheetKit
import SwiftUI

// The target is named App (its module is ArgonStorefront); the qualified protocol keeps "App" unambiguous.
// This file imports Checkout Kit, whose public `Image` would clash with SwiftUI's: no unqualified `Image` here.
@main
struct ArgonApp: SwiftUI.App {
    init() {
        // .web = the store's own checkout branding (Checkout Kit's default is a generic light/dark theme)
        ShopifyCheckoutSheetKit.configure {
            $0.colorScheme = .web
            $0.preloading.enabled = true
        }
    }

    var body: some Scene {
        WindowGroup { AppRoot() }
    }
}

/// The tabs in the shop's colour, or the setup screen when the app can't reach the store.
@MainActor
struct AppRoot: View {
    var body: some View {
        // the app can't reach a real store without its Storefront token (mock.shop needs none)
        if AppGraph.storefrontToken.trimmingCharacters(in: .whitespaces).isEmpty && AppGraph.shopDomain != "mock.shop" {
            SetupView()
        } else {
            Tabs()
                .tint(brandColor(AppGraph.brand.value?.accent) ?? .accentColor)
                // A preloaded checkout shows the cart and the buyer as they were: a cart change (a product added, a stepper
                // tap), a sign-in or a sign-out makes it stale.
                .onChange(of: AppGraph.cart.cart) { ShopifyCheckoutSheetKit.invalidate() }
                .onChange(of: AppGraph.auth.signedIn) { ShopifyCheckoutSheetKit.invalidate() }
        }
    }
}
