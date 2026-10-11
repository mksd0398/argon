import ArgonUI
import SwiftUI

private let exchangeHint = "The store confirms exchanges by email."

/// The returns flow of the order with id `orderId`: its three steps, then the request's outcome. `onBackToOrder` leaves
/// the flow.
@MainActor
struct ReturnFlowView: View {
    let flow: ReturnFlow
    let orderId: String
    let onBackToOrder: () -> Void

    var body: some View {
        if let done = flow.submitted {
            ReturnRequested(done: done, exchange: flow.chosen.contains { flow.choice($0).exchange }, onBackToOrder: onBackToOrder)
        } else if flow.items.isEmpty {
            NothingToReturn(summary: flow.options.nonReturnableSummary, onBackToOrder: onBackToOrder)
        } else {
            // keyed by the step: each one starts at its top, with nothing said yet about what it still needs
            ReturnSteps(flow: flow, orderId: orderId).id(flow.step)
        }
    }
}

/// The step's progress and title, its content, and "Back" / "Continue" (the last step: "Submit request") under it.
@MainActor
private struct ReturnSteps: View {
    let flow: ReturnFlow
    let orderId: String
    // "Continue" was tapped on this step: what stops it is said from then on, and gone as soon as it is put right
    @State private var tapped = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let spacing = theme.spacing
        let last = flow.step == returnSteps.count - 1
        let problem = stepProblem(flow.step, flow.chosen.map { ($0, flow.choice($0)) })
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing.l) {
                    // in the scroll, so it moves away and leaves the room to a note being typed
                    StepHeader(step: flow.step)
                    switch flow.step {
                    case 0: ChooseItems(flow: flow)
                    case 1: ForEach(flow.chosen, id: \.lineItemId) { Resolution(flow: flow, item: $0, showProblem: tapped) }
                    default: ReviewStep(flow: flow)
                    }
                }
                .padding(spacing.l)
            }
            // a note being typed: dragging the page puts the keyboard away
            .scrollDismissesKeyboard(.interactively)
            ArgonDivider()
            VStack(alignment: .leading, spacing: spacing.s) {
                // why the step isn't done, or (the last step) why the request didn't go through
                ErrorText(tapped && problem != nil ? problem : last ? flow.error : nil)
                HStack(spacing: spacing.m) {
                    if flow.step > 0 {
                        ArgonButton(title: "Back", style: .secondary, isEnabled: !flow.submitting, fullWidth: true) { flow.step -= 1 }
                    }
                    ArgonButton(title: last ? "Submit request" : "Continue", isLoading: flow.submitting, fullWidth: true) {
                        tapped = true
                        if problem != nil { return }
                        if last { submit(flow, orderId) } else { flow.step += 1 }
                    }
                }
            }
            .padding(spacing.l)
        }
    }
}

/// How far the flow is (the bar and "Step 2 of 3") and the step's title.
@MainActor
private struct StepHeader: View {
    let step: Int
    @Environment(\.argonTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            ArgonProgressBar(value: Double(step + 1) / Double(returnSteps.count))
            Text(verbatim: "Step \(step + 1) of \(returnSteps.count)").font(theme.type.caption).foregroundStyle(theme.colors.muted)
            Text(returnSteps[step]).font(theme.type.title).foregroundStyle(theme.colors.ink).accessibilityAddTraits(.isHeader)
        }
    }
}

/// Sends the request apart from the screen (leaving it doesn't drop the request); the flow shows how it went.
@MainActor
private func submit(_ flow: ReturnFlow, _ orderId: String) {
    flow.submitting = true
    flow.error = nil
    Task {
        do {
            flow.submitted = try await AppGraph.customerAccount.requestReturn(orderId, lines: returnLines(flow.items, flow.choices))
        } catch {
            flow.error = error.localizedDescription
        }
        flow.submitting = false
    }
}

// MARK: Step 1

/// Each returnable item with its checkbox and, once chosen, how many of it go back; then why the rest can't.
@MainActor
private struct ChooseItems: View {
    let flow: ReturnFlow
    @Environment(\.argonTheme) private var theme

    var body: some View {
        ForEach(flow.items, id: \.lineItemId) { item in
            ChooseItem(item: item, choice: flow.choice(item)) { change in flow.update(item, change) }
        }
        if let summary = trimmedText(flow.options.nonReturnableSummary) {
            Text(summary).font(theme.type.label).foregroundStyle(theme.colors.muted)
        }
    }
}

@MainActor
private struct ChooseItem: View {
    let item: ReturnableItem
    let choice: ReturnChoice
    let onChange: ((inout ReturnChoice) -> Void) -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let checked = choice.quantity > 0
        // ticking an item starts at one of it
        let toggle: (Bool) -> Void = { on in onChange { $0.quantity = on ? 1 : 0 } }
        HStack(alignment: .top, spacing: theme.spacing.s) {
            ArgonCheckbox(isChecked: checked, onChange: toggle)
                // the box alone says nothing: it goes by the item's name
                .accessibilityLabel(Text(verbatim: item.title))
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                ItemRow(
                    image: item.image,
                    title: item.title,
                    details: itemDetails(item.variantTitle, sku: item.sku, quantity: nil),
                    trailing: item.price?.display()
                )
                .contentShape(Rectangle())
                .onTapGesture { toggle(!checked) }
                if checked && item.quantity > 1 {
                    HStack(spacing: theme.spacing.m) {
                        ArgonQuantityStepper(
                            value: choice.quantity,
                            onChange: { quantity in onChange { $0.quantity = quantity } },
                            max: item.quantity,
                            size: .s
                        )
                        Text(verbatim: "of \(item.quantity)").font(theme.type.label).foregroundStyle(theme.colors.muted)
                    }
                }
            }
        }
    }
}

// MARK: Step 2

/// One chosen item: refund or exchange, the reason, the replacement (an exchange), and a note.
@MainActor
private struct Resolution: View {
    let flow: ReturnFlow
    let item: ReturnableItem
    let showProblem: Bool
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let choice = flow.choice(item)
        let reasons = item.reasons
        let note = Binding(get: { flow.choice(item).note }, set: { text in flow.update(item) { $0.note = text } })
        Panel {
            ItemRow(image: item.image, title: item.title, details: itemDetails(item.variantTitle, sku: nil, quantity: choice.quantity))
            ArgonButtonGroup(options: ["Refund", "Exchange"], selectedIndex: choice.exchange ? 1 : 0) { index in
                flow.update(item) { $0.exchange = index == 1 }
            }
            if !reasons.isEmpty {
                ArgonDropdown(
                    label: "Reason",
                    options: reasons.map { $0.name },
                    selectedIndex: reasons.firstIndex { $0.id == choice.reasonId }
                ) { index in flow.update(item) { $0.reasonId = reasons[index].id } }
            }
            if choice.exchange {
                Replacement(flow: flow, item: item)
                Text(exchangeHint).font(theme.type.caption).foregroundStyle(theme.colors.muted)
            }
            ArgonTextArea(label: "Note (optional)", text: note, minLines: 2, maxLength: noteLimit(choice))
            if showProblem { ErrorText(choiceProblem(item, choice)) }
        }
    }
}

/// The product of the item being exchanged, with its options and variants; nil when it can't be had.
/// ponytail: the Product query loads the first 250 variants, so a product with more shows "Unavailable" for the ones that
/// didn't load (as the product page does). Ask `variantBySelectedOptions` for each selection when a store needs more.
@MainActor
private func loadProduct(_ productId: String?) async -> Product? {
    guard let productId = productId else { return nil }
    do {
        // an order line knows its product's id, the product query wants its handle
        guard let handle = try await AppGraph.storefront.productsByIds([productId]).first?.handle else { return nil }
        return try await AppGraph.storefront.product(handle)
    } catch {
        return nil
    }
}

/// What the shopper wants instead: the product's options to pick the replacement variant from. While the product loads, a
/// spinner; when it can't be loaded, a field to say it in words.
@MainActor
private struct Replacement: View {
    let flow: ReturnFlow
    let item: ReturnableItem
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let choice = flow.choice(item)
        Group {
            if let loaded = flow.products[item.lineItemId] {
                if let product = loaded.product {
                    picker(product, choice)
                } else {
                    ArgonInput(
                        label: "What would you like instead?",
                        text: Binding(get: { flow.choice(item).wanted }, set: { text in flow.update(item) { $0.wanted = text } })
                    )
                }
            } else {
                HStack(spacing: theme.spacing.s) {
                    ArgonSpinner(size: .s)
                    Text("Loading options").font(theme.type.label).foregroundStyle(theme.colors.muted)
                }
            }
        }
        .task(id: item.lineItemId) {
            if flow.products[item.lineItemId] != nil { return }
            let product = await loadProduct(item.productId)
            // the shopper went back to a refund, or left the step, while it loaded: the next look loads it again
            if Task.isCancelled { return }
            if let product = product {
                let start = startSelection(product, item.variantId)
                flow.update(item) {
                    $0.selection = start
                    $0.wanted = wantedVariant(product, start)
                }
            }
            flow.products[item.lineItemId] = ExchangeProduct(product: product)
        }
    }

    /// One row of tags per option, starting on the returned variant, then what the selection comes to.
    @ViewBuilder
    private func picker(_ product: Product, _ choice: ReturnChoice) -> some View {
        Text("Exchange for").font(theme.type.label).foregroundStyle(theme.colors.ink)
        ForEach(choosableOptions(product), id: \.name) { option in
            Text(verbatim: "\(option.name): \(choice.selection[option.name] ?? "")")
                .font(theme.type.caption)
                .foregroundStyle(theme.colors.muted)
            WrappingRow(spacing: theme.spacing.s) {
                ForEach(option.optionValues, id: \.name) { value in
                    ArgonTag(text: value.name, isSelected: choice.selection[option.name] == value.name, onClick: {
                        var selection = choice.selection
                        selection[option.name] = value.name
                        flow.update(item) {
                            $0.selection = selection
                            $0.wanted = wantedVariant(product, selection)
                        }
                    })
                }
            }
        }
        // what the selection comes to: the variant by name, or why it can't be had
        if let variant = Variants.match(product.variants, selection: choice.selection) {
            if variant.available {
                Text(choice.wanted).font(theme.type.label).foregroundStyle(theme.colors.ink)
            } else {
                ErrorText("Sold out")
            }
        } else {
            ErrorText("Unavailable")
        }
    }
}

// MARK: Step 3

/// The chosen items with what was asked for each, what the return costs, and how it ships back. (`Review` is a product
/// review.)
@MainActor
private struct ReviewStep: View {
    let flow: ReturnFlow
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let fees = feeRows(flow.options)
        Panel(title: "Items") {
            ForEach(flow.chosen, id: \.lineItemId) { item in
                ItemRow(image: item.image, title: item.title, details: reviewDetails(item, flow.choice(item)))
            }
        }
        if !fees.isEmpty {
            Panel(title: "Fees") {
                ForEach(fees.indices, id: \.self) { InfoRow(label: fees[$0].label, value: fees[$0].amount) }
            }
        }
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            if let note = trimmedText(flow.options.returnShippingMethodNote) {
                Text(note).font(theme.type.body).foregroundStyle(theme.colors.ink)
            }
            if flow.chosen.contains(where: { flow.choice($0).exchange }) {
                Text(exchangeHint).font(theme.type.body).foregroundStyle(theme.colors.muted)
            }
        }
    }
}

// MARK: Outcomes

/// The request went through: the return's name and status, and the way back to the order.
@MainActor
private struct ReturnRequested: View {
    let done: OrderReturn
    let exchange: Bool
    let onBackToOrder: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Outcome(button: "Back to order", onClick: onBackToOrder) {
            ArgonIcon(name: .check, size: 40, tint: theme.colors.success)
            Text("Return requested").font(theme.type.title).foregroundStyle(theme.colors.ink)
            Text([trimmedText(done.name), displayStatus(done.status)].compactMap { $0 }.joined(separator: " · "))
                .font(theme.type.body)
                .foregroundStyle(theme.colors.ink)
            if exchange {
                Text(exchangeHint).font(theme.type.body).foregroundStyle(theme.colors.muted)
            }
        }
    }
}

/// Nothing on the order can go back (any more): the store's reason, when it gives one.
@MainActor
private struct NothingToReturn: View {
    let summary: String?
    let onBackToOrder: () -> Void
    @Environment(\.argonTheme) private var theme

    var body: some View {
        Outcome(button: "Back to order", onClick: onBackToOrder) {
            Text("Nothing on this order can be returned").font(theme.type.headline).foregroundStyle(theme.colors.ink)
            if let summary = trimmedText(summary) {
                Text(summary).font(theme.type.body).foregroundStyle(theme.colors.muted)
            }
        }
    }
}

/// A centred message with one button under it.
@MainActor
private struct Outcome<Content: View>: View {
    private let button: String
    private let onClick: () -> Void
    private let content: Content
    @Environment(\.argonTheme) private var theme

    init(button: String, onClick: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.button = button
        self.onClick = onClick
        self.content = content()
    }

    var body: some View {
        VStack(spacing: theme.spacing.m) {
            content
            ArgonButton(title: button, fullWidth: true, action: onClick)
        }
        .multilineTextAlignment(.center)
        .padding(theme.spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
