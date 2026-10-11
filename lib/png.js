/**
 * Argon: a small PNG reader and writer on Node's zlib, so the app icon and the launch image can be built from the
 * store's logo without an image dependency.
 *
 * An image is { width, height, data }: `data` is a Buffer of RGBA, 8 bits a channel, row by row from the top left.
 * A colour is a "#RRGGBB" string.
 */
import { deflateSync, inflateSync } from "node:zlib";

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
// Samples in a pixel, by PNG colour type: grey, RGB, palette index, grey + alpha, RGBA
const SAMPLES = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };
// The bit depths the format allows each colour type
const DEPTHS = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
// ponytail: nothing over 4096 px a side is read (64 MB decoded); Shopify's CDN is asked for 1024 at most
const MAX_SIDE = 4096;

// zlib.crc32 only exists from Node 20.15, and the CLI runs on 18
const CRC_TABLE = Uint32Array.from({ length: 256 }, (_, n) => {
  for (let bit = 0; bit < 8; bit++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n;
});
function crc32(bytes) {
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) crc = CRC_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

// The Paeth filter predicts a byte from the ones to its left (a), above (b) and above left (c): whichever is
// nearest to a + b - c
function paeth(a, b, c) {
  const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

/**
 * PNG file bytes -> image. Reads every colour type at every bit depth (16 bits keep their high byte), with tRNS
 * transparency. Throws on anything else: not a PNG, truncated or corrupt, interlaced, over 4096 px a side.
 * ponytail: Adam7 interlacing isn't read, and the caller then uses the default icon. If stores' logos turn out to be
 * interlaced, unfilter each of the seven passes as its own small image and spread its pixels over the grid.
 */
export function decodePng(buffer) {
  if (buffer.length < 8 || !SIGNATURE.equals(buffer.subarray(0, 8))) throw new Error("Not a PNG file");
  let header, palette, transparency;
  const compressed = [];
  for (let at = 8, type; type !== "IEND"; ) {
    const length = at + 8 <= buffer.length ? buffer.readUInt32BE(at) : 0;
    const end = at + 8 + length;
    if (end + 4 > buffer.length) throw new Error("PNG is truncated");
    type = buffer.toString("latin1", at + 4, at + 8);
    if (crc32(buffer.subarray(at + 4, end)) !== buffer.readUInt32BE(end)) throw new Error(`PNG is corrupt (${type} checksum)`);
    const body = buffer.subarray(at + 8, end);
    if (type === "IHDR") header = body;
    else if (type === "PLTE") palette = body;
    else if (type === "tRNS") transparency = body;
    else if (type === "IDAT") compressed.push(body);
    at = end + 4;
  }
  if (header?.length !== 13) throw new Error("PNG has no header");
  const width = header.readUInt32BE(0), height = header.readUInt32BE(4);
  const depth = header[8], colourType = header[9];
  if (!DEPTHS[colourType]?.includes(depth)) throw new Error(`Unsupported PNG (colour type ${colourType}, ${depth} bits)`);
  if (header[12]) throw new Error("Interlaced PNGs are not supported");
  if (!width || !height || width > MAX_SIDE || height > MAX_SIDE) throw new Error(`PNG is ${width}×${height}; the limit is ${MAX_SIDE} px a side`);
  if (colourType === 3 && !palette) throw new Error("PNG has no palette");

  const samples = SAMPLES[colourType];
  const stride = Math.ceil((width * samples * depth) / 8); // bytes in a row
  const step = Math.max(1, (samples * depth) / 8); // bytes in a pixel: how far back "the byte to the left" is
  let raw;
  try {
    raw = inflateSync(Buffer.concat(compressed), { maxOutputLength: (stride + 1) * height });
  } catch (err) {
    throw new Error(`PNG is corrupt (${err.message})`);
  }
  if (raw.length < (stride + 1) * height) throw new Error("PNG is truncated");

  // Each row is stored as a filter byte and the differences from that filter's prediction
  const pixels = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const from = y * (stride + 1) + 1, to = y * stride, filter = raw[from - 1];
    if (filter > 4) throw new Error(`PNG is corrupt (filter ${filter})`);
    for (let x = 0; x < stride; x++) {
      const a = x >= step ? pixels[to + x - step] : 0;
      const b = y > 0 ? pixels[to + x - stride] : 0;
      const c = x >= step && y > 0 ? pixels[to + x - stride - step] : 0;
      pixels[to + x] = raw[from + x] + (filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b : filter === 3 ? (a + b) >> 1 : paeth(a, b, c));
    }
  }
  if (colourType === 6 && depth === 8) return { width, height, data: pixels };

  // One sample as stored: the high byte of 16 bits, a whole byte, or bits packed from the top of a byte
  const max = (1 << Math.min(depth, 8)) - 1;
  const sample = depth === 16 ? (row, i) => pixels[row + i * 2]
    : depth === 8 ? (row, i) => pixels[row + i]
    : (row, i) => (pixels[row + ((i * depth) >> 3)] >> (8 - depth - ((i * depth) & 7))) & max;
  const stretch = 255 / max; // 1, 2 and 4 bit greys spread over 0...255
  // tRNS on a grey or RGB image names the one colour that is transparent (two bytes a sample).
  // ponytail: at 16 bits only the high bytes are compared, the ones that are kept
  const clear = transparency && (colourType === 0 || colourType === 2)
    ? Array.from({ length: samples }, (_, n) => transparency[n * 2 + (depth === 16 ? 0 : 1)])
    : null;
  const colour = samples < 3 ? 1 : 3; // the grey or RGB samples; one more is alpha
  const data = Buffer.alloc(width * height * 4);
  for (let y = 0, o = 0; y < height; y++) {
    for (let x = 0, row = y * stride; x < width; x++, o += 4) {
      if (colourType === 3) {
        const index = sample(row, x);
        if (index * 3 + 3 > palette.length) throw new Error("PNG is corrupt (a colour outside its palette)");
        palette.copy(data, o, index * 3, index * 3 + 3);
        data[o + 3] = transparency?.[index] ?? 255; // tRNS lists the palette's alphas, and may stop early
        continue;
      }
      const i = x * samples;
      for (let n = 0; n < 3; n++) data[o + n] = sample(row, i + (colour === 1 ? 0 : n)) * stretch;
      data[o + 3] = samples > colour ? sample(row, i + colour) : clear?.every((v, n) => sample(row, i + n) === v) ? 0 : 255;
    }
  }
  return { width, height, data };
}

function chunk(type, body) {
  const out = Buffer.alloc(12 + body.length);
  out.writeUInt32BE(body.length, 0);
  out.write(type, 4, "latin1");
  body.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + body.length)), 8 + body.length);
  return out;
}

/**
 * image -> PNG file bytes, 8-bit RGBA. `alpha: false` writes RGB: the alpha channel is dropped, not blended.
 * ponytail: rows are written unfiltered. Small for a logo's flat colours, large for a photo; filter each row if
 * a photo ever goes through here.
 */
export function encodePng({ width, height, data }, { alpha = true } = {}) {
  const samples = alpha ? 4 : 3;
  const raw = Buffer.alloc((width * samples + 1) * height); // each row starts with its filter byte: 0, no filter
  for (let y = 0, i = 0, o = 0; y < height; y++) {
    o++;
    for (let x = 0; x < width; x++, i += 4) for (let n = 0; n < samples; n++) raw[o++] = data[i + n];
  }
  const header = Buffer.alloc(13); // compression, filter method and interlace stay 0
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = alpha ? 6 : 2;
  return Buffer.concat([SIGNATURE, chunk("IHDR", header), chunk("IDAT", deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

// For each output pixel along one axis, the source pixels that feed it, as [index, weight] pairs. A triangle
// filter: bilinear when enlarging, widened to take in every source pixel when shrinking.
function taps(from, to) {
  const ratio = from / to, reach = Math.max(1, ratio);
  return Array.from({ length: to }, (_, i) => {
    const centre = (i + 0.5) * ratio - 0.5, out = [];
    for (let s = Math.max(0, Math.ceil(centre - reach)); s <= Math.min(from - 1, centre + reach); s++) {
      const weight = 1 - Math.abs(s - centre) / reach;
      if (weight > 0) out.push([s, weight]);
    }
    return out;
  });
}

// `image` resampled to width × height. Colours are weighted by their alpha, so a transparent pixel's unseen colour
// doesn't leak into the edge next to it.
function resize({ width: fromWidth, height: fromHeight, data }, width, height) {
  const out = Buffer.alloc(width * height * 4);
  const columns = taps(fromWidth, width), rows = taps(fromHeight, height);
  for (let y = 0, o = 0; y < height; y++) {
    for (let x = 0; x < width; x++, o += 4) {
      let r = 0, g = 0, b = 0, a = 0, total = 0;
      for (const [sy, wy] of rows[y]) {
        for (const [sx, wx] of columns[x]) {
          const i = (sy * fromWidth + sx) * 4, opacity = wx * wy * data[i + 3];
          r += data[i] * opacity;
          g += data[i + 1] * opacity;
          b += data[i + 2] * opacity;
          a += opacity;
          total += wx * wy;
        }
      }
      if (a > 0) out.set([Math.round(r / a), Math.round(g / a), Math.round(b / a), Math.round(a / total)], o);
    }
  }
  return { width, height, data: out };
}

const scaled = (image, scale) =>
  resize(image, Math.max(1, Math.round(image.width * scale)), Math.max(1, Math.round(image.height * scale)));

/** `image` scaled down to fit maxWidth × maxHeight, proportions kept. Never up: a smaller image comes back as a copy. */
export const fit = (image, maxWidth, maxHeight) => scaled(image, Math.min(1, maxWidth / image.width, maxHeight / image.height));

const rgb = (colour) => [1, 3, 5].map((i) => parseInt(colour.slice(i, i + 2), 16));

const canvas = (size, colour) => ({ width: size, height: size, data: Buffer.alloc(size * size * 4, Buffer.from([...rgb(colour), 255])) });

// Paints a colour over the opaque pixel at data[at], with `alpha` from 0 to 1
function paint(data, at, r, g, b, alpha) {
  data[at] = Math.round(r * alpha + data[at] * (1 - alpha));
  data[at + 1] = Math.round(g * alpha + data[at + 1] * (1 - alpha));
  data[at + 2] = Math.round(b * alpha + data[at + 2] * (1 - alpha));
}

/**
 * A square, opaque size × size image: `background` with `image` in the middle, scaled to fit `fraction` of the side.
 * Unlike `fit` this also scales up: an app icon is drawn far smaller than its 1024 px, so a small logo enlarged
 * here still ends up sharper on the phone than its source, and a logo left small would be a dot in the icon.
 */
export function compose(image, size, background, fraction) {
  const logo = scaled(image, Math.min((size * fraction) / image.width, (size * fraction) / image.height));
  const out = canvas(size, background);
  const left = (size - logo.width) >> 1, top = (size - logo.height) >> 1;
  for (let y = 0, i = 0; y < logo.height; y++) {
    for (let x = 0; x < logo.width; x++, i += 4) {
      paint(out.data, ((top + y) * size + left + x) * 4, logo.data[i], logo.data[i + 1], logo.data[i + 2], logo.data[i + 3] / 255);
    }
  }
  return out;
}

/**
 * The colour to put behind `image`: its top-left pixel when that is opaque (a logo on its own background). A logo on a
 * transparent background gets white, or `dark` when the logo itself is light: a white logo can't be seen on white.
 * ponytail: one pixel decides whether the logo has its own background.
 */
export function backgroundOf({ data }, dark = "#17150F") {
  if (data[3] === 255) return `#${data.subarray(0, 3).toString("hex").toUpperCase()}`;
  // how light the logo's visible pixels are on average (Rec. 601 luma, 0...255), each weighted by how opaque it is
  let light = 0, weight = 0;
  for (let i = 0; i < data.length; i += 4) {
    light += (data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114) * data[i + 3];
    weight += data[i + 3];
  }
  return weight && light / weight > 200 ? dark : "#FFFFFF";
}

/** The icon of a store without a logo: a `background` square with a rounded square in `mark` in the middle. */
export function plainIcon(size, background, mark) {
  const out = canvas(size, background);
  const [r, g, b] = rgb(mark);
  const half = size * 0.19, radius = half * 0.44, centre = size / 2;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      // how far the pixel's centre is past the rounded square's edge (below zero inside it), for a one-pixel soft edge
      const dx = Math.max(0, Math.abs(x + 0.5 - centre) - (half - radius));
      const dy = Math.max(0, Math.abs(y + 0.5 - centre) - (half - radius));
      const cover = Math.min(1, radius + 0.5 - Math.hypot(dx, dy));
      if (cover > 0) paint(out.data, (y * size + x) * 4, r, g, b, cover);
    }
  }
  return out;
}
