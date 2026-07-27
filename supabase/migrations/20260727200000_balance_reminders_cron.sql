-- Cron diário da RÉGUA INTERNA de cobrança do saldo (balance-reminders).
-- 08:30 BRT (11:30 UTC), logo depois do resumo matinal. Interno: avisa o gestor sobre saldos que
-- cruzaram marcos de atraso (venceu ontem / 7 / 30 dias). Não envia nada ao cliente.
SELECT cron.unschedule('balance-reminders-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'balance-reminders-daily');

SELECT cron.schedule('balance-reminders-daily', '30 11 * * *', $cmd$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/balance-reminders',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
$cmd$);
