-- Advisor multiple_permissive_policies (19/09/2026): 6 tabelas tinham DUAS policies
-- permissivas idênticas para o mesmo comando e papel (uma com nome legado em inglês, outra
-- com o nome padronizado). Duas policies iguais custam o dobro por linha e não mudam nada.
-- Fica a de nome padronizado; a expressão é a mesma (conferido em pg_policies antes do drop).
--
-- Também fecha o resto do auth_rls_initplan: as 4 policies de quote_request_supplier_terms
-- (criadas hoje) passam a avaliar auth.uid() uma vez por consulta, como as outras 229.

drop policy if exists "Admins can do everything on commissions" on public.commissions;         -- fica commissions_admin_all
drop policy if exists "Users can view own commissions" on public.commissions;                  -- fica commissions_self_select
drop policy if exists "Enable read/write for all authenticated users" on public.cost_centers;  -- fica cost_centers_all_authenticated
drop policy if exists "Enable all for authenticated users" on public.price_update_suggestions; -- fica pus_all_authenticated
drop policy if exists "Enable all for authenticated users" on public.product_price_history;    -- fica pph_all_authenticated
drop policy if exists "Enable all for authenticated users" on public.supplier_product_mappings; -- fica spm_all_authenticated

alter policy quote_request_supplier_terms_select on public.quote_request_supplier_terms
  using (is_admin_or_financial((select auth.uid())));
alter policy quote_request_supplier_terms_insert on public.quote_request_supplier_terms
  with check (is_admin_or_financial((select auth.uid())));
alter policy quote_request_supplier_terms_update on public.quote_request_supplier_terms
  using (is_admin_or_financial((select auth.uid()))) with check (is_admin_or_financial((select auth.uid())));
alter policy quote_request_supplier_terms_delete on public.quote_request_supplier_terms
  using (is_admin_or_financial((select auth.uid())));

-- Aplicada por `db query -f`: registra a si mesma.
insert into supabase_migrations.schema_migrations (version, name)
values ('20260919150000', 'policies_permissivas_duplicadas')
on conflict do nothing;
