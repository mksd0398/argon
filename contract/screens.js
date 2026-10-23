// Screens v2 (docs/superpowers/specs/2026-10-19-screens-v2-design.md): every screen is an `app_screen` metaobject
// whose `template` is JSON, a list of sections. This file is the catalogue as data — the section types, their
// settings and defaults — plus the checks an editor (Krypton's builder) runs before saving. The apps decode the same
// JSON leniently on their own; this is the strict side.

/** The metaobject each screen is: its handle is the screen. */
export const APP_SCREEN_DEFINITION = {
  type: "app_screen",
  name: "App screen",
  displayNameKey: "title",
  access: { storefront: "PUBLIC_READ" },
  fieldDefinitions: [
    { key: "title", name: "Title", type: "single_line_text_field", required: true },
    { key: "template", name: "Template", type: "json", required: true, description: "The screen's sections, edited in Krypton or by hand (see Argon's screens v2 spec)." },
  ],
};

/**
 * Built-in screens: whether sections may go above and below the screen's own content (its `main` section). `only`: the
 * one section type the screen takes, and that only it takes.
 */
export const SYSTEM_SCREENS = {
  // the first-launch welcome (2026-10-23-theme-and-onboarding-design.md)
  onboarding: { main: false, only: "onboarding" },
  home: { main: false },
  product: { main: true, above: true, below: true },
  collection: { main: true, above: true, below: false },
  search: { main: true, above: true, below: false },
  cart: { main: true, above: true, below: true },
  account: { main: true, above: true, below: true },
  orders: { main: true, above: true, below: true },
  wishlist: { main: true, above: true, below: true },
};

export const PRODUCT_BLOCKS = ["gallery", "title", "price", "options", "purchase", "bundle", "details", "reviews", "rails"];

const s = (key, type, extra = {}) => ({ key, type, ...extra });
const choice = (key, choices, value) => s(key, "choice", { choices, default: value });
const HEIGHTS = ["small", "medium", "large"];
/** The icons a feature block can show: Argon's icon set (ArgonIconName / ArgonIcon), snake_case. */
export const FEATURE_ICONS = ["truck", "returns", "lock", "leaf", "gift", "clock", "star", "heart", "globe", "check", "tag", "phone", "mail", "location", "info"];
/** Every section type but the welcome also takes these: a colour drawn behind it, and room above and below inside that colour. */
const STYLE_SETTINGS = [s("background", "color"), choice("padding", ["none", "small", "medium", "large"], undefined)];

/** Section types: their settings (type, default, limits) and the blocks they take. */
export const SECTION_TYPES = {
  banner: {
    name: "Banner",
    settings: [
      s("image", "image"), s("heading", "text"), s("text", "text"), s("button_label", "text"), s("link", "link"),
      choice("style", ["hero", "card"], "hero"), choice("height", HEIGHTS, "large"), s("text_color", "color", { default: "#FFFFFF" }),
    ],
  },
  slideshow: {
    name: "Slideshow",
    settings: [s("autoplay", "boolean", { default: true }), s("interval", "number", { min: 3, max: 15, default: 5 }), choice("height", HEIGHTS, "large")],
    blocks: { slide: { name: "Slide", settings: [s("image", "image"), s("heading", "text"), s("text", "text"), s("button_label", "text"), s("link", "link")] } },
    maxBlocks: 10,
  },
  products: {
    name: "Products",
    settings: [
      s("heading", "text"), s("collection", "collection"), s("products", "products"),
      choice("style", ["carousel", "grid"], "carousel"), s("limit", "number", { min: 1, max: 24, default: 8 }), s("show_all", "boolean", { default: true }),
    ],
  },
  collections: {
    name: "Collections",
    settings: [s("heading", "text"), s("collections", "collections"), choice("style", ["circles", "grid", "list"], "circles")],
  },
  rich_text: {
    name: "Rich text",
    settings: [s("heading", "text"), s("text", "richtext"), choice("alignment", ["start", "center"], "start")],
  },
  image_with_text: {
    name: "Image with text",
    settings: [
      s("image", "image"), s("heading", "text"), s("text", "richtext"), s("button_label", "text"), s("link", "link"),
      choice("image_position", ["start", "end"], "start"),
    ],
  },
  video: {
    name: "Video",
    settings: [
      s("url", "url"), s("poster", "image"), s("autoplay", "boolean", { default: true }), s("loop", "boolean", { default: true }),
      s("muted", "boolean", { default: true }), choice("aspect", ["16:9", "9:16", "1:1", "4:5"], "16:9"),
    ],
  },
  countdown: {
    name: "Countdown",
    settings: [s("heading", "text"), s("text", "text"), s("ends_at", "datetime"), s("link", "link"), s("hide_when_over", "boolean", { default: true })],
  },
  spacer: {
    name: "Spacer",
    settings: [s("height", "number", { min: 4, max: 120, default: 24 }), s("divider", "boolean", { default: false })],
  },
  custom: {
    name: "Custom HTML",
    settings: [s("html", "html"), choice("render", ["native", "web"], "web"), s("nodes", "nodes"), s("height", "number", { min: 0, max: 2000, default: 0 })],
  },
  marquee: {
    name: "Scrolling text",
    settings: [s("text", "text"), s("link", "link"), choice("speed", ["slow", "medium", "fast"], "medium"), s("text_color", "color", { default: "#FFFFFF" })],
  },
  faq: {
    name: "FAQ",
    settings: [s("heading", "text")],
    blocks: { question: { name: "Question", settings: [s("question", "text"), s("answer", "richtext")] } },
    maxBlocks: 20,
  },
  features: {
    name: "Features",
    settings: [s("heading", "text"), choice("layout", ["row", "grid"], "row")],
    blocks: { feature: { name: "Feature", settings: [choice("icon", FEATURE_ICONS, "check"), s("heading", "text"), s("text", "text")] } },
    maxBlocks: 8,
  },
  onboarding: {
    name: "Welcome pages",
    settings: [s("enabled", "boolean", { default: true })],
    blocks: {
      page: {
        name: "Page",
        settings: [
          s("image", "image"), s("video", "url"), s("heading", "text", { max: 60 }), s("text", "text", { max: 200 }),
          s("button_label", "text", { max: 24 }),
        ],
      },
    },
    maxBlocks: 5,
  },
  image_grid: {
    name: "Image grid",
    settings: [s("heading", "text"), choice("columns", ["2", "3"], "2"), choice("aspect", ["square", "portrait", "landscape"], "square")],
    blocks: { tile: { name: "Tile", settings: [s("image", "image"), s("heading", "text"), s("link", "link")] } },
    maxBlocks: 12,
  },
};
for (const [key, type] of Object.entries(SECTION_TYPES)) if (key !== "onboarding") type.settings.push(...STYLE_SETTINGS);
/** The screen a section type is only for (its `only`); null: any screen but those. */
const onlyOn = (type) => Object.keys(SYSTEM_SCREENS).find((screen) => SYSTEM_SCREENS[screen].only === type) ?? null;

/**
 * A template's `screen`: how the screen itself looks. `top_bar` and `top_bar_tint` are for screens drawn wholly from
 * sections (home and custom pages): `transparent` lays the bar over the first section, solid once that scrolls under
 * it; `top_bar_tint` is the clear bar's title and icons (light over dark images). `background` is any screen's.
 */
export const SCREEN_SETTINGS = [
  choice("top_bar", ["solid", "transparent"], undefined), choice("top_bar_tint", ["light", "dark"], "light"), s("background", "color"),
];

const MAIN_SETTINGS = {
  product: [s("blocks", "product_blocks")],
  collection: [choice("filters", ["top", "bottom"], undefined)],
};

// ─── Checking a template (the editor's side) ──────────────────────────────

export class TemplateError extends Error {}

const LIMITS = { text: 1000, richtext: 10_000, html: 50_000, url: 2000 };
const GID = (kind) => new RegExp(`^gid://shopify/${kind}/\\d+$`);
const ID = /^[a-z0-9_-]{1,40}$/;
const isObject = (v) => !!v && typeof v === "object" && !Array.isArray(v);

/** A link the apps can follow: a store path, an app screen, or an https URL. */
export function isLink(value) {
  if (typeof value !== "string" || value.length > 2000) return false;
  if (value === "") return true;
  if (/^\/[^\s]*$/.test(value)) return true;
  if (/^app:\/\/screens\/[a-z0-9-]{1,100}$/.test(value)) return true;
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
}

const NODE_TYPES = ["heading", "paragraph", "list", "image", "button", "divider", "product", "collection"];

function checkRuns(runs, at) {
  if (!Array.isArray(runs)) throw new TemplateError(`${at}: runs must be a list`);
  for (const [i, run] of runs.entries()) {
    if (!isObject(run) || typeof run.text !== "string") throw new TemplateError(`${at}.${i}: a run needs text`);
    if (run.link !== undefined && !isLink(run.link)) throw new TemplateError(`${at}.${i}: bad link`);
  }
}

function checkNodes(nodes, at) {
  if (!Array.isArray(nodes) || nodes.length > 200) throw new TemplateError(`${at}: up to 200 nodes`);
  for (const [i, node] of nodes.entries()) {
    const here = `${at}.${i}`;
    if (!isObject(node) || !NODE_TYPES.includes(node.type)) throw new TemplateError(`${here}: unknown node`);
    if (node.type === "paragraph") checkRuns(node.runs, `${here}.runs`);
    if (node.type === "list") (node.items ?? []).forEach((item, j) => checkRuns(item, `${here}.items.${j}`));
    if (["button", "image"].includes(node.type) && node.link !== undefined && !isLink(node.link)) throw new TemplateError(`${here}: bad link`);
    if (node.type === "image" && (typeof node.url !== "string" || !/^https:\/\//.test(node.url))) throw new TemplateError(`${here}: an image needs an https url`);
    if (node.type === "product" && !GID("Product").test(node.id ?? "")) throw new TemplateError(`${here}: bad product`);
    if (node.type === "collection" && !GID("Collection").test(node.id ?? "")) throw new TemplateError(`${here}: bad collection`);
  }
}

/** One setting's value, checked; throws naming it. Returns the value to store (undefined: leave it out). */
function checkValue(setting, value, at) {
  if (value === undefined || value === null) return undefined;
  const fail = (why) => new TemplateError(`${at}: ${why}`);
  switch (setting.type) {
    case "text": case "richtext": case "html": case "url":
      if (typeof value !== "string") throw fail("must be text");
      if (value.length > (setting.max ?? LIMITS[setting.type])) throw fail(`is longer than ${setting.max ?? LIMITS[setting.type]} characters`);
      if (setting.type === "url" && value && !/^https:\/\/\S+$/.test(value)) throw fail("must be an https link");
      return value;
    case "image":
      if (!isObject(value) || typeof value.url !== "string" || !/^https:\/\//.test(value.url)) throw fail("must be an image with an https url");
      return { url: value.url, alt: typeof value.alt === "string" ? value.alt.slice(0, 500) : "", width: Number(value.width) || 0, height: Number(value.height) || 0 };
    case "link":
      if (!isLink(value)) throw fail("must be a store path, app://screens/<handle> or an https link");
      return value;
    case "product": case "collection":
      if (!GID(setting.type === "product" ? "Product" : "Collection").test(value)) throw fail(`must be a ${setting.type}`);
      return value;
    case "products": case "collections": {
      const kind = setting.type === "products" ? "Product" : "Collection";
      if (!Array.isArray(value) || value.length > 24 || !value.every((id) => GID(kind).test(id))) throw fail(`must be up to 24 ${setting.type}`);
      return [...new Set(value)];
    }
    case "number":
      if (typeof value !== "number" || !Number.isFinite(value)) throw fail("must be a number");
      if (value < setting.min || value > setting.max) throw fail(`must be from ${setting.min} to ${setting.max}`);
      return value;
    case "boolean":
      if (typeof value !== "boolean") throw fail("must be true or false");
      return value;
    case "color":
      if (typeof value !== "string" || !/^#[0-9a-fA-F]{6}$/.test(value)) throw fail("must be a colour like #1F6FEB");
      return value.toUpperCase();
    case "choice":
      if (!setting.choices.includes(value)) throw fail(`must be one of ${setting.choices.join(", ")}`);
      return value;
    case "datetime":
      if (typeof value !== "string" || Number.isNaN(Date.parse(value))) throw fail("must be a date and time");
      return new Date(value).toISOString();
    case "nodes":
      checkNodes(value, at);
      return value;
    case "product_blocks": {
      if (!Array.isArray(value)) throw fail("must be a list");
      const seen = new Set();
      return value.map((block, i) => {
        if (!isObject(block) || !PRODUCT_BLOCKS.includes(block.type) || seen.has(block.type)) throw fail(`${i}: unknown or repeated block`);
        seen.add(block.type);
        return block.hidden ? { type: block.type, hidden: true } : { type: block.type };
      });
    }
    default:
      throw fail("can't be set");
  }
}

function checkSettings(definitions, given, at) {
  if (given === undefined) return {};
  if (!isObject(given)) throw new TemplateError(`${at}: settings must be an object`);
  const out = {};
  for (const [key, value] of Object.entries(given)) {
    const setting = definitions.find((d) => d.key === key);
    if (!setting) throw new TemplateError(`${at}.${key}: unknown setting`);
    const checked = checkValue(setting, value, `${at}.${key}`);
    if (checked !== undefined) out[key] = checked;
  }
  return out;
}

/**
 * The template for `screen` (a SYSTEM_SCREENS key, or a custom page's handle), checked: unknown section types and
 * settings refused, values checked, ids unique, exactly one `main` on a screen that has one (added at the end when
 * missing). `metafields` is recomputed from the Liquid. Throws TemplateError naming the first problem.
 */
export function checkTemplate(template, screen) {
  if (!isObject(template) || !Array.isArray(template.sections)) throw new TemplateError("The template must have a list of sections");
  if (template.sections.length > 50) throw new TemplateError("A screen takes up to 50 sections");
  const system = SYSTEM_SCREENS[screen];
  const ids = new Set();
  let mains = 0;
  const sections = template.sections.map((section, index) => {
    const at = `sections.${index}`;
    if (!isObject(section)) throw new TemplateError(`${at}: must be an object`);
    if (typeof section.id !== "string" || !ID.test(section.id) || ids.has(section.id)) throw new TemplateError(`${at}: needs a unique id (a-z, 0-9, _ and -)`);
    ids.add(section.id);
    const out = { id: section.id, type: section.type };
    if (section.type === "main") {
      if (!system?.main) throw new TemplateError(`${at}: this screen has no main section`);
      mains += 1;
      out.settings = checkSettings(MAIN_SETTINGS[screen] ?? [], section.settings, `${at}.settings`);
      return out;
    }
    const type = SECTION_TYPES[section.type];
    if (!type) throw new TemplateError(`${at}: unknown section type "${section.type}"`);
    if (onlyOn(section.type) !== (system?.only ? screen : null)) throw new TemplateError(`${at}: the ${screen} screen doesn't take ${type.name} sections`);
    out.settings = checkSettings(type.settings, section.settings, `${at}.settings`);
    if (section.blocks !== undefined) {
      if (!type.blocks || !Array.isArray(section.blocks) || section.blocks.length > (type.maxBlocks ?? 0)) throw new TemplateError(`${at}.blocks: not allowed here, or too many`);
      const blockIds = new Set();
      out.blocks = section.blocks.map((block, j) => {
        const where = `${at}.blocks.${j}`;
        if (!isObject(block) || !type.blocks[block.type]) throw new TemplateError(`${where}: unknown block`);
        if (typeof block.id !== "string" || !ID.test(block.id) || blockIds.has(block.id)) throw new TemplateError(`${where}: needs a unique id`);
        blockIds.add(block.id);
        return { id: block.id, type: block.type, settings: checkSettings(type.blocks[block.type].settings, block.settings, `${where}.settings`) };
      });
    }
    if (section.platforms !== undefined) {
      if (!Array.isArray(section.platforms) || !section.platforms.length || !section.platforms.every((p) => p === "ios" || p === "android")) throw new TemplateError(`${at}.platforms: ios, android or both`);
      if (section.platforms.length === 1) out.platforms = [...section.platforms];
    }
    if (section.track !== undefined) {
      if (typeof section.track !== "string" || !/^[a-z0-9_]{1,40}$/.test(section.track)) throw new TemplateError(`${at}.track: a-z, 0-9 and _, up to 40`);
      out.track = section.track;
    }
    if (section.hidden === true) out.hidden = true;
    return out;
  });
  if (mains > 1) throw new TemplateError("A screen has one main section");
  if (system?.only && sections.length > 1) throw new TemplateError(`The ${screen} screen has one section`);
  if (system?.main && !mains) sections.push({ id: "main", type: "main", settings: {} });
  if (system?.main) {
    const main = sections.findIndex((x) => x.type === "main");
    if (!system.below && main !== sections.length - 1) throw new TemplateError(`Nothing can go below the ${screen} screen's own content`);
    if (!system.above && main !== 0) throw new TemplateError(`Nothing can go above the ${screen} screen's own content`);
  }
  const checked = { version: 2, sections };
  if (template.screen !== undefined) {
    const look = checkSettings(SCREEN_SETTINGS, template.screen, "screen");
    if ((system?.main || system?.only) && ("top_bar" in look || "top_bar_tint" in look)) {
      throw new TemplateError(`screen: the ${screen} screen keeps its own top bar; top_bar is for home and your pages`);
    }
    if (Object.keys(look).length) checked.screen = look;
  }
  const refs = metafieldRefs(checked);
  if (refs.length) checked.metafields = refs;
  return checked;
}

// ─── Liquid's metafields ──────────────────────────────────────────────────

const METAFIELD = /\b(product|collection|shop)\.metafields\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)/g;

/** Every `owner.metafields.namespace.key` the template's text reads, sorted, without repeats. */
export function metafieldRefs(template) {
  const found = new Set();
  const visit = (value) => {
    if (typeof value === "string") for (const m of value.matchAll(METAFIELD)) found.add(`${m[1]}.${m[2]}.${m[3]}`);
    else if (Array.isArray(value)) value.forEach(visit);
    else if (isObject(value)) Object.values(value).forEach(visit);
  };
  visit(template.sections);
  return [...found].sort();
}

/** A new section of `type` with its defaults, for an editor's "Add section". */
export function newSection(type, id) {
  const definition = SECTION_TYPES[type];
  if (!definition) throw new TemplateError(`unknown section type "${type}"`);
  const settings = Object.fromEntries(definition.settings.filter((x) => x.default !== undefined).map((x) => [x.key, x.default]));
  return { id, type, settings, ...(definition.blocks ? { blocks: [] } : {}) };
}
