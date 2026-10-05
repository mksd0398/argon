/**
 * Argon: CLI core.
 *
 * Generates a native iOS + Android Shopify storefront app.
 */
import { chmodSync, cpSync, existsSync, mkdirSync, readdirSync, renameSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import prompts from "prompts";
import { loadContract } from "./contract.js";
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
const VALUE = { "--store": "store", "--token": "token", "--client-id": "clientId", "--bundle-id": "bundleId" };

export function parseArgs(argv) {
  const o = {
    name: undefined, demo: false, store: undefined, token: undefined, clientId: undefined,
    bundleId: undefined, skipContent: false, yes: false, help: false,
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

// ─── Scaffold ────────────────────────────────────────────────────────────
const TEMPLATES = fileURLToPath(new URL("../templates/", import.meta.url));

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

export async function scaffold({ dir, appName, bundleId, shopDomain, token, clientId, shopId, pdpMetafields = "" }) {
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

  const values = {
    SHOP_DOMAIN: shopDomain,
    STOREFRONT_TOKEN: token,
    CUSTOMER_CLIENT_ID: clientId,
    SHOP_ID: shopId,
    API_VERSION,
    APP_NAME: appName,
    BUNDLE_ID: bundleId,
    PDP_METAFIELDS: pdpMetafields,
  };
  writeFileSync(join(dir, "ios/Config.xcconfig"), configText(values, "ios"));
  writeFileSync(join(dir, "android/shopify.properties"), configText(values, "android"));

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

const onCancel = () => {
  console.log("\n  Cancelled.\n");
  process.exit(0);
};

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

    section("Headless channel (one manual step in Shopify admin)");
    console.log(`  Open https://${domain}/admin, then:`);
    console.log("    1. Install the Headless channel");
    console.log("    2. Create a storefront");
    console.log("    3. Make your products and collections available to the Headless channel, and keep the storefront's");
    console.log("       metaobject read permission on (otherwise the app shows an empty or fallback home)");
    console.log("    4. Copy the public Storefront token");
    token = o.token ?? (await ask("Storefront access token"));
  }

  const shop = await shopify.verifyStorefront(domain, token);
  if (!o.demo) {
    ok(`Storefront token works for ${shop.name}`);
    console.log(`    5. In Customer Account API settings, add a Mobile client with callback shop.${shop.shopId}.app://callback, then copy its client ID`);
  }

  const clientId = o.demo ? "" : (o.clientId ?? (interactive ? await ask("Customer Account API client ID (blank to skip)", "", () => true) : ""));
  if (!clientId) info("Login hidden until CUSTOMER_CLIENT_ID is set");

  section("Generating the apps");
  await scaffold({
    dir,
    appName: shop.name,
    bundleId: o.bundleId ?? bundleIdFor(slug, domain),
    shopDomain: domain,
    token,
    clientId,
    shopId: shop.shopId,
  });
  ok(`Created ${name}/ (ios + android)`);
  await gitInit(exec, dir);

  console.log(`
  ${c.bold}Next steps${c.reset}

    cd ${name}
    Open ios/App.xcodeproj in Xcode 16+
    Open android/ in Android Studio

  ${c.bold}Store checklist${c.reset} (details in README.md)

    - New customer accounts are on (login)
    - Storefront password is off (checkout)
    - Products and collections are available to the Headless channel (home and product lists)
    - Search & Discovery filters are set up (collection and search filters)
`);
}
