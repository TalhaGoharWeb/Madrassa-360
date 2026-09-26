-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 017: offline-first notifications (server)
-- Phase 6 / Worker 2 (notifications framework)
--
-- Run AFTER 001–016. Adds the server-side half of the notifications
-- framework:
--
--   notifications
--     id          UUID PK (client-generated v4 UUID — the SAME id the app
--                   creates offline in SQLite; the send-notification Edge
--                   Function upserts on it, so retries are idempotent).
--     tenant_id   UUID NOT NULL → tenants(id) ON DELETE CASCADE.
--     user_id     UUID NULL → auth.users(id) ON DELETE CASCADE.
--                   NULL = tenant broadcast (visible to every member).
--     type        TEXT — 'fee_invoice_created' | 'payment_received' |
--                   'result_published' | 'announcement_posted' |
--                   'backup_completed' | … (open set; see the client
--                   NotificationType constants).
--     title / title_urdu / body / body_urdu — Urdu-first content; the
--                   *_urdu column wins on ur-PK clients.
--     data        JSONB — deep-link payload
--                   (e.g. {"invoice_id": "...", "route": "/fees/invoices"}).
--     channel     TEXT — which channel fanned this row out server-side
--                   ('in_app' | 'push' | 'email'; future: 'sms','whatsapp').
--     read_at     TIMESTAMPTZ NULL — targeted rows: set by the owning user
--                   only. Broadcast rows (user_id IS NULL): frozen
--                   server-side — read state for broadcasts is local-only
--                   on each device (no sync path for this table).
--     created_at  TIMESTAMPTZ.
--
--   notification_preferences
--     Per-user, per-tenant, per-channel opt-out. PK (user_id, tenant_id,
--     channel). Absence of a row = channel ENABLED (default-on; the app
--     treats "no row" as enabled so fresh users get everything).
--
--   notification_device_tokens
--     FCM registration tokens for push fan-out, one row per (user, token).
--     Written by the app (RLS: own tokens only); read by the
--     send-notification Edge Function via the service role.
--
-- ── DESIGN NOTES ────────────────────────────────────────────────
-- * These tables are INTENTIONALLY outside the 016 sync_apply contract:
--   notifications are append-only, server-fanned-out events, not
--   optimistic-concurrency business rows. The app records them locally in
--   SQLite (offline-first) and the NotificationDispatcher fans them out
--   through the `send-notification` Edge Function when online — never
--   through sync_apply (whose entity whitelist is unchanged).
-- * Client INSERT is restricted: apps create notifications through the
--   Edge Function (service role, membership-checked in code). Direct
--   INSERT is platform-admin only, so a compromised client token cannot
--   spam a tenant's broadcasts.
-- * UPDATE is guarded twice: RLS limits it to rows visible to the caller,
--   and the trg_notifications_read_only_guard trigger rejects any UPDATE
--   that touches a column other than read_at (prevents privilege/content
--   tampering through the read-receipt path).
-- * RLS uses the 004 helpers public.is_platform_admin() /
--   public.is_tenant_member(UUID) — no new helpers, no legacy DROPs
--   (these tables are new in 017; nothing pre-exists to drop).
--
-- Idempotent: CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS /
-- pg_policies existence guards / CREATE OR REPLACE trigger function /
-- schema_migrations ON CONFLICT DO NOTHING.
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- (a) tables
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.notifications (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id    UUID        REFERENCES auth.users(id) ON DELETE CASCADE,
  type       TEXT        NOT NULL,
  title      TEXT        NOT NULL,
  title_urdu TEXT,
  body       TEXT,
  body_urdu  TEXT,
  data       JSONB       NOT NULL DEFAULT '{}'::jsonb,
  channel    TEXT        NOT NULL DEFAULT 'in_app',
  read_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT notifications_title_not_empty CHECK (char_length(title) > 0)
);

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id  UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  channel    TEXT        NOT NULL,
  enabled    BOOLEAN     NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, tenant_id, channel),
  CONSTRAINT notification_preferences_channel_not_empty
    CHECK (char_length(channel) > 0)
);

CREATE TABLE IF NOT EXISTS public.notification_device_tokens (
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id  UUID        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  token      TEXT        NOT NULL,
  platform   TEXT        NOT NULL DEFAULT 'android',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, token),
  CONSTRAINT notification_device_tokens_token_not_empty
    CHECK (char_length(token) > 0),
  CONSTRAINT notification_device_tokens_platform_known
    CHECK (platform IN ('android', 'ios', 'macos', 'web'))
);


-- ─────────────────────────────────────────────────────────────
-- (b) indexes
-- ─────────────────────────────────────────────────────────────

-- Required: (tenant_id, user_id, created_at) — the hot read path
-- (a user's inbox / tenant broadcasts, newest first).
CREATE INDEX IF NOT EXISTS idx_notifications_tenant_user_created
  ON public.notifications (tenant_id, user_id, created_at DESC);

-- Unread badge counts without scanning read rows.
CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON public.notifications (tenant_id, user_id)
  WHERE read_at IS NULL;

-- Type-filtered queries (e.g. "all fee notifications").
CREATE INDEX IF NOT EXISTS idx_notifications_tenant_type
  ON public.notifications (tenant_id, type);

CREATE INDEX IF NOT EXISTS idx_notification_device_tokens_lookup
  ON public.notification_device_tokens (tenant_id, user_id);

CREATE INDEX IF NOT EXISTS idx_notification_preferences_lookup
  ON public.notification_preferences (tenant_id, user_id);


-- ─────────────────────────────────────────────────────────────
-- (c) read-receipt guard: only read_at may change via UPDATE
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notifications_read_only_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.id         IS DISTINCT FROM NEW.id         OR
     OLD.tenant_id  IS DISTINCT FROM NEW.tenant_id  OR
     OLD.user_id    IS DISTINCT FROM NEW.user_id    OR
     OLD.type       IS DISTINCT FROM NEW.type       OR
     OLD.title      IS DISTINCT FROM NEW.title      OR
     OLD.title_urdu IS DISTINCT FROM NEW.title_urdu OR
     OLD.body       IS DISTINCT FROM NEW.body       OR
     OLD.body_urdu  IS DISTINCT FROM NEW.body_urdu  OR
     OLD.data       IS DISTINCT FROM NEW.data       OR
     OLD.channel    IS DISTINCT FROM NEW.channel    OR
     OLD.created_at IS DISTINCT FROM NEW.created_at THEN
    RAISE EXCEPTION
      'notifications: only read_at may be updated (read receipts)';
  END IF;
  -- Broadcast rows (user_id IS NULL) are shared by the whole tenant: one
  -- member must not be able to mark them read for everyone. Broadcast read
  -- state is local-only on each device (the notifications table has no
  -- sync path — read_at never travels upstream), so freeze it server-side.
  IF OLD.user_id IS NULL AND
     NEW.read_at IS DISTINCT FROM OLD.read_at THEN
    RAISE EXCEPTION
      'notifications: broadcast read state is local-only (user_id IS NULL)';
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_notifications_read_only_guard'
                    AND tgrelid = 'public.notifications'::regclass) THEN
    CREATE TRIGGER trg_notifications_read_only_guard
      BEFORE UPDATE ON public.notifications
      FOR EACH ROW EXECUTE FUNCTION public.notifications_read_only_guard();
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────
-- (d) RLS — tenant-scoped, membership-checked
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.notifications              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_device_tokens ENABLE ROW LEVEL SECURITY;

-- ── notifications ──
DO $$
BEGIN
  -- Users see their own notifications + tenant broadcasts (user_id NULL).
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='notifications'
                 AND policyname='notifications_select_tenant') THEN
    CREATE POLICY "notifications_select_tenant" ON public.notifications
      FOR SELECT USING (
        public.is_platform_admin()
        OR (public.is_tenant_member(notifications.tenant_id)
            AND (notifications.user_id IS NULL
                 OR notifications.user_id = auth.uid()))
      );
  END IF;

  -- Direct INSERT is platform-admin only. Apps fan out through the
  -- send-notification Edge Function (service role, membership-checked).
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='notifications'
                 AND policyname='notifications_insert_admin') THEN
    CREATE POLICY "notifications_insert_admin" ON public.notifications
      FOR INSERT WITH CHECK (public.is_platform_admin());
  END IF;

  -- Read receipts: users may UPDATE rows they can see (the trigger above
  -- restricts the write to read_at); admins unrestricted.
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='notifications'
                 AND policyname='notifications_update_read_own') THEN
    CREATE POLICY "notifications_update_read_own" ON public.notifications
      FOR UPDATE USING (
        public.is_platform_admin()
        OR (public.is_tenant_member(notifications.tenant_id)
            AND (notifications.user_id IS NULL
                 OR notifications.user_id = auth.uid()))
      ) WITH CHECK (
        public.is_platform_admin()
        OR (public.is_tenant_member(notifications.tenant_id)
            AND (notifications.user_id IS NULL
                 OR notifications.user_id = auth.uid()))
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='notifications'
                 AND policyname='notifications_delete_admin') THEN
    CREATE POLICY "notifications_delete_admin" ON public.notifications
      FOR DELETE USING (public.is_platform_admin());
  END IF;
END $$;

-- ── notification_preferences ──
-- Users manage ONLY their own rows; platform admins manage all.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='notification_preferences'
                 AND policyname='notification_preferences_select_own') THEN
    CREATE POLICY "notification_preferences_select_own"
      ON public.notification_preferences FOR SELECT USING (
        public.is_platform_admin()
        OR (public.is_tenant_member(notification_preferences.tenant_id)
            AND notification_preferences.user_id = auth.uid())
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='notification_preferences'
                 AND policyname='notification_preferences_write_own') THEN
    CREATE POLICY "notification_preferences_write_own"
      ON public.notification_preferences FOR ALL USING (
        public.is_platform_admin()
        OR (public.is_tenant_member(notification_preferences.tenant_id)
            AND notification_preferences.user_id = auth.uid())
      ) WITH CHECK (
        public.is_platform_admin()
        OR (public.is_tenant_member(notification_preferences.tenant_id)
            AND notification_preferences.user_id = auth.uid())
      );
  END IF;
END $$;

-- ── notification_device_tokens ──
-- Users manage ONLY their own tokens; platform admins manage all.
-- (The send-notification Edge Function reads via the service role.)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='notification_device_tokens'
                 AND policyname='notification_device_tokens_select_own') THEN
    CREATE POLICY "notification_device_tokens_select_own"
      ON public.notification_device_tokens FOR SELECT USING (
        public.is_platform_admin()
        OR (public.is_tenant_member(notification_device_tokens.tenant_id)
            AND notification_device_tokens.user_id = auth.uid())
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='notification_device_tokens'
                 AND policyname='notification_device_tokens_write_own') THEN
    CREATE POLICY "notification_device_tokens_write_own"
      ON public.notification_device_tokens FOR ALL USING (
        public.is_platform_admin()
        OR (public.is_tenant_member(notification_device_tokens.tenant_id)
            AND notification_device_tokens.user_id = auth.uid())
      ) WITH CHECK (
        public.is_platform_admin()
        OR (public.is_tenant_member(notification_device_tokens.tenant_id)
            AND notification_device_tokens.user_id = auth.uid())
      );
  END IF;
END $$;


-- ─────────────────────────────────────────────────────────────
-- (e) documentation
-- ─────────────────────────────────────────────────────────────

COMMENT ON TABLE public.notifications IS
  '017: offline-first notification records. user_id NULL = tenant broadcast. '
  'Server fan-out goes through the send-notification Edge Function; direct '
  'client INSERT is platform-admin only. Outside the 016 sync_apply contract.';
COMMENT ON TABLE public.notification_preferences IS
  '017: per-user per-tenant per-channel opt-out. Missing row = enabled.';
COMMENT ON TABLE public.notification_device_tokens IS
  '017: FCM registration tokens for push fan-out. Written by the app (own '
  'tokens only), read by the send-notification Edge Function (service role).';
COMMENT ON FUNCTION public.notifications_read_only_guard() IS
  '017: UPDATE guard — only read_at may change on notifications rows.';


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('017_notifications') ON CONFLICT DO NOTHING;
