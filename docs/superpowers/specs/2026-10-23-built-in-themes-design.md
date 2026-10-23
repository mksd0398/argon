# Built-in themes: twenty complete presets, picked in Krypton, baked into the build

Date: 2026-10-23. Follows 2026-10-24-design-system-design.md (one design system).

## Why

The merchant wants "a built-in theme which they pick while deploying the native apps; the whole theme only gets
deployed while doing the build". The design system made every surface follow a few tokens. A theme is a complete,
tasteful set of those tokens, plus the navigation and every screen's sections, arranged for one kind of store.
That's the step up from AppBrew-style colour presets: a jewellery store starts from a jewellery app.

## What a theme is

One JSON file per theme in `contract/themes/<id>.json`. Argon's tests check every one against the screens contract
and the theme tokens.

```json
{
  "id": "ember-street", "name": "Ember Street", "vertical": "Streetwear",
  "description": "Loud, image-first drops for streetwear and menswear labels.",
  "settings": { "brand": {}, "appearance": {}, "navigation": {}, "announcement": {}, "home": {}, "collection": {} },
  "screens": { "home": {}, "product": {}, "collection": {}, "cart": {}, "onboarding": {} }
}
```

- **`settings`** is exactly what Krypton saves, so Apply is a merge and the apps read it as they read any settings:
  - accent;
  - background, text and secondary colours;
  - Google fonts, already resolved to their TTF files, so neither the CLI nor Apply needs Google;
  - corners, buttons, type scale, icon style and light/dark mode;
  - tabs, top bar and tab bar (colours by theme name);
  - the announcement bar;
  - the v1 home and collection templates, for apps built before screens v2.
- **`screens`** are app_screen templates that pass `checkTemplate`. They use placeholder content that is safe in
  any store:
  - Section words are generic, e.g. "New this week" or "Free shipping on prepaid orders". There is no Liquid in the
    welcome's words, because the apps draw them as written.
  - Pictures are Burst photos (Shopify's free stock, commercial use allowed, credited in
    `contract/themes/CREDITS.md`), loaded from burst.shopifycdn.com.
  - Products and collections are left unset. Krypton fills them from the store when the theme is applied: each
    products section gets the next collection that has products, and each collections section gets the first six.
    In an app without them, those sections show nothing, which is what an empty section already does.
- `contract/themes.js` lists the themes and names the default, `studio`.

## Where a theme takes effect

1. **Krypton: Design → Themes.** A gallery of the 20 themes. Each card shows the theme's swatches, fonts and a phone
   preview of its home. The preview is painted with js/theme.js like every other phone.
   - **Apply** writes the theme's settings over the store's settings. The store's own keys, delivery and checkout
     options stay as they are.
   - It then saves the five screens: bound to the store's collections, checked, and written as app_screen
     metaobjects. The onboarding screen also syncs `settings.onboarding`, as saving it in the builder does.
   - It records `theme.id` in the settings.
   - If any of those screens was saved by the merchant since the last Apply, Krypton lists them and asks before
     replacing them.
   - Apply is live for every app already installed, from the next launch, as any settings change is.
2. **The build bakes it in.** The Krypton CLI hands Argon the store's saved settings (`--settings-file`) and the
   theme (`--theme=<settings.theme.id>`). Argon writes:
   - `built-in/settings.json` into the app (Android assets, iOS Resources). The app runs with it whenever it has no fetched
     copy yet. This closes the gap where the first launch showed Argon's defaults and the theme only appeared from
     the second launch.
   - `built-in/fonts/<sha256 of the URL>.ttf`: the settings' Google font files, named the way the apps' font caches
     name a download. The app copies them into its cache, so the theme's fonts also show from the first launch.
   - `built-in/screen-<handle>.json` for the theme's five screens. The app uses them only when the store has no app_screen
     with that handle.
   - Run on its own, `npx @mksd0398/argon my-app --theme=loom-story` gives a standalone app with the theme's look
     and screens, and no Krypton involved.
3. **The release records the theme.** The Releases page shows which theme each build carries, read from the settings
   it was built with.

**New stores start on `studio`.** The first time Krypton makes a store's content, it applies the default theme,
provided the store has no saved settings and no home screen. Existing stores are never changed.

**Plan hook.** `THEMES[i].plan` is `"free"` for now (all of them). The freemium session can gate Apply on it.

## Backward compatibility

- Apps built before this ignore `theme` (they decode settings leniently).
- They get the applied tokens and screens live, as Apply only writes things they already read.
- Apps built before colour names fall back to their own colours. Themes use names on purpose, so a theme's colours
  follow the merchant's later edits.
- Old Krypton settings gain `theme: { id: "" }` from `withDefaults`.

## The twenty

Inspiration is recorded here only: never in the product, never brand names, colours, logos, words or pictures. Every
colour below is our own. Inspired-by means "the layout pattern and mood", nothing else.

| id | Name | For | Mood / layout | Inspired by (internal) |
|---|---|---|---|---|
| studio | Studio | Any store (default) | Clean, neutral, rounded; slideshow, circles, rails | (Argon's own) |
| ember-street | Ember Street | Streetwear, menswear drops | Black/white, ember accent, condensed caps; clear top bar over a tall hero, marquee, 2-up grids | Snitch |
| midnight-drip | Midnight Drip | Premium streetwear | Dark mode, acid-lime accent, square, filled icons; drop countdown | Chapter 2 Drip |
| pop-tee | Pop Tee | Graphic tees, youth casual | Sunny yellow, chunky type, pill buttons; image grid of fits | Bewakoof |
| fandom-fest | Fandom Fest | Pop-culture merch | Crimson + navy, poster type; collections grid "shop by fandom" | The Souled Store |
| silver-bloom | Silver Bloom | Everyday silver jewellery | Blush paper, rose accent, serif headings, round; slideshow, gifting | Giva |
| solitaire | Solitaire | Fine diamond and gold jewellery | Violet + gold, elegant serif; trust features, certified | Caratlane |
| temple-silk | Temple Silk | Heritage silk sarees | Ivory, maroon, antique gold; heritage story, weave sections | Nalli |
| loom-story | Loom Story | Handwoven sarees, storytelling | Earthy terracotta and leaf green; long rich text, image with text | Iwasasari |
| craft-bazaar | Craft Bazaar | Artisanal ethnic wear and home | Oatmeal, indigo and madder; craft clusters, square buttons | FabIndia |
| monsoon-kurta | Monsoon Kurta | Everyday women's ethnic wear | Teal and mustard; occasion tiles, new arrivals | W / Libas |
| deep-rest | Deep Rest | Mattresses and sleep | Navy and sea green; trial and warranty features, FAQ | Duroflex |
| cloud-nine | Cloud Nine | Playful sleep and bedding | Lilac and pink, round, big friendly type | Sleepyhead |
| hearth | Hearth & Home | Furniture and home | Warm amber on cream; room tiles, EMI and delivery features | Wakefit |
| bold-pout | Bold Pout | Bold makeup | Black, hot rose, square, filled icons; shades rail | Sugar Cosmetics |
| leaf-dew | Leaf & Dew | Natural skin, hair and baby care | Sage and honey, soft serif; shop by concern | Mamaearth |
| rose-edit | Rose Edit | Women's fashion | Rose on blush, Didone headings; edits, image grid | Nykaa Fashion |
| sharp-edge | Sharp Edge | Men's grooming | Charcoal, copper, condensed caps; routines, kits | Bombay Shaving Company |
| carry-on | Carry On | Luggage and travel gear | Stone and olive, minimal; features, collections list | Mokobara |
| clear-view | Clear View | Eyewear | Ink-teal and apricot, round; shop by shape, try-on story | Lenskart |

## Not doing

- Theme versioning or upgrades: re-applying a theme is the upgrade.
- Copying theme images into the merchant's Shopify Files. They stay on Burst's CDN until the merchant replaces them.
  Add the copy if a merchant asks to own them.
- Per-theme custom section types: themes only arrange the sections that already exist.
