import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DEFAULT_THEME, THEME_IDS, THEME_SCREENS, checkTheme, loadTheme, themes } from "../contract/themes.js";
import { parseArgs, run } from "../lib/index.js";

const DIR = new URL("../contract/themes/", import.meta.url);

test("every theme file is listed, once, and the default is the first", () => {
  const files = readdirSync(DIR).filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -5)).sort();
  assert.deepEqual(files, [...THEME_IDS].sort());
  assert.equal(new Set(THEME_IDS).size, 20);
  assert.equal(DEFAULT_THEME, "studio");
  assert.throws(() => loadTheme("nope"), /isn't a theme/);
});

test("every theme passes the contract: tokens, navigation, screens and colours that read", () => {
  for (const theme of themes()) {
    assert.doesNotThrow(() => checkTheme(theme), theme.id);
    assert.equal(theme.id, theme.id.toLowerCase());
  }
});

test("themes are distinct, demo-safe and credited", () => {
  const all = themes();
  const looks = new Set(all.map((t) => `${t.settings.brand.accent}${t.settings.appearance.colors.background}${t.settings.appearance.fonts.heading.family}`));
  assert.equal(looks.size, all.length, "no two themes share accent, background and heading font");
  assert.equal(new Set(all.map((t) => t.name)).size, all.length);
  const credits = readFileSync(new URL("CREDITS.md", DIR), "utf8");
  for (const theme of all) {
    const text = JSON.stringify(theme);
    for (const [, slug] of text.matchAll(/https:\/\/burst\.shopifycdn\.com\/photos\/([a-z0-9-]+)\.jpg/g)) assert.ok(credits.includes(`/photos/${slug} `), `${theme.id}: ${slug} is credited`);
    for (const [, url] of text.matchAll(/"url": ?"([^"]+)"/g)) assert.match(url, /^https:\/\/(burst\.shopifycdn\.com|fonts\.gstatic\.com)\//, `${theme.id}: only Burst photos`);
  }
});

test("checkTheme refuses what a theme can't be", () => {
  const theme = loadTheme("studio");
  const broken = (change) => {
    const copy = structuredClone(theme);
    change(copy);
    return () => checkTheme(copy);
  };
  assert.throws(broken((t) => { t.settings.gokwik = {}; }), /settings take/);
  assert.throws(broken((t) => { t.settings.appearance.colors.text = t.settings.appearance.colors.background; }), /text on background/);
  assert.throws(broken((t) => { t.settings.announcement.color = "background"; t.settings.announcement.background = "surface"; }), /announcement/);
  assert.throws(broken((t) => { t.screens.home.sections[2].settings.collection = "gid://shopify/Collection/1"; }), /names a store's/);
  assert.throws(broken((t) => { delete t.screens.cart; }), /screens are/);
  assert.throws(broken((t) => { t.settings.appearance.fonts.body.files["400"] = "https://example.com/a.ttf"; }), /Google font/);
});

test("--theme: only a theme's id; --settings-file goes with it", () => {
  assert.equal(parseArgs(["x", "--theme=loom-story"]).theme, "loom-story");
  assert.throws(() => parseArgs(["x", "--theme=nope"]), /--theme must be one of: studio/);
});

test("--theme bakes the theme's settings and five screens into both apps; --settings-file wins for the settings", async () => {
  const cwd = mkdtempSync(join(tmpdir(), "argon-theme-"));
  const exec = async () => ({ code: 0, stdout: "", stderr: "" });
  const fetch = async () => new Response(JSON.stringify({ data: { shop: { name: "Mock.shop", id: "gid://shopify/Shop/68817551382", brand: null } } }), { headers: { "content-type": "application/json" } });
  const log = console.log;
  console.log = () => {};
  try {
    writeFileSync(join(cwd, "settings.json"), JSON.stringify({ version: 1, brand: { accent: "#123456" } }));
    await run(["themed", "--demo", "--yes", "--theme=temple-silk"], { exec, fetch, cwd });
    await run(["stored", "--demo", "--yes", "--theme=temple-silk", "--settings-file=settings.json"], { exec, fetch, cwd });
    await assert.rejects(run(["bad", "--demo", "--yes", "--settings-file=missing.json"], { exec, fetch, cwd }), /couldn't read/);
  } finally {
    console.log = log;
  }
  const theme = loadTheme("temple-silk");
  for (const folder of ["android/app/src/main/assets/built-in", "ios/App/Resources/built-in"]) {
    const read = (app, file) => JSON.parse(readFileSync(join(cwd, app, folder, file), "utf8"));
    assert.deepEqual(read("themed", "settings.json"), { version: 1, ...theme.settings });
    assert.deepEqual(read("stored", "settings.json"), { version: 1, brand: { accent: "#123456" } });
    for (const handle of THEME_SCREENS) assert.deepEqual(read("themed", `screen-${handle}.json`), theme.screens[handle]);
  }
  const xtool = readFileSync(join(cwd, "themed/ios/xtool.yml"), "utf8");
  for (const file of ["settings.json", ...THEME_SCREENS.map((h) => `screen-${h}.json`)]) assert.ok(xtool.includes(`- App/Resources/built-in/${file}`), file);
  assert.ok(readFileSync(join(cwd, "themed/android/shopify.properties"), "utf8").includes("HOME_TEMPLATE=fashion"));
  assert.ok(!existsSync(join(cwd, "bad")));
  rmSync(cwd, { recursive: true, force: true });
});
