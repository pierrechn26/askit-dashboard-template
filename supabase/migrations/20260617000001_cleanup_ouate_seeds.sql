-- Clean up Ouate-specific seed data from the template.
-- client_plan must be inserted per-client at provisioning (Phase D).
-- marketing_sources are global (shared across all tenants) — project_id set to NULL.

-- 1. Remove Ouate client_plan seed
DELETE FROM public.client_plan WHERE project_id = 'ouate';

-- 2. Drop NOT NULL constraint BEFORE setting values to NULL
ALTER TABLE public.marketing_sources ALTER COLUMN project_id DROP NOT NULL;
ALTER TABLE public.marketing_sources ALTER COLUMN project_id SET DEFAULT NULL;

-- 3. Neutralize project_id on marketing_sources (global sources, not tenant-specific)
UPDATE public.marketing_sources SET project_id = NULL WHERE project_id = 'ouate';

-- 4. Same for market_intelligence (written per-tenant with explicit project_id,
-- but DEFAULT should not be 'ouate' — no insert relies on the default)
ALTER TABLE public.market_intelligence ALTER COLUMN project_id SET DEFAULT NULL;
