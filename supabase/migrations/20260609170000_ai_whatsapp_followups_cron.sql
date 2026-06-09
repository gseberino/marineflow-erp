-- Schedule ai-whatsapp-followups every 30 minutes.
-- Processes pending ai_agent_tasks with task_type whatsapp_followup/quote_followup/satisfaction_followup.

DO $$
BEGIN
  PERFORM cron.unschedule('ai-whatsapp-followups');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'ai-whatsapp-followups',
  '*/30 * * * *',
  $cmd$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-whatsapp-followups',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $cmd$
);
