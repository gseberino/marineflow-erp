-- Enable pg_cron and pg_net for scheduled Edge Function invocations
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Schedule whatsapp-status-worker every minute.
-- Uses idempotent DO block; skips if job already exists.
-- The x-cron-secret header is populated at runtime from app_settings
-- so the secret is never stored in the cron.job command column.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'whatsapp-status-worker') THEN
    PERFORM cron.schedule(
      'whatsapp-status-worker',
      '* * * * *',
      $cmd$
      SELECT net.http_post(
        url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-status-worker',
        headers    := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
        ),
        body       := '{}'::jsonb,
        timeout_milliseconds := 25000
      );
      $cmd$
    );
  END IF;
END
$$;

-- Schedule whatsapp-queue-worker every minute.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'whatsapp-queue-worker') THEN
    PERFORM cron.schedule(
      'whatsapp-queue-worker',
      '* * * * *',
      $cmd$
      SELECT net.http_post(
        url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-queue-worker',
        headers    := jsonb_build_object(
          'Content-Type',  'application/json',
          'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
        ),
        body       := '{}'::jsonb,
        timeout_milliseconds := 55000
      );
      $cmd$
    );
  END IF;
END
$$;
