-- Prova: a semana inteira numa gravação só (migration 20261027200000_diarias_em_lote).
--
--   supabase db query --linked -f supabase/tests/diarias_em_lote.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um freelancer de teste.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_dono uuid;
  v_hoje date := public._hoje_brt();
  v_fav uuid;
  r jsonb;
  v_n integer;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  r := public.cadastrar_freelancer('Teste Lote ' || lpad((floor(random() * 1000000))::int::text, 6, '0'),
                                   100, v_hoje - 20, null, null, null, null, null, false, v_dono);
  v_fav := (r ->> 'favorecido_id')::uuid;

  -- L1. Dias de jornadas diferentes, com extra e observação, numa chamada só.
  r := public.registrar_diarias_em_lote(v_fav, jsonb_build_array(
         jsonb_build_object('data', v_hoje - 10, 'jornada', 'inteiro'),
         jsonb_build_object('data', v_hoje - 9, 'jornada', 'meio'),
         jsonb_build_object('data', v_hoje - 8, 'jornada', 'inteiro', 'extras', 20, 'observacao', 'almoço')),
       'agente', v_dono);
  select count(*) into v_n from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_fav;
  insert into _resultado values ('L1 lote grava todos',
    (r ->> 'quantos')::int = 3 and v_n = 3
      and (public.conta_corrente_freelancer(v_fav, null, null, v_dono) ->> 'saldo_final')::numeric = 270,
    r::text);

  -- L2. Um dia recusado derruba o lote inteiro (nada entra) e diz qual.
  begin
    perform public.registrar_diarias_em_lote(v_fav, jsonb_build_array(
              jsonb_build_object('data', v_hoje - 7, 'jornada', 'inteiro'),
              jsonb_build_object('data', v_hoje + 5, 'jornada', 'inteiro')), 'agente', v_dono);
    insert into _resultado values ('L2 dia recusado derruba o lote', false, 'gravou');
  exception when others then
    select count(*) into v_n from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
     where wp.payee_id = v_fav and ws.data = v_hoje - 7;
    insert into _resultado values ('L2 dia recusado derruba o lote', v_n = 0 and sqlerrm like 'Nada foi gravado: o dia % foi recusado%', sqlerrm);
  end;

  -- L3. O mesmo dia duas vezes e a lista vazia viram pergunta.
  begin
    perform public.registrar_diarias_em_lote(v_fav, jsonb_build_array(
              jsonb_build_object('data', v_hoje - 6, 'jornada', 'inteiro'),
              jsonb_build_object('data', v_hoje - 6, 'jornada', 'meio')), 'agente', v_dono);
    insert into _resultado values ('L3a dia repetido', false, 'gravou');
  exception when others then
    insert into _resultado values ('L3a dia repetido', sqlerrm like 'O mesmo dia aparece duas vezes%', sqlerrm);
  end;
  begin
    perform public.registrar_diarias_em_lote(v_fav, '[]'::jsonb, 'agente', v_dono);
    insert into _resultado values ('L3b lista vazia', false, 'gravou');
  exception when others then
    insert into _resultado values ('L3b lista vazia', sqlerrm like 'Nenhum dia%', sqlerrm);
  end;

  -- L4. Repetir um dia já lançado corrige (não duplica), como o registrar_diaria.
  r := public.registrar_diarias_em_lote(v_fav, jsonb_build_array(jsonb_build_object('data', v_hoje - 9, 'jornada', 'inteiro')), 'agente', v_dono);
  select count(*) into v_n from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_fav and ws.data = v_hoje - 9;
  insert into _resultado values ('L4 corrige sem duplicar', v_n = 1 and r -> 'dias' -> 0 ->> 'acao' = 'atualizado', r::text);

  -- L5. Quem pode.
  insert into _resultado values ('L5 permissoes',
    not has_function_privilege('anon', 'public.registrar_diarias_em_lote(uuid, jsonb, text, uuid)', 'execute')
      and has_function_privilege('authenticated', 'public.registrar_diarias_em_lote(uuid, jsonb, text, uuid)', 'execute'),
    null);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
