-- Busca automática do extrato, duas vezes por dia.
--
-- Frequência: o conector gratuito do Pluggy (MeuPluggy) atualiza os dados uma vez ao dia,
-- então buscar de hora em hora só gastaria chamada sem trazer novidade. Duas passadas —
-- de manhã cedo e no fim da tarde — cobrem o dia útil e dão margem para o banco publicar
-- lançamentos com atraso.
--
-- Roda ANTES do briefing das 07:30 (que aqui é 10:30 UTC) de propósito: assim o resumo da
-- manhã já comenta as entradas que chegaram durante a noite.

SELECT cron.unschedule('banking-sync-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'banking-sync-daily');

SELECT cron.schedule(
  'banking-sync-daily',
  '0 9,21 * * *',  -- 06:00 e 18:00 no horário de Brasília
  $$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/banking-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $$
);
