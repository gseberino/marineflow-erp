-- ─────────────────────────────────────────────────────────────────────────────
-- RLS das tabelas de COMPRAS: de "qualquer autenticado" para "admin ou financeiro".
--
-- Estado anterior (5 políticas): FOR ALL TO authenticated USING (true). Ou seja,
-- técnico e vendedor externo — que fazem login no mesmo sistema — podiam LER e
-- ESCREVER ordens de compra e cotações, incluindo custo de aquisição e margem do
-- fornecedor. As rotas já restringem a admin/financial na interface, mas rota não é
-- segurança: a API REST responde direto a qualquer token válido.
--
-- Estas 5 caem da lista de `rls_policy_always_true` dos advisors (Fase 2 do roadmap).
--
-- Decisões:
--   • Uma política POR COMANDO, nunca FOR ALL. Políticas do mesmo comando se somam por
--     OR — uma FOR ALL permissiva anularia qualquer restrição adicionada depois.
--   • `TO authenticated` explícito em todas. Sem isso a política também valeria para
--     anon, e is_admin_or_financial(NULL) devolve false sem FECHAR o acesso — a
--     ausência de política é que fecha, e é fácil errar isso.
--   • REVOKE de anon nas 5 tabelas, na mesma migration.
--   • Edge functions (motor de automação, agente) usam service_role e não passam por
--     RLS — o funcionamento delas não muda.
--
-- Efeito visível: técnico deixa de ver a seção de compras vinculadas dentro da OS.
-- É o comportamento pretendido — custo de compra não é informação de quem executa.
-- ─────────────────────────────────────────────────────────────────────────────

do $$
declare
  t text;
begin
  foreach t in array array[
    'purchase_orders', 'purchase_order_items',
    'quote_requests', 'quote_request_items', 'quote_responses'
  ] loop
    -- Remove as permissivas antigas (nomes diferentes entre os dois módulos).
    execute format('drop policy if exists %I on public.%I', 'auth_all_po', t);
    execute format('drop policy if exists %I on public.%I', 'auth_all_poi', t);
    execute format('drop policy if exists %I on public.%I', 'authenticated_all_' || t, t);

    execute format($f$
      create policy %I on public.%I
        for select to authenticated
        using (public.is_admin_or_financial(auth.uid()))
    $f$, t || '_select', t);

    execute format($f$
      create policy %I on public.%I
        for insert to authenticated
        with check (public.is_admin_or_financial(auth.uid()))
    $f$, t || '_insert', t);

    execute format($f$
      create policy %I on public.%I
        for update to authenticated
        using (public.is_admin_or_financial(auth.uid()))
        with check (public.is_admin_or_financial(auth.uid()))
    $f$, t || '_update', t);

    execute format($f$
      create policy %I on public.%I
        for delete to authenticated
        using (public.is_admin_or_financial(auth.uid()))
    $f$, t || '_delete', t);

    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

comment on table public.quote_requests is
  'Cotações a fornecedores (COT-). Acesso restrito a admin/financeiro pela RLS.';
