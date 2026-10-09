/**
 * Argon: GraphQL contract loader.
 *
 * One operation per file: contract/queries/<Name>.graphql (Storefront API, fragments in contract/fragments.graphql)
 * and contract/customer/<Name>.graphql (Customer Account API, fragments in contract/customer/fragments.graphql).
 * Each API resolves fragments from its own file. Both apps call the resolved documents (operation + the fragments it uses).
 */
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// ponytail: matches spreads inside comments and strings too; the contract files have neither
const SPREAD = /\.\.\.\s*([A-Z]\w*)/g;

/** Appends every fragment `source` uses, transitively, once each, in first-use order. */
export function resolveDocument(source, fragments) {
  const out = [source.trim()];
  const seen = new Set();
  const visit = (text) => {
    for (const [, name] of text.matchAll(SPREAD)) {
      if (!fragments.has(name) || seen.has(name)) continue;
      seen.add(name);
      out.push(fragments.get(name));
      visit(fragments.get(name));
    }
  };
  visit(source);
  return out.join("\n\n") + "\n";
}

/** [operations folder, its fragments file], relative to contract/. */
const APIS = [
  ["queries", "fragments.graphql"],
  ["customer", "customer/fragments.graphql"],
];

/** Map<operation name (= file name), resolved document>, both APIs. Names are unique across both. */
export async function loadContract(dir = fileURLToPath(new URL("../contract/", import.meta.url))) {
  const contract = new Map();
  for (const [folder, fragmentsFile] of APIS) {
    const fragments = new Map();
    for (const chunk of (await readFile(join(dir, fragmentsFile), "utf8")).split(/^(?=fragment\s)/m)) {
      const name = chunk.match(/^fragment\s+(\w+)/)?.[1];
      if (name) fragments.set(name, chunk.trim());
    }
    const files = (await readdir(join(dir, folder))).filter((f) => f.endsWith(".graphql") && f !== "fragments.graphql");
    for (const file of files.sort()) {
      const name = file.slice(0, -".graphql".length);
      if (contract.has(name)) throw new Error(`Duplicate contract operation ${name} (${folder}/${file})`);
      contract.set(name, resolveDocument(await readFile(join(dir, folder, file), "utf8"), fragments));
    }
  }
  return contract;
}
