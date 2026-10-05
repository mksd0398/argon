/**
 * Argon: store provisioning over the Shopify CLI (`store auth` / `store execute`), plus two HTTP checks.
 *
 * The Shopify CLI owns the Admin credentials; Argon never sees, stores or sends an Admin token.
 * `exec` and `fetch` are injected so tests never touch the CLI or a store.
 */
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SECTION_DEFINITIONS, screenDefinition, buildSeed } from "../contract/sections.js";
import { loadContract } from "./contract.js";

export const API_VERSION = "2026-10";
const SCOPES = "read_products,write_metaobject_definitions,write_metaobjects";

const QUERIES = {
  definition: "query Definition($type: String!) { metaobjectDefinitionByType(type: $type) { id } }",
  createDefinition: `mutation CreateDefinition($definition: MetaobjectDefinitionCreateInput!) {
  metaobjectDefinitionCreate(definition: $definition) {
    metaobjectDefinition { id type }
    userErrors { field message }
  }
}`,
  home: 'query Home { metaobjectByHandle(handle: { type: "mobile_screen", handle: "home" }) { id } }',
  seedSource: "query SeedSource { shop { name } collections(first: 10) { nodes { id productsCount { count } } } }",
  createEntry: `mutation CreateEntry($metaobject: MetaobjectCreateInput!) {
  metaobjectCreate(metaobject: $metaobject) {
    metaobject { id handle }
    userErrors { field message }
  }
}`,
  accounts: "query Accounts { shop { customerAccountsV2 { customerAccountsVersion } } }",
};

// shell: true because on Windows `shopify` is a .cmd/.ps1 shim that spawn can't run directly.
// ponytail: args are only wrapped in double quotes. That is literal on cmd.exe except for a quote (it ends the
// quoting, so `&`, `|`, `<` and `>` after it run as commands), %VAR% expansion and a trailing backslash. POSIX
// sh still expands `$` and backticks inside double quotes. quote() refuses all of those rather than escaping
// them: our args are flags, normalized store domains, mkdtemp paths and the user's project path (a path that
// holds one of these characters is refused, not run). If arbitrary args are ever needed, drop the shell and
// exec the resolved binary/shim directly.
const quote = (arg) => {
  arg = String(arg);
  if (/["%`$]|\\$/.test(arg)) throw new Error(`Unsafe argument for shell: ${arg}`);
  return `"${arg}"`;
};

// opts.interactive: give the child our terminal (browser prompts, a manual auth URL) and report only the exit code.
export const defaultExec = (cmd, args, { interactive = false } = {}) =>
  new Promise((resolve, reject) => {
    const child = spawn([cmd, ...args.map(quote)].join(" "), { shell: true, stdio: interactive ? "inherit" : "pipe" });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (chunk) => (stdout += chunk));
    child.stderr?.on("data", (chunk) => (stderr += chunk));
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stdout, stderr }));
  });

export function createShopify({
  exec = defaultExec,
  fetch = globalThis.fetch,
  // ponytail: never removed; it only holds the query and variable files (no credentials)
  tmpDir = mkdtempSync(join(tmpdir(), "argon-")),
} = {}) {
  async function shopifyCli(args, opts) {
    const { code, stdout, stderr } = await exec("shopify", args, opts);
    if (code !== 0) {
      const output = stderr.trim() || stdout.trim();
      throw new Error(`shopify ${args[0]} ${args[1]} failed (exit ${code})${output ? `: ${output}` : ""}`);
    }
  }

  const storeAuth = (store) =>
    shopifyCli(["store", "auth", "--store", store, "--scopes", SCOPES], { interactive: true });

  // ponytail: fixed file names in tmpDir, so calls must run one at a time (provision does)
  async function adminExecute(store, query, variables = {}, { mutations = false } = {}) {
    const queryFile = join(tmpDir, "query.graphql");
    const variableFile = join(tmpDir, "variables.json");
    const outputFile = join(tmpDir, "output.json");
    writeFileSync(queryFile, query);
    writeFileSync(variableFile, JSON.stringify(variables));
    rmSync(outputFile, { force: true }); // never read a previous call's result
    await shopifyCli([
      "store", "execute", "--store", store,
      "--query-file", queryFile, "--variable-file", variableFile, "--output-file", outputFile,
      "--version", API_VERSION, ...(mutations ? ["--allow-mutations"] : []),
    ]);
    // Shopify CLI 4.8.x writes just the GraphQL `data` object to --output-file (its store execute
    // returns the response's `data`); top-level GraphQL `errors` make the command exit non-zero
    // instead. The `errors` check below is only a guard for a CLI that changes that.
    const data = JSON.parse(readFileSync(outputFile, "utf8"));
    if (data.errors) throw new Error(`Admin API error: ${JSON.stringify(data.errors)}`);
    for (const payload of Object.values(data)) {
      if (payload?.userErrors?.length) throw new Error(payload.userErrors.map((e) => e.message).join("; "));
    }
    return data;
  }

  async function provision(store) {
    const created = [];
    const warnings = [];

    const ensureDefinition = async (definition) => {
      const { metaobjectDefinitionByType: existing } = await adminExecute(store, QUERIES.definition, { type: definition.type });
      if (existing) return existing.id;
      const made = await adminExecute(store, QUERIES.createDefinition, { definition }, { mutations: true });
      created.push(definition.type);
      return made.metaobjectDefinitionCreate.metaobjectDefinition.id;
    };
    const createEntry = async (metaobject) =>
      (await adminExecute(store, QUERIES.createEntry, { metaobject }, { mutations: true })).metaobjectCreate.metaobject.id;

    const sectionDefinitionIds = [];
    for (const definition of SECTION_DEFINITIONS) sectionDefinitionIds.push(await ensureDefinition(definition));
    await ensureDefinition(screenDefinition(sectionDefinitionIds));

    let seeded = false;
    if (!(await adminExecute(store, QUERIES.home)).metaobjectByHandle) {
      const { shop, collections } = await adminExecute(store, QUERIES.seedSource);
      const { sections, screen } = buildSeed({
        shopName: shop.name,
        collections: collections.nodes.map((c) => ({ id: c.id, productsCount: c.productsCount?.count ?? 0 })),
      });
      const sectionIds = [];
      for (const section of sections) sectionIds.push(await createEntry(section));
      await createEntry(screen(sectionIds));
      seeded = true;
    }

    // ponytail: any failure here (missing scope, old API) only warns; the check is advisory
    try {
      const { shop } = await adminExecute(store, QUERIES.accounts);
      if (shop.customerAccountsV2.customerAccountsVersion === "CLASSIC") {
        warnings.push("Store uses legacy customer accounts; turn on new customer accounts for login");
      }
    } catch {
      warnings.push("Couldn't check customer account version");
    }

    return { created, seeded, warnings };
  }

  async function passwordProtected(domain) {
    const res = await fetch(`https://${domain}/`, { redirect: "manual" });
    return res.status >= 300 && res.status < 400 && (res.headers.get("location") ?? "").includes("/password");
  }

  async function verifyStorefront(domain, token) {
    const res = await fetch(`https://${domain}/api/${API_VERSION}/graphql.json`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(token && { "X-Shopify-Storefront-Access-Token": token }) },
      body: JSON.stringify({ query: (await loadContract()).get("Shop") }),
    });
    if (res.status === 401 || res.status === 403) throw new Error(`Storefront token rejected for ${domain}`);
    if (!res.ok) throw new Error(`Storefront API returned HTTP ${res.status} for ${domain}`);
    const { data, errors } = await res.json();
    if (errors?.length) throw new Error(errors.map((e) => e.message).join("; "));
    return { name: data.shop.name, shopId: data.shop.id.split("/").pop() };
  }

  return { storeAuth, adminExecute, provision, passwordProtected, verifyStorefront };
}
