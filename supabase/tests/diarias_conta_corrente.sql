-- Prova: diária idempotente, valor gravado no dia, rateio entre OS, apagar/desfazer, conta
-- corrente coerente, bolso do sócio entrando no que o freelancer recebeu, folha barrando diarista
-- e nenhum valor do módulo para quem não é admin/financeiro
-- (migration 20260928190000_diarias_conta_corrente).
--
-- ═══ COMO RODAR ═══
--
--   supabase db query --linked -f supabase/tests/diarias_conta_corrente.sql --output json
--
-- Seguro em produção: a transação inteira termina em ROLLBACK. Usa o primeiro freelancer com
-- perfil de diária e um dia sem lançamento dentro da vigência dele.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_dono uuid;
  v_fav uuid;
  v_perfil record;
  v_socio uuid;
  v_dia date;
  v_dia2 date;
  v_os uuid[];
  r jsonb;
  c jsonb;
  v_n integer;
  v_num numeric;
  v_txt text;
  v_tec uuid;
  v_visto integer;
  v_barrado boolean;
begin
  select id into v_dono from public.app_users where role = 'admin' and active order by created_at limit 1;
  select wp.* into v_perfil from public.work_profiles wp
   where wp.modo_pagamento = 'diaria' and wp.payee_id is not null and wp.vigencia_fim is null
   order by wp.vigencia_inicio limit 1;
  v_fav := v_perfil.payee_id;
  if v_dono is null or v_fav is null then
    insert into _resultado values ('setup', false, 'sem admin ativo ou sem freelancer com diária');
    return;
  end if;
  -- Dentro da vigência E da conta corrente (antes do início dela, o dia não entra no saldo).
  select d::date into v_dia from generate_series(
           greatest(v_perfil.vigencia_inicio, coalesce((select conta_corrente_desde from public.payees where id = v_fav), v_perfil.vigencia_inicio)),
           public._hoje_brt(), interval '1 day') d
   where not exists (select 1 from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
                      where wp.payee_id = v_fav and ws.data = d::date and ws.fracao is not null)
   order by d limit 1;
  select d::date into v_dia2 from generate_series(v_dia + 1, public._hoje_brt(), interval '1 day') d
   where not exists (select 1 from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
                      where wp.payee_id = v_fav and ws.data = d::date and ws.fracao is not null)
   order by d limit 1;
  if v_dia is null or v_dia2 is null then
    insert into _resultado values ('setup', false, 'sem dois dias livres na vigência do perfil');
    return;
  end if;
  update public.payees set conta_corrente_desde = coalesce(conta_corrente_desde, v_perfil.vigencia_inicio) where id = v_fav;

  -- T1. Dia novo: cria com a diária do perfil.
  r := public.registrar_diaria(v_fav, v_dia, 'inteiro', null, 'teste automático', null, null, null, 'painel', v_dono);
  insert into _resultado values ('T1 cria', r ->> 'acao' = 'criado' and (r ->> 'valor_dia')::numeric = v_perfil.valor_diaria, r ->> 'message');

  -- T2. A mesma frase de novo não duplica.
  r := public.registrar_diaria(v_fav, v_dia, 'inteiro', null, null, null, null, null, 'agente', v_dono);
  select count(*) into v_n from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_fav and ws.data = v_dia;
  insert into _resultado values ('T2 idempotente', r ->> 'acao' = 'sem_mudanca' and v_n = 1, r ->> 'acao' || ', ' || v_n || ' linha(s)');

  -- T3. Meio período atualiza o mesmo dia e conta o que era antes.
  r := public.registrar_diaria(v_fav, v_dia, 'meio', null, null, null, null, null, 'agente', v_dono);
  insert into _resultado values ('T3 meio', r ->> 'acao' = 'atualizado' and (r ->> 'valor_dia')::numeric = round(v_perfil.valor_diaria * 0.5, 2)
                                  and r -> 'antes' ->> 'jornada' = 'inteiro', r ->> 'message');

  -- T4. "Faltou" grava a ausência, com valor zero — não apaga.
  r := public.registrar_diaria(v_fav, v_dia, 'faltou', null, null, null, null, null, 'agente', v_dono);
  select count(*) into v_n from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_fav and ws.data = v_dia and ws.tipo = 'falta' and ws.fracao = 0;
  insert into _resultado values ('T4 faltou', (r ->> 'valor_dia')::numeric = 0 and v_n = 1, r ->> 'message');

  -- T5. Rateio: duas OS no dia, e depois nenhuma.
  select array_agg(id) into v_os from (select id from public.service_orders order by created_at desc limit 2) x;
  r := public.registrar_diaria(v_fav, v_dia, 'inteiro', v_os, null, null, null, null, 'painel', v_dono);
  select count(*) into v_n from public.work_shift_os where shift_id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('T5 duas OS', v_n = 2 and jsonb_array_length(r -> 'os') = 2, r ->> 'message');
  r := public.registrar_diaria(v_fav, v_dia, 'inteiro', '{}'::uuid[], null, null, null, null, 'painel', v_dono);
  select count(*) into v_n from public.work_shift_os where shift_id = (r ->> 'diaria_id')::uuid;
  insert into _resultado values ('T5 tira OS', v_n = 0, v_n || ' OS');

  -- T6. Mudar a diária do cadastro não reescreve o dia já lançado; o dia novo pega a nova.
  update public.work_profiles set valor_diaria = valor_diaria + 1000 where id = v_perfil.id;
  r := public.registrar_diaria(v_fav, v_dia, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  v_num := (r ->> 'valor_diaria')::numeric;
  r := public.registrar_diaria(v_fav, v_dia2, 'inteiro', null, null, null, null, null, 'painel', v_dono);
  insert into _resultado values ('T6 valor gravado', v_num = v_perfil.valor_diaria and (r ->> 'valor_diaria')::numeric = v_perfil.valor_diaria + 1000,
                                 'antigo ' || v_num || ', novo ' || (r ->> 'valor_diaria'));
  update public.work_profiles set valor_diaria = v_perfil.valor_diaria where id = v_perfil.id;

  -- T7. Apagar devolve tudo, e registrar de novo com o que voltou reconstrói o dia (Desfazer).
  r := public.registrar_diaria(v_fav, v_dia, 'meio', v_os, 'obs de teste', 12.5, 2, null, 'painel', v_dono);
  -- O que o dia é (não a frase: depois do Desfazer ela diz "registrado", não "atualizado").
  v_txt := concat_ws('|', r ->> 'jornada', r ->> 'valor_diaria', r ->> 'valor_dia', r -> 'os');
  c := public.apagar_diaria((r ->> 'diaria_id')::uuid, v_dono) -> 'apagado';
  select count(*) into v_n from public.work_shifts ws join public.work_profiles wp on wp.id = ws.work_profile_id
   where wp.payee_id = v_fav and ws.data = v_dia;
  r := public.registrar_diaria((c ->> 'favorecido_id')::uuid, (c ->> 'data')::date, c ->> 'jornada',
         array(select jsonb_array_elements_text(c -> 'os_ids'))::uuid[], c ->> 'observacao',
         (c ->> 'extras')::numeric, (c ->> 'descontos')::numeric, (c ->> 'valor_diaria')::numeric, 'painel', v_dono);
  insert into _resultado values ('T7 apagar e desfazer',
    v_n = 0 and concat_ws('|', r ->> 'jornada', r ->> 'valor_diaria', r ->> 'valor_dia', r -> 'os') = v_txt
    and (select observacao from public.work_shifts where id = (r ->> 'diaria_id')::uuid) = 'obs de teste',
    r ->> 'message');

  -- T8. Dia no futuro é recusado.
  begin
    perform public.registrar_diaria(v_fav, public._hoje_brt() + 1, 'inteiro', null, null, null, null, null, 'painel', v_dono);
    insert into _resultado values ('T8 futuro', false, 'aceitou data no futuro');
  exception when others then
    insert into _resultado values ('T8 futuro', true, left(sqlerrm, 100));
  end;

  -- T9. Bolso do sócio: o Pix pago por um sócio a ele entra no que ele recebeu.
  select id into v_socio from public.payees where kind = 'socio' and active order by name limit 1;
  if v_socio is null then
    insert into _resultado values ('T9 bolso do sócio', true, 'sem sócio cadastrado: pulado');
  else
    r := public.lancar_no_caixa('saida', 77.77, 'teste bolso do sócio', v_dia, null, null, v_fav, null, null, 'socio', v_socio, v_dono);
    select count(*) into v_n from public.payables where id = (r ->> 'lancamento_id')::uuid and beneficiario_id = v_fav and payee_id = v_socio;
    c := public.conta_corrente_freelancer(v_fav, v_dia, v_dia, v_dono);
    insert into _resultado values ('T9 bolso do sócio', v_n = 1 and (c ->> 'pago')::numeric >= 77.77
                                   and exists (select 1 from jsonb_array_elements(c -> 'linhas') l where l ->> 'conta' like 'Bolso de %'),
                                   'pago no dia: ' || (c ->> 'pago'));
  end if;

  -- T10. Conta corrente coerente: saldo final = anterior + trabalhado − pago = saldo da última linha.
  c := public.conta_corrente_freelancer(v_fav, null, null, v_dono);
  v_num := (c ->> 'saldo_anterior')::numeric + (c ->> 'trabalhado')::numeric - (c ->> 'pago')::numeric;
  insert into _resultado values ('T10 saldo coerente',
    abs(v_num - (c ->> 'saldo_final')::numeric) < 0.01
    and abs((c -> 'linhas' -> (jsonb_array_length(c -> 'linhas') - 1) ->> 'saldo')::numeric - (c ->> 'saldo_final')::numeric) < 0.01,
    'saldo ' || (c ->> 'saldo_final') || ' (' || (c ->> 'estado') || ')');

  -- T11. Resumo e extrato dizem o mesmo saldo.
  r := public.resumo_freelancers(null, null, v_dono);
  select (x ->> 'saldo_final')::numeric into v_num from jsonb_array_elements(r -> 'pessoas') x where (x ->> 'id')::uuid = v_fav;
  insert into _resultado values ('T11 resumo = extrato', v_num = (c ->> 'saldo_final')::numeric, 'resumo ' || v_num);

  -- T12. A folha recusa diarista com conta corrente (a despesa sairia em dobro).
  begin
    insert into public.payroll_periods (de, ate, descricao) values (v_dia, v_dia, 'teste') returning id into v_tec;
    insert into public.payroll_lines (payroll_period_id, work_profile_id) values (v_tec, v_perfil.id);
    insert into _resultado values ('T12 folha barra diarista', false, 'a folha aceitou o diarista');
  exception when check_violation then
    insert into _resultado values ('T12 folha barra diarista', true, left(sqlerrm, 100));
  end;

  -- T13. Quem não é admin/financeiro não vê valor nenhum — nem o próprio perfil (D10).
  select id into v_tec from public.app_users where role = 'technician' order by created_at limit 1;
  if v_tec is null then
    insert into _resultado values ('T13 técnico', true, 'sem técnico cadastrado: pulado');
  else
    insert into public.work_profiles (app_user_id, tipo_vinculo, modo_pagamento, valor_hora)
    values (v_tec, 'clt', 'hora', 10);
    perform set_config('request.jwt.claims', json_build_object('sub', v_tec, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_tec::text, true);
    execute 'set local role authenticated';
    select count(*) into v_visto from public.work_profiles;
    select count(*) into v_n from public.work_shifts;
    v_barrado := false;
    begin
      perform public.conta_corrente_freelancer(v_fav, null, null, null);
    exception when insufficient_privilege then
      v_barrado := true;
    end;
    execute 'reset role';
    insert into _resultado values ('T13 técnico', v_visto = 0 and v_n = 0 and v_barrado,
                                   'perfis ' || v_visto || ', dias ' || v_n || ', extrato barrado ' || v_barrado);
  end if;

  -- T14. anon não executa nada do módulo.
  insert into _resultado values ('T14 anon',
    not has_function_privilege('anon', 'public.registrar_diaria(uuid, date, text, uuid[], text, numeric, numeric, numeric, text, uuid)', 'execute')
    and not has_function_privilege('anon', 'public.apagar_diaria(uuid, uuid)', 'execute')
    -- 06/10/2026: as duas ganharam p_atalho (migration 20261006200000).
    and not has_function_privilege('anon', 'public.conta_corrente_freelancer(uuid, date, date, uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.resumo_freelancers(date, date, uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public._conta_corrente_linhas(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public._conta_corrente_linhas(uuid)', 'execute')
    and not has_table_privilege('anon', 'public.work_shift_os', 'select'),
    'sem execução para anon');
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
