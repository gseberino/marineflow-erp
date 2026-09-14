-- Recuperada do transcript da sessão (C--Users-PC/a12c77fb-6295-4d2c-86c2-da5fd7d7a34a.jsonl, 2026-09-09T20:14:49.510Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260909201437 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Complemento do lev-14 (paridade do PDF do cliente): sob o token, receivables/
-- payments/expenses/survey voltavam VAZIOS (política ausente filtra linha) — o
-- cliente que pagou o sinal baixava documento sem registro do pagamento, e o
-- levantamento nunca chegava. Mesmo padrão das 7 políticas de 20260729144824:
-- SELECT para anon amarrado a share_token_da_requisicao(), escopo = a OS do token.

create policy "anon_receivables_via_share_token" on public.receivables
  for select to anon using (
    exists (
      select 1 from service_orders so
      where so.id = receivables.service_order_id
        and so.share_token is not null
        and so.share_token::text = share_token_da_requisicao()
    )
  );

create policy "anon_payments_via_share_token" on public.payments
  for select to anon using (
    exists (
      select 1
      from receivables r
      join service_orders so on so.id = r.service_order_id
      where r.id = payments.receivable_id
        and so.share_token is not null
        and so.share_token::text = share_token_da_requisicao()
    )
  );

create policy "anon_so_expenses_via_share_token" on public.service_order_expenses
  for select to anon using (
    exists (
      select 1 from service_orders so
      where so.id = service_order_expenses.service_order_id
        and so.share_token is not null
        and so.share_token::text = share_token_da_requisicao()
    )
  );

-- Levantamento: só o FECHADO (status closed) — rascunho de levantamento não é
-- documento do cliente; é exatamente o recorte que o PDF do ERP usa.
create policy "anon_surveys_via_share_token" on public.service_surveys
  for select to anon using (
    status = 'closed'
    and exists (
      select 1 from service_orders so
      where so.id = service_surveys.service_order_id
        and so.share_token is not null
        and so.share_token::text = share_token_da_requisicao()
    )
  );

create policy "anon_survey_answers_via_share_token" on public.service_survey_answers
  for select to anon using (
    exists (
      select 1
      from service_surveys sv
      join service_orders so on so.id = sv.service_order_id
      where sv.id = service_survey_answers.survey_id
        and sv.status = 'closed'
        and so.share_token is not null
        and so.share_token::text = share_token_da_requisicao()
    )
  );

insert into supabase_migrations.schema_migrations (version, name)
values ('20260909150000', 'portal_ve_sinal_e_levantamento')
on conflict (version) do nothing;
