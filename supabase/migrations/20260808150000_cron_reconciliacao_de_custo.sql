-- Agenda a reconciliação de custo com o OpenRouter.
--
-- De hora em hora, aos 40 minutos: fora dos minutos onde já se concentram outros crons
-- (00, 05, 15, 20, 30) para não disputar worker com eles.
--
-- Cadência horária é deliberada — o OpenRouter não guarda a geração indefinidamente, então
-- perguntar perto do fato é o que garante resposta. Um cron diário perderia parte das linhas.

select cron.unschedule('ai-cost-reconcile')
where exists (select 1 from cron.job where jobname = 'ai-cost-reconcile');

select cron.schedule(
  'ai-cost-reconcile',
  '40 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-cost-reconcile',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
  $$
);
