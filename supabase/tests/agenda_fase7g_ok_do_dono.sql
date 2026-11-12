-- Prova do "espera o seu ok", Fase 7g (pacote P5b; migration 20261112100700; spec-fase7g §3.1 item 8, §5.5, §6.4, §8.3 K4 a K10 e o bloco R9: R9.4-4 e os 7
-- pontos, R9.5-23 a 25, R9.6, R9.12, R9.13 — "K4 a K9 da spec, mais os 7 pontos de R9.4-4, com freio × espera (a reserva fica) e OS sem linha"; o K10 que o P5
-- deixou: a ação nivel no "o que mudou").
-- bancada: depende de 20261112100700
--
-- O cenário: o de hoje do P2 do lote (a fixture-2310, qui 29/10/2026, Roberto e João na equipe), com OS novas de motorhome com "Troca do inversor" (a classe de
-- campo rv:energia, "energia em motorhome"), aprovadas, sinal pago, material conferido e os dias pelo orçamento (os_planejamento.estimativa_fonte orcamento, 2 dias,
-- Roberto o dia todo): OS-00950 (Nelson), OS-00951 (Otávio), OS-00952 (Paulo), OS-00953 (Quirino, SEM linha em os_planejamento). Os modos que o P5b precisa
-- (modo_proposta, modo_rebaixar, modo_veto e modo_marcar_sozinho ligados, o freio solto) são ligados aqui, em cada bloco, e cada bloco desfaz o que fez.
--
--   K0  o catálogo: as 4 novas (search_path, volatilidade, invoker, as portas); as 11 recriadas: tiradas as marcas do P5b, o corpo da origem (md5); a migration
--       como texto cria só as 4 e recria só as 11; as 3 listas; critica com ok_marcacao; as 3 colunas e os CHECKs de os_planejamento
--   K1  _agenda_espera_ok: OS sem linha = não (ponto 2); modo cru (ponto 5: com o freio, sim); sem o veto ou sem o rebaixar ligado, não (K9); com o ok, não
--   K4  a classe (pontos 1, 3, 4): só depois de nada mais segurar e com fonte orcamento; a condição (ponto 6); o motor reserva com ok_do_dono; a pergunta nasce 1 vez,
--       com o padrão da 7f; a tela; a saúde (ok_sem_pergunta); a pergunta em *agenda pendências* (K10b); freio × espera (a reserva fica)
--   K5  decidir 1 (o ok e a reserva vira compromisso) e 2 (solta, pergunta os dias, não reserva de novo); o *desfaz <nome>* depois do ok volta a reserva e o "espero o
--       seu ok", sem a vigia promover de novo (K5k a K5n, NOVO-agenda-297)
--   K6  o prazo da 7f vence → a opção 1 (ok_do_dono_via = prazo); sem ok_marcacao em veto_tipos, não vence
--   K7  o tipo de OS: 3 de 4 corrigidas → espera_ok (a ação nivel, o espera_ok_desde das OS da classe sem dia, também a sem linha); 2× = 1×; a volta com 3 aceitas
--   K8  *desfaz espera* depois de 24 h (ponto 7) e a trava; sem nenhuma em espera
--   K9  sem o veto ligado, ou com o freio: só teria (nenhum nível muda)
--   K10 a ação nivel no "o que mudou" (_agenda_mudancas, sem recriar)
--   K11 a rodada: o passo ok a cada tique (também cedo), sem linha; a saúde nivel_sem_aviso
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Seguro em produção: termina em ROLLBACK. O que usa o cenário ou a migration como texto só roda na bancada (fora dela sai PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_visto text, p_esperado text) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, p_visto is not distinct from p_esperado,
           case when p_visto is distinct from p_esperado then 'veio: ' || coalesce(p_visto, '(null)') end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- o corpo sem os blocos do P5b (o tirador do montador, linha a linha)
create function pg_temp.sem_p5b(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(p, E'\n') loop
    if not v_dentro and l ~ '^\s*-- FASE 7g: \(7g P5b' then v_dentro := true; continue; end if;
    if v_dentro and l ~ '^\s*-- FASE 7g: fim\s*$' then v_dentro := false; continue; end if;
    if v_dentro then continue; end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
create function pg_temp.agora(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- os modos do P5b: o motor publica, o gestor marca sozinho, o veto e o rebaixar ligados, o freio solto
create function pg_temp.ligar() returns void language sql as $f$
  update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_rebaixar = 'ligado', modo_veto = 'ligado',
         modo_marcar_sozinho = 'ligado', gestor_so_propor = false where id
$f$;
-- uma OS de motorhome com "Troca do inversor" (rv:energia), aprovada, sinal pago; com p_linha, os dias pelo orçamento (2) com o Roberto e o material conferido
create function pg_temp.os_nova(p_n int, p_nome text, p_linha boolean default true) returns uuid language plpgsql as $f$
declare
  v_os  uuid := ('05000000-0000-4000-8000-000000000' || p_n)::uuid;
  v_cli uuid := ('c4000000-0000-4000-8000-000000000' || p_n)::uuid;
  v_bem uuid := ('f4000000-0000-4000-8000-000000000' || p_n)::uuid;
begin
  insert into public.clients (id, type, name) values (v_cli, 'individual', p_nome);
  insert into public.vessels (id, client_id, name, asset_type) values (v_bem, v_cli, 'Motorhome ' || p_nome, 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at,
                                     converted_to_os_at, grand_total)
  values (v_os, 'OS-00' || p_n, v_cli, v_bem, 'approved', 'approved', 'repair', timestamptz '2026-10-28 12:00-03', timestamptz '2026-10-28 12:00-03',
          timestamptz '2026-10-28 12:00-03', 2160);
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (md5('7g:p5b:servico:' || p_n)::uuid, v_os, '5e000000-0000-4000-8000-000000000003', 'Troca do inversor', 'unit', 1, 2160, 2160,
          timestamptz '2026-10-28 12:00-03');
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount, balance_amount, is_deposit)
  values (md5('7g:p5b:sinal:' || p_n)::uuid, v_cli, v_os, 'Sinal OS-00' || p_n, date '2026-10-28', date '2026-10-28', 500, 'paid', 500, 0, true);
  if p_linha then
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, material_conferido_em)
    values (v_os, 2, 'orcamento', timestamptz '2026-10-28 18:00-03', timestamptz '2026-10-28 18:00-03');
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_os, 'bb000000-0000-4000-8000-000000000002', 'dia');
  end if;
  return v_os;
end $f$;
-- os meios-dias vigentes da OS: 'dia turno tipo condicao' (ordenados)
create function pg_temp.alocs(p_os uuid) returns text language sql as $f$
  select coalesce(string_agg(format('%s %s %s %s', a.dia, a.turno, a.tipo, coalesce(a.condicao_tipo, '-')), ' | ' order by a.dia, a.turno, a.tipo), '(nada)')
    from public.agenda_alocacoes a where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.presenca = 'turno'
$f$;
-- uma marcação decidida do gestor na classe (a ação e a linha de agenda_marcacoes, na forma do P5)
create function pg_temp.marcacao(p_os uuid, p_k text, p_desfecho text, p_em timestamptz) returns void language plpgsql as $f$
declare
  v_acao uuid := md5('7g:p5b:acao:' || p_k)::uuid;
begin
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (v_acao, p_em - interval '5 days', ((p_em - interval '5 days') at time zone 'America/Sao_Paulo')::date, true, 'vigia', 'criar', p_os, array[p_os],
          '{}'::jsonb, '{}'::jsonb, 'Ação de teste ' || p_k);
  insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, duracao_fonte, de, ate, meios, pessoas, marcada_em,
                                       primeiro_inicio, desfecho, ajustes, desfecho_em)
  values (v_acao, p_os, 'gestor', 'vigia', 'criar', 'rv:energia', 'orcamento', (p_em at time zone 'America/Sao_Paulo')::date,
          (p_em at time zone 'America/Sao_Paulo')::date, 2, array['bb000000-0000-4000-8000-000000000002'::uuid], p_em - interval '5 days', p_em,
          p_desfecho, case when p_desfecho = 'ajustada' then array['dia'] else '{}'::text[] end, p_em);
end $f$;

-- ── K0. O catálogo ──────────────────────────────────────────────────────────────────────────────────
do $k0$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  v_mig text := coalesce(current_setting('agenda_teste.mig_ok_fase7g', true), '');
  v_nomes text[];
begin
  select string_agg(format('%s(%s,%s,%s,%s)', p.proname, p.provolatile::text, p.prosecdef, p.proconfig::text,
                           (select string_agg(r.rolname || ':' || has_function_privilege(r.rolname, p.oid, 'execute'), ',' order by r.rolname)
                              from pg_roles r where r.rolname in ('anon', 'authenticated', 'service_role'))), ' ' order by p.proname)
    into v_dif
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('_agenda_espera_ok', '_agenda_explicar_ok', '_agenda_ok_decidir', '_agenda_desfazer_nivel');
  v_res := pg_temp.igual(v_res, 'K0a as 4 novas: search_path fixo, invoker; _agenda_espera_ok STABLE com a porta de authenticated (a cadeia de _agenda_classe_da_os); as outras 3 VOLATILE só service_role',
    v_dif,
    '_agenda_desfazer_nivel(v,f,{search_path=public},anon:false,authenticated:false,service_role:true) '
    || '_agenda_espera_ok(s,f,{search_path=public},anon:false,authenticated:true,service_role:true) '
    || '_agenda_explicar_ok(v,f,{search_path=public},anon:false,authenticated:false,service_role:true) '
    || '_agenda_ok_decidir(v,f,{search_path=public},anon:false,authenticated:false,service_role:true)');
  select string_agg(p.proname, ',' order by p.proname) into v_dif
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('_agenda_espera_ok', '_agenda_explicar_ok', '_agenda_ok_decidir', '_agenda_desfazer_nivel')
     and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0);
  v_res := pg_temp.ok(v_res, 'K0a2 nenhuma das 4 com execute para PUBLIC', v_dif is null, v_dif);
  -- as 11 recriadas: tiradas as marcas do P5b, o corpo da origem (o md5 do R9.1 nas 7 da tabela; o da 7g, fixado pelo montador, nas 4 do P5, P6 e P7)
  select string_agg(format('%s: %s', t.n, md5(pg_temp.sem_p5b(p.prosrc))), '; ' order by t.n) into v_dif
    from (values ('_agenda_classe_da_os', '06aa24fb0049f269d39787434c3aceeb'), ('_agenda_condicao_da_reserva', '63b22e85a316102edad939f2e57ae53c'),
                 ('_agenda_padrao_da_pergunta', '4c2024d1cb4ed7f252e09adaa7351615'), ('_agenda_modo_da_pergunta', '40a78627108f025a6caaa035df768927'),
                 ('agenda_decidir', '108125fc0e603c9f9077d019f6767809'), ('agenda_desfazer', '7a138b9382d5fc4289de0b770a70fa55'),
                 ('agenda_desfazer_dito', 'f90e5d978ac75a1e05c56f2bb128042d'), ('_agenda_explicar_tipos', 'c43c683a81b2419c4470f7f511d2a731'),
                 ('agenda_explicar_rodar', '49c8737529162699e8c26e9b7aa1e769'), ('_agenda_saude_explicar', '1be352347492cf36427707bd3ca87606'),
                 ('agenda_tela_semana', '1491d1fc43940ccf0d0a6dd8cbdf3a9a')) t(n, h)
    join pg_proc p on p.proname = t.n and p.pronamespace = 'public'::regnamespace
   where md5(pg_temp.sem_p5b(p.prosrc)) <> t.h or p.prosrc not like '%-- FASE 7g: (7g P5b%';
  v_res := pg_temp.ok(v_res, 'K0b as 11 recriadas têm o bloco do P5b e, sem ele, são a origem byte a byte (md5 do corpo)', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'K0b2 o tirador morde: o corpo vivo, com o bloco, não é a origem',
    (select md5(p.prosrc) from pg_proc p where p.proname = 'agenda_decidir' and p.pronamespace = 'public'::regnamespace) <> '108125fc0e603c9f9077d019f6767809', null);
  -- as listas, a crítica e as colunas
  v_res := pg_temp.ok(v_res, 'K0c as 3 listas: ok_marcacao nas perguntas, ok_do_dono na condição, nivel nas ações',
    (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'agenda_perguntas_tipo_check') like '%''ok_marcacao''%'
    and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'agenda_alocacoes_condicao_tipo_check') like '%''ok_do_dono''%'
    and (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'agenda_acoes_tipo_check') like '%''nivel''%', null);
  v_res := pg_temp.ok(v_res, 'K0d a coluna gerada critica tem ok_marcacao e ainda tem acesso (a expressão da 7d copiada)',
    (select pg_get_expr(d.adbin, d.adrelid) from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica') ~ '''ok_marcacao''.*'
    and (select pg_get_expr(d.adbin, d.adrelid) from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
          where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica') like '%''acesso''%', null);
  select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull, ',' order by a.attname) into v_dif
    from pg_attribute a where a.attrelid = 'public.os_planejamento'::regclass and a.attname in ('espera_ok_desde', 'ok_do_dono_em', 'ok_do_dono_via') and not a.attisdropped;
  v_res := pg_temp.igual(v_res, 'K0e os_planejamento: as 3 colunas, nulas', v_dif,
    'espera_ok_desde:timestamp with time zone:false,ok_do_dono_em:timestamp with time zone:false,ok_do_dono_via:text:false');
  begin
    insert into public.os_planejamento (service_order_id, ok_do_dono_em) values ((select id from public.service_orders order by id limit 1), now())
    on conflict (service_order_id) do update set ok_do_dono_em = excluded.ok_do_dono_em;
    v_dif := 'passou';
  exception when check_violation then
    get stacked diagnostics v_dif = constraint_name;
  end;
  v_res := pg_temp.igual(v_res, 'K0f o ok sem a via é recusado (os_planejamento_ok_coerente)', v_dif, 'os_planejamento_ok_coerente');
  begin
    insert into public.os_planejamento (service_order_id, ok_do_dono_em, ok_do_dono_via) values ((select id from public.service_orders order by id limit 1), now(), 'talvez')
    on conflict (service_order_id) do update set ok_do_dono_em = excluded.ok_do_dono_em, ok_do_dono_via = excluded.ok_do_dono_via;
    v_dif := 'passou';
  exception when check_violation then
    get stacked diagnostics v_dif = constraint_name;
  end;
  v_res := pg_temp.igual(v_res, 'K0g a via fora de dono/prazo é recusada', v_dif, 'os_planejamento_ok_do_dono_via_check');
  -- veto_tipos aceita ok_marcacao (R9.4-4 ponto 1: o CHECK da 7f é a lista dos que nunca vencem)
  begin
    update public.agenda_config set veto_tipos = veto_tipos || '{ok_marcacao}' where id;
    v_dif := 'passou';
    raise exception 'desfaz' using errcode = 'P0099';
  exception
    when sqlstate 'P0099' then null;
    when check_violation then get stacked diagnostics v_dif = constraint_name;
  end;
  v_res := pg_temp.igual(v_res, 'K0h veto_tipos aceita ok_marcacao (ponto 1)', v_dif, 'passou');
  -- a migration como texto: cria só as 4 e recria só as 11
  if v_mig = '' then
    v_res := pg_temp.ok(v_res, 'K0i a migration cria as 4 e recria as 11', true, 'PULADO: sem a migration como texto (rode pela bancada)');
  else
    v_nomes := array(select distinct m[1] from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m order by 1);
    v_res := pg_temp.igual(v_res, 'K0i a migration cria as 4 e recria só as 11 (nenhuma outra: R9.1 "Não recriar")', array_to_string(v_nomes, ','),
      '_agenda_classe_da_os,_agenda_condicao_da_reserva,_agenda_desfazer_nivel,_agenda_espera_ok,_agenda_explicar_ok,_agenda_explicar_tipos,_agenda_modo_da_pergunta,'
      || '_agenda_ok_decidir,_agenda_padrao_da_pergunta,_agenda_saude_explicar,agenda_decidir,agenda_desfazer,agenda_desfazer_dito,agenda_explicar_rodar,agenda_tela_semana');
  end if;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('K0 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$k0$;

-- ── K1 e K4 (a classe e a condição pelas funções puras) ─────────────────────────────────────────────
do $k1$
declare
  v_res  jsonb := '[]'::jsonb;
  v_os   uuid := gen_random_uuid();
  v_pr   jsonb;
  v_c    jsonb;
  v_t    text := '';
begin
  -- uma prontidão pronta (nada a segurar) para uma OS qualquer, e os meios pelo orçamento
  v_pr := jsonb_build_object('ok', true, 'os', v_os, 'estado', 'pronta', 'estado_texto', 'pronto', 'restricoes', '[]'::jsonb,
                             'material', jsonb_build_object('estado', 'completo', 'itens', '[]'::jsonb));
  perform pg_temp.ligar();
  -- K1: a OS sem linha em os_planejamento (ponto 2)
  v_res := pg_temp.ok(v_res, 'K1a OS sem linha em os_planejamento: não espera (coalesce por fora, ponto 2)', public._agenda_espera_ok(v_os) = false, null);
  v_c := public._agenda_classe_da_os(v_pr, '{"fonte": "orcamento", "total": 4}'::jsonb, date '2026-10-29');
  v_res := pg_temp.igual(v_res, 'K1b e a classe dela é a de antes: 2, pronta', v_c ->> 'classe' || ' ' || (v_c ->> 'motivo'), '2 pronta');
  -- com a linha (a OS precisa existir: uma da fixture)
  v_os := (select so.id from public.service_orders so where not exists (select 1 from public.os_planejamento pl where pl.service_order_id = so.id) order by so.id limit 1);
  v_pr := jsonb_set(v_pr, '{os}', to_jsonb(v_os));
  insert into public.os_planejamento (service_order_id, espera_ok_desde) values (v_os, timestamptz '2026-10-28 19:00-03');
  v_res := pg_temp.ok(v_res, 'K1c com espera_ok_desde e os 3 modos ligados: espera', public._agenda_espera_ok(v_os), null);
  update public.agenda_config set gestor_so_propor = true where id;
  v_res := pg_temp.ok(v_res, 'K1d com *gestor, só propor*: continua esperando (o modo cru, R9.6 e ponto 5)', public._agenda_espera_ok(v_os), null);
  update public.agenda_config set gestor_so_propor = false, modo_veto = 'sombra' where id;
  v_res := pg_temp.ok(v_res, 'K1e com o veto em sombra: não espera (K9: age como sombra)', not public._agenda_espera_ok(v_os), null);
  update public.agenda_config set modo_veto = 'ligado', modo_rebaixar = 'sombra' where id;
  v_res := pg_temp.ok(v_res, 'K1f com o rebaixar em sombra: não espera', not public._agenda_espera_ok(v_os), null);
  update public.agenda_config set modo_rebaixar = 'ligado', modo_marcar_sozinho = 'sombra' where id;
  v_res := pg_temp.ok(v_res, 'K1g com o gestor marcando em sombra: não espera', not public._agenda_espera_ok(v_os), null);
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
  update public.os_planejamento set ok_do_dono_em = now(), ok_do_dono_via = 'dono' where service_order_id = v_os;
  v_res := pg_temp.ok(v_res, 'K1h com o ok dado: não espera', not public._agenda_espera_ok(v_os), null);
  update public.os_planejamento set ok_do_dono_em = null, ok_do_dono_via = null where service_order_id = v_os;

  -- K4: a classe (pontos 1, 3, 4)
  v_c := public._agenda_classe_da_os(v_pr, '{"fonte": "orcamento", "total": 4}'::jsonb, date '2026-10-29');
  v_res := pg_temp.igual(v_res, 'K4a pronta pelo orçamento e esperando: classe 3, motivo espera, condição ok_do_dono, "espero o seu ok" (a OS vem de p_pront ->> os)',
    v_c::text, '{"texto": "espero o seu ok", "classe": 3, "motivo": "espera", "condicoes": ["ok_do_dono"], "condicao_tipo": "ok_do_dono"}');
  v_c := public._agenda_classe_da_os(v_pr, '{"fonte": "dono", "total": 4}'::jsonb, date '2026-10-29');
  v_res := pg_temp.igual(v_res, 'K4b com os dias ditos pelo dono (fonte dono): a de antes, classe 2 (só a fonte orcamento espera, ponto 3)', v_c ->> 'classe', '2');
  v_c := public._agenda_classe_da_os(jsonb_set(v_pr, '{material}', '{"estado": "nao_conferido", "itens": []}'::jsonb), '{"fonte": "orcamento", "total": 4}'::jsonb, date '2026-10-29');
  v_res := pg_temp.igual(v_res, 'K4c com outra condição (o material a conferir): a condição de antes, não a do ok (o teste só depois de v_cond vazio, ponto 3)',
    v_c ->> 'classe' || ' ' || (v_c ->> 'condicao_tipo'), '3 conferir_material');
  v_res := pg_temp.igual(v_res, 'K4d o motivo espera já tem frase no "de fora" (ponto 4: não cai em "outro motivo")',
    public._agenda_gestor_motivo_texto('espera'), 'esperando a sua decisão');
  -- a opção 2 dada desde que a OS passou a esperar: espera os dias, sem reservar
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, recomendacao, modo, estado, opcao_escolhida, respondida_em, respondida_via)
  values ('ok_marcacao', 'ok_marcacao:k4:' || v_os, v_os, array[v_os], 'Pode marcar assim? 1) Pode marcar assim; 2) Não marca: eu digo os dias.',
          '[{"n": 1, "texto": "Pode marcar assim"}, {"n": 2, "texto": "Não marca: eu digo os dias"}]'::jsonb, 1, 'ligado', 'respondida', 2,
          timestamptz '2026-10-29 10:00-03', 'whatsapp');
  v_c := public._agenda_classe_da_os(v_pr, '{"fonte": "orcamento", "total": 4}'::jsonb, date '2026-10-29');
  v_res := pg_temp.igual(v_res, 'K4e depois do "Não marca" (a opção 2): classe 4 duracao, espera os dias do dono (não reserva de novo)',
    v_c ->> 'classe' || ' ' || (v_c ->> 'motivo'), '4 duracao');
  update public.os_planejamento set espera_ok_desde = timestamptz '2026-10-29 11:00-03' where service_order_id = v_os;
  v_c := public._agenda_classe_da_os(v_pr, '{"fonte": "orcamento", "total": 4}'::jsonb, date '2026-10-29');
  v_res := pg_temp.igual(v_res, 'K4f o "Não marca" de antes de a OS voltar a esperar não conta: de novo classe 3 ok_do_dono', v_c ->> 'condicao_tipo', 'ok_do_dono');

  -- K4 a condição (ponto 6): a véspera útil do 1º dia, nunca antes de hoje + veto_du + 1 dias úteis
  v_c := public._agenda_condicao_da_reserva(v_os, 'ok_do_dono', date '2026-11-16', v_pr, date '2026-10-29');
  v_res := pg_temp.igual(v_res, 'K4g a condição com o 1º dia longe (seg 16/11): até a véspera útil (sex 13/11)', v_c::text,
    '{"condicao": "se você der o ok até sex 13/11", "condicao_ate": "2026-11-13"}');
  v_c := public._agenda_condicao_da_reserva(v_os, 'ok_do_dono', date '2026-10-30', v_pr, date '2026-10-29');
  v_res := pg_temp.igual(v_res, 'K4h com o 1º dia amanhã (sex 30/10): nunca antes do prazo da pergunta mostrada no próximo dia útil (ter 03/11; seg 02 é Finados, ponto 6)',
    v_c ->> 'condicao_ate', '2026-11-03');
  v_res := pg_temp.ok(v_res, 'K4i e esse dia não é antes do prazo que a 7f daria à pergunta mostrada amanhã (_agenda_veto_ate de sex 30/10)',
    (v_c ->> 'condicao_ate')::date >= (public._agenda_veto_ate(pg_temp.agora(date '2026-10-30', '17:30')) at time zone 'America/Sao_Paulo')::date,
    (public._agenda_veto_ate(pg_temp.agora(date '2026-10-30', '17:30')))::text);
  v_c := public._agenda_condicao_da_reserva(v_os, 'duracao', date '2026-11-16', v_pr, date '2026-10-29');
  v_res := pg_temp.ok(v_res, 'K4j as outras condições, as de antes (duracao)', v_c ->> 'condicao' like 'se você confirmar os dias até %', v_c::text);
  -- o padrão da 7f para ok_marcacao (ponto 1, R8.5-2)
  v_res := pg_temp.igual(v_res, 'K4k o padrão de ok_marcacao: recomendação, opção; fora de veto_tipos, espera tipo',
    public._agenda_padrao_da_pergunta('ok_marcacao', true, v_os, '[{"n": 1}, {"n": 2}]'::jsonb, 1::smallint)::text,
    '{"chave": "recomendacao", "efeito": "opcao", "espera": "tipo"}');
  update public.agenda_config set veto_tipos = veto_tipos || '{ok_marcacao}' where id;
  v_res := pg_temp.igual(v_res, 'K4l com ok_marcacao em veto_tipos (o dado 100990): pode vencer pelo prazo',
    public._agenda_padrao_da_pergunta('ok_marcacao', true, v_os, '[{"n": 1}, {"n": 2}]'::jsonb, 1::smallint)::text,
    '{"chave": "recomendacao", "efeito": "opcao", "espera": null}');
  update public.os_planejamento set prometido_tipo = 'firme', prometido_ate = date '2026-11-20' where service_order_id = v_os;
  v_res := pg_temp.igual(v_res, 'K4m com dia dito ao cliente: espera o dono (AG7-15)',
    public._agenda_padrao_da_pergunta('ok_marcacao', true, v_os, '[{"n": 1}, {"n": 2}]'::jsonb, 1::smallint) ->> 'espera', 'cliente');
  v_res := pg_temp.igual(v_res, 'K4n ok_marcacao é do modo_rebaixar, cru (R9.5-23)', public._agenda_modo_da_pergunta('ok_marcacao', 'ok_marcacao:x'), 'ligado');
  update public.agenda_config set gestor_so_propor = true where id;
  v_res := pg_temp.igual(v_res, 'K4o com o freio, o modo da pergunta continua ligado (a aberta segue respondível)',
    public._agenda_modo_da_pergunta('ok_marcacao', 'ok_marcacao:x'), 'ligado');
  raise exception 'desfaz' using errcode = 'P0099';
exception
  when sqlstate 'P0099' then perform pg_temp.gravar(v_res);
  when others then perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('K1/K4 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$k1$;

-- ── K4 a K6 pelo motor, no cenário de hoje (29/10) ──────────────────────────────────────────────────
do $m$
declare
  c_hoje  constant date := date '2026-10-29';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_fix   boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                     and exists (select 1 from public.services where id = '5e000000-0000-4000-8000-000000000003');
  v_res   jsonb := '[]'::jsonb;
  v_os    uuid;
  v_os2   uuid;
  v_r     jsonb;
  v_q     public.agenda_perguntas;
  v_t     text;
  v_n     int;
begin
  if not v_fix then
    perform pg_temp.gravar(pg_temp.ok('[]', 'K4–K6 o motor', true, 'PULADO: sem a fixture-2310 (rode pela bancada)'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);

  -- ── K4: a reserva ok_do_dono e a pergunta ──
  begin
    perform pg_temp.ligar();
    v_os := pg_temp.os_nova(950, 'Nelson');
    update public.os_planejamento set espera_ok_desde = timestamptz '2026-10-28 19:00-03' where service_order_id = v_os;
    v_r := public._agenda_propor_e_aplicar('os', array[v_os], 'vigia', null, c_hoje, pg_temp.agora(c_hoje, '17:40'));
    v_res := pg_temp.igual(v_res, 'K4p o motor só reserva, com a condição ok_do_dono (ter 03 e qua 04/11, o Roberto; a condição até ter 03/11)', pg_temp.alocs(v_os),
      '2026-11-03 manha reserva ok_do_dono | 2026-11-03 tarde reserva ok_do_dono | 2026-11-04 manha reserva ok_do_dono | 2026-11-04 tarde reserva ok_do_dono');
    v_res := pg_temp.igual(v_res, 'K4q a condição da reserva', (select string_agg(distinct a.condicao || ' / ' || a.condicao_ate, ',') from public.agenda_alocacoes a
                                                                   where a.service_order_id = v_os and a.estado = 'publicada'),
      'se você der o ok até ter 03/11 / 2026-11-03');
    -- a saúde antes da pergunta: a reserva tem mais de 30 minutos sem ela
    v_r := public._agenda_saude_explicar(c_hoje, pg_temp.agora(c_hoje, '18:20'));
    v_res := pg_temp.ok(v_res, 'K4r a saúde: a reserva ok_do_dono sem a pergunta há mais de 30 min acende ok_sem_pergunta (e zeros_ok falso)',
      (v_r ->> 'ok_sem_pergunta')::int = 1 and not (v_r ->> 'zeros_ok')::boolean, v_r::text);
    v_r := public._agenda_explicar_ok(c_hoje, pg_temp.agora(c_hoje, '17:45'));
    v_res := pg_temp.igual(v_res, 'K4s o passo ok: 1 pergunta criada', v_r::text, '{"criadas": 1, "fechadas": 0}');
    v_r := public._agenda_explicar_ok(c_hoje, pg_temp.agora(c_hoje, '18:00'));
    v_res := pg_temp.igual(v_res, 'K4t 2× = 1×: nenhuma a mais', v_r::text, '{"criadas": 0, "fechadas": 0}');
    select * into v_q from public.agenda_perguntas where tipo = 'ok_marcacao' and service_order_id = v_os;
    v_res := pg_temp.igual(v_res, 'K4u a pergunta: crítica, ligada, a chave, o dia, a perda, as opções, a recomendação e o padrão da 7f (fora de veto_tipos: espera tipo)',
      format('%s|%s|%s|%s|%s|%s|%s|%s/%s/%s', v_q.critica, v_q.modo, v_q.chave, v_q.dia, v_q.perda_em, v_q.opcoes, v_q.recomendacao, v_q.padrao_chave,
             v_q.padrao_efeito, v_q.veto_espera),
      't|ligado|ok_marcacao:05000000-0000-4000-8000-000000000950:2026-10-29|2026-11-03|2026-11-03|[{"n": 1, "texto": "Pode marcar assim"}, {"n": 2, "texto": "Não marca: eu digo os dias"}]|1|recomendacao/opcao/tipo');
    v_res := pg_temp.igual(v_res, 'K4v o texto da pergunta (§6.4)', v_q.texto,
      'Reservei Nelson (OS-00950) de ter 03 e qua 04/11 com Roberto (2 dias pelo orçamento, estimativa minha). Nas OS de energia em motorhome eu espero o seu ok. 1) Pode marcar assim (recomendo); 2) Não marca: eu digo os dias.');
    v_r := public._agenda_saude_explicar(c_hoje, pg_temp.agora(c_hoje, '18:20'));
    v_res := pg_temp.igual(v_res, 'K4w a saúde com a pergunta: ok_sem_pergunta 0', v_r ->> 'ok_sem_pergunta', '0');
    -- a tela: "Reserva, esperando o seu ok"
    select string_agg(distinct b ->> 'reserva_texto', ',') into v_t
      from jsonb_array_elements(public.agenda_tela_semana(date '2026-11-02', c_hoje, pg_temp.agora(c_hoje, '17:45')) -> 'dias') d, jsonb_array_elements(d -> 'blocos') b
     where b ->> 'os' = v_os::text;
    v_res := pg_temp.igual(v_res, 'K4x a Semana: os blocos da reserva dizem "Reserva, esperando o seu ok" (§5.7)', v_t, 'Reserva, esperando o seu ok');
    -- K10b a pergunta entra na ordem das perguntas (o lote da 7f e *agenda pendências*)
    v_res := pg_temp.ok(v_res, 'K10b a pergunta está em agenda_perguntas_em_ordem (o lote da 7f, *agenda pendências*)',
      exists (select 1 from jsonb_array_elements(public.agenda_perguntas_em_ordem(c_hoje, pg_temp.agora(c_hoje, '17:50'))) e where (e ->> 'id')::uuid = v_q.id), null);
    -- freio × espera (ponto 5): com *gestor, só propor*, a vigia não promove a reserva, e ela fica
    update public.agenda_config set gestor_so_propor = true where id;
    v_r := public._agenda_vigia_reservas(c_hoje, pg_temp.agora(c_hoje, '18:00'));
    v_res := pg_temp.ok(v_res, 'K4y freio × espera: com *gestor, só propor* a vigia não promove (a classe continua 3) e a reserva fica (ponto 5)',
      (v_r ->> 'promovidas')::int = 0 and pg_temp.alocs(v_os) like '2026-11-03 manha reserva ok_do_dono%', v_r::text || ' ' || pg_temp.alocs(v_os));
    -- e o prazo não decide com o freio (a porta da 7f): a pergunta segue aberta
    v_r := public.agenda_decidir(v_q.id, 1::smallint, null, 'prazo', null, c_hoje, pg_temp.agora(c_hoje, '18:05'));
    v_res := pg_temp.ok(v_res, 'K4z com o freio, o prazo não decide (a porta da 7f) e a pergunta fica aberta',
      not (v_r ->> 'ok')::boolean and (select estado from public.agenda_perguntas where id = v_q.id) = 'aberta', v_r::text);
    update public.agenda_config set gestor_so_propor = false where id;

    -- ── K5: decidir 1 ──
    v_r := public.agenda_decidir(v_q.id, 1::smallint, c_admin, 'whatsapp', '1', c_hoje, pg_temp.agora(c_hoje, '18:10'));
    v_res := pg_temp.igual(v_res, 'K5a decidir 1: "Combinado: … fica marcado de … com …" (§6.4)', v_r ->> 'texto',
      'Combinado: Nelson (OS-00950) fica marcado de ter 03 e qua 04/11 com Roberto.');
    v_res := pg_temp.igual(v_res, 'K5b o ok gravado (via dono) e a reserva virou compromisso pela porta (a reserva cancelada como promovida)',
      (select format('%s %s', ok_do_dono_em is not null, ok_do_dono_via) from public.os_planejamento where service_order_id = v_os) || ' | ' || pg_temp.alocs(v_os)
      || ' | ' || (select string_agg(distinct a.cancelada_motivo, ',') from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado = 'cancelada'),
      't dono | 2026-11-03 manha execucao - | 2026-11-03 tarde execucao - | 2026-11-04 manha execucao - | 2026-11-04 tarde execucao - | promovida');
    v_res := pg_temp.igual(v_res, 'K5c a pergunta respondida (1, pelo WhatsApp, com o autor) e a OS não espera mais',
      (select format('%s %s %s %s', estado, opcao_escolhida, respondida_via, respondida_por = c_admin) from public.agenda_perguntas where id = v_q.id)
      || ' ' || public._agenda_espera_ok(v_os), 'respondida 1 whatsapp t false');
    v_r := public.agenda_decidir(v_q.id, 1::smallint, c_admin, 'whatsapp', '1', c_hoje, pg_temp.agora(c_hoje, '18:11'));
    v_res := pg_temp.igual(v_res, 'K5d de novo: já respondida, nada muda', v_r ->> 'texto', 'Essa pergunta já foi respondida ou resolvida.');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── K5k a K5n (fechamento, NOVO-agenda-297): o *desfaz* depois do ok volta a reserva E o "espero o seu ok" ──
  -- Antes, o ok ficava e a vigia promovia a reserva de novo no tique seguinte (com o mesmo "*desfaz <nome>* volta como estava"). A pergunta nasce às 14:00 de ter
  -- 27/10: a reserva que o *desfaz* devolve nasce com criado_em = now(), que na bancada é o relógio fixo (27/10 15:00, andando); em produção o now() do *desfaz*
  -- vem sempre depois da pergunta respondida, e é isso que deixa a pergunta nascer de novo.
  begin
    perform pg_temp.ligar();
    v_os := pg_temp.os_nova(954, 'Rui');
    update public.os_planejamento set espera_ok_desde = timestamptz '2026-10-27 10:00-03' where service_order_id = v_os;
    perform public._agenda_propor_e_aplicar('os', array[v_os], 'vigia', null, c_hoje, pg_temp.agora(c_hoje, '17:40'));
    perform public._agenda_explicar_ok(c_hoje, timestamptz '2026-10-27 14:00-03');
    select * into v_q from public.agenda_perguntas where tipo = 'ok_marcacao' and service_order_id = v_os;
    v_r := public.agenda_decidir(v_q.id, 1::smallint, c_admin, 'whatsapp', '1', c_hoje, pg_temp.agora(c_hoje, '18:10'));
    v_res := pg_temp.igual(v_res, 'K5k0 (o cenário) decidir 1: a reserva virou compromisso', (v_r ->> 'texto') || ' | ' || pg_temp.alocs(v_os),
      'Combinado: Rui (OS-00954) fica marcado de ter 03 e qua 04/11 com Roberto. | 2026-11-03 manha execucao - | 2026-11-03 tarde execucao - | 2026-11-04 manha execucao - | 2026-11-04 tarde execucao -');
    v_r := public.agenda_desfazer_dito(c_admin, 'Rui', 'whatsapp', c_hoje, pg_temp.agora(c_hoje, '18:20'));
    v_res := pg_temp.igual(v_res, 'K5k *desfaz Rui* depois do ok: a reserva volta e o texto diz que volto a esperar o ok', v_r ->> 'texto',
      'Desfeito: a reserva do Rui (OS-00954) volta como estava. Volto a esperar o seu ok antes de marcar.');
    v_res := pg_temp.igual(v_res, 'K5l o ok sai (ok_do_dono_em e ok_do_dono_via nulos), espera_ok_desde fica, a reserva ok_do_dono volta e a OS espera de novo (classe 3 espera)',
      (select format('%s %s %s', ok_do_dono_em is null, ok_do_dono_via is null, espera_ok_desde is not null) from public.os_planejamento where service_order_id = v_os)
      || ' ' || public._agenda_espera_ok(v_os) || ' ' || (public._agenda_classe_agora(v_os, c_hoje) ->> 'classe') || ' '
      || (public._agenda_classe_agora(v_os, c_hoje) ->> 'motivo') || ' | ' || pg_temp.alocs(v_os),
      't t t true 3 espera | 2026-11-03 manha reserva ok_do_dono | 2026-11-03 tarde reserva ok_do_dono | 2026-11-04 manha reserva ok_do_dono | 2026-11-04 tarde reserva ok_do_dono');
    v_r := public._agenda_vigia_reservas(c_hoje, pg_temp.agora(c_hoje, '18:35'));
    v_res := pg_temp.ok(v_res, 'K5m a vigia do tique seguinte não promove a reserva de novo (promovidas 0; a reserva fica)',
      (v_r ->> 'promovidas')::int = 0 and pg_temp.alocs(v_os) like '2026-11-03 manha reserva ok_do_dono%', v_r::text || ' ' || pg_temp.alocs(v_os));
    v_r := public._agenda_explicar_ok(c_hoje, pg_temp.agora(c_hoje, '18:36'));
    v_res := pg_temp.igual(v_res, 'K5n o passo ok pergunta de novo "Pode marcar assim?" (1 criada, aberta, ligada) e a saúde fica sem ok_sem_pergunta',
      v_r::text || ' ' || (select count(*) from public.agenda_perguntas q where q.tipo = 'ok_marcacao' and q.service_order_id = v_os and q.estado = 'aberta' and q.modo = 'ligado')
      || ' ' || (public._agenda_saude_explicar(c_hoje, pg_temp.agora(c_hoje, '18:40')) ->> 'ok_sem_pergunta'),
      '{"criadas": 1, "fechadas": 0} 1 0');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── K5: decidir 2 (o "Não marca: eu digo os dias") e a opção que não existe ──
  begin
    perform pg_temp.ligar();
    v_os := pg_temp.os_nova(951, 'Otávio');
    update public.os_planejamento set espera_ok_desde = timestamptz '2026-10-28 19:00-03' where service_order_id = v_os;
    perform public._agenda_propor_e_aplicar('os', array[v_os], 'vigia', null, c_hoje, pg_temp.agora(c_hoje, '17:40'));
    perform public._agenda_explicar_ok(c_hoje, pg_temp.agora(c_hoje, '17:45'));
    select * into v_q from public.agenda_perguntas where tipo = 'ok_marcacao' and service_order_id = v_os;
    v_r := public.agenda_decidir(v_q.id, 3::smallint, c_admin, 'whatsapp', '3', c_hoje, pg_temp.agora(c_hoje, '18:10'));
    v_res := pg_temp.igual(v_res, 'K5e a opção que não existe: a recusa diz as opções, nada muda', v_r ->> 'texto',
      'Essa opção não existe. As opções são: 1) Pode marcar assim; 2) Não marca: eu digo os dias.');
    v_r := public.agenda_decidir(v_q.id, 2::smallint, c_admin, 'whatsapp', '2', c_hoje, pg_temp.agora(c_hoje, '18:10'));
    v_res := pg_temp.igual(v_res, 'K5f decidir 2: "Certo: tirei a reserva de Otávio. Me diga quantos dias e com quem (está em *agenda pendências*)." (§6.4)', v_r ->> 'texto',
      'Certo: tirei a reserva de Otávio. Me diga quantos dias e com quem (está em *agenda pendências*).');
    v_res := pg_temp.igual(v_res, 'K5g a reserva solta (motivo dono), a ação soltar_reserva do dono, crítica, com a pergunta e sem desfazer',
      pg_temp.alocs(v_os) || ' | ' || (select string_agg(distinct a.cancelada_motivo, ',') from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado = 'cancelada')
      || ' | ' || (select format('%s %s %s %s %s', x.origem, x.tipo, x.critica, x.pergunta_id = v_q.id, x.desfazivel_ate is null) from public.agenda_acoes x where x.id = (v_r ->> 'acao_id')::uuid),
      '(nada) | dono | dono soltar_reserva t t t');
    v_res := pg_temp.igual(v_res, 'K5h a pergunta dos dias da OS aberta (duracao, ligada) e espera_ok_desde fica',
      (select format('%s %s', q.tipo, q.modo) from public.agenda_perguntas q where q.chave = 'duracao:' || v_os and q.estado = 'aberta')
      || ' ' || (select espera_ok_desde is not null from public.os_planejamento where service_order_id = v_os), 'duracao ligado true');
    v_r := public._agenda_classe_agora(v_os, c_hoje);
    v_res := pg_temp.igual(v_res, 'K5i e o motor não reserva de novo: classe 4 duracao até o dono dizer os dias', v_r ->> 'classe' || ' ' || (v_r ->> 'motivo'), '4 duracao');
    perform public._agenda_propor_e_aplicar('os', array[v_os], 'vigia', null, c_hoje, pg_temp.agora(c_hoje, '18:30'));
    v_r := public._agenda_explicar_ok(c_hoje, pg_temp.agora(c_hoje, '18:31'));
    v_res := pg_temp.igual(v_res, 'K5j o replano não reserva de novo, e o passo ok não pergunta de novo', pg_temp.alocs(v_os) || ' ' || v_r::text,
      '(nada) {"criadas": 0, "fechadas": 0}');
    -- K7 (a amostra): a resposta "Não marca" conta como desfeita para a classe
    perform pg_temp.marcacao(v_os, 'k5:a', 'aceita', pg_temp.agora(date '2026-10-26', '10:00'));
    v_r := public._agenda_explicar_tipos(c_hoje, pg_temp.agora(c_hoje, '18:40'));
    v_res := pg_temp.igual(v_res, 'K7a a amostra soma a resposta "Não marca" como desfeita (n 2, corrigidas 1; a pergunta marcada na amostra)',
      (select format('%s %s %s', t.n, t.corrigidas, t.amostra @> jsonb_build_array(jsonb_build_object('pergunta', true, 'desfecho', 'desfeita')))
         from public.agenda_tipos_os t where t.classe = 'rv:energia'), '2 1 t');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── K6: o prazo da 7f vence → a opção 1 ──
  begin
    perform pg_temp.ligar();
    update public.agenda_config set veto_tipos = veto_tipos || '{ok_marcacao}' where id;
    v_os := pg_temp.os_nova(952, 'Paulo');
    v_os2 := pg_temp.os_nova(953, 'Quirino', false);
    update public.os_planejamento set espera_ok_desde = timestamptz '2026-10-28 19:00-03' where service_order_id = v_os;
    perform public._agenda_propor_e_aplicar('os', array[v_os], 'vigia', null, c_hoje, pg_temp.agora(c_hoje, '17:40'));
    perform public._agenda_explicar_ok(c_hoje, pg_temp.agora(c_hoje, '17:45'));
    select * into v_q from public.agenda_perguntas where tipo = 'ok_marcacao' and service_order_id = v_os;
    -- mostrada no fechamento de hoje, com o prazo da 7a (sex 30/10 18:00)
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.agora(c_hoje, '17:50'), mostrada_via = 'fechamento',
           veto_ate = public._agenda_veto_ate(pg_temp.agora(c_hoje, '17:50'))
     where id = v_q.id;
    perform set_config('agenda.hoje', '2026-10-30', true);
    v_r := public._agenda_gestor_vetos(date '2026-10-30', pg_temp.agora(date '2026-10-30', '18:05'));
    select * into v_q from public.agenda_perguntas where id = v_q.id;
    v_res := pg_temp.igual(v_res, 'K6a o prazo venceu (sex 30/10 18:00, mostrada antes): a opção 1 pelo prazo; ok_do_dono_via = prazo; a reserva virou compromisso (o replano de sex 30/10 a põe em qua 04 e qui 05/11)',
      format('%s %s %s %s', v_q.estado, v_q.opcao_escolhida, v_q.respondida_via, v_q.assumida_por)
      || ' | ' || (select format('%s %s', ok_do_dono_em is not null, ok_do_dono_via) from public.os_planejamento where service_order_id = v_os)
      || ' | ' || pg_temp.alocs(v_os),
      'respondida 1 prazo prazo | t prazo | 2026-11-04 manha execucao - | 2026-11-04 tarde execucao - | 2026-11-05 manha execucao - | 2026-11-05 tarde execucao -');
    -- a OS SEM linha em os_planejamento (Quirino) e uma pergunta que nasceu fora de veto_tipos não vencem pelo prazo
    perform set_config('agenda.hoje', c_hoje::text, true);
    update public.agenda_config set veto_tipos = array_remove(veto_tipos, 'ok_marcacao') where id;
    insert into public.os_planejamento (service_order_id, espera_ok_desde) values (v_os2, timestamptz '2026-10-28 19:00-03');
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_os2, 'bb000000-0000-4000-8000-000000000002', 'dia');
    update public.os_planejamento set dias = 2, estimativa_fonte = 'orcamento', estimativa_em = timestamptz '2026-10-28 18:00-03',
           material_conferido_em = timestamptz '2026-10-28 18:00-03' where service_order_id = v_os2;
    perform public._agenda_propor_e_aplicar('os', array[v_os2], 'vigia', null, c_hoje, pg_temp.agora(c_hoje, '17:40'));
    perform public._agenda_explicar_ok(c_hoje, pg_temp.agora(c_hoje, '17:46'));
    select * into v_q from public.agenda_perguntas where tipo = 'ok_marcacao' and service_order_id = v_os2;
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.agora(c_hoje, '17:50'), mostrada_via = 'fechamento',
           veto_ate = public._agenda_veto_ate(pg_temp.agora(c_hoje, '17:50'))
     where id = v_q.id;
    perform set_config('agenda.hoje', '2026-10-30', true);
    perform public._agenda_gestor_vetos(date '2026-10-30', pg_temp.agora(date '2026-10-30', '18:05'));
    v_res := pg_temp.igual(v_res, 'K6b a linha que nasceu pelo insert … on conflict serve (a OS sem linha); fora de veto_tipos (espera tipo), o prazo não vence: aberta, a reserva fica',
      (select format('%s %s', q.estado, q.veto_espera) from public.agenda_perguntas q where q.id = v_q.id) || ' | ' || split_part(pg_temp.alocs(v_os2), ' | ', 1),
      'aberta tipo | 2026-11-03 manha reserva ok_do_dono');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('K4–K6 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$m$;

-- ── K7 a K11: o tipo de OS, o *desfaz espera*, o "o que mudou" e a rodada ───────────────────────────────
do $t$
declare
  c_hoje  constant date := date '2026-10-29';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_fix   boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                     and exists (select 1 from public.services where id = '5e000000-0000-4000-8000-000000000003');
  v_res   jsonb := '[]'::jsonb;
  v_os    uuid;
  v_sem   uuid;
  v_r     jsonb;
  v_t     public.agenda_tipos_os;
  v_a     public.agenda_acoes;
  v_txt   text;
begin
  if not v_fix then
    perform pg_temp.gravar(pg_temp.ok('[]', 'K7–K11 o tipo de OS', true, 'PULADO: sem a fixture-2310 (rode pela bancada)'));
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  begin
    update public.agenda_config set modo_porque = 'desligado' where id;
    v_os := pg_temp.os_nova(950, 'Nelson');
    v_sem := pg_temp.os_nova(953, 'Quirino', false);
    -- 4 decididas do gestor na classe nas 8 semanas: 1 aceita, 2 ajustadas, 1 desfeita (3 de 4 → espera_ok, AG7-25)
    perform pg_temp.marcacao(v_os, 't:1', 'aceita', pg_temp.agora(date '2026-10-19', '10:00'));
    perform pg_temp.marcacao(v_os, 't:2', 'ajustada', pg_temp.agora(date '2026-10-20', '10:00'));
    perform pg_temp.marcacao(v_os, 't:3', 'desfeita', pg_temp.agora(date '2026-10-21', '10:00'));
    perform pg_temp.marcacao(v_os, 't:4', 'ajustada', pg_temp.agora(date '2026-10-22', '10:00'));

    -- K9: com o veto em sombra, ou com o freio, só teria (o nível não muda)
    perform pg_temp.ligar();
    update public.agenda_config set modo_veto = 'sombra' where id;
    v_r := public._agenda_explicar_tipos(c_hoje, pg_temp.agora(c_hoje, '16:40'));
    select * into v_t from public.agenda_tipos_os where classe = 'rv:energia';
    v_res := pg_temp.igual(v_res, 'K9a com o veto em sombra: age como sombra (teria espera_ok, o nível sozinho, nenhuma ação nivel)',
      format('%s %s %s %s', v_t.teria, v_t.nivel, (select count(*) from public.agenda_acoes where tipo = 'nivel'), v_r), 'espera_ok sozinho 0 {"teria": 1, "classes": 1, "voltaram": 0, "espera_ok": 0}');
    update public.agenda_config set modo_veto = 'ligado', gestor_so_propor = true where id;
    v_r := public._agenda_explicar_tipos(c_hoje, pg_temp.agora(c_hoje, '16:41'));
    v_res := pg_temp.igual(v_res, 'K9b com *gestor, só propor*: também só teria (R9.6)',
      (select nivel from public.agenda_tipos_os where classe = 'rv:energia') || ' ' || (select count(*) from public.agenda_acoes where tipo = 'nivel'), 'sozinho 0');
    update public.agenda_config set gestor_so_propor = false where id;

    -- K7: a ida a espera_ok
    v_r := public._agenda_explicar_tipos(c_hoje, pg_temp.agora(c_hoje, '16:42'));
    select * into v_t from public.agenda_tipos_os where classe = 'rv:energia';
    select * into v_a from public.agenda_acoes where id = v_t.acao_id;
    v_res := pg_temp.igual(v_res, 'K7b ligado: a classe passa a esperar o ok (o retorno conta 1)', v_r ->> 'espera_ok' || ' ' || v_t.nivel || ' ' || (v_t.desde is not null),
      '1 espera_ok true');
    v_res := pg_temp.igual(v_res, 'K7c a ação nivel: vigia, executada, sem OS, antes/depois, desfazível (o *desfaz espera*)',
      format('%s %s %s %s %s %s', v_a.origem, v_a.executada, v_a.service_order_id is null, v_a.antes, v_a.depois, v_a.desfazivel_ate is not null),
      'vigia t t {"nivel": "sozinho", "classe": "rv:energia"} {"n": 4, "nivel": "espera_ok", "classe": "rv:energia", "corrigidas": 3} t');
    v_res := pg_temp.igual(v_res, 'K7d o texto da ação (§6.4)', v_a.texto,
      'Nas OS de energia em motorhome você corrigiu 3 das minhas últimas 4 marcações. A partir de agora, nelas eu reservo e espero o seu ok antes de valer (a equipe e o cliente só sabem depois). *desfaz espera* volta.');
    v_res := pg_temp.igual(v_res, 'K7e o texto da linha (o placar lê): o do nível, não o "Em teste"', v_t.texto,
      'Nas OS de energia em motorhome eu espero o seu ok antes de marcar, desde qui 29/10.');
    v_res := pg_temp.igual(v_res, 'K7f as OS da classe na carteira, sem dia marcado: espera_ok_desde, também a SEM linha (a linha nasce: insert … on conflict, ponto 2)',
      (select format('%s %s', count(*) filter (where pl.service_order_id = v_os and pl.espera_ok_desde is not null),
                     count(*) filter (where pl.service_order_id = v_sem and pl.espera_ok_desde is not null))
         from public.os_planejamento pl), '1 1');
    v_r := public._agenda_explicar_tipos(c_hoje, pg_temp.agora(c_hoje, '16:43'));
    v_res := pg_temp.igual(v_res, 'K7g 2× = 1×: nenhuma ação nivel a mais, o texto e o nível iguais',
      (select count(*) from public.agenda_acoes where tipo = 'nivel') || ' ' || (select nivel || ' ' || (texto = v_t.texto) from public.agenda_tipos_os where classe = 'rv:energia')
      || ' ' || (v_r ->> 'espera_ok'), '1 espera_ok true 0');
    -- K10: a ação nivel no "o que mudou" (_agenda_mudancas, sem recriar: origem vigia entra por b)
    v_res := pg_temp.ok(v_res, 'K10a a ação nivel aparece no "o que mudou" de hoje',
      public._agenda_mudancas(c_hoje, c_hoje, true, false, pg_temp.agora(c_hoje, '17:00'))::text like '%passo%esperar%'
      or public._agenda_mudancas(c_hoje, c_hoje, true, false, pg_temp.agora(c_hoje, '17:00'))::text like '%espero o seu ok%',
      left(public._agenda_mudancas(c_hoje, c_hoje, true, false, pg_temp.agora(c_hoje, '17:00'))::text, 300));
    -- K11: a saúde nivel_sem_aviso: 0 com a ação; plantado sem a ação, 1
    v_res := pg_temp.igual(v_res, 'K11a a saúde: nivel_sem_aviso 0 com a ação nivel', public._agenda_saude_explicar(c_hoje, pg_temp.agora(c_hoje, '17:00')) ->> 'nivel_sem_aviso', '0');

    -- K8: *desfaz espera* depois de 24 h (ponto 7) e a trava
    v_r := public.agenda_desfazer_dito(c_admin, 'espera', 'whatsapp', date '2026-10-31', pg_temp.agora(date '2026-10-31', '09:00'));
    v_res := pg_temp.igual(v_res, 'K8a *desfaz espera* 2 dias depois (passou o desfazivel_ate de 24 h): volta (§6.4, sem "salvo se você pedir")', v_r ->> 'texto',
      'Desfeito: volto a marcar sozinho nas OS de energia em motorhome. Não passo a esperar o seu ok nelas de novo por 28 dias.');
    select * into v_t from public.agenda_tipos_os where classe = 'rv:energia';
    v_res := pg_temp.igual(v_res, 'K8b o estado depois: sozinho, travado até 31/10 + 28, a ação desfeita, as OS sem espera_ok_desde',
      format('%s %s %s %s', v_t.nivel, v_t.travado_ate, (select desfeita_em is not null from public.agenda_acoes where id = v_t.acao_id),
             (select count(*) from public.os_planejamento where espera_ok_desde is not null)), 'sozinho 2026-11-28 t 0');
    v_res := pg_temp.igual(v_res, 'K8c a saúde depois do *desfaz*: nivel_sem_aviso 0', public._agenda_saude_explicar(c_hoje, pg_temp.agora(c_hoje, '17:00')) ->> 'nivel_sem_aviso', '0');
    v_r := public._agenda_explicar_tipos(date '2026-10-31', pg_temp.agora(date '2026-10-31', '16:40'));
    v_res := pg_temp.igual(v_res, 'K8d a trava: com a mesma amostra, a classe não volta a esperar (teria sozinho, nenhuma ação nova)',
      (select teria || ' ' || nivel from public.agenda_tipos_os where classe = 'rv:energia') || ' ' || (select count(*) from public.agenda_acoes where tipo = 'nivel'),
      'sozinho sozinho 1');
    v_r := public.agenda_desfazer_dito(c_admin, 'espera', 'whatsapp', date '2026-10-31', pg_temp.agora(date '2026-10-31', '09:05'));
    v_res := pg_temp.igual(v_res, 'K8e *desfaz espera* sem nenhuma em espera (ligado): "não tenho"', v_r ->> 'texto',
      'Não tenho tipo de serviço esperando o seu ok agora: eu marco sozinho em todos.');
    v_r := public.agenda_desfazer(v_t.acao_id, c_admin, 'dono', date '2026-10-31', pg_temp.agora(date '2026-10-31', '09:06'));
    v_res := pg_temp.igual(v_res, 'K8f o mesmo *desfaz* de novo: já desfeito', v_r ->> 'texto', 'Isso já foi desfeito.');
    update public.agenda_config set modo_rebaixar = 'desligado' where id;
    v_r := public.agenda_desfazer_dito(c_admin, 'espera', 'whatsapp', date '2026-10-31', pg_temp.agora(date '2026-10-31', '09:07'));
    v_res := pg_temp.ok(v_res, 'K8g desligado: "desfaz espera" segue o caminho de antes (agenda_acao_desfazivel)',
      v_r ->> 'status' is not distinct from (public.agenda_acao_desfazivel('espera', date '2026-10-31', pg_temp.agora(date '2026-10-31', '09:07')) ->> 'status')
      and v_r ->> 'texto' is not distinct from (public.agenda_acao_desfazivel('espera', date '2026-10-31', pg_temp.agora(date '2026-10-31', '09:07')) ->> 'texto'), v_r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- K7: a volta a sozinho com voltar_n aceitas seguidas; a volta não se desfaz
  begin
    update public.agenda_config set modo_porque = 'desligado' where id;
    perform pg_temp.ligar();
    v_os := pg_temp.os_nova(950, 'Nelson');
    perform pg_temp.marcacao(v_os, 'v:1', 'aceita', pg_temp.agora(date '2026-10-19', '10:00'));
    perform pg_temp.marcacao(v_os, 'v:2', 'ajustada', pg_temp.agora(date '2026-10-20', '10:00'));
    perform pg_temp.marcacao(v_os, 'v:3', 'desfeita', pg_temp.agora(date '2026-10-21', '10:00'));
    perform pg_temp.marcacao(v_os, 'v:4', 'ajustada', pg_temp.agora(date '2026-10-22', '10:00'));
    perform public._agenda_explicar_tipos(c_hoje, pg_temp.agora(c_hoje, '16:40'));
    -- 2 aceitas: não volta; a 3ª: volta
    perform pg_temp.marcacao(v_os, 'v:5', 'aceita', pg_temp.agora(date '2026-11-03', '10:00'));
    perform pg_temp.marcacao(v_os, 'v:6', 'aceita', pg_temp.agora(date '2026-11-04', '10:00'));
    v_r := public._agenda_explicar_tipos(date '2026-11-05', pg_temp.agora(date '2026-11-05', '16:40'));
    v_res := pg_temp.igual(v_res, 'K7h com 2 aceitas seguidas, continua esperando', (select nivel || ' ' || aceitas_seguidas from public.agenda_tipos_os where classe = 'rv:energia'),
      'espera_ok 2');
    perform pg_temp.marcacao(v_os, 'v:7', 'aceita', pg_temp.agora(date '2026-11-05', '10:00'));
    update public.os_planejamento set espera_ok_desde = timestamptz '2026-10-29 16:40-03' where service_order_id = v_os;
    v_r := public._agenda_explicar_tipos(date '2026-11-06', pg_temp.agora(date '2026-11-06', '16:40'));
    select * into v_t from public.agenda_tipos_os where classe = 'rv:energia';
    select * into v_a from public.agenda_acoes where id = v_t.acao_id;
    v_res := pg_temp.igual(v_res, 'K7i com 3 aceitas seguidas (voltar_n): volta a sozinho, a ação nivel de volta (§6.4), o espera_ok_desde das OS limpo',
      format('%s %s | %s | %s | %s', v_r ->> 'voltaram', v_t.nivel, v_a.texto, v_a.desfazivel_ate is null,
             (select count(*) from public.os_planejamento where espera_ok_desde is not null)),
      '1 sozinho | Nas OS de energia em motorhome as minhas últimas 3 marcações ficaram como fiz: volto a marcar sozinho nelas. Você continua podendo corrigir. | t | 0');
    v_r := public.agenda_desfazer(v_a.id, c_admin, 'dono', date '2026-11-06', pg_temp.agora(date '2026-11-06', '17:00'));
    v_res := pg_temp.ok(v_res, 'K7j a volta não se desfaz, e a recusa diz o caminho', not (v_r ->> 'ok')::boolean and v_r ->> 'texto' like 'Isso não se desfaz:%volto a esperar o seu ok.',
      v_r ->> 'texto');
    v_res := pg_temp.igual(v_res, 'K11b a saúde: nivel_sem_aviso 0 depois da volta', public._agenda_saude_explicar(date '2026-11-06', pg_temp.agora(date '2026-11-06', '17:00')) ->> 'nivel_sem_aviso', '0');
    update public.agenda_tipos_os set nivel = 'espera_ok', desde = pg_temp.agora(date '2026-11-06', '17:00') where classe = 'rv:energia';
    v_res := pg_temp.igual(v_res, 'K11c o controle: o nível em espera_ok sem a ação nivel que o pôs lá acende nivel_sem_aviso',
      public._agenda_saude_explicar(date '2026-11-06', pg_temp.agora(date '2026-11-06', '17:00')) ->> 'nivel_sem_aviso', '1');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- K11: a rodada: o passo ok a cada tique (também antes de explicar_hora), sem linha
  begin
    update public.agenda_config set modo_porque = 'desligado', modo_placar = 'desligado' where id;
    perform pg_temp.ligar();
    v_os := pg_temp.os_nova(950, 'Nelson');
    update public.os_planejamento set espera_ok_desde = timestamptz '2026-10-28 19:00-03' where service_order_id = v_os;
    perform public._agenda_propor_e_aplicar('os', array[v_os], 'vigia', null, c_hoje, pg_temp.agora(c_hoje, '09:00'));
    v_r := public.agenda_explicar_rodar(c_hoje, pg_temp.agora(c_hoje, '09:15'));
    v_res := pg_temp.igual(v_res, 'K11d a rodada cedo (09:15): o passo ok criou a pergunta, e a rodada não rodou nem gravou linha',
      format('%s %s %s', v_r, (select count(*) from public.agenda_perguntas where tipo = 'ok_marcacao'),
             (select count(*) from public.agenda_vigia_rodadas where rotina = 'explicar')),
      '{"cedo": true, "hora": "16:35:00", "rodou": false} 1 0');
    -- a reserva sai (a vigia soltou): no tique seguinte a pergunta fecha, e a rodada do dia leva o passo
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'condicao_vencida' where service_order_id = v_os and estado = 'publicada';
    v_r := public.agenda_explicar_rodar(c_hoje, pg_temp.agora(c_hoje, '16:40'));
    v_res := pg_temp.igual(v_res, 'K11e a pergunta sem a reserva fecha (resolvida, "a reserva saiu da agenda"); a rodada do dia leva contagens.ok',
      (select format('%s %s', estado, resolvida_motivo) from public.agenda_perguntas where tipo = 'ok_marcacao') || ' | ' || (v_r #>> '{contagens,ok}'),
      'resolvida a reserva saiu da agenda | {"criadas": 0, "fechadas": 1}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('K7–K11 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$t$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
