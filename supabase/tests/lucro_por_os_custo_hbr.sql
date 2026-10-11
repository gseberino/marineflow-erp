-- Prova: o Lucro por OS desconta o custo interno da OS (migration 20261011205000, OK nomeado P2).
--
--   L1 um custo interno de 10 (despesa não faturável) tira exatamente 10 do net_profit e aparece em hbr_cost
--   L2 a despesa que nasceu de comprovante (origem_codigo) é custo interno igual à marcada "Interno"
--   L3 a despesa faturável continua como antes (entra pelo operational_cost_total, não pelo hbr_cost)
--   L4 anon sem select na view; authenticated com; hbr_cost é a última coluna e as de antes ficam
--      na mesma ordem
--   L5 contar o deslocamento uma vez só (ajustes do dono, 11/10/2026): combustível interno de 30 numa OS
--      com deslocamento cobrado de 50 não tira nada; de 80 tira 30 (o maior dos dois, nunca a soma); o
--      pedágio também é viagem; numa OS sem deslocamento cobrado, a viagem interna entra inteira
--   L6 o cupom interno e a mesma compra também cobrada do cliente (mesmo valor, ±3 dias) contam uma vez só,
--      em qualquer ordem (revisão dos ajustes, 11/10/2026)
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado P3 da spec da F2; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/lucro_por_os_custo_hbr.sql --output json
--
-- Seguro em produção: cria as próprias OS (cliente e barco de mentira, número OS-9xxxxx livre), lança
-- as despesas direto na tabela e termina em ROLLBACK. Sem id nem data fixa.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._os(p_deslocamento numeric) returns uuid language plpgsql as $$
declare
  v_cli uuid;
  v_ves uuid;
  v_os uuid;
  v_num integer := 900000 + floor(random() * 99000)::integer;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'OS-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Lucro F2') returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Barco Teste Lucro F2') returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, grand_total,
                                     operational_cost_total, labor_cost_total, travel_cost_total)
  values ('OS-' || v_num, v_cli, v_ves, 'completed', 1000 + p_deslocamento, 0, 1000, p_deslocamento)
  returning id into v_os;
  return v_os;
end $$;

do $$
declare
  v_os uuid := pg_temp._os(0);
  v0 record;
  v1 record;
  v2 record;
  v3 record;
begin
  select net_profit, hbr_cost, operational_cost into v0 from public.vw_os_profitability where os_id = v_os;
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
  values (v_os, 'Outras despesas', 'custo interno de teste', 10, 'company', false);
  select net_profit, hbr_cost, operational_cost into v1 from public.vw_os_profitability where os_id = v_os;
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client, origem_codigo)
  values (v_os, 'Alimentação de campo', 'custo interno de comprovante (teste)', 7, 'company', false, 'CMP-99999');
  select net_profit, hbr_cost, operational_cost into v2 from public.vw_os_profitability where os_id = v_os;
  -- faturável: o lucro vê pelo operational_cost_total (o que a tela grava pela rota); aqui só a linha
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
  values (v_os, 'Outras despesas', 'faturável de teste', 5, 'company', true);
  select net_profit, hbr_cost, operational_cost into v3 from public.vw_os_profitability where os_id = v_os;

  insert into _resultado values ('L1 custo interno de 10 tira 10 do lucro e entra no hbr_cost',
    v0.net_profit - v1.net_profit = 10 and v0.hbr_cost = 0 and v1.hbr_cost = 10,
    'lucro ' || v0.net_profit || ' → ' || v1.net_profit || '; hbr_cost ' || v0.hbr_cost || ' → ' || v1.hbr_cost);
  insert into _resultado values ('L2 a despesa que nasceu de comprovante é custo interno (tira 7)',
    v1.net_profit - v2.net_profit = 7 and v2.hbr_cost = 17,
    'lucro ' || v1.net_profit || ' → ' || v2.net_profit || '; hbr_cost ' || v2.hbr_cost);
  insert into _resultado values ('L3 despesa faturável não entra no hbr_cost',
    v3.hbr_cost = 17 and v3.net_profit = v2.net_profit and v3.operational_cost = v2.operational_cost,
    'hbr_cost ' || v3.hbr_cost || '; lucro ' || v3.net_profit);
exception when others then
  insert into _resultado values ('L1-L3 Lucro por OS com o custo interno', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

do $$
declare
  v_cols text;
begin
  select string_agg(a.attname, ',' order by a.attnum) into v_cols
    from pg_attribute a
   where a.attrelid = 'public.vw_os_profitability'::regclass and a.attnum > 0 and not a.attisdropped;
  insert into _resultado values ('L4 anon sem select; colunas de antes na mesma ordem e hbr_cost no fim',
    not has_table_privilege('anon', 'public.vw_os_profitability', 'select')
    and has_table_privilege('authenticated', 'public.vw_os_profitability', 'select')
    and v_cols = 'os_id,service_order_number,status,revenue,parts_cost,travel_cost,operational_cost,commission_cost,'
                 || 'gross_profit,net_profit,net_margin_percent,created_at,finished_at,client_name,labor_cost_real,labor_days,'
                 || 'labor_sold,hours_sold,hbr_cost',
    v_cols);
exception when others then
  insert into _resultado values ('L4 anon sem select; colunas de antes na mesma ordem e hbr_cost no fim', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ L5: o deslocamento conta uma vez só (ajustes do dono, 11/10/2026) ═══════════════════════════
do $$
declare
  v_os uuid := pg_temp._os(50);
  v_sem uuid := pg_temp._os(0);
  v0 record;
  v30 record;
  v80 record;
  s0 record;
  s1 record;
begin
  select net_profit, hbr_cost into v0 from public.vw_os_profitability where os_id = v_os;
  -- combustível interno de 30 numa OS que cobra 50 de deslocamento: o custo da viagem já está no lucro
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client, origem_codigo)
  values (v_os, 'Combustível e deslocamento', 'combustível de teste', 30, 'company', false, 'CMP-99998');
  select net_profit, hbr_cost into v30 from public.vw_os_profitability where os_id = v_os;
  -- mais 50 de pedágio (viagem: 80 ao todo): só os 30 que passam do deslocamento cobrado
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
  values (v_os, 'Pedágio e estacionamento', 'pedágio de teste', 50, 'company', false);
  select net_profit, hbr_cost into v80 from public.vw_os_profitability where os_id = v_os;
  -- sem deslocamento cobrado, a viagem interna entra inteira
  select net_profit, hbr_cost into s0 from public.vw_os_profitability where os_id = v_sem;
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
  values (v_sem, 'Combustível e deslocamento', 'combustível de teste', 30, 'company', false);
  select net_profit, hbr_cost into s1 from public.vw_os_profitability where os_id = v_sem;
  insert into _resultado values ('L5 deslocamento uma vez só: viagem interna de 30 com 50 cobrados tira 0; de 80 tira 30; sem cobrado, tira tudo',
    v30.net_profit = v0.net_profit and v30.hbr_cost = 0
    and v0.net_profit - v80.net_profit = 30 and v80.hbr_cost = 30
    and s0.net_profit - s1.net_profit = 30 and s1.hbr_cost = 30,
    'cobrado 50: lucro ' || v0.net_profit || ' → ' || v30.net_profit || ' → ' || v80.net_profit
    || '; sem cobrado: ' || s0.net_profit || ' → ' || s1.net_profit);
exception when others then
  insert into _resultado values ('L5 deslocamento uma vez só: viagem interna de 30 com 50 cobrados tira 0; de 80 tira 30; sem cobrado, tira tudo', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ L6: a mesma compra também cobrada do cliente conta uma vez só (revisão dos ajustes, 11/10/2026) ═══
do $$
declare
  v_a uuid := pg_temp._os(0);
  v_b uuid := pg_temp._os(0);
  v_c uuid := pg_temp._os(0);
  a record;
  b record;
  c record;
  b1 record;
begin
  update public.service_orders set status = 'open' where id in (v_a, v_b, v_c);
  -- A: só a despesa cobrada (pela rota da tela, com o recálculo da OS)
  perform public.so_expense_add(v_a, 'Combustível e deslocamento', 'gasolina cobrada', 62, current_date, 'company', true, null, null);
  -- B: primeiro o cupom (custo interno do CMP), depois a mesma compra cobrada
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client,
                                             expense_date, origem_codigo)
  values (v_b, 'Combustível e deslocamento', 'cupom de gasolina (teste)', 62, 'company', false, current_date - 1, 'CMP-99997');
  select net_profit, hbr_cost into b1 from public.vw_os_profitability where os_id = v_b;
  perform public.so_expense_add(v_b, 'Combustível e deslocamento', 'gasolina cobrada', 62, current_date, 'company', true, null, null);
  -- C: a ordem inversa
  perform public.so_expense_add(v_c, 'Combustível e deslocamento', 'gasolina cobrada', 62, current_date, 'company', true, null, null);
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client,
                                             expense_date, origem_codigo)
  values (v_c, 'Combustível e deslocamento', 'cupom de gasolina (teste)', 62, 'company', false, current_date + 1, 'CMP-99996');
  select net_profit, hbr_cost into a from public.vw_os_profitability where os_id = v_a;
  select net_profit, hbr_cost into b from public.vw_os_profitability where os_id = v_b;
  select net_profit, hbr_cost into c from public.vw_os_profitability where os_id = v_c;
  insert into _resultado values ('L6 cupom interno + a mesma compra cobrada do cliente: conta uma vez, em qualquer ordem (o interno sozinho conta)',
    b.net_profit = a.net_profit and c.net_profit = a.net_profit and b.hbr_cost = 0 and c.hbr_cost = 0 and b1.hbr_cost = 62,
    'só cobrada ' || a.net_profit || '; cupom antes ' || b.net_profit || ' (só o cupom: hbr ' || b1.hbr_cost || '); cupom depois ' || c.net_profit);
exception when others then
  insert into _resultado values ('L6 cupom interno + a mesma compra cobrada do cliente: conta uma vez, em qualquer ordem (o interno sozinho conta)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
