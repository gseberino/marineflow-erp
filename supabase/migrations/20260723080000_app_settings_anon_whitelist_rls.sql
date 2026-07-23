-- S1/A1+A2 do plano de otimização (22/07/2026):
-- (1) vw_os_profitability respeita permissões do consultante (advisor ERROR security_definer_view).
-- (2) app_settings: leitura anônima passa de "tabela inteira" (3 policies always-true) para
--     whitelist de chaves de exibição pública; cron_worker_secret fica invisível também para
--     authenticated (service_role de crons/functions não passa por RLS).
-- Rollback: recriar as policies antigas (authenticated ALL true + anon SELECT true) e
--           alter view ... set (security_invoker = off).

alter view public.vw_os_profitability set (security_invoker = on);

drop policy if exists "anon_read_app_settings" on public.app_settings;
drop policy if exists "anon_app_settings_select" on public.app_settings;
drop policy if exists "Public company settings viewing" on public.app_settings;

create policy "anon_public_settings_whitelist" on public.app_settings
  for select to anon
  using (
    key like 'public_view_%' or key in (
      'company_name','company_logo_url','company_address','company_city','company_state',
      'company_neighborhood','company_postal_code','company_country',
      'address_line_1','address_number','neighborhood','city','postal_code',
      'phone','email','cnpj','pix_key','bank_name','bank_agency','bank_account',
      'app_public_url','base_currency','display_currency','language','card_fee_percent'
    )
  );

drop policy if exists "authenticated_full_access" on public.app_settings;

create policy "app_settings_auth_select" on public.app_settings
  for select to authenticated using (key <> 'cron_worker_secret');
create policy "app_settings_auth_insert" on public.app_settings
  for insert to authenticated with check (key <> 'cron_worker_secret');
create policy "app_settings_auth_update" on public.app_settings
  for update to authenticated using (key <> 'cron_worker_secret') with check (key <> 'cron_worker_secret');
create policy "app_settings_auth_delete" on public.app_settings
  for delete to authenticated using (key <> 'cron_worker_secret');
