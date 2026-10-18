// Offline checks of every contract document against the vendored 2026-10 schemas (test/schema/, from
// @shopify/hydrogen@2026.10.0; sha256 in docs/superpowers/specs/2026-10-09-api-catalog-research.md).
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import {
  buildClientSchema, executeSync, getNamedType, isAbstractType, isEnumType, isInputObjectType, isListType, isNonNullType,
  Kind, NoDeprecatedCustomRule, parse, print, specifiedRules, TypeInfo, typeFromAST, validate, visit, visitWithTypeInfo,
} from "graphql";
import { loadContract } from "../lib/contract.js";

const CONTRACT = new URL("../contract/", import.meta.url);
// assumeValid: Shopify's own schema breaks a graphql 17 schema rule (a deprecated field implementing a live interface field)
const schema = (file) =>
  buildClientSchema(JSON.parse(readFileSync(new URL(`schema/${file}`, import.meta.url), "utf8")), { assumeValid: true });
const storefront = schema("storefront-2026-10.json");
const customerAccount = schema("customer-account-2026-10.json");

const docs = [...(await loadContract())].map(([name, text]) => {
  const ast = parse(text);
  const customer = existsSync(new URL(`customer/${name}.graphql`, CONTRACT));
  return { name, ast, customer, schema: customer ? customerAccount : storefront, op: ast.definitions.find((d) => d.kind === Kind.OPERATION_DEFINITION) };
});

test("every document validates against its API's 2026-10 schema and selects no deprecated field", () => {
  assert.equal(docs.filter((d) => !d.customer).length, 45);
  assert.equal(docs.filter((d) => d.customer).length, 14);
  const errors = docs.flatMap((d) => validate(d.schema, d.ast, [...specifiedRules, NoDeprecatedCustomRule]).map((e) => `${d.name}: ${e.message}`));
  assert.deepEqual(errors, []);
});

// Customer Account fields Hydrogen's schema has but shopify.dev's public 2026-10 reference doesn't: the live API refuses
// a third-party client's whole query over any of them ("Field ... doesn't exist on type ...").
const HYDROGEN_ONLY = [
  "Order.latestFulfillmentDeliveryDate", "Order.lineItemsSummary",
  "Return.decline", "Return.timelineEvents", "Return.tmpReturnLineItemsCount",
  "OrderNonReturnableSummary.summaryMessage",
];

test("no Customer Account document selects a field public clients don't get", () => {
  const found = [];
  for (const d of docs.filter((d) => d.customer)) {
    const info = new TypeInfo(d.schema);
    visit(d.ast, visitWithTypeInfo(info, {
      Field(node) {
        const field = `${info.getParentType()?.name}.${node.name.value}`;
        if (HYDROGEN_ONLY.includes(field)) found.push(`${d.name}: ${field}`);
      },
    }));
  }
  assert.deepEqual(found, []);
});

test("every Storefront operation takes $country, $language and $buyer and runs @inContext with them", () => {
  for (const { name, op } of docs.filter((d) => !d.customer)) {
    const vars = Object.fromEntries((op.variableDefinitions ?? []).map((v) => [v.variable.name.value, print(v.type)]));
    assert.equal(vars.country, "CountryCode", name);
    assert.equal(vars.language, "LanguageCode", name);
    assert.equal(vars.buyer, "BuyerInput", name);
    assert.deepEqual((op.directives ?? []).map(print), ["@inContext(country: $country, language: $language, buyer: $buyer)"], name);
  }
});

test("every polymorphic selection selects __typename", () => {
  const missing = [];
  for (const d of docs) {
    const fragments = Object.fromEntries(d.ast.definitions.filter((f) => f.kind === Kind.FRAGMENT_DEFINITION).map((f) => [f.name.value, f]));
    const typenamed = (set) => set.selections.some((s) =>
      s.kind === Kind.FIELD ? s.name.value === "__typename" : typenamed(s.kind === Kind.FRAGMENT_SPREAD ? fragments[s.name.value].selectionSet : s.selectionSet));
    const info = new TypeInfo(d.schema);
    visit(d.ast, visitWithTypeInfo(info, {
      Field(node) {
        if (node.selectionSet && isAbstractType(getNamedType(info.getType())) && !typenamed(node.selectionSet)) missing.push(`${d.name}: ${node.name.value}`);
      },
    }));
  }
  assert.deepEqual(missing, []);
});

test("every cart mutation selects userErrors { field message code } and warnings { code message target }", () => {
  const carts = docs.filter((d) => d.op.operation === "mutation" && !d.customer);
  assert.equal(carts.length, 14);
  for (const { name, op } of carts) {
    const payload = op.selectionSet.selections[0].selectionSet.selections.map(print);
    assert.ok(payload.includes("userErrors {\n  ...CartUserError\n}") && payload.includes("warnings {\n  ...CartWarning\n}"), name);
  }
  const fragments = readFileSync(new URL("fragments.graphql", CONTRACT), "utf8");
  assert.ok(fragments.includes("fragment CartUserError on CartUserError { field message code }"));
  assert.ok(fragments.includes("fragment CartWarning on CartWarning { code message target }"));
});

// Variables a document needs to execute at all (resolvers ignore arguments): the smallest value of each required type.
function sample(type) {
  if (isNonNullType(type)) return sample(type.ofType);
  if (isListType(type)) return [];
  if (isInputObjectType(type)) {
    return Object.fromEntries(Object.values(type.getFields()).filter((f) => isNonNullType(f.type)).map((f) => [f.name, sample(f.type)]));
  }
  if (isEnumType(type)) return type.getValues()[0].name;
  return { Int: 1, Float: 1, Boolean: true }[type.name] ?? "1";
}

// Executing the document over the fixture returns the fixture unchanged only if the fixture
// has exactly the selected fields, non-null where the schema says so, valid enum values, and __typename on abstract types.
test("every operation has a fixture, shaped exactly like its document's response", () => {
  // JudgeMeReviews.json is Judge.me's answer, not an operation's
  const fixtures = readdirSync(new URL("fixtures/", CONTRACT)).filter((f) => f.endsWith(".json") && !f.startsWith("JudgeMe")).map((f) => f.slice(0, -".json".length));
  assert.deepEqual(fixtures.sort(), docs.map((d) => d.name).sort());
  for (const { name, ast, op, schema } of docs) {
    const data = JSON.parse(readFileSync(new URL(`fixtures/${name}.json`, CONTRACT), "utf8"));
    assert.deepEqual(Object.keys(data).sort(), op.selectionSet.selections.map((s) => (s.alias ?? s.name).value).sort(), `${name}: root fields`);
    const variableValues = Object.fromEntries(
      (op.variableDefinitions ?? []).filter((v) => v.type.kind === Kind.NON_NULL_TYPE).map((v) => [v.variable.name.value, sample(typeFromAST(schema, v.type))]),
    );
    // by response key, so an aliased field (firstVariant: selectedOrFirstAvailableVariant) reads the fixture's alias
    const fieldResolver = (source, _args, _context, info) => source[info.path.key];
    const result = executeSync({ schema, document: ast, rootValue: data, variableValues, fieldResolver });
    assert.deepEqual(result.errors?.map((e) => `${e.message} (${e.path?.join(".")})`) ?? [], [], name);
    assert.deepEqual(JSON.parse(JSON.stringify(result.data)), data, `${name}: fixture fields differ from the document's selection`);
  }
});
