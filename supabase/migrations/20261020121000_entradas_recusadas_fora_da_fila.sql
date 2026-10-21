-- Papelada do financeiro (20/10/2026), item B3: as entradas antigas que o dono JÁ RECUSOU saem da fila do banco
-- pelo mesmo caminho que a recusa passa a seguir (finance-review/recusa.ts, item A2). Spec:
-- D:/IA-HBR/comprovantes-bancada/spec/spec-papelada-fix.md (B3).
--
-- ═══ GRAVA DADO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
--
-- O DEFEITO: recusar uma entrada na fila não marcava a linha do banco. O resumo da manhã e a tarde contam "entrada
-- sem identificação" pelos créditos com reconciled=false e dismissed_at nulo, então as 6 entradas antigas que o dono
-- já recusou (R$ 1.045,95; 5 delas duas vezes, em 20/09 e 26/09) continuavam contadas para sempre.
--
-- O QUE MUDA (5 linhas; conferidas em produção em 20/10/2026 — nenhuma tem despesa, receita ou pagamento ligado, todas
-- têm a última proposta 'rejected' pelo admin ativo, nenhuma tem proposta pendente):
--   19/09/2025  R$ 11,40  AXK4J38-ARTERIS LITORAL SUL  BR101 793 N   estorno de pedágio
--   25/11/2025  R$ 11,40  AXK4J38-ARTERIS LITORAL SUL  BR101 793 S   estorno de pedágio
--   20/02/2026  R$ 11,40  AXK4J38-ARTERIS LITORAL SUL  BR101 1574    estorno de pedágio
--   20/03/2026  R$ 11,40  AXK4J38-ARTERIS LITORAL SUL  BR101 1574    estorno de pedágio
--   23/04/2026  R$  0,35  CHEQUE ESPECIAL                            crédito de centavos do cheque especial
-- Cada uma vira o que a recusa de uma entrada passa a gravar: reconciled = true, dismissed_kind = 'manual' (conta no
-- saldo e no fluxo de caixa como movimento — o dinheiro entrou de verdade; NÃO 'estornada', que tiraria a linha do
-- saldo), dismissed_reason 'Recusada na fila: …', dismissed_at = agora, dismissed_by = quem recusou (o decided_by da
-- última recusa da linha), e a trilha 'ignorou' em reconciliation_log com o mesmo autor.
-- FICA para o dono: 10/04/2026  R$ 1.000,00  Pix recebido de pessoa física (recusado em 26/09 e 28/09, sem nota) —
-- não é tocado aqui.
--
-- IDEMPOTENTE: cada linha só muda se ainda estiver livre (crédito, reconciled=false, fora da fila nunca, sem
-- lançamento nem pagamento ligado, mesma data e mesmo valor, última proposta recusada e nenhuma pendente). A 2ª
-- aplicação não acha nada para mudar e não grava trilha de novo.
--
-- DESFAZER (uma linha): Extrato › Fora da fila › trazer de volta (o undismiss de sempre) — ou, no banco:
--   update public.bank_transactions set reconciled = false, dismissed_kind = null, dismissed_reason = null,
--          dismissed_at = null, dismissed_by = null
--    where id = '…' and dismissed_kind = 'manual' and dismissed_reason like 'Recusada na fila:%';

-- As 5 linhas-alvo (id, data, valor, motivo), escritas DUAS vezes (aqui e na prova) de propósito: nada de tabela
-- auxiliar, nem temporária.
with alvo (id, dia, valor, motivo) as (
  values
    ('c40b8d03-82b5-459d-b979-790537551de7'::uuid, date '2025-09-19', 11.40, 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente'),
    ('14bce45c-d889-44df-aa48-ba7a099e8a9b'::uuid, date '2025-11-25', 11.40, 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente'),
    ('34cc3028-eb49-430e-b4e2-5654b87bdca5'::uuid, date '2026-02-20', 11.40, 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente'),
    ('59777142-d985-4a53-954d-5f0c0dacb75d'::uuid, date '2026-03-20', 11.40, 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente'),
    ('eb1c966c-b2a0-4e1f-82e0-494b0fb907ad'::uuid, date '2026-04-23',  0.35, 'Recusada na fila: crédito de centavos do cheque especial, não é receita de cliente')
),
livres as (
  select t.id, a.motivo, t.amount,
         (select q.decided_by from public.finance_review_queue q
           where q.bank_transaction_id = t.id and q.kind = 'create_receivable' and q.status = 'rejected'
           order by q.decided_at desc nulls last, q.created_at desc limit 1) as quem
    from public.bank_transactions t
    join alvo a on a.id = t.id
   where t.transaction_type = 'credit'
     and coalesce(t.reconciled, false) = false
     and t.dismissed_reason is null and t.dismissed_kind is null and t.dismissed_at is null
     and t.transaction_date = a.dia and round(t.amount, 2) = a.valor
     and not exists (select 1 from public.payables p where p.bank_transaction_id = t.id)
     and not exists (select 1 from public.receivables r where r.bank_transaction_id = t.id)
     and not exists (select 1 from public.payments pm where pm.bank_transaction_id = t.id)
     and not exists (select 1 from public.finance_review_queue q where q.bank_transaction_id = t.id and q.status = 'pending')
     -- a ÚLTIMA proposta da linha é a recusa (a recusa ainda vale)
     and (select q.status from public.finance_review_queue q
           where q.bank_transaction_id = t.id and q.kind <> 'anomaly'
           order by q.created_at desc limit 1) = 'rejected'
),
marcadas as (
  update public.bank_transactions t
     set reconciled = true,
         dismissed_kind = 'manual',
         dismissed_reason = l.motivo,
         dismissed_at = now(),
         dismissed_by = l.quem
    from livres l
   where t.id = l.id
  returning t.id, t.amount, l.motivo, l.quem
)
insert into public.reconciliation_log (acao, autor, bank_transaction_id, valor, detalhe, antes, depois)
select 'ignorou', m.quem, m.id, m.amount,
       left(m.motivo || ' · entrada antiga já recusada, tirada da fila pela papelada de 20/10/2026', 300),
       jsonb_build_object('estado', 'pendente', 'contada_como', 'entrada sem identificação'),
       jsonb_build_object('estado', 'fora_da_fila', 'dismissed_kind', 'manual')
  from marcadas m;

-- ---------------------------------------------------------------------------------------------
-- Prova (antes do registro da versão): as 5 estão fora da fila com o motivo; a de R$ 1.000 não foi tocada
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_existem integer;
  v_fora integer;
  v_mil_intacta boolean;
begin
  with alvo (id, motivo) as (
    values
      ('c40b8d03-82b5-459d-b979-790537551de7'::uuid, 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente'),
      ('14bce45c-d889-44df-aa48-ba7a099e8a9b'::uuid, 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente'),
      ('34cc3028-eb49-430e-b4e2-5654b87bdca5'::uuid, 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente'),
      ('59777142-d985-4a53-954d-5f0c0dacb75d'::uuid, 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente'),
      ('eb1c966c-b2a0-4e1f-82e0-494b0fb907ad'::uuid, 'Recusada na fila: crédito de centavos do cheque especial, não é receita de cliente')
  )
  select count(*), count(*) filter (where t.reconciled and t.dismissed_kind = 'manual' and t.dismissed_reason = a.motivo
                                          and t.dismissed_at is not null)
    into v_existem, v_fora
    from public.bank_transactions t join alvo a on a.id = t.id;
  -- linha que não existe neste banco (ensaio) não conta; a que existe e não saiu da fila, conta
  if v_fora < v_existem then
    raise exception 'B3: só % de % linhas-alvo ficaram fora da fila — alguma mudou desde 20/10/2026; confira antes de reaplicar', v_fora, v_existem;
  end if;

  select coalesce(bool_and(coalesce(t.reconciled, false) = false and t.dismissed_reason is null), true) into v_mil_intacta
    from public.bank_transactions t where t.id = '16e364db-99da-4a29-80a0-224e30387b72';
  if not v_mil_intacta then
    raise exception 'B3: a entrada de R$ 1.000 (10/04/2026) foi tocada — ela é do dono';
  end if;
  raise notice 'B3: % linha(s) fora da fila; a de R$ 1.000 ficou para o dono', v_fora;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261020121000', 'entradas_recusadas_fora_da_fila')
on conflict do nothing;
