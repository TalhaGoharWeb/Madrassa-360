// POST /functions/v1/export-tenant
//
// Master-Admin only (platform_admins). Full tenant dataset export for
// offboarding / support / disaster recovery: reads every tenant-scoped
// table server-side (service role from env only) and writes ONE JSONL
// file to the `tenant-exports` bucket at
//   exports/{tenant_id}/{timestamp}.jsonl
//
// File format (single file):
//   line 1        manifest JSON: { format, tenant_id, exported_at,
//                   schema_version, tables: { name: rowCount }, sha256 }
//   lines 2..n    one JSON object per row: { table, row }
//
// The SHA-256 covers the row lines only (never the manifest itself), so
// the file is self-verifying: hash lines 2..n and compare with the
// manifest's sha256.
//
// SECURITY: the response NEVER contains row data — only the storage path
// and the manifest. All reads use the service-role client built from
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY env secrets (never from the
// request). Audit-logged like every other tenant lifecycle action.
//
// Request:  { tenant_id: "<uuid>" }
// Success:  200 { tenant_id, bucket, storage_path, manifest }

import {
  isUuid,
  json,
  preflight,
  readJsonBody,
  requirePlatformAdmin,
} from "../_shared/guard.ts";

// Tenant-scoped server tables, mirroring the local Drift schema
// (lib/data/local/app_database.dart). Every table here carries tenant_id.
const EXPORT_TABLES = [
  "students",
  "classes",
  "darjas",
  "darja_sections",
  "attendance_records",
  "staff",
  "invoices",
  "invoice_items",
  "payments",
  "accounts",
  "transactions",
  "income",
  "expenses",
  "refunds",
  "discounts",
  "scholarships",
  "exams",
  "results",
  "library_books",
  "book_issues",
  "announcements",
] as const;

const BUCKET = "tenant-exports";
const PAGE_SIZE = 1000;
const FORMAT = "m360-export/1";
const SCHEMA_VERSION = 1;

type Row = Record<string, unknown>;

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

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
  const { tenant_id } = parsed.body;
  if (!isUuid(tenant_id)) {
    return json(
      { error: "invalid_input", message: "tenant_id: required UUID." },
      400,
    );
  }

  // Confirm the tenant exists (and surface its name for the audit log).
  const { data: tenant, error: tenantErr } = await supabase
    .from("tenants")
    .select("id, name")
    .eq("id", tenant_id)
    .maybeSingle();
  if (tenantErr) {
    return json(
      { error: "load_failed", message: `Could not load tenant: ${tenantErr.message}` },
      500,
    );
  }
  if (!tenant) {
    return json({ error: "tenant_not_found", message: "No tenant with that id." }, 404);
  }

  // Pull every tenant-scoped table, paginated. Row lines are collected in
  // memory; for very large tenants this is the documented scaling limit
  // (see docs/BACKUP_RESTORE.md) — acceptable for a support/offboarding
  // tool, not a hot path.
  const rowLines: string[] = [];
  const counts: Record<string, number> = {};
  for (const table of EXPORT_TABLES) {
    let from = 0;
    let count = 0;
    for (;;) {
      const { data, error } = await supabase
        .from(table)
        .select("*")
        .eq("tenant_id", tenant_id)
        .order("id", { ascending: true })
        .range(from, from + PAGE_SIZE - 1);
      if (error) {
        return json(
          {
            error: "export_failed",
            message: `Could not read ${table}: ${error.message}`,
          },
          500,
        );
      }
      const rows = (data ?? []) as Row[];
      for (const row of rows) {
        rowLines.push(JSON.stringify({ table, row }));
      }
      count += rows.length;
      if (rows.length < PAGE_SIZE) break;
      from += PAGE_SIZE;
    }
    counts[table] = count;
  }

  const dataBytes = new TextEncoder().encode(rowLines.join("\n") + (rowLines.length ? "\n" : ""));
  const sha256 = toHex(
    await crypto.subtle.digest("SHA-256", dataBytes),
  );

  const exportedAt = new Date().toISOString();
  const manifest = {
    format: FORMAT,
    tenant_id,
    tenant_name: tenant.name ?? null,
    exported_at: exportedAt,
    schema_version: SCHEMA_VERSION,
    tables: counts,
    total_rows: rowLines.length,
    sha256,
  };

  const manifestLine = JSON.stringify(manifest) + "\n";
  const payload = new Blob([manifestLine, dataBytes], {
    type: "application/x-ndjson",
  });

  const stamp = exportedAt.replace(/[:.]/g, "-");
  const storagePath = `exports/${tenant_id}/${stamp}.jsonl`;

  const { error: uploadErr } = await supabase.storage
    .from(BUCKET)
    .upload(storagePath, payload, {
      contentType: "application/x-ndjson",
      upsert: true,
    });
  if (uploadErr) {
    return json(
      {
        error: "upload_failed",
        message: `Could not write export file: ${uploadErr.message}`,
      },
      500,
    );
  }

  const { error: auditErr } = await supabase.from("audit_logs").insert({
    tenant_id,
    user_id: callerId,
    action: "tenant.export",
    entity: "tenants",
    entity_id: tenant_id,
    new_data: {
      bucket: BUCKET,
      storage_path: storagePath,
      total_rows: rowLines.length,
      sha256,
      tenant_name: tenant.name ?? null,
    },
  });
  if (auditErr) {
    // Export succeeded; audit write failed. Report both — the file is in
    // storage, the caller just needs to know the audit trail is missing.
    return json(
      {
        tenant_id,
        bucket: BUCKET,
        storage_path: storagePath,
        manifest: { ...manifest, tables: counts },
        warning: "audit_write_failed",
        warning_detail: auditErr.message,
      },
      200,
    );
  }

  // NOTE: row data is deliberately NOT echoed back — storage path only.
  return json(
    {
      tenant_id,
      bucket: BUCKET,
      storage_path: storagePath,
      manifest: { ...manifest, tables: counts },
    },
    200,
  );
});
