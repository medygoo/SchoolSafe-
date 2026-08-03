import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  ImageMagick,
  initializeImageMagick,
  MagickFormat,
  MagickGeometry,
} from "@imagemagick/magick-wasm";

const MAX_INPUT_SIZE = 8 * 1024 * 1024;
const MAX_FINAL_SIZE = 5 * 1024 * 1024;
const MAX_DIMENSION = 12000;
const MAX_PIXELS = 40_000_000;
const OPTIMIZATION_VERSION = 1;
const IMAGE_MIME_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const ALLOWED_MIME_TYPES = new Set([...IMAGE_MIME_TYPES, "application/pdf"]);
const DOCUMENT_CATEGORIES = new Set([
  "document", "receipt", "homework", "report", "archive",
  "teacher_preparation", "administrative_document",
]);
const DEFAULT_ORIGINS = [
  "https://medygoo.github.io",
  "https://medt121.github.io",
  "https://cslesage.com",
  "https://www.cslesage.com",
];

type Json = Record<string, unknown>;
type Dimensions = { width: number; height: number };
type Profile = { name: "photo" | "identity" | "card" | "document"; maxDimension: number; quality: number };
type OptimizedImage = {
  bytes: Uint8Array;
  originalWidth: number;
  originalHeight: number;
  finalWidth: number;
  finalHeight: number;
  quality: number;
};

const wasmBytes = await Deno.readFile(
  new URL("magick.wasm", import.meta.resolve("npm:@imagemagick/magick-wasm@0.0.40")),
);
await initializeImageMagick(wasmBytes);

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function defaultSupabaseKey(name: string): string {
  const raw = requiredEnv(name);
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    return parsed.default || Object.values(parsed)[0] || raw;
  } catch (_) {
    return raw;
  }
}

function allowedOrigins(): Set<string> {
  const configured = Deno.env.get("APP_ALLOWED_ORIGINS");
  return new Set(configured
    ? configured.split(",").map((value) => value.trim()).filter(Boolean)
    : DEFAULT_ORIGINS);
}

function corsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-idempotency-key",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
  if (origin && allowedOrigins().has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

function respond(data: Json, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function safeFilename(value: string): string {
  return value.replace(/[\r\n"\\]/g, "_").slice(0, 160) || "document";
}

function safeWebpFilename(name: string): string {
  const safe = safeFilename(name).slice(0, 150);
  return `${safe.replace(/\.[^.]{1,10}$/u, "") || "image"}.webp`;
}

function detectMime(bytes: Uint8Array): string | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a) return "image/png";
  if (bytes.length >= 12 && String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" && String.fromCharCode(...bytes.slice(8, 12)) === "WEBP") return "image/webp";
  if (bytes.length >= 5 && String.fromCharCode(...bytes.slice(0, 5)) === "%PDF-") return "application/pdf";
  return null;
}

function readU24LE(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

function parsePngDimensions(bytes: Uint8Array): Dimensions | null {
  if (bytes.length < 24) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { width: view.getUint32(16, false), height: view.getUint32(20, false) };
}

function parseJpegDimensions(bytes: Uint8Array): Dimensions | null {
  let offset = 2;
  const sofMarkers = new Set([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf]);
  while (offset + 9 < bytes.length) {
    if (bytes[offset] !== 0xff) { offset += 1; continue; }
    while (offset < bytes.length && bytes[offset] === 0xff) offset += 1;
    const marker = bytes[offset++];
    if (marker === 0xd8 || marker === 0xd9) continue;
    if (marker === 0xda) break;
    if (offset + 1 >= bytes.length) break;
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    if (length < 2 || offset + length > bytes.length) break;
    if (sofMarkers.has(marker) && length >= 7) {
      const height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      const width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      return { width, height };
    }
    offset += length;
  }
  return null;
}

function parseWebpDimensions(bytes: Uint8Array): Dimensions | null {
  if (bytes.length < 30) return null;
  const chunk = String.fromCharCode(...bytes.slice(12, 16));
  if (chunk === "VP8X" && bytes.length >= 30) {
    return { width: 1 + readU24LE(bytes, 24), height: 1 + readU24LE(bytes, 27) };
  }
  if (chunk === "VP8 " && bytes.length >= 30 && bytes[23] === 0x9d && bytes[24] === 0x01 && bytes[25] === 0x2a) {
    return {
      width: ((bytes[27] << 8) | bytes[26]) & 0x3fff,
      height: ((bytes[29] << 8) | bytes[28]) & 0x3fff,
    };
  }
  if (chunk === "VP8L" && bytes.length >= 25 && bytes[20] === 0x2f) {
    const bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) | (bytes[24] << 24);
    return { width: 1 + (bits & 0x3fff), height: 1 + ((bits >> 14) & 0x3fff) };
  }
  return null;
}

function parseDimensions(bytes: Uint8Array, mime: string): Dimensions | null {
  if (mime === "image/png") return parsePngDimensions(bytes);
  if (mime === "image/jpeg") return parseJpegDimensions(bytes);
  if (mime === "image/webp") return parseWebpDimensions(bytes);
  return null;
}

function validateDimensions(dimensions: Dimensions | null): boolean {
  if (!dimensions) return false;
  return dimensions.width >= 1 && dimensions.height >= 1 &&
    dimensions.width <= MAX_DIMENSION && dimensions.height <= MAX_DIMENSION &&
    dimensions.width * dimensions.height <= MAX_PIXELS;
}

function profileFor(category: string): Profile {
  if (DOCUMENT_CATEGORIES.has(category)) return { name: "document", maxDimension: 2400, quality: 84 };
  if (category === "identity") return { name: "identity", maxDimension: 1600, quality: 80 };
  if (category === "card") return { name: "card", maxDimension: 1800, quality: 84 };
  return { name: "photo", maxDimension: 1280, quality: 76 };
}

function resizeWithin(image: { width: number; height: number; resize: (geometry: MagickGeometry) => void }, maxDimension: number): void {
  const largest = Math.max(image.width, image.height);
  if (largest <= maxDimension) return;
  const ratio = maxDimension / largest;
  const geometry = new MagickGeometry(
    Math.max(1, Math.round(image.width * ratio)),
    Math.max(1, Math.round(image.height * ratio)),
  );
  geometry.ignoreAspectRatio = false;
  image.resize(geometry);
}

function optimizeImage(input: Uint8Array, profile: Profile): OptimizedImage {
  let result: OptimizedImage | null = null;
  ImageMagick.read(input, (image) => {
    const originalWidth = image.width;
    const originalHeight = image.height;
    const optional = image as unknown as {
      autoOrient?: () => void;
      removeProfile?: (name: string) => unknown;
    };
    optional.autoOrient?.();
    optional.removeProfile?.("exif");
    optional.removeProfile?.("xmp");
    optional.removeProfile?.("iptc");

    resizeWithin(image, profile.maxDimension);
    let quality = profile.quality;
    let output = new Uint8Array();

    for (let attempt = 0; attempt < 3; attempt += 1) {
      image.quality = quality;
      image.write(MagickFormat.WebP, (data: Uint8Array) => { output = Uint8Array.from(data); });
      if (output.length > 0 && output.length <= MAX_FINAL_SIZE) break;
      quality = Math.max(64, quality - 8);
      resizeWithin(image, Math.max(1200, Math.round(Math.max(image.width, image.height) * 0.8)));
    }

    if (output.length === 0 || output.length > MAX_FINAL_SIZE) {
      throw new Error("Optimized image remains larger than 5 MB");
    }
    result = {
      bytes: output,
      originalWidth,
      originalHeight,
      finalWidth: image.width,
      finalHeight: image.height,
      quality,
    };
  });
  if (!result) throw new Error("Image optimization produced no output");
  return result;
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmacHex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function copyFormFields(source: FormData, target: FormData): void {
  for (const [key, value] of source.entries()) if (key !== "file") target.append(key, value);
}

async function forwardToR2Files(request: Request, form: FormData, signature: string): Promise<Response> {
  const supabaseUrl = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
  const headers = new Headers();
  for (const name of ["Authorization", "apikey", "x-client-info", "x-idempotency-key"]) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  headers.set("x-schoolsafe-processing-signature", signature);
  return await fetch(`${supabaseUrl}/functions/v1/r2-files`, { method: "POST", headers, body: form });
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("Origin");
  if (request.method === "OPTIONS") {
    if (origin && !allowedOrigins().has(origin)) return respond({ error: "Origin not allowed" }, 403, origin);
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (request.method !== "POST") return respond({ error: "Method not allowed" }, 405, origin);
  if (origin && !allowedOrigins().has(origin)) return respond({ error: "Origin not allowed" }, 403, origin);

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) return respond({ error: "Authentication required" }, 401, origin);

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")
      ? defaultSupabaseKey("SUPABASE_PUBLISHABLE_KEYS")
      : requiredEnv("SUPABASE_ANON_KEY");
    const secretKey = defaultSupabaseKey("SUPABASE_SECRET_KEYS");
    const userClient = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const admin = createClient(supabaseUrl, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return respond({ error: "Invalid session" }, 401, origin);

    const contentType = request.headers.get("Content-Type") || "";
    if (!contentType.includes("multipart/form-data")) return respond({ error: "Multipart form required" }, 400, origin);

    const idempotencyKey = String(request.headers.get("x-idempotency-key") || "").trim();
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey)) {
      return respond({ error: "A valid x-idempotency-key header is required" }, 400, origin);
    }

    const sourceForm = await request.formData();
    const file = sourceForm.get("file");
    if (!(file instanceof File)) return respond({ error: "File is required" }, 400, origin);
    if (file.size <= 0 || file.size > MAX_INPUT_SIZE) return respond({ error: "Source file must be between 1 byte and 8 MB" }, 413, origin);

    const sourceBytes = new Uint8Array(await file.arrayBuffer());
    const sourceMime = detectMime(sourceBytes);
    if (!sourceMime || !ALLOWED_MIME_TYPES.has(sourceMime)) return respond({ error: "Unsupported or corrupt file" }, 415, origin);
    if (file.type && file.type !== sourceMime) return respond({ error: "File content does not match its declared type" }, 415, origin);

    const category = String(sourceForm.get("category") || "document").trim().toLowerCase();
    const targetForm = new FormData();
    copyFormFields(sourceForm, targetForm);

    let finalBytes = sourceBytes;
    let finalMime = sourceMime;
    let finalName = safeFilename(file.name);
    let sourceDimensions: Dimensions | null = null;
    let finalDimensions: Dimensions | null = null;
    let optimized = false;
    let quality: number | null = null;
    let profileName: "photo" | "identity" | "card" | "document" | "passthrough" = "passthrough";

    if (IMAGE_MIME_TYPES.has(sourceMime)) {
      sourceDimensions = parseDimensions(sourceBytes, sourceMime);
      if (!validateDimensions(sourceDimensions)) {
        return respond({ error: "Image dimensions are invalid or exceed 40 megapixels" }, 413, origin);
      }
      const profile = profileFor(category);
      profileName = profile.name;
      const candidate = optimizeImage(sourceBytes, profile);
      const mustUseCandidate = sourceBytes.length > MAX_FINAL_SIZE;
      const candidateIsSmaller = candidate.bytes.length <= Math.floor(sourceBytes.length * 0.98);
      if (mustUseCandidate || candidateIsSmaller) {
        finalBytes = candidate.bytes;
        finalMime = "image/webp";
        finalName = safeWebpFilename(file.name);
        finalDimensions = { width: candidate.finalWidth, height: candidate.finalHeight };
        optimized = true;
        quality = candidate.quality;
      } else {
        finalDimensions = sourceDimensions;
      }
    }

    if (finalBytes.length > MAX_FINAL_SIZE) return respond({ error: "Final file exceeds 5 MB" }, 413, origin);
    const finalFile = new File([finalBytes], finalName, { type: finalMime });
    targetForm.append("file", finalFile);

    const checksum = await sha256Hex(finalBytes);
    const signingPayload = `${checksum}\n${idempotencyKey}\n${finalBytes.length}\n${finalMime}`;
    const signature = await hmacHex(secretKey, signingPayload);
    const upstream = await forwardToR2Files(request, targetForm, signature);
    const rawBody = await upstream.text();
    let parsed: Json;
    try { parsed = JSON.parse(rawBody) as Json; } catch (_) { parsed = { error: "Invalid storage service response" }; }
    if (!upstream.ok) return respond(parsed, upstream.status, origin);

    const fileRecord = parsed.file as Json | undefined;
    const fileId = String(fileRecord?.id || "");
    if (!fileId) return respond({ error: "Storage response did not include a file id" }, 502, origin);

    const { data: existing, error: lookupError } = await admin
      .from("school_files")
      .select("id,metadata,size_bytes,mime_type")
      .eq("id", fileId)
      .maybeSingle();
    if (lookupError || !existing) {
      return respond({ error: "Upload completed but optimization metadata lookup failed", upload_committed: true, file_id: fileId, retry_same_idempotency_key: true }, 500, origin);
    }
    const existingMetadata = existing.metadata && typeof existing.metadata === "object" ? existing.metadata as Json : {};
    const metrics = {
      version: OPTIMIZATION_VERSION,
      optimized,
      profile: profileName,
      source_size: sourceBytes.length,
      final_size: Number(existing.size_bytes),
      source_mime_type: sourceMime,
      final_mime_type: String(existing.mime_type),
      source_width: sourceDimensions?.width ?? null,
      source_height: sourceDimensions?.height ?? null,
      final_width: finalDimensions?.width ?? null,
      final_height: finalDimensions?.height ?? null,
      quality,
    };
    const { data: updated, error: updateError } = await admin
      .from("school_files")
      .update({
        source_original_name: safeFilename(file.name),
        source_mime_type: sourceMime,
        source_size_bytes: sourceBytes.length,
        source_width: sourceDimensions?.width ?? null,
        source_height: sourceDimensions?.height ?? null,
        processed_width: finalDimensions?.width ?? null,
        processed_height: finalDimensions?.height ?? null,
        compression_quality: quality,
        compression_profile: profileName,
        optimized,
        optimization_version: OPTIMIZATION_VERSION,
        metadata: { ...existingMetadata, optimization: metrics },
      })
      .eq("id", fileId)
      .select("id,source_size_bytes,size_bytes,compression_saved_bytes,compression_ratio_pct,optimized,compression_profile,source_width,source_height,processed_width,processed_height")
      .single();
    if (updateError) {
      return respond({ error: "Upload completed but optimization metadata update failed", upload_committed: true, file_id: fileId, retry_same_idempotency_key: true }, 500, origin);
    }

    return respond({ ...parsed, optimization: updated }, upstream.status, origin);
  } catch (error) {
    console.error("r2-upload error", error instanceof Error ? error.message : "unknown error");
    return respond({ error: "Image upload service unavailable" }, 500, origin);
  }
});
