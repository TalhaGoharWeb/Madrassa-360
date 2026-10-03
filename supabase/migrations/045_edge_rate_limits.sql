-- ═══════════════════════════════════════════════════════════════
-- Madrasa-360 SaaS — Migration 045: edge_rate_limits table
--
-- RED-TEAM RT-03: supabase/functions/_shared/guard.ts ships a
-- fixed-window rate limiter (rateLimit()) whose backing table was NEVER
-- created — every rate-limit check failed open with a server-side log
-- line, so send-notification's broadcast/targeted limits (and any
-- future callers) enforced nothing. This migration creates the table
-- exactly as guard.ts documents it.
--
-- Design notes:
--   * Service-role only: RLS is enabled with NO policies (service role
--     bypasses RLS; anon/authenticated get zero access).
--   * Rows are event-log entries; guard.ts opportunistically deletes
--     rows older than 2× the calling window (~5% of calls). A scheduled
--     cleanup (pg_cron / scheduled function) is recommended for
--     long-term hygiene but not required for correctness.
--   * Idempotent: CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT
--     EXISTS / ledger ON CONFLICT DO NOTHING.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.edge_rate_limits (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bucket_key TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_edge_rate_limits_key_time
  ON public.edge_rate_limits (bucket_key, created_at);

ALTER TABLE public.edge_rate_limits ENABLE ROW LEVEL SECURITY;

-- Intentionally no policies: service-role-only table.
-- (Service role bypasses RLS; anon/authenticated roles see nothing.)

COMMENT ON TABLE public.edge_rate_limits IS
  '045: fixed-window rate-limit event log for Edge Functions '
  '(guard.ts rateLimit()). Service-role only; RLS enabled with no policies.';


-- ── ledger ───────────────────────────────────────────────────
INSERT INTO public.schema_migrations(version) VALUES ('045_edge_rate_limits')
ON CONFLICT DO NOTHING;
