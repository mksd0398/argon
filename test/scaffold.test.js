import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import prompts from "prompts";
import { run, scaffold, writeAppIcon, configText, xtoolFiles, packageSwift, withFirebase, firebaseConfig, ANALYTICS } from "../lib/index.js";
import { loadContract } from "../lib/contract.js";
import { decodePng, encodePng } from "../lib/png.js";

const WHICH = process.platform === "win32" ? "where" : "command";
const flag = (args, name) => args[args.indexOf(name) + 1];

/**
 * Fake exec/fetch. Records every call; `shopify store execute` answers from the query text (everything exists).
 * gitThrows: every `git -C <dir> ...` call throws, like defaultExec refusing an unsafe path.
 * brand: what the Logo query answers for shop.brand (none: a brand without logos); files: { url: () => Response }
 * for the logo downloads.
 */
function fakes({
  git = true, gitThrows = false, shopify = true, shopName = "Mock.shop", password = false, passwordFails = false,
  content = { products: true, home: true }, brand = { squareLogo: null, logo: null, colors: { primary: [] } }, files = {},
} = {}) {
  const calls = [];
  const urls = [];
  const exec = async (cmd, args) => {
    calls.push([cmd, ...args]);
    if (cmd === WHICH) return { code: shopify ? 0 : 1, stdout: "", stderr: "" };
    if (cmd === "git") {
      if (gitThrows && args[0] === "-C") throw new Error("Unsafe argument for shell: " + args[1]);
      return { code: git ? 0 : 1, stdout: "", stderr: "" };
    }
    if (cmd === "shopify" && args[1] === "execute") {
      const query = readFileSync(flag(args, "--query-file"), "utf8");
      const data = /metaobjectDefinitionByType/.test(query)
        ? { metaobjectDefinitionByType: { id: "gid://shopify/MetaobjectDefinition/1" } }
        : /metaobjectByHandle/.test(query)
          ? { metaobjectByHandle: { id: "gid://shopify/Metaobject/1" } }
          : { shop: { customerAccountsV2: { customerAccountsVersion: "CLASSIC" } } };
      writeFileSync(flag(args, "--output-file"), JSON.stringify(data));
    }
    return { code: 0, stdout: "", stderr: "" };
  };
  const fetch = async (url, init) => {
    urls.push(url);
    if (url in files) return files[url]();
    if (init?.method !== "POST") {
      if (passwordFails) throw new Error("network down");
      return { status: password ? 302 : 200, headers: new Headers(password ? { location: "/password" } : {}) };
    }
    const { query } = JSON.parse(init.body);
    if (query.startsWith("query Logo") && brand === "fails") return { ok: false, status: 500 };
    const body = query.startsWith("query Content")
      ? { data: { products: { nodes: content.products ? [{ id: "p" }] : [] }, metaobject: content.home ? { id: "m" } : null } }
      : query.startsWith("query Logo")
        ? { data: { shop: { brand } } }
        : { data: { shop: { id: "gid://shopify/Shop/68817551382", name: shopName } } };
    return { ok: true, status: 200, json: async () => body };
  };
  return { calls, urls, exec, fetch };
}

/** A fresh temp cwd, console capture and no terminal (terminal: true for one). restore() undoes the capture; done() also removes the cwd. */
function sandbox({ terminal = false } = {}) {
  const cwd = mkdtempSync(join(tmpdir(), "argon-test-"));
  const lines = [], log = console.log, tty = Object.getOwnPropertyDescriptor(process.stdin, "isTTY");
  console.log = (s = "") => lines.push(s);
  Object.defineProperty(process.stdin, "isTTY", { value: terminal, configurable: true });
  const restore = () => {
    console.log = log;
    tty ? Object.defineProperty(process.stdin, "isTTY", tty) : delete process.stdin.isTTY;
  };
  return { cwd, restore, out: () => lines.join("\n"), done: () => (restore(), rmSync(cwd, { recursive: true, force: true })) };
}

// files: { name: content } written into the cwd before the run; terminal: the run can ask (answers come from prompts.inject)
async function withRun(argv, deps, check, { files = {}, terminal = false } = {}) {
  const t = sandbox({ terminal });
  try {
    for (const [name, content] of Object.entries(files)) writeFileSync(join(t.cwd, name), content);
    await run(argv, { ...deps, cwd: t.cwd });
    t.restore();
    await check(t.cwd, t.out());
  } finally {
    t.done();
  }
}

const filesUnder = (dir) =>
  readdirSync(dir, { recursive: true, withFileTypes: true }).filter((e) => e.isFile()).map((e) => join(e.parentPath ?? e.path, e.name));
const queryFiles = (dir) => readdirSync(dir).filter((f) => f.endsWith(".graphql")).sort();

// ─── App icon and launch screen: what the CLI writes, read back with its own PNG reader ───
const ICON = "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png";
const RES = "android/app/src/main/res";
const TEMPLATE_RES = fileURLToPath(new URL("../templates/android/app/src/main/res/", import.meta.url));
const SQUARE_URL = "https://cdn.shopify.com/s/files/1/square.png?width=1024&height=1024";
const LOGO_URL = "https://cdn.shopify.com/s/files/1/logo.png?width=1024&height=1024";
const GREEN = [28, 110, 74], INK = [0x17, 0x15, 0x0f], PAPER = [0xf6, 0xf4, 0xf0], WHITE = [255, 255, 255];
const WHITE_SET = { "color-space": "srgb", components: { alpha: "1.000", blue: "0xFF", green: "0xFF", red: "0xFF" } };
const pixel = (image, x, y) => [...image.data.subarray((y * image.width + x) * 4, (y * image.width + x) * 4 + 4)];
const listing = (dir) => new Set(existsSync(dir) ? readdirSync(dir, { recursive: true }).map((path) => path.replaceAll("\\", "/")) : []);

/** A logo: transparent, with an opaque green block that leaves a margin of a tenth of each side. */
function logoImage(width, height) {
  const data = Buffer.alloc(width * height * 4);
  const top = Math.round(height / 10), left = Math.round(width / 10);
  for (let y = top; y < height - top; y++) {
    for (let x = left; x < width - left; x++) data.set([...GREEN, 255], (y * width + x) * 4);
  }
  return { width, height, data };
}

function branding(dir) {
  const read = (path) => (existsSync(join(dir, path)) ? readFileSync(join(dir, path)) : null);
  const image = (path) => (read(path) ? decodePng(read(path)) : null);
  const assets = "ios/App/Assets.xcassets";
  return {
    iconFile: read(`ios/${ICON}`),
    icon: image(`ios/${ICON}`),
    launch: image(`${assets}/LaunchLogo.imageset/LaunchLogo.png`),
    launchBackground: JSON.parse(read(`${assets}/LaunchBackground.colorset/Contents.json`)).colors[0].color,
    launcher: image(`${RES}/drawable-xxxhdpi/launcher_logo.png`),
    launcherXml: read(`${RES}/values/launcher.xml`)?.toString() ?? null,
  };
}

// The icon every case shares: 1024×1024, written as RGB (no alpha channel), in `corner` at its corners and `centre` in the middle
function assertIcon({ iconFile, icon }, corner, centre) {
  assert.deepEqual([icon.width, icon.height], [1024, 1024]);
  assert.equal(iconFile[25], 2, "the icon's PNG colour type is RGB: no alpha channel");
  for (const [x, y] of [[0, 0], [1023, 0], [0, 1023], [1023, 1023]]) assert.deepEqual(pixel(icon, x, y), [...corner, 255]);
  assert.deepEqual(pixel(icon, 512, 512), [...centre, 255]);
}

/** A project made from the transparent green logo: the five files of the spec's table, and the template's vector mark gone. */
function assertLogoBranding(dir, { launcher, launch }) {
  const b = branding(dir);
  assertIcon(b, WHITE, GREEN);
  for (const [image, [width, height]] of [[b.launcher, launcher], [b.launch, launch]]) {
    assert.deepEqual([image.width, image.height], [width, height]);
    assert.deepEqual(pixel(image, width >> 1, height >> 1), [...GREEN, 255]);
    assert.equal(pixel(image, 0, 0)[3], 0, "transparent as downloaded");
  }
  assert.equal(b.launcherXml, '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="launcher_background">#FFFFFF</color>\n</resources>\n');
  assert.deepEqual(b.launchBackground, WHITE_SET);
  const expected = listing(TEMPLATE_RES);
  expected.delete("drawable/launcher_logo.xml");
  for (const path of ["drawable-xxxhdpi", "drawable-xxxhdpi/launcher_logo.png", "values", "values/launcher.xml"]) expected.add(path);
  assert.deepEqual(listing(join(dir, RES)), expected);
}

/** A project made without a logo: Android's resources are the template's, iOS has the plain icon and an empty launch logo. */
function assertDefaultBranding(dir, background = INK, mark = PAPER) {
  const b = branding(dir);
  assertIcon(b, background, mark);
  assert.deepEqual([b.launch.width, b.launch.height, [...b.launch.data]], [1, 1, [0, 0, 0, 0]]);
  assert.deepEqual(b.launchBackground, WHITE_SET);
  assert.equal(b.launcher, null);
  assert.deepEqual(listing(join(dir, RES)), listing(TEMPLATE_RES));
}

test("--demo --yes scaffolds both apps against mock.shop", async () => {
  const f = fakes();
  const contract = await loadContract();
  await withRun(["demo-app", "--demo", "--yes"], f, (cwd, out) => {
    const dir = join(cwd, "demo-app");
    const props = readFileSync(join(dir, "android/shopify.properties"), "utf8");
    for (const line of ["SHOP_DOMAIN=mock.shop", "SHOP_ID=68817551382", "STOREFRONT_TOKEN=", "CUSTOMER_CLIENT_ID=",
      "API_VERSION=2026-10", "APP_NAME=Mock.shop", "BUNDLE_ID=com.mockshop.demoapp", "PDP_METAFIELDS=",
      "HOME_TEMPLATE=fashion", "COLLECTION_TEMPLATE=top", "JUDGEME_PUBLIC_TOKEN=", "SHOW_VENDOR=false", "ONBOARDING=true", "FREE_SHIPPING_THRESHOLD=150",
      "META_APP_ID=", "META_CLIENT_TOKEN=", "MOENGAGE_WORKSPACE_ID=", "MOENGAGE_DATA_CENTER=", "SERVER_PURCHASE=false",
      "CHECKOUT=shopify", "LOGIN=shopify", "GOKWIK_MERCHANT_ID=", "GOKWIK_ENVIRONMENT=production", "ARGON_REVISION=0.1.0"]) {
      assert.ok(props.split("\n").includes(line), `shopify.properties has ${line}`);
    }
    // no analytics unless asked for: no SDK in the iOS package, no Firebase file, no server, nothing about it at the end
    assert.equal(readFileSync(join(dir, "ios/Package.swift"), "utf8"), readFileSync(new URL("../templates/ios/Package.swift", import.meta.url), "utf8"));
    for (const path of ["server", "android/app/google-services.json", "ios/App/GoogleService-Info.plist"]) assert.ok(!existsSync(join(dir, path)), path);
    assert.ok(!out.includes("Analytics"));
    const xcconfig = readFileSync(join(dir, "ios/Config.xcconfig"), "utf8");
    assert.ok(xcconfig.split("\n").includes("SHOP_DOMAIN = mock.shop"));
    assert.ok(xcconfig.split("\n").includes("SHOP_ID = 68817551382"));

    const android = queryFiles(join(dir, "android/app/src/main/assets/queries"));
    const ios = queryFiles(join(dir, "ios/App/Resources/queries"));
    assert.equal(android.length, 59);
    assert.deepEqual(ios, android);

    // xtool (iOS without a Mac): every file the app reads from its bundle is listed, and each exists
    const xtool = readFileSync(join(dir, "ios/xtool.yml"), "utf8").trimEnd().split("\n");
    assert.deepEqual(xtool.slice(0, 5), [
      "version: 1", "bundleID: com.mockshop.demoapp", "infoPath: Xtool-Info.plist",
      "iconPath: App/Assets.xcassets/AppIcon.appiconset/AppIcon.png", "resources:",
    ]);
    const resources = xtool.slice(5).map((line) => line.replace(/^- /, ""));
    assert.deepEqual(resources.slice(0, 2), ["Config.xcconfig", "App/PrivacyInfo.xcprivacy"]);
    assert.deepEqual(resources.slice(2, 2 + ios.length), ios.map((file) => `App/Resources/queries/${file}`));
    // the home templates' placeholder banners, and (demo store only) the sample account, in both apps
    const images = readdirSync(new URL("../templates/images/", import.meta.url)).filter((file) => file.endsWith(".jpg")).sort();
    assert.equal(images.length, 12);
    assert.deepEqual(readdirSync(join(dir, "android/app/src/main/assets/home")).sort(), images);
    const samples = readdirSync(join(dir, "android/app/src/main/assets/sample")).sort();
    assert.equal(samples.length, 15); // the 14 Customer Account operations and the sample reviews
    assert.ok(samples.includes("Orders.sample.json") && samples.includes("JudgeMeWidget.sample.html"));
    const deleted = JSON.parse(readFileSync(join(dir, "android/app/src/main/assets/sample/CustomerAddressDelete.sample.json"), "utf8"));
    assert.ok(deleted.customerAddressDelete.deletedAddressId, "the preview's address delete succeeds");
    assert.deepEqual(readdirSync(join(dir, "ios/App/Resources/sample")).sort(), samples);
    assert.deepEqual(resources.slice(2 + ios.length), [...images.map((file) => `App/Resources/home/${file}`), ...samples.map((file) => `App/Resources/sample/${file}`)]);
    for (const file of [...resources, "Xtool-Info.plist", "Package.swift", ICON]) assert.ok(existsSync(join(dir, "ios", file)), file);
    assert.ok(readFileSync(join(dir, "ios/Xtool-Info.plist"), "utf8").includes("<string>Mock.shop</string>"));
    for (const folder of ["android/app/src/main/assets/queries", "ios/App/Resources/queries"]) {
      for (const [name, document] of contract) {
        assert.equal(readFileSync(join(dir, folder, `${name}.graphql`), "utf8"), document, `${folder}/${name}`);
      }
    }
    // every operation's fixture, for the apps' decoding tests
    for (const folder of ["android/app/src/test/resources/fixtures", "ios/AppTests/Fixtures"]) {
      for (const name of contract.keys()) {
        const fixture = readFileSync(new URL(`../contract/fixtures/${name}.json`, import.meta.url), "utf8");
        assert.equal(readFileSync(join(dir, folder, `${name}.json`), "utf8"), fixture, `${folder}/${name}.json`);
      }
    }

    for (const sub of ["", "android", "ios"]) {
      assert.ok(existsSync(join(dir, sub, ".gitignore")), `${sub || "root"} .gitignore`);
      assert.ok(!existsSync(join(dir, sub, "gitignore")), `${sub || "root"} gitignore renamed`);
    }
    assert.equal(readFileSync(join(dir, "CLAUDE.md"), "utf8").trim(), "See AGENTS.md");
    for (const name of ["AGENTS.md", "README.md"]) assert.ok(existsSync(join(dir, name)), name);
    for (const file of filesUnder(dir)) assert.ok(!readFileSync(file, "utf8").includes("__ARGON_"), `${file} has no placeholder`);

    assert.ok(f.calls.every(([cmd]) => cmd !== "shopify" && cmd !== WHICH), "demo never touches the Shopify CLI");
    // the shop, then its logo
    assert.deepEqual(f.urls, ["https://mock.shop/api/2026-10/graphql.json", "https://mock.shop/api/2026-10/graphql.json"]);
    const git = f.calls.filter(([cmd]) => cmd === "git");
    assert.deepEqual(git, [
      ["git", "--version"],
      ["git", "-C", dir, "init"],
      ["git", "-C", dir, "add", "-A"],
      ["git", "-C", dir, "update-index", "--chmod=+x", "android/gradlew"],
      ["git", "-C", dir, "commit", "-m", "Initial Argon scaffold"],
    ]);
    for (const text of ["Open ios/App.xcodeproj in Xcode 16+", "Open android/ in Android Studio", "README.md"]) {
      assert.ok(out.includes(text), `final message: ${text}`);
    }
  });
});

test("no git, no git commands beyond the version probe", async () => {
  const f = fakes({ git: false });
  await withRun(["demo-app", "--demo", "--yes"], f, () => {
    assert.deepEqual(f.calls.filter(([cmd]) => cmd === "git"), [["git", "--version"]]);
  });
});

test("git failing (an unsafe path, say) only warns; the run still finishes with next steps", async () => {
  const f = fakes({ gitThrows: true });
  await withRun(["demo-app", "--demo", "--yes"], f, (cwd, out) => {
    assert.ok(existsSync(join(cwd, "demo-app", "android", "shopify.properties")), "project was written");
    assert.ok(out.includes("Couldn't create the git repo: Unsafe argument for shell"));
    assert.ok(!out.includes("Initialized a git repository"));
    assert.ok(out.includes("Open ios/App.xcodeproj in Xcode 16+"), "next steps still printed");
  });
});

test("real store: auth, provision, password check, Headless steps, verify, config", async () => {
  const f = fakes({ shopName: "Nalli Silks", password: true, content: { products: false, home: false } });
  const clientId = "3cecd990-4824-4e27-beb2-46c8e822ec14"; // Headless issues a bare UUID
  const argv = ["store-app", "--store", "https://Nalli.myshopify.com/", "--token", "tok123", "--client-id", clientId, "--yes"];
  await withRun(argv, f, (cwd, out) => {
    const cli = f.calls.filter(([cmd]) => cmd === WHICH || cmd === "shopify").map((c) => c.slice(0, 3).join(" "));
    assert.equal(cli[0], `${WHICH} ${process.platform === "win32" ? "shopify" : "-v shopify"}`);
    assert.equal(cli[1], "shopify store auth");
    assert.ok(cli.slice(2).every((c) => c === "shopify store execute"));
    const graphql = "https://nalli.myshopify.com/api/2026-10/graphql.json";
    assert.deepEqual(f.urls, ["https://nalli.myshopify.com/", graphql, graphql, graphql]); // password, shop, content, logo
    assert.ok(f.calls.every(([cmd]) => !["start", "open", "xdg-open"].includes(cmd)), "no browser without a terminal");

    assert.ok(out.includes("Store uses legacy customer accounts"), "provision warnings are printed");
    assert.ok(out.includes("Storefront password is on — Checkout Kit can't open checkout until it's off"));
    const at = (text) => {
      const i = out.indexOf(text);
      assert.ok(i >= 0, `output has "${text}"`);
      return i;
    };
    assert.ok(at("https://apps.shopify.com/headless") < at("1. Create a storefront"));
    assert.ok(at("1. Create a storefront") < at("2. Make your products and collections available to the storefront"));
    assert.ok(at("2. Make your products") < at("3. Storefront API: copy the public access token"));
    assert.ok(at("3. Storefront API") < at("Storefront token works for Nalli Silks"));
    assert.ok(at("Storefront token works") < at("The app sees no products: make them available to the storefront's sales channel"));
    assert.ok(at("The app sees no products") < at("The app can't read the home screen: allow unauthenticated_read_metaobjects"));
    assert.ok(at("can't read the home screen") < at("4. Customer Account API: edit Client type to Public (mobile app)"));
    assert.ok(at("4. Customer Account API: edit") < at("shop.68817551382.app://callback"), "callback needs the shop id");
    assert.ok(!out.includes("Login hidden"), "a client id was given");
    assert.ok(!out.includes("doesn't look like a Customer Account API client ID"));

    const dir = join(cwd, "store-app");
    const props = readFileSync(join(dir, "android/shopify.properties"), "utf8").split("\n");
    for (const line of ["SHOP_DOMAIN=nalli.myshopify.com", "STOREFRONT_TOKEN=tok123", `CUSTOMER_CLIENT_ID=${clientId}`,
      "SHOP_ID=68817551382", "APP_NAME=Nalli Silks", "BUNDLE_ID=com.nalli.storeapp"]) {
      assert.ok(props.includes(line), line);
    }
    assert.ok(readFileSync(join(dir, "ios/Config.xcconfig"), "utf8").includes("APP_NAME = Nalli Silks"));
  });
});

test("--skip-content skips the Shopify CLI; a failed password check and a blank client id only warn", async () => {
  const f = fakes({ passwordFails: true });
  await withRun(["store-app", "--store", "nalli", "--token", "t", "--skip-content", "--yes"], f, (cwd, out) => {
    assert.ok(f.calls.every(([cmd]) => cmd !== "shopify" && cmd !== WHICH));
    assert.ok(out.includes("Couldn't check storefront password"));
    assert.ok(out.includes("The app can see your products") && out.includes("The app can read the home screen"));
    assert.ok(out.includes("Login hidden until CUSTOMER_CLIENT_ID is set"));
    assert.ok(readFileSync(join(cwd, "store-app/android/shopify.properties"), "utf8").includes("CUSTOMER_CLIENT_ID=\n"));
  });
});

// ─── Analytics: Firebase's two files as its console writes them, and what the CLI makes of each provider ───
const googleServices = (...packages) => JSON.stringify({
  project_info: { project_number: "1234", project_id: "argon-demo" },
  client: packages.map((name, n) => ({ client_info: { mobilesdk_app_id: `1:1234:android:${n}abc`, android_client_info: { package_name: name } } })),
}, null, 2);
const googleServiceInfo = (bundleId) => `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>AIzaSyExample</string>
	<key>BUNDLE_ID</key>
	<string>${bundleId}</string>
	<key>GOOGLE_APP_ID</key>
	<string>1:1234:ios:def</string>
	<key>IS_ANALYTICS_ENABLED</key>
	<false></false>
</dict>
</plist>
`;
const TEMPLATE_PACKAGE = readFileSync(new URL("../templates/ios/Package.swift", import.meta.url), "utf8");
const lines = (text) => text.split(/\r?\n/);
// what packageSwift added to the template, in order (a changed line counts as added)
const addedLines = (text) => lines(text).filter((line) => !lines(TEMPLATE_PACKAGE).includes(line)).map((line) => line.trim());
const SDK_LINES = {
  firebase: ['.package(url: "https://github.com/firebase/firebase-ios-sdk", from: "13.0.1"),', '.product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),'],
  meta: ['.package(url: "https://github.com/facebook/facebook-ios-sdk", from: "18.1.1"),', '.product(name: "FacebookCore", package: "facebook-ios-sdk"),'],
  moengage: ['.package(url: "https://github.com/moengage/apple-sdk", from: "11.3.0"),', '.product(name: "MoEngage-iOS-SDK", package: "apple-sdk"),'],
};
// what Firebase changes on the app target: its file kept out of the sources, and -ObjC on the link
const FIREBASE_TARGET = [
  'exclude: ["Resources", "PrivacyInfo.xcprivacy", "GoogleService-Info.plist", "Assets.xcassets"],',
  "swiftSettings: [.swiftLanguageMode(.v5)],",
  'linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]',
];
const config = (dir) => ({
  android: readFileSync(join(dir, "android/shopify.properties"), "utf8").split("\n"),
  ios: readFileSync(join(dir, "ios/Config.xcconfig"), "utf8").split("\n"),
});

test("every analytics flag: keys in both config files, Firebase's files, the iOS packages, Meta's Info.plist keys, server/", async () => {
  const files = { "google-services.json": googleServices("com.other.app", "com.mockshop.demoapp"), "GoogleService-Info.plist": googleServiceInfo("com.mockshop.demoapp") };
  const argv = ["demo-app", "--demo", "--yes", "--firebase-android=google-services.json", "--firebase-ios=GoogleService-Info.plist",
    "--meta-app-id=123", "--meta-client-token=abc", "--moengage-workspace-id=XYZ", "--moengage-data-center=3"];
  await withRun(argv, fakes(), (cwd, out) => {
    const dir = join(cwd, "demo-app");
    const { android, ios } = config(dir);
    // SERVER_PURCHASE stays false without --server: the apps report the purchase to Google Analytics themselves
    for (const [key, value] of [["META_APP_ID", "123"], ["META_CLIENT_TOKEN", "abc"], ["MOENGAGE_WORKSPACE_ID", "XYZ"], ["MOENGAGE_DATA_CENTER", "3"], ["SERVER_PURCHASE", "false"]]) {
      assert.ok(android.includes(`${key}=${value}`) && ios.includes(`${key} = ${value}`), key);
    }
    // Firebase's files, byte for byte, where each platform's SDK looks for them
    assert.equal(readFileSync(join(dir, "android/app/google-services.json"), "utf8"), files["google-services.json"]);
    assert.equal(readFileSync(join(dir, "ios/App/GoogleService-Info.plist"), "utf8"), files["GoogleService-Info.plist"]);
    assert.ok(lines(readFileSync(join(dir, "ios/xtool.yml"), "utf8")).includes("- App/GoogleService-Info.plist"), "bundled by an xtool build");

    const added = addedLines(readFileSync(join(dir, "ios/Package.swift"), "utf8"));
    // Firebase brings crash reports: Crashlytics below Analytics
    const products = Object.values(SDK_LINES).map(([, product]) => product);
    products.splice(1, 0, SDK_LINES.firebase[1].replace("FirebaseAnalytics", "FirebaseCrashlytics"));
    assert.deepEqual(added, [...Object.values(SDK_LINES).map(([dependency]) => dependency), ...products, ...FIREBASE_TARGET]);
    const info = readFileSync(join(dir, "ios/Xtool-Info.plist"), "utf8");
    for (const [key, value] of [["CFBundleDisplayName", "Mock.shop"], ["FacebookAppID", "123"], ["FacebookClientToken", "abc"], ["FacebookDisplayName", "Mock.shop"]]) {
      assert.ok(info.includes(`\t<key>${key}</key>\n\t<string>${value}</string>\n`), key);
    }

    assert.deepEqual(readdirSync(join(dir, "server")).sort(), [".gitignore", "README.md", "worker.js", "wrangler.toml"]);
    assert.equal(readFileSync(join(dir, "server/worker.js"), "utf8"), readFileSync(new URL("../templates/server/worker.js", import.meta.url), "utf8"));

    // one line per provider at the end, with each app's Firebase app ID
    for (const line of [
      "- Google Analytics (Android app 1:1234:android:1abc, iOS app 1:1234:ios:def): nothing more to set up; the apps report the purchase themselves",
      "- Meta: deploy server/",
      "- MoEngage: nothing more to set up; push and in-app messages are not included",
      "- iOS built with Xcode: add the Meta and MoEngage Swift package to the App target",
    ]) assert.ok(out.includes(line), line);
  }, { files });
});

test("one provider at a time: only its SDK, and server/ only for Google Analytics, Meta or --server", async () => {
  const project = (dir) => ({
    added: addedLines(readFileSync(join(dir, "ios/Package.swift"), "utf8")),
    server: existsSync(join(dir, "server/worker.js")),
    info: readFileSync(join(dir, "ios/Xtool-Info.plist"), "utf8"),
    ...config(dir),
  });
  await withRun(["demo-app", "--demo", "--yes", "--moengage-workspace-id=XYZ"], fakes(), (cwd, out) => {
    const p = project(join(cwd, "demo-app"));
    assert.deepEqual([p.added, p.server], [SDK_LINES.moengage, false]);
    assert.ok(p.android.includes("MOENGAGE_DATA_CENTER=1") && p.ios.includes("MOENGAGE_DATA_CENTER = 1"), "data center 1 unless told");
    assert.ok(!p.info.includes("FacebookAppID") && !out.includes("Meta:") && !out.includes("Google Analytics"));
  });
  // a data center without a workspace configures nothing. --server: server/, and the Google Analytics purchase is its to report
  await withRun(["demo-app", "--demo", "--yes", "--moengage-data-center=4", "--server"], fakes(), (cwd, out) => {
    const p = project(join(cwd, "demo-app"));
    assert.deepEqual([p.added, p.server], [[], true]);
    assert.ok(p.android.includes("MOENGAGE_DATA_CENTER=") && !out.includes("Analytics"));
    assert.ok(p.android.includes("SERVER_PURCHASE=true") && p.ios.includes("SERVER_PURCHASE = true"));
  });
  await withRun(["demo-app", "--demo", "--yes", "--meta-app-id=123", "--meta-client-token=a&b"], fakes(), (cwd) => {
    const p = project(join(cwd, "demo-app"));
    assert.deepEqual([p.added, p.server], [SDK_LINES.meta, true]);
    assert.ok(p.info.includes("<string>a&amp;b</string>") && p.ios.includes("META_CLIENT_TOKEN = a&b"));
  });
  // Android's file alone: the iOS app gets no Firebase, and the last lines name only the Android app
  const files = { "google-services.json": googleServices("com.mockshop.demoapp") };
  await withRun(["demo-app", "--demo", "--yes", "--firebase-android", "google-services.json"], fakes(), (cwd, out) => {
    const p = project(join(cwd, "demo-app"));
    assert.deepEqual([p.added, p.server], [[], true]);
    assert.ok(existsSync(join(cwd, "demo-app/android/app/google-services.json")) && !existsSync(join(cwd, "demo-app/ios/App/GoogleService-Info.plist")));
    assert.ok(out.includes("- Google Analytics (Android app 1:1234:android:0abc): nothing more to set up") && !out.includes("iOS built with Xcode"));
    assert.ok(p.android.includes("SERVER_PURCHASE=false"), "server/ is written, but only --server hands it the Google Analytics purchase");
  }, { files });
  await withRun(["demo-app", "--demo", "--yes", "--firebase-android", "google-services.json", "--server"], fakes(), (cwd, out) => {
    assert.ok(project(join(cwd, "demo-app")).android.includes("SERVER_PURCHASE=true"));
    assert.ok(out.includes("- Google Analytics (Android app 1:1234:android:0abc): deploy server/ with its Google secrets before you release the apps"));
  }, { files });
});

test("a Firebase file for another app, or one that can't be read, stops the run before anything is written or fetched", async () => {
  const files = {
    "google-services.json": googleServices("com.other.app", "com.another.app"),
    "GoogleService-Info.plist": googleServiceInfo("com.other.ios"),
    "binary.plist": Buffer.concat([Buffer.from("bplist00"), Buffer.from([0xd1, 0x01, 0x02, 0x00])]),
    "broken.json": "{ not json",
    "empty.plist": '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n',
  };
  const f = fakes();
  const t = sandbox();
  try {
    for (const [name, content] of Object.entries(files)) writeFileSync(join(t.cwd, name), content);
    const refused = async (flag, expected) => {
      const error = await run(["demo-app", "--demo", "--yes", flag], { ...f, cwd: t.cwd }).then(() => assert.fail(`${flag} was accepted`), (err) => err);
      for (const text of expected) assert.ok(error.message.includes(text), `${flag}: "${error.message}" has "${text}"`);
    };
    // the file and both ids are named
    await refused("--firebase-android=google-services.json", [join(t.cwd, "google-services.json"), "is for com.other.app, com.another.app, but this app is com.mockshop.demoapp", "--bundle-id"]);
    await refused("--firebase-ios=GoogleService-Info.plist", [join(t.cwd, "GoogleService-Info.plist"), "is for com.other.ios, but this app is com.mockshop.demoapp"]);
    await refused("--firebase-ios=missing.plist", [join(t.cwd, "missing.plist"), "can't be read (ENOENT)", "GoogleService-Info.plist"]);
    await refused("--firebase-ios=binary.plist", ["binary.plist is a binary plist"]);
    await refused("--firebase-ios=empty.plist", ["empty.plist is not a GoogleService-Info.plist"]);
    await refused("--firebase-android=broken.json", ["broken.json is not a google-services.json"]);
    await refused("--firebase-android=GoogleService-Info.plist", ["is not a google-services.json"]); // the two files swapped
    await refused("--push", ["--push needs Firebase"]);
    assert.deepEqual([existsSync(join(t.cwd, "demo-app")), f.urls.length, f.calls.length], [false, 0, 0]);

    // --bundle-id is the id the files are checked against
    const { appId } = firebaseConfig(join(t.cwd, "google-services.json"), "android", "com.another.app");
    assert.equal(appId, "1:1234:android:1abc");
    await run(["demo-app", "--demo", "--yes", "--bundle-id=com.other.ios", "--firebase-ios=GoogleService-Info.plist"], { ...f, cwd: t.cwd });
    assert.ok(existsSync(join(t.cwd, "demo-app/ios/App/GoogleService-Info.plist")));
  } finally {
    t.done();
  }
});

test("in a terminal: one Analytics question, then only what the picked providers need", async () => {
  const f = fakes();
  const argv = ["store-app", "--store", "nalli", "--token", "t", "--client-id", "3cecd990-4824-4e27-beb2-46c8e822ec14", "--skip-content"];
  const files = { "google-services.json": googleServices("com.nalli.storeapp") };
  // home, collection, Judge.me; Analytics; then Firebase's two files (the iOS one skipped), Meta's two values, MoEngage's two
  prompts.inject(["beauty", "bottom", "", ["firebase", "meta", "moengage"], "google-services.json", "", "123", "abc", "WS1", "3"]);
  await withRun(argv, f, (cwd, out) => {
    const dir = join(cwd, "store-app");
    const { android } = config(dir);
    for (const line of ["HOME_TEMPLATE=beauty", "META_APP_ID=123", "META_CLIENT_TOKEN=abc", "MOENGAGE_WORKSPACE_ID=WS1", "MOENGAGE_DATA_CENTER=3"]) assert.ok(android.includes(line), line);
    assert.ok(existsSync(join(dir, "android/app/google-services.json")) && !existsSync(join(dir, "ios/App/GoogleService-Info.plist")));
    assert.deepEqual(addedLines(readFileSync(join(dir, "ios/Package.swift"), "utf8")), [SDK_LINES.meta[0], SDK_LINES.moengage[0], SDK_LINES.meta[1], SDK_LINES.moengage[1]]);
    assert.ok(existsSync(join(dir, "server/worker.js")) && out.includes("- Google Analytics (Android app 1:1234:android:0abc)"));
  }, { files, terminal: true });

  // nothing picked: only what the flags gave is configured, and none of it is asked for again
  prompts.inject(["fashion", "top", "", []]);
  await withRun([...argv, "--meta-app-id=9", "--meta-client-token=z"], f, (cwd) => {
    const { android } = config(join(cwd, "store-app"));
    for (const line of ["META_APP_ID=9", "META_CLIENT_TOKEN=z", "MOENGAGE_WORKSPACE_ID=", "MOENGAGE_DATA_CENTER="]) assert.ok(android.includes(line), line);
    assert.ok(!existsSync(join(cwd, "store-app/android/app/google-services.json")));
  }, { terminal: true });
});

test("packageSwift: each SDK's package and product go in below Checkout Kit's, in the file's own line endings", () => {
  assert.equal(packageSwift(TEMPLATE_PACKAGE, []), TEMPLATE_PACKAGE);
  const meta = lines(packageSwift(TEMPLATE_PACKAGE, ["meta"]));
  assert.equal(meta.length, lines(TEMPLATE_PACKAGE).length + 2);
  assert.deepEqual(meta.slice(meta.findIndex((line) => line.includes("checkout-sheet-kit-swift\", from")) + 1).slice(0, 2), [`        ${SDK_LINES.meta[0]}`, "    ],"]);
  assert.deepEqual(meta.slice(meta.findIndex((line) => line.includes("ShopifyCheckoutSheetKit")) + 1).slice(0, 2), [`                ${SDK_LINES.meta[1]}`, "            ],"]);
  // the order is fixed, whatever order the providers are given in; only Firebase has a file to keep out of the target
  assert.deepEqual(addedLines(packageSwift(TEMPLATE_PACKAGE, ["moengage", "firebase"])), [SDK_LINES.firebase[0], SDK_LINES.moengage[0], SDK_LINES.firebase[1], SDK_LINES.firebase[1].replace("FirebaseAnalytics", "FirebaseCrashlytics"), SDK_LINES.moengage[1], ...FIREBASE_TARGET]);

  const unix = lines(TEMPLATE_PACKAGE).join("\n"), windows = lines(TEMPLATE_PACKAGE).join("\r\n");
  assert.ok(!packageSwift(unix, ["firebase", "meta", "moengage"]).includes("\r"));
  assert.ok(!/[^\r]\n/.test(packageSwift(windows, ["firebase", "meta", "moengage"])), "every line still ends in CRLF");

  // a template that lost a line this builds on is an error, not an app without its SDKs
  assert.throws(() => packageSwift(TEMPLATE_PACKAGE.replace("Shopify/checkout-sheet-kit-swift", "Shopify/checkout-kit"), ["meta"]), /Package\.swift no longer has \.package\(url: "https:\/\/github\.com\/Shopify\/checkout-sheet-kit-swift"/);
  assert.throws(() => packageSwift(TEMPLATE_PACKAGE.replace("ShopifyCheckoutSheetKit", "CheckoutKit"), ["moengage"]), /Package\.swift no longer has \.product\(name: "ShopifyCheckoutSheetKit"/);
  const noExclude = TEMPLATE_PACKAGE.replace('"Resources", "PrivacyInfo.xcprivacy"', '"Resources", "Other", "PrivacyInfo.xcprivacy"');
  assert.throws(() => packageSwift(noExclude, ["firebase"]), /Package\.swift no longer has exclude: \["Resources", "PrivacyInfo\.xcprivacy"/);
  assert.deepEqual(addedLines(packageSwift(noExclude, ["meta"])).slice(0, 2), SDK_LINES.meta, "only Firebase needs the exclude list");

  // the generated README names the same packages, for adding them in Xcode
  const readme = readFileSync(new URL("../templates/shared/README.md", import.meta.url), "utf8");
  for (const { ios } of ANALYTICS) assert.ok(readme.includes(`| \`${ios.url}\`, ${ios.from} or later | \`${ios.product}\` |`), ios.url);
});

// in LF, whatever the checkout's line endings: the CRLF case is tested on its own
const TEMPLATE_PROJECT = lines(readFileSync(new URL("../templates/ios/App.xcodeproj/project.pbxproj", import.meta.url), "utf8")).join("\n");

test("withFirebase: the Xcode project's App target gets Firebase's package, products, -ObjC and the Crashlytics phase", () => {
  const project = withFirebase(TEMPLATE_PROJECT);
  const { url, from } = ANALYTICS.find((a) => a.value === "firebase").ios;
  assert.ok(project.includes(`repositoryURL = "${url}";\n\t\t\trequirement = {\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = ${from};`));
  // each product: a dependency of the App target and a file of its Frameworks phase, none for the tests
  const target = (name) => project.slice(project.indexOf(`/* ${name} */ = {\n\t\t\tisa = PBXNativeTarget;`)).split("\n\t\t};")[0];
  for (const product of ["FirebaseAnalytics", "FirebaseCrashlytics"]) {
    assert.ok(project.includes(`productName = ${product};`), product);
    assert.ok(target("App").includes(` /* ${product} */,`), product);
    assert.ok(!target("AppTests").includes(product), product);
    assert.equal(project.split(` /* ${product} in Frameworks */`).length - 1, 2, "the build file and its place in the Frameworks phase");
  }
  assert.ok(!project.includes("FirebaseMessaging"), "Messaging only with push");
  assert.ok(withFirebase(TEMPLATE_PROJECT, { push: true }).includes("productName = FirebaseMessaging;"));
  // the dSYM upload runs last, after the app's resources
  assert.match(target("App"), /\/\* Resources \*\/,\n\t\t\t\t\w{24} \/\* Crashlytics \*\/,\n\t\t\t\);/);
  assert.ok(project.includes('shellScript = "\\"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run\\"\\n";'));
  assert.equal(project.split('OTHER_LDFLAGS = "$(inherited) -ObjC";').length - 1, 2, "the app target's Debug and Release, not the tests");
  assert.equal(project.split("ENABLE_USER_SCRIPT_SANDBOXING = NO;").length - 1, 2);
  // every object it refers to is defined once
  for (const id of new Set(project.match(/F12EBA5E\w{16}/g))) assert.equal(project.match(new RegExp(`${id}[^\\n]*= \\{`, "g")).length, 1, id);
  // the template's line endings, and a template that lost a line this builds on is an error
  assert.ok(!/[^\r]\n/.test(withFirebase(lines(TEMPLATE_PROJECT).join("\r\n"))), "every line still ends in CRLF");
  assert.throws(() => withFirebase(TEMPLATE_PROJECT.replaceAll("ShopifyCheckoutSheetKit", "CheckoutKit")), /App\.xcodeproj no longer has/);
});

const withLogos = (files, primary = []) => ({
  brand: { squareLogo: SQUARE_URL in files ? { image: { url: SQUARE_URL } } : null, logo: LOGO_URL in files ? { image: { url: LOGO_URL } } : null, colors: { primary } },
  files,
});
const DEFAULTS = "Android keeps the default icon and iOS gets a plain one";

test("the store's square logo becomes the app icon and the launch screen; the wide logo isn't fetched", async () => {
  const square = () => new Response(encodePng(logoImage(1024, 1024)));
  const f = fakes(withLogos({ [SQUARE_URL]: square, [LOGO_URL]: () => assert.fail("the square logo is preferred") }));
  await withRun(["demo-app", "--demo", "--yes"], f, (cwd, out) => {
    assertLogoBranding(join(cwd, "demo-app"), { launcher: [264, 264], launch: [600, 600] });
    assert.equal(f.urls.at(-1), SQUARE_URL);
    assert.ok(out.includes("App icon and launch screen: the store's square logo, on #FFFFFF"));
    assert.ok(!out.includes(DEFAULTS));
  });
});

test("a square logo that can't be read falls back to the wide logo, which is never enlarged for Android or the launch screen", async () => {
  const f = fakes(withLogos({ [SQUARE_URL]: () => new Response("<svg xmlns='http://www.w3.org/2000/svg'/>"), [LOGO_URL]: () => new Response(encodePng(logoImage(200, 100))) }));
  await withRun(["store-app", "--store", "nalli", "--token", "t", "--skip-content", "--yes"], f, (cwd, out) => {
    assertLogoBranding(join(cwd, "store-app"), { launcher: [200, 100], launch: [200, 100] });
    assert.deepEqual(f.urls.slice(-2), [SQUARE_URL, LOGO_URL]);
    assert.ok(out.includes("App icon and launch screen: the store's logo, on #FFFFFF"));
  });
});

test("a brand without a logo: one info line, and the default icon", async () => {
  await withRun(["demo-app", "--demo", "--yes"], fakes(), (cwd, out) => {
    assertDefaultBranding(join(cwd, "demo-app"));
    assert.ok(out.includes(`The store's brand has no logo for the app icon. ${DEFAULTS}`));
    assert.ok(!out.includes("Couldn't use the store's logo"));
  });
});

test("a logo that can't be downloaded, or a logo query that fails, only warns: the apps get the default icon", async () => {
  const gone = fakes(withLogos({ [LOGO_URL]: () => new Response("gone", { status: 404 }) }, [{ background: "#1c6e4a" }]));
  await withRun(["demo-app", "--demo", "--yes"], gone, (cwd, out) => {
    assertDefaultBranding(join(cwd, "demo-app"), GREEN); // on the brand's primary colour
    assert.ok(out.includes(`Couldn't use the store's logo for the app icon (HTTP 404). ${DEFAULTS}`));
    assert.ok(out.includes("Created demo-app/") && out.includes("Open android/ in Android Studio"), "the run still finishes");
  });
  await withRun(["demo-app", "--demo", "--yes"], fakes({ brand: "fails" }), (cwd, out) => {
    assertDefaultBranding(join(cwd, "demo-app"));
    assert.ok(out.includes(`Couldn't use the store's logo for the app icon (Storefront API returned HTTP 500 for mock.shop). ${DEFAULTS}`));
    assert.ok(out.includes("Created demo-app/"));
  });
});

test("scaffold: called without a logo it writes the defaults, with one the files made from it", async () => {
  const cwd = mkdtempSync(join(tmpdir(), "argon-test-"));
  try {
    const project = { appName: "Nalli", bundleId: "com.nalli.app", shopDomain: "nalli.myshopify.com", token: "t", clientId: "", shopId: "1" };
    await scaffold({ ...project, dir: join(cwd, "plain") });
    assertDefaultBranding(join(cwd, "plain"));
    await scaffold({ ...project, dir: join(cwd, "logo"), logo: logoImage(1000, 500), brandColor: "#1C6E4A" });
    assertLogoBranding(join(cwd, "logo"), { launcher: [264, 132], launch: [600, 300] });
    for (const dir of ["plain", "logo"]) {
      assert.ok(readFileSync(join(cwd, dir, "ios/xtool.yml"), "utf8").includes(`\niconPath: ${ICON}\n`));
      assert.ok(existsSync(join(cwd, dir, "ios", ICON)));
    }
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
});

test("writeAppIcon: the template's vector mark goes only when the logo's PNG replaces it", () => {
  const dir = mkdtempSync(join(tmpdir(), "argon-test-"));
  try {
    const vector = join(dir, RES, "drawable/launcher_logo.xml");
    mkdirSync(join(dir, RES, "drawable"), { recursive: true });
    writeFileSync(vector, "<vector/>");

    writeAppIcon(dir);
    assert.ok(existsSync(vector), "no logo: the vector stays");
    assert.deepEqual(listing(join(dir, RES)), new Set(["drawable", "drawable/launcher_logo.xml"]));
    assertIcon(branding(dir), INK, PAPER);
    // the mark is whichever of paper and ink shows on the brand's colour
    writeAppIcon(dir, { brandColor: "#1C6E4A" });
    assertIcon(branding(dir), GREEN, PAPER);
    writeAppIcon(dir, { brandColor: "#FFE14D" });
    assertIcon(branding(dir), [255, 225, 77], INK);
    assert.ok(existsSync(vector));

    // a logo on its own opaque background: that colour is the icon's and the launch screen's background
    writeAppIcon(dir, { logo: { width: 100, height: 100, data: Buffer.alloc(100 * 100 * 4, Buffer.from([...GREEN, 255])) }, brandColor: "#FFE14D" });
    assert.ok(!existsSync(vector), "a resource can't be both a vector and a PNG");
    const b = branding(dir);
    assertIcon(b, GREEN, GREEN);
    assert.ok(b.launcherXml.includes('<color name="launcher_background">#1C6E4A</color>'));
    assert.deepEqual(b.launchBackground.components, { alpha: "1.000", blue: "0x4A", green: "0x6E", red: "0x1C" });
    assert.deepEqual([b.launcher.width, b.launcher.height, b.launch.width, b.launch.height], [100, 100, 100, 100]);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a missing Shopify CLI stops the run before anything else happens", async () => {
  const f = fakes({ shopify: false });
  const t = sandbox();
  try {
    await assert.rejects(
      run(["store-app", "--store", "nalli", "--token", "t"], { ...f, cwd: t.cwd }),
      /Shopify CLI not found — install it with: npm i -g @shopify\/cli/,
    );
    assert.equal(f.calls.length, 1);
    assert.equal(f.urls.length, 0);
    assert.equal(readdirSync(t.cwd).length, 0);
  } finally {
    t.done();
  }
});

test("rejects an empty slug and never writes into a non-empty directory", async () => {
  const f = fakes();
  const t = sandbox();
  try {
    await assert.rejects(run(["!!!", "--demo", "--yes"], { ...f, cwd: t.cwd }), /Project name must contain letters or numbers/);

    mkdirSync(join(t.cwd, "taken"));
    writeFileSync(join(t.cwd, "taken", "mine.txt"), "keep");
    await assert.rejects(run(["taken", "--demo", "--yes"], { ...f, cwd: t.cwd }), /Directory taken already exists and is not empty/);
    assert.equal(readFileSync(join(t.cwd, "taken", "mine.txt"), "utf8"), "keep");
    assert.deepEqual(readdirSync(join(t.cwd, "taken")), ["mine.txt"]);
    assert.equal(f.urls.length, 0, "refused before any network call");

    mkdirSync(join(t.cwd, "empty"));
    await run(["empty", "--demo", "--yes"], { ...f, cwd: t.cwd });
    assert.ok(existsSync(join(t.cwd, "empty", "android", "shopify.properties")), "an empty directory is fine");
  } finally {
    t.done();
  }
});

test("configText: one line per key, no scheme, values safe for each file format", () => {
  const values = { SHOP_DOMAIN: "https://a.myshopify.com/", APP_NAME: "Café \\ // Shop", PDP_METAFIELDS: "" };
  assert.equal(configText(values, "ios"), "SHOP_DOMAIN = a.myshopify.com\nAPP_NAME = Café \\ /$()/ Shop\nPDP_METAFIELDS = \n");
  assert.equal(configText(values, "android"), "SHOP_DOMAIN=a.myshopify.com\nAPP_NAME=Caf\\u00e9 \\\\ // Shop\nPDP_METAFIELDS=\n");
});

test("configText: xcconfig never keeps two slashes in a row, however many there are", () => {
  assert.equal(configText({ APP_NAME: "a///b" }, "ios"), "APP_NAME = a/$()/$()/b\n");
  assert.equal(configText({ APP_NAME: "a////b//" }, "ios").includes("//"), false);
});

test("xtoolFiles: the display name is XML-escaped", () => {
  const files = xtoolFiles({ appName: "Fish & <Chips>", bundleId: "com.x.y", operations: ["Shop"] });
  assert.ok(files["Xtool-Info.plist"].includes("<string>Fish &amp; &lt;Chips&gt;</string>"));
  // the SDKs' own collection starts off, with or without an SDK, as in the template's Info.plist
  const template = readFileSync(new URL("../templates/ios/Info.plist", import.meta.url), "utf8");
  const off = [...files["Xtool-Info.plist"].matchAll(/<key>(.+)<\/key>\n\t<false\/>/g)].map((match) => match[1]);
  assert.deepEqual(off, ["FacebookAutoLogAppEventsEnabled", "FacebookAdvertiserIDCollectionEnabled", "FIREBASE_ANALYTICS_COLLECTION_ENABLED",
    "FirebaseAutomaticScreenReportingEnabled", "FirebaseAppDelegateProxyEnabled"]);
  for (const key of off) assert.match(template, new RegExp(`<key>${key}</key>\\s*<false/>`), key);
  assert.ok(files["xtool.yml"].endsWith("- App/Resources/queries/Shop.graphql\n"));
  assert.ok(files["xtool.yml"].includes("\niconPath: App/Assets.xcassets/AppIcon.appiconset/AppIcon.png\n"));
});

test("push: Firebase Messaging, the iOS push entitlement and the devices URL, only with --push", async () => {
  const cwd = mkdtempSync(join(tmpdir(), "argon-test-"));
  try {
    const base = { appName: "Nalli", bundleId: "com.nalli.app", shopDomain: "nalli.myshopify.com", token: "t", clientId: "", shopId: "1",
      firebaseAndroid: Buffer.from("{}"), firebaseIos: Buffer.from("<plist/>"), settingsUrl: "https://k.web.app/v1/settings/nalli.myshopify.com" };
    const dir = join(cwd, "push-app");
    await scaffold({ ...base, dir, push: true });
    const props = readFileSync(join(dir, "android/shopify.properties"), "utf8").split("\n");
    assert.ok(props.includes("PUSH=true"));
    assert.ok(props.includes("DEVICES_URL=https://k.web.app/v1/devices/nalli.myshopify.com"));
    assert.match(readFileSync(join(dir, "ios/App/App.entitlements"), "utf8"), /<key>aps-environment<\/key>/);
    const project = readFileSync(join(dir, "ios/App.xcodeproj/project.pbxproj"), "utf8");
    assert.equal(project.match(/CODE_SIGN_ENTITLEMENTS = App\/App\.entitlements;/g).length, 2, "the app target's Debug and Release, not the tests");
    assert.match(readFileSync(join(dir, "ios/Package.swift"), "utf8"), /\.product\(name: "FirebaseMessaging", package: "firebase-ios-sdk"\)/);
    assert.match(project, /productName = FirebaseMessaging;/, "in the Xcode project too");
    assert.match(readFileSync(join(dir, "ios/xtool.yml"), "utf8"), /\nentitlementsPath: App\/App\.entitlements\n/);
    assert.match(readFileSync(join(dir, "ios/Package.swift"), "utf8"), /"GoogleService-Info\.plist", "App\.entitlements"/, "not one of the target's sources");

    const plain = join(cwd, "plain-app");
    await scaffold({ ...base, dir: plain });
    assert.ok(readFileSync(join(plain, "android/shopify.properties"), "utf8").split("\n").includes("PUSH=false"));
    assert.ok(!existsSync(join(plain, "ios/App/App.entitlements")));
    assert.ok(!readFileSync(join(plain, "ios/Package.swift"), "utf8").includes("FirebaseMessaging"));
    const plainProject = readFileSync(join(plain, "ios/App.xcodeproj/project.pbxproj"), "utf8");
    assert.ok(plainProject.includes("productName = FirebaseCrashlytics;") && !plainProject.includes("FirebaseMessaging"));
    assert.ok(!readFileSync(join(plain, "ios/xtool.yml"), "utf8").includes("entitlementsPath"));
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
});

test("Krypton: a settings URL and a customer redirect are written, and no server/ (the backend reports purchases)", async () => {
  const cwd = mkdtempSync(join(tmpdir(), "argon-test-"));
  try {
    const dir = join(cwd, "krypton-app");
    await scaffold({
      dir, appName: "Nalli", bundleId: "com.nalli.app", shopDomain: "nalli.myshopify.com", token: "t", clientId: "0123456789abcdef0123456789abcdef", shopId: "1",
      metaAppId: "123", metaClientToken: "abc",
      settingsUrl: "https://k.web.app/v1/settings/nalli.myshopify.com", customerRedirectUri: "https://k.web.app/customer-account/callback",
    });
    const props = readFileSync(join(dir, "android/shopify.properties"), "utf8").split("\n");
    assert.ok(props.includes("SETTINGS_URL=https://k.web.app/v1/settings/nalli.myshopify.com"));
    assert.ok(props.includes("CUSTOMER_REDIRECT_URI=https://k.web.app/customer-account/callback"));
    // xcconfig keeps the two slashes of a URL with /$()/
    const xcconfig = readFileSync(join(dir, "ios/Config.xcconfig"), "utf8").split("\n");
    assert.ok(xcconfig.includes("SETTINGS_URL = https:/$()/k.web.app/v1/settings/nalli.myshopify.com"));
    assert.ok(!existsSync(join(dir, "server")), "Meta's purchase goes through the backend, not server/");

    const plain = join(cwd, "argon-app");
    await scaffold({ dir: plain, appName: "Nalli", bundleId: "com.nalli.app", shopDomain: "nalli.myshopify.com", token: "t", clientId: "", shopId: "1" });
    const plainProps = readFileSync(join(plain, "android/shopify.properties"), "utf8").split("\n");
    assert.ok(plainProps.includes("SETTINGS_URL=") && plainProps.includes("CUSTOMER_REDIRECT_URI="), "empty without Krypton");
  } finally {
    rmSync(cwd, { recursive: true, force: true });
  }
});
