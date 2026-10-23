# Theme and onboarding: one design system, and the welcome as a screen

Date: 2026-10-23. Repos: Argon (apps, contract) and Krypton (admin). Builds on screens v2 (2026-10-19-screens-v2-design.md).

## Why

The merchant asked two things of Krypton's admin:

1. "Onboarding screens should come under screens, correct? Why is this setting here." The welcome pages were three
   heading/text pairs in App settings, with no pictures, no preview, and a fixed count of three.
2. "Appearance feels like it's not linked to settings on screens and pages." Appearance (accent, light/dark, fonts),
   Navigation (bars and their colours) and the builder's screen look (background, top bar, section colours) were three
   pages that never showed each other's changes: change the accent and the builder's phone stayed grey.

AppBrew, the benchmark, has one theme that every screen is drawn with. This spec gives Argon the same.

## Decisions

### 1. One theme, set once, inherited everywhere

The theme is a handful of global tokens. Screens and sections inherit them and override only where it is a real
choice for that screen or section.

| Token | Settings path | Values | As built |
|---|---|---|---|
| Accent | `brand.accent` (unchanged) | `#RRGGBB` | the shop's brand colour, else ink |
| Background | `appearance.colors.background` **new** | `#RRGGBB` or "" | Argon paper `#F6F4F0` |
| Text | `appearance.colors.text` **new** | `#RRGGBB` or "" | Argon ink `#17150F` |
| Light / dark | `appearance.mode` (unchanged) | system, light, dark | system |
| Fonts | `appearance.fonts` (unchanged) | heading, body | Instrument Serif, Hanken Grotesk |
| Corners | `appearance.corners` **new** | square, rounded, round | rounded |
| Buttons | `appearance.buttons` **new** | pill, rounded, square | pill |

The tokens stay in the settings (GET /v1/settings/{shop}) rather than a screen: the app needs them before it draws
anything, and the settings are already cached for that.

**Background and text are the light appearance's.** In dark appearance the apps keep Argon's dark palette (with the
accent). One pair of colours can't be right for both, and a merchant who wants a dark brand sets "Always dark". The
admin says so next to the fields.

**Derived tokens.** From background (B) and text (T), when either is set (contract/theme.js, `themeTokens`):

- paper = B, ink = T
- muted = T at 62% over B; border = T at 14% over B
- surface = B mixed 70% toward white when B is light, else B mixed 8% toward T
- onAccent stays black or white by contrast with the accent

**Corners** scale the radius tokens: square 0/0/0, rounded 4/8/16 (Argon's own), round 8/16/24 (s/m/l). Cards,
images, inputs and sheets read them. **Buttons** have their own shape: pill (fully round), rounded (8), square (0).

The derivation lives once, in Argon's `contract/theme.js`, with vectors in `contract/fixtures/theme/vectors.json` that the
Kotlin, Swift and JavaScript tests all check, and that Krypton's preview script is tested against.

**Overrides, by level.**

- Screen: `screen.background` (exists) replaces the theme background on that screen; `top_bar`/`top_bar_tint` (exist).
- Section: `background` and `padding` (exist). A section on its own background picks its text colour itself: the
  theme's text when it reads at 4.5:1 or better on that background, else black or white. No new setting.
- Bars: the top bar and tab bar colours (exist, in `navigation`) default to the theme (background, text, accent).

Nothing else is overridable per screen: fonts, corners and buttons are brand-wide on purpose.

### 2. One "Design" page instead of Appearance + Navigation

The admin's navigation goes from nine items to eight: Overview, Screens & pages, **Design**, Push notifications,
App settings, Releases, App health, Integrations. Design has, in order: Theme (colours, light/dark, fonts, corners,
buttons), Tab bar, Top bar and menu, Announcement bar, with one phone preview beside them and one save bar. The old
`/appearance` and `/navigation` URLs redirect to `/design`.

"Set when the apps are built" (name, icon, launch screen) moves to the bottom of Design as a note.

### 3. Every preview draws with the same tokens

Krypton's `web/js/theme.js` computes the tokens (the same function as the contract's, tested against its vectors) and
writes them as CSS variables onto a `.phone`. The phone's CSS reads only those variables: background, text, muted,
border, surface, accent, radius s/m/l, button radius, heading and body font. The builder's phone (every screen,
including onboarding), and the Design phone call it, so an accent, background or font change on Design shows in the
builder, and the builder's phone shows the bars as Design has them. Design's phone repaints as the merchant types,
before saving.

### 4. Onboarding is a screen

A new system screen, handle `onboarding`, listed first under Screens & pages and edited in the same builder.

Its template holds exactly one section, type `onboarding` ("Welcome pages"), which only this screen takes:

- settings: `enabled` (boolean, default true): show the welcome the first time the app opens.
- blocks `page`, 1 to 5, in order; each: `image` (image), `video` (url, MP4 or HLS: plays muted on a loop over the
  image), `heading` (text, up to 60), `text` (text, up to 200), `button_label` (text, up to 24; empty: "Next", and
  "Get started" on the last page).

The screen takes no other section types and no `top_bar`; a page without a picture or video shows the stock picture
for its place, as the built-in welcome does, so the builder hides Screen look here. The builder's phone shows the page
being edited full-screen with the theme's fonts and button shape.

**Apps.** The welcome reads the `onboarding` screen live (it is shown once, and must be the merchant's words that
very first time, which the cached settings can't be: there are none on a first launch). Up to 3 seconds; meanwhile
the plain theme background. Then, in order:

1. the screen's `onboarding` section: `enabled: false` (or hidden) skips the welcome; its pages are shown (a page
   without picture or video gets the stock picture for its place);
2. else the settings' `onboarding.pages` words over the built-in pages (what apps did before);
3. else the built-in pages.

**Older apps** read only `settings.onboarding`. Saving the onboarding screen also writes `settings.onboarding`
(`enabled`, and each of the first three pages' heading and text), so they keep following the merchant.

**Migration.** The first time the builder opens the onboarding screen and it was never saved, it starts from
`settings.onboarding`: enabled as it was, one page per saved page (heading and text), else three empty pages. Nothing
is written until the merchant saves. App settings loses its "Welcome pages" section and links to the screen instead.

## Not doing

- Per-screen fonts, corners or buttons: brand-wide by design.
- A dark-mode pair of background/text colours: "Always dark" plus Argon's dark palette covers it.
- Skip-button or dot-style options on the welcome: Argon's own.
