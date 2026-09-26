-- Compra no débito ("DEBITO DE CARTAO") não é pagamento de fatura (26/09/2026).
--
-- O C6 manda a compra feita com o cartão na função DÉBITO só com o texto "DEBITO DE CARTAO":
-- sem loja, sem CNPJ, sem ramo (MCC) — a regra do Open Finance dispensa o banco de informar a
-- contraparte no débito. A migration 20260810040000 partiu da premissa errada de que esse
-- texto era pagamento de fatura: trocou 4 lançamentos que o dono aprovou em 05/08 e as
-- sugestões da fila. A memória por nome então tomou o texto por uma loja e passou a sugerir
-- fatura para TODA compra no débito (fora do DRE). O motor foi corrigido no mesmo commit
-- (historicoSemIdentidade: esse texto não ensina nem é ensinado); aqui vão a view e os dados.
--
-- Tudo por id explícito ou critério estreito, com trilha em reconciliation_log.

-- ── 1. A conferência de fatura do cartão não conta compra no débito como pagamento ──
create or replace view public.faturas_do_cartao with (security_invoker = on) as
 with compras as (
         select bt.bill_id,
            bt.provider_account_id,
            count(*) as compras,
            min(bt.transaction_date) as primeira_compra,
            max(bt.transaction_date) as ultima_compra,
            round(sum(bt.amount), 2) as total,
            string_agg(distinct bt.card_last_digits, ', '::text order by bt.card_last_digits) as cartoes,
            count(*) filter (where bt.installment_label is not null) as compras_parceladas
           from bank_transactions bt
          where bt.source_type = 'credit_card'::text and bt.transaction_type = 'debit'::text and bt.bill_id is not null
          group by bt.bill_id, bt.provider_account_id
        )
 select c.bill_id,
    c.provider_account_id,
    c.compras,
    c.compras_parceladas,
    c.primeira_compra,
    c.ultima_compra,
    c.total,
    c.cartoes,
    pg.id as pagamento_id,
    pg.transaction_date as pagamento_data,
    pg.amount as pagamento_valor,
    pg.description as pagamento_descricao
   from compras c
     left join lateral ( select b.id,
            b.transaction_date,
            b.amount,
            b.description
           from bank_transactions b
          where b.source_type = 'bank'::text and b.transaction_type = 'debit'::text
            and (b.description ~~* '%FAT%CARTAO%'::text or b.description ~~* '%FATURA%CART%'::text or b.description ~~* '%PGTO%CARTAO%'::text)
            and round(b.amount::numeric, 2) = c.total and b.transaction_date >= c.ultima_compra
            and b.transaction_date <= (c.ultima_compra + '45 days'::interval)
          order by b.transaction_date
         limit 1) pg on true;

comment on view public.faturas_do_cartao is
  'Uma linha por fatura de cartao (bill_id): compras, periodo, total, cartoes do ciclo e o pagamento no extrato quando o valor casa exatamente. O pagamento e sugestao — o provedor nao entrega esse vinculo. "DEBITO DE CARTAO" (compra no debito) NAO e pagamento de fatura (26/09/2026).';
revoke all on public.faturas_do_cartao from anon;
grant select on public.faturas_do_cartao to authenticated;

-- ── 2. Os 4 lançamentos de R$ 8,90 voltam para a escolha do dono (05/08) ──
-- Aprovados por ele como "Pedágio e estacionamento" (a própria migration de 10/08 registra
-- que a memória tinha aprendido "pedágio" com eles) e trocados para fatura sem pergunta.
-- Só volta o que ainda está como fatura: se alguém já corrigiu, fica como está.
with voltam as (
  update public.payables p
     set expense_category = 'Pedágio e estacionamento', updated_at = now()
   where p.id in ('c164f952-e5ec-4c51-a0cc-96fd70115ca4', '11a887d7-4450-4546-a7e4-db78ff57bfb4',
                  'ef5e61f9-4e96-47ec-a7fc-019b5519d3da', '4fe31cdc-af80-4388-a90f-63c0fc7fdaf6')
     and p.expense_category = 'Pagamento de fatura de cartão'
     and p.status <> 'cancelled'
  returning p.id, p.bank_transaction_id, p.amount
)
insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, valor, detalhe, antes, depois)
select 'corrigiu_lancamento', null, v.bank_transaction_id, v.id, v.amount,
       'Compra no débito tinha sido trocada para fatura pela correção de 10/08; volta para a categoria que o dono escolheu em 05/08',
       jsonb_build_object('expense_category', 'Pagamento de fatura de cartão'),
       jsonb_build_object('expense_category', 'Pedágio e estacionamento')
  from voltam v;

-- ── 3. Sugestões cuja linha já foi lançada por outro caminho saem da fila ──
-- O motor passa a fazer isto sozinho (tirarDaFilaOQueJaFoiLancado); estas 6 são as de hoje.
with saem as (
  update public.finance_review_queue q
     set status = 'superseded',
         decision_note = left('Já lançada por outro caminho como ' || coalesce(
           (select 'despesa "' || left(p.description, 60) || '" (' || coalesce(p.expense_category, 'sem categoria') || ')'
              from public.payables p where p.bank_transaction_id = q.bank_transaction_id),
           (select 'receita "' || left(r.description, 60) || '"'
              from public.receivables r where r.bank_transaction_id = q.bank_transaction_id)), 300),
         updated_at = now()
   where q.id in ('0e7f51ee-d1c1-49ea-ac6d-00374affa4f1', 'f57a5517-9483-495d-ba0e-fbbb97f76900',
                  '106114ee-4298-499f-8ebc-f409d80106fe', '3d5cbc4d-7f3e-4446-84db-9dc826206211',
                  'd0ceceda-6323-4380-95de-dbe29b193798', '16836fa6-e9d4-4cb9-a215-9a9d9398bad2')
     and q.status = 'pending'
     and (exists (select 1 from public.payables p where p.bank_transaction_id = q.bank_transaction_id)
       or exists (select 1 from public.receivables r where r.bank_transaction_id = q.bank_transaction_id))
  returning q.bank_transaction_id, q.suggested_amount, q.decision_note
)
insert into public.reconciliation_log (acao, autor, bank_transaction_id, valor, detalhe)
select 'tirou_da_fila_ja_lancada', null, s.bank_transaction_id, s.suggested_amount,
       left('Sugestão saiu da fila: ' || s.decision_note, 300)
  from saem s;

-- ── 4. As compras no débito na fila deixam de ser "fatura" e pedem a loja ──
-- Mesmo resultado que o motor corrigido dá (Outras despesas, confiança 30, motivo escrito);
-- aqui só para não esperar a varredura das 6h.
update public.finance_review_queue q
   set suggested_category = 'Outras despesas',
       dre_group = 'despesa_operacional',
       confidence = 30,
       reasoning = 'Compra no débito: o banco não informa onde foi. Diga a loja ao aprovar — ou, na próxima, avise pelo WhatsApp na hora',
       updated_at = now()
  from public.bank_transactions bt
 where bt.id = q.bank_transaction_id
   and q.status = 'pending'
   and q.kind = 'create_payable'
   and q.suggested_category = 'Pagamento de fatura de cartão'
   and upper(bt.description) = 'DEBITO DE CARTAO'
   and coalesce(bt.counterparty_name, '') = ''
   and length(regexp_replace(coalesce(bt.counterparty_document, ''), '\D', '', 'g')) < 11;

-- ── 5. Ponto de partida do saldo do C6 ──
-- Fixado em 25/09 às 18:00:14 com a soma de ANTES de gravar 3 Pix que chegaram na mesma
-- busca (+2.070, −110, −100 = +1.860): 7.810,51 no lugar de 5.950,51. A busca passa a
-- conferir depois de gravar (banking-sync). Guarda: só troca se ainda estiver no valor errado.
with c6 as (
  update public.bank_connections
     set saldo_base = 5950.51
   where id = 'd288bc10-eff3-42c8-ae31-4c9a9b35e5c6'
     and saldo_base = 7810.51
  returning id
)
-- A conferência registrada leva a hora em que o banco informou os 3.246,61 (25/09, logo
-- depois da base de 18:00:14), não a hora da migration: aplicada depois de uma busca nova,
-- ela não pode passar na frente da conferência real e mostrar um saldo velho como "confere".
insert into public.bank_balance_checks (bank_connection_id, conferido_em, saldo_do_provedor, saldo_calculado, diferenca, transacoes_no_periodo, fecha, observacao)
select id, '2026-09-25 21:00:14.3+00', 3246.61, 3246.61, 0, 906, true,
       'Linha de base corrigida em 26/09/2026: 7.810,51 → 5.950,51. A de 25/09 foi fixada antes de gravar 3 Pix da mesma busca (+1.860).'
  from c6;

-- ── 6. A contagem do Caixa que bate também fica registrada ──
-- "Contei o dinheiro" com o mesmo valor do sistema voltava sem gravar nada, e a tela não tinha
-- como saber que alguém contou (o aviso "conte o dinheiro" ficaria para sempre). Mesma
-- função, mesmas regras; a diferença é o registro 'contou_caixa' quando não há ajuste.
create or replace function public.ajustar_caixa(p_saldo_contado numeric, p_motivo text, p_autor uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_atual numeric := public.saldo_do_caixa();
  v_dif numeric;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if p_saldo_contado is null or p_saldo_contado < 0 then raise exception 'Informe quanto dinheiro há no caixa agora.'; end if;
  if v_motivo is null then raise exception 'Diga o motivo do ajuste (ex.: contagem de sexta).'; end if;
  v_dif := round(p_saldo_contado - v_atual, 2);
  if v_dif = 0 then
    insert into public.reconciliation_log (acao, autor, valor, detalhe, antes, depois)
    values ('contou_caixa', v_autor, 0, left('Contagem bateu: ' || v_motivo, 300),
            jsonb_build_object('saldo', v_atual), jsonb_build_object('saldo', p_saldo_contado));
    return jsonb_build_object('ok', true, 'diferenca', 0, 'saldo_do_caixa', v_atual, 'message', 'O Caixa já bate com a contagem.');
  end if;
  perform public._linha_do_caixa(case when v_dif > 0 then 'credit' else 'debit' end, abs(v_dif), public._hoje_brt(),
                                 'Ajuste pela contagem: ' || v_motivo, null, 'ajuste_caixa', 'Ajuste pela contagem: ' || v_motivo, v_autor);
  insert into public.reconciliation_log (acao, autor, valor, detalhe, antes, depois)
  values ('ajustou_caixa', v_autor, v_dif, left('Contagem: ' || v_motivo, 300),
          jsonb_build_object('saldo', v_atual), jsonb_build_object('saldo', p_saldo_contado));
  return jsonb_build_object('ok', true, 'diferenca', v_dif, 'saldo_do_caixa', public.saldo_do_caixa(),
    'message', case when v_dif > 0 then 'Sobrou ' else 'Faltou ' end || public._brl(abs(v_dif))
               || ' em relação ao sistema. Caixa ajustado para ' || public._brl(p_saldo_contado) || '.');
end;
$$;
revoke all on function public.ajustar_caixa(numeric, text, uuid) from public, anon;
grant execute on function public.ajustar_caixa(numeric, text, uuid) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260926200000', 'debito_de_cartao_nao_e_fatura')
on conflict do nothing;
