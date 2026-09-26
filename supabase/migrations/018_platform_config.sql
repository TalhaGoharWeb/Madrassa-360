-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 018: platform_config + device management
-- (auto-update backend + per-install device registry + session revocation)
-- Phase 7 / Worker: AUTO-UPDATE + DEVICE MANAGEMENT (§§44–45)
--
-- Run AFTER 001–017. Adds three tables:
--
--   platform_config
--     Keyed single-row table (key='default') holding the release train
--     state for the Windows desktop app:
--       latest_version            TEXT — newest published version (semver)
--       minimum_supported_version TEXT — clients older than this MUST update
--       download_url              TEXT — where the installer lives
--       release_notes / release_notes_urdu — shown in the update UI
--       updated_at                TIMESTAMPTZ
--     RLS: SELECT is PUBLIC (USING (true)) — the update check runs
--     PRE-LOGIN, so the anon key must be able to read this row. Explicit
--     GRANT SELECT to anon/authenticated (RLS does the rest). ALL writes
--     are platform-admin only (is_platform_admin()).
--
--   devices
--     Per-install registry. device_id is a CLIENT-GENERATED v4 UUID
--     minted on first run and stored at %APPDATA%\Madrassa360\device.json —
--     it is explicitly NOT a hardware fingerprint (no MAC, no disk serial,
--     no TPM handle). Users are NEVER locked out by device binding;
--     revocation is admin-initiated only.
--       id UUID PK, device_id TEXT UNIQUE NOT NULL,
--       user_id → auth.users, tenant_id → tenants,
--       os / os_version / app_version TEXT,
--       last_active TIMESTAMPTZ (opportunistic heartbeat, ≤1/hour),
--       created_at TIMESTAMPTZ.
--     RLS: users see/update their OWN devices; tenant admins
--     (is_tenant_admin) see their tenant's devices; platform admins see all.
--
--   device_sessions
--     Login-session rows (one per device per sign-in). Revocation is a
--     timestamp, not a delete — revoked rows stay for audit.
--       id UUID PK, device_id → devices, user_id → auth.users,
--       tenant_id → tenants (denormalised so RLS needs no join),
--       revoked_at TIMESTAMPTZ NULL, created_at.
--     RLS: users may revoke their OWN sessions; tenant admins may set
--     revoked_at on their tenant's devices; platform admins full access.
--     A trigger (device_sessions_revoke_only_guard) narrows UPDATE to
--     revoked_at ONLY and makes revocation one-way (clients can never
--     un-revoke; that is platform-ops / service-role territory).
--
-- ── REVOCATION ENFORCEMENT CONTRACT (documented, not live) ──────────
-- This migration stores revocation state; it does NOT enforce it at the
-- auth layer. Enforcement is a documented contract for the platform team:
--   Option A (recommended): a Supabase Auth Hook
--     (auth → Hooks → "Custom Access Token" or a pre-auth check) that
--     rejects token issuance/refresh when
--     EXISTS (SELECT 1 FROM device_sessions
--             WHERE device_id = <claim device_id> AND revoked_at IS NULL
--             AND created_at > <some grace>) is false — i.e. the device's
--     latest session is revoked.
--   Option B: an Edge Function `check-session` invoked by the app on
--     login AND on each hourly heartbeat; it signs the user out client-
--     side when their active session row has revoked_at set.
-- Until either is wired, revocation is advisory (admin dashboard shows
-- the state; the client reports it). The app MUST NOT brick itself when
-- the enforcement endpoint is unreachable — offline tolerance is a hard
-- requirement (§44).
--
-- ── SEED ────────────────────────────────────────────────────────────
-- One platform_config row: latest=1.0.0, minimum=1.0.0, download_url =
-- the GitHub Releases page. THE RELEASE WORKFLOW (not this seed) updates
-- this row on every publish — see docs/WINDOWS_BUILD.md § "Version bump
-- procedure". The seed is ON CONFLICT DO NOTHING so re-runs never clobber
-- a newer row written by the release pipeline.
--
-- Idempotent: CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS /
-- pg_policies existence guards / CREATE OR REPLACE trigger function /
-- schema_migrations ON CONFLICT DO NOTHING.
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- (a) tables
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.platform_config (
  key                     TEXT        PRIMARY KEY DEFAULT 'default',
  latest_version          TEXT        NOT NULL DEFAULT '1.0.0',
  minimum_supported_version TEXT      NOT NULL DEFAULT '1.0.0',
  download_url            TEXT        NOT NULL
      DEFAULT 'https://github.com/TalhaGoharWeb/Madrassa-360/releases',
  release_notes           TEXT,
  release_notes_urdu      TEXT,
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.devices (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   TEXT        NOT NULL UNIQUE,
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id   UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  os          TEXT,
  os_version  TEXT,
  app_version TEXT,
  last_active TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.device_sessions (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id   UUID        NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id   UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  revoked_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_devices_tenant_id
  ON public.devices(tenant_id);
CREATE INDEX IF NOT EXISTS idx_devices_user_id
  ON public.devices(user_id);
CREATE INDEX IF NOT EXISTS idx_device_sessions_device_id
  ON public.device_sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_device_sessions_user_id
  ON public.device_sessions(user_id);
-- Partial index: the hot query is "is this device's latest session revoked?"
CREATE INDEX IF NOT EXISTS idx_device_sessions_active
  ON public.device_sessions(device_id, created_at DESC)
  WHERE revoked_at IS NULL;

ALTER TABLE public.platform_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_sessions ENABLE ROW LEVEL SECURITY;

-- The update check runs pre-login through the anon key: make the grant
-- explicit rather than relying on project default privileges.
GRANT SELECT ON public.platform_config TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.devices TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_sessions TO authenticated;


-- ─────────────────────────────────────────────────────────────
-- (b) RLS policies
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
  -- platform_config: public read (pre-login update check), platform-admin write.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='platform_config'
                 AND policyname='platform_config_public_read') THEN
    CREATE POLICY "platform_config_public_read"
      ON public.platform_config FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='platform_config'
                 AND policyname='platform_config_admin_write') THEN
    CREATE POLICY "platform_config_admin_write"
      ON public.platform_config FOR ALL USING (public.is_platform_admin())
      WITH CHECK (public.is_platform_admin());
  END IF;

  -- devices: own rows for users; tenant rows for tenant admins; all for platform admins.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='devices'
                 AND policyname='devices_select') THEN
    CREATE POLICY "devices_select"
      ON public.devices FOR SELECT USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(devices.tenant_id)
        OR (devices.user_id = auth.uid()
            AND public.is_tenant_member(devices.tenant_id))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='devices'
                 AND policyname='devices_insert_own') THEN
    CREATE POLICY "devices_insert_own"
      ON public.devices FOR INSERT WITH CHECK (
        public.is_platform_admin()
        OR (devices.user_id = auth.uid()
            AND public.is_tenant_member(devices.tenant_id))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='devices'
                 AND policyname='devices_update') THEN
    CREATE POLICY "devices_update"
      ON public.devices FOR UPDATE USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(devices.tenant_id)
        OR (devices.user_id = auth.uid()
            AND public.is_tenant_member(devices.tenant_id))
      ) WITH CHECK (
        public.is_platform_admin()
        OR public.is_tenant_admin(devices.tenant_id)
        OR (devices.user_id = auth.uid()
            AND public.is_tenant_member(devices.tenant_id))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='devices'
                 AND policyname='devices_delete_admin') THEN
    CREATE POLICY "devices_delete_admin"
      ON public.devices FOR DELETE USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(devices.tenant_id)
      );
  END IF;

  -- device_sessions: users manage own; tenant admins revoke their tenant's; platform admins all.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='device_sessions'
                 AND policyname='device_sessions_select') THEN
    CREATE POLICY "device_sessions_select"
      ON public.device_sessions FOR SELECT USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(device_sessions.tenant_id)
        OR (device_sessions.user_id = auth.uid()
            AND public.is_tenant_member(device_sessions.tenant_id))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='device_sessions'
                 AND policyname='device_sessions_insert_own') THEN
    CREATE POLICY "device_sessions_insert_own"
      ON public.device_sessions FOR INSERT WITH CHECK (
        public.is_platform_admin()
        OR (device_sessions.user_id = auth.uid()
            AND public.is_tenant_member(device_sessions.tenant_id))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='device_sessions'
                 AND policyname='device_sessions_revoke') THEN
    CREATE POLICY "device_sessions_revoke"
      ON public.device_sessions FOR UPDATE USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(device_sessions.tenant_id)
        OR (device_sessions.user_id = auth.uid()
            AND public.is_tenant_member(device_sessions.tenant_id))
      ) WITH CHECK (
        public.is_platform_admin()
        OR public.is_tenant_admin(device_sessions.tenant_id)
        OR (device_sessions.user_id = auth.uid()
            AND public.is_tenant_member(device_sessions.tenant_id))
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='device_sessions'
                 AND policyname='device_sessions_delete_admin') THEN
    CREATE POLICY "device_sessions_delete_admin"
      ON public.device_sessions FOR DELETE USING (
        public.is_platform_admin()
        OR public.is_tenant_admin(device_sessions.tenant_id)
      );
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────
-- (c) revoke-only trigger: UPDATE may touch revoked_at, nothing else;
--     revocation is one-way (NULL → timestamp only).
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.device_sessions_revoke_only_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.id        IS DISTINCT FROM NEW.id
     OR OLD.device_id IS DISTINCT FROM NEW.device_id
     OR OLD.user_id   IS DISTINCT FROM NEW.user_id
     OR OLD.tenant_id IS DISTINCT FROM NEW.tenant_id
     OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION 'device_sessions: only revoked_at may be updated via client';
  END IF;
  IF OLD.revoked_at IS NOT NULL
     AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
    RAISE EXCEPTION 'device_sessions: revocation cannot be undone via client';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_device_sessions_revoke_only_guard
  ON public.device_sessions;
CREATE TRIGGER trg_device_sessions_revoke_only_guard
  BEFORE UPDATE ON public.device_sessions
  FOR EACH ROW EXECUTE FUNCTION public.device_sessions_revoke_only_guard();


-- ─────────────────────────────────────────────────────────────
-- (d) seed — release workflow owns this row afterwards
-- ─────────────────────────────────────────────────────────────

INSERT INTO public.platform_config
  (key, latest_version, minimum_supported_version, download_url,
   release_notes, release_notes_urdu)
VALUES
  ('default', '1.0.0', '1.0.0',
   'https://github.com/TalhaGoharWeb/Madrassa-360/releases',
   'Initial production release of Madrasa-360 for Windows.',
   'ونڈوز کے لیے مدرسہ 360 کی پہلی پروڈکشن ریلیز۔')
ON CONFLICT (key) DO NOTHING;


-- ─────────────────────────────────────────────────────────────
-- (e) documentation
-- ─────────────────────────────────────────────────────────────

COMMENT ON TABLE public.platform_config IS
  '018: release-train state for auto-update. SELECT is public (pre-login '
  'update check via anon key); writes are platform-admin only. Updated by '
  'the release workflow on every publish — see docs/WINDOWS_BUILD.md.';
COMMENT ON TABLE public.devices IS
  '018: per-install device registry. device_id is a client-generated UUID '
  'stored at %APPDATA%/Madrassa360/device.json — NOT a hardware fingerprint. '
  'Revocation is admin-initiated; users are never locked out by device binding.';
COMMENT ON TABLE public.device_sessions IS
  '018: per-login session rows. revoked_at = admin/user-initiated revoke; '
  'one-way via client (trigger-guarded). Live enforcement is a documented '
  'contract (auth hook / Edge Function), not implemented here.';
COMMENT ON FUNCTION public.device_sessions_revoke_only_guard() IS
  '018: UPDATE guard — only revoked_at may change, and only NULL → timestamp.';


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('018_platform_config') ON CONFLICT DO NOTHING;
