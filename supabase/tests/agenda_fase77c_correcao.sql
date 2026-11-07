-- Prova da correção da revisão da etapa 7c da Agenda de Produção (migration 20261102100580): cada achado reproduzido e consertado pela
-- causa, com o "desligado = antes" e as cópias (notas-fase77c.md, seção "Correção da revisão").
-- bancada: depende de 20261102100580
--
--   K0  as cópias: as 10 recriadas, tirados os blocos e as marcas da correção, são a definição mais nova de antes, byte a byte (e a viva é
--       a desta migration); nenhuma é do anon; as portas são as de antes
--   K11 (achado 11; a equipe real) a pergunta de quem faz o quê é refeita quando o dono grava "o Alex não sobe no teto" antes de vê-la:
--       o texto novo não diz "e sobe no teto" e o exemplo não sugere o que já vale; sem mudança, não refaz
--   K1  (achado 1, AG7-10c) quem responde pelas etapas: só o responsável da OS na equipe do meio-dia; o "responsável da equipe" e o ajudante
--       não respondem (nulo: o dono confere)
--   K10 (achado 10) a OS começada antes das etapas: os meios-dias feitos sem linha de etapa saem do total — o plano exato dos que faltam
--       cabe (nada de "não cabe" falso); com os dias de antes congelados, o de antes
--   K12 (achado 12) o prazo que já passou não vira "Até qui 10/09 não cabe"
--   K5  (achado 5) em teste, o dia da pessoa diz que é teste ("— em teste (a equipe ainda não recebe), o que fazer: …"); ligado, o de antes
--   K16 (achado 16) o exemplo do foco *agenda quem faz* não sugere "o Mateus instala sozinho" para quem vem sob demanda (o novo)
--   K9  (achado 9) a troca avisada do responsável vai no texto do item (o que vira a ação do "o que mudou") e na ação aplicada
--   K7  (achado 7) a pergunta por OS na ordem da produção: a OS que a vigia tira depois da rodada do dia ganha a pergunta no tique seguinte;
--       a proposta de ontem conta na rodada de hoje; fecha quando volta a caber; em teste, a saída de antes
--   K14 (achado 14) a linha (n): com a chamada da 7b já vista e fora do dia dela e a de quem faz o quê nunca vista, a de quem faz o quê vai
--       primeiro (conta como vista) e a chamada fica para o dia dela; com a chamada perdendo hoje, a de antes
--   K8  (achado 8) com a linha da 7c ligada, a mensagem ao cliente (75) ganha a forma curta; sem a 7c ligada, a de antes
--   K2  (achado 2) a (n) com quem faz o quê nunca vista há 2 dias úteis sobe a 77; com 1 dia, 75; com a pergunta do gestor que vence hoje
--       (76), não sobe. (Correção 2, achado 1: sem a pergunta do gestor de 76 para ceder, volta a 75 — o K2a; o C1 da correção 2 prova a
--       subida com a de 76 e com a mensagem ao cliente.)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase77c_correcao.sql
--   Seguro em produção: termina em ROLLBACK. Fora da bancada, o K0 confere só as portas e o resto sai PULADO.
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
-- O texto sem os blocos da correção ("-- FASE 7c: (7c correção … -- FASE 7c: fim") e sem as marcas dela ("-- (7c correção … -- (7c: fim)").
create function pg_temp.sem_corr(p text) returns text language plpgsql immutable as $f$
declare
  v_out text[] := '{}';
  l     text;
  v_b   boolean := false;
  v_m   boolean := false;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_b and not v_m and l ~ '^\s*-- FASE 7c: \(7c correção' then v_b := true; continue; end if;
    if not v_b and not v_m and l ~ '^\s*-- \(7c correção' then v_m := true; continue; end if;
    if v_b then if l ~ '^\s*-- FASE 7c: fim' then v_b := false; end if; continue; end if;
    if v_m then if l ~ '^\s*-- \(7c: fim\)' then v_m := false; end if; continue; end if;
    v_out := v_out || l;
  end loop;
  return array_to_string(v_out, E'\n');
end $f$;

-- FASE 7c: (correção 2 da revisão, 20261102100590) o texto sem os blocos e as marcas da correção 2 ("-- FASE 7c: (7c correção 2, …" /
-- "-- (7c correção 2, …"), para o K0c comparar a viva com a desta migration: a 100590 recria 4 das 10 (_agenda_tarefas_planejar,
-- _agenda_linhas_do_fechamento, agenda_habilidade e _agenda_ver_habilidades) só com acréscimos; o C0 de agenda_fase77c_correcao2.sql
-- confere as cópias dela.
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
-- FASE 7c: fim

-- FASE 7d: (7d P4) o texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim": a 20261107100300 recria esta função de novo (só acréscimo), e a régua daqui
-- é de um bloco específico; ela sai antes, na viva (molde: B11d de agenda_fase7c_base.sql)
create function pg_temp.sem_7d(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[df]:' and l !~ '^\s*-- FASE 7[df]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[df]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[df]: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- FASE 7d: fim

-- ── K0. As cópias e as portas (as portas sem fixture) ──────────────────────────────────────────────────────────────────────────
do $k0$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_correcao_fase7c', true), '');
  v_dif  text;
  v_viva text;
  v_sem  text;
  v_n    int := 0;
  v_anon text;
  v_def  text;
  v_novo text;
  f      record;
begin
  -- as portas: nenhuma das 10 do anon; as definer continuam definer (create or replace mantém os grants e o security)
  select string_agg(x.sig, ', ') filter (where p.oid is null or has_function_privilege('anon', p.oid, 'execute')),
         string_agg(x.sig, ', ') filter (where p.oid is not null and p.prosecdef is distinct from x.definer)
    into v_anon, v_def
    from (values ('public._agenda_tarefas_planejar(uuid, date, text)', false), ('public.os_tarefas_da_os(uuid, date)', true),
                 ('public.agenda_dia_da_pessoa(uuid, date, date)', false), ('public._agenda_linhas_do_fechamento(date)', false),
                 ('public._agenda_habilidade_perguntas_os(date, timestamptz)', true), ('public.agenda_habilidade(date, timestamptz)', true),
                 ('public._agenda_habilidade_pergunta_texto(date, uuid[])', false), ('public._agenda_habilidade_propor(date, timestamptz)', true),
                 ('public._agenda_ver_habilidades(date, timestamptz, uuid)', true),
                 ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', true)) x(sig, definer)
    left join pg_proc p on p.oid = to_regprocedure(x.sig);
  v_res := pg_temp.ok(v_res, 'K0a as 10 recriadas existem, nenhuma é executável pelo anon e as definer continuam definer (as portas de antes)',
    v_anon is null and v_def is null, coalesce('do anon: ' || v_anon, '') || coalesce(' definer trocado: ' || v_def, ''));
  if v_mig = '' then
    insert into _resultado values ('K0b as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;
  for f in select * from (values
      ('_agenda_tarefas_planejar', 'agenda_teste.mig_tarefas_fase7c', 4), ('os_tarefas_da_os', 'agenda_teste.mig_tarefas_fase7c', 1),
      ('agenda_dia_da_pessoa', 'agenda_teste.mig_tarefas_fase7c', 2), ('_agenda_linhas_do_fechamento', 'agenda_teste.mig_tarefas_fase7c', 4),
      ('_agenda_habilidade_perguntas_os', 'agenda_teste.mig_rodada_fase7c', 2), ('agenda_habilidade', 'agenda_teste.mig_rodada_fase7c', 2),
      ('_agenda_habilidade_pergunta_texto', 'agenda_teste.mig_rodada_fase7c', 2), ('_agenda_habilidade_propor', 'agenda_teste.mig_rodada_fase7c', 1),
      ('_agenda_ver_habilidades', 'agenda_teste.mig_leituras_fase7c', 1), ('agenda_propor', 'agenda_teste.mig_motor_fase7c', 2)) x(nome, origem, blocos)
  loop
    if coalesce(current_setting(f.origem, true), '') = '' then
      v_sem := concat_ws(', ', v_sem, f.nome);
      continue;
    end if;
    v_n := v_n + 1;
    if pg_temp.corpo(current_setting(f.origem), f.nome) = ''
       or pg_temp.sem_corr(pg_temp.corpo(v_mig, f.nome)) is distinct from replace(pg_temp.corpo(current_setting(f.origem), f.nome), E'\r\n', E'\n')
       or (select count(*) from regexp_matches(pg_temp.corpo(v_mig, f.nome), '\n\s*-- (FASE 7c: )?\(7c correção', 'g')) <> f.blocos then
      v_dif := concat_ws(', ', v_dif, f.nome);
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f.nome;
    if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f.nome) <> 1
       -- FASE 7c: (correção 2 da revisão, 20261102100590) a viva sem os blocos e as marcas da correção 2
       or pg_temp.sem_corr2(pg_temp.sem_7d(v_novo)) is distinct from pg_temp.corpo(v_mig, f.nome) then
       -- FASE 7c: fim
      v_viva := concat_ws(', ', v_viva, f.nome);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'K0b as 10 recriadas, tirados os blocos e as marcas da correção, são a definição mais nova de antes (a 100550, a 100400, a 100500 e a 100100), byte a byte, com 4, 1, 2, 4, 2, 2, 2, 1, 1 e 2 blocos/marcas',
    v_n = 10 and v_dif is null and v_sem is null,
    format('%s conferidas; diferentes: %s; sem a origem: %s', v_n, coalesce(v_dif, 'nenhuma'), coalesce(v_sem, 'nenhuma')));
  v_res := pg_temp.ok(v_res, 'K0c no banco está a desta migration (uma definição de cada)', v_viva is null, coalesce(v_viva, 'iguais'));
  v_res := pg_temp.ok(v_res, 'K0d a migration só recria (10 funções, nenhuma nova: nenhum create table, column, index nem grant)',
    (select count(*) from regexp_matches(v_mig, '\ncreate or replace function public\.([a-z_0-9]+)\(', 'g')) = 10
    and v_mig !~* '\n\s*(create (table|index|unique index)|alter table|grant |revoke |drop )',
    (select count(*) from regexp_matches(v_mig, '\ncreate or replace function public\.([a-z_0-9]+)\(', 'g'))::text);
  perform pg_temp.gravar(v_res);
end
$k0$;

-- ── As fixtures e os ajudantes ──────────────────────────────────────────────────────────────────────────────────────────────────
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
create function pg_temp.nao_vem(p_nome text, p_de date, p_ate date) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(p_de, p_ate, '[]'), null, 'indisponivel', 'dono', 'não vem (teste)', timestamptz '2026-11-04 10:01-03'
    from public.payees p where p.name = p_nome and p.active
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

-- ── K11. A pergunta de quem faz o quê acompanha o que o dono disse (a equipe real; antes da fixture sintética) ───────────────────────
do $k11$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  q1    public.agenda_perguntas;
  q2    public.agenda_perguntas;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
begin
  if not pg_temp.na_bancada() or exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    insert into _resultado values ('K11 a pergunta refeita', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  begin
    perform set_config('agenda_teste.fase7b_equipe', 'real', true);
    execute current_setting('agenda_teste.fase7c');
    perform set_config('agenda_teste.fase7b_equipe', '', true);
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    q1 := pg_temp.pergunta_aberta();
    -- o dono grava "o Alex não sobe no teto" antes de ver a pergunta (a etiqueta de altura do dono; o caminho do *grava*)
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em, criado_por)
    values (pg_temp.pessoa('Alex'), 'altura', 0, 'dono', 'vale', 'você disse', 'o Alex não sobe no teto',
            pg_temp.em(date '2026-11-06', '09:01'), pg_temp.em(date '2026-11-06', '09:01'), pg_temp.adm());
    v := public._agenda_habilidade_propor(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:15'));
    q2 := pg_temp.pergunta_aberta();
    t1 := (v ->> 'refeita') || ' | ' || (select x.estado || ' ' || x.resolvida_motivo from public.agenda_perguntas x where x.id = q1.id)
          || ' | ' || (q2.id <> q1.id)::text || ' ' || q2.modo || ' ' || (q2.mostrada_vezes)::text;
    t2 := q2.texto;
    -- a rodada de novo sem mudança: não refaz
    v := public._agenda_habilidade_propor(date '2026-11-09', pg_temp.em(date '2026-11-09', '16:15'));
    t3 := (v ->> 'refeita') || ' ' || ((v ->> 'pergunta_id')::uuid = q2.id)::text;
    -- a de antes (sem a altura do dono): o texto do R5.1-6, byte a byte
    t4 := q1.texto;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  v_res := pg_temp.ok(v_res, 'K11a antes da altura do dono, o texto é o do R5.1-6 (com "e sobe no teto"), byte a byte',
    t4 = 'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: Alex instala sozinho, também com 220 V ou banco de bateria, e sobe no teto (você disse que ele vem todo dia útil). Comissionar Victron fica com você. Se você não responder até as 18:00 do próximo dia útil depois de ver esta pergunta, fica assim. Para corrigir, me diga numa frase (ex.: "o Alex não sobe no teto" ou "o Alex é ajudante").',
    t4);
  v_res := pg_temp.ok(v_res, 'K11b o dono grava "o Alex não sobe no teto" antes de ver: a rodada refaz a pergunta (a de antes descartada, "a proposta mudou: perguntei de novo"; a nova ligada, nunca vista)',
    t1 = 'true | descartada a proposta mudou: perguntei de novo | true ligado 0', t1);
  v_res := pg_temp.ok(v_res, 'K11c o texto novo não diz "e sobe no teto" e o exemplo não sugere o que já vale ("o Alex é ajudante")',
    t2 = 'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: Alex instala sozinho, também com 220 V ou banco de bateria (você disse que ele vem todo dia útil). Comissionar Victron fica com você. Se você não responder até as 18:00 do próximo dia útil depois de ver esta pergunta, fica assim. Para corrigir, me diga numa frase (ex.: "o Alex é ajudante").',
    t2);
  v_res := pg_temp.ok(v_res, 'K11d sem mudança, a rodada seguinte não refaz (a mesma pergunta)', t3 = 'false true', t3);
  perform pg_temp.gravar(v_res);
end
$k11$;

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
-- quem responde em cada meio-dia do plano das etapas, na ordem ("você" = nulo: o dono pela conferência)
create function pg_temp.respondem(p jsonb) returns text language sql stable as $f$
  select string_agg(to_char((m ->> 'dia')::date, 'DD') || left(m ->> 'turno', 1) || ':' || coalesce(public._agenda_nome_curto(py.name), 'você'),
                    ',' order by m ->> 'dia', m ->> 'turno' = 'tarde')
    from jsonb_array_elements(p -> 'meios') m left join public.payees py on py.id = (m ->> 'responde')::uuid
$f$;

-- ── K1. Quem responde pelas etapas (AG7-10c) ───────────────────────────────────────────────────────────────────────────────────────
do $k1$
declare
  v_res jsonb := '[]'::jsonb;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K1 quem responde', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.etapas_modo('ligado');
    perform set_config('agenda.hoje', '2026-11-03', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os(n), date '2026-11-03', pg_temp.em(date '2026-11-03', '07:10'))
       from unnest(array['OS-97192', 'OS-97194']) n;
    -- o Lenine (192): a manhã de qua só com o Mateus (ajudante, com telefone e na rotina); as outras com o Alex (o responsável da OS)
    t1 := pg_temp.respondem(public._agenda_tarefas_planejar(pg_temp.os('OS-97192'), date '2026-11-03', 'ligado'));
    -- o Vanderlei (194) com o responsável dito pelo dono = o Roberto, que não está no plano (o Alex faz os 4 meios-dias): ninguém responde
    update public.os_planejamento set lider_payee_id = pg_temp.pessoa('Roberto'), lider_em = pg_temp.em(date '2026-11-03', '07:00'),
                                      lider_trecho = 'o responsável do Vanderlei é o Roberto'
     where service_order_id = pg_temp.os('OS-97194');
    t2 := pg_temp.respondem(public._agenda_tarefas_planejar(pg_temp.os('OS-97194'), date '2026-11-03', 'ligado'));
    -- com o responsável dito = o Alex, ele responde em todos
    update public.os_planejamento set lider_payee_id = pg_temp.pessoa('Alex') where service_order_id = pg_temp.os('OS-97194');
    t3 := pg_temp.respondem(public._agenda_tarefas_planejar(pg_temp.os('OS-97194'), date '2026-11-03', 'ligado'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K1a o ajudante sozinho no meio-dia (a manhã do Mateus no Lenine) não responde: você confere; o Alex (o responsável da OS) responde nos dele',
    t1 = '04m:você,04t:Alex,05m:Alex,05t:Alex', t1);
  v_res := pg_temp.ok(v_res, 'K1b o responsável da OS (o Roberto, dito) fora do meio-dia: o "responsável da equipe" (o Alex, de maior instala) não responde no lugar dele — você confere',
    t2 = '10m:você,10t:você,11m:você,11t:você', t2);
  v_res := pg_temp.ok(v_res, 'K1c com o responsável da OS no meio-dia (o Alex, dito), ele responde em todos', t3 = '10m:Alex,10t:Alex,11m:Alex,11t:Alex', t3);
  perform pg_temp.gravar(v_res);
end
$k1$;

-- ── K10. A OS começada antes das etapas ─────────────────────────────────────────────────────────────────────────────────────────────
do $k10$
declare
  v_res jsonb := '[]'::jsonb;
  p  jsonb;
  t1 text; t2 text; t3 text; t4 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K10 a OS começada antes das etapas', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    -- o Flávio (191): 2 dias ditos (4 meios-dias); ter 03/11 manhã e tarde com o Alex já passaram SEM linha de etapa (as etapas nascem
    -- na qua 04/11); sex 06/11 manhã e tarde é o que falta — o plano exato
    perform pg_temp.etapas_modo('ligado');
    perform set_config('agenda.hoje', '2026-11-04', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '10:00'));
    p := public._agenda_tarefas_planejar(pg_temp.os('OS-97191'), date '2026-11-04', 'ligado');
    t1 := (p ->> 'total') || ' ' || (p ->> 'falta') || ' ' || (p ->> 'sobra_no_prazo') || ' ' || (p ->> 'meios_ate_prazo');
    t2 := coalesce(public.os_tarefas_da_os(pg_temp.os('OS-97191'), date '2026-11-04') ->> 'texto', '-');
    t3 := (select count(*)::text from public.agenda_perguntas q where q.chave like 'tarefa:prazo:%' and q.estado = 'aberta')
          || ' ' || ((public._agenda_tarefas_excecoes(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:20'), array[pg_temp.os('OS-97191')])) ->> 'nao_cabe');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o de antes: com a terça congelada (as linhas de etapa de ter 03/11), a conta é a da linha (o T6d)
    perform pg_temp.etapas_modo('ligado');
    perform set_config('agenda.hoje', '2026-11-03', true);
    perform public.agenda_tarefas_rodar(date '2026-11-03', pg_temp.em(date '2026-11-03', '07:10'));
    perform set_config('agenda.hoje', '2026-11-04', true);
    p := public._agenda_tarefas_planejar(pg_temp.os('OS-97191'), date '2026-11-04', 'ligado');
    t4 := (p ->> 'total') || ' ' || (p ->> 'falta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K10a os 2 meios-dias de terça sem linha de etapa saem do total: as etapas repartem os 2 que faltam, cabe até sex 06/11 (sobra 0) — o total da saída continua o da OS (4)',
    t1 = '4 2.000 0.000 2', t1);
  v_res := pg_temp.ok(v_res, 'K10b a leitura das etapas não diz "não cabe"', t2 like 'Etapas: 0 de 4 feitas. Falta: %' and t2 not like '%não cabe%', t2);
  v_res := pg_temp.ok(v_res, 'K10c nenhuma pergunta "o que falta não cabe até o prazo" nasce', t3 like '0 %' and coalesce(split_part(t3, ' ', 2), '0') in ('0', ''), t3);
  v_res := pg_temp.ok(v_res, 'K10d com a terça congelada (as linhas de etapa), a conta é a de antes: o total 4 e o que falta pela linha', t4 like '4 %', t4);
  perform pg_temp.gravar(v_res);
end
$k10$;

-- ── K12. O prazo que já passou ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $k12$
declare
  v_res jsonb := '[]'::jsonb;
  r  jsonb;
  t1 text; t2 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K12 o prazo vencido', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    -- o Vanderlei (194) marcado ter 10 e qua 11/11, com o prazo do cliente em qui 10/09 (já passou)
    perform pg_temp.etapas_modo('ligado');
    perform set_config('agenda.hoje', '2026-11-04', true);
    update public.os_planejamento set precisa_ate = date '2026-09-10' where service_order_id = pg_temp.os('OS-97194');
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97194'), date '2026-11-04', pg_temp.em(date '2026-11-04', '10:00'));
    r := public.os_tarefas_da_os(pg_temp.os('OS-97194'), date '2026-11-04');
    t1 := (r ->> 'prazo') || ' ' || (r ->> 'cabe') || ' | ' || coalesce(r ->> 'texto', '-');
    -- com o prazo de amanhã (qui 05/11) o "não cabe" de sempre continua
    update public.os_planejamento set precisa_ate = date '2026-11-05' where service_order_id = pg_temp.os('OS-97194');
    r := public.os_tarefas_da_os(pg_temp.os('OS-97194'), date '2026-11-04');
    t2 := (r ->> 'cabe') || ' | ' || coalesce(r ->> 'texto', '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K12a o prazo vencido (qui 10/09): a leitura não diz "Até qui 10/09 não cabe" e cabe = true',
    t1 like '2026-09-10 true | Etapas: %' and t1 not like '%não cabe%', t1);
  v_res := pg_temp.ok(v_res, 'K12b com o prazo por vir (qui 05/11, antes dos dias marcados), o "não cabe" de sempre', t2 like 'false | %Até qui 05/11 não cabe%', t2);
  perform pg_temp.gravar(v_res);
end
$k12$;

-- ── K5. O dia da pessoa em teste ────────────────────────────────────────────────────────────────────────────────────────────────────
do $k5$
declare
  v_res jsonb := '[]'::jsonb;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K5 o dia da pessoa em teste', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.etapas_modo('sombra');
    perform set_config('agenda.hoje', '2026-11-04', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97192'), date '2026-11-04', pg_temp.em(date '2026-11-04', '10:00'));
    t1 := public.agenda_dia_da_pessoa(pg_temp.pessoa('Alex'), date '2026-11-05', date '2026-11-04') ->> 'texto';
    t3 := (select max(char_length(i)) from unnest(string_to_array(t1, E'\n')) i)::text;
    perform pg_temp.etapas_modo('ligado');
    t2 := public.agenda_dia_da_pessoa(pg_temp.pessoa('Alex'), date '2026-11-05', date '2026-11-04') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K5a em teste, o item da OS diz que é teste: " — em teste (a equipe ainda não recebe), o que fazer: …" (e não " — o que fazer: …")',
    t1 like '%Lenine (OS-97192)% — em teste (a equipe ainda não recebe), o que fazer: 1) %' and t1 not like '% — o que fazer: %', t1);
  v_res := pg_temp.ok(v_res, 'K5b ligado, o de antes: " — o que fazer: …"', t2 like '%Lenine (OS-97192)% — o que fazer: 1) %' and t2 not like '%em teste%', t2);
  perform pg_temp.gravar(v_res);
end
$k5$;

-- ── K16. O exemplo do foco não tira a proteção de quem vem sob demanda ─────────────────────────────────────────────────────────────
do $k16$
declare
  v_res jsonb := '[]'::jsonb;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K16 o exemplo do foco', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    perform set_config('agenda.hoje', '2026-11-04', true);
    -- o Mateus (ajudante 2 do dono) com o padrão dele: ajudante (papel 1) — o exemplo de sempre, "o Mateus instala sozinho"
    t1 := substring(public._agenda_ver_habilidades(date '2026-11-04', pg_temp.em(date '2026-11-04', '10:00')) ->> 'texto' from 'Para corrigir, .*$');
    -- o Mateus passa a vir só nas datas que o dono diz (sob demanda: o padrão dele substituído e duas datas): nunca vai sozinho (papel novo)
    update public.agenda_disponibilidade set substituida_em = pg_temp.em(date '2026-11-04', '09:00')
     where payee_id = pg_temp.pessoa('Mateus') and dias_semana is not null and substituida_em is null;
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
    select pg_temp.pessoa('Mateus'), daterange(d, d, '[]'), null, 'disponivel', 'dono', 'Você disse que vem (sob demanda)', pg_temp.em(date '2026-11-04', '09:00')
      from unnest(array[date '2026-11-10', date '2026-11-11']) d;
    t2 := substring(public._agenda_ver_habilidades(date '2026-11-04', pg_temp.em(date '2026-11-04', '10:00')) ->> 'texto' from 'Para corrigir, .*$');
    t3 := (select h.papel::text || ' ' || h.texto from public.agenda_habilidades(date '2026-11-04', array[pg_temp.pessoa('Mateus')]) h);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K16a o ajudante (papel 1) continua o exemplo da spec: "o Mateus instala sozinho"', t1 = 'Para corrigir, me diga numa frase (ex.: "o Mateus instala sozinho").', t1);
  v_res := pg_temp.ok(v_res, 'K16b quem vem sob demanda (o novo, nunca sozinho) nunca é o exemplo de "instala sozinho": a frase tiraria a proteção dele',
    t3 like '2 %' and t2 not like '%instala sozinho%' and t2 like 'Para corrigir, me diga numa frase (ex.: "o % é ajudante").', t3 || ' | ' || t2);
  perform pg_temp.gravar(v_res);
end
$k16$;

-- ── K9. A troca do responsável no "o que mudou" ─────────────────────────────────────────────────────────────────────────────────────
do $k9$
declare
  v_res jsonb := '[]'::jsonb;
  v  jsonb;
  ap jsonb;
  t1 text; t2 text; t3 text; t4 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K9 a troca do responsável', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    -- o Edu (175): o Roberto fez o 1º dia (ter 03/11) e não vem de qui 05 a ter 10/11: a troca avisada (o M6b do motor)
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    perform pg_temp.nao_vem('Roberto', date '2026-11-05', date '2026-11-10');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97175')], '{}'::jsonb, true, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:15'));
    t1 := (select i ->> 'texto' from jsonb_array_elements(v -> 'itens') i where i ->> 'numero' = 'OS-97175' and i ->> 'op' = 'criar' limit 1);
    ap := public.agenda_aplicar((v ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    t2 := (select a.texto from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-97175') and a.proposta_id = (v ->> 'proposta_id')::uuid
            order by a.criada_em desc limit 1);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- sem a troca (o Roberto livre): o texto de antes
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97175')], '{}'::jsonb, false, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:15'));
    t3 := (select i ->> 'texto' from jsonb_array_elements(v -> 'itens') i where i ->> 'numero' = 'OS-97175' and i ->> 'op' = 'criar' limit 1);
    -- em teste (os 3 em sombra), nada de troca
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    perform pg_temp.nao_vem('Roberto', date '2026-11-05', date '2026-11-10');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97175')], '{}'::jsonb, false, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:15'));
    t4 := (select i ->> 'texto' from jsonb_array_elements(v -> 'itens') i where i ->> 'numero' = 'OS-97175' and i ->> 'op' = 'criar' limit 1);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K9a com a troca avisada, o texto do item termina " — troquei o responsável: Roberto não está livre até qua 11/11; segui com <quem vai>." (até 320; com a fixture das etapas, o Mateus)',
    t1 like 'Edu (OS-97175): sex 06 e seg 09/11, % — troquei o responsável: Roberto não está livre até qua 11/11; segui com %.' and char_length(t1) <= 320, t1);
  v_res := pg_temp.ok(v_res, 'K9b a ação aplicada (o "o que mudou", o fechamento e o aviso leem dela) diz a troca', t2 like 'Edu (OS-97175): % — troquei o responsável: Roberto não está livre até qua 11/11; segui com %', t2);
  v_res := pg_temp.ok(v_res, 'K9c sem troca, o texto de antes (nada de "troquei"); em teste, nada de troca',
    t3 like 'Edu (OS-97175): %' and t3 not like '%troquei%' and t4 not like '%troquei%', t3 || ' | ' || t4);
  perform pg_temp.gravar(v_res);
end
$k9$;

-- ── K7. A pergunta por OS na ordem em que a produção roda ───────────────────────────────────────────────────────────────────────────
do $k7$
declare
  v_res jsonb := '[]'::jsonb;
  v  jsonb;
  r  jsonb;
  t1 text; t2 text; t3 text; t4 text; t5 text; t6 text; t7 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K7 a pergunta por OS', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado', 'desligado');
    -- a rodada do dia (16:15) roda antes da vigia: nada a perguntar ainda
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    t1 := (r ->> 'rodou') || ' ' || coalesce((r #>> '{contagens,perguntas_os,abertas}'), '-');
    -- depois dela, a vigia (no mesmo tique) tira o Caio (173: comissionamento em todos os dias, o dono "nunca") por habilidade
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97173')], '{}'::jsonb, true, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:16'));
    t2 := (select string_agg(f ->> 'motivo', ',') from jsonb_array_elements(v -> 'fora') f where f ->> 'numero' = 'OS-97173');
    -- o tique seguinte (16:30, a rodada do dia já rodou): a pergunta nasce
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:30'));
    t3 := (r ->> 'rodou') || ' ' || (r ->> 'ja_rodou') || ' ' || ((r -> 'perguntas_os') - 'proposta')::text || ' | '
          || coalesce((select x.modo || ' ' || x.texto from public.agenda_perguntas x
                        where x.chave = 'habilidade:os:' || pg_temp.os('OS-97173') and x.estado = 'aberta'), '-');
    -- no outro dia de manhã (cedo, sem proposta nova): uma aberta só
    r := public.agenda_habilidade(date '2026-11-05', pg_temp.em(date '2026-11-05', '09:15'));
    t4 := (r ->> 'cedo') || ' ' || ((r -> 'perguntas_os') - 'proposta')::text
          || ' ' || (select count(*) from public.agenda_perguntas x where x.chave = 'habilidade:os:' || pg_temp.os('OS-97173'));
    -- o dono diz que o Caio não precisa de quem comissiona: a vigia o encaixa e, no tique seguinte, a pergunta fecha
    update public.os_planejamento set exigencias_ditas = '{"comissionamento": "nao"}' where service_order_id = pg_temp.os('OS-97173');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97173')], '{}'::jsonb, true, 'vigia', null, date '2026-11-05',
                              pg_temp.em(date '2026-11-05', '09:20'));
    r := public.agenda_habilidade(date '2026-11-05', pg_temp.em(date '2026-11-05', '09:30'));
    t5 := ((r -> 'perguntas_os') - 'proposta')::text || ' ' || (select x.estado || ' ' || x.resolvida_motivo from public.agenda_perguntas x
                                                                where x.chave = 'habilidade:os:' || pg_temp.os('OS-97173'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a proposta de ontem (o gestor às 16:53, depois da rodada) e nenhuma hoje: a rodada do dia de hoje a lê
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado', 'desligado');
    insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina,
                                             modo_equipe, modo_diaria)
    select pg_temp.em(date '2026-11-04', '16:15'), date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'), c.modo_proposta, c.modo_vigia,
           '{}'::jsonb, 0, 0, 'habilidade', c.modo_equipe, c.modo_diaria
      from public.agenda_config c where c.id;
    update public.agenda_config set modo_habilidade = 'sombra' where id;
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97173')], '{}'::jsonb, true, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:53'));
    -- em teste (modo_habilidade em sombra), o tique é o de antes, byte a byte (a saída sem perguntas_os)
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '17:00'));
    t7 := (r - 'modos')::text;
    update public.agenda_config set modo_habilidade = 'ligado' where id;
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97173')], '{}'::jsonb, true, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:54'));
    r := public.agenda_habilidade(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:15'));
    t6 := (r ->> 'rodou') || ' ' || ((r #> '{contagens,perguntas_os}') - 'proposta')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K7a a rodada do dia (16:15) roda antes da vigia: ainda nada a perguntar', t1 = 'true 0', t1);
  v_res := pg_temp.ok(v_res, 'K7b depois da rodada, a vigia tira o Caio por falta de quem o serviço pede', t2 = 'habilidade', t2);
  v_res := pg_temp.ok(v_res, 'K7c no tique seguinte (a rodada já rodou) a pergunta habilidade:os nasce, ligada, com o texto da §6.4 (antes: nunca nascia)',
    t3 = 'false true {"abertas": 1, "resolvidas": 0} | ligado Caio: o serviço pede quem comissiona Victron em todos os dias, e nas próximas 6 semanas não acho ninguém com isso livre. Quem pode? Me diga numa frase (ex.: "o responsável do Caio é o Alex" ou "o Caio não precisa de quem comissiona Victron").',
    t3);
  v_res := pg_temp.ok(v_res, 'K7d no outro dia, cedo e sem proposta nova: nada muda (uma pergunta só)', t4 = 'true {"abertas": 0, "resolvidas": 0} 1', t4);
  v_res := pg_temp.ok(v_res, 'K7e o Caio volta a caber (a vigia de 09:20): no tique seguinte a pergunta fecha ("coube")',
    t5 = '{"abertas": 0, "resolvidas": 1} resolvida coube: a equipe tem quem o serviço pede', t5);
  v_res := pg_temp.ok(v_res, 'K7f a proposta de ontem (16:54, depois da rodada) conta na rodada de hoje, que antes só lia as de hoje', t6 = 'true {"abertas": 1, "resolvidas": 0}', t6);
  v_res := pg_temp.ok(v_res, 'K7g com modo_habilidade em teste, o tique depois da rodada é o de antes, byte a byte', t7 = '{"rodou": false, "ja_rodou": true}', t7);
  perform pg_temp.gravar(v_res);
end
$k7$;

-- ── K14, K8 e K2. A linha (n) e o fechamento cheio ──────────────────────────────────────────────────────────────────────────────────
-- a chamada da 7b (equipe_cadastro:chamada) aberta e ligada, vista p_vezes vezes, com o prazo p_veto
create function pg_temp.chamada(p_vezes int, p_veto timestamptz) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, criada_em, mostrada_vezes, mostrada_em, mostrada_via, veto_ate)
  values ('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-02',
          'Na agenda conto com Alex: você disse todo dia útil. Está certo? 1) Está certo (recomendo); 2) Mudou. Se não responder em 3 dias úteis depois de ver, sigo assim.',
          'ligado', '[{"n": 1, "texto": "Está certo"}, {"n": 2, "texto": "Mudou"}]'::jsonb, pg_temp.em(date '2026-11-02', '16:30'), p_vezes,
          case when p_vezes > 0 then pg_temp.em(date '2026-11-04', '17:30') end, case when p_vezes > 0 then 'fechamento' end, p_veto)
  returning id
$f$;
do $k14$
declare
  v_res jsonb := '[]'::jsonb;
  l    jsonb;
  q    public.agenda_perguntas;
  v_ch uuid;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K14 a linha (n)', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado');
    update public.agenda_config set modo_cadastro = 'ligado' where id;
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    perform public._agenda_habilidade_propor(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:15'));
    q := pg_temp.pergunta_aberta();
    -- a chamada já vista uma vez (qua), com o prazo na ter 10/11: na sex 06/11 não é o dia dela
    v_ch := pg_temp.chamada(1, pg_temp.em(date '2026-11-10', '18:00'));
    l := pg_temp.linha_n(date '2026-11-06');
    t1 := (l ->> 'perda') || ' ' || (l ->> 'pergunta_id' = q.id::text)::text || ' ' || (l -> 'pergunta_ids' ? v_ch::text)::text || ' | '
          || left(l ->> 'texto', 60) || ' | ' || (l ->> 'texto' like '%chamada%' or l ->> 'texto' like '%Na agenda conto com%')::text;
    -- no dia em que ela vence (ter 10/11), a de antes: a chamada primeiro (e conta)
    l := pg_temp.linha_n(date '2026-11-10');
    t2 := (l ->> 'perda') || ' ' || (l ->> 'pergunta_id' = v_ch::text)::text || ' | ' || left(l ->> 'texto', 40);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a chamada nunca vista (perde hoje: a de antes, a 7b primeiro e quem faz o quê como "Também", sem contar)
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado');
    update public.agenda_config set modo_cadastro = 'ligado' where id;
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    perform public._agenda_habilidade_propor(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:15'));
    q := pg_temp.pergunta_aberta();
    v_ch := pg_temp.chamada(0, null);
    l := pg_temp.linha_n(date '2026-11-06');
    t3 := (l ->> 'perda') || ' ' || (l ->> 'pergunta_id' = v_ch::text)::text || ' ' || (l -> 'pergunta_ids' ? q.id::text)::text || ' | '
          || (l ->> 'texto' like '%Também: quem faz o quê (marquei: %')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K14a a chamada já vista e fora do dia dela, quem faz o quê nunca vista: a de quem faz o quê vai primeiro, inteira, e conta; a chamada fica fora da linha (não gasta a vez dela)',
    t1 like '75 true false | Agenda: Para não mandar ninguém sozinho em serviço de risco% | false', t1);
  v_res := pg_temp.ok(v_res, 'K14b no dia em que a chamada vence, a de antes: a chamada primeiro (e conta)', t2 like '75 true | Agenda: Na agenda conto com%', t2);
  -- FASE 7c: (correção 2 da revisão, 20261102100590, achado 11) a de quem faz o quê da equipe, ligada, que vai como "Também" atrás da
  -- chamada leva o que foi marcado e o prazo e conta como vista (fica em pergunta_ids). Antes, "sem contar": na semana real ela nunca era
  -- vista (a chamada e depois o telefone do Alex iam sempre primeiro). A chamada continua primeiro.
  v_res := pg_temp.ok(v_res, 'K14c a chamada nunca vista (perde hoje): a chamada primeiro, quem faz o quê como "Também" com o prazo, e conta (correção 2, achado 11)', t3 = '75 true true | true', t3);
  -- FASE 7c: fim
  perform pg_temp.gravar(v_res);
end
$k14$;

-- uma mensagem ao cliente da véspera esperando *manda cliente* (aguardando_dono, aprovação pedida), para amanhã às 09:00
create function pg_temp.cliente_espera(p_numero text, p_hoje date) returns uuid language plpgsql as $f$
declare
  v_q  uuid;
  v_os uuid := pg_temp.os(p_numero);
begin
  insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, modo, opcoes, criada_em)
  values ('cliente_aprovar', 'cliente_aprovar:k8:' || v_os, v_os, 'Mensagem para o cliente (véspera): *manda cliente* ou *segura cliente*.',
          'ligado', '[]'::jsonb, pg_temp.em(p_hoje, '16:30'))
  returning id into v_q;
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, dia_alvo, modo, texto, enviar_em, valida_ate, aprovacao,
                                               pergunta_id, estado, dedupe_key, criada_em)
  select so.client_id, v_os, 'vespera', 'rodada', p_hoje + 2, 'ligado',
         'Bom dia! Aqui é o Gustavo, da HBR Marine. Amanhã chegamos o dia todo para o serviço no seu barco. Para não perdermos a viagem: onde o seu barco vai estar, e a chave fica com quem? Pode responder por aqui mesmo, até por áudio.',
         pg_temp.em(p_hoje + 1, '09:00'), pg_temp.em(p_hoje + 1, '12:00'), 'pedida', v_q, 'aguardando_dono', 'k8:' || v_os,
         pg_temp.em(p_hoje, '16:30')
    from public.service_orders so where so.id = v_os;
  return v_q;
end $f$;
do $k8$
declare
  v_res jsonb := '[]'::jsonb;
  ls   jsonb;
  c    jsonb;
  v_cq uuid;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K8 a forma curta do cliente', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado');
    update public.agenda_config set modo_cliente = 'ligado' where id;
    perform set_config('agenda.agora', pg_temp.em(date '2026-11-05', '17:30')::text, true);
    v_cq := pg_temp.cliente_espera('OS-97192', date '2026-11-05');
    -- sem a 7c ligada (desligada): a linha do cliente sem forma curta (a de antes)
    perform pg_temp.modos7c('desligado', 'desligado', 'desligado');
    c := (select l from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-05')) l where l ->> 'tipo' = 'cliente' and (l ->> 'perda')::int = 75);
    t1 := (c ->> 'pergunta_id' = v_cq::text)::text || ' ' || (c ? 'texto_curto')::text || ' | ' || left(c ->> 'texto', 50);
    -- com a de quem faz o quê ligada e nunca vista (a (n) com perda 75): a do cliente ganha a forma curta
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    perform public._agenda_habilidade_propor(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:15'));
    ls := public._agenda_linhas_do_fechamento(date '2026-11-05');
    c := (select l from jsonb_array_elements(ls) l where l ->> 'tipo' = 'cliente' and (l ->> 'perda')::int = 75);
    t2 := coalesce(c ->> 'texto_curto', '-') || ' | ' || (char_length(c ->> 'texto_curto') < char_length(c ->> 'texto'))::text
          || ' | ' || (select count(*) from jsonb_array_elements(ls) l where l ->> 'texto' like '%quem faz o quê%' and l ->> 'modo' = 'ligado');
    -- em teste (a 7c em sombra: a linha da 7c não é ligada), a de antes
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    perform public._agenda_habilidade_propor(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:16'));
    c := (select l from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-05')) l where l ->> 'tipo' = 'cliente' and (l ->> 'perda')::int = 75);
    t3 := (c ? 'texto_curto')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'K8a sem a 7c ligada, a linha do cliente (75) é a de antes: sem forma curta', t1 like 'true false | Mensagem para Lenine (%', t1);
  v_res := pg_temp.ok(v_res, 'K8b com a (n) de quem faz o quê ligada, a do cliente ganha a forma curta ("… espera *manda cliente Lenine* (sai …); *agenda clientes* mostra."), mais curta que a inteira',
    t2 like 'Mensagem para Lenine (%) espera *manda cliente Lenine* (sai %); *agenda clientes* mostra. | true | 1', t2);
  v_res := pg_temp.ok(v_res, 'K8c com a 7c em teste, a de antes (sem forma curta)', t3 = 'false', t3);
  perform pg_temp.gravar(v_res);
end
$k8$;

do $k2$
declare
  v_res jsonb := '[]'::jsonb;
  l    jsonb;
  t1 text; t2 text; t3 text; t4 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('K2 a (n) que ficou de fora', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    update public.agenda_config set modo_vigia = 'ligado' where id;
    -- a pergunta de quem faz o quê nasce na qua 04/11 às 16:15 e nunca é vista (o Secretário cheio a tirou)
    perform public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    l := pg_temp.linha_n(date '2026-11-04'); t1 := l ->> 'perda';
    l := pg_temp.linha_n(date '2026-11-05'); t2 := l ->> 'perda';
    l := pg_temp.linha_n(date '2026-11-06'); t3 := l ->> 'perda';
    -- na sex 06/11 a pergunta do gestor (76) vence hoje: a (n) não a tira
    insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, modo, opcoes, criada_em, mostrada_vezes, mostrada_em, mostrada_via, veto_ate)
    values ('situacao', 'situacao:k2:' || pg_temp.os('OS-97174') || ':comecada', pg_temp.os('OS-97174'),
            'Duda (OS-97174) está em andamento: o serviço já começou? Se você não me disser nada até sex 06/11 às 18:00, conto o serviço inteiro.',
            'ligado', '[]'::jsonb, pg_temp.em(date '2026-11-04', '16:53'), 1, pg_temp.em(date '2026-11-05', '17:30'), 'fechamento',
            pg_temp.em(date '2026-11-06', '18:00'));
    t4 := (select string_agg(x ->> 'perda', ',' order by (x ->> 'perda')::int desc) from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-06')) x
            where x ->> 'modo' = 'ligado' and x ->> 'tipo' = 'pergunta' and (x ->> 'perda')::int >= 75);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- FASE 7c: (correção 2 da revisão, 20261102100590, achado 1) a subida a 77 só vale com a pergunta do gestor de 76 para ceder (o caso de
  -- 3 linhas da correção, provado no C1 de agenda_fase77c_correcao2.sql); aqui não há a de 76, e a (n) a 77 só passaria à frente de outra
  -- de 75 (a mensagem ao cliente, que a guarda não protegia): ela volta a 75. Antes, 77 depois de 2 dias úteis.
  v_res := pg_temp.ok(v_res, 'K2a a (n) com quem faz o quê nunca vista: 75 no dia em que nasce, no seguinte (1 dia útil) e depois de 2 dias úteis sem a pergunta do gestor de 76 para ceder (correção 2, achado 1)',
    t1 = '75' and t2 = '75' and t3 = '75', concat_ws(' ', t1, t2, t3));
  -- FASE 7c: fim
  v_res := pg_temp.ok(v_res, 'K2b com a pergunta do gestor que vence hoje (76), a (n) não sobe (fica 75: não tira quem perde hoje)', t4 = '76,75', t4);
  perform pg_temp.gravar(v_res);
end
$k2$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
