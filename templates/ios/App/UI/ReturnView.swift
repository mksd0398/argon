import ArgonUI
import SwiftUI

@MainActor
private func loadFlow(_ orderId: String) async throws -> ReturnFlow {
    guard let options = try await AppGraph.customerAccount.returnOptions(orderId) else { throw NotFound(what: "Order") }
    return ReturnFlow(options: options)
}

/// Returning or exchanging items of the order with id `orderId` (route `return/<orderId>`): choose the items, say what to
/// do with each, review, and send the request. The steps are in `Returns/`.
@MainActor
struct ReturnView: View {
    let orderId: String
    // the loaded flow, for the top bar's back arrow: a step back while there is one, else out of the screen
    @State private var flow: ReturnFlow? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.argonTheme) private var theme

    var body: some View {
        // kept for the screen (the Loader's way): the flow holds the shopper's choices
        Loader(load: { try await loadFlow(orderId) }) { loaded in
            ReturnFlowView(flow: loaded, orderId: orderId, onBackToOrder: { dismiss() })
                .onAppear { flow = loaded }
        }
        .background(theme.colors.paper)
        // the bar's own back button always leaves the screen: this one goes a step back first
        .navigationBarBackButtonHidden(true)
        .argonTopBar(title: "Return or exchange", leading: [ArgonTopBarAction(icon: .back, accessibilityLabel: "Back") { back() }])
    }

    private func back() {
        if let current = flow, current.step > 0, current.submitted == nil, !current.submitting {
            current.step -= 1
        } else {
            dismiss()
        }
    }
}
