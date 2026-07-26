-- Agenda Autônoma — Fase 9: agenda o detector da Caixa de Entrada.
-- De hora em hora (a caixa é assíncrona por design; latência de até 1h é aceitável e
-- mantém o custo de LLM baixo). Mesmo padrão de segredo dos demais crons.
SELECT cron.schedule(
  'agenda-inbox-detector',
  '20 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/agenda-inbox-detector',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$
);
