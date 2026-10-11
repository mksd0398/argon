import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildClientSchema, NoDeprecatedCustomRule, parse, specifiedRules, validate } from "graphql";
import { createShopify, defaultExec } from "../lib/shopify.js";
import { decodePng } from "../lib/png.js";
import { loadContract } from "../lib/contract.js";

const STORE = "nalli.myshopify.com";
const SECTION_TYPES = ["mobile_banner", "mobile_products", "mobile_collections"];
const flag = (args, name) => args[args.indexOf(name) + 1];

/** In-memory stand-in for the Admin API behind `shopify store execute`, matching on the query text. */
function fakeAdmin({ collections = [], accounts = "NEW_CUSTOMER_ACCOUNTS", accountsFail = false, taken } = {}) {
  const admin = { defs: new Map(), entries: new Map(), mutations: [], calls: [] };
  let n = 0;
  const gid = (kind) => `gid://shopify/${kind}/${++n}`;
  const payload = (key, field, value) => ({ [key]: { [field]: value, userErrors: [] } });

  const respond = (query, vars) => {
    if (/metaobjectDefinitionByType/.test(query)) {
      const id = admin.defs.get(vars.type);
      return { metaobjectDefinitionByType: id ? { id } : null };
    }
    if (/metaobjectDefinitionCreate\(/.test(query)) {
      const { type } = vars.definition;
      admin.mutations.push({ kind: "definition", input: vars.definition });
      if (type === taken) {
        return { metaobjectDefinitionCreate: { metaobjectDefinition: null, userErrors: [{ field: ["definition", "type"], message: "Type taken" }] } };
      }
      const id = gid("MetaobjectDefinition");
      admin.defs.set(type, id);
      return payload("metaobjectDefinitionCreate", "metaobjectDefinition", { id, type });
    }
    if (/metaobjectByHandle/.test(query)) {
      const id = admin.entries.get("mobile_screen/home");
      return { metaobjectByHandle: id ? { id } : null };
    }
    if (/metaobjectCreate\(/.test(query)) {
      const { type, handle } = vars.metaobject;
      admin.mutations.push({ kind: "entry", input: vars.metaobject });
      const id = gid("Metaobject");
      admin.entries.set(`${type}/${handle}`, id);
      return payload("metaobjectCreate", "metaobject", { id, handle });
    }
    if (/collections\(/.test(query)) return { shop: { name: "Nalli" }, collections: { nodes: collections } };
    if (/customerAccountsV2/.test(query)) {
      if (accountsFail) return null;
      return { shop: { customerAccountsV2: { customerAccountsVersion: accounts } } };
    }
    throw new Error(`fake admin: unexpected query ${query}`);
  };

  admin.exec = async (cmd, args, opts) => {
    admin.calls.push({ cmd, args, opts });
    if (args[1] === "auth") return { code: 0, stdout: "", stderr: "" };
    const query = readFileSync(flag(args, "--query-file"), "utf8");
    const vars = JSON.parse(readFileSync(flag(args, "--variable-file"), "utf8"));
    // like the real CLI: mutations are refused unless --allow-mutations is passed
    if (/^\s*mutation\b/.test(query) && !args.includes("--allow-mutations")) {
      return { code: 1, stdout: "", stderr: "Mutations are disabled. Re-run with --allow-mutations.\n" };
    }
    const data = respond(query, vars);
    if (data === null) return { code: 1, stdout: "", stderr: "Access denied for customerAccountsV2.\n" };
    writeFileSync(flag(args, "--output-file"), JSON.stringify(data, null, 2));
    return { code: 0, stdout: "Operation succeeded.\n", stderr: "" };
  };
  return admin;
}

function setup(t, admin = fakeAdmin(), extra = {}) {
  const tmpDir = mkdtempSync(join(tmpdir(), "argon-test-"));
  t.after(() => rmSync(tmpDir, { recursive: true, force: true }));
  return { admin, shopify: createShopify({ exec: admin.exec, tmpDir, ...extra }) };
}

const entryFields = (entry) => Object.fromEntries(entry.fields.map((f) => [f.key, f.value]));

test("provision, first run: definitions, then the screen definition, then seed entries, then the home screen", async (t) => {
  const collections = [
    { id: "gid://shopify/Collection/1", productsCount: { count: 5, precision: "EXACT" } },
    { id: "gid://shopify/Collection/2", productsCount: { count: 0, precision: "EXACT" } },
  ];
  const { admin, shopify } = setup(t, fakeAdmin({ collections }));

  const result = await shopify.provision(STORE);
  assert.deepEqual(result, { created: [...SECTION_TYPES, "mobile_screen"], seeded: true, warnings: [] });

  const kinds = admin.mutations.map((m) => m.kind);
  assert.deepEqual(kinds, ["definition", "definition", "definition", "definition", "entry", "entry", "entry", "entry"]);
  assert.deepEqual(admin.mutations.slice(0, 4).map((m) => m.input.type), [...SECTION_TYPES, "mobile_screen"]);

  // the screen definition allows exactly the three section definitions
  const screenDef = admin.mutations[3].input;
  const allowed = screenDef.fieldDefinitions.find((f) => f.key === "sections").validations[0];
  assert.equal(allowed.name, "metaobject_definition_ids");
  assert.deepEqual(JSON.parse(allowed.value), SECTION_TYPES.map((type) => admin.defs.get(type)));

  // seed: a collection reported as productsCount { count: 5 } is used, the empty one is not
  const [hero, collectionsSection, featured, home] = admin.mutations.slice(4).map((m) => m.input);
  assert.deepEqual([hero.handle, collectionsSection.handle, featured.handle, home.handle], ["home-hero", "home-collections", "home-featured", "home"]);
  assert.equal(entryFields(hero).heading, "Nalli");
  assert.deepEqual(JSON.parse(entryFields(collectionsSection).collections), ["gid://shopify/Collection/1"]);
  assert.equal(entryFields(featured).collection, "gid://shopify/Collection/1");

  // the home screen lists the ids of the three entries just created, in order
  const seedIds = ["mobile_banner/home-hero", "mobile_collections/home-collections", "mobile_products/home-featured"].map((k) => admin.entries.get(k));
  assert.deepEqual(JSON.parse(entryFields(home).sections), seedIds);
});

test("provision, re-run: nothing exists to create, so no mutation runs", async (t) => {
  const { admin, shopify } = setup(t, fakeAdmin({ collections: [{ id: "gid://shopify/Collection/1", productsCount: { count: 2 } }] }));
  await shopify.provision(STORE);
  const before = admin.mutations.length;
  const mutationRuns = () => admin.calls.filter((c) => c.args.includes("--allow-mutations")).length;
  const runsBefore = mutationRuns();

  const again = await shopify.provision(STORE);
  assert.deepEqual(again, { created: [], seeded: false, warnings: [] });
  assert.equal(admin.mutations.length, before);
  assert.equal(mutationRuns(), runsBefore);
});

test("provision: existing section definitions are skipped but their ids still go into the screen definition", async (t) => {
  const admin = fakeAdmin();
  SECTION_TYPES.forEach((type, i) => admin.defs.set(type, `gid://shopify/MetaobjectDefinition/${900 + i}`));
  const { shopify } = setup(t, admin);

  const { created } = await shopify.provision(STORE);
  assert.deepEqual(created, ["mobile_screen"]);
  const allowed = admin.mutations[0].input.fieldDefinitions.find((f) => f.key === "sections").validations[0];
  assert.deepEqual(JSON.parse(allowed.value), SECTION_TYPES.map((_, i) => `gid://shopify/MetaobjectDefinition/${900 + i}`));
});

test("provision: a store with no collections seeds just the hero banner and the home screen", async (t) => {
  const { admin, shopify } = setup(t);
  assert.equal((await shopify.provision(STORE)).seeded, true);
  assert.deepEqual(admin.mutations.slice(4).map((m) => m.input.handle), ["home-hero", "home"]);
});

test("provision: userErrors reject with their message", async (t) => {
  const { shopify } = setup(t, fakeAdmin({ taken: "mobile_products" }));
  await assert.rejects(shopify.provision(STORE), /Type taken/);
});

test("provision: customer accounts check warns on legacy accounts", async (t) => {
  const { shopify } = setup(t, fakeAdmin({ accounts: "CLASSIC" }));
  const { warnings } = await shopify.provision(STORE);
  assert.deepEqual(warnings, ["Store uses legacy customer accounts; turn on new customer accounts for login"]);
});

test("provision: a failing customer accounts query only adds a warning", async (t) => {
  const { shopify } = setup(t, fakeAdmin({ accountsFail: true }));
  const result = await shopify.provision(STORE);
  assert.deepEqual(result.warnings, ["Couldn't check customer account version"]);
  assert.equal(result.seeded, true);
});

test("storeAuth runs shopify store auth with the three scopes, interactively", async (t) => {
  const { admin, shopify } = setup(t);
  await shopify.storeAuth(STORE);
  assert.deepEqual(admin.calls, [{
    cmd: "shopify",
    args: ["store", "auth", "--store", STORE, "--scopes", "read_products,write_metaobject_definitions,write_metaobjects"],
    opts: { interactive: true },
  }]);
});

test("storeAuth: a non-zero interactive exit rejects, and there is no output to quote", async (t) => {
  const { shopify } = setup(t, undefined, { exec: async () => ({ code: 2, stdout: "", stderr: "" }) });
  await assert.rejects(shopify.storeAuth(STORE), { message: "shopify store auth failed (exit 2)" });
});

test("a non-zero exit rejects with the trimmed stderr, for auth and execute alike", async (t) => {
  const exec = async () => ({ code: 1, stdout: "", stderr: "  Not logged in to nalli.myshopify.com\n" });
  const { shopify } = setup(t, undefined, { exec });
  await assert.rejects(shopify.storeAuth(STORE), /Not logged in to nalli\.myshopify\.com$/);
  await assert.rejects(shopify.adminExecute(STORE, "query { shop { name } }"), /Not logged in to nalli\.myshopify\.com$/);
});

test("adminExecute: passes files, version and --allow-mutations only when asked, and rejects on an errors key", async (t) => {
  const seen = [];
  const exec = async (cmd, args) => {
    seen.push(args);
    writeFileSync(flag(args, "--output-file"), JSON.stringify(seen.length === 1 ? { shop: { name: "Nalli" } } : { errors: [{ message: "Access denied" }] }));
    return { code: 0, stdout: "", stderr: "" };
  };
  const { shopify } = setup(t, undefined, { exec });

  assert.deepEqual(await shopify.adminExecute(STORE, "query Q($a: Int) { shop { name } }", { a: 1 }), { shop: { name: "Nalli" } });
  const args = seen[0];
  assert.deepEqual(args.slice(0, 4), ["store", "execute", "--store", STORE]);
  assert.equal(flag(args, "--version"), "2026-10");
  assert.equal(args.includes("--allow-mutations"), false);
  assert.equal(readFileSync(flag(args, "--query-file"), "utf8"), "query Q($a: Int) { shop { name } }");
  assert.deepEqual(JSON.parse(readFileSync(flag(args, "--variable-file"), "utf8")), { a: 1 });

  await assert.rejects(shopify.adminExecute(STORE, "mutation { x }", {}, { mutations: true }), /Access denied/);
  assert.ok(seen[1].includes("--allow-mutations"));
});

test("passwordProtected: true for a redirect to /password, false otherwise", async (t) => {
  const asked = [];
  const reply = (response) => async (url, init) => (asked.push([url, init]), response);
  const redirect = new Response(null, { status: 302, headers: { location: "https://nalli.myshopify.com/password" } });
  const { shopify } = setup(t, undefined, { fetch: reply(redirect) });

  assert.equal(await shopify.passwordProtected("nalli.myshopify.com"), true);
  assert.deepEqual(asked, [["https://nalli.myshopify.com/", { redirect: "manual" }]]);

  const open = setup(t, undefined, { fetch: reply(new Response("<html>", { status: 200 })) });
  assert.equal(await open.shopify.passwordProtected("nalli.myshopify.com"), false);
  const elsewhere = new Response(null, { status: 301, headers: { location: "https://www.nalli.com/" } });
  assert.equal(await setup(t, undefined, { fetch: reply(elsewhere) }).shopify.passwordProtected("nalli.myshopify.com"), false);
});

test("passwordProtected: follows one redirect to a custom domain, and no more", async (t) => {
  const asked = [];
  const redirects = (hops) => async (url, init) => (asked.push(url), new Response(null, { status: 301, headers: { location: hops[url] } }));
  const custom = setup(t, undefined, { fetch: redirects({ "https://nalli.myshopify.com/": "https://www.nalli.com/", "https://www.nalli.com/": "/password" }) });

  assert.equal(await custom.shopify.passwordProtected("nalli.myshopify.com"), true);
  assert.deepEqual(asked, ["https://nalli.myshopify.com/", "https://www.nalli.com/"]);

  asked.length = 0;
  const chain = setup(t, undefined, {
    fetch: redirects({ "https://nalli.myshopify.com/": "https://www.nalli.com/", "https://www.nalli.com/": "https://nalli.com/", "https://nalli.com/": "/password" }),
  });
  assert.equal(await chain.shopify.passwordProtected("nalli.myshopify.com"), false);
  assert.deepEqual(asked, ["https://nalli.myshopify.com/", "https://www.nalli.com/"], "a third hop isn't followed");
});

test("passwordProtected: a network error rejects", async (t) => {
  const { shopify } = setup(t, undefined, { fetch: async () => { throw new TypeError("fetch failed"); } });
  await assert.rejects(shopify.passwordProtected("nalli.myshopify.com"), /fetch failed/);
});

test("verifyStorefront: returns the name and numeric shop id, sending the Shop document and the token", async (t) => {
  const sent = [];
  const fetch = async (url, init) => {
    sent.push([url, init]);
    return Response.json({ data: { shop: { id: "gid://shopify/Shop/68817551382", name: "Nalli" } } });
  };
  const { shopify } = setup(t, undefined, { fetch });

  assert.deepEqual(await shopify.verifyStorefront("nalli.myshopify.com", "shpat_public"), { name: "Nalli", shopId: "68817551382" });
  const [url, init] = sent[0];
  assert.equal(url, "https://nalli.myshopify.com/api/2026-10/graphql.json");
  assert.equal(init.method, "POST");
  assert.equal(init.headers["Content-Type"], "application/json");
  assert.equal(init.headers["X-Shopify-Storefront-Access-Token"], "shpat_public");
  assert.equal(JSON.parse(init.body).query, (await loadContract()).get("Shop"));

  await shopify.verifyStorefront("mock.shop", "");
  assert.equal("X-Shopify-Storefront-Access-Token" in sent[1][1].headers, false);
});

test("verifyStorefront: 401/403 and GraphQL errors throw", async (t) => {
  for (const status of [401, 403]) {
    const { shopify } = setup(t, undefined, { fetch: async () => new Response("nope", { status }) });
    await assert.rejects(shopify.verifyStorefront("nalli.myshopify.com", "bad"), /^Error: Storefront token rejected for nalli\.myshopify\.com$/);
  }
  const errors = Response.json({ errors: [{ message: "Field 'shop' doesn't exist" }, { message: "Second" }] });
  const { shopify } = setup(t, undefined, { fetch: async () => errors });
  await assert.rejects(shopify.verifyStorefront("nalli.myshopify.com", "t"), /Field 'shop' doesn't exist; Second/);
});

test("storefrontContent: a denied metaobject is false, a failed query is unknown (null)", async (t) => {
  const answer = (body) => setup(t, undefined, { fetch: async () => Response.json(body) }).shopify;
  const denied = { data: { products: { nodes: [{ id: "p" }] }, metaobject: null }, errors: [{ message: "denied", path: ["metaobject"], extensions: { code: "ACCESS_DENIED" } }] };
  assert.deepEqual(await answer(denied).storefrontContent("nalli.myshopify.com", "t"), { products: true, home: false });
  const empty = { data: { products: { nodes: [] }, metaobject: { id: "m" } } };
  assert.deepEqual(await answer(empty).storefrontContent("nalli.myshopify.com", "t"), { products: false, home: true });
  const failed = { data: null, errors: [{ message: "Internal error" }] };
  assert.deepEqual(await answer(failed).storefrontContent("nalli.myshopify.com", "t"), { products: null, home: null });
});

test("storefrontLogo: the two logos as PNG URLs and the primary colour, from one query the 2026-10 schema accepts", async (t) => {
  const sent = [];
  const answer = (body) => setup(t, undefined, { fetch: async (url, init) => (sent.push([url, init]), Response.json(body)) }).shopify;
  const image = (name) => ({ image: { url: `https://cdn.shopify.com/s/files/1/${name}.png?width=1024&height=1024` } });
  const brand = { squareLogo: image("square"), logo: image("logo"), colors: { primary: [{ background: "#1c6e4a" }, { background: "#000000" }] } };

  assert.deepEqual(await answer({ data: { shop: { brand } } }).storefrontLogo("nalli.myshopify.com", "tok"), {
    square: "https://cdn.shopify.com/s/files/1/square.png?width=1024&height=1024",
    logo: "https://cdn.shopify.com/s/files/1/logo.png?width=1024&height=1024",
    primary: "#1C6E4A",
  });
  const [url, init] = sent[0];
  assert.equal(url, "https://nalli.myshopify.com/api/2026-10/graphql.json");
  assert.equal(init.headers["X-Shopify-Storefront-Access-Token"], "tok");
  const { query } = JSON.parse(init.body);
  assert.equal(query.match(/url\(transform: \{ maxWidth: 1024, maxHeight: 1024, preferredContentType: PNG \}\)/g).length, 2);
  const schema = buildClientSchema(JSON.parse(readFileSync(new URL("schema/storefront-2026-10.json", import.meta.url), "utf8")), { assumeValid: true });
  assert.deepEqual(validate(schema, parse(query), [...specifiedRules, NoDeprecatedCustomRule]).map((e) => e.message), []);

  // what mock.shop answers: no square logo, no colours
  const none = { square: null, logo: null, primary: null };
  assert.deepEqual(await answer({ data: { shop: { brand: { squareLogo: null, logo: image("logo"), colors: { primary: [] } } } } }).storefrontLogo("mock.shop", ""),
    { ...none, logo: "https://cdn.shopify.com/s/files/1/logo.png?width=1024&height=1024" });
  // no brand, a colour that isn't #RRGGBB, a failed query: nothing to use, and no throw
  assert.deepEqual(await answer({ data: { shop: { brand: null } } }).storefrontLogo("nalli.myshopify.com", "t"), none);
  assert.deepEqual(await answer({ data: { shop: { brand: { squareLogo: null, logo: null, colors: { primary: [{ background: "green" }] } } } } }).storefrontLogo("nalli.myshopify.com", "t"), none);
  assert.deepEqual(await answer({ data: null, errors: [{ message: "Internal error" }] }).storefrontLogo("nalli.myshopify.com", "t"), none);
});

test("download: the body's bytes, with a timeout; an HTTP error, a body over the limit and a stalled server reject", async (t) => {
  const asked = [];
  const serve = (response) => setup(t, undefined, { fetch: async (url, init) => (asked.push([url, init]), response()) }).shopify;

  const bytes = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 255]);
  assert.deepEqual(await serve(() => new Response(bytes)).download("https://cdn.shopify.com/logo.png"), bytes);
  assert.equal(asked[0][0], "https://cdn.shopify.com/logo.png");
  assert.ok(asked[0][1].signal instanceof AbortSignal);
  assert.deepEqual(await serve(() => new Response(null, { status: 200 })).download("https://cdn.shopify.com/empty"), Buffer.alloc(0));

  await assert.rejects(serve(() => new Response("gone", { status: 404 })).download("https://cdn.shopify.com/logo.png"), /^Error: HTTP 404$/);

  await assert.rejects(serve(() => new Response(Buffer.alloc(5))).download("https://cdn.shopify.com/logo.png", { maxBytes: 4 }), /larger than/);
  await serve(() => new Response(Buffer.alloc(4))).download("https://cdn.shopify.com/logo.png", { maxBytes: 4 });
  // a body that never ends is dropped at the limit, not read to the end
  let cancelled = false;
  const endless = () => new Response(new ReadableStream({ pull: (c) => c.enqueue(new Uint8Array(1024)), cancel: () => { cancelled = true; } }));
  await assert.rejects(serve(endless).download("https://cdn.shopify.com/logo.png"), /^Error: larger than 8 MB$/);
  assert.equal(cancelled, true);

  // AbortSignal.timeout's timer doesn't keep Node running (a real fetch's socket does), so the stand-in holds the loop open
  const stalled = (url, { signal }) => new Promise((_, reject) => {
    const open = setInterval(() => {}, 1000);
    signal.addEventListener("abort", () => (clearInterval(open), reject(signal.reason)));
  });
  await assert.rejects(setup(t, undefined, { fetch: stalled }).shopify.download("https://cdn.shopify.com/logo.png", { timeoutMs: 20 }), { name: "TimeoutError" });
});

// Live (ARGON_LIVE=1, see `npm run test:live`): the demo's icon is made from this
test("live: mock.shop's logo is found, downloads and decodes", { skip: !process.env.ARGON_LIVE, timeout: 60_000 }, async (t) => {
  const { shopify } = setup(t); // the real fetch
  const { square, logo } = await shopify.storefrontLogo("mock.shop", "");
  const image = decodePng(await shopify.download(square ?? logo));
  assert.ok(image.width > 0 && image.height > 0);
  assert.equal(image.data.length, image.width * image.height * 4);
});

test("defaultExec: runs through a shell and returns code, stdout and stderr; a path with spaces is one argument", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "argon test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const spaced = join(dir, "dir with spaces", "file name.txt");
  const code = "console.log(process.argv[1]); console.error('oops'); process.exit(3)";
  const result = await defaultExec("node", ["-e", code, spaced]);
  assert.equal(result.code, 3);
  assert.equal(result.stdout.trim(), spaced);
  assert.equal(result.stderr.trim(), "oops");
});

test("defaultExec: refuses arguments that could escape the quotes, before anything is spawned", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "argon-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const marker = join(dir, "ran");
  const unsafe = [
    'a" & echo PWNED & "b',
    `a" & node -p 1 > "${marker}" & "b`,
    "%PATH%",
    "C:\\some dir\\",
    "x$(echo hi)",
    "$HOME",
    "a`echo hi`b",
  ];
  for (const arg of unsafe) {
    await assert.rejects(defaultExec("node", ["-e", "0", arg]), { message: `Unsafe argument for shell: ${arg}` });
  }
  assert.equal(existsSync(marker), false);
});

test("defaultExec: interactive hands the terminal to the child instead of capturing its output", () => {
  // run defaultExec in a grandchild whose stdout we capture: the child's own output must show up there
  const lib = new URL("../lib/shopify.js", import.meta.url).href;
  const script = `import { defaultExec } from "${lib}";
    console.log(JSON.stringify(await defaultExec("node", ["-e", "console.log('visible'); process.exit(4)"], { interactive: true })));`;
  const out = execFileSync(process.execPath, ["--input-type=module", "-e", script], { encoding: "utf8" });
  assert.equal(out.replace(/\r\n/g, "\n"), 'visible\n{"code":4,"stdout":"","stderr":""}\n');
});
