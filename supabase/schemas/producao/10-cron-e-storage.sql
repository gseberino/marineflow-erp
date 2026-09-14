-- 10 · Agendamentos (pg_cron) e buckets do Storage
-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.
-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.

-- agenda-inbox-detector · 20 * * * *
select cron.schedule('agenda-inbox-detector', '20 * * * *', $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/agenda-inbox-detector',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- ai-business-monitor · 5 * * * *
select cron.schedule('ai-business-monitor', '5 * * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-business-monitor',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- ai-cost-reconcile · 40 * * * *
select cron.schedule('ai-cost-reconcile', '40 * * * *', $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-cost-reconcile',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
  $cron$);

-- ai-daily-briefing · 30 10 * * *
select cron.schedule('ai-daily-briefing', '30 10 * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-daily-briefing',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- ai-whatsapp-followups · */30 * * * *
select cron.schedule('ai-whatsapp-followups', '*/30 * * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-whatsapp-followups',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $cron$);

-- archive-fiscal-drafts · 20 4 * * *
select cron.schedule('archive-fiscal-drafts', '20 4 * * *', $cron$select public.archive_old_fiscal_drafts(30);$cron$);

-- balance-reminders-daily · 30 11 * * *
select cron.schedule('balance-reminders-daily', '30 11 * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/balance-reminders',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
$cron$);

-- banking-sync-daily · 0 9,21 * * *
select cron.schedule('banking-sync-daily', '0 9,21 * * *', $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/banking-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- expire-pending-actions · */15 * * * *
select cron.schedule('expire-pending-actions', '*/15 * * * *', $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/expire-pending-actions',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
  $cron$);

-- fiscal-reconcile · */15 * * * *
select cron.schedule('fiscal-reconcile', '*/15 * * * *', $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/fiscal-reconcile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- prune-app-error-logs · 10 4 * * *
select cron.schedule('prune-app-error-logs', '10 4 * * *', $cron$ SELECT public.prune_app_error_logs(90); $cron$);

-- purge-cron-history · 45 4 * * *
select cron.schedule('purge-cron-history', '45 4 * * *', $cron$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$cron$);

-- purge-pgnet-responses · 50 4 * * 0
select cron.schedule('purge-pgnet-responses', '50 4 * * 0', $cron$TRUNCATE net._http_response$cron$);

-- quote-reminders · 0 12 * * *
select cron.schedule('quote-reminders', '0 12 * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/quote-reminders',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- receivable-reminders-daily · 0 11 * * *
select cron.schedule('receivable-reminders-daily', '0 11 * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/receivable-reminders',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- task-automations · */15 * * * *
select cron.schedule('task-automations', '*/15 * * * *', $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/task-automations',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- whatsapp-process-scheduled · */5 * * * *
select cron.schedule('whatsapp-process-scheduled', '*/5 * * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-process-scheduled',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- whatsapp-queue-worker · */5 * * * *
select cron.schedule('whatsapp-queue-worker', '*/5 * * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-queue-worker',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$);

-- whatsapp-status-worker · */5 * * * *
select cron.schedule('whatsapp-status-worker', '*/5 * * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-status-worker',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 25000
  );
  $cron$);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('company-assets', 'company-assets', true, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('documents', 'documents', true, 26214400, '{application/pdf}') on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('expense-receipts', 'expense-receipts', true, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('fiscal-xml', 'fiscal-xml', false, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('product-images', 'product-images', true, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('service-order-photos', 'service-order-photos', true, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('signatures', 'signatures', true, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('whatsapp_status', 'whatsapp_status', true, 52428800, null) on conflict (id) do nothing;
