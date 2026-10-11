import { test } from "node:test";
import assert from "node:assert/strict";
import { crc32, deflateSync } from "node:zlib";
import { backgroundOf, compose, decodePng, encodePng, fit, plainIcon } from "../lib/png.js";

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const SAMPLES = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };

// Node's own crc32, so the reader's checksum is checked against another implementation
function chunk(type, body = Buffer.alloc(0)) {
  const out = Buffer.alloc(12 + body.length);
  out.writeUInt32BE(body.length, 0);
  out.write(type, 4, "latin1");
  Buffer.from(body).copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + body.length)), 8 + body.length);
  return out;
}

/**
 * A PNG written by hand. rows: the scanlines as the format packs them, before filtering; filters: a filter type per
 * row (0 where none is given). The Paeth predictor here is written differently from the reader's.
 */
function png({ width, depth = 8, colourType, rows, filters = [], palette, transparency, interlace = 0 }) {
  const step = Math.max(1, (SAMPLES[colourType] * depth) / 8);
  const lines = rows.map((row, y) => {
    const above = rows[y - 1];
    const line = Buffer.alloc(row.length + 1);
    line[0] = filters[y] ?? 0;
    row.forEach((byte, x) => {
      const a = x >= step ? row[x - step] : 0, b = above ? above[x] : 0, c = above && x >= step ? above[x - step] : 0;
      const nearest = [a, b, c].reduce((best, v) => (Math.abs(a + b - c - v) < Math.abs(a + b - c - best) ? v : best));
      line[x + 1] = byte - [0, a, b, (a + b) >> 1, nearest, 0][line[0]];
    });
    return line;
  });
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(rows.length, 4);
  header.set([depth, colourType, 0, 0, interlace], 8);
  return Buffer.concat([
    SIGNATURE,
    chunk("IHDR", header),
    ...(palette ? [chunk("PLTE", Buffer.from(palette.flat()))] : []),
    ...(transparency ? [chunk("tRNS", Buffer.from(transparency))] : []),
    chunk("IDAT", deflateSync(Buffer.concat(lines))),
    chunk("IEND"),
  ]);
}

const row = (...bytes) => Buffer.from(bytes.flat());
const pixels = (image) => Array.from({ length: image.width * image.height }, (_, i) => [...image.data.subarray(i * 4, i * 4 + 4)]);
const pixel = (image, x, y) => [...image.data.subarray((y * image.width + x) * 4, (y * image.width + x) * 4 + 4)];
const solid = (width, height, rgba) => ({ width, height, data: Buffer.alloc(width * height * 4, Buffer.from(rgba)) });
// bytes that look like noise, the same on every run
const noise = (length, seed = 1) => Buffer.from(Array.from({ length }, (_, i) => ((i + seed) * 2654435761) >>> 24));

test("encodePng and decodePng round trip RGBA, and RGB when the alpha channel is dropped", () => {
  const image = { width: 7, height: 5, data: noise(7 * 5 * 4) };
  const rgba = encodePng(image);
  assert.deepEqual([rgba[24], rgba[25]], [8, 6], "8-bit RGBA");
  assert.deepEqual(decodePng(rgba), image);

  const rgb = encodePng(image, { alpha: false });
  assert.deepEqual([rgb[24], rgb[25]], [8, 2], "8-bit RGB");
  const opaque = decodePng(rgb);
  assert.deepEqual([opaque.width, opaque.height], [7, 5]);
  assert.deepEqual(pixels(opaque), pixels(image).map(([r, g, b]) => [r, g, b, 255]));
});

test("decodePng: grey (colour type 0), with its transparent value, and packed below 8 bits", () => {
  const grey = decodePng(png({ width: 2, colourType: 0, rows: [row(0, 128), row(255, 64)] }));
  assert.deepEqual(pixels(grey), [[0, 0, 0, 255], [128, 128, 128, 255], [255, 255, 255, 255], [64, 64, 64, 255]]);

  const keyed = decodePng(png({ width: 2, colourType: 0, rows: [row(0, 128), row(255, 64)], transparency: [0, 128] }));
  assert.deepEqual(pixels(keyed).map((p) => p[3]), [255, 0, 255, 255]);

  // 1 bit: ten pixels in two bytes, the last six bits padding
  const bits = decodePng(png({ width: 10, depth: 1, colourType: 0, rows: [row(0b10110010, 0b01000000)] }));
  assert.deepEqual(pixels(bits).map((p) => p[0]), [255, 0, 255, 255, 0, 0, 255, 0, 0, 255]);
  // 2 and 4 bits spread over 0...255
  const two = decodePng(png({ width: 4, depth: 2, colourType: 0, rows: [row(0b00011011)] }));
  assert.deepEqual(pixels(two).map((p) => p[0]), [0, 85, 170, 255]);
  const four = decodePng(png({ width: 3, depth: 4, colourType: 0, rows: [row(0x0f, 0x70)], transparency: [0, 7] }));
  assert.deepEqual(pixels(four), [[0, 0, 0, 255], [255, 255, 255, 255], [119, 119, 119, 0]]);
});

test("decodePng: RGB (colour type 2), with its transparent colour", () => {
  const rows = [row([255, 0, 0], [0, 255, 0]), row([0, 0, 255], [10, 20, 30])];
  assert.deepEqual(pixels(decodePng(png({ width: 2, colourType: 2, rows }))), [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [10, 20, 30, 255]]);
  const keyed = decodePng(png({ width: 2, colourType: 2, rows, transparency: [0, 0, 0, 255, 0, 0] }));
  assert.deepEqual(pixels(keyed), [[255, 0, 0, 255], [0, 255, 0, 0], [0, 0, 255, 255], [10, 20, 30, 255]]);
});

test("decodePng: palette (colour type 3) with tRNS alphas, at 8 bits and packed", () => {
  const palette = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [9, 8, 7]];
  const expected = [[9, 8, 7, 255], [0, 255, 0, 128], [255, 0, 0, 0], [0, 0, 255, 255]];
  // tRNS covers the first two colours only: the rest are opaque
  const whole = decodePng(png({ width: 2, colourType: 3, palette, transparency: [0, 128], rows: [row(3, 1), row(0, 2)] }));
  assert.deepEqual(pixels(whole), expected);
  const packed = decodePng(png({ width: 4, depth: 2, colourType: 3, palette, transparency: [0, 128], rows: [row(0b11010010)] }));
  assert.deepEqual(pixels(packed), expected);
  assert.deepEqual(pixels(decodePng(png({ width: 2, colourType: 3, palette, rows: [row(0, 1)] }))), [[255, 0, 0, 255], [0, 255, 0, 255]]);
});

test("decodePng: grey + alpha (colour type 4) and RGBA (colour type 6), written by hand", () => {
  const greyAlpha = decodePng(png({ width: 2, colourType: 4, rows: [row([200, 255], [50, 0])] }));
  assert.deepEqual(pixels(greyAlpha), [[200, 200, 200, 255], [50, 50, 50, 0]]);
  const rgba = decodePng(png({ width: 2, colourType: 6, rows: [row([1, 2, 3, 4], [250, 251, 252, 253])] }));
  assert.deepEqual(pixels(rgba), [[1, 2, 3, 4], [250, 251, 252, 253]]);
});

test("decodePng: 16 bits a sample keep the high byte", () => {
  const wide = (...values) => row(values.flatMap((v) => [v, 0x99])); // the low byte is dropped
  assert.deepEqual(pixels(decodePng(png({ width: 1, depth: 16, colourType: 6, rows: [wide(10, 20, 30, 40)] }))), [[10, 20, 30, 40]]);
  assert.deepEqual(pixels(decodePng(png({ width: 2, depth: 16, colourType: 2, rows: [wide(1, 2, 3, 4, 5, 6)] }))), [[1, 2, 3, 255], [4, 5, 6, 255]]);
  assert.deepEqual(pixels(decodePng(png({ width: 2, depth: 16, colourType: 4, rows: [wide(7, 8, 9, 0)] }))), [[7, 7, 7, 8], [9, 9, 9, 0]]);
  const keyed = decodePng(png({ width: 2, depth: 16, colourType: 0, rows: [wide(7, 9)], transparency: [9, 0x99] }));
  assert.deepEqual(pixels(keyed), [[7, 7, 7, 255], [9, 9, 9, 0]]);
});

test("decodePng: every filter type, for 1, 3, 4 and 8 bytes a pixel", () => {
  const filters = [0, 1, 2, 3, 4, 4, 3, 2, 1]; // Paeth and Average also on rows that have one above
  for (const [colourType, depth] of [[0, 8], [2, 8], [6, 8], [6, 16]]) {
    const width = 6, bytes = width * SAMPLES[colourType] * (depth / 8);
    const rows = filters.map((_, y) => noise(bytes, y * 31 + colourType));
    const image = decodePng(png({ width, depth, colourType, rows, filters }));
    const plain = decodePng(png({ width, depth, colourType, rows }));
    assert.deepEqual([image.width, image.height], [width, filters.length]);
    assert.deepEqual(image.data, plain.data, `colour type ${colourType} at ${depth} bits`);
    if (colourType === 6 && depth === 8) assert.deepEqual(image.data, Buffer.concat(rows));
  }
});

test("decodePng: IDAT split over several chunks, and unknown chunks skipped", () => {
  const image = { width: 9, height: 9, data: noise(9 * 9 * 4) };
  const whole = encodePng(image);
  const idat = whole.subarray(33 + 8, whole.length - 12 - 4); // after the signature and IHDR; before the CRC and IEND
  const parts = [idat.subarray(0, 5), idat.subarray(5, 6), idat.subarray(6)].map((part) => chunk("IDAT", part));
  const split = Buffer.concat([whole.subarray(0, 33), chunk("tEXt", Buffer.from("Comment\0hello")), ...parts, chunk("IEND")]);
  assert.deepEqual(decodePng(split), image);
});

test("decodePng: clear errors for what it can't read", () => {
  const good = encodePng(solid(4, 4, [1, 2, 3, 255]));
  assert.throws(() => decodePng(Buffer.alloc(0)), /^Error: Not a PNG file$/);
  assert.throws(() => decodePng(Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'/>")), /Not a PNG file/);
  assert.throws(() => decodePng(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46])), /Not a PNG file/, "a JPEG");

  // cut anywhere, it is an error and never a partial image
  for (let length = 8; length < good.length; length++) assert.throws(() => decodePng(good.subarray(0, length)), /PNG is truncated/, `cut at ${length}`);
  // the file is whole but its pixel data stops early
  const short = Buffer.concat([good.subarray(0, 33), chunk("IDAT", deflateSync(Buffer.alloc(10))), chunk("IEND")]);
  assert.throws(() => decodePng(short), /PNG is truncated/);
  const cutStream = Buffer.concat([good.subarray(0, 33), chunk("IDAT", deflateSync(noise(68)).subarray(0, 20)), chunk("IEND")]);
  assert.throws(() => decodePng(cutStream), /PNG is corrupt/);
  assert.throws(() => decodePng(Buffer.concat([good.subarray(0, 33), chunk("IEND")])), /PNG is corrupt/, "no pixel data at all");

  const flipped = Buffer.from(good);
  flipped[45] ^= 1; // a byte of the pixel data
  assert.throws(() => decodePng(flipped), /PNG is corrupt \(IDAT checksum\)/);

  const rgba = (extra) => png({ width: 1, colourType: 6, rows: [row(1, 2, 3, 4)], ...extra });
  assert.throws(() => decodePng(rgba({ interlace: 1 })), /Interlaced PNGs are not supported/);
  assert.throws(() => decodePng(rgba({ filters: [5] })), /PNG is corrupt \(filter 5\)/);
  assert.throws(() => decodePng(rgba({ depth: 4 })), /Unsupported PNG \(colour type 6, 4 bits\)/);
  assert.throws(() => decodePng(rgba({ colourType: 5 })), /Unsupported PNG \(colour type 5, 8 bits\)/);
  assert.throws(() => decodePng(rgba({ width: 5000 })), /5000×1; the limit is 4096 px a side/);
  assert.throws(() => decodePng(rgba({ width: 0 })), /0×1/);
  assert.throws(() => decodePng(png({ width: 1, colourType: 3, rows: [row(0)] })), /PNG has no palette/);
  assert.throws(() => decodePng(png({ width: 1, colourType: 3, palette: [[1, 2, 3]], rows: [row(1)] })), /a colour outside its palette/);
  assert.throws(() => decodePng(Buffer.concat([SIGNATURE, chunk("IEND")])), /PNG has no header/);
});

test("fit: scales down in proportion, and never up", () => {
  const wide = fit(solid(400, 200, [10, 200, 30, 255]), 100, 100);
  assert.deepEqual([wide.width, wide.height], [100, 50]);
  assert.deepEqual(new Set(pixels(wide).map(String)), new Set(["10,200,30,255"]), "a flat colour stays that colour");
  const tall = fit(solid(30, 90, [0, 0, 0, 255]), 264, 60);
  assert.deepEqual([tall.width, tall.height], [20, 60]);
  assert.deepEqual([fit(solid(3, 4000, [0, 0, 0, 255]), 264, 264).width, fit(solid(1, 4000, [0, 0, 0, 255]), 264, 264).width], [1, 1], "never thinner than a pixel");

  const small = { width: 5, height: 3, data: noise(5 * 3 * 4).map((byte, i) => (i % 4 === 3 ? byte | 1 : byte)) }; // no alpha of 0
  const same = fit(small, 264, 264);
  assert.deepEqual(same, small);
  assert.notEqual(same.data, small.data, "a new image");
});

test("fit: averages what it covers, and a transparent pixel's colour doesn't bleed into its neighbours", () => {
  // left half opaque red, right half transparent green
  const halves = solid(8, 8, [255, 0, 0, 255]);
  for (let y = 0; y < 8; y++) for (let x = 4; x < 8; x++) halves.data.set([0, 255, 0, 0], (y * 8 + x) * 4);
  const one = fit(halves, 1, 1);
  assert.deepEqual(pixel(one, 0, 0).slice(0, 3), [255, 0, 0]);
  assert.ok(Math.abs(pixel(one, 0, 0)[3] - 128) <= 1, "half covered");

  // a checkerboard of black and white comes out mid grey
  const board = solid(64, 64, [0, 0, 0, 255]);
  for (let y = 0; y < 64; y++) for (let x = y % 2; x < 64; x += 2) board.data.set([255, 255, 255, 255], (y * 64 + x) * 4);
  for (const [r, g, b, a] of pixels(fit(board, 8, 8))) assert.ok(Math.abs(r - 128) <= 2 && r === g && g === b && a === 255, `grey, not ${r}`);
});

test("compose: an opaque square in the background colour with the image centred in its fraction", () => {
  // a 200×100 logo: transparent, with an opaque blue block that leaves a 10 px margin
  const logo = solid(200, 100, [0, 0, 0, 0]);
  for (let y = 10; y < 90; y++) for (let x = 10; x < 190; x++) logo.data.set([0, 0, 255, 255], (y * 200 + x) * 4);
  const icon = compose(logo, 100, "#FFCC00", 0.5); // the logo becomes 50×25, at (25, 37)
  assert.deepEqual([icon.width, icon.height, icon.data.length], [100, 100, 100 * 100 * 4]);
  assert.ok(pixels(icon).every((p) => p[3] === 255), "opaque everywhere");
  for (const [x, y] of [[0, 0], [99, 0], [0, 99], [99, 99], [50, 30], [20, 50], [80, 50]]) assert.deepEqual(pixel(icon, x, y), [255, 204, 0, 255], `background at ${x},${y}`);
  for (const [x, y] of [[50, 50], [30, 42], [69, 57]]) assert.deepEqual(pixel(icon, x, y), [0, 0, 255, 255], `logo at ${x},${y}`);
  // the logo's transparent margin shows the background, not black
  assert.deepEqual(pixel(icon, 26, 38), [255, 204, 0, 255]);
});

test("compose: blends by alpha, and enlarges a small image to fill its fraction", () => {
  const veil = compose(solid(10, 10, [0, 0, 0, 128]), 20, "#FFFFFF", 0.5);
  assert.deepEqual(pixel(veil, 10, 10), [127, 127, 127, 255]);
  assert.deepEqual(pixel(veil, 2, 2), [255, 255, 255, 255]);

  const icon = compose(solid(16, 16, [200, 0, 0, 255]), 1024, "#FFFFFF", 0.62); // 635 px, from 194 to 829
  assert.deepEqual(pixel(icon, 512, 512), [200, 0, 0, 255]);
  assert.deepEqual([pixel(icon, 200, 512), pixel(icon, 825, 512), pixel(icon, 512, 200)], Array(3).fill([200, 0, 0, 255]));
  assert.deepEqual([pixel(icon, 190, 512), pixel(icon, 832, 512), pixel(icon, 512, 190)], Array(3).fill([255, 255, 255, 255]));
});

test("backgroundOf: the top-left pixel when it is opaque, else white", () => {
  assert.equal(backgroundOf(solid(2, 2, [28, 110, 74, 255])), "#1C6E4A");
  assert.equal(backgroundOf(solid(2, 2, [0, 0, 0, 255])), "#000000");
  assert.equal(backgroundOf(solid(2, 2, [28, 110, 74, 0])), "#FFFFFF");
  assert.equal(backgroundOf(solid(2, 2, [28, 110, 74, 254])), "#FFFFFF", "a soft corner is not a background");
  const corner = solid(2, 2, [1, 2, 3, 255]);
  corner.data.set([9, 9, 9, 0], 0); // only the first pixel counts
  assert.equal(backgroundOf(corner), "#FFFFFF");
});

test("backgroundOf: a light logo on a transparent background gets the dark colour, so it can be seen", () => {
  const white = solid(3, 3, [255, 255, 255, 255]);
  white.data.set([0, 0, 0, 0], 0); // a transparent corner: the logo has no background of its own
  assert.equal(backgroundOf(white), "#17150F");
  assert.equal(backgroundOf(white, "#7A1F2B"), "#7A1F2B");
  const faint = solid(3, 3, [0, 0, 0, 0]);
  faint.data.set([250, 250, 250, 255], 16); // one white pixel among transparent black ones: transparent pixels don't count
  assert.equal(backgroundOf(faint), "#17150F");
});

test("plainIcon: an opaque square with a rounded square in the mark colour in the middle", () => {
  const icon = plainIcon(200, "#17150F", "#F6F4F0");
  assert.deepEqual([icon.width, icon.height], [200, 200]);
  assert.ok(pixels(icon).every((p) => p[3] === 255), "opaque everywhere");
  for (const [x, y] of [[0, 0], [199, 199], [100, 50], [50, 100]]) assert.deepEqual(pixel(icon, x, y), [0x17, 0x15, 0x0f, 255]);
  for (const [x, y] of [[100, 100], [100, 64], [64, 100], [136, 100]]) assert.deepEqual(pixel(icon, x, y), [0xf6, 0xf4, 0xf0, 255]);
  // the mark spans 62...138; its corners are rounded off
  for (const [x, y] of [[62, 62], [137, 62], [62, 137], [137, 137]]) assert.deepEqual(pixel(icon, x, y), [0x17, 0x15, 0x0f, 255], `corner ${x},${y}`);
  assert.deepEqual(decodePng(encodePng(icon, { alpha: false })), icon);
});
