// POST /functions/v1/upload-image
//
// Secure image upload endpoint (SEC-H10). This is the server-side
// replacement for direct client-side Storage uploads (tenant logos and
// student/staff photos), which today have only bypassable Dart-side
// validation and no content-type guarantees.
//
// Pipeline:
//   JWT auth → tenant membership → per-kind permission check
//   (`settings.update` / `students.update` / `staff.update`, or legacy
//   tenant_owner/tenant_admin) → magic-byte sniff (PNG/JPEG/WebP ONLY;
//   SVG/BMP/TIFF/GIF rejected) → server-side size cap → pixel-dimension
//   cap (decompression-bomb guard) → server-generated filename (never from
//   user input) → fixed contentType → the function writes
//   logo_url/photo_url itself.
//
// Body (JSON):
//   { tenant_id, kind: "logo" | "student_photo" | "staff_photo",
//     entity_id?, content_base64 }
//   entity_id is required for *_photo kinds and must belong to tenant_id;
//   it must NOT be sent for kind=logo.
//
// Buckets: tenant-logos (public), student-photos / staff-photos (private).
// Photo URLs are stored as storage PATHS — serve private photos via
// short-lived signed URLs, never public buckets. The response includes a
// 1-hour signed URL for immediate use.
//
// NOTE (limitation): without native image bindings in the Edge runtime we
// cannot re-encode uploads (the ideal polyglot/metadata stripper). The
// combination of magic-byte sniffing + dimension caps + size caps is the
// practical server-side control; treat served bytes as untrusted and serve
// with the fixed contentType below.

import {
  badBodyResponse,
  hasEffectivePermission,
  invalidBodyResponse,
  json,
  logServerError,
  newCorrelationId,
  preflight,
  rateLimit,
  readJsonBody,
  resolveJwtUser,
  serviceClient,
  tooManyRequests,
  validateBody,
  type FieldRule,
} from "../_shared/guard.ts";
import {
  base64ToBytes,
  IMAGE_CONTENT_TYPES,
  IMAGE_EXTENSIONS,
  imageDimensions,
  sniffImage,
} from "../_shared/image.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";

type Kind = "logo" | "student_photo" | "staff_photo";

interface KindConfig {
  bucket: string;
  /** Max decoded bytes. */
  maxBytes: number;
  /** Effective permission code, or legacy owner/admin rank. */
  permission: string;
  /** Table + column the function writes the URL into. */
  table: string;
  urlColumn: string;
  /** Logos live in a public bucket; photos are private (path stored). */
  public: boolean;
}

const KINDS: Record<Kind, KindConfig> = {
  logo: {
    bucket: "tenant-logos",
    maxBytes: 5_242_880, // 5 MiB
    permission: "settings.update",
    table: "tenants",
    urlColumn: "logo_url",
    public: true,
  },
  student_photo: {
    bucket: "student-photos",
    maxBytes: 2_097_152, // 2 MiB
    permission: "students.update",
    table: "students",
    urlColumn: "photo_url",
    public: false,
  },
  staff_photo: {
    bucket: "staff-photos",
    maxBytes: 2_097_152, // 2 MiB
    permission: "staff.update",
    table: "staff",
    urlColumn: "photo_url",
    public: false,
  },
};

const KIND_KEYS = new Set(Object.keys(KINDS));
const LEGACY_MANAGERS = new Set(["tenant_owner", "tenant_admin"]);

/** Pixel-dimension caps — a tiny file declaring gigapixel dimensions is a
 * decompression bomb; reject it without decoding. */
const MAX_DIMENSION = 4096;
const MAX_PIXELS = 16_777_216; // 4096^2

Deno.serve(async (req: Request): Promise<Response> => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed", message: "Use POST." }, 405);
  }

  let supabase: SupabaseClient;
  try {
    supabase = serviceClient();
  } catch {
    return json(
      { error: "server_misconfigured", message: "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY." },
      500,
    );
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";

  // ── authenticate ─────────────────────────────────────────────
  const callerOr = await resolveJwtUser(req, supabase);
  if (!callerOr.ok) return callerOr.response;
  const callerId = callerOr.userId;

  // ── validate body ──────────────────────────────────────────
  // 8 MiB JSON cap: base64 inflates ~33%, and the largest raw payload
  // (5 MiB logo) needs ~6.7 MiB of base64.
  const parsed = await readJsonBody(req, 8_000_000);
  if (!parsed.ok) return badBodyResponse(parsed);
  const BODY_SCHEMA: Record<string, FieldRule> = {
    tenant_id: { required: true, type: "uuid" },
    kind: { required: true, type: "string", minLength: 1, maxLength: 32 },
    entity_id: { type: "uuid", allowNull: true },
    content_base64: { required: true, type: "string", minLength: 1, maxLength: 11_000_000 },
  };
  const valid = validateBody(parsed.body, BODY_SCHEMA);
  if (!valid.ok) return invalidBodyResponse(valid.problems);
  const body = parsed.body;

  const tenantId = body["tenant_id"] as string;
  const kind = body["kind"] as string;
  const entityId = (body["entity_id"] as string | null | undefined) ?? null;

  if (!KIND_KEYS.has(kind)) {
    return json(
      { error: "invalid_kind", message: "kind must be logo, student_photo, or staff_photo." },
      400,
    );
  }
  const cfg = KINDS[kind as Kind];
  const needsEntity = kind !== "logo";
  if (needsEntity && !entityId) {
    return json({ error: "invalid_input", message: "entity_id is required for photo uploads." }, 400);
  }
  if (!needsEntity && entityId) {
    return json({ error: "invalid_input", message: "entity_id must not be sent for kind=logo." }, 400);
  }

  // ── authorize ──────────────────────────────────────────────
  const { data: adminRow } = await supabase
    .from("platform_admins")
    .select("user_id")
    .eq("user_id", callerId)
    .maybeSingle();
  if (!adminRow) {
    const { data: membership, error: mErr } = await supabase
      .from("tenant_memberships")
      .select("role")
      .eq("tenant_id", tenantId)
      .eq("user_id", callerId)
      .eq("is_active", true)
      .maybeSingle();
    if (mErr || !membership) {
      return json({ error: "forbidden", message: "Not a member of this tenant." }, 403);
    }
    const role = membership.role as string;
    const permitted = LEGACY_MANAGERS.has(role) ||
      await hasEffectivePermission(supabase, tenantId, callerId, cfg.permission);
    if (!permitted) {
      return json(
        {
          error: "forbidden",
          message: `Uploading this image requires the ${cfg.permission} permission.`,
        },
        403,
      );
    }
  }

  // ── rate limit (RED-TEAM RT-03) ──────────────────────────────
  // 5 MiB uploads are the most expensive request this API serves;
  // without a limit one compromised manager account could fill the
  // bucket (storage-exhaustion DoS).
  const rl = await rateLimit(
    supabase,
    `upload-image:${callerId}:${tenantId}`,
    60,
    3600,
  );
  if (!rl.allowed) return tooManyRequests(rl.retryAfterSec);

  // Photos: the entity must belong to the caller's tenant (no cross-tenant
  // writes via a foreign entity_id).
  if (needsEntity) {
    const { data: entity, error: entErr } = await supabase
      .from(cfg.table)
      .select("id")
      .eq("id", entityId)
      .eq("tenant_id", tenantId)
      .maybeSingle();
    if (entErr || !entity) {
      const cid = newCorrelationId();
      if (entErr) logServerError("upload-image", cid, "entity_lookup", entErr);
      return json(
        { error: "entity_not_found", message: "The target record was not found in this tenant.", ref: cid },
        404,
      );
    }
  }

  // ── decode + sniff ─────────────────────────────────────────
  const bytes = base64ToBytes(body["content_base64"] as string);
  if (!bytes || bytes.length === 0) {
    return json({ error: "bad_image", message: "Could not decode the image data." }, 400);
  }
  if (bytes.length > cfg.maxBytes) {
    return json(
      {
        error: "too_large",
        message: `Image exceeds the ${Math.round(cfg.maxBytes / 1048576)} MiB limit for ${kind}.`,
      },
      413,
    );
  }
  const imageType = sniffImage(bytes);
  if (!imageType) {
    return json(
      { error: "bad_image", message: "Only PNG, JPEG, and WebP images are accepted." },
      400,
    );
  }
  const dims = imageDimensions(bytes, imageType);
  if (!dims || dims.w <= 0 || dims.h <= 0) {
    return json({ error: "bad_image", message: "Could not read the image dimensions." }, 400);
  }
  if (dims.w > MAX_DIMENSION || dims.h > MAX_DIMENSION || dims.w * dims.h > MAX_PIXELS) {
    return json(
      {
        error: "bad_dimensions",
        message: `Image dimensions exceed the ${MAX_DIMENSION}px / ${MAX_PIXELS} pixel limit.`,
      },
      400,
    );
  }

  // ── store (deterministic, policy-matching path) ─────────────
  // RED-TEAM RT-04: paths MUST follow the convention migration 040's
  // storage RLS policies parse —
  //   <tenant_id>/logo.<ext>
  //   <tenant_id>/students/<student_id>.<ext>
  //   <tenant_id>/staff/<staff_id>.<ext>
  // A random-suffix layout broke the parent-of-student SELECT exception
  // (storage_photo_student_id() parses foldername[3]) and orphaned every
  // replaced image. Deterministic paths + upsert make replacement atomic
  // and keep the policy's student-id extraction working.
  const ext = IMAGE_EXTENSIONS[imageType];
  const targetId = needsEntity ? entityId! : tenantId;
  const path = needsEntity
    ? `${tenantId}/${kind === "student_photo" ? "students" : "staff"}/${entityId}.${ext}`
    : `${tenantId}/logo.${ext}`;

  // Remember the previous file so a changed extension (PNG -> WebP)
  // doesn't leave an orphan behind. Only paths inside this bucket are
  // ever deleted — external/legacy URLs are left alone.
  let oldPath: string | null = null;
  try {
    const { data: cur } = await supabase
      .from(cfg.table)
      .select(cfg.urlColumn)
      .eq("id", targetId)
      .maybeSingle();
    const curUrl = (cur as Record<string, unknown> | null)?.[cfg.urlColumn] as
      | string
      | null
      | undefined;
    if (typeof curUrl === "string" && curUrl !== "") {
      if (cfg.public) {
        const prefix =
          `${supabaseUrl}/storage/v1/object/public/${cfg.bucket}/`;
        if (curUrl.startsWith(prefix)) oldPath = curUrl.slice(prefix.length);
      } else if (!curUrl.includes("://")) {
        oldPath = curUrl;
      }
    }
  } catch {
    /* best-effort — never blocks the upload */
  }

  const { error: upErr } = await supabase.storage
    .from(cfg.bucket)
    .upload(path, bytes, {
      contentType: IMAGE_CONTENT_TYPES[imageType],
      upsert: true,
    });
  if (upErr) {
    const cid = newCorrelationId();
    logServerError("upload-image", cid, "storage_upload", upErr);
    return json(
      { error: "upload_failed", message: "Could not store the image.", ref: cid },
      500,
    );
  }

  // ── write the URL back ─────────────────────────────────────
  // Logos: public bucket → store the public URL (matches existing
  // tenants.logo_url semantics). Photos: private bucket → store the
  // storage path; serve via signed URLs, never public buckets.
  const storedUrl = cfg.public
    ? `${supabaseUrl}/storage/v1/object/public/${cfg.bucket}/${path}`
    : path;
  let urlQuery = supabase.from(cfg.table).update({ [cfg.urlColumn]: storedUrl });
  urlQuery = urlQuery.eq("id", targetId);
  if (needsEntity) {
    // tenants has no tenant_id column (it IS the tenant); scoped tables do.
    urlQuery = urlQuery.eq("tenant_id", tenantId);
  }
  const { error: urlErr } = await urlQuery;
  if (urlErr) {
    const cid = newCorrelationId();
    logServerError("upload-image", cid, "url_write", urlErr);
    // The bytes are safely stored; the URL write failed — report so the
    // caller can retry or reconcile (path is returned for recovery).
    return json(
      {
        error: "url_write_failed",
        message: "Image stored but the record could not be updated.",
        ref: cid,
        path,
      },
      500,
    );
  }

  // Best-effort audit row — never fails the upload.
  try {
    await supabase.from("audit_logs").insert({
      tenant_id: tenantId,
      user_id: callerId,
      action: "upload-image",
      entity: cfg.table,
      entity_id: targetId,
      new_data: { kind, path, bytes: bytes.length, width: dims.w, height: dims.h },
    });
  } catch {
    /* ignored */
  }

  // Delete the orphaned previous file when the extension changed
  // (logo.png -> logo.webp). Best-effort; never fails the upload.
  if (oldPath && oldPath !== path) {
    try {
      await supabase.storage.from(cfg.bucket).remove([oldPath]);
    } catch {
      /* ignored */
    }
  }

  // A short-lived signed URL for immediate display (photos especially).
  let displayUrl = storedUrl;
  if (!cfg.public) {
    const { data: signed } = await supabase.storage
      .from(cfg.bucket)
      .createSignedUrl(path, 3600);
    if (signed?.signedUrl) displayUrl = signed.signedUrl;
  }

  return json({
    ok: true,
    kind,
    path,
    url: displayUrl,
    width: dims.w,
    height: dims.h,
    bytes: bytes.length,
  });
});
