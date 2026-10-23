# One design system: colours, type, icons and shapes, used by everything

Date: 2026-10-24. Follows 2026-10-23-theme-and-onboarding-design.md.

## Why

The merchant: "there should be 1 color system, 1 font system, 1 icon system and so on that gets applied throughout
the theme, including on pages. Sections can still use their own colours, but by default they use the colours in the
design."

After the theme work the apps had global tokens, but everything else that takes a colour (a section's background
or text colour, a screen's background, the top bar, tab bar and announcement bar) took a raw `#RRGGBB` with defaults
of its own (`#111111`, `#FFFFFF`), so none of it followed the theme. Icons had no theme setting, and type had fonts but
no sizes.

## Decisions

### Colour system: eight named colours, referred to by name

| Name | Set on Design | As built |
|---|---|---|
| `accent` | yes (`brand.accent`) | the shop's brand colour, else text |
| `secondary` | yes, **new** (`appearance.colors.secondary`) | text |
| `background` | yes (`appearance.colors.background`) | Argon paper |
| `text` | yes (`appearance.colors.text`) | Argon ink |
| `surface`, `muted`, `border` | made from background and text | Argon's |
| `sale` | no | Argon's |

**Every colour setting anywhere takes a name or a custom `#RRGGBB`**: section `background`, `text_color`, the screen's
`background`, `navigation.topBar.background/foreground`, `navigation.tabBar.*`, `announcement.background/color`.
A name follows the theme (and light/dark): change the accent on Design and every section set to `accent` changes.
A custom hex stays what it is. That's the "can still use their own colours".

**Defaults are names, never hex.** The announcement bar and the scrolling-text section are the theme inverted:
background `text`, words `background`. A banner's words over a picture stay white (they sit on a
photo, not on the theme). Empty bar colours are the theme's (unchanged).

The admin's colour fields become one picker everywhere: the theme's swatches first (each named, painted in the
current theme), then "Custom" with the hex field. The stored value is the name or the hex.

Older apps read a name as an invalid colour and use their own default: nothing breaks.

### Type system

Heading and body fonts (exists), and **one size scale**, `appearance.type.scale`: `small` (0.9), `medium` (1, as built),
`large` (1.12), applied to every text role. Sections never pick fonts or sizes.

### Icon system

One icon set (Argon's: Material Symbols on Android, SF Symbols on iOS, the same shapes by name) and **one style**,
`appearance.icons`: `outline` (as built) or `filled`, for every icon the apps draw: tabs, bars, feature blocks,
buttons. A merchant's uploaded tab icon is drawn as uploaded. Android bundles the filled Material Symbols beside the
outlined ones; iOS uses each SF Symbol's `.fill`.

### Shapes

Corners and buttons (exist). Nothing new.

### Where it's set

Design → Theme groups them: Colours (accent, secondary, background, text, with the made ones shown as swatches),
Type (fonts, size), Icons (style), Shapes (corners, buttons), Light and dark. Every preview paints with them
(js/theme.js), including name references in sections.

## Not doing

- Per-section fonts or icon styles: one system on purpose.
- A dark-mode set of colours: dark keeps Argon's palette with the accent (unchanged).
