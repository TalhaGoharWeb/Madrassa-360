// POST /functions/v1/provision-tenant
//
// Master-Admin only (platform_admins). Creates a complete tenant in one call:
// tenants row → tenant_settings update → tenant_modules → tenant_subscriptions
// + licenses → auth user (tenant_owner) → tenant_membership → audit_logs.
//
// Body:
//   { name, name_urdu?, slug?, address?, city?, district?, province?, country?,
//     phone?, email?, website?, principal_name?, registration_number?,
//     language?, timezone?, currency?,
//     plan_id, modules?: string[] (catalog names),
//     admin: { name, email, password } }
//
// Success: 200 { tenant_id, tenant_code, slug, admin_user_id, admin_email }
// Failure AFTER the tenant row exists triggers best-effort compensating
// cleanup (reverse order) and returns 500 with step + cleanup info.
// The admin password is NEVER returned or logged.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";
import {
  isEmail,
  isNonEmptyString,
  isSlug,
  isUuid,
  json,
  newTenantCode,
  parseWebsite,
  preflight,
  readJsonBody,
  requirePlatformAdmin,
} from "../_shared/guard.ts";

/** Default module set — mirrors trg_tenants_enable_default_modules() in 003. */
const TRIGGER_DEFAULT_MODULES = [
  "students",
  "teachers",
  "attendance",
  "academics",
  "exams",
  "results",
  "fees",
  "parents",
  "notifications",
  "reports",
] as const;

const TRIAL_DAYS = 30;

interface ProvisionInput {
  name: string;
  name_urdu?: string;
  slug?: string;
  address?: string;
  city?: string;
  district?: string;
  province?: string;
  country?: string;
  phone?: string;
  email?: string;
  website?: string;
  principal_name?: string;
  registration_number?: string;
  language?: string;
  timezone?: string;
  currency?: string;
  plan_id: string;
  modules?: string[];
  admin: { name: string; email: string; password: string };
}

interface LicensePlan {
  id: string;
  name: string;
  description: string | null;
  max_students: number | null;
  max_users: number | null;
  max_teachers: number | null;
  enabled_modules: string[] | null;
  price_monthly: number | null;
  is_active: boolean;
}

/** Tracks everything created so cleanup can run in reverse on failure. */
interface Created {
  tenantId: string | null;
  authUserId: string | null;
  licenseId: string | null;
  subscriptionId: string | null;
  membershipId: string | null;
}

function cleanStr(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
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
  const input = validate(parsed.body);
  if ("error" in input) return json(input, 400);
  const b = input as ProvisionInput;

  const created: Created = {
    tenantId: null,
    authUserId: null,
    licenseId: null,
    subscriptionId: null,
    membershipId: null,
  };
  const cleanupErrors: Array<{ step: string; message: string }> = [];

  try {
    // ── 1. Load and validate the license plan ───────────────────────────
    const { data: plan, error: planErr } = await supabase
      .from("license_plans")
      .select(
        "id, name, description, max_students, max_users, max_teachers, enabled_modules, price_monthly, is_active",
      )
      .eq("id", b.plan_id)
      .eq("is_active", true)
      .maybeSingle<LicensePlan>();
    if (planErr) throw step("load_plan", planErr.message);
    if (!plan) {
      return json(
        {
          error: "unknown_plan",
          message: "plan_id does not match an active license plan.",
        },
        400,
      );
    }

    // ── 2. Validate requested modules against the live catalog ───────────
    const { data: catalog, error: catErr } = await supabase
      .from("modules_catalog")
      .select("module");
    if (catErr) throw step("load_catalog", catErr.message);
    const catalogSet = new Set((catalog ?? []).map((m) => m.module as string));

    const planModules: string[] = Array.isArray(plan.enabled_modules)
      ? plan.enabled_modules.filter((m) => catalogSet.has(m))
      : [];

    let enabledSet: Set<string>;
    if (b.modules === undefined) {
      // Default: the plan's module allowance; fall back to the 10 trigger
      // defaults (already enabled by the trigger) when the plan lists none.
      enabledSet = new Set(
        planModules.length > 0 ? planModules : [...TRIGGER_DEFAULT_MODULES],
      );
    } else {
      const unknown = b.modules.filter((m) => !catalogSet.has(m));
      if (unknown.length > 0) {
        return json(
          {
            error: "unknown_modules",
            message: `Not in modules_catalog: ${unknown.join(", ")}.`,
          },
          400,
        );
      }
      if (planModules.length > 0) {
        const outside = b.modules.filter((m) => !planModules.includes(m));
        if (outside.length > 0) {
          return json(
            {
              error: "module_not_in_plan",
              message:
                `Plan "${plan.name}" does not include: ${outside.join(", ")}.`,
            },
            400,
          );
        }
      }
      enabledSet = new Set(b.modules);
    }
    const enabledModules = [...enabledSet];

    // ── 3. Insert tenant (retry on tenant_code collision) ────────────────
    let tenant: { id: string; tenant_code: string; slug: string } | null = null;
    let attempts = 0;
    for (;;) {
      attempts++;
      const { data, error } = await supabase
        .from("tenants")
        .insert({
          tenant_code: newTenantCode(),
          name: b.name,
          name_urdu: b.name_urdu ?? null,
          // slug omitted when absent → BEFORE INSERT trigger fills it from
          // name and guarantees uniqueness (-2, -3, …).
          slug: b.slug ?? undefined,
          address: b.address ?? null,
          city: b.city ?? null,
          district: b.district ?? null,
          province: b.province ?? null,
          country: b.country ?? "Pakistan",
          phone: b.phone ?? null,
          email: b.email ?? null,
          website: b.website ?? null,
          principal_name: b.principal_name ?? null,
          registration_number: b.registration_number ?? null,
          status: "trial",
        })
        .select("id, tenant_code, slug")
        .single();
      if (!error) {
        tenant = data;
        break;
      }
      if (
        attempts < 3 && error.code === "23505" &&
        error.message.includes("tenant_code")
      ) {
        continue; // astronomically unlikely collision — regenerate and retry
      }
      if (error.code === "23505" && error.message.includes("slug")) {
        // Explicit slug was taken (trigger leaves explicit slugs as-is).
        await cleanup(supabase, created, cleanupErrors);
        return json(
          {
            error: "slug_taken",
            message: `Slug "${b.slug}" is already in use.`,
          },
          409,
        );
      }
      throw step("insert_tenant", error.message);
    }
    if (!tenant) throw step("insert_tenant", "Insert returned no row.");
    created.tenantId = tenant.id;

    // ── 4. Update the trigger-created tenant_settings row ────────────────
    const settingsPatch: Record<string, string> = {};
    if (b.language) settingsPatch.language = b.language;
    if (b.timezone) settingsPatch.timezone = b.timezone;
    if (b.currency) settingsPatch.currency = b.currency;
    if (Object.keys(settingsPatch).length > 0) {
      const { error: setErr } = await supabase
        .from("tenant_settings")
        .update(settingsPatch)
        .eq("tenant_id", tenant.id);
      if (setErr) throw step("update_settings", setErr.message);
    }

    // ── 5. Set the full module enablement (all 17 catalog rows) ──────────
    const moduleRows = [...catalogSet].map((module) => ({
      tenant_id: tenant.id,
      module,
      enabled: enabledSet.has(module),
    }));
    const { error: modErr } = await supabase
      .from("tenant_modules")
      .upsert(moduleRows, { onConflict: "tenant_id,module" });
    if (modErr) throw step("set_modules", modErr.message);

    // ── 6. License + subscription rows (trial: 30 days) ──────────────────
    const now = new Date();
    const expiresAt = new Date(now.getTime() + TRIAL_DAYS * 24 * 60 * 60 * 1000)
      .toISOString();

    const { data: license, error: licErr } = await supabase
      .from("licenses")
      .insert({
        tenant_id: tenant.id,
        plan_id: plan.id,
        issued_at: now.toISOString(),
        expires_at: expiresAt,
        status: "trial",
        max_users: plan.max_users,
        max_students: plan.max_students,
        enabled_modules: enabledModules,
      })
      .select("id")
      .single();
    if (licErr) throw step("insert_license", licErr.message);
    created.licenseId = license.id;

    const { data: sub, error: subErr } = await supabase
      .from("tenant_subscriptions")
      .insert({
        tenant_id: tenant.id,
        plan_id: plan.id,
        status: "trial",
        started_at: now.toISOString(),
        expires_at: expiresAt,
      })
      .select("id")
      .single();
    if (subErr) throw step("insert_subscription", subErr.message);
    created.subscriptionId = sub.id;

    // ── 7. Create the tenant-owner auth user ─────────────────────────────
    const { data: authData, error: authErr } =
      await supabase.auth.admin.createUser({
        email: b.admin.email,
        password: b.admin.password,
        email_confirm: true,
        user_metadata: { name: b.admin.name, provisioned_by: callerId },
      });
    if (authErr || !authData?.user) {
      const msg = authErr?.message ?? "createUser returned no user";
      if (/already\s+(been\s+)?registered|already\s+exists/i.test(msg)) {
        await cleanup(supabase, created, cleanupErrors);
        return json(
          {
            error: "admin_email_taken",
            message: `Admin email "${b.admin.email}" is already registered.`,
          },
          409,
        );
      }
      throw step("create_admin_user", msg);
    }
    created.authUserId = authData.user.id;

    // ── 8. Owner membership ──────────────────────────────────────────────
    const { data: membership, error: memErr } = await supabase
      .from("tenant_memberships")
      .insert({
        tenant_id: tenant.id,
        user_id: authData.user.id,
        role: "tenant_owner",
        is_active: true,
      })
      .select("id")
      .single();
    if (memErr) throw step("insert_membership", memErr.message);
    created.membershipId = membership.id;

    // ── 9. Audit trail ───────────────────────────────────────────────────
    const { error: auditErr } = await supabase.from("audit_logs").insert({
      tenant_id: tenant.id,
      user_id: callerId,
      action: "tenant.provisioned",
      entity: "tenants",
      entity_id: tenant.id,
      new_data: {
        tenant_code: tenant.tenant_code,
        name: b.name,
        slug: tenant.slug,
        plan_id: plan.id,
        plan_name: plan.name,
        admin_email: b.admin.email,
        admin_user_id: authData.user.id,
        enabled_modules: enabledModules,
        license_id: license.id,
        subscription_id: sub.id,
      },
    });
    if (auditErr) throw step("insert_audit", auditErr.message);

    return json({
      tenant_id: tenant.id,
      tenant_code: tenant.tenant_code,
      slug: tenant.slug,
      admin_user_id: authData.user.id,
      admin_email: b.admin.email,
    }, 200);
  } catch (e) {
    // Any failure after the tenant insert → best-effort reverse cleanup.
    await cleanup(supabase, created, cleanupErrors);
    const s = e as { step?: string; message?: string };
    return json(
      {
        error: "provision_failed",
        step: s.step ?? "unknown",
        message: s.message ?? String(e),
        cleanup_errors: cleanupErrors,
      },
      500,
    );
  }
});

// ── validation ────────────────────────────────────────────────────────────

function validate(
  body: Record<string, unknown>,
): ProvisionInput | { error: string; message: string; details?: string[] } {
  const problems: string[] = [];

  const name = cleanStr(body.name);
  if (!name || name.length < 2 || name.length > 120) {
    problems.push("name: required, 2–120 chars");
  }

  const slug = body.slug === undefined || body.slug === null ||
      (typeof body.slug === "string" && body.slug.trim() === "")
    ? undefined
    : String(body.slug).trim().toLowerCase();
  if (slug !== undefined && !isSlug(slug)) {
    problems.push("slug: must match ^[a-z0-9]+(-[a-z0-9]+)*$, ≤60 chars");
  }

  if (!isUuid(body.plan_id)) problems.push("plan_id: required UUID");

  const admin = body.admin;
  let adminOut: ProvisionInput["admin"] | null = null;
  if (admin === null || typeof admin !== "object" || Array.isArray(admin)) {
    problems.push("admin: required object { name, email, password }");
  } else {
    const a = admin as Record<string, unknown>;
    const an = cleanStr(a.name);
    const ae = typeof a.email === "string" ? a.email.trim() : "";
    const ap = typeof a.password === "string" ? a.password : "";
    if (!an || an.length < 2 || an.length > 100) {
      problems.push("admin.name: required, 2–100 chars");
    }
    if (!isEmail(ae)) problems.push("admin.email: must be a valid email");
    if (ap.length < 6) problems.push("admin.password: minimum 6 characters");
    if (problems.length === 0) adminOut = { name: an!, email: ae, password: ap };
  }

  let modules: string[] | undefined;
  if (body.modules !== undefined) {
    if (
      !Array.isArray(body.modules) || body.modules.length === 0 ||
      !body.modules.every((m) => typeof m === "string" && m.trim() !== "")
    ) {
      problems.push("modules: must be a non-empty array of module names");
    } else {
      modules = (body.modules as string[]).map((m) => m.trim().toLowerCase());
    }
  }

  const email = typeof body.email === "string" && body.email.trim() !== ""
    ? body.email.trim()
    : undefined;
  if (email !== undefined && !isEmail(email)) {
    problems.push("email: must be a valid email");
  }

  const website = parseWebsite(body.website);
  if (website.invalid) problems.push("website: must be a valid http(s) URL");

  const strOpt = (k: string, max: number) => {
    const v = body[k];
    if (v === undefined || v === null || v === "") return undefined;
    if (!isNonEmptyString(v, max)) {
      problems.push(`${k}: must be a string ≤ ${max} chars`);
      return undefined;
    }
    return v.trim();
  };

  if (problems.length > 0) {
    return {
      error: "invalid_input",
      message: "Request validation failed.",
      details: problems,
    };
  }

  const out: ProvisionInput = {
    name: name!,
    plan_id: body.plan_id as string,
    admin: adminOut!,
  };
  const set = (k: keyof ProvisionInput, v: string | undefined | null) => {
    if (v !== undefined && v !== null) {
      (out as unknown as Record<string, unknown>)[k] = v;
    }
  };
  set("name_urdu", cleanStr(body.name_urdu));
  if (slug !== undefined) set("slug", slug);
  set("address", strOpt("address", 500));
  set("city", strOpt("city", 120));
  set("district", strOpt("district", 120));
  set("province", strOpt("province", 120));
  set("country", strOpt("country", 120));
  set("phone", strOpt("phone", 60));
  if (email !== undefined) set("email", email);
  if (website.present && !website.invalid) set("website", website.url!);
  set("principal_name", strOpt("principal_name", 200));
  set("registration_number", strOpt("registration_number", 200));
  set("language", strOpt("language", 10));
  set("timezone", strOpt("timezone", 60));
  set("currency", strOpt("currency", 10));
  if (modules !== undefined) out.modules = modules;
  return out;
}

function step(step: string, message: string): Error & { step: string } {
  const e = new Error(message) as Error & { step: string };
  e.step = step;
  return e;
}

/**
 * Best-effort compensating cleanup in reverse creation order.
 * Errors are collected, never thrown.
 */
async function cleanup(
  supabase: SupabaseClient,
  created: Created,
  cleanupErrors: Array<{ step: string; message: string }>,
): Promise<void> {
  const attempt = async (s: string, fn: () => Promise<unknown>) => {
    try {
      await fn();
    } catch (e) {
      cleanupErrors.push({ step: s, message: String(e) });
    }
  };

  if (created.authUserId) {
    await attempt("delete_admin_user", async () => {
      const { error } = await supabase.auth.admin.deleteUser(
        created.authUserId!,
      );
      if (error) throw new Error(error.message);
    });
  }
  if (created.membershipId) {
    await attempt("delete_membership", async () => {
      const { error } = await supabase.from("tenant_memberships").delete()
        .eq("id", created.membershipId!);
      if (error) throw new Error(error.message);
    });
  }
  if (created.licenseId) {
    await attempt("delete_license", async () => {
      const { error } = await supabase.from("licenses").delete()
        .eq("id", created.licenseId!);
      if (error) throw new Error(error.message);
    });
  }
  if (created.subscriptionId) {
    await attempt("delete_subscription", async () => {
      const { error } = await supabase.from("tenant_subscriptions").delete()
        .eq("id", created.subscriptionId!);
      if (error) throw new Error(error.message);
    });
  }
  if (created.tenantId) {
    await attempt("delete_modules", async () => {
      const { error } = await supabase.from("tenant_modules").delete()
        .eq("tenant_id", created.tenantId!);
      if (error) throw new Error(error.message);
    });
    await attempt("delete_settings", async () => {
      const { error } = await supabase.from("tenant_settings").delete()
        .eq("tenant_id", created.tenantId!);
      if (error) throw new Error(error.message);
    });
    await attempt("delete_audit", async () => {
      const { error } = await supabase.from("audit_logs").delete()
        .eq("tenant_id", created.tenantId!);
      if (error) throw new Error(error.message);
    });
    await attempt("delete_tenant", async () => {
      const { error } = await supabase.from("tenants").delete()
        .eq("id", created.tenantId!);
      if (error) throw new Error(error.message);
    });
  }
}
