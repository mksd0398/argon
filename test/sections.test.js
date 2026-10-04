import { test } from "node:test";
import assert from "node:assert/strict";
import { SECTION_DEFINITIONS, screenDefinition, buildSeed } from "../contract/sections.js";

const keys = (d) => d.fieldDefinitions.map((f) => f.key);
const field = (d, key) => d.fieldDefinitions.find((f) => f.key === key);
const val = (d, key, name) => field(d, key).validations.find((v) => v.name === name).value;
const byType = Object.fromEntries(SECTION_DEFINITIONS.map((d) => [d.type, d]));
const fields = (o) => Object.fromEntries(o.fields.map((f) => [f.key, f.value]));

test("section definitions match the spec table", () => {
  assert.deepEqual(SECTION_DEFINITIONS.map((d) => d.type), ["mobile_banner", "mobile_products", "mobile_collections"]);
  assert.deepEqual(keys(byType.mobile_banner), ["image", "heading", "text", "button_label", "link", "style"]);
  assert.deepEqual(keys(byType.mobile_products), ["heading", "collection", "products", "style", "limit"]);
  assert.deepEqual(keys(byType.mobile_collections), ["heading", "collections"]);
  for (const d of [...SECTION_DEFINITIONS, screenDefinition([])]) {
    assert.deepEqual(d.access, { storefront: "PUBLIC_READ" });
    assert.equal(d.capabilities, undefined);
    assert.ok(d.name);
    assert.ok(d.fieldDefinitions.every((f) => f.key && f.name && f.type));
  }
  assert.deepEqual(SECTION_DEFINITIONS.map((d) => d.displayNameKey), ["heading", "heading", "heading"]);
});

test("field types and validations use the exact Admin API strings", () => {
  const { mobile_banner: b, mobile_products: p, mobile_collections: c } = byType;
  assert.equal(field(b, "image").type, "file_reference");
  assert.equal(val(b, "image", "file_type_options"), '["Image"]');
  assert.equal(field(b, "text").type, "multi_line_text_field");
  assert.equal(val(b, "style", "choices"), '["hero","card"]');
  assert.match(field(b, "link").description, /\/collections\/sale/);
  assert.equal(field(p, "collection").type, "collection_reference");
  assert.equal(field(p, "products").type, "list.product_reference");
  assert.equal(val(p, "style", "choices"), '["carousel","grid"]');
  assert.equal(field(p, "limit").type, "number_integer");
  assert.equal(val(p, "limit", "min"), "1");
  assert.equal(val(p, "limit", "max"), "24");
  assert.equal(field(c, "collections").type, "list.collection_reference");
  assert.equal(field(c, "collections").required, true);
});

test("screenDefinition references the section definition ids", () => {
  const ids = ["gid://shopify/MetaobjectDefinition/1", "gid://shopify/MetaobjectDefinition/2"];
  const d = screenDefinition(ids);
  assert.equal(d.type, "mobile_screen");
  assert.equal(d.displayNameKey, "title");
  assert.deepEqual(keys(d), ["title", "sections"]);
  assert.equal(field(d, "title").required, true);
  assert.equal(field(d, "sections").type, "list.mixed_reference");
  assert.equal(field(d, "sections").required, true);
  assert.equal(val(d, "sections", "metaobject_definition_ids"), JSON.stringify(ids));
});

test("buildSeed with 8 collections (2 empty)", () => {
  const collections = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => ({ id: `gid://shopify/Collection/${i}`, productsCount: i === 0 || i === 3 ? 0 : 5 }));
  const { sections } = buildSeed({ shopName: "Nalli", collections });
  assert.deepEqual(sections.map((s) => [s.type, s.handle]), [
    ["mobile_banner", "home-hero"],
    ["mobile_collections", "home-collections"],
    ["mobile_products", "home-featured"],
  ]);
  const [hero, cols, featured] = sections.map(fields);
  assert.deepEqual(hero, {
    heading: "Nalli",
    text: "Add an image and edit this banner in Content → Metaobjects → Mobile banner.",
    style: "hero",
  });
  assert.equal(cols.heading, "Shop by collection");
  assert.equal(cols.collections, JSON.stringify([1, 2, 4, 5, 6, 7].map((i) => `gid://shopify/Collection/${i}`)));
  assert.deepEqual(featured, {
    heading: "Featured",
    collection: "gid://shopify/Collection/1",
    style: "carousel",
    limit: "8",
  });
});

test("buildSeed caps collections at 6 and handles no non-empty collections", () => {
  const many = Array.from({ length: 9 }, (_, i) => ({ id: `c${i}`, productsCount: 1 }));
  assert.equal(JSON.parse(fields(buildSeed({ shopName: "S", collections: many }).sections[1]).collections).length, 6);
  const none = buildSeed({ shopName: "S", collections: [{ id: "c0", productsCount: 0 }] });
  assert.deepEqual(none.sections.map((s) => s.type), ["mobile_banner"]);
});

test("seed screen(ids) is the home entry", () => {
  const ids = ["gid://shopify/Metaobject/1", "gid://shopify/Metaobject/2"];
  const s = buildSeed({ shopName: "S", collections: [] }).screen(ids);
  assert.equal(s.type, "mobile_screen");
  assert.equal(s.handle, "home");
  assert.deepEqual(fields(s), { title: "Home", sections: JSON.stringify(ids) });
});
