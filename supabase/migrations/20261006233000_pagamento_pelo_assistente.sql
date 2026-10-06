-- Registrar pagamento pelo assistente (06/10/2026).
--
-- POR QUE: register_payment_and_update_balance só aceitava o usuário da SESSÃO
-- (is_admin_or_financial(auth.uid())). O assistente roda com o service role — sem sessão —, então
-- auth.uid() é nulo e toda baixa pelo assistente terminava em "Acesso negado", até para o dono:
-- 0 de 6 em 60 dias (15/07, 21/08...). O conciliar_transacao do assistente usa a mesma função.
--
-- Agora vale o mesmo padrão das funções de lançamento (_autor_do_financeiro, 25/09/2026): na tela,
-- o usuário da sessão; pelo assistente, quem pediu (p_autor), e os dois precisam ser admin ou
-- financeiro. anon e public não executam a função, então "sem usuário e sem autor" só pode ser o
-- service role (as rotinas do sistema).
--
-- O corpo é o de produção em 06/10/2026, sem outra mudança. A assinatura ganha p_autor com default:
-- as chamadas da tela (parâmetros nomeados, sem p_autor) continuam iguais.

drop function if exists public.register_payment_and_update_balance(uuid, uuid, numeric, date, text, integer, numeric, numeric, text);

create function public.register_payment_and_update_balance(
  p_receivable_id uuid,
  p_payable_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_payment_method text,
  p_installments integer,
  p_card_fee_percent numeric,
  p_net_amount numeric,
  p_notes text,
  p_autor uuid default null
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_payment_id      UUID;
  v_total_paid      NUMERIC;
  v_original_amount NUMERIC;
  v_new_balance     NUMERIC;
  v_new_status      TEXT;
  v_table_name      TEXT;
  v_parent_id       UUID;
BEGIN
  -- Autorização: admin ou financeiro — o usuário da sessão ou, pelo assistente, quem pediu.
  PERFORM public._autor_do_financeiro(p_autor);

  -- Validação de valor positivo
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'O valor do pagamento deve ser maior que zero (recebido: %)', p_amount;
  END IF;

  IF p_card_fee_percent IS NOT NULL AND (p_card_fee_percent < 0 OR p_card_fee_percent > 100) THEN
    RAISE EXCEPTION 'Percentual de taxa de cartão inválido: %', p_card_fee_percent;
  END IF;

  INSERT INTO public.payments (
    receivable_id, payable_id, amount, payment_date, payment_method,
    installments, card_fee_percent, net_amount, notes, status
  ) VALUES (
    p_receivable_id, p_payable_id, p_amount, p_payment_date, p_payment_method,
    p_installments, p_card_fee_percent, p_net_amount, p_notes, 'confirmed'
  ) RETURNING id INTO v_payment_id;

  IF p_receivable_id IS NOT NULL THEN
    v_table_name := 'receivables';
    v_parent_id  := p_receivable_id;
  ELSIF p_payable_id IS NOT NULL THEN
    v_table_name := 'payables';
    v_parent_id  := p_payable_id;
  ELSE
    RAISE EXCEPTION 'Deve fornecer receivable_id ou payable_id';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM public.payments
  WHERE (receivable_id = p_receivable_id OR payable_id = p_payable_id)
    AND status = 'confirmed';

  IF v_table_name = 'receivables' THEN
    SELECT amount INTO v_original_amount FROM public.receivables WHERE id = v_parent_id FOR UPDATE;
  ELSE
    SELECT amount INTO v_original_amount FROM public.payables WHERE id = v_parent_id FOR UPDATE;
  END IF;

  v_new_balance := GREATEST(0, v_original_amount - v_total_paid);

  IF v_total_paid >= v_original_amount THEN
    v_new_status := 'paid';
  ELSIF v_total_paid > 0 THEN
    v_new_status := 'partially_paid';
  ELSE
    v_new_status := 'pending';
  END IF;

  IF v_table_name = 'receivables' THEN
    UPDATE public.receivables SET paid_amount=v_total_paid, balance_amount=v_new_balance, status=v_new_status WHERE id=v_parent_id;
  ELSE
    UPDATE public.payables SET paid_amount=v_total_paid, balance_amount=v_new_balance, status=v_new_status WHERE id=v_parent_id;
  END IF;

  RETURN json_build_object('payment_id',v_payment_id,'total_paid',v_total_paid,'balance_amount',v_new_balance,'status',v_new_status);
END;
$function$;

revoke all on function public.register_payment_and_update_balance(uuid, uuid, numeric, date, text, integer, numeric, numeric, text, uuid) from public, anon;
grant execute on function public.register_payment_and_update_balance(uuid, uuid, numeric, date, text, integer, numeric, numeric, text, uuid) to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.register_payment_and_update_balance(uuid, uuid, numeric, date, text, integer, numeric, numeric, text, uuid)', 'execute') then
    raise exception 'register_payment_and_update_balance exposta ao anon';
  end if;
  if not has_function_privilege('authenticated', 'public.register_payment_and_update_balance(uuid, uuid, numeric, date, text, integer, numeric, numeric, text, uuid)', 'execute') then
    raise exception 'register_payment_and_update_balance sem acesso para a tela';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261006233000', 'pagamento_pelo_assistente')
on conflict do nothing;
