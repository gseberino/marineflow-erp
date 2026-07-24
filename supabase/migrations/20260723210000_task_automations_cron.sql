-- Agenda & Tarefas 2.0 — Fase 2: agenda o motor de automações.
-- Mesmo padrão dos demais crons (segredo em app_settings.cron_worker_secret,
-- validado na function contra CRON_SECRET). cron.schedule com nome já existente
-- atualiza o job em vez de duplicar — seguro rodar de novo.
SELECT cron.schedule(
  'task-automations',
  '*/15 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/task-automations',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$
);
