-- Prova da correção 2 da revisão da etapa 7c da Agenda de Produção (migration 20261102100590): cada achado da 2ª revisão reproduzido e
-- consertado pela causa, com o "desligado = antes" e as cópias (notas-fase77c.md, seção "Correção 2 da revisão").
-- bancada: depende de 20261102100590
--
--   C0  as cópias: as 6 recriadas, tiradas os blocos e as marcas da correção 2, são a definição mais nova de antes, byte a byte (e a viva é
--       a desta migration); nenhuma é do anon; o security é o de antes; a migration só recria
--   C6a (achado 16; a equipe real) logo depois do ligar da pergunta, a proposta ainda de teste não diz "em teste, eu marcaria" debaixo de
--       "(já escalo por isso)"
--   C1  (achado 1) com a (n) de quem faz o quê nunca vista há 2 dias úteis, a pergunta do gestor de 76 que não perde hoje e a mensagem ao
--       cliente esperando *manda cliente*: as de 75 sobem juntas (o cliente fica à frente da de 76); sem a de 76, a (n) volta a 75; com a
--       de 76 perdendo hoje, nada sobe
--   C2  (achado 2) a pergunta ligada de quem faz o quê e das etapas que sobra depois do DESFAZER (o modo de volta a teste) é descartada no
--       tique seguinte, e a chamada ligada da 7b volta ao fechamento do dono; a rodada refaz a de teste
--   C3  (achado 5) a linha de os_planejamento que a rodada das etapas cria nasce com o carimbo da OS, não com o de agora; a que já existe
--       não muda
--   C4  (achado 12) com a dupla inferida da 7b ligada e o motor marcando 1 pessoa (o bloco de 1 pessoa), as etapas somam a duração do plano
--       (12 meios-dias, não 10): o último dia tem o que fazer; com a dupla desligada, a de antes
--   C5  (achados 13 e 15; o achado 13 saiu na 7d P5, R6.12) na véspera de um dia de revisão da tarde, a linha (o) não cobra mais o último dia que cai depois
--       dele: com as linhas nos dias de revisão (62d1fd95), a cobrança sai no próprio dia; o C5d mostra que isso é tudo o que mudou. E a
--       forma curta diz o dia ("ter 03/11"), não "amanhã"
--   C6b (achado 3) com a escalação em teste e a dupla da 7b ligada, a linha de quem tem perfil novo e a palavra do dono valendo diz que
--       ela já vale (o novato da 7b)
--   C7  (achado 14; a 7b) "Mateus vem qui 19 e seg 23/11" (o texto do quem chamar) = qui 19/11 e seg 23/11; "24, 25 e 26/11"; o número de
--       antes do mês; a hora não é dia; "qua 18/11 e qui 19/11" como antes; as outras frases do achado ("qua 11 e qui 12/11", "ter 24, qua
--       25 e qui 26/11", a da linha do tempo, "de 24 a 26/11" como antes); a quantidade ("3 dias") e "das 8" não são dia
--   C8  (achado 11) a de quem faz o quê ligada que vai como "Também" atrás da chamada leva o prazo e conta como vista no registro
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase77c_correcao2.sql
--   Seguro em produção: termina em ROLLBACK. Fora da bancada, o C0 confere só as portas e o resto sai PULADO.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- o cabeçalho da função (do "create or replace" ao "as $function$"): o security dela
create function pg_temp.cabeca(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\nas $function$' in v));
end $f$;
-- O texto sem os blocos da correção 2 ("-- FASE 7c: (7c correção 2, … -- FASE 7c: fim") e sem as marcas dela ("-- (7c correção 2, … --
-- (7c: fim)"); os da correção 1 ("(7c correção, achado") ficam.
create function pg_temp.sem_corr2(p text) returns text language plpgsql immutable as $f$
declare
  v_out text[] := '{}';
  l     text;
  v_b   boolean := false;
  v_m   boolean := false;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_b and not v_m and l ~ '^\s*-- FASE 7c: \(7c correção 2,' then v_b := true; continue; end if;
    if not v_b and not v_m and l ~ '^\s*-- \(7c correção 2,' then v_m := true; continue; end if;
    if v_b then if l ~ '^\s*-- FASE 7c: fim' then v_b := false; end if; continue; end if;
    if v_m then if l ~ '^\s*-- \(7c: fim\)' then v_m := false; end if; continue; end if;
    v_out := v_out || l;
  end loop;
  return array_to_string(v_out, E'\n');
end $f$;

-- FASE 7d: (7d P5) _agenda_linhas_do_fechamento passou a viver na 7d: a viva, sem os blocos "-- FASE 7d:" e as marcas "-- (7d …", é a desta migration
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro int := 0;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if v_dentro = 0 and l ~ '^\s*-- FASE 7d:' and l !~ '^\s*-- FASE 7d: fim' then
      v_dentro := 1;
      continue;
    end if;
    if v_dentro = 1 and l ~ '^\s*-- FASE 7d: fim' then
      v_dentro := 0;
      continue;
    end if;
    if v_dentro = 0 and l ~ '^\s*-- \(7d ' then
      v_dentro := 2;
      continue;
    end if;
    if v_dentro = 2 and l ~ '^\s*-- \(7d: fim\)' then
      v_dentro := 0;
      continue;
    end if;
    if v_dentro = 0 then
      v_fora := v_fora || l;
    end if;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- FASE 7d: fim

-- ── C0. As cópias e as portas (as portas sem fixture) ──────────────────────────────────────────────────────────────────────────
do $c0$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_correcao2_fase7c', true), '');
  v_dif  text;
  v_viva text;
  v_sec  text;
  v_sem  text;
  v_n    int := 0;
  v_anon text;
  v_novo text;
  f      record;
begin
  select string_agg(x.sig, ', ') filter (where p.oid is null or has_function_privilege('anon', p.oid, 'execute'))
    into v_anon
    from (values ('public._agenda_linhas_do_fechamento(date)'), ('public._agenda_tarefas_planejar(uuid, date, text)'),
                 ('public._agenda_tarefas_sincronizar(uuid, date, timestamptz)'), ('public.agenda_habilidade(date, timestamptz)'),
                 ('public._agenda_ver_habilidades(date, timestamptz, uuid)'),
                 ('public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text)')) x(sig)
    left join pg_proc p on p.oid = to_regprocedure(x.sig);
  v_res := pg_temp.ok(v_res, 'C0a as 6 recriadas existem e nenhuma é executável pelo anon (as portas de antes)', v_anon is null, coalesce('do anon: ' || v_anon, ''));
  if v_mig = '' then
    insert into _resultado values ('C0b as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  for f in select * from (values
      ('_agenda_linhas_do_fechamento', 'agenda_teste.mig_correcao_fase7c', 7), ('_agenda_tarefas_planejar', 'agenda_teste.mig_correcao_fase7c', 2),
      ('_agenda_tarefas_sincronizar', 'agenda_teste.mig_tarefas_fase7c', 1), ('agenda_habilidade', 'agenda_teste.mig_correcao_fase7c', 1),
      ('_agenda_ver_habilidades', 'agenda_teste.mig_correcao_fase7c', 2),
      ('agenda_rascunho_disponibilidade', 'agenda_teste.mig_correcao_fase7b', 2)) x(nome, origem, blocos)
  loop
    if coalesce(current_setting(f.origem, true), '') = '' then
      v_sem := concat_ws(', ', v_sem, f.nome);
      continue;
    end if;
    v_n := v_n + 1;
    if pg_temp.corpo(current_setting(f.origem), f.nome) = ''
       or pg_temp.sem_corr2(pg_temp.corpo(v_mig, f.nome)) is distinct from replace(pg_temp.corpo(current_setting(f.origem), f.nome), E'\r\n', E'\n')
       or (select count(*) from regexp_matches(pg_temp.corpo(v_mig, f.nome), '\n\s*-- (FASE 7c: )?\(7c correção 2,', 'g')) <> f.blocos then
      v_dif := concat_ws(', ', v_dif, f.nome);
    end if;
    if (pg_temp.cabeca(v_mig, f.nome) like '%security definer%') is distinct from (pg_temp.cabeca(current_setting(f.origem), f.nome) like '%security definer%')
       or (select bool_or(p.prosecdef) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f.nome)
          is distinct from (pg_temp.cabeca(current_setting(f.origem), f.nome) like '%security definer%') then
      v_sec := concat_ws(', ', v_sec, f.nome);
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f.nome;
    if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f.nome) <> 1
       or pg_temp.sem_7d(v_novo) is distinct from pg_temp.corpo(v_mig, f.nome) then
      v_viva := concat_ws(', ', v_viva, f.nome);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'C0b as 6 recriadas, tirados os blocos e as marcas da correção 2, são a definição mais nova de antes (a 100580, a 100550 e a 100800), byte a byte, com 7, 2, 1, 1, 2 e 2 blocos/marcas',
    v_n = 6 and v_dif is null and v_sem is null,
    format('%s conferidas; diferentes: %s; sem a origem: %s', v_n, coalesce(v_dif, 'nenhuma'), coalesce(v_sem, 'nenhuma')));
  v_res := pg_temp.ok(v_res, 'C0c o security de cada uma é o da origem (definer continua definer; invoker, invoker)', v_sec is null, coalesce(v_sec, 'iguais'));
  v_res := pg_temp.ok(v_res, 'C0d no banco está a desta migration (uma definição de cada)', v_viva is null, coalesce(v_viva, 'iguais'));
  v_res := pg_temp.ok(v_res, 'C0e a migration só recria (6 funções, nenhuma nova: nenhum create table, column, index nem grant)',
    (select count(*) from regexp_matches(v_mig, '\ncreate or replace function public\.([a-z_0-9]+)\(', 'g')) = 6
    and v_mig !~* '\n\s*(create (table|index|unique index)|alter table|grant |revoke |drop )',
    (select count(*) from regexp_matches(v_mig, '\ncreate or replace function public\.([a-z_0-9]+)\(', 'g'))::text);
  perform pg_temp.gravar(v_res);
end
$c0$;

-- ── As fixtures e os ajudantes (os mesmos de agenda_fase77c_correcao.sql) ──────────────────────────────────────────────────────────
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7c_tarefas', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7a', true), '') <> ''
     and coalesce(current_setting('agenda_teste.replay2910', true), '') <> ''
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.modos7c(p_hab text, p_lid text, p_prop text) returns void language sql as $f$
  update public.agenda_config set modo_habilidade = p_hab, modo_lider = p_lid, modo_habilidade_propor = p_prop where id
$f$;
create function pg_temp.modos7b(p_modo text) returns void language sql as $f$
  update public.agenda_config set modo_dias = p_modo, modo_dupla = p_modo, modo_sabado = p_modo, modo_cadastro = p_modo,
                                  modo_chamar = p_modo where id
$f$;
create function pg_temp.gestor(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end, modo_proposta = 'ligado'
   where id
$f$;
create function pg_temp.pergunta_aberta() returns public.agenda_perguntas language sql stable as $f$
  select q.* from public.agenda_perguntas q
   where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta'
   order by q.criada_em desc, q.id desc limit 1
$f$;
-- a linha (n) do fechamento (a da equipe: tipo pergunta com pergunta_ids e "quem faz o quê" ou a chamada)
create function pg_temp.linha_n(p_dia date) returns jsonb language sql stable as $f$
  select l from jsonb_array_elements(public._agenda_linhas_do_fechamento(p_dia)) l
   where l ->> 'tipo' = 'pergunta' and l ->> 'modo' = 'ligado'
     and (l ->> 'texto' like '%quem faz o quê%' or l ->> 'texto' like '%Na agenda conto com%') limit 1
$f$;
create function pg_temp.etapas_modo(p text) returns void language sql as $f$
  update public.agenda_config set modo_tarefas = p, modo_equipe = 'ligado', modo_proposta = 'ligado' where id
$f$;
-- as linhas ligadas do fechamento de 75 ou mais, na ordem em que saem ("cliente 77, pergunta 77, pergunta 76")
create function pg_temp.altas(p_dia date) returns text language sql stable as $f$
  select string_agg((x ->> 'tipo') || ' ' || (x ->> 'perda'), ', ' order by o)
    from jsonb_array_elements(public._agenda_linhas_do_fechamento(p_dia)) with ordinality t(x, o)
   where x ->> 'modo' = 'ligado' and (x ->> 'perda')::int >= 75
$f$;

-- ── C6a. Logo depois do ligar da pergunta (a equipe real; antes da fixture sintética) ───────────────────────────────────────────────
do $c6a$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t1    text;
  t2    text;
begin
  if not pg_temp.na_bancada() or exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    insert into _resultado values ('C6a o foco logo depois do ligar', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  begin
    perform set_config('agenda_teste.fase7b_equipe', 'real', true);
    execute current_setting('agenda_teste.fase7c');
    perform set_config('agenda_teste.fase7b_equipe', '', true);
    -- em teste: a rodada das 16:15 propõe "Alex instala sozinho" (a pergunta em teste)
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    v := public._agenda_habilidade_propor(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:15'));
    t1 := public._agenda_ver_habilidades(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:20')) ->> 'texto';
    -- 16:22, o ligar dos 3: a proposta ainda é a de teste até a rodada de amanhã
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    t2 := public._agenda_ver_habilidades(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:25')) ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  v_res := pg_temp.ok(v_res, 'C6a em teste, o de antes: "(em teste: ainda escalo como antes)" e "(em teste, eu marcaria: …)"',
    t1 like 'Quem faz o quê (em teste: ainda escalo como antes):%' and t1 like '%(em teste, eu marcaria: você disse que ele vem todo dia útil)%', t1);
  v_res := pg_temp.ok(v_res, 'C6b logo depois do ligar, "(já escalo por isso)" e a proposta ainda de teste diz "(ainda vou te perguntar; eu marcaria porque …)", sem "em teste" (achado 16)',
    t2 like 'Quem faz o quê (já escalo por isso):%' and t2 like '%(ainda vou te perguntar; eu marcaria porque você disse que ele vem todo dia útil)%'
    and t2 not like '%em teste, eu marcaria%', t2);
  perform pg_temp.gravar(v_res);
end
$c6a$;

-- A fixture do P8 (por cima da 7c sintética, da 7b, da 7a e do replay), uma vez; cada caso abaixo roda numa subtransação desfeita.
do $carga$
begin
  if not pg_temp.na_bancada() then
    return;
  end if;
  execute current_setting('agenda_teste.fase7c_tarefas');
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97191')
     and exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97171')
$f$;
-- a chamada da 7b (equipe_cadastro:chamada) aberta e ligada, vista p_vezes vezes, com o prazo p_veto
create function pg_temp.chamada(p_vezes int, p_veto timestamptz) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, criada_em, mostrada_vezes, mostrada_em, mostrada_via, veto_ate)
  values ('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-02',
          'Na agenda conto com Alex: você disse todo dia útil. Está certo? 1) Está certo (recomendo); 2) Mudou. Se não responder em 3 dias úteis depois de ver, sigo assim.',
          'ligado', '[{"n": 1, "texto": "Está certo"}, {"n": 2, "texto": "Mudou"}]'::jsonb, pg_temp.em(date '2026-11-02', '16:30'), p_vezes,
          case when p_vezes > 0 then pg_temp.em(date '2026-11-04', '17:30') end, case when p_vezes > 0 then 'fechamento' end, p_veto)
  returning id
$f$;
-- uma mensagem ao cliente da véspera esperando *manda cliente* (aguardando_dono, aprovação pedida), para amanhã às 09:00
create function pg_temp.cliente_espera(p_numero text, p_hoje date) returns uuid language plpgsql as $f$
declare
  v_q  uuid;
  v_os uuid := pg_temp.os(p_numero);
begin
  insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, modo, opcoes, criada_em)
  values ('cliente_aprovar', 'cliente_aprovar:c1:' || v_os, v_os, 'Mensagem para o cliente (véspera): *manda cliente* ou *segura cliente*.',
          'ligado', '[]'::jsonb, pg_temp.em(p_hoje, '16:30'))
  returning id into v_q;
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, dia_alvo, modo, texto, enviar_em, valida_ate, aprovacao,
                                               pergunta_id, estado, dedupe_key, criada_em)
  select so.client_id, v_os, 'vespera', 'rodada', p_hoje + 2, 'ligado',
         'Bom dia! Aqui é o Gustavo, da HBR Marine. Amanhã chegamos o dia todo para o serviço no seu barco. Para não perdermos a viagem: onde o seu barco vai estar, e a chave fica com quem? Pode responder por aqui mesmo, até por áudio.',
         pg_temp.em(p_hoje + 1, '09:00'), pg_temp.em(p_hoje + 1, '12:00'), 'pedida', v_q, 'aguardando_dono', 'c1:' || v_os,
         pg_temp.em(p_hoje, '16:30')
    from public.service_orders so where so.id = v_os;
  return v_q;
end $f$;
-- a pergunta do gestor (situacao) que vai na linha (m), já vista uma vez, com o prazo p_veto
create function pg_temp.gestor_pergunta(p_numero text, p_veto timestamptz) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, modo, opcoes, criada_em, mostrada_vezes, mostrada_em, mostrada_via, veto_ate)
  values ('situacao', 'situacao:c1:' || pg_temp.os(p_numero) || ':comecada', pg_temp.os(p_numero),
          'Duda (OS-97174) está em andamento: o serviço já começou? Se você não me disser nada até o prazo, conto o serviço inteiro.',
          'ligado', '[]'::jsonb, pg_temp.em(date '2026-11-04', '16:53'), 1, pg_temp.em(date '2026-11-05', '17:30'), 'fechamento', p_veto)
  returning id
$f$;

-- ── C1. As linhas de 75 sobem juntas (achado 1) ─────────────────────────────────────────────────────────────────────────────────
do $c1$
declare
  v_res jsonb := '[]'::jsonb;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C1 as linhas de 75', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- a pergunta de quem faz o quê nasce na qua 04/11 às 16:15 e nunca é vista; na sex 06/11 (2 dias úteis) a 100580 sobe a (n) a 77.
    -- A pergunta do gestor (76) vence só na seg 09/11; a mensagem ao cliente (75) espera *manda cliente*.
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    update public.agenda_config set modo_vigia = 'ligado', modo_cliente = 'ligado' where id;
    perform set_config('agenda.agora', pg_temp.em(date '2026-11-06', '17:30')::text, true);
    perform public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    perform pg_temp.cliente_espera('OS-97192', date '2026-11-06');
    t2 := pg_temp.altas(date '2026-11-06');
    perform pg_temp.gestor_pergunta('OS-97174', pg_temp.em(date '2026-11-09', '18:00'));
    t1 := pg_temp.altas(date '2026-11-06');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a pergunta do gestor vence hoje (sex 06/11): nada sobe (a guarda da 100580)
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    update public.agenda_config set modo_vigia = 'ligado', modo_cliente = 'ligado' where id;
    perform set_config('agenda.agora', pg_temp.em(date '2026-11-06', '17:30')::text, true);
    perform public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    perform pg_temp.cliente_espera('OS-97192', date '2026-11-06');
    perform pg_temp.gestor_pergunta('OS-97174', pg_temp.em(date '2026-11-06', '18:00'));
    t3 := pg_temp.altas(date '2026-11-06');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda.agora', '', true);
  v_res := pg_temp.ok(v_res, 'C1a a (n) nunca vista há 2 dias úteis, a pergunta do gestor (76, vence seg) e o cliente esperando: as de 75 sobem juntas a 77 — o cliente fica à frente da de 76, que é quem sai no corte (antes: pergunta 77, pergunta 76, cliente 75)',
    t1 = 'cliente 77, pergunta 77, pergunta 76', t1);
  v_res := pg_temp.ok(v_res, 'C1b sem a pergunta do gestor de 76 para ceder, nada passa à frente: a (n) volta a 75, atrás do cliente (antes: pergunta 77, cliente 75)',
    t2 = 'cliente 75, pergunta 75', t2);
  v_res := pg_temp.ok(v_res, 'C1c com a pergunta do gestor vencendo hoje, nada sobe (a guarda de antes)', t3 = 'pergunta 76, cliente 75, pergunta 75', t3);
  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C2. A pergunta ligada que sobra depois do DESFAZER (achado 2) ────────────────────────────────────────────────────────────────
do $c2$
declare
  v_res jsonb := '[]'::jsonb;
  r    jsonb;
  v    jsonb;
  l    jsonb;
  v_ch uuid;
  v_os uuid;
  t0 text; t1 text; t2 text; t3 text; t4 text; t5 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C2 a pergunta que sobra', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- qui 05/11 com a 7c ligada: a pergunta da equipe (16:15), a por OS do Caio (a vigia o tira por habilidade; o tique das 16:30) e uma
    -- das etapas; a chamada da 7b ligada, nunca vista
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado');
    update public.agenda_config set modo_cadastro = 'ligado' where id;
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado'); perform pg_temp.etapas_modo('ligado');
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97173')], '{}'::jsonb, true, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:16'));
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:30'));
    v_os := pg_temp.os('OS-97194');
    insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, modo, opcoes, criada_em)
    values ('tarefa', 'tarefa:prazo:' || v_os, v_os, 'Vanderlei: as etapas não cabem até o prazo. Me diga o que fazer.', 'ligado', '[]'::jsonb,
            pg_temp.em(date '2026-11-04', '16:31'));
    v_ch := pg_temp.chamada(0, null);
    t0 := (select string_agg(split_part(q.chave, ':', 1) || ':' || split_part(q.chave, ':', 2), ',' order by q.chave)
             from public.agenda_perguntas q where q.estado = 'aberta' and q.modo = 'ligado' and q.tipo in ('habilidade', 'tarefa'));
    -- o DESFAZER 1 e o das etapas: os 4 de volta a teste
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra'); perform pg_temp.etapas_modo('sombra');
    l := pg_temp.linha_n(date '2026-11-05');
    t1 := coalesce((l ->> 'pergunta_id' = v_ch::text)::text, 'sem a linha ligada');
    -- o tique seguinte (qui 05/11 10:15)
    r := public.agenda_habilidade(date '2026-11-05', pg_temp.em(date '2026-11-05', '10:15'));
    t2 := (select string_agg(split_part(q.chave, ':', 2) || ' ' || q.estado, ',' order by q.chave)
             from public.agenda_perguntas q where q.modo = 'ligado' and q.tipo in ('habilidade', 'tarefa'))
          || ' | ' || coalesce((select max(q.resolvida_motivo) from public.agenda_perguntas q where q.modo = 'ligado' and q.tipo in ('habilidade', 'tarefa')), '-');
    l := pg_temp.linha_n(date '2026-11-05');
    t3 := coalesce((l ->> 'pergunta_id' = v_ch::text)::text || ' ' || (l ->> 'perda'), 'sem a linha ligada');
    -- a rodada das 16:15: refaz a de teste (a proposta fica)
    r := public.agenda_habilidade(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:15'));
    t4 := coalesce((select q.modo || ' ' || q.estado from public.agenda_perguntas q
                     where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta'), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- com os modos ligados, o tique não descarta nada
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado');
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado'); perform pg_temp.etapas_modo('ligado');
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    r := public.agenda_habilidade(date '2026-11-05', pg_temp.em(date '2026-11-05', '10:15'));
    t5 := (select count(*)::text from public.agenda_perguntas q where q.modo = 'ligado' and q.tipo = 'habilidade' and q.estado = 'aberta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C2a o cenário: as 3 ligadas abertas (a da equipe, a por OS, a das etapas)', t0 = 'habilidade:equipe,habilidade:os,tarefa:prazo', t0);
  v_res := pg_temp.ok(v_res, 'C2b logo depois do DESFAZER (antes do tique), a chamada ligada não está no texto do dono (o defeito)', t1 = 'sem a linha ligada', t1);
  v_res := pg_temp.ok(v_res, 'C2c no tique seguinte as 3 viram descartadas, com o motivo "o modo voltou a teste"',
    t2 like 'equipe descartada,os descartada,prazo descartada | o modo voltou a teste%', t2);
  v_res := pg_temp.ok(v_res, 'C2d e a chamada ligada da 7b volta à linha (n) do dono, primeiro, perda 75', t3 = 'true 75', t3);
  v_res := pg_temp.ok(v_res, 'C2e a rodada das 16:15 refaz a pergunta da equipe em teste', t4 = 'sombra aberta', t4);
  v_res := pg_temp.ok(v_res, 'C2f com os modos ligados, o tique não descarta nada', t5 = '1', t5);
  perform pg_temp.gravar(v_res);
end
$c2$;

-- ── C3. O carimbo da linha de os_planejamento que a rodada das etapas cria (achado 5) ───────────────────────────────────────────────
do $c3$
declare
  v_res jsonb := '[]'::jsonb;
  v_os  uuid;
  r     jsonb;
  t1 text; t2 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C3 o carimbo', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.etapas_modo('sombra');
    v_os := pg_temp.os('OS-97192');
    delete from public.os_planejamento where service_order_id = v_os;
    update public.service_orders set created_at = timestamptz '2026-09-01 10:00-03' where id = v_os;
    r := public._agenda_tarefas_sincronizar(v_os, date '2026-11-05', pg_temp.em(date '2026-11-05', '10:15'));
    select (pl.atualizado_em = timestamptz '2026-09-01 10:00-03')::text || ' ' || (pl.tarefas_assinatura is not null)::text || ' '
           || (pl.tarefas_sincronizadas_em = pg_temp.em(date '2026-11-05', '10:15'))::text || ' ' || coalesce(pl.atualizado_por::text, 'null')
      into t1 from public.os_planejamento pl where pl.service_order_id = v_os;
    -- a que já existe não muda: o dono mexeu (atualizado_em 04/11 09:00) e a base mudou (a assinatura de antes)
    update public.os_planejamento set atualizado_em = pg_temp.em(date '2026-11-04', '09:00'), tarefas_assinatura = md5('outra') where service_order_id = v_os;
    r := public._agenda_tarefas_sincronizar(v_os, date '2026-11-05', pg_temp.em(date '2026-11-05', '10:30'));
    select (pl.atualizado_em = pg_temp.em(date '2026-11-04', '09:00'))::text || ' ' || (pl.tarefas_assinatura <> md5('outra'))::text
      into t2 from public.os_planejamento pl where pl.service_order_id = v_os;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C3a a linha nova nasce com o carimbo da OS (o created_at), não com o de agora: o encaixe e a trava do *desfaz* da 7a não a tomam como "mudou"; a assinatura e a hora da sincronização gravadas',
    t1 = 'true true true null', t1);
  v_res := pg_temp.ok(v_res, 'C3b a que já existe não muda o carimbo (só as colunas das etapas)', t2 = 'true true', t2);
  perform pg_temp.gravar(v_res);
end
$c3$;

-- ── C4. As etapas somam a duração do plano com a dupla da 7b ligada (achado 12) ─────────────────────────────────────────────────────
do $c4$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_alx uuid;
  m  jsonb;
  p  jsonb;
  p2 jsonb;
  t1 text; t2 text;
begin
  if not pg_temp.carregada() or pg_temp.os('OS-00074') is null then
    insert into _resultado values ('C4 a duração do plano', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- o Lenine real (OS-00074): com o gestor e a dupla da 7b ligados, 12 diárias-pessoa e 10 meios-dias (2 em dupla); sem a 2ª pessoa, o
    -- motor marca o Alex sozinho (o bloco de 1 pessoa): 12 meios-dias, de seg 30/11 a seg 07/12
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('ligado'); perform pg_temp.etapas_modo('sombra');
    perform set_config('agenda.hoje', '2026-11-05', true);
    v_len := pg_temp.os('OS-00074');
    v_alx := pg_temp.pessoa('Alex');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select md5(format('c7c2:c4:%s:%s', d, t))::uuid, v_len, v_alx, d, t, 'turno', 'execucao', 'publicada', 'motor', pg_temp.em(date '2026-11-05', '10:00')
      from unnest(array[date '2026-11-30', date '2026-12-01', date '2026-12-02', date '2026-12-03', date '2026-12-04', date '2026-12-07']) d,
           unnest(array['manha', 'tarde']) t;
    m := public.agenda_meios_da_os(v_len, date '2026-11-05');
    perform public._agenda_tarefas_sincronizar(v_len, date '2026-11-05', pg_temp.em(date '2026-11-05', '10:15'));
    p := public._agenda_tarefas_planejar(v_len, date '2026-11-05', 'sombra');
    t1 := format('%s %s | %s %s %s %s | %s', m ->> 'total', m #>> '{dupla,pm}', p ->> 'total', jsonb_array_length(p -> 'meios'),
                 jsonb_array_length(p -> 'meios' -> -1 -> 'itens') > 0, p ->> 'sobra_meios',
                 (select count(*) from public.os_tarefas x where x.service_order_id = v_len and x.estado = 'viva'));
    -- com a dupla da 7b em teste: o total de antes (12, sem encolher), a de antes
    perform pg_temp.modos7b('sombra');
    p2 := public._agenda_tarefas_planejar(v_len, date '2026-11-05', 'sombra');
    t2 := format('%s %s', p2 ->> 'total', jsonb_array_length(p2 -> 'meios' -> -1 -> 'itens') > 0);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C4a a dupla da 7b ligada (10 meios-dias, pm 12) e o plano de 1 pessoa (12): as etapas repartem os 12 — o último dia tem o que fazer e nada sobra (antes: total 10, o último dia vazio)',
    t1 like '10 12 | 12 12 t 0.000 | %' and split_part(t1, ' | ', 3)::int > 0, t1);
  v_res := pg_temp.ok(v_res, 'C4b com a dupla da 7b em teste, a de antes (o total de agenda_meios_da_os, já 12)', t2 = '12 t', t2);
  perform pg_temp.gravar(v_res);
end
$c4$;

-- ── C5. O último dia depois de um dia de revisão e a forma curta com o dia (achados 13 e 15) ──────────────────────────────────────
do $c5$
declare
  v_res  jsonb := '[]'::jsonb;
  o      jsonb;
  o2     jsonb;
  v_joao uuid;
  t1 text; t2 text;
  -- FASE 7d: (7d P5, R6.12) o antes × depois do remendo
  n_1 jsonb; n_2 jsonb; n_3 jsonb; a_1 jsonb; a_2 jsonb; a_3 jsonb;
  o_n jsonb; o_a jsonb;
  -- FASE 7d: fim
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C5 a véspera do dia de revisão', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- sex 30/10: o próximo dia útil é ter 03/11 (seg 02/11 é Finados), a revisão do mês, e qua 04/11 é a da semana — a tarde do Secretário
    -- nesses dois dias não traz as linhas da agenda. O Lenine (192) termina na qui 05/11; o Alex, sem telefone, trabalha ter 03/11 no Flávio.
    perform pg_temp.etapas_modo('ligado');
    perform pg_temp.gestor('ligado');
    v_joao := pg_temp.pessoa('João');
    update public.payees set phone = '5547900000041' where id = v_joao;
    if not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = v_joao) then
      insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
      values (v_joao, true, 'dono', timestamptz '2026-10-30 00:11-03');
    end if;
    update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null, parou_motivo = null where payee_id = v_joao;
    update public.payees set phone = null where id = pg_temp.pessoa('Alex');
    perform set_config('agenda.hoje', '2026-10-30', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-10-30', pg_temp.em(date '2026-10-30', '10:00'));
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97192'), date '2026-10-30', pg_temp.em(date '2026-10-30', '10:00'));
    o := (select x from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-10-30')) x
           where x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas (%');
    t1 := format('%s · %s · %s', o ->> 'perda', o ->> 'texto', o ->> 'texto_curto');
    -- qua 04/11 (amanhã é qui 05/11, o último dia; não é revisão): a de antes, com "amanhã"
    perform set_config('agenda.hoje', '2026-11-04', true);
    o2 := (select x from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-04')) x
            where x ->> 'tipo' = 'dia' and x ->> 'texto' like 'Etapas (%');
    t2 := format('%s · %s', o2 ->> 'perda', o2 ->> 'texto_curto');
    -- FASE 7d: (7d P5, R6.12) a linha nova e a de antes da 7d (a 100590) nos mesmos dias: sex 30/10 (véspera de 2 dias de revisão), ter 03/11 (dia de revisão) e qua 04/11
    perform set_config('agenda.hoje', '2026-10-30', true);
    n_1 := public._agenda_linhas_do_fechamento(date '2026-10-30');
    perform set_config('agenda.hoje', '2026-11-03', true);
    n_2 := public._agenda_linhas_do_fechamento(date '2026-11-03');
    perform set_config('agenda.hoje', '2026-11-04', true);
    n_3 := public._agenda_linhas_do_fechamento(date '2026-11-04');
    if coalesce(current_setting('agenda_teste.mig_correcao2_fase7c', true), '') <> '' then
      execute 'create or replace function public._agenda_linhas_do_fechamento(p_hoje date) returns jsonb language plpgsql stable set search_path to ''public'' as $x$'
              || pg_temp.corpo(current_setting('agenda_teste.mig_correcao2_fase7c'), '_agenda_linhas_do_fechamento') || '$x$';
      perform set_config('agenda.hoje', '2026-10-30', true);
      a_1 := public._agenda_linhas_do_fechamento(date '2026-10-30');
      perform set_config('agenda.hoje', '2026-11-03', true);
      a_2 := public._agenda_linhas_do_fechamento(date '2026-11-03');
      perform set_config('agenda.hoje', '2026-11-04', true);
      a_3 := public._agenda_linhas_do_fechamento(date '2026-11-04');
    end if;
    -- FASE 7d: fim
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- FASE 7d: (7d P5, R6.12) deliberado: o remendo do achado 13 saiu. Na sexta, a (o) fica como era antes dele: perda 70 e sem a cobrança; a véspera do último dia
  -- sai no próprio dia de revisão, porque com 62d1fd95 as linhas saem nesse dia. A parte do achado 15 (o dia, não "amanhã") fica.
  v_res := pg_temp.ok(v_res, 'C5a sex 30/10, véspera de 2 dias de revisão: a linha (o) NÃO cobra mais o último dia do Lenine (qui 05/11): perda 70, sem "aviso hoje porque" (7d P5, R6.12)',
    t1 like '70 · Etapas (Alex não tem telefone: quem passa e confere é você). Ter 03/11, Alex no Flávio: % · %' and t1 not like '%é dia de revisão%' and t1 not like '%Qui 05/11 é o último dia%', t1);
  v_res := pg_temp.ok(v_res, 'C5b a forma curta diz o dia, não "amanhã" (achado 15, que fica), e não leva mais o último dia depois da revisão (7d P5, R6.12)',
    t1 like '% · Etapas: ter 03/11, Alex no Flávio (%). Pergunte o que o Alex faz na ter 03/11.' and t1 not like '%qui 05/11 é o último dia do Lenine%', t1);
  -- O antes × depois: o remendo muda uma coisa só. Fora da linha (o), as linhas são iguais; na (o) da sexta, sai só a frase da cobrança, a parte do texto curto e a perda
  if a_1 is not null then
    o_n := (select x from jsonb_array_elements(n_1) x where x ->> 'texto' like 'Etapas (%');
    o_a := (select x from jsonb_array_elements(a_1) x where x ->> 'texto' like 'Etapas (%');
    v_res := pg_temp.ok(v_res, 'C5d antes × depois em sex 30/10: fora da linha (o), as linhas são as mesmas, byte a byte',
      (select jsonb_agg(x order by x ->> 'tipo', x ->> 'texto') from jsonb_array_elements(n_1) x where x ->> 'texto' not like 'Etapas (%')
      is not distinct from (select jsonb_agg(x order by x ->> 'tipo', x ->> 'texto') from jsonb_array_elements(a_1) x where x ->> 'texto' not like 'Etapas (%'), null);
    v_res := pg_temp.ok(v_res, 'C5e antes × depois da linha (o) em sex 30/10: o texto de antes é o de agora mais a frase da cobrança; a perda foi de 75 a 70; a forma curta perde só o último dia',
      o_a ->> 'texto' = (o_n ->> 'texto') || ' Qui 05/11 é o último dia do Lenine (Alex): tem que ficar tudo pronto — aviso hoje porque qua 04/11 é dia de revisão.'
      and (o_a ->> 'perda')::int = 75 and (o_n ->> 'perda')::int = 70
      and replace(o_a ->> 'texto_curto', '; qui 05/11 é o último dia do Lenine (Alex)', '') = o_n ->> 'texto_curto',
      format('antes: %s · %s · %s | depois: %s · %s · %s', o_a ->> 'perda', right(o_a ->> 'texto', 170), o_a ->> 'texto_curto', o_n ->> 'perda', right(o_n ->> 'texto', 170), o_n ->> 'texto_curto'));
    v_res := pg_temp.ok(v_res, 'C5f antes × depois em qua 04/11 (a véspera de verdade, sem revisão no meio): nada muda',
      n_3 = a_3 and exists (select 1 from jsonb_array_elements(n_3) x where x ->> 'texto' like 'Etapas (%' and (x ->> 'perda')::int = 75), null);
    v_res := pg_temp.ok(v_res, 'C5g o que muda de ter 03/11 é só a linha (o) (a cobrança de qua 04/11, dia de revisão também)',
      (select jsonb_agg(x order by x ->> 'tipo', x ->> 'texto') from jsonb_array_elements(n_2) x where x ->> 'texto' not like 'Etapas (%')
      is not distinct from (select jsonb_agg(x order by x ->> 'tipo', x ->> 'texto') from jsonb_array_elements(a_2) x where x ->> 'texto' not like 'Etapas (%'), null);
  end if;
  -- FASE 7d: fim
  v_res := pg_temp.ok(v_res, 'C5c com amanhã sendo amanhã e sem revisão no meio, a forma curta de antes ("amanhã")',
    t2 like '75 · Etapas: amanhã é o último dia do Lenine (Alex, %. Pergunte o que o Alex faz amanhã.', t2);
  perform pg_temp.gravar(v_res);
end
$c5$;

-- ── C6b. A palavra do dono já vale para quem é novo (achado 3) ─────────────────────────────────────────────────────────────────────
do $c6b$
declare
  v_res jsonb := '[]'::jsonb;
  v_b   uuid;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() or pg_temp.pessoa('Bruno') is null then
    insert into _resultado values ('C6b a palavra do dono e o novato', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- a 7b como na noite da publicação (a dupla ligada) e a 7c em teste: "o Bruno instala sozinho" gravado (instala 2, do dono, vale)
    perform pg_temp.modos7b('ligado'); perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    v_b := pg_temp.pessoa('Bruno');
    t3 := public._agenda_e_novato(v_b, date '2026-11-05')::text;
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em, criado_por)
    values (v_b, 'instala', 2, 'dono', 'vale', 'você disse', 'o Bruno instala sozinho', pg_temp.em(date '2026-11-04', '16:20'),
            pg_temp.em(date '2026-11-04', '16:20'), pg_temp.adm());
    t3 := t3 || ' ' || public._agenda_e_novato(v_b, date '2026-11-05')::text;
    t1 := (select x from unnest(string_to_array(public._agenda_ver_habilidades(date '2026-11-05', pg_temp.em(date '2026-11-05', '10:00')) ->> 'texto', E'\n')) x
            where x like '• Bruno:%');
    -- com a escalação ligada, a linha de antes (o cabeçalho "já escalo por isso" já diz)
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    t2 := (select x from unnest(string_to_array(public._agenda_ver_habilidades(date '2026-11-05', pg_temp.em(date '2026-11-05', '10:00')) ->> 'texto', E'\n')) x
            where x like '• Bruno:%');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C6c o cenário: o Bruno é novo pelo perfil e deixa de ser com a palavra do dono (a 7b já usa, sem portão de modo)', t3 = 'true false', t3);
  v_res := pg_temp.ok(v_res, 'C6d em teste, a linha dele diz que isso já vale: "(Isto já vale hoje: sendo novo, ele pode ir sozinho, porque você disse.)"',
    t1 like '• Bruno: %(Isto já vale hoje: sendo novo, ele pode ir sozinho, porque você disse.)', t1);
  v_res := pg_temp.ok(v_res, 'C6e com a escalação ligada, a linha de antes (sem a frase)', t2 not like '%Isto já vale hoje%', t2);
  perform pg_temp.gravar(v_res);
end
$c6b$;

-- ── C7. As datas com o mês só na última (achado 14; a 7b) ───────────────────────────────────────────────────────────────────────────
create function pg_temp.le(p text) returns text language plpgsql as $f$
declare
  v jsonb;
  u uuid := pg_temp.adm();
begin
  begin
    v := public.agenda_rascunho_disponibilidade(u, 'whatsapp', 'Mateus', 'vem', p, false, 'Mateus vem ' || p, date '2026-11-02');
  exception when others then
    perform public.agenda_rascunho_descartar(u);
    return 'ERRO ' || sqlerrm;
  end;
  perform public.agenda_rascunho_descartar(u);
  return coalesce(v ->> 'item', v ->> 'texto', v::text);
end $f$;
do $c7$
declare
  v_res jsonb := '[]'::jsonb;
  t1 text; t2 text; t3 text; t4 text; t5 text; t6 text; t7 text; t8 text; t9 text; t10 text; t11 text; t12 text;
begin
  if not pg_temp.carregada() or pg_temp.pessoa('Mateus') is null then
    insert into _resultado values ('C7 as datas', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7b('sombra');
    t1 := pg_temp.le('qui 19 e seg 23/11');
    t2 := pg_temp.le('24, 25 e 26/11');
    t3 := pg_temp.le('ter 10 e qua 11/11 e ter 24 e qua 25/11');
    t4 := pg_temp.le('qua 18/11 e qui 19/11');
    t5 := pg_temp.le('30 e 02/12');
    t6 := pg_temp.le('qua 18/11 e qui 19/11 às 8h');
    -- as outras frases do achado (a 2ª revisão, r7-datas.out) e a da linha do tempo real
    t7 := pg_temp.le('qua 11 e qui 12/11');
    t8 := pg_temp.le('ter 24, qua 25 e qui 26/11');
    t9 := pg_temp.le('ter 10, qua 11, ter 24, qua 25 e qui 26/11');
    t10 := pg_temp.le('de 24 a 26/11');
    t11 := pg_temp.le('3 dias: 24, 25 e 26/11');
    t12 := pg_temp.le('24 e 25/11, das 8 às 17h');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C7a "qui 19 e seg 23/11" (o texto do quem chamar) = qui 19/11 e seg 23/11 (antes: seg 09/11 e qui 12/11, calado)',
    t1 like '%qui 19/11%' and t1 like '%seg 23/11%' and t1 not like '%09/11%' and t1 not like '%12/11%', t1);
  v_res := pg_temp.ok(v_res, 'C7b "24, 25 e 26/11" = as 3 datas (antes: só qui 26/11)', t2 like '%24/11%' and t2 like '%25/11%' and t2 like '%26/11%', t2);
  v_res := pg_temp.ok(v_res, 'C7c "ter 10 e qua 11/11 e ter 24 e qua 25/11" = as 4 datas (antes: recusada, "datas não batem")',
    t3 like '%10/11%' and t3 like '%11/11%' and t3 like '%24/11%' and t3 like '%25/11%' and t3 not like 'ERRO%', t3);
  v_res := pg_temp.ok(v_res, 'C7d "qua 18/11 e qui 19/11" como antes', t4 like '%18/11%' and t4 like '%19/11%', t4);
  v_res := pg_temp.ok(v_res, 'C7e o número maior que o dia da próxima data é do mês de antes: "30 e 02/12" = 30/11 e 02/12', t5 like '%30/11%' and t5 like '%02/12%', t5);
  v_res := pg_temp.ok(v_res, 'C7f a hora não é dia: "qua 18/11 e qui 19/11 às 8h" = as 2 datas', t6 like '%18/11%' and t6 like '%19/11%' and t6 not like '%08/11%', t6);
  v_res := pg_temp.ok(v_res, 'C7g "qua 11 e qui 12/11" = qua 11/11 e qui 12/11 (antes: qua 04/11 e qui 05/11, calado)',
    t7 like '%11/11%' and t7 like '%12/11%' and t7 not like '%04/11%' and t7 not like '%05/11%', t7);
  v_res := pg_temp.ok(v_res, 'C7h "ter 24, qua 25 e qui 26/11" = as 3 datas (antes: ter 03/11, qua 04/11 e qui 05/11, calado)',
    t8 like '%24/11%' and t8 like '%25/11%' and t8 like '%26/11%' and t8 not like '%03/11%' and t8 not like '%04/11%' and t8 not like '%05/11%', t8);
  v_res := pg_temp.ok(v_res, 'C7i "ter 10, qua 11, ter 24, qua 25 e qui 26/11" (a fala da linha do tempo) = as 5 datas (antes: ter 10, qua 11 e qui 12/11)',
    t9 like '%10/11%' and t9 like '%11/11%' and t9 like '%24/11%' and t9 like '%25/11%' and t9 like '%26/11%' and t9 not like '%12/11%'
    and t9 not like 'ERRO%', t9);
  v_res := pg_temp.ok(v_res, 'C7j "de 24 a 26/11" (a faixa) como antes', t10 like '%24/11%' and t10 like '%26/11%' and t10 not like 'ERRO%', t10);
  v_res := pg_temp.ok(v_res, 'C7k uma quantidade não é dia: "3 dias: 24, 25 e 26/11" = as 3 datas, sem 03/11',
    t11 like '%24/11%' and t11 like '%25/11%' and t11 like '%26/11%' and t11 not like '%03/11%', t11);
  v_res := pg_temp.ok(v_res, 'C7l a hora com "das" não é dia: "24 e 25/11, das 8 às 17h" = as 2 datas',
    t12 like '%24/11%' and t12 like '%25/11%' and t12 not like '%08/11%' and t12 not like '%17/11%' and t12 not like 'ERRO%', t12);
  perform pg_temp.gravar(v_res);
end
$c7$;

-- ── C8. A "Também" de quem faz o quê com o prazo conta (achado 11) ─────────────────────────────────────────────────────────────────
do $c8$
declare
  v_res jsonb := '[]'::jsonb;
  l    jsonb;
  q    public.agenda_perguntas;
  v_ch uuid;
  r    jsonb;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C8 a Também que conta', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- ter 10/11 da semana real: a chamada da 7b vence hoje (vista, prazo hoje) e vai primeiro; quem faz o quê nunca vista vai como "Também"
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado');
    update public.agenda_config set modo_cadastro = 'ligado' where id;
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    perform public._agenda_habilidade_propor(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:15'));
    q := pg_temp.pergunta_aberta();
    v_ch := pg_temp.chamada(1, pg_temp.em(date '2026-11-10', '18:00'));
    l := pg_temp.linha_n(date '2026-11-10');
    t1 := concat_ws(' | ', l ->> 'pergunta_id' = v_ch::text, l -> 'pergunta_ids' ? q.id::text,
                    l ->> 'texto' like '%Também: quem faz o quê (marquei: %; sem resposta até qua 11/11 às 18:00, fica assim; responda em *agenda pendências*).%');
    t2 := l ->> 'texto_curto';
    -- o registro do fechamento (o Secretário mostrou a linha) conta as duas como vistas
    perform set_config('agenda.agora', pg_temp.em(date '2026-11-10', '17:31')::text, true);
    r := public.agenda_fechamento_registrar(date '2026-11-10',
           jsonb_build_array(jsonb_build_object('pergunta_id', l -> 'pergunta_id', 'acao_ids', coalesce(l -> 'acao_ids', '[]'::jsonb),
                                                'pergunta_ids', l -> 'pergunta_ids')),
           'fechamento', pg_temp.em(date '2026-11-10', '17:31'));
    perform set_config('agenda.agora', '', true);
    t3 := (select string_agg(x.tipo || ' ' || x.mostrada_vezes, ', ' order by x.tipo) from public.agenda_perguntas x where x.id in (v_ch, q.id));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda.agora', '', true);
  v_res := pg_temp.ok(v_res, 'C8a a chamada primeiro; quem faz o quê como "Também" com o que foi marcado E o prazo, em pergunta_ids (antes: sem o prazo e fora de pergunta_ids)',
    t1 = 't | t | t', t1);
  v_res := pg_temp.ok(v_res, 'C8b a forma curta leva o prazo das duas', t2 like 'Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim; quem faz o quê — marquei: %; sem resposta até qua 11/11 às 18:00, fica assim. *agenda pendências* mostra.', t2);
  v_res := pg_temp.ok(v_res, 'C8c o registro conta as duas como vistas (antes: só a chamada)', t3 = 'equipe_cadastro 2, habilidade 1', t3);
  perform pg_temp.gravar(v_res);
end
$c8$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
