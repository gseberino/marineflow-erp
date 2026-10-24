-- Replay das conclusões reais (o aceite do D7), Agenda de Produção Fase 3 (pacote P2; migration 20261026100100).
-- bancada: depende de 20261026100100
--
-- As 21 OS concluídas ou faturadas de produção até 24/10/2026, só números (scripts/bancada-agenda/fixture-replay-conclusoes.sql,
-- gerada por gerar-replay-conclusoes.mjs a partir do SELECT sql/i06_replay_export.sql). Para cada uma, a OS é montada na
-- bancada no estado de ANTES da saída — os recebíveis criados mais de 5 minutos antes dela, mais os sinais criados até ela
-- (o sinal do mesmo minuto existia quando a tela conferiu) — e _os_recebiveis_da_conclusao roda no dia da saída em Brasília.
-- O gabarito é o que a tela gerou de verdade: os recebíveis que não são sinal criados a até 5 minutos da saída.
--
--   Classe A  igual à tela, campo a campo (descrição, valor, emissão, vencimento, due_on_completion)       OS-00038
--   Classe B  título único da versão antiga (antes de 23/09): mesmo valor, emissão e vencimento; a descrição é a de hoje
--             (só o número)                                                                                OS-00044…48
--   Classe C  o gêmeo que a correção de 24/09 cancelou: o sinal existia, a porta diz ja_tem                   OS-00073, 75, 84
--   Classe D  já tinha recebível antes da saída: ja_tem                                         OS-00034, 41, ORÇ-00070, 60…
--   Classe E  total zero (a tela antiga gravou um título de R$ 0,00): total_zero                             OS-00016
--   Classe F  concluída fora da tela, sem nada na hora: o que o TS de hoje daria (o esperado do JSON)         OS-00001, 105
--
--   R0  a fixture e o JSON chegaram
--   R1  cada OS cai na classe dela e a porta dá o que a classe espera
--   R2  a contagem de 24/10: A 1 · B 5 · C 3 · D 9 · E 1 · F 2 (21)
--   R3  cada OS: o banco = o TS (o esperado de recebiveis-casos.json, que o vitest confere contra o TS)
--   R4  cada OS: o estado de antes da saída montado aqui = o do JSON (as duas pontas da mesma regra)
--   R5  toda OS concluída depois de 24/10 (quando a fixture for regerada) cai em A ou D. Divergência = achar quem errou
--       antes de mudar número.
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100100
--   Fora da bancada não há a fixture: PULADO. Em produção, a mesma comparação só de leitura é a do
--   supabase/tests/agenda_fase3_pos_deploy.sql (P7).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create temp table _replay_resultado (
  numero text primary key, saida date, classe text, motivo text, linhas jsonb, tela jsonb, antes jsonb, esperado jsonb,
  existentes_json jsonb
) on commit drop;

do $r$
declare
  v_doc    jsonb := nullif(current_setting('agenda_teste.recebiveis_casos', true), '')::jsonb;
  o        record;
  v_os     uuid;
  v_preset uuid;
  v_saida  date;
  v_antes  jsonb;
  v_tela   jsonb;
  v_classe text;
  r        jsonb;
  c_cli    constant uuid := 'c3400000-0000-4000-8000-000000000001';
  c_barco  constant uuid := 'c3410000-0000-4000-8000-000000000001';
begin
  if coalesce(current_setting('agenda_teste.replay_conclusoes', true), '') = '' or v_doc is null then
    insert into _resultado values ('R0 a fixture do replay e o JSON dos casos', true,
      'PULADO: sem agenda_teste.replay_conclusoes / recebiveis_casos (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.replay_conclusoes');

  insert into public.clients (id, type, name) values (c_cli, 'individual', 'Cliente TESTE P2 replay');
  insert into public.vessels (id, client_id, name) values (c_barco, c_cli, 'Barco TESTE P2 replay');

  for o in select * from _replay_os order by check_out_at, numero loop
    v_os := md5('replay:' || o.numero)::uuid;
    v_preset := null;
    if o.tem_preset then
      v_preset := md5('replay-preset:' || o.numero)::uuid;
      insert into public.payment_condition_presets (id, label, installments)
      values (v_preset, 'TESTE P2 replay ' || o.numero, o.preset_installments);
    end if;
    insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status,
                                       payment_condition_preset_id, custom_payment_installments, grand_total,
                                       labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total,
                                       subcontract_cost_total, is_travel_billable, discount_amount, tax_amount,
                                       created_at, converted_to_os_at)
    values (v_os, c_cli, c_barco, o.numero, 'in_progress', 'approved', v_preset, o.custom_payment_installments, o.grand_total,
            o.labor_cost_total, o.parts_cost_total, o.operational_cost_total, o.travel_cost_total, o.subcontract_cost_total,
            coalesce(o.is_travel_billable, true), o.discount_amount, o.tax_amount, o.created_at, o.converted_to_os_at);

    -- O estado de antes da saída (a mesma regra do gerar-replay-conclusoes.mjs).
    insert into public.receivables (client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                    balance_amount, is_deposit, due_on_completion, created_at)
    select c_cli, v_os, 'TESTE P2 replay', x.issue_date, x.due_date, x.amount, x.status, x.paid_amount, x.balance_amount,
           x.is_deposit, x.due_on_completion, x.created_at
      from _replay_rec x
     where x.numero = o.numero
       and (x.created_at < o.check_out_at - interval '5 minutes' or (x.is_deposit and x.created_at <= o.check_out_at))
     order by x.n;
    select coalesce(jsonb_agg(jsonb_build_object('status', x.status, 'is_deposit', x.is_deposit, 'amount', x.amount)
                              order by x.n), '[]'::jsonb)
      into v_antes
      from _replay_rec x
     where x.numero = o.numero
       and (x.created_at < o.check_out_at - interval '5 minutes' or (x.is_deposit and x.created_at <= o.check_out_at));
    -- O gabarito: o que a tela gerou na saída (não sinal, a até 5 minutos dela).
    select jsonb_agg(jsonb_build_object('amount', x.amount, 'status', x.status, 'issue_date', x.issue_date,
                                        'due_date', x.due_date, 'due_on_completion', x.due_on_completion,
                                        'created_at', x.created_at) order by x.created_at, x.n)
      into v_tela
      from _replay_rec x
     where x.numero = o.numero and not x.is_deposit
       and abs(extract(epoch from (x.created_at - o.check_out_at))) <= 300;

    v_saida := (o.check_out_at at time zone 'America/Sao_Paulo')::date;
    r := public._os_recebiveis_da_conclusao(v_os, v_saida);
    v_classe := case
      when exists (select 1 from jsonb_array_elements(v_antes) a where a ->> 'status' <> 'cancelled')
        then case when exists (select 1 from jsonb_array_elements(coalesce(v_tela, '[]')) t where t ->> 'status' = 'cancelled')
                  then 'C' else 'D' end
      when v_tela is null then 'F'
      when (select bool_and((t ->> 'amount')::numeric = 0) from jsonb_array_elements(v_tela) t) then 'E'
      when (select min((t ->> 'created_at')::timestamptz) from jsonb_array_elements(v_tela) t) < timestamptz '2026-09-23 00:00-03'
        then 'B'
      else 'A' end;
    insert into _replay_resultado
    values (o.numero, v_saida, v_classe, r ->> 'motivo', r -> 'linhas', v_tela, v_antes,
            (select x -> 'esperado' from jsonb_array_elements(v_doc -> 'casos') x
              where (x ->> 'replay')::boolean and x -> 'os' ->> 'service_order_number' = o.numero),
            (select x -> 'existentes' from jsonb_array_elements(v_doc -> 'casos') x
              where (x ->> 'replay')::boolean and x -> 'os' ->> 'service_order_number' = o.numero));
  end loop;
end
$r$;

-- R0
insert into _resultado
select 'R0 a fixture tem as 21 OS concluídas até 24/10 e o JSON tem o esperado de cada uma',
       count(*) filter (where x.saida <= date '2026-10-24') = 21 and bool_and(x.esperado is not null),
       format('%s OS (%s até 24/10); sem esperado: %s', count(*), count(*) filter (where x.saida <= date '2026-10-24'),
              coalesce(string_agg(x.numero, ', ') filter (where x.esperado is null), 'nenhuma'))
  from _replay_resultado x
having count(*) > 0;

-- R1: a classe e o que ela espera da porta.
insert into _resultado
select format('R1 %s (%s) classe %s', x.numero, to_char(x.saida, 'DD/MM'), x.classe),
       case x.classe
         when 'A' then x.motivo in ('parcelas', 'titulo_unico')
                       and jsonb_array_length(x.linhas) = jsonb_array_length(x.tela)
                       and not exists (
                         select 1
                           from jsonb_array_elements(x.tela) with ordinality t(l, o)
                           left join jsonb_array_elements(x.linhas) with ordinality b(l, o) on b.o = t.o
                          where b.l is null
                             or (b.l ->> 'amount')::numeric <> (t.l ->> 'amount')::numeric
                             or (b.l ->> 'issue_date')::date <> (t.l ->> 'issue_date')::date
                             or (b.l ->> 'due_date')::date <> (t.l ->> 'due_date')::date
                             or (b.l ->> 'due_on_completion')::boolean <> (t.l ->> 'due_on_completion')::boolean)
         when 'B' then x.motivo = 'titulo_unico' and jsonb_array_length(x.tela) = 1
                       and x.linhas -> 0 ->> 'description' = x.numero
                       and (x.linhas -> 0 ->> 'amount')::numeric = (x.tela -> 0 ->> 'amount')::numeric
                       and (x.linhas -> 0 ->> 'issue_date')::date = (x.tela -> 0 ->> 'issue_date')::date
                       and (x.linhas -> 0 ->> 'due_date')::date = (x.tela -> 0 ->> 'due_date')::date
         when 'C' then x.motivo = 'ja_tem'
         when 'D' then x.motivo = 'ja_tem'
         when 'E' then x.motivo = 'total_zero'
         when 'F' then x.motivo = x.esperado ->> 'motivo'
       end,
       format('porta %s %s | tela %s', x.motivo, coalesce(x.linhas::text, '[]'), coalesce(x.tela::text, '—'))
  from _replay_resultado x;

-- A descrição da classe A também é a da tela (a regra de hoje é a que a tela usou em 13/10).
insert into _resultado
select format('R1 %s classe A: a descrição é a da tela ("À vista — OS-00038")', x.numero),
       x.linhas -> 0 ->> 'description' = 'À vista — ' || x.numero, x.linhas::text
  from _replay_resultado x where x.classe = 'A' and x.numero = 'OS-00038';

-- R2
insert into _resultado
select 'R2 as classes de 24/10: A 1 · B 5 · C 3 · D 9 · E 1 · F 2',
       string_agg(c.classe || ' ' || coalesce(n.qtd, 0), ' · ' order by c.classe) = 'A 1 · B 5 · C 3 · D 9 · E 1 · F 2',
       string_agg(c.classe || ' ' || coalesce(n.qtd, 0) || coalesce(' (' || n.quais || ')', ''), ' · ' order by c.classe)
  from (values ('A'), ('B'), ('C'), ('D'), ('E'), ('F')) c(classe)
  left join (select x.classe, count(*) as qtd, string_agg(x.numero, ', ' order by x.numero) as quais
               from _replay_resultado x where x.saida <= date '2026-10-24' group by x.classe) n on n.classe = c.classe
having exists (select 1 from _replay_resultado);

-- R3: o banco = o TS, linha a linha.
insert into _resultado
select format('R3 %s: o banco dá o mesmo que o TS de hoje (recebiveis-casos.json)', x.numero),
       x.motivo = x.esperado ->> 'motivo'
       and jsonb_array_length(coalesce(x.linhas, '[]')) = jsonb_array_length(x.esperado -> 'linhas')
       and not exists (
         select 1
           from jsonb_array_elements(x.esperado -> 'linhas') with ordinality e(l, o)
           left join jsonb_array_elements(x.linhas) with ordinality b(l, o) on b.o = e.o
          where b.l is null
             or b.l ->> 'description' is distinct from e.l ->> 'description'
             or (b.l ->> 'amount')::numeric is distinct from (e.l ->> 'amount')::numeric
             or (b.l ->> 'issue_date')::date is distinct from (e.l ->> 'issue_date')::date
             or (b.l ->> 'due_date')::date is distinct from (e.l ->> 'due_date')::date
             or (b.l ->> 'due_on_completion')::boolean is distinct from (e.l ->> 'due_on_completion')::boolean),
       format('banco %s %s | TS %s', x.motivo, coalesce(x.linhas::text, '[]'), x.esperado::text)
  from _replay_resultado x;

-- R4: as duas pontas da regra do "antes da saída".
insert into _resultado
select format('R4 %s: o estado de antes da saída é o mesmo do JSON', x.numero),
       (select coalesce(jsonb_agg(a order by o), '[]') from jsonb_array_elements(x.antes) with ordinality t(a, o))
       = (select coalesce(jsonb_agg(jsonb_build_object('status', e ->> 'status', 'is_deposit', (e ->> 'is_deposit')::boolean,
                                                      'amount', (e ->> 'amount')::numeric) order by o), '[]')
            from jsonb_array_elements(x.existentes_json) with ordinality t(e, o)),
       format('aqui %s | JSON %s', x.antes, x.existentes_json)
  from _replay_resultado x;

-- R5
insert into _resultado
select 'R5 depois de 24/10, toda conclusão cai em A ou D',
       coalesce(bool_and(x.classe in ('A', 'D')), true),
       coalesce(string_agg(x.numero || ' ' || x.classe, ', '), 'nenhuma depois de 24/10 nesta fixture')
  from _replay_resultado x where x.saida > date '2026-10-24'
having exists (select 1 from _replay_resultado);

select teste, ok, detalhe from _resultado order by teste;

rollback;
