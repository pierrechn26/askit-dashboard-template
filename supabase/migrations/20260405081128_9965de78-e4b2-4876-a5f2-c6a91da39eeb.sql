-- Add weekly_trends_refresh column to market_intelligence
ALTER TABLE public.market_intelligence 
ADD COLUMN IF NOT EXISTS weekly_trends_refresh jsonb DEFAULT NULL;

-- Conditional unschedule: job may not exist on a fresh database
DO $$ BEGIN
  PERFORM cron.unschedule('weekly-recommendations-monday');
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Cron job weekly-recommendations-monday not found, skipping';
END $$;

-- NEUTRALIZED: cron.schedule commented out because it hardcodes the template
-- project_ref (btkjdqelvvqmtguhhkdv). Crons must be created per-tenant via
-- a dedicated idempotent migration with dynamic URL resolution.
-- See: docs/RUNBOOK_ONBOARDING_CLIENT.md §4