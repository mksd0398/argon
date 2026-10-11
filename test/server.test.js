import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash, createHmac } from "node:crypto";
import { readFileSync } from "node:fs";
import worker, { validSignature, ga4Purchase, metaPurchase } from "../templates/server/worker.js";

// An order placed in the Android app, in the shape of Shopify's orders/create webhook: 2 shirts, a tote and a custom
// line (150.00), a 10% code (-15.00), 10.80 tax and 10.00 shipping on top: 155.80
const RAW = readFileSync(new URL("./fixtures/orders-create.json", import.meta.url), "utf8");
const ORDER = JSON.parse(RAW);
const PLACED = Date.parse("2026-10-11T13:30:00Z"); // the order's created_at
const SECRET = "webhook-secret";
const ENV = {
  SHOPIFY_WEBHOOK_SECRET: SECRET,
  GA4_API_SECRET: "ga-secret", GA4_FIREBASE_APP_ID_ANDROID: "1:1234:android:abcd", GA4_FIREBASE_APP_ID_IOS: "1:1234:ios:ef01",
  META_DATASET_ID: "998877", META_ACCESS_TOKEN: "meta-token",
};
const GOOGLE = "www.google-analytics.com", META = "graph.facebook.com";

// Node's own HMAC and hash, to check the Worker's Web Crypto against
const sign = (body, secret = SECRET) => createHmac("sha256", secret).update(body).digest("base64");
const sha256 = (text) => createHash("sha256").update(text).digest("hex");
const json = (value) => JSON.parse(JSON.stringify(value)); // as it is sent: a key without a value is left out
const changed = (change) => {
  const order = structuredClone(ORDER);
  change(order);
  return order;
};
const without = (...names) => changed((order) => (order.note_attributes = order.note_attributes.filter((note) => !names.includes(note.name))));
const withNote = (name, value) => changed((order) => (order.note_attributes.find((note) => note.name === name).value = value));
const omit = (object, ...keys) => Object.fromEntries(Object.entries(object).filter(([key]) => !keys.includes(key)));

/**
 * Delivers `body` to the Worker the way Shopify does. No request leaves the machine: fetch is replaced, and answers
 * 204 unless `answers` has a function for the host. Returns the Worker's status, what it sent and what it logged.
 */
async function deliver({ body = RAW, signature = sign(body), env = ENV, answers = {}, method = "POST", path = "/webhooks/orders" } = {}) {
  const sent = [], logged = [], realFetch = globalThis.fetch, realError = console.error;
  globalThis.fetch = async (url, init) => {
    sent.push({ host: new URL(url).host, url, method: init.method, type: init.headers["Content-Type"], body: JSON.parse(init.body) });
    return answers[new URL(url).host]?.() ?? new Response(null, { status: 204 });
  };
  console.error = (line) => logged.push(line);
  try {
    const headers = signature === null ? {} : { "X-Shopify-Hmac-Sha256": signature };
    const request = new Request(`https://argon-purchases.example.workers.dev${path}`, { method, headers, body: method === "POST" ? body : undefined });
    const response = await worker.fetch(request, env);
    return { status: response.status, sent, logged };
  } finally {
    globalThis.fetch = realFetch;
    console.error = realError;
  }
}

const GA4_BODY = {
  app_instance_id: "6f2c1d7e9a8b4c3d5e6f7a8b9c0d1e2f",
  timestamp_micros: PLACED * 1000,
  events: [{
    name: "purchase",
    params: {
      transaction_id: "6183412097110",
      currency: "USD",
      value: 135, // the total without tax and shipping
      tax: 10.8,
      shipping: 10,
      coupon: "WELCOME10",
      items: [
        { item_id: "8123456789012", item_name: "Linen Shirt", item_variant: "Blue / M", item_brand: "Argon Supply", price: 60, quantity: 2 },
        { item_id: "8123456789099", item_name: "Canvas Tote", item_brand: "Argon Supply", price: 25, quantity: 1 },
        { item_name: "Gift wrap", price: 5, quantity: 1 }, // a custom line has no product
      ],
    },
  }],
};
const META_BODY = {
  data: [{
    event_name: "Purchase",
    event_time: PLACED / 1000,
    event_id: "purchase-6183412097110",
    action_source: "app",
    user_data: {
      em: [sha256("asha.rao@example.com")],
      ph: [sha256("919876543210")],
      external_id: [sha256("7412589630123")],
      anon_id: "XZ6f1a2b3c-4d5e-6f70-8192-a3b4c5d6e7f8",
      client_ip_address: "203.0.113.24",
      client_user_agent: ORDER.client_details.user_agent,
    },
    custom_data: {
      currency: "USD",
      value: 155.8,
      order_id: "6183412097110",
      content_type: "product",
      content_ids: ["8123456789012", "8123456789099"],
      contents: [{ id: "8123456789012", quantity: 2, item_price: 60 }, { id: "8123456789099", quantity: 1, item_price: 25 }],
    },
    app_data: {
      advertiser_tracking_enabled: 1,
      application_tracking_enabled: 1,
      extinfo: ["a2", "com.argon.demo", "1", "1.0", "16", "Pixel 9", "en_IN", "IST", "Jio", "1080", "2424", "2.63", "8", "128", "64", "Asia/Kolkata"],
    },
  }],
};

test("validSignature: the base64 HMAC-SHA256 of the raw body under the secret, and nothing else", async () => {
  const body = Buffer.from(RAW);
  assert.equal(await validSignature(body, sign(RAW), SECRET), true);
  assert.equal(await validSignature(new TextEncoder().encode(RAW).buffer, sign(RAW), SECRET), true, "an ArrayBuffer, as the Worker reads it");
  assert.equal(await validSignature(body, sign(RAW, "another-secret"), SECRET), false);
  assert.equal(await validSignature(Buffer.from(RAW.replace("155.80", "155.81")), sign(RAW), SECRET), false, "a body changed after signing");
  assert.equal(await validSignature(body, createHmac("sha256", SECRET).update(RAW).digest("hex"), SECRET), false, "hex is not what Shopify sends");
  assert.equal(await validSignature(body, sign(RAW).slice(0, -4), SECRET), false, "a shortened signature");
  for (const signature of ["not base64 !!", "", null, undefined]) assert.equal(await validSignature(body, signature, SECRET), false);
  for (const secret of ["", undefined]) assert.equal(await validSignature(body, sign(RAW, ""), secret), false, "no secret set: nothing is valid");
});

test("a call that Shopify didn't sign gets 401 and nothing is sent; any other address gets 404", async () => {
  for (const signature of [sign(RAW, "another-secret"), "nonsense", null]) {
    assert.deepEqual(await deliver({ signature }), { status: 401, sent: [], logged: [] });
  }
  assert.equal((await deliver({ signature: sign(RAW + " ") })).status, 401, "the signature of another body");
  assert.equal((await deliver({ env: omit(ENV, "SHOPIFY_WEBHOOK_SECRET") })).status, 401, "the Worker has no secret yet");
  assert.deepEqual(await deliver({ path: "/" }), { status: 404, sent: [], logged: [] });
  assert.deepEqual(await deliver({ method: "GET" }), { status: 404, sent: [], logged: [] });
  assert.deepEqual(await deliver({ body: "<order><id>1</id></order>" }), { status: 400, sent: [], logged: [] }, "a webhook created with the XML format");
});

test("an order that wasn't placed in the app gets 200 and is not forwarded", async () => {
  for (const order of [without("_argon_platform"), changed((o) => (o.note_attributes = [])), omit(ORDER, "note_attributes")]) {
    assert.deepEqual(await deliver({ body: JSON.stringify(order) }), { status: 200, sent: [], logged: [] });
  }
});

test("ga4Purchase: a Measurement Protocol purchase for the app's stream, with the order's numeric id as transaction_id", () => {
  const { url, body } = ga4Purchase(ORDER, ENV);
  assert.equal(url.split("?")[0], `https://${GOOGLE}/mp/collect`);
  assert.deepEqual(Object.fromEntries(new URL(url).searchParams), { api_secret: "ga-secret", firebase_app_id: "1:1234:android:abcd" });
  assert.deepEqual(json(body), GA4_BODY);

  // an order from the iOS app goes to the iOS app's stream; a stream's own secret is used when it is set
  const ios = withNote("_argon_platform", "ios");
  assert.equal(new URL(ga4Purchase(ios, ENV).url).searchParams.get("firebase_app_id"), "1:1234:ios:ef01");
  const ownSecrets = { ...ENV, GA4_API_SECRET_IOS: "ios-secret" };
  assert.equal(new URL(ga4Purchase(ios, ownSecrets).url).searchParams.get("api_secret"), "ios-secret");
  assert.equal(new URL(ga4Purchase(ORDER, ownSecrets).url).searchParams.get("api_secret"), "ga-secret");
  assert.equal(new URL(ga4Purchase(ios, omit(ownSecrets, "GA4_API_SECRET")).url).searchParams.get("api_secret"), "ios-secret");

  // no discount code: no coupon. Prices that include tax: the value is still without it
  assert.equal("coupon" in json(ga4Purchase(changed((o) => (o.discount_codes = [])), ENV).body).events[0].params, false);
  const inclusive = changed((o) => Object.assign(o, { taxes_included: true, subtotal_price: "135.00", total_tax: "20.59", total_price: "145.00" }));
  assert.equal(ga4Purchase(inclusive, ENV).body.events[0].params.value, 114.41);
});

test("metaPurchase: a Conversions API app event with the id purchase-<order id>, the customer hashed", async () => {
  const { url, body } = await metaPurchase(ORDER, ENV);
  assert.equal(url, `https://${META}/v26.0/998877/events?access_token=meta-token`);
  assert.deepEqual(json(body), META_BODY);
  assert.equal(JSON.stringify(body).toLowerCase().includes("asha"), false, "no email as it is");
  assert.equal(JSON.stringify(body).includes("9876543210"), false, "no phone as it is");

  // the phone is hashed as digits with the country code: no symbols, no leading zeros
  const phone = await metaPurchase(changed((o) => (o.phone = "00 91 (98765) 43-210")), ENV);
  assert.deepEqual(phone.body.data[0].user_data.ph, [sha256("919876543210")]);
  // a guest order without a phone: what is missing is left out, not sent empty
  const guest = json((await metaPurchase(changed((o) => Object.assign(o, { phone: null, customer: null, client_details: null })), ENV)).body);
  assert.deepEqual(guest.data[0].user_data, { em: [sha256("asha.rao@example.com")], anon_id: "XZ6f1a2b3c-4d5e-6f70-8192-a3b4c5d6e7f8" });
  // the device's tracking setting off: Meta is told so
  const limited = await metaPurchase(withNote("_meta_tracking", "0"), ENV);
  assert.deepEqual(omit(limited.body.data[0].app_data, "extinfo"), { advertiser_tracking_enabled: 0, application_tracking_enabled: 1 });
});

test("the Worker posts both purchases as JSON and answers 200", async () => {
  const { status, sent, logged } = await deliver();
  assert.equal(status, 200);
  assert.deepEqual(logged, []);
  assert.deepEqual(sent.map(({ host, method, type }) => [host, method, type]), [[GOOGLE, "POST", "application/json"], [META, "POST", "application/json"]]);
  assert.deepEqual(sent.map((request) => request.body), [GA4_BODY, META_BODY]);
  assert.equal(sent[0].url, ga4Purchase(ORDER, ENV).url);
});

test("a provider without its secrets, or without its ids on the order, is skipped", async () => {
  const hosts = async (options) => {
    const { status, sent } = await deliver(options);
    assert.equal(status, 200);
    return sent.map((request) => request.host);
  };
  assert.deepEqual(await hosts({ env: omit(ENV, "GA4_API_SECRET") }), [META]);
  assert.deepEqual(await hosts({ env: omit(ENV, "GA4_FIREBASE_APP_ID_ANDROID") }), [META], "the order is from the Android app");
  assert.deepEqual(await hosts({ env: omit(ENV, "GA4_FIREBASE_APP_ID_IOS") }), [GOOGLE, META]);
  assert.deepEqual(await hosts({ env: omit(ENV, "META_ACCESS_TOKEN") }), [GOOGLE]);
  assert.deepEqual(await hosts({ env: omit(ENV, "META_DATASET_ID") }), [GOOGLE]);
  assert.deepEqual(await hosts({ env: { SHOPIFY_WEBHOOK_SECRET: SECRET } }), []);
  // an app without Firebase sends no instance id, one without Meta's SDK no device details
  assert.deepEqual(await hosts({ body: JSON.stringify(without("_ga_app_instance_id")) }), [META]);
  assert.deepEqual(await hosts({ body: JSON.stringify(without("_meta_extinfo")) }), [GOOGLE]);
  assert.equal(ga4Purchase(without("_ga_app_instance_id"), ENV), null);
  assert.equal(await metaPurchase(without("_meta_extinfo"), ENV), null);
  assert.equal(await metaPurchase(withNote("_meta_extinfo", "not json"), ENV), null);
});

test("a provider that fails gives 500, so Shopify sends the order again; the failure is logged without a secret", async () => {
  const refused = () => new Response('{"error":{"message":"Invalid OAuth access token"}}', { status: 400 });
  const down = () => {
    throw new Error("network down");
  };
  const metaOnly = omit(ENV, "GA4_API_SECRET");
  const failed = await deliver({ env: metaOnly, answers: { [META]: refused } });
  assert.equal(failed.status, 500);
  assert.deepEqual(failed.logged, ['Meta: HTTP 400 {"error":{"message":"Invalid OAuth access token"}}']);
  assert.deepEqual(await deliver({ env: metaOnly, answers: { [META]: down } }), { status: 500, sent: failed.sent, logged: ["Meta: network down"] });

  // Google Analytics failed: Meta, which took the purchase, counts the repeat once
  const google = await deliver({ answers: { [GOOGLE]: () => new Response("", { status: 503 }) } });
  assert.deepEqual([google.status, google.sent.length, google.logged], [500, 2, ["Google Analytics: HTTP 503 "]]);
  assert.equal((await deliver({ answers: { [GOOGLE]: down, [META]: refused } })).status, 500);

  // Google Analytics took it and Meta didn't: 200, because Google Analytics would count a repeat (it only
  // de-duplicates purchases on web streams). Meta's failure is still logged
  const meta = await deliver({ answers: { [META]: refused } });
  assert.deepEqual([meta.status, meta.sent.length, meta.logged.length], [200, 2, 1]);

  for (const { logged } of [failed, google, meta]) assert.equal(/ga-secret|meta-token|webhook-secret/.test(logged.join()), false);
});
