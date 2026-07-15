-- Ensure profiles.permissions exists and is consistently usable by RBAC.
-- Safe to run multiple times.

BEGIN;

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS permissions jsonb;

ALTER TABLE public.profiles
ALTER COLUMN permissions SET DEFAULT '[]'::jsonb;

UPDATE public.profiles
SET permissions = '[]'::jsonb
WHERE permissions IS NULL;

ALTER TABLE public.profiles
ALTER COLUMN permissions SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_permissions_gin
ON public.profiles
USING gin (permissions);

COMMIT;
