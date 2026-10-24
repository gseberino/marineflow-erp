-- Paridade TS × banco das cobranças da conclusão, Agenda de Produção Fase 3 (pacote P2; migration 20261026100100).
-- bancada: depende de 20261026100100
--
-- scripts/bancada-agenda/recebiveis-casos.json tem os casos fixos (≥ 20) e os 21 do replay das conclusões reais, cada um com o
-- esperado que o TS de hoje dá (recebiveisDaConclusao, src/lib/completion-receivables.ts; o vitest
-- completion-receivables.paridade.test.ts confere o TS contra o MESMO esperado). Aqui, para cada caso, a OS é montada no
-- banco (os totais, o preset com as parcelas, as personalizadas e os recebíveis que ela já tem) e _os_recebiveis_da_conclusao
-- tem de devolver o mesmo motivo e as mesmas linhas, na mesma ordem: descrição, valor, emissão, vencimento e
-- due_on_completion. Nada é gravado de cobrança: a função não escreve.
--
--   P1  o JSON chegou e tem os casos (≥ 20 fixos e os 21 do replay)
--   P2  cada caso: o banco = o TS, campo a campo
--   P3  a função não escreveu nada (nenhum recebível novo)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100100
--   Fora da bancada não há o JSON (agenda_teste.recebiveis_casos): PULADO. Em produção, o replay só de leitura é o
--   supabase/tests/agenda_fase3_pos_deploy.sql (P7).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

do $p$
declare
  v_doc    jsonb := nullif(current_setting('agenda_teste.recebiveis_casos', true), '')::jsonb;
  c        jsonb;
  e        jsonb;
  r        jsonb;
  i        int := 0;
  v_os     uuid;
  v_preset uuid;
  v_ok     boolean;
  v_det    text;
  v_rec    bigint;
  c_cli    constant uuid := 'c3300000-0000-4000-8000-000000000001';
  c_barco  constant uuid := 'c3310000-0000-4000-8000-000000000001';
begin
  if v_doc is null then
    insert into _resultado values ('P1 os casos de recebiveis-casos.json', true,
      'PULADO: sem agenda_teste.recebiveis_casos (rode pela bancada)');
    return;
  end if;
  insert into _resultado values ('P1 o JSON tem pelo menos 20 casos fixos e os 21 do replay, todos com o esperado',
    (select count(*) from jsonb_array_elements(v_doc -> 'casos') x where not coalesce((x ->> 'replay')::boolean, false)) >= 20
    and (select count(*) from jsonb_array_elements(v_doc -> 'casos') x where (x ->> 'replay')::boolean) = 21
    and not exists (select 1 from jsonb_array_elements(v_doc -> 'casos') x where jsonb_typeof(x -> 'esperado') <> 'object'),
    jsonb_array_length(v_doc -> 'casos')::text);

  insert into public.clients (id, type, name) values (c_cli, 'individual', 'Cliente TESTE P2 casos');
  insert into public.vessels (id, client_id, name) values (c_barco, c_cli, 'Barco TESTE P2 casos');

  for c in select x from jsonb_array_elements(v_doc -> 'casos') with ordinality t(x, o) order by o loop
    i := i + 1;
    v_os := ('f3300000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
    v_preset := null;
    -- O preset existe quando o caso tem a chave (mesmo que as parcelas dele não sejam lista: aí valem as personalizadas).
    if c ? 'preset_installments' then
      v_preset := ('d3300000-0000-4000-8000-' || lpad(i::text, 12, '0'))::uuid;
      insert into public.payment_condition_presets (id, label, installments)
      values (v_preset, 'TESTE P2 caso ' || i, c -> 'preset_installments');
    end if;
    insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status,
                                       payment_condition_preset_id, custom_payment_installments, grand_total,
                                       labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total,
                                       subcontract_cost_total, is_travel_billable, discount_amount, tax_amount)
    values (v_os, c_cli, c_barco, c -> 'os' ->> 'service_order_number', 'in_progress', 'approved', v_preset,
            case when jsonb_typeof(c -> 'custom_payment_installments') in ('null') or c -> 'custom_payment_installments' is null
                 then null else c -> 'custom_payment_installments' end,
            (c -> 'os' ->> 'grand_total')::numeric, (c -> 'os' ->> 'labor_cost_total')::numeric,
            (c -> 'os' ->> 'parts_cost_total')::numeric, (c -> 'os' ->> 'operational_cost_total')::numeric,
            (c -> 'os' ->> 'travel_cost_total')::numeric, (c -> 'os' ->> 'subcontract_cost_total')::numeric,
            coalesce((c -> 'os' ->> 'is_travel_billable')::boolean, true),
            (c -> 'os' ->> 'discount_amount')::numeric, (c -> 'os' ->> 'tax_amount')::numeric);
    -- Os recebíveis que a OS já tem (só o status e o valor importam para a regra).
    insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                    balance_amount, is_deposit)
    select c_cli, v_os, 'TESTE P2 existente', (c ->> 'data')::date, (c ->> 'data')::date,
           coalesce((x ->> 'amount')::numeric, 100), x ->> 'status',
           case when x ->> 'status' = 'paid' then coalesce((x ->> 'amount')::numeric, 100) else 0 end,
           case when x ->> 'status' = 'paid' then 0 else coalesce((x ->> 'amount')::numeric, 100) end,
           coalesce((x ->> 'is_deposit')::boolean, false)
      from jsonb_array_elements(coalesce(c -> 'existentes', '[]'::jsonb)) x;

    select count(*) into v_rec from public.receivables where service_order_id = v_os;
    r := public._os_recebiveis_da_conclusao(v_os, (c ->> 'data')::date);
    e := c -> 'esperado';
    v_ok := r ->> 'motivo' = e ->> 'motivo'
            and jsonb_array_length(r -> 'linhas') = jsonb_array_length(e -> 'linhas')
            and not exists (
              select 1
                from jsonb_array_elements(e -> 'linhas') with ordinality le(l, o)
                left join jsonb_array_elements(r -> 'linhas') with ordinality lb(l, o) on lb.o = le.o
               where lb.l is null
                  or lb.l ->> 'description' is distinct from le.l ->> 'description'
                  or (lb.l ->> 'amount')::numeric is distinct from (le.l ->> 'amount')::numeric
                  or (lb.l ->> 'issue_date')::date is distinct from (le.l ->> 'issue_date')::date
                  or (lb.l ->> 'due_date')::date is distinct from (le.l ->> 'due_date')::date
                  or (lb.l ->> 'due_on_completion')::boolean is distinct from (le.l ->> 'due_on_completion')::boolean)
            -- e a função não escreveu nada
            and (select count(*) from public.receivables where service_order_id = v_os) = v_rec;
    v_det := case when v_ok then null
                  else format('banco %s %s | TS %s %s', r ->> 'motivo', r -> 'linhas', e ->> 'motivo', e -> 'linhas') end;
    insert into _resultado values (format('P2 %s', c ->> 'nome'), v_ok, v_det);
  end loop;

  insert into _resultado values ('P3 nenhum recebível nasceu dos casos (a função não escreve)',
    (select count(*) from public.receivables r join public.service_orders so on so.id = r.service_order_id
      where so.client_id = c_cli and r.description <> 'TESTE P2 existente') = 0, null);
end
$p$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
