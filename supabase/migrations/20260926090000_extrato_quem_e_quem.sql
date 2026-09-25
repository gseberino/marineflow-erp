-- Fase 2 do Financeiro Confiável: o sistema sabe quem é quem — e não lança o mesmo
-- dinheiro duas vezes.
--
-- Medido em 25/09/2026 na fila do Extrato:
--   * 3 de 47 saídas chegavam com fornecedor, 0 com favorecido; 1 de 24 entradas com
--     cliente — embora quase todas trouxessem CPF/CNPJ;
--   * 3 entradas eram o sinal de um orçamento JÁ lançado à mão (ORÇ-00077, 00084, 00075).
--     Aprovar criava receita nova ao lado da existente: dinheiro contado duas vezes.
--
-- O identificador e a busca de vínculo rodam na edge (TypeScript, testados). Aqui ficam o
-- que precisa ser atômico e auditado: guardar a evidência, casar com o que já existe,
-- registrar sinal pelo extrato e cadastrar a contraparte que faltava.

-- ── A evidência e o vínculo, guardados na proposta ──────────────────────────────────────
alter table public.finance_review_queue
  add column if not exists evidencia jsonb,
  add column if not exists vinculo_sugerido jsonb;

comment on column public.finance_review_queue.evidencia is
  'Quem é a contraparte e por qual prova (documento, conta, histórico, nome); o que cadastrar quando nada foi reconhecido.';
comment on column public.finance_review_queue.vinculo_sugerido is
  'O que a transação provavelmente paga: recebível ou conta em aberto, pagamento já lançado, sinal de orçamento, saldo de OS. Com alternativas.';

-- ── Reavaliar a fila numa ida só ────────────────────────────────────────────────────────
-- "Revisar a fila" agora reidentifica cada linha; com evidência por linha, agrupar updates
-- iguais deixa de funcionar e seriam centenas de idas ao banco.
create or replace function public.aplicar_reavaliacao_da_fila(p_linhas jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  update public.finance_review_queue q set
    suggested_category = coalesce(l.suggested_category, q.suggested_category),
    dre_group = coalesce(l.dre_group, q.dre_group),
    suggested_supplier_id = l.suggested_supplier_id,
    suggested_payee_id = l.suggested_payee_id,
    suggested_client_id = l.suggested_client_id,
    suggested_service_order_id = coalesce(l.suggested_service_order_id, q.suggested_service_order_id),
    applied_rule_id = l.applied_rule_id,
    confidence = coalesce(l.confidence, q.confidence),
    reasoning = coalesce(l.reasoning, q.reasoning),
    evidencia = l.evidencia,
    vinculo_sugerido = l.vinculo_sugerido,
    updated_at = now()
  from jsonb_to_recordset(p_linhas) as l(
    id uuid, suggested_category text, dre_group text, suggested_supplier_id uuid,
    suggested_payee_id uuid, suggested_client_id uuid, suggested_service_order_id uuid,
    applied_rule_id uuid, confidence integer, reasoning text, evidencia jsonb, vinculo_sugerido jsonb)
  where q.id = l.id and q.status = 'pending';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ── Casar com o que já foi pago: amarrar também o PAGAMENTO ─────────────────────────────
-- Quando a conta já está paga (sinal lançado à mão, por exemplo), o casamento com a linha
-- do extrato não registra pagamento novo — mas precisa dizer QUAL pagamento aquela linha
-- é. Sem isso a Conciliação antiga continua oferecendo o mesmo pagamento como "sem banco".
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
    select p.id into v_pagamento_existente
      from public.payments p
     where p.status = 'confirmed'
       and ((p_tipo = 'payable' and p.payable_id = p_id) or (p_tipo = 'receivable' and p.receivable_id = p_id))
       and not exists (select 1 from public.bank_transactions t where t.reconciled_payment_id = p.id)
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
$$;

-- ── Sinal de orçamento pago, lido no extrato ────────────────────────────────────────────
-- O mesmo efeito do botão "Receber sinal" (register_deposit_and_convert: recebível do
-- sinal, pagamento, OS aberta), com a linha do extrato já amarrada e na trilha.
create or replace function public.registrar_sinal_pelo_extrato(
  p_orcamento uuid,
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
  v_os record;
  v_tx public.bank_transactions%rowtype;
  v_r json;
  v_metodo text;
begin
  select id, service_order_number, status, quote_status into v_os
    from public.service_orders where id = p_orcamento for update;
  if v_os.id is null then raise exception 'Orçamento não encontrado.'; end if;
  if v_os.status = 'cancelled' then raise exception 'O orçamento % está cancelado.', v_os.service_order_number; end if;
  if exists (select 1 from public.receivables where service_order_id = p_orcamento and is_deposit and status = 'paid') then
    raise exception 'O sinal do % já está lançado. Case a linha do extrato com ele em vez de lançar de novo.', v_os.service_order_number;
  end if;

  select * into v_tx from public.bank_transactions where id = p_transacao for update;
  if v_tx.id is null then raise exception 'Linha do extrato não encontrada.'; end if;
  if v_tx.transaction_type <> 'credit' then raise exception 'Sinal é dinheiro entrando: escolha uma entrada do extrato.'; end if;
  if v_tx.dismissed_kind is not null then
    raise exception 'Essa linha do extrato está fora da fila (%). Traga-a de volta antes.', v_tx.dismissed_kind;
  end if;
  if exists (select 1 from public.receivables where bank_transaction_id = p_transacao)
     or exists (select 1 from public.payables where bank_transaction_id = p_transacao) then
    raise exception 'Essa linha do extrato já está vinculada a outro lançamento.';
  end if;
  perform public._recusa_se_mes_fechado(v_tx.transaction_date, 'registrar o sinal nesta data');

  v_metodo := case
    when coalesce(v_tx.payment_method, '') ilike '%pix%' or coalesce(v_tx.description, '') ilike '%pix%' then 'pix'
    else 'bank_transfer' end;

  v_r := public.register_deposit_and_convert(
    p_orcamento, v_tx.amount, v_tx.transaction_date, v_metodo, 0,
    'Sinal identificado no extrato de ' || to_char(v_tx.transaction_date, 'DD/MM/YYYY'));

  update public.receivables set bank_transaction_id = p_transacao where id = (v_r ->> 'receivable_id')::uuid;
  update public.bank_transactions
     set reconciled = true, reconciled_payment_id = (v_r ->> 'payment_id')::uuid
   where id = p_transacao;
  update public.finance_review_queue
     set status = 'approved', decided_by = v_autor, decided_at = now(),
         created_receivable_id = (v_r ->> 'receivable_id')::uuid,
         decision_note = 'Sinal do ' || v_os.service_order_number
   where bank_transaction_id = p_transacao and status = 'pending';

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, receivable_id, valor, detalhe, antes, depois)
  values ('aprovou_proposta', v_autor, p_transacao, (v_r ->> 'receivable_id')::uuid, v_tx.amount,
          left('Sinal do ' || v_os.service_order_number || ' · ' || coalesce(v_tx.counterparty_name, v_tx.description, ''), 300),
          jsonb_build_object('orcamento', v_os.service_order_number, 'status', v_os.status, 'quote_status', v_os.quote_status),
          jsonb_build_object('sinal', v_r));

  return jsonb_build_object(
    'ok', true,
    'receivable_id', v_r ->> 'receivable_id',
    'message', 'Sinal de ' || public._brl(v_tx.amount) || ' registrado; o orçamento virou a '
      || (select service_order_number from public.service_orders where id = p_orcamento) || '.'
  );
end;
$$;

-- ── Cadastrar a contraparte que o extrato trouxe ────────────────────────────────────────
-- Um cadastro por documento: se já existe, devolve o que existe em vez de duplicar. Depois
-- de cadastrar, TODA linha pendente com o mesmo documento passa a apontar para ele — não
-- só a que foi clicada.
create or replace function public.cadastrar_contraparte(
  p_tipo text,
  p_dados jsonb,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_doc text := nullif(regexp_replace(coalesce(p_dados ->> 'documento', ''), '\D', '', 'g'), '');
  v_nome text := nullif(btrim(coalesce(p_dados ->> 'nome', '')), '');
  v_id uuid;
  v_ja_existia boolean := false;
  v_categoria text := nullif(btrim(coalesce(p_dados ->> 'categoria', '')), '');
  v_dre text;
  v_atualizadas integer := 0;
  v_evid jsonb;
  v_chave text;
begin
  if p_tipo not in ('fornecedor', 'favorecido', 'cliente') then
    raise exception 'Tipo de cadastro inválido: % (fornecedor, favorecido ou cliente).', p_tipo;
  end if;
  if v_nome is null then raise exception 'Informe o nome.'; end if;
  if v_doc is not null and length(v_doc) not in (11, 14) then
    raise exception 'CPF tem 11 dígitos e CNPJ tem 14; recebi %.', length(v_doc);
  end if;
  if v_categoria is not null then
    select dre_group into v_dre from public.financial_categories where name = v_categoria and type = 'payable' and active;
    if not found then v_categoria := null; end if;
  end if;

  if p_tipo = 'fornecedor' then
    if v_doc is not null then
      select id into v_id from public.suppliers where regexp_replace(coalesce(cnpj_cpf, ''), '\D', '', 'g') = v_doc limit 1;
    end if;
    if v_id is null then
      insert into public.suppliers (name, trade_name, cnpj_cpf, phone, email, postal_code, address_line_1,
                                    address_number, address_complement, neighborhood, city, state, country, notes, active)
      values (v_nome, nullif(p_dados ->> 'nome_fantasia', ''), v_doc, nullif(p_dados ->> 'telefone', ''),
              nullif(p_dados ->> 'email', ''), nullif(p_dados ->> 'cep', ''), nullif(p_dados ->> 'logradouro', ''),
              nullif(p_dados ->> 'numero', ''), nullif(p_dados ->> 'complemento', ''), nullif(p_dados ->> 'bairro', ''),
              nullif(p_dados ->> 'cidade', ''), nullif(p_dados ->> 'uf', ''), 'BR',
              nullif(p_dados ->> 'observacao', ''), true)
      returning id into v_id;
    else
      v_ja_existia := true;
    end if;
  elsif p_tipo = 'favorecido' then
    if v_doc is not null then
      select id into v_id from public.payees where regexp_replace(coalesce(document, ''), '\D', '', 'g') = v_doc limit 1;
    end if;
    if v_id is null then
      insert into public.payees (name, kind, document, default_category, notes, active)
      values (v_nome, coalesce(nullif(p_dados ->> 'tipo_de_favorecido', ''), 'prestador'), v_doc, v_categoria,
              nullif(p_dados ->> 'observacao', ''), true)
      returning id into v_id;
    else
      v_ja_existia := true;
    end if;
  else
    if v_doc is not null then
      select id into v_id from public.clients where regexp_replace(coalesce(cpf_cnpj, ''), '\D', '', 'g') = v_doc limit 1;
    end if;
    if v_id is null then
      insert into public.clients (type, name, display_name, cpf_cnpj, phone, email, postal_code, address_line_1,
                                  address_number, address_complement, neighborhood, city, state, country, notes, active)
      values (case when length(coalesce(v_doc, '')) = 14 then 'company' else 'individual' end,
              v_nome, nullif(p_dados ->> 'nome_fantasia', ''), v_doc, nullif(p_dados ->> 'telefone', ''),
              nullif(p_dados ->> 'email', ''), nullif(p_dados ->> 'cep', ''), nullif(p_dados ->> 'logradouro', ''),
              nullif(p_dados ->> 'numero', ''), nullif(p_dados ->> 'complemento', ''), nullif(p_dados ->> 'bairro', ''),
              nullif(p_dados ->> 'cidade', ''), nullif(p_dados ->> 'uf', ''), 'BR',
              nullif(p_dados ->> 'observacao', ''), true)
      returning id into v_id;
    else
      v_ja_existia := true;
    end if;
  end if;

  -- Toda linha pendente com o mesmo documento passa a apontar para o cadastro.
  if v_doc is not null then
    v_chave := p_tipo;
    v_evid := jsonb_build_object(v_chave, jsonb_build_object(
      'id', v_id, 'nome', v_nome, 'por', 'documento',
      'detalhe', case when length(v_doc) = 14 then 'CNPJ' else 'CPF' end || ' confere com o ' || p_tipo || ' ' || v_nome));
    update public.finance_review_queue q set
      suggested_supplier_id = case when p_tipo = 'fornecedor' then v_id else q.suggested_supplier_id end,
      suggested_payee_id = case when p_tipo = 'favorecido' then v_id else q.suggested_payee_id end,
      suggested_client_id = case when p_tipo = 'cliente' then v_id else q.suggested_client_id end,
      evidencia = (coalesce(q.evidencia, '{}'::jsonb) - 'cadastrar') || v_evid,
      -- A categoria da atividade (CNAE) só entra onde o sistema não sabia nada: "Outras
      -- despesas" sem regra sua. Não passa por cima do que você ou uma regra decidiu.
      suggested_category = case
        when v_categoria is not null and p_tipo in ('fornecedor', 'favorecido') and q.kind = 'create_payable'
             and q.applied_rule_id is null and q.suggested_category = 'Outras despesas'
          then v_categoria else q.suggested_category end,
      dre_group = case
        when v_categoria is not null and p_tipo in ('fornecedor', 'favorecido') and q.kind = 'create_payable'
             and q.applied_rule_id is null and q.suggested_category = 'Outras despesas'
          then coalesce(v_dre, q.dre_group) else q.dre_group end,
      updated_at = now()
    from public.bank_transactions t
    where t.id = q.bank_transaction_id and q.status = 'pending'
      and regexp_replace(coalesce(t.counterparty_document, ''), '\D', '', 'g') = v_doc
      and ((p_tipo = 'cliente' and q.kind = 'create_receivable')
        or (p_tipo in ('fornecedor', 'favorecido') and q.kind = 'create_payable'));
    get diagnostics v_atualizadas = row_count;
  end if;

  insert into public.reconciliation_log (acao, autor, valor, detalhe, antes, depois)
  values ('cadastrou_contraparte', v_autor, null,
          left(case when v_ja_existia then 'Já existia: ' else 'Cadastrou ' end || p_tipo || ' ' || v_nome
               || coalesce(' (' || v_doc || ')', ''), 300),
          null,
          jsonb_build_object('tipo', p_tipo, 'id', v_id, 'documento', v_doc, 'categoria', v_categoria,
                             'linhas_da_fila', v_atualizadas, 'ja_existia', v_ja_existia));

  return jsonb_build_object(
    'ok', true, 'id', v_id, 'ja_existia', v_ja_existia, 'linhas_atualizadas', v_atualizadas,
    'message', case when v_ja_existia then initcap(p_tipo) || ' já estava cadastrado' else initcap(p_tipo) || ' cadastrado' end
      || case when v_atualizadas > 0 then '; ' || v_atualizadas || ' linha(s) do Extrato já apontam para ele.' else '.' end
  );
end;
$$;

-- ── Cache da consulta de CNPJ (Receita, via BrasilAPI) ──────────────────────────────────
-- A mesma empresa aparece dezenas de vezes no extrato; perguntar à Receita a cada clique
-- seria lento e bateria no limite da API pública.
create table if not exists public.consulta_cnpj (
  cnpj text primary key check (cnpj ~ '^\d{14}$'),
  dados jsonb not null,
  consultado_em timestamptz not null default now()
);
alter table public.consulta_cnpj enable row level security;
revoke all on public.consulta_cnpj from anon, authenticated;

-- ── Registrar sinal: técnico não converte orçamento ─────────────────────────────────────
-- A função rodava com privilégio elevado e sem conferir quem chamava: qualquer usuário
-- logado, técnico incluído, podia registrar sinal e converter orçamento em OS chamando a
-- API direto. A tela nunca mostra o botão ao técnico; o banco agora também recusa.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'register_deposit_and_convert';
  if v_def is null or position('Técnico não registra sinal' in v_def) > 0 then
    return;
  end if;
  v_def := replace(v_def,
    E'BEGIN\n  IF p_amount <= 0 THEN',
    E'BEGIN\n  -- Técnico não registra sinal nem converte orçamento (chamada sem usuário = sistema).\n'
    || E'  IF auth.uid() IS NOT NULL AND EXISTS (SELECT 1 FROM public.app_users WHERE id = auth.uid() AND role = ''technician'') THEN\n'
    || E'    RAISE EXCEPTION ''Técnico não registra sinal nem converte orçamento.'' USING ERRCODE = ''42501'';\n'
    || E'  END IF;\n\n  IF p_amount <= 0 THEN');
  if position('Técnico não registra sinal' in v_def) = 0 then
    raise exception 'Não achei onde inserir a trava de cargo em register_deposit_and_convert';
  end if;
  execute v_def;
end;
$$;

-- ── Quem executa ────────────────────────────────────────────────────────────────────────
revoke all on function public.aplicar_reavaliacao_da_fila(jsonb) from public, anon, authenticated;
grant execute on function public.aplicar_reavaliacao_da_fila(jsonb) to service_role;
revoke all on function public.conciliar_lancamento(text, uuid, uuid, uuid) from public, anon;
grant execute on function public.conciliar_lancamento(text, uuid, uuid, uuid) to authenticated, service_role;
revoke all on function public.registrar_sinal_pelo_extrato(uuid, uuid, uuid) from public, anon;
grant execute on function public.registrar_sinal_pelo_extrato(uuid, uuid, uuid) to authenticated, service_role;
revoke all on function public.cadastrar_contraparte(text, jsonb, uuid) from public, anon;
grant execute on function public.cadastrar_contraparte(text, jsonb, uuid) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260926090000', 'extrato_quem_e_quem')
on conflict do nothing;
