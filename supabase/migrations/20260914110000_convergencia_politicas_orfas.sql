-- Convergência repositório ↔ produção, parte 1 (MF-AUD-058 / MF-AUD-022), decisão nº 8.
--
-- O histórico de migrations não reconstruía a produção: 179 versões aplicadas sem arquivo e
-- 111 arquivos aplicados sem registro. A reconciliação de 14/09/2026
-- (audit/migrations-reconciliacao-20260914.md) fez três coisas: snapshot fiel do banco em
-- supabase/schemas/producao/, registro das versões aplicadas (20260914100000) e um arquivo
-- para cada versão sem arquivo (20 recuperados dos transcripts das sessões, o resto stubs).
--
-- Esta migration fecha a deriva de POLÍTICAS: os arquivos do repo criam 24 políticas que a
-- produção não tem mais — foram derrubadas por migrations perdidas (a mais importante,
-- 20260706165104_remove_remaining_open_anon_policies) e são as allow-all da era Lovable.
-- Numa build do zero elas voltariam a existir por cima das políticas por cargo.
-- `drop policy if exists`: no-op em produção, convergência no repositório.
-- (A parte 2, funções executáveis por anon, é a 20260914120000_fecha_funcoes_para_anon.)

drop policy if exists "Authenticated users can do everything on app_users" on public.app_users;
drop policy if exists "Authenticated users can do everything on marinas" on public.marinas;
drop policy if exists "Authenticated users can do everything on clients" on public.clients;
drop policy if exists "Authenticated users can do everything on vessels" on public.vessels;
drop policy if exists "Authenticated users can do everything on products" on public.products;
drop policy if exists "Authenticated users can do everything on service_orders" on public.service_orders;
drop policy if exists "Authenticated users can do everything on service_order_technicians" on public.service_order_technicians;
drop policy if exists "Authenticated users can do everything on service_order_parts" on public.service_order_parts;
drop policy if exists "Authenticated users can do everything on time_entries" on public.time_entries;
drop policy if exists "Authenticated users can do everything on inventory_movements" on public.inventory_movements;
drop policy if exists "Authenticated users can do everything on invoices" on public.invoices;
drop policy if exists "Authenticated users can do everything on receivables" on public.receivables;
drop policy if exists "Authenticated users can do everything on payables" on public.payables;
drop policy if exists "Authenticated users can do everything on exchange_rates" on public.exchange_rates;
drop policy if exists "Authenticated users can do everything on app_settings" on public.app_settings;
drop policy if exists "allow_all_suppliers" on public.suppliers;
drop policy if exists "allow_all_product_suppliers" on public.product_suppliers;
drop policy if exists "app_users_select_auth" on public.app_users;
drop policy if exists "app_users_insert_admin" on public.app_users;
drop policy if exists "app_users_update_admin" on public.app_users;
drop policy if exists "app_users_delete_admin" on public.app_users;
drop policy if exists "authenticated_all_agenda_tasks" on public.agenda_tasks;
drop policy if exists "auth_all_po" on public.purchase_orders;
drop policy if exists "auth_all_poi" on public.purchase_order_items;

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260914110000', 'convergencia_politicas_orfas')
on conflict (version) do nothing;
