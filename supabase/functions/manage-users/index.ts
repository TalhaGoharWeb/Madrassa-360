// POST /functions/v1/manage-users
//
// Privileged user management for Madrassa 360. The service-role key lives
// ONLY here (server-side env) — the Flutter client must never hold it.
//
// Two caller classes:
//   1. platform_admins — unrestricted, except only a platform_owner (not
//      platform_support) may grant/revoke platform roles.
//   2. tenant_owner / tenant_admin (active membership) — may manage users
//      ONLY inside the tenants they administer, may assign roles at or
//      below their own rank, may never touch platform_admins rows, and may
//      never leave a tenant without at least one active tenant_owner.
//
// Actions (JSON body, POST):
//   create_user       {email, password, user_metadata?, app_metadata?, tenant_id?, role?}
//   update_user       {user_id, email?, password?, user_metadata?, app_metadata?}
//   set_active        {user_id, active}
//   delete_user       {user_id}          (tenant owner/admin or platform admin only)
//   assign_membership {user_id, tenant_id, role}
//   remove_membership {user_id, tenant_id}
//   list_users        {tenant_id?, search?, limit?, offset?}
//   safety_check      {tenant_id, user_id}  (last-owner / last-assign-holder pre-check)
//   set_platform_role {user_id, role: 'platform_owner'|'platform_support'|null}
//
// Caller rights (Phase 8a): besides the legacy tenant_owner/tenant_admin
// ranks, callers holding the Phase-6 template roles are authorized through
// their EFFECTIVE permissions (user_effective_permission RPC):
//   users.view       -> list_users, safety_check, create_user (bare auth user)
//   roles.assign     -> create_user (with membership), assign_membership, remove_membership
//   users.deactivate -> set_active
// delete_user stays restricted to legacy tenant owner/admin + platform admin.
//
// Every mutating action is written to public.audit_logs. Passwords are never
// logged and never returned.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";
import {
  badBodyResponse,
  hasEffectivePermission,
  invalidBodyResponse,
  isEmail,
  isUuid,
  json,
  logServerError,
  newCorrelationId,
  preflight,
  readJsonBody,
  serviceClient,
  tooManyRequests,
  rateLimit,
  validateBody,
  type FieldRule,
} from "../_shared/guard.ts";

/** Tenant roles this function may assign, with rank (higher = more power). */
const TENANT_ROLE_RANK: Record<string, number> = {
  tenant_owner: 100,
  tenant_admin: 90,
  principal: 80,
  accountant: 70,
  teacher: 50,
  librarian: 50,
  hostel_manager: 50,
  staff: 50,
  parent: 10,
  student: 10,
};

/**
 * Authority ceiling for permission-based (non-legacy) callers (SEC-H2).
 * Template-role holders authorized via permission codes get an effective
 * rank ABOVE every staff-level legacy role (≤50) but BELOW every
 * managerial role (accountant 70, principal 80, tenant_admin 90,
 * tenant_owner 100). They can manage teachers/staff/students/parents —
 * never managers, never owners.
 */
const PERMISSION_CALLER_CEILING = 60;

/**
 * Permission codes that mark a role as managerial. Holders of any of these
 * may only be managed by tenant_owner / tenant_admin / platform admins —
 * never by junior permission-based callers (SEC-H2 peer-reset attack).
 */
const MANAGERIAL_CODES = new Set([
  "users.create",
  "users.update",
  "users.deactivate",
  "roles.assign",
  "settings.update",
  "finance.approve",
]);

const PLATFORM_ROLES = ["platform_owner", "platform_support"] as const;

interface CallerScope {
  callerId: string;
  isPlatformAdmin: boolean;
  isPlatformOwner: boolean;
  /** tenant_id -> caller's rank in that tenant (tenant_owner/tenant_admin only) */
  tenantRanks: Map<string, number>;
  /** tenants where the caller may manage users (owner/admin, or users.view) */
  userTenants: Set<string>;
  /**
   * tenants where the caller may WRITE user records — legacy owner/admin,
   * or holders of the `users.update` effective permission (SEC-C4: the
   * read-only `users.view` set must NEVER grant credential changes).
   */
  userWriteTenants: Set<string>;
  /** tenants where the caller may assign roles (owner/admin, or roles.assign) */
  roleTenants: Set<string>;
  /** tenants where the caller may (de)activate users (owner/admin, or users.deactivate) */
  deactivateTenants: Set<string>;
  /**
   * tenant_id -> authority ceiling for permission-based callers
   * (PERMISSION_CALLER_CEILING where they hold a management code).
   * Legacy rank-based callers are governed by tenantRanks instead.
   */
  permissionCeilings: Map<string, number>;
}

/** Resolve the caller: platform_admins row, else active memberships.
 * Legacy tenant_owner/tenant_admin callers get rank-based rights;
 * Phase-6 template-role callers get rights from their effective
 * permissions (users.view / roles.assign / users.deactivate). */
async function resolveCaller(
  supabase: SupabaseClient,
  req: Request,
): Promise<CallerScope | Response> {
  const authz = req.headers.get("Authorization");
  if (!authz || !authz.toLowerCase().startsWith("bearer ")) {
    return json({ error: "unauthorized", message: "Missing Authorization: Bearer <jwt>." }, 401);
  }
  const jwt = authz.slice(7).trim();
  const { data: userData, error: userErr } = await supabase.auth.getUser(jwt);
  const caller = userData?.user;
  if (userErr || !caller) {
    return json({ error: "unauthorized", message: "Invalid or expired token." }, 401);
  }

  const { data: adminRow } = await supabase
    .from("platform_admins")
    .select("role")
    .eq("user_id", caller.id)
    .maybeSingle();

  const tenantRanks = new Map<string, number>();
  const userTenants = new Set<string>();
  const userWriteTenants = new Set<string>();
  const roleTenants = new Set<string>();
  const deactivateTenants = new Set<string>();
  const permissionCeilings = new Map<string, number>();

  if (!adminRow) {
    const { data: memberships, error: memErr } = await supabase
      .from("tenant_memberships")
      .select("tenant_id, role")
      .eq("user_id", caller.id)
      .eq("is_active", true);
    if (memErr) {
      return json({ error: "auth_check_failed", message: "Could not verify caller memberships." }, 500);
    }
    for (const m of memberships ?? []) {
      const role = m.role as string;
      const tenantId = m.tenant_id as string;
      if (role === "tenant_owner" || role === "tenant_admin") {
        tenantRanks.set(tenantId, TENANT_ROLE_RANK[role] ?? 0);
        userTenants.add(tenantId);
        userWriteTenants.add(tenantId);
        roleTenants.add(tenantId);
        deactivateTenants.add(tenantId);
      } else {
        // Phase-6 template roles: rights from effective permissions.
        // NOTE (SEC-C4): `users.view` grants READ ONLY. Credential/profile
        // writes need the separate `users.update` code, recorded in
        // userWriteTenants — never in userTenants.
        const [canView, canUpdate, canAssign, canDeactivate] = await Promise.all([
          hasEffectivePermission(supabase, tenantId, caller.id, "users.view"),
          hasEffectivePermission(supabase, tenantId, caller.id, "users.update"),
          hasEffectivePermission(supabase, tenantId, caller.id, "roles.assign"),
          hasEffectivePermission(supabase, tenantId, caller.id, "users.deactivate"),
        ]);
        if (canView) userTenants.add(tenantId);
        if (canUpdate) userWriteTenants.add(tenantId);
        if (canAssign) roleTenants.add(tenantId);
        if (canDeactivate) deactivateTenants.add(tenantId);
        if (canUpdate || canAssign || canDeactivate) {
          // Permission-based management authority (SEC-H2): capped well
          // below every managerial rank (see PERMISSION_CALLER_CEILING).
          permissionCeilings.set(tenantId, PERMISSION_CALLER_CEILING);
        }
      }
    }
    if (
      tenantRanks.size === 0 &&
      userTenants.size === 0 &&
      userWriteTenants.size === 0 &&
      roleTenants.size === 0 &&
      deactivateTenants.size === 0
    ) {
      return json(
        { error: "forbidden", message: "Caller is not a platform admin or tenant manager." },
        403,
      );
    }
  }

  return {
    callerId: caller.id,
    isPlatformAdmin: !!adminRow,
    isPlatformOwner: adminRow?.role === "platform_owner",
    tenantRanks,
    userTenants,
    userWriteTenants,
    roleTenants,
    deactivateTenants,
    permissionCeilings,
  };
}

/** Right check for one tenant: platform admins pass; otherwise the
 * per-right tenant set built by resolveCaller. */
function callerCan(
  scope: CallerScope,
  tenantId: string,
  right: "users" | "users_write" | "roles" | "deactivate",
): boolean {
  if (scope.isPlatformAdmin) return true;
  if (right === "users") return scope.userTenants.has(tenantId);
  if (right === "users_write") return scope.userWriteTenants.has(tenantId);
  if (right === "roles") return scope.roleTenants.has(tenantId);
  return scope.deactivateTenants.has(tenantId);
}

/** Target user's tenant footprint: tenant_id -> role key (active memberships only). */
async function targetFootprint(
  supabase: SupabaseClient,
  userId: string,
): Promise<Map<string, string>> {
  const { data } = await supabase
    .from("tenant_memberships")
    .select("tenant_id, role")
    .eq("user_id", userId)
    .eq("is_active", true);
  const map = new Map<string, string>();
  for (const m of data ?? []) map.set(m.tenant_id as string, m.role as string);
  return map;
}

async function isPlatformAdminUser(supabase: SupabaseClient, userId: string): Promise<boolean> {
  const { data } = await supabase
    .from("platform_admins")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle();
  return !!data;
}

/**
 * Does [userId] hold any managerial permission code in [tenantId]?
 * Used to classify template-role targets (whose keys are not in
 * TENANT_ROLE_RANK): a "junior admin" must never manage someone holding
 * user/role management codes, even if the role key is unfamiliar.
 * Fail-closed: any check error counts as managerial.
 */
async function targetIsManagerial(
  supabase: SupabaseClient,
  tenantId: string,
  userId: string,
): Promise<boolean> {
  for (const code of MANAGERIAL_CODES) {
    try {
      if (await hasEffectivePermission(supabase, tenantId, userId, code)) {
        return true;
      }
    } catch {
      return true;
    }
  }
  return false;
}

/**
 * Can this caller mutate the target user with the given [right]?
 * Platform admins: yes (except platform-role changes are gated separately).
 * Tenant callers: the target must not be a platform admin, must live
 * entirely inside the caller's scoped tenants for that right, and must
 * sit BELOW the caller's authority ceiling:
 * - legacy rank-based callers: unchanged behavior — target must not hold a
 *   role strictly above the caller's own rank.
 * - permission-based (Phase-6) callers: strict ceiling (SEC-H2) — the
 *   target's rank must be BELOW PERMISSION_CALLER_CEILING, and template-
 *   role targets holding any managerial code are off-limits entirely.
 *   tenant_owner (and every managerial role) is unreachable.
 */
async function canMutateUser(
  supabase: SupabaseClient,
  scope: CallerScope,
  targetUserId: string,
  right: "users" | "users_write" | "roles" | "deactivate",
): Promise<{ ok: true } | { ok: false; message: string }> {
  if (scope.isPlatformAdmin) return { ok: true };
  if (targetUserId === scope.callerId) {
    return { ok: false, message: "You cannot change your own privileged record through this API." };
  }
  if (await isPlatformAdminUser(supabase, targetUserId)) {
    return { ok: false, message: "Target is a platform admin and cannot be managed by a tenant admin." };
  }
  const footprint = await targetFootprint(supabase, targetUserId);
  if (footprint.size === 0) {
    return { ok: false, message: "Target user has no tenant membership in your scope." };
  }
  for (const [tenantId, roleKey] of footprint) {
    if (!callerCan(scope, tenantId, right)) {
      return { ok: false, message: "Target belongs to a tenant outside your administration." };
    }
    const legacyRank = scope.tenantRanks.get(tenantId) ?? 0;
    if (legacyRank > 0) {
      // Legacy behavior unchanged.
      const targetRank = TENANT_ROLE_RANK[roleKey] ?? 0;
      if (targetRank > legacyRank) {
        return { ok: false, message: "Target holds a higher role than you in a shared tenant." };
      }
    } else {
      // Permission-based caller: strict authority ceiling (SEC-H2).
      const ceiling = scope.permissionCeilings.get(tenantId) ?? 0;
      const targetRank = TENANT_ROLE_RANK[roleKey];
      if (targetRank !== undefined) {
        if (targetRank >= ceiling) {
          return { ok: false, message: "Target holds a role at or above your authority ceiling." };
        }
      } else if (await targetIsManagerial(supabase, tenantId, targetUserId)) {
        return { ok: false, message: "Target holds a managerial role and cannot be managed by a junior administrator." };
      }
    }
  }
  return { ok: true };
}

/** Is [role] an active tenant role key for [tenantId]? (nicer 400 than the
 * DB trigger's exception when the client sends a bad key.) */
async function isActiveTenantRole(
  supabase: SupabaseClient,
  tenantId: string,
  role: string,
): Promise<boolean> {
  const { data } = await supabase
    .from("tenant_roles")
    .select("key")
    .eq("tenant_id", tenantId)
    .eq("key", role)
    .eq("is_active", true)
    .maybeSingle();
  return !!data;
}

/**
 * Does the tenant role [roleKey] grant any managerial permission code?
 * Used when a permission-based caller assigns a template role: they may
 * only hand out roles whose power stays below their own ceiling — never a
 * role that would let the assignee manage managers (SEC-H2).
 * Fail-closed: any check error counts as managerial.
 */
async function roleIsManagerial(
  supabase: SupabaseClient,
  tenantId: string,
  roleKey: string,
): Promise<boolean> {
  try {
    const { data: roleRow, error: roleErr } = await supabase
      .from("tenant_roles")
      .select("id")
      .eq("tenant_id", tenantId)
      .eq("key", roleKey)
      .eq("is_active", true)
      .maybeSingle();
    if (roleErr || !roleRow) return true;
    const { data: permRows, error: permErr } = await supabase
      .from("tenant_role_permissions")
      .select("permission_id")
      .eq("tenant_role_id", (roleRow as { id: string }).id);
    if (permErr) return true;
    const permIds = (permRows ?? []).map(
      (r) => (r as { permission_id: string }).permission_id,
    );
    if (permIds.length === 0) return false;
    const { data: codes, error: codeErr } = await supabase
      .from("permissions")
      .select("code")
      .in("id", permIds);
    if (codeErr) return true;
    return (codes ?? []).some((c) =>
      MANAGERIAL_CODES.has((c as { code: string }).code)
    );
  } catch {
    return true;
  }
}

/**
 * Rank gate for assigning [role] in [tenantId].
 * - Legacy callers: unchanged behavior — cannot assign strictly above
 *   their own rank.
 * - Permission-based callers (SEC-H2): strict ceiling — may only assign
 *   legacy roles BELOW the ceiling (tenant_admin at 90 and every other
 *   managerial role is unreachable without being tenant_owner) and
 *   template roles that grant no managerial codes.
 * Returns an error message, or null when allowed.
 */
async function assignRoleGate(
  supabase: SupabaseClient,
  scope: CallerScope,
  tenantId: string,
  role: string,
): Promise<string | null> {
  const legacyRank = scope.tenantRanks.get(tenantId) ?? 0;
  if (legacyRank > 0) {
    const targetRank = TENANT_ROLE_RANK[role] ?? 0;
    if (targetRank > legacyRank) {
      return "You cannot assign a role above your own.";
    }
    return null;
  }
  const ceiling = scope.permissionCeilings.get(tenantId) ?? 0;
  const targetRank = TENANT_ROLE_RANK[role];
  if (targetRank !== undefined) {
    if (targetRank >= ceiling) {
      return "You cannot assign a role at or above your authority ceiling. Managerial roles require a tenant owner or platform admin.";
    }
    return null;
  }
  if (await roleIsManagerial(supabase, tenantId, role)) {
    return "You cannot assign a managerial role. Managerial roles require a tenant owner or platform admin.";
  }
  return null;
}

/** Refuse to leave a tenant with zero active owners. */
async function ownerCount(
  supabase: SupabaseClient,
  tenantId: string,
  excludeUserId?: string,
): Promise<number> {
  let q = supabase
    .from("tenant_memberships")
    .select("user_id", { count: "exact", head: true })
    .eq("tenant_id", tenantId)
    .eq("role", "tenant_owner")
    .eq("is_active", true);
  if (excludeUserId) q = q.neq("user_id", excludeUserId);
  const { count } = await q;
  return count ?? 0;
}

async function audit(
  supabase: SupabaseClient,
  scope: CallerScope,
  tenantId: string | null,
  action: string,
  entity: string,
  entityId: string,
  newData: Record<string, unknown>,
): Promise<void> {
  // Best-effort: audit must never break the user operation.
  try {
    await supabase.from("audit_logs").insert({
      tenant_id: tenantId,
      user_id: scope.callerId,
      action: `manage-users.${action}`,
      entity,
      entity_id: entityId,
      new_data: newData,
    });
  } catch {
    /* ignored */
  }
}

function cleanStr(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
}

function asRecord(v: unknown): Record<string, unknown> | null {
  return v !== null && typeof v === "object" && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : null;
}

/**
 * Strips caller-controlled role claims from auth metadata (SEC-H15).
 * Roles are server-derived via tenant_memberships / platform_admins —
 * never from metadata the caller supplies. Non-platform callers get an
 * allow-list of benign profile keys; `role`/`roles` are always dropped.
 * Platform admins keep their input unchanged (trusted tier).
 */
const SAFE_METADATA_KEYS = new Set(["name", "full_name", "avatar_url", "phone"]);

function sanitizeMetadata(
  input: Record<string, unknown> | null,
  isPlatformAdmin: boolean,
): Record<string, unknown> {
  const src = input ?? {};
  if (isPlatformAdmin) return { ...src };
  const out: Record<string, unknown> = {};
  for (const k of SAFE_METADATA_KEYS) {
    if (src[k] !== undefined) out[k] = src[k];
  }
  return out;
}

// ── action handlers ──────────────────────────────────────────────────────

async function handleCreateUser(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  const email = cleanStr(b.email);
  const password = typeof b.password === "string" ? b.password : null;
  if (!email || !isEmail(email)) {
    return json({ error: "invalid_email", message: "A valid email is required." }, 400);
  }
  if (!password || password.length < 6) {
    return json({ error: "weak_password", message: "Password must be at least 6 characters." }, 400);
  }
  const userMetadata = sanitizeMetadata(asRecord(b.user_metadata), scope.isPlatformAdmin);
  const appMetadata = sanitizeMetadata(asRecord(b.app_metadata), scope.isPlatformAdmin);

  const tenantId = cleanStr(b.tenant_id);
  const role = cleanStr(b.role);
  if ((tenantId && !role) || (role && !tenantId)) {
    return json({ error: "invalid_membership", message: "tenant_id and role must be provided together." }, 400);
  }
  if (tenantId && !isUuid(tenantId)) {
    return json({ error: "invalid_tenant", message: "tenant_id must be a UUID." }, 400);
  }
  if (tenantId && role) {
    // The key must be an active role of THIS tenant (legacy keys and
    // Phase-6 template keys both live in tenant_roles).
    if (!(await isActiveTenantRole(supabase, tenantId, role))) {
      return json({ error: "invalid_role", message: `Unknown or inactive role for this tenant: ${role}.` }, 400);
    }
  }
  if (!scope.isPlatformAdmin) {
    if (tenantId && role) {
      if (!callerCan(scope, tenantId, "roles")) {
        return json({ error: "forbidden", message: "You do not administer this tenant." }, 403);
      }
      const gateMsg = await assignRoleGate(supabase, scope, tenantId, role);
      if (gateMsg) {
        return json({ error: "forbidden", message: gateMsg }, 403);
      }
    } else if (
      scope.userTenants.size === 0 &&
      scope.userWriteTenants.size === 0 &&
      scope.tenantRanks.size === 0
    ) {
      // Bare auth-user creation (no membership): needs user-management rights.
      return json({ error: "forbidden", message: "You cannot create users." }, 403);
    }
  }

  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: userMetadata,
    app_metadata: appMetadata,
  });
  if (error || !data?.user) {
    const cid = newCorrelationId();
    logServerError("manage-users", cid, "create_user", error);
    // 409 kept for client UX, but the driver message never leaves the
    // server (SEC-H14). The existence oracle itself is tracked as SEC-M10.
    const alreadyExists = /already/i.test(error?.message ?? "");
    return json(
      {
        error: "create_failed",
        message: alreadyExists
          ? "An account with this email already exists."
          : "Could not create the user account.",
        ref: cid,
      },
      alreadyExists ? 409 : 500,
    );
  }
  const newUserId = data.user.id;

  // Optional membership — reverse the auth creation if this fails.
  if (tenantId && role) {
    const { error: memErr } = await supabase.from("tenant_memberships").insert({
      tenant_id: tenantId,
      user_id: newUserId,
      role,
      is_active: true,
    });
    if (memErr) {
      await supabase.auth.admin.deleteUser(newUserId).catch(() => {});
      const cid = newCorrelationId();
      logServerError("manage-users", cid, "create_user/membership", memErr);
      return json(
        {
          error: "membership_failed",
          message: "Account created but tenant assignment failed; the account was removed.",
          ref: cid,
        },
        500,
      );
    }
  }

  await audit(supabase, scope, tenantId, "create_user", "auth_user", newUserId, {
    email,
    role: role ?? null,
    // password deliberately omitted
  });
  // The client reads id (or user_id) — never the password.
  return json({ id: newUserId, user_id: newUserId, email });
}

async function handleUpdateUser(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  const userId = cleanStr(b.user_id);
  if (!userId || !isUuid(userId)) {
    return json({ error: "invalid_user", message: "user_id must be a UUID." }, 400);
  }
  // SEC-C4: credential/profile writes need the WRITE right (`users.update`
  // or legacy owner/admin) — never the `users.view` read set.
  const gate = await canMutateUser(supabase, scope, userId, "users_write");
  if (!gate.ok) return json({ error: "forbidden", message: gate.message }, 403);

  const attrs: Record<string, unknown> = {};
  const email = cleanStr(b.email);
  if (email) {
    if (!isEmail(email)) return json({ error: "invalid_email", message: "Invalid email." }, 400);
    attrs.email = email;
  }
  if (typeof b.password === "string" && b.password !== "") {
    if (b.password.length < 6) {
      return json({ error: "weak_password", message: "Password must be at least 6 characters." }, 400);
    }
    attrs.password = b.password;
  }
  // SEC-H15: role claims in metadata are caller-controlled — strip them.
  // Skip fields that sanitize to empty so we never wipe stored metadata.
  const userMetadata = sanitizeMetadata(asRecord(b.user_metadata), scope.isPlatformAdmin);
  if (Object.keys(userMetadata).length > 0) attrs.user_metadata = userMetadata;
  const appMetadata = sanitizeMetadata(asRecord(b.app_metadata), scope.isPlatformAdmin);
  if (Object.keys(appMetadata).length > 0) attrs.app_metadata = appMetadata;
  if (Object.keys(attrs).length === 0) {
    return json({ error: "nothing_to_update", message: "No updatable fields provided." }, 400);
  }

  const { error } = await supabase.auth.admin.updateUserById(userId, attrs);
  if (error) {
    const cid = newCorrelationId();
    logServerError("manage-users", cid, "update_user", error);
    return json(
      { error: "update_failed", message: "Could not update the user account.", ref: cid },
      500,
    );
  }

  const logged: Record<string, unknown> = {};
  if (email) logged.email = email;
  if (Object.keys(userMetadata).length > 0) logged.user_metadata = userMetadata;
  if (Object.keys(appMetadata).length > 0) logged.app_metadata = appMetadata;
  await audit(supabase, scope, null, "update_user", "auth_user", userId, logged);
  return json({ ok: true, user_id: userId });
}

async function handleSetActive(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  const userId = cleanStr(b.user_id);
  if (!userId || !isUuid(userId)) {
    return json({ error: "invalid_user", message: "user_id must be a UUID." }, 400);
  }
  if (typeof b.active !== "boolean") {
    return json({ error: "invalid_active", message: "active must be a boolean." }, 400);
  }
  const gate = await canMutateUser(supabase, scope, userId, "deactivate");
  if (!gate.ok) return json({ error: "forbidden", message: gate.message }, 403);

  if (!b.active && !scope.isPlatformAdmin) {
    // Deactivating: ensure no tenant loses its last owner.
    const footprint = await targetFootprint(supabase, userId);
    for (const [tenantId, roleKey] of footprint) {
      if (roleKey === "tenant_owner" && callerCan(scope, tenantId, "deactivate")) {
        const remaining = await ownerCount(supabase, tenantId, userId);
        if (remaining === 0) {
          return json(
            { error: "last_owner", message: "Refusing: this user is the last active owner of a tenant you administer." },
            409,
          );
        }
      }
    }
  }

  // Ban = deactivated; unban = active. 100 years is effectively permanent.
  const { error } = await supabase.auth.admin.updateUserById(userId, {
    ban_duration: b.active ? "0s" : "876000h",
  });
  if (error) {
    const cid = newCorrelationId();
    logServerError("manage-users", cid, "set_active", error);
    return json(
      { error: "update_failed", message: "Could not change the account status.", ref: cid },
      500,
    );
  }

  await audit(supabase, scope, null, "set_active", "auth_user", userId, { active: b.active });
  return json({ ok: true, user_id: userId, active: b.active });
}

async function handleDeleteUser(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  const userId = cleanStr(b.user_id);
  if (!userId || !isUuid(userId)) {
    return json({ error: "invalid_user", message: "user_id must be a UUID." }, 400);
  }
  // delete_user stays restricted: legacy tenant owner/admin or platform
  // admin only (permission-based managers use set_active instead).
  const gate = await canMutateUser(supabase, scope, userId, "deactivate");
  if (!gate.ok) return json({ error: "forbidden", message: gate.message }, 403);
  const isLegacyManager =
    scope.isPlatformAdmin ||
    [...scope.tenantRanks.values()].some((r) => r >= 90);
  if (!isLegacyManager) {
    return json(
      { error: "forbidden", message: "Only a tenant owner/admin or platform admin can delete users." },
      403,
    );
  }

  if (await isPlatformAdminUser(supabase, userId)) {
    // Only a platform_owner may delete platform admins, and never the last one.
    if (!scope.isPlatformOwner) {
      return json({ error: "forbidden", message: "Only a platform owner can delete a platform admin." }, 403);
    }
    const { count } = await supabase
      .from("platform_admins")
      .select("user_id", { count: "exact", head: true });
    if ((count ?? 0) <= 1) {
      return json({ error: "last_platform_owner", message: "Refusing to delete the last platform admin." }, 409);
    }
    await supabase.from("platform_admins").delete().eq("user_id", userId);
  } else if (!scope.isPlatformAdmin) {
    const footprint = await targetFootprint(supabase, userId);
    for (const [tenantId, roleKey] of footprint) {
      if (roleKey === "tenant_owner" && callerCan(scope, tenantId, "deactivate")) {
        const remaining = await ownerCount(supabase, tenantId, userId);
        if (remaining === 0) {
          return json(
            { error: "last_owner", message: "Refusing: this user is the last active owner of a tenant you administer." },
            409,
          );
        }
      }
    }
  }

  const { error } = await supabase.auth.admin.deleteUser(userId);
  if (error) {
    const cid = newCorrelationId();
    logServerError("manage-users", cid, "delete_user", error);
    return json(
      { error: "delete_failed", message: "Could not delete the user account.", ref: cid },
      500,
    );
  }
  // tenant_memberships rows cascade via FK (ON DELETE CASCADE).

  await audit(supabase, scope, null, "delete_user", "auth_user", userId, {});
  return json({ ok: true, user_id: userId });
}

async function handleAssignMembership(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  const userId = cleanStr(b.user_id);
  const tenantId = cleanStr(b.tenant_id);
  const role = cleanStr(b.role);
  if (!userId || !isUuid(userId) || !tenantId || !isUuid(tenantId)) {
    return json({ error: "invalid_input", message: "user_id and tenant_id must be UUIDs." }, 400);
  }
  if (!role || !(await isActiveTenantRole(supabase, tenantId, role))) {
    return json({ error: "invalid_role", message: `Unknown or inactive role for this tenant: ${role ?? "(none)"}.` }, 400);
  }
  if (!scope.isPlatformAdmin) {
    if (!callerCan(scope, tenantId, "roles")) {
      return json({ error: "forbidden", message: "You do not administer this tenant." }, 403);
    }
    const gateMsg = await assignRoleGate(supabase, scope, tenantId, role);
    if (gateMsg) {
      return json({ error: "forbidden", message: gateMsg }, 403);
    }
    const gate = await canMutateUser(supabase, scope, userId, "roles");
    if (!gate.ok) return json({ error: "forbidden", message: gate.message }, 403);
  } else if (await isPlatformAdminUser(supabase, userId)) {
    return json({ error: "forbidden", message: "Platform admins are managed via set_platform_role." }, 403);
  }

  const { error } = await supabase.from("tenant_memberships").upsert(
    { tenant_id: tenantId, user_id: userId, role, is_active: true },
    { onConflict: "user_id,tenant_id" },
  );
  if (error) {
    const cid = newCorrelationId();
    logServerError("manage-users", cid, "assign_membership", error);
    return json(
      { error: "assign_failed", message: "Could not assign the membership.", ref: cid },
      500,
    );
  }

  await audit(supabase, scope, tenantId, "assign_membership", "tenant_membership", userId, { role });
  return json({ ok: true, user_id: userId, tenant_id: tenantId, role });
}

async function handleRemoveMembership(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  const userId = cleanStr(b.user_id);
  const tenantId = cleanStr(b.tenant_id);
  if (!userId || !isUuid(userId) || !tenantId || !isUuid(tenantId)) {
    return json({ error: "invalid_input", message: "user_id and tenant_id must be UUIDs." }, 400);
  }
  if (!scope.isPlatformAdmin && !callerCan(scope, tenantId, "roles")) {
    return json({ error: "forbidden", message: "You do not administer this tenant." }, 403);
  }

  const { data: existing } = await supabase
    .from("tenant_memberships")
    .select("role")
    .eq("user_id", userId)
    .eq("tenant_id", tenantId)
    .maybeSingle();
  if (!existing) {
    return json({ error: "not_found", message: "No such membership." }, 404);
  }
  if (existing.role === "tenant_owner") {
    const remaining = await ownerCount(supabase, tenantId, userId);
    if (remaining === 0) {
      return json({ error: "last_owner", message: "Refusing: this is the tenant's last active owner." }, 409);
    }
  }

  const { error } = await supabase
    .from("tenant_memberships")
    .delete()
    .eq("user_id", userId)
    .eq("tenant_id", tenantId);
  if (error) {
    const cid = newCorrelationId();
    logServerError("manage-users", cid, "remove_membership", error);
    return json(
      { error: "remove_failed", message: "Could not remove the membership.", ref: cid },
      500,
    );
  }

  await audit(supabase, scope, tenantId, "remove_membership", "tenant_membership", userId, { role: existing.role });
  return json({ ok: true, user_id: userId, tenant_id: tenantId });
}

async function handleListUsers(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  const filterTenant = cleanStr(b.tenant_id);
  if (filterTenant && !isUuid(filterTenant)) {
    return json({ error: "invalid_tenant", message: "tenant_id must be a UUID." }, 400);
  }
  const search = cleanStr(b.search)?.toLowerCase() ?? null;
  const limit = Math.min(Math.max(Number(b.limit) || 50, 1), 200);
  const offset = Math.max(Number(b.offset) || 0, 0);

  // Scope: which tenants may this caller see users for?
  let tenantIds: string[];
  if (scope.isPlatformAdmin) {
    if (filterTenant) {
      tenantIds = [filterTenant];
    } else {
      const { data } = await supabase.from("tenants").select("id").limit(1000);
      tenantIds = (data ?? []).map((t) => t.id as string);
    }
  } else {
    tenantIds = [...scope.userTenants];
    if (filterTenant) {
      if (!callerCan(scope, filterTenant, "users")) {
        return json({ error: "forbidden", message: "You do not administer this tenant." }, 403);
      }
      tenantIds = [filterTenant];
    }
  }

  const { data: memberships } = await supabase
    .from("tenant_memberships")
    .select("user_id, tenant_id, role, is_active")
    .in("tenant_id", tenantIds.length > 0 ? tenantIds : ["00000000-0000-0000-0000-000000000000"]);

  const byUser = new Map<string, { tenants: { tenant_id: string; role: string; is_active: boolean }[] }>();
  for (const m of memberships ?? []) {
    const entry = byUser.get(m.user_id) ?? { tenants: [] };
    entry.tenants.push({ tenant_id: m.tenant_id, role: m.role, is_active: m.is_active });
    byUser.set(m.user_id, entry);
  }

  const users: Record<string, unknown>[] = [];
  for (const [userId, info] of byUser) {
    const { data: u, error } = await supabase.auth.admin.getUserById(userId);
    if (error || !u?.user) continue;
    const email = (u.user.email ?? "").toLowerCase();
    const name = ((u.user.user_metadata as Record<string, unknown> | null)?.name as string | undefined) ?? "";
    if (search && !email.includes(search) && !name.toLowerCase().includes(search)) continue;
    // `banned_until` is not on the User type in supabase-js 2.44 — read defensively.
    const bannedUntil = (u.user as unknown as Record<string, unknown>).banned_until;
    users.push({
      id: u.user.id,
      email: u.user.email,
      name,
      banned: !!bannedUntil,
      last_sign_in_at: u.user.last_sign_in_at,
      created_at: u.user.created_at,
      tenants: info.tenants,
    });
  }
  users.sort((a, b) => String(a.email ?? "").localeCompare(String(b.email ?? "")));
  const total = users.length;
  return json({ users: users.slice(offset, offset + limit), total, limit, offset });
}

/**
 * safety_check {tenant_id, user_id} — principal-safety pre-check for the
 * 8a UI: counts active tenant_owners and active holders of roles.assign
 * in the tenant, and reports whether the target is the last of each.
 * The client refuses the destructive/demoting action with a plain-Urdu
 * explanation BEFORE attempting it; the DB triggers remain the backstop.
 */
async function handleSafetyCheck(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  const tenantId = cleanStr(b.tenant_id);
  const userId = cleanStr(b.user_id);
  if (!tenantId || !isUuid(tenantId) || !userId || !isUuid(userId)) {
    return json({ error: "invalid_input", message: "tenant_id and user_id must be UUIDs." }, 400);
  }
  if (!callerCan(scope, tenantId, "users")) {
    return json({ error: "forbidden", message: "You do not administer this tenant." }, 403);
  }

  const { data: ownerRows } = await supabase
    .from("tenant_memberships")
    .select("user_id")
    .eq("tenant_id", tenantId)
    .eq("role", "tenant_owner")
    .eq("is_active", true);
  const ownerIds = (ownerRows ?? []).map((r) => r.user_id as string);

  // Tenant role keys that currently grant roles.assign.
  const { data: permRow } = await supabase
    .from("permissions")
    .select("id")
    .eq("code", "roles.assign")
    .maybeSingle();
  const holderIds: string[] = [];
  if (permRow) {
    const { data: trpRows } = await supabase
      .from("tenant_role_permissions")
      .select("tenant_role_id")
      .eq("permission_id", (permRow as Record<string, unknown>).id as string);
    const roleIds = (trpRows ?? []).map((r) => r.tenant_role_id as string);
    if (roleIds.length > 0) {
      const { data: roleRows } = await supabase
        .from("tenant_roles")
        .select("key")
        .in("id", roleIds)
        .eq("tenant_id", tenantId)
        .eq("is_active", true);
      const assignKeys = (roleRows ?? []).map((r) => r.key as string);
      if (assignKeys.length > 0) {
        const { data: holderRows } = await supabase
          .from("tenant_memberships")
          .select("user_id")
          .eq("tenant_id", tenantId)
          .in("role", assignKeys)
          .eq("is_active", true);
        for (const r of holderRows ?? []) holderIds.push(r.user_id as string);
      }
    }
  }

  const { data: targetMem } = await supabase
    .from("tenant_memberships")
    .select("role")
    .eq("tenant_id", tenantId)
    .eq("user_id", userId)
    .eq("is_active", true)
    .maybeSingle();
  const targetRole = targetMem ? (targetMem.role as string) : null;

  await audit(supabase, scope, tenantId, "safety_check", "tenant_membership", userId, {
    target_role: targetRole,
  });
  return json({
    owner_count: ownerIds.length,
    is_last_owner: ownerIds.length === 1 && ownerIds[0] === userId,
    assign_holder_count: holderIds.length,
    is_last_assign_holder: holderIds.length === 1 && holderIds[0] === userId,
    target_role: targetRole,
  });
}

async function handleSetPlatformRole(
  supabase: SupabaseClient,
  scope: CallerScope,
  b: Record<string, unknown>,
): Promise<Response> {
  if (!scope.isPlatformOwner) {
    return json({ error: "forbidden", message: "Only a platform owner can manage platform roles." }, 403);
  }
  const userId = cleanStr(b.user_id);
  if (!userId || !isUuid(userId)) {
    return json({ error: "invalid_user", message: "user_id must be a UUID." }, 400);
  }
  const role = b.role === null ? null : cleanStr(b.role);
  if (role !== null && !(PLATFORM_ROLES as readonly string[]).includes(role)) {
    return json({ error: "invalid_role", message: "role must be platform_owner, platform_support, or null." }, 400);
  }

  if (role === null) {
    // Revoking: never remove the last platform admin, never self-revoke the last owner blindly.
    const { count } = await supabase
      .from("platform_admins")
      .select("user_id", { count: "exact", head: true });
    if ((count ?? 0) <= 1) {
      return json({ error: "last_platform_admin", message: "Refusing to remove the last platform admin." }, 409);
    }
    const { error } = await supabase.from("platform_admins").delete().eq("user_id", userId);
    if (error) {
      const cid = newCorrelationId();
      logServerError("manage-users", cid, "set_platform_role/revoke", error);
      return json(
        { error: "revoke_failed", message: "Could not revoke the platform role.", ref: cid },
        500,
      );
    }
  } else {
    const { error } = await supabase
      .from("platform_admins")
      .upsert({ user_id: userId, role }, { onConflict: "user_id" });
    if (error) {
      const cid = newCorrelationId();
      logServerError("manage-users", cid, "set_platform_role/grant", error);
      return json(
        { error: "grant_failed", message: "Could not grant the platform role.", ref: cid },
        500,
      );
    }
  }

  await audit(supabase, scope, null, "set_platform_role", "platform_admin", userId, { role });
  return json({ ok: true, user_id: userId, role });
}

// ── router ───────────────────────────────────────────────────────────────

/**
 * Per-action key allow-lists (SEC-M12): any unknown top-level key is
 * rejected with 400 before the handler runs. Mass-assignment defense —
 * a new privileged field added to a handler later is NOT writable until
 * it is listed here.
 */
const ACTION_SCHEMAS: Record<string, Record<string, FieldRule>> = {
  create_user: {
    action: {}, email: {}, password: {}, user_metadata: {}, app_metadata: {},
    tenant_id: {}, role: {},
  },
  update_user: {
    action: {}, user_id: {}, email: {}, password: {}, user_metadata: {}, app_metadata: {},
  },
  set_active: { action: {}, user_id: {}, active: {} },
  delete_user: { action: {}, user_id: {} },
  assign_membership: { action: {}, user_id: {}, tenant_id: {}, role: {} },
  remove_membership: { action: {}, user_id: {}, tenant_id: {} },
  list_users: { action: {}, tenant_id: {}, search: {}, limit: {}, offset: {} },
  safety_check: { action: {}, tenant_id: {}, user_id: {} },
  set_platform_role: { action: {}, user_id: {}, role: {} },
};

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

  const scopeOr = await resolveCaller(supabase, req);
  if (scopeOr instanceof Response) return scopeOr;
  const scope = scopeOr;

  // RED-TEAM RT-03: admin APIs are high-blast-radius — throttle per
  // caller so one compromised manager account cannot be scripted at
  // full speed (mass user creation / deactivation / password resets).
  const rl = await rateLimit(supabase, `manage-users:${scope.callerId}`, 120, 3600);
  if (!rl.allowed) return tooManyRequests(rl.retryAfterSec);

  const parsed = await readJsonBody(req);
  if (!parsed.ok) {
    return badBodyResponse(parsed);
  }
  const action = cleanStr(parsed.body.action);
  const b = parsed.body;

  // Account creation is the spammiest action (auth-user exhaustion,
  // email-enumeration oracle) — tighter bucket on top of the general one.
  if (action === "create_user") {
    const rlCreate = await rateLimit(
      supabase,
      `manage-users:create:${scope.callerId}`,
      30,
      3600,
    );
    if (!rlCreate.allowed) return tooManyRequests(rlCreate.retryAfterSec);
  }

  // Reject unknown top-level keys per action (mass-assignment defense).
  if (action && ACTION_SCHEMAS[action]) {
    const v = validateBody(b, ACTION_SCHEMAS[action]);
    if (!v.ok) return invalidBodyResponse(v.problems);
  }

  try {
    switch (action) {
      case "create_user":
        return await handleCreateUser(supabase, scope, b);
      case "update_user":
        return await handleUpdateUser(supabase, scope, b);
      case "set_active":
        return await handleSetActive(supabase, scope, b);
      case "delete_user":
        return await handleDeleteUser(supabase, scope, b);
      case "assign_membership":
        return await handleAssignMembership(supabase, scope, b);
      case "remove_membership":
        return await handleRemoveMembership(supabase, scope, b);
      case "list_users":
        return await handleListUsers(supabase, scope, b);
      case "safety_check":
        return await handleSafetyCheck(supabase, scope, b);
      case "set_platform_role":
        return await handleSetPlatformRole(supabase, scope, b);
      default:
        return json(
          {
            error: "unknown_action",
            message:
              "action must be one of: create_user, update_user, set_active, delete_user, assign_membership, remove_membership, list_users, safety_check, set_platform_role.",
          },
          400,
        );
    }
  } catch (e) {
    // Never leak stack traces or secrets to the client.
    const cid = newCorrelationId();
    logServerError("manage-users", cid, "unhandled", e);
    return json({ error: "internal", message: "Unexpected server error.", ref: cid }, 500);
  }
});
