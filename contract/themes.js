// Built-in themes (docs/superpowers/specs/2026-10-23-built-in-themes-design.md): complete presets of the settings'
// design tokens, navigation and announcement, and the screens' templates, one JSON file each in contract/themes/.
// Krypton applies one to a store; the CLI bakes one into an app (--theme). checkTheme is what the tests hold them to.

import { readFileSync } from "node:fs";
import { BUTTONS, CORNERS, COLOR_NAMES, ICON_STYLES, TYPE_SCALES, contrast, resolveColor, themeTokens } from "./theme.js";
import { checkTemplate, isLink } from "./screens.js";

/** Every theme, in the order a gallery shows them; the first is the default for new stores. */
export const THEME_IDS = [
  "studio", "ember-street", "midnight-drip", "pop-tee", "fandom-fest", "silver-bloom", "solitaire", "temple-silk",
  "loom-story", "craft-bazaar", "monsoon-kurta", "deep-rest", "cloud-nine", "hearth", "bold-pout", "leaf-dew",
  "rose-edit", "sharp-edge", "carry-on", "clear-view",
];
export const DEFAULT_THEME = THEME_IDS[0];
/** The screens every theme sets. */
export const THEME_SCREENS = ["home", "product", "collection", "cart", "onboarding"];
/** The settings sections a theme sets: its look and its navigation, never a store's keys, checkout or delivery. */
export const THEME_SETTINGS = ["brand", "appearance", "navigation", "announcement", "home", "collection"];

/** The theme `id`, read from contract/themes/<id>.json; throws for an id that isn't one. */
export function loadTheme(id) {
  if (!THEME_IDS.includes(id)) throw new Error(`"${id}" isn't a theme. Themes: ${THEME_IDS.join(", ")}`);
  return JSON.parse(readFileSync(new URL(`./themes/${id}.json`, import.meta.url), "utf8"));
}

/** Every theme, in gallery order. */
export const themes = () => THEME_IDS.map(loadTheme);

const HEX = /^#[0-9A-F]{6}$/;
const isObject = (v) => !!v && typeof v === "object" && !Array.isArray(v);
const TAB_IDS = ["home", "shop", "search", "wishlist", "cart", "account"];
const TAB_ICONS = ["home", "grid", "search", "heart", "bag", "person", "star", "tag", "menu"];

/**
 * Throws naming the first problem: the fields and tokens are what Krypton's settings take, every screen passes
 * checkTemplate unchanged, and every pair of colours a theme puts together reads (text 4.5:1, bars and sections 3:1)
 * in light, and in dark too unless the theme is light only.
 */
export function checkTheme(theme) {
  const fail = (why) => { throw new Error(`${theme?.id}: ${why}`); };
  if (!isObject(theme) || !/^[a-z][a-z0-9-]{1,30}$/.test(theme.id ?? "")) fail("needs an id");
  for (const key of ["name", "vertical", "description"]) if (typeof theme[key] !== "string" || !theme[key].trim() || theme[key].length > 160) fail(`needs a ${key}`);
  if (theme.plan !== "free" && theme.plan !== "paid") fail("plan is free or paid");
  const s = theme.settings;
  if (!isObject(s) || Object.keys(s).some((k) => !THEME_SETTINGS.includes(k))) fail(`settings take ${THEME_SETTINGS.join(", ")}`);

  const a = s.appearance;
  if (!HEX.test(s.brand?.accent ?? "")) fail("brand.accent is a #RRGGBB");
  for (const key of ["background", "text", "secondary"]) if (!HEX.test(a?.colors?.[key] ?? "")) fail(`appearance.colors.${key} is a #RRGGBB`);
  if (!(a.corners in CORNERS) || !(a.buttons in BUTTONS) || !(a.type?.scale in TYPE_SCALES) || !ICON_STYLES.includes(a.icons)) fail("corners, buttons, type.scale and icons are the theme's");
  if (!["", "light", "dark"].includes(a.mode)) fail(`appearance.mode is "", light or dark`);
  for (const role of ["heading", "body"]) {
    const font = a.fonts?.[role];
    const files = Object.entries(font?.files ?? {});
    if (typeof font?.family !== "string" || !files.length || files.length > 4) fail(`appearance.fonts.${role} is a Google font with its files`);
    for (const [weight, url] of files) if (!/^[1-9]00$/.test(weight) || !/^https:\/\/fonts\.gstatic\.com\/\S+\.ttf$/.test(url)) fail(`appearance.fonts.${role} has a file that isn't a Google font`);
  }
  if (!["fashion", "beauty", "grocery", "b2b"].includes(s.home?.template) || !["top", "bottom"].includes(s.collection?.template)) fail("home and collection templates");

  const colour = (value, at, empty = true) => {
    if ((empty && value === "") || COLOR_NAMES.includes(value) || HEX.test(value ?? "")) return;
    fail(`${at} is a theme colour or #RRGGBB`);
  };
  const n = s.navigation;
  if (!Array.isArray(n?.tabs) || n.tabs.length < 2 || n.tabs.length > 5 || n.tabs[0].id !== "home") fail("2 to 5 tabs, Home first");
  for (const tab of n.tabs) if (!TAB_IDS.includes(tab.id) || !TAB_ICONS.includes(tab.icon) || !tab.title || tab.title.length > 16) fail(`tab ${tab.id}`);
  if (!["standard", "centered_logo", "search"].includes(n.topBar?.style)) fail("navigation.topBar.style");
  for (const key of ["background", "foreground"]) colour(n.topBar[key], `navigation.topBar.${key}`);
  for (const key of ["background", "active", "inactive"]) colour(n.tabBar?.[key], `navigation.tabBar.${key}`);
  const ann = s.announcement;
  if (!Array.isArray(ann?.messages) || !ann.messages.length || ann.messages.length > 5) fail("announcement messages");
  for (const m of ann.messages) if (!m.text || m.text.length > 120 || !isLink(m.link)) fail("an announcement message");
  colour(ann.background, "announcement.background");
  colour(ann.color, "announcement.color");

  if (!isObject(theme.screens) || Object.keys(theme.screens).sort().join() !== [...THEME_SCREENS].sort().join()) fail(`screens are ${THEME_SCREENS.join(", ")}`);
  for (const [handle, template] of Object.entries(theme.screens)) {
    let checked;
    try { checked = checkTemplate(template, handle); } catch (err) { fail(`screens.${handle}: ${err.message}`); }
    if (JSON.stringify(checked) !== JSON.stringify(template)) fail(`screens.${handle} isn't as checkTemplate keeps it`);
    // demo-safe: nothing from one store
    if (/gid:\/\/shopify\//.test(JSON.stringify(template))) fail(`screens.${handle} names a store's product or collection`);
  }

  const appearance = { accent: s.brand.accent, ...a.colors, corners: a.corners, buttons: a.buttons, scale: a.type.scale, icons: a.icons };
  for (const dark of a.mode === "light" ? [false] : a.mode === "dark" ? [true] : [false, true]) {
    const t = themeTokens(appearance, dark);
    const reads = (fg, bg, min, at) => {
      const [f, b] = [resolveColor(fg, t), resolveColor(bg, t)];
      if (f && b && contrast(f, b) < min) fail(`${at} reads ${contrast(f, b).toFixed(2)}:1 in ${dark ? "dark" : "light"}, under ${min}:1`);
    };
    reads("text", "background", 4.5, "text on background");
    reads("accent", "background", 1.3, "the accent on the background");
    reads(ann.color, ann.background, 4.5, "the announcement");
    reads(n.topBar.foreground || "text", n.topBar.background || "background", 4.5, "the top bar");
    reads(n.tabBar.active || "accent", n.tabBar.background || "background", 3, "the active tab");
    for (const [handle, template] of Object.entries(theme.screens)) {
      for (const section of template.sections) {
        const { background, text_color: fg, image } = section.settings ?? {};
        // words over a picture sit on the picture, not the colour
        if (background && fg && !image) reads(fg, background, 3, `screens.${handle} ${section.id}`);
      }
    }
  }
  return theme;
}
