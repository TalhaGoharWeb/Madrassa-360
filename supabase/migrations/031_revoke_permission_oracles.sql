-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 031: revoke permission-oracle RPCs
--
-- SEC-M6: the SECURITY DEFINER helpers user_effective_permission(UUID,
-- UUID, TEXT), user_code_denied(UUID, UUID, TEXT) and
-- tenant_has_permission(UUID, TEXT) take tenant/user as parameters and
-- were GRANTed to `authenticated` (020). Any JWT holder could probe
-- arbitrary tenant/user/code triples — cross-tenant role/permission
-- reconnaissance and tenant-existence probing.
--
-- Fix: REVOKE EXECUTE from authenticated/anon on the parameterized
-- helpers. The auth.uid()-bound wrappers the app actually uses
-- (get_my_permissions, get_my_permissions_detailed) stay granted.
-- RLS policies keep working: they run these functions as SECURITY
-- DEFINER regardless of the caller's grant. Edge Functions call them
-- via the service_role client, which bypasses grants entirely.
--
-- NOTE: user_is_tenant_admin(UUID,UUID), scope_allows(UUID,UUID,TEXT,UUID)
-- and result_class_id(UUID,UUID) are similarly parameterizable. They are
-- left granted here because RLS-adjacent client flows reference them;
-- see docs/audit/security/MIGRATION_NOTES_029_044.md for the follow-up.
--
-- Idempotent: REVOKE ... FROM is a safe no-op when the grant is absent.
-- ═══════════════════════════════════════════════════════════════

REVOKE EXECUTE ON FUNCTION public.user_effective_permission(UUID, UUID, TEXT)
  FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.user_code_denied(UUID, UUID, TEXT)
  FROM authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.tenant_has_permission(UUID, TEXT)
  FROM authenticated, anon;

-- Explicitly keep the auth.uid()-bound wrappers callable by the app.
GRANT EXECUTE ON FUNCTION public.get_my_permissions(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_permissions_detailed(UUID) TO authenticated;


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('031_revoke_permission_oracles')
ON CONFLICT DO NOTHING;
