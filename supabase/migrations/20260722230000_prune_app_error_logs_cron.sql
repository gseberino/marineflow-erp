-- Expurgo diário do registro de erros: a tabela app_error_logs cresceria sem
-- limite (mesmo agrupando por fingerprint, erros novos abrem linhas novas). A
-- função prune_app_error_logs(90) já existia mas nunca era chamada; agenda ela
-- às 04:10 (horário do servidor) para remover episódios com mais de 90 dias.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('prune-app-error-logs')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'prune-app-error-logs');
    PERFORM cron.schedule(
      'prune-app-error-logs', '10 4 * * *',
      $cmd$ SELECT public.prune_app_error_logs(90); $cmd$
    );
  END IF;
END $$;
