-- "Este Pix paga…": uma entrada do banco aplicada em uma ou mais contas a receber — forma A, F2
-- (02/10/2026, autorizada pelo dono: "pode aplicar").
--
-- Depois da F1 o pagamento sabe de qual Pix veio (payments.bank_transaction_id) e vários
-- pagamentos podem vir da mesma entrada. Aqui está a ação: o financeiro escolhe as contas e
-- quanto da entrada vai para cada uma; o banco cria um pagamento por conta, com a data e a forma
-- da entrada, e acerta saldo e situação de cada conta. Serve para:
--   - um Pix que paga várias OS (o caso do Lenine: R$ 4.800 = sinal do ORÇ-00074 + do 00077);
--   - uma OS paga em vários Pix (cada entrada aplicada na mesma conta, até quitar);
--   - "associar outra OS" ao Pix que sobrou depois de pagar a primeira conta;
--   - o pagamento já lançado à mão (o "Receber sinal" do orçamento) e o Pix chegando depois: a
--     entrada passa a ser a origem daquele pagamento, sem criar outro (item {pagamento_id}).
--
-- Regras do dono (02/10/2026): pagou a mais até R$ 10 é receita; faltou até R$ 10 pode ser
-- acertado sozinho (desconto). Acima disso, avaliar: a função recusa e explica. A entrada tem de
-- ser aplicada por inteiro — a sobra virando crédito do cliente é a fase seguinte (F3).
--
-- O vínculo antigo (receivables.bank_transaction_id, uma linha ↔ uma conta, índice único) fica
-- com UMA conta da entrada (a "dona"); as outras se ligam pelo pagamento. Por isso as regras que
-- supunham uma linha, uma conta ganham proteção (levantamento das telas de 02/10):
--   - desfazer, cancelar ou desfazer a aplicação numa das contas NÃO solta a entrada enquanto
--     outra conta continua paga por ela (_reacomodar_entrada passa a "dona" para outra conta);
--   - ajustar ao valor do banco recusa quando a entrada também paga outra conta (contaria o
--     mesmo dinheiro duas vezes);
--   - conciliar_lancamento recusa entrada que já paga alguma conta e não reaproveita pagamento
--     que já veio de outra entrada (o gatilho da F1 trocaria a origem dele em silêncio).
-- A conciliação (conciliacao_lancamentos, que alimenta o "Mês pronto?") passa a enxergar a conta
-- paga pela entrada mesmo sem o vínculo antigo, e compara a entrada com tudo o que foi aplicado
-- dela. Medido em 02/10 antes de trocar: só os sinais ORÇ-00074 e 00077 mudam (de "sem extrato"
-- para conciliados, sem diferença); nenhum mês passa a travar. Contas a pagar: nada muda.

-- 1. Quem segura a entrada quando uma das contas sai ------------------------------------------
-- Se ainda há pagamento confirmado de conta a receber vindo da entrada, ela continua conciliada,
-- aponta para um deles e, se nenhuma conta segura o vínculo antigo, a conta desse pagamento passa
-- a segurar. Devolve false quando nada mais da entrada está aplicado (quem chamou decide soltar).
create or replace function public._reacomodar_entrada(p_tx uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_um uuid;
begin
  if p_tx is null then return false; end if;
  select x.id into v_um
    from public.payments x
   where x.bank_transaction_id = p_tx and x.status = 'confirmed' and x.receivable_id is not null
   order by (x.id = (select t.reconciled_payment_id from public.bank_transactions t where t.id = p_tx)) desc,
            x.created_at
   limit 1;
  if v_um is null then return false; end if;

  update public.bank_transactions set reconciled = true, reconciled_payment_id = v_um where id = p_tx;
  update public.receivables set bank_transaction_id = p_tx
   where id = (select receivable_id from public.payments where id = v_um)
     and bank_transaction_id is null
     and not exists (select 1 from public.receivables where bank_transaction_id = p_tx);
  return true;
end;
$$;
revoke all on function public._reacomodar_entrada(uuid) from public;
revoke all on function public._reacomodar_entrada(uuid) from anon;
revoke all on function public._reacomodar_entrada(uuid) from authenticated;

-- 2. Aplicar uma entrada em contas a receber --------------------------------------------------
create or replace function public.aplicar_entrada_em_contas(
  p_transacao uuid,
  p_aplicacoes jsonb,
  p_motivo text default null,
  p_autor uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c_tolerancia constant numeric := 10;  -- dono, 02/10/2026
  v_autor uuid := public._autor_do_financeiro(p_autor);
  t public.bank_transactions%rowtype;
  r public.receivables%rowtype;
  pg public.payments%rowtype;
  v_item jsonb;
  v_ja numeric;
  v_restante numeric;
  v_total numeric := 0;
  v_valor numeric;
  v_saldo numeric;
  v_acrescimo numeric;
  v_desconto numeric;
  v_quitar boolean;
  v_novo_valor numeric;
  v_novo_pago numeric;
  v_metodo text;
  v_pagamento uuid;
  v_primeiro uuid;
  v_dono_da_linha uuid;
  v_varias boolean;
  v_n integer := 0;
  v_feitos jsonb := '[]'::jsonb;
  v_nota text;
  v_hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
  v_msg text;
begin
  select * into t from public.bank_transactions where id = p_transacao for update;
  if not found then raise exception 'Linha do extrato não encontrada.'; end if;
  if t.transaction_type <> 'credit' then
    raise exception 'Só uma entrada do banco paga contas a receber.';
  end if;
  if t.dismissed_kind is not null then
    raise exception 'Essa entrada está fora da fila (%). Traga-a de volta em Extrato › Fora da fila antes de aplicar.', t.dismissed_kind;
  end if;
  perform public._recusa_se_mes_fechado(t.transaction_date, 'aplicar esta entrada');
  if exists (select 1 from public.payables where bank_transaction_id = t.id and status <> 'cancelled') then
    raise exception 'Essa entrada está ligada a uma conta a pagar. Desfaça aquele vínculo antes.';
  end if;

  if p_aplicacoes is null or jsonb_typeof(p_aplicacoes) <> 'array' or jsonb_array_length(p_aplicacoes) = 0 then
    raise exception 'Escolha ao menos uma conta para esta entrada pagar.';
  end if;
  if (select count(distinct coalesce(e ->> 'receivable_id', 'p:' || (e ->> 'pagamento_id'))) from jsonb_array_elements(p_aplicacoes) e)
     <> jsonb_array_length(p_aplicacoes) then
    raise exception 'A mesma conta apareceu duas vezes.';
  end if;
  if exists (select 1 from jsonb_array_elements(p_aplicacoes) e
              where e ->> 'pagamento_id' is null
                and ((e ->> 'receivable_id') is null or (e ->> 'valor') is null or round((e ->> 'valor')::numeric, 2) <= 0)) then
    raise exception 'Cada conta escolhida precisa de um valor maior que zero.';
  end if;

  select coalesce(sum(p.amount), 0) into v_ja
    from public.payments p
   where p.bank_transaction_id = t.id and p.status = 'confirmed' and p.receivable_id is not null;
  v_restante := round(t.amount - v_ja, 2);
  if v_restante <= 0.005 then
    raise exception 'Esta entrada (%) já está toda aplicada.', public._brl(t.amount);
  end if;

  -- Total: valores novos + pagamentos já lançados que esta entrada passa a explicar.
  select round(coalesce(sum((e ->> 'valor')::numeric) filter (where e ->> 'pagamento_id' is null), 0)
               + coalesce(sum(p.amount) filter (where e ->> 'pagamento_id' is not null), 0), 2)
    into v_total
    from jsonb_array_elements(p_aplicacoes) e
    left join public.payments p on p.id = (e ->> 'pagamento_id')::uuid;
  if v_total > v_restante + 0.005 then
    raise exception 'As contas somam %, mas desta entrada faltam aplicar %.', public._brl(v_total), public._brl(v_restante);
  end if;
  if v_total < v_restante - 0.005 then
    raise exception 'Sobram % desta entrada (de %). Aplique o valor inteiro: guardar a sobra como crédito do cliente chega na próxima etapa.',
      public._brl(v_restante - v_total), public._brl(v_restante);
  end if;

  v_metodo := case
    when coalesce(t.payment_method, '') ilike '%pix%' or coalesce(t.description, '') ilike '%pix%' then 'pix'
    when t.card_last_digits is not null then 'debit_card'
    else 'bank_transfer' end;
  v_varias := jsonb_array_length(p_aplicacoes) > 1 or v_ja > 0;
  select id into v_dono_da_linha from public.receivables where bank_transaction_id = t.id limit 1;

  for v_item in select * from jsonb_array_elements(p_aplicacoes) loop
    if v_item ->> 'pagamento_id' is not null then
      -- Pagamento já lançado à mão: a entrada passa a ser a origem dele.
      select * into pg from public.payments where id = (v_item ->> 'pagamento_id')::uuid for update;
      if not found or pg.receivable_id is null then raise exception 'Pagamento de conta a receber não encontrado.'; end if;
      if pg.status <> 'confirmed' then raise exception 'Esse pagamento foi estornado.'; end if;
      if pg.bank_transaction_id is not null then
        raise exception 'Esse pagamento já está ligado a outra entrada do banco.';
      end if;
      select * into r from public.receivables where id = pg.receivable_id for update;
      if r.status = 'cancelled' then raise exception '"%" está cancelada.', r.description; end if;

      update public.payments set bank_transaction_id = t.id where id = pg.id;
      update public.receivables
         set bank_transaction_id = case when bank_transaction_id is null and v_dono_da_linha is null then t.id
                                        else bank_transaction_id end,
             notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] O pagamento de ' || public._brl(pg.amount)
                     || ' de ' || to_char(pg.payment_date, 'DD/MM/YYYY') || ' veio da entrada de '
                     || to_char(t.transaction_date, 'DD/MM/YYYY') || ' (' || public._brl(t.amount) || ').')
       where id = r.id;
      v_pagamento := pg.id;
      v_valor := pg.amount;
      v_acrescimo := 0;
      v_desconto := 0;
    else
      select * into r from public.receivables where id = (v_item ->> 'receivable_id')::uuid for update;
      if not found then raise exception 'Conta a receber não encontrada.'; end if;
      if r.status not in ('pending', 'overdue', 'partially_paid') then
        raise exception '"%" não está em aberto (%).', r.description,
          case r.status when 'paid' then 'já está paga' when 'cancelled' then 'está cancelada' else r.status end;
      end if;
      perform public._recusa_se_mes_fechado(r.issue_date, 'receber nesta conta');

      v_valor := round((v_item ->> 'valor')::numeric, 2);
      v_quitar := coalesce((v_item ->> 'quitar')::boolean, false);
      v_saldo := round(r.amount - coalesce(r.paid_amount, 0), 2);
      v_acrescimo := 0;
      v_desconto := 0;
      v_novo_valor := r.amount;

      if v_valor > v_saldo + 0.005 then
        v_acrescimo := round(v_valor - v_saldo, 2);
        if v_acrescimo > c_tolerancia then
          raise exception 'Em "%" o valor passa do que falta receber (%) em %. Acima de R$ 10, avalie o porquê antes: pode ser outra conta do cliente ou crédito dele.',
            r.description, public._brl(v_saldo), public._brl(v_acrescimo);
        end if;
        v_novo_valor := r.amount + v_acrescimo;
      end if;
      v_novo_pago := round(coalesce(r.paid_amount, 0) + v_valor, 2);

      if v_quitar and v_novo_valor - v_novo_pago > 0.005 then
        v_desconto := round(v_novo_valor - v_novo_pago, 2);
        if v_desconto > c_tolerancia then
          raise exception 'Em "%" ainda faltariam % — acima de R$ 10 não se quita por desconto sozinho.',
            r.description, public._brl(v_desconto);
        end if;
        v_novo_valor := v_novo_pago;
      end if;

      insert into public.payments (receivable_id, amount, payment_date, payment_method, installments,
                                   card_fee_percent, net_amount, notes, status, bank_transaction_id)
      values (r.id, v_valor, t.transaction_date, v_metodo, 1, 0, v_valor,
              'Conciliado com o extrato de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
                || case when v_varias then ' (entrada de ' || public._brl(t.amount) || ' que pagou mais de uma conta).' else '.' end,
              'confirmed', t.id)
      returning id into v_pagamento;

      v_nota := '[' || v_hoje || '] Recebido ' || public._brl(v_valor) || ' da entrada de '
                || to_char(t.transaction_date, 'DD/MM/YYYY') || ' (' || public._brl(t.amount) || ')'
                || case when v_acrescimo > 0 then '; pagou ' || public._brl(v_acrescimo) || ' a mais (receita)' else '' end
                || case when v_desconto > 0 then '; ' || public._brl(v_desconto) || ' deixam de ser cobrados (desconto)' else '' end
                || '.' || coalesce(' Motivo: ' || nullif(btrim(p_motivo), '') || '.', '');

      update public.receivables
         set amount = v_novo_valor,
             paid_amount = v_novo_pago,
             balance_amount = greatest(0, round(v_novo_valor - v_novo_pago, 2)),
             status = public._situacao_do_saldo(v_novo_valor, v_novo_pago, status),
             bank_transaction_id = case when bank_transaction_id is null and v_dono_da_linha is null then t.id
                                        else bank_transaction_id end,
             notes = btrim(coalesce(notes, '') || ' ' || v_nota)
       where id = r.id;
    end if;

    if v_dono_da_linha is null and r.bank_transaction_id is null then
      v_dono_da_linha := r.id;
    end if;
    v_primeiro := coalesce(v_primeiro, v_pagamento);
    v_n := v_n + 1;
    v_feitos := v_feitos || jsonb_build_object(
      'receivable_id', r.id, 'descricao', r.description, 'pagamento', v_pagamento, 'valor', v_valor,
      'ligado', v_item ->> 'pagamento_id' is not null,
      'valor_antes', r.amount, 'acrescimo', v_acrescimo, 'desconto', v_desconto);
  end loop;

  update public.bank_transactions
     set reconciled = true,
         reconciled_payment_id = coalesce(reconciled_payment_id, v_primeiro)
   where id = t.id;
  update public.finance_review_queue
     set status = 'superseded', decision_note = 'Aplicada em ' || v_n || ' conta(s) a receber'
   where bank_transaction_id = t.id and status = 'pending';

  v_msg := 'Entrada de ' || public._brl(t.amount) || ' de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
           || ' aplicada em ' || v_n || case when v_n = 1 then ' conta' else ' contas' end || ': '
           || (select string_agg(f ->> 'descricao' || ' ' || public._brl((f ->> 'valor')::numeric), ', ')
                 from jsonb_array_elements(v_feitos) f) || '.';

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, depois)
  values ('aplicou_pix', v_autor, t.id, case when v_n = 1 then (v_feitos -> 0 ->> 'receivable_id')::uuid end,
          v_total, left(coalesce(nullif(btrim(p_motivo), '') || ' · ', '') || v_msg, 300),
          jsonb_build_object('aplicacoes', v_feitos, 'ja_aplicado_antes', v_ja));

  return jsonb_build_object('ok', true, 'aplicado', v_total, 'contas', v_n, 'aplicacoes', v_feitos, 'message', v_msg);
end;
$$;
comment on function public.aplicar_entrada_em_contas(uuid, jsonb, text, uuid) is
  'Aplica uma entrada do banco em contas a receber. Itens: {receivable_id, valor, quitar?} cria um pagamento; {pagamento_id} faz da entrada a origem de um pagamento já lançado. Tolerância de R$ 10 para mais (receita) e, com quitar, para menos (desconto).';
revoke all on function public.aplicar_entrada_em_contas(uuid, jsonb, text, uuid) from public;
revoke all on function public.aplicar_entrada_em_contas(uuid, jsonb, text, uuid) from anon;
grant execute on function public.aplicar_entrada_em_contas(uuid, jsonb, text, uuid) to authenticated, service_role;

-- 3. Desfazer uma aplicação --------------------------------------------------------------------
create or replace function public.desfazer_aplicacao(
  p_pagamento uuid,
  p_motivo text default null,
  p_autor uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  p public.payments%rowtype;
  r public.receivables%rowtype;
  t public.bank_transactions%rowtype;
  v_aplic jsonb;
  v_ligado boolean;
  v_valor_original numeric;
  v_novo_pago numeric;
  v_continua boolean;
  v_msg text;
  v_hoje text := to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');
begin
  select * into p from public.payments where id = p_pagamento for update;
  if not found or p.receivable_id is null then raise exception 'Pagamento de conta a receber não encontrado.'; end if;
  if p.status <> 'confirmed' then raise exception 'Este pagamento já foi estornado.'; end if;
  if p.bank_transaction_id is null then
    raise exception 'Este pagamento não veio de uma entrada do banco. Para estorná-lo, use o histórico de pagamentos da conta.';
  end if;
  select * into r from public.receivables where id = p.receivable_id for update;
  select * into t from public.bank_transactions where id = p.bank_transaction_id for update;
  perform public._recusa_se_mes_fechado(p.payment_date, 'desfazer esta aplicação');

  select a into v_aplic
    from public.reconciliation_log l, jsonb_array_elements(l.depois -> 'aplicacoes') a
   where l.acao = 'aplicou_pix' and l.bank_transaction_id = t.id and (a ->> 'pagamento')::uuid = p.id
   order by l.ocorrido_em desc limit 1;
  -- Sem registro da aplicação (pagamento ligado à entrada por outro caminho), vale a observação:
  -- o que a conciliação criou começa com "Concilia…"; o resto foi lançado à mão.
  v_ligado := case when v_aplic is not null then coalesce((v_aplic ->> 'ligado')::boolean, false)
                   else coalesce(p.notes, '') not ilike 'concilia%' end;

  if v_ligado then
    -- Era um pagamento lançado à mão: continua valendo, só deixa de vir desta entrada.
    update public.payments set bank_transaction_id = null where id = p.id;
    update public.receivables
       set bank_transaction_id = case when bank_transaction_id = t.id then null else bank_transaction_id end,
           notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] O pagamento de ' || public._brl(p.amount)
                   || ' deixou de vir da entrada de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
                   || coalesce(': ' || nullif(btrim(p_motivo), ''), '') || '.')
     where id = r.id;
    v_valor_original := r.amount;
    v_novo_pago := r.paid_amount;
  else
    -- Pagamento criado pela aplicação: estorna, e o acréscimo ou o desconto dela voltam.
    v_valor_original := case when v_aplic is not null
                               and (coalesce((v_aplic ->> 'acrescimo')::numeric, 0) > 0 or coalesce((v_aplic ->> 'desconto')::numeric, 0) > 0)
                             then r.amount - coalesce((v_aplic ->> 'acrescimo')::numeric, 0) + coalesce((v_aplic ->> 'desconto')::numeric, 0)
                             else r.amount end;
    update public.payments
       set status = 'cancelled', cancelled_at = now(),
           cancellation_reason = left('Aplicação desfeita' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
     where id = p.id;
    v_novo_pago := greatest(0, round(coalesce(r.paid_amount, 0) - p.amount, 2));
    update public.receivables
       set amount = v_valor_original,
           paid_amount = v_novo_pago,
           balance_amount = greatest(0, round(v_valor_original - v_novo_pago, 2)),
           status = public._situacao_do_saldo(v_valor_original, v_novo_pago, status),
           bank_transaction_id = case
             when bank_transaction_id = t.id and not exists (
                    select 1 from public.payments x
                     where x.receivable_id = r.id and x.bank_transaction_id = t.id and x.status = 'confirmed')
             then null else bank_transaction_id end,
           notes = btrim(coalesce(notes, '') || ' [' || v_hoje || '] Aplicação de ' || public._brl(p.amount)
                   || ' da entrada de ' || to_char(t.transaction_date, 'DD/MM/YYYY') || ' desfeita'
                   || coalesce(': ' || nullif(btrim(p_motivo), ''), '') || '.')
     where id = r.id;
  end if;

  v_continua := public._reacomodar_entrada(t.id);
  if not v_continua then
    update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = t.id;
  end if;

  v_msg := case when v_ligado
                then 'O pagamento de ' || public._brl(p.amount) || ' de "' || r.description
                     || '" continua valendo, mas deixou de vir da entrada de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
                else 'Aplicação desfeita: ' || public._brl(p.amount) || ' da entrada de ' || to_char(t.transaction_date, 'DD/MM/YYYY')
                     || ' voltaram a faltar em "' || r.description || '"' end
           || case when v_continua then '; o resto da entrada continua aplicado nas outras contas.'
                   else '; a entrada voltou para a fila do Extrato.' end;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, antes, depois)
  values ('desfez_aplicacao', v_autor, t.id, r.id, p.amount,
          left(coalesce(nullif(btrim(p_motivo), '') || ' · ', '') || v_msg, 300),
          jsonb_build_object('pagamento', p.id, 'ligado', v_ligado, 'amount', r.amount, 'paid_amount', r.paid_amount, 'status', r.status),
          jsonb_build_object('amount', v_valor_original, 'paid_amount', v_novo_pago));

  return jsonb_build_object('ok', true, 'entrada_livre', not v_continua, 'message', v_msg);
end;
$$;
comment on function public.desfazer_aplicacao(uuid, text, uuid) is
  'Desfaz uma aplicação de entrada do banco: estorna o pagamento criado por ela (devolvendo saldo, acréscimo e desconto) ou, se era pagamento já lançado, só o desliga; solta a entrada quando nada mais dela fica aplicado.';
revoke all on function public.desfazer_aplicacao(uuid, text, uuid) from public;
revoke all on function public.desfazer_aplicacao(uuid, text, uuid) from anon;
grant execute on function public.desfazer_aplicacao(uuid, text, uuid) to authenticated, service_role;

-- 4. Desfazer a aprovação: a entrada só volta para a fila se não pagar mais nenhuma conta ---------
create or replace function public.desfazer_aprovacao(p_tipo text, p_id uuid, p_motivo text DEFAULT NULL::text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx uuid;
  v_nasceu boolean;
  v_pagamento_id uuid;
  v_pagamento_valor numeric;
  v_pago numeric;
  v_voltaram int := 0;
  v_acao text;
  v_nota text;
  v_msg text;
  v_grupo jsonb;
  v_continua boolean := false;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;

  if p_tipo = 'payable' then
    -- Pix dividido (pró-labore + retirada de sócio): as partes voltam a ser um lançamento só e o
    -- resto segue como sempre, sobre o principal (28/09/2026).
    v_grupo := public._divisao_de(p_id);
    p_id := public._juntar_divisao(p_id, 'desfazer a aprovação', v_autor);
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;
  if v_antes is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Este lançamento já está cancelado.'; end if;

  v_tx := (v_antes ->> 'bank_transaction_id')::uuid;
  if v_tx is null then
    raise exception 'Este lançamento não está ligado a nenhuma linha do extrato, então não há aprovação a desfazer. Para tirá-lo do resultado, cancele-o.';
  end if;
  perform public._recusa_se_mes_fechado((v_antes ->> 'issue_date')::date, 'desfazer esta aprovação');

  v_nasceu := public._nasceu_do_extrato(p_tipo, p_id);
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] ';

  if v_nasceu then
    -- A receita que nasceu da entrada é a entrada inteira; se a entrada também paga outra conta,
    -- desfazer aqui devolveria à fila um dinheiro que continua aplicado (02/10/2026).
    if p_tipo = 'receivable' and exists (
         select 1 from public.payments x
          where x.bank_transaction_id = v_tx and x.status = 'confirmed' and x.receivable_id <> p_id) then
      raise exception 'Esta entrada do extrato também paga outra(s) conta(s). Desfaça aquelas aplicações antes de desfazer esta aprovação.';
    end if;
    v_acao := 'desfez_aprovacao';
    v_nota := v_nota || 'Aprovação desfeita' || coalesce(': ' || nullif(btrim(p_motivo), ''), '') || '.';

    update public.payments
       set status = 'cancelled', cancelled_at = now(), cancellation_reason = left('Aprovação desfeita' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
     where status = 'confirmed'
       and ((p_tipo = 'payable' and payable_id = p_id) or (p_tipo = 'receivable' and receivable_id = p_id));

    if p_tipo = 'payable' then
      update public.payables set status = 'cancelled', bank_transaction_id = null,
             notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
      update public.finance_review_queue
         set status = 'pending', decided_by = null, decided_at = null, created_payable_id = null,
             decision_note = v_nota
       where created_payable_id = p_id;
    else
      update public.receivables set status = 'cancelled', bank_transaction_id = null,
             notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
      update public.finance_review_queue
         set status = 'pending', decided_by = null, decided_at = null, created_receivable_id = null,
             decision_note = v_nota
       where created_receivable_id = p_id;
    end if;
    get diagnostics v_voltaram = row_count;

    update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
    v_msg := 'Aprovação desfeita: o lançamento foi cancelado e a linha do extrato voltou para a fila.';
  else
    v_acao := 'desconciliou';
    v_pago := coalesce((v_antes ->> 'paid_amount')::numeric, 0);

    if p_tipo = 'payable' then
      -- O pagamento que o CASAMENTO registrou sai junto. Pagamento lançado à mão e só depois
      -- ligado ao extrato continua valendo — medido em 25/09/2026: das 49 linhas do extrato
      -- com pagamento ligado, parte foi criada pela conciliação ("Conciliação automática…",
      -- "Conciliado com o extrato…") e parte pelo dono, semanas antes do casamento. Estornar
      -- o segundo tipo desfaria um recebimento que aconteceu.
      select p.id, p.amount into v_pagamento_id, v_pagamento_valor
        from public.bank_transactions t join public.payments p on p.id = t.reconciled_payment_id
       where t.id = v_tx and p.status = 'confirmed'
         and coalesce(p.notes, '') ilike 'concilia%'
         and p.payable_id = p_id;
      if v_pagamento_id is not null then
        update public.payments
           set status = 'cancelled', cancelled_at = now(),
               cancellation_reason = left('Vínculo com o extrato desfeito' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
         where id = v_pagamento_id;
        v_pago := greatest(0, v_pago - v_pagamento_valor);
      end if;
      update public.payables set bank_transaction_id = null,
             paid_amount = v_pago,
             balance_amount = greatest(0, amount - v_pago),
             status = public._situacao_do_saldo(amount, v_pago, status)
       where id = p_id;
      update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
    else
      -- Conta a receber: os pagamentos dela que vieram desta entrada pelo casamento ("Concilia…")
      -- são estornados; os lançados à mão continuam valendo e só deixam de vir dela. A entrada
      -- só volta para a fila se não pagar mais nenhuma conta (um Pix para várias contas, F2).
      select (array_agg(p.id order by p.created_at))[1], coalesce(sum(p.amount), 0)
        into v_pagamento_id, v_pagamento_valor
        from public.payments p
       where p.receivable_id = p_id and p.status = 'confirmed'
         and coalesce(p.notes, '') ilike 'concilia%'
         and (p.bank_transaction_id = v_tx
              or p.id = (select t.reconciled_payment_id from public.bank_transactions t where t.id = v_tx));
      if v_pagamento_id is not null then
        update public.payments
           set status = 'cancelled', cancelled_at = now(),
               cancellation_reason = left('Vínculo com o extrato desfeito' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
         where receivable_id = p_id and status = 'confirmed'
           and coalesce(notes, '') ilike 'concilia%'
           and (bank_transaction_id = v_tx
                or id = (select t.reconciled_payment_id from public.bank_transactions t where t.id = v_tx));
        v_pago := greatest(0, v_pago - v_pagamento_valor);
      end if;
      update public.payments set bank_transaction_id = null
       where receivable_id = p_id and status = 'confirmed' and bank_transaction_id = v_tx;

      update public.receivables set bank_transaction_id = null,
             paid_amount = v_pago,
             balance_amount = greatest(0, amount - v_pago),
             status = public._situacao_do_saldo(amount, v_pago, status)
       where id = p_id;
      v_continua := public._reacomodar_entrada(v_tx);
      if not v_continua then
        update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
      end if;
    end if;

    v_msg := 'Vínculo desfeito: o lançamento continua valendo e '
      || case when v_continua then 'a linha do extrato continua pagando a(s) outra(s) conta(s).'
              else 'a linha do extrato voltou para a fila.' end
      || case when v_pagamento_id is not null then ' O pagamento que o casamento tinha registrado foi estornado.'
              when v_pago > 0 then ' O pagamento registrado à mão continua valendo.'
              else '' end;
  end if;

  if v_grupo is not null then
    v_msg := v_msg || ' ' || (v_grupo ->> 'frase');
  end if;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    v_acao, v_autor, v_tx,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    (v_antes ->> 'amount')::numeric,
    left(coalesce(nullif(btrim(p_motivo), ''), v_msg) || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'bank_transaction_id', v_tx, 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('status', case when v_nasceu then 'cancelled' else null end, 'bank_transaction_id', null,
                       'proposta_voltou', v_voltaram > 0, 'pagamento_estornado', v_pagamento_id,
                       'entrada_continua_em_outras_contas', v_continua)
  );

  return jsonb_build_object('ok', true, 'acao', v_acao, 'proposta_voltou', v_voltaram > 0, 'message', v_msg);
end;
$function$;

-- 5. Cancelar: a entrada só volta para a fila se não pagar mais nenhuma conta ---------------------
create or replace function public.cancelar_lancamento(p_tipo text, p_id uuid, p_motivo text, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx uuid;
  v_nasceu boolean;
  v_caixa boolean;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_nota text;
  v_destino text := null;
  v_grupo jsonb;
  v_linhas uuid[] := '{}';
  v_linha uuid;
  v_outras_soltas int := 0;
  v_outras_seguem int := 0;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;
  if v_motivo is null or length(v_motivo) < 3 then
    raise exception 'Diga por que o lançamento está sendo cancelado.';
  end if;

  if p_tipo = 'payable' then
    -- Pix dividido (pró-labore + retirada de sócio): as partes voltam a ser um lançamento só e o
    -- cancelamento vale para o pagamento inteiro (28/09/2026).
    v_grupo := public._divisao_de(p_id);
    p_id := public._juntar_divisao(p_id, 'cancelar o lançamento', v_autor);
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;
  if v_antes is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Este lançamento já está cancelado.'; end if;
  perform public._recusa_se_mes_fechado((v_antes ->> 'issue_date')::date, 'cancelar este lançamento');

  v_tx := (v_antes ->> 'bank_transaction_id')::uuid;
  v_nasceu := v_tx is not null and public._nasceu_do_extrato(p_tipo, p_id);
  v_caixa := v_tx is not null and exists (
    select 1 from public.bank_transactions t
     where t.id = v_tx and (t.bank_ref_id like 'caixa:%' or t.source_type = 'cash'));
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] Cancelado: ' || v_motivo;

  -- Entradas de onde vieram os pagamentos desta conta a receber (um Pix pode pagar várias contas).
  if p_tipo = 'receivable' then
    select coalesce(array_agg(distinct x.bank_transaction_id), '{}') into v_linhas
      from public.payments x
     where x.receivable_id = p_id and x.status = 'confirmed' and x.bank_transaction_id is not null
       and x.bank_transaction_id is distinct from v_tx;
  end if;

  update public.payments
     set status = 'cancelled', cancelled_at = now(), cancellation_reason = left('Lançamento cancelado: ' || v_motivo, 200)
   where status = 'confirmed'
     and ((p_tipo = 'payable' and payable_id = p_id) or (p_tipo = 'receivable' and receivable_id = p_id));

  if p_tipo = 'payable' then
    update public.payables set status = 'cancelled', bank_transaction_id = null,
           notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
    update public.finance_review_queue set status = 'superseded', decision_note = v_nota
     where created_payable_id = p_id;
  else
    update public.receivables set status = 'cancelled', bank_transaction_id = null,
           notes = btrim(coalesce(notes, '') || ' ' || v_nota) where id = p_id;
    update public.finance_review_queue set status = 'superseded', decision_note = v_nota
     where created_receivable_id = p_id;
  end if;

  if v_tx is not null then
    if v_caixa then
      -- Linha do Caixa: quem a criou foi o lançamento; cancelado ele, o dinheiro não saiu (ou
      -- não entrou). Sai do saldo e não vai para a fila do Extrato.
      update public.bank_transactions set
        reconciled = true, reconciled_payment_id = null,
        dismissed_kind = 'estornada',
        dismissed_reason = left('Lançamento do Caixa cancelado: ' || v_motivo, 300),
        dismissed_at = now(),
        dismissed_by = v_autor
      where id = v_tx;
      v_destino := 'caixa_estornado';
    elsif p_tipo = 'receivable' and public._reacomodar_entrada(v_tx) then
      -- A entrada também paga outra conta: continua conciliada, segurada por ela.
      v_destino := 'outras_contas';
    elsif v_nasceu then
      update public.bank_transactions set
        reconciled = true, reconciled_payment_id = null,
        dismissed_kind = 'manual',
        dismissed_reason = left('Lançamento cancelado: ' || v_motivo, 300),
        dismissed_at = now(),
        dismissed_by = v_autor
      where id = v_tx;
      v_destino := 'fora_da_fila';
    else
      update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
      v_destino := 'fila';
    end if;
  end if;

  -- As outras entradas que pagavam esta conta (sem o vínculo antigo): seguem conciliadas se ainda
  -- pagam outra conta; senão voltam para a fila.
  foreach v_linha in array v_linhas loop
    if public._reacomodar_entrada(v_linha) then
      v_outras_seguem := v_outras_seguem + 1;
    else
      update public.bank_transactions set reconciled = false, reconciled_payment_id = null
       where id = v_linha and dismissed_kind is null;
      v_outras_soltas := v_outras_soltas + 1;
    end if;
  end loop;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'cancelou_lancamento', v_autor, v_tx,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    (v_antes ->> 'amount')::numeric,
    left(v_motivo || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'bank_transaction_id', v_tx, 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('status', 'cancelled', 'linha_do_extrato', v_destino,
                       'outras_entradas', to_jsonb(v_linhas), 'outras_voltaram_a_fila', v_outras_soltas)
  );

  return jsonb_build_object(
    'ok', true,
    'linha_do_extrato', v_destino,
    'message', 'Lançamento cancelado.'
      || case v_destino
           when 'caixa_estornado' then ' O Caixa deixou de contar este valor.'
           when 'fora_da_fila' then ' A linha do extrato foi para "Fora da fila" com o mesmo motivo; de lá ela pode voltar.'
           when 'fila' then ' A linha do extrato voltou para a fila.'
           when 'outras_contas' then ' A linha do extrato continua pagando a(s) outra(s) conta(s).'
           else '' end
      || case when v_outras_soltas > 0 then ' ' || v_outras_soltas || ' entrada(s) do extrato que pagavam esta conta voltaram para a fila.' else '' end
      || case when v_outras_seguem > 0 then ' ' || v_outras_seguem || ' entrada(s) do extrato que pagavam esta conta continuam pagando outras contas.' else '' end
      || coalesce(' ' || (v_grupo ->> 'frase'), '')
  );
end;
$function$;

-- 6. Conciliar: não casar entrada que já paga conta, nem roubar pagamento de outra entrada --------
create or replace function public.conciliar_lancamento(p_tipo text, p_id uuid, p_transacao uuid, p_autor uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx public.bank_transactions%rowtype;
  v_aberto boolean;
  v_saldo numeric;
  v_valor_pago numeric := 0;
  v_pago numeric;
  v_pagamento uuid := null;
  v_pagamento_existente uuid := null;
  v_metodo text;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;

  if p_tipo = 'payable' then
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;
  if v_antes is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Lançamento cancelado não se concilia.'; end if;
  if v_antes ->> 'bank_transaction_id' is not null then
    raise exception 'Este lançamento já está casado com outra linha do extrato. Desfaça o vínculo antes.';
  end if;

  select * into v_tx from public.bank_transactions where id = p_transacao for update;
  if v_tx.id is null then raise exception 'Linha do extrato não encontrada.'; end if;
  if (p_tipo = 'payable' and v_tx.transaction_type <> 'debit')
     or (p_tipo = 'receivable' and v_tx.transaction_type <> 'credit') then
    raise exception 'Conta a pagar só casa com saída do banco; conta a receber, só com entrada.';
  end if;
  if v_tx.dismissed_kind is not null then
    raise exception 'Essa linha do extrato está fora da fila (%). Traga-a de volta antes de casar.', v_tx.dismissed_kind;
  end if;
  if exists (select 1 from public.payables where bank_transaction_id = p_transacao)
     or exists (select 1 from public.receivables where bank_transaction_id = p_transacao) then
    raise exception 'Essa linha do extrato já está vinculada a outro lançamento.';
  end if;
  -- Um Pix pode pagar várias contas (F2, 02/10/2026): entrada que já paga alguma conta não se
  -- casa de novo aqui — o que sobrou dela se aplica em "Este Pix paga…".
  if exists (select 1 from public.payments where bank_transaction_id = p_transacao and status = 'confirmed') then
    raise exception 'Essa linha do extrato já paga outra(s) conta(s). Para aplicar o que sobrou dela, use "Este Pix paga…".';
  end if;

  v_pago := coalesce((v_antes ->> 'paid_amount')::numeric, 0);
  v_aberto := v_antes ->> 'status' in ('pending', 'overdue', 'partially_paid');

  if v_aberto then
    perform public._recusa_se_mes_fechado(v_tx.transaction_date, 'registrar pagamento nesta data');
    v_saldo := coalesce((v_antes ->> 'balance_amount')::numeric, (v_antes ->> 'amount')::numeric - v_pago);
    v_valor_pago := round(least(v_saldo, v_tx.amount), 2);
    if v_valor_pago > 0 then
      v_metodo := case
        when coalesce(v_tx.payment_method, '') ilike '%pix%' or coalesce(v_tx.description, '') ilike '%pix%' then 'pix'
        when v_tx.card_last_digits is not null then 'debit_card'
        else 'bank_transfer' end;
      insert into public.payments (payable_id, receivable_id, amount, payment_date, payment_method,
                                   installments, card_fee_percent, net_amount, notes, status)
      values (
        case when p_tipo = 'payable' then p_id end,
        case when p_tipo = 'receivable' then p_id end,
        v_valor_pago, v_tx.transaction_date, v_metodo, 1, 0, v_valor_pago,
        'Conciliado com o extrato de ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY'),
        'confirmed'
      ) returning id into v_pagamento;
      v_pago := v_pago + v_valor_pago;
    end if;
  else
    -- Já pago: qual pagamento esta linha do extrato é? O de valor mais próximo, ainda sem
    -- linha do extrato, dentro de 2% (tarifa de maquininha costuma ficar abaixo disso).
    -- Pagamento que já veio de outra entrada fica de fora (o gatilho trocaria a origem dele).
    select p.id into v_pagamento_existente
      from public.payments p
     where p.status = 'confirmed'
       and ((p_tipo = 'payable' and p.payable_id = p_id) or (p_tipo = 'receivable' and p.receivable_id = p_id))
       and not exists (select 1 from public.bank_transactions t where t.reconciled_payment_id = p.id)
       and p.bank_transaction_id is null
       and abs(p.amount - v_tx.amount) <= greatest(0.01, p.amount * 0.02)
     order by abs(p.amount - v_tx.amount), abs(p.payment_date - v_tx.transaction_date)
     limit 1;
  end if;

  if p_tipo = 'payable' then
    update public.payables set bank_transaction_id = p_transacao,
           paid_amount = v_pago,
           balance_amount = greatest(0, amount - v_pago),
           status = public._situacao_do_saldo(amount, v_pago, status)
     where id = p_id;
  else
    update public.receivables set bank_transaction_id = p_transacao,
           paid_amount = v_pago,
           balance_amount = greatest(0, amount - v_pago),
           status = public._situacao_do_saldo(amount, v_pago, status)
     where id = p_id;
  end if;

  update public.bank_transactions
     set reconciled = true, reconciled_payment_id = coalesce(v_pagamento, v_pagamento_existente)
   where id = p_transacao;
  update public.finance_review_queue
     set status = 'superseded', decision_note = 'Casada com um lançamento que já existia'
   where bank_transaction_id = p_transacao and status = 'pending';

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'conciliou', v_autor, p_transacao,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    v_tx.amount,
    left(coalesce(v_antes ->> 'description', '') || ' ↔ ' || coalesce(v_tx.counterparty_name, v_tx.description, '')
         || ' de ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY'), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('bank_transaction_id', p_transacao, 'pagamento_registrado', v_pagamento,
                       'pagamento_existente', v_pagamento_existente, 'valor_pago', v_valor_pago)
  );

  return jsonb_build_object(
    'ok', true,
    'pagamento_registrado', v_pagamento is not null,
    'valor_pago', v_valor_pago,
    'message', case
      when v_pagamento is not null
        then 'Conciliado. Pagamento de ' || public._brl(v_valor_pago) || ' registrado em ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY') || '.'
      when v_pagamento_existente is not null
        then 'Conciliado com o pagamento que já estava lançado — nenhuma receita nova foi criada.'
      else 'Conciliado.' end
  );
end;
$function$;

-- 7. Ajustar ao valor do banco: recusa quando a entrada também paga outra conta ------------------
create or replace function public.ajustar_ao_valor_do_banco(
  p_tipo text,
  p_id uuid,
  p_motivo text default null,
  p_autor uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  r public.receivables%rowtype;
  t public.bank_transactions%rowtype;
  v_pagamento public.payments%rowtype;
  v_pagamentos integer;
  v_outras integer;
  v_banco numeric;
  v_dif numeric;
  v_msg text;
  v_nota text;
begin
  if p_tipo <> 'receivable' then
    raise exception 'O ajuste ao valor do banco vale para conta a receber. Numa conta a pagar, desfaça a aprovação e aprove de novo com o valor certo.';
  end if;

  select * into r from public.receivables where id = p_id for update;
  if not found then raise exception 'Lançamento não encontrado.'; end if;
  if r.status = 'cancelled' then raise exception 'Este lançamento está cancelado.'; end if;
  if r.bank_transaction_id is null then
    raise exception 'Este lançamento não está ligado a nenhuma linha do extrato: não há valor do banco para seguir.';
  end if;
  perform public._recusa_se_mes_fechado(r.issue_date, 'ajustar este lançamento ao valor do banco');

  select * into t from public.bank_transactions where id = r.bank_transaction_id;
  v_banco := abs(t.amount);

  -- A entrada também paga outra conta: o valor dela não é desta conta sozinha (F2, 02/10/2026).
  select count(distinct x.receivable_id) into v_outras
    from public.payments x
   where x.bank_transaction_id = t.id and x.status = 'confirmed'
     and x.receivable_id is not null and x.receivable_id <> r.id;
  if v_outras > 0 then
    raise exception 'Esta entrada de % também paga % outra(s) conta(s): ajustar esta conta ao valor inteiro dela contaria o mesmo dinheiro duas vezes. Para o que sobrou da entrada, use "Este Pix paga…".',
      public._brl(v_banco), v_outras;
  end if;

  -- Só o caso inequívoco: UM pagamento confirmado, e é o que a linha do banco registrou.
  select count(*) into v_pagamentos from public.payments where receivable_id = r.id and status = 'confirmed';
  select * into v_pagamento from public.payments
   where id = t.reconciled_payment_id and receivable_id = r.id and status = 'confirmed';
  if v_pagamentos <> 1 or v_pagamento.id is null then
    raise exception 'Este lançamento tem % pagamento(s) e nem todos vieram desta linha do banco. Confira os pagamentos antes: ajustar aqui apagaria a diferença sem saber de onde ela vem.',
      v_pagamentos;
  end if;

  v_dif := round(v_banco - r.amount, 2);
  if abs(v_dif) < 0.005 and abs(v_pagamento.amount - v_banco) < 0.005 then
    raise exception 'O lançamento já bate com o banco (%).', public._brl(v_banco);
  end if;

  v_msg := case
    when v_dif > 0 then 'Ajustado ao banco: o cliente pagou ' || public._brl(v_dif) || ' a mais; o lançamento passou de '
                        || public._brl(r.amount) || ' para ' || public._brl(v_banco) || '.'
    when v_dif < 0 then 'Ajustado ao banco: ' || public._brl(-v_dif) || ' deixam de ser cobrados (desconto); o lançamento passou de '
                        || public._brl(r.amount) || ' para ' || public._brl(v_banco) || '.'
    else 'Ajustado ao banco: o pagamento passou a ' || public._brl(v_banco) || '.'
  end;
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] ' || v_msg
            || coalesce(' Motivo: ' || nullif(btrim(p_motivo), '') || '.', '');

  -- O líquido acompanha quando era igual ao valor (Pix, transferência); com taxa de cartão ele
  -- é outro número e fica como está.
  update public.payments
     set amount = v_banco,
         net_amount = case when net_amount is null or round(net_amount, 2) = round(amount, 2) then v_banco else net_amount end
   where id = v_pagamento.id;
  update public.receivables
     set amount = v_banco, paid_amount = v_banco, balance_amount = 0, status = 'paid',
         notes = btrim(coalesce(notes, '') || ' ' || v_nota)
   where id = r.id;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, antes, depois)
  values ('ajustou_ao_banco', v_autor, t.id, r.id, v_banco,
          left(coalesce(nullif(btrim(p_motivo), ''), v_msg) || ' · ' || coalesce(r.description, ''), 300),
          jsonb_build_object('amount', r.amount, 'paid_amount', r.paid_amount, 'status', r.status, 'pagamento', v_pagamento.amount),
          jsonb_build_object('amount', v_banco, 'paid_amount', v_banco, 'status', 'paid', 'pagamento', v_banco));

  return jsonb_build_object('ok', true, 'antes', r.amount, 'depois', v_banco, 'diferenca', v_dif, 'message', v_msg);
end;
$$;
revoke all on function public.ajustar_ao_valor_do_banco(text, uuid, text, uuid) from public;
revoke all on function public.ajustar_ao_valor_do_banco(text, uuid, text, uuid) from anon;
grant execute on function public.ajustar_ao_valor_do_banco(text, uuid, text, uuid) to authenticated, service_role;

-- 8. Conciliação: a conta paga pela entrada aparece conciliada, e a diferença é da entrada inteira -
create or replace view public.conciliacao_lancamentos
with (security_invoker = on) as
 SELECT 'payable'::text AS lado,
    p.id,
    p.description,
    p.amount,
    p.status,
    p.due_date,
    p.issue_date,
    COALESCE(s.name, p.supplier_name) AS contraparte,
    p.expense_category AS categoria,
    p.bank_transaction_id,
        CASE
            WHEN p.bank_transaction_id IS NOT NULL THEN 'conciliado'::text
            WHEN p.payment_method = 'credito_fornecedor'::text THEN 'fora_do_banco'::text
            ELSE 'sem_extrato'::text
        END AS situacao,
    bt.transaction_date AS extrato_data,
    bt.amount AS extrato_valor,
    bt.description AS extrato_descricao,
        CASE
            WHEN p.bank_transaction_id IS NOT NULL THEN round(COALESCE(g.soma, p.amount) - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    p.origin = 'bank_reconciliation'::text OR (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_payable_id = p.id)) AS nasceu_do_extrato,
        CASE
            WHEN bt.installment_label ~ '^\d{1,2}/\d{1,2}$'::text AND split_part(bt.installment_label, '/'::text, 2)::integer >= 2 THEN abs(p.amount - split_part(bt.installment_label, '/'::text, 2)::integer::numeric * bt.amount) <= ((split_part(bt.installment_label, '/'::text, 2)::integer * (split_part(bt.installment_label, '/'::text, 2)::integer - 1))::numeric * 0.01)
            ELSE false
        END AS compra_parcelada,
        CASE
            WHEN bt.installment_label ~ '^\d{1,2}/\d{1,2}$'::text THEN split_part(bt.installment_label, '/'::text, 2)::integer
            ELSE NULL::integer
        END AS parcelas,
    d.payable_id IS NOT NULL AS lancada_em_dobro
   FROM payables p
     LEFT JOIN bank_transactions bt ON bt.id = p.bank_transaction_id
     LEFT JOIN suppliers s ON s.id = p.supplier_id
     LEFT JOIN compras_parceladas_em_dobro d ON d.payable_id = p.id
     LEFT JOIN LATERAL ( SELECT sum(x.amount) AS soma
           FROM payables x
          WHERE x.bank_transaction_id = p.bank_transaction_id AND x.status <> 'cancelled'::text AND COALESCE(x.divisao_id, x.id) = COALESCE(p.divisao_id, p.id)) g ON p.bank_transaction_id IS NOT NULL
  WHERE p.status <> 'cancelled'::text
UNION ALL
 SELECT 'receivable'::text AS lado,
    r.id,
    r.description,
    r.amount,
    r.status,
    r.due_date,
    r.issue_date,
    c.name AS contraparte,
    r.category AS categoria,
    r.bank_transaction_id,
        CASE
            WHEN COALESCE(r.bank_transaction_id, lp.linha) IS NOT NULL THEN 'conciliado'::text
            ELSE 'sem_extrato'::text
        END AS situacao,
    bt.transaction_date AS extrato_data,
    bt.amount AS extrato_valor,
    bt.description AS extrato_descricao,
        CASE
            WHEN bt.id IS NOT NULL THEN round(COALESCE(apl.total, r.amount) - bt.amount, 2)
            ELSE NULL::numeric
        END AS diferenca,
    (EXISTS ( SELECT 1
           FROM finance_review_queue q
          WHERE q.created_receivable_id = r.id)) AS nasceu_do_extrato,
    false AS compra_parcelada,
    NULL::integer AS parcelas,
    false AS lancada_em_dobro
   FROM receivables r
     LEFT JOIN LATERAL ( SELECT p.bank_transaction_id AS linha
           FROM payments p
          WHERE p.receivable_id = r.id AND p.status = 'confirmed'::text AND p.bank_transaction_id IS NOT NULL
          ORDER BY p.payment_date DESC, p.created_at DESC
         LIMIT 1) lp ON r.bank_transaction_id IS NULL
     LEFT JOIN bank_transactions bt ON bt.id = COALESCE(r.bank_transaction_id, lp.linha)
     LEFT JOIN LATERAL ( SELECT sum(x.amount) AS total
           FROM payments x
          WHERE x.bank_transaction_id = bt.id AND x.status = 'confirmed'::text AND x.receivable_id IS NOT NULL) apl ON bt.id IS NOT NULL
     LEFT JOIN clients c ON c.id = r.client_id
  WHERE r.status <> 'cancelled'::text;

revoke all on public.conciliacao_lancamentos from anon;
grant select on public.conciliacao_lancamentos to authenticated, service_role;

-- 9. O Pix do Lenine (11/08) deixa "Fora da fila" e o sinal ORÇ-00074 passa a segurá-lo ---------
-- A F1 o aplicou aos dois sinais que ele pagou (confirmado pelo dono em 02/10/2026).
with volta as (
  update public.bank_transactions
     set dismissed_kind = null, dismissed_reason = null, dismissed_at = null, dismissed_by = null, reconciled = true
   where id = 'fdb480ce-203e-4262-8b96-962b520f4ddf' and dismissed_kind is not null
     and exists (select 1 from public.payments where bank_transaction_id = 'fdb480ce-203e-4262-8b96-962b520f4ddf' and status = 'confirmed')
  returning id, amount
)
insert into public.reconciliation_log (acao, bank_transaction_id, valor, detalhe)
select 'voltou_da_fila', id, amount,
       'Pix do Lenine (11/08) saiu de "Fora da fila": está aplicado aos sinais ORÇ-00074 e ORÇ-00077 (F2, 02/10/2026).'
  from volta;
select public._reacomodar_entrada('fdb480ce-203e-4262-8b96-962b520f4ddf');

insert into supabase_migrations.schema_migrations (version, name)
values ('20261002140000', 'este_pix_paga')
on conflict do nothing;
