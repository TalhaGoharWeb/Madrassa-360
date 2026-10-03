// POST /functions/v1/manage-tenant
//
// Master-Admin only (platform_admins). Lifecycle control for a tenant:
//   { tenant_id, action: "suspend" | "reactivate" | "archive", reason? }
// Maps to tenants.status ∈ suspended / active / archived and writes an
// audit_logs entry. Archive NEVER deletes data — it only flips status.
//
// Success: 200 { tenant_id, status, changed }

import {
  badBodyResponse,
  isUuid,
  json,
  logServerError,
  newCorrelationId,
  preflight,
  rateLimit,
  readJsonBody,
  requirePlatformAdmin,
  tooManyRequests,
} from "../_shared/guard.ts";

const ACTIONS = {
  suspend: "suspended",
  reactivate: "active",
  archive: "archived",
} as const;

type Action = keyof typeof ACTIONS;

Deno.serve(async (req: Request): Promise<Response> => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed", message: "Use POST." }, 405);
  }

  const guard = await requirePlatformAdmin(req);
  if (!guard.ok) return guard.response;
  const { supabase, callerId } = guard;

  // RED-TEAM RT-03: suspend/reactivate/archive are tenant-killing
  // actions — throttle per caller as a backstop against a compromised
  // platform-admin session being scripted.
  const rl = await rateLimit(supabase, `manage-tenant:${callerId}`, 30, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfterSec);

  const parsed = await readJsonBody(req);
  if (!parsed.ok) {
    return badBodyResponse(parsed);
  }
  const { tenant_id, action, reason } = parsed.body;

  if (!isUuid(tenant_id)) {
    return json(
      { error: "invalid_input", message: "tenant_id: required UUID." },
      400,
    );
  }
  if (typeof action !== "string" || !(action in ACTIONS)) {
    return json(
      {
        error: "invalid_input",
        message: 'action: must be one of "suspend", "reactivate", "archive".',
      },
      400,
    );
  }
  const targetStatus: string = ACTIONS[action as Action];

  if (reason !== undefined && reason !== null && reason !== "") {
    if (typeof reason !== "string" || reason.length > 1000) {
      return json(
        {
          error: "invalid_input",
          message: "reason: must be a string ≤ 1000 chars.",
        },
        400,
      );
    }
  }
  const reasonStr: string | null =
    typeof reason === "string" && reason.trim() !== "" ? reason.trim() : null;

  // Load current status.
  const { data: tenant, error: loadErr } = await supabase
    .from("tenants")
    .select("id, status, name")
    .eq("id", tenant_id)
    .maybeSingle();
  if (loadErr) {
    const cid = newCorrelationId();
    logServerError("manage-tenant", cid, "load_tenant", loadErr);
    return json(
      { error: "load_failed", message: "Could not load the tenant.", ref: cid },
      500,
    );
  }
  if (!tenant) {
    return json(
      { error: "tenant_not_found", message: "No tenant with that id." },
      404,
    );
  }

  const prevStatus: string = tenant.status;
  if (prevStatus === targetStatus) {
    // Idempotent no-op — still report the current state.
    return json({ tenant_id: tenant.id, status: targetStatus, changed: false }, 200);
  }

  const { error: updErr } = await supabase
    .from("tenants")
    .update({ status: targetStatus })
    .eq("id", tenant.id);
  if (updErr) {
    const cid = newCorrelationId();
    logServerError("manage-tenant", cid, "update_status", updErr);
    return json(
      {
        error: "update_failed",
        message: "Could not update the tenant status.",
        ref: cid,
      },
      500,
    );
  }

  const { error: auditErr } = await supabase.from("audit_logs").insert({
    tenant_id: tenant.id,
    user_id: callerId,
    action: `tenant.${action}`,
    entity: "tenants",
    entity_id: tenant.id,
    old_data: { status: prevStatus },
    new_data: {
      status: targetStatus,
      reason: reasonStr,
      tenant_name: tenant.name,
    },
  });
  if (auditErr) {
    // Status change succeeded; the audit write failed. Report both so the
    // caller can re-audit — do not roll back the status change.
    // The driver detail stays server-side (SEC-H14).
    const cid = newCorrelationId();
    logServerError("manage-tenant", cid, "audit_write", auditErr);
    return json(
      {
        tenant_id: tenant.id,
        status: targetStatus,
        changed: true,
        warning: "audit_write_failed",
        ref: cid,
      },
      200,
    );
  }

  return json({ tenant_id: tenant.id, status: targetStatus, changed: true }, 200);
});
