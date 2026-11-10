-- Prova do porquê gravado no motor, Fase 7g (pacote P2): as suposições e o degrau no item e na alocação, os 3 caminhos do gatilho, a zona e o degrau da ação, a
-- vigente que não muda o porquê, as cópias, o foco locais igual e o motor sem chamada nova em simulação (migration 20261112100100; spec-fase7g §5.2, §8.3
-- agenda_fase7g_porque.sql e o bloco R9: R9.4-1, R9.5-1 a 4 e 16, R9.8, R9.12-3, R9.12-10, R9.13).
-- bancada: depende de 20261112100100
--
-- O cenário real: o replay de 29/10 (a forma de produção: a OS sem linha em os_planejamento, a ação da vigia) com o Lenine (OS-00074) e o Vanderlei (OS-00069)
-- marcados pela estimativa, qui 29/10 16:52 (o cenário B de agenda_fase7a_compras.sql: os 5 modos do gestor ligados e sem o freio, a presença do dono de produção;
-- o motor grava e o agenda_aplicar publica).
--
--   P0  as portas e o catálogo: os 2 gatilhos BEFORE INSERT, na ordem pelo nome (o das alocações depois do critério e da fonte); o das ações definer, o das alocações
--       invoker; nenhuma das 3 novas com porta para anon nem authenticated; _agenda_suposicoes_da_os com porta para o service_role; search_path fixo
--   P1  a proposta gravada em sombra: o item criar ganha porque {suposicoes, degrau} (as suposições de cada OS, os códigos e o detalhe, byte a byte); as alocações
--       de turno com as suposições e o degrau do item, a abertura e o fechamento com [] e sem degrau; o que o agenda_aplicar grava na ação (a zona e o degrau); o
--       pedido do dono 3 semanas depois dá o degrau data no item e nas alocações; a reserva condicionada leva as suposições
--   P2  modo_porque desligado: nada novo (sem a chave, as colunas nulas); em sombra, tirada a chave porque e as colunas novas, a proposta, as alocações, as ações e
--       o texto do aplicar são os de desligado, byte a byte; a simulação (p_persistir false) é a mesma nos 3 modos, byte a byte
--   P3  o gatilho das alocações nas 3 entradas e no corte: (a) a substituição copia as suposições, sem degrau (o critério só com ligado); (b) o item (P1); (c) a
--       proposta do gestor: a escada (reparar, com o degrau) e o corte (reestimar, sem degrau) copiam da alocação mais nova da OS, nunca da própria proposta; o
--       degrau fora da lista não entra; a OS sem porquê guardado fica nula; o corte (sem proposta nem substituída) fica nulo; quem grava já disse, fica
--   P4  o gatilho das ações: a zona na travada, na firme e na livre (a âncora é a data, contada à parte), o degrau (pessoa, turno, data, tirou), a ação sem as
--       alocações (zona pelos ids, degrau nulo), a falha que não derruba a ação (registra), a ação não executada e o tipo fora da lista, desligado, e o service_role
--   P5  a vigente não muda o porquê (suposicoes, degrau, duracao_fonte); a proposta muda
--   P6  as cópias: tiradas os blocos -- FASE 7g, agenda_propor e _agenda_alocacoes_imutavel são as da origem, byte a byte; a migration só recria essas 2
--   P7  o foco locais e o bloco do local iguais com e sem o porque no item (os modos do local ligados, sem o freio)
--   P8  as suposições, código a código: cada uma entra só com o fato que a sustenta (a prontidão, os meios e o bloco montados; o que é lido do banco,
--       montado no banco), na ordem do §3.1-3, e a saída passa no CHECK
--   M1c _agenda_suposicoes_da_os trocada por uma que lança: a simulação roda sem erro, igual e sem registro (nunca a chama); a vigia roda sem erro; gravando, o
--       motor segue, o item fica sem porque, a alocação nula e o erro registrado (o controle que morde)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7g_porque.sql
--   Seguro em produção: termina em ROLLBACK. O que usa o replay, a fixture ou a migration como texto só roda na bancada (fora dela sai PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

create function pg_temp.os(p_num text) returns uuid language sql stable as $f$
  select id from public.service_orders where service_order_number = p_num
$f$;

-- p_sql como o papel p_papel, sem login: o resultado em texto, ou 'erro <estado>: <mensagem>'
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    reset role;
    return 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  return v;
end $f$;

-- Os itens sem o que muda de uma gravação para outra (os ids das alocações novas) e sem a chave porque.
create function pg_temp.limpo(p jsonb) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg((i - 'porque') || case when jsonb_typeof(i -> 'alocacoes') = 'array' then jsonb_build_object('alocacoes',
           (select coalesce(jsonb_agg(a - 'alocacao_id' order by o), '[]'::jsonb) from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, o)))
           else '{}'::jsonb end order by k), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p, '[]'::jsonb)) with ordinality t(i, k)
$f$;

-- As alocações de uma proposta, sem os ids e sem as colunas da 7g (o que tem de ser igual com e sem o porquê).
create function pg_temp.alocs(p_prop uuid) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s', a.service_order_id, a.payee_id, a.dia, a.turno, a.presenca, a.tipo, a.estado, a.origem,
                                    a.reserva_de, a.duracao_fonte, a.criterio, a.criterio_detalhe), ' ; ' order by a.service_order_id, a.dia, a.turno, a.presenca, a.payee_id), '')
    from public.agenda_alocacoes a where a.proposta_id = p_prop
$f$;

-- O cenário: o Lenine e o Vanderlei pelo motor, qui 29/10 16:52, com modo_porque = p_modo. Grava (e aplica) com p_persistir.
create function pg_temp.cenario(p_modo text, p_persistir boolean) returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
  v_a jsonb;
begin
  update public.agenda_config set modo_porque = p_modo where id;
  v_p := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00069'), pg_temp.os('OS-00074')], '{}'::jsonb, p_persistir, 'vigia', null,
                              date '2026-10-29', timestamptz '2026-10-29 16:52-03');
  if p_persistir then
    v_a := public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
    v_p := v_p || jsonb_build_object('_aplicar', v_a);
  end if;
  return v_p;
end $f$;

-- As ações que o aplicar gravou, sem os ids, as horas e as colunas da 7g.
create function pg_temp.acoes(p_ids jsonb) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s|%s|%s|%s|%s|%s|%s|%s|%s', x.tipo, x.origem, x.service_order_id, x.executada, x.texto, x.motivo, x.atraso_du,
                                    regexp_replace(pg_temp.limpo(jsonb_build_array(x.antes))::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g'),
                                    regexp_replace(pg_temp.limpo(jsonb_build_array(x.depois))::text, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'U', 'g')),
                             ' ; ' order by x.service_order_id, x.tipo), '')
    from public.agenda_acoes x where x.id in (select e::uuid from jsonb_array_elements_text(coalesce(p_ids, '[]'::jsonb)) e)
$f$;

-- O replay de 29/10 e a fixture da 7a (se a bancada não os carregou), como em agenda_fase7a_compras.sql.
-- Depois, o cenário B da 7a: os 5 modos do gestor ligados, sem o freio, com as regras todas (pg_temp.modos('ligado') de agenda_fase7a_compras.sql), e a presença
-- do dono de produção no Lenine e no Vanderlei. Sem isso, em 29/10 o motor não marca nenhum dos dois (o Lenine espera "tem peça a comprar?", o Vanderlei, o
-- material), e não haveria porquê a gravar.
do $f$
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') <> '' and pg_temp.os('OS-97006') is null then
    execute current_setting('agenda_teste.replay2910');
    execute current_setting('agenda_teste.fase7a');
  end if;
  if pg_temp.os('OS-00074') is not null then
    update public.agenda_config
       set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado',
           modo_vaga_fechamento = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null, marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03',
           marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
     where id;
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  end if;
end $f$;

-- ── P0. As portas e o catálogo ───────────────────────────────────────────────────────────────────────
do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  v     text;
begin
  select string_agg(t.tgname, ',' order by t.tgname) into v
    from pg_trigger t where t.tgrelid = 'public.agenda_alocacoes'::regclass and not t.tgisinternal
     and (t.tgtype & 2) <> 0 and (t.tgtype & 4) <> 0;   -- BEFORE INSERT
  v_res := pg_temp.ok(v_res, 'P0a os BEFORE INSERT de agenda_alocacoes, pelo nome: o porquê depois do critério e da fonte',
                      v = 'agenda_alocacoes_antes,agenda_alocacoes_criterio,agenda_alocacoes_fonte,agenda_alocacoes_porque', v);
  select string_agg(t.tgname, ',' order by t.tgname) into v
    from pg_trigger t where t.tgrelid = 'public.agenda_acoes'::regclass and not t.tgisinternal and (t.tgtype & 2) <> 0 and (t.tgtype & 4) <> 0;
  v_res := pg_temp.ok(v_res, 'P0b os BEFORE INSERT de agenda_acoes: o da zona e do degrau existe',
                      v like '%agenda_acoes_porque%' and v not like '%agenda_acoes_porque%agenda_acoes_porque%', v);
  select string_agg(format('%s:%s:%s:%s', p.proname, p.prosecdef, p.provolatile, coalesce(array_to_string(p.proconfig, ','), '-')), ' | ' order by p.proname) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('_agenda_suposicoes_da_os', '_agenda_alocacoes_porque', '_agenda_acoes_porque');
  v_res := pg_temp.ok(v_res, 'P0c as 3 novas: o gatilho das ações definer, os outros 2 invoker; a das suposições STABLE; search_path fixo',
                      v = '_agenda_acoes_porque:t:v:search_path=public | _agenda_alocacoes_porque:f:v:search_path=public | _agenda_suposicoes_da_os:f:s:search_path=public', v);
  select string_agg(format('%s:%s:%s:%s', f, has_function_privilege('anon', f, 'execute'), has_function_privilege('authenticated', f, 'execute'),
                           has_function_privilege('service_role', f, 'execute')), ' | ' order by f) into v
    from unnest(array['public._agenda_suposicoes_da_os(uuid, jsonb, jsonb, date)', 'public._agenda_alocacoes_porque()', 'public._agenda_acoes_porque()']) f;
  v_res := pg_temp.ok(v_res, 'P0d as portas: anon e authenticated sem nenhuma; o service_role só na das suposições (os gatilhos rodam no insert)',
                      v = 'public._agenda_acoes_porque():f:f:f | public._agenda_alocacoes_porque():f:f:f | public._agenda_suposicoes_da_os(uuid, jsonb, jsonb, date):f:f:t', v);
  -- as recriadas mantêm a porta: o motor só para o service_role; o gatilho da vigente, para ninguém de fora
  v := format('%s:%s:%s', has_function_privilege('authenticated', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'execute'),
              has_function_privilege('service_role', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'execute'),
              has_function_privilege('authenticated', 'public._agenda_alocacoes_imutavel()', 'execute'));
  v_res := pg_temp.ok(v_res, 'P0e as recriadas com a porta de antes (agenda_propor: service_role sim, authenticated não; a vigente: authenticated não)', v = 'f:t:f', v);
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('P0 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$p0$;

-- ── P1 e P2. A proposta gravada: sombra × desligado, e a simulação ────────────────────────────────────
do $p1$
declare
  v_res  jsonb := '[]'::jsonb;
  v_d    jsonb;   -- desligado, gravado
  v_s    jsonb;   -- sombra, gravado
  v_l    jsonb;   -- ligado, gravado
  v_d_al text; v_s_al text; v_s_al7g text; v_d_ac text; v_s_ac text; v_s_ac7g text; v_d_al7g text; v_d_ac7g text;
  v_sim  text[] := '{}';
  v      text;
  m      text;
  v_ok   boolean;
  v_fim  date;
  v_f    jsonb;
  v_it   jsonb;
begin
  if pg_temp.os('OS-00074') is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P1 a proposta gravada', true, 'PULADO: sem o replay de 29/10 (rode pela bancada)'));
    return;
  end if;
  -- cada rodada numa subtransação desfeita: as 3 partem do mesmo estado
  begin
    v_d := pg_temp.cenario('desligado', true);
    v_d_al := pg_temp.alocs((v_d ->> 'proposta_id')::uuid);
    v_d_ac := pg_temp.acoes(v_d #> '{_aplicar,acoes}');
    select string_agg(format('%s|%s', a.suposicoes, a.degrau), ',' order by a.dia, a.turno, a.presenca, a.payee_id) into v_d_al7g
      from public.agenda_alocacoes a where a.proposta_id = (v_d ->> 'proposta_id')::uuid;
    select string_agg(format('%s|%s', x.zona, x.degrau), ',' order by x.service_order_id) into v_d_ac7g
      from public.agenda_acoes x where x.id in (select e::uuid from jsonb_array_elements_text(v_d #> '{_aplicar,acoes}') e);
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_s := pg_temp.cenario('sombra', true);
    v_s_al := pg_temp.alocs((v_s ->> 'proposta_id')::uuid);
    v_s_ac := pg_temp.acoes(v_s #> '{_aplicar,acoes}');
    select string_agg(format('%s %s %s %s|%s', a.dia, a.turno, a.presenca, a.suposicoes, a.degrau), ' ; ' order by a.service_order_id, a.dia, a.turno, a.presenca, a.payee_id)
      into v_s_al7g
      from public.agenda_alocacoes a where a.proposta_id = (v_s ->> 'proposta_id')::uuid;
    select string_agg(format('%s:%s|%s', x.tipo, x.zona, x.degrau), ',' order by x.service_order_id) into v_s_ac7g
      from public.agenda_acoes x where x.id in (select e::uuid from jsonb_array_elements_text(v_s #> '{_aplicar,acoes}') e);
    -- P1c: cada alocação tem o porquê do item dela (turno: as suposições e o degrau do item; abertura e fechamento: [] e sem degrau)
    -- (null-safe dentro do bool_and: ele ignora nulo, e a coluna nula passaria)
    select coalesce(bool_and(case when a.presenca = 'turno' then a.suposicoes is not distinct from it.i #> '{porque,suposicoes}' and a.suposicoes is not null
                                                              and a.degrau is not distinct from it.i #>> '{porque,degrau}'
                                  else a.suposicoes is not distinct from '[]'::jsonb and a.degrau is null end), false) and count(*) > 0
      into v_ok
      from public.agenda_alocacoes a
      cross join lateral (select i from jsonb_array_elements(v_s -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') x
                           where x ->> 'alocacao_id' = a.id::text) it
     where a.proposta_id = (v_s ->> 'proposta_id')::uuid;
    v_res := pg_temp.ok(v_res, 'P1c cada alocação gravada tem o porquê do item dela (turno: suposições e degrau; abertura e fechamento: [] sem degrau)', v_ok, v_s_al7g);
    -- P1e: o dono pede o Lenine 3 semanas depois do último dia dele: o que ele tinha sai (v_canc, motivo dono) e o item novo leva o degrau do que perdeu. A âncora,
    -- contada à parte: o fim novo passa da semana do fim de antes (e do prometido, se houver) = data.
    select max(a.dia) into v_fim from public.agenda_alocacoes a
     where a.proposta_id = (v_s ->> 'proposta_id')::uuid and a.service_order_id = pg_temp.os('OS-00074') and a.estado = 'publicada';
    v_f := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00074')],
                                jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-00074'), 'de', public.agenda_somar_du(v_fim + 21, 0)))),
                                true, 'dono', null, date '2026-10-29', timestamptz '2026-10-29 17:00-03');
    select i into v_it from jsonb_array_elements(v_f -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'os' = pg_temp.os('OS-00074')::text and i ->> 'tipo' <> 'reserva';
    select coalesce(bool_and(case when a.presenca = 'turno' then a.degrau is not distinct from 'data' else a.degrau is null end), false) and count(*) > 0 into v_ok
      from public.agenda_alocacoes a where a.proposta_id = (v_f ->> 'proposta_id')::uuid;
    v_res := pg_temp.ok(v_res, 'P1e o pedido do dono 3 semanas depois: o item do Lenine leva o degrau data (do que perdeu, contra a semana do fim de antes), e as alocações de turno também',
                        v_fim is not null and v_it #>> '{porque,degrau}' = 'data' and v_ok
                        and coalesce((select pl.prometido_ate < (v_it ->> 'ate')::date from public.os_planejamento pl where pl.service_order_id = pg_temp.os('OS-00074')), true),
                        format('fim de antes %s, item %s %s..%s, degrau %s', v_fim, v_it ->> 'tipo', v_it ->> 'de', v_it ->> 'ate', v_it #>> '{porque,degrau}'));
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- P1f: a reserva condicionada leva as suposições (a §5.2: no compromisso e na reserva condicionada; a por teto e a do pátio levam [], e a bancada não faz
  -- nenhuma das 2: ver notas), e as alocações de turno dela, as mesmas. O Wagner (OS-97004) pela OS, com o freio, em 29/10: a reserva condicionada.
  v := null;
  v_ok := false;
  begin
    update public.agenda_config set modo_porque = 'sombra', gestor_so_propor = true where id;
    v_f := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97004')], '{}'::jsonb, true, 'vigia', null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
    select i into v_it from jsonb_array_elements(v_f -> 'itens') i
     where i ->> 'op' = 'criar' and i ->> 'tipo' = 'reserva' and i ->> 'reserva_de' = 'condicionada'
     order by i ->> 'de' limit 1;
    if v_it is not null then
      select coalesce(bool_and(coalesce(a.suposicoes = v_it #> '{porque,suposicoes}', false)), false) and count(*) > 0 into v_ok
        from public.agenda_alocacoes a
       where a.id in (select (x ->> 'alocacao_id')::uuid from jsonb_array_elements(v_it -> 'alocacoes') x) and a.presenca = 'turno';
      v := format('%s condicionada: %s; alocações iguais %s', v_it ->> 'numero', v_it #> '{porque,suposicoes}', v_ok);
      v_ok := v_ok and jsonb_array_length(v_it #> '{porque,suposicoes}') > 0;
    end if;
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'P1f a reserva condicionada (o Wagner, com o freio) leva as suposições no item, e as alocações de turno dela, as mesmas',
                      v is not null and v_ok, coalesce(v, 'sem a reserva condicionada do Wagner'));
  begin
    v_l := pg_temp.cenario('ligado', true);
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- a simulação nos 3 modos
  foreach m in array array['desligado', 'sombra', 'ligado'] loop
    begin
      v_sim := v_sim || md5(pg_temp.cenario(m, false)::text);
      raise exception using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;

  -- P1a: o item criar ganha porque = {suposicoes, degrau}, as suposições válidas (o CHECK da alocação); a chave suposicoes do 7d não muda (P7 mede o leitor)
  select coalesce(bool_and(coalesce(jsonb_typeof(i -> 'porque') = 'object' and (select array_agg(k order by k) from jsonb_object_keys(i -> 'porque') k) = array['degrau', 'suposicoes']
                                    and jsonb_typeof(i #> '{porque,suposicoes}') = 'array' and public._agenda_suposicoes_validas(i #> '{porque,suposicoes}'), false)), false)
         and count(*) > 0
    into v_ok
    from jsonb_array_elements(v_s -> 'itens') i where i ->> 'op' = 'criar';
  v_res := pg_temp.ok(v_res, 'P1a em sombra, todo item criar gravado tem porque {suposicoes, degrau}, com as suposições válidas', v_ok,
                      (select string_agg(format('%s %s %s', i ->> 'numero', i ->> 'tipo', i -> 'porque'), ' ; ') from jsonb_array_elements(v_s -> 'itens') i where i ->> 'op' = 'criar'));
  -- P1b: as suposições de cada OS, byte a byte (o que o motor leu: a estimativa do orçamento, 1 pessoa, o dono que abre e fecha pela regra)
  select string_agg(format('%s %s %s deg=%s', i ->> 'numero', i ->> 'tipo', i #> '{porque,suposicoes}', coalesce(i #>> '{porque,degrau}', '-')), ' ; '
                    order by i ->> 'numero', i ->> 'de', i ->> 'tipo') into v
    from jsonb_array_elements(v_s -> 'itens') i where i ->> 'op' = 'criar';
  v_res := pg_temp.ok(v_res, 'P1b as suposições e o degrau de cada OS, byte a byte (o Vanderlei: 3 peças críticas sem fornecedor com o prazo padrão, João e Roberto sem os dias declarados da semana, a compra com o tempo interno do parâmetro, 7,5 dias pelo orçamento, 1 pessoa, 1 item pequeno; o Lenine: Roberto sem os dias declarados, 6 dias pelo orçamento, 1 pessoa, sem peça; degrau nulo nos 2: nada deles saiu nesta proposta)',
                      v = 'OS-00069 execucao [{"codigo": "prazo_padrao_peca", "detalhe": {"du": 7, "itens": ["Kit Cabos/ Conectores/…", "Cabos Elétricos Diversos…", "Kit cabos eletricos…"]}}, {"codigo": "disponibilidade_suposta", "detalhe": {"pessoas": ["João", "Roberto"]}}, {"codigo": "compra_interna_padrao", "detalhe": {"du": 1}}, {"codigo": "duracao_orcamento", "detalhe": {"mo": 5600.00, "dias": 7.5}}, {"codigo": "uma_pessoa", "detalhe": {}}, {"codigo": "peca_nao_segura", "detalhe": {"n": 1, "limiar": 300.00}}] deg=- ; OS-00074 execucao [{"codigo": "disponibilidade_suposta", "detalhe": {"pessoas": ["Roberto"]}}, {"codigo": "duracao_orcamento", "detalhe": {"mo": 4560.00, "dias": 6}}, {"codigo": "uma_pessoa", "detalhe": {}}, {"codigo": "sem_peca", "detalhe": {}}] deg=-', v);
  -- P1d: a ação que o aplicar gravou tem a zona (o 1º dia do Vanderlei e do Lenine passa do congelamento: a régua da 7f) e, sem antes, degrau nulo
  v_res := pg_temp.ok(v_res, 'P1d as ações do aplicar: a zona dos dias tocados (firme: depois do congelamento e dentro da semana do cliente); o criar sem antes com degrau nulo; o promover_reserva (a reserva que vira compromisso) com o degrau do antes para o depois',
                      v_s_ac7g = 'promover_reserva:firme|dia,criar:firme|', v_s_ac7g);

  -- P2a: desligado: sem a chave, as colunas novas nulas na alocação e na ação
  v_res := pg_temp.ok(v_res, 'P2a desligado: nenhum item com porque',
                      not exists (select 1 from jsonb_array_elements(v_d -> 'itens') i where i ? 'porque')
                      and jsonb_array_length(v_d -> 'itens') > 0, null);
  v_res := pg_temp.ok(v_res, 'P2b desligado: suposições e degrau nulos nas alocações gravadas, zona e degrau nulos nas ações',
                      v_d_al7g !~ '[^|,]' and v_d_ac7g !~ '[^|,]' and v_d_al7g <> '' and v_d_ac7g <> '', v_d_al7g || ' / ' || v_d_ac7g);
  -- P2c: em sombra e ligado, tirada a chave porque, a proposta é a de desligado, byte a byte; as alocações e as ações (sem as colunas da 7g) também
  v_res := pg_temp.ok(v_res, 'P2c sombra = desligado, tirado o porque: itens, fora, carga, perguntas, pontuação, textos e texto',
                      pg_temp.limpo(v_s -> 'itens') = pg_temp.limpo(v_d -> 'itens') and (v_s - 'proposta_id' - 'itens' - '_aplicar') = (v_d - 'proposta_id' - 'itens' - '_aplicar'),
                      md5(pg_temp.limpo(v_s -> 'itens')::text) || ' x ' || md5(pg_temp.limpo(v_d -> 'itens')::text));
  v_res := pg_temp.ok(v_res, 'P2d ligado = desligado, tirado o porque (o porquê não muda decisão)',
                      pg_temp.limpo(v_l -> 'itens') = pg_temp.limpo(v_d -> 'itens') and (v_l - 'proposta_id' - 'itens' - '_aplicar') = (v_d - 'proposta_id' - 'itens' - '_aplicar'), null);
  v_res := pg_temp.ok(v_res, 'P2e o que grava: as alocações e as ações (sem as colunas da 7g) e o texto do aplicar iguais em desligado e sombra',
                      v_s_al = v_d_al and v_s_ac = v_d_ac and v_s_al <> '' and v_s_ac <> ''
                      and (v_s #>> '{_aplicar,texto}') = (v_d #>> '{_aplicar,texto}'),
                      format('alocações %s x %s; ações %s x %s; texto %s', md5(v_s_al), md5(v_d_al), md5(v_s_ac), md5(v_d_ac), (v_s #>> '{_aplicar,texto}') = (v_d #>> '{_aplicar,texto}')));
  v_res := pg_temp.ok(v_res, 'P2f a simulação (p_persistir false) é a mesma em desligado, sombra e ligado, byte a byte',
                      cardinality(v_sim) = 3 and v_sim[1] = v_sim[2] and v_sim[2] = v_sim[3], array_to_string(v_sim, ','));
  -- controle: a comparação morde (a mesma proposta com uma OS a menos não é igual)
  begin
    update public.agenda_config set modo_porque = 'desligado' where id;
    v := md5(pg_temp.limpo(public.agenda_propor('os', null, null, array[pg_temp.os('OS-00074')], '{}'::jsonb, true, 'vigia', null,
                                                 date '2026-10-29', timestamptz '2026-10-29 16:52-03') -> 'itens')::text);
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'P2g controle: a comparação dos itens morde (sem o Vanderlei, os itens mudam)', v <> md5(pg_temp.limpo(v_d -> 'itens')::text), v);
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('P1 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$p1$;

-- Uma proposta replano aberta para a OS, no molde dos escritores do gestor (o item criar sem porque, com o alocacao_id dado); p_gestor nulo = sem gestor.
create function pg_temp.prop_gestor(p_os uuid, p_gestor jsonb, p_aloc uuid default null) returns uuid language plpgsql as $f$
declare
  v_pid uuid := gen_random_uuid();
begin
  insert into public.agenda_propostas (id, escopo, periodo, os_alvo, versao_base, modo, estado, itens, fora, carga, textos, parametros, pontuacao, criada_por,
                                       autor, criada_em, expira_em)
  values (v_pid, 'replano', daterange(date '2031-01-01', date '2031-01-31', '[]'), array[p_os], 0, 'ligado', 'aberta',
          case when p_aloc is null then '[]'::jsonb
               else jsonb_build_array(jsonb_build_object('op', 'criar', 'os', p_os, 'tipo', 'execucao',
                                                         'alocacoes', jsonb_build_array(jsonb_build_object('alocacao_id', p_aloc, 'dia', '2031-01-09', 'turno', 'manha')))) end,
          '[]', '{}', '{}', jsonb_build_object('p_hoje', '2026-10-29') || case when p_gestor is null then '{}'::jsonb else jsonb_build_object('gestor', p_gestor) end,
          null, 'vigia', null, now(), now() + interval '1 day');
  return v_pid;
end $f$;

-- ── P3. O gatilho das alocações: as 3 entradas, a escada e o corte ─────────────────────────────────────
do $p3$
declare
  v_res  jsonb := '[]'::jsonb;
  v_s    jsonb;
  v_len  uuid := pg_temp.os('OS-00074');
  v_out  uuid := pg_temp.os('OS-97006');
  v_dono uuid := public._agenda_dono(null);
  v_ref  public.agenda_alocacoes;
  v_pes  uuid;
  v_id   uuid;
  v_pid  uuid;
  r      public.agenda_alocacoes;
  v      text;
begin
  if v_len is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P3 o gatilho das alocações', true, 'PULADO: sem o replay de 29/10 (rode pela bancada)'));
    return;
  end if;
  begin
  -- o Lenine marcado em sombra: as alocações dele têm o porquê (o P1). A de referência: a de turno mais nova, de quem não é o dono (o critério do dono é presenca_do_dono).
  v_s := pg_temp.cenario('sombra', true);
  select * into strict v_ref from public.agenda_alocacoes a
   where a.service_order_id = v_len and a.suposicoes is not null and a.presenca = 'turno' and a.estado = 'publicada'
     and a.payee_id is distinct from public._agenda_dono(null)
   order by a.criado_em desc, a.id desc limit 1;
  v_pes := v_ref.payee_id;

  -- (a) a substituição copia as suposições, sem o degrau; em sombra o critério é o da 7c (fora_do_motor)
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id, cancelada_em)
  values (v_len, v_pes, date '2031-01-07', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_ref.id, now())
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3a (a) a substituição copia as suposições da substituída, sem o degrau',
                      r.suposicoes = v_ref.suposicoes and r.degrau is null and jsonb_array_length(r.suposicoes) > 0, format('%s | %s', r.suposicoes, r.degrau));
  v_res := pg_temp.ok(v_res, 'P3b (a) em sombra o critério fica o da 7c (fora_do_motor): as colunas de fora da 7g não mudam',
                      r.criterio is null and r.criterio_detalhe = '{"regra": "fora_do_motor"}'::jsonb, format('%s %s', r.criterio, r.criterio_detalhe));
  update public.agenda_config set modo_porque = 'ligado' where id;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id, cancelada_em)
  values (v_len, v_pes, date '2031-01-08', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_ref.id, now())
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3c (a) em ligado o critério da substituída vem junto (R9.4-1), com as suposições',
                      r.criterio is not distinct from v_ref.criterio and r.criterio_detalhe = v_ref.criterio_detalhe and r.suposicoes = v_ref.suposicoes,
                      format('%s %s / ref %s %s', r.criterio, r.criterio_detalhe, v_ref.criterio, v_ref.criterio_detalhe));
  update public.agenda_config set modo_porque = 'sombra' where id;

  -- uma alocação bem mais antiga da OS, com outras suposições: a escada copia a mais nova, não esta
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, cancelada_em, criado_em, suposicoes)
  values (v_len, v_pes, date '2031-01-06', 'tarde', 'turno', 'execucao', 'cancelada', 'motor', now(), timestamptz '2026-01-01 08:00-03',
          '[{"codigo": "uma_pessoa", "detalhe": {}}]');
  -- (c) a escada: a proposta do gestor (reparar, com o degrau), sem porque no item: as suposições da alocação mais nova da OS, o degrau da escada
  v_id := gen_random_uuid();
  v_pid := pg_temp.prop_gestor(v_len, jsonb_build_object('tipo', 'reparar', 'degrau', 'pessoa'), v_id);
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
  values (v_id, v_len, v_pes, date '2031-01-09', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_pid, now())
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3d (c) a escada (reparar): as suposições da alocação mais nova da OS e o degrau da escada',
                      r.suposicoes = v_ref.suposicoes and r.degrau = 'pessoa', format('%s | %s', r.suposicoes, r.degrau));
  -- a abertura da mesma proposta: [] e sem degrau
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
  values (v_len, v_dono, date '2031-01-10', 'manha', 'abertura', 'execucao', 'cancelada', 'motor', v_pid, now())
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3e (c) a abertura na proposta do gestor: [] e sem degrau', r.suposicoes = '[]'::jsonb and r.degrau is null, format('%s | %s', r.suposicoes, r.degrau));
  -- nunca da própria proposta: a 2ª alocação de turno da mesma proposta não copia da 1ª (que é mais nova), copia a de antes
  -- (a hora: a da bancada é anterior à do cenário de 29/10; a irmã fica de fato a mais nova da OS, e some no fim do caso)
  begin
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em, criado_em, suposicoes)
    values (v_len, v_pes, date '2031-01-11', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_pid, now(), timestamptz '2026-12-01 10:00-03',
            '[{"codigo": "sem_peca", "detalhe": {}}]');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
    values (v_len, v_pes, date '2031-01-12', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_pid, now())
    returning * into r;
    v_res := pg_temp.ok(v_res, 'P3f (c) nunca copia da própria proposta (a irmã mais nova com outras suposições não conta)',
                        r.suposicoes = v_ref.suposicoes, format('%s', r.suposicoes));
    raise exception using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  -- mais novas que não contam: a abertura do dono (não é meio-dia de turno) e uma reserva (a reserva copia de reserva; o compromisso, de compromisso)
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, cancelada_em, criado_em, suposicoes)
  values (v_len, v_dono, date '2031-01-05', 'manha', 'abertura', 'execucao', 'cancelada', 'motor', now(), timestamptz '2026-12-01 11:00-03', '[]');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, reserva_de, cancelada_em, criado_em, suposicoes)
  values (v_len, v_pes, date '2031-01-05', 'tarde', 'turno', 'reserva', 'cancelada', 'motor', 'teto', now(), timestamptz '2026-12-01 12:00-03', '[]');
  -- o corte (reestimar): sem degrau na proposta, sem degrau; as suposições copiadas
  v_pid := pg_temp.prop_gestor(v_len, jsonb_build_object('tipo', 'reestimar'));
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
  values (v_len, v_pes, date '2031-01-13', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_pid, now())
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3g (c) o corte (reestimar): as suposições copiadas e sem degrau', r.suposicoes = v_ref.suposicoes and r.degrau is null,
                      format('%s | %s', r.suposicoes, r.degrau));
  -- o degrau fora da lista do CHECK não entra (a alocação entra)
  v_pid := pg_temp.prop_gestor(v_len, jsonb_build_object('tipo', 'reparar', 'degrau', 'troca'));
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
  values (v_len, v_pes, date '2031-01-14', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_pid, now())
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3h (c) o degrau fora da lista não entra, e a alocação entra', r.degrau is null and r.suposicoes = v_ref.suposicoes, format('%s', r.degrau));
  -- a OS sem porquê guardado (o Wagner, de antes): nula (não se afirma o que não foi guardado); o degrau da escada entra
  v_pid := pg_temp.prop_gestor(v_out, jsonb_build_object('tipo', 'reparar', 'degrau', 'dia'));
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
  values (v_out, v_pes, date '2031-01-15', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_pid, now())
  returning * into r;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
  values (v_out, v_dono, date '2031-01-15', 'tarde', 'fechamento', 'execucao', 'cancelada', 'motor', v_pid, now())
  returning coalesce(suposicoes::text, '') || '|' || coalesce(degrau, '-') into v;
  v_res := pg_temp.ok(v_res, 'P3i2 (c) o fechamento da OS sem porquê guardado: nulo (não [], que diria "sem suposição"), sem degrau', v = '|-', v);
  v_res := pg_temp.ok(v_res, 'P3i (c) a OS sem porquê guardado: suposições nulas, o degrau da escada',
                      r.suposicoes is null and r.degrau = 'dia' and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_out and a.suposicoes is not null and a.id <> r.id),
                      format('%s | %s', r.suposicoes, r.degrau));
  -- o corte: sem proposta nem substituída, nula; a proposta sem gestor e sem porque no item, nula
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, cancelada_em)
  values (v_len, v_pes, date '2031-01-16', 'manha', 'turno', 'execucao', 'cancelada', 'motor', now())
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3j o corte: sem proposta nem substituída, nula e sem degrau', r.suposicoes is null and r.degrau is null, null);
  v_pid := pg_temp.prop_gestor(v_len, null);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
  values (v_len, v_pes, date '2031-01-17', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_pid, now())
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3k a proposta sem gestor e sem porque no item: nula', r.suposicoes is null and r.degrau is null, null);
  -- quem grava já disse: fica
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id, cancelada_em, suposicoes)
  values (v_len, v_pes, date '2031-01-18', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_ref.id, now(), '[]')
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P3l quem grava já disse o porquê: fica', r.suposicoes = '[]'::jsonb, format('%s', r.suposicoes));
  -- desligado: nenhuma das 3 entradas grava
  update public.agenda_config set modo_porque = 'desligado' where id;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, substitui_id, cancelada_em)
  values (v_len, v_pes, date '2031-01-19', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_ref.id, now())
  returning * into r;
  v_pid := pg_temp.prop_gestor(v_len, jsonb_build_object('tipo', 'reparar', 'degrau', 'dia'));
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, cancelada_em)
  values (v_len, v_pes, date '2031-01-20', 'manha', 'turno', 'execucao', 'cancelada', 'motor', v_pid, now());
  v_res := pg_temp.ok(v_res, 'P3m desligado: nem a substituição nem a escada gravam o porquê',
                      r.suposicoes is null and (select a.suposicoes is null and a.degrau is null from public.agenda_alocacoes a
                                                 where a.service_order_id = v_len and a.dia = date '2031-01-20'), null);
  raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('P3 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$p3$;

-- ── P4. O gatilho das ações: a zona e o degrau ───────────────────────────────────────────────────────
do $p4$
declare
  v_res  jsonb := '[]'::jsonb;
  v_len  uuid := pg_temp.os('OS-00074');
  v_sem  uuid;
  v_pes  uuid;
  v_pes2 uuid;
  cf     public.agenda_config := public._agenda_cfg();
  r      public.agenda_acoes;
  v_n    int;
  v      text;
  c_h    constant date := date '2026-10-29';
begin
  if v_len is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P4 o gatilho das ações', true, 'PULADO: sem o replay de 29/10 (rode pela bancada)'));
    return;
  end if;
  begin
  update public.agenda_config set modo_porque = 'sombra' where id;
  -- a OS das ações: uma sem linha em os_planejamento (o caso comum, R9.12-3: sem prometido), a 1ª pelo número
  select so.id into strict v_sem from public.service_orders so
   where not exists (select 1 from public.os_planejamento pl where pl.service_order_id = so.id)
   order by so.service_order_number, so.id limit 1;
  v_len := v_sem;
  select p.id into v_pes from public.payees p where p.active and p.kind <> 'socio' and p.id is distinct from public._agenda_dono(null) order by p.name, p.id limit 1;
  select p.id into v_pes2 from public.payees p where p.active and p.kind <> 'socio' and p.id is distinct from public._agenda_dono(null) and p.id <> v_pes
   order by p.name, p.id limit 1;
  -- a âncora: as datas pela régua contada à parte (o congelamento e a semana do cliente da config, em dias úteis), e os dias de teste sem ficha nem aviso
  v_res := pg_temp.ok(v_res, 'P4a a régua da âncora: qui 29/10 é travada (congelamento), ter 10/11 é firme (antes de cliente_semana_du), ter 15/12 é livre',
                      c_h <= public.agenda_somar_du(c_h, cf.congelamento_du)
                      and date '2026-11-10' > public.agenda_somar_du(c_h, cf.congelamento_du) and date '2026-11-10' <= public.agenda_somar_du(c_h, cf.cliente_semana_du)
                      and date '2026-12-15' > public.agenda_somar_du(c_h, cf.cliente_semana_du)
                      and public._agenda_dia_avisado(v_pes, v_len, date '2026-11-10') is null and public._agenda_dia_avisado(v_pes, v_len, date '2026-12-15') is null
                      and public._agenda_dia_avisado(v_pes2, v_len, date '2026-12-15') is null and public._agenda_dia_avisado(v_pes, v_len, date '2026-10-29') is null
                      and public._agenda_dia_avisado(v_pes2, v_len, date '2026-11-10') is null
                      and (select pl.prometido_ate from public.os_planejamento pl where pl.service_order_id = v_len) is null,
                      format('congela %s, cliente %s', public.agenda_somar_du(c_h, cf.congelamento_du), public.agenda_somar_du(c_h, cf.cliente_semana_du)));
  -- mover na livre, só de pessoa: livre e pessoa
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'mover', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha', 'presenca', 'turno'))),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes2, 'dia', '2026-12-15', 'turno', 'manha', 'presenca', 'turno'))),
          'teste P4 livre') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4b mover na livre, só de pessoa: zona livre, degrau pessoa', r.zona = 'livre' and r.degrau = 'pessoa', format('%s %s', r.zona, r.degrau));
  -- na firme, de turno
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'mover', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-11-10', 'turno', 'manha', 'presenca', 'turno'))),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-11-10', 'turno', 'tarde', 'presenca', 'turno'))),
          'teste P4 firme') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4c mover na firme, de turno: zona firme, degrau turno', r.zona = 'firme' and r.degrau = 'turno', format('%s %s', r.zona, r.degrau));
  -- da livre para a travada (o dia mais severo vence), com o fim bem depois: travada e data
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'mover', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-10-29', 'turno', 'tarde', 'presenca', 'turno')), 'fim', '2026-10-29'),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2027-02-01', 'turno', 'manha', 'presenca', 'turno')), 'fim', '2027-02-01'),
          'teste P4 travada') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4d da travada para a livre: a mais severa (travada) e a data andou', r.zona = 'travada' and r.degrau = 'data', format('%s %s', r.zona, r.degrau));
  -- cancelar: tirou
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'cancelar', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha', 'presenca', 'turno'))),
          jsonb_build_object('alocacoes', '[]'::jsonb), 'teste P4 tirou') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4e cancelar na livre: zona livre, degrau tirou', r.zona = 'livre' and r.degrau = 'tirou', format('%s %s', r.zona, r.degrau));
  -- reparar e reestimar estão na lista (R9.5-16)
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'reparar', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-11-10', 'turno', 'manha'))),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes2, 'dia', '2026-11-10', 'turno', 'manha'))), 'teste P4 reparar') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4f reparar entra (R9.5-16): firme e pessoa (sem presenca no item = turno)', r.zona = 'firme' and r.degrau = 'pessoa', format('%s %s', r.zona, r.degrau));
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'reestimar', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha'),
                                                            jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-16', 'turno', 'manha'))),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha'))), 'teste P4 reestimar') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4g reestimar entra (R9.5-16): livre, e o corte de um dia dentro da semana é dia', r.zona = 'livre' and r.degrau = 'dia', format('%s %s', r.zona, r.degrau));
  -- sem as alocações no antes/depois: a zona pelos ids (uma alocação publicada do replay), degrau nulo
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, cancelada_em)
  values (v_len, v_pes, date '2026-11-10', 'tarde', 'turno', 'execucao', 'cancelada', 'motor', now()) returning id into strict v;
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, texto)
  values (c_h, true, 'tela', 'fixar', v_len, array[v_len], array[v::uuid], 'teste P4 ids') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4h sem as alocações no antes/depois: a zona pelos ids (firme), degrau nulo', r.zona = 'firme' and r.degrau is null, format('%s %s', r.zona, r.degrau));
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, texto)
  values (c_h, true, 'tela', 'fixar', v_len, array[v_len], jsonb_build_object('alocacoes', jsonb_build_array(v)), 'teste P4 ids texto') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4i os ids em texto no antes também dão a zona', r.zona = 'firme' and r.degrau is null, format('%s %s', r.zona, r.degrau));
  -- a falha não derruba a ação: o fim que não é data
  select count(*) into v_n from public.app_error_logs where action = 'explicar:acao';
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'mover', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha')), 'fim', 'não é data'),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes2, 'dia', '2026-12-15', 'turno', 'manha'))), 'teste P4 falha') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4j a falha do cálculo não derruba a ação: zona e degrau nulos, o erro registrado (explicar:acao)',
                      r.id is not null and r.zona is null and r.degrau is null
                      and (select count(*) from public.app_error_logs where action = 'explicar:acao') = v_n + 1, format('%s %s', r.zona, r.degrau));
  -- não executada (a sombra da 7a) e tipo fora da lista: nada
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, false, 'vigia', 'mover', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha'))),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes2, 'dia', '2026-12-15', 'turno', 'manha'))), 'teste P4 sombra') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4k a ação não executada: nada', r.zona is null and r.degrau is null, null);
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'resultado', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha'))),
          jsonb_build_object('alocacoes', '[]'::jsonb), 'teste P4 resultado') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4l o tipo fora da lista (resultado): nada', r.zona is null and r.degrau is null, null);
  -- quem grava já disse a zona: fica (o dia é da travada)
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, zona)
  values (c_h, true, 'vigia', 'mover', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-10-29', 'turno', 'tarde'))),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes2, 'dia', '2026-10-29', 'turno', 'tarde'))), 'teste P4 dita', 'livre')
  returning * into r;
  v_res := pg_temp.ok(v_res, 'P4o a zona que quem grava já disse fica (e o degrau não é calculado por cima)', r.zona = 'livre' and r.degrau is null, format('%s %s', r.zona, r.degrau));
  -- desligado: nada
  update public.agenda_config set modo_porque = 'desligado' where id;
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (c_h, true, 'vigia', 'mover', v_len, array[v_len],
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha'))),
          jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes2, 'dia', '2026-12-15', 'turno', 'manha'))), 'teste P4 desligado') returning * into r;
  v_res := pg_temp.ok(v_res, 'P4m desligado: nada', r.zona is null and r.degrau is null, null);
  update public.agenda_config set modo_porque = 'sombra' where id;
  -- quem insere é o service_role (sem porta em _agenda_zona): o gatilho é definer e calcula
  if has_table_privilege('service_role', 'public.agenda_acoes', 'insert') and (select ro.rolbypassrls from pg_roles ro where ro.rolname = 'service_role') then
    select count(*) into v_n from public.app_error_logs where action = 'explicar:acao';
    v := pg_temp.como('service_role', format($q$with x as (insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
             values (%L, true, 'vigia', 'mover', %L, array[%L::uuid], %L::jsonb, %L::jsonb, 'teste P4 service_role') returning zona, degrau)
             select zona || ' ' || degrau from x$q$, c_h, v_len, v_len,
             jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes, 'dia', '2026-12-15', 'turno', 'manha'))),
             jsonb_build_object('alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_pes2, 'dia', '2026-12-15', 'turno', 'manha')))));
    v_res := pg_temp.ok(v_res, 'P4n o service_role insere a ação e o gatilho (definer) calcula a zona, sem registrar erro',
                        v = 'livre pessoa' and (select count(*) from public.app_error_logs where action = 'explicar:acao') = v_n, v);
  else
    v_res := pg_temp.ok(v_res, 'P4n o service_role insere a ação', true, 'PULADO: o service_role não grava agenda_acoes aqui');
  end if;
  raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('P4 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$p4$;

-- ── P5. A vigente não muda o porquê ──────────────────────────────────────────────────────────────────
do $p5$
declare
  v_res jsonb := '[]'::jsonb;
  v_id  uuid;
  v_p   jsonb;
  v     text;
  c     text;
begin
  if pg_temp.os('OS-00074') is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P5 a vigente', true, 'PULADO: sem o replay de 29/10 (rode pela bancada)'));
    return;
  end if;
  begin
    -- o cenário em sombra: as publicadas têm o porquê
    v_p := pg_temp.cenario('sombra', true);
    select a.id into strict v_id from public.agenda_alocacoes a
     where a.proposta_id = (v_p ->> 'proposta_id')::uuid and a.estado = 'publicada' and a.presenca = 'turno' and a.suposicoes is not null
     order by a.dia, a.turno, a.payee_id limit 1;
    foreach c in array array['suposicoes = ''[]''::jsonb', 'degrau = ''dia''', 'duracao_fonte = ''dono'''] loop
      begin
        execute format('update public.agenda_alocacoes set %s where id = %L', c, v_id);
        v := 'aceitou';
        raise exception using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
                when others then v := sqlerrm;
      end;
      v_res := pg_temp.ok(v_res, 'P5a a publicada não muda: ' || c, v like 'Alocação publicada não muda%', v);
    end loop;
    -- a cancelada também não (o cancelamento é permitido; depois, nada muda)
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where id = v_id;
    begin
      update public.agenda_alocacoes set degrau = 'tirou' where id = v_id;
      v := 'aceitou';
      raise exception using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
              when others then v := sqlerrm;
    end;
    v_res := pg_temp.ok(v_res, 'P5b a cancelada não muda o porquê', v like 'Alocação cancelada não volta nem muda%', v);
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a proposta (antes de aplicar) muda: a imutável é a vigente
    update public.agenda_config set modo_porque = 'sombra' where id;
    v_p := public.agenda_propor('os', null, null, array[pg_temp.os('OS-00074')], '{}'::jsonb, true, 'vigia', null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
    select a.id into strict v_id from public.agenda_alocacoes a where a.proposta_id = (v_p ->> 'proposta_id')::uuid and a.estado = 'proposta'
     order by a.dia, a.turno, a.payee_id, a.presenca limit 1;
    begin
      update public.agenda_alocacoes set suposicoes = '[]', degrau = 'dia', duracao_fonte = 'dono' where id = v_id;
      v := 'aceitou';
    exception when others then v := sqlerrm;
    end;
    v_res := pg_temp.ok(v_res, 'P5c a alocação em proposta muda o porquê (a imutável é a vigente)', v = 'aceitou', v);
    raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('P5 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$p5$;

-- ── P6. As cópias ────────────────────────────────────────────────────────────────────────────────────
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- o corpo sem os blocos deste pacote ("-- FASE 7g: (7g P2 … -- FASE 7g: fim")
create function pg_temp.sem_p2(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(p_corpo, E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7g: \(7g P2' then v_bloco := true; continue; end if;
    if v_bloco and l ~ '^\s*-- FASE 7g: fim' then v_bloco := false; continue; end if;
    if not v_bloco then v_b := v_b || l; end if;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

do $p6$
declare
  v_res jsonb := '[]'::jsonb;
  v_m   text := current_setting('agenda_teste.mig_porque_fase7g', true);
  v     text;
begin
  if coalesce(v_m, '') = '' or coalesce(current_setting('agenda_teste.mig_folga_fase7e', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P6 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)'));
    return;
  end if;
  v_res := pg_temp.ok(v_res, 'P6a agenda_propor: tirados os blocos da 7g, a da 7e P4 (20261111100300), byte a byte',
                      pg_temp.sem_p2(pg_temp.corpo(v_m, 'agenda_propor')) = pg_temp.corpo(current_setting('agenda_teste.mig_folga_fase7e'), 'agenda_propor')
                      and pg_temp.corpo(v_m, 'agenda_propor') <> pg_temp.corpo(current_setting('agenda_teste.mig_folga_fase7e'), 'agenda_propor'), null);
  v_res := pg_temp.ok(v_res, 'P6b _agenda_alocacoes_imutavel: tirado o bloco da 7g, a da 7c P2 (20261102100100), byte a byte',
                      pg_temp.sem_p2(pg_temp.corpo(v_m, '_agenda_alocacoes_imutavel')) = pg_temp.corpo(current_setting('agenda_teste.mig_motor_fase7c'), '_agenda_alocacoes_imutavel')
                      and pg_temp.corpo(v_m, '_agenda_alocacoes_imutavel') <> pg_temp.corpo(current_setting('agenda_teste.mig_motor_fase7c'), '_agenda_alocacoes_imutavel'), null);
  v_res := pg_temp.ok(v_res, 'P6c a viva é a da migration (agenda_propor e a vigente)',
                      (select replace(p.prosrc, E'\r\n', E'\n') from pg_proc p where p.oid = 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)'::regprocedure)
                        = pg_temp.corpo(v_m, 'agenda_propor')
                      and (select replace(p.prosrc, E'\r\n', E'\n') from pg_proc p where p.oid = 'public._agenda_alocacoes_imutavel()'::regprocedure) = pg_temp.corpo(v_m, '_agenda_alocacoes_imutavel'), null);
  select string_agg(distinct m[1] collate "C", ',' order by m[1] collate "C") into v
    from regexp_matches(v_m, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
  v_res := pg_temp.ok(v_res, 'P6d a migration recria só agenda_propor e a vigente, e cria as 3 novas',
                      v = '_agenda_acoes_porque,_agenda_alocacoes_imutavel,_agenda_alocacoes_porque,_agenda_suposicoes_da_os,agenda_propor', v);
  -- o controle: o tirador morde (sem tirar, o corpo não é o da origem)
  v_res := pg_temp.ok(v_res, 'P6e controle: sem tirar os blocos, a cópia não é a da origem',
                      pg_temp.corpo(v_m, 'agenda_propor') <> pg_temp.corpo(current_setting('agenda_teste.mig_folga_fase7e'), 'agenda_propor'), null);
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('P6 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$p6$;

-- ── P7. O foco locais igual ──────────────────────────────────────────────────────────────────────────
do $p7$
declare
  v_res jsonb := '[]'::jsonb;
  v_os  uuid[];
  v     text[] := '{}';
  m     text;
  v_p   jsonb;
  x     uuid;
begin
  if pg_temp.os('OS-00074') is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P7 o foco locais', true, 'PULADO: sem o replay de 29/10 (rode pela bancada)'));
    return;
  end if;
  v_os := array[pg_temp.os('OS-00069'), pg_temp.os('OS-00074')];
  foreach m in array array['desligado', 'sombra'] loop
    begin
      update public.agenda_config
         set modo_porque = m, gestor_so_propor = false, modo_local_calendario = 'ligado', modo_patio = 'ligado', modo_mesmo_local = 'ligado', modo_bem = 'ligado'
       where id;
      v_p := public.agenda_propor('os', null, null, v_os, '{}'::jsonb, true, 'vigia', null, date '2026-10-29', timestamptz '2026-10-29 16:52-03');
      v := v || md5(coalesce((select jsonb_agg(i -> 'suposicoes' order by i ->> 'numero', i ->> 'de') from jsonb_array_elements(v_p -> 'itens') i), '[]')::text
                    || (select string_agg(public._agenda_local_bloco(o, date '2026-10-29')::text, '|' order by o) from unnest(v_os) o)
                    || coalesce(public._agenda_ver_locais(date '2026-10-29', null)::text, ''));
      raise exception using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'P7 com os modos do local ligados, a chave suposicoes do 7d, o bloco do local e o foco locais iguais com e sem o porque no item',
                      cardinality(v) = 2 and v[1] = v[2], array_to_string(v, ','));
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('P7 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$p7$;

-- ── P8. As suposições, código a código (_agenda_suposicoes_da_os com a prontidão e os meios montados; o que ela lê do banco, montado no banco) ─────
do $p8$
declare
  v_res  jsonb := '[]'::jsonb;
  cf     public.agenda_config := public._agenda_cfg();
  v_os   uuid;
  v_os2  uuid;
  v_dono uuid := public._agenda_dono(null);
  v_p    uuid[];
  v_q    uuid;
  s      jsonb;
  v_lr   jsonb;
  v      text;
  c_d    constant date := date '2026-11-12';
  a1     jsonb;
  m      jsonb;
begin
  begin
  -- uma OS sem linha em os_planejamento (o caso comum), a 1ª pelo número: a base dos casos montados
  select so.id into strict v_os from public.service_orders so
   where not exists (select 1 from public.os_planejamento pl where pl.service_order_id = so.id) and so.merged_into_id is null
   order by so.service_order_number, so.id limit 1;
  select array_agg(x.id order by x.name, x.id) into v_p
    from (select p.id, p.name from public.payees p where p.active and p.kind <> 'socio' and p.id is distinct from v_dono order by p.name, p.id limit 4) x;
  a1 := jsonb_build_array(jsonb_build_object('payee_id', v_p[1], 'nome', 'Alfa', 'dia', c_d, 'turno', 'manha', 'presenca', 'turno'));

  -- vazio: nada
  s := public._agenda_suposicoes_da_os(v_os, '{}'::jsonb, '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8a sem prontidão, meios nem bloco: nenhuma suposição', s = '[]'::jsonb, s::text);

  -- prazo_padrao_peca: só a crítica em falta com a classe padrao (crítico nulo conta), na ordem da prontidão; o nome curto em branco vira "peça"
  m := jsonb_build_object('material', jsonb_build_object('itens', jsonb_build_array(
         jsonb_build_object('curto', 'Cerbo', 'situacao', 'falta', 'classe', 'padrao', 'critico', true, 'prazo_du', 7),
         jsonb_build_object('curto', 'Parafuso', 'situacao', 'falta', 'classe', 'padrao', 'critico', false, 'prazo_du', 7),
         jsonb_build_object('curto', ' ', 'situacao', 'falta', 'classe', 'padrao', 'prazo_du', 7),
         jsonb_build_object('curto', 'Bomba', 'situacao', 'falta', 'classe', 'local', 'critico', true, 'prazo_du', 2),
         jsonb_build_object('curto', 'Relé', 'situacao', 'comprado', 'classe', 'padrao', 'critico', true, 'prazo_du', 9))));
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('pront', m), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8b prazo_padrao_peca: a crítica em falta com prazo padrão (e a de crítico nulo), na ordem da prontidão, com o prazo',
                      s = '[{"codigo": "prazo_padrao_peca", "detalhe": {"du": 7, "itens": ["Cerbo", "peça"]}}]'::jsonb, s::text);
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('pront', jsonb_build_object('material', jsonb_build_object('itens', jsonb_build_array(
         jsonb_build_object('curto', 'Cerbo', 'situacao', 'falta', 'classe', 'padrao', 'critico', true))))), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8c prazo_padrao_peca sem o prazo: não entra (não se afirma o que não foi contado)', s = '[]'::jsonb, s::text);

  -- sinal_a_cobrar, sem_peca
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('pront', jsonb_build_object('restricoes', jsonb_build_array(
         jsonb_build_object('tipo', 'cliente'), jsonb_build_object('tipo', 'sinal'), jsonb_build_object('tipo', 'sem_peca_suposta')))), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8d sinal_a_cobrar (a restrição sinal) e sem_peca (sem_peca_suposta), na ordem do §3.1-3; a restrição cliente não é suposição',
                      s = '[{"codigo": "sinal_a_cobrar", "detalhe": {}}, {"codigo": "sem_peca", "detalhe": {}}]'::jsonb, s::text);

  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('pront', jsonb_build_object('restricoes', jsonb_build_array(
         jsonb_build_object('tipo', 'cliente'), jsonb_build_object('tipo', 'escopo')))), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8d2 sem a restrição sinal nem a sem_peca_suposta (cliente, escopo): nenhuma suposição', s = '[]'::jsonb, s::text);

  -- compra_interna_padrao: a falta com compra_firme e compre até, sem o número medido no item e sem o congelado
  m := jsonb_build_object('situacao', 'falta', 'compra_firme', true, 'compre_ate', '2026-11-05');
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('pront', jsonb_build_object('material', jsonb_build_object('itens', jsonb_build_array(m)))), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8e compra_interna_padrao: o tempo interno do parâmetro',
                      s = jsonb_build_array(jsonb_build_object('codigo', 'compra_interna_padrao', 'detalhe', jsonb_build_object('du', cf.compra_interna_du))), s::text);
  select string_agg(public._agenda_suposicoes_da_os(v_os, jsonb_build_object('pront', jsonb_build_object('material', jsonb_build_object('itens', jsonb_build_array(x)))),
                                                    '[]'::jsonb, c_d)::text, ' ' order by o)
    into v
    from unnest(array[m || '{"tempo_interno_du": 2}', m || '{"compra_firme": false}', m - 'compre_ate', m || '{"situacao": "comprado"}']) with ordinality t(x, o);
  v_res := pg_temp.ok(v_res, 'P8f compra_interna_padrao não entra com o medido no item, sem compra_firme, sem compre até, ou comprado', v = '[] [] [] []', v);
  insert into public.os_planejamento (service_order_id, tempo_compra_marcado, marcado_em) values (v_os, 2, now());
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('pront', jsonb_build_object('material', jsonb_build_object('itens', jsonb_build_array(m)))), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8g compra_interna_padrao não entra com o congelado na marcação (tempo_compra_marcado)', s = '[]'::jsonb, s::text);
  delete from public.os_planejamento where service_order_id = v_os;

  -- peca_nao_segura: os separar_vespera fora da mão, com o limiar da config
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('pront', jsonb_build_object('material', jsonb_build_object('itens', jsonb_build_array(
         jsonb_build_object('situacao', 'falta', 'separar_vespera', true), jsonb_build_object('situacao', 'comprado', 'separar_vespera', true),
         jsonb_build_object('situacao', 'na_mao', 'separar_vespera', true), jsonb_build_object('situacao', 'falta', 'separar_vespera', false))))), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8h peca_nao_segura: os itens pequenos fora da mão (2 de 3) e o limiar de critico_valor_min',
                      s = jsonb_build_array(jsonb_build_object('codigo', 'peca_nao_segura', 'detalhe', jsonb_build_object('n', 2, 'limiar', cf.critico_valor_min))), s::text);

  -- duracao_orcamento: a fonte orcamento, com os dias e a mão de obra do orçamento (nula quando zero)
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('fonte', 'orcamento', 'dias', 3, 'equipe_dita', true)), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8i duracao_orcamento: os dias dos meios e a mão de obra do orçamento',
                      s = jsonb_build_array(jsonb_build_object('codigo', 'duracao_orcamento', 'detalhe',
                            jsonb_build_object('dias', 3, 'mo', nullif((public.os_duracao_sugerida(v_os) ->> 'mo')::numeric, 0)))), s::text);
  select string_agg(public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', x), '[]'::jsonb, c_d)::text, ' ' order by o) into v
    from unnest(array['{"fonte": "sugerida", "dias": 3, "equipe_dita": true}'::jsonb, '{"fonte": "orcamento", "dias": 0, "equipe_dita": true}',
                      '{"fonte": "orcamento", "equipe_dita": true}']) with ordinality t(x, o);
  v_res := pg_temp.ok(v_res, 'P8j duracao_orcamento não entra com outra fonte, com 0 dias ou sem os dias', v = '[] [] []', v);

  -- uma_pessoa: sem equipe nem dupla dita, 1 pessoa por meio-dia (a abertura do dono não conta)
  m := a1 || jsonb_build_array(jsonb_build_object('payee_id', v_p[1], 'dia', c_d, 'turno', 'tarde', 'presenca', 'turno'),
                               jsonb_build_object('payee_id', v_dono, 'dia', c_d, 'turno', 'manha', 'presenca', 'abertura'));
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('equipe_dita', false)), m, c_d);
  v_res := pg_temp.ok(v_res, 'P8k uma_pessoa: 1 pessoa por meio-dia, sem equipe nem dupla dita (a abertura do dono não conta)',
                      s @> '[{"codigo": "uma_pessoa", "detalhe": {}}]'::jsonb, s::text);
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('equipe_dita', false)),
                                       m || jsonb_build_array(jsonb_build_object('payee_id', v_p[2], 'dia', c_d, 'turno', 'tarde')), c_d);
  v := (s @> '[{"codigo": "uma_pessoa"}]')::text;
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), m, c_d);
  v := v || ' ' || (s @> '[{"codigo": "uma_pessoa"}]')::text;
  insert into public.os_planejamento (service_order_id, dupla_dita, dupla_em) values (v_os, 'nao', now());
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('equipe_dita', false)), m, c_d);
  v := v || ' ' || (s @> '[{"codigo": "uma_pessoa"}]')::text;
  delete from public.os_planejamento where service_order_id = v_os;
  v_res := pg_temp.ok(v_res, 'P8l uma_pessoa não entra com 2 num meio-dia, com a equipe dita ou com a dupla dita (mesmo "sem dupla")', v = 'false false false', v);

  -- dono_abre_fecha: a abertura ou o fechamento no bloco e a presença do dono pela regra (abre e fecha)
  select so.id into v_os2 from public.service_orders so
   where public.os_presenca_do_dono(so.id) ->> 'presenca' = 'abre_e_fecha' and coalesce(public.os_presenca_do_dono(so.id) ->> 'fonte', 'regra') = 'regra'
     and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = so.id)
   order by so.service_order_number, so.id limit 1;
  if v_os2 is null then
    v_res := pg_temp.ok(v_res, 'P8m dono_abre_fecha', false, 'sem OS com a presença do dono pela regra do abre e fecha');
  else
    m := jsonb_build_array(jsonb_build_object('payee_id', v_dono, 'dia', c_d, 'turno', 'tarde', 'presenca', 'fechamento'));
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), m, c_d);
    v := s::text;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), a1, c_d);
    v := v || ' ' || s::text;
    insert into public.os_planejamento (service_order_id, dono_presenca) values (v_os2, 'abre_e_fecha');
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), m, c_d);
    v := v || ' ' || s::text;
    delete from public.os_planejamento where service_order_id = v_os2;
    v_res := pg_temp.ok(v_res, 'P8m dono_abre_fecha: com o fechamento no bloco e a presença pela regra; sem abertura nem fechamento, não; com a presença dita pelo dono, não',
                        v = '[{"codigo": "dono_abre_fecha", "detalhe": {}}] [] []', v);
  end if;

  -- disponibilidade_suposta: a semente (historico) e o padrão que não foi o dono quem disse; a semana dita e o padrão do dono são declarados; o dono não entra
  update public.agenda_disponibilidade set substituida_em = now() where payee_id = any (v_p || v_dono) and substituida_em is null;
  insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, frequencia) values
    (v_p[1], '{1,2,3,4,5}', 'disponivel', 'historico', 0.9), (v_dono, '{1,2,3,4,5}', 'disponivel', 'historico', 0.9);
  insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values
    (v_p[2], '{1,2,3,4,5}', 'disponivel', 'dono'), (v_p[3], '{1,2,3,4,5}', 'disponivel', 'diarista');
  insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, semana_dita) values
    (v_p[4], daterange(c_d, c_d, '[]'), 'disponivel', 'diarista', c_d - (extract(isodow from c_d)::int - 1));
  m := jsonb_build_array(
         jsonb_build_object('payee_id', v_p[1], 'nome', 'Alfa', 'dia', c_d, 'turno', 'tarde', 'presenca', 'turno'),
         jsonb_build_object('payee_id', v_p[2], 'nome', 'Beta', 'dia', c_d, 'turno', 'manha', 'presenca', 'turno'),
         jsonb_build_object('payee_id', v_p[3], 'nome', 'Gama', 'dia', c_d, 'turno', 'manha', 'presenca', 'turno'),
         jsonb_build_object('payee_id', v_p[4], 'nome', 'Delta', 'dia', c_d, 'turno', 'manha', 'presenca', 'turno'),
         jsonb_build_object('payee_id', v_dono, 'nome', 'Dono', 'dia', c_d, 'turno', 'manha', 'presenca', 'turno'));
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), m, c_d);
  v_res := pg_temp.ok(v_res, 'P8n disponibilidade_suposta: Gama (o padrão que ele mesmo disse) e Alfa (a semente), na ordem do 1º meio-dia; Beta (o padrão do dono), Delta (a semana dita) e o dono, não',
                      s = '[{"codigo": "disponibilidade_suposta", "detalhe": {"pessoas": ["Gama", "Alfa"]}}]'::jsonb, s::text);

  -- quanto_falta_padrao: os dias gravados quando a pergunta do "quanto falta?" venceu sem resposta (o caminho de verdade: _agenda_gestor_gravar_dias)
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, versao_base, modo, criada_em)
  values ('situacao', 'situacao:p8:' || v_os, v_os, array[v_os], 'Teste P8: quanto falta?',
          '[{"n": 1, "texto": "1,5 dia", "efeito": {"dias": 1.5}}, {"n": 2, "texto": "Eu digo"}]'::jsonb, 1, cf.versao_plano, 'ligado', now())
  returning id into v_q;
  update public.agenda_perguntas set estado = 'resolvida', opcao_escolhida = 1, resolvida_motivo = 'sem resposta até qui 12/11 18:00: ficou como eu disse' where id = v_q;
  perform public._agenda_gestor_gravar_dias(v_os, 1.5, 'Sem resposta (teste P8)', v_q, now());
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('fonte', 'orcamento', 'dias', 9, 'equipe_dita', true)), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8o quanto_falta_padrao: os dias gravados pelo prazo (1,5), antes da duração pelo orçamento',
                      s -> 0 = '{"codigo": "quanto_falta_padrao", "detalhe": {"dias": 1.5}}'::jsonb and s -> 1 ->> 'codigo' = 'duracao_orcamento'
                      and jsonb_array_length(s) = 2, s::text);
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('fonte', 'sugerida', 'dias', 9, 'equipe_dita', true)), '[]'::jsonb, c_d);
  v := s::text;
  -- a 2ª: resolvida sem opção (a condição mudou: não foi o prazo)
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, versao_base, modo, criada_em)
  values ('situacao', 'situacao:p8b:' || v_os, v_os, array[v_os], 'Teste P8: quanto falta? (2)',
          '[{"n": 1, "texto": "2 dias", "efeito": {"dias": 2}}, {"n": 2, "texto": "Eu digo"}]'::jsonb, 1, cf.versao_plano, 'ligado', now())
  returning id into v_q;
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'não precisa mais: mudou o que falta saber' where id = v_q;
  perform public._agenda_gestor_gravar_dias(v_os, 2, 'Teste P8 (2)', v_q, now() + interval '1 minute');
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('fonte', 'orcamento', 'dias', 9, 'equipe_dita', true)), '[]'::jsonb, c_d);
  v_res := pg_temp.ok(v_res, 'P8o2 quanto_falta_padrao não entra com a última pergunta resolvida sem opção (a condição mudou; não foi o prazo)',
                      s -> 0 ->> 'codigo' = 'duracao_orcamento' and jsonb_array_length(s) = 1, s::text);
  -- a 3ª: respondida pelo dono
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, versao_base, modo, criada_em)
  values ('situacao', 'situacao:p8c:' || v_os, v_os, array[v_os], 'Teste P8: quanto falta? (3)',
          '[{"n": 1, "texto": "2,5 dias", "efeito": {"dias": 2.5}}, {"n": 2, "texto": "Eu digo"}]'::jsonb, 1, cf.versao_plano, 'ligado', now())
  returning id into v_q;
  update public.agenda_perguntas set estado = 'respondida', respondida_em = now(), opcao_escolhida = 1 where id = v_q;
  perform public._agenda_gestor_gravar_dias(v_os, 2.5, 'Teste P8 (3)', v_q, now() + interval '2 minutes');
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object('meios', jsonb_build_object('fonte', 'orcamento', 'dias', 9, 'equipe_dita', true)), '[]'::jsonb, c_d);
  v := v || ' ' || (s -> 0 ->> 'codigo');
  v_res := pg_temp.ok(v_res, 'P8p quanto_falta_padrao não entra com a fonte de agora sugerida, nem com a pergunta respondida pelo dono', v = '[] duracao_orcamento', v);

  -- bem_disponivel: o barco num dia de temporada, sem nada dito sobre o uso dele
  select so.id into v_os2 from public.service_orders so
   where public._agenda_classe_de_campo(so.id) ->> 'bem' = 'barco' and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = so.id)
   order by so.service_order_number, so.id limit 1;
  if v_os2 is null or not (12 = any (cf.temporada_meses)) or 7 = any (cf.temporada_meses) then
    v_res := pg_temp.ok(v_res, 'P8q bem_disponivel', false, 'sem OS de barco, ou dezembro fora / julho dentro da temporada');
  else
    m := jsonb_build_array(jsonb_build_object('payee_id', v_p[1], 'dia', '2026-12-10', 'turno', 'manha', 'presenca', 'turno'));
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), m, c_d);
    v := (s @> '[{"codigo": "bem_disponivel", "detalhe": {"bem": "barco"}}]')::text;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)),
                                         jsonb_build_array(jsonb_build_object('payee_id', v_p[1], 'dia', '2026-07-10', 'turno', 'manha')), c_d);
    v := v || ' ' || (s @> '[{"codigo": "bem_disponivel"}]')::text;
    insert into public.os_planejamento (service_order_id, precisa_ate) values (v_os2, date '2026-12-20');
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), m, c_d);
    v := v || ' ' || (s @> '[{"codigo": "bem_disponivel"}]')::text;
    update public.os_planejamento set precisa_ate = null, bem_indisponivel = '{[2027-01-04,2027-01-09)}' where service_order_id = v_os2;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), m, c_d);
    v := v || ' ' || (s @> '[{"codigo": "bem_disponivel"}]')::text;
    update public.os_planejamento set bem_indisponivel = '{}' where service_order_id = v_os2;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), m, c_d);
    v := v || ' ' || (s @> '[{"codigo": "bem_disponivel"}]')::text;
    delete from public.os_planejamento where service_order_id = v_os2;
    v_res := pg_temp.ok(v_res, 'P8q bem_disponivel: o barco em dezembro (temporada) sem nada dito; em julho, não; com o precisa_ate dito, não; com dias fora ditos, não; com a linha sem nada dito, sim',
                        v = 'true false false false true', v);
  end if;

  -- local_suposto: como o motor, só com um modo do local ligado de verdade (sem o freio); com o freio, em teste: não
  select so.id, public._agenda_local_resolvido(so.id, c_d) into v_os2, v_lr from public.service_orders so
   where (public._agenda_local_resolvido(so.id, c_d) ->> 'suposicao')::boolean and public._agenda_local_resolvido(so.id, c_d) ->> 'fonte' in ('patio', 'cidade', 'bem')
     and nullif(btrim(public._agenda_local_resolvido(so.id, c_d) ->> 'texto_curto'), '') is not null
   order by so.service_order_number, so.id limit 1;
  if v_os2 is null then
    v_res := pg_temp.ok(v_res, 'P8r local_suposto', false, 'sem OS com o local suposto');
  else
    update public.agenda_config set modo_local_calendario = 'desligado', modo_patio = 'desligado', modo_viagem = 'desligado', modo_mesmo_local = 'desligado',
                                    gestor_so_propor = false where id;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), '[]'::jsonb, c_d);
    v := (s @> '[{"codigo": "local_suposto"}]')::text;
    update public.agenda_config set modo_local_calendario = 'ligado', gestor_so_propor = true where id;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), '[]'::jsonb, c_d);
    v := v || ' ' || (s @> '[{"codigo": "local_suposto"}]')::text;
    update public.agenda_config set gestor_so_propor = false where id;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), '[]'::jsonb, c_d);
    v_res := pg_temp.ok(v_res, 'P8r local_suposto: só com o modo do local ligado de verdade; com o lugar (com a preposição), a fonte e, pelo cadastro, o bem',
                        v = 'false false' and s @> jsonb_build_array(jsonb_build_object('codigo', 'local_suposto', 'detalhe',
                              jsonb_build_object('local', btrim(v_lr ->> 'texto_curto'), 'fonte', v_lr ->> 'fonte')
                              || case when v_lr ->> 'fonte' = 'bem' then jsonb_build_object('bem', case public._agenda_classe_de_campo(v_os2) ->> 'bem'
                                   when 'rv' then 'motorhome' when 'barco' then 'barco' else 'bem' end) else '{}'::jsonb end)),
                        v || ' / ' || s::text);
    -- os outros 3 modos, um por vez
    foreach v in array array['modo_patio', 'modo_viagem', 'modo_mesmo_local'] loop
      update public.agenda_config set modo_local_calendario = 'desligado', modo_patio = 'desligado', modo_viagem = 'desligado', modo_mesmo_local = 'desligado' where id;
      execute format('update public.agenda_config set %I = ''ligado'' where id', v);
      s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), '[]'::jsonb, c_d);
      v_res := pg_temp.ok(v_res, 'P8s local_suposto também com ' || v || ' ligado', s @> '[{"codigo": "local_suposto"}]', s::text);
    end loop;
  end if;

  -- o local que não é suposição: o mesmo OS do P8r, com o local dito pelo dono (fonte dono): não entra, com o modo ligado de verdade
  if v_os2 is not null and v_lr is not null then
    update public.agenda_config set modo_local_calendario = 'ligado', gestor_so_propor = false where id;
    -- (sem local nenhum na bancada, um de teste)
    if (v_lr ->> 'local_id') is null and not exists (select 1 from public.agenda_locais x where x.ativo) then
      insert into public.agenda_locais (nome, tipo, municipio, uf) values ('Porto de teste P8', 'marina', 'Cidade de teste', 'SC');
    end if;
    insert into public.os_planejamento (service_order_id, local_id, local_fonte, local_em)
    values (v_os2, coalesce((v_lr ->> 'local_id')::uuid, (select x.id from public.agenda_locais x where x.ativo order by x.nome, x.id limit 1)), 'dono', now())
    on conflict (service_order_id) do update set local_id = excluded.local_id, local_fonte = 'dono', local_em = now();
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), '[]'::jsonb, c_d);
    v_res := pg_temp.ok(v_res, 'P8r2 o local dito pelo dono (fonte ' || coalesce(public._agenda_local_resolvido(v_os2, c_d) ->> 'fonte', '?') || ', sem suposição): não entra',
                        public._agenda_local_resolvido(v_os2, c_d) ->> 'fonte' = 'dono' and not s @> '[{"codigo": "local_suposto"}]', s::text);
  else
    v_res := pg_temp.ok(v_res, 'P8r2 o local dito pelo dono', false, 'sem a OS do P8r');
  end if;
  -- o local do cadastro do barco: a marina do barco que é local, com a OS sem marina, não é suposição (fonte bem); a OS com outra marina que não virou local, é
  select so.id into v_os2 from public.service_orders so
   where so.vessel_id is not null and so.marina_id is null
   order by so.service_order_number, so.id limit 1;
  if v_os2 is null or (select count(*) from public.marinas) < 2 then
    v_res := pg_temp.ok(v_res, 'P8r3 o local do cadastro do barco', false, 'sem OS com barco e sem marina, ou menos de 2 marinas');
  else
    update public.agenda_config set modo_local_calendario = 'ligado', gestor_so_propor = false where id;
    delete from public.os_planejamento where service_order_id = v_os2 and local_id is not null;
    update public.vessels set marina_id = (select m.id from public.marinas m order by m.id limit 1)
     where id = (select so.vessel_id from public.service_orders so where so.id = v_os2);
    insert into public.agenda_locais (nome, tipo, municipio, uf, marina_id)
    values ('Marina de teste P8', 'marina', 'Cidade de teste', 'SC', (select m.id from public.marinas m order by m.id limit 1))
    on conflict (marina_id) do nothing;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), '[]'::jsonb, c_d);
    v := coalesce(public._agenda_local_resolvido(v_os2, c_d) ->> 'fonte', '?') || ':' || coalesce(public._agenda_local_resolvido(v_os2, c_d) ->> 'suposicao', '?')
         || ' ' || (s @> '[{"codigo": "local_suposto"}]')::text;
    update public.service_orders set marina_id = (select m.id from public.marinas m order by m.id offset 1 limit 1) where id = v_os2;
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)), '[]'::jsonb, c_d);
    v := v || ' / ' || coalesce(public._agenda_local_resolvido(v_os2, c_d) ->> 'fonte', '?') || ':' || coalesce(public._agenda_local_resolvido(v_os2, c_d) ->> 'suposicao', '?')
         || ' ' || coalesce((select e -> 'detalhe' ->> 'fonte' || ',' || coalesce(e -> 'detalhe' ->> 'bem', '-') from jsonb_array_elements(s) e where e ->> 'codigo' = 'local_suposto'), 'sem');
    v_res := pg_temp.ok(v_res, 'P8r3 o local pelo cadastro do barco: a marina do barco que é local (fonte bem, sem suposição) não entra; com a OS numa marina que não virou local (fonte bem, suposição) entra, com o bem',
                        v ~ '^bem:false false / bem:true bem,(barco|motorhome|bem)$', v);
  end if;
  -- a presença do dono pela regra que não é o abre e fecha (sempre: diagnóstico, comissionamento, marina nova): "você abre e fecha" seria falso
  select so.id into v_os2 from public.service_orders so
   where public.os_presenca_do_dono(so.id) ->> 'presenca' = 'sempre' and public.os_presenca_do_dono(so.id) ->> 'fonte' = 'regra'
   order by so.service_order_number, so.id limit 1;
  if v_os2 is null then
    v_res := pg_temp.ok(v_res, 'P8m2 a presença sempre pela regra', false, 'sem OS com a presença sempre pela regra');
  else
    s := public._agenda_suposicoes_da_os(v_os2, jsonb_build_object('meios', jsonb_build_object('equipe_dita', true)),
                                         jsonb_build_array(jsonb_build_object('payee_id', v_dono, 'dia', c_d, 'turno', 'tarde', 'presenca', 'fechamento')), c_d);
    v_res := pg_temp.ok(v_res, 'P8m2 a presença do dono pela regra do "sempre": dono_abre_fecha não entra', not s @> '[{"codigo": "dono_abre_fecha"}]', s::text);
  end if;

  -- a ordem do §3.1-3 com vários juntos (9 dos 12: o local da OS de base é suposto pela cidade, com o calendário ligado acima), e a saída passa no CHECK da alocação
  s := public._agenda_suposicoes_da_os(v_os, jsonb_build_object(
         'pront', jsonb_build_object('restricoes', jsonb_build_array(jsonb_build_object('tipo', 'sem_peca_suposta'), jsonb_build_object('tipo', 'sinal')),
                                     'material', jsonb_build_object('itens', jsonb_build_array(
                                       jsonb_build_object('situacao', 'falta', 'separar_vespera', true),
                                       jsonb_build_object('curto', 'Cerbo', 'situacao', 'falta', 'classe', 'padrao', 'critico', true, 'prazo_du', 7,
                                                          'compra_firme', true, 'compre_ate', '2026-11-05')))),
         'meios', jsonb_build_object('fonte', 'orcamento', 'dias', 2, 'equipe_dita', false)), a1, c_d);
  select string_agg(e ->> 'codigo', ',' order by o) into v from jsonb_array_elements(s) with ordinality t(e, o);
  v_res := pg_temp.ok(v_res, 'P8t a ordem do §3.1-3 (a do "1 motivo") e a saída passa no CHECK das suposições',
                      v = 'prazo_padrao_peca,local_suposto,disponibilidade_suposta,compra_interna_padrao,sinal_a_cobrar,duracao_orcamento,uma_pessoa,peca_nao_segura,sem_peca'
                      and public._agenda_suposicoes_validas(s), v);
  raise exception using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('P8 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$p8$;

-- ── M1c. Nenhuma chamada nova fora da gravação; a falha não derruba o motor ──────────────────────────
do $m1$
declare
  v_res jsonb := '[]'::jsonb;
  v_n   int;
  v_p   jsonb;
  v     text;
  v_sim text;
begin
  if pg_temp.os('OS-00074') is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'M1c', true, 'PULADO: sem o replay de 29/10 (rode pela bancada)'));
    return;
  end if;
  update public.agenda_config set modo_porque = 'sombra' where id;
  v_sim := md5(pg_temp.cenario('sombra', false)::text);
  execute $q$create or replace function public._agenda_suposicoes_da_os(p_os uuid, p_info jsonb, p_alocs jsonb, p_hoje date) returns jsonb language plpgsql stable
             set search_path to 'public' as $b$ begin raise exception 'M1c: _agenda_suposicoes_da_os foi chamada' using errcode = 'P0001'; end; $b$$q$;
  select count(*) into v_n from public.app_error_logs where action = 'explicar:porque';
  -- a simulação em sombra não a chama: sem erro, a mesma saída, nada registrado
  begin
    v := md5(pg_temp.cenario('sombra', false)::text);
  exception when others then v := 'erro: ' || sqlerrm;
  end;
  v_res := pg_temp.ok(v_res, 'M1c-a a simulação em sombra não chama as suposições (a mesma saída, nada registrado)',
                      v = v_sim and (select count(*) from public.app_error_logs where action = 'explicar:porque') = v_n, v);
  -- a vigia roda sem erro
  begin
    perform public.agenda_vigiar(date '2026-10-29', timestamptz '2026-10-29 16:52-03');
    v := 'rodou';
  exception when others then v := 'erro: ' || sqlerrm;
  end;
  v_res := pg_temp.ok(v_res, 'M1c-b a vigia em sombra roda sem erro com a função que lança', v = 'rodou', v);
  -- o controle que morde: gravando, ela é chamada; o motor segue, o item fica sem porque, a alocação nula, e o erro fica registrado
  begin
    v_p := pg_temp.cenario('sombra', true);
    v := 'rodou';
  exception when others then v := 'erro: ' || sqlerrm;
  end;
  v_res := pg_temp.ok(v_res, 'M1c-c controle: gravando, a falha é pega (o motor segue), o item fica sem porque e a alocação sem suposições, e o erro fica registrado',
                      v = 'rodou'
                      and not exists (select 1 from jsonb_array_elements(v_p -> 'itens') i where i ? 'porque')
                      and not exists (select 1 from public.agenda_alocacoes a where a.proposta_id = (v_p ->> 'proposta_id')::uuid and a.suposicoes is not null)
                      and exists (select 1 from public.agenda_alocacoes a where a.proposta_id = (v_p ->> 'proposta_id')::uuid)
                      and (select count(*) from public.app_error_logs where action = 'explicar:porque') > v_n,
                      v || ' ' || (select count(*) from public.app_error_logs where action = 'explicar:porque') || ' registro(s)');
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('M1c o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$m1$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
