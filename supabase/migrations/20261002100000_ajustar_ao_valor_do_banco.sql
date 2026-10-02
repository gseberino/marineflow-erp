-- Ajustar uma conta a receber ao valor que entrou no banco (02/10/2026).
--
-- Pedido do dono: no "Mês pronto?", o lançamento que não bate com o extrato só dizia "Veio do
-- extrato. Para mudar, desfaça a aprovação" — sem dizer qual aprovação nem oferecer o conserto.
-- O caso que motivou: o sinal do ORÇ-00073 é R$ 1.865,47 e o cliente pagou R$ 1.866,00.
--
-- Medido antes (02/10): 4 lançamentos com diferença para o banco, todos a receber e casados (não
-- nasceram do extrato). Só 2 têm UM pagamento, e é o da linha do banco: ORÇ-00073 (+R$ 0,53) e
-- OS-00046 (R$ 520 com R$ 500 no banco: R$ 20 em aberto). Os outros 2 (OS-00034 e OS-00041, da
-- mesma cliente) têm dois pagamentos e vínculo trocado com cópias do mesmo Pix — não se ajustam
-- por botão; a função recusa e a tela explica.
--
-- O que faz: o pagamento que veio da linha passa a valer o valor do banco, e o lançamento
-- passa a valer o mesmo (pago, sem saldo). Banco maior: o cliente pagou a mais e a diferença
-- conta como recebida dele. Banco menor: a diferença deixa de ser cobrada (desconto). Fica na
-- trilha (reconciliation_log) e nas observações do lançamento. Só administrador ou financeiro.
-- Mês fechado recusa. Conta a pagar fica de fora por enquanto (divisão de pró-labore, compra
-- parcelada): lá o caminho continua sendo desfazer a aprovação.

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

  update public.payments set amount = v_banco where id = v_pagamento.id;
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

revoke all on function public.ajustar_ao_valor_do_banco(text, uuid, text, uuid) from public, anon;
grant execute on function public.ajustar_ao_valor_do_banco(text, uuid, text, uuid) to authenticated, service_role;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261002100000', 'ajustar_ao_valor_do_banco')
on conflict do nothing;
