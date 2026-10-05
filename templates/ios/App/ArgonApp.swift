import SwiftUI

// The target is named App (its module is ArgonStorefront); the qualified protocol keeps "App" unambiguous.
@main
struct ArgonApp: SwiftUI.App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Text("Home").tabItem { Label("Home", systemImage: "house") }
                Text("Shop").tabItem { Label("Shop", systemImage: "list.bullet") }
                Text("Wishlist").tabItem { Label("Wishlist", systemImage: "heart") }
                Text("Cart").tabItem { Label("Cart", systemImage: "cart") }
                Text("Account").tabItem { Label("Account", systemImage: "person") }
            }
        }
    }
}
