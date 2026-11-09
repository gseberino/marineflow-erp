-- Prova da disponibilidade da Agenda de Produção, Fase 7b (pacote P2): a semana dita (presa, uma linha por dia), o padrão (só de quem
-- já tem ou do dono), a chance de falta (só medida), o rascunho com a semana e com as datas de quem vem sob demanda ("Mateus vem qua e
-- qui"), a pessoa do cadastro, a dupla dita pelo planejar e a capacidade semanal com o dono pela metade (migration 20261101100100).
-- bancada: depende de 20261101100100
--
--   G0  _agenda_semana_perguntada (qui 05/11: a de 16/11, o prazo qui 12/11 16:00, até ter 10/11) e _agenda_semana_dita ("semana que
--       vem", "semana de 16/11", "a outra semana", "essa semana", "dia 16"; a semana passada e a fora do trecho recusadas)
--   G1  a resposta do diarista (Rafael "seg ter qui", semana de 16/11): 3 disponíveis e 1 indisponível com semana_dita (a sex 20/11 é
--       feriado: sem linha), o padrão trocado, o texto; a semente do histórico sai na 1ª declaração (semente_saiu)
--   G2  o dono "seg e qua": so_pontas nos outros dias; agenda_capacidade dá sem_padrao/0 com o motivo e agenda_grade mantém as pontas;
--       sem so_pontas, a capacidade é a de antes, byte a byte (a de 20261030100600 rodada como pg_temp)
--   G3  "nenhum" prende só a semana: o padrão fica (do diarista e do dono com a linha seg–sex; o so_pontas vence o padrão)
--   G4  a exceção do dono no dia: a resposta do diarista não escreve por cima e o conflito volta
--   G5  a data dita pelo dono (rascunho + *grava*) troca a linha da semana presa do mesmo dia
--   G6  a semana seguinte sem resposta = o padrão dito; quem nunca disse e tem semente = o histórico; com a equipe da fixture, ninguém
--       pela semente; quem vem sob demanda = nenhum
--   G7  _agenda_chance_de_falta (Rafael: 2 de 13 — o "não vou" tardio e o meio-dia não cumprido; o "não vou" avisado antes não conta;
--       Bruno: ainda pouco para medir)
--   G8  o rascunho com a semana (as releituras da §6.6 byte a byte; turno recusado; semana passada recusada; "não vem" de um dia só
--       recusado; o *grava* prende a semana e fecha a pergunta dias_semana do dono)
--   G9  o sábado só de manhã
--   G10 gravar 2× igual = mudou false
--   G11 o *grava* do padrão do dono troca o padrão do diarista (A4) com modo_dias fora de desligado; desligado, o de antes
--   G12 _agenda_dias_curtos (10 casos)
--   G13 "Mateus vem qua e qui" → as datas da 1ª semana com os dois dias por vir (dito qui 05/11, qua 04/11 e seg 02/11), nada de
--       padrão, a releitura byte a byte; "de quarta a sexta" continua faixa; o feriado recusado; o *grava*
--   G14 Mateus sem perfil de diária achado pelo cadastro (o prestador, nunca o fornecedor); Vinicius sem cadastro → a frase; dois
--       Mateus → a pergunta; desligado → o resolvedor de antes
--   G15 a semana dita de quem não tem padrão (sob demanda) não cria padrão; a do dono sem padrão cria o dele
--   G16 agenda_capacidade_semanal com a linha do dono: sombra e ligado = 7,5 e 6,5 (o dono 2,5); desligado = a de antes, byte a byte
--   G17 com modo_dias e modo_dupla desligados: o rascunho de "qua e qui" é o de antes (a de 20261024160600 rodada como pg_temp); a
--       semana e a dupla inicio/fim recusadas com a frase; todos e nao aceitos
--   G18 a dupla dita pelo planejar: as releituras da §6.6; os meios-dias no trecho; o aviso com menos técnicos; o *grava* grava a dupla
--   G19 as cópias: tirados os blocos "-- FASE 7b:", o corpo de cada recriada é o da origem, com o número de blocos
--   G20 as portas: as novas sem anon nem authenticated; o gravador definer sem grant a ninguém; o rascunho de 9 argumentos com as
--       portas de antes e o de 8 fora; a volatilidade
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7b_disponibilidade.sql
--   Seguro em produção: termina em ROLLBACK. G0, G12, G20 rodam em qualquer banco; o resto usa as fixtures e as migrations como texto e
--   só roda na bancada (fora dela sai PULADO).
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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$") e a definição inteira.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7b: … -- FASE 7b: fim" (as linhas de abrir e de fechar saem junto).
-- FASE 7c: (7c P4) e sem os blocos "-- FASE 7c: … fim": _agenda_rascunho_frase e agenda_rascunho_gravar foram recriadas de novo em
-- 20261102100300 (só acréscimo; o G19 confere a cópia da 7b nelas). A régua passa a "FASE 7[bc]"; a contagem dos blocos da 7b não muda.
-- FASE 7c: fim
create function pg_temp.sem_7b(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[bcdef]:' and l !~ '-- FASE 7[bcdef]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[bcdef]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[bcdef]: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- p_sql (que devolve um valor) como o papel p_papel: o resultado em texto, ou 'erro <estado>: <mensagem>'.
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
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ── G0. A semana perguntada e a semana dita (sem fixture) ───────────────────────────────────────────────────────
do $g0$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t     text;
begin
  v := public._agenda_semana_perguntada(date '2026-11-05');
  v_res := pg_temp.ok(v_res, 'G0a _agenda_semana_perguntada(qui 05/11): a semana de 16/11 (a seguinte à próxima), o prazo qui 12/11 às 16:00 (hora_do_plano − 30 min), pode perguntar até ter 10/11',
    (v ->> 'quinta')::date = date '2026-11-05' and (v ->> 'seg')::date = date '2026-11-16' and (v ->> 'prazo_dia')::date = date '2026-11-12'
    and (v ->> 'prazo_em')::timestamptz = timestamptz '2026-11-12 16:00-03' and (v ->> 'pode_perguntar_ate')::date = date '2026-11-10',
    v::text);
  v := public._agenda_semana_perguntada(date '2026-11-09');
  v_res := pg_temp.ok(v_res, 'G0b na seg 09/11, a quinta é a de 05/11 (a mais recente) e a semana continua a de 16/11',
    (v ->> 'quinta')::date = date '2026-11-05' and (v ->> 'seg')::date = date '2026-11-16', v::text);

  select string_agg(x.t || '=' || coalesce(r ->> 'seg', r ->> 'motivo'), ' | ' order by x.o) into t
    from (values (1, 'semana que vem'), (2, 'semana de 16/11'), (3, 'a outra semana'), (4, 'essa semana'), (5, 'dia 16'))
         x(o, t),
         lateral (select public._agenda_semana_dita(x.t, 'o Roberto vem na ' || x.t, date '2026-11-05') as r) y;
  v_res := pg_temp.ok(v_res, 'G0c _agenda_semana_dita (qui 05/11): "semana que vem" = 09/11; "semana de 16/11" e "a outra semana" = 16/11; "essa semana" = 02/11; "dia 16" = 16/11',
    t = 'semana que vem=2026-11-09 | semana de 16/11=2026-11-16 | a outra semana=2026-11-16 | essa semana=2026-11-02 | dia 16=2026-11-16', t);
  v := public._agenda_semana_dita('semana de 26/10', 'a semana de 26/10', date '2026-11-05');
  v_res := pg_temp.ok(v_res, 'G0d a semana que já passou é recusada ("A semana de 26/10 já passou. Qual semana?")',
    not (v ->> 'ok')::boolean and v ->> 'pergunta' = 'A semana de 26/10 já passou. Qual semana?', v::text);
  v := public._agenda_semana_dita('semana de 16/11', 'o Roberto vem toda semana', date '2026-11-05');
  v_res := pg_temp.ok(v_res, 'G0e a semana fora do que o dono disse é recusada (fora_do_trecho); vazia pergunta qual',
    not (v ->> 'ok')::boolean and v ->> 'motivo' = 'fora_do_trecho'
    and public._agenda_semana_dita('', 'x', date '2026-11-05') ->> 'motivo' = 'semana', v::text);
  perform pg_temp.gravar(v_res);
end
$g0$;

-- ── G12. Os dias em texto curto (sem fixture) ──────────────────────────────────────────────────────────────────
insert into _resultado
select 'G12 _agenda_dias_curtos: os 10 casos (lista, três ou mais seguidos = faixa, o sábado de manhã, nenhum dia)',
       string_agg(public._agenda_dias_curtos(x.d, x.s), ' | ' order by x.o)
         = 'seg, ter e qui | de seg a sex | seg, ter e sáb de manhã | nenhum dia | sáb de manhã | de seg a qua e sex | de ter a sex | '
           'seg e qua | de seg a sex e sáb de manhã | qui',
       string_agg(public._agenda_dias_curtos(x.d, x.s), ' | ' order by x.o)
  from (values (1, '{1,2,4}'::smallint[], false), (2, '{1,2,3,4,5}', false), (3, '{1,2}', true), (4, '{}', false), (5, '{}', true),
               (6, '{1,2,3,5}', false), (7, '{2,3,4,5}', false), (8, '{3,1}', false), (9, '{1,2,3,4,5,6}', false),
               (10, '{4}', false)) x(o, d, s);

-- ── As fixtures e as definições de antes (uma vez; cada caso abaixo roda numa subtransação desfeita) ─────────────
do $carga$
declare
  v_m text;
begin
  if coalesce(current_setting('agenda_teste.fase7b', true), '') = '' or coalesce(current_setting('agenda_teste.fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    return;
  end if;
  execute current_setting('agenda_teste.fase7b');
  -- a régua de antes: as leituras da correção da equipe (30/10) e o rascunho da Fase 1
  v_m := coalesce(current_setting('agenda_teste.mig_correcao_equipe', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, 'agenda_capacidade'), 'create or replace function public.agenda_capacidade(',
                    'create function pg_temp.capacidade_antes(');
    execute replace(pg_temp.inteira(v_m, 'agenda_capacidade_semanal'), 'create or replace function public.agenda_capacidade_semanal(',
                    'create function pg_temp.semanal_antes(');
  end if;
  v_m := coalesce(current_setting('agenda_teste.mig_rascunho_fase1', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, 'agenda_rascunho_disponibilidade'),
                    'create or replace function public.agenda_rascunho_disponibilidade(', 'create function pg_temp.disp_antes(');
  end if;
end
$carga$;

create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.payees where id = 'f7b00000-0000-4000-8000-000000000302')
     and to_regprocedure('pg_temp.capacidade_antes(date, date, date)') is not null
     and to_regprocedure('pg_temp.disp_antes(uuid, text, text, text, text, boolean, text, date)') is not null
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
-- As linhas vivas da semana presa de uma pessoa: "dd/mm=situacao[:turno]", na ordem do dia.
create function pg_temp.semana(p_payee uuid, p_seg date) returns text language sql stable as $f$
  select coalesce(string_agg(to_char(lower(d.periodo), 'DD/MM') || '=' || d.situacao || coalesce(':' || d.turno, ''), ' '
                             order by lower(d.periodo), d.turno), '-')
    from public.agenda_disponibilidade d
   where d.payee_id = p_payee and d.substituida_em is null and d.semana_dita = p_seg
$f$;
-- Os padrões vivos "vem" de uma pessoa: "{dias}:origem".
create function pg_temp.padroes(p_payee uuid) returns text language sql stable as $f$
  select coalesce(string_agg(d.dias_semana::text || ':' || d.origem, ' ' order by d.dias_semana::text, d.origem), '-')
    from public.agenda_disponibilidade d
   where d.payee_id = p_payee and d.substituida_em is null and d.dias_semana is not null and d.situacao in ('disponivel', 'confirmada')
$f$;
-- A capacidade de uma pessoa num dia: "manha=situacao/meios/motivo tarde=…".
create function pg_temp.cap(p_payee uuid, p_dia date) returns text language sql stable as $f$
  select string_agg(g.turno || '=' || g.situacao || '/' || trim_scale(g.meios_esperados) || '/' || coalesce(g.motivo, '-'), ' '
                    order by g.turno = 'tarde')
    from public.agenda_capacidade(p_dia, p_dia, date '2026-11-05') g where g.payee_id = p_payee
$f$;

-- ── G1–G7, G9, G10, G15: o gravador da semana presa ──────────────────────────────────────────────────────────────
do $grav$
declare
  v_res    jsonb := '[]'::jsonb;
  c_s      constant date := date '2026-11-16';
  c_agora  constant timestamptz := timestamptz '2026-11-05 16:45-03';
  v_rafael uuid;
  v_mateus uuid;
  v_bruno  uuid;
  v_dono   uuid;
  v_sem    uuid := 'd7b00000-0000-4000-8000-0000000002e1';
  v        jsonb;
  v2       jsonb;
  a        text;
  b        text;
  n        int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('G1–G10, G15 (o gravador da semana)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_rafael := pg_temp.pessoa('Rafael');
  v_mateus := pg_temp.pessoa('Mateus');
  v_bruno := pg_temp.pessoa('Bruno');
  v_dono := public._agenda_dono(null);

  -- G1: a resposta do Rafael (diarista, padrão seg–sex dito por ele) para a semana de 16/11
  begin
    v := public._agenda_equipe_dias_gravar(v_rafael, c_s, '{1,2,4}', false, 'diarista', 'seg ter qui', c_agora);
    v_res := pg_temp.ok(v_res, 'G1a Rafael "seg ter qui" (semana de 16/11): seg, ter e qui disponíveis, qua indisponível, presas na semana (a sex 20/11 é feriado: sem linha), com a nota e o trecho',
      pg_temp.semana(v_rafael, c_s) = '16/11=disponivel 17/11=disponivel 18/11=indisponivel 19/11=disponivel'
      and (select bool_and(d.origem = 'diarista' and d.trecho = 'seg ter qui' and d.criado_em = c_agora and d.turno is null
                           and d.nota = case d.situacao when 'disponivel' then 'Disse que pode (semana de 16/11)'
                                                        else 'Disse que não pode (semana de 16/11)' end)
             from public.agenda_disponibilidade d where d.payee_id = v_rafael and d.semana_dita = c_s),
      pg_temp.semana(v_rafael, c_s));
    v_res := pg_temp.ok(v_res, 'G1b o padrão do Rafael passa a ser o dito (seg, ter e qui, origem diarista, "Disse em 05/11"); o de seg a sex sai (substituida_em); o texto "Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!"',
      pg_temp.padroes(v_rafael) = '{1,2,4}:diarista'
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rafael and d.dias_semana = '{1,2,3,4,5}'
                                                                 and d.substituida_em = c_agora)
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_rafael and d.substituida_em is null
                                                                 and d.dias_semana = '{1,2,4}' and d.nota = 'Disse em 05/11'
                                                                 and d.frequencia is null and d.semana_dita is null)
      and (v ->> 'mudou')::boolean and (v ->> 'padrao_mudou')::boolean and not (v ->> 'semente_saiu')::boolean
      and jsonb_array_length(v -> 'linhas') = 4 and v -> 'conflitos' = '[]'::jsonb
      and v ->> 'texto' = 'Anotei: na semana de 16/11 você pode seg, ter e qui. Obrigado!',
      v::text);
    -- G6 (o padrão vale para a semana sem resposta)
    v := public._agenda_dias_declarados(v_rafael, c_s);
    v2 := public._agenda_dias_declarados(v_rafael, c_s + 7);
    v_res := pg_temp.ok(v_res, 'G6a a semana dita vale para ela (fonte semana); a seguinte, sem resposta, é o padrão dito (fonte padrao, origem diarista, "seg, ter e qui")',
      v ->> 'fonte' = 'semana' and v -> 'dias' = '[1, 2, 4]'::jsonb and v ->> 'origem' = 'diarista' and (v ->> 'dito_em')::timestamptz = c_agora
      and v2 ->> 'fonte' = 'padrao' and v2 -> 'dias' = '[1, 2, 4]'::jsonb and v2 ->> 'origem' = 'diarista' and v2 ->> 'texto' = 'seg, ter e qui',
      v::text || ' | ' || v2::text);
    -- G10: o mesmo de novo
    v := public._agenda_equipe_dias_gravar(v_rafael, c_s, '{4,1,2}', false, 'diarista', 'seg ter qui', c_agora + interval '1 hour');
    v_res := pg_temp.ok(v_res, 'G10 gravar o mesmo de novo = nada muda (mudou false, as linhas e o padrão como estavam)',
      not (v ->> 'mudou')::boolean and pg_temp.semana(v_rafael, c_s) = '16/11=disponivel 17/11=disponivel 18/11=indisponivel 19/11=disponivel'
      and (select count(*) from public.agenda_disponibilidade d where d.payee_id = v_rafael and d.semana_dita = c_s) = 4
      and pg_temp.padroes(v_rafael) = '{1,2,4}:diarista',
      v::text);
    -- G3: "nenhum" na semana seguinte prende só a semana; o padrão fica
    v := public._agenda_equipe_dias_gravar(v_rafael, c_s + 7, '{}', false, 'diarista', 'nenhum', c_agora);
    v_res := pg_temp.ok(v_res, 'G3a "nenhum" (semana de 23/11): os 5 dias indisponíveis presos; o padrão (seg, ter e qui) fica; "Anotei: na semana de 23/11 você não pode. Obrigado por avisar!"',
      pg_temp.semana(v_rafael, c_s + 7) = '23/11=indisponivel 24/11=indisponivel 25/11=indisponivel 26/11=indisponivel 27/11=indisponivel'
      and pg_temp.padroes(v_rafael) = '{1,2,4}:diarista' and not (v ->> 'padrao_mudou')::boolean
      and v ->> 'texto' = 'Anotei: na semana de 23/11 você não pode. Obrigado por avisar!'
      and public._agenda_dias_declarados(v_rafael, c_s + 14) ->> 'fonte' = 'padrao',
      v::text);
    -- G9: o sábado de manhã
    v := public._agenda_equipe_dias_gravar(v_rafael, c_s, '{1}', true, 'diarista', 'segunda e sábado', c_agora + interval '2 hours');
    v_res := pg_temp.ok(v_res, 'G9 o sábado de manhã: a linha da semana no sáb 21/11 só de manhã (a capacidade: manhã livre, tarde fim de semana); "Anotei: … você pode seg e sáb de manhã. Obrigado!"',
      pg_temp.semana(v_rafael, c_s) = '16/11=disponivel 17/11=indisponivel 18/11=indisponivel 19/11=indisponivel 21/11=disponivel:manha'
      and pg_temp.cap(v_rafael, date '2026-11-21') like 'manha=livre/1/% tarde=fim_de_semana/0/%'
      and v ->> 'texto' = 'Anotei: na semana de 16/11 você pode seg e sáb de manhã. Obrigado!'
      and public._agenda_dias_declarados(v_rafael, c_s) @> '{"sabado": true, "texto": "seg e sáb de manhã"}'::jsonb,
      v::text || ' | ' || pg_temp.cap(v_rafael, date '2026-11-21'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- G1c / G6b: a semente do histórico sai na 1ª declaração
  begin
    insert into public.payees (id, name, kind, active, phone) values (v_sem, 'TESTE AG7B Semente', 'diarista', true, '5547900000099');
    insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, frequencia, nota, criado_em) values
      (v_sem, '{2}', 'disponivel', 'historico', 0.6, 'semente', timestamptz '2026-10-28 10:00-03'),
      (v_sem, '{3}', 'disponivel', 'historico', 0.6, 'semente', timestamptz '2026-10-28 10:00-03'),
      (v_sem, '{5}', 'disponivel', 'historico', 0.1, 'semente', timestamptz '2026-10-28 10:00-03');
    v := public._agenda_dias_declarados(v_sem, c_s);
    v_res := pg_temp.ok(v_res, 'G6b quem nunca disse e tem semente: fonte historico, só os dias com a frequência mínima (ter e qua; a sexta de 0,1 fica fora)',
      v ->> 'fonte' = 'historico' and v -> 'dias' = '[2, 3]'::jsonb and v ->> 'texto' = 'ter e qua' and v ->> 'origem' = 'historico',
      v::text);
    v := public._agenda_equipe_dias_gravar(v_sem, c_s, '{1,2}', false, 'diarista', 'seg e ter', c_agora);
    v_res := pg_temp.ok(v_res, 'G1c a 1ª declaração substitui a semente (as 3 linhas do histórico com substituida_em; semente_saiu) e o padrão é o dito',
      (v ->> 'semente_saiu')::boolean and (v ->> 'padrao_mudou')::boolean and pg_temp.padroes(v_sem) = '{1,2}:diarista'
      and (select count(*) from public.agenda_disponibilidade d where d.payee_id = v_sem and d.origem = 'historico' and d.substituida_em = c_agora) = 3,
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- G6c: com a equipe da fixture, ninguém da grade conta pela semente; quem vem sob demanda não tem nada
  select string_agg(distinct g.pessoa || '=' || (public._agenda_dias_declarados(g.payee_id, c_s) ->> 'fonte'), ' ')
    into a
    from public.agenda_capacidade(c_s, c_s + 4, date '2026-11-05') g where not g.eh_dono;
  v_res := pg_temp.ok(v_res, 'G6c com a equipe da fixture, ninguém pela semente: Alex e Rafael pelo padrão dito; Bruno (só uma data dita) e Mateus (sob demanda) sem nada',
    a = 'Alex=padrao Bruno=nenhum Rafael=padrao' and public._agenda_dias_declarados(v_mateus, c_s) ->> 'fonte' = 'nenhum'
    and public._agenda_dias_declarados(pg_temp.pessoa('Alex'), c_s) @> '{"origem": "dono", "texto": "de seg a sex"}'::jsonb,
    a);

  -- G2: o dono "seg e qua" (sem a linha dele): so_pontas nos outros; a capacidade e as pontas
  begin
    a := (select jsonb_agg(to_jsonb(g) order by g.payee_id, g.dia, g.turno)::text
            from public.agenda_capacidade(date '2026-10-29', date '2026-12-04', date '2026-11-05') g);
    b := (select jsonb_agg(to_jsonb(g) order by g.payee_id, g.dia, g.turno)::text
            from pg_temp.capacidade_antes(date '2026-10-29', date '2026-12-04', date '2026-11-05') g);
    v_res := pg_temp.ok(v_res, 'G2a sem nenhum so_pontas, agenda_capacidade é a de antes (20261030100600), byte a byte (29/10 a 04/12, toda a equipe da fixture)',
      a = b and length(a) > 1000, md5(a) || ' / ' || md5(b));
    v := public._agenda_equipe_dias_gravar(v_dono, c_s, '{1,3}', false, 'dono', 'fico em campo seg e qua', c_agora, null, null, pg_temp.adm());
    v_res := pg_temp.ok(v_res, 'G2b o dono "seg e qua": seg e qua disponíveis, ter e qui "só abre e fecha" (so_pontas, nunca indisponível), com as notas; "Anotei: na semana de 16/11 você fica em campo seg e qua; nos outros dias, só abre e fecha."',
      pg_temp.semana(v_dono, c_s) = '16/11=disponivel 17/11=so_pontas 18/11=disponivel 19/11=so_pontas'
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_dono and d.semana_dita = c_s and d.situacao = 'so_pontas'
                                                                 and d.nota = 'Você disse que só abre e fecha (semana de 16/11)')
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_dono and d.semana_dita = c_s and d.situacao = 'disponivel'
                                                                 and d.nota = 'Você disse que fica em campo (semana de 16/11)')
      and v ->> 'texto' = 'Anotei: na semana de 16/11 você fica em campo seg e qua; nos outros dias, só abre e fecha.',
      v::text);
    v_res := pg_temp.ok(v_res, 'G2c agenda_capacidade no dia so_pontas: sem_padrao, 0, origem dono, "você disse que nesse dia só abre e fecha"; no dia dito, livre',
      pg_temp.cap(v_dono, date '2026-11-17') = 'manha=sem_padrao/0/você disse que nesse dia só abre e fecha tarde=sem_padrao/0/você disse que nesse dia só abre e fecha'
      and (select bool_and(g.origem = 'dono') from public.agenda_capacidade(date '2026-11-17', date '2026-11-17', date '2026-11-05') g
            where g.payee_id = v_dono)
      and pg_temp.cap(v_dono, date '2026-11-16') like 'manha=livre/1/% tarde=livre/1/%',
      pg_temp.cap(v_dono, date '2026-11-17') || ' | ' || pg_temp.cap(v_dono, date '2026-11-16'));
    select string_agg(g.turno || '=' || array_to_string(g.curta_livre, ','), ' ' order by g.turno = 'tarde') into a
      from public.agenda_grade(date '2026-11-17', date '2026-11-17', date '2026-11-05') g where g.eh_dono;
    v_res := pg_temp.ok(v_res, 'G2d agenda_grade mantém as pontas do dono no dia so_pontas (abertura e fechamento livres nos dois turnos)',
      a = 'manha=abertura,fechamento tarde=abertura,fechamento', a);
    a := (select jsonb_agg(to_jsonb(g) order by g.payee_id, g.dia, g.turno)::text
            from public.agenda_capacidade(date '2026-10-29', date '2026-12-04', date '2026-11-05') g
           where not (g.payee_id = v_dono and g.dia in (date '2026-11-17', date '2026-11-19')));
    b := (select jsonb_agg(to_jsonb(g) order by g.payee_id, g.dia, g.turno)::text
            from pg_temp.capacidade_antes(date '2026-10-29', date '2026-12-04', date '2026-11-05') g
           where not (g.payee_id = v_dono and g.dia in (date '2026-11-17', date '2026-11-19')));
    v_res := pg_temp.ok(v_res, 'G2e fora dos dias so_pontas, a capacidade continua a de antes, byte a byte (a exceção "vem" do dono no dia dito é a de sempre)',
      a = b, md5(a) || ' / ' || md5(b));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- G3b: o dono com a linha seg–sex diz "nenhum dia" na semana de 16/11: o so_pontas vence o padrão; o padrão fica
  begin
    perform set_config('agenda_teste.fase7b_dono', 'campo', true);
    execute current_setting('agenda_teste.fase7b');
    perform set_config('agenda_teste.fase7b_dono', '', true);
    v := public._agenda_equipe_dias_gravar(v_dono, c_s, '{}', false, 'dono', 'opção 3', c_agora);
    v_res := pg_temp.ok(v_res, 'G3b o dono com a linha seg–sex e "nenhum dia" na semana: so_pontas nos 4 dias úteis, a capacidade sem_padrao/0 (o so_pontas vence o padrão), o padrão seg–sex fica; "Anotei: na semana de 16/11 você só abre e fecha."',
      pg_temp.semana(v_dono, c_s) = '16/11=so_pontas 17/11=so_pontas 18/11=so_pontas 19/11=so_pontas'
      and pg_temp.cap(v_dono, date '2026-11-16') like 'manha=sem_padrao/0/você disse que nesse dia só abre e fecha %'
      and pg_temp.cap(v_dono, date '2026-11-23') like 'manha=livre/1/% tarde=livre/1/%'
      and pg_temp.padroes(v_dono) = '{1,2,3,4,5}:dono' and not (v ->> 'padrao_mudou')::boolean
      and v ->> 'texto' = 'Anotei: na semana de 16/11 você só abre e fecha.',
      v::text || ' | ' || pg_temp.cap(v_dono, date '2026-11-16'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- G4: a exceção do dono no dia vence a resposta do diarista
  begin
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em)
    values (v_rafael, daterange(date '2026-11-18', date '2026-11-18', '[]'), 'indisponivel', 'dono', 'você disse que não vem',
            timestamptz '2026-11-03 10:00-03');
    v := public._agenda_equipe_dias_gravar(v_rafael, c_s, '{1,2,3,4,5}', false, 'diarista', 'todos', c_agora);
    v_res := pg_temp.ok(v_res, 'G4 a exceção do dono (Rafael não vem qua 18/11) fica: a resposta "todos" não escreve qua 18/11 e o conflito volta {dia, situacao_do_dono}',
      pg_temp.semana(v_rafael, c_s) = '16/11=disponivel 17/11=disponivel 19/11=disponivel'
      and v -> 'conflitos' = '[{"dia": "2026-11-18", "situacao_do_dono": "indisponivel"}]'::jsonb
      and pg_temp.cap(v_rafael, date '2026-11-18') like 'manha=indisponivel/0/você disse que não vem %',
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- G15: quem vem sob demanda (sem padrão) só prende a semana; o dono sem padrão cria o dele
  begin
    v := public._agenda_equipe_dias_gravar(v_mateus, c_s, '{3,4}', false, 'dono', 'Mateus vem qua e qui na semana de 16/11', c_agora);
    v_res := pg_temp.ok(v_res, 'G15a a semana dita do Mateus (sob demanda, sem padrão) prende só a semana: nenhum padrão nasce; "Anotei: na semana de 16/11 Mateus vem qua e qui."',
      pg_temp.semana(v_mateus, c_s) = '16/11=indisponivel 17/11=indisponivel 18/11=disponivel 19/11=disponivel'
      and pg_temp.padroes(v_mateus) = '-' and not (v ->> 'padrao_mudou')::boolean
      and (select bool_and(d.nota like 'Você disse que %vem (semana de 16/11)') from public.agenda_disponibilidade d where d.payee_id = v_mateus)
      and v ->> 'texto' = 'Anotei: na semana de 16/11 Mateus vem qua e qui.',
      v::text);
    -- FASE 7b: (correção da revisão da 7b, achados 3 e 10) o padrão do dono só muda pela opção "toda semana" da pergunta dos dias
    -- (agenda_decidir liga agenda.dias_padrao_do_dono só nessa chamada; aqui, à mão)
    perform set_config('agenda.dias_padrao_do_dono', 'sim', true);
    -- FASE 7b: fim
    v := public._agenda_equipe_dias_gravar(v_dono, c_s, '{1,2,3,4,5}', false, 'dono', 'opção 2', c_agora);
    -- FASE 7b: (correção da revisão da 7b, achados 3 e 10) de volta a vazio
    perform set_config('agenda.dias_padrao_do_dono', '', true);
    -- FASE 7b: fim
    v_res := pg_temp.ok(v_res, 'G15b o dono sem padrão, "fico em campo de seg a sex" (a opção da pergunta dos dias): cria o padrão dele (seg a sex, origem dono, sem frequência, "você disse em 05/11") e diz que é toda semana',
      (v ->> 'padrao_mudou')::boolean and pg_temp.padroes(v_dono) = '{1,2,3,4,5}:dono'
      and exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_dono and d.substituida_em is null and d.dias_semana is not null
                                                                 and d.frequencia is null and d.nota = 'você disse em 05/11' and d.turno is null)
      -- FASE 7b: (correção da revisão da 7b, achados 3 e 10) a resposta diz que é toda semana
      and v ->> 'texto' = 'Anotei: você fica em campo de seg a sex, toda semana a partir de agora. Se mudar, me diga.',
      -- FASE 7b: fim
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- G1d: as entradas que não valem
  a := '';
  begin perform public._agenda_equipe_dias_gravar(v_rafael, date '2026-11-17', '{1}', false, 'diarista', 'x', c_agora);
  exception when others then a := a || sqlstate || ' '; end;
  begin perform public._agenda_equipe_dias_gravar(v_rafael, c_s, '{1,6}', false, 'diarista', 'x', c_agora);
  exception when others then a := a || sqlstate || ' '; end;
  begin perform public._agenda_equipe_dias_gravar(v_rafael, c_s, '{1}', false, 'tela', 'x', c_agora);
  exception when others then a := a || sqlstate || ' '; end;
  begin perform public._agenda_equipe_dias_gravar(v_rafael, c_s, '{1}', false, 'diarista', 'x', null);
  exception when others then a := a || sqlstate; end;
  v_res := pg_temp.ok(v_res, 'G1d o gravador recusa a semana que não começa na segunda, o 6 nos dias (o sábado é p_sabado), a origem fora da lista e a hora nula',
    a = '22023 22023 22023 22004', a);

  -- G7: a chance de falta (a história de 8 semanas antes de seg 02/11: 07/09 a 01/11)
  begin
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, semana_dita, criado_em)
    select v_rafael, daterange(x.d, x.d, '[]'), 'disponivel', 'diarista', 'Disse que pode', x.d - (extract(isodow from x.d)::int - 1),
           timestamptz '2026-09-20 10:00-03'
      from unnest(array[date '2026-10-05', date '2026-10-06', date '2026-10-07', date '2026-10-08', date '2026-10-09',
                        date '2026-10-13', date '2026-10-14', date '2026-10-15', date '2026-10-16',
                        date '2026-10-19', date '2026-10-20', date '2026-10-21']) x(d);
    -- o "não vou" tardio (qui 15/10 às 07:30: depois do fim da manhã de qua 14/10) é falta; o avisado antes (ter 20/10, dito sex 16/10) não
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota, criado_em) values
      (v_rafael, daterange(date '2026-10-15', date '2026-10-15', '[]'), 'indisponivel', 'diarista', 'não vou', timestamptz '2026-10-15 07:30-03'),
      (v_rafael, daterange(date '2026-10-20', date '2026-10-20', '[]'), 'indisponivel', 'diarista', 'não vou', timestamptz '2026-10-16 10:00-03');
    -- um meio-dia não cumprido porque a equipe faltou (qui 22/10, fora dos dias ditos: conta nos dois)
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, periodo, tipo, estado, origem, resultado, motivo,
                                         resultado_em, resultado_via, publicada_em)
    select so.id, v_rafael, date '2026-10-22', 'manha', 'turno', public.agenda_periodo(date '2026-10-22', 'manha'), 'execucao', 'publicada',
           'motor', 'nao_cumprido', 'equipe_faltou', timestamptz '2026-10-22 18:00-03', 'sistema', timestamptz '2026-10-15 16:30-03'
      from public.service_orders so where so.service_order_number = 'OS-00074';
    v := public._agenda_chance_de_falta(v_rafael, date '2026-11-05');
    v2 := public._agenda_chance_de_falta(v_bruno, date '2026-11-05');
    v_res := pg_temp.ok(v_res, 'G7 _agenda_chance_de_falta: Rafael 2 de 13 (o "não vou" tardio e o meio-dia não cumprido; o "não vou" avisado antes não conta), p 0,15, fonte medida; Bruno ainda pouco para medir (p nulo)',
      v @> '{"dias": 13, "faltas": 2, "fonte": "medida", "texto": "2 de 13"}'::jsonb and (v ->> 'p')::numeric = round(2::numeric / 13, 2)
      and v2 @> '{"dias": 0, "fonte": "pouco_dado", "texto": "ainda pouco para medir"}'::jsonb and v2 -> 'p' = 'null'::jsonb,
      v::text || ' | ' || v2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$grav$;

-- ── G5, G8, G11, G13, G14, G16, G17: o rascunho, o *grava* e a capacidade semanal ─────────────────────────────────
create function pg_temp.disp(p_pessoa text, p_sit text, p_dias text, p_padrao boolean, p_trecho text, p_hoje date,
                             p_semana text default null) returns jsonb language sql as $f$
  select public.agenda_rascunho_disponibilidade(pg_temp.adm(), 'whatsapp', p_pessoa, p_sit, p_dias, p_padrao, p_trecho, p_hoje, p_semana)
$f$;
create function pg_temp.grava(p_hoje date, p_hora text) returns jsonb language plpgsql as $f$
declare
  v jsonb;
begin
  perform set_config('agenda.agora', pg_temp.em(p_hoje, p_hora)::text, true);
  v := public.agenda_rascunho_gravar(pg_temp.adm(), p_hoje);
  perform set_config('agenda.agora', '', true);
  return v;
end $f$;
create function pg_temp.releitura(p_linha text) returns text language sql immutable as $f$
  select 'Entendi assim, confere?' || E'\n' || p_linha || E'\n' || 'Responda *grava* ou corrija o que estiver errado.'
$f$;

do $rasc$
declare
  v_res    jsonb := '[]'::jsonb;
  c_qui    constant date := date '2026-11-05';
  c_s      constant date := date '2026-11-16';
  v_rafael uuid;
  v_mateus uuid;
  v_alex   uuid;
  v_dono   uuid;
  v        jsonb;
  v2       jsonb;
  a        text;
  b        text;
  v_q      uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('G5, G8, G11, G13, G14, G16, G17 (o rascunho)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_rafael := pg_temp.pessoa('Rafael');
  v_mateus := pg_temp.pessoa('Mateus');
  v_alex := pg_temp.pessoa('Alex');
  v_dono := public._agenda_dono(null);

  -- G17: com modo_dias e modo_dupla desligados (a linha nasce assim), o rascunho é o de antes
  begin
    v := pg_temp.disp('Alex', 'vem', 'quarta e quinta', false, 'o Alex vem quarta e quinta', c_qui);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v2 := pg_temp.disp_antes(pg_temp.adm(), 'whatsapp', 'Alex', 'vem', 'quarta e quinta', false, 'o Alex vem quarta e quinta', c_qui);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G17a desligado: "Alex vem quarta e quinta" é a saída de antes, byte a byte (a de 20261024160600 rodada como pg_temp; grava só a quarta, como em produção hoje)',
    v = v2 and v ->> 'item' = 'Alex: vem qua 11/11', v::text || ' | ' || v2::text);
  begin
    v := pg_temp.disp('Mateus', 'vem', 'quarta e quinta', false, 'o Mateus vem quarta e quinta', c_qui);
    v2 := pg_temp.disp('Rafael', 'vem', 'seg, ter e qui', false, 'o Rafael vem seg, ter e qui na semana de 16/11', c_qui, 'semana de 16/11');
    a := (public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', 'Lenine', '{"dupla": "inicio", "dupla_meios": 2}'::jsonb,
                                          'o Lenine precisa de dois no primeiro dia', c_qui)) ->> 'pergunta';
    b := concat_ws(' / ',
           (public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', 'Lenine', '{"dupla": "todos"}'::jsonb,
                                            'o Lenine vai em dupla o tempo todo', c_qui)) ->> 'ok',
           (public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', 'Vanderlei', '{"dupla": "nao"}'::jsonb,
                                            'o Vanderlei vai com um só', c_qui)) ->> 'ok');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G17b desligado: a pessoa fora da equipe é o resolvedor de antes; a semana é recusada com a frase; a dupla inicio/fim é recusada com a frase; todos e nao aceitos',
    v ->> 'pergunta' = 'Não conheço ninguém chamado Mateus na equipe.'
    and v2 ->> 'pergunta' = 'Anotar os dias de uma semana só ainda não está ligado. Diga as datas (ex.: "Roberto vem quarta dia 18") ou os dias de toda semana (ex.: "Roberto vem toda terça").'
    and a = 'A dupla só numa parte do serviço ainda não está ligada. Diga *Lenine com dupla* (o tempo todo) ou ''vai com um só''.'
    and b = 'true / true',
    concat_ws(' | ', v ->> 'pergunta', v2 ->> 'pergunta', a, b));

  update public.agenda_config set modo_dias = 'sombra', modo_dupla = 'sombra' where id;

  -- G13: "Mateus vem qua e qui" — as datas da 1ª semana com os dois dias por vir
  begin
    v := pg_temp.disp('Mateus', 'vem', 'quarta e quinta', false, 'o Mateus vem quarta e quinta', c_qui);
    v_res := pg_temp.ok(v_res, 'G13a dito na qui 05/11: qua 11/11 e qui 12/11 (a 1ª semana com os dois por vir), a releitura byte a byte (com a pessoa do cadastro)',
      v ->> 'releitura' = pg_temp.releitura('• Mateus: vem qua 11/11 e qui 12/11 (só nesses dias). Mateus ainda não está na equipe da agenda: com *grava*, ele entra só nesses dias.')
      and (select r.dados -> 'datas' = '["2026-11-11", "2026-11-12"]'::jsonb and r.chave = format('disp:%s:l2026-11-11_2026-11-12:dia', v_mateus)
                  and not (r.dados ->> 'padrao')::boolean and (r.dados ->> 'payee_id')::uuid = v_mateus
             from public.agenda_rascunho r where r.estado = 'aberto' and r.tipo = 'disponibilidade'),
      v::text);
    v2 := pg_temp.grava(c_qui, '16:50');
    v_res := pg_temp.ok(v_res, 'G13b o *grava*: uma exceção por data (qua 11 e qui 12/11), disponível, origem dono, o dia inteiro, "Você disse que vem (sob demanda)"; nenhum padrão; Mateus passa a contar nesses dias (e só neles)',
      (v2 ->> 'ok')::boolean
      and (select string_agg(to_char(lower(d.periodo), 'DD/MM') || '=' || d.situacao || '/' || d.origem || '/' || coalesce(d.turno, 'dia')
                             || '/' || d.nota, ' ' order by lower(d.periodo))
             from public.agenda_disponibilidade d where d.payee_id = v_mateus and d.substituida_em is null)
          = '11/11=disponivel/dono/dia/Você disse que vem (sob demanda) 12/11=disponivel/dono/dia/Você disse que vem (sob demanda)'
      and pg_temp.padroes(v_mateus) = '-'
      and pg_temp.cap(v_mateus, date '2026-11-11') like 'manha=livre/1/% tarde=livre/1/%'
      and pg_temp.cap(v_mateus, date '2026-11-13') like 'manha=sem_padrao/0/% tarde=sem_padrao/0/%'
      and public.agenda_resolver_pessoa('Mateus', pg_temp.adm(), c_qui) ->> 'status' = 'ok',
      v2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v := pg_temp.disp('Mateus', 'vem', 'quarta e quinta', false, 'o Mateus vem quarta e quinta', date '2026-11-04');
    a := (select r.dados ->> 'datas' from public.agenda_rascunho r where r.estado = 'aberto' and r.tipo = 'disponibilidade');
    perform public.agenda_rascunho_descartar(pg_temp.adm());
    v := pg_temp.disp('Mateus', 'vem', 'qua e qui', false, 'o Mateus vem quarta e quinta', date '2026-11-02');
    b := (select r.dados ->> 'datas' from public.agenda_rascunho r where r.estado = 'aberto' and r.tipo = 'disponibilidade');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G13c dito na qua 04/11: as da semana seguinte (qua 11 e qui 12/11 — nunca qui de amanhã e qua da outra); dito na seg 02/11: as desta semana (qua 04 e qui 05/11), também com "qua e qui"',
    a = '["2026-11-11", "2026-11-12"]' and b = '["2026-11-04", "2026-11-05"]', a || ' | ' || b);
  begin
    v := pg_temp.disp('Mateus', 'vem', 'de quarta a sexta', false, 'o Mateus vem de quarta a sexta', c_qui);
    a := (select coalesce(r.dados ->> 'datas', '-') || '/' || (r.dados ->> 'de') || '/' || (r.dados ->> 'ate')
            from public.agenda_rascunho r where r.estado = 'aberto' and r.tipo = 'disponibilidade');
    perform public.agenda_rascunho_descartar(pg_temp.adm());
    v2 := pg_temp.disp('Mateus', 'vem', 'quinta e sexta', false, 'o Mateus vem quinta e sexta', date '2026-11-16');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G13d "de quarta a sexta" continua faixa (de qua 11 a sex 13/11, sem datas); "quinta e sexta" dito na seg 16/11 cai na sex 20/11 e é recusado: "sex 20/11 é feriado (Consciência Negra): outro dia?"',
    a = '-/2026-11-11/2026-11-13' and v ->> 'releitura' like '%• Mateus: vem de qua 11/11 a sex 13/11. Mateus ainda não está na equipe da agenda: com *grava*, ele entra só nesses dias.%'
    and v2 ->> 'pergunta' = 'sex 20/11 é feriado (Consciência Negra): outro dia?',
    a || ' | ' || (v ->> 'releitura') || ' | ' || (v2 ->> 'pergunta'));

  -- G14: a pessoa do cadastro
  begin
    v := pg_temp.disp('Vinicius', 'vem', 'quarta e quinta', false, 'o Vinicius vem quarta e quinta', c_qui);
    insert into public.payees (id, name, kind, active) values ('d7b00000-0000-4000-8000-0000000002e2', 'Mateus Silva', 'diarista', true);
    v2 := pg_temp.disp('Mateus', 'vem', 'quarta e quinta', false, 'o Mateus vem quarta e quinta', c_qui);
    a := pg_temp.disp('Mateus', 'nao_vem', 'quarta', false, 'o Mateus não vem quarta', c_qui) ->> 'pergunta';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G14 sem cadastro (Vinicius): "Não achei Vinicius no cadastro de pessoas. Cadastre ele (o nome e o telefone) e me diga de novo."; dois no cadastro: "Qual Mateus: Mateus ou Mateus Silva?"; o "não vem" de quem não está na equipe continua o resolvedor',
    v ->> 'pergunta' = 'Não achei Vinicius no cadastro de pessoas. Cadastre ele (o nome e o telefone) e me diga de novo.'
    and v2 ->> 'pergunta' = 'Qual Mateus: Mateus ou Mateus Silva?' and v2 -> 'opcoes' = '["Mateus", "Mateus Silva"]'::jsonb
    and a = 'Não conheço ninguém chamado Mateus na equipe.'
    and not exists (select 1 from public.payees p where p.name = 'Mateus' and p.id <> v_mateus),
    concat_ws(' | ', v ->> 'pergunta', v2 ->> 'pergunta', a));

  -- G8: o rascunho com a semana
  begin
    v := pg_temp.disp('Rafael', 'vem', 'seg, ter e qui', false, 'o Rafael vem seg, ter e qui na semana de 16/11', c_qui, 'semana de 16/11');
    v_res := pg_temp.ok(v_res, 'G8a "Rafael vem seg, ter e qui na semana de 16/11": a releitura "Rafael, semana de 16/11: vem seg, ter e qui (e não vem qua e sex)." e a chave da semana',
      v ->> 'releitura' = pg_temp.releitura('• Rafael, semana de 16/11: vem seg, ter e qui (e não vem qua e sex).')
      and exists (select 1 from public.agenda_rascunho r where r.estado = 'aberto' and r.chave = format('disp:%s:s2026-11-16', v_rafael)
                                                         and r.dados ->> 'semana' = '2026-11-16' and r.dados -> 'dias_semana' = '[1, 2, 4]'::jsonb),
      v::text);
    v2 := pg_temp.disp('eu', 'vem', 'segunda e quarta', false, 'eu fico em campo segunda e quarta na semana de 16/11', c_qui, 'semana de 16/11');
    v_res := pg_temp.ok(v_res, 'G8b o dono "segunda e quarta na semana de 16/11": "Você, semana de 16/11: fica em campo seg e qua; nos outros dias, só abre e fecha."',
      v2 ->> 'releitura' like '%• Você, semana de 16/11: fica em campo seg e qua; nos outros dias, só abre e fecha.%', v2::text);
    -- a pergunta dias_semana do dono dessa semana (a do P3), aberta, fecha no *grava*
    insert into public.agenda_perguntas (tipo, chave, texto, modo, dia)
    values ('dias_semana', format('dias_semana:%s:%s', v_dono, c_s), 'Semana de 16/11: conto com Alex de seg a sex (você disse).', 'sombra', c_s)
    returning id into v_q;
    v := pg_temp.grava(c_qui, '16:50');
    v_res := pg_temp.ok(v_res, 'G8c o *grava*: a semana presa do Rafael (origem dono, "Você disse que vem…") e a do dono (so_pontas nos outros dias); o padrão passa a ser o dito (o do Rafael, que tinha; o do dono, que é o dono: §5.1 passo 4); a pergunta dias_semana do dono fecha ("você disse os dias") e as linhas a citam',
      (v ->> 'ok')::boolean
      and pg_temp.semana(v_rafael, c_s) = '16/11=disponivel 17/11=disponivel 18/11=indisponivel 19/11=disponivel'
      and pg_temp.semana(v_dono, c_s) = '16/11=disponivel 17/11=so_pontas 18/11=disponivel 19/11=so_pontas'
      and (select bool_and(d.origem = 'dono' and d.nota like 'Você disse que %vem (semana de 16/11)') from public.agenda_disponibilidade d
            where d.payee_id = v_rafael and d.semana_dita = c_s)
      -- FASE 7b: (correção da revisão da 7b, achados 3 e 10) a semana dita pelo dono no rascunho prende só a semana: os padrões não
      -- mudam (o do Rafael continua o dele; o dono continua sem padrão)
      and pg_temp.padroes(v_rafael) = '{1,2,3,4,5}:diarista' and pg_temp.padroes(v_dono) = '-'
      -- FASE 7b: fim
      and exists (select 1 from public.agenda_perguntas q where q.id = v_q and q.estado = 'resolvida' and q.resolvida_motivo = 'você disse os dias')
      and (select bool_and(d.pergunta_id = v_q) from public.agenda_disponibilidade d where d.payee_id = v_dono and d.semana_dita = c_s)
      and v ->> 'texto' like 'Gravado. Agora:' || E'\n' || '• Rafael, semana de 16/11: vem seg, ter e qui (e não vem qua e sex).%',
      v::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    a := concat_ws(' | ',
      pg_temp.disp('Rafael', 'nao_vem', 'a semana toda', false, 'o Rafael não vem a semana que vem toda', c_qui, 'semana que vem') ->> 'releitura',
      pg_temp.disp('Rafael', 'so_manha', 'segunda', false, 'o Rafael só de manhã na segunda da semana que vem', c_qui, 'semana que vem') ->> 'pergunta',
      pg_temp.disp('Rafael', 'vem', 'segunda', false, 'o Rafael vem segunda na semana de 26/10', c_qui, 'semana de 26/10') ->> 'pergunta',
      pg_temp.disp('Rafael', 'nao_vem', 'quarta', false, 'o Rafael não vem quarta na semana que vem', c_qui, 'semana que vem') ->> 'pergunta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G8d "não vem a semana toda" = "Rafael, semana de 09/11: não vem."; meio dia recusado; a semana passada recusada; "não vem quarta" na semana recusado (um dia só é por data)',
    a = pg_temp.releitura('• Rafael, semana de 09/11: não vem.')
        || ' | Para a semana, me diga os dias inteiros; meio dia só por data. | A semana de 26/10 já passou. Qual semana? | '
        || 'Para um dia só, me diga a data (ex.: "Roberto não vem quarta dia 18"); para a semana, os dias em que vem (ex.: "Roberto vem seg, ter e qui na semana que vem").',
    a);

  -- G5: a data dita pelo dono troca a linha da semana presa do mesmo dia
  begin
    perform public._agenda_equipe_dias_gravar(v_rafael, c_s, '{1,2,4}', false, 'diarista', 'seg ter qui', pg_temp.em(c_qui, '16:45'));
    a := pg_temp.cap(v_rafael, date '2026-11-18');
    v := pg_temp.disp('Rafael', 'vem', 'dia 18', false, 'o Rafael vem dia 18', c_qui);
    v2 := pg_temp.grava(c_qui, '17:10');
    v_res := pg_temp.ok(v_res, 'G5 "Rafael vem dia 18" (o dono, depois de ele dizer que não pode): a linha da semana de qua 18/11 sai (substituida_em) e a do dono vale — a capacidade vai de indisponível a livre',
      a like 'manha=indisponivel/0/Disse que não pode (semana de 16/11)%' and (v2 ->> 'ok')::boolean
      and pg_temp.semana(v_rafael, c_s) = '16/11=disponivel 17/11=disponivel 19/11=disponivel'
      and pg_temp.cap(v_rafael, date '2026-11-18') like 'manha=livre/1/% tarde=livre/1/%',
      a || ' | ' || pg_temp.cap(v_rafael, date '2026-11-18'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- G11: o *grava* do padrão do dono troca o padrão do diarista (A4)
  begin
    v := pg_temp.disp('Rafael', 'vem', 'terça e quinta', true, 'o Rafael vem toda terça e quinta', c_qui);
    v := pg_temp.grava(c_qui, '17:00');
    a := pg_temp.padroes(v_rafael);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set modo_dias = 'desligado' where id;
    v := pg_temp.disp('Rafael', 'vem', 'terça e quinta', true, 'o Rafael vem toda terça e quinta', c_qui);
    v := pg_temp.grava(c_qui, '17:00');
    b := pg_temp.padroes(v_rafael);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G11 "Rafael vem toda terça e quinta" + *grava*: com modo_dias em sombra, o padrão dito por ele (seg a sex) sai e fica só o do dono (A4); desligado, o de antes (os dois vivos)',
    a = '{2,4}:dono' and b = '{1,2,3,4,5}:diarista {2,4}:dono', a || ' | ' || b);

  -- G16: a capacidade semanal com a linha do dono (só o Alex e o dono: o Rafael sem o padrão)
  begin
    update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-01 10:00-03'
     where payee_id = v_rafael and substituida_em is null and dias_semana is not null;
    perform set_config('agenda_teste.fase7b_dono', 'campo', true);
    execute current_setting('agenda_teste.fase7b');
    perform set_config('agenda_teste.fase7b_dono', '', true);
    v := public.agenda_capacidade_semanal(c_qui);
    update public.agenda_config set modo_dias = 'ligado' where id;
    v2 := public.agenda_capacidade_semanal(c_qui);
    v_res := pg_temp.ok(v_res, 'G16a com a linha do dono (seg a sex) e modo_dias em sombra e em ligado: 7,5 diárias e 6,5 comprometíveis (Alex 5 × 0,80 + o dono 5 × 0,50); o dono aparece com 2,5',
      (v ->> 'diarias_semana')::numeric = 7.5 and (v ->> 'comprometivel')::numeric = 6.5 and (v ->> 'conta_dono')::boolean
      and (select (e ->> 'diarias_semana')::numeric from jsonb_array_elements(v -> 'pessoas') e where (e ->> 'eh_dono')::boolean) = 2.5
      and (select (e ->> 'diarias_semana')::numeric from jsonb_array_elements(v -> 'pessoas') e where e ->> 'nome' = 'Alex') = 5
      and v2 = v,
      v::text);
    update public.agenda_config set modo_dias = 'desligado' where id;
    v := public.agenda_capacidade_semanal(c_qui);
    v2 := pg_temp.semanal_antes(c_qui);
    v_res := pg_temp.ok(v_res, 'G16b desligado (com a linha do dono): a de antes (20261030100600), byte a byte — 10 e 8',
      v = v2 and (v ->> 'diarias_semana')::numeric = 10 and (v ->> 'comprometivel')::numeric = 8, v::text || ' | ' || v2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v := public.agenda_capacidade_semanal(c_qui);
  v_res := pg_temp.ok(v_res, 'G16c sem a linha do dono, com modo_dias em sombra: a de antes, byte a byte (Alex e Rafael, 10 e 8)',
    v = pg_temp.semanal_antes(c_qui) and (v ->> 'diarias_semana')::numeric = 10, v::text);

  update public.agenda_config set modo_dias = 'desligado', modo_dupla = 'desligado' where id;
  perform pg_temp.gravar(v_res);
end
$rasc$;

-- ── G18. A dupla dita pelo planejar ──────────────────────────────────────────────────────────────────────────────
create function pg_temp.planejar(p_dados jsonb, p_trecho text) returns jsonb language sql as $f$
  select public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', 'Lenine', p_dados, p_trecho, date '2026-11-05')
$f$;

do $dupla$
declare
  v_res    jsonb := '[]'::jsonb;
  v_lenine uuid;
  v        jsonb;
  a        text;
  r        record;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('G18 (a dupla dita)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  select id into v_lenine from public.service_orders where service_order_number = 'OS-00074';
  update public.agenda_config set modo_dupla = 'sombra' where id;

  -- as releituras (Alex e Rafael na grade: sem o aviso)
  for r in select * from (values
      (1, '{"dupla": "nao"}', 'o Lenine vai com um só', 'vai com 1 pessoa só'),
      (2, '{"dupla": "todos"}', 'o Lenine precisa de dois o tempo todo', 'vai em dupla o tempo todo'),
      (3, '{"dupla": "inicio", "dupla_meios": 2}', 'o Lenine precisa de dois no primeiro dia', 'vai em dupla nos 2 primeiros meios-dias'),
      (4, '{"dupla": "fim", "dupla_meios": 2}', 'no último dia o Lenine vai em dupla', 'vai em dupla nos 2 últimos meios-dias'),
      (5, '{"dupla": "inicio", "dupla_meios": 1}', 'o Lenine vai em dupla só na primeira manhã, um meio dia', 'vai em dupla no primeiro meio-dia'),
      (6, '{"dupla": "inicio", "dupla_meios": 4}', 'o Lenine vai em dupla nos dois primeiros dias', 'vai em dupla nos 4 primeiros meios-dias'))
    x(o, dados, trecho, frase) order by o
  loop
    begin
      v := pg_temp.planejar(r.dados::jsonb, r.trecho);
      a := v ->> 'releitura';
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_res := pg_temp.ok(v_res, format('G18a.%s %s → "Lenine (OS-00074): %s." (§6.6)', r.o, r.dados, r.frase),
      a = pg_temp.releitura('• Lenine (OS-00074): ' || r.frase || '.'), coalesce(a, v::text));
  end loop;

  -- as recusas
  begin
    a := concat_ws(' | ',
      pg_temp.planejar('{"dupla": "inicio"}', 'o Lenine vai em dupla no início') ->> 'pergunta',
      pg_temp.planejar('{"dupla": "inicio", "dupla_meios": 3}', 'o Lenine vai em dupla no começo') ->> 'pergunta');
    begin
      perform pg_temp.planejar('{"dupla": "meio"}', 'o Lenine vai em dupla no meio');
      a := a || ' | aceitou';
    exception when sqlstate '22023' then a := a || ' | 22023';
    end;
    begin
      perform pg_temp.planejar('{"dupla": "todos", "dupla_meios": 2}', 'o Lenine vai em dupla o tempo todo, dois');
      a := a || ' | aceitou';
    exception when sqlstate '22023' then a := a || ' | 22023';
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G18b inicio sem os meios-dias pergunta quantos; 3 fora do trecho é recusado; a dupla fora da lista e os meios-dias com todos são erro de quem chamou (22023)',
    a = 'Em quantos meios-dias vai a dupla? (por exemplo, "dois no primeiro dia" = 2 meios-dias) | '
        || 'Não achei "3" no que você disse; me diga de novo em quantos meios-dias vai a dupla. | 22023 | 22023', a);

  -- o aviso com menos técnicos do que a dupla pede (só o Alex na grade)
  begin
    update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-01 10:00-03'
     where payee_id = 'f7b00000-0000-4000-8000-000000000302' and substituida_em is null and dias_semana is not null;
    -- FASE 7b: (7b P4, R4.3(c)) com modo_dupla fora de desligado, quem vem sob demanda com algum meio-dia livre no horizonte conta como
    -- a 2ª pessoa (_agenda_tecnicos_da_grade): "só o Alex na grade" é também sem a data dita do Bruno (ter 10/11)
    update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-01 10:00-03'
     where payee_id = 'f7b00000-0000-4000-8000-000000000303' and substituida_em is null;
    -- FASE 7b: fim
    v := pg_temp.planejar('{"dupla": "inicio", "dupla_meios": 2}', 'o Lenine precisa de dois no primeiro dia');
    a := v ->> 'releitura';
    v := pg_temp.planejar('{"dupla": "nao"}', 'o Lenine vai com um só');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G18c com só o Alex na grade: "… vai em dupla nos 2 primeiros meios-dias. Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine."; o "vai com um só" corrige e o aviso sai',
    a = pg_temp.releitura('• Lenine (OS-00074): vai em dupla nos 2 primeiros meios-dias. Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine.')
    and v ->> 'releitura' = pg_temp.releitura('• Lenine (OS-00074): vai com 1 pessoa só.'),
    coalesce(a, '') || ' | ' || coalesce(v ->> 'releitura', v::text));

  -- o *grava* grava a dupla (e o histórico)
  begin
    perform pg_temp.planejar('{"dupla": "inicio", "dupla_meios": 2}', 'o Lenine precisa de dois no primeiro dia');
    v := pg_temp.grava(date '2026-11-05', '17:20');
    select pl.dupla_dita || '/' || pl.dupla_meios || '/' || pl.dupla_motivo || '/' || (pl.dupla_em = pg_temp.em(date '2026-11-05', '17:20'))
           || '/' || (pl.historico -> -1 -> 'depois' ->> 'dupla_dita') || '/' || coalesce(pl.historico -> -1 -> 'antes' ->> 'dupla_dita', 'null')
      into a
      from public.os_planejamento pl where pl.service_order_id = v_lenine;
    perform pg_temp.planejar('{"dupla": "nao"}', 'o Lenine vai com um só');
    v := pg_temp.grava(date '2026-11-05', '17:30');
    select a || ' | ' || pl.dupla_dita || '/' || coalesce(pl.dupla_meios::text, 'null') || '/' || pl.dupla_motivo into a
      from public.os_planejamento pl where pl.service_order_id = v_lenine;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G18d o *grava*: dupla_dita inicio, dupla_meios 2, dupla_motivo "você disse: vai em dupla nos 2 primeiros meios-dias", dupla_em = a hora do *grava*, no histórico; "vai com um só" depois: nao, sem meios-dias',
    a = 'inicio/2/você disse: vai em dupla nos 2 primeiros meios-dias/true/inicio/null | nao/null/você disse: vai com 1 pessoa só', a);

  -- o prometido e a dupla na mesma linha: os dois gravam
  begin
    perform pg_temp.planejar('{"dupla": "todos", "prometido": "dia 18"}', 'o Lenine vai em dupla o tempo todo, eu disse dia 18 ao cliente');
    v := pg_temp.grava(date '2026-11-05', '17:40');
    select pl.dupla_dita || '/' || pl.prometido_ate into a from public.os_planejamento pl where pl.service_order_id = v_lenine;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'G18e o prometido e a dupla na mesma linha: os dois gravam (o *grava* não volta só com o prometido)',
    a = 'todos/2026-11-18', coalesce(a, v::text));

  update public.agenda_config set modo_dupla = 'desligado' where id;
  perform pg_temp.gravar(v_res);
end
$dupla$;

-- ── G19. As cópias ───────────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  f      record;
  v_mig  text;
  v_novo text;
  v_n    int;
begin
  for f in select * from (values
      ('agenda_capacidade', 'public.agenda_capacidade(date, date, date)', 'mig_correcao_equipe', '20261030100600', 6),
      ('agenda_capacidade_semanal', 'public.agenda_capacidade_semanal(date)', 'mig_correcao_equipe', '20261030100600', 2),
      ('agenda_rascunho_disponibilidade', 'public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text)',
       -- FASE 7b: (correção da revisão da 7b) + 2 blocos da correção 20261101100800 (também "-- FASE 7b:"; o 3º fica dentro de um bloco da
       -- 7b, com a marca de dentro, e sai junto com ele)
       'mig_rascunho_fase1', '20261024160600', 6),
      -- FASE 7b: fim
      ('_agenda_aplicar_disponibilidade', 'public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date)', 'mig_rascunho_fase1', '20261024160600', 3),
      ('agenda_rascunho_gravar', 'public.agenda_rascunho_gravar(uuid, date)', 'mig_compras_fase7a', '20261031100800', 1),
      ('agenda_rascunho_planejar', 'public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)', 'mig_leituras_fase5', '20261028100500', 3),
      ('_agenda_aplicar_planejar', 'public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)', 'mig_leituras_fase5', '20261028100500', 4),
      ('_agenda_rascunho_frase', 'public._agenda_rascunho_frase(text, jsonb)', 'mig_leituras_fase5', '20261028100500', 3))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('G19 %s: a cópia', f.nome), true, format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7b: fim', 'g');
    insert into _resultado values (
      format('G19 %s: sem os %s blocos "-- FASE 7b:", é o corpo de %s', f.nome, f.blocos, f.versao),
      pg_temp.corpo(v_mig, f.nome) <> '' and pg_temp.sem_7b(v_novo) = pg_temp.corpo(v_mig, f.nome) and v_n = f.blocos,
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(v_mig, f.nome)), length(pg_temp.sem_7b(v_novo))));
  end loop;
end
$copia$;

-- ── G20. As portas ───────────────────────────────────────────────────────────────────────────────────────────────
-- FASE 7b: (7b P3, 20261101100200) as 4 leituras que o foco equipe usa (_agenda_ver_equipe, invoker, authenticated e service_role)
-- ganharam authenticated na migration do P3 (a nota do P2: "uma leitura invoker do painel que as use precisa do grant na migration
-- dela"); a semana dita continua só do service_role. A coluna p3 diz quais (sem o P3 aplicado, nenhuma tem authenticated).
-- FASE 7b: fim
with f(sig, vol, p3) as (values
  ('public._agenda_dias_curtos(smallint[], boolean)', 'i', true), ('public._agenda_semana_perguntada(date)', 's', true),
  ('public._agenda_dias_declarados(uuid, date)', 's', true), ('public._agenda_chance_de_falta(uuid, date)', 's', true),
  ('public._agenda_semana_dita(text, text, date)', 's', false))
insert into _resultado
select 'G20a as 5 novas de leitura e de texto: invoker, search_path fixo, a volatilidade da spec; nunca anon; o service_role; authenticated só nas 4 que o foco equipe lê (com o P3)',
       bool_and(not p.prosecdef and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'
                and not has_function_privilege('anon', p.oid, 'execute')
                and has_function_privilege('authenticated', p.oid, 'execute')
                    = (f.p3 and to_regprocedure('public.agenda_equipe_semana(date, timestamptz)') is not null)
                and has_function_privilege('service_role', p.oid, 'execute')) and count(*) = 5,
       string_agg(f.sig, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')
                                          or has_function_privilege('authenticated', p.oid, 'execute')
                                             <> (f.p3 and to_regprocedure('public.agenda_equipe_semana(date, timestamptz)') is not null))
  from f join pg_proc p on p.oid = f.sig::regprocedure;
insert into _resultado
select 'G20b o gravador da semana: security definer, VOLATILE, search_path fixo, sem grant a ninguém (nem service_role)',
       p.prosecdef and p.provolatile = 'v' and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute'), null
  from pg_proc p where p.oid = 'public._agenda_equipe_dias_gravar(uuid, date, smallint[], boolean, text, text, timestamptz, uuid, uuid, uuid)'::regprocedure;
insert into _resultado
select 'G20c anon recebe 42501 nas novas (o dia curto e a semana dita)',
       pg_temp.como('anon', $q$select public._agenda_dias_curtos('{1}')$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public._agenda_semana_dita('semana que vem', 'semana que vem', date '2026-11-05')::text$q$) like 'erro 42501%',
       pg_temp.como('anon', $q$select public._agenda_dias_curtos('{1}')$q$);
insert into _resultado
select 'G20d o rascunho de disponibilidade só com a assinatura nova (p_semana no fim): definer, authenticated e service_role, nunca anon; a de 8 argumentos não existe',
       to_regprocedure('public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date)') is null
       and p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
       and not has_function_privilege('anon', p.oid, 'execute')
       and (select count(*) from pg_proc x where x.proname = 'agenda_rascunho_disponibilidade' and x.pronamespace = 'public'::regnamespace) = 1,
       null
  from pg_proc p where p.oid = 'public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date, text)'::regprocedure;
with f(sig, quem) as (values
  ('public.agenda_capacidade(date, date, date)', 'a'), ('public.agenda_capacidade_semanal(date)', 'a'),
  ('public.agenda_rascunho_gravar(uuid, date)', 'a'), ('public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)', 'a'),
  ('public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date)', 's'), ('public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)', 's'),
  ('public._agenda_rascunho_frase(text, jsonb)', 's'))
insert into _resultado
select 'G20e as recriadas com as portas de antes (as leituras e as RPCs: authenticated e service_role; as de dentro: só service_role; nunca anon)',
       bool_and(not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                and has_function_privilege('authenticated', p.oid, 'execute') = (f.quem = 'a')) and count(*) = 7,
       string_agg(f.sig, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')
                                          or has_function_privilege('authenticated', p.oid, 'execute') <> (f.quem = 'a'))
  from f join pg_proc p on p.oid = f.sig::regprocedure;

select teste, ok, detalhe from _resultado order by teste;

rollback;
