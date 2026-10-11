package app.argon.ui.gallery

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import app.argon.ui.ArgonSize
import app.argon.ui.ArgonTheme
import app.argon.ui.components.ArgonAccordion
import app.argon.ui.components.ArgonAvatar
import app.argon.ui.components.ArgonBadge
import app.argon.ui.components.ArgonBadgedBox
import app.argon.ui.components.ArgonBottomBar
import app.argon.ui.components.ArgonBottomBarItem
import app.argon.ui.components.ArgonBottomSheet
import app.argon.ui.components.ArgonButton
import app.argon.ui.components.ArgonButtonGroup
import app.argon.ui.components.ArgonButtonStyle
import app.argon.ui.components.ArgonCard
import app.argon.ui.components.ArgonCardStyle
import app.argon.ui.components.ArgonCarousel
import app.argon.ui.components.ArgonCheckbox
import app.argon.ui.components.ArgonDatePicker
import app.argon.ui.components.ArgonDateRangePicker
import app.argon.ui.components.ArgonDivider
import app.argon.ui.components.ArgonDropdown
import app.argon.ui.components.ArgonFullScreenModal
import app.argon.ui.components.ArgonIcon
import app.argon.ui.components.ArgonIconName
import app.argon.ui.components.ArgonInput
import app.argon.ui.components.ArgonInputOTP
import app.argon.ui.components.ArgonKeyboard
import app.argon.ui.components.ArgonList
import app.argon.ui.components.ArgonListItem
import app.argon.ui.components.ArgonListLeading
import app.argon.ui.components.ArgonListTrailing
import app.argon.ui.components.ArgonModal
import app.argon.ui.components.ArgonModalAction
import app.argon.ui.components.ArgonProgressBar
import app.argon.ui.components.ArgonQuantityStepper
import app.argon.ui.components.ArgonRadioGroup
import app.argon.ui.components.ArgonRangeSlider
import app.argon.ui.components.ArgonRating
import app.argon.ui.components.ArgonSheetDetent
import app.argon.ui.components.ArgonSideMenu
import app.argon.ui.components.ArgonSideMenuItem
import app.argon.ui.components.ArgonSpinner
import app.argon.ui.components.ArgonSwatch
import app.argon.ui.components.ArgonSwitch
import app.argon.ui.components.ArgonTabs
import app.argon.ui.components.ArgonTag
import app.argon.ui.components.ArgonTagStyle
import app.argon.ui.components.ArgonTextArea
import app.argon.ui.components.ArgonTopBar
import app.argon.ui.components.ArgonTopBarAction
import app.argon.ui.components.ArgonTopBarVariant
import coil3.compose.AsyncImage
import java.time.LocalDate

// mock.shop product photos (the demo store's CDN)
private val photos = listOf(
    "2b6e548b7deeed36367218be099c91d2366145fdac845fa32455c6ee502cdaea",
    "e4fe192f0e86ffc74d3b906f754119d4b5f4432cf01120d090ab7eb5182e8897",
    "c99af4de567f8baafab47fa2d5267d83a997f9082892f01d7145c0eaa5403832",
    "3d4d46da1bdbda2bf52f92987e6d4108770eb0a8f233f63a279849fce731f5af",
).map { "https://cdn.shopify.com/mock-shop-production-media/_seeds/demostore/$it.jpg?width=600" }

/**
 * Every Argon component in each of its states, with a light/dark switch: the visual review surface.
 * The app shows it in debug builds only (Account > Components). [accentHex] is the shop's brand colour.
 */
@Composable
fun ArgonGallery(accentHex: String? = null, onBack: (() -> Unit)? = null) {
    val system = isSystemInDarkTheme()
    var dark by rememberSaveable { mutableStateOf(system) }
    ArgonTheme(accentHex, dark) {
        var menuOpen by remember { mutableStateOf(false) }
        ArgonSideMenu(
            isOpen = menuOpen,
            onDismiss = { menuOpen = false },
            header = { Text("Maison", Modifier.padding(ArgonTheme.spacing.xl), style = ArgonTheme.type.title) },
            footer = { ArgonButton("Sign in", Modifier.padding(ArgonTheme.spacing.l), style = ArgonButtonStyle.Secondary, fullWidth = true) { menuOpen = false } },
            content = {
                ArgonSideMenuItem("New in", { menuOpen = false }, icon = ArgonIconName.Gift, isSelected = true)
                ArgonSideMenuItem("Women", { menuOpen = false }, hasChildren = true)
                ArgonSideMenuItem("Men", { menuOpen = false }, hasChildren = true)
                ArgonSideMenuItem("Sale", { menuOpen = false }, icon = ArgonIconName.Tag, badge = 12)
            },
        ) {
            Scaffold(
                topBar = {
                    ArgonTopBar(
                        "Components",
                        leading = listOfNotNull(onBack?.let { ArgonTopBarAction(ArgonIconName.Back, "Back", action = it) }),
                        trailing = listOf(ArgonTopBarAction(ArgonIconName.Menu, "Open menu") { menuOpen = true }),
                    )
                },
            ) { padding ->
                // Lazy: a section is composed (and its animations run) only while it is on screen
                LazyColumn(
                    Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding),
                    contentPadding = PaddingValues(bottom = ArgonTheme.spacing.xxl),
                ) {
                    item {
                        ArgonSwitch(dark, { dark = it }, Modifier.padding(horizontal = ArgonTheme.spacing.l), label = "Dark mode")
                        ArgonDivider()
                    }
                    item { Tokens() }
                    item { Icons() }
                    item { Buttons() }
                    item { Choices() }
                    item { Badges() }
                    item { Commerce() }
                    item { Inputs() }
                    item { Selection() }
                    item { Sliders() }
                    item { Progress() }
                    item { Containers() }
                    item { Carousels() }
                    item { Lists() }
                    item { Bars() }
                    item { Overlays(onOpenMenu = { menuOpen = true }) }
                    item { Dates() }
                }
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(ArgonTheme.spacing.l),
        verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m),
    ) {
        Text(title, style = ArgonTheme.type.title, color = ArgonTheme.colors.ink)
        content()
    }
    ArgonDivider()
}

@Composable
private fun Caption(text: String) = Text(text, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Tokens() = Section("Theme") {
    val c = ArgonTheme.colors
    FlowRow(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m)) {
        listOf(
            "ink" to c.ink, "muted" to c.muted, "paper" to c.paper, "surface" to c.surface, "border" to c.border,
            "accent" to c.accent, "onAccent" to c.onAccent, "sale" to c.sale, "success" to c.success,
        ).forEach { (name, color) ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(Modifier.size(48.dp).clip(ArgonTheme.radius.m).background(color).border(1.dp, c.border, ArgonTheme.radius.m))
                Caption(name)
            }
        }
    }
    val t = ArgonTheme.type
    listOf("Display" to t.display, "Title" to t.title, "Headline" to t.headline, "Body" to t.body, "Label" to t.label, "Caption" to t.caption)
        .forEach { (name, style: TextStyle) -> Text("$name — The linen shirt", style = style, color = c.ink) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Icons() = Section("Icons") {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
        ArgonIconName.entries.forEach { name ->
            Column(Modifier.width(84.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                ArgonIcon(name, tint = ArgonTheme.colors.ink, contentDescription = name.name)
                Caption(name.name)
            }
        }
    }
}

@Composable
private fun Buttons() = Section("Buttons") {
    ArgonButtonStyle.entries.forEach { style ->
        Caption(style.name)
        Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
            ArgonButton("Add", style = style, icon = ArgonIconName.Bag) {}
            ArgonButton("Off", style = style, isEnabled = false) {}
            ArgonButton("Wait", style = style, isLoading = true) {}
        }
    }
    Caption("Sizes")
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
        ArgonSize.entries.forEach { ArgonButton(it.name, size = it) {} }
    }
    ArgonButton("Full width", fullWidth = true, size = ArgonSize.L) {}
}

@Composable
private fun Choices() = Section("Button group, tabs, tags") {
    var group by remember { mutableIntStateOf(0) }
    ArgonButtonGroup(listOf("Grid", "List", "Map"), group, { group = it })
    var tab by remember { mutableIntStateOf(0) }
    ArgonTabs(listOf("Details", "Care", "Reviews"), tab, { tab = it })
    var scrollTab by remember { mutableIntStateOf(2) }
    ArgonTabs(listOf("All", "New in", "Dresses", "Knitwear", "Trousers", "Accessories", "Sale"), scrollTab, { scrollTab = it }, isScrollable = true)
    var linen by remember { mutableStateOf(true) }
    var wool by remember { mutableStateOf(false) }
    var sizes by remember { mutableStateOf(listOf("S", "M", "L")) }
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
        ArgonTag("Linen", isSelected = linen, onClick = { linen = !linen })
        ArgonTag("Wool", isSelected = wool, onClick = { wool = !wool })
        ArgonTag("New", style = ArgonTagStyle.Info)
    }
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s)) {
        sizes.forEach { size -> ArgonTag(size, style = ArgonTagStyle.Input, onRemove = { sizes = sizes - size }) }
        if (sizes.isEmpty()) ArgonButton("Reset", style = ArgonButtonStyle.Tertiary, size = ArgonSize.S) { sizes = listOf("S", "M", "L") }
    }
}

@Composable
private fun Badges() = Section("Badges and avatars") {
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xl), verticalAlignment = Alignment.CenterVertically) {
        ArgonBadge()
        ArgonBadge(3)
        ArgonBadge(120)
        ArgonBadgedBox(2) { ArgonIcon(ArgonIconName.Bag, contentDescription = "Bag, 2 items") }
        ArgonBadgedBox(null) { ArgonIcon(ArgonIconName.Heart, contentDescription = "Wishlist, updated") }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m), verticalAlignment = Alignment.CenterVertically) {
        ArgonSize.entries.forEach { ArgonAvatar(imageUrl = photos[0], size = it, contentDescription = "Profile photo") }
        ArgonAvatar(initials = "AB")
        ArgonAvatar(icon = ArgonIconName.Person, size = ArgonSize.L)
        ArgonAvatar(initials = "MK", size = ArgonSize.L)
    }
}

@Composable
private fun Commerce() = Section("Rating, quantity stepper, swatches") {
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xl), verticalAlignment = Alignment.CenterVertically) {
        ArgonRating(4.6, count = 128)
        ArgonRating(3.5, size = ArgonSize.M)
        ArgonRating(0.0, count = 0, size = ArgonSize.L)
    }
    var quantity by remember { mutableIntStateOf(1) }
    var pack by remember { mutableIntStateOf(6) }
    Caption("Quantity $quantity (1 or more); pack of $pack (multiples of 6, 6 to 24)")
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m), verticalAlignment = Alignment.CenterVertically) {
        ArgonQuantityStepper(quantity, { quantity = it }, size = ArgonSize.S)
        ArgonQuantityStepper(pack, { pack = it }, min = 6, max = 24, step = 6)
        ArgonQuantityStepper(2, {}, size = ArgonSize.L, isEnabled = false)
    }
    val shades = listOf("Sand" to "#D8C3A5", "Olive" to "#708238", "Navy" to "#1B2A49", "White" to "#FFFFFF")
    var shade by remember { mutableStateOf("Olive") }
    Caption("Colour: $shade")
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.s), verticalAlignment = Alignment.CenterVertically) {
        shades.forEach { (name, hex) -> ArgonSwatch(hex, null, name, isSelected = name == shade, onClick = { shade = name }) }
        ArgonSwatch("#B23A2E", null, "Rust, sold out", isAvailable = false, onClick = {})
        ArgonSwatch(null, photos[1], "Print", onClick = {})
        ArgonSwatch(null, null, "Unknown colour")
    }
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xs), verticalAlignment = Alignment.CenterVertically) {
        shades.forEach { (name, hex) -> ArgonSwatch(hex, null, name, size = ArgonSize.S) }
        Caption("+2")
    }
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m)) {
        shades.take(3).forEach { (name, hex) -> ArgonSwatch(hex, null, name, isSelected = name == shade, size = ArgonSize.L, onClick = { shade = name }) }
        ArgonSwatch("#B23A2E", null, "Rust", isAvailable = false, size = ArgonSize.L, onClick = {})
    }
}

@Composable
private fun Inputs() = Section("Text fields") {
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("ada@example") }
    var password by remember { mutableStateOf("hunter22") }
    var note by remember { mutableStateOf("") }
    ArgonInput("Name", name, { name = it }, placeholder = "Ada Lovelace", helper = "As on your card", leadingIcon = ArgonIconName.Person)
    ArgonInput("Email", email, { email = it }, keyboard = ArgonKeyboard.Email, error = if ("." in email.substringAfter("@")) null else "Enter a full email address")
    ArgonInput("Password", password, { password = it }, isSecure = true, trailingIcon = ArgonIconName.Lock)
    ArgonInput("Phone (disabled)", "", {}, keyboard = ArgonKeyboard.Phone, isEnabled = false)
    ArgonTextArea("Gift note", note, { note = it }, placeholder = "Write a message", maxLength = 120, helper = "Printed on the card")
    ArgonTextArea("Review", "Too short", {}, error = "At least 20 characters", minLines = 2)
    var code by remember { mutableStateOf("") }
    var completed by remember { mutableIntStateOf(0) }
    Caption("One-time code (completed $completed times)")
    ArgonInputOTP(code, { code = it }, { completed++ })
}

@Composable
private fun Selection() = Section("Checkbox, radio, switch, dropdown") {
    var terms by remember { mutableStateOf(false) }
    var news by remember { mutableStateOf(true) }
    var bare by remember { mutableStateOf(true) }
    ArgonCheckbox(terms, { terms = it }, label = "I accept the terms")
    ArgonCheckbox(news, { news = it }, label = "Email me about new arrivals")
    ArgonCheckbox(true, {}, label = "Disabled", isEnabled = false)
    ArgonCheckbox(bare, { bare = it })
    var shipping by remember { mutableStateOf<Int?>(0) }
    ArgonRadioGroup(listOf("Standard (3–5 days)", "Express (1–2 days)", "Pick up in store"), shipping, { shipping = it })
    ArgonRadioGroup(listOf("Unavailable"), null, {}, isEnabled = false)
    var push by remember { mutableStateOf(true) }
    var bareSwitch by remember { mutableStateOf(false) }
    ArgonSwitch(push, { push = it }, label = "Order updates")
    ArgonSwitch(false, {}, label = "Disabled", isEnabled = false)
    ArgonSwitch(bareSwitch, { bareSwitch = it })
    var country by remember { mutableStateOf<Int?>(null) }
    val countries = listOf("India", "United Kingdom", "United States")
    ArgonDropdown("Country", countries, country, { country = it })
    ArgonDropdown("Size", listOf("S", "M", "L"), 1, {}, isEnabled = false)
}

@Composable
private fun Sliders() = Section("Range slider") {
    var lower by remember { mutableFloatStateOf(40f) }
    var upper by remember { mutableFloatStateOf(260f) }
    Caption("Price ₹${lower.toInt()} – ₹${upper.toInt()} (step 10)")
    ArgonRangeSlider(lower, upper, 0f..500f, { l, u -> lower = l; upper = u }, step = 10f)
    ArgonRangeSlider(20f, 80f, 0f..100f, { _, _ -> }, isEnabled = false)
}

@Composable
private fun Progress() = Section("Progress") {
    ArgonProgressBar(0.35f)
    ArgonProgressBar()
    Row(horizontalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.xl), verticalAlignment = Alignment.CenterVertically) {
        ArgonSize.entries.forEach { ArgonSpinner(it) }
    }
}

@Composable
private fun Containers() = Section("Cards, accordion") {
    ArgonCardStyle.entries.forEach { style ->
        ArgonCard(Modifier.fillMaxWidth(), style = style, onClick = if (style == ArgonCardStyle.Elevated) ({}) else null) {
            Column(Modifier.padding(ArgonTheme.spacing.l)) {
                Text(style.name, style = ArgonTheme.type.headline)
                Caption(if (style == ArgonCardStyle.Elevated) "Tappable" else "Static")
            }
        }
    }
    var open by remember { mutableIntStateOf(0) }
    listOf("Description", "Size & fit", "Shipping & returns").forEachIndexed { i, title ->
        ArgonAccordion(title, open == i, { open = if (open == i) -1 else i }) {
            Text("Relaxed fit in washed linen. Model is 180 cm and wears size M.", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
        }
        ArgonDivider()
    }
}

/** Not in a padded [Section]: carousels span the screen edge to edge. */
@Composable
private fun Carousels() {
    val side = Modifier.padding(horizontal = ArgonTheme.spacing.l)
    Column(Modifier.fillMaxWidth().padding(vertical = ArgonTheme.spacing.l), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m)) {
        Text("Carousel", side, style = ArgonTheme.type.title, color = ArgonTheme.colors.ink)
        Text("Edge to edge, neighbours peek 4%, autoplay every 3 s", side, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
        ArgonCarousel(photos.size, autoplaySeconds = 3.0) { i ->
            AsyncImage(photos[i], "Photo ${i + 1}", Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(ArgonTheme.radius.l), contentScale = ContentScale.Crop)
        }
        Text("Multi-browse", side, style = ArgonTheme.type.caption, color = ArgonTheme.colors.muted)
        ArgonCarousel(photos.size, Modifier.height(200.dp), multiBrowse = true) { i ->
            AsyncImage(photos[i], "Photo ${i + 1}", Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
    }
    ArgonDivider()
}

@Composable
private fun Lists() = Section("List") {
    var notify by remember { mutableStateOf(true) }
    var saved by remember { mutableStateOf(false) }
    ArgonList(Modifier.fillMaxWidth().height(440.dp).border(1.dp, ArgonTheme.colors.border, ArgonTheme.radius.m), header = "ACCOUNT") {
        item { ArgonListItem("Orders", subtitle = "2 on the way", leading = ArgonListLeading.Icon(ArgonIconName.Truck), trailing = ArgonListTrailing.Chevron, onClick = {}) }
        item { ArgonDivider(inset = 56.dp) }
        item { ArgonListItem("Ada Lovelace", subtitle = "ada@example.com", leading = ArgonListLeading.Avatar(initials = "AL"), trailing = ArgonListTrailing.Text("Edit")) }
        item { ArgonDivider(inset = 56.dp) }
        item { ArgonListItem("Linen shirt", subtitle = "Size M · Sand", leading = ArgonListLeading.Image(photos[2]), trailing = ArgonListTrailing.Badge(3)) }
        item { ArgonDivider(inset = 56.dp) }
        item { ArgonListItem("Notifications", leading = ArgonListLeading.Icon(ArgonIconName.Info), trailing = ArgonListTrailing.Switch(notify) { notify = it }) }
        item { ArgonDivider(inset = 56.dp) }
        item { ArgonListItem("Save my details", trailing = ArgonListTrailing.Checkbox(saved) { saved = it }) }
    }
}

@Composable
private fun Bars() = Section("Top and bottom bars") {
    val back = ArgonTopBarAction(ArgonIconName.Back, "Back") {}
    val bag = ArgonTopBarAction(ArgonIconName.Bag, "Bag", badge = 2) {}
    val search = ArgonTopBarAction(ArgonIconName.Search, "Search") {}
    Caption("Standard")
    ArgonTopBar("Product", leading = listOf(back), trailing = listOf(search, bag))
    Caption("Large title")
    ArgonTopBar("Wishlist", variant = ArgonTopBarVariant.LargeTitle, trailing = listOf(bag))
    Caption("Centred logo (title when there is no logo)")
    ArgonTopBar("Maison", variant = ArgonTopBarVariant.CenteredLogo, leading = listOf(ArgonTopBarAction(ArgonIconName.Menu, "Menu") {}), trailing = listOf(bag))
    Caption("Search")
    var query by remember { mutableStateOf("") }
    ArgonTopBar("Search products", variant = ArgonTopBarVariant.Search, searchText = query, onSearchTextChange = { query = it }, trailing = listOf(bag))
    Caption("Overlay: over a picture, then solid as the picture scrolls away")
    var solid by remember { mutableStateOf(false) }
    val solidity by animateFloatAsState(if (solid) 1f else 0f, label = "solid")
    Box(Modifier.fillMaxWidth().height(160.dp).clip(ArgonTheme.radius.m)) {
        AsyncImage(photos[0], null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        ArgonTopBar("Maison", variant = ArgonTopBarVariant.Overlay, trailing = listOf(search, bag), solid = solidity)
    }
    ArgonSwitch(solid, { solid = it }, label = "Solid")
    var selected by remember { mutableStateOf("home") }
    ArgonBottomBar(
        listOf(
            ArgonBottomBarItem("home", "Home", ArgonIconName.Home),
            ArgonBottomBarItem("shop", "Shop", ArgonIconName.Grid),
            ArgonBottomBarItem("wishlist", "Wishlist", ArgonIconName.Heart),
            ArgonBottomBarItem("cart", "Cart", ArgonIconName.Bag, badge = 3),
            ArgonBottomBarItem("account", "Account", ArgonIconName.Person),
        ),
        selected,
        { selected = it },
    )
}

@Composable
private fun Overlays(onOpenMenu: () -> Unit) = Section("Overlays") {
    var modal by remember { mutableStateOf(false) }
    var fullScreen by remember { mutableStateOf(false) }
    var sheet by remember { mutableStateOf<Set<ArgonSheetDetent>?>(null) }
    var result by remember { mutableStateOf("—") }
    Caption("Last dialog choice: $result")
    ArgonButton("Modal", style = ArgonButtonStyle.Secondary, fullWidth = true) { modal = true }
    ArgonButton("Full-screen modal", style = ArgonButtonStyle.Secondary, fullWidth = true) { fullScreen = true }
    ArgonButton("Bottom sheet (medium + large)", style = ArgonButtonStyle.Secondary, fullWidth = true) { sheet = setOf(ArgonSheetDetent.Medium, ArgonSheetDetent.Large) }
    ArgonButton("Bottom sheet (large)", style = ArgonButtonStyle.Secondary, fullWidth = true) { sheet = setOf(ArgonSheetDetent.Large) }
    ArgonButton("Side menu", style = ArgonButtonStyle.Secondary, fullWidth = true, action = onOpenMenu)
    ArgonModal(
        isPresented = modal,
        title = "Remove item?",
        message = "The linen shirt will be removed from your bag.",
        primaryAction = ArgonModalAction("Remove", isDestructive = true) { result = "Remove" },
        onDismiss = { modal = false },
        secondaryAction = ArgonModalAction("Keep") { result = "Keep" },
    )
    ArgonFullScreenModal(fullScreen, { fullScreen = false }, "Size guide") {
        Column(Modifier.fillMaxSize().padding(ArgonTheme.spacing.l), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.l)) {
            Text("Chest", style = ArgonTheme.type.display, color = ArgonTheme.colors.ink)
            Text("Measure around the fullest part of your chest.", style = ArgonTheme.type.body, color = ArgonTheme.colors.muted)
            ArgonButton("Done", fullWidth = true) { fullScreen = false }
        }
    }
    ArgonBottomSheet(sheet != null, { sheet = null }, sheet ?: emptySet()) {
        Column(Modifier.padding(ArgonTheme.spacing.l), verticalArrangement = Arrangement.spacedBy(ArgonTheme.spacing.m)) {
            Text("Filters", style = ArgonTheme.type.title, color = ArgonTheme.colors.ink)
            repeat(12) { ArgonCheckbox(it % 3 == 0, {}, label = "Option ${it + 1}") }
            ArgonButton("Show results", fullWidth = true) { sheet = null }
        }
    }
}

@Composable
private fun Dates() = Section("Date pickers") {
    val today = remember { LocalDate.now() }
    var date by remember { mutableStateOf<LocalDate?>(today.plusDays(2)) }
    var start by remember { mutableStateOf<LocalDate?>(null) }
    var end by remember { mutableStateOf<LocalDate?>(null) }
    Caption("Delivery date: ${date ?: "none"} (today to +90 days)")
    ArgonDatePicker(date, { date = it }, minDate = today, maxDate = today.plusDays(90))
    Caption("Stay: ${start ?: "…"} to ${end ?: "…"}")
    ArgonDateRangePicker(start, end, { s, e -> start = s; end = e }, Modifier.height(520.dp), minDate = today)
}
