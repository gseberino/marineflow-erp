-- Prova das leituras da Agenda de Produção, Fase 7f (pacote P7): *agenda pendências* com o número de sempre e o prazo só onde ele vale, a palavra *agenda espera <nome>* (o *agenda
-- fica* não existe) e a saúde da comunicação (migration 20261109100600; spec-fase7f §5.7, §6.2, §7, §8.3 agenda_fase7f_leituras.sql, §11 e R8.5-26, 28 e 29, R8.6, R8.7, R8.8,
-- R8.12, R8.13).
-- bancada: depende de 20261109100600
--
--   V0   sempre: as 2 novas e as portas; as cópias só mudam nos blocos; a migration cria e recria só o que diz; a lista do que nunca vence é a do CHECK
--   V1   o foco decisoes: "Decisão N" é o n de agenda_decisoes_abertas (com o controle de outra ordem); 8 abertas em 1.800 letras, e o corte diz quais saíram; o prazo só onde
--        ele vale (com o freio e em sombra, nenhum); a ordem do "Também quero saber"; a leitura não marca nada; contra a origem (a 7d), só a ordem muda
--   V2   *agenda espera <nome>*: só espera; o alvo pela régua do *desfaz*; veto_espera = dono e o prazo nulo; não vence mais (o prazo e o teto do P2, o registro do P3); com o freio;
--        o nome que não casa; a que já espera; o prazo próprio; os dias do dono ficam de fora; as portas; o gatilho
--   V3   a saúde: os zeros quando nada aconteceu; cada violação forçada conta 1; os números do P3 e do P4 (a cota, a quinta, o bloco, as falhas, as mensagens por origem); o zero
--        prazo_em_critica redefinido; contra a origem, só a chave nova
--   V4   o técnico recebe 42501; 2 chamadas dão o mesmo md5
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela, só o V0 roda; o resto sai PULADO: usa a fixture da 7f, que nunca roda em produção.
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
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
create function pg_temp.lanca(p_sql text) returns text language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    return sqlstate || ': ' || sqlerrm;
  end;
  return 'ok';
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7f: … -- FASE 7f: fim" e, dentro de bloco de antes, "-- (7f … -- (7f: fim)" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7f(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- (FASE 7f:|\(7f )' and l !~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' then 1
                                                when l ~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- Só os blocos deste pacote ("(7f P7" na linha de abrir), com as linhas de abrir e de fechar: os dos pacotes de antes ficam.
create function pg_temp.sem_p7(p text) returns text language plpgsql immutable as $f$
declare
  l      text;
  fora   text[] := '{}';
  dentro boolean := false;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not dentro and l ~ '^\s*-- (FASE 7f: \(7f P7|\(7f P7)' then dentro := true; continue; end if;
    if dentro and l ~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' then dentro := false; continue; end if;
    if not dentro then fora := fora || l; end if;
  end loop;
  return array_to_string(fora, E'\n');
end $f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at, id limit 1
$f$;
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_leituras_fase7f', true), '') <> ''
$f$;
create function pg_temp.q(p_c text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-0000000005' || p_c)::uuid $f$;
create function pg_temp.a(p_c text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-0000000006' || p_c)::uuid $f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$ select ('f7f00000-0000-4000-8000-000000097' || p_n)::uuid $f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O cenário: a fixture da 7f, a agenda automática e a leitura ligadas, o dono no WhatsApp e o freio de produção (gestor_so_propor), na terça 10/11 às 17:30.
create function pg_temp.prepara() returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.fase7f');
  update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_leitura = 'ligado', gestor_so_propor = true where id;
  update public.app_users set ai_whatsapp_enabled = true, phone_normalized = '5547900000210' where id = pg_temp.adm();
  perform set_config('agenda.hoje', '2026-11-10', true);
  perform set_config('agenda.agora', '2026-11-10 17:30:00-03', true);
end $f$;
create function pg_temp.modos(p text) returns void language sql as $f$
  update public.agenda_config
     set modo_bloco_agenda = p, modo_veto = p, modo_lote_dono = p, modo_equipe_previsto = p, modo_equipe_convite = p, modo_cliente_camadas = p
   where id
$f$;
-- *agenda espera* sem derrubar o arquivo: o erro (do gatilho ou do CHECK) volta como status, e a linha do caso reprova com ele
create function pg_temp.espera(p_alvo text, p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
begin
  return public.agenda_veto_dito(pg_temp.adm(), 'espera', p_alvo, p_hoje, p_agora);
exception when others then
  return jsonb_build_object('status', 'erro', 'erro', sqlstate || ': ' || sqlerrm);
end $f$;
create function pg_temp.foco() returns text language sql stable as $f$
  select public._agenda_ver_decisoes(date '2026-11-10', timestamptz '2026-11-10 17:30-03') ->> 'texto'
$f$;
-- O que a leitura não pode mudar: o que conta como mostrado e o prazo de cada pergunta.
create function pg_temp.mostradas() returns text language sql stable as $f$
  select md5(coalesce(string_agg(format('%s|%s|%s|%s|%s|%s|%s', q.id, q.mostrada_vezes, q.mostrada_em, q.mostrada_via, q.veto_ate, q.veto_teria_em, q.carona_em), ',' order by q.id), ''))
    from public.agenda_perguntas q
$f$;
create function pg_temp.desfaz() returns void language plpgsql as $f$
begin
  raise exception using errcode = 'P0001', message = '__desfaz__';
end $f$;
-- A origem: _agenda_ver_decisoes e agenda_saude como eram antes desta migration (a 7d), com outro nome, para comparar a saída na mesma transação.
create function pg_temp.criar_origens() returns void language plpgsql as $f$
begin
  execute format($q$create function pg_temp.dec_7d(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable set search_path to 'public' as $b$%s$b$$q$,
                 pg_temp.corpo(current_setting('agenda_teste.mig_correcao3_fase7d'), '_agenda_ver_decisoes'));
  execute format($q$create function pg_temp.saude_7d(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable set search_path to 'public' as $b$%s$b$$q$,
                 pg_temp.corpo(current_setting('agenda_teste.mig_leituras_fase7d'), 'agenda_saude'));
  -- agenda_saude desta migration com só o 1º termo do ok (o de antes da 7b) em verdadeiro: na fixture ele já é falso por outro motivo, e assim o que sobra no ok são as
  -- chaves equipe_dias, local e comunicacao. Se a troca não achar o termo, o V3b0 reprova.
  execute format($q$create function pg_temp.saude_so_zeros(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable set search_path to 'public' as $b$%s$b$$q$,
                 replace(pg_temp.corpo(current_setting('agenda_teste.mig_leituras_fase7f'), 'agenda_saude'), $r$'ok', v_sem = 0 and$r$, $r$'ok', true or v_sem = 0 and$r$));
end $f$;
-- Os títulos do "Também esperam: …" (a linha do corte), em ordem; e as linhas do texto sem ela.
create function pg_temp.titulos(p text) returns text[] language sql immutable as $f$
  select coalesce(string_to_array(rtrim(substr(l, length('Também esperam: ') + 1), '.'), '; '), '{}')
    from unnest(string_to_array(p, E'\n')) l where l like 'Também esperam: %'
$f$;

-- A fixture entra uma vez, na transação de fora: cada caso mexe nela dentro de uma subtransação desfeita. A bancada não tem resumo_tarde (é do Secretário, 20261015210000, fora
-- dela): a saúde a lê por to_regclass, e aqui ela nasce só com as colunas que a saúde lê, dentro desta transação, que é desfeita. Em produção ela existe.
do $v$
begin
  if pg_temp.na_bancada() then
    perform pg_temp.prepara();
    perform pg_temp.criar_origens();
    if to_regclass('public.resumo_tarde') is null then
      create table public.resumo_tarde (id uuid primary key default gen_random_uuid(), dia date not null, phone_normalized text not null, turno text not null,
                                        modo text not null, formato text not null, texto text, detalhe jsonb not null default '{}'::jsonb,
                                        criado_em timestamptz not null default now());
    end if;
  end if;
end
$v$;

-- ── V0: sempre ──────────────────────────────────────────────────────────────────────────────────────
do $v0$
declare
  r     jsonb := '[]';
  v_mig text := coalesce(current_setting('agenda_teste.mig_leituras_fase7f', true), '');
  v     text;
  v_a   text;
begin
  r := pg_temp.ok(r, 'V0a agenda_veto_dito: 1 assinatura, security definer; só service_role (nem anon, nem authenticated, nem public)',
    (select count(*) from pg_proc where proname = 'agenda_veto_dito' and pronamespace = 'public'::regnamespace) = 1
    and (select prosecdef from pg_proc where oid = 'public.agenda_veto_dito(uuid, text, text, date, timestamptz)'::regprocedure)
    and has_function_privilege('service_role', 'public.agenda_veto_dito(uuid, text, text, date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_veto_dito(uuid, text, text, date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_veto_dito(uuid, text, text, date, timestamptz)', 'execute'), null);
  r := pg_temp.ok(r, 'V0b _agenda_saude_comunicacao: security definer; authenticated e service_role (a porta é dentro), nunca anon',
    (select prosecdef from pg_proc where oid = 'public._agenda_saude_comunicacao(date, timestamptz)'::regprocedure)
    and has_function_privilege('service_role', 'public._agenda_saude_comunicacao(date, timestamptz)', 'execute')
    and has_function_privilege('authenticated', 'public._agenda_saude_comunicacao(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public._agenda_saude_comunicacao(date, timestamptz)', 'execute'), null);
  r := pg_temp.ok(r, 'V0c as 3 recriadas mantêm as portas: _agenda_ver_decisoes e agenda_saude fora de anon; _agenda_perguntas_antes fora de anon e authenticated',
    not has_function_privilege('anon', 'public._agenda_ver_decisoes(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_saude(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public._agenda_perguntas_antes()', 'execute')
    and not has_function_privilege('authenticated', 'public._agenda_perguntas_antes()', 'execute'), null);
  -- a lista do que nunca vence em _agenda_saude_comunicacao é a do CHECK de veto_tipos (uma fonte só para o que proíbe: o CHECK; a saúde a repete e este caso cobra)
  select string_agg(m[1], ',' order by m[1]) into v
    from pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''::text', 'g') m
   where c.conrelid = 'public.agenda_config'::regclass and c.conname = 'agenda_config_veto_tipos_check';
  select string_agg(m[1], ',' order by m[1]) into v_a
    from regexp_matches(substring(pg_get_functiondef('public._agenda_saude_comunicacao(date, timestamptz)'::regprocedure) from 'c_nunca +constant text\[\] := array\[([^\]]+)\]'), '''([a-z_]+)''', 'g') m;
  r := pg_temp.ok(r, 'V0d a lista do que nunca vence na saúde é a do CHECK agenda_config_veto_tipos_check, nome a nome (20)', v = v_a and v_a like '%dia_avisado%', format('CHECK %s; saúde %s', v, v_a));
  if v_mig = '' then
    r := pg_temp.ok(r, 'V0e as cópias', true, 'PULADO: sem agenda_teste.mig_leituras_fase7f (rode pela bancada)');
  else
    select string_agg(distinct m[1], ',' order by m[1]) into v_a
      from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
    r := pg_temp.ok(r, 'V0e a migration só cria as 2 novas e recria as 3: nada de agenda_decisoes_abertas, agenda_rascunho_aplicar, agenda_ver, agenda_resolver_os, os_carteira nem _agenda_cliente_contexto',
      v_a = '_agenda_perguntas_antes,_agenda_saude_comunicacao,_agenda_ver_decisoes,agenda_saude,agenda_veto_dito', v_a);
    select replace(p.prosrc, E'\r\n', E'\n') into v from pg_proc p where p.oid = 'public._agenda_ver_decisoes(date, timestamptz)'::regprocedure;
    r := pg_temp.ok(r, 'V0f _agenda_ver_decisoes: o corpo vivo é o desta migration; sem os blocos "-- FASE 7f:", é o de 20261107100860 (a mais nova antes), byte a byte',
      v = pg_temp.corpo(v_mig, '_agenda_ver_decisoes') and pg_temp.sem_7f(v) = pg_temp.corpo(current_setting('agenda_teste.mig_correcao3_fase7d'), '_agenda_ver_decisoes'),
      format('vivo %s; sem blocos %s; origem %s', length(v), length(pg_temp.sem_7f(v)), length(pg_temp.corpo(current_setting('agenda_teste.mig_correcao3_fase7d'), '_agenda_ver_decisoes'))));
    select replace(p.prosrc, E'\r\n', E'\n') into v from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure;
    r := pg_temp.ok(r, 'V0g agenda_saude: o corpo vivo é o desta migration; sem as marcas "-- (7f", é o de 20261107100700 (a 7e não existe), byte a byte',
      v = pg_temp.corpo(v_mig, 'agenda_saude') and pg_temp.sem_7f(v) = pg_temp.corpo(current_setting('agenda_teste.mig_leituras_fase7d'), 'agenda_saude'),
      format('vivo %s; sem blocos %s; origem %s', length(v), length(pg_temp.sem_7f(v)), length(pg_temp.corpo(current_setting('agenda_teste.mig_leituras_fase7d'), 'agenda_saude'))));
    select replace(p.prosrc, E'\r\n', E'\n') into v from pg_proc p where p.oid = 'public._agenda_perguntas_antes()'::regprocedure;
    r := pg_temp.ok(r, 'V0h _agenda_perguntas_antes: o corpo vivo é o desta migration; sem o bloco do P7, é o do P1 (20261109100000), byte a byte',
      v = pg_temp.corpo(v_mig, '_agenda_perguntas_antes')
      and pg_temp.sem_p7(v) = pg_temp.corpo(current_setting('agenda_teste.mig_base_fase7f'), '_agenda_perguntas_antes')
      and pg_temp.sem_p7(v) <> v,
      format('vivo %s; do P1 %s', length(v), length(pg_temp.corpo(current_setting('agenda_teste.mig_base_fase7f'), '_agenda_perguntas_antes'))));
    r := pg_temp.ok(r, 'V0i nenhuma das 3 recriadas lê as tabelas de mensagem por texto: a saúde conta a fila só por origem e dia',
      position('whatsapp_messages' in v_mig) = 0 and position('ai_operator_messages' in v_mig) = 0
      and position('f.message' in v_mig) = 0, null);
  end if;
  perform pg_temp.gravar(r);
end
$v0$;

-- ── V1: o foco decisoes ─────────────────────────────────────────────────────────────────────────────
do $v1$
declare
  r      jsonb := '[]';
  v      text;
  v2     text;
  v_dec  jsonb;
  v_ord  jsonb;
  v_m0   text;
  v_lin  text[];
  v_tit  text[];
  v_esp  text[];
  e      jsonb;
  k      int;
  c_h constant date := date '2026-11-10';
  c_a constant timestamptz := timestamptz '2026-11-10 17:30-03';
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V1 o foco', true, 'PULADO: sem a fixture da 7f (rode pela bancada)'));
    return;
  end if;
  -- V1a: o número é o n de agenda_decisoes_abertas, na ordem dela. O controle: com destrava, a ordem do bloco (agenda_perguntas_em_ordem) põe a diária antes do Giancarlo
  begin
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_so_propor = false where id;
    update public.agenda_perguntas set destrava = 9000 where id = pg_temp.q('08');
    v := pg_temp.foco();
    v_dec := public.agenda_decisoes_abertas(c_a);
    v_ord := public.agenda_perguntas_em_ordem(c_h, c_a);
    r := pg_temp.ok(r, 'V1a0 o controle: na ordem do bloco a diária (n 3) vem antes do Giancarlo (n 2)',
      (select (o ->> 'ordem')::int from jsonb_array_elements(v_ord) o where o ->> 'id' = pg_temp.q('08')::text)
      < (select (o ->> 'ordem')::int from jsonb_array_elements(v_ord) o where o ->> 'id' = pg_temp.q('07')::text), v_ord::text);
    k := 0;
    for e in select x from jsonb_array_elements(v_dec) x order by (x ->> 'n')::int loop
      k := k + 1;
      if position(format('Decisão %s: %s', e ->> 'n', left(case when e ->> 'tipo' = 'diaria' then public._agenda_texto_da_diaria((e ->> 'id')::uuid) else e ->> 'texto' end, 60)) in v) = 0 then
        k := -100;
      end if;
    end loop;
    r := pg_temp.ok(r, 'V1a cada "Decisão N:" é a pergunta de n = N em agenda_decisoes_abertas (as 3), na ordem 1, 2, 3, mesmo com a ordem do bloco diferente',
      k = 3 and position('Decisão 1:' in v) < position('Decisão 2:' in v) and position('Decisão 2:' in v) < position('Decisão 3:' in v)
      and position('Decisão 2: O serviço do Giancarlo' in v) > 0 and position('Decisão 3: A diária do Roberto' in v) > 0, v);
    r := pg_temp.ok(r, 'V1a2 o mesmo número do bloco e da linha: a linha do Giancarlo (agenda_perguntas_em_ordem) começa com "Decisão 2:", e o dado decisoes do foco é agenda_decisoes_abertas',
      (select o ->> 'linha' from jsonb_array_elements(v_ord) o where o ->> 'id' = pg_temp.q('07')::text) like 'Decisão 2: %'
      and (public._agenda_ver_decisoes(c_h, c_a) #> '{dados,decisoes}') = v_dec, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V1b e V1c: 8 abertas em 1.800 letras; o corte tira o "Também quero saber" do fim e diz quais. O prazo, com o freio (o caso real), nunca.
  begin
    v_m0 := pg_temp.mostradas();
    foreach v2 in array array['desligado', 'sombra', 'ligado'] loop
      perform pg_temp.modos(v2);
      update public.agenda_config set gestor_so_propor = true where id;
      v := pg_temp.foco();
      v_tit := pg_temp.titulos(v);
      r := pg_temp.ok(r, format('V1b 8 abertas, com o freio, %s: cabe em 1.800 letras, as 3 decisões inteiras, e o "Também esperam" dá o título das 5 que saíram', v2),
        char_length(v) <= 1800 and v like '3 decisões esperam você na agenda:%' and cardinality(v_tit) = 5
        and (select bool_and(position(public._agenda_titulo_da_pergunta(q.texto) in v) > 0) from public.agenda_perguntas q
              where q.id in (pg_temp.q('01'), pg_temp.q('02'), pg_temp.q('03'), pg_temp.q('04'), pg_temp.q('05')))
        and position('Também quero saber' in v) = 0, format('%s letras: %s', char_length(v), v));
      r := pg_temp.ok(r, format('V1c com o freio, %s: nenhuma linha diz "Sem resposta até", nem o *agenda espera*; o "Eu não escolho por você" fica', v2),
        position('Sem resposta até' in v) = 0 and position('agenda espera' in v) = 0 and position('Eu não escolho por você.' in v) > 0, v);
    end loop;
    -- em sombra, sem o freio: também nenhum prazo (R8.6: só ligado escreve)
    perform pg_temp.modos('sombra');
    update public.agenda_config set gestor_so_propor = false where id;
    v := pg_temp.foco();
    r := pg_temp.ok(r, 'V1c2 em sombra, sem o freio: nenhuma linha diz "Sem resposta até"', position('Sem resposta até' in v) = 0 and char_length(v) <= 1800, v);
    -- ligado, sem o freio: a decisão que pode vencer (Giancarlo) tem o prazo curto da linha; as que esperam (Flávio, o cliente; a diária, dinheiro) não; e cabe, com o corte
    perform pg_temp.modos('ligado');
    v := pg_temp.foco();
    v_ord := public.agenda_perguntas_em_ordem(c_h, c_a);
    r := pg_temp.ok(r, 'V1d ligado, sem o freio, 8 abertas: cabe em 1.800 letras; a Decisão 2 (Giancarlo) termina no prazo curto da linha dela; a 1 e a 3 sem prazo; o corte diz as 5',
      char_length(v) <= 1800 and cardinality(pg_temp.titulos(v)) = 5
      and position((select substr(o ->> 'linha', position('Sem resposta até' in o ->> 'linha')) from jsonb_array_elements(v_ord) o where o ->> 'id' = pg_temp.q('07')::text) || E'\nDecisão 3:' in v) > 0
      and (select count(*) from regexp_matches(v, 'Sem resposta até', 'g')) = 1, format('%s letras: %s', char_length(v), v));
    r := pg_temp.ok(r, 'V1e com prazo numa decisão, a linha de como responder perde o "Eu não escolho por você" e ganha o *agenda espera*; o *agenda fica* não aparece',
      position('Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Para uma esperar você, sem prazo: *agenda espera* e o nome.' in v) > 0
      and position('Eu não escolho por você' in v) = 0 and position('agenda fica' in v) = 0, v);
    r := pg_temp.ok(r, 'V1f nenhuma leitura marcou nada: o mostrado e o prazo das perguntas iguais depois das 5 leituras', pg_temp.mostradas() = v_m0, null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V1g a V1i: sem as decisões numeradas e sem a Correa, o "Também quero saber" cabe inteiro (4); o prazo nele; a ordem do bloco, depois de quem tem opções; a linha do *agenda
  -- espera* antes dele
  begin
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V1g' where id in (pg_temp.q('04'), pg_temp.q('06'), pg_temp.q('07'), pg_temp.q('08'));
    update public.agenda_perguntas set destrava = 100 where id = pg_temp.q('05');   -- o Vanderlei passa à frente na ordem do bloco
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_so_propor = false where id;
    v := pg_temp.foco();
    v_ord := public.agenda_perguntas_em_ordem(c_h, c_a);
    v_lin := array(select l from unnest(string_to_array(v, E'\n')) l where l like 'Também quero saber: %');
    v_esp := array(select (select q.texto from public.agenda_perguntas q where q.id = (o ->> 'id')::uuid) from jsonb_array_elements(v_ord) o order by (o ->> 'ordem')::int);
    r := pg_temp.ok(r, 'V1g as 4, na ordem do bloco (o Vanderlei, que destrava mais, logo depois dos seus dias), cada uma com o texto inteiro da pergunta',
      cardinality(v_lin) = 4 and cardinality(v_esp) = 4
      and (select bool_and(v_lin[o] like 'Também quero saber: ' || replace(replace(v_esp[o], '%', '\%'), '_', '\_') || '%') from generate_series(1, 4) o)
      and v_lin[1] like 'Também quero saber: Quais dias você fica em campo%' and v_lin[2] like 'Também quero saber: A OS do Vanderlei%', v);
    r := pg_temp.ok(r, 'V1h o prazo só onde a linha o escreve (a mesma forma do bloco): cada "Também quero saber" termina no trecho "Sem resposta até…" da linha dela, ou sem nada',
      (select bool_and(case when o ->> 'veto_ate' is null then position('Sem resposta até' in v_lin[(o ->> 'ordem')::int]) = 0
                            else v_lin[(o ->> 'ordem')::int] like '%' || substr(o ->> 'linha', position('Sem resposta até' in o ->> 'linha')) end)
         from jsonb_array_elements(v_ord) o)
      and (select count(*) from jsonb_array_elements(v_ord) o where o ->> 'veto_ate' is not null) >= 3, format('%s / %s', v, v_ord));
    r := pg_temp.ok(r, 'V1i sem decisão numerada, a linha do *agenda espera* vem antes do "Também quero saber" (o corte tira do fim)',
      position(E'Para uma pergunta esperar você, sem prazo: *agenda espera* e o nome.\nTambém quero saber: ' in v) > 0 and position('Eu não escolho' in v) = 0, v);
    -- o mesmo com o freio: as 5, a mesma ordem, nenhum prazo, nenhuma linha do *agenda espera*
    update public.agenda_config set gestor_so_propor = true where id;
    v2 := pg_temp.foco();
    r := pg_temp.ok(r, 'V1i2 o mesmo cenário com o freio: as mesmas 4, na mesma ordem, sem prazo e sem a linha do *agenda espera*',
      position('Sem resposta até' in v2) = 0 and position('agenda espera' in v2) = 0
      and array(select regexp_replace(l, ' Sem resposta até.*$', '') from unnest(v_lin) l) = array(select l from unnest(string_to_array(v2, E'\n')) l where l like 'Também quero saber: %'), v2);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- V1i3: decisões numeradas sem prazo (o Giancarlo espera você; o Flávio espera o cliente; a diária é dinheiro) e prazo só no "Também quero saber": o "Eu não escolho por você"
  -- continua verdade para as decisões, e fica, com o *agenda espera* no fim da mesma linha
  begin
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_so_propor = false where id;
    perform pg_temp.espera('Giancarlo', c_h, c_a);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V1i3' where id in (pg_temp.q('02'), pg_temp.q('03'), pg_temp.q('04'), pg_temp.q('05'));
    v := pg_temp.foco();
    r := pg_temp.ok(r, 'V1i3 nenhuma decisão com prazo e prazo no "Também quero saber": "Eu não escolho por você." fica, com o *agenda espera* no fim',
      position('Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você. Para uma esperar você, sem prazo: *agenda espera* e o nome.' in v) > 0
      and (select count(*) from regexp_matches(v, 'Sem resposta até', 'g')) = 1 and position('Decisão 1:' in v) > 0, v);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V1j: contra a origem (a 7d), na mesma fixture: em desligado, sombra e ligado com o freio, as mesmas linhas, e só a ordem do "Também quero saber" (aqui, os títulos do corte)
  -- muda. Na fixture as duas ordens já diferem: a 7d vai por perda_em; a do bloco põe os seus dias primeiro e as de prazo antes das sem prazo.
  begin
    foreach v2 in array array['desligado', 'sombra', 'ligado'] loop
      perform pg_temp.modos(v2);
      update public.agenda_config set gestor_so_propor = true where id;
      v := pg_temp.foco();
      v_m0 := pg_temp.dec_7d(c_h, c_a) ->> 'texto';
      r := pg_temp.ok(r, format('V1j %s com o freio, contra a 7d: as linhas iguais fora a do corte; os títulos do corte, os mesmos, em outra ordem (a do bloco)', v2),
        array(select l from unnest(string_to_array(v, E'\n')) l where l not like 'Também esperam: %')
          = array(select l from unnest(string_to_array(v_m0, E'\n')) l where l not like 'Também esperam: %')
        and array(select x from unnest(pg_temp.titulos(v)) x order by x) = array(select x from unnest(pg_temp.titulos(v_m0)) x order by x)
        and pg_temp.titulos(v) <> pg_temp.titulos(v_m0), format('novo %s / 7d %s', pg_temp.titulos(v), pg_temp.titulos(v_m0)));
    end loop;
    -- a ordem nova é a do bloco (agenda_perguntas_em_ordem: os seus dias, o prazo mais cedo, a de antes no empate): título a título, na ordem dela
    r := pg_temp.ok(r, 'V1j3 os títulos do corte vêm na ordem do bloco (agenda_perguntas_em_ordem), um a um: os seus dias, as 2 com prazo, e as sem prazo',
      pg_temp.titulos(v) = array(select public._agenda_titulo_da_pergunta(q.texto)
                                   from jsonb_array_elements(public.agenda_perguntas_em_ordem(c_h, c_a)) o
                                   join public.agenda_perguntas q on q.id = (o ->> 'id')::uuid
                                  where q.id in (pg_temp.q('01'), pg_temp.q('02'), pg_temp.q('03'), pg_temp.q('04'), pg_temp.q('05'))
                                  order by (o ->> 'ordem')::int),
      format('novo %s', pg_temp.titulos(v)));
    -- os dados que o assistente lê: as decisões iguais; as abertas sem número, as mesmas, em outra ordem
    perform pg_temp.modos('sombra');
    r := pg_temp.ok(r, 'V1j2 os dados do foco: decisoes igual à 7d; abertas, as mesmas da 7d, só em outra ordem; outras, o mesmo número',
      (public._agenda_ver_decisoes(c_h, c_a) #> '{dados,decisoes}') = (pg_temp.dec_7d(c_h, c_a) #> '{dados,decisoes}')
      and (public._agenda_ver_decisoes(c_h, c_a) #> '{dados,outras}') = (pg_temp.dec_7d(c_h, c_a) #> '{dados,outras}')
      and (select array_agg(x::text order by x::text) from jsonb_array_elements(public._agenda_ver_decisoes(c_h, c_a) #> '{dados,abertas}') x)
          = (select array_agg(x::text order by x::text) from jsonb_array_elements(pg_temp.dec_7d(c_h, c_a) #> '{dados,abertas}') x)
      and (public._agenda_ver_decisoes(c_h, c_a) #> '{dados,abertas}') <> (pg_temp.dec_7d(c_h, c_a) #> '{dados,abertas}'), null);
    -- e o "Nada esperando": igual
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V1k' where estado = 'aberta';
    r := pg_temp.ok(r, 'V1k nada aberto: "Nada esperando você na agenda agora.", como antes', pg_temp.foco() = 'Nada esperando você na agenda agora.' and pg_temp.foco() = (pg_temp.dec_7d(c_h, c_a) ->> 'texto'), pg_temp.foco());
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- V1m (NOVO-agenda-121): o corte pelo caminho de verdade. O WhatsApp chama agenda_ver como service_role, e o painel com o JWT do administrador: _agenda_ver_decisoes é invoker e
  -- chama _agenda_titulo_da_pergunta no corte, que a 7d deixou sem grant. Com 8 abertas, o mesmo texto do teste (que roda como dono do banco), sem "permission denied".
  r := pg_temp.ok(r, 'V1m 8 abertas, acima das 1.800 letras, pelo service_role e pelo administrador logado: o mesmo texto, com o corte (a 7d dava permission denied)',
    pg_temp.como(null, 'service_role', format($q$select public._agenda_ver_decisoes(%L, %L) ->> 'texto'$q$, c_h, c_a)) = pg_temp.foco()
    and pg_temp.como(pg_temp.adm(), 'authenticated', format($q$select public._agenda_ver_decisoes(%L, %L) ->> 'texto'$q$, c_h, c_a)) = pg_temp.foco()
    and pg_temp.foco() like '%Também esperam: %',
    pg_temp.como(null, 'service_role', format($q$select public._agenda_ver_decisoes(%L, %L) ->> 'texto'$q$, c_h, c_a)));
  -- V1m2: a porta do título (o V1m roda depois do mesmo foco como dono do banco, e o plpgsql reaproveita o plano na sessão: quem morde de ponta a ponta é o eval K140, que
  -- chama pelo service_role numa sessão nova). _agenda_ver_decisoes é invoker e chama o título.
  r := pg_temp.ok(r, 'V1m2 _agenda_titulo_da_pergunta: authenticated e service_role podem; o anon não; e o foco, invoker, a chama',
    has_function_privilege('service_role', 'public._agenda_titulo_da_pergunta(text)', 'execute')
    and has_function_privilege('authenticated', 'public._agenda_titulo_da_pergunta(text)', 'execute')
    and not has_function_privilege('anon', 'public._agenda_titulo_da_pergunta(text)', 'execute')
    and not (select prosecdef from pg_proc where oid = 'public._agenda_ver_decisoes(date, timestamptz)'::regprocedure)
    and (select prosrc from pg_proc where oid = 'public._agenda_ver_decisoes(date, timestamptz)'::regprocedure) like '%public._agenda_titulo_da_pergunta(%', null);
  -- V1l: pelo roteador (agenda_ver foco decisoes), o mesmo texto
  r := pg_temp.ok(r, 'V1l agenda_ver foco decisoes devolve o texto do foco (o roteador não foi recriado)',
    (public.agenda_ver(pg_temp.adm(), null, null, 'decisoes', null, null, false, c_h) ->> 'texto') = pg_temp.foco(), null);
  perform pg_temp.gravar(r);
end
$v1$;

-- ── V2: *agenda espera <nome>* ──────────────────────────────────────────────────────────────────────
do $v2$
declare
  r      jsonb := '[]';
  v      jsonb;
  v_t    text;
  v_m0   text;
  v_q    public.agenda_perguntas;
  v_id   uuid;
  c_h constant date := date '2026-11-10';
  c_a constant timestamptz := timestamptz '2026-11-10 17:30-03';
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V2 o *agenda espera*', true, 'PULADO: sem a fixture da 7f (rode pela bancada)'));
    return;
  end if;
  -- V2a: só espera
  begin
    v_m0 := md5((select string_agg(to_jsonb(q)::text, ',' order by q.id) from public.agenda_perguntas q));
    v_t := pg_temp.lanca(format($q$select public.agenda_veto_dito(%L, 'fica', null, %L, %L)$q$, pg_temp.adm(), c_h, c_a));
    r := pg_temp.ok(r, 'V2a *agenda fica* não existe: 22023, com a saída (o silêncio e o *agenda espera*), e nada muda',
      v_t like '22023: Não existe *agenda fica*: sem resposta, cada pergunta fica como eu disse%*agenda espera* e o nome.'
      and md5((select string_agg(to_jsonb(q)::text, ',' order by q.id) from public.agenda_perguntas q)) = v_m0, v_t);
    r := pg_temp.ok(r, 'V2a2 sem o dia ou a hora: 22004, dela (antes de ler qualquer coisa)',
      pg_temp.lanca(format($q$select public.agenda_veto_dito(%L, 'espera', 'Nelson', null, %L)$q$, pg_temp.adm(), c_a)) like '22004: agenda_veto_dito: sem o dia ou a hora%'
      and pg_temp.lanca(format($q$select public.agenda_veto_dito(%L, 'espera', 'Nelson', %L, null)$q$, pg_temp.adm(), c_h)) like '22004: agenda_veto_dito: sem o dia ou a hora%', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V2b a V2d: com o freio (o caso real), o Nelson. O nome é ambíguo no resolvedor (3 Nelson na carteira da bancada), e só a OS-F1 tem pergunta aberta: é ela.
  begin
    perform pg_temp.modos('sombra');
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.ok(r, 'V2b0 o controle: "Nelson" é ambíguo no resolvedor, e a pergunta da OS-F1 tem o prazo de ter 10/11 18:00, mostrada antes dele',
      public.agenda_resolver_os('Nelson', c_h) ->> 'status' = 'ambiguo'
      and (select veto_ate = timestamptz '2026-11-10 18:00-03' and mostrada_vezes > 0 and veto_espera is null from public.agenda_perguntas where id = pg_temp.q('02')), null);
    v_m0 := md5((select string_agg(to_jsonb(q)::text, ',' order by q.id) from public.agenda_perguntas q where q.id <> pg_temp.q('02')));
    v := pg_temp.espera('Nelson', c_h, c_a);
    select * into v_q from public.agenda_perguntas where id = pg_temp.q('02');
    r := pg_temp.ok(r, 'V2b *agenda espera Nelson*, com o freio: o texto da §6.2; a pergunta do Nelson ganha veto_espera = dono e o prazo nulo; as outras não mudam',
      v ->> 'texto' = 'Combinado: a pergunta de Nelson espera você, sem prazo.' and (v ->> 'mudou')::boolean and v ->> 'pergunta_id' = pg_temp.q('02')::text
      and v_q.veto_espera = 'dono' and v_q.veto_ate is null and v_q.estado = 'aberta'
      and md5((select string_agg(to_jsonb(x)::text, ',' order by x.id) from public.agenda_perguntas x where x.id <> pg_temp.q('02'))) = v_m0, v::text);
    -- V2c: não vence mais. A função do P2 que vence no prazo, ligada de verdade e sem o freio, depois do prazo de antes: o Nelson fica; o Lenine (a mesma forma) vence (o controle)
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_so_propor = false where id;
    v := public._agenda_gestor_vetos(c_h, timestamptz '2026-11-10 18:07-03');
    r := pg_temp.ok(r, 'V2c pelo prazo (_agenda_gestor_vetos, ligado, sem o freio, às 18:07): a do Nelson fica aberta e sem assumida; a do Lenine, que não espera, vence (o controle)',
      (select estado = 'aberta' and assumida_por is null and veto_ate is null from public.agenda_perguntas where id = pg_temp.q('02'))
      and (select assumida_por = 'prazo' from public.agenda_perguntas where id = pg_temp.q('03')), v::text);
    -- pelo teto (_agenda_comunicar_teto): com o teto em 3 sobra o Nelson para fechar, e ele não fecha; as outras de efeito nada, sim
    update public.agenda_config set perguntas_abertas_max = 3 where id;
    v := public._agenda_comunicar_teto(c_h, timestamptz '2026-11-10 18:08-03');
    r := pg_temp.ok(r, 'V2c2 pelo teto (_agenda_comunicar_teto, acima de 3): fecham as de efeito nada que podem vencer, nunca a do Nelson',
      (select estado = 'aberta' and assumida_por is null from public.agenda_perguntas where id = pg_temp.q('02'))
      and (v ->> 'assumidas')::int >= 1, v::text);
    -- pela linha e pelo registro do fechamento (P3): a linha não tem prazo, e o registro não regrava
    v := public._agenda_pergunta_linha(pg_temp.q('02'), c_h, timestamptz '2026-11-10 18:10-03');
    r := pg_temp.ok(r, 'V2d a linha do Nelson (a do bloco e da quinta) não tem prazo nem "Sem resposta até", e veto_ate nulo',
      v ->> 'veto_ate' is null and position('Sem resposta até' in v ->> 'texto') = 0 and v ->> 'texto' like '%Nelson%', v::text);
    update public.agenda_config set modo_bloco_agenda = 'ligado' where id;
    perform set_config('agenda.agora', '2026-11-10 18:10:00-03', true);
    v := public.agenda_textos_do_fechamento(c_h, public.agenda_somar_du(c_h, 1)) -> 'bloco';
    perform public.agenda_fechamento_registrar(c_h, (select coalesce(jsonb_agg(l), '[]'::jsonb) from jsonb_array_elements(v -> 'linhas') l), 'fechamento',
                                               timestamptz '2026-11-10 18:12-03');
    r := pg_temp.ok(r, 'V2d2 o registro do fechamento (agenda_fechamento_registrar, P3) com as linhas do bloco ligado não regrava o prazo do Nelson',
      (select veto_ate is null and veto_espera = 'dono' from public.agenda_perguntas where id = pg_temp.q('02')), v::text);
    perform set_config('agenda.agora', '2026-11-10 17:30:00-03', true);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V2e a V2i: os outros caminhos
  begin
    perform pg_temp.modos('sombra');
    -- o nome que não casa: a lista das que podem esperar, na ordem do bloco, sem os dias do dono e sem a Correa (sem OS nem fornecedor na chave)
    v := pg_temp.espera('Tadeu', c_h, c_a);
    r := pg_temp.ok(r, 'V2e o nome sem pergunta aberta (o Tadeu): nao_achei e a lista, na ordem do bloco, sem os dias do dono nem a Correa; nada muda',
      v ->> 'status' = 'nao_achei' and not (v ->> 'mudou')::boolean
      and v ->> 'texto' = 'Não achei pergunta aberta de Tadeu. Podem esperar você: Flávio, Nelson, Lenine, Vanderlei e Giancarlo. Diga *agenda espera* e o nome.'
      and not exists (select 1 from public.agenda_perguntas where veto_espera = 'dono'), v::text);
    v := pg_temp.espera('Fulano de Tal', c_h, c_a);
    r := pg_temp.ok(r, 'V2e2 o nome que não é de ninguém: a mesma lista', v ->> 'status' = 'nao_achei' and v ->> 'texto' like 'Não achei pergunta aberta de Fulano de Tal. Podem esperar você: Flávio,%', v::text);
    -- os dias do dono (AG7-37): nenhum nome os alcança
    v_m0 := md5((select to_jsonb(x)::text from public.agenda_perguntas x where x.id = pg_temp.q('01')));
    v := pg_temp.espera('você', c_h, c_a);
    r := pg_temp.ok(r, 'V2f a pergunta dos seus dias em campo (padrao_do_dono, AG7-37) não é alvo: "você" não acha nada, e ela não muda',
      v ->> 'status' = 'nao_achei' and md5((select to_jsonb(x)::text from public.agenda_perguntas x where x.id = pg_temp.q('01'))) = v_m0, v::text);
    -- a que já espera: o Flávio (espera o cliente desde que nasceu)
    v := pg_temp.espera('Flávio', c_h, c_a);
    r := pg_temp.ok(r, 'V2g a que já espera (o Flávio, mexe no dia que o cliente já sabe): ja_espera, nada muda',
      v ->> 'status' = 'ja_espera' and not (v ->> 'mudou')::boolean and v ->> 'texto' = 'A pergunta de Flávio já espera você: ela não fica com o padrão sozinha.'
      and (select veto_espera from public.agenda_perguntas where id = pg_temp.q('06')) = 'cliente', v::text);
    -- a crítica que pode vencer (Giancarlo) também pode esperar; e pelo número da OS
    v := pg_temp.espera('Giancarlo', c_h, c_a);
    r := pg_temp.ok(r, 'V2h a crítica que pode vencer (Giancarlo, AG7-15) também passa a esperar, pelo nome; a linha dela perde a opção que fica',
      v ->> 'texto' = 'Combinado: a pergunta de Giancarlo espera você, sem prazo.' and (select veto_espera from public.agenda_perguntas where id = pg_temp.q('07')) = 'dono'
      and position('Recomendo a opção' in public._agenda_pergunta_linha(pg_temp.q('07'), c_h, c_a) ->> 'texto') = 0, v::text);
    -- dito de novo: a 2ª vez já espera
    v := pg_temp.espera('Giancarlo', c_h, c_a);
    r := pg_temp.ok(r, 'V2h2 de novo: "já espera você", nada muda', v ->> 'status' = 'ja_espera' and v ->> 'texto' = 'A pergunta de Giancarlo já espera você: ela não fica com o padrão sozinha.', v::text);
    -- o Vanderlei tem 3: a parada e um estouro (os 2 podem esperar; a parada vem antes na ordem do bloco: a mais velha) e a diária (dinheiro); vai a 1ª que pode, na ordem
    insert into public.agenda_perguntas (chave, tipo, texto, modo, service_order_id, os_ids, perda_em, expira_em, criada_em)
    values ('estouro:teste-v2i', 'estouro', 'A OS do Vanderlei (motorhome, Instalação de carregador) passou do previsto. Deixo como está no plano?', 'ligado',
            pg_temp.os('303'), array[pg_temp.os('303')], date '2026-11-13', timestamptz '2026-11-17 18:00-03', timestamptz '2026-11-10 16:00-03');
    v := pg_temp.espera('Vanderlei', c_h, c_a);
    r := pg_temp.ok(r, 'V2i o nome com 3 abertas: vai a 1ª que ainda pode esperar na ordem do bloco (a parada do Vanderlei), nem o estouro (depois dela) nem a diária',
      v ->> 'pergunta_id' = pg_temp.q('05')::text and (select veto_espera from public.agenda_perguntas where id = pg_temp.q('05')) = 'dono'
      and (select veto_espera from public.agenda_perguntas where chave = 'estouro:teste-v2i') is null
      and (select veto_espera from public.agenda_perguntas where id = pg_temp.q('08')) = 'dinheiro', v::text);
    -- dito de novo, a próxima que pode: o estouro
    v := pg_temp.espera('Vanderlei', c_h, c_a);
    r := pg_temp.ok(r, 'V2i2 de novo, a próxima do mesmo nome que ainda pode esperar (o estouro)',
      v ->> 'status' = 'espera' and (select veto_espera from public.agenda_perguntas where chave = 'estouro:teste-v2i') = 'dono', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V2j: o prazo próprio (um tipo com relógio dele, espera = tipo, com veto_ate) e a de opcao_padrao (o CHECK veto_padrao_tem_prazo segura o prazo)
  begin
    insert into public.agenda_perguntas (chave, tipo, texto, modo, service_order_id, os_ids, opcoes, recomendacao, veto_ate, perda_em, expira_em)
    values ('situacao:teste-v2j', 'situacao', 'A OS do Tadeu (motorhome, Instalação de placa solar) está parada: quanto falta? 1) Metade. 2) Quase tudo.', 'ligado',
            pg_temp.os('306'), array[pg_temp.os('306')], '[{"n": 1, "texto": "Metade"}, {"n": 2, "texto": "Quase tudo"}]', 1,
            timestamptz '2026-11-11 18:00-03', date '2026-11-11', timestamptz '2026-11-12 18:00-03')
    returning id into v_id;
    v := pg_temp.espera('Tadeu', c_h, c_a);
    r := pg_temp.ok(r, 'V2j o tipo com prazo próprio (situacao, espera = tipo): prazo_proprio, com o dia e a hora dele, e nada muda',
      v ->> 'status' = 'prazo_proprio'
      and v ->> 'texto' = 'A pergunta de Tadeu tem prazo próprio, até qua 11/11 às 18:00: o *agenda espera* não muda esse. Para outra escolha, responda a pergunta.'
      and (select veto_espera = 'tipo' and veto_ate = timestamptz '2026-11-11 18:00-03' from public.agenda_perguntas where id = v_id), v::text);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V2j' where id = v_id;
    insert into public.agenda_perguntas (chave, tipo, texto, modo, service_order_id, os_ids, opcoes, recomendacao, opcao_padrao, veto_ate, perda_em, expira_em)
    values ('duracao:teste-v2j', 'duracao', 'A OS do Tadeu (motorhome, Instalação de placa solar) ainda não tem a duração dita. 1) 2 dias. 2) 3 dias.', 'ligado',
            pg_temp.os('306'), array[pg_temp.os('306')], '[{"n": 1, "texto": "2 dias"}, {"n": 2, "texto": "3 dias"}]', 1, 1,
            timestamptz '2026-11-11 18:00-03', date '2026-11-11', timestamptz '2026-11-12 18:00-03')
    returning id into v_id;
    v := pg_temp.espera('Tadeu', c_h, c_a);
    r := pg_temp.ok(r, 'V2j2 com opcao_padrao, o prazo fica (veto_padrao_tem_prazo) e a pergunta passa a esperar: nada lança',
      v ->> 'status' = 'espera' and (select veto_espera = 'dono' and veto_ate is not null from public.agenda_perguntas where id = v_id), v::text);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V2j2' where id = v_id;
    -- a OS só em os_ids (sem service_order_id) também é dela
    insert into public.agenda_perguntas (chave, tipo, texto, modo, service_order_id, os_ids, perda_em, expira_em)
    values ('parada:teste-v2j3', 'parada', 'A instalação de placa solar está parada há 3 dias úteis. Deixo como está no plano?', 'ligado',
            null, array[pg_temp.os('306')], date '2026-11-13', timestamptz '2026-11-17 18:00-03')
    returning id into v_id;
    v := pg_temp.espera('Tadeu', c_h, c_a);
    r := pg_temp.ok(r, 'V2j3 a pergunta com a OS só em os_ids: o nome do cliente dela a acha',
      v ->> 'status' = 'espera' and v ->> 'pergunta_id' = v_id::text and (select veto_espera from public.agenda_perguntas where id = v_id) = 'dono', v::text);
    -- os dias do dono com OS (como a do Rodrigo em produção, se viesse com a OS): nem assim é alvo (AG7-37)
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V2j3' where id = v_id;
    insert into public.agenda_perguntas (chave, tipo, texto, modo, service_order_id, os_ids, perda_em, expira_em)
    values ('padrao_do_dono:teste-v2j3', 'padrao_do_dono', 'Para marcar Tadeu (OS-F6), preciso saber em que dias você fica em campo.', 'ligado',
            pg_temp.os('306'), array[pg_temp.os('306')], date '2026-11-13', timestamptz '2026-11-17 18:00-03')
    returning id into v_id;
    v := pg_temp.espera('Tadeu', c_h, c_a);
    r := pg_temp.ok(r, 'V2f2 os seus dias em campo com a OS do Tadeu: *agenda espera Tadeu* não os alcança (nao_achei), e a pergunta não muda (AG7-37)',
      v ->> 'status' = 'nao_achei' and (select veto_espera from public.agenda_perguntas where id = v_id) is null, v::text);
    -- e com a OS de outro Nelson (OS-J2): "Nelson" continua ambíguo no resolvedor, e os dias do dono não contam como pergunta dele; vai a do Nelson da OS-F1
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V2f3' where id = v_id;
    insert into public.agenda_perguntas (chave, tipo, texto, modo, service_order_id, os_ids, perda_em, expira_em)
    values ('padrao_do_dono:teste-v2f3', 'padrao_do_dono', 'Para marcar Nelson (OS-J2), preciso saber em que dias você fica em campo.', 'ligado',
            'd7d00000-0000-4000-8000-000000097202', array['d7d00000-0000-4000-8000-000000097202'::uuid], date '2026-11-13', timestamptz '2026-11-17 18:00-03')
    returning id into v_id;
    v := pg_temp.espera('Nelson', c_h, c_a);
    r := pg_temp.ok(r, 'V2f3 os seus dias com a OS de outro Nelson: o ambíguo vai à do Nelson da OS-F1, não pergunta qual; os seus dias não mudam',
      v ->> 'status' = 'espera' and v ->> 'pergunta_id' = pg_temp.q('02')::text and (select veto_espera from public.agenda_perguntas where id = v_id) is null, v::text);
    -- o fornecedor da pergunta (sem OS): pelo nome dele
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V2f2' where id = v_id;
    insert into public.suppliers (id, name, display_name, active) values ('f7f00000-0000-4000-8000-00000000f7a1', 'Correa Materiais Elétricos Ltda', 'Correa', true);
    insert into public.agenda_perguntas (chave, tipo, texto, modo, perda_em, expira_em)
    values ('fornecedor_cadastro:f7f00000-0000-4000-8000-00000000f7a1', 'fornecedor_cadastro', 'A Correa não tem cadastro de prazo. Conto 7 dias úteis?', 'ligado',
            date '2026-11-13', timestamptz '2026-11-17 18:00-03')
    returning id into v_id;
    v := pg_temp.espera('Correa', c_h, c_a);
    r := pg_temp.ok(r, 'V2j4 sem OS, o fornecedor da pergunta pelo nome: *agenda espera Correa* acha a do cadastro dela',
      v ->> 'status' = 'espera' and v ->> 'pergunta_id' = v_id::text and v ->> 'texto' = 'Combinado: a pergunta de Correa espera você, sem prazo.', v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V2k: o gatilho. O prazo vai a nulo só junto de veto_espera de nulo a dono
  begin
    r := pg_temp.ok(r, 'V2k o prazo não vai a nulo sozinho, nem com veto_espera = sem_padrao: "A pergunta não muda o que pergunta"',
      pg_temp.lanca(format($q$update public.agenda_perguntas set veto_ate = null where id = %L$q$, pg_temp.q('02'))) like '%A pergunta não muda o que pergunta%'
      and pg_temp.lanca(format($q$update public.agenda_perguntas set veto_ate = null, veto_espera = 'sem_padrao' where id = %L$q$, pg_temp.q('02'))) like '%A pergunta não muda o que pergunta%', null);
    r := pg_temp.ok(r, 'V2k2 junto de veto_espera de nulo a dono, vai; e a que já espera não volta a nulo',
      pg_temp.lanca(format($q$update public.agenda_perguntas set veto_ate = null, veto_espera = 'dono' where id = %L$q$, pg_temp.q('02'))) = 'ok'
      and pg_temp.lanca(format($q$update public.agenda_perguntas set veto_espera = null where id = %L$q$, pg_temp.q('02'))) like '%A pergunta não muda o que pergunta%', null);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V2l: as portas
  r := pg_temp.ok(r, 'V2l só o administrador: o técnico e o anon não chegam (42501); pelo service_role, com p_autor que não é administrador, 42501',
    pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated', format($q$select public.agenda_veto_dito(null, 'espera', 'Nelson', %L, %L)::text$q$, c_h, c_a)) like 'erro 42501%'
    and pg_temp.como(null, 'anon', format($q$select public.agenda_veto_dito(null, 'espera', 'Nelson', %L, %L)::text$q$, c_h, c_a)) like 'erro 42501%'
    and pg_temp.como(null, 'service_role', format($q$select public.agenda_veto_dito(%L, 'espera', 'Nelson', %L, %L)::text$q$, 'aa000000-0000-4000-8000-0000000000ff', c_h, c_a)) like 'erro 42501%'
    and pg_temp.como(null, 'service_role', format($q$select public.agenda_veto_dito(%L, 'espera', 'Fulano', %L, %L)::text$q$, pg_temp.adm(), c_h, c_a)) like '%nao_achei%', null);
  perform pg_temp.gravar(r);
end
$v2$;

-- ── V3: a saúde da comunicação ──────────────────────────────────────────────────────────────────────
do $v3$
declare
  r      jsonb := '[]';
  v      jsonb;
  s      jsonb;
  v2     text;
  c_h constant date := date '2026-11-10';
  c_a constant timestamptz := timestamptz '2026-11-10 17:30-03';
  c_zeros constant text[] := array['assumida_sem_prazo_mostrado', 'assumida_que_esperava', 'assumida_tipo_proibido', 'teto_passou_sem_motivo', 'bloco_grande', 'excecao_acima_do_teto'];
begin
  if not pg_temp.na_bancada() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'V3 a saúde', true, 'PULADO: sem a fixture da 7f (rode pela bancada)'));
    return;
  end if;
  -- V3a: nada aconteceu = os 6 zeros, em todo modo, e o ok de antes
  foreach v2 in array array['desligado', 'sombra', 'ligado'] loop
    perform pg_temp.modos(v2);
    s := public.agenda_saude(c_h, c_a);
    v := s -> 'comunicacao';
    r := pg_temp.ok(r, format('V3a %s: os 6 zeros, zeros_ok, e o ok de agenda_saude o de antes (a 7d, sem a chave nova)', v2),
      (select bool_and((v ->> z)::int = 0) from unnest(c_zeros) z) and (v ->> 'zeros_ok')::boolean
      and (s ->> 'ok') = (pg_temp.saude_7d(c_h, c_a) ->> 'ok')
      and v -> 'modos' = jsonb_build_object('bloco', v2, 'lote', v2, 'veto', v2, 'previsto', v2, 'convite', v2, 'camadas', v2), v::text);
  end loop;
  perform pg_temp.modos('desligado');
  r := pg_temp.ok(r, 'V3a2 com os 6 desligados, contra a 7d: só a chave comunicacao a mais, o resto byte a byte; e os números não são lidos',
    (public.agenda_saude(c_h, c_a) - 'comunicacao') = pg_temp.saude_7d(c_h, c_a) and (public.agenda_saude(c_h, c_a) #> '{comunicacao,numeros}') = '{}'::jsonb, null);

  -- V3b: cada violação forçada conta 1, e só ela; o ok de agenda_saude cai
  begin
    perform pg_temp.modos('sombra');
    r := pg_temp.ok(r, 'V3b0 o controle: na cópia de agenda_saude com o resto do ok em verdadeiro, sem violação o ok é verdadeiro (e o de agenda_saude já é falso na fixture)',
      (pg_temp.saude_so_zeros(c_h, c_a) ->> 'ok')::boolean and not (public.agenda_saude(c_h, c_a) ->> 'ok')::boolean
      and pg_temp.saude_so_zeros(c_h, c_a) - 'ok' = public.agenda_saude(c_h, c_a) - 'ok', null);
    -- assumida pelo prazo sem ter sido mostrada antes dele (a Correa nunca foi mostrada)
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V3b', assumida_por = 'prazo', assumida_em = c_a where id = pg_temp.q('04');
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3b assumida_sem_prazo_mostrado = 1 (a Correa, nunca mostrada), e só ela; zeros_ok falso e o ok de agenda_saude cai',
      (v ->> 'assumida_sem_prazo_mostrado')::int = 1 and (select bool_and((v ->> z)::int = 0) from unnest(c_zeros) z where z <> 'assumida_sem_prazo_mostrado')
      and not (v ->> 'zeros_ok')::boolean and not (public.agenda_saude(c_h, c_a) ->> 'ok')::boolean and not (pg_temp.saude_so_zeros(c_h, c_a) ->> 'ok')::boolean, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.modos('sombra');
    -- assumida pelo teto a que esperava o cliente (o Flávio)
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V3b2', assumida_por = 'teto', assumida_em = c_a where id = pg_temp.q('06');
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3b2 assumida_que_esperava = 1 (o Flávio, que esperava o cliente), e só ela',
      (v ->> 'assumida_que_esperava')::int = 1 and (select bool_and((v ->> z)::int = 0) from unnest(c_zeros) z where z <> 'assumida_que_esperava'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.modos('sombra');
    -- assumida de tipo que nunca vence: a diária, com veto_espera nula à força (só a migration liga agenda.backfill_padrao; aqui, para isolar o zero)
    perform set_config('agenda.backfill_padrao', 'on', true);
    update public.agenda_perguntas set veto_espera = null where id = pg_temp.q('08');
    perform set_config('agenda.backfill_padrao', '', true);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V3b3', assumida_por = 'teto', assumida_em = c_a where id = pg_temp.q('08');
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3b3 assumida_tipo_proibido = 1 (a diária: dinheiro nunca vence), e só ela',
      (v ->> 'assumida_tipo_proibido')::int = 1 and (select bool_and((v ->> z)::int = 0) from unnest(c_zeros) z where z <> 'assumida_tipo_proibido'), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    -- o teto passou sem motivo: 8 abertas, teto 7, uma rodada comunicar depois de todas nascerem, o prazo ligado de verdade, e nenhuma fechada
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_so_propor = false, perguntas_abertas_max = 7 where id;
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    values (c_a, c_h, c_a - interval '15 minutes', 'ligado', 'ligado', '{}', 0, 1, 'comunicar', 'desligado', 'desligado');
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3b4 teto_passou_sem_motivo = 1 (8 abertas, teto 7, e o teto não fechou nenhuma das que podia), e só ela',
      (v ->> 'teto_passou_sem_motivo')::int = 1 and (select bool_and((v ->> z)::int = 0) from unnest(c_zeros) z where z <> 'teto_passou_sem_motivo'), v::text);
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.ok(r, 'V3b4 o controle: com o freio o teto não age, e não é violação', ((public.agenda_saude(c_h, c_a) -> 'comunicacao') ->> 'teto_passou_sem_motivo')::int = 0, null);
    -- a rodada de antes de todas nascerem não teve a chance de fechar nenhuma: não é violação
    update public.agenda_config set gestor_so_propor = false where id;
    update public.agenda_vigia_rodadas set p_agora = timestamptz '2026-11-01 10:00-03' where rotina = 'comunicar' and p_hoje = c_h;
    r := pg_temp.ok(r, 'V3b4b a última rodada comunicar é de antes de todas nascerem: o teto ainda não teve a chance, 0',
      ((public.agenda_saude(c_h, c_a) -> 'comunicacao') ->> 'teto_passou_sem_motivo')::int = 0, null);
    update public.agenda_vigia_rodadas set p_agora = c_a - interval '15 minutes' where rotina = 'comunicar' and p_hoje = c_h;
    -- o teto só fecha efeito nada que pode vencer: com as de efeito nada esperando o dono ou fechadas, sobra só o Giancarlo (efeito opcao), e o teto passa com motivo
    update public.agenda_config set perguntas_abertas_max = 5 where id;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste V3b4c' where id in (pg_temp.q('01'), pg_temp.q('04'));
    perform pg_temp.espera(x, c_h, c_a) from unnest(array['Nelson', 'Lenine', 'Vanderlei']) x;
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3b4c 6 abertas, teto 5: as de efeito nada esperam você, e a que sobra (Giancarlo) é de efeito opcao, que o teto não fecha: 0',
      (v ->> 'teto_passou_sem_motivo')::int = 0 and (v #>> '{numeros,perguntas,abertas}')::int = 6 and (v #>> '{numeros,perguntas,esperam_voce}')::int = 3, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.modos('ligado');
    -- o bloco grande: o fechamento ligado de hoje com 1.100 letras e a linha Hoje (acima do mínimo); e o de ontem, no mínimo (veredito + 2 decisões), que pode passar
    insert into public.resumo_tarde (dia, phone_normalized, turno, modo, formato, texto, detalhe)
    values (c_h, '5547900000210', 'fechamento', 'novo', 'ligado', 'Fechamento de teste.',
            jsonb_build_object('caracteres', 1100, 'agenda', jsonb_build_object('bloco_diria', jsonb_build_object('modo', 'ligado', 'nivel', 2),
              'bloco_mostrou', jsonb_build_array(jsonb_build_object('parte', 'veredito'), jsonb_build_object('parte', 'hoje'), jsonb_build_object('parte', 'decisao'))))),
           (c_h - 1, '5547900000210', 'fechamento', 'novo', 'ligado', 'Fechamento de teste.',
            jsonb_build_object('caracteres', 1050, 'agenda', jsonb_build_object('bloco_diria', jsonb_build_object('modo', 'ligado', 'nivel', 5),
              'bloco_mostrou', jsonb_build_array(jsonb_build_object('parte', 'veredito'), jsonb_build_object('parte', 'decisao'), jsonb_build_object('parte', 'decisao'))))),
           (c_h - 2, '5547900000210', 'fechamento', 'novo', 'ligado', 'Fechamento de teste.',
            jsonb_build_object('caracteres', 900, 'agenda', jsonb_build_object('bloco_diria', jsonb_build_object('modo', 'ligado', 'nivel', 0),
              'bloco_mostrou', jsonb_build_array(jsonb_build_object('parte', 'veredito'), jsonb_build_object('parte', 'hoje'), jsonb_build_object('parte', 'decisao')))));
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3b5 bloco_grande = 1 (o de hoje, acima de 1.000 com a linha Hoje); o de ontem, no mínimo, e o de anteontem, dentro de 1.000, não contam (NOVO-agenda-114); e só ele',
      (v ->> 'bloco_grande')::int = 1 and (select bool_and((v ->> z)::int = 0) from unnest(c_zeros) z where z <> 'bloco_grande')
      and (v #>> '{numeros,bloco,ligado}')::int = 3 and (v #>> '{numeros,bloco,ligado_acima}')::int = 2, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  begin
    perform pg_temp.modos('ligado');
    -- a exceção acima do teto: com acordes_dia_max 1, 2 avisos de exceção na fila hoje (a cota furada em 1)
    update public.agenda_config set acordes_dia_max = 1 where id;
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, estado, dedupe_key, fila_id)
    values (pg_temp.em(c_h, '10:00'), c_h, 'Agenda — exceção 1.', array[pg_temp.a('01')], '{}', '5547900000210', pg_temp.em(c_h, '10:00'), 'enfileirada', 'agenda-dono:excecao:teste-v3-1', gen_random_uuid()),
           (pg_temp.em(c_h, '11:00'), c_h, 'Agenda — exceção 2.', array[pg_temp.a('02')], '{}', '5547900000210', pg_temp.em(c_h, '11:00'), 'enfileirada', 'agenda-dono:excecao:teste-v3-2', gen_random_uuid());
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, estado, recusa_motivo, dedupe_key, fila_id, devolvida_em)
    values (pg_temp.em(c_h, '12:00'), c_h, 'Agenda — exceção recusada.', array[pg_temp.a('03')], '{}', '5547900000210', pg_temp.em(c_h, '12:00'), 'recusada', 'janela',
            'agenda-dono:excecao:teste-v3-3', null, pg_temp.em(c_h, '12:00'));
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3b6 excecao_acima_do_teto = 1 (2 exceções na fila com a cota de 1), e só ela; o número das exceções de hoje diz 2',
      (v ->> 'excecao_acima_do_teto')::int = 1 and (select bool_and((v ->> z)::int = 0) from unnest(c_zeros) z where z <> 'excecao_acima_do_teto')
      and (v #>> '{numeros,excecoes,hoje}')::int = 2 and (v #>> '{numeros,excecoes,cota_livre}')::int = 0, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V3c: os números do P4 e do P3, pelas formas que eles gravam
  begin
    perform pg_temp.modos('sombra');
    -- 2 tiques ligados com os mesmos ids acima da cota (os ids voltam até o bloco contar): conta os distintos; 1 rodada em sombra com aviso
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
    values (c_a, c_h, pg_temp.em(c_h, '14:15'), 'ligado', 'ligado',
            jsonb_build_object('lote_guardaria', jsonb_build_object('modo', 'ligado', 'cota_livre', 0, 'acima_da_cota', 2, 'acima_da_cota_ids', jsonb_build_array(pg_temp.a('01'), pg_temp.a('02')))), 0, 1, 'comunicar', 'desligado', 'desligado'),
           (c_a, c_h, pg_temp.em(c_h, '14:30'), 'ligado', 'ligado',
            jsonb_build_object('lote_guardaria', jsonb_build_object('modo', 'ligado', 'cota_livre', 0, 'acima_da_cota', 3, 'acima_da_cota_ids', jsonb_build_array(pg_temp.a('01'), pg_temp.a('02'), pg_temp.a('03')))), 0, 1, 'comunicar', 'desligado', 'desligado'),
           (c_a, c_h, pg_temp.em(c_h, '14:45'), 'ligado', 'ligado',
            jsonb_build_object('lote_guardaria', jsonb_build_object('modo', 'sombra', 'aviso', gen_random_uuid(), 'levaria', jsonb_build_object('acoes', 1, 'ids', '[]'::jsonb),
                               'guardaria', jsonb_build_object('acoes', 2, 'ids', '[]'::jsonb, 'perguntas', 3, 'pergunta_ids', '[]'::jsonb), 'acima_da_cota', 1)), 0, 1, 'comunicar', 'desligado', 'desligado'),
           -- a quinta em sombra: o que ela diria
           (c_a, c_h, pg_temp.em(c_h, '14:00'), 'ligado', 'ligado',
            jsonb_build_object('quinta', jsonb_build_object('quinta_diria', jsonb_build_object('texto', 'Agenda — a semana que vem: …', 'caracteres', 272, 'cabe', true, 'mudancas', 0, 'perguntas', 1))), 0, 1, 'comunicar', 'desligado', 'desligado');
    -- a mensagem da semana que saiu, e 2 falhas do pré-passo do lote
    insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, telefone, enviar_em, estado, dedupe_key, fila_id, enviada_em)
    values (pg_temp.em(c_h - 5, '17:00'), c_h - 5, 'Agenda — a semana que vem.', '{}', array[pg_temp.q('01')], '5547900000210', pg_temp.em(c_h - 5, '17:00'), 'enviada',
            'agenda-dono:semana:' || (c_h - 5)::text, gen_random_uuid(), pg_temp.em(c_h - 5, '17:01')),
           (pg_temp.em(c_h, '10:00'), c_h, 'Agenda — exceção de hoje.', array[pg_temp.a('01')], '{}', '5547900000210', pg_temp.em(c_h, '10:00'), 'enviada',
            'agenda-dono:excecao:teste-v3c', gen_random_uuid(), pg_temp.em(c_h, '10:01'));
    perform public.log_app_error('db', 'teste V3c', 'agenda', 'comunicar:lote_guardaria', 'error', '{}'::jsonb);
    perform public.log_app_error('db', 'teste V3c, o teto', 'agenda', 'comunicar:teto', 'error', '{}'::jsonb);
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3c a exceção acima da cota de hoje conta os ids distintos dos tiques (3, não 5); em sombra, o que o lote levaria e guardaria, somado por rodada com aviso',
      (v #>> '{numeros,excecoes,acima_da_cota_hoje}')::int = 3
      and v #> '{numeros,excecoes,em_sombra_hoje}' = '{"avisos": 1, "levaria": 1, "guardaria": 2, "guardaria_perguntas": 3, "acima_da_cota": 1}'::jsonb, v::text);
    r := pg_temp.ok(r, 'V3c2 a quinta: a que saiu (qui 05/11, enviada às 17:01, pela chave agenda-dono:semana:<dia>) e, em sombra, o que a de hoje diria (272 letras, cabe)',
      (v #>> '{numeros,quinta,saiu,enviada_em}')::timestamptz = pg_temp.em(c_h - 5, '17:01') and (v #>> '{numeros,quinta,saiu,dia}')::date = c_h - 5
      and (v #>> '{numeros,quinta,diria,caracteres}')::int = 272 and (v #>> '{numeros,quinta,diria,cabe}')::boolean, v::text);
    r := pg_temp.ok(r, 'V3c3 as falhas comunicar:lote_guardaria em 24 h (1, não a do teto) e os erros comunicar:% (2); 4 rodadas comunicar em 24 h; não entram nos zeros',
      (v ->> 'falhas_lote_guardaria_24h')::int = 1 and (v ->> 'erros_24h')::int = 2 and (v ->> 'rodadas_24h')::int = 4 and (v ->> 'zeros_ok')::boolean, v::text);
    -- o bloco em sombra: 2 tardes, uma cabe em 1.000 e outra não; por turno, só as que cabem
    insert into public.resumo_tarde (dia, phone_normalized, turno, modo, formato, texto, detalhe)
    values (c_h, '5547900000210', 'fechamento', 'novo', 'ligado', 'Fechamento de teste.',
            jsonb_build_object('caracteres', 800, 'agenda', jsonb_build_object('bloco_diria', jsonb_build_object('modo', 'sombra'), 'bloco_seria', jsonb_build_object('caracteres', 980)))),
           (c_h - 1, '5547900000210', 'revisao_semana', 'novo', 'ligado', 'Revisão de teste.',
            jsonb_build_object('caracteres', 900, 'agenda', jsonb_build_object('bloco_diria', jsonb_build_object('modo', 'sombra'), 'bloco_seria', jsonb_build_object('caracteres', 1040))));
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3c4 o bloco em sombra (resumo_tarde, 7 dias): 2 tardes, 1 cabe em 1.000 (o fechamento) e 1 não (a revisão); o último é o de hoje, 980',
      v #> '{numeros,bloco}' @> '{"em_sombra": 2, "seria_dentro": 1, "seria_acima": 1, "seria_dentro_por_turno": {"fechamento": 1}, "ligado": 0}'::jsonb
      and (v #>> '{numeros,bloco,ultimo,caracteres}')::int = 980 and (v #>> '{numeros,bloco,ultimo,dia}')::date = c_h, v::text);
    -- as mensagens de hoje por origem (só contagens): o fechamento, o aviso (agenda-dono) e o acorde (agenda); a que falhou não conta
    insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, dedupe_key, status, created_at)
    values ('5547900000210', 'teste', 'ai_briefing_tarde', gen_random_uuid(), 'teste-v3c-1', 'sent', pg_temp.em(c_h, '17:31')),
           ('5547900000210', 'teste', 'ai_briefing_tarde', gen_random_uuid(), 'teste-v3c-2', 'failed', pg_temp.em(c_h, '17:32')),
           ('5547900000210', 'teste', 'ai_briefing_tarde', gen_random_uuid(), 'teste-v3c-3', 'sent', pg_temp.em(c_h - 1, '17:31'));
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3c5 as mensagens de hoje por origem: 1 fechamento (a que falhou e a de ontem não contam); o alvo é 2 + acordes_dia_max',
      (v #>> '{numeros,mensagens_hoje,fechamento}')::int = 1 and (v #>> '{numeros,mensagens_hoje,alvo}')::int = 2 + (select acordes_dia_max from public.agenda_config where id), v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  -- V3c6: o resumo_tarde mínimo que agenda_fase2_conferencia_vigia.sql cria na bancada (dia, telefone, detalhe; sem turno nem criado_em): a saúde não quebra, e o bloco
  -- conta como sem a tabela; com a tabela inteira (o controle, o V3c4), ele é lido
  begin
    perform pg_temp.modos('sombra');
    drop table public.resumo_tarde;
    create table public.resumo_tarde (dia date, phone_normalized text, detalhe jsonb not null default '{}');
    insert into public.resumo_tarde (dia, phone_normalized, detalhe)
    values (c_h, '5547900000210', jsonb_build_object('caracteres', 1400, 'agenda', jsonb_build_object('bloco_diria', jsonb_build_object('modo', 'ligado'),
            'bloco_mostrou', jsonb_build_array(jsonb_build_object('parte', 'veredito'), jsonb_build_object('parte', 'dia')))));
    r := pg_temp.ok(r, 'V3c6 resumo_tarde sem turno nem criado_em (o da bancada da Fase 2): a saúde não quebra; o bloco sai {} e bloco_grande 0, como sem a tabela',
      pg_temp.lanca($q$select public.agenda_saude(date '2026-11-10', timestamptz '2026-11-10 17:30-03')$q$) = 'ok'
      and (public.agenda_saude(c_h, c_a) #> '{comunicacao,numeros,bloco}') = '{}'::jsonb and (public.agenda_saude(c_h, c_a) #>> '{comunicacao,bloco_grande}')::int = 0,
      pg_temp.lanca($q$select public.agenda_saude(date '2026-11-10', timestamptz '2026-11-10 17:30-03')$q$));
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V3d: as perguntas — com prazo, esperam você, a idade em dias úteis e a complacência
  begin
    perform pg_temp.modos('sombra');
    perform pg_temp.espera('Giancarlo', c_h, c_a);
    v := public.agenda_saude(c_h, c_a) -> 'comunicacao';
    r := pg_temp.ok(r, 'V3d as perguntas: 8 abertas, teto 5, 3 acima; com prazo 2 (Nelson e Lenine), 1 espera você (o Giancarlo, depois do *agenda espera*); a idade média em dias úteis',
      v #> '{numeros,perguntas}' @> '{"abertas": 8, "teto": 5, "acima_do_teto": 3, "com_prazo": 2, "esperam_voce": 1}'::jsonb
      and (v #>> '{numeros,perguntas,idade_media_du}')::numeric > 0, v::text);
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;

  -- V3e: o zero prazo_em_critica do gestor, redefinido (R2): a crítica que pode vencer pode ter prazo; a que espera, não
  begin
    perform pg_temp.modos('ligado');
    update public.agenda_config set gestor_so_propor = false where id;
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-11 18:00-03' where id = pg_temp.q('07');   -- Giancarlo: crítica, nao_cabe em veto_tipos, sem espera
    s := public.agenda_saude(c_h, c_a);
    r := pg_temp.ok(r, 'V3e a crítica que pode vencer com prazo (o Giancarlo) não é violação: prazo_em_critica 0, e o ok do gestor fica; a régua do 7a contaria 1 (o controle)',
      (s #>> '{gestor,prazo_em_critica}')::int = 0 and (pg_temp.saude_7d(c_h, c_a) #>> '{gestor,prazo_em_critica}')::int = 1
      and (s #>> '{gestor,zeros_ok}')::boolean, s #>> '{gestor}');
    update public.agenda_perguntas set veto_ate = timestamptz '2026-11-11 18:00-03' where id = pg_temp.q('06');   -- Flávio: crítica que espera o cliente
    s := public.agenda_saude(c_h, c_a);
    r := pg_temp.ok(r, 'V3e2 a crítica que espera o cliente (o Flávio) com prazo conta 1, e o ok do gestor cai',
      (s #>> '{gestor,prazo_em_critica}')::int = 1 and not (s #>> '{gestor,zeros_ok}')::boolean, s #>> '{gestor}');
    perform pg_temp.desfaz();
  exception when sqlstate 'P0001' then
    if sqlerrm <> '__desfaz__' then raise; end if;
  end;
  perform pg_temp.gravar(r);
end
$v3$;

-- ── V4: o técnico e o determinismo ──────────────────────────────────────────────────────────────────
do $v4$
declare
  r      jsonb := '[]';
  v_tec  uuid := 'aa000000-0000-4000-8000-0000000000ff';
  a      text;
  b      text;
  c_h constant date := date '2026-11-10';
  c_a constant timestamptz := timestamptz '2026-11-10 17:30-03';
begin
  r := pg_temp.ok(r, 'V4a o técnico recebe 42501 na saúde da comunicação; o anon não chega',
    pg_temp.como(v_tec, 'authenticated', format($q$select public._agenda_saude_comunicacao(%L, %L)::text$q$, c_h, c_a)) like 'erro 42501%'
    and pg_temp.como(null, 'anon', format($q$select public._agenda_saude_comunicacao(%L, %L)::text$q$, c_h, c_a)) like 'erro 42501%'
    and pg_temp.como(null, 'authenticated', format($q$select public._agenda_saude_comunicacao(%L, %L)::text$q$, c_h, c_a)) like 'erro 42501%'
    and pg_temp.como(null, 'service_role', format($q$select public._agenda_saude_comunicacao(%L, %L)::text$q$, c_h, c_a)) like '{%',
    pg_temp.como(v_tec, 'authenticated', format($q$select public._agenda_saude_comunicacao(%L, %L)::text$q$, c_h, c_a)));
  r := pg_temp.ok(r, 'V4c a saúde da comunicação sem o dia ou a hora: 22004',
    pg_temp.lanca(format($q$select public._agenda_saude_comunicacao(null, %L)$q$, c_a)) like '22004%' and pg_temp.lanca(format($q$select public._agenda_saude_comunicacao(%L, null)$q$, c_h)) like '22004%', null);
  r := pg_temp.ok(r, 'V4a2 agenda_saude: o técnico não lê (para em agenda_config, como antes da 7f: P0002) e o anon não tem grant',
    pg_temp.como(v_tec, 'authenticated', format($q$select public.agenda_saude(%L, %L)::text$q$, c_h, c_a)) like 'erro P0002%'
    and pg_temp.como(null, 'anon', format($q$select public.agenda_saude(%L, %L)::text$q$, c_h, c_a)) like 'erro 42501%',
    pg_temp.como(v_tec, 'authenticated', format($q$select public.agenda_saude(%L, %L)::text$q$, c_h, c_a)));
  if pg_temp.na_bancada() then
    perform pg_temp.modos('sombra');
    a := md5((public.agenda_saude(c_h, c_a) -> 'comunicacao')::text);
    b := md5((public.agenda_saude(c_h, c_a) -> 'comunicacao')::text);
    r := pg_temp.ok(r, 'V4b 2 chamadas da saúde dão o mesmo md5 (a comunicação), e as do foco também', a = b and md5(pg_temp.foco()) = md5(pg_temp.foco()), a);
  end if;
  perform pg_temp.gravar(r);
end
$v4$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
