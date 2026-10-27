-- Diárias: só o que é diária abate a conta do freelancer — 27/10/2026 (fase 1b da revisão de 24/10).
--
-- Até aqui todo pagamento ao freelancer abatia a conta das diárias, de qualquer categoria. O dono pediu
-- em 17/10 que o Pix de alimentação do Roberto (R$ 63, 15/10, "Alimentação de campo") não abatesse; o
-- mesmo vale para o de peças do Mickael (R$ 70, 28/08, "Peças e materiais"). Era também o que impedia
-- juntar comissão depois: um Pix de comissão seria lido como pagamento de diária.
--
-- Regra: abate o lançamento/anotação da categoria "Diárias de freelancers" e o que ainda não tem
-- categoria (Pix que o banco trouxe e espera a fila: o dono ainda vai dizer o que é; o recibo trava
-- enquanto houver um assim). Qualquer outra categoria sai da conta — é dinheiro dado por outro motivo.
--
-- Medido em 27/10 (prévia): Roberto −443 → −380, Mickael 210 → 280, João 325 igual.
-- Só create or replace de _conta_corrente_linhas (corpo de 20261027120000 igual fora os trechos "1b") e
-- uma função nova de uma linha. Nenhum dado é escrito. Teste: supabase/tests/diarias_so_categoria_diarias.sql.

create or replace function public._abate_diarias(p_categoria text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select coalesce(p_categoria, 'Diárias de freelancers') = 'Diárias de freelancers';
$$;

revoke all on function public._abate_diarias(text) from public, anon, authenticated;

create or replace function public._conta_corrente_linhas(p_favorecido_id uuid)
returns table(data date, tipo text, id uuid, jornada text, fracao numeric, valor_diaria numeric, extras numeric,
              descontos numeric, trabalhado numeric, pago numeric, descricao text, conta text, categoria text,
              observacao text, os jsonb, criado_em timestamptz, aguardando boolean)
language sql
stable
security definer
set search_path = public
as $$
  with fav as (
    select id, coalesce(conta_corrente_desde, date '1900-01-01') as desde,
           nullif(regexp_replace(coalesce(document, ''), '\D', '', 'g'), '') as doc
      from public.payees where id = p_favorecido_id
  ),
  -- 1a: o lançamento com o valor que ele recebeu (o principal do grupo, com a soma das partes)
  lanc as (
    select p.id, p.issue_date, p.bank_transaction_id, g.pago
      from public.payables p
      join fav on (p.payee_id = fav.id or p.beneficiario_id = fav.id)
      cross join lateral (
        select sum(case when x.payee_id = fav.id then coalesce(x.paid_amount, 0) else x.amount end) as pago
          from public.payables x
         where (x.id = p.id or x.divisao_id = p.id) and x.status <> 'cancelled') g
     where p.status <> 'cancelled' and p.divisao_id is null and p.issue_date >= fav.desde and g.pago > 0
       and public._abate_diarias(p.expense_category)
  ),
  -- 1a: anotação que nunca casou com o banco e o lançamento que já a cobre (defeito 4)
  soltas as (
    select a.id, a.valor, a.data_prevista
      from public.anotacoes_do_extrato a
      join fav on fav.id = a.favorecido_id
     where a.sentido = 'debit' and a.status = 'aguardando' and a.bank_transaction_id is null
       and a.data_prevista >= fav.desde and public._abate_diarias(a.categoria)
  ),
  cobertas as (
    select s.id
      from soltas s
     where (select count(*) from soltas o
             where o.valor = s.valor and abs(o.data_prevista - s.data_prevista) <= 3
               and (o.data_prevista, o.id) <= (s.data_prevista, s.id))
        <= (select count(*) from lanc l
             where l.pago = s.valor and abs(l.issue_date - s.data_prevista) <= 3
               and not exists (select 1 from public.anotacoes_do_extrato an
                                where an.bank_transaction_id = l.bank_transaction_id and an.status <> 'cancelada'))
  )
  select ws.data, 'dia'::text, ws.id,
         case ws.fracao when 1 then 'inteiro' when 0.5 then 'meio' else 'faltou' end,
         ws.fracao, ws.valor_diaria, ws.extras, ws.descontos, ws.valor_dia, 0::numeric,
         null::text, null::text, null::text, ws.observacao,
         coalesce((select jsonb_agg(jsonb_build_object('id', so.id, 'numero', so.service_order_number)
                                    order by so.service_order_number)
                     from public.work_shift_os wo
                     join public.service_orders so on so.id = wo.service_order_id
                    where wo.shift_id = ws.id), '[]'::jsonb),
         ws.created_at, false
    from public.work_shifts ws
    join public.work_profiles wp on wp.id = ws.work_profile_id
    join fav on fav.id = wp.payee_id
   where ws.fracao is not null and ws.data >= fav.desde
  union all
  -- O que ele recebeu: lançamento no nome dele (conta o que foi pago dele) ou pago do bolso do
  -- sócio para ele (conta o valor inteiro — o dinheiro já chegou a ele, o reembolso é do sócio).
  -- Resposta 4 do dono (11/10/2026): o pagamento dividido entre diárias e reembolso é UMA linha (o
  -- principal do grupo, com a soma das partes) e diz quanto dele foi reembolso: o saldo não muda.
  select p.issue_date, 'pagamento'::text, p.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric,
         g.pago,
         -- 1a: sufixo só quando houve reembolso (defeito 1)
         p.description || case when coalesce(dv.reembolsos, 0) > 0
                               then ' (inclui reembolso de despesas pagas pelo técnico: ' || public._brl(dv.reembolsos) || ')'
                               else '' end,
         case when p.payee_id = fav.id
              then coalesce(bc.label, case when p.payment_method = 'cash' then 'Caixa (dinheiro)' end, 'Sem conta ligada')
              else 'Bolso de ' || coalesce(soc.name, 'sócio') end,
         p.expense_category, null::text, '[]'::jsonb, p.created_at, false
    from public.payables p
    join fav on (p.payee_id = fav.id or p.beneficiario_id = fav.id)
    cross join lateral (
      select sum(case when x.payee_id = fav.id then coalesce(x.paid_amount, 0) else x.amount end) as pago
        from public.payables x
       where (x.id = p.id or x.divisao_id = p.id) and x.status <> 'cancelled') g
    left join lateral (
      select sum(r.valor) as reembolsos
        from public.diarias_pagamentos_divididos d
        join public.diarias_reembolsos r on r.id = any (d.reembolsos)
       where d.payable_id = p.id and d.status = 'aplicada' and p.bank_transaction_id is not null) dv on true
    left join public.payees soc on soc.id = p.payee_id
    left join public.bank_transactions bt on bt.id = p.bank_transaction_id
    left join public.bank_connections bc on bc.id = bt.bank_connection_id
   where p.status <> 'cancelled' and p.divisao_id is null and p.issue_date >= fav.desde
     and g.pago > 0
     and public._abate_diarias(p.expense_category)  -- 1b
  union all
  -- Pix/débito ANOTADO para ele que ainda não virou lançamento (decisão do dono, 06/10/2026: já
  -- desconta). Esperando a linha do banco, ou já casado com ela e esperando a aprovação. Quando o
  -- lançamento existe, ele entra pela parte de cima e esta linha sai — nunca os dois. Linha casada
  -- que foi RECUSADA na fila não conta: o dono disse que não era aquilo.
  select a.data_prevista, 'pagamento'::text, a.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric, a.valor,
         coalesce(a.descricao, 'Pix anotado')
           || case when coalesce(dva.reembolsos, 0) > 0
                   then ' (inclui reembolso de despesas pagas pelo técnico: ' || public._brl(dva.reembolsos) || ')'
                   else '' end,
         -- 1a: o que o banco já trouxe não está "aguardando o banco" (defeito 2)
         case when a.bank_transaction_id is not null then 'No banco — falta aprovar na fila'
              else 'Anotado — aguardando o banco' end,
         a.categoria, null::text, '[]'::jsonb, a.criada_em, true
    from public.anotacoes_do_extrato a
    join fav on fav.id = a.favorecido_id
    left join lateral (
      select sum(r.valor) as reembolsos
        from public.diarias_pagamentos_divididos d
        join public.diarias_reembolsos r on r.id = any (d.reembolsos)
       where d.anotacao_id = a.id and d.status = 'pendente') dva on true
   where a.sentido = 'debit' and a.data_prevista >= fav.desde
     and public._abate_diarias(a.categoria)  -- 1b
     and (a.status = 'aguardando'
          or (a.status = 'aplicada' and a.bank_transaction_id is not null
              and not exists (select 1 from public.payables p
                               where p.bank_transaction_id = a.bank_transaction_id and p.status <> 'cancelled')
              and not exists (select 1 from public.finance_review_queue q
                               where q.bank_transaction_id = a.bank_transaction_id and q.status = 'rejected')))
     and not exists (select 1 from cobertas c where c.id = a.id)
  union all
  -- 1a: Pix do banco para o CPF dele que ainda não virou lançamento nem tem anotação (defeito 3)
  select bt.transaction_date, 'pagamento'::text, bt.id, null::text, null::numeric, null::numeric, null::numeric,
         null::numeric, 0::numeric, bt.amount,
         coalesce(nullif(btrim(bt.description), ''), 'Pix enviado'),
         'No banco — falta aprovar na fila',
         null::text, null::text, '[]'::jsonb, bt.created_at, true
    from public.bank_transactions bt
    join fav on fav.doc is not null
            and regexp_replace(coalesce(bt.counterparty_document, ''), '\D', '', 'g') = fav.doc
   where bt.transaction_type = 'debit' and bt.amount > 0 and bt.transaction_date >= fav.desde
     and bt.dismissed_kind is null
     and not exists (select 1 from public.payables p where p.bank_transaction_id = bt.id and p.status <> 'cancelled')
     and not exists (select 1 from public.anotacoes_do_extrato an where an.bank_transaction_id = bt.id and an.status <> 'cancelada')
     and not exists (select 1 from public.finance_review_queue q where q.bank_transaction_id = bt.id and q.status = 'rejected')
  union all
  -- F2b: o reembolso de despesa que ele pagou (comprovante). Crédito dele: entra como "trabalhado";
  -- "conta" é o código do CMP. Cancelado não conta. Já quitado por um pagamento dividido (resposta 4):
  -- "pago em DD/MM".
  select r.data, 'reembolso'::text, r.id, null::text, null::numeric, null::numeric, null::numeric, null::numeric,
         r.valor, 0::numeric, r.descricao, r.origem_codigo, r.categoria,
         (select 'pago em ' || to_char(coalesce(pp.issue_date, an.data_prevista), 'DD/MM')
            from public.diarias_pagamentos_divididos d
            left join public.payables pp on pp.id = d.payable_id
            left join public.anotacoes_do_extrato an on an.id = d.anotacao_id
           where r.id = any (d.reembolsos)
             and public._diarias_divisao_viva(d.status, d.payable_id, d.lancamentos)
           order by d.criado_em desc
           limit 1),
         case when so.id is null then '[]'::jsonb
              else jsonb_build_array(jsonb_build_object('id', so.id, 'numero', so.service_order_number)) end,
         r.criado_em, false
    from public.diarias_reembolsos r
    join fav on fav.id = r.favorecido_id
    left join public.service_orders so on so.id = r.os_id
   where r.status = 'ativo' and r.data >= fav.desde;
$$;
