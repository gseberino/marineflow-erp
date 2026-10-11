-- Prova: o Lucro por OS desconta o custo da HBR (migration 20261011205000, OK nomeado P2).
--
--   L1 uma despesa não faturável de 10 tira exatamente 10 do net_profit e aparece em hbr_cost
--   L2 a despesa "cobrar à parte" (não faturável, cobrar_a_parte) não entra no custo da HBR
--   L3 a despesa faturável continua como antes (entra pelo operational_cost_total, não pelo hbr_cost)
--   L4 anon sem select na view; authenticated com; hbr_cost é a última coluna e as de antes ficam
--      na mesma ordem
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado P3 da spec da F2; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/lucro_por_os_custo_hbr.sql --output json
--
-- Seguro em produção: cria a própria OS (cliente e barco de mentira, número OS-9xxxxx livre), lança
-- as despesas direto na tabela e termina em ROLLBACK. Sem id nem data fixa.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_cli uuid;
  v_ves uuid;
  v_os uuid;
  v_num integer := 900000 + floor(random() * 99000)::integer;
  v0 record;
  v1 record;
  v2 record;
  v3 record;
begin
  while exists (select 1 from public.service_orders where service_order_number = 'OS-' || v_num) loop
    v_num := v_num + 1;
  end loop;
  insert into public.clients (type, name) values ('individual', 'Cliente Teste Lucro F2') returning id into v_cli;
  insert into public.vessels (client_id, name) values (v_cli, 'Barco Teste Lucro F2') returning id into v_ves;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, grand_total,
                                     operational_cost_total, labor_cost_total, travel_cost_total)
  values ('OS-' || v_num, v_cli, v_ves, 'completed', 1000, 0, 1000, 0)
  returning id into v_os;

  select net_profit, hbr_cost, operational_cost into v0 from public.vw_os_profitability where os_id = v_os;
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
  values (v_os, 'Outras despesas', 'custo da HBR de teste', 10, 'company', false);
  select net_profit, hbr_cost, operational_cost into v1 from public.vw_os_profitability where os_id = v_os;
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client, cobrar_a_parte)
  values (v_os, 'Outras despesas', 'cobrar à parte de teste', 7, 'company', false, true);
  select net_profit, hbr_cost, operational_cost into v2 from public.vw_os_profitability where os_id = v_os;
  -- faturável: o lucro vê pelo operational_cost_total (o que a tela grava pela rota); aqui só a linha
  insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
  values (v_os, 'Outras despesas', 'faturável de teste', 5, 'company', true);
  select net_profit, hbr_cost, operational_cost into v3 from public.vw_os_profitability where os_id = v_os;

  insert into _resultado values ('L1 despesa não faturável de 10 tira 10 do lucro e entra no hbr_cost',
    v0.net_profit - v1.net_profit = 10 and v0.hbr_cost = 0 and v1.hbr_cost = 10,
    'lucro ' || v0.net_profit || ' → ' || v1.net_profit || '; hbr_cost ' || v0.hbr_cost || ' → ' || v1.hbr_cost);
  insert into _resultado values ('L2 "cobrar à parte" não é custo da HBR',
    v2.net_profit = v1.net_profit and v2.hbr_cost = 10,
    'lucro ' || v1.net_profit || ' → ' || v2.net_profit || '; hbr_cost ' || v2.hbr_cost);
  insert into _resultado values ('L3 despesa faturável não entra no hbr_cost',
    v3.hbr_cost = 10 and v3.net_profit = v2.net_profit and v3.operational_cost = v2.operational_cost,
    'hbr_cost ' || v3.hbr_cost || '; lucro ' || v3.net_profit);
exception when others then
  insert into _resultado values ('L1-L3 Lucro por OS com custo da HBR', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
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

select teste, ok, detalhe from _resultado order by teste;

rollback;
