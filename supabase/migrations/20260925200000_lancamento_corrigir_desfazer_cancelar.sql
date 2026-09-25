-- Corrigir, desfazer e cancelar um lançamento depois de aprovado — e casar com o extrato.
--
-- O dono parou de confiar nos lançamentos: "as ferramentas não estavam lançando
-- corretamente mesmo depois que eu aprovava". Parte era defeito do motor (compra parcelada
-- lançada de novo a cada mês, corrigido em 25/09/2026). A outra parte era não ter como
-- consertar: conta paga não abria para edição, fornecedor e OS não mudavam depois de
-- criados, não existia "desfazer" e a única saída era apagar no banco. Quem não consegue
-- corrigir um número não fecha o mês com ele.
--
-- Quatro funções, um caminho só. A tela, o assistente do painel e o do WhatsApp chamam as
-- mesmas funções, então as regras valem igual para os três:
--   * toda mudança vai para a trilha (reconciliation_log) com o antes e o depois;
--   * mês fechado recusa a mudança (a trava antiga só valia para lançamento NOVO);
--   * categoria sensível continua visível e editável só para o administrador;
--   * valor que veio do banco não muda à mão — para isso existe desfazer a aprovação.
--
-- Antes, a edição gravava direto na tabela: sem trilha, sem trava de período, e mudar o
-- valor de uma conta em aberto não recalculava o saldo (balance_amount ficava o antigo).

-- ── Quem está pedindo ───────────────────────────────────────────────────────────────────
-- Na tela, é o usuário da sessão. Pelo WhatsApp, o assistente roda com o service role (sem
-- usuário na sessão) e informa quem pediu. anon e public não executam nenhuma destas
-- funções, então "sem usuário" só pode ser o service role.
create or replace function public._autor_do_financeiro(p_autor uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v uuid := auth.uid();
begin
  if v is not null then
    if not public.is_admin_or_financial(v) then
      raise exception 'Só administrador ou financeiro pode alterar lançamentos.' using errcode = '42501';
    end if;
    return v;
  end if;
  if p_autor is not null and not public.is_admin_or_financial(p_autor) then
    raise exception 'Só administrador ou financeiro pode alterar lançamentos.' using errcode = '42501';
  end if;
  return p_autor;
end;
$$;

-- ── Mês fechado ─────────────────────────────────────────────────────────────────────────
create or replace function public._recusa_se_mes_fechado(p_data date, p_o_que text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_data is not null and public.periodo_esta_fechado(p_data) then
    raise exception 'O mês % está fechado. Reabra-o em Financeiro › Fechamento para %.',
      to_char(p_data, 'MM/YYYY'), p_o_que
      using errcode = 'check_violation';
  end if;
end;
$$;

-- ── O lançamento nasceu de uma linha do extrato? ────────────────────────────────────────
-- Faz diferença para desfazer: o que NASCEU da aprovação é cancelado e a linha volta para a
-- fila; o que já existia e só foi CASADO com o extrato perde o vínculo e continua valendo.
create or replace function public._nasceu_do_extrato(p_tipo text, p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_tipo = 'payable' then
      exists (select 1 from public.payables where id = p_id and origin = 'bank_reconciliation')
      or exists (select 1 from public.finance_review_queue where created_payable_id = p_id)
    else
      exists (select 1 from public.finance_review_queue where created_receivable_id = p_id)
  end;
$$;

-- ── Valor em reais, para as mensagens ───────────────────────────────────────────────────
-- to_char com G/D depende do locale do servidor, que aqui é C (1,234.56).
create or replace function public._brl(p_valor numeric)
returns text
language sql
immutable
set search_path = public
as $$
  select 'R$ ' || translate(to_char(coalesce(p_valor, 0), 'FM999,999,990.00'), ',.', '.,');
$$;

-- ── Saldo depois de mexer no pago ou no valor ───────────────────────────────────────────
create or replace function public._situacao_do_saldo(p_valor numeric, p_pago numeric, p_status_atual text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when coalesce(p_pago, 0) > 0 and coalesce(p_pago, 0) >= p_valor - 0.005 then 'paid'
    when coalesce(p_pago, 0) > 0 then 'partially_paid'
    when p_status_atual in ('paid', 'partially_paid') then 'pending'
    else p_status_atual
  end;
$$;

-- ═════════════════════════════════════════════════════════════════════════════════════════
-- CORRIGIR
-- ═════════════════════════════════════════════════════════════════════════════════════════
-- p_campos leva só o que muda. Chave ausente fica como está; chave com null (ou texto vazio)
-- limpa o campo, quando o campo aceita ficar vazio.
--   a pagar:  description, notes, expense_category, supplier_id, payee_id,
--             linked_service_order_id, cost_center_id, issue_date, due_date, amount
--   a receber: description, notes, category, client_id, service_order_id, cost_center_id,
--             issue_date, due_date, amount
create or replace function public.corrigir_lancamento(
  p_tipo text,
  p_id uuid,
  p_campos jsonb,
  p_motivo text default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_permitidos text[];
  v_chave text;
  v_valor_novo jsonb;
  v_novo jsonb := '{}'::jsonb;
  v_era jsonb := '{}'::jsonb;
  v_alterados text[] := array[]::text[];
  v_valor numeric;
  v_pago numeric;
  v_status text;
  v_data_antes date;
  v_data_nova date;
  v_categoria_antes text;
  v_categoria_nova text;
  v_tabela text;
  v_aplicar jsonb;
  v_sets text;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;
  if p_campos is null or jsonb_typeof(p_campos) <> 'object' then
    raise exception 'Informe o que corrigir.';
  end if;

  if p_tipo = 'payable' then
    v_permitidos := array['description', 'notes', 'expense_category', 'supplier_id', 'payee_id',
      'linked_service_order_id', 'cost_center_id', 'issue_date', 'due_date', 'amount'];
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    v_permitidos := array['description', 'notes', 'category', 'client_id', 'service_order_id',
      'cost_center_id', 'issue_date', 'due_date', 'amount'];
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;

  if v_antes is null then
    raise exception 'Lançamento não encontrado.';
  end if;
  if v_antes->>'status' = 'cancelled' then
    raise exception 'Este lançamento está cancelado. Se o cancelamento foi engano, lance de novo.';
  end if;

  -- Só entra o que muda de verdade. Texto vazio vale como "limpar".
  for v_chave in select jsonb_object_keys(p_campos) loop
    if not v_chave = any (v_permitidos) then
      raise exception 'O campo "%" não se corrige por aqui.', v_chave;
    end if;
    v_valor_novo := p_campos -> v_chave;
    if jsonb_typeof(v_valor_novo) = 'string' and btrim(v_valor_novo #>> '{}') = '' then
      v_valor_novo := 'null'::jsonb;
    end if;
    if coalesce(v_antes -> v_chave, 'null'::jsonb) is distinct from v_valor_novo then
      v_novo := v_novo || jsonb_build_object(v_chave, v_valor_novo);
      v_era := v_era || jsonb_build_object(v_chave, coalesce(v_antes -> v_chave, 'null'::jsonb));
      v_alterados := v_alterados || v_chave;
    end if;
  end loop;

  if array_length(v_alterados, 1) is null then
    return jsonb_build_object('ok', true, 'alterados', '[]'::jsonb, 'message', 'Nada mudou: os valores informados já eram os atuais.');
  end if;

  -- Campos que não podem ficar vazios.
  if v_novo ? 'description' and v_novo -> 'description' = 'null'::jsonb then
    raise exception 'A descrição não pode ficar vazia.';
  end if;
  if v_novo ? 'issue_date' and v_novo -> 'issue_date' = 'null'::jsonb then
    raise exception 'A data do lançamento não pode ficar vazia.';
  end if;
  if v_novo ? 'due_date' and v_novo -> 'due_date' = 'null'::jsonb then
    raise exception 'O vencimento não pode ficar vazio.';
  end if;
  if v_novo ? 'client_id' and v_novo -> 'client_id' = 'null'::jsonb then
    raise exception 'Conta a receber precisa de cliente.';
  end if;

  -- Referências: erro legível em vez de "violates foreign key constraint".
  if v_novo ->> 'supplier_id' is not null
     and not exists (select 1 from public.suppliers where id = (v_novo ->> 'supplier_id')::uuid) then
    raise exception 'Fornecedor não encontrado no cadastro.';
  end if;
  if v_novo ->> 'payee_id' is not null
     and not exists (select 1 from public.payees where id = (v_novo ->> 'payee_id')::uuid) then
    raise exception 'Favorecido não encontrado no cadastro.';
  end if;
  if v_novo ->> 'client_id' is not null
     and not exists (select 1 from public.clients where id = (v_novo ->> 'client_id')::uuid) then
    raise exception 'Cliente não encontrado no cadastro.';
  end if;
  if coalesce(v_novo ->> 'linked_service_order_id', v_novo ->> 'service_order_id') is not null
     and not exists (select 1 from public.service_orders
                      where id = coalesce(v_novo ->> 'linked_service_order_id', v_novo ->> 'service_order_id')::uuid) then
    raise exception 'OS não encontrada.';
  end if;
  if v_novo ->> 'cost_center_id' is not null
     and not exists (select 1 from public.cost_centers where id = (v_novo ->> 'cost_center_id')::uuid) then
    raise exception 'Centro de custo não encontrado.';
  end if;

  -- Categoria sensível: a mesma regra da RLS — só o administrador vê e mexe.
  if p_tipo = 'payable' and v_autor is not null and not public.is_admin(v_autor) then
    v_categoria_antes := v_antes ->> 'expense_category';
    v_categoria_nova := coalesce(v_novo ->> 'expense_category', v_categoria_antes);
    if (v_categoria_antes is not null and public.categoria_e_sensivel(v_categoria_antes))
       or (v_categoria_nova is not null and public.categoria_e_sensivel(v_categoria_nova)) then
      raise exception 'Categoria restrita: só o administrador altera este lançamento.' using errcode = '42501';
    end if;
  end if;

  -- Mês fechado. Anotação pura (só observação) passa: não muda número nenhum.
  if v_alterados <> array['notes'] then
    v_data_antes := (v_antes ->> 'issue_date')::date;
    v_data_nova := coalesce((v_novo ->> 'issue_date')::date, v_data_antes);
    perform public._recusa_se_mes_fechado(v_data_antes, 'corrigir este lançamento');
    perform public._recusa_se_mes_fechado(v_data_nova, 'mover o lançamento para esta data');
  end if;

  -- Valor.
  v_valor := (v_antes ->> 'amount')::numeric;
  v_pago := coalesce((v_antes ->> 'paid_amount')::numeric, 0);
  v_status := v_antes ->> 'status';
  if v_novo ? 'amount' then
    if v_antes ->> 'bank_transaction_id' is not null then
      raise exception 'O valor deste lançamento veio do extrato do banco (%) e não muda à mão. Se o lançamento está errado, desfaça a aprovação.',
        public._brl((v_antes ->> 'amount')::numeric);
    end if;
    if v_novo -> 'amount' = 'null'::jsonb or (v_novo ->> 'amount')::numeric <= 0 then
      raise exception 'O valor precisa ser maior que zero.';
    end if;
    v_valor := round((v_novo ->> 'amount')::numeric, 2);
    if v_valor < v_pago - 0.005 then
      raise exception 'O novo valor (%) é menor que o já pago (%). Estorne o pagamento antes.',
        public._brl(v_valor), public._brl(v_pago);
    end if;
    v_status := public._situacao_do_saldo(v_valor, v_pago, v_status);
  end if;

  -- Grava SÓ as colunas que mudaram. Um UPDATE que regrava tudo dispara os gatilhos de
  -- coerência de colunas que ninguém tocou — e um recebível antigo com data torta ficaria
  -- impossível de corrigir até na descrição.
  v_aplicar := v_novo;
  if v_novo ? 'amount' then
    v_aplicar := v_aplicar || jsonb_build_object(
      'amount', v_valor, 'balance_amount', greatest(0, v_valor - v_pago), 'status', v_status);
  end if;
  v_tabela := case when p_tipo = 'payable' then 'payables' else 'receivables' end;
  select string_agg(format('%I = (x.r).%I', k, k), ', ') into v_sets
    from jsonb_object_keys(v_aplicar) as k;
  execute format(
    'update public.%I t set %s from (select jsonb_populate_record(null::public.%I, $1) as r) x where t.id = $2',
    v_tabela, v_sets, v_tabela)
  using v_aplicar, p_id;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'corrigiu_lancamento', v_autor,
    (v_antes ->> 'bank_transaction_id')::uuid,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    v_valor,
    left(coalesce(nullif(btrim(p_motivo), ''), 'Corrigiu ' || array_to_string(v_alterados, ', ')) || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    v_era,
    v_novo
  );

  return jsonb_build_object(
    'ok', true,
    'alterados', to_jsonb(v_alterados),
    'antes', v_era,
    'depois', v_novo,
    'message', 'Lançamento corrigido: ' || array_to_string(v_alterados, ', ')
  );
end;
$$;

-- ═════════════════════════════════════════════════════════════════════════════════════════
-- DESFAZER A APROVAÇÃO (ou o vínculo com o extrato)
-- ═════════════════════════════════════════════════════════════════════════════════════════
-- O que nasceu da aprovação é cancelado e a proposta volta para a fila do Extrato, pronta
-- para ser aprovada de outro jeito. O que já existia e só foi casado perde o vínculo; se o
-- casamento registrou pagamento, o pagamento é estornado.
create or replace function public.desfazer_aprovacao(
  p_tipo text,
  p_id uuid,
  p_motivo text default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Este lançamento já está cancelado.'; end if;

  v_tx := (v_antes ->> 'bank_transaction_id')::uuid;
  if v_tx is null then
    raise exception 'Este lançamento não está ligado a nenhuma linha do extrato, então não há aprovação a desfazer. Para tirá-lo do resultado, cancele-o.';
  end if;
  perform public._recusa_se_mes_fechado((v_antes ->> 'issue_date')::date, 'desfazer esta aprovação');

  v_nasceu := public._nasceu_do_extrato(p_tipo, p_id);
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] ';

  if v_nasceu then
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

    -- O pagamento que o CASAMENTO registrou sai junto. Pagamento lançado à mão e só depois
    -- ligado ao extrato continua valendo — medido em 25/09/2026: das 49 linhas do extrato
    -- com pagamento ligado, parte foi criada pela conciliação ("Conciliação automática…",
    -- "Conciliado com o extrato…") e parte pelo dono, semanas antes do casamento. Estornar
    -- o segundo tipo desfaria um recebimento que aconteceu.
    select p.id, p.amount into v_pagamento_id, v_pagamento_valor
      from public.bank_transactions t join public.payments p on p.id = t.reconciled_payment_id
     where t.id = v_tx and p.status = 'confirmed'
       and coalesce(p.notes, '') ilike 'concilia%'
       and ((p_tipo = 'payable' and p.payable_id = p_id) or (p_tipo = 'receivable' and p.receivable_id = p_id));
    if v_pagamento_id is not null then
      update public.payments
         set status = 'cancelled', cancelled_at = now(),
             cancellation_reason = left('Vínculo com o extrato desfeito' || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), 200)
       where id = v_pagamento_id;
      v_pago := greatest(0, v_pago - v_pagamento_valor);
    end if;

    if p_tipo = 'payable' then
      update public.payables set bank_transaction_id = null,
             paid_amount = v_pago,
             balance_amount = greatest(0, amount - v_pago),
             status = public._situacao_do_saldo(amount, v_pago, status)
       where id = p_id;
    else
      update public.receivables set bank_transaction_id = null,
             paid_amount = v_pago,
             balance_amount = greatest(0, amount - v_pago),
             status = public._situacao_do_saldo(amount, v_pago, status)
       where id = p_id;
    end if;
    update public.bank_transactions set reconciled = false, reconciled_payment_id = null where id = v_tx;
    v_msg := 'Vínculo desfeito: o lançamento continua valendo e a linha do extrato voltou para a fila.'
      || case when v_pagamento_id is not null then ' O pagamento que o casamento tinha registrado foi estornado.'
              when v_pago > 0 then ' O pagamento registrado à mão continua valendo.'
              else '' end;
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
                       'proposta_voltou', v_voltaram > 0, 'pagamento_estornado', v_pagamento_id)
  );

  return jsonb_build_object('ok', true, 'acao', v_acao, 'proposta_voltou', v_voltaram > 0, 'message', v_msg);
end;
$$;

-- ═════════════════════════════════════════════════════════════════════════════════════════
-- CANCELAR
-- ═════════════════════════════════════════════════════════════════════════════════════════
-- Cancelar é o "excluir" auditável: o lançamento sai do resultado, mas continua existindo
-- com o motivo, e a trilha diz quem e quando. Nada some.
-- Se o lançamento nasceu de uma linha do extrato, a linha vai para "Fora da fila" com o
-- mesmo motivo — o dinheiro passou pelo banco, mas não é receita nem despesa da empresa.
-- De lá ela pode voltar. Se o lançamento só estava casado, a linha volta para a fila.
create or replace function public.cancelar_lancamento(
  p_tipo text,
  p_id uuid,
  p_motivo text,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx uuid;
  v_nasceu boolean;
  v_motivo text := nullif(btrim(p_motivo), '');
  v_nota text;
  v_destino text := null;
begin
  if p_tipo not in ('payable', 'receivable') then
    raise exception 'Tipo de lançamento inválido: % (use payable ou receivable).', p_tipo;
  end if;
  if v_motivo is null or length(v_motivo) < 3 then
    raise exception 'Diga por que o lançamento está sendo cancelado.';
  end if;

  if p_tipo = 'payable' then
    select to_jsonb(p) into v_antes from public.payables p where p.id = p_id for update;
  else
    select to_jsonb(r) into v_antes from public.receivables r where r.id = p_id for update;
  end if;
  if v_antes is null then raise exception 'Lançamento não encontrado.'; end if;
  if v_antes ->> 'status' = 'cancelled' then raise exception 'Este lançamento já está cancelado.'; end if;
  perform public._recusa_se_mes_fechado((v_antes ->> 'issue_date')::date, 'cancelar este lançamento');

  v_tx := (v_antes ->> 'bank_transaction_id')::uuid;
  v_nasceu := v_tx is not null and public._nasceu_do_extrato(p_tipo, p_id);
  v_nota := '[' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || '] Cancelado: ' || v_motivo;

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
    if v_nasceu then
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

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values (
    'cancelou_lancamento', v_autor, v_tx,
    case when p_tipo = 'payable' then p_id end,
    case when p_tipo = 'receivable' then p_id end,
    (v_antes ->> 'amount')::numeric,
    left(v_motivo || ' · ' || coalesce(v_antes ->> 'description', ''), 300),
    jsonb_build_object('status', v_antes ->> 'status', 'bank_transaction_id', v_tx, 'paid_amount', v_antes -> 'paid_amount'),
    jsonb_build_object('status', 'cancelled', 'linha_do_extrato', v_destino)
  );

  return jsonb_build_object(
    'ok', true,
    'linha_do_extrato', v_destino,
    'message', 'Lançamento cancelado.'
      || case v_destino
           when 'fora_da_fila' then ' A linha do extrato foi para "Fora da fila" com o mesmo motivo; de lá ela pode voltar.'
           when 'fila' then ' A linha do extrato voltou para a fila.'
           else '' end
  );
end;
$$;

-- ═════════════════════════════════════════════════════════════════════════════════════════
-- CASAR COM O EXTRATO
-- ═════════════════════════════════════════════════════════════════════════════════════════
-- Casar uma conta em ABERTO com a linha do banco é dizer que ela foi paga: o pagamento é
-- registrado na data do extrato. Antes, o casamento só gravava o vínculo e a conta
-- continuava "pendente" com o dinheiro já fora do banco.
create or replace function public.conciliar_lancamento(
  p_tipo text,
  p_id uuid,
  p_transacao uuid,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_antes jsonb;
  v_tx public.bank_transactions%rowtype;
  v_aberto boolean;
  v_saldo numeric;
  v_valor_pago numeric := 0;
  v_pago numeric;
  v_pagamento uuid := null;
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

  update public.bank_transactions set reconciled = true, reconciled_payment_id = v_pagamento where id = p_transacao;
  -- A linha agora tem lançamento: a proposta de criar outro deixa de valer.
  update public.finance_review_queue
     set status = 'superseded', decision_note = 'Casada na Conciliação com um lançamento que já existia'
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
    jsonb_build_object('bank_transaction_id', p_transacao, 'pagamento_registrado', v_pagamento, 'valor_pago', v_valor_pago)
  );

  return jsonb_build_object(
    'ok', true,
    'pagamento_registrado', v_pagamento is not null,
    'valor_pago', v_valor_pago,
    'message', case when v_pagamento is not null
      then 'Conciliado. Pagamento de ' || public._brl(v_valor_pago) || ' registrado em ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY') || '.'
      else 'Conciliado.' end
  );
end;
$$;

-- ── Conciliação: sem cancelados, com o nome certo e dizendo de onde o lançamento veio ──
-- A lista "sem par no extrato" mostrava 48 lançamentos CANCELADOS como se faltasse achar o
-- banco deles. E a contraparte vinha de supplier_name, que fica vazio justamente quando o
-- fornecedor está cadastrado.
create or replace view public.conciliacao_lancamentos
with (security_invoker = on) as
 select 'payable'::text as lado,
    p.id,
    p.description,
    p.amount,
    p.status,
    p.due_date,
    p.issue_date,
    coalesce(s.name, p.supplier_name) as contraparte,
    p.expense_category as categoria,
    p.bank_transaction_id,
    case when p.bank_transaction_id is not null then 'conciliado'::text else 'sem_extrato'::text end as situacao,
    bt.transaction_date as extrato_data,
    bt.amount as extrato_valor,
    bt.description as extrato_descricao,
    case when p.bank_transaction_id is not null then round(p.amount - bt.amount, 2) else null::numeric end as diferenca,
    (p.origin = 'bank_reconciliation'
      or exists (select 1 from public.finance_review_queue q where q.created_payable_id = p.id)) as nasceu_do_extrato
   from public.payables p
     left join public.bank_transactions bt on bt.id = p.bank_transaction_id
     left join public.suppliers s on s.id = p.supplier_id
  where p.status <> 'cancelled'
union all
 select 'receivable'::text as lado,
    r.id,
    r.description,
    r.amount,
    r.status,
    r.due_date,
    r.issue_date,
    c.name as contraparte,
    r.category as categoria,
    r.bank_transaction_id,
    case when r.bank_transaction_id is not null then 'conciliado'::text else 'sem_extrato'::text end as situacao,
    bt.transaction_date as extrato_data,
    bt.amount as extrato_valor,
    bt.description as extrato_descricao,
    case when r.bank_transaction_id is not null then round(r.amount - bt.amount, 2) else null::numeric end as diferenca,
    exists (select 1 from public.finance_review_queue q where q.created_receivable_id = r.id) as nasceu_do_extrato
   from public.receivables r
     left join public.bank_transactions bt on bt.id = r.bank_transaction_id
     left join public.clients c on c.id = r.client_id
  where r.status <> 'cancelled';

revoke all on public.conciliacao_lancamentos from anon;

-- ── Quem executa ────────────────────────────────────────────────────────────────────────
-- Grant nominal: revogar de public não fecha anon (default privileges dão execute por nome).
revoke all on function public._autor_do_financeiro(uuid) from public, anon, authenticated;
revoke all on function public._recusa_se_mes_fechado(date, text) from public, anon, authenticated;
revoke all on function public._nasceu_do_extrato(text, uuid) from public, anon, authenticated;
revoke all on function public._situacao_do_saldo(numeric, numeric, text) from public, anon, authenticated;
revoke all on function public._brl(numeric) from public, anon, authenticated;
revoke all on function public.corrigir_lancamento(text, uuid, jsonb, text, uuid) from public, anon;
revoke all on function public.desfazer_aprovacao(text, uuid, text, uuid) from public, anon;
revoke all on function public.cancelar_lancamento(text, uuid, text, uuid) from public, anon;
revoke all on function public.conciliar_lancamento(text, uuid, uuid, uuid) from public, anon;
grant execute on function public.corrigir_lancamento(text, uuid, jsonb, text, uuid) to authenticated, service_role;
grant execute on function public.desfazer_aprovacao(text, uuid, text, uuid) to authenticated, service_role;
grant execute on function public.cancelar_lancamento(text, uuid, text, uuid) to authenticated, service_role;
grant execute on function public.conciliar_lancamento(text, uuid, uuid, uuid) to authenticated, service_role;
grant execute on function public._autor_do_financeiro(uuid) to service_role;
grant execute on function public._recusa_se_mes_fechado(date, text) to service_role;
grant execute on function public._nasceu_do_extrato(text, uuid) to service_role;
grant execute on function public._situacao_do_saldo(numeric, numeric, text) to service_role;
grant execute on function public._brl(numeric) to service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260925200000', 'lancamento_corrigir_desfazer_cancelar')
on conflict do nothing;
