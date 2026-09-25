// POST /functions/v1/manage-tenant
//
// Master-Admin only (platform_admins). Lifecycle control for a tenant:
//   { tenant_id, action: "suspend" | "reactivate" | "archive", reason? }
// Maps to tenants.status ∈ suspended / active / archived and writes an
// audit_logs entry. Archive NEVER deletes data — it only flips status.
//
// Success: 200 { tenant_id, status, changed }

import {
  isUuid,
  json,
  preflight,
  readJsonBody,
  requirePlatformAdmin,
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

  const parsed = await readJsonBody(req);
  if (!parsed.ok) {
    return json(
      { error: "invalid_json", message: "Request body must be a JSON object." },
      400,
    );
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
    return json(
      { error: "load_failed", message: `Could not load tenant: ${loadErr.message}` },
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
    return json(
      {
        error: "update_failed",
        message: `Could not update tenant status: ${updErr.message}`,
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
    return json(
      {
        tenant_id: tenant.id,
        status: targetStatus,
        changed: true,
        warning: "audit_write_failed",
        warning_detail: auditErr.message,
      },
      200,
    );
  }

  return json({ tenant_id: tenant.id, status: targetStatus, changed: true }, 200);
});
