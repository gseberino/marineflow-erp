-- Financeiro pelo assistente (07/10/2026): corrigir a anotação de Pix e estornar pagamento.
--
-- POR QUE duas funções novas, e não o caminho da tela:
--
-- 1. corrigir_anotacao — a tela (Caixa › "Anotado, esperando o banco") só CANCELA a anotação; não
--    há como corrigir valor, categoria ou data. O assistente faz o que a tela permitiria em dois
--    passos (cancelar e anotar de novo), mas numa transação só: se a anotação corrigida não couber
--    (outra anotação igual esperando, duas transações do mesmo valor, já lançada...), NADA muda e a
--    anotação antiga continua esperando. Anotar de novo é a MESMA anotar_transacao da tela e do
--    assistente — as regras de casamento não têm como divergir.
--
-- 2. estornar_pagamento — o "Cancelar (estornar)" da tela (PaymentDialog → cancelPaymentCascade,
--    src/lib/cascade-updates.ts) grava passo a passo pelo navegador: marca o pagamento cancelado,
--    recalcula a conta, desfaz o reembolso de gasto da OS e grava a auditoria. Pelo assistente
--    (service role, sem sessão) isso vira uma função com p_autor (_autor_do_financeiro) e com os
--    mesmos efeitos — numa transação só: mês fechado (o gatilho da conta) recusa o estorno inteiro,
--    em vez de deixar o pagamento cancelado e a conta sem recalcular. Pagamento que veio do EXTRATO
--    (Pix aplicado, ou linha conciliada) não se estorna aqui: tem caminho próprio, que devolve a
--    linha para a fila (desfazer a aplicação do Pix / desfazer a aprovação do lançamento).

-- ── 1. corrigir_anotacao ──────────────────────────────────────────────────────────────────────────
create or replace function public.corrigir_anotacao(
  p_anotacao uuid,
  p_valor numeric default null,
  p_categoria text default null,
  p_data date default null,
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
  v_antiga public.anotacoes_do_extrato%rowtype;
  v_res jsonb;
  v_categoria text := nullif(btrim(coalesce(p_categoria, '')), '');
begin
  select * into v_antiga from public.anotacoes_do_extrato where id = p_anotacao for update;
  if not found then raise exception 'Anotação não encontrada.'; end if;
  if v_antiga.status <> 'aguardando' then
    raise exception 'Esta anotação não está mais esperando o banco (%): nada a corrigir.',
      case v_antiga.status when 'aplicada' then 'já foi aplicada a uma transação' else 'foi cancelada' end;
  end if;
  if p_valor is null and v_categoria is null and p_data is null then
    raise exception 'Diga o que corrigir: valor, categoria ou data.';
  end if;
  if p_valor is not null and p_valor <= 0 then raise exception 'O valor precisa ser maior que zero.'; end if;

  -- Bloco com EXCEPTION = subtransação: se a anotação corrigida não couber, o cancelamento da
  -- antiga e a nova voltam atrás juntos.
  begin
    update public.anotacoes_do_extrato
       set status = 'cancelada', cancelada_em = now(),
           motivo_cancelamento = left('corrigida' || coalesce(': ' || nullif(btrim(coalesce(p_motivo, '')), ''), ''), 500)
     where id = p_anotacao;

    v_res := public.anotar_transacao(
      case when v_antiga.sentido = 'debit' then 'saida' else 'entrada' end,
      coalesce(p_valor, v_antiga.valor),
      coalesce(p_data, v_antiga.data_prevista),
      v_antiga.documento, v_antiga.nome,
      v_antiga.fornecedor_id, v_antiga.favorecido_id, v_antiga.cliente_id,
      coalesce(v_categoria, v_antiga.categoria),
      v_antiga.os_id, v_antiga.descricao,
      v_autor);

    if not coalesce((v_res ->> 'ok')::boolean, false) then
      raise exception using errcode = 'MFA01', message = 'a anotação corrigida não coube';
    end if;
  exception when sqlstate 'MFA01' then
    return jsonb_build_object('ok', false, 'corrigida', false, 'anotacao_id', p_anotacao,
      'message', 'Nada mudou: a anotação antiga continua esperando o banco. ' || coalesce(v_res ->> 'message', ''));
  end;

  -- A data dita na anotação original vale como foi dita: sem data nova, a corrigida volta a ter a
  -- folga de dias da antiga (anotar_transacao marca como exata toda data passada a ela).
  if p_data is null and not v_antiga.data_exata then
    update public.anotacoes_do_extrato set data_exata = false
     where id = (v_res ->> 'id')::uuid and status = 'aguardando';
  end if;

  return v_res || jsonb_build_object('corrigida', true, 'anotacao_antiga', p_anotacao, 'anotacao_id', v_res -> 'id');
end;
$$;

revoke all on function public.corrigir_anotacao(uuid, numeric, text, date, text, uuid) from public, anon;
grant execute on function public.corrigir_anotacao(uuid, numeric, text, date, text, uuid) to authenticated, service_role;

-- ── 2. estornar_pagamento ─────────────────────────────────────────────────────────────────────────
create or replace function public.estornar_pagamento(
  p_pagamento uuid,
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
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  p public.payments%rowtype;
  v_pago numeric;
  v_valor numeric;
  v_status text;
  v_descricao text;
  v_quem text;
  v_brl text;
begin
  if v_motivo is null or length(v_motivo) < 3 then raise exception 'Diga o motivo do estorno.'; end if;

  select * into p from public.payments where id = p_pagamento for update;
  if not found then raise exception 'Pagamento não encontrado.'; end if;
  if p.status <> 'confirmed' then
    raise exception 'Este pagamento já está estornado (desde %).',
      coalesce(to_char(p.cancelled_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'), 'antes');
  end if;
  if p.bank_transaction_id is not null
     or exists (select 1 from public.bank_transactions t where t.reconciled_payment_id = p.id) then
    raise exception 'Este pagamento veio do extrato do banco: não se estorna, desfaz-se a aplicação do Pix (conta a receber) ou a aprovação do lançamento (conta a pagar) — a linha volta para a fila do Extrato.';
  end if;

  update public.payments
     set status = 'cancelled', cancelled_at = now(), cancellation_reason = v_motivo
   where id = p.id;

  -- O mesmo recálculo da tela (recalcReceivableBalance / recalcPayableBalance).
  if p.receivable_id is not null then
    select coalesce(sum(amount), 0) into v_pago
      from public.payments where receivable_id = p.receivable_id and status = 'confirmed';
    select amount, description into v_valor, v_descricao from public.receivables where id = p.receivable_id for update;
    v_status := case when v_pago >= v_valor then 'paid' when v_pago > 0 then 'partially_paid' else 'pending' end;
    update public.receivables
       set paid_amount = v_pago, balance_amount = greatest(0, v_valor - v_pago), status = v_status
     where id = p.receivable_id;
  elsif p.payable_id is not null then
    select coalesce(sum(amount), 0) into v_pago
      from public.payments where payable_id = p.payable_id and status = 'confirmed';
    select amount, description into v_valor, v_descricao from public.payables where id = p.payable_id for update;
    v_status := case when v_pago >= v_valor then 'paid' when v_pago > 0 then 'partially_paid' else 'pending' end;
    update public.payables
       set paid_amount = v_pago, balance_amount = greatest(0, v_valor - v_pago), status = v_status
     where id = p.payable_id;
  end if;

  -- O reembolso de gasto da OS que tinha este pagamento como prova volta a ficar em aberto.
  update public.service_order_expenses
     set reimbursed = false, reimbursed_at = null, reimbursed_payment_id = null
   where reimbursed_payment_id = p.id;

  select full_name into v_quem from public.app_users where id = v_autor;
  insert into public.audit_log (table_name, record_id, action, changed_by, previous_value, new_value, reason)
  values ('payments', p.id, 'cancel', coalesce(v_quem, 'assistente'),
          jsonb_build_object('status', 'confirmed', 'amount', p.amount),
          jsonb_build_object('status', 'cancelled'), v_motivo);

  v_brl := translate(to_char(p.amount, 'FM999,999,990.00'), ',.', '.,');
  return jsonb_build_object(
    'ok', true,
    'pagamento_id', p.id,
    'valor', p.amount,
    'conta', case when p.receivable_id is not null then 'receber' when p.payable_id is not null then 'pagar' end,
    'conta_id', coalesce(p.receivable_id, p.payable_id),
    'situacao_da_conta', v_status,
    'saldo_da_conta', case when v_valor is null then null else greatest(0, v_valor - v_pago) end,
    'message', format('Estornei o pagamento de R$ %s de %s%s. A conta voltou a %s.',
      v_brl, to_char(p.payment_date, 'DD/MM/YYYY'), coalesce(' (' || v_descricao || ')', ''),
      case v_status when 'pending' then 'ficar em aberto' when 'partially_paid' then 'ficar parcialmente paga' else 'ficar paga (há outros pagamentos)' end)
  );
end;
$$;

revoke all on function public.estornar_pagamento(uuid, text, uuid) from public, anon;
grant execute on function public.estornar_pagamento(uuid, text, uuid) to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.corrigir_anotacao(uuid, numeric, text, date, text, uuid)', 'execute') then
    raise exception 'corrigir_anotacao exposta ao anon';
  end if;
  if has_function_privilege('anon', 'public.estornar_pagamento(uuid, text, uuid)', 'execute') then
    raise exception 'estornar_pagamento exposta ao anon';
  end if;
  if not has_function_privilege('authenticated', 'public.corrigir_anotacao(uuid, numeric, text, date, text, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.estornar_pagamento(uuid, text, uuid)', 'execute') then
    raise exception 'funções do financeiro sem acesso para quem está logado';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261007100000', 'financeiro_pelo_assistente')
on conflict do nothing;
