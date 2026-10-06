-- 10 · Agendamentos (pg_cron) e buckets do Storage
-- Gerado por scripts/snapshot-producao.mjs a partir dos catálogos do banco de produção.
-- NÃO editar à mão: regenerar. A data e as contagens ficam no README.md ao lado.

-- acompanhar-conversas · */15 * * * *
select cron.schedule('acompanhar-conversas', '*/15 * * * *', $cron$
    SELECT net.http_post(
      url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/acompanhar-conversas',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 120000
    );
    $cron$);

-- agenda-inbox-detector · 20 * * * * · INATIVO
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
update cron.job set active = false where jobname = 'agenda-inbox-detector';

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

-- ai-followup-runner · 15 * * * * · INATIVO
select cron.schedule('ai-followup-runner', '15 * * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-followup-runner',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$);
update cron.job set active = false where jobname = 'ai-followup-runner';

-- ai-gateway-relogio · * * * * *
select cron.schedule('ai-gateway-relogio', '* * * * *', $cron$select public._ai_gateway_reap()$cron$);

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

-- banking-sync-daily · 0 9,18 * * *
select cron.schedule('banking-sync-daily', '0 9,18 * * *', $cron$
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

-- finance-review-generate · 10 9,18 * * *
select cron.schedule('finance-review-generate', '10 9,18 * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/finance-review',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{"action": "generate"}'::jsonb,
    timeout_milliseconds := 120000
  );
  $cron$);

-- finance-vigilante · 30 9 * * *
select cron.schedule('finance-vigilante', '30 9 * * *', $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/finance-review',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{"action": "vigiar"}'::jsonb,
    timeout_milliseconds := 60000
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

-- separar-pro-labore · 20 9,18 * * *
select cron.schedule('separar-pro-labore', '20 9,18 * * *', $cron$select public.separar_pro_labore()$cron$);

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

-- whatsapp-conexao-vigia · */5 * * * *
select cron.schedule('whatsapp-conexao-vigia', '*/5 * * * *', $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-conexao',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
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

-- whatsapp-repescar-audios · 10 4 * * *
select cron.schedule('whatsapp-repescar-audios', '10 4 * * *', $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-repescar-audios',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 180000
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
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('documents', 'documents', false, 26214400, '{application/pdf}') on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('email-attachments', 'email-attachments', false, 26214400, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('expense-receipts', 'expense-receipts', false, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('fiscal-xml', 'fiscal-xml', false, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('pdf-agente', 'pdf-agente', false, 26214400, '{application/pdf}') on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('product-images', 'product-images', true, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('service-order-photos', 'service-order-photos', false, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('signatures', 'signatures', false, null, null) on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('whatsapp_status', 'whatsapp_status', true, 52428800, null) on conflict (id) do nothing;
