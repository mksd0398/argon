/**
 * Argon: CLI core.
 *
 * Generates a native iOS + Android Shopify storefront app.
 */
import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import prompts from "prompts";
import { loadContract } from "./contract.js";
import { backgroundOf, compose, decodePng, encodePng, fit, plainIcon } from "./png.js";
import { API_VERSION, createShopify, defaultExec } from "./shopify.js";

// ─── ANSI helpers (no chalk dependency) ──────────────────────────────────
const c = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  green: "\x1b[32m",
  cyan: "\x1b[36m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
};

const ok = (msg) => console.log(`  ${c.green}✔${c.reset} ${msg}`);
const warn = (msg) => console.log(`  ${c.yellow}⚠${c.reset} ${msg}`);
const info = (msg) => console.log(`  ${c.cyan}ℹ${c.reset} ${msg}`);
const fail = (msg) => console.log(`  ${c.red}✘${c.reset} ${msg}`);
const section = (title) => {
  console.log();
  console.log(`  ${c.cyan}===${c.reset} ${c.bold}${title}${c.reset} ${c.cyan}===${c.reset}`);
  console.log();
};

// ─── Arguments ───────────────────────────────────────────────────────────
const BOOLEAN = { "--demo": "demo", "--skip-content": "skipContent", "--yes": "yes", "--help": "help", "-h": "help" };
const VALUE = {
  "--store": "store", "--token": "token", "--client-id": "clientId", "--bundle-id": "bundleId",
  "--home": "home", "--collection": "collection", "--judgeme-token": "judgemeToken",
};

/** The page templates every app carries; HOME_TEMPLATE and COLLECTION_TEMPLATE pick one. The first is the default. */
export const HOME_TEMPLATES = [
  { value: "fashion", title: "Fashion: editorial, image-led" },
  { value: "beauty", title: "Beauty: soft cards, ratings, shop by routine" },
  { value: "grocery", title: "Grocery: search first, dense, quick add" },
  { value: "b2b", title: "Industrial & B2B: SKUs, trade prices, bulk quantities" },
];
export const COLLECTION_TEMPLATES = [
  { value: "top", title: "Sort and filters in a sticky bar at the top" },
  { value: "bottom", title: "Sort and filters in a floating bar at the bottom" },
];

export function parseArgs(argv) {
  const o = {
    name: undefined, demo: false, store: undefined, token: undefined, clientId: undefined,
    bundleId: undefined, home: undefined, collection: undefined, judgemeToken: undefined, skipContent: false, yes: false, help: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("-")) {
      o.name ??= arg;
      continue;
    }
    const eq = arg.indexOf("=");
    const flag = eq < 0 ? arg : arg.slice(0, eq);
    if (flag in BOOLEAN) o[BOOLEAN[flag]] = true;
    else if (flag in VALUE) {
      const value = eq < 0 ? argv[++i] : arg.slice(eq + 1);
      if (value === undefined || value.startsWith("--")) throw new Error(`Missing value for ${flag}`);
      o[VALUE[flag]] = value;
    } else throw new Error(`Unknown option ${flag}`);
  }
  for (const [flag, value, templates] of [["--home", o.home, HOME_TEMPLATES], ["--collection", o.collection, COLLECTION_TEMPLATES]]) {
    const values = templates.map((t) => t.value);
    if (value !== undefined && !values.includes(value)) throw new Error(`${flag} must be one of: ${values.join(", ")}`);
  }
  return o;
}

// ─── Naming rules ────────────────────────────────────────────────────────
export const slugify = (name) =>
  name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

/** "nalli", "Nalli.myshopify.com", "https://nalli.myshopify.com/" -> "nalli.myshopify.com" */
export function normalizeStore(input) {
  let host = input.trim().toLowerCase().replace(/^https?:\/\//, "").split(/[/?#]/)[0];
  if (!host.includes(".")) host += ".myshopify.com";
  if (!/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(host)) {
    throw new Error(`"${input}" is not a store domain: use your store's *.myshopify.com domain`);
  }
  return host;
}

// ponytail: Java keywords are not handled; --bundle-id overrides (run() rejects an empty slug)
const segment = (s) => {
  s = s.toLowerCase().replace(/[^a-z0-9]/g, "");
  return /^\d/.test(s) ? `a${s}` : s;
};

/** ("my-store-app", "nalli.myshopify.com") -> "com.nalli.mystoreapp" */
export const bundleIdFor = (slug, storeDomain) =>
  `com.${segment(storeDomain.replace(/\.myshopify\.com$/i, ""))}.${segment(slug)}`;

// ─── Run ─────────────────────────────────────────────────────────────────
function printHelp() {
  console.log(`
  ${c.bold}Argon${c.reset}

  Generate a native iOS + Android Shopify storefront app in one command.

  ${c.bold}Usage:${c.reset}

    ${c.cyan}npx @mksd0398/argon${c.reset} [project-name] [options]

  ${c.bold}Options:${c.reset}

    --demo                   Use the mock.shop demo store (no Shopify account needed)
    --store=DOMAIN           Your store's *.myshopify.com domain (or just the handle)
    --token=TOKEN            Public Storefront API access token
    --client-id=ID           Customer Account API client ID (omit to hide login)
    --bundle-id=ID           Bundle / application ID (default: com.<store>.<project>)
    --home=TEMPLATE          Home screen: fashion (default), beauty, grocery or b2b
    --collection=TEMPLATE    Collection filters: top (default, sticky bar) or bottom (floating bar)
    --judgeme-token=TOKEN    Judge.me public API token (omit to hide product reviews)
    --skip-content           Don't create the home screen content metaobjects
    --yes                    Accept defaults, ask nothing
    --help                   Show this help
`);
}

// ─── Config files ────────────────────────────────────────────────────────
// xcconfig starts a comment at `//`; `/$()/` is the usual way to keep two slashes.
// Java reads .properties as Latin-1, so backslashes and non-ASCII (shop names) are written as escapes.
const xcconfigValue = (v) => v.replace(/\/(?=\/)/g, "/$()");
const propertiesValue = (v) =>
  v.replaceAll("\\", "\\\\").replace(/[^\x20-\x7e]/g, (ch) => `\\u${ch.charCodeAt(0).toString(16).padStart(4, "0")}`);

/** values: { KEY: value }; platform: "ios" (`KEY = value`, xcconfig) or "android" (`KEY=value`, .properties). */
export function configText(values, platform) {
  return (
    Object.entries(values)
      .map(([key, value]) => {
        value = String(value ?? "");
        if (key === "SHOP_DOMAIN") value = value.replace(/^https?:\/\//, "").replace(/\/+$/, "");
        return platform === "ios" ? `${key} = ${xcconfigValue(value)}` : `${key}=${propertiesValue(value)}`;
      })
      .join("\n") + "\n"
  );
}

// xtool (iOS without a Mac) builds ios/Package.swift instead of the Xcode project. It has no build settings, so the
// display name is written as a literal, and every file the app reads from its bundle is listed: xtool copies those to
// the app's top level (Config.xcconfig is where the app then finds its per-store values). It can't compile an asset
// catalog either, so it is pointed at the icon's PNG inside it.
const xmlText = (v) => v.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
const IOS_ASSETS = "App/Assets.xcassets";
const IOS_ICON = `${IOS_ASSETS}/AppIcon.appiconset/AppIcon.png`;

/**
 * { file name in ios/: text } for an xtool build of the app. operations: the contract's operation names;
 * resources: more files the app reads from its bundle, as paths in ios/.
 */
export function xtoolFiles({ appName, bundleId, operations, resources = [] }) {
  return {
    "xtool.yml": [
      "version: 1",
      `bundleID: ${bundleId}`,
      "infoPath: Xtool-Info.plist",
      `iconPath: ${IOS_ICON}`,
      "resources:",
      "- Config.xcconfig",
      "- App/PrivacyInfo.xcprivacy",
      ...[...operations].sort().map((name) => `- App/Resources/queries/${name}.graphql`),
      ...[...resources].sort().map((path) => `- ${path}`),
    ].join("\n") + "\n",
    "Xtool-Info.plist": `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>${xmlText(appName)}</string>
</dict>
</plist>
`,
  };
}

// ─── Scaffold ────────────────────────────────────────────────────────────
const TEMPLATES = fileURLToPath(new URL("../templates/", import.meta.url));
const FIXTURES = fileURLToPath(new URL("../contract/fixtures/", import.meta.url));
const IMAGES = join(TEMPLATES, "images");
const CUSTOMER_OPERATIONS = fileURLToPath(new URL("../contract/customer/", import.meta.url));

const assertFreshDir = (dir) => {
  if (existsSync(dir) && !(statSync(dir).isDirectory() && readdirSync(dir).length === 0)) {
    throw new Error(`Directory ${basename(dir)} already exists and is not empty`);
  }
};

// npm strips dotfiles from packages, so templates ship `gitignore`
const renameGitignores = (dir) => {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) renameGitignores(path);
    else if (entry.name === "gitignore") renameSync(path, join(dir, ".gitignore"));
  }
};

// The design's ink and paper: the default icon's colours
const INK = "#17150F";
const PAPER = "#F6F4F0";
const channels = (colour) => [1, 3, 5].map((i) => colour.slice(i, i + 2));
// Rec. 601 luma of a "#RRGGBB" colour, 0...255: how light it looks
const luma = (colour) => channels(colour).reduce((sum, hex, n) => sum + parseInt(hex, 16) * [0.299, 0.587, 0.114][n], 0);

const colorSet = (colour) => {
  const [red, green, blue] = channels(colour).map((hex) => `0x${hex}`);
  const color = { "color-space": "srgb", components: { alpha: "1.000", blue, green, red } };
  return JSON.stringify({ colors: [{ color, idiom: "universal" }], info: { author: "xcode", version: 1 } }, null, 2) + "\n";
};

/**
 * Writes the app icon and the launch screen into the project at `dir`. They are part of the binary, so they are made
 * at generation, from the store's logo.
 * logo: a decoded image (lib/png.js). Without one Android keeps the template's own icon, and iOS gets a plain mark on
 * brandColor ("#RRGGBB", the brand's primary colour) or ink.
 * The asset catalog's other Contents.json files (the icon set, the image set) are the iOS template's.
 */
export function writeAppIcon(dir, { logo, brandColor } = {}) {
  const write = (path, content) => {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), content);
  };
  const res = "android/app/src/main/res";
  let background = "#FFFFFF"; // the Android template's launcher_background
  if (logo) {
    background = backgroundOf(logo);
    // 264 px is 66 dp at xxxhdpi: the part of an adaptive icon no launcher's mask cuts off
    write(`${res}/drawable-xxxhdpi/launcher_logo.png`, encodePng(fit(logo, 264, 264)));
    rmSync(join(dir, res, "drawable/launcher_logo.xml"), { force: true }); // the template's mark: a resource can't be both
    write(`${res}/values/launcher.xml`, `<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="launcher_background">${background}</color>\n</resources>\n`);
  }
  const plain = brandColor ?? INK;
  // the mark is paper, or ink where paper wouldn't show on the brand's colour
  const icon = logo ? compose(logo, 1024, background, 0.62) : plainIcon(1024, plain, luma(plain) > 150 ? INK : PAPER);
  write(`ios/${IOS_ICON}`, encodePng(icon, { alpha: false })); // the App Store refuses an icon with an alpha channel
  // an image set can't be empty: one transparent pixel is "no logo"
  const launch = logo ? fit(logo, 600, 600) : { width: 1, height: 1, data: Buffer.alloc(4) };
  write(`ios/${IOS_ASSETS}/LaunchLogo.imageset/LaunchLogo.png`, encodePng(launch));
  write(`ios/${IOS_ASSETS}/LaunchBackground.colorset/Contents.json`, colorSet(background));
}

export async function scaffold({
  dir, appName, bundleId, shopDomain, token, clientId, shopId, pdpMetafields = "",
  homeTemplate = HOME_TEMPLATES[0].value, collectionTemplate = COLLECTION_TEMPLATES[0].value, judgemeToken = "",
  logo, brandColor,
}) {
  const contract = await loadContract();
  assertFreshDir(dir); // never overwrite user files; nothing awaits between this check and the writes

  mkdirSync(dir, { recursive: true });
  for (const part of ["android", "ios"]) cpSync(join(TEMPLATES, part), join(dir, part), { recursive: true });
  cpSync(join(TEMPLATES, "shared"), dir, { recursive: true });
  renameGitignores(dir);

  for (const folder of ["android/app/src/main/assets/queries", "ios/App/Resources/queries"]) {
    mkdirSync(join(dir, folder), { recursive: true });
    for (const [name, document] of contract) writeFileSync(join(dir, folder, `${name}.graphql`), document);
  }
  // One recorded or hand-written response `data` per operation, for the apps' decoding tests
  for (const folder of ["android/app/src/test/resources/fixtures", "ios/AppTests/Fixtures"]) {
    cpSync(FIXTURES, join(dir, folder), { recursive: true });
  }

  // The home templates' placeholder banners (templates/images/CREDITS.md), shown until the store has its own
  const resources = [];
  const images = readdirSync(IMAGES).filter((f) => f.endsWith(".jpg"));
  for (const folder of ["android/app/src/main/assets/home", "ios/App/Resources/home"]) {
    mkdirSync(join(dir, folder), { recursive: true });
    for (const image of images) cpSync(join(IMAGES, image), join(dir, folder, image));
  }
  resources.push(...images.map((image) => `App/Resources/home/${image}`));
  // The demo store has no customer accounts and no reviews app: its Account tab previews a sample account from the
  // Customer Account fixtures, and its product pages show sample reviews from the Judge.me widget fixture
  if (shopDomain === "mock.shop") {
    const operations = readdirSync(CUSTOMER_OPERATIONS).filter((f) => f !== "fragments.graphql").map((f) => f.slice(0, -".graphql".length));
    // The fixtures are written for the decoding tests; three things differ so the preview reads well:
    // the address delete succeeds (the fixture is the refusal of deleting the default address), the order has no
    // discount (the fixture's isn't in its totals), and the review's photo is a real picture (the fixture's URL is made up)
    const sample = (name) => {
      const data = JSON.parse(readFileSync(join(FIXTURES, `${name}.json`), "utf8"));
      if (name === "CustomerAddressDelete") data.customerAddressDelete = { deletedAddressId: "gid://shopify/CustomerAddress/8000002", userErrors: [] };
      if (name === "Order") data.order.discountApplications.nodes = [];
      return JSON.stringify(data, null, 2) + "\n";
    };
    const photo = JSON.parse(readFileSync(join(FIXTURES, "Order.json"), "utf8")).order.lineItems.nodes[0].image.url;
    const reviews = readFileSync(join(FIXTURES, "JudgeMeWidget.html"), "utf8").replaceAll(/https:\/\/review-images\.judgeme\.com\/[^?'"]+/g, photo);
    for (const folder of ["android/app/src/main/assets/sample", "ios/App/Resources/sample"]) {
      mkdirSync(join(dir, folder), { recursive: true });
      for (const name of operations) writeFileSync(join(dir, folder, `${name}.sample.json`), sample(name));
      writeFileSync(join(dir, folder, "JudgeMeWidget.sample.html"), reviews);
    }
    resources.push(...operations.map((name) => `App/Resources/sample/${name}.sample.json`), "App/Resources/sample/JudgeMeWidget.sample.html");
  }

  const values = {
    SHOP_DOMAIN: shopDomain,
    STOREFRONT_TOKEN: token,
    CUSTOMER_CLIENT_ID: clientId,
    SHOP_ID: shopId,
    API_VERSION,
    APP_NAME: appName,
    BUNDLE_ID: bundleId,
    PDP_METAFIELDS: pdpMetafields,
    HOME_TEMPLATE: homeTemplate,
    COLLECTION_TEMPLATE: collectionTemplate,
    JUDGEME_PUBLIC_TOKEN: judgemeToken,
    SHOW_VENDOR: "false",
    ONBOARDING: "true",
    // the demo sets one so its cart shows the free-shipping progress; a real store fills in its own
    FREE_SHIPPING_THRESHOLD: shopDomain === "mock.shop" ? "150" : "",
  };
  writeFileSync(join(dir, "ios/Config.xcconfig"), configText(values, "ios"));
  writeFileSync(join(dir, "android/shopify.properties"), configText(values, "android"));
  for (const [file, text] of Object.entries(xtoolFiles({ appName, bundleId, operations: [...contract.keys()], resources }))) {
    writeFileSync(join(dir, "ios", file), text);
  }
  writeAppIcon(dir, { logo, brandColor });

  const gradlew = join(dir, "android/gradlew");
  if (existsSync(gradlew)) chmodSync(gradlew, 0o755);
}

// ─── Preflight and git ───────────────────────────────────────────────────
const succeeds = (exec, cmd, args) => exec(cmd, args).then((r) => r.code === 0, () => false);

// The Shopify CLI is only looked up, never run: running `shopify` auto-upgrades a global install.
async function preflight(exec, { demo, skipContent }) {
  if (Number(process.versions.node.split(".")[0]) < 18) {
    throw new Error(`Node 18 or newer is required (found ${process.versions.node})`);
  }
  if (!demo && !skipContent) {
    const found = process.platform === "win32"
      ? await succeeds(exec, "where", ["shopify"])
      : await succeeds(exec, "command", ["-v", "shopify"]);
    if (!found) throw new Error("Shopify CLI not found — install it with: npm i -g @shopify/cli");
  }
  const { ANDROID_HOME, ANDROID_SDK_ROOT, LOCALAPPDATA } = process.env;
  const sdkDirs = [
    LOCALAPPDATA && join(LOCALAPPDATA, "Android", "Sdk"),
    join(homedir(), "Library", "Android", "sdk"),
    join(homedir(), "Android", "Sdk"),
  ];
  if (!ANDROID_HOME && !ANDROID_SDK_ROOT && !sdkDirs.some((d) => d && existsSync(d))) {
    warn("Android SDK not found — install Android Studio to build the Android app");
  }
  if (process.platform !== "darwin") info("iOS builds need a Mac with Xcode 16+");
  else if (!(await succeeds(exec, "xcode-select", ["-p"]))) warn("Xcode not found — install Xcode 16+ to build the iOS app");
}

// The project is already written when this runs, so any failure (an unsafe path included) only warns.
async function gitInit(exec, dir) {
  const git = async (...args) => {
    const { code, stderr } = await exec("git", ["-C", dir, ...args]);
    if (code !== 0) throw new Error(`git ${args[0]} failed${stderr?.trim() ? `: ${stderr.trim()}` : ""}`);
  };
  try {
    if (!(await succeeds(exec, "git", ["--version"]))) return;
    await git("init");
    await git("add", "-A");
    // Windows can't set the executable bit on disk, so record it in the index for Mac and Linux checkouts
    if (existsSync(join(dir, "android", "gradlew"))) await git("update-index", "--chmod=+x", "android/gradlew");
    await git("commit", "-m", "Initial Argon scaffold");
    ok("Initialized a git repository");
  } catch (err) {
    warn(`Couldn't create the git repo: ${err.message}`);
  }
}

// ─── Run ─────────────────────────────────────────────────────────────────
const DEFAULT_NAME = "my-store-app";
const NAME_ERROR = "Project name must contain letters or numbers";

const HEADLESS_APP = "https://apps.shopify.com/headless";
// Headless storefronts issue a bare UUID; Hydrogen's are prefixed shp_
const CLIENT_ID = /^(shp_)?[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

// Best effort: if no browser opens, the printed link still works
const openUrl = (exec, url) =>
  (process.platform === "win32"
    ? exec("start", ["", url]) // start's first quoted argument is the window title
    : exec(process.platform === "darwin" ? "open" : "xdg-open", [url])
  ).catch(() => {});

const onCancel = () => {
  console.log("\n  Cancelled.\n");
  process.exit(0);
};

// The store's logo for the app icon and the launch screen: the square logo, else the wide one. Never throws, so a
// logo can't stop a run: { image, source } when one downloads and decodes, { problem } when none did.
async function storeLogo(shopify, domain, token) {
  let brand;
  try {
    brand = await shopify.storefrontLogo(domain, token);
  } catch (err) {
    return { problem: err.message };
  }
  let problem;
  for (const [source, url] of [["square logo", brand.square], ["logo", brand.logo]]) {
    if (!url) continue;
    try {
      return { image: decodePng(await shopify.download(url)), source, primary: brand.primary };
    } catch (err) {
      problem = err.message;
    }
  }
  return { primary: brand.primary, problem };
}

// deps are injected by tests: a fake exec (every external command), a fake fetch, and a temp cwd
export async function run(argv, { exec = defaultExec, fetch = globalThis.fetch, cwd = process.cwd() } = {}) {
  const o = parseArgs(argv);
  if (o.help) return printHelp();

  // Without a terminal (an agent, CI), or with --yes (accept defaults), nothing is asked:
  // a value that has no default is then an error, before anything touches the store
  const interactive = process.stdin.isTTY && !o.yes;
  if (!interactive) {
    const missing = !o.name && !process.stdin.isTTY ? "project name" : !o.demo && !o.store ? "--store" : !o.demo && !o.token ? "--token" : null;
    if (missing) throw new Error(`Missing ${missing} (${process.stdin.isTTY ? "--yes asks nothing" : "no terminal to prompt"})`);
  }
  const ask = async (message, initial = "", validate = (v) => v.trim() !== "" || "Required") => {
    const { value } = await prompts({ type: "text", name: "value", message, initial, validate }, { onCancel });
    return value.trim();
  };

  // Name first, and the directory check before anything touches the store
  const name = o.name ?? (interactive ? await ask("Project name", DEFAULT_NAME, (v) => slugify(v) !== "" || NAME_ERROR) : DEFAULT_NAME);
  const slug = slugify(name);
  if (!slug) throw new Error(NAME_ERROR);
  // ponytail: the name is used as typed for the path (`argon ../x` scaffolds there); the slug comes from the whole string
  const dir = resolve(cwd, name);
  assertFreshDir(dir);

  const domain = o.demo ? "mock.shop" : normalizeStore(o.store ?? (await ask("Store domain (*.myshopify.com)")));

  section("Checking your setup");
  await preflight(exec, o);

  const shopify = createShopify({ exec, fetch });
  let token = "";
  let shop;
  if (!o.demo) {
    if (!o.skipContent) {
      section("Store content");
      await shopify.storeAuth(domain);
      let result;
      try {
        result = await shopify.provision(domain);
      } catch (err) {
        err.message += "\n  If it stopped part-way, delete any entries it created under Content → Metaobjects (Mobile banner, Mobile collections, Mobile products) before re-running.";
        throw err;
      }
      if (result.created.length) ok(`Created metaobject definitions: ${result.created.join(", ")}`);
      else info("Metaobject definitions already exist");
      if (result.seeded) ok("Created the Home screen (Content → Metaobjects → Mobile screen → Home)");
      else info("Home screen entry already exists; left as is");
      for (const message of result.warnings) warn(message);
    }

    try {
      if (await shopify.passwordProtected(domain)) warn("Storefront password is on — Checkout Kit can't open checkout until it's off");
    } catch {
      warn("Couldn't check storefront password");
    }

    section("Headless channel (Shopify admin; Shopify has no API for this part)");
    console.log(`  Install or open it from ${HEADLESS_APP}, then:`);
    if (interactive) await openUrl(exec, HEADLESS_APP);
    console.log("    1. Create a storefront (Sales channels → Headless)");
    console.log("    2. Make your products and collections available to the storefront (each storefront is its own sales channel, by its name)");
    console.log("    3. Storefront API: copy the public access token (Permissions already allow reading metaobjects by default)");
    // The token is checked as it is entered, so a bad paste is asked again instead of ending the run
    token = o.token ?? (await ask("Public Storefront API access token", "", async (v) => {
      if (!v.trim()) return "Required";
      try {
        shop = await shopify.verifyStorefront(domain, v.trim());
        return true;
      } catch (err) {
        return err.message;
      }
    }));
  }

  shop ??= await shopify.verifyStorefront(domain, token);
  if (!o.demo) {
    ok(`Storefront token works for ${shop.name}`);
    let content = {};
    try {
      content = await shopify.storefrontContent(domain, token);
    } catch {} // advisory: the token itself is already verified
    if (content.products) ok("The app can see your products");
    else if (content.products === false) warn("The app sees no products: make them available to the storefront's sales channel");
    if (content.home) ok("The app can read the home screen");
    else if (content.home === false && !o.skipContent) warn("The app can't read the home screen: allow unauthenticated_read_metaobjects in Storefront API permissions");

    console.log("    4. Customer Account API: edit Client type to Public (mobile app) and save. Check that Callback URI(s) shows");
    console.log(`         shop.${shop.shopId}.app://callback`);
    console.log("       (Shopify fills it in), then copy the Client ID");
  }

  const clientId = o.demo ? "" : (o.clientId ?? (interactive ? await ask("Customer Account API client ID (blank to skip)", "", () => true) : ""));
  if (!clientId) info("Login hidden until CUSTOMER_CLIENT_ID is set");
  else if (!CLIENT_ID.test(clientId)) warn(`"${clientId}" doesn't look like a Customer Account API client ID (a UUID); login fails if it's wrong`);

  // The templates: every app carries all of them, these pick the ones it shows (one line each in the config files)
  const pick = async (message, templates, chosen) => {
    if (chosen || !interactive) return chosen ?? templates[0].value;
    const { value } = await prompts({ type: "select", name: "value", message, choices: templates }, { onCancel });
    return value;
  };
  const homeTemplate = await pick("Home screen", HOME_TEMPLATES, o.home);
  const collectionTemplate = await pick("Collection pages", COLLECTION_TEMPLATES, o.collection);
  // Judge.me admin → Settings → Integrations → View API tokens. The public one only: it is built into the app.
  const judgemeToken = o.judgemeToken ?? (interactive && !o.demo ? await ask("Judge.me public API token, for product reviews (blank to skip)", "", () => true) : "");

  section("Generating the apps");
  const brand = await storeLogo(shopify, domain, token);
  await scaffold({
    dir,
    appName: shop.name,
    bundleId: o.bundleId ?? bundleIdFor(slug, domain),
    shopDomain: domain,
    token,
    clientId,
    shopId: shop.shopId,
    homeTemplate,
    collectionTemplate,
    judgemeToken,
    logo: brand.image,
    brandColor: brand.primary,
  });
  ok(`Created ${name}/ (ios + android)`);
  const defaults = "Android keeps the default icon and iOS gets a plain one (README.md has the files to replace)";
  if (brand.image) ok(`App icon and launch screen: the store's ${brand.source}, on ${backgroundOf(brand.image)}`);
  else if (brand.problem) warn(`Couldn't use the store's logo for the app icon (${brand.problem}). ${defaults}`);
  else info(`The store's brand has no logo for the app icon. ${defaults}`);
  await gitInit(exec, dir);

  console.log(`
  ${c.bold}Next steps${c.reset}

    cd ${name}
    Open ios/App.xcodeproj in Xcode 16+
    Open android/ in Android Studio

  ${c.bold}Store checklist${c.reset} (details in README.md)

    - New customer accounts are on (login)
    - Storefront password is off (checkout)
    - Products and collections are available to the storefront's sales channel (home and product lists)
    - Search & Discovery filters are set up (collection and search filters)
`);
}
