/**
 * Argon: GraphQL contract loader.
 *
 * contract/queries/<Name>.graphql holds one operation each; contract/fragments.graphql holds
 * the shared fragments. Both apps call the resolved documents (operation + the fragments it uses).
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

/** Map<operation name (= file name), resolved document>. */
export async function loadContract(dir = fileURLToPath(new URL("../contract/", import.meta.url))) {
  const fragments = new Map();
  for (const chunk of (await readFile(join(dir, "fragments.graphql"), "utf8")).split(/^(?=fragment\s)/m)) {
    const name = chunk.match(/^fragment\s+(\w+)/)?.[1];
    if (name) fragments.set(name, chunk.trim());
  }
  const queries = join(dir, "queries");
  const contract = new Map();
  for (const file of (await readdir(queries)).filter((f) => f.endsWith(".graphql")).sort()) {
    contract.set(file.slice(0, -".graphql".length), resolveDocument(await readFile(join(queries, file), "utf8"), fragments));
  }
  return contract;
}
