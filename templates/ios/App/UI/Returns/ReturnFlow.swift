import Foundation
import Observation

/// The product of an item being exchanged, for its options; nil `product`: it couldn't be loaded (the shopper types what they want).
struct ExchangeProduct {
    let product: Product?
}

/// The returns flow of one order: the step it is on, what the shopper chose, and how the request went. Kept with the
/// screen (it is what the screen's Loader loads), so a look at another tab or another app doesn't lose the choices.
@MainActor
@Observable
final class ReturnFlow {
    let options: OrderReturnOptions

    /// The items that can go back.
    let items: [ReturnableItem]

    /// 0, 1, 2: an index into `returnSteps`.
    var step = 0

    /// By line item id.
    private(set) var choices: [String: ReturnChoice] = [:]

    /// The products loaded for the replacement picker, by line item id; none yet: still loading.
    var products: [String: ExchangeProduct] = [:]

    var submitting = false

    /// Why the request was refused (Shopify's user errors) or couldn't be sent.
    var error: String? = nil

    /// The return Shopify created: the flow is done.
    var submitted: OrderReturn? = nil

    init(options: OrderReturnOptions) {
        self.options = options
        items = returnableItems(options)
    }

    func choice(_ item: ReturnableItem) -> ReturnChoice {
        choices[item.lineItemId] ?? ReturnChoice()
    }

    func update(_ item: ReturnableItem, _ change: (inout ReturnChoice) -> Void) {
        var changed = choice(item)
        change(&changed)
        choices[item.lineItemId] = changed
    }

    /// The items chosen to go back, in the order's order.
    var chosen: [ReturnableItem] { items.filter { choice($0).quantity > 0 } }
}
