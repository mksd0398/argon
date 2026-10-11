import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { resolveDocument, loadContract } from "../lib/contract.js";

const CONTRACT = fileURLToPath(new URL("../contract/", import.meta.url));

const fragments = new Map([
  ["Image", "fragment Image on Image { url }"],
  ["Money", "fragment Money on MoneyV2 { amount }"],
  ["ProductCard", "fragment ProductCard on Product { featuredImage { ...Image } price { ...Money } }"],
  ["CollectionCard", "fragment CollectionCard on Collection { image { ...Image } }"],
  ["Unused", "fragment Unused on Product { id }"],
]);
const count = (text, needle) => text.split(needle).length - 1;

test("resolveDocument: nested fragments once each, in first-use order", () => {
  const doc = resolveDocument(
    "query Q { a { ...ProductCard } b { ...ProductCard ...Image ... on Product { id } } }",
    fragments,
  );
  assert.equal(count(doc, "fragment ProductCard on"), 1);
  assert.equal(count(doc, "fragment Image on"), 1);
  assert.equal(count(doc, "fragment Money on"), 1);
  assert.ok(doc.indexOf("fragment ProductCard") < doc.indexOf("fragment Image"));
  assert.ok(doc.indexOf("fragment Image") < doc.indexOf("fragment Money"));
});

test("resolveDocument: omits unused fragments and leaves inline fragments alone", () => {
  const doc = resolveDocument("query Q { a { ... on Product { ...Money } } }", fragments);
  assert.match(doc, /fragment Money on/);
  assert.doesNotMatch(doc, /fragment (Image|ProductCard|CollectionCard|Unused) on/);
});

test("loadContract: 55 documents, operation name equals key, fragments resolved from the document's own API", async () => {
  const contract = await loadContract();
  assert.equal(contract.size, 55);
  const customer = new Set(readdirSync(join(CONTRACT, "customer")).map((f) => f.replace(/\.graphql$/, "")));
  const definedIn = (file) => new Set([...readFileSync(join(CONTRACT, file), "utf8").matchAll(/^fragment (\w+) on /gm)].map((m) => m[1]));
  const fragments = { storefront: definedIn("fragments.graphql"), customer: definedIn("customer/fragments.graphql") };
  for (const [name, doc] of contract) {
    assert.equal(doc.match(/^\s*(?:query|mutation)\s+(\w+)/m)?.[1], name);
    // every spread has a definition and every definition appears once
    for (const [, used] of doc.matchAll(/\.\.\.\s*([A-Z]\w*)/g)) assert.match(doc, new RegExp(`fragment ${used} on `));
    for (const [, def] of doc.matchAll(/^fragment (\w+) on /gm)) {
      assert.equal(count(doc, `fragment ${def} on `), 1, `${name}/${def}`);
      assert.ok(fragments[customer.has(name) ? "customer" : "storefront"].has(def), `${name}/${def} comes from its own API's fragments`);
    }
  }
});

test("loadContract: an operation name used by both APIs is an error", async () => {
  const dir = mkdtempSync(join(tmpdir(), "argon-contract-"));
  try {
    for (const folder of ["queries", "customer"]) {
      mkdirSync(join(dir, folder));
      writeFileSync(join(dir, folder, "Shop.graphql"), "query Shop { shop { id } }");
    }
    writeFileSync(join(dir, "fragments.graphql"), "");
    writeFileSync(join(dir, "customer", "fragments.graphql"), "");
    await assert.rejects(loadContract(dir), /Duplicate contract operation Shop \(customer\/Shop.graphql\)/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// Lists cut to 3 items and long text (policy and description HTML) to 300 characters, so recorded fixtures stay small
const trim = (v) =>
  Array.isArray(v) ? v.slice(0, 3).map(trim)
  : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, trim(x)]))
  : typeof v === "string" && v.length > 300 ? `${v.slice(0, 300)}…`
  : v;

// Live: POST every Storefront document to the public tokenless mock.shop (ARGON_LIVE=1, see `npm run test:live`).
// ARGON_RECORD=1 also rewrites contract/fixtures/<Operation>.json from the responses; `record: false` marks the ones
// mock.shop has no data for (or refuses), whose fixtures are hand-written.
test("live: Storefront documents run against mock.shop", { skip: !process.env.ARGON_LIVE, timeout: 180_000 }, async () => {
  const contract = await loadContract();
  const covered = new Set();
  const call = async (name, variables = {}, { record = true, userErrors = false } = {}) => {
    covered.add(name);
    const res = await fetch("https://mock.shop/api/2026-10/graphql.json", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: contract.get(name), variables, operationName: name }),
    });
    const json = await res.json();
    assert.equal(json.errors, undefined, `${name}: ${JSON.stringify(json.errors)}`);
    if (!userErrors) for (const v of Object.values(json.data)) assert.deepEqual(v?.userErrors ?? [], [], `${name} userErrors`);
    if (record && process.env.ARGON_RECORD) writeFileSync(join(CONTRACT, "fixtures", `${name}.json`), JSON.stringify(trim(json.data), null, 2) + "\n");
    return json.data;
  };

  assert.ok((await call("Shop")).shop.name);
  assert.ok((await call("Shop", { country: "CA", language: "FR" }, { record: false })).shop.name, "@inContext with values");
  await call("Localization");
  await call("ShopPolicies");
  await call("Menu", { handle: "main-menu" });
  // mock.shop has no metaobjects, locations or pickup availability
  assert.equal((await call("HomeScreen", { handle: "home" }, { record: false })).metaobject, null);
  await call("Metaobject", { type: "mobile_screen", handle: "home" }, { record: false });
  await call("Metaobjects", { type: "mobile_screen", first: 2 }, { record: false });
  await call("Locations", { first: 2 }, { record: false });
  const home = await call("FallbackHome");
  const products = home.collections.nodes.flatMap((c) => c.products.nodes);
  assert.ok(products.length > 0);
  await call("Collections", { first: 3 });
  // hand-written from here on where mock.shop has no data for what the apps decode: filters with swatches, a card with
  // swatches and a rating, a bundle variant with volume pricing
  await call("Collection", { handle: "men", first: 4 }, { record: false });
  await call("Catalog", { first: 4, query: "shirt", sortKey: "PRICE", reverse: true });
  await call("Search", { query: "shirt", first: 4, types: ["PRODUCT", "ARTICLE", "PAGE"] });
  await call("PredictiveSearch", { query: "shirt" });
  await call("Products", { ids: products.slice(0, 3).map((p) => p.id) }, { record: false });
  // men-crewneck: the product the v0.1 app tests expect (Size and Color, first variant Small / Green); both metafields unset
  const metafields = [{ namespace: "custom", key: "material" }, { namespace: "custom", key: "care" }];
  const { product } = await call("Product", { handle: "men-crewneck" });
  await call("ProductMetafields", { handle: product.handle, metafields }, { record: false }); // mock.shop has neither set
  const [variant, other] = product.variants.nodes;
  await call("VariantBySelectedOptions", { handle: product.handle, selectedOptions: other.selectedOptions }, { record: false });
  await call("ProductRecommendations", { productId: product.id, intent: "RELATED" });
  await call("StoreAvailability", { variantId: variant.id, first: 2 }, { record: false });

  const { pages } = await call("Pages", { first: 3 });
  await call("Page", { handle: pages.nodes[0].handle });
  const { blogs } = await call("Blogs", { first: 3 });
  await call("Blog", { handle: blogs.nodes[0].handle, first: 3 });
  const { articles } = await call("Articles", { first: 3 });
  await call("Article", { blogHandle: articles.nodes[0].blog.handle, articleHandle: articles.nodes[0].handle });

  // cart chain; the cart is read once it holds 3 items (the v0.1 app tests expect that)
  const merchandiseId = variant.id;
  const { cartCreate } = await call("CartCreate", { input: { lines: [{ merchandiseId, quantity: 1 }] } });
  const cartId = cartCreate.cart.id;
  const { cartLinesAdd } = await call("CartLinesAdd", { cartId, lines: [{ merchandiseId, quantity: 1 }] });
  const lineId = cartLinesAdd.cart.lines.nodes[0].id;
  await call("CartLinesUpdate", { cartId, lines: [{ id: lineId, quantity: 3 }] });
  await call("CartNoteUpdate", { cartId, note: "Gift wrap, please" });
  await call("CartAttributesUpdate", { cartId, attributes: [{ key: "source", value: "app" }] });
  await call("CartDiscountCodesUpdate", { cartId, discountCodes: ["WELCOME10"] }); // unknown code: a cart warning
  await call("CartBuyerIdentityUpdate", { cartId, buyerIdentity: { countryCode: "CA" } });
  // not recorded: the fixture also carries an automatic discount and a compare-at price, which mock.shop has no data for
  assert.equal((await call("Cart", { id: cartId }, { record: false })).cart.totalQuantity, 3);
  await call("CartGiftCardCodesAdd", { cartId, giftCardCodes: ["ABCD1234EFGH5678"] });
  await call("CartGiftCardCodesRemove", { cartId, appliedGiftCardIds: ["gid://shopify/AppliedGiftCard/1"] });
  // mock.shop answers the delivery mutations with a "not supported" user error (its carts never reach checkout)
  const address = { address1: "150 Elgin St", city: "Ottawa", provinceCode: "ON", zip: "K2P 1L4", countryCode: "CA" };
  const unsupported = { record: false, userErrors: true };
  await call("CartDeliveryAddressesAdd", { cartId, addresses: [{ address: { deliveryAddress: address }, selected: true }] }, unsupported);
  const addressId = "gid://shopify/CartSelectableAddress/1";
  await call("CartDeliveryAddressesUpdate", { cartId, addresses: [{ id: addressId, selected: true }] }, unsupported);
  await call("CartDeliveryAddressesRemove", { cartId, addressIds: [addressId] }, unsupported);
  await call("CartLinesRemove", { cartId, lineIds: [lineId] });

  // Not run: the Customer Account documents (they need a signed-in customer's token), and
  const skipped = ["CartSelectedDeliveryOptionsUpdate"]; // needs a cart delivery group: mock.shop carts get none (no addresses)
  const customer = readdirSync(join(CONTRACT, "customer")).map((f) => f.replace(/\.graphql$/, ""));
  assert.deepEqual([...covered].sort(), [...contract.keys()].filter((k) => !customer.includes(k) && !skipped.includes(k)).sort());
});
