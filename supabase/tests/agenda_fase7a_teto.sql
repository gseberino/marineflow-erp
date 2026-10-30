-- Prova do teto da equipe-semana do gestor da agenda, Fase 7a (pacote P5): cada técnico até 100% do que se espera dele, a equipe
-- inteira até a carga da semana (arredonda uma vez, na soma), e o gancho do sábado de manhã (migration 20261031100400), sobre a
-- carteira REAL de 29/10 (o replay), a sintética da 7a e duas OS deste teste (Zeca e Ivo) na semana de 23/11.
-- bancada: depende de 20261031100400
--
--   T0 as portas e o que é (sem fixture): as 5 recriadas com a mesma assinatura, volatilidade e portas de antes (o contexto, o
--      bloco, o encaixe e o porquê só do service_role; o validador para authenticated e service_role; nunca anon); nenhuma nova
--   T1 o caso que só cabe com o teto da equipe (semana de 23/11: João 4,25 e Roberto 2 esperados — por pessoa 3 + 1 = 4; a
--      equipe, floor(0,8 × 6,25) = 5): o contexto (teto80 = teto100 para a equipe; teto_equipe 5) e o motor (o Zeca, 5 meios-dias
--      de 1 pessoa, cabe de seg 23 a qua 25/11 só com o teto da equipe; sem ele, vai de qui 26 a seg 30/11)
--   T2 a equipe não passa do teto: com o Zeca na semana, o Ivo (meio dia) vai para seg 30/11; com o Zeca publicado, o porquê de
--      não caber na qui 26/11 é "a equipe já está com a semana cheia" (o João ainda tem 1 dos 4 dele) — e não com o pedido do
--      dono (teto100) nem sem o portão
--   T3 o dono com o teto dele: com a linha do dono (seg a sex), o teto dele continua floor(carga dele × esperado), ele fica fora
--      do teto da equipe e o motor não o põe em vaga de técnico; o validador cobra o teto dele
--   T4 o validador (regra 6 nova) recusa o que o encaixe recusaria: a proposta do motor passa; sem o portão, o Roberto passaria do
--      limite; o Ivo na mesma semana do Zeca = "A equipe passaria do limite da semana de 23/11: 6 meios-dias de serviço para 5.";
--      com acima_da_carga ou com o pedido do dono, não; o motor com o portão nunca monta proposta que o validador recusa
--   T5 com o portão falso (desligado, sombra sem a simulação, *gestor, só propor*, sem a regra teto_equipe) o contexto (cada
--      semana, uma e duas), o motor (a semana, a carteira, o Zeca e o Ivo), o validador e o porquê são os de antes, byte a byte (as
--      definições de antes postas no lugar, numa subtransação desfeita); o controle: com o portão, diferem
--   T6 a manhã de sábado (AG7-08): só com a variável agenda.sabado = 'on', só com sabado_manha diferente de 'nunca', só de quem tem
--      o padrão de sábado e não tem exceção no dia; a tarde fica sem ninguém; o esperado e os tetos não mudam; o sábado já útil e
--      o sábado sem ninguém não mudam; o encaixe usa a manhã; o validador ainda não (o aviso ao P12)
--   T7 as cópias: _agenda_contexto e _agenda_validar_itens (de 20261029100400), _agenda_tentar_bloco e _agenda_por_que_nao (de
--      20261025100200) e _agenda_encaixar (de 20261030100200) sem os blocos "-- FASE 7:"; a saída repetida do contexto com o
--      portão (só teto80 e teto_equipe mudam, chave a chave)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7a_teto.sql
--   Seguro em produção: T0 e T7a (as cópias saem PULADO sem as migrations como texto) só leem; T1 a T6 e T7b usam as fixtures e
--   só rodam na bancada (fora dela saem PULADO). Termina em ROLLBACK.
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

-- A OS pelo número (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;

-- A função inteira (do "create or replace" ao "$function$;") e só o corpo, a partir do texto da migration.
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;

-- O corpo sem os blocos "-- FASE 7: … -- FASE 7: fim" (o fim lido pelo prefixo).
create function pg_temp.sem_fase7(p_corpo text) returns text language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 7:' and l !~ '^\s*-- FASE 7: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 7: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return array_to_string(v_b, E'\n');
end $f$;

-- As células "criar" de uma OS numa proposta: "23/11 manha Roberto turno | …".
create function pg_temp.cel(p_r jsonb, p_numero text) returns text language sql immutable as $f$
  select coalesce(string_agg(to_char((a ->> 'dia')::date, 'DD/MM') || ' ' || (a ->> 'turno') || ' ' || (a ->> 'nome') || ' ' || (a ->> 'presenca'),
                             ' | ' order by (a ->> 'dia')::date, a ->> 'turno' = 'tarde', a ->> 'nome'), '-')
    from jsonb_array_elements(coalesce(p_r -> 'itens', '[]'::jsonb)) i, jsonb_array_elements(i -> 'alocacoes') a
   where i ->> 'numero' = p_numero and i ->> 'op' = 'criar'
$f$;
-- Os textos da regra 6 de uma lista de violações, na ordem.
create function pg_temp.regra6(p_v jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(e ->> 'texto', ' | ' order by o), '-')
    from jsonb_array_elements(coalesce(p_v, '[]'::jsonb)) with ordinality t(e, o) where (e ->> 'regra')::int = 6
$f$;
-- A posição (de 1) de uma pessoa no contexto do motor, pelo nome.
create function pg_temp.idx(p_ctx jsonb, p_nome text) returns int language sql immutable as $f$
  select o::int from jsonb_array_elements_text(p_ctx -> 'nomes') with ordinality t(n, o) where n = p_nome
$f$;
-- O valor de um array do contexto na pessoa e semana (de 1).
create function pg_temp.na(p_ctx jsonb, p_chave text, p_nome text, p_semana int default 1) returns numeric language sql immutable as $f$
  select (p_ctx -> p_chave ->> ((pg_temp.idx(p_ctx, p_nome) - 1) * (p_ctx ->> 'nw')::int + p_semana - 1))::numeric
$f$;
-- O motor sem gravar nada, como a vigia o chama.
create function pg_temp.propor(p_escopo text, p_os uuid[] default null, p_restr jsonb default '{}'::jsonb) returns jsonb
language sql as $f$
  select public.agenda_propor(p_escopo, null, null, p_os, p_restr, false, 'motor', null, date '2026-10-29',
                              timestamptz '2026-10-29 16:52-03')
$f$;

-- O cenário da semana de 23/11, por cima do replay e da sintética: o Roberto vem só na seg 23/11 (exceção "vem" no dia e "não vem"
-- de ter a sex: 2 meios-dias esperados; o João continua com a semente, 4,25), e duas OS prontas de 1 pessoa (mão de obra abaixo de
-- uma diária), sem o dono, com os dias ditos: Zeca (OS-97101, 2,5 dias = 5 meios-dias, aprovada antes) e Ivo (OS-97102, meio dia).
create function pg_temp.cenario() returns void language plpgsql as $f$
declare
  v_rob uuid;
  v_adm uuid;
begin
  select id into strict v_rob from public.payees where name = 'Roberto' and active;
  select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
  insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por) values
    (v_rob, daterange(date '2026-11-23', date '2026-11-23', '[]'), 'disponivel', 'dono', 'teste 7a P5: vem seg 23/11', v_adm),
    (v_rob, daterange(date '2026-11-24', date '2026-11-27', '[]'), 'indisponivel', 'dono', 'teste 7a P5: não vem de ter 24 a sex 27/11', v_adm);
  insert into public.clients (id, type, name) values ('f7a50000-0000-4000-8000-000000000101', 'individual', 'Zeca'),
                                                     ('f7a50000-0000-4000-8000-000000000102', 'individual', 'Ivo');
  insert into public.vessels (id, client_id, name, asset_type) values
    ('f7a50000-0000-4000-8000-000000000201', 'f7a50000-0000-4000-8000-000000000101', 'Motorhome', 'Motorhome'),
    ('f7a50000-0000-4000-8000-000000000202', 'f7a50000-0000-4000-8000-000000000102', 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     created_at, updated_at, converted_to_os_at) values
    ('f7a50000-0000-4000-8000-000000097101', 'OS-97101', 'f7a50000-0000-4000-8000-000000000101', 'f7a50000-0000-4000-8000-000000000201',
     'open', 'approved', 'repair', timestamptz '2026-10-20 10:00-03', timestamptz '2026-10-23 10:00-03', timestamptz '2026-10-23 10:00-03'),
    ('f7a50000-0000-4000-8000-000000097102', 'OS-97102', 'f7a50000-0000-4000-8000-000000000102', 'f7a50000-0000-4000-8000-000000000202',
     'open', 'approved', 'repair', timestamptz '2026-10-20 11:00-03', timestamptz '2026-10-24 10:00-03', timestamptz '2026-10-24 10:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at) values
    (md5('f7a5:servico:97101')::uuid, 'f7a50000-0000-4000-8000-000000097101', null, 'Revisão do quadro 12 V', 'unit', 1, 700, 700,
     timestamptz '2026-10-20 10:00-03'),
    (md5('f7a5:servico:97102')::uuid, 'f7a50000-0000-4000-8000-000000097102', null, 'Troca de tomada', 'unit', 1, 300, 300,
     timestamptz '2026-10-20 11:00-03');
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em) values
    ('f7a50000-0000-4000-8000-000000097101', 2.5, 'dono', timestamptz '2026-10-28 18:00-03', 'nunca', timestamptz '2026-10-28 18:00-03'),
    ('f7a50000-0000-4000-8000-000000097102', 0.5, 'dono', timestamptz '2026-10-28 18:00-03', 'nunca', timestamptz '2026-10-28 18:00-03');
end $f$;
-- Zeca e Ivo só depois de seg 23/11 (o pedido do dono que não fixa dia: só a data mínima).
create function pg_temp.depois_de_23() returns jsonb language sql immutable as $f$
  select jsonb_build_object('so_depois_de', jsonb_build_array(
           jsonb_build_object('os', 'f7a50000-0000-4000-8000-000000097101', 'dia', '2026-11-23'),
           jsonb_build_object('os', 'f7a50000-0000-4000-8000-000000097102', 'dia', '2026-11-23')))
$f$;
-- O portão do teto da equipe: ligado só com a regra teto_equipe (as outras regras da 7a ficam fora: a prova é só deste pacote).
create function pg_temp.portao(p_ligado boolean) returns void language sql as $f$
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false,
         marcar_regras = case when p_ligado then '{teto_equipe}'::text[] else '{}'::text[] end where id
$f$;

-- ── T0. As portas e o que é (sem fixture) ───────────────────────────────────────────────────────────────
with f(assinatura, args, ret, vol, quem) as (values
  ('public._agenda_contexto(date, date, date, uuid[], uuid[])',
   'p_d_ini date, p_d_fim date, p_hoje date, p_ignorar uuid[], p_fila uuid[]', 'jsonb', 's', 'motor'),
  ('public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)',
   'p_g jsonb, p_util boolean[], p_sem integer[], p_cap integer[], p_curta integer[], p_ocup integer[], p_fr integer[], p_teto integer[], p_uso integer[], p_rest integer[], p_loc integer[], p_o jsonb, p_d0 integer, p_reserva boolean, p_min_h integer',
   'jsonb', 'i', 'motor'),
  ('public._agenda_encaixar(jsonb, jsonb, jsonb)', 'p_ctx jsonb, p_fila jsonb, p_par jsonb', 'jsonb', 'i', 'motor'),
  ('public._agenda_por_que_nao(jsonb, jsonb, integer, integer)', 'p_ctx jsonb, p_o jsonb, p_d0 integer, p_wip integer', 'text', 's', 'motor'),
  ('public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)',
   'p_itens jsonb, p_parametros jsonb, p_hoje date, p_agora timestamp with time zone, p_aplicar boolean, p_pront jsonb', 'jsonb', 's',
   'leitura'))
insert into _resultado
select 'T0a as 5 recriadas: a mesma assinatura, a volatilidade de antes (o contexto, o porquê e o validador STABLE; o bloco e o encaixe IMMUTABLE), invoker, search_path fixo; o motor só do service_role, o validador também de authenticated; nunca anon',
       bool_and(p.oid is not null and pg_get_function_identity_arguments(p.oid) = f.args and pg_get_function_result(p.oid) = f.ret)
       and bool_and(p.provolatile = f.vol and not p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(not has_function_privilege('anon', p.oid, 'execute')
                    and has_function_privilege('authenticated', p.oid, 'execute') = (f.quem = 'leitura')
                    and has_function_privilege('service_role', p.oid, 'execute'))
       and count(*) = 5,
       string_agg(p.proname || ':' || p.provolatile::text || ':' || pg_get_function_result(p.oid), ', ' order by p.proname)
  from f left join pg_proc p on p.oid = to_regprocedure(f.assinatura);
insert into _resultado
select 'T0b nenhuma função nova: só estas 5 trazem o "-- FASE 7: (7a P5)"',
       count(*) = 5 and bool_and(p.proname in ('_agenda_contexto', '_agenda_tentar_bloco', '_agenda_encaixar', '_agenda_por_que_nao',
                                                '_agenda_validar_itens')),
       string_agg(p.proname, ', ' order by p.proname)
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%-- FASE 7: (7a P5)%';

-- ── T1 a T5 e T7b: com as fixtures (o replay de 29/10, a sintética e o cenário da semana de 23/11) ─────────────────
do $fx$
declare
  v_res    jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-29';
  c_agora  constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_zeca   constant uuid := 'f7a50000-0000-4000-8000-000000097101';
  c_ivo    constant uuid := 'f7a50000-0000-4000-8000-000000097102';
  c_zeca_com constant text := '23/11 manha Roberto turno | 23/11 tarde Roberto turno | 24/11 manha João turno | 24/11 tarde João turno | 25/11 manha João turno';
  c_zeca_sem constant text := '26/11 manha João turno | 26/11 tarde João turno | 27/11 manha João turno | 30/11 manha Roberto turno | 30/11 tarde Roberto turno';
  c_todas  constant text[] := '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}';
  v_dono6  text := coalesce(current_setting('agenda_teste.mig_dono_fase6', true), '');
  v_mot2   text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_mot3   text := coalesce(current_setting('agenda_teste.mig_correcao_motor', true), '');
  v_dono   uuid;
  v_joao   uuid;
  v_adm    uuid;
  v_cart   uuid[];
  v_c0     jsonb;
  v_c1     jsonb;
  r        jsonb;
  r2       jsonb;
  v_itx    jsonb;
  v_ity    jsonb;
  v_itd    jsonb;
  v_t      text;
  v_dif    text;
  v_n      int;
  v_novo   text;
  v_antes  text;
  v_trocou boolean;
  v_entrada jsonb;
  v_dia    date;
  m        record;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' or v_dono6 = '' or v_mot2 = '' or v_mot3 = '' then
    insert into _resultado values ('T1 a T5 e T7b (as fixtures da 7a)', true,
      'PULADO: sem agenda_teste.replay2910, fase7a, mig_dono_fase6, mig_motor_fase2 e mig_correcao_motor (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.replay2910');
    execute current_setting('agenda_teste.fase7a');
    perform pg_temp.cenario();
    v_dono := public._agenda_dono(null);
    select id into strict v_joao from public.payees where name = 'João' and active;
    select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
    v_cart := array(select k.service_order_id from public.os_carteira(c_hoje) k order by 1);

    -- ── T1. O caso que só cabe com o teto da equipe ─────────────────────────────────────────────────────────
    v_res := pg_temp.ok(v_res, 'T1a o cenário: Zeca e Ivo prontos (classe 2), de 1 pessoa, sem o dono, na carteira',
      (public._agenda_classe_agora(c_zeca, c_hoje) ->> 'classe')::int = 2 and (public._agenda_classe_agora(c_ivo, c_hoje) ->> 'classe')::int = 2
      and c_zeca = any (v_cart) and c_ivo = any (v_cart)
      and (public.agenda_meios_da_os(c_zeca, c_hoje) #>> '{por_turno,manha,desejado}')::int = 1
      and (public.agenda_meios_da_os(c_zeca, c_hoje) ->> 'presenca') = 'nunca',
      (public._agenda_classe_agora(c_zeca, c_hoje) - 'pront')::text);
    perform pg_temp.portao(false);
    v_c0 := public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje);
    perform pg_temp.portao(true);
    v_c1 := public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje);
    v_res := pg_temp.ok(v_res, 'T1b sem o portão (a regra fora da lista), o teto por pessoa: João 4,25 esperados → 3, Roberto 2 → 1 (juntos 4); 100%: 4 e 2; nada de teto_equipe',
      pg_temp.na(v_c0, 'esperado', 'João') = 4.25 and pg_temp.na(v_c0, 'esperado', 'Roberto') = 2
      and pg_temp.na(v_c0, 'teto80', 'João') = 3 and pg_temp.na(v_c0, 'teto80', 'Roberto') = 1
      and pg_temp.na(v_c0, 'teto100', 'João') = 4 and pg_temp.na(v_c0, 'teto100', 'Roberto') = 2 and not v_c0 ? 'teto_equipe',
      format('esperado %s, teto80 %s, teto100 %s', v_c0 -> 'esperado', v_c0 -> 'teto80', v_c0 -> 'teto100'));
    v_res := pg_temp.ok(v_res, 'T1c com o portão, cada um até 100% (João 4, Roberto 2) e a equipe até floor(carga_max × 6,25) = 5 (arredonda uma vez, na soma); o dono (sem linha: 0) fica de fora',
      pg_temp.na(v_c1, 'teto80', 'João') = 4 and pg_temp.na(v_c1, 'teto80', 'Roberto') = 2
      and v_c1 -> 'teto100' = v_c0 -> 'teto100' and v_c1 -> 'esperado' = v_c0 -> 'esperado'
      and v_c1 -> 'teto_equipe' = jsonb_build_array(5) and pg_temp.na(v_c1, 'teto80', 'Gustavo') = pg_temp.na(v_c0, 'teto80', 'Gustavo'),
      format('teto80 %s, teto_equipe %s', v_c1 -> 'teto80', v_c1 -> 'teto_equipe'));
    perform pg_temp.portao(false);
    r := pg_temp.propor('os', array[c_zeca], pg_temp.depois_de_23());
    perform pg_temp.portao(true);
    r2 := pg_temp.propor('os', array[c_zeca], pg_temp.depois_de_23());
    v_res := pg_temp.ok(v_res, 'T1d o motor: o Zeca (5 meios-dias de 1 pessoa, depois de seg 23/11) só cabe na semana de 23/11 com o teto da equipe (seg 23 o Roberto, ter 24 e qua 25 de manhã o João: 5 = o teto da equipe); sem ele, vai de qui 26 a seg 30/11',
      pg_temp.cel(r, 'OS-97101') = c_zeca_sem and pg_temp.cel(r2, 'OS-97101') = c_zeca_com
      and jsonb_array_length(r -> 'fora') = 0 and jsonb_array_length(r2 -> 'fora') = 0,
      pg_temp.cel(r, 'OS-97101') || ' → ' || pg_temp.cel(r2, 'OS-97101') || ' | '
      || (select string_agg(i ->> 'texto', ' ') from jsonb_array_elements(r2 -> 'itens') i where i ->> 'op' = 'criar'));
    v_itx := (select jsonb_agg(i) from jsonb_array_elements(r2 -> 'itens') i where i ->> 'op' = 'criar');

    -- ── T2. A equipe não passa do teto ───────────────────────────────────────────────────────────────────────
    perform pg_temp.portao(false);
    r := pg_temp.propor('os', array[c_zeca, c_ivo], pg_temp.depois_de_23());
    perform pg_temp.portao(true);
    r2 := pg_temp.propor('os', array[c_zeca, c_ivo], pg_temp.depois_de_23());
    v_res := pg_temp.ok(v_res, 'T2a com o Zeca na semana de 23/11 (a equipe nos 5 dela), o Ivo (meio dia, aprovado depois) não entra na semana: vai para seg 30/11 com o Roberto, embora o João ainda tenha 1 dos 4 dele; sem o portão, o Ivo fica na seg 23/11 e o Zeca, de qui 26 a seg 30/11',
      pg_temp.cel(r2, 'OS-97101') = c_zeca_com and pg_temp.cel(r2, 'OS-97102') = '30/11 manha Roberto turno'
      and pg_temp.cel(r, 'OS-97101') = c_zeca_sem and pg_temp.cel(r, 'OS-97102') = '23/11 manha Roberto turno',
      pg_temp.cel(r2, 'OS-97102') || ' (sem o portão: ' || pg_temp.cel(r, 'OS-97102') || ')');
    v_res := pg_temp.ok(v_res, 'T2b (T4: o encaixe e o validador concordam) as propostas do motor com o portão passam no validador: a do Zeca e a do Zeca com o Ivo',
      public._agenda_validar_itens(v_itx, '{}'::jsonb, c_hoje, c_agora, false) = '[]'::jsonb
      and public._agenda_validar_itens(r2 -> 'itens', jsonb_build_object('p_restricoes', pg_temp.depois_de_23()), c_hoje, c_agora, false) = '[]'::jsonb,
      public._agenda_validar_itens(r2 -> 'itens', '{}'::jsonb, c_hoje, c_agora, false)::text);
    -- o Zeca publicado (o motor grava e a aplicação valida de novo, com o portão), e o porquê do Ivo na qui 26/11 (numa
    -- subtransação desfeita: a semana volta a ficar vazia para os próximos)
    v_entrada := jsonb_build_object('i', 1, 'passos', 1, 'pm', '[]'::jsonb, 'teto100', false);
    begin
      r := public.agenda_propor('os', null, null, array[c_zeca], pg_temp.depois_de_23(), true, 'motor', null, c_hoje, c_agora);
      r2 := public.agenda_aplicar((r ->> 'proposta_id')::uuid, null, 'motor', null, null, c_hoje, c_agora);
      v_c1 := public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje, '{}'::uuid[], array[c_ivo]);
      v_t := public._agenda_por_que_nao(v_c1, v_entrada, 4, 2);
      v_res := pg_temp.ok(v_res, 'T2c com o Zeca publicado (a aplicação valida com o portão e aceita), o Ivo não cabe na qui 26/11 porque "a equipe já está com a semana cheia" (5 de 5; o João está com 3 dos 4 dele)',
        (r2 ->> 'ok')::boolean and v_t = 'a equipe já está com a semana cheia'
        and pg_temp.na(v_c1, 'uso_c', 'João') = 3 and pg_temp.na(v_c1, 'teto80', 'João') = 4,
        coalesce(v_t, '-') || ' | ' || coalesce(r2 ->> 'texto', r2::text));
      v_t := public._agenda_por_que_nao(v_c1, v_entrada || '{"teto100": true}'::jsonb, 4, 2);
      perform pg_temp.portao(false);
      v_c0 := public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje, '{}'::uuid[], array[c_ivo]);
      perform pg_temp.portao(true);
      v_res := pg_temp.ok(v_res, 'T2d o pedido do dono (teto100, a OS sem o teto da equipe) não recebe esse motivo; sem o portão, também não ("falta gente nesse dia")',
        v_t <> 'a equipe já está com a semana cheia' and public._agenda_por_que_nao(v_c0, v_entrada, 4, 2) = 'falta gente nesse dia',
        v_t || ' | sem o portão: ' || public._agenda_por_que_nao(v_c0, v_entrada, 4, 2));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- ── T3. O dono com o teto dele (numa subtransação desfeita: a linha do dono sai depois) ──────────────────────
    begin
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, nota, criado_por)
    values (v_dono, '{1,2,3,4,5}', 'disponivel', 'dono', 'teste 7a P5: fico em campo de segunda a sexta', v_adm);
    perform pg_temp.portao(false);
    v_c0 := public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje);
    perform pg_temp.portao(true);
    v_c1 := public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje);
    v_res := pg_temp.ok(v_res, 'T3a com a linha do dono (seg a sex: 10 meios-dias esperados), o teto dele com o portão continua floor(carga dele × esperado) = 8 (não 10), igual ao de sem o portão; a equipe continua 5 (o dono fora da soma)',
      pg_temp.na(v_c1, 'esperado', 'Gustavo') = 10
      and pg_temp.na(v_c1, 'teto80', 'Gustavo') = floor(public._agenda_carga_da_pessoa(v_dono) * 10)
      and pg_temp.na(v_c1, 'teto80', 'Gustavo') = pg_temp.na(v_c0, 'teto80', 'Gustavo') and pg_temp.na(v_c1, 'teto80', 'Gustavo') < 10
      and pg_temp.na(v_c1, 'teto100', 'Gustavo') = 10 and v_c1 -> 'teto_equipe' = jsonb_build_array(5),
      format('dono: esperado %s, teto80 %s (sem o portão %s), teto100 %s; teto_equipe %s', pg_temp.na(v_c1, 'esperado', 'Gustavo'),
             pg_temp.na(v_c1, 'teto80', 'Gustavo'), pg_temp.na(v_c0, 'teto80', 'Gustavo'), pg_temp.na(v_c1, 'teto100', 'Gustavo'),
             v_c1 -> 'teto_equipe'));
    r := pg_temp.propor('os', array[c_zeca], pg_temp.depois_de_23());
    v_res := pg_temp.ok(v_res, 'T3b com o dono em campo, o motor continua sem pô-lo em vaga de técnico: o Zeca sai igual (Roberto e João, 5 meios-dias na semana de 23/11)',
      pg_temp.cel(r, 'OS-97101') = c_zeca_com, pg_temp.cel(r, 'OS-97101'));
    v_itd := jsonb_build_array(jsonb_build_object('op', 'criar', 'os', c_ivo, 'numero', 'OS-97102', 'tipo', 'execucao',
               'alocacoes', (select jsonb_agg(jsonb_build_object('payee_id', v_dono, 'nome', 'Gustavo', 'dia', d::date, 'turno', t,
                                                                 'presenca', 'turno') order by d, t = 'tarde')
                               from generate_series(date '2026-11-23', date '2026-11-27', interval '1 day') d,
                                    unnest(array['manha', 'tarde']) t
                              where not (d::date = date '2026-11-27' and t = 'tarde'))));
    v_res := pg_temp.ok(v_res, 'T3c o validador cobra o teto do dono com o portão (9 meios-dias seus para os 8 dele) e não o põe na soma da equipe (nenhuma linha "A equipe …", com o Zeca nos 5 da equipe)',
      floor(public._agenda_carga_da_pessoa(v_dono) * 10) < 9
      and pg_temp.regra6(public._agenda_validar_itens(v_itx || v_itd, '{}'::jsonb, c_hoje, c_agora, false))
        = format('Gustavo passaria do limite da semana de 23/11: 9 meios-dias de serviço para %s.',
                 floor(public._agenda_carga_da_pessoa(v_dono) * 10)::int),
      pg_temp.regra6(public._agenda_validar_itens(v_itx || v_itd, '{}'::jsonb, c_hoje, c_agora, false)));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- ── T4. O validador recusa o que o encaixe recusaria ─────────────────────────────────────────────────────
    v_ity := jsonb_build_array(jsonb_build_object('op', 'criar', 'os', c_ivo, 'numero', 'OS-97102', 'tipo', 'execucao',
               'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_joao, 'nome', 'João', 'dia', date '2026-11-26',
                                                                 'turno', 'manha', 'presenca', 'turno'))));
    perform pg_temp.portao(false);
    v_t := pg_temp.regra6(public._agenda_validar_itens(v_itx, '{}'::jsonb, c_hoje, c_agora, false));
    perform pg_temp.portao(true);
    v_res := pg_temp.ok(v_res, 'T4a sem o portão, a semana do Zeca com o teto da equipe passa do teto de cada um: "Roberto passaria do limite da semana de 23/11: 2 meios-dias de serviço para 1." (o João, 3 de 3, não)',
      v_t = 'Roberto passaria do limite da semana de 23/11: 2 meios-dias de serviço para 1.', v_t);
    v_t := pg_temp.regra6(public._agenda_validar_itens(v_itx || v_ity, '{}'::jsonb, c_hoje, c_agora, false));
    v_res := pg_temp.ok(v_res, 'T4b com o portão, o Ivo na mesma semana (o João na qui 26/11 de manhã) passa do teto da equipe: só "A equipe passaria do limite da semana de 23/11: 6 meios-dias de serviço para 5." (cada um continua dentro do dele: João 4 de 4, Roberto 2 de 2)',
      v_t = 'A equipe passaria do limite da semana de 23/11: 6 meios-dias de serviço para 5.'
      and exists (select 1 from jsonb_array_elements(public._agenda_validar_itens(v_itx || v_ity, '{}'::jsonb, c_hoje, c_agora, true)) e
                   where (e ->> 'regra')::int = 6 and e ->> 'pessoa' is null and (e ->> 'dia')::date = date '2026-11-23'),
      v_t);
    v_res := pg_temp.ok(v_res, 'T4c com acima_da_carga (o encaixe também não usa o teto da equipe) e com o Ivo pedido pelo dono (fixar_dono: o encaixe põe o pedido do dono sem o teto da equipe), o validador não recusa',
      pg_temp.regra6(public._agenda_validar_itens(v_itx || v_ity, '{"p_restricoes": {"acima_da_carga": true}}'::jsonb, c_hoje, c_agora, false)) = '-'
      and pg_temp.regra6(public._agenda_validar_itens(v_itx || jsonb_build_array(v_ity -> 0 || '{"fixar_dono": true}'::jsonb), '{}'::jsonb,
                                                      c_hoje, c_agora, false)) = '-',
      pg_temp.regra6(public._agenda_validar_itens(v_itx || v_ity, '{"p_restricoes": {"acima_da_carga": true}}'::jsonb, c_hoje, c_agora, false)));
    -- o Ivo publicado na qui 26/11 (o vigente conta na soma): o Zeca sozinho passa a recusar (numa subtransação desfeita)
    begin
      insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
      values (md5('f7a5:aloc:ivo')::uuid, c_ivo, v_joao, date '2026-11-26', 'manha', 'turno', 'execucao', 'publicada', 'motor', c_agora);
      v_t := pg_temp.regra6(public._agenda_validar_itens(v_itx, '{}'::jsonb, c_hoje, c_agora, false));
      r := pg_temp.propor('os', array[c_zeca], pg_temp.depois_de_23());
      v_res := pg_temp.ok(v_res, 'T4d com o Ivo já publicado na semana (o vigente conta), os 5 meios-dias do Zeca passam do teto da equipe (6 para 5) — e o motor, com o portão, não põe mais o Zeca de seg 23 a qua 25/11',
        v_t = 'A equipe passaria do limite da semana de 23/11: 6 meios-dias de serviço para 5.'
        and pg_temp.cel(r, 'OS-97101') <> c_zeca_com
        and public._agenda_validar_itens(r -> 'itens', jsonb_build_object('p_restricoes', pg_temp.depois_de_23()), c_hoje, c_agora, false) = '[]'::jsonb,
        v_t || ' | o motor: ' || pg_temp.cel(r, 'OS-97101'));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- ── T5. O portão falso: byte a byte com as definições de antes ──────────────────────────────────────────
    v_dif := null;
    for m in
      select * from (values (1, 'desligado', 'desligado', false, c_todas),
                            (2, 'em teste (sombra, sem a simulação)', 'sombra', false, c_todas),
                            (3, '*gestor, só propor*', 'ligado', true, c_todas),
                            (4, 'ligado sem a regra teto_equipe (as outras da 7a ligadas)', 'ligado', false,
                             array_remove(c_todas, 'teto_equipe'))) t(o, nome, modo, so_propor, regras)
       order by o
    loop
      update public.agenda_config set modo_marcar_sozinho = m.modo, gestor_so_propor = m.so_propor, marcar_regras = m.regras where id;
      select string_agg(md5(public._agenda_contexto(s::date, s::date + 6, c_hoje)::text)
                        || md5(public._agenda_contexto(s::date, s::date + 13, c_hoje, '{}'::uuid[], array[c_zeca, c_ivo])::text), '' order by s)
             || md5(pg_temp.propor('semana')::text) || md5(pg_temp.propor('os', v_cart)::text)
             || md5(pg_temp.propor('os', array[c_zeca, c_ivo], pg_temp.depois_de_23())::text)
             || md5(public._agenda_validar_itens(v_itx || v_ity, '{}'::jsonb, c_hoje, c_agora, true)::text)
             || md5(public._agenda_validar_itens(v_itx || v_ity, '{"p_restricoes": {"acima_da_carga": true}}'::jsonb, c_hoje, c_agora, false)::text)
             || md5(coalesce(public._agenda_por_que_nao(public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje, '{}'::uuid[],
                                                                                  array[c_ivo]), v_entrada, 4, 2), '-'))
        into v_novo
        from generate_series(date '2026-10-26', date '2026-12-07', interval '7 days') s;
      v_trocou := false;
      begin
        execute pg_temp.inteira(v_dono6, '_agenda_contexto');
        execute pg_temp.inteira(v_dono6, '_agenda_validar_itens');
        execute pg_temp.inteira(v_mot2, '_agenda_tentar_bloco');
        execute pg_temp.inteira(v_mot2, '_agenda_por_que_nao');
        execute pg_temp.inteira(v_mot3, '_agenda_encaixar');
        v_trocou := (select count(*) = 5 and bool_and(prosrc !~ '-- FASE 7:') from pg_proc
                      where pronamespace = 'public'::regnamespace
                        and proname in ('_agenda_contexto', '_agenda_validar_itens', '_agenda_tentar_bloco', '_agenda_por_que_nao',
                                        '_agenda_encaixar'));
        select string_agg(md5(public._agenda_contexto(s::date, s::date + 6, c_hoje)::text)
                          || md5(public._agenda_contexto(s::date, s::date + 13, c_hoje, '{}'::uuid[], array[c_zeca, c_ivo])::text), '' order by s)
               || md5(pg_temp.propor('semana')::text) || md5(pg_temp.propor('os', v_cart)::text)
               || md5(pg_temp.propor('os', array[c_zeca, c_ivo], pg_temp.depois_de_23())::text)
               || md5(public._agenda_validar_itens(v_itx || v_ity, '{}'::jsonb, c_hoje, c_agora, true)::text)
               || md5(public._agenda_validar_itens(v_itx || v_ity, '{"p_restricoes": {"acima_da_carga": true}}'::jsonb, c_hoje, c_agora, false)::text)
               || md5(coalesce(public._agenda_por_que_nao(public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje, '{}'::uuid[],
                                                                                    array[c_ivo]), v_entrada, 4, 2), '-'))
          into v_antes
          from generate_series(date '2026-10-26', date '2026-12-07', interval '7 days') s;
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      if not v_trocou or v_novo is distinct from v_antes then v_dif := concat_ws('; ', v_dif, m.nome); end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'T5a com o portão falso (desligado, sombra sem a simulação, *gestor, só propor*, sem a regra teto_equipe), o contexto de 7 semanas (de 26/10 a 07/12, uma e duas), o motor (a semana, a carteira, o Zeca e o Ivo), o validador e o porquê são os de antes, byte a byte',
      v_dif is null, coalesce(v_dif, '—'));
    -- o controle: com o portão, as mesmas contas acusam a diferença
    perform pg_temp.portao(true);
    v_novo := md5(public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje)::text)
              || md5(pg_temp.propor('os', array[c_zeca, c_ivo], pg_temp.depois_de_23())::text);
    begin
      execute pg_temp.inteira(v_dono6, '_agenda_contexto');
      execute pg_temp.inteira(v_dono6, '_agenda_validar_itens');
      execute pg_temp.inteira(v_mot2, '_agenda_tentar_bloco');
      execute pg_temp.inteira(v_mot2, '_agenda_por_que_nao');
      execute pg_temp.inteira(v_mot3, '_agenda_encaixar');
      v_antes := md5(public._agenda_contexto(date '2026-11-23', date '2026-11-29', c_hoje)::text)
                 || md5(pg_temp.propor('os', array[c_zeca, c_ivo], pg_temp.depois_de_23())::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'T5b o controle, com o portão: o contexto da semana de 23/11 e o motor do Zeca com o Ivo deixam de ser os de antes',
      left(v_novo, 32) <> left(v_antes, 32) and right(v_novo, 32) <> right(v_antes, 32), v_novo || ' / ' || coalesce(v_antes, '-'));

    -- ── T7b. A saída repetida do contexto com o portão: chave a chave, só teto80 e teto_equipe mudam ─────────────
    -- (instrução a instrução: o contexto é STABLE e não vê o portão mudado na mesma instrução)
    v_n := 0;
    v_t := null;
    for v_dia in select g::date from generate_series(date '2026-10-26', date '2026-12-07', interval '7 days') g loop
      perform pg_temp.portao(false);
      v_c0 := public._agenda_contexto(v_dia, v_dia + 13, c_hoje, '{}'::uuid[], array[c_zeca]);
      perform pg_temp.portao(true);
      v_c1 := public._agenda_contexto(v_dia, v_dia + 13, c_hoje, '{}'::uuid[], array[c_zeca]);
      v_n := v_n + 1;
      if (v_c1 - 'teto80' - 'teto_equipe') is distinct from (v_c0 - 'teto80') or v_c0 ? 'teto_equipe'
         or jsonb_array_length(v_c1 -> 'teto_equipe') <> (v_c1 ->> 'nw')::int
         or (select array_agg(k order by k) from jsonb_object_keys(v_c1) k)
            is distinct from (select array_agg(k order by k) from jsonb_object_keys(v_c0 || '{"teto_equipe": []}'::jsonb) k) then
        v_t := concat_ws(', ', v_t, to_char(v_dia, 'DD/MM'));
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, format('T7b a saída do contexto com o portão (a repetida no bloco) é a de sem o portão chave a chave, menos teto80 e mais teto_equipe, um por semana (%s janelas de duas semanas)', v_n),
      v_t is null and v_n = 7, coalesce(v_t, '—'));

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$fx$;

-- ── T6. A manhã de sábado (o gancho do P12) ──────────────────────────────────────────────────────────────
do $sab$
declare
  v_res    jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-29';
  c_agora  constant timestamptz := timestamptz '2026-10-29 16:52-03';
  v_rob    uuid;
  v_adm    uuid;
  v_os     uuid;
  v_c0     jsonb;
  v_c1     jsonb;
  v_c2     jsonb;
  v_sab    int;
  v_cr     int;
  v_cj     int;
  v_entrada jsonb;
  v_par    jsonb;
  r        jsonb;
  cf       public.agenda_config;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('T6 a manhã de sábado (as fixtures da 7a)', true,
      'PULADO: sem agenda_teste.replay2910 e fase7a (rode pela bancada)');
    return;
  end if;
  begin
    perform set_config('agenda_teste.fase7a_sabado', 'on', true);   -- o Roberto com o padrão de sábado de manhã
    execute current_setting('agenda_teste.replay2910');
    execute current_setting('agenda_teste.fase7a');
    perform set_config('agenda_teste.fase7a_sabado', '', true);
    select id into strict v_rob from public.payees where name = 'Roberto' and active;
    select id into strict v_adm from public.app_users where role = 'admin' and active order by id limit 1;
    v_os := pg_temp.os('OS-97003');   -- Tânia: uma OS qualquer da carteira, só para a posição na fila
    select * into cf from public.agenda_config where id;
    -- a semana de 02/11 (sáb 07/11 = o 6º dia); a célula da manhã de sábado de cada um: (pessoa − 1) × nh + 11
    v_c0 := public._agenda_contexto(date '2026-11-02', date '2026-11-08', c_hoje, '{}'::uuid[], array[v_os]);
    v_sab := 6;
    v_cr := (pg_temp.idx(v_c0, 'Roberto') - 1) * (v_c0 ->> 'nh')::int + 2 * (v_sab - 1) + 1;
    v_cj := (pg_temp.idx(v_c0, 'João') - 1) * (v_c0 ->> 'nh')::int + 2 * (v_sab - 1) + 1;
    perform set_config('agenda.sabado', 'on', true);
    v_c1 := public._agenda_contexto(date '2026-11-02', date '2026-11-08', c_hoje, '{}'::uuid[], array[v_os]);
    perform set_config('agenda.sabado', '', true);
    v_res := pg_temp.ok(v_res, 'T6a sem a variável, o sábado do Roberto (padrão de sábado de manhã) não é útil e ninguém tem lugar nele',
      not (v_c0 -> 'util' ->> (v_sab - 1))::boolean and (v_c0 -> 'cap' ->> (v_cr - 1))::int = 0 and (v_c0 -> 'cap' ->> v_cr)::int = 0,
      format('útil %s, Roberto manhã %s tarde %s', v_c0 -> 'util' ->> (v_sab - 1), v_c0 -> 'cap' ->> (v_cr - 1), v_c0 -> 'cap' ->> v_cr));
    v_res := pg_temp.ok(v_res, 'T6b com agenda.sabado = on (e sabado_manha so_prazo): sáb 07/11 vira útil, a manhã é do Roberto (o padrão), não do João; a tarde fica sem ninguém; o esperado, os tetos e o resto do contexto não mudam',
      (v_c1 -> 'util' ->> (v_sab - 1))::boolean and (v_c1 -> 'cap' ->> (v_cr - 1))::int = 1 and (v_c1 -> 'cap' ->> v_cr)::int = 0
      and (v_c1 -> 'cap' ->> (v_cj - 1))::int = 0 and (v_c1 -> 'cap' ->> v_cj)::int = 0 and cf.sabado_manha = 'so_prazo'
      and v_c1 -> 'esperado' = v_c0 -> 'esperado' and v_c1 -> 'teto80' = v_c0 -> 'teto80' and v_c1 -> 'teto100' = v_c0 -> 'teto100'
      and (v_c1 - 'util' - 'cap') = (v_c0 - 'util' - 'cap')
      and (select count(*) from jsonb_array_elements(v_c1 -> 'cap') with ordinality t(e, o)
            where e is distinct from v_c0 -> 'cap' -> (o::int - 1)) between 1 and (v_c0 ->> 'np')::int * 2,
      format('útil %s; Roberto manhã %s tarde %s; João manhã %s', v_c1 -> 'util' ->> (v_sab - 1), v_c1 -> 'cap' ->> (v_cr - 1),
             v_c1 -> 'cap' ->> v_cr, v_c1 -> 'cap' ->> (v_cj - 1)));
    -- o encaixe usa a manhã de sábado (uma OS de meio dia de 1 pessoa, a partir do sábado): com a variável, o Roberto no sáb 07/11
    -- de manhã; sem ela, não há onde (a grade só vai até dom 08/11)
    v_entrada := jsonb_build_object('i', 1, 'os', v_os, 'classe', 2, 'ordem', 1, 'passos', 1, 'abre', false, 'fecha', false,
                   'dt_m', false, 'dt_t', false, 'dm', 1, 'dtd', 1, 'pm', '[]'::jsonb, 'pt', '[]'::jsonb, 'fixa', 0,
                   'est', v_sab, 'est_cond', v_sab, 'min_h', 1, 'bem', '[]'::jsonb, 'tem_reserva', false, 'teto100', false,
                   'dono_impossivel', false, 'evento_real', false);
    v_par := jsonb_build_object('wip', cf.wip_max, 'imax', cf.interrupcoes_max, 'inicios', cf.inicios_tentados_du, 'semana', false,
                                'acima', false);
    r := public._agenda_encaixar(v_c1, jsonb_build_array(v_entrada), v_par);
    v_res := pg_temp.ok(v_res, 'T6c o encaixe põe o meio dia na manhã de sábado do Roberto com a variável; sem ela, fica fora (sem encaixe)',
      r #> '{colocadas,0,h}' = jsonb_build_array(2 * (v_sab - 1) + 1)
      and r #> '{colocadas,0,p}' = jsonb_build_array(pg_temp.idx(v_c0, 'Roberto'))
      and public._agenda_encaixar(v_c0, jsonb_build_array(v_entrada), v_par) #>> '{fora,0,motivo}' = 'sem_encaixe',
      r::text);
    -- o validador ainda não aceita o sábado (a regra 1 lê a grade: "sábado só quando vocês combinam") — aviso ao P12, que liga a
    -- variável na decisão e tem de recriar _agenda_validar_itens para aceitar a manhã de quem tem o padrão
    v_res := pg_temp.ok(v_res, 'T6d (aviso ao P12) o validador ainda recusa a manhã de sábado pela regra 1 (a grade diz fim de semana): o P12 o recria para a decisão do sábado',
      exists (select 1 from jsonb_array_elements(public._agenda_validar_itens(jsonb_build_array(jsonb_build_object('op', 'criar', 'os', v_os,
                'numero', 'OS-97003', 'tipo', 'execucao', 'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', v_rob, 'nome', 'Roberto',
                'dia', date '2026-11-07', 'turno', 'manha', 'presenca', 'turno')))), '{}'::jsonb, c_hoje, c_agora, false)) e
               where (e ->> 'regra')::int = 1),
      null);
    -- sabado_manha = nunca: a variável não muda nada
    update public.agenda_config set sabado_manha = 'nunca' where id;
    perform set_config('agenda.sabado', 'on', true);
    v_c2 := public._agenda_contexto(date '2026-11-02', date '2026-11-08', c_hoje, '{}'::uuid[], array[v_os]);
    perform set_config('agenda.sabado', '', true);
    update public.agenda_config set sabado_manha = 'so_prazo' where id;
    v_res := pg_temp.ok(v_res, 'T6e com sabado_manha = nunca, a variável não muda nada', v_c2 = v_c0, null);
    -- a exceção "não vem" do Roberto nesse sábado: ninguém pode vir, e o sábado não muda (não vira útil e vazio)
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_por)
    values (v_rob, daterange(date '2026-11-07', date '2026-11-07', '[]'), 'indisponivel', 'dono', 'teste 7a P5: não vem sáb 07/11', v_adm);
    v_c0 := public._agenda_contexto(date '2026-11-02', date '2026-11-08', c_hoje, '{}'::uuid[], array[v_os]);
    perform set_config('agenda.sabado', 'on', true);
    v_c2 := public._agenda_contexto(date '2026-11-02', date '2026-11-08', c_hoje, '{}'::uuid[], array[v_os]);
    perform set_config('agenda.sabado', '', true);
    v_res := pg_temp.ok(v_res, 'T6f com a exceção "não vem" do Roberto no sáb 07/11, ninguém vem: com a variável, o contexto é o de sem ela (o sábado não vira útil e vazio, que contaria como dia parado)',
      v_c2 = v_c0 and not (v_c2 -> 'util' ->> (v_sab - 1))::boolean, v_c2 -> 'util' ->> (v_sab - 1));
    -- o sábado que já é útil (sabado_util) não muda com a variável
    update public.agenda_config set sabado_util = true where id;
    v_c0 := public._agenda_contexto(date '2026-11-09', date '2026-11-15', c_hoje, '{}'::uuid[], array[v_os]);
    perform set_config('agenda.sabado', 'on', true);
    v_c2 := public._agenda_contexto(date '2026-11-09', date '2026-11-15', c_hoje, '{}'::uuid[], array[v_os]);
    perform set_config('agenda.sabado', '', true);
    v_res := pg_temp.ok(v_res, 'T6g com sabado_util ligado (o sábado já é útil, manhã e tarde), a variável não muda nada',
      v_c2 = v_c0 and (v_c0 -> 'util' ->> 5)::boolean, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda.sabado', '', true);
  perform pg_temp.gravar(v_res);
end
$sab$;

-- ── T7a. As cópias ───────────────────────────────────────────────────────────────────────────────────────
do $copias$
declare
  v_dono6 text := coalesce(current_setting('agenda_teste.mig_dono_fase6', true), '');
  v_mot2  text := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  v_mot3  text := coalesce(current_setting('agenda_teste.mig_correcao_motor', true), '');
  r      record;
  v_novo text;
  v_n    int;
begin
  if v_dono6 = '' or v_mot2 = '' or v_mot3 = '' then
    insert into _resultado values ('T7a as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_contexto', 'public._agenda_contexto(date, date, date, uuid[], uuid[])', v_dono6, '20261029100400', 4),
      -- (2 blocos do P5 + 1 do 7a P12, 20261031100900: a manhã de sábado autorizada; quem recria copia da mais nova)
      ('_agenda_validar_itens', 'public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)', v_dono6, '20261029100400', 3),
      ('_agenda_tentar_bloco', 'public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)',
       v_mot2, '20261025100200', 4),
      ('_agenda_por_que_nao', 'public._agenda_por_que_nao(jsonb, jsonb, integer, integer)', v_mot2, '20261025100200', 2),
      ('_agenda_encaixar', 'public._agenda_encaixar(jsonb, jsonb, jsonb)', v_mot3, '20261030100200', 2)
    ) t(nome, assinatura, fonte, versao, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.assinatura::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7: fim', 'g');
    insert into _resultado
    select format('T7a %s: sem os %s blocos "-- FASE 7:", é o corpo de %s (a mais nova antes da 7a P5)', r.nome, r.blocos, r.versao),
           v_n = r.blocos and pg_temp.corpo(r.fonte, r.nome) <> '' and pg_temp.sem_fase7(v_novo) = pg_temp.corpo(r.fonte, r.nome),
           format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(r.fonte, r.nome)),
                  length(pg_temp.sem_fase7(v_novo)));
  end loop;
end
$copias$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
