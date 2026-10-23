import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { APP_SCREEN_DEFINITION, SECTION_TYPES, SYSTEM_SCREENS, checkTemplate, isLink, metafieldRefs, newSection, TemplateError } from "../contract/screens.js";

const fixture = (name) => JSON.parse(readFileSync(new URL(`../contract/fixtures/screens/${name}.json`, import.meta.url), "utf8"));
const fails = (template, screen, message) =>
  assert.throws(() => checkTemplate(template, screen), (err) => err instanceof TemplateError && message.test(err.message));
const one = (section, screen = "home") => checkTemplate({ sections: [section] }, screen).sections[0];

test("the app_screen definition: a title and a JSON template, readable by the apps", () => {
  assert.equal(APP_SCREEN_DEFINITION.type, "app_screen");
  assert.deepEqual(APP_SCREEN_DEFINITION.access, { storefront: "PUBLIC_READ" });
  assert.deepEqual(APP_SCREEN_DEFINITION.fieldDefinitions.map((f) => [f.key, f.type, f.required]),
    [["title", "single_line_text_field", true], ["template", "json", true]]);
});

test("the catalogue matches the spec", () => {
  assert.deepEqual(Object.keys(SECTION_TYPES),
    ["banner", "slideshow", "products", "collections", "rich_text", "image_with_text", "video", "countdown", "spacer", "custom", "marquee", "faq", "features", "onboarding", "image_grid"]);
  assert.deepEqual(Object.keys(SYSTEM_SCREENS), ["onboarding", "home", "product", "collection", "search", "cart", "account", "orders", "wishlist"]);
  for (const type of Object.values(SECTION_TYPES)) {
    for (const setting of type.settings) if (setting.type === "choice") assert.ok(setting.choices.length >= 2);
  }
});

test("the sample templates: product and about are valid; home's unknown and bad sections are refused", () => {
  const product = fixture("product");
  product.sections.find((s) => s.type === "main").settings.blocks = [{ type: "gallery" }, { type: "reviews", hidden: true }];
  const checked = checkTemplate(product, "product");
  assert.deepEqual(checked.metafields, ["product.custom.fabric"]);
  assert.deepEqual(checked.sections.find((s) => s.type === "main").settings.blocks, [{ type: "gallery" }, { type: "reviews", hidden: true }]);
  // the sample product lists an unknown PDP block (for the apps' lenient decoding); an editor refuses it
  fails(fixture("product"), "product", /unknown or repeated block/);

  const about = fixture("about");
  about.sections[0].settings.nodes = about.sections[0].settings.nodes.filter((n) => n.type !== "marquee");
  assert.equal(checkTemplate(about, "about").sections.length, 3);
  fails(fixture("about"), "about", /unknown node/);

  fails(fixture("home"), "home", /unknown section type "hologram"/);
  const home = fixture("home");
  home.sections = home.sections.filter((s) => !["future", "bad"].includes(s.id));
  assert.deepEqual(checkTemplate(home, "home").metafields, ["shop.custom.promo"]);
});

test("values are checked and normalised", () => {
  assert.equal(one({ id: "a", type: "banner", settings: { text_color: "#abcdef" } }).settings.text_color, "#ABCDEF");
  assert.deepEqual(one({ id: "a", type: "products", settings: { products: ["gid://shopify/Product/1", "gid://shopify/Product/1"] } }).settings.products,
    ["gid://shopify/Product/1"]);
  assert.equal(one({ id: "a", type: "countdown", settings: { ends_at: "2030-01-01T05:30:00+05:30" } }).settings.ends_at, "2030-01-01T00:00:00.000Z");
  assert.equal(one({ id: "a", type: "banner", platforms: ["ios", "android"] }).platforms, undefined, "both is the default");
  assert.deepEqual(one({ id: "a", type: "banner", platforms: ["ios"], track: "hero_1", hidden: true }),
    { id: "a", type: "banner", settings: {}, platforms: ["ios"], track: "hero_1", hidden: true });
  fails({ sections: [{ id: "a", type: "banner", settings: { style: "giant" } }] }, "home", /one of hero, card/);
  fails({ sections: [{ id: "a", type: "banner", settings: { colour: "red" } }] }, "home", /unknown setting/);
  fails({ sections: [{ id: "a", type: "banner", settings: { image: { url: "http://x" } } }] }, "home", /https/);
  fails({ sections: [{ id: "a", type: "banner", settings: { link: "javascript:alert(1)" } }] }, "home", /store path/);
  fails({ sections: [{ id: "a", type: "products", settings: { limit: 99 } }] }, "home", /from 1 to 24/);
  fails({ sections: [{ id: "a", type: "products", settings: { products: ["gid://shopify/Collection/1"] } }] }, "home", /products/);
  fails({ sections: [{ id: "A B", type: "banner" }] }, "home", /unique id/);
  fails({ sections: [{ id: "a", type: "banner" }, { id: "a", type: "spacer" }] }, "home", /unique id/);
  fails({ sections: [{ id: "a", type: "banner", blocks: [] }] }, "home", /not allowed/);
  fails({ sections: [{ id: "a", type: "slideshow", blocks: [{ id: "x", type: "video" }] }] }, "home", /unknown block/);
  fails({ sections: [{ id: "a", type: "spacer", track: "Bad Name" }] }, "home", /track/);
});

test("main sections: one, on system screens only, where the screen allows", () => {
  assert.deepEqual(checkTemplate({ sections: [{ id: "a", type: "spacer" }] }, "product").sections.map((s) => s.type), ["spacer", "main"],
    "a missing main goes at the end");
  fails({ sections: [{ id: "m", type: "main" }] }, "home", /no main/);
  fails({ sections: [{ id: "m", type: "main" }] }, "about", /no main/);
  fails({ sections: [{ id: "m", type: "main" }, { id: "n", type: "main" }] }, "cart", /one main/);
  fails({ sections: [{ id: "m", type: "main" }, { id: "a", type: "spacer" }] }, "collection", /below the collection/);
  const collection = checkTemplate({ sections: [{ id: "a", type: "spacer" }, { id: "m", type: "main", settings: { filters: "bottom" } }] }, "collection");
  assert.equal(collection.sections[1].settings.filters, "bottom");
  fails({ sections: [{ id: "m", type: "main", settings: { blocks: [{ type: "gallery" }, { type: "gallery" }] } }] }, "product", /repeated/);
});

test("links the apps can follow", () => {
  for (const ok of ["", "/collections/sale", "/products/x?variant=1", "/pages/about", "/search?q=boots", "/cart", "app://screens/size-guide", "https://example.com/a"]) {
    assert.ok(isLink(ok), ok);
  }
  for (const bad of ["javascript:alert(1)", "http://example.com", "app://screens/Bad Handle", "ftp://x", "collections/sale", 42]) {
    assert.ok(!isLink(bad), String(bad));
  }
});

test("metafield references come from every text in the template", () => {
  const refs = metafieldRefs({ sections: [
    { settings: { heading: "{{ product.metafields.custom.fabric }}", text: "{% if collection.metafields.seo.hidden %}x{% endif %} {{ shop.metafields.custom.promo }} {{ product.metafields.custom.fabric }}" } },
    { blocks: [{ settings: { heading: "{{ customer.metafields.a.b }} {{ product.metafields.my-ns.size_chart }}" } }] },
  ] });
  assert.deepEqual(refs, ["collection.seo.hidden", "product.custom.fabric", "product.my-ns.size_chart", "shop.custom.promo"]);
});

test("new sections start from their defaults", () => {
  assert.deepEqual(newSection("products", "p1"), { id: "p1", type: "products", settings: { style: "carousel", limit: 8, show_all: true } });
  assert.deepEqual(newSection("slideshow", "s1").blocks, []);
  assert.throws(() => newSection("hologram", "x"), TemplateError);
});

test("AppScreen's fixture carries the sample home template", () => {
  const data = JSON.parse(readFileSync(new URL("../contract/fixtures/AppScreen.json", import.meta.url), "utf8"));
  assert.deepEqual(JSON.parse(data.metaobject.template.value), fixture("home"));
});

test("detailing: every section takes a background and padding; the four new types; the screen's own look", () => {
  for (const type of Object.values(SECTION_TYPES)) if (type !== SECTION_TYPES.onboarding) assert.deepEqual(type.settings.slice(-2).map((x) => x.key), ["background", "padding"]);
  assert.deepEqual(one({ id: "a", type: "spacer", settings: { background: "#f5f0e8", padding: "large" } }).settings, { background: "#F5F0E8", padding: "large" });
  fails({ sections: [{ id: "a", type: "banner", settings: { padding: "huge" } }] }, "home", /one of none/);

  const faq = one({ id: "f", type: "faq", settings: { heading: "Questions" }, blocks: [{ id: "q1", type: "question", settings: { question: "Returns?", answer: "<p>30 days</p>" } }] });
  assert.equal(faq.blocks[0].settings.answer, "<p>30 days</p>");
  assert.equal(one({ id: "g", type: "features", blocks: [{ id: "b", type: "feature", settings: { icon: "truck" } }] }).blocks[0].settings.icon, "truck");
  fails({ sections: [{ id: "g", type: "features", blocks: [{ id: "b", type: "feature", settings: { icon: "rocket" } }] }] }, "home", /one of truck/);
  fails({ sections: [{ id: "g", type: "features", blocks: Array.from({ length: 9 }, (_, i) => ({ id: `b${i}`, type: "feature" })) }] }, "home", /too many/);
  assert.equal(one({ id: "i", type: "image_grid", settings: { columns: "3" }, blocks: [{ id: "t", type: "tile", settings: { link: "/collections/sale" } }] }).settings.columns, "3");
  assert.equal(one({ id: "m", type: "marquee", settings: { text: "Free shipping {{ shop.name }}", speed: "fast" } }).settings.speed, "fast");
  assert.deepEqual(newSection("marquee", "m").settings, { speed: "medium", text_color: "background" });

  assert.deepEqual(checkTemplate({ screen: { top_bar: "transparent", top_bar_tint: "dark", background: "#fafafa" }, sections: [] }, "home").screen,
    { top_bar: "transparent", top_bar_tint: "dark", background: "#FAFAFA" });
  assert.deepEqual(checkTemplate({ screen: { top_bar: "transparent" }, sections: [] }, "lookbook").screen, { top_bar: "transparent" });
  assert.deepEqual(checkTemplate({ screen: { background: "#FFFFFF" }, sections: [] }, "cart").screen, { background: "#FFFFFF" });
  assert.equal(checkTemplate({ screen: {}, sections: [] }, "home").screen, undefined);
  fails({ screen: { top_bar: "transparent" }, sections: [] }, "product", /own top bar/);
  fails({ screen: { top_bar: "glass" }, sections: [] }, "home", /one of solid, transparent/);
  fails({ screen: { blur: true }, sections: [] }, "home", /unknown setting/);
});

test("the onboarding screen: one welcome section of up to 5 pages, which no other screen takes", () => {
  const page = (id, settings) => ({ id, type: "page", settings });
  const welcome = { id: "w", type: "onboarding", settings: { enabled: false }, blocks: [
    page("p1", { heading: "Hi", text: "Fresh every day", button_label: "Next", image: { url: "https://cdn.shopify.com/a.jpg" } }),
    page("p2", { video: "https://cdn.shopify.com/v.mp4" }),
  ] };
  const checked = checkTemplate({ screen: { background: "#101010" }, sections: [welcome] }, "onboarding");
  assert.equal(checked.sections[0].settings.enabled, false);
  assert.deepEqual(checked.sections[0].blocks.map((b) => b.id), ["p1", "p2"]);
  assert.deepEqual(SECTION_TYPES.onboarding.settings.map((x) => x.key), ["enabled"], "no style settings on the welcome");
  fails({ sections: [welcome] }, "home", /doesn't take Welcome pages/);
  fails({ sections: [welcome] }, "about", /doesn't take Welcome pages/);
  fails({ sections: [{ id: "b", type: "banner" }] }, "onboarding", /doesn't take Banner/);
  fails({ sections: [welcome, { ...welcome, id: "w2" }] }, "onboarding", /has one section/);
  fails({ screen: { top_bar: "transparent" }, sections: [] }, "onboarding", /keeps its own top bar/);
  fails({ sections: [{ ...welcome, blocks: [1, 2, 3, 4, 5, 6].map((i) => page("p" + i, {})) }] }, "onboarding", /too many/);
  fails({ sections: [{ ...welcome, blocks: [page("p", { heading: "x".repeat(61) })] }] }, "onboarding", /longer than 60/);
  fails({ sections: [{ ...welcome, blocks: [page("p", { button_label: "x".repeat(25) })] }] }, "onboarding", /longer than 24/);
  fails({ sections: [{ ...welcome, blocks: [page("p", { video: "http://x.test/v.mp4" })] }] }, "onboarding", /https/);
  assert.deepEqual(checkTemplate({ sections: [] }, "onboarding").sections, []);
});

test("a colour setting takes one of the theme's colours by name, or a hex of its own", () => {
  assert.equal(one({ id: "a", type: "spacer", settings: { background: "accent" } }).settings.background, "accent");
  assert.equal(checkTemplate({ screen: { background: "surface" }, sections: [] }, "home").screen.background, "surface");
  fails({ sections: [{ id: "a", type: "spacer", settings: { background: "Accent" } }] }, "home", /theme's: accent, secondary/);
  fails({ sections: [{ id: "a", type: "spacer", settings: { background: "primary" } }] }, "home", /#1F6FEB or one of the theme's/);
});
