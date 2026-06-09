-- ai_daily_briefings: one record per day with the morning intelligence briefing.
-- Generated at 7:30am BRT by the ai-daily-briefing cron function.

CREATE TABLE IF NOT EXISTS public.ai_daily_briefings (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  date            date        NOT NULL UNIQUE,
  summary_text    text        NOT NULL,
  critical_count  integer     NOT NULL DEFAULT 0,
  warning_count   integer     NOT NULL DEFAULT 0,
  tasks_due_count integer     NOT NULL DEFAULT 0,
  agenda_count    integer     NOT NULL DEFAULT 0,
  sections        jsonb       NOT NULL DEFAULT '{}',
  generated_at    timestamptz NOT NULL DEFAULT now(),
  whatsapp_sent   boolean     NOT NULL DEFAULT false,
  whatsapp_sent_at timestamptz
);

ALTER TABLE public.ai_daily_briefings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_briefings_read"
  ON public.ai_daily_briefings
  FOR SELECT
  TO authenticated
  USING (private.ai_op_is_active(auth.uid()));

-- Schedule daily briefing at 10:30 UTC = 07:30 BRT
DO $$
BEGIN
  PERFORM cron.unschedule('ai-daily-briefing');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'ai-daily-briefing',
  '30 10 * * *',
  $cmd$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-daily-briefing',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cmd$
);
