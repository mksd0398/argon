/**
 * Argon: reports the app's purchases to Google Analytics 4 and Meta.
 *
 * A Cloudflare Worker, one file, no dependencies (Web APIs only). Shopify calls it with every new order
 * (the orders/create webhook); it sends the purchase to each provider whose secrets are set. The keys that let a
 * server report a sale must never be in an app, which is why this runs here. README.md has the setup.
 */

// Meta retires a Graph API version about two years after its release: https://developers.facebook.com/docs/graph-api/changelog
const GRAPH_VERSION = "v26.0";

const encoder = new TextEncoder();
const sha256 = async (text) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(text)))].map((byte) => byte.toString(16).padStart(2, "0")).join("");

/** Whether `signature` (the X-Shopify-Hmac-Sha256 header, base64) is the HMAC-SHA256 of the raw `body` under `secret`. */
export async function validSignature(body, signature, secret) {
  if (!signature || !secret) return false;
  let bytes;
  try {
    bytes = Uint8Array.from(atob(signature), (ch) => ch.charCodeAt(0));
  } catch {
    return false; // not base64
  }
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  return crypto.subtle.verify("HMAC", key, bytes, body); // verify compares in constant time
}

// What the app put on the cart when it created it: Shopify hands the cart's attributes on as the order's note attributes
const attributes = (order) => Object.fromEntries((order.note_attributes ?? []).map(({ name, value }) => [name, value]));
// The numeric id at the end of a Shopify gid, as text: the ids the apps send
const tail = (gid) => String(gid ?? "").split("/").pop();
const orderId = (order) => tail(order.admin_graphql_api_id) || String(order.id);
const amount = (text) => Number(text ?? 0);
const round = (value) => Math.round(value * 1000) / 1000; // no currency has more than three decimals
// When the order was placed, in milliseconds: Shopify retries a failed delivery for hours
const placed = (order) => Date.parse(order.created_at) || Date.now();
// ponytail: a product id is a JSON number, exact up to 2^53; Shopify's are a thousand times smaller today
const productId = (line) => (line.product_id == null ? undefined : String(line.product_id));

/**
 * The Measurement Protocol request ({ url, body }) for the order's `purchase`, or null when Google Analytics isn't
 * set up for the order's platform or the order has no app instance id. The app puts that id on the cart only when
 * it leaves the purchase to this server (SERVER_PURCHASE=true); otherwise it has reported the purchase itself.
 * https://developers.google.com/analytics/devguides/collection/protocol/ga4/reference?client_type=firebase
 */
export function ga4Purchase(order, env) {
  const notes = attributes(order);
  // Each app is its own data stream in Google Analytics, with its own app id and Measurement Protocol secret
  const platform = String(notes._argon_platform).toUpperCase(); // ANDROID or IOS
  const appId = env[`GA4_FIREBASE_APP_ID_${platform}`];
  const secret = env[`GA4_API_SECRET_${platform}`];
  if (!appId || !secret || !notes._ga_app_instance_id) return null;
  const tax = amount(order.total_tax);
  const shipping = amount(order.total_shipping_price_set?.shop_money?.amount);
  return {
    // ponytail: the global endpoint; a property that keeps its data in the EU uses region1.google-analytics.com
    url: `https://www.google-analytics.com/mp/collect?${new URLSearchParams({ api_secret: secret, firebase_app_id: appId })}`,
    body: {
      app_instance_id: notes._ga_app_instance_id,
      timestamp_micros: placed(order) * 1000,
      events: [{
        name: "purchase",
        params: {
          transaction_id: orderId(order),
          currency: order.currency,
          value: round(amount(order.total_price) - tax - shipping), // Google's value leaves tax and shipping out
          tax,
          shipping,
          coupon: order.discount_codes?.map((discount) => discount.code).join(",") || undefined,
          items: (order.line_items ?? []).map((line) => ({
            item_id: productId(line),
            item_name: line.title,
            item_variant: line.variant_title ?? undefined,
            item_brand: line.vendor ?? undefined,
            price: amount(line.price),
            quantity: line.quantity,
          })),
        },
      }],
    },
  };
}

/**
 * The Conversions API request ({ url, body }) for the order's `Purchase`, or null when Meta isn't set up or the order
 * has no device details (`extinfo`, which Meta requires of an app event).
 * https://developers.facebook.com/docs/marketing-api/conversions-api/app-events
 */
export async function metaPurchase(order, env) {
  const notes = attributes(order);
  let extinfo;
  try {
    extinfo = JSON.parse(notes._meta_extinfo);
  } catch {} // not there
  if (!env.META_DATASET_ID || !env.META_ACCESS_TOKEN || !Array.isArray(extinfo)) return null;
  // Meta takes these three as SHA-256 only: the email trimmed and in lower case, the phone as digits with its country code
  const hashed = async (value) => (value ? [await sha256(value)] : undefined);
  const email = order.email ?? order.customer?.email;
  const phone = order.phone ?? order.customer?.phone;
  const lines = (order.line_items ?? []).filter((line) => line.product_id != null);
  return {
    url: `https://graph.facebook.com/${GRAPH_VERSION}/${env.META_DATASET_ID}/events?${new URLSearchParams({ access_token: env.META_ACCESS_TOKEN })}`,
    body: {
      data: [{
        event_name: "Purchase",
        event_time: Math.floor(placed(order) / 1000),
        event_id: `purchase-${orderId(order)}`, // the app's purchase has the same id: Meta counts the two once
        action_source: "app",
        user_data: {
          em: await hashed(email?.trim().toLowerCase()),
          ph: await hashed(phone?.replace(/\D/g, "").replace(/^0+/, "")),
          external_id: await hashed(tail(order.customer?.admin_graphql_api_id)),
          anon_id: notes._meta_anon_id,
          client_ip_address: order.client_details?.browser_ip ?? undefined,
          client_user_agent: order.client_details?.user_agent ?? undefined,
        },
        custom_data: {
          currency: order.currency,
          value: amount(order.total_price),
          order_id: orderId(order),
          content_type: "product",
          content_ids: lines.map(productId),
          contents: lines.map((line) => ({ id: productId(line), quantity: line.quantity, item_price: amount(line.price) })),
        },
        app_data: {
          // the device's own setting (iOS's tracking prompt, Android's ad id), as the app read it
          advertiser_tracking_enabled: notes._meta_tracking === "1" ? 1 : 0,
          // the app's "Share usage data" switch: it was on, or the order would carry none of the app's attributes
          application_tracking_enabled: 1,
          extinfo,
        },
      }],
    },
  };
}

// Whether the provider took the purchase; null when there is nothing to send it. A failure is logged
// (`wrangler tail` shows it), not thrown
async function send(provider, purchase) {
  if (!purchase) return null;
  const { url, body } = purchase;
  try {
    const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    if (!response.ok) console.error(`${provider}: HTTP ${response.status} ${await response.text()}`);
    return response.ok;
  } catch (err) {
    console.error(`${provider}: ${err.message}`);
    return false;
  }
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST" || new URL(request.url).pathname !== "/webhooks/orders") return new Response("Not found", { status: 404 });
    const body = await request.arrayBuffer();
    if (!(await validSignature(body, request.headers.get("X-Shopify-Hmac-Sha256"), env.SHOPIFY_WEBHOOK_SECRET))) {
      return new Response("Invalid signature", { status: 401 });
    }
    let order;
    try {
      order = JSON.parse(new TextDecoder().decode(body));
    } catch {
      return new Response("The webhook's format must be JSON", { status: 400 });
    }
    // An order from the website: the store's web pixels already report it
    if (!attributes(order)._argon_platform) return new Response("Not an app order");
    // Anything but 200 makes Shopify deliver the order again. Meta counts a repeated purchase once (same event id);
    // Google Analytics does that for web streams only, not for apps (https://support.google.com/analytics/answer/12313109).
    // So Meta goes first and Google last: whichever fails, Google has not taken the purchase when Shopify retries
    const taken = (await send("Meta", await metaPurchase(order, env))) !== false && (await send("Google Analytics", ga4Purchase(order, env))) !== false;
    return taken ? new Response("OK") : new Response("A provider didn't take the purchase", { status: 500 });
  },
};
