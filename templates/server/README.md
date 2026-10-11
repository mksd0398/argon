# Purchases, reported from a server

A Cloudflare Worker in one file (`worker.js`, no dependencies). Shopify tells it about every new order, and it reports the orders placed in the app to Google Analytics 4 and to Meta as a purchase.

The apps have no backend, and the keys that let a server report a sale (Google Analytics' API secret, Meta's access token) must never be inside an app. So this small server holds them, and the store deploys it to its own Cloudflare account.

## What it does

- It answers one address: `POST /webhooks/orders`, for Shopify's "Order creation" webhook. It checks Shopify's signature on every call and answers 401 to anything else.
- An order that was not placed in the app is ignored: the store's web pixels already report web orders. The app marks its carts with `_argon_platform` (and the ids each provider needs), which Shopify passes on as the order's additional details. A cart made while "Share usage data" was off in the app has no such mark, and its order is not reported.
- **Google Analytics**: a `purchase` for the app's data stream, through the Measurement Protocol. Its `transaction_id` is the order's numeric id; it carries the currency, the value without tax and shipping, tax, shipping, the discount code and the items.
- **Meta**: a `Purchase` through the Conversions API, as an app event. Its event id is `purchase-<order id>`; it carries the currency, the order's total and the products. The customer's email, phone and customer id are sent as SHA-256 hashes, never as they are. Meta also gets what it matches an app event by: the install id and device details the app put on the cart, and the IP address and browser the order came from.
- A provider whose secrets are not set is skipped, so the same Worker serves a store with one provider or both.

Only the purchase goes through the server. Every other event comes from the app alone: sent from both sides it would be counted twice, because only a purchase carries an id, the order's, that a platform can match.

### A purchase counted once

The app reports the purchase as well, with the same ids.

- Meta counts two events with the same event id and name once.
- Google Analytics does that for web data streams only, not for app streams ([Analytics Help](https://support.google.com/analytics/answer/12313109)). With the `GA4_...` secrets set, a purchase the app also reported shows twice in Google Analytics. Leave them unset to report purchases to Google Analytics from the app alone.

## Deploy

You need a Cloudflare account and Node.js.

1. In this folder, run `npx wrangler deploy`. The first time it opens a browser to sign in to Cloudflare. It prints the Worker's address, like `https://argon-purchases.<your subdomain>.workers.dev`.
2. Set each secret below with `npx wrangler secret put <NAME>`: it asks for the value. Set the ones of the providers you use.
3. In Shopify admin, go to **Settings → Notifications → Webhooks** and create a webhook: event **Order creation**, format **JSON**, URL `https://<the Worker's address>/webhooks/orders`. Under the list of webhooks Shopify then shows the key it signs them with. Put it in `SHOPIFY_WEBHOOK_SECRET`.
4. Place an order from the app with `npx wrangler tail` running: it shows the call, and anything a provider refused.

| Secret | Where to find it |
|---|---|
| `SHOPIFY_WEBHOOK_SECRET` | Shopify admin → Settings → Notifications → Webhooks, under the list: the key your webhooks are signed with |
| `GA4_FIREBASE_APP_ID_ANDROID` | Firebase console → Project settings → Your apps → the Android app → App ID (`1:...:android:...`). Also `mobilesdk_app_id` in `android/app/google-services.json` |
| `GA4_FIREBASE_APP_ID_IOS` | The same place, the iOS app (`1:...:ios:...`). Also `GOOGLE_APP_ID` in `ios/App/GoogleService-Info.plist` |
| `GA4_API_SECRET` | Google Analytics → Admin → Data streams → the app's stream → Measurement Protocol API secrets → Create |
| `META_DATASET_ID` | Meta Events Manager → the dataset connected to the app → Settings → Dataset ID |
| `META_ACCESS_TOKEN` | The same dataset → Settings → Conversions API → Generate access token |

Google Analytics needs `GA4_API_SECRET` and the Firebase app ID of each app you have set up. A Measurement Protocol secret belongs to one data stream, and the Android app and the iOS app are two streams: with both, create a secret in each stream and set `GA4_API_SECRET_ANDROID` and `GA4_API_SECRET_IOS` instead. Meta needs both of its secrets.

## Good to know

- When a provider refuses a purchase or can't be reached, the Worker answers Shopify with an error and Shopify sends the order again, several times over the next hours. Shopify removes a webhook that keeps failing, so look at the logs (`npx wrangler tail`, or the Worker's Logs in the Cloudflare dashboard) after a change of secrets. The one exception: once Google Analytics has taken a purchase the Worker answers OK even if Meta refused it, because Google Analytics would count the repeat.
- The Worker's name is in `wrangler.toml`. Change it before deploying if the Cloudflare account already has a Worker with that name.
- A Google Analytics property that keeps its data in the EU uses another address: in `worker.js`, replace `www.google-analytics.com` with `region1.google-analytics.com`.
- Amounts are in the shop's currency.
