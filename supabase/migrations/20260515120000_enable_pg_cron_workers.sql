-- Enable pg_cron and pg_net for scheduled Edge Function invocations
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Schedule whatsapp-status-worker every minute (posts pending WhatsApp Status/Stories)
SELECT cron.schedule(
  'whatsapp-status-worker',
  '* * * * *',
  $$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-status-worker',
    headers    := '{"Content-Type": "application/json"}'::jsonb,
    body       := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
  $$
);

-- Schedule whatsapp-queue-worker every minute (sends queued WhatsApp messages)
-- Only added if not already scheduled via the Supabase dashboard.
SELECT cron.schedule(
  'whatsapp-queue-worker',
  '* * * * *',
  $$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-queue-worker',
    headers    := '{"Content-Type": "application/json"}'::jsonb,
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $$
);
