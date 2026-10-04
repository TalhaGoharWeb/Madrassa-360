// POST /functions/v1/manage-demo-data
//
// One-click demo data install/remove for SaaS trial users.
//
// A tenant admin can install a compact, realistic Urdu-first demo dataset
// into their OWN tenant to explore every module, and remove it again with
// one click. Deletes are scoped to (tenant_id, is_demo = true) — real rows
// can never match.
//
// Authorization: the caller must be authenticated, an active member of the
// target tenant, AND hold the `settings.update` effective permission (or a
// legacy tenant_owner/tenant_admin rank). tenant_id is validated against
// membership — never trusted blindly.
//
// Body: { tenant_id, action: "status" | "install" | "remove" }
//
// Actions:
//   status  → 200 { installed: bool, counts: { table: n } }
//   install → 200 { installed: true, counts } (idempotent)
//   remove  → 200 { removed: true, demo_students_removed: n }
//
// Rate limits: install/remove 5 per hour per tenant; status 120 per hour.
// All DB work runs inside the SECURITY DEFINER demo_* RPCs (single
// transaction each). The RPCs are revoked from anon/authenticated — only
// this function's service-role client may call them.

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

type Action = "status" | "install" | "remove";

const SCHEMA: Record<string, FieldRule> = {
  tenant_id: { type: "uuid", required: true },
  action: { type: "string", required: true },
};

const ALLOWED_ACTIONS: Action[] = ["status", "install", "remove"];

Deno.serve(async (req: Request): Promise<Response> => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const correlationId = newCorrelationId();

  // ── Body (size-capped, schema-validated) ──
  const parsed = await readJsonBody(req, 8 * 1024);
  if (!parsed.ok) return badBodyResponse(parsed);
  const validated = validateBody(parsed.body, SCHEMA);
  if (!validated.ok) return invalidBodyResponse(validated.problems);
  const tenantId = parsed.body["tenant_id"] as string;
  const action = parsed.body["action"] as string;
  if (!ALLOWED_ACTIONS.includes(action as Action)) {
    return invalidBodyResponse(["action: must be one of status, install, remove"]);
  }
  const typedAction = action as Action;

  const supabase = serviceClient();

  // ── Auth: real user, never a service key ──
  const caller = await resolveJwtUser(req, supabase);
  if (!caller.ok) return caller.response;
  const userId = caller.userId;

  // ── Tenant membership (server-side, never client claims) ──
  const { data: membership, error: memberError } = await supabase
    .from("tenant_memberships")
    .select("id")
    .eq("tenant_id", tenantId)
    .eq("user_id", userId)
    .eq("is_active", true)
    .maybeSingle();
  if (memberError || !membership) {
    return json({ error: "forbidden", correlation_id: correlationId }, 403);
  }

  // ── Admin-level permission ──
  const allowed = await hasEffectivePermission(
    supabase,
    tenantId,
    userId,
    "settings.update",
  );
  if (!allowed) {
    return json({ error: "forbidden", correlation_id: correlationId }, 403);
  }

  // ── Rate limiting ──
  const heavy = typedAction !== "status";
  const rl = await rateLimit(
    supabase,
    `demo-data:${typedAction}:${tenantId}`,
    heavy ? 5 : 120,
    3600,
  );
  if (!rl.allowed) return tooManyRequests(rl.retryAfterSec);

  // ── Dispatch to the locked-down RPC ──
  try {
    if (typedAction === "status") {
      const { data, error } = await supabase.rpc("demo_status", {
        p_tenant_id: tenantId,
      });
      if (error) throw error;
      const counts = (data ?? {}) as Record<string, number>;
      const installed = Object.values(counts).some((n) => n > 0);
      return json({ installed, counts, correlation_id: correlationId });
    }

    if (typedAction === "install") {
      const { data, error } = await supabase.rpc("demo_install", {
        p_tenant_id: tenantId,
      });
      if (error) throw error;
      return json({ ...(data as object), correlation_id: correlationId });
    }

    // typedAction === "remove"
    const { data, error } = await supabase.rpc("demo_remove", {
      p_tenant_id: tenantId,
    });
    if (error) throw error;
    return json({ ...(data as object), correlation_id: correlationId });
  } catch (e) {
    logServerError("manage-demo-data", correlationId, "dispatch", e);
    // Generic client error — never leak SQL or internals.
    return json(
      { error: "server_error", correlation_id: correlationId },
      500,
    );
  }
});
