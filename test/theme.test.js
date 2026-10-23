import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { contrast, resolveColor, textOn, themeTokens } from "../contract/theme.js";

const vectors = JSON.parse(readFileSync(new URL("../contract/fixtures/theme/vectors.json", import.meta.url), "utf8"));

test("the theme's vectors: what the apps and Krypton's previews are tested against", () => {
  for (const v of vectors) assert.deepEqual(themeTokens(v.appearance, v.dark), v.tokens, JSON.stringify(v.appearance));
});

test("as built is Argon's palette; background and text are the light appearance's only", () => {
  assert.equal(themeTokens({}).paper, "#F6F4F0");
  assert.equal(themeTokens({ background: "#000000", text: "#FFFFFF" }, true).paper, "#17150F");
  assert.deepEqual(themeTokens({ corners: "square", buttons: "square" }).radius, { s: 0, m: 0, l: 0 });
});

test("derived text reads: muted on paper and the accent's text at least 3:1 and 4.5:1", () => {
  for (const v of vectors) {
    const t = v.tokens;
    assert.ok(contrast(t.muted, t.paper) >= 3, `muted on ${t.paper}`);
    assert.ok(contrast(t.onAccent, t.accent) >= 4.5, `on ${t.accent}`);
  }
  assert.equal(textOn("#111111", "#17150F"), "#FFFFFF");
  assert.equal(textOn("#F5F0E8", "#17150F"), "#17150F");
});

test("a colour by name follows the theme; a hex stays itself", () => {
  const t = themeTokens({ accent: "#8A3B12", background: "#F7F3EE", text: "#2B2118", secondary: "#2A9D8F" });
  assert.deepEqual(["accent", "secondary", "background", "text", "#abcdef", "nope", undefined].map((v) => resolveColor(v, t)),
    ["#8A3B12", "#2A9D8F", "#F7F3EE", "#2B2118", "#ABCDEF", null, null]);
  assert.equal(themeTokens({}).secondary, themeTokens({}).ink, "secondary is text until set");
  assert.deepEqual([themeTokens({ scale: "large" }).scale, themeTokens({ icons: "filled" }).icons, themeTokens({}).icons], [1.12, "filled", "outline"]);
});
