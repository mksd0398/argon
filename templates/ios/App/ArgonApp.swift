import ShopifyCheckoutSheetKit
import SwiftUI

// The target is named App (its module is ArgonStorefront); the qualified protocol keeps "App" unambiguous.
// This file imports Checkout Kit, whose public `Image` would clash with SwiftUI's: no unqualified `Image` here.
@main
struct ArgonApp: SwiftUI.App {
    init() {
        ShopifyCheckoutSheetKit.configure { $0.preloading.enabled = true }
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
                // A preloaded checkout shows the cart as it was: any change to the cart makes it stale.
                .onChange(of: AppGraph.cart.cart) { ShopifyCheckoutSheetKit.invalidate() }
        }
    }
}
