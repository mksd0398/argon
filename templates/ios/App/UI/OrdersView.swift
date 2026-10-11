import ArgonUI
import SwiftUI

/// The customer's orders (route `orders`).
/// Placeholder: the orders pages replace this body.
@MainActor
struct OrdersView: View {
    var body: some View {
        Text("Orders").argonTopBar(title: "Orders")
    }
}
