-- Hardening de segurança (advisor rls_disabled do Supabase).
--
-- A tabela de backup public.products_stock_backup_pre_v2 (snapshot tirado antes
-- da migração de estoque v2, ~413 linhas) estava com RLS DESLIGADA — ou seja,
-- exposta às roles anon/authenticated: qualquer um com a anon key podia ler
-- (e escrever) todas as linhas.
--
-- Verificado antes de aplicar que NADA depende dela: nenhuma referência no
-- código (frontend/edge functions), nem em view/matview/função/trigger/FK.
-- Logo, ligar a RLS não quebra nenhum fluxo.
--
-- Liga a RLS e permite apenas LEITURA por admin (mesmo padrão do resto do
-- banco: public.is_admin(auth.uid())). Sem policies de escrita de propósito —
-- é um backup imutável; restauração, se necessária, é feita via SQL/service_role,
-- que ignora a RLS.
alter table public.products_stock_backup_pre_v2 enable row level security;

drop policy if exists "psbpv2_admin_select" on public.products_stock_backup_pre_v2;
create policy "psbpv2_admin_select" on public.products_stock_backup_pre_v2
  for select to authenticated using (public.is_admin(auth.uid()));
