-- ═══════════════════════════════════════════════════════════════
-- Migration 021 — Role template seeds for new + existing tenants
-- (Phase 6, mission §§16–17, 50–53, 65)
--
-- (a) tenant_roles gains two ADDITIVE columns (019/020 semantics
--     untouched):
--       is_template_default BOOLEAN NOT NULL DEFAULT FALSE — TRUE for
--         rows seeded from the global template catalog by
--         provision_role_templates() (or the 019 backfill), so the UI
--         can show "based on template X". Roles a Principal creates
--         via create_tenant_role() keep the FALSE default: they are
--         Principal-owned, never system defaults.
--         NOTE: the flag records provenance ("seeded from a template"),
--         not "unedited" — a Principal's later edits do not clear it.
--       description TEXT — the template's admin-facing description,
--         copied from public.roles at seed time.
--     Existing template-derived rows (template_key set, created_by NULL
--     = seeded by the 019 backfill, not by a Principal) are backfilled
--     to is_template_default=TRUE + their catalog description.
--
-- (b) provision_role_templates(p_tenant_id uuid): idempotent seeder that
--     materializes a tenant's editable role catalog from the global
--     template catalog (public.roles is_system, scope madrasa/external
--     + public.role_permissions) — the same proven algorithm as 019's
--     backfill, parameterized for a single tenant:
--       * INSERT tenant_roles … ON CONFLICT (tenant_id, key) DO NOTHING
--         — existing rows are NEVER updated, so a Principal's renames /
--         edits / deactivations survive re-runs.
--       * tenant_role_permissions are inserted ONLY for roles inserted
--         by this call, plus a repair pass for template-derived roles
--         that hold zero permissions (partial-run recovery, 019
--         semantics) — a role holding any permissions is never touched,
--         so permissions a Principal deliberately removed are never
--         re-added.
--     The 15 Pakistani-madrasa role templates (mission §65, design doc
--     §5) are named explicitly and FAIL LOUD if any is missing from the
--     catalog, has an empty curated permission set, or leaves a seeded
--     role with zero permissions:
--       mohtamim, naib_mohtamim, nazim_aala, nazim_taleem,
--       nazim_intizamia, nazim_maliyat, daftar_dar, ustad, ustad_hifz,
--       nazim_hifz, nazim_darul_iqama, warden, mumtahin, store_incharge,
--       hr_incharge.
--     Permission sets are copied from the catalog (the exact canonical
--     66 dotted + 56 legacy codes seeded by 019), and a fail-loud check
--     raises if any referenced permission_id does not resolve to a live
--     catalog code.
--
-- (c) EXECUTE is granted to service_role ONLY — the intended caller is
--     the provision-tenant edge function (plus platform operators via
--     SQL). Authenticated app users manage roles through the 020 RPCs
--     (roles.assign-gated), never this seeder.
--
-- Idempotent: safe to re-run.
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- (a) Additive columns on tenant_roles
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.tenant_roles
  ADD COLUMN IF NOT EXISTS is_template_default BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.tenant_roles
  ADD COLUMN IF NOT EXISTS description TEXT;

-- Backfill rows seeded by the 019 backfill (template_key set and
-- created_by NULL — i.e. NOT created by a Principal via the
-- create_tenant_role RPC, which always sets created_by).
UPDATE public.tenant_roles tr
   SET description = r.description
  FROM public.roles r
 WHERE r.name = tr.template_key
   AND tr.template_key IS NOT NULL
   AND tr.created_by IS NULL
   AND tr.description IS NULL
   AND r.description IS NOT NULL;

UPDATE public.tenant_roles
   SET is_template_default = TRUE
 WHERE template_key IS NOT NULL
   AND created_by IS NULL
   AND is_template_default = FALSE;


-- ═══════════════════════════════════════════════════════════════
-- (b) provision_role_templates(p_tenant_id uuid)
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.provision_role_templates(p_tenant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_missing_templates TEXT;
  v_empty_templates   TEXT;
  v_orphan_perm_ids   TEXT;
  v_zero_perm_roles   TEXT;
BEGIN
  -- Fail early with a clear message (the FK would catch this on insert).
  IF NOT EXISTS (SELECT 1 FROM public.tenants WHERE id = p_tenant_id) THEN
    RAISE EXCEPTION 'provision_role_templates: tenant % does not exist', p_tenant_id;
  END IF;

  -- Fail-loud 1: every one of the 15 Phase-6 role templates (mission §65,
  -- design doc §5) must exist in the global template catalog.
  SELECT string_agg(t.k, ', ' ORDER BY t.k) INTO v_missing_templates
    FROM (VALUES
      ('mohtamim'), ('naib_mohtamim'), ('nazim_aala'), ('nazim_taleem'),
      ('nazim_intizamia'), ('nazim_maliyat'), ('daftar_dar'), ('ustad'),
      ('ustad_hifz'), ('nazim_hifz'), ('nazim_darul_iqama'), ('warden'),
      ('mumtahin'), ('store_incharge'), ('hr_incharge')
    ) AS t(k)
   WHERE NOT EXISTS (
           SELECT 1 FROM public.roles r
            WHERE r.name = t.k AND r.is_system
         );
  IF v_missing_templates IS NOT NULL THEN
    RAISE EXCEPTION 'provision_role_templates FAIL-LOUD: template key(s) missing from public.roles: %',
      v_missing_templates;
  END IF;

  -- Fail-loud 2: each of the 15 must carry a non-empty curated permission
  -- set in the catalog (the phase-2 doc §5 curated sets, seeded by 019).
  SELECT string_agg(t.k, ', ' ORDER BY t.k) INTO v_empty_templates
    FROM (VALUES
      ('mohtamim'), ('naib_mohtamim'), ('nazim_aala'), ('nazim_taleem'),
      ('nazim_intizamia'), ('nazim_maliyat'), ('daftar_dar'), ('ustad'),
      ('ustad_hifz'), ('nazim_hifz'), ('nazim_darul_iqama'), ('warden'),
      ('mumtahin'), ('store_incharge'), ('hr_incharge')
    ) AS t(k)
   WHERE NOT EXISTS (
           SELECT 1
             FROM public.role_permissions rp
             JOIN public.roles r ON r.id = rp.role_id
            WHERE r.name = t.k
         );
  IF v_empty_templates IS NOT NULL THEN
    RAISE EXCEPTION 'provision_role_templates FAIL-LOUD: template(s) with empty catalog permission set: %',
      v_empty_templates;
  END IF;

  -- Fail-loud 3: every permission_id referenced by the template catalog
  -- sets must resolve to a live catalog code (the canonical 66 dotted +
  -- 56 legacy codes from 019). The FK makes orphans impossible; this is
  -- the explicit check the mission asks for.
  SELECT string_agg(DISTINCT rp.permission_id::text, ', ' ORDER BY rp.permission_id::text)
    INTO v_orphan_perm_ids
    FROM public.role_permissions rp
    JOIN public.roles r ON r.id = rp.role_id
   WHERE r.is_system
     AND r.scope IN ('madrasa', 'external')
     AND NOT EXISTS (
           SELECT 1 FROM public.permissions p WHERE p.id = rp.permission_id
         );
  IF v_orphan_perm_ids IS NOT NULL THEN
    RAISE EXCEPTION 'provision_role_templates FAIL-LOUD: template catalog references unknown permission_id(s): %',
      v_orphan_perm_ids;
  END IF;

  -- Seed the tenant's editable role catalog from the global template
  -- catalog. Existing rows are NEVER touched (ON CONFLICT DO NOTHING) —
  -- a Principal's renames, edits, and deactivations survive re-runs.
  -- There is deliberately no is_system immutability lock: every row is
  -- fully editable/deletable by the tenant afterwards.
  WITH new_roles AS (
    INSERT INTO public.tenant_roles
      (tenant_id, key, display_name, display_urdu, description,
       template_key, is_template_default)
    SELECT p_tenant_id, r.name, r.display_name, r.display_urdu,
           r.description, r.name, TRUE
      FROM public.roles r
     WHERE r.is_system
       AND r.scope IN ('madrasa', 'external')
    ON CONFLICT (tenant_id, key) DO NOTHING
    RETURNING id, template_key
  )
  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_id)
  SELECT nr.id, rp.permission_id
    FROM new_roles nr
    JOIN public.roles r             ON r.name = nr.template_key
    JOIN public.role_permissions rp ON rp.role_id = r.id
  ON CONFLICT (tenant_role_id, permission_id) DO NOTHING;

  -- Repair pass (019 semantics): a template-derived role that somehow
  -- holds ZERO permissions (partial earlier run) gets its catalog set
  -- now. Roles holding any permissions are never touched — permissions
  -- a Principal deliberately removed are never re-added.
  INSERT INTO public.tenant_role_permissions (tenant_role_id, permission_id)
  SELECT tr.id, rp.permission_id
    FROM public.tenant_roles tr
    JOIN public.roles r             ON r.name = tr.template_key
    JOIN public.role_permissions rp ON rp.role_id = r.id
   WHERE tr.tenant_id = p_tenant_id
     AND tr.template_key IS NOT NULL
     AND NOT EXISTS (
           SELECT 1 FROM public.tenant_role_permissions x
            WHERE x.tenant_role_id = tr.id
         )
  ON CONFLICT (tenant_role_id, permission_id) DO NOTHING;

  -- Fail-loud 4 (final invariant): after seeding, every one of the 15
  -- templates must hold at least one permission in this tenant.
  SELECT string_agg(tr.key, ', ' ORDER BY tr.key) INTO v_zero_perm_roles
    FROM public.tenant_roles tr
   WHERE tr.tenant_id = p_tenant_id
     AND tr.template_key IN (
           'mohtamim', 'naib_mohtamim', 'nazim_aala', 'nazim_taleem',
           'nazim_intizamia', 'nazim_maliyat', 'daftar_dar', 'ustad',
           'ustad_hifz', 'nazim_hifz', 'nazim_darul_iqama', 'warden',
           'mumtahin', 'store_incharge', 'hr_incharge'
         )
     AND NOT EXISTS (
           SELECT 1 FROM public.tenant_role_permissions x
            WHERE x.tenant_role_id = tr.id
         );
  IF v_zero_perm_roles IS NOT NULL THEN
    RAISE EXCEPTION 'provision_role_templates FAIL-LOUD: seeded template role(s) hold zero permissions: %',
      v_zero_perm_roles;
  END IF;
END;
$$;

-- (c) Lock down execution: the provision-tenant edge function
-- (service_role) and platform operators only.
REVOKE ALL ON FUNCTION public.provision_role_templates(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.provision_role_templates(UUID) TO service_role;


-- ── Version stamp ──────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('021_role_template_seeds')
ON CONFLICT DO NOTHING;
