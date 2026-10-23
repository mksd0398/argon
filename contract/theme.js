// The theme (docs/superpowers/specs/2026-10-23-theme-and-onboarding-design.md): the few tokens a merchant sets in the
// settings, and every token the apps derive from them. The apps (Colors.kt, ArgonTheme.swift) and Krypton's previews
// (web/js/theme.js) compute the same; contract/fixtures/theme/vectors.json holds the vectors all of them are tested against.

export const CORNERS = { square: [0, 0, 0], rounded: [4, 8, 16], round: [8, 16, 24] };
export const BUTTONS = { pill: 999, rounded: 8, square: 0 };
/** The type scale: every text role's size times this (2026-10-24-design-system-design.md). */
export const TYPE_SCALES = { small: 0.9, medium: 1, large: 1.12 };
export const ICON_STYLES = ["outline", "filled"];
/** The theme's colours by name: what any colour setting may say instead of a #RRGGBB. */
export const COLOR_NAMES = ["accent", "secondary", "background", "surface", "text", "muted", "border", "sale"];
const TOKEN_OF = { accent: "accent", secondary: "secondary", background: "paper", surface: "surface", text: "ink", muted: "muted", border: "border", sale: "sale" };

/** Argon's own palettes, as ArgonPalette / Palette have them. */
export const PALETTES = {
  light: { ink: "#17150F", muted: "#6E6A63", paper: "#F6F4F0", surface: "#FFFFFF", border: "#E2DED6", sale: "#B23A2E", success: "#2E7D4F" },
  dark: { ink: "#F6F4F0", muted: "#A29E96", paper: "#17150F", surface: "#221F19", border: "#3A362F", sale: "#E8735F", success: "#6CC08A" },
};

const HEX = /^#[0-9A-Fa-f]{6}$/;
const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const hex = (c) => "#" + c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("").toUpperCase();
/** `a` at `amount` (0..1) over `b`. */
export const mix = (a, b, amount) => hex(rgb(a).map((v, i) => v * amount + rgb(b)[i] * (1 - amount)));

export function luminance(color) {
  const [r, g, b] = rgb(color).map((v) => {
    const c = v / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export const contrast = (a, b) => {
  const [x, y] = [luminance(a), luminance(b)];
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
};

/** Black or white, whichever reads better on `color`. */
export const onColor = (color) => (contrast(color, "#000000") >= contrast(color, "#FFFFFF") ? "#000000" : "#FFFFFF");

/** The text colour for something drawn on `background`: `text` when it reads at 4.5:1 or better, else black or white. */
export const textOn = (background, text) => (contrast(background, text) >= 4.5 ? text : onColor(background));

/** A colour setting's value (a name or #RRGGBB) as #RRGGBB in `tokens`; null when it's neither. */
export function resolveColor(value, tokens) {
  if (typeof value !== "string") return null;
  if (HEX.test(value)) return value.toUpperCase();
  return TOKEN_OF[value] ? tokens[TOKEN_OF[value]] : null;
}

/**
 * Every token for `appearance` (`{ accent, secondary, background, text, corners, buttons, scale, icons }`, as the
 * settings have them: "" or missing is as built) in light or `dark` appearance. Background and text are the light
 * appearance's only; accent and secondary are both appearances'.
 */
export function themeTokens(appearance = {}, dark = false) {
  const p = { ...PALETTES[dark ? "dark" : "light"] };
  const background = !dark && HEX.test(appearance.background ?? "") ? appearance.background.toUpperCase() : null;
  const text = !dark && HEX.test(appearance.text ?? "") ? appearance.text.toUpperCase() : null;
  if (background || text) {
    p.paper = background ?? p.paper;
    p.ink = text ?? p.ink;
    p.muted = mix(p.ink, p.paper, 0.62);
    p.border = mix(p.ink, p.paper, 0.14);
    p.surface = luminance(p.paper) > 0.5 ? mix("#FFFFFF", p.paper, 0.7) : mix(p.ink, p.paper, 0.08);
  }
  const accent = HEX.test(appearance.accent ?? "") ? appearance.accent.toUpperCase() : p.ink;
  const [s, m, l] = CORNERS[appearance.corners] ?? CORNERS.rounded;
  const secondary = HEX.test(appearance.secondary ?? "") ? appearance.secondary.toUpperCase() : p.ink;
  return {
    ...p, accent, onAccent: onColor(accent), secondary, onSecondary: onColor(secondary), radius: { s, m, l },
    button: BUTTONS[appearance.buttons] ?? BUTTONS.pill, scale: TYPE_SCALES[appearance.scale] ?? 1,
    icons: ICON_STYLES.includes(appearance.icons) ? appearance.icons : "outline",
  };
}
