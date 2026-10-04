import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveDocument, loadContract } from "../lib/contract.js";

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

test("loadContract: 17 documents, operation name equals key, fragments resolved", async () => {
  const contract = await loadContract();
  assert.equal(contract.size, 17);
  for (const [name, doc] of contract) {
    assert.equal(doc.match(/^\s*(?:query|mutation)\s+(\w+)/m)?.[1], name);
    // every spread has a definition and every definition appears once
    for (const [, used] of doc.matchAll(/\.\.\.\s*([A-Z]\w*)/g)) assert.match(doc, new RegExp(`fragment ${used} on `));
    for (const [, def] of doc.matchAll(/^fragment (\w+) on /gm)) assert.equal(count(doc, `fragment ${def} on `), 1, `${name}/${def}`);
  }
  // Customer Account documents must not pull in Storefront fragments
  for (const name of ["Customer", "Order"]) assert.doesNotMatch(contract.get(name), /^fragment /m);
});

// Live: POST every Storefront document to the public tokenless mock.shop (ARGON_LIVE=1, see `npm run test:live`)
test("live: Storefront documents run against mock.shop", { skip: !process.env.ARGON_LIVE, timeout: 120_000 }, async () => {
  const contract = await loadContract();
  const covered = new Set();
  const call = async (name, variables = {}) => {
    covered.add(name);
    const res = await fetch("https://mock.shop/api/2026-10/graphql.json", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: contract.get(name), variables, operationName: name }),
    });
    const json = await res.json();
    assert.equal(json.errors, undefined, `${name}: ${JSON.stringify(json.errors)}`);
    for (const v of Object.values(json.data)) assert.deepEqual(v?.userErrors ?? [], [], `${name} userErrors`);
    return json.data;
  };

  assert.ok((await call("Shop")).shop.name);
  assert.equal((await call("HomeScreen", { handle: "home" })).metaobject, null);
  const home = await call("FallbackHome");
  const products = home.collections.nodes.flatMap((c) => c.products.nodes);
  assert.ok(products.length > 0);
  await call("Menu", { handle: "main-menu" });
  await call("Collection", { handle: "men", first: 4 });
  await call("Search", { query: "shirt", first: 4 });
  await call("PredictiveSearch", { query: "shirt" });
  await call("Products", { ids: products.slice(0, 3).map((p) => p.id) });
  const { product } = await call("Product", { handle: products[0].handle, metafields: [] });
  const merchandiseId = product.variants.nodes[0].id;

  // cart chain: create -> read -> add -> update -> remove
  const { cartCreate } = await call("CartCreate", { input: { lines: [{ merchandiseId, quantity: 1 }] } });
  const cartId = cartCreate.cart.id;
  await call("Cart", { id: cartId });
  const { cartLinesAdd } = await call("CartLinesAdd", { cartId, lines: [{ merchandiseId, quantity: 1 }] });
  const lineId = cartLinesAdd.cart.lines.nodes[0].id;
  await call("CartLinesUpdate", { cartId, lines: [{ id: lineId, quantity: 3 }] });
  await call("CartLinesRemove", { cartId, lineIds: [lineId] });
  await call("CartBuyerIdentityUpdate", { cartId, buyerIdentity: { countryCode: "US" } });

  // Customer and Order target the Customer Account API and need a customer token: not run here
  assert.deepEqual([...covered].sort(), [...contract.keys()].filter((k) => !["Customer", "Order"].includes(k)).sort());
});
