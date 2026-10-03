// Shared image-validation helpers for Edge Functions (SEC-H10).
//
// Pure byte-level parsing — no native image bindings needed in the Edge
// runtime. Used by upload-image to sniff magic bytes and read pixel
// dimensions WITHOUT decoding the image (a decompression bomb must be
// rejected before any decoder touches it).

/** Image types the platform accepts. SVG/BMP/TIFF/GIF are rejected. */
export type ImageType = "png" | "jpeg" | "webp";

export const IMAGE_CONTENT_TYPES: Record<ImageType, string> = {
  png: "image/png",
  jpeg: "image/jpeg",
  webp: "image/webp",
};

export const IMAGE_EXTENSIONS: Record<ImageType, string> = {
  png: "png",
  jpeg: "jpg",
  webp: "webp",
};

/** Magic-byte sniff. Returns null for anything that is not PNG/JPEG/WebP
 * (notably SVG, BMP, TIFF, GIF, and polyglots with a foreign header). */
export function sniffImage(b: Uint8Array): ImageType | null {
  if (
    b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e &&
    b[3] === 0x47 && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a &&
    b[7] === 0x0a
  ) {
    return "png";
  }
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
    return "jpeg";
  }
  if (
    b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 &&
    b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 &&
    b[11] === 0x50
  ) {
    return "webp";
  }
  return null;
}

function readU16BE(b: Uint8Array, o: number): number {
  return (b[o] << 8) | b[o + 1];
}

function readU32BE(b: Uint8Array, o: number): number {
  return b[o] * 0x1000000 + (b[o + 1] << 16) + (b[o + 2] << 8) + b[o + 3];
}

function pngDimensions(b: Uint8Array): { w: number; h: number } | null {
  // 8-byte signature, then IHDR chunk: length(4)=13, type(4)="IHDR".
  if (b.length < 24 || readU32BE(b, 8) !== 13) return null;
  if (b[12] !== 0x49 || b[13] !== 0x48 || b[14] !== 0x44 || b[15] !== 0x52) {
    return null;
  }
  return { w: readU32BE(b, 16), h: readU32BE(b, 20) };
}

function jpegDimensions(b: Uint8Array): { w: number; h: number } | null {
  let o = 2; // skip SOI
  while (o + 4 < b.length) {
    if (b[o] !== 0xff) return null;
    const marker = b[o + 1];
    if (marker >= 0xc0 && marker <= 0xc3) {
      // SOF0..SOF3: len(2), precision(1), height(2), width(2)
      return { h: readU16BE(b, o + 5), w: readU16BE(b, o + 7) };
    }
    if (
      marker === 0xd8 || marker === 0xd9 ||
      (marker >= 0xd0 && marker <= 0xd7)
    ) {
      o += 2;
      continue;
    }
    const len = readU16BE(b, o + 2);
    if (len < 2) return null;
    o += 2 + len;
  }
  return null;
}

function webpDimensions(b: Uint8Array): { w: number; h: number } | null {
  let o = 12; // skip RIFF header
  while (o + 8 <= b.length) {
    const fourcc = String.fromCharCode(b[o + 4], b[o + 5], b[o + 6], b[o + 7]);
    const size = b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
    const d = o + 8;
    if (fourcc === "VP8X" && d + 10 <= b.length) {
      const w = (b[d + 4] | (b[d + 5] << 8) | (b[d + 6] << 16)) + 1;
      const h = (b[d + 7] | (b[d + 8] << 8) | (b[d + 9] << 16)) + 1;
      return { w, h };
    }
    if (fourcc === "VP8 " && d + 10 <= b.length) {
      // frame tag (3) + start code 9D 01 2A, then 14-bit w/h (LE)
      if (b[d + 3] === 0x9d && b[d + 4] === 0x01 && b[d + 5] === 0x2a) {
        const w = b[d + 6] | ((b[d + 7] & 0x3f) << 8);
        const h = b[d + 8] | ((b[d + 9] & 0x3f) << 8);
        return { w, h };
      }
      return null;
    }
    if (fourcc === "VP8L" && d + 5 <= b.length) {
      if (b[d] !== 0x2f) return null;
      const bits = b[d + 1] | (b[d + 2] << 8) | (b[d + 3] << 16) |
        (b[d + 4] << 24);
      return { w: (bits & 0x3fff) + 1, h: ((bits >> 14) & 0x3fff) + 1 };
    }
    o = d + size + (size % 2); // chunks are 2-byte aligned
  }
  return null;
}

/**
 * Reads pixel dimensions from the image header without decoding pixels.
 * Returns null when the header is malformed or truncated.
 */
export function imageDimensions(
  b: Uint8Array,
  t: ImageType,
): { w: number; h: number } | null {
  if (t === "png") return pngDimensions(b);
  if (t === "jpeg") return jpegDimensions(b);
  return webpDimensions(b);
}

/** Strict base64 decode; null on malformed input. */
export function base64ToBytes(s: string): Uint8Array | null {
  try {
    const bin = atob(s.replace(/\s+/g, ""));
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

/** URL/filename-safe random hex (nBytes → 2*nBytes hex chars). */
export function randomHex(nBytes: number): string {
  return [...crypto.getRandomValues(new Uint8Array(nBytes))]
    .map((x) => x.toString(16).padStart(2, "0"))
    .join("");
}
