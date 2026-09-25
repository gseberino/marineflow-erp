-- Fase 4 do Financeiro Confiável: o Caixa em dinheiro, com saldo, e a anotação antecipada.
--
-- Decisões do dono (25/09/2026):
--   * o Caixa TEM saldo — "eu posso acabar misturando o dinheiro da empresa com o pessoal";
--   * lançar pelo WhatsApp pede confirmação sempre, no começo;
--   * a IA pensa e chama a função; quem preenche data, status, saldo e vínculo é o sistema.
--
-- O Caixa é uma conta como as do banco: tem extrato, saldo dia a dia e conferência pela
-- contagem. Por isso cada gasto em dinheiro vira uma LINHA do Caixa ligada ao lançamento —
-- nunca um "pago" solto, que a Conciliação acusaria como pagamento sem rastro.

-- ── A conta ─────────────────────────────────────────────────────────────────────────────
insert into public.bank_connections (provider, external_id, label, institution, account_kind, active,
                                     last_sync_status, saldo_base, saldo_base_em)
select 'caixa', 'caixa-da-empresa', 'Caixa (dinheiro)', 'Dinheiro em espécie', 'bank', true, 'never', 0, current_date
where not exists (select 1 from public.bank_connections where provider = 'caixa');

create or replace function public._conta_caixa()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.bank_connections where provider = 'caixa' order by created_at limit 1;
$$;

/** Saldo do Caixa agora: base + soma com sinal de tudo que conta. */
create or replace function public.saldo_do_caixa()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select round(coalesce(c.saldo_base, 0) + coalesce(sum(case when t.transaction_type = 'credit' then t.amount else -t.amount end), 0), 2)
    from public.bank_connections c
    left join public.bank_transactions t
      on t.bank_connection_id = c.id and coalesce(t.tx_status, '') <> 'PENDING' and coalesce(t.dismissed_kind, '') <> 'duplicata'
   where c.id = public._conta_caixa()
   group by c.saldo_base;
$$;

-- Hoje no fuso da empresa: um gasto às 22h de Itajaí não pode cair no dia seguinte (UTC).
create or replace function public._hoje_brt()
returns date language sql stable set search_path = public
as $$ select (now() at time zone 'America/Sao_Paulo')::date; $$;

/** Uma linha no Caixa. `p_fora` = transferência ou ajuste: conta no saldo, mas não é despesa. */
create or replace function public._linha_do_caixa(
  p_tipo text, p_valor numeric, p_data date, p_descricao text, p_quem text, p_fora_tipo text, p_fora_motivo text, p_autor uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, provider,
                                        bank_ref_id, bank_connection_id, counterparty_name, reconciled,
                                        dismissed_kind, dismissed_reason, dismissed_at, dismissed_by)
  values (p_data, left(p_descricao, 300), round(p_valor, 2), p_tipo, 'cash', 'caixa',
          'caixa:' || gen_random_uuid(), public._conta_caixa(), p_quem, true,
          p_fora_tipo, p_fora_motivo, case when p_fora_tipo is not null then now() end,
          case when p_fora_tipo is not null then p_autor end)
  returning id into v_id;
  return v_id;
end;
$$;

-- ── Lançar no Caixa (ou pago do bolso do sócio) ─────────────────────────────────────────
create or replace function public.lancar_no_caixa(
  p_sentido text,                 -- 'saida' | 'entrada'
  p_valor numeric,
  p_descricao text,
  p_data date default null,
  p_categoria text default null,
  p_fornecedor_id uuid default null,
  p_favorecido_id uuid default null,
  p_cliente_id uuid default null,
  p_os_id uuid default null,
  p_pago_por text default 'caixa',   -- 'caixa' | 'socio' (saiu do bolso de um sócio: vira reembolso a pagar)
  p_socio_id uuid default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_data date := coalesce(p_data, public._hoje_brt());
  v_desc text := nullif(btrim(coalesce(p_descricao, '')), '');
  v_cat text;
  v_quem text;
  v_tx uuid;
  v_id uuid;
  v_socio text;
begin
  if p_sentido not in ('saida', 'entrada') then raise exception 'Sentido inválido: % (saida ou entrada).', p_sentido; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;
  if v_desc is null then raise exception 'Diga o que foi (ex.: almoço da equipe).'; end if;
  if p_pago_por not in ('caixa', 'socio') then raise exception 'Pago por: caixa ou socio.'; end if;
  if v_data > public._hoje_brt() + 1 then raise exception 'Data no futuro: para algo que ainda vai acontecer, use conta a pagar.'; end if;
  perform public._recusa_se_mes_fechado(v_data, 'lançar nesta data');

  v_quem := coalesce(
    (select name from public.suppliers where id = p_fornecedor_id),
    (select name from public.payees where id = p_favorecido_id),
    (select name from public.clients where id = p_cliente_id));

  if p_sentido = 'saida' then
    -- Categoria: a informada; senão a padrão do favorecido; senão "Outras despesas".
    v_cat := coalesce(nullif(btrim(coalesce(p_categoria, '')), ''),
                      (select default_category from public.payees where id = p_favorecido_id),
                      'Outras despesas');

    if p_pago_por = 'socio' then
      if p_socio_id is null then raise exception 'Diga qual sócio pagou, para o reembolso ficar no nome dele.'; end if;
      select name into v_socio from public.payees where id = p_socio_id;
      if v_socio is null then raise exception 'Sócio não encontrado entre os favorecidos.'; end if;
      -- A despesa existe (entra no resultado) e a empresa DEVE ao sócio: conta a pagar em
      -- aberto no nome dele. Nada sai do Caixa.
      insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                   expense_category, supplier_id, payee_id, linked_service_order_id, origin, notes)
      values (left('Pago por ' || v_socio || ': ' || v_desc, 200), v_data, v_data, round(p_valor, 2), 0, round(p_valor, 2), 'pending',
              v_cat, p_fornecedor_id, p_socio_id, p_os_id, 'manual',
              'Reembolso ao sócio — pago do bolso' || coalesce(' para ' || v_quem, '') || '.')
      returning id into v_id;
    else
      v_tx := public._linha_do_caixa('debit', p_valor, v_data, v_desc, coalesce(v_quem, v_desc), null, null, v_autor);
      insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                   expense_category, supplier_id, payee_id, supplier_name, linked_service_order_id,
                                   origin, payment_method, bank_transaction_id)
      values (left(v_desc, 200), v_data, v_data, round(p_valor, 2), round(p_valor, 2), 0, 'paid',
              v_cat, p_fornecedor_id, p_favorecido_id, case when p_fornecedor_id is null then v_quem end, p_os_id,
              'manual', 'cash', v_tx)
      returning id into v_id;
    end if;
  else
    if p_cliente_id is null then raise exception 'Dinheiro que entra precisa de cliente: de quem veio?'; end if;
    if p_pago_por <> 'caixa' then raise exception 'Entrada em dinheiro vai para o Caixa.'; end if;
    v_cat := coalesce(nullif(btrim(coalesce(p_categoria, '')), ''), 'Serviços prestados');
    v_tx := public._linha_do_caixa('credit', p_valor, v_data, v_desc, v_quem, null, null, v_autor);
    insert into public.receivables (description, issue_date, due_date, amount, paid_amount, balance_amount, status,
                                    category, client_id, service_order_id, payment_method, bank_transaction_id)
    values (left(v_desc, 200), v_data, v_data, round(p_valor, 2), round(p_valor, 2), 0, 'paid',
            v_cat, p_cliente_id, p_os_id, 'cash', v_tx)
    returning id into v_id;
  end if;

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, payable_id, receivable_id, valor, detalhe, antes, depois)
  values ('lancou_no_caixa', v_autor, v_tx,
          case when p_sentido = 'saida' then v_id end, case when p_sentido = 'entrada' then v_id end,
          round(p_valor, 2),
          left(case when p_pago_por = 'socio' then 'Pago do bolso de ' || v_socio || ': ' else '' end || v_desc || coalesce(' · ' || v_quem, ''), 300),
          null, jsonb_build_object('sentido', p_sentido, 'categoria', v_cat, 'pago_por', p_pago_por, 'data', v_data));

  return jsonb_build_object(
    'ok', true,
    'lancamento_id', v_id,
    'tipo', case when p_sentido = 'saida' then 'payable' else 'receivable' end,
    'categoria', v_cat,
    'saldo_do_caixa', public.saldo_do_caixa(),
    'message', case
      when p_pago_por = 'socio' then 'Lançado ' || public._brl(p_valor) || ' em ' || v_cat || ', pago por ' || v_socio || ' — fica como reembolso a pagar a ele.'
      when p_sentido = 'saida' then 'Lançado ' || public._brl(p_valor) || ' em ' || v_cat || ', pago em dinheiro. Caixa agora: ' || public._brl(public.saldo_do_caixa()) || '.'
        || case when public.saldo_do_caixa() < 0 then ' Atenção: o Caixa ficou negativo — falta registrar o dinheiro que entrou nele (saldo inicial pela contagem, ou o saque do banco).' else '' end
      else 'Entrada de ' || public._brl(p_valor) || ' em dinheiro lançada. Caixa agora: ' || public._brl(public.saldo_do_caixa()) || '.' end
  );
end;
$$;

-- ── Saque e depósito: dinheiro que muda de lugar, não de dono ──────────────────────────
create or replace function public.mover_caixa(
  p_sentido text,                 -- 'saque' (banco → caixa) | 'deposito' (caixa → banco)
  p_valor numeric,
  p_data date default null,
  p_transacao_banco uuid default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_data date := coalesce(p_data, public._hoje_brt());
  v_banco public.bank_transactions%rowtype;
  v_rotulo text;
begin
  if p_sentido not in ('saque', 'deposito') then raise exception 'Sentido inválido: % (saque ou deposito).', p_sentido; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;
  perform public._recusa_se_mes_fechado(v_data, 'lançar nesta data');
  v_rotulo := case when p_sentido = 'saque' then 'Saque do banco para o Caixa' else 'Depósito do Caixa no banco' end;

  if p_transacao_banco is not null then
    select * into v_banco from public.bank_transactions where id = p_transacao_banco for update;
    if v_banco.id is null then raise exception 'Linha do banco não encontrada.'; end if;
    if (p_sentido = 'saque' and v_banco.transaction_type <> 'debit') or (p_sentido = 'deposito' and v_banco.transaction_type <> 'credit') then
      raise exception 'Saque é saída do banco; depósito é entrada no banco.';
    end if;
    if abs(v_banco.amount - p_valor) > 0.01 then raise exception 'O valor da linha do banco (%) não é o informado.', public._brl(v_banco.amount); end if;
    if exists (select 1 from public.payables where bank_transaction_id = p_transacao_banco)
       or exists (select 1 from public.receivables where bank_transaction_id = p_transacao_banco) then
      raise exception 'Essa linha do banco já virou lançamento. Desfaça antes.';
    end if;
    update public.bank_transactions set reconciled = true, dismissed_kind = 'transferencia', dismissed_reason = v_rotulo,
           dismissed_at = now(), dismissed_by = v_autor where id = p_transacao_banco;
    update public.finance_review_queue set status = 'superseded', decision_note = v_rotulo
     where bank_transaction_id = p_transacao_banco and status = 'pending';
    v_data := v_banco.transaction_date;
  end if;

  perform public._linha_do_caixa(case when p_sentido = 'saque' then 'credit' else 'debit' end, p_valor, v_data, v_rotulo, null,
                                 'transferencia', v_rotulo, v_autor);

  insert into public.reconciliation_log (acao, autor, bank_transaction_id, valor, detalhe)
  values ('moveu_caixa', v_autor, p_transacao_banco, round(p_valor, 2), v_rotulo);

  return jsonb_build_object('ok', true, 'saldo_do_caixa', public.saldo_do_caixa(),
    'message', v_rotulo || ': ' || public._brl(p_valor) || '. Caixa agora: ' || public._brl(public.saldo_do_caixa()) || '.');
end;
$$;

-- ── Contei o dinheiro: o Caixa passa a bater com a contagem ────────────────────────────
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

-- ── Anotação antecipada ────────────────────────────────────────────────────────────────
-- "Fiz um Pix de 1.500 para o CNPJ X, classifica como fornecedor TSD." O banco só traz a
-- transação um ou dois dias depois; a anotação espera por ela e, quando ela chega, a
-- proposta já nasce com o que o dono disse.
create table if not exists public.anotacoes_do_extrato (
  id uuid primary key default gen_random_uuid(),
  sentido text not null check (sentido in ('debit', 'credit')),
  valor numeric not null check (valor > 0),
  data_prevista date not null,
  documento text,
  nome text,
  fornecedor_id uuid references public.suppliers(id) on delete set null,
  favorecido_id uuid references public.payees(id) on delete set null,
  cliente_id uuid references public.clients(id) on delete set null,
  categoria text,
  os_id uuid references public.service_orders(id) on delete set null,
  descricao text,
  status text not null default 'aguardando' check (status in ('aguardando', 'aplicada', 'cancelada')),
  bank_transaction_id uuid references public.bank_transactions(id) on delete set null,
  criada_por uuid references public.app_users(id) on delete set null,
  criada_em timestamptz not null default now(),
  aplicada_em timestamptz
);
alter table public.anotacoes_do_extrato enable row level security;
revoke all on public.anotacoes_do_extrato from anon;
drop policy if exists "financeiro le anotacoes" on public.anotacoes_do_extrato;
create policy "financeiro le anotacoes" on public.anotacoes_do_extrato
  for select to authenticated using (public.is_admin_or_financial((select auth.uid())));
drop policy if exists "financeiro cancela anotacoes" on public.anotacoes_do_extrato;
create policy "financeiro cancela anotacoes" on public.anotacoes_do_extrato
  for update to authenticated using (public.is_admin_or_financial((select auth.uid())))
  with check (public.is_admin_or_financial((select auth.uid())));

/** Aplica uma anotação a uma proposta pendente: o que o dono disse vira a sugestão. */
create or replace function public._aplicar_anotacao(p_anotacao uuid, p_proposta uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  a public.anotacoes_do_extrato%rowtype;
  v_dre text;
begin
  select * into a from public.anotacoes_do_extrato where id = p_anotacao;
  if a.categoria is not null then
    select dre_group into v_dre from public.financial_categories where name = a.categoria and active limit 1;
  end if;
  update public.finance_review_queue q set
    suggested_supplier_id = coalesce(a.fornecedor_id, q.suggested_supplier_id),
    suggested_payee_id = coalesce(a.favorecido_id, q.suggested_payee_id),
    suggested_client_id = coalesce(a.cliente_id, q.suggested_client_id),
    suggested_service_order_id = coalesce(a.os_id, q.suggested_service_order_id),
    suggested_category = coalesce(a.categoria, q.suggested_category),
    dre_group = coalesce(v_dre, q.dre_group),
    suggested_description = coalesce(a.descricao, q.suggested_description),
    confidence = 99,
    reasoning = left('Anotado por você em ' || to_char(a.criada_em at time zone 'America/Sao_Paulo', 'DD/MM')
                     || coalesce(': ' || a.descricao, '') || ' · ' || coalesce(q.reasoning, ''), 2000),
    evidencia = coalesce(q.evidencia, '{}'::jsonb) - 'cadastrar' || jsonb_build_object('anotacao', jsonb_build_object('id', a.id)),
    updated_at = now()
  where q.id = p_proposta and q.status = 'pending';
  update public.anotacoes_do_extrato
     set status = 'aplicada', aplicada_em = now(),
         bank_transaction_id = (select bank_transaction_id from public.finance_review_queue where id = p_proposta)
   where id = p_anotacao;
end;
$$;

/**
 * A transação desta anotação: mesmo sentido, valor ao centavo, de 3 dias antes a 7 dias
 * depois da data prevista, e o documento, quando informado. A mais próxima da data vence.
 */
create or replace function public._proposta_da_anotacao(p_anotacao uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select q.id
    from public.anotacoes_do_extrato a
    join public.bank_transactions t on t.transaction_type = a.sentido
     and abs(t.amount - a.valor) < 0.01
     and t.transaction_date between a.data_prevista - 3 and a.data_prevista + 7
     and (a.documento is null or regexp_replace(coalesce(t.counterparty_document, ''), '\D', '', 'g') = a.documento)
    join public.finance_review_queue q on q.bank_transaction_id = t.id and q.status = 'pending'
     and q.kind = case when a.sentido = 'debit' then 'create_payable' else 'create_receivable' end
   where a.id = p_anotacao
   order by abs(t.transaction_date - a.data_prevista), t.transaction_date
   limit 1;
$$;

create or replace function public.anotar_transacao(
  p_sentido text,                 -- 'saida' | 'entrada'
  p_valor numeric,
  p_data date default null,
  p_documento text default null,
  p_nome text default null,
  p_fornecedor_id uuid default null,
  p_favorecido_id uuid default null,
  p_cliente_id uuid default null,
  p_categoria text default null,
  p_os_id uuid default null,
  p_descricao text default null,
  p_autor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_autor uuid := public._autor_do_financeiro(p_autor);
  v_id uuid;
  v_proposta uuid;
  v_doc text := nullif(regexp_replace(coalesce(p_documento, ''), '\D', '', 'g'), '');
  v_lancada record;
begin
  if p_sentido not in ('saida', 'entrada') then raise exception 'Sentido inválido: % (saida ou entrada).', p_sentido; end if;
  if p_valor is null or p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;
  if v_doc is not null and length(v_doc) not in (11, 14) then raise exception 'CPF tem 11 dígitos e CNPJ tem 14.'; end if;
  if p_categoria is null and p_fornecedor_id is null and p_favorecido_id is null and p_cliente_id is null and p_os_id is null then
    raise exception 'Diga o que classificar: fornecedor, favorecido, cliente, categoria ou OS.';
  end if;

  insert into public.anotacoes_do_extrato (sentido, valor, data_prevista, documento, nome, fornecedor_id, favorecido_id,
                                           cliente_id, categoria, os_id, descricao, criada_por)
  values (case when p_sentido = 'saida' then 'debit' else 'credit' end, round(p_valor, 2), coalesce(p_data, public._hoje_brt()),
          v_doc, nullif(btrim(coalesce(p_nome, '')), ''), p_fornecedor_id, p_favorecido_id, p_cliente_id,
          nullif(btrim(coalesce(p_categoria, '')), ''), p_os_id, nullif(btrim(coalesce(p_descricao, '')), ''), v_autor)
  returning id into v_id;

  -- Já chegou do banco e está na fila? Aplica agora.
  v_proposta := public._proposta_da_anotacao(v_id);
  if v_proposta is not null then
    perform public._aplicar_anotacao(v_id, v_proposta);
    return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', true, 'proposta_id', v_proposta,
      'message', 'A transação já tinha chegado do banco: a linha do Extrato foi classificada como você disse. Falta aprovar.');
  end if;

  -- Já chegou E já virou lançamento? Então não é anotação, é correção.
  select coalesce(p.id, r.id) id, case when p.id is not null then 'payable' else 'receivable' end tipo into v_lancada
    from public.bank_transactions t
    left join public.payables p on p.bank_transaction_id = t.id and p.status <> 'cancelled'
    left join public.receivables r on r.bank_transaction_id = t.id and r.status <> 'cancelled'
   where t.transaction_type = case when p_sentido = 'saida' then 'debit' else 'credit' end
     and abs(t.amount - p_valor) < 0.01
     and t.transaction_date between coalesce(p_data, public._hoje_brt()) - 3 and coalesce(p_data, public._hoje_brt()) + 7
     and (v_doc is null or regexp_replace(coalesce(t.counterparty_document, ''), '\D', '', 'g') = v_doc)
     and coalesce(p.id, r.id) is not null
   limit 1;
  if v_lancada.id is not null then
    update public.anotacoes_do_extrato set status = 'cancelada' where id = v_id;
    return jsonb_build_object('ok', false, 'ja_lancada', true, 'lancamento_id', v_lancada.id, 'tipo', v_lancada.tipo,
      'message', 'Essa transação já chegou e já foi lançada. Para mudar fornecedor ou categoria, corrija o lançamento.');
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'aplicada', false,
    'message', 'Anotado. Quando a transação chegar do banco, ela já entra classificada.');
end;
$$;

/** Para a varredura diária: toda anotação esperando é conferida contra a fila. */
create or replace function public.aplicar_anotacoes_pendentes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  v_proposta uuid;
  v_n integer := 0;
begin
  for a in select id from public.anotacoes_do_extrato where status = 'aguardando' order by criada_em loop
    v_proposta := public._proposta_da_anotacao(a.id);
    if v_proposta is not null then
      perform public._aplicar_anotacao(a.id, v_proposta);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$$;

-- ── Quem executa ────────────────────────────────────────────────────────────────────────
revoke all on function public._conta_caixa() from public, anon, authenticated;
revoke all on function public._hoje_brt() from public, anon;
revoke all on function public._linha_do_caixa(text, numeric, date, text, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public._aplicar_anotacao(uuid, uuid) from public, anon, authenticated;
revoke all on function public._proposta_da_anotacao(uuid) from public, anon, authenticated;
revoke all on function public.saldo_do_caixa() from public, anon;
revoke all on function public.lancar_no_caixa(text, numeric, text, date, text, uuid, uuid, uuid, uuid, text, uuid, uuid) from public, anon;
revoke all on function public.mover_caixa(text, numeric, date, uuid, uuid) from public, anon;
revoke all on function public.ajustar_caixa(numeric, text, uuid) from public, anon;
revoke all on function public.anotar_transacao(text, numeric, date, text, text, uuid, uuid, uuid, text, uuid, text, uuid) from public, anon;
grant execute on function public._conta_caixa() to service_role;
grant execute on function public._hoje_brt() to authenticated, service_role;
grant execute on function public._linha_do_caixa(text, numeric, date, text, text, text, text, uuid) to service_role;
grant execute on function public._aplicar_anotacao(uuid, uuid) to service_role;
grant execute on function public._proposta_da_anotacao(uuid) to service_role;
-- Saldo do Caixa: a tela lê pelo extrato da conta (que respeita o cargo); aqui, só o sistema.
revoke all on function public.saldo_do_caixa() from authenticated;
grant execute on function public.saldo_do_caixa() to service_role;
revoke all on function public.aplicar_anotacoes_pendentes() from public, anon, authenticated;
grant execute on function public.aplicar_anotacoes_pendentes() to service_role;
grant execute on function public.lancar_no_caixa(text, numeric, text, date, text, uuid, uuid, uuid, uuid, text, uuid, uuid) to authenticated, service_role;
grant execute on function public.mover_caixa(text, numeric, date, uuid, uuid) to authenticated, service_role;
grant execute on function public.ajustar_caixa(numeric, text, uuid) to authenticated, service_role;
grant execute on function public.anotar_transacao(text, numeric, date, text, text, uuid, uuid, uuid, text, uuid, text, uuid) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20260926150000', 'caixa_e_anotacoes')
on conflict do nothing;
