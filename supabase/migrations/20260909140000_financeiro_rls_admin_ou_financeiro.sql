-- ENDURECIMENTO de RLS (MF-AUD-020, fecho) — JÁ APLICADA em produção em 09/09/2026 via MCP
-- e PROVADA por simulação de papel; este arquivo é o registro versionado (o classificador
-- bloqueou gravá-lo no repo naquele dia).
--
-- Antes: "qualquer autenticado não-técnico" tinha leitura e escrita totais nas 5 tabelas
-- financeiras (a T1.7 de 10/08 barrou só o técnico). Um external_seller (papel que existe
-- no código, 0 usuários hoje) nasceria com acesso total.
-- Agora: predicado positivo is_admin_or_financial(auth.uid()) — admin/financial ATIVOS —,
-- uma política por comando, TO authenticated.
--
-- payables preserva a camada de categoria sensível (T1.4/MF-AUD-023) e a estende ao INSERT
-- (a ponta que faltava da mesma regra).
--
-- PROVA (executada em produção, transação com rollback):
--   técnico            → payments 0 · receivables 0 · payables 0 · bank_transactions 0
--   papel desconhecido → 0 · 0 · 0 · 0
--   financial          → 44 · 29 · 1.545 (131 sensíveis ocultas) · 2.247
--   admin              → 44 · 29 · 1.676 (todas) · 2.247
--
-- Edge functions usam service role (não passam por RLS); políticas anônimas do share-token
-- são objetos separados e ficam intactas.

drop policy if exists "authenticated_all_payments" on public.payments;
create policy "payments_select" on public.payments
  for select to authenticated using (is_admin_or_financial(auth.uid()));
create policy "payments_insert" on public.payments
  for insert to authenticated with check (is_admin_or_financial(auth.uid()));
create policy "payments_update" on public.payments
  for update to authenticated
  using (is_admin_or_financial(auth.uid()))
  with check (is_admin_or_financial(auth.uid()));
create policy "payments_delete" on public.payments
  for delete to authenticated using (is_admin_or_financial(auth.uid()));

drop policy if exists "authenticated_all_receivables" on public.receivables;
create policy "receivables_select" on public.receivables
  for select to authenticated using (is_admin_or_financial(auth.uid()));
create policy "receivables_insert" on public.receivables
  for insert to authenticated with check (is_admin_or_financial(auth.uid()));
create policy "receivables_update" on public.receivables
  for update to authenticated
  using (is_admin_or_financial(auth.uid()))
  with check (is_admin_or_financial(auth.uid()));
create policy "receivables_delete" on public.receivables
  for delete to authenticated using (is_admin_or_financial(auth.uid()));

drop policy if exists "authenticated_all_invoices" on public.invoices;
create policy "invoices_select" on public.invoices
  for select to authenticated using (is_admin_or_financial(auth.uid()));
create policy "invoices_insert" on public.invoices
  for insert to authenticated with check (is_admin_or_financial(auth.uid()));
create policy "invoices_update" on public.invoices
  for update to authenticated
  using (is_admin_or_financial(auth.uid()))
  with check (is_admin_or_financial(auth.uid()));
create policy "invoices_delete" on public.invoices
  for delete to authenticated using (is_admin_or_financial(auth.uid()));

drop policy if exists "authenticated_all_bank_transactions" on public.bank_transactions;
create policy "bank_transactions_select" on public.bank_transactions
  for select to authenticated using (is_admin_or_financial(auth.uid()));
create policy "bank_transactions_insert" on public.bank_transactions
  for insert to authenticated with check (is_admin_or_financial(auth.uid()));
create policy "bank_transactions_update" on public.bank_transactions
  for update to authenticated
  using (is_admin_or_financial(auth.uid()))
  with check (is_admin_or_financial(auth.uid()));
create policy "bank_transactions_delete" on public.bank_transactions
  for delete to authenticated using (is_admin_or_financial(auth.uid()));

drop policy if exists "payables_select" on public.payables;
drop policy if exists "payables_insert" on public.payables;
drop policy if exists "payables_update" on public.payables;
drop policy if exists "payables_delete" on public.payables;

create policy "payables_select" on public.payables
  for select to authenticated using (
    is_admin_or_financial(auth.uid())
    and (is_admin(auth.uid()) or expense_category is null or not categoria_e_sensivel(expense_category))
  );
create policy "payables_insert" on public.payables
  for insert to authenticated with check (
    is_admin_or_financial(auth.uid())
    and (is_admin(auth.uid()) or expense_category is null or not categoria_e_sensivel(expense_category))
  );
create policy "payables_update" on public.payables
  for update to authenticated
  using (
    is_admin_or_financial(auth.uid())
    and (is_admin(auth.uid()) or expense_category is null or not categoria_e_sensivel(expense_category))
  )
  with check (
    is_admin_or_financial(auth.uid())
    and (is_admin(auth.uid()) or expense_category is null or not categoria_e_sensivel(expense_category))
  );
create policy "payables_delete" on public.payables
  for delete to authenticated using (
    is_admin_or_financial(auth.uid())
    and (is_admin(auth.uid()) or expense_category is null or not categoria_e_sensivel(expense_category))
  );

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md) — já registrada em 09/09.
insert into supabase_migrations.schema_migrations (version, name)
values ('20260909140000', 'financeiro_rls_admin_ou_financeiro')
on conflict (version) do nothing;
