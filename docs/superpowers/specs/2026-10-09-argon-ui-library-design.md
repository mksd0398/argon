# Argon UI library — design

Date: 2026-10-09. Phase 2, project 1 of 4 (then: API layer → 24 sections → core screens).

## Goal

A native component library in every generated Argon app, so sections and screens for **any** Shopify store are composed from one set of themed building blocks instead of ad-hoc views. SwiftUI on iOS, Jetpack Compose (Material 3) on Android, two codebases like v0.1. The Maison design (`Mobile Storefront.html`) is a visual reference only: shared brand, native chrome.

Success: both apps contain the 29 components below with the same names and parameters; a debug-only gallery screen shows every component in every state, light and dark; the library builds and its logic is unit-tested in CI.

Out of scope: rebuilding existing screens (project 4), section blocks (project 3), API work (project 2).

## Placement

| | Android | iOS |
|---|---|---|
| Module | `android/ui` Gradle library module, package `app.argon.ui` | local Swift package `ios/ArgonUI` (iOS 17+), product `ArgonUI` |
| Depends on | Compose Material 3 (BOM 2026.06.01 → material3 1.4.0), Coil (images) | SwiftUI only |
| Used by | `:app` (`implementation(project(":ui"))`) | `App` target (local package reference) |
| Tests | `android/ui/src/test` (JVM) | the existing `AppTests` target, `import ArgonUI` |

The library never imports app code or Shopify types: callers pass plain values (strings, URLs, numbers, closures). This keeps it testable alone and reusable by sections and screens.

## Theme

`ArgonTheme` — tokens with light and dark values:

- **Colors:** `ink #17150F`, `muted #6E6A63`, `paper #F6F4F0` (background), `surface` (cards/sheets), `border`, `accent` (the shop's brand colour from Storefront `shop.brand`, falling back to ink), `onAccent` (black/white by luminance > 0.5, today's rule), `sale #B23A2E`, `success`. Dark mode inverts paper/ink and lowers surface contrast.
- **Type:** display = Instrument Serif; text = Hanken Grotesk 400/500/600/700; system chrome (nav bars, tab labels) keeps SF Pro / Roboto. Roles: `display`, `title`, `headline`, `body`, `label`, `caption`. Both fonts are OFL (Google Fonts), bundled with `OFL.txt`; if a font fails to load, the system font is used.
- **Spacing:** 2, 4, 8, 12, 16, 24, 32. **Radius:** 4, 8, 16, pill.
- iOS: `.argonTheme(accentHex:)` view modifier → `@Environment(\.argonTheme)`. Android: `ArgonTheme(accentHex) { … }` wraps `MaterialTheme` (tokens mapped onto the M3 colour scheme, typography and shapes) and exposes `ArgonTheme.colors/type/spacing/radius` via CompositionLocals.
- iOS links and affordances use the system accent role; Android uses the M3 primary role — both set to `accent`.

## Components

All are prefixed `Argon` (avoids clashes with `Button`, `List`, `Divider`…). Parameters are named identically on both platforms (Swift labels / Kotlin named args); state is passed in and changes come out through callbacks (`Binding` on iOS where idiomatic).

Native = the platform's own control styled with tokens. Custom = built from primitives because the platform has none.

| # | Component | Key parameters | iOS | Android |
|---|---|---|---|---|
| 1 | `ArgonAccordion` | `title`, `isExpanded`, `onToggle`, `content` | native `DisclosureGroup` | custom (M3 has none) |
| 2 | `ArgonAvatar` | `imageUrl?`, `initials?`, `icon?`, `size` s/m/l | custom | custom |
| 3 | `ArgonBadge`, `ArgonBadgedBox` | `count?` (nil = dot, > 99 = "99+"), `content` | native `.badge()` on tab/list items; standalone custom | native `Badge` / `BadgedBox` |
| 4 | `ArgonBottomBar` | `items` (id, title, icon, badge?), `selectedId`, `onSelect` | native `TabView` tab bar | native `NavigationBar` |
| 5 | `ArgonBottomSheet` | `isPresented`, `detents` medium/large, `content` | native `.sheet` + `.presentationDetents` | native `ModalBottomSheet` |
| 6 | `ArgonButton` | `title`, `style` primary/secondary/tertiary/destructive, `size` s/m/l, `icon?`, `isLoading`, `isEnabled`, `fullWidth`, `action` | native `Button` + style | native `Button`/`OutlinedButton`/`TextButton` |
| 7 | `ArgonButtonGroup` | `options`, `selectedIndex`, `onSelect` | native segmented `Picker` | native `SingleChoiceSegmentedButtonRow` |
| 8 | `ArgonCard` | `style` elevated/outlined/filled, `onClick?`, `content` | custom | native `Card`/`ElevatedCard`/`OutlinedCard` |
| 9 | `ArgonCarousel` | `count`, `autoplaySeconds?`, `showsIndicators`, `itemContent(index)` | native paging (`TabView` page style) + custom autoplay | native `HorizontalPager` (+ `HorizontalMultiBrowseCarousel` variant) + custom dots/autoplay |
| 10 | `ArgonCheckbox` | `isChecked`, `label?`, `isEnabled`, `onChange` | custom (checkbox style is macOS-only) | native `Checkbox` |
| 11 | `ArgonDatePicker`, `ArgonDateRangePicker` | `selection` / `start`,`end`, `minDate?`, `maxDate?` | native `DatePicker`; range custom (two linked pickers) | native `DatePicker` / `DateRangePicker` |
| 12 | `ArgonDivider` | `inset?` | native `Divider` | native `HorizontalDivider` |
| 13 | `ArgonDropdown` | `label`, `options`, `selectedIndex?`, `onSelect` | native `Menu`/`Picker(.menu)` | native `ExposedDropdownMenuBox` |
| 14 | `ArgonIcon` | `name: ArgonIconName`, `size`, `tint?` | native SF Symbols | Material Symbols bundled as vector drawables (only the names below) |
| 15 | `ArgonInput` | `label`, `text`, `placeholder?`, `helper?`, `error?`, `keyboard` text/email/number/phone, `isSecure`, `leadingIcon?`, `trailingIcon?` | native `TextField`/`SecureField` + style | native `OutlinedTextField` |
| 16 | `ArgonInputOTP` | `length` (6), `code`, `onComplete` | custom boxes + `.textContentType(.oneTimeCode)` | custom boxes + SMS-OTP autofill hint |
| 17 | `ArgonList` | `header?`, `content` | native `List`/`LazyVStack` | native `LazyColumn` |
| 18 | `ArgonListItem` | `title`, `subtitle?`, `leading?` icon/avatar/image, `trailing?` chevron/text/badge/switch/checkbox, `onClick?` | custom row on native list | native `ListItem` |
| 19 | `ArgonModal`, `ArgonFullScreenModal` | `isPresented`, `title`, `message`, `primaryAction`, `secondaryAction?` / `content` | native `.alert` / `.fullScreenCover` | native `AlertDialog` / `Dialog` |
| 20 | `ArgonProgressBar` | `value?` 0…1 (nil = indeterminate) | native `ProgressView` | native `LinearProgressIndicator` |
| 21 | `ArgonRadioButton`, `ArgonRadioGroup` | `isSelected`, `label`, `onSelect` / `options`, `selectedIndex`, `onSelect` | custom | native `RadioButton` |
| 22 | `ArgonRangeSlider` | `lower`, `upper`, `bounds`, `step?`, `onChange` | custom (`Slider` is single-value) | native `RangeSlider` |
| 23 | `ArgonSideMenu`, `ArgonSideMenuItem` | menu: `isOpen`, `onDismiss`, `header?`, `footer?`, `content`; item: `title`, `icon?`, `badge?`, `isSelected`, `hasChildren`, `onClick` | custom slide-over with dimmed scrim, edge-swipe dismiss | native `ModalNavigationDrawer` / `NavigationDrawerItem` |
| 24 | `ArgonSpinner` | `size` s/m/l | native `ProgressView` | native `CircularProgressIndicator` |
| 25 | `ArgonSwitch` | `isOn`, `label?`, `onChange` | native `Toggle` | native `Switch` |
| 26 | `ArgonTabs` | `titles`, `selectedIndex`, `onSelect`, `isScrollable` | native segmented `Picker` (fixed); scrollable underline tabs custom | native `PrimaryTabRow` / `ScrollableTabRow` |
| 27 | `ArgonTag` | `text`, `style` filter/input/info, `isSelected`, `onClick?`, `onRemove?` | custom capsule | native `FilterChip`/`InputChip`/`AssistChip` |
| 28 | `ArgonTextArea` | `label`, `text`, `placeholder?`, `minLines`, `maxLength?`, `helper?`, `error?` | native `TextField(axis: .vertical)` | native `OutlinedTextField` (multi-line) |
| 29 | `ArgonTopBar` | `variant` standard/largeTitle/centeredLogo/search, `title`, `logoUrl?`, `leading` and `trailing` actions (icon, badge?, action), `searchText?` | native `NavigationStack` toolbar (`.principal` logo, `.searchable`), applied as `.argonTopBar(...)` | native `TopAppBar`/`CenterAlignedTopAppBar`/`LargeTopAppBar`/`SearchBar` |

**Icon names** (`ArgonIconName`), each mapped to an SF Symbol and a bundled Material Symbol: home, grid, search, bag, heart, heartFilled, person, menu, close, back, chevronRight, chevronDown, chevronUp, plus, minus, filter, sort, share, star, starFilled, location, phone, mail, check, info, warning, trash, edit, play, pause, truck, returns, leaf, clock, gift, lock, globe, calendar, tag, external, eye, eyeOff. A unit test asserts every name maps on its platform.

## Gallery

`ArgonGallery` — one screen listing every component in each state (enabled/disabled, empty/filled/error, loading, selected), with a light/dark toggle. Shown only in debug builds, from a "Components" row at the bottom of Account (`#if DEBUG` / `BuildConfig.DEBUG`). It is the visual review surface: open it on the phone.

## Accessibility

Dynamic Type / font scale respected by all text tokens; touch targets ≥ 44 pt / 48 dp; every icon-only control takes an accessibility label; carousel autoplay stops when Reduce Motion / remove-animations is on; colour pairs meet 4.5:1 for body text (unit-tested for ink/paper and accent/onAccent).

## Testing

- Unit tests (both platforms): OTP input (typing, deleting, pasting a full code, non-digits ignored, `onComplete` once); range slider clamping and stepping (lower ≤ upper, inside bounds); badge count formatting; theme accent parsing + onAccent choice + contrast; icon map completeness.
- CI: Android `:ui` tests + assemble; iOS build + `AppTests` on Xcode 16 (required) and Xcode 26.
- Visual: the gallery on a real phone (Android locally; iOS via CI build, reviewed on a Mac when available).

## Integration with today's app

The app theme moves to `ArgonTheme` (today's `AppTheme`/`brandColor` become thin calls into it). Existing screens keep working unchanged; they adopt components in project 4. The CLI copies the new module/package with the rest of the templates (no CLI change beyond file lists, if any).
