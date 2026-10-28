-- Prova: o sinal registrado pela tela (register_deposit_and_convert) guarda o valor orçado e não pega o número
-- de outra OS (migration 20261029120000).
--
--   S1 orçamento com sinal registrado: vira OS-N (mesmo número), aberta, com o valor orçado guardado
--   S2 o OS-N já é de outra OS: o sinal registra e o número fica ORÇ-N (não duplica, não quebra)
--   S3 segundo sinal numa OS já convertida: número e valor orçado (vazio) ficam como estavam
--   S4 as permissões seguem as de antes: anon não executa; authenticated e service_role executam
--
-- ═══ COMO RODAR ═══ (só com OK nomeado)
--
--   supabase db query --linked -f supabase/tests/sinal_registrado_guarda_valor_orcado.sql --output json
--
-- Seguro em produção: cliente, barco e ordens de teste (números 9xxxxx livres), chamada sem usuário (= sistema),
-- sem parcelas de saldo nem cobranças; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop')
$$;

-- Número 9xxxxx livre como ORÇ- e como OS-
create function pg_temp._numero_livre() returns integer language plpgsql as $$
declare v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders
                where service_order_number in ('ORÇ-' || v_num, 'OS-' || v_num)) loop
    v_num := v_num + 1;
  end loop;
  return v_num;
end $$;

-- Ordem de teste com cliente e barco próprios
create function pg_temp._ordem(p_numero text, p_status text, p_quote_status text, p_total numeric,
                               p_convertida boolean default false)
returns uuid language plpgsql as $$
declare
  v_cli uuid;
  v_ves uuid;
  v_os uuid;
begin
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Sinal ' || pg_temp._letras(6))
  returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Navio' || pg_temp._letras(8)) returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, invoicing_status,
                                     grand_total, operational_cost_total, labor_cost_total, travel_cost_total,
                                     converted_to_os_at)
  values (p_numero, v_cli, v_ves, p_status, p_quote_status, 'not_invoiced', p_total, 0, 0, 0,
          case when p_convertida then now() - interval '1 day' end)
  returning id into v_os;
  return v_os;
end $$;

-- ═══ S1 conversão pelo sinal ════════════════════════════════════════════════════════════════
do $$
declare
  v_num integer := pg_temp._numero_livre();
  v_os uuid := pg_temp._ordem('ORÇ-' || v_num, 'draft', 'awaiting_deposit', 1000);
  r record;
begin
  perform public.register_deposit_and_convert(v_os, 300, current_date, 'pix');
  select service_order_number, status, quote_status, original_quote_amount, converted_to_os_at into r
    from public.service_orders where id = v_os;
  insert into _resultado values ('S1 sinal registrado: OS-N com o mesmo número, aberta e com o valor orçado guardado',
    r.service_order_number = 'OS-' || v_num and r.status = 'open' and r.quote_status = 'approved'
    and r.original_quote_amount = 1000 and r.converted_to_os_at is not null,
    'numero=' || r.service_order_number || ' status=' || r.status || ' quote=' || coalesce(r.quote_status, 'null')
    || ' orcado=' || coalesce(r.original_quote_amount::text, 'null'));
exception when others then
  insert into _resultado values ('S1 sinal registrado: OS-N com o mesmo número, aberta e com o valor orçado guardado',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ S2 número já ocupado ═══════════════════════════════════════════════════════════════════
do $$
declare
  v_num integer := pg_temp._numero_livre();
  v_outra uuid := pg_temp._ordem('OS-' || v_num, 'open', null, 500, true);
  v_os uuid := pg_temp._ordem('ORÇ-' || v_num, 'draft', 'awaiting_deposit', 800);
  r record;
  v_dup integer;
begin
  perform public.register_deposit_and_convert(v_os, 200, current_date, 'pix');
  select service_order_number, status, original_quote_amount into r from public.service_orders where id = v_os;
  select count(*) into v_dup from public.service_orders where service_order_number = 'OS-' || v_num;
  insert into _resultado values ('S2 OS-N já é de outra OS: o sinal registra e o número fica ORÇ-N',
    r.service_order_number = 'ORÇ-' || v_num and r.status = 'open' and r.original_quote_amount = 800 and v_dup = 1,
    'numero=' || r.service_order_number || ' status=' || r.status || ' com_OS-N=' || v_dup || ' outra=' || v_outra);
exception when others then
  insert into _resultado values ('S2 OS-N já é de outra OS: o sinal registra e o número fica ORÇ-N',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ S3 OS já convertida ════════════════════════════════════════════════════════════════════
do $$
declare
  v_num integer := pg_temp._numero_livre();
  v_os uuid := pg_temp._ordem('OS-' || v_num, 'open', 'approved', 2000, true);
  r record;
begin
  perform public.register_deposit_and_convert(v_os, 400, current_date, 'pix');
  select service_order_number, status, original_quote_amount into r from public.service_orders where id = v_os;
  insert into _resultado values ('S3 segundo sinal numa OS já convertida: número e valor orçado como estavam',
    r.service_order_number = 'OS-' || v_num and r.status = 'open' and r.original_quote_amount is null,
    'numero=' || r.service_order_number || ' orcado=' || coalesce(r.original_quote_amount::text, 'null'));
exception when others then
  insert into _resultado values ('S3 segundo sinal numa OS já convertida: número e valor orçado como estavam',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ S4 permissões ══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text := 'public.register_deposit_and_convert(uuid, numeric, date, text, numeric, text, jsonb, boolean)';
begin
  insert into _resultado values ('S4 anon não executa; authenticated e service_role executam',
    not has_function_privilege('anon', v_f, 'execute')
    and has_function_privilege('authenticated', v_f, 'execute')
    and has_function_privilege('service_role', v_f, 'execute'),
    'anon=' || has_function_privilege('anon', v_f, 'execute'));
exception when others then
  insert into _resultado values ('S4 anon não executa; authenticated e service_role executam',
    false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
