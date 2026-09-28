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
  isEmail,
  isUuid,
  json,
  preflight,
  readJsonBody,
  serviceClient,
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

const PLATFORM_ROLES = ["platform_owner", "platform_support"] as const;

interface CallerScope {
  callerId: string;
  isPlatformAdmin: boolean;
  isPlatformOwner: boolean;
  /** tenant_id -> caller's rank in that tenant (tenant_owner/tenant_admin only) */
  tenantRanks: Map<string, number>;
  /** tenants where the caller may manage users (owner/admin, or users.view) */
  userTenants: Set<string>;
  /** tenants where the caller may assign roles (owner/admin, or roles.assign) */
  roleTenants: Set<string>;
  /** tenants where the caller may (de)activate users (owner/admin, or users.deactivate) */
  deactivateTenants: Set<string>;
}

/** Effective-permission check for one code via the 020 RPC (service role). */
async function holdsPermission(
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
  const roleTenants = new Set<string>();
  const deactivateTenants = new Set<string>();

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
        roleTenants.add(tenantId);
        deactivateTenants.add(tenantId);
      } else {
        // Phase-6 template roles: rights from effective permissions.
        const [canView, canAssign, canDeactivate] = await Promise.all([
          holdsPermission(supabase, tenantId, caller.id, "users.view"),
          holdsPermission(supabase, tenantId, caller.id, "roles.assign"),
          holdsPermission(supabase, tenantId, caller.id, "users.deactivate"),
        ]);
        if (canView) userTenants.add(tenantId);
        if (canAssign) roleTenants.add(tenantId);
        if (canDeactivate) deactivateTenants.add(tenantId);
      }
    }
    if (
      tenantRanks.size === 0 &&
      userTenants.size === 0 &&
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
    roleTenants,
    deactivateTenants,
  };
}

/** Right check for one tenant: platform admins pass; otherwise the
 * per-right tenant set built by resolveCaller. */
function callerCan(
  scope: CallerScope,
  tenantId: string,
  right: "users" | "roles" | "deactivate",
): boolean {
  if (scope.isPlatformAdmin) return true;
  if (right === "users") return scope.userTenants.has(tenantId);
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
 * Can this caller mutate the target user with the given [right]?
 * Platform admins: yes (except platform-role changes are gated separately).
 * Tenant callers: the target must not be a platform admin, must live
 * entirely inside the caller's scoped tenants for that right, and —
 * for legacy rank-based callers — must hold no role above the caller's
 * rank there. Permission-based (Phase-6) callers may never touch a
 * tenant_owner: only owners / platform admins may manage owners.
 */
async function canMutateUser(
  supabase: SupabaseClient,
  scope: CallerScope,
  targetUserId: string,
  right: "users" | "roles" | "deactivate",
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
    const callerRank = scope.tenantRanks.get(tenantId) ?? 0;
    const targetRank = TENANT_ROLE_RANK[roleKey] ?? 0;
    if (callerRank > 0 && targetRank > callerRank) {
      return { ok: false, message: "Target holds a higher role than you in a shared tenant." };
    }
    if (callerRank === 0 && roleKey === "tenant_owner") {
      return { ok: false, message: "Only a tenant owner or platform admin can manage a tenant owner." };
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

/** Rank gate for assigning [role] in [tenantId]: legacy callers cannot
 * assign above their own rank; permission-based callers cannot assign
 * the tenant_owner key. Returns an error message, or null when allowed. */
function assignRoleGate(
  scope: CallerScope,
  tenantId: string,
  role: string,
): string | null {
  const callerRank = scope.tenantRanks.get(tenantId) ?? 0;
  const targetRank = TENANT_ROLE_RANK[role] ?? 0;
  if (callerRank > 0 && targetRank > callerRank) {
    return "You cannot assign a role above your own.";
  }
  if (callerRank === 0 && role === "tenant_owner") {
    return "Only a tenant owner or platform admin can assign the owner role.";
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
  const userMetadata = asRecord(b.user_metadata) ?? {};
  const appMetadata = asRecord(b.app_metadata) ?? {};

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
      const gateMsg = assignRoleGate(scope, tenantId, role);
      if (gateMsg) {
        return json({ error: "forbidden", message: gateMsg }, 403);
      }
    } else if (scope.userTenants.size === 0 && scope.tenantRanks.size === 0) {
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
    const msg = error?.message ?? "User creation failed.";
    const status = /already/i.test(msg) ? 409 : 500;
    return json({ error: "create_failed", message: msg }, status);
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
      return json(
        { error: "membership_failed", message: `Auth user created but membership failed (${memErr.message}); creation was rolled back.` },
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
  const gate = await canMutateUser(supabase, scope, userId, "users");
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
  const userMetadata = asRecord(b.user_metadata);
  if (userMetadata) attrs.user_metadata = userMetadata;
  const appMetadata = asRecord(b.app_metadata);
  if (appMetadata) attrs.app_metadata = appMetadata;
  if (Object.keys(attrs).length === 0) {
    return json({ error: "nothing_to_update", message: "No updatable fields provided." }, 400);
  }

  const { error } = await supabase.auth.admin.updateUserById(userId, attrs);
  if (error) return json({ error: "update_failed", message: error.message }, 500);

  const logged: Record<string, unknown> = {};
  if (email) logged.email = email;
  if (userMetadata) logged.user_metadata = userMetadata;
  if (appMetadata) logged.app_metadata = appMetadata;
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
  if (error) return json({ error: "update_failed", message: error.message }, 500);

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
  if (error) return json({ error: "delete_failed", message: error.message }, 500);
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
    const gateMsg = assignRoleGate(scope, tenantId, role);
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
  if (error) return json({ error: "assign_failed", message: error.message }, 500);

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
  if (error) return json({ error: "remove_failed", message: error.message }, 500);

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
    if (error) return json({ error: "revoke_failed", message: error.message }, 500);
  } else {
    const { error } = await supabase
      .from("platform_admins")
      .upsert({ user_id: userId, role }, { onConflict: "user_id" });
    if (error) return json({ error: "grant_failed", message: error.message }, 500);
  }

  await audit(supabase, scope, null, "set_platform_role", "platform_admin", userId, { role });
  return json({ ok: true, user_id: userId, role });
}

// ── router ───────────────────────────────────────────────────────────────

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

  const parsed = await readJsonBody(req);
  if (!parsed.ok) {
    return json({ error: "invalid_json", message: "Request body must be a JSON object." }, 400);
  }
  const action = cleanStr(parsed.body.action);
  const b = parsed.body;

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
    console.error("[manage-users] unhandled error:", (e as Error)?.message ?? e);
    return json({ error: "internal", message: "Unexpected server error." }, 500);
  }
});
