import Foundation

// The returns flow's rules, kept free of UI so they can be tested (and read side by side with Android).

/// The most Shopify takes as a return line's note (`customerNote`).
/// ponytail: counted in characters, as the note field counts them; Android counts UTF-16 units, so a note full of emoji
/// can run longer here. Count `utf16` if Shopify turns such a note down.
let noteLimit = 300

/// The flow's three steps.
let returnSteps = ["Choose items", "Refund or exchange", "Review"]

/// What the shopper chose for one returnable item. `quantity`: how many go back (0: the item isn't chosen); `exchange`:
/// a replacement instead of a refund; `reasonId`: the return reason picked; `note`: their own words; `wanted`: what they
/// want instead (an exchange), as the store will read it: the variant picked (`exchangeItem`) or, when the product's
/// options couldn't be loaded, what they typed; `selection`: the options picked in the replacement picker.
struct ReturnChoice: Equatable {
    var quantity = 0
    var exchange = false
    var reasonId: String? = nil
    var note = ""
    var wanted = ""
    var selection: [String: String] = [:]
}

extension ReturnableItem {
    /// This item with `quantity` of it returnable.
    func with(quantity: Int) -> ReturnableItem {
        ReturnableItem(
            lineItemId: lineItemId, title: title, image: image, quantity: quantity, reasons: reasons,
            variantTitle: variantTitle, sku: sku, productId: productId, variantId: variantId, price: price
        )
    }
}

/// A replacement as the store reads it: "Men's Crewneck - Large / Olive (SKU MC-LO)". The SKU part is left out when there
/// is none, and the variant part for a product without options (Shopify's "Default Title").
func exchangeItem(productTitle: String, variantTitle: String?, sku: String?) -> String {
    let variant = variantLabel(variantTitle).map { " - \($0)" } ?? ""
    let code = trimmedText(sku).map { " (SKU \($0))" } ?? ""
    return productTitle.trimmingCharacters(in: .whitespacesAndNewlines) + variant + code
}

/// The note of a return line that is an exchange: "Exchange for: <wanted>", then on a new line the shopper's `note` when
/// they wrote one. The Customer Account API has no exchange input: the store reads the wanted item here and completes the
/// exchange in its admin.
func exchangeNote(wanted: String, note: String) -> String {
    ["Exchange for: \(wanted.trimmingCharacters(in: .whitespacesAndNewlines))", trimmedText(note)].compactMap { $0 }.joined(separator: "\n")
}

/// `exchangeNote` for a picked variant: "Exchange for: <product title> - <variant title> (SKU <sku>)", then the note.
func exchangeNote(productTitle: String, variantTitle: String?, sku: String?, note: String) -> String {
    exchangeNote(wanted: exchangeItem(productTitle: productTitle, variantTitle: variantTitle, sku: sku), note: note)
}

/// How long the shopper's own note may be: an exchange's note starts with what they want instead, which counts too.
func noteLimit(_ choice: ReturnChoice) -> Int {
    choice.exchange ? max(noteLimit - exchangeNote(wanted: choice.wanted, note: "").count - 1, 0) : noteLimit
}

/// The lines of the return request: one per chosen item of `items` (`choices` by line item id, quantity above 0), with at
/// most the quantity that can go back, the reason, and the note (an exchange's says what is wanted, `exchangeNote`) cut to
/// what Shopify takes.
func returnLines(_ items: [ReturnableItem], _ choices: [String: ReturnChoice]) -> [ReturnLineInput] {
    items.compactMap { item in
        guard let choice = choices[item.lineItemId], choice.quantity > 0, item.quantity > 0 else { return nil }
        let note = choice.exchange ? exchangeNote(wanted: choice.wanted, note: choice.note) : choice.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(note.prefix(noteLimit))
        return ReturnLineInput(
            lineItemId: item.lineItemId,
            quantity: min(choice.quantity, item.quantity),
            returnReasonDefinitionId: choice.reasonId,
            customerNote: cut.isEmpty ? nil : cut
        )
    }
}

/// What a chosen item still needs before the review, in the shopper's words; nil when it is complete.
func choiceProblem(_ item: ReturnableItem, _ choice: ReturnChoice) -> String? {
    if !item.reasons.isEmpty && choice.reasonId == nil { return "Choose a reason" }
    if choice.exchange && trimmedText(choice.wanted) == nil { return "Choose what you'd like instead" }
    return nil
}

/// What stops the flow from leaving `step` (an index into `returnSteps`) with these `chosen` items and their choices:
/// nothing chosen (step 1), the first chosen item that is incomplete (step 2); nil when it can go on.
func stepProblem(_ step: Int, _ chosen: [(ReturnableItem, ReturnChoice)]) -> String? {
    switch step {
    case 0: return chosen.isEmpty ? "Choose at least one item" : nil
    case 1: return chosen.lazy.compactMap { choiceProblem($0.0, $0.1) }.first
    default: return nil
    }
}

/// The items of an order that can go back, each order line once: Shopify may list a line more than once (it shipped in
/// parts), and the flow keeps one choice per line. Lines with nothing left to return are left out.
func returnableItems(_ options: OrderReturnOptions) -> [ReturnableItem] {
    var merged: [ReturnableItem] = []
    for item in options.returnableItems {
        if let same = merged.firstIndex(where: { $0.lineItemId == item.lineItemId }) {
            merged[same] = merged[same].with(quantity: merged[same].quantity + item.quantity)
        } else {
            merged.append(item)
        }
    }
    return merged.filter { $0.quantity > 0 }
}

/// The lines under a chosen item in the review: its variant, "Qty N", "Refund" or "Exchange for: ...", the reason, and
/// the shopper's note.
func reviewDetails(_ item: ReturnableItem, _ choice: ReturnChoice) -> [String] {
    [
        variantLabel(item.variantTitle),
        "Qty \(min(choice.quantity, item.quantity))",
        choice.exchange ? exchangeNote(wanted: choice.wanted, note: "") : "Refund",
        item.reasons.first { $0.id == choice.reasonId }?.name,
        trimmedText(choice.note),
    ].compactMap { $0 }
}

/// A fee's name: the store's title for it, else by its kind.
func feeLabel(_ fee: ReturnFee) -> String {
    if let title = trimmedText(fee.title) { return title }
    switch fee.kind {
    case "ReturnShippingFee": return "Return shipping"
    case "RestockingFee": return "Restocking fee"
    default: return "Fee"
    }
}

/// What a return costs, as label and amount: each fee the store lists, and "Applies" for a fee it says there is without
/// listing an amount. `money` formats an amount.
func feeRows(_ options: OrderReturnOptions, money: (Money) -> String = { $0.display() }) -> [(label: String, amount: String)] {
    var rows = options.fees.map { (label: feeLabel($0), amount: $0.amount.map(money) ?? "Applies") }
    let kinds = options.fees.map { $0.kind }
    if options.hasReturnShippingFee && !kinds.contains("ReturnShippingFee") { rows.append((label: "Return shipping", amount: "Applies")) }
    if options.hasRestockingFee && !kinds.contains("RestockingFee") { rows.append((label: "Restocking fee", amount: "Applies")) }
    return rows
}

/// The options a shopper chooses between: all but Shopify's lone "Title: Default Title" of a product without options.
func choosableOptions(_ product: Product) -> [ProductOption] {
    product.options.filter { option in
        !(option.name == "Title" && option.optionValues.map { $0.name } == ["Default Title"])
    }
}

/// Where the replacement picker starts: the options of the variant being returned (the shopper then changes the size),
/// else of the first available variant, else of the first.
func startSelection(_ product: Product, _ variantId: String?) -> [String: String] {
    let variants = product.variants
    return (variants.first { $0.id == variantId } ?? variants.first { $0.available } ?? variants.first)?.options ?? [:]
}

/// What `selection` asks for, as the exchange note names it (`exchangeItem`); empty when no variant has those options or it is sold out.
func wantedVariant(_ product: Product, _ selection: [String: String]) -> String {
    guard let variant = Variants.match(product.variants, selection: selection), variant.available else { return "" }
    return exchangeItem(productTitle: product.title, variantTitle: variant.title, sku: variant.sku)
}
