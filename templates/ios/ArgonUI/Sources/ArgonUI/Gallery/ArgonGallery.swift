import SwiftUI

/// Every Argon component in each of its states, with a light/dark switch: the screen to review the library on a phone.
/// Push it inside a `NavigationStack` (the app shows it from Account in debug builds).
@MainActor
public struct ArgonGallery: View {
    @Environment(\.colorScheme) private var systemScheme
    @State private var scheme: ColorScheme? = nil

    public init() {}

    public var body: some View {
        let current = scheme ?? systemScheme
        GalleryContent()
            .environment(\.colorScheme, current)
            .navigationTitle("Components")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { scheme = current == .dark ? ColorScheme.light : .dark } label: {
                        Image(systemName: current == .dark ? "sun.max" : "moon")
                    }
                    .accessibilityLabel(current == .dark ? Text("Light mode") : Text("Dark mode"))
                }
            }
    }
}

// mock.shop's demo product photo
private let sampleImage = URL(string: "https://cdn.shopify.com/mock-shop-production-media/_seeds/demostore/dfe6fa49317d241f5dc7295e8eff79027fd51b512d04f2441aa4b7060f7e35f7.jpg")

@MainActor
private struct GalleryContent: View {
    @Environment(\.argonTheme) private var theme
    @State private var accordionOpen = true
    @State private var careOpen = false
    @State private var segment = 1
    @State private var fixedTab = 0
    @State private var scrollTab = 0
    @State private var email = ""
    @State private var name = "Ada Lovelace"
    @State private var password = "secret"
    @State private var note = ""
    @State private var code = ""
    @State private var completedCode: String? = nil
    @State private var checked = true
    @State private var radio = 0
    @State private var switchOn = true
    @State private var priceLow = 20.0
    @State private var priceHigh = 120.0
    @State private var size: Int? = nil
    @State private var date = Date()
    @State private var rangeStart = Date()
    @State private var rangeEnd = Date().addingTimeInterval(7 * 86_400)
    @State private var inStock = true
    @State private var tags = ["Silk", "Cotton", "Linen"]
    @State private var listSwitch = true
    @State private var listCheck = false
    @State private var modal = false
    @State private var fullScreen = false
    @State private var sheet = false
    @State private var bottomBar = false
    @State private var menuOpen = false

    init() {}

    var body: some View {
        ScrollView {
            // Lazy: a group is built (and its animations run) only while it is on screen
            LazyVStack(alignment: .leading, spacing: theme.spacing.xxl) {
                Group { tokens; icons; buttons; choices; fields }
                Group { selection; pickers; tagSection; badges; containers }
                Group { progress; list; navigation }
            }
            .padding(theme.spacing.l)
        }
        .background { theme.colors.paper.ignoresSafeArea() }
        .tint(theme.colors.accent)
        .argonModal(
            isPresented: $modal,
            title: "Remove this item?",
            message: "It will leave your bag.",
            primaryAction: ArgonModalAction("Remove", isDestructive: true),
            secondaryAction: ArgonModalAction("Cancel")
        )
        .argonFullScreenModal(isPresented: $fullScreen, title: "Size guide") {
            ScrollView {
                Text("Measure around the fullest part of the chest, keeping the tape level.")
                    .font(theme.type.body)
                    .foregroundStyle(theme.colors.ink)
                    .padding(theme.spacing.l)
            }
            .background { theme.colors.paper.ignoresSafeArea() }
        }
        .argonBottomSheet(isPresented: $sheet) {
            VStack(alignment: .leading, spacing: theme.spacing.m) {
                Text("Sort by").font(theme.type.title).foregroundStyle(theme.colors.ink)
                ArgonRadioGroup(options: ["Featured", "Price, low to high", "Newest"], selectedIndex: radio) { radio = $0 }
            }
            .padding(theme.spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { theme.colors.surface.ignoresSafeArea() }
        }
        .overlay {
            ArgonSideMenu(isOpen: menuOpen, onDismiss: { menuOpen = false }) {
                Text("Maison").font(theme.type.title).foregroundStyle(theme.colors.ink).padding(theme.spacing.l)
            } footer: {
                Text("Signed in as Ada").font(theme.type.caption).foregroundStyle(theme.colors.muted).padding(theme.spacing.l)
            } content: {
                ArgonSideMenuItem(title: "Home", icon: .home, isSelected: true) { menuOpen = false }
                ArgonSideMenuItem(title: "Women", hasChildren: true) {}
                ArgonSideMenuItem(title: "Men", hasChildren: true) {}
                ArgonSideMenuItem(title: "Wishlist", icon: .heart, badge: 3) {}
                ArgonSideMenuItem(title: "Gift cards", icon: .gift) {}
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(theme.type.caption).foregroundStyle(theme.colors.muted)
    }

    // MARK: Sections

    private var tokens: some View {
        let swatches: [(String, Color)] = [
            ("ink", theme.colors.ink), ("muted", theme.colors.muted), ("paper", theme.colors.paper),
            ("surface", theme.colors.surface), ("border", theme.colors.border), ("accent", theme.colors.accent),
            ("onAccent", theme.colors.onAccent), ("sale", theme.colors.sale), ("success", theme.colors.success),
        ]
        return GallerySection("Theme") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), alignment: .top)], spacing: theme.spacing.m) {
                ForEach(swatches.indices, id: \.self) { index in
                    VStack(spacing: theme.spacing.xs) {
                        RoundedRectangle(cornerRadius: theme.radius.m)
                            .fill(swatches[index].1)
                            .overlay { RoundedRectangle(cornerRadius: theme.radius.m).strokeBorder(theme.colors.border) }
                            .frame(height: 44)
                        caption(swatches[index].0)
                    }
                }
            }
            VStack(alignment: .leading, spacing: theme.spacing.s) {
                Text("Display").font(theme.type.display)
                Text("Title").font(theme.type.title)
                Text("Headline").font(theme.type.headline)
                Text("Body text for descriptions and paragraphs.").font(theme.type.body)
                Text("Label").font(theme.type.label)
                Text("Caption").font(theme.type.caption)
            }
            .foregroundStyle(theme.colors.ink)
        }
    }

    private var icons: some View {
        GallerySection("Icon") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), alignment: .top)], spacing: theme.spacing.m) {
                ForEach(ArgonIconName.allCases, id: \.self) { name in
                    VStack(spacing: theme.spacing.xs) {
                        ArgonIcon(name: name, size: 22, tint: theme.colors.ink)
                        caption(name.rawValue)
                    }
                }
            }
        }
    }

    private var buttons: some View {
        GallerySection("Button") {
            ForEach([ArgonButtonStyle.primary, .secondary, .tertiary, .destructive], id: \.self) { style in
                HStack(spacing: theme.spacing.s) {
                    ArgonButton(title: "\(style)".capitalized, style: style, size: .s) {}
                    ArgonButton(title: "Disabled", style: style, size: .s, isEnabled: false) {}
                    ArgonButton(title: "Loading", style: style, size: .s, isLoading: true) {}
                }
            }
            HStack(spacing: theme.spacing.s) {
                ArgonButton(title: "Small", size: .s) {}
                ArgonButton(title: "Medium") {}
                ArgonButton(title: "Large", size: .l) {}
            }
            ArgonButton(title: "Add to bag", icon: .bag, fullWidth: true) {}
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxl) {
            GallerySection("ButtonGroup") {
                ArgonButtonGroup(options: ["XS", "S", "M", "L"], selectedIndex: segment) { segment = $0 }
            }
            GallerySection("Tabs") {
                caption("Fixed")
                ArgonTabs(titles: ["Details", "Care", "Shipping"], selectedIndex: fixedTab, onSelect: { fixedTab = $0 })
                caption("Scrollable")
                ArgonTabs(
                    titles: ["New in", "Sarees", "Kurtas", "Dupattas", "Jewellery", "Gifts", "Sale"],
                    selectedIndex: scrollTab,
                    onSelect: { scrollTab = $0 },
                    isScrollable: true
                )
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxl) {
            GallerySection("Input") {
                ArgonInput(
                    label: "Email", text: $email, placeholder: "you@example.com", helper: "For your receipt",
                    keyboard: .email, leadingIcon: .mail
                )
                ArgonInput(label: "Name", text: $name)
                ArgonInput(label: "Password", text: $password, error: "At least 8 characters", isSecure: true, trailingIcon: .eyeOff)
            }
            GallerySection("TextArea") {
                ArgonTextArea(label: "Gift note", text: $note, placeholder: "Write a message", maxLength: 120, helper: "Printed on the card")
                ArgonTextArea(label: "Review", text: .constant("Too short"), minLines: 2, error: "Tell us a little more")
            }
            GallerySection("InputOTP") {
                ArgonInputOTP(code: $code) { completedCode = $0 }
                caption(completedCode.map { "Completed: \($0)" } ?? "Type, paste or autofill 6 digits")
            }
        }
    }

    private var selection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxl) {
            GallerySection("Checkbox") {
                ArgonCheckbox(isChecked: checked, label: "Gift wrap") { checked = $0 }
                ArgonCheckbox(isChecked: !checked, label: "Leave at the door") { checked = !$0 }
                ArgonCheckbox(isChecked: true, label: "Disabled", isEnabled: false) { _ in }
            }
            GallerySection("RadioButton") {
                ArgonRadioGroup(options: ["Standard", "Express", "Pick up in store"], selectedIndex: radio) { radio = $0 }
            }
            GallerySection("Switch") {
                ArgonSwitch(isOn: switchOn, label: "Order updates") { switchOn = $0 }
                ArgonSwitch(isOn: !switchOn, label: "Newsletter") { switchOn = !$0 }
            }
            GallerySection("RangeSlider") {
                ArgonRangeSlider(lower: priceLow, upper: priceHigh, bounds: 0...200, step: 5) { lower, upper in
                    priceLow = lower
                    priceHigh = upper
                }
                caption("\(Int(priceLow)) – \(Int(priceHigh))")
            }
        }
    }

    private var pickers: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxl) {
            GallerySection("Dropdown") {
                ArgonDropdown(label: "Size", options: ["XS", "S", "M", "L", "XL"], selectedIndex: size) { size = $0 }
                ArgonDropdown(label: "Colour", options: ["Ivory", "Rust"], selectedIndex: 1) { _ in }
            }
            GallerySection("DatePicker") {
                ArgonDatePicker(label: "Delivery", selection: $date, minDate: Date())
                ArgonDateRangePicker(start: $rangeStart, end: $rangeEnd, minDate: Date())
            }
        }
    }

    private var tagSection: some View {
        GallerySection("Tag") {
            HStack(spacing: theme.spacing.s) {
                ArgonTag(text: "In stock", isSelected: inStock, onClick: { inStock.toggle() })
                ArgonTag(text: "On sale", isSelected: !inStock, onClick: { inStock.toggle() })
            }
            HStack(spacing: theme.spacing.s) {
                ForEach(tags, id: \.self) { tag in
                    ArgonTag(text: tag, style: .input, onRemove: { tags.removeAll { $0 == tag } })
                }
                if tags.isEmpty {
                    ArgonButton(title: "Reset", style: .tertiary, size: .s) { tags = ["Silk", "Cotton", "Linen"] }
                }
            }
            ArgonTag(text: "Free shipping", style: .info)
        }
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxl) {
            GallerySection("Badge") {
                HStack(spacing: theme.spacing.xl) {
                    ArgonBadge()
                    ArgonBadge(count: 3)
                    ArgonBadge(count: 120)
                    ArgonBadgedBox(count: 2) { ArgonIcon(name: .bag, size: 24, tint: theme.colors.ink) }
                    ArgonBadgedBox(count: nil) { ArgonIcon(name: .heart, size: 24, tint: theme.colors.ink) }
                }
            }
            GallerySection("Avatar") {
                HStack(spacing: theme.spacing.m) {
                    ArgonAvatar(initials: "AL", size: .s)
                    ArgonAvatar(initials: "AL")
                    ArgonAvatar(initials: "AL", size: .l)
                    ArgonAvatar(size: .l)
                    ArgonAvatar(imageUrl: sampleImage, initials: "AL", size: .l)
                }
            }
        }
    }

    private var containers: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxl) {
            GallerySection("Card") {
                ForEach([ArgonCardStyle.elevated, .outlined, .filled], id: \.self) { style in
                    ArgonCard(style: style) {
                        VStack(alignment: .leading, spacing: theme.spacing.xs) {
                            Text("\(style)".capitalized).font(theme.type.headline).foregroundStyle(theme.colors.ink)
                            caption("Content brings its own padding")
                        }
                        .padding(theme.spacing.l)
                    }
                }
                ArgonCard(style: .outlined, onClick: {}) {
                    Text("Tappable card").font(theme.type.body).foregroundStyle(theme.colors.ink).padding(theme.spacing.l)
                }
            }
            GallerySection("Carousel") {
                ArgonCarousel(count: 4, autoplaySeconds: 3) { index in
                    RoundedRectangle(cornerRadius: theme.radius.l)
                        .fill(theme.colors.border)
                        .overlay { Text("Slide \(index + 1)").font(theme.type.title).foregroundStyle(theme.colors.ink) }
                }
                .frame(height: 200)
                // out of the gallery's side padding: a carousel spans the screen edge to edge
                .padding(.horizontal, -theme.spacing.l)
                caption("Edge to edge, neighbours peek 4%. Autoplays every 3 s (not under Reduce Motion)")
            }
            GallerySection("Accordion") {
                ArgonAccordion(title: "Shipping & returns", isExpanded: accordionOpen, onToggle: { accordionOpen.toggle() }) {
                    Text("Free shipping over $100. Returns within 30 days.")
                }
                ArgonDivider()
                ArgonAccordion(title: "Care", isExpanded: careOpen, onToggle: { careOpen.toggle() }) {
                    Text("Dry clean only.")
                }
            }
            GallerySection("Divider") {
                ArgonDivider()
                ArgonDivider(inset: 16)
            }
        }
    }

    private var progress: some View {
        GallerySection("ProgressBar, Spinner") {
            ArgonProgressBar(value: 0.35)
            ArgonProgressBar(value: nil)
            HStack(spacing: theme.spacing.xl) {
                ArgonSpinner(size: .s)
                ArgonSpinner()
                ArgonSpinner(size: .l)
            }
        }
    }

    private var list: some View {
        GallerySection("List, ListItem") {
            ArgonList(header: "Account") {
                ArgonListItem(title: "Orders", subtitle: "2 on the way", leading: .icon(.bag), trailing: .chevron, onClick: {})
                ArgonListItem(title: "Ada Lovelace", subtitle: "ada@example.com", leading: .avatar(imageUrl: nil, initials: "AL"), trailing: .text("Edit"))
                ArgonListItem(title: "Messages", leading: .icon(.mail), trailing: .badge(4))
                ArgonListItem(title: "What's new", leading: .icon(.gift), trailing: .badge(nil))
                ArgonListItem(title: "Order updates", leading: .icon(.info), trailing: .`switch`(isOn: listSwitch, onChange: { listSwitch = $0 }))
                ArgonListItem(title: "Remember me", trailing: .checkbox(isChecked: listCheck, onChange: { listCheck = $0 }))
                ArgonListItem(title: "Silk saree", subtitle: "Image leading", leading: .image(sampleImage))
            }
            .frame(height: 560)
        }
    }

    private var navigation: some View {
        GallerySection("Modal, FullScreenModal, BottomSheet, SideMenu, TopBar, BottomBar") {
            HStack(spacing: theme.spacing.s) {
                ArgonButton(title: "Modal", style: .secondary, size: .s) { modal = true }
                ArgonButton(title: "Full screen", style: .secondary, size: .s) { fullScreen = true }
                ArgonButton(title: "Sheet", style: .secondary, size: .s) { sheet = true }
            }
            HStack(spacing: theme.spacing.s) {
                ArgonButton(title: "Side menu", style: .secondary, size: .s, icon: .menu) { menuOpen = true }
                ArgonButton(title: "Bottom bar", style: .secondary, size: .s) { bottomBar = true }
                    .argonFullScreenModal(isPresented: $bottomBar, title: "BottomBar") { BottomBarDemo() }
            }
            ForEach([ArgonTopBarVariant.standard, .largeTitle, .centeredLogo, .search], id: \.self) { variant in
                NavigationLink {
                    TopBarDemo(variant: variant)
                } label: {
                    HStack {
                        Text("TopBar: \(String(describing: variant))").font(theme.type.body).foregroundStyle(theme.colors.ink)
                        Spacer()
                        ArgonIcon(name: .chevronRight, size: 14, tint: theme.colors.muted)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }
}

@MainActor
private struct GallerySection<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.argonTheme) private var theme

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            Text(title).font(theme.type.title).foregroundStyle(theme.colors.ink)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private struct TopBarDemo: View {
    let variant: ArgonTopBarVariant
    @State private var search = ""

    init(variant: ArgonTopBarVariant) {
        self.variant = variant
    }

    var body: some View {
        List(1...30, id: \.self) { row in
            Text("Row \(row)")
        }
        .argonTopBar(
            variant: variant,
            title: "Maison",
            leading: variant == .standard ? [ArgonTopBarAction(icon: .menu, accessibilityLabel: "Menu") {}] : [],
            trailing: [
                ArgonTopBarAction(icon: .search, accessibilityLabel: "Search") {},
                ArgonTopBarAction(icon: .bag, accessibilityLabel: "Bag", badge: 2) {},
            ],
            searchText: $search
        )
    }
}

@MainActor
private struct BottomBarDemo: View {
    @State private var selected = "home"
    @Environment(\.argonTheme) private var theme

    private let items = [
        ArgonBottomBarItem(id: "home", title: "Home", icon: .home),
        ArgonBottomBarItem(id: "shop", title: "Shop", icon: .grid),
        ArgonBottomBarItem(id: "wishlist", title: "Wishlist", icon: .heart),
        ArgonBottomBarItem(id: "bag", title: "Bag", icon: .bag, badge: 3),
        ArgonBottomBarItem(id: "account", title: "Account", icon: .person),
    ]

    init() {}

    var body: some View {
        ArgonBottomBar(items: items, selectedId: selected, onSelect: { selected = $0 }) { item in
            Text(item.title)
                .font(theme.type.title)
                .foregroundStyle(theme.colors.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.colors.paper)
        }
    }
}
