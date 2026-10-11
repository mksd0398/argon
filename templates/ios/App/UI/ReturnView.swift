import ArgonUI
import SwiftUI

/// The return and exchange flow of the order with id `orderId` (route `return/<orderId>`).
/// Placeholder: the orders pages replace this body.
@MainActor
struct ReturnView: View {
    let orderId: String

    var body: some View {
        Text("Return or exchange").argonTopBar(title: "Return or exchange")
    }
}
