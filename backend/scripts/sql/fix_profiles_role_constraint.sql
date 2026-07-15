-- Fix legacy role check constraint on public.profiles.
-- Safe to run multiple times.
-- Run in Supabase SQL Editor or via psql.

BEGIN;

-- 1) Normalize existing role values to the 4 business roles.
UPDATE public.profiles
SET role = CASE
  WHEN role IS NULL OR btrim(role) = '' THEN 'technicien'
  WHEN lower(btrim(role)) IN ('admin', 'administrateur', 'owner') THEN 'admin'
  WHEN lower(btrim(role)) IN ('gestionnaire_ferme', 'gestionnaire', 'manager', 'gestionnaire de ferme') THEN 'gestionnaire_ferme'
  WHEN lower(btrim(role)) IN ('commercial', 'vendeur', 'sales') THEN 'commercial'
  WHEN lower(btrim(role)) IN ('technicien', 'technique', 'technician', 'agent', 'utilisateur', 'user', 'viewer') THEN 'technicien'
  ELSE 'technicien'
END;

-- 2) Drop legacy role check constraints (dynamic, unknown names).
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'profiles'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%role%'
  LOOP
    EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS %I', c.conname);
  END LOOP;
END $$;

-- 3) Enforce the new role model.
ALTER TABLE public.profiles
  ALTER COLUMN role SET DEFAULT 'technicien';

ALTER TABLE public.profiles
  ALTER COLUMN role SET NOT NULL;

ALTER TABLE public.profiles
  ADD CONSTRAINT chk_profiles_role
  CHECK (role IN ('admin', 'gestionnaire_ferme', 'commercial', 'technicien'));

COMMIT;
