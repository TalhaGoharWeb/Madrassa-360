-- 026_repair_profiles_columns.sql
--
-- The public.profiles table was created outside migrations and is missing
-- columns the app reads (auth_repository.dart: phone, photo_url, madrasa_id).
-- The demo seed (demo/seed_demo_madrassa.sql) also inserts phone.
-- This migration adds them idempotently.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS phone      TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS photo_url  TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS madrasa_id UUID REFERENCES public.tenants(id) ON DELETE SET NULL;
