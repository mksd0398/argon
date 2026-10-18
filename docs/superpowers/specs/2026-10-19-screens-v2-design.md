# Argon screens v2: every screen from sections

Date: 2026-10-19. Status: decided by Claude on Mayank's instruction ("take calls everywhere"). Used by Krypton's
builder (`mksd0398/krypton`, docs/specs/2026-10-18-krypton-dashboard.md).

## What changes

Today one screen is configurable: the home screen, as a list of `mobile_banner` / `mobile_products` /
`mobile_collections` metaobjects drawn by one of four template views. v2 makes **every screen** a list of sections
read from the store, so a merchant (through Krypton, or Shopify's own metaobject editor) composes the home screen,
adds sections above and below the product, collection, cart, search, account, orders and wishlist screens, and makes
pages of their own, with no release. The native code is the section catalogue; the store holds the layout.

Old apps and stores keep working: a screen without a v2 template is drawn exactly as today. The one change every
store sees is the link rules (*Links*): `/pages/x`, `/cart`, `/account`, `/wishlist` and `/` open in the app instead
of the browser (a page with no body text, such as one built from theme sections, still opens in the browser).

## Where screens live

One metaobject per screen, type **`app_screen`**, storefront `PUBLIC_READ`:

| Field | Type | |
|---|---|---|
| `title` | single_line_text_field, required | The screen's title (custom pages show it in the top bar) |
| `template` | json, required | The sections, below |

The handle is the screen: `home`, `product`, `collection`, `cart`, `search`, `account`, `orders`, `wishlist`, or any
other handle for a **custom page** (`about`, `size-guide`, ...). `contract/sections.js` adds the definition next to
the v1 ones; Argon's CLI and Krypton create it. Read with `AppScreen.graphql`
(`metaobject(handle: { type: "app_screen", handle })`, fields `title`, `template`, `updatedAt`).

The home screen tries `app_screen/home` first; if it is missing or its template has no sections, the v1 path
(`mobile_screen/home` and the home template views) runs as today.

## The template

```json
{
  "version": 2,
  "metafields": ["product.custom.fabric", "shop.custom.promo"],
  "sections": [
    {
      "id": "s7f3a",
      "type": "banner",
      "settings": { "heading": "Winter is here", "image": { "url": "https://cdn.shopify.com/...", "alt": "", "width": 1600, "height": 2000 }, "link": "/collections/winter", "style": "hero" },
      "blocks": [],
      "platforms": ["ios", "android"],
      "track": "winter_hero",
      "hidden": false
    },
    { "id": "main", "type": "main", "settings": {} }
  ]
}
```

- `id`: unique in the template, `[a-z0-9_-]{1,40}`. Krypton generates them; analytics uses them.
- `type`: a section type below. **Unknown types are skipped**, so an old app ignores a section a newer app knows.
- `settings`: by type. Every setting is optional; a missing or invalid value falls back to the type's default,
  value by value (the same lenient decoding as RemoteSettings).
- `blocks`: `[{ id, type, settings }]`, used by `slideshow` (blocks of type `slide`).
- `platforms`: where it shows; missing = both.
- `hidden`: kept in the template, not shown.
- `track`: optional name for analytics; default the section's type.
- `metafields`: every metafield the template's Liquid reads, as `owner.namespace.key` with owner `product`,
  `collection` or `shop`. Krypton fills it at save time from the Liquid; the app queries exactly these.

Decoding never fails a screen: a template that isn't valid JSON is "no template".

### Main section (system screens)

Each system screen's template has exactly one section of type `main`: where the screen's own content goes.
Sections before it are drawn above, sections after it below. If `main` is missing, it is appended at the end.

| Screen | Above | Below | `main` settings |
|---|---|---|---|
| home | - | - | none: home has no `main`; all its content is sections |
| product | yes | yes | `blocks`: the PDP blocks in order, each `{ "type": "gallery" \| "title" \| "price" \| "options" \| "purchase" \| "bundle" \| "details" \| "reviews" \| "rails", "hidden": bool }`; missing ones keep their default place |
| collection | yes | no (infinite grid) | `filters`: `"top"` \| `"bottom"` (overrides the collection template) |
| search | yes | no | none |
| cart | yes | yes | none |
| account | yes | yes | none |
| orders | yes | yes | none |
| wishlist | yes | yes | none |
| custom page | - | - | none: no `main` |

## Settings value types

| Type | JSON | |
|---|---|---|
| text | string | May contain Liquid (`{{ }}`, `{% %}`) |
| richtext | string | Simple HTML (`p`, `strong`, `em`, `a`, `br`, `ul`, `ol`, `li`), drawn with HtmlText; may contain Liquid |
| image | `{ url, alt, width, height }` | A Shopify CDN URL; the app asks for its size with `&width=` |
| link | string | A store path (`/collections/x`, `/products/x`, `/pages/x`, `/search?q=`), `/cart`, `/account`, `/wishlist`, `app://screens/<handle>`, or an https URL |
| product | string | Product GID |
| products | string[] | Product GIDs |
| collection | string | Collection GID |
| collections | string[] | Collection GIDs |
| number | number | |
| boolean | boolean | |
| color | string | `#RRGGBB` |
| choice | string | One of the type's choices |
| datetime | string | ISO 8601 |
| html | string | Custom section only |

Products and collections are GIDs so one `SectionNodes.graphql` query (`nodes(ids:)`, ProductCard and
CollectionCard with `products(first: 24)`) loads every section of a screen at once.

## Section catalogue

| Type | Settings (default) | Blocks |
|---|---|---|
| `banner` | image, heading (text), text (text), button_label (text), link, style (choice hero\|card, hero), height (choice small\|medium\|large, large), text_color (color, #FFFFFF) | |
| `slideshow` | autoplay (boolean, true), interval (number seconds 3-15, 5), height (choice, large) | `slide`: image, heading, text, button_label, link |
| `products` | heading, collection, products, style (choice carousel\|grid, carousel), limit (number 1-24, 8), show_all (boolean, true) | |
| `collections` | heading, collections, style (choice circles\|grid\|list, circles) | |
| `rich_text` | heading (text), text (richtext), alignment (choice start\|center, start) | |
| `image_with_text` | image, heading, text (richtext), button_label, link, image_position (choice start\|end, start) | |
| `video` | url (https mp4 or HLS), poster (image), autoplay (boolean, true), loop (boolean, true), muted (boolean, true), aspect (choice 16:9\|9:16\|1:1\|4:5, 16:9) | |
| `countdown` | heading, text, ends_at (datetime), link, hide_when_over (boolean, true) | |
| `spacer` | height (number 4-120, 24), divider (boolean, false) | |
| `custom` | html (html), render (choice native\|web, web), nodes (Krypton's compiled tree, below), height (number, 0 = fit content) | |

`products`: `products` when not empty, else the collection's first `limit`; "See all" opens the collection.
`collections`: circles (image in a circle, title below, horizontal), grid (2 columns), list (rows).

## Links

One function on each platform, `Links.resolve`, extended:
- `/pages/<handle>` → `Route.Page(handle)`: the Shopify page, drawn natively with HtmlText (`Page.graphql`).
  Previously these opened the web.
- `app://screens/<handle>` → `Route.Screen(handle)`: a custom page from `app_screen`.
- `/cart`, `/account`, `/wishlist` → that tab. `/` → home tab.
- Everything else as today.

## Analytics

Two GA4 ecommerce events on every section, through the existing `Analytics` hub and sinks:
- `view_promotion` once per section per screen visit, when at least half of it is on screen.
- `select_promotion` when a section's link, button, product or collection is tapped.

Params: `promotion_id` = section id, `promotion_name` = `track` or type, `creative_name` = block id when a block was
tapped, `creative_slot` = `<screen>:<index>`. Meta and MoEngage sinks pass them under the same names.

## Liquid

Text, richtext and html settings may hold Liquid, evaluated on the device when the section is drawn, with the
screen's objects. Argon carries its own small interpreter on each platform (`Liquid.kt`, `Liquid.swift`): no
dependency, the same behaviour on both, checked by shared test cases in `contract/liquid-cases.json` that
[liquidjs](https://liquidjs.com) (Shopify's semantics, used by Krypton's preview) must also pass (`npm test`).

Supported:
- Output `{{ expr | filter: arg, ... }}`; expressions are literals (strings, numbers, true, false, nil), variables
  with `.key` and `[0]` / `["key"]` access, `.size`, `.first`, `.last`.
- Tags: `if` / `elsif` / `else` / `unless` with `==`, `!=`, `<`, `>`, `<=`, `>=`, `contains`, `and`, `or`
  (right to left, as Liquid); `for` over arrays with `limit:`, `offset:`, `reversed`, `forloop.index`,
  `forloop.first`, `forloop.last`, `else`; `assign`; `capture`; `comment`; `raw`.
  Whitespace control `{{-` `-}}` `{%-` `-%}`.
- Filters: `append`, `prepend`, `upcase`, `downcase`, `capitalize`, `strip`, `lstrip`, `rstrip`, `strip_html`,
  `escape`, `truncate`, `truncatewords`, `replace`, `replace_first`, `remove`, `split`, `join`, `first`, `last`,
  `size`, `default`, `plus`, `minus`, `times`, `divided_by`, `modulo`, `round`, `ceil`, `floor`, `abs`, `date`
  (strftime subset `%Y %m %d %e %b %B %a %A %H %M %I %p %y %j %%`), `money` (the shop's currency, from a decimal
  string), `money_without_currency`, `handleize`, `url_encode`, `newline_to_br`, `pluralize`.
- Anything else (unknown tags, unknown filters, `render`, `section`, `form`, `paginate`) renders as nothing, and a
  syntax error renders the original text without the Liquid. Never a crash.

Objects:

| Name | Where | Fields |
|---|---|---|
| `shop` | everywhere | name, currency, metafields |
| `product` | product screen | title, handle, vendor, type, tags, price, compare_at_price, available, url, metafields |
| `collection` | collection screen | title, handle, description, url, metafields |
| `customer` | signed in | first_name, last_name, email, tags (when the Customer Account API has them) |
| `cart` | everywhere | item_count, total_price |
| `section` | in a section | id, settings |
| `block` | in a block | id, settings |

`metafields.<namespace>.<key>` is the metafield's value as text (JSON values parsed). Only metafields listed in the
template's `metafields` are loaded (`product.metafields(identifiers:)` as today, plus `CollectionMetafields.graphql`
and `ShopMetafields.graphql`), and only those storefront-accessible: others read as nil.

## Custom section

`html` is HTML with Liquid. Two ways to draw it:

- **web** (default): Liquid is evaluated over the whole html, which is shown in a WebView in a page with the app's
  font, colours and accent as CSS variables (`--accent`, `--text`, `--background`), `max-width: 100%` images, no
  margins and 16px side padding (the native sections' gutter; the merchant's CSS can change it). Height fits the content (measured in the page), or `height` when set. Links in it go through
  `Links.resolve`: store links open in the app, others in the browser. JavaScript is on (the merchant's own).
- **native**: Krypton compiles html that stays within a known subset into `nodes`, and the app draws them with its
  components. Liquid is only in text and attributes (evaluated per node). The subset: `h1`-`h3`, `p`, `strong`/`b`,
  `em`/`i`, `a`, `br`, `ul`/`ol`/`li`, `img`, `hr`, `button`/`a.button` and Argon's own tags `<k-product id>`,
  `<k-collection id limit>`, `<k-button link>`. Anything else (style, script, tables, structural Liquid like a `for`
  that makes elements) makes Krypton save it as `web`. An app given `render: native` with no `nodes` draws it as web.

`nodes` shape:
```json
[
  { "type": "heading", "level": 2, "text": "Hello {{ customer.first_name }}" },
  { "type": "paragraph", "runs": [{ "text": "Made in ", "bold": false }, { "text": "Italy", "bold": true, "link": "/pages/about" }] },
  { "type": "list", "ordered": false, "items": [[{ "text": "One" }], [{ "text": "Two" }]] },
  { "type": "image", "url": "https://...", "alt": "", "link": "" },
  { "type": "button", "label": "Shop now", "link": "/collections/all" },
  { "type": "divider" },
  { "type": "product", "id": "gid://shopify/Product/1" },
  { "type": "collection", "id": "gid://shopify/Collection/1", "limit": 8 }
]
```
A run has `text`, and optional `bold`, `italic`, `link`.

## App shell (RemoteSettings, Krypton)

New RemoteSettings fields, decoded leniently like the rest; applied at the next launch:

```json
{
  "navigation": {
    "tabs": [{ "id": "home", "title": "Home", "icon": "home" }, { "id": "shop" }, { "id": "search" }, { "id": "wishlist" }, { "id": "account" }],
    "labels": true,
    "topBar": { "style": "standard", "transparentOnHome": false },
    "drawer": { "enabled": false, "menu": "main-menu" }
  },
  "announcement": {
    "enabled": true, "messages": [{ "text": "Free shipping over $75", "link": "/collections/all" }],
    "background": "#111111", "color": "#FFFFFF", "interval": 5, "dismissible": true
  },
  "appearance": { "mode": "system" }
}
```

- `tabs`: 2 to 5, ids `home`, `shop`, `search`, `wishlist`, `cart`, `account`, or `screen:<handle>`; `home` is
  required and first. `icon` from Argon's icon set (`home`, `grid`, `search`, `heart`, `bag`, `person`, `star`,
  `tag`, `menu`); `title` up to 16 characters. Invalid lists fall back to the built-in five. The cart opens as a
  tab when listed, otherwise from the bag button in the top bar.
- `labels`: show tab titles.
- `topBar.style`: `standard` | `centered_logo` | `search` (the template's own bar when absent).
  `transparentOnHome`: the home top bar over the first section, solid on scroll (the fashion behaviour).
- `drawer`: a side menu from the Shopify menu `menu` (`Menu.graphql`, as the Shop tab), opened by a menu button in
  the top bar.
- `announcement`: a strip above the top bar on every tab root, rotating `messages` every `interval` seconds (3-15),
  links through `Links.resolve`, closable for the session when `dismissible`.
- `appearance.mode`: `system` | `light` | `dark`.

## Push notifications

With `--push` (needs the Firebase files), the apps subscribe to the store's Firebase Cloud Messaging topics `all`
and `ios` / `android` once the customer allows notifications (from Account, or after their first purchase; never at
first launch), and report the opt-in to Krypton (`/v1/devices/{shop}`, an anonymous install id). A notification's
`link` opens through `Links.resolve`. The sending side is Krypton's (its dashboard spec, "Push notifications").

## Out of scope here

Drag-and-drop editing in the app, section types loaded at runtime, mid-session settings changes, rich images in
iOS notifications (a notification service extension).

## Testing

- `npm test`: the `app_screen` definition; every contract query against the schema; `liquid-cases.json` through
  liquidjs; fixtures for the new queries.
- Both platforms: unit tests for template decoding (lenient, unknown types skipped, `main` placement), Liquid (every
  case in `liquid-cases.json`, read from the fixtures), `Links.resolve` additions, nav settings decoding, custom
  nodes decoding, promotion events. Android runs them locally (`./gradlew testDebugUnitTest`); iOS in CI on macOS,
  and the app compiles locally with xtool in WSL.
