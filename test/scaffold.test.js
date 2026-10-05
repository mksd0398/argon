import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { run, configText } from "../lib/index.js";
import { loadContract } from "../lib/contract.js";

const WHICH = process.platform === "win32" ? "where" : "command";
const flag = (args, name) => args[args.indexOf(name) + 1];

/**
 * Fake exec/fetch. Records every call; `shopify store execute` answers from the query text (everything exists).
 * gitThrows: every `git -C <dir> ...` call throws, like defaultExec refusing an unsafe path.
 */
function fakes({ git = true, gitThrows = false, shopify = true, shopName = "Mock.shop", password = false, passwordFails = false } = {}) {
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
    if (init?.method !== "POST") {
      if (passwordFails) throw new Error("network down");
      return { status: password ? 302 : 200, headers: new Headers(password ? { location: "/password" } : {}) };
    }
    const body = { data: { shop: { id: "gid://shopify/Shop/68817551382", name: shopName } } };
    return { ok: true, status: 200, json: async () => body };
  };
  return { calls, urls, exec, fetch };
}

/** A fresh temp cwd, console capture and no terminal. restore() undoes the capture; done() also removes the cwd. */
function sandbox() {
  const cwd = mkdtempSync(join(tmpdir(), "argon-test-"));
  const lines = [], log = console.log, tty = Object.getOwnPropertyDescriptor(process.stdin, "isTTY");
  console.log = (s = "") => lines.push(s);
  Object.defineProperty(process.stdin, "isTTY", { value: false, configurable: true });
  const restore = () => {
    console.log = log;
    tty ? Object.defineProperty(process.stdin, "isTTY", tty) : delete process.stdin.isTTY;
  };
  return { cwd, restore, out: () => lines.join("\n"), done: () => (restore(), rmSync(cwd, { recursive: true, force: true })) };
}

async function withRun(argv, deps, check) {
  const t = sandbox();
  try {
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

test("--demo --yes scaffolds both apps against mock.shop", async () => {
  const f = fakes();
  const contract = await loadContract();
  await withRun(["demo-app", "--demo", "--yes"], f, (cwd, out) => {
    const dir = join(cwd, "demo-app");
    const props = readFileSync(join(dir, "android/shopify.properties"), "utf8");
    for (const line of ["SHOP_DOMAIN=mock.shop", "SHOP_ID=68817551382", "STOREFRONT_TOKEN=", "CUSTOMER_CLIENT_ID=",
      "API_VERSION=2026-10", "APP_NAME=Mock.shop", "BUNDLE_ID=com.mockshop.demoapp", "PDP_METAFIELDS="]) {
      assert.ok(props.split("\n").includes(line), `shopify.properties has ${line}`);
    }
    const xcconfig = readFileSync(join(dir, "ios/Config.xcconfig"), "utf8");
    assert.ok(xcconfig.split("\n").includes("SHOP_DOMAIN = mock.shop"));
    assert.ok(xcconfig.split("\n").includes("SHOP_ID = 68817551382"));

    const android = queryFiles(join(dir, "android/app/src/main/assets/queries"));
    const ios = queryFiles(join(dir, "ios/App/Resources/queries"));
    assert.equal(android.length, 18);
    assert.deepEqual(ios, android);
    for (const folder of ["android/app/src/main/assets/queries", "ios/App/Resources/queries"]) {
      for (const [name, document] of contract) {
        assert.equal(readFileSync(join(dir, folder, `${name}.graphql`), "utf8"), document, `${folder}/${name}`);
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
    assert.deepEqual(f.urls, ["https://mock.shop/api/2026-10/graphql.json"]);
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
  const f = fakes({ shopName: "Nalli Silks", password: true });
  const argv = ["store-app", "--store", "https://Nalli.myshopify.com/", "--token", "tok123", "--client-id", "cid456", "--yes"];
  await withRun(argv, f, (cwd, out) => {
    const cli = f.calls.filter(([cmd]) => cmd === WHICH || cmd === "shopify").map((c) => c.slice(0, 3).join(" "));
    assert.equal(cli[0], `${WHICH} ${process.platform === "win32" ? "shopify" : "-v shopify"}`);
    assert.equal(cli[1], "shopify store auth");
    assert.ok(cli.slice(2).every((c) => c === "shopify store execute"));
    assert.deepEqual(f.urls, ["https://nalli.myshopify.com/", "https://nalli.myshopify.com/api/2026-10/graphql.json"]);

    assert.ok(out.includes("Store uses legacy customer accounts"), "provision warnings are printed");
    assert.ok(out.includes("Storefront password is on — Checkout Kit can't open checkout until it's off"));
    const at = (text) => {
      const i = out.indexOf(text);
      assert.ok(i >= 0, `output has "${text}"`);
      return i;
    };
    assert.ok(at("1. Install the Headless channel") < at("2. Create a storefront"));
    assert.ok(at("2. Create a storefront") < at("3. Copy the public Storefront token"));
    assert.ok(at("3. Copy the public Storefront token") < at("4. In Customer Account API settings"));
    assert.ok(at("4. In Customer Account API settings") < at("shop.68817551382.app://callback"), "callback needs the shop id");
    assert.ok(!out.includes("Login hidden"), "a client id was given");

    const dir = join(cwd, "store-app");
    const props = readFileSync(join(dir, "android/shopify.properties"), "utf8").split("\n");
    for (const line of ["SHOP_DOMAIN=nalli.myshopify.com", "STOREFRONT_TOKEN=tok123", "CUSTOMER_CLIENT_ID=cid456",
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
    assert.ok(out.includes("Login hidden until CUSTOMER_CLIENT_ID is set"));
    assert.ok(readFileSync(join(cwd, "store-app/android/shopify.properties"), "utf8").includes("CUSTOMER_CLIENT_ID=\n"));
  });
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
