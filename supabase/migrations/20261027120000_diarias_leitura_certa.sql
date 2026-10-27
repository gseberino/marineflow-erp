-- Diárias: a conta corrente lê certo o que já aconteceu — 27/10/2026 (fase 1a da revisão de 24/10).
--
-- Quatro defeitos de LEITURA, achados no dado real; nenhum dado é escrito e nenhuma assinatura muda:
--
-- 1. "(inclui reembolso de despesas pagas pelo técnico: R$ 0,00)" em 34 de 34 pagamentos: _brl(null)
--    devolve 'R$ 0,00', não nulo, e o coalesce nunca entrava. O mesmo texto fazia todo pagamento parecer
--    "já dividido" na tela e no assistente (que reconhecem a divisão pelo sufixo). Agora só com reembolso.
-- 2. "Anotado — aguardando o banco" também no Pix anotado que o banco JÁ trouxe (casado, esperando a
--    aprovação na fila): Roberto 06/10 R$ 100 e 17/10 R$ 600. Esse passa a dizer "No banco — falta aprovar
--    na fila", e "pago_aguardando_banco" soma só o que o banco ainda não trouxe.
-- 3. Pix do banco para o CPF dele, ainda sem lançamento e sem anotação, NÃO contava: a tela dizia que a
--    HBR devia R$ 867 ao Roberto com R$ 510 (10/10) já pagos na fila. Pela decisão do dono de 06/10
--    ("o anotado aparece e desconta"), o Pix que saiu da conta para o CPF dele também desconta, como
--    "No banco — falta aprovar na fila", até virar lançamento (aí entra pela linha do lançamento, uma vez
--    só). Identidade só pelo CPF do cadastro (regra do dono: nome parecido nunca identifica). Linha
--    recusada na fila ou dispensada do extrato não conta: o dono disse que não era aquilo.
-- 4. Anotação que nunca casou com o banco (João: cadastro sem CPF e nome diferente do extrato) seguiria
--    contando DEPOIS que o dono aprovasse a linha do banco na fila — o mesmo Pix duas vezes. Agora ela sai
--    quando existe o lançamento dela: mesma pessoa, mesmo valor, até 3 dias, um lançamento por anotação.
--
-- Corpos de 20261011301000 IGUAIS (conferidos por md5 contra a produção em 27/10) fora os trechos
-- marcados "1a:". Teste repetível: supabase/tests/diarias_leitura_certa.sql.

-- ---------------------------------------------------------------------------------------------
-- 1. _conta_corrente_linhas
-- ---------------------------------------------------------------------------------------------
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
  ),
  -- 1a: anotação que nunca casou com o banco e o lançamento que já a cobre (defeito 4)
  soltas as (
    select a.id, a.valor, a.data_prevista
      from public.anotacoes_do_extrato a
      join fav on fav.id = a.favorecido_id
     where a.sentido = 'debit' and a.status = 'aguardando' and a.bank_transaction_id is null
       and a.data_prevista >= fav.desde
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

-- ---------------------------------------------------------------------------------------------
-- 2. conta_corrente_freelancer: "pago_aguardando_banco" só do que o banco ainda não trouxe e, à parte,
--    "pago_falta_aprovar" (no banco, esperando a fila). Chave nova; nenhuma some.
-- ---------------------------------------------------------------------------------------------
create or replace function public.conta_corrente_freelancer(
  p_favorecido_id uuid,
  p_de date default null,
  p_ate date default null,
  p_autor uuid default null,
  p_atalho text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_fav record;
  v_perfil record;
  v_de date := p_de;
  v_ate date := p_ate;
  v_anterior numeric;
  v_linhas jsonb;
  v_dias numeric;
  v_trab numeric;
  v_reemb numeric;
  v_pago numeric;
  v_aguardando numeric;
  v_falta_aprovar numeric;
  v_final numeric;
  v_dias_tudo numeric;
  v_pago_tudo numeric;
begin
  select id, name, conta_corrente_desde, saldo_anterior into v_fav
    from public.payees where id = p_favorecido_id;
  if v_fav.id is null then raise exception 'Freelancer não encontrado entre os favorecidos.'; end if;

  if p_atalho is not null then
    select x.de, x.ate into v_de, v_ate from public._periodo_do_atalho(p_favorecido_id, p_atalho) x;
  end if;

  v_de := greatest(coalesce(v_de, v_fav.conta_corrente_desde, date '1900-01-01'),
                   coalesce(v_fav.conta_corrente_desde, date '1900-01-01'));
  v_ate := coalesce(v_ate, date '9999-12-31');
  if v_ate < v_de then raise exception 'Período invertido: % a %.', to_char(v_de, 'DD/MM/YYYY'), to_char(v_ate, 'DD/MM/YYYY'); end if;

  select * into v_perfil from public.work_profiles
   where payee_id = p_favorecido_id and modo_pagamento = 'diaria'
     and vigencia_inicio <= least(v_ate, public._hoje_brt())
   order by vigencia_inicio desc limit 1;

  select v_fav.saldo_anterior + coalesce(sum(l.trabalhado - l.pago), 0) into v_anterior
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data < v_de;

  with l as (
    select * from public._conta_corrente_linhas(p_favorecido_id) where data between v_de and v_ate
  ), o as (
    select l.*, v_anterior + sum(l.trabalhado - l.pago) over (
             order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id
             rows between unbounded preceding and current row) as saldo,
           row_number() over (order by l.data, case l.tipo when 'dia' then 0 else 1 end, l.criado_em, l.id) as ordem
      from l
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'data', o.data, 'tipo', o.tipo, 'id', o.id, 'jornada', o.jornada, 'fracao', o.fracao,
           'valor_diaria', o.valor_diaria, 'extras', o.extras, 'descontos', o.descontos,
           'trabalhado', o.trabalhado, 'pago', o.pago, 'descricao', o.descricao, 'conta', o.conta,
           'categoria', o.categoria, 'observacao', o.observacao, 'os', o.os, 'saldo', round(o.saldo, 2),
           'aguardando', o.aguardando, 'criado_em', o.criado_em)
           order by o.ordem), '[]'::jsonb),
         coalesce(sum(o.fracao) filter (where o.tipo = 'dia'), 0),
         coalesce(sum(o.trabalhado) filter (where o.tipo = 'dia'), 0),
         coalesce(sum(o.trabalhado) filter (where o.tipo = 'reembolso'), 0),
         coalesce(sum(o.pago), 0),
         -- 1a: só o que o banco ainda não trouxe; o que já está no banco vai à parte
         coalesce(sum(o.pago) filter (where o.aguardando and o.conta = 'Anotado — aguardando o banco'), 0),
         coalesce(sum(o.pago) filter (where o.aguardando and o.conta = 'No banco — falta aprovar na fila'), 0)
    into v_linhas, v_dias, v_trab, v_reemb, v_pago, v_aguardando, v_falta_aprovar
    from o;

  v_final := v_anterior + v_trab + v_reemb - v_pago;

  select coalesce(sum(l.fracao) filter (where l.tipo = 'dia'), 0), coalesce(sum(l.pago), 0)
    into v_dias_tudo, v_pago_tudo
    from public._conta_corrente_linhas(p_favorecido_id) l where l.data <= v_ate;

  return jsonb_build_object(
    'favorecido', jsonb_build_object('id', v_fav.id, 'nome', v_fav.name,
                                     'desde', v_fav.conta_corrente_desde, 'saldo_inicial', v_fav.saldo_anterior,
                                     'diaria', v_perfil.valor_diaria),
    'atalho', p_atalho,
    'de', case when v_de = date '1900-01-01' then null else v_de end,
    'ate', case when v_ate = date '9999-12-31' then null else v_ate end,
    'saldo_anterior', round(v_anterior, 2),
    'linhas', v_linhas,
    'dias', v_dias,
    'trabalhado', round(v_trab, 2),
    'reembolsos', round(v_reemb, 2),
    'pago', round(v_pago, 2),
    'pago_aguardando_banco', round(v_aguardando, 2),
    'pago_falta_aprovar', round(v_falta_aprovar, 2),
    'saldo_final', round(v_final, 2),
    'estado', public._estado_do_saldo(v_final, v_dias_tudo, v_pago_tudo)
  );
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 3. resumo_freelancers: corpo de 20261011301000 IGUAL + "pago_falta_aprovar" por pessoa
-- ---------------------------------------------------------------------------------------------
create or replace function public.resumo_freelancers(
  p_de date default null,
  p_ate date default null,
  p_autor uuid default null,
  p_atalho text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_pessoas jsonb := '[]'::jsonb;
  f record;
  c jsonb;
  v_ultimo date;
begin
  for f in
    select distinct p.id, p.name
      from public.payees p
      join public.work_profiles wp on wp.payee_id = p.id and wp.modo_pagamento = 'diaria'
     where p.active
     order by p.name
  loop
    c := public.conta_corrente_freelancer(f.id, p_de, p_ate, p_autor, p_atalho);
    select max(l.data) into v_ultimo
      from public._conta_corrente_linhas(f.id) l
     where l.tipo = 'pagamento'
       and l.data <= coalesce((c ->> 'ate')::date, date '9999-12-31')
       and l.data >= coalesce((c ->> 'de')::date, date '1900-01-01');
    v_pessoas := v_pessoas || jsonb_build_object(
      'id', f.id, 'nome', f.name,
      'diaria', c -> 'favorecido' -> 'diaria',
      'desde', c -> 'favorecido' -> 'desde',
      'de', c -> 'de', 'ate', c -> 'ate',
      'dias', c -> 'dias', 'trabalhado', c -> 'trabalhado', 'reembolsos', c -> 'reembolsos', 'pago', c -> 'pago',
      'pago_aguardando_banco', c -> 'pago_aguardando_banco',
      'pago_falta_aprovar', c -> 'pago_falta_aprovar',
      'ultimo_pagamento', v_ultimo,
      'saldo_final', c -> 'saldo_final', 'estado', c -> 'estado');
  end loop;

  return jsonb_build_object(
    'pessoas', v_pessoas,
    'atalho', p_atalho,
    'trabalhado', coalesce((select sum((x ->> 'trabalhado')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'reembolsos', coalesce((select sum((x ->> 'reembolsos')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'pago', coalesce((select sum((x ->> 'pago')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'dias', coalesce((select sum((x ->> 'dias')::numeric) from jsonb_array_elements(v_pessoas) x), 0),
    'deve', coalesce((select sum(greatest((x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0),
    'adiantado', coalesce((select sum(greatest(-(x ->> 'saldo_final')::numeric, 0)) from jsonb_array_elements(v_pessoas) x), 0)
  );
end;
$$;
