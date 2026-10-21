import { test } from "node:test";
import assert from "node:assert/strict";
import { parseArgs, slugify, normalizeStore, bundleIdFor, run } from "../lib/index.js";

test("slugify", () => {
  assert.equal(slugify("My Store App!"), "my-store-app");
  assert.equal(slugify("  --Nalli  "), "nalli");
});
test("normalizeStore", () => {
  assert.equal(normalizeStore("https://Nalli.myshopify.com/"), "nalli.myshopify.com");
  assert.equal(normalizeStore("nalli"), "nalli.myshopify.com");
  assert.throws(() => normalizeStore("nalli.com"), /myshopify\.com/);
});
test("bundleIdFor", () => {
  assert.equal(bundleIdFor("my-store-app", "nalli.myshopify.com"), "com.nalli.mystoreapp");
  assert.equal(bundleIdFor("9lives", "mock.shop"), "com.mockshop.a9lives");
});
test("parseArgs", () => {
  const o = parseArgs(["shop-app", "--demo", "--yes", "--client-id", "abc"]);
  assert.deepEqual([o.name, o.demo, o.yes, o.clientId], ["shop-app", true, true, "abc"]);
  assert.throws(() => parseArgs(["--nope"]), /Unknown option --nope/);
});

test("parseArgs: --flag=value, defaults and missing value", () => {
  const o = parseArgs(["--store=a.myshopify.com", "--bundle-id", "com.x.y", "--token=t=1", "app"]);
  assert.deepEqual(o, {
    name: "app", demo: false, store: "a.myshopify.com", token: "t=1", clientId: undefined,
    bundleId: "com.x.y", home: undefined, collection: undefined, judgemeToken: undefined,
    firebaseAndroid: undefined, firebaseIos: undefined, metaAppId: undefined, metaClientToken: undefined,
    moengageWorkspaceId: undefined, moengageDataCenter: undefined, settingsUrl: undefined, customerRedirectUri: undefined,
    checkout: undefined, login: undefined, gokwikMerchantId: undefined, gokwikEnvironment: undefined,
    server: false, push: false, skipContent: false, yes: false, help: false,
  });
  assert.throws(() => parseArgs(["--store"]), /Missing value for --store/);
  const templates = parseArgs(["app", "--home=grocery", "--collection", "bottom", "--judgeme-token=pub"]);
  assert.deepEqual([templates.home, templates.collection, templates.judgemeToken], ["grocery", "bottom", "pub"]);
  assert.throws(() => parseArgs(["--home=luxury"]), /--home must be one of: fashion, beauty, grocery, b2b/);
  assert.throws(() => parseArgs(["--collection=side"]), /--collection must be one of: top, bottom/);
});

test("parseArgs: GoKwik checkout and KwikPass", () => {
  const o = parseArgs(["app", "--checkout=gokwik", "--login=kwikpass", "--gokwik-merchant-id=19g6jle2d5p3n", "--gokwik-environment=sandbox"]);
  assert.deepEqual([o.checkout, o.login, o.gokwikMerchantId, o.gokwikEnvironment], ["gokwik", "kwikpass", "19g6jle2d5p3n", "sandbox"]);
  assert.equal(parseArgs(["app", "--login=kwikpass", "--gokwik-merchant-id=m1"]).checkout, undefined, "KwikPass alone keeps Shopify's checkout");
  assert.throws(() => parseArgs(["app", "--checkout=gokwik"]), /need --gokwik-merchant-id/);
  assert.throws(() => parseArgs(["app", "--login=kwikpass"]), /need --gokwik-merchant-id/);
  assert.throws(() => parseArgs(["app", "--checkout=razorpay"]), /--checkout must be one of: shopify, gokwik/);
  assert.throws(() => parseArgs(["app", "--login=otp"]), /--login must be one of: shopify, kwikpass/);
  assert.throws(() => parseArgs(["app", "--checkout=gokwik", "--gokwik-merchant-id=a b"]), /letters, digits/);
});

test("parseArgs: analytics flags", () => {
  const o = parseArgs(["app", "--firebase-android=a/google-services.json", "--firebase-ios", "GoogleService-Info.plist",
    "--meta-app-id=123", "--meta-client-token=abc", "--moengage-workspace-id=WS", "--moengage-data-center=6", "--server"]);
  assert.deepEqual(
    [o.firebaseAndroid, o.firebaseIos, o.metaAppId, o.metaClientToken, o.moengageWorkspaceId, o.moengageDataCenter, o.server],
    ["a/google-services.json", "GoogleService-Info.plist", "123", "abc", "WS", "6", true],
  );
  for (const value of ["0", "7", "01", "eu"]) {
    assert.throws(() => parseArgs([`--moengage-data-center=${value}`]), /--moengage-data-center must be a number from 1 to 6/);
  }
  // Meta's SDK needs both values, so one without the other is refused
  assert.throws(() => parseArgs(["--meta-app-id=123"]), /--meta-app-id and --meta-client-token go together/);
  assert.throws(() => parseArgs(["--meta-client-token=abc"]), /--meta-app-id and --meta-client-token go together/);
});

test("parseArgs: Krypton's settings URL and customer redirect", () => {
  const o = parseArgs(["app", "--settings-url=https://k.web.app/v1/settings/a.myshopify.com", "--customer-redirect-uri", "https://k.web.app/customer-account/callback"]);
  assert.deepEqual([o.settingsUrl, o.customerRedirectUri], ["https://k.web.app/v1/settings/a.myshopify.com", "https://k.web.app/customer-account/callback"]);
  for (const flag of ["--settings-url", "--customer-redirect-uri"]) {
    for (const value of ["http://k.web.app/x", "k.web.app/x", "https://", "https://a b/c"]) {
      assert.throws(() => parseArgs([`${flag}=${value}`]), new RegExp(`${flag} must be an https:// URL`));
    }
  }
});

// run(): console and TTY are swapped out so --help and the no-terminal check can be asserted
async function runWith(argv, isTTY) {
  const lines = [], log = console.log, tty = Object.getOwnPropertyDescriptor(process.stdin, "isTTY");
  console.log = (s = "") => lines.push(s);
  Object.defineProperty(process.stdin, "isTTY", { value: isTTY, configurable: true });
  try {
    await run(argv);
    return lines.join("\n");
  } finally {
    console.log = log;
    tty ? Object.defineProperty(process.stdin, "isTTY", tty) : delete process.stdin.isTTY;
  }
}

test("run --help lists every flag", async () => {
  const out = await runWith(["--help"], false);
  for (const f of ["--demo", "--store", "--token", "--client-id", "--bundle-id", "--skip-content", "--yes", "--help",
    "--firebase-android", "--firebase-ios", "--meta-app-id", "--meta-client-token", "--moengage-workspace-id", "--moengage-data-center", "--server"]) {
    assert.ok(out.includes(f), `help mentions ${f}`);
  }
});
test("run without a terminal throws on missing values", async () => {
  await assert.rejects(runWith([], false), /Missing project name \(no terminal to prompt\)/);
  await assert.rejects(runWith(["app"], false), /Missing --store \(no terminal to prompt\)/);
  await assert.rejects(runWith(["app", "--store", "a"], false), /Missing --token \(no terminal to prompt\)/);
});
