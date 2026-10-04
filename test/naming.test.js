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
    bundleId: "com.x.y", skipContent: false, yes: false, help: false,
  });
  assert.throws(() => parseArgs(["--store"]), /Missing value for --store/);
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
  for (const f of ["--demo", "--store", "--token", "--client-id", "--bundle-id", "--skip-content", "--yes", "--help"]) {
    assert.ok(out.includes(f), `help mentions ${f}`);
  }
});
test("run without a terminal throws on missing values", async () => {
  await assert.rejects(runWith([], false), /Missing project name \(no terminal to prompt\)/);
  await assert.rejects(runWith(["app"], false), /Missing --store \(no terminal to prompt\)/);
  await assert.rejects(runWith(["app", "--store", "a"], false), /Missing --token \(no terminal to prompt\)/);
  assert.match(await runWith(["app", "--demo"], false), /later version/);
});
