-- ============================================================
-- Dynamic cron jobs via Vault-backed wrapper
-- No hardcoded project_ref or anon key.
--
-- Prerequisites (per-client, at provisioning time):
--   SELECT vault.create_secret('<BASE_URL>', 'project_base_url', '...');
--   SELECT vault.create_secret('<ANON_KEY>', 'project_anon_key', '...');
--
-- TODO: mark-stale-sessions-as-abandoned — logique inexistante dans le repo.
-- Pas de cron créé. À implémenter : edge function ou SQL direct qui UPDATE
-- diagnostic_sessions SET status='abandonne', exit_type='abandon'
-- WHERE status='en_cours' AND updated_at < NOW() - INTERVAL '24 hours'.
-- ============================================================

-- 1. Wrapper function: reads URL + key from Vault at execution time
CREATE OR REPLACE FUNCTION public.call_edge_function(fn_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  base_url text;
  anon_key text;
BEGIN
  SELECT decrypted_secret INTO base_url
  FROM vault.decrypted_secrets WHERE name = 'project_base_url' LIMIT 1;

  SELECT decrypted_secret INTO anon_key
  FROM vault.decrypted_secrets WHERE name = 'project_anon_key' LIMIT 1;

  IF base_url IS NULL OR anon_key IS NULL THEN
    RAISE WARNING '[call_edge_function] Vault secrets project_base_url/project_anon_key not set — skipping %', fn_name;
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := base_url || '/functions/v1/' || fn_name,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || anon_key
    ),
    body := '{"source": "cron"}'::jsonb
  );
END;
$$;

-- 2. Unschedule any existing jobs (idempotent)
DO $$ BEGIN PERFORM cron.unschedule('detect-persona-clusters-daily');   EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN PERFORM cron.unschedule('aski-daily-learn');                EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN PERFORM cron.unschedule('monthly-market-intelligence');     EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN PERFORM cron.unschedule('weekly-intelligence-refresh');     EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN PERFORM cron.unschedule('scrape-commercial-facts-weekly');  EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- 3. Schedule 5 crons
SELECT cron.schedule('detect-persona-clusters-daily',  '0 3 * * *',   $$ SELECT public.call_edge_function('detect-persona-clusters') $$);
SELECT cron.schedule('aski-daily-learn',               '0 4 * * *',   $$ SELECT public.call_edge_function('aski-daily-learn') $$);
SELECT cron.schedule('monthly-market-intelligence',    '0 8 1 * *',   $$ SELECT public.call_edge_function('monthly-market-intelligence') $$);
SELECT cron.schedule('weekly-intelligence-refresh',    '0 7 * * 1',   $$ SELECT public.call_edge_function('weekly-intelligence-refresh') $$);
SELECT cron.schedule('scrape-commercial-facts-weekly', '0 8 * * 1',   $$ SELECT public.call_edge_function('scrape-commercial-facts') $$);
