// Shared helpers for the Madrassa-360 platform (master-admin) Edge Functions.
// Not a function itself — imported via relative path, e.g.
//   import { preflight, json, requirePlatformAdmin } from "../_shared/guard.ts";

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.44.4";

/** CORS headers applied to every response from these functions. */
export const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Returns a 200 preflight response for OPTIONS, otherwise null. */
export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }
  return null;
}

/** JSON response with CORS headers attached. */
export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/**
 * Service-role client for internal DB work. Bypasses RLS on purpose —
 * these functions enforce authorization in code (platform-admin check below).
 * Secrets come ONLY from env; never hardcode them.
 */
export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error(
      "Server misconfigured: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are not set.",
    );
  }
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export type GuardResult =
  | { ok: true; supabase: SupabaseClient; callerId: string; callerRole: string }
  | { ok: false; response: Response };

/**
 * Platform-admin guard. Reads the JWT from the Authorization header, resolves
 * the caller via auth.getUser(), and requires a row in public.platform_admins.
 * Returns 401 (missing/bad token) or 403 (not a platform admin) on failure.
 * The caller must already be in platform_admins — bootstrap via SQL
 * (see supabase/functions/README.md).
 */
export async function requirePlatformAdmin(
  req: Request,
): Promise<GuardResult> {
  let supabase: SupabaseClient;
  try {
    supabase = serviceClient();
  } catch {
    return {
      ok: false,
      response: json(
        {
          error: "server_misconfigured",
          message:
            "Function secrets not configured. Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.",
        },
        500,
      ),
    };
  }

  const authz = req.headers.get("Authorization");
  if (!authz || !authz.toLowerCase().startsWith("bearer ")) {
    return {
      ok: false,
      response: json(
        {
          error: "unauthorized",
          message: "Missing Authorization: Bearer <jwt> header.",
        },
        401,
      ),
    };
  }
  const jwt = authz.slice(7).trim();
  if (!jwt) {
    return {
      ok: false,
      response: json({ error: "unauthorized", message: "Empty token." }, 401),
    };
  }

  const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
  const caller = userData?.user;
  if (userErr || !caller) {
    return {
      ok: false,
      response: json(
        { error: "unauthorized", message: "Invalid or expired token." },
        401,
      ),
    };
  }

  const { data: admin, error: adminErr } = await supabase
    .from("platform_admins")
    .select("user_id, role")
    .eq("user_id", caller.id)
    .maybeSingle();
  if (adminErr) {
    return {
      ok: false,
      response: json(
        {
          error: "auth_check_failed",
          message: "Could not verify platform admin status.",
        },
        500,
      ),
    };
  }
  if (!admin) {
    return {
      ok: false,
      response: json(
        {
          error: "forbidden",
          message: "Caller is not a platform admin (platform_admins).",
        },
        403,
      ),
    };
  }
  return { ok: true, supabase, callerId: caller.id, callerRole: admin.role };
}

// ── input validation helpers ──────────────────────────────────────────────

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function isEmail(v: unknown): v is string {
  return typeof v === "string" && EMAIL_RE.test(v.trim());
}

export function isUuid(v: unknown): v is string {
  return typeof v === "string" && UUID_RE.test(v);
}

export function isSlug(v: unknown): v is string {
  return typeof v === "string" && v.length <= 60 && SLUG_RE.test(v);
}

export function isNonEmptyString(v: unknown, max = 500): v is string {
  return typeof v === "string" && v.trim().length > 0 && v.length <= max;
}

/** Mirrors public.slugify() in 001_tenant_core.sql for client-side previews. */
export function slugify(text: string): string {
  const v = text
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return v || "tenant";
}

/** 'T-' + 8 random hex chars, uppercase — mirrors the tenants default. */
export function newTenantCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(4));
  return "T-" +
    Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")
      .toUpperCase();
}

/** Reads and parses a JSON body; returns { ok:false } on malformed JSON.
 *
 * Byte cap: bodies larger than [maxBytes] (default 1 MiB) are rejected with
 * `reason: "too_large"` BEFORE parsing — callers should map that to HTTP
 * 413. The cap is enforced twice: first via the declared Content-Length
 * (cheap reject), then while streaming the body so a lying header cannot
 * force unbounded memory allocation (SEC-M11).
 */
export async function readJsonBody(
  req: Request,
  maxBytes = 1_048_576,
): Promise<
  | { ok: true; body: Record<string, unknown> }
  | { ok: false; reason: "too_large" | "invalid" }
> {
  const declared = req.headers.get("content-length");
  if (declared !== null) {
    const n = Number(declared);
    if (Number.isFinite(n) && n > maxBytes) {
      return { ok: false, reason: "too_large" };
    }
  }
  try {
    const stream = req.body;
    if (!stream) {
      return { ok: false, reason: "invalid" };
    }
    const reader = stream.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await reader.cancel().catch(() => {});
        return { ok: false, reason: "too_large" };
      }
      chunks.push(value);
    }
    const merged = new Uint8Array(total);
    let off = 0;
    for (const c of chunks) {
      merged.set(c, off);
      off += c.byteLength;
    }
    const body = JSON.parse(new TextDecoder().decode(merged));
    if (body === null || typeof body !== "object" || Array.isArray(body)) {
      return { ok: false, reason: "invalid" };
    }
    return { ok: true, body: body as Record<string, unknown> };
  } catch {
    return { ok: false, reason: "invalid" };
  }
}

/** Maps a readJsonBody failure to the right HTTP response (413 vs 400). */
export function badBodyResponse(
  parsed: { ok: false; reason: "too_large" | "invalid" },
): Response {
  if (parsed.reason === "too_large") {
    return json(
      { error: "payload_too_large", message: "Request body exceeds the size limit." },
      413,
    );
  }
  return json(
    { error: "invalid_json", message: "Request body must be a JSON object." },
    400,
  );
}

/**
 * Parses an optional website field.
 * Returns { present: false } when omitted/blank, { present: true, url }
 * when valid, or { present: true, invalid: true } when malformed.
 */
export function parseWebsite(v: unknown): {
  present: boolean;
  url?: string;
  invalid?: boolean;
} {
  if (v === undefined || v === null) return { present: false };
  if (typeof v !== "string" || v.trim() === "") return { present: false };
  const trimmed = v.trim();
  try {
    const url = new URL(
      /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`,
    );
    if (url.protocol !== "http:" && url.protocol !== "https:") {
      return { present: true, invalid: true };
    }
    return { present: true, url: url.toString() };
  } catch {
    return { present: true, invalid: true };
  }
}

// ── centralized request validation (SEC-M12 / Phase 4.2) ──────────────────

/** Per-field validation rule for validateBody(). */
export interface FieldRule {
  required?: boolean;
  allowNull?: boolean;
  type?: "string" | "number" | "boolean" | "uuid" | "email" | "object" | "array";
  minLength?: number; // strings
  maxLength?: number; // strings
  minItems?: number; // arrays
  maxItems?: number; // arrays
  maxBytes?: number; // JSON-encoded size for objects
}

/**
 * Validates a parsed JSON body against a per-field schema.
 * - Rejects UNKNOWN keys with 400-worthy problems (mass-assignment defense:
 *   callers must allow-list every accepted key per action).
 * - Type-checks known keys; length/item/byte caps stop oversized payloads.
 * Returns { ok:true } or { ok:false, problems } — the caller maps problems
 * to a 400 response. Problem strings name only the offending FIELD, never
 * internal schema details.
 */
export function validateBody(
  body: Record<string, unknown>,
  schema: Record<string, FieldRule>,
): { ok: true } | { ok: false; problems: string[] } {
  const problems: string[] = [];
  for (const key of Object.keys(body)) {
    if (!Object.prototype.hasOwnProperty.call(schema, key)) {
      problems.push(`unknown field: ${key}`);
    }
  }
  for (const [key, rule] of Object.entries(schema)) {
    const v = body[key];
    if (v === undefined || v === null) {
      if (rule.required && !(v === null && rule.allowNull)) {
        problems.push(`missing required field: ${key}`);
      }
      continue;
    }
    const t = rule.type;
    if (t === "uuid" && !isUuid(v)) problems.push(`${key}: must be a UUID`);
    else if (t === "email" && !isEmail(v)) {
      problems.push(`${key}: must be a valid email`);
    } else if (t === "string" && typeof v !== "string") {
      problems.push(`${key}: must be a string`);
    } else if (t === "number" && typeof v !== "number") {
      problems.push(`${key}: must be a number`);
    } else if (t === "boolean" && typeof v !== "boolean") {
      problems.push(`${key}: must be a boolean`);
    } else if (t === "array" && !Array.isArray(v)) {
      problems.push(`${key}: must be an array`);
    } else if (
      t === "object" &&
      (typeof v !== "object" || Array.isArray(v))
    ) {
      problems.push(`${key}: must be an object`);
    }
    if (
      typeof v === "string" && rule.minLength !== undefined &&
      v.length < rule.minLength
    ) {
      problems.push(`${key}: must be at least ${rule.minLength} characters`);
    }
    if (
      typeof v === "string" && rule.maxLength !== undefined &&
      v.length > rule.maxLength
    ) {
      problems.push(`${key}: exceeds max length of ${rule.maxLength}`);
    }
    if (
      Array.isArray(v) && rule.minItems !== undefined &&
      v.length < rule.minItems
    ) {
      problems.push(`${key}: needs at least ${rule.minItems} items`);
    }
    if (
      Array.isArray(v) && rule.maxItems !== undefined &&
      v.length > rule.maxItems
    ) {
      problems.push(`${key}: exceeds max of ${rule.maxItems} items`);
    }
    if (t === "object" && rule.maxBytes !== undefined) {
      const n = JSON.stringify(v).length;
      if (n > rule.maxBytes) {
        problems.push(`${key}: exceeds max size of ${rule.maxBytes} bytes`);
      }
    }
  }
  return problems.length === 0 ? { ok: true } : { ok: false, problems };
}

/** 400 response for validateBody() failures. */
export function invalidBodyResponse(problems: string[]): Response {
  return json(
    {
      error: "invalid_input",
      message: "Request validation failed.",
      details: problems.slice(0, 10),
    },
    400,
  );
}

// ── error hygiene (SEC-H14) ────────────────────────────────────────────────

/** Short random id tying a client-visible error to its server-side log line. */
export function newCorrelationId(): string {
  return crypto.randomUUID().replace(/-/g, "").slice(0, 12);
}

/**
 * Server-side error log. Driver/SQL details go HERE (console) — never into
 * the HTTP response. Pair with `ref: cid` in the client response.
 */
export function logServerError(
  fn: string,
  cid: string,
  where: string,
  err: unknown,
): void {
  const msg = err instanceof Error ? err.message : String(err);
  console.error(`[${fn}] cid=${cid} ${where}: ${msg}`);
}

// ── shared authz helpers ───────────────────────────────────────────────────

/**
 * Resolves the caller from the Authorization Bearer JWT via auth.getUser().
 * 401 on missing/invalid/expired token. Does NOT check any role — the
 * caller authorizes after this.
 */
export async function resolveJwtUser(
  req: Request,
  supabase: SupabaseClient,
): Promise<{ ok: true; userId: string } | { ok: false; response: Response }> {
  const authz = req.headers.get("Authorization");
  const jwt = authz?.toLowerCase().startsWith("bearer ")
    ? authz.slice(7).trim()
    : "";
  if (!jwt) {
    return {
      ok: false,
      response: json(
        { error: "unauthorized", message: "Missing bearer token." },
        401,
      ),
    };
  }
  const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
  const caller = userData?.user;
  if (userErr || !caller) {
    return {
      ok: false,
      response: json(
        { error: "unauthorized", message: "Invalid or expired token." },
        401,
      ),
    };
  }
  return { ok: true, userId: caller.id };
}

/**
 * Effective-permission check via the 020 `user_effective_permission` RPC
 * (service role). Returns false on any error (fail closed). Consults only
 * server-side tables — never client-supplied role claims.
 */
export async function hasEffectivePermission(
  supabase: SupabaseClient,
  tenantId: string,
  userId: string,
  code: string,
): Promise<boolean> {
  const { data, error } = await supabase.rpc("user_effective_permission", {
    p_tenant_id: tenantId,
    p_user_id: userId,
    p_code: code,
  });
  if (error) return false;
  return data === true;
}

// ── rate limiting (SEC-H8 / Phase 4.4) ─────────────────────────────────────
//
// Backed by a Postgres event log so limits hold across Deno isolates
// (in-memory buckets alone are insufficient on Deno Deploy). Inserts are
// atomic; the count is a fixed-window snapshot — races make it slightly
// permissive, which is acceptable for abuse throttling.
//
// Backing table: migration 045_edge_rate_limits
//   CREATE TABLE public.edge_rate_limits (
//     id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
//     bucket_key TEXT NOT NULL,
//     created_at TIMESTAMPTZ NOT NULL DEFAULT now()
//   );
//   CREATE INDEX ix_edge_rate_limits_key_time
//     ON public.edge_rate_limits (bucket_key, created_at);
//   -- RLS enabled, no policies: service-role only.

/** Result of a rate-limit check. */
export interface RateLimitResult {
  allowed: boolean;
  /** Seconds the caller should wait before retrying (for Retry-After). */
  retryAfterSec: number;
}

/**
 * Fixed-window rate limiter. Records one event per allowed call in
 * `edge_rate_limits` and denies when [maxEvents] were already recorded
 * inside the trailing [windowSec] seconds.
 *
 * Fail-open on infrastructure errors (missing table, DB down): abuse
 * throttling must never turn into a self-inflicted outage. The failure is
 * logged server-side.
 */
export async function rateLimit(
  supabase: SupabaseClient,
  bucketKey: string,
  maxEvents: number,
  windowSec: number,
): Promise<RateLimitResult> {
  const windowStart = new Date(Date.now() - windowSec * 1000).toISOString();
  try {
    const { count, error } = await supabase
      .from("edge_rate_limits")
      .select("id", { count: "exact", head: true })
      .eq("bucket_key", bucketKey)
      .gt("created_at", windowStart);
    if (error) throw error;
    if ((count ?? 0) >= maxEvents) {
      return { allowed: false, retryAfterSec: windowSec };
    }
    const { error: insErr } = await supabase
      .from("edge_rate_limits")
      .insert({ bucket_key: bucketKey });
    if (insErr) throw insErr;
    // Opportunistic cleanup of expired rows (~5% of calls).
    if (Math.random() < 0.05) {
      const cutoff = new Date(Date.now() - 2 * windowSec * 1000).toISOString();
      await supabase.from("edge_rate_limits").delete().lt(
        "created_at",
        cutoff,
      );
    }
    return { allowed: true, retryAfterSec: 0 };
  } catch (e) {
    console.error(
      "[guard] rateLimit infra failure (failing open):",
      e instanceof Error ? e.message : String(e),
    );
    return { allowed: true, retryAfterSec: 0 };
  }
}

/** 429 response with a Retry-After header. */
export function tooManyRequests(retryAfterSec: number): Response {
  return new Response(
    JSON.stringify({
      error: "rate_limited",
      message: "Too many requests. Please slow down and retry.",
    }),
    {
      status: 429,
      headers: {
        ...CORS_HEADERS,
        "Content-Type": "application/json",
        "Retry-After": String(Math.max(1, Math.ceil(retryAfterSec))),
      },
    },
  );
}
