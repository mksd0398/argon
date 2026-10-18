import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { Liquid } from "liquidjs";

// contract/fixtures/liquid/cases.json is what Liquid.kt and Liquid.swift must pass. Here liquidjs, Shopify's
// semantics, checks that every expected output is what Liquid really gives. Lenient cases are Argon's own rules for
// what Liquid would refuse (unknown filters and tags, syntax errors), so only the apps check them.
const { context: shared, cases } = JSON.parse(readFileSync(new URL("../contract/fixtures/liquid/cases.json", import.meta.url), "utf8"));

const merge = (base, over) => {
  if (!over) return base;
  const out = { ...base };
  for (const [key, value] of Object.entries(over)) {
    out[key] = value && typeof value === "object" && !Array.isArray(value) ? merge(base[key] ?? {}, value) : value;
  }
  return out;
};

// The filters Shopify adds to Liquid, as Argon defines them (the spec's Liquid section)
const SYMBOLS = { USD: "$", CAD: "$", AUD: "$", NZD: "$", SGD: "$", INR: "₹", EUR: "€", GBP: "£", JPY: "¥" };
const grouped = (value) => {
  const [whole, cents] = (Math.round(Number(value) * 100) / 100).toFixed(2).split(".");
  return `${whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",")}.${cents}`;
};
function engine(currency) {
  const liquid = new Liquid({ timezoneOffset: 0 });
  liquid.registerFilter("money", (v) => (SYMBOLS[currency] ? `${SYMBOLS[currency]}${grouped(v)}` : `${grouped(v)} ${currency}`));
  liquid.registerFilter("money_without_currency", (v) => grouped(v));
  liquid.registerFilter("handleize", (v) => String(v).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""));
  liquid.registerFilter("pluralize", (n, one, many) => (Number(n) === 1 ? one : many));
  // Where liquidjs differs from Shopify's (Ruby) Liquid, Shopify wins: integer division of integers, and escape's
  // entities (CGI.escapeHTML)
  liquid.registerFilter("divided_by", (a, b) =>
    Number.isInteger(Number(a)) && Number.isInteger(Number(b)) && !String(b).includes(".") ? Math.floor(Number(a) / Number(b)) : Number(a) / Number(b));
  liquid.registerFilter("escape", (v) => String(v ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;"));
  return liquid;
}

test("every Liquid case gives its expected output in liquidjs", async () => {
  assert.ok(cases.length >= 60);
  assert.equal(new Set(cases.map((c) => c.name)).size, cases.length, "case names are unique");
  const wrong = [];
  for (const c of cases.filter((c) => !c.lenient)) {
    const context = merge(shared, c.context);
    const out = await engine(context.shop.currency).parseAndRender(c.template, context);
    if (out !== c.expected) wrong.push(`${c.name}: got ${JSON.stringify(out)}, expected ${JSON.stringify(c.expected)}`);
  }
  assert.deepEqual(wrong, []);
});
