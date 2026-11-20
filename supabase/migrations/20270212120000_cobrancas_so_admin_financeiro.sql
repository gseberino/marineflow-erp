-- Cobranças (public.collections): só administrador e financeiro criam, alteram e apagam. 20/11/2026.
--
-- Decisão do dono (Respostas do Diário, 20/11/2026): "Técnico pode criar cobrança pela tela?" → "Só admin e
-- financeiro". Até aqui uma policy só (authenticated_full_access, FOR ALL) deixava qualquer logado menos o vendedor
-- externo ler E gravar. Fica:
--   SELECT  → como estava (logado, menos o vendedor externo): a OS mostra "Cobranças geradas" a quem a abre.
--   INSERT / UPDATE / DELETE → is_admin_or_financial (o helper das policies de receivables).
-- Todas com TO authenticated (policy sem TO vale para anon: as funções de cargo devolvem false para usuário nulo).
-- E anon perde os privilégios da tabela (segunda barreira; nenhuma policy de anon existe).
--
-- Inventário de quem grava em collections (20/11/2026), para nada legítimo quebrar:
--   Banco, SECURITY DEFINER (a RLS não se aplica): cobrar_juntas_registrar_envio (só admin/financeiro, 20270212110000),
--     cancel_service_order_cascade, register_deposit_and_convert, sync_balance_due_on_completion,
--     sync_collection_from_receivable (gatilho), _agenda_desfazer_marco.
--   Edge com service role (a RLS não se aplica): registrarEnvioDaCobranca (send_collection_reminder e o lote),
--     banking-reconcile (cobrança quitada).
--   Edge com o JWT de quem pede (a RLS se aplica): criar_cobranca e alterar_cobranca do assistente — passam a
--     admin/financeiro também na tool (_shared/ai/tools/cobrancas.ts), para a recusa sair em português.
--   Tela (a RLS se aplica): Cobranças (rota só admin/financeiro: criar, editar, cancelar, dar baixa, enviar,
--     marcar vencidas); geração na OS (generate-collections.ts: botão "Gerar Cobranças", que o técnico não vê, e
--     a geração automática quando a OS aberta na tela vê a assinatura chegar ou é salva como faturada — essa
--     passa a rodar só na sessão de admin/financeiro, ServiceOrderForm.tsx).
-- collection_contacts (o histórico de contatos) fica como está.

drop policy if exists authenticated_full_access on public.collections;
drop policy if exists collections_leitura on public.collections;
drop policy if exists collections_criar on public.collections;
drop policy if exists collections_alterar on public.collections;
drop policy if exists collections_apagar on public.collections;

create policy collections_leitura on public.collections
  for select to authenticated
  using (not (select public.is_external_seller((select auth.uid()))));

create policy collections_criar on public.collections
  for insert to authenticated
  with check ((select public.is_admin_or_financial((select auth.uid()))));

create policy collections_alterar on public.collections
  for update to authenticated
  using ((select public.is_admin_or_financial((select auth.uid()))))
  with check ((select public.is_admin_or_financial((select auth.uid()))));

create policy collections_apagar on public.collections
  for delete to authenticated
  using ((select public.is_admin_or_financial((select auth.uid()))));

revoke all on public.collections from anon;

-- Conferência: nenhuma policy de collections vale para public/anon, e são exatamente as 4 de cima.
do $$
declare
  v_qtd integer;
begin
  select count(*) into v_qtd from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'collections';
  if v_qtd <> 4 then
    raise exception 'collections deveria ter 4 policies, tem %', v_qtd;
  end if;
  if exists (select 1 from pg_policies p
              where p.schemaname = 'public' and p.tablename = 'collections'
                and (p.roles @> array['public']::name[] or p.roles @> array['anon']::name[])) then
    raise exception 'policy de collections aberta para public/anon';
  end if;
  if has_table_privilege('anon', 'public.collections', 'select')
     or has_table_privilege('anon', 'public.collections', 'insert') then
    raise exception 'anon ainda tem privilégio em collections';
  end if;
end $$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name)
values ('20270212120000', 'cobrancas_so_admin_financeiro')
on conflict do nothing;
