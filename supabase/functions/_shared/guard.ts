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

/** Reads and parses a JSON body; returns { ok:false } on malformed JSON. */
export async function readJsonBody(
  req: Request,
): Promise<{ ok: true; body: Record<string, unknown> } | { ok: false }> {
  try {
    const body = await req.json();
    if (body === null || typeof body !== "object" || Array.isArray(body)) {
      return { ok: false };
    }
    return { ok: true, body: body as Record<string, unknown> };
  } catch {
    return { ok: false };
  }
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
