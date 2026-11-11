-- Prova das leituras e da saúde da Agenda de Produção, Fase 7b (pacote P5): o bloco "Equipe" do cartão da OS (quantas pessoas, a dupla
-- que a tarefa pede ou que o dono disse, a 2ª pessoa que falta no plano, a dupla dita que espera, a nota do espaço apertado), a dupla
-- no plano (_agenda_dupla_no_plano) e a saúde dos dias da equipe e da dupla (_agenda_saude_equipe7b, a chave equipe_dias de
-- agenda_saude) (migration 20261101100400).
-- bancada: depende de 20261101100400
--
--   L0  as portas: as 2 novas (invoker, STABLE, search_path fixo, authenticated e service_role, nunca anon: 42501), as 2 recriadas com
--       as de antes (os_plano_da_os definer, agenda_saude invoker) e o desfeito da 7a com a porta de leitura (o foco gestor o lê)
--   L1  o cartão, o texto byte a byte (§6.4 e R4.4): a regra sem plano; a regra com a 2ª pessoa faltando no plano (o Lenine com só o
--       Alex; o tempo todo da Kalmar-33; o início e o fim do Giancarlo); a dupla completa (o Mateus nos 2 primeiros); a dita (início,
--       "vai com um só") e a dita que espera (a classe 4 dupla, o tempo todo e no início; o "fora" dupla da montagem com o Mateus só qua
--       e qui); em teste (com e sem a regra uma_pessoa); a nota do espaço apertado; nada; a equipe dita; desligado e a OS concluída
--       (nulo, e o resto do cartão é o de antes, byte a byte, em todas as OS)
--   L2  agenda_saude().equipe_dias: desligado (a saúde de antes byte a byte, mais a chave nova, com os zeros 0); cada um dos 11 zeros
--       forçado = 1 (os outros 0) e o ok falso; os números (a dupla esperando o ajudante, as duplas, a semana passada, as perguntadas)
--   L3  o determinismo: o cartão e a saúde, 2 vezes, o mesmo md5
--   L4  o técnico não lê o cartão (42501); o anon não executa as novas (42501); o admin logado lê a saúde e o cartão (sem 42501)
--   L5  as cópias: tirados os blocos "-- FASE 7b:" (e o "-- FASE 7b (P5…)" de dentro do bloco do gestor), o corpo de cada recriada é o
--       da origem, com o número de blocos
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7b_leituras.sql
--   Seguro em produção: termina em ROLLBACK. L0 e L5 rodam em qualquer banco (L5 sai PULADO sem as migrations como texto); o resto usa
--   as fixtures e só roda na bancada (fora dela sai PULADO).
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
-- O texto sem os blocos "-- FASE 7b: … -- FASE 7b: fim" e "-- FASE 7b (P5…) … -- FASE 7b (P5): fim" (as linhas de abrir e de
-- fechar saem junto).
create function pg_temp.sem_7b(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7b( \(P5\))?: fim' then -1
                                                when l ~ '^\s*-- FASE 7b(:| \(P5)' then 1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7b( \(P5\))?: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- (7d P8) a função passou a viver na 7d: antes de comparar com a etapa dela, tiram-se os blocos "-- FASE 7d:" e as marcas "-- (7d … -- (7d: fim)"
create function pg_temp.sem_7d(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when (l ~ '^\s*-- FASE 7[def]:' and l !~ '^\s*-- FASE 7[def]: fim')
                                                     or (l ~ '^\s*-- \(7[def] ' and l !~ '^\s*-- \(7[def]: fim\)') then 1
                                                when l ~ '^\s*-- (FASE 7[def]: fim|\(7[def]: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7[def]: fim|\(7[def]: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- p_sql (que devolve um valor) como o papel p_papel: o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_papel text, p_sql text, p_sub uuid default null) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_sub::text, ''), true);
  perform set_config('request.jwt.claims', case when p_sub is null then json_build_object('role', p_papel)::text
                                                    else json_build_object('sub', p_sub, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $f$;

-- ── L0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────
with f(sig) as (values ('public._agenda_dupla_no_plano(uuid, date)'), ('public._agenda_saude_equipe7b(date, timestamptz)'))
insert into _resultado
select 'L0a as 2 novas: invoker, STABLE, search_path fixo, authenticated e service_role, nunca anon',
       count(p.oid) = 2
       and bool_and(not p.prosecdef and p.provolatile = 's' and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                    and not has_function_privilege('anon', p.oid, 'execute')),
       string_agg(format('%s %s definer=%s anon=%s', f.sig, p.provolatile, p.prosecdef, has_function_privilege('anon', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'L0b as 2 recriadas com as portas de antes: os_plano_da_os definer, agenda_saude invoker; authenticated e service_role; nunca anon',
       (select p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public%' from pg_proc p
         where p.oid = 'public.os_plano_da_os(uuid, date)'::regprocedure)
       and (select not p.prosecdef and p.provolatile = 's' from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure)
       and has_function_privilege('authenticated', 'public.os_plano_da_os(uuid, date)', 'execute')
       and has_function_privilege('service_role', 'public.os_plano_da_os(uuid, date)', 'execute')
       and not has_function_privilege('anon', 'public.os_plano_da_os(uuid, date)', 'execute')
       and has_function_privilege('authenticated', 'public.agenda_saude(date, timestamptz)', 'execute')
       and has_function_privilege('service_role', 'public.agenda_saude(date, timestamptz)', 'execute')
       and not has_function_privilege('anon', 'public.agenda_saude(date, timestamptz)', 'execute'),
       null;
insert into _resultado
select 'L0c o desfeito da 7a (que o foco *agenda gestor* lê) com as portas de leitura: authenticated e service_role, nunca anon',
       has_function_privilege('authenticated', 'public._agenda_gestor_desfeito(uuid, timestamptz)', 'execute')
       and has_function_privilege('service_role', 'public._agenda_gestor_desfeito(uuid, timestamptz)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_gestor_desfeito(uuid, timestamptz)', 'execute'),
       null;

-- ── As fixtures (uma vez; cada caso abaixo roda numa subtransação desfeita) ────────────────────────────────────────
-- A base é a fixture da 7b com Mateus (sob demanda, sem linha), Rafael (diarista com padrão) e Bruno (o novato com ter 10/11), mais a
-- presença do dono do Lenine e do Vanderlei como em produção (abre e fecha).
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7b', true), '') = '' or coalesce(current_setting('agenda_teste.fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    return;
  end if;
  execute current_setting('agenda_teste.fase7b');
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
end
$carga$;

create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.payees py where py.name = 'Mateus' and py.kind = 'prestador' and py.active)
     and exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97101')
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
-- o gestor da 7a (os 5 modos dele) e os modos da 7b de uma vez
create function pg_temp.gestor(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end
   where id
$f$;
create function pg_temp.modos7b(p_modo text) returns void language sql as $f$
  update public.agenda_config set modo_dias = p_modo, modo_dupla = p_modo, modo_sabado = p_modo, modo_cadastro = p_modo,
                                  modo_chamar = p_modo where id
$f$;
-- só o Alex (e o Mateus, sem linha: fora da grade até o dono dizer as datas dele)
create function pg_temp.so_alex() returns void language sql as $f$
  update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-05 10:00-03'
   where substituida_em is null and payee_id in (select id from public.payees where name in ('Rafael', 'Bruno'))
$f$;
-- as datas ditas pelo dono para quem vem sob demanda (o que o *grava* de "Mateus vem qua e qui" escreve)
create function pg_temp.vem(p_nome text, p_dias date[]) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(d, d, '[]'), null, 'disponivel', 'dono', 'Você disse que vem (sob demanda)', timestamptz '2026-11-05 10:00-03'
    from public.payees p, unnest(p_dias) d where p.name = p_nome and p.active
$f$;
create function pg_temp.marcar(p_os uuid[]) returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  v_p := public.agenda_propor('os', null, null, p_os, '{}'::jsonb, true, 'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
  perform public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
  return v_p;
end $f$;
-- meios-dias do plano inseridos direto (o que o motor teria gravado): a pessoa em cada dia × turno
create function pg_temp.plano(p_os uuid, p_pessoa uuid, p_dias date[], p_turnos text[] default array['manha', 'tarde']) returns void
language sql as $f$
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, criado_em)
  select p_os, p_pessoa, d, t, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-05 16:45-03', timestamptz '2026-11-05 16:45-03'
    from unnest(p_dias) d, unnest(p_turnos) t
$f$;
create function pg_temp.cartao(p_os uuid) returns jsonb language sql stable as $f$
  select public.os_plano_da_os(p_os, date '2026-11-05')
$f$;
create function pg_temp.eq(p_os uuid) returns jsonb language sql stable as $f$
  select public.os_plano_da_os(p_os, date '2026-11-05') -> 'equipe'
$f$;

-- ── L1. O cartão ───────────────────────────────────────────────────────────────────────────────────────────────
do $l1$
declare
  v_res  jsonb := '[]'::jsonb;
  v_len  uuid;
  v_alex uuid;
  a      jsonb;
  b      jsonb;
  c      jsonb;
  d      jsonb;
  v_n    int;
  v_dif  text;
begin
  if not pg_temp.carregada() or coalesce(current_setting('agenda_teste.mig_correcao_textos_fase6', true), '') = '' then
    insert into _resultado values ('L1 (o cartão)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  v_alex := pg_temp.pessoa('Alex');
  -- L1a/L1b a regra (ligado, só o Alex): sem plano o texto da dupla; marcado com o bloco de 1 pessoa, a 2ª pessoa que falta
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    a := pg_temp.eq(v_len);
    perform pg_temp.marcar(array[v_len]);
    b := pg_temp.eq(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1a a regra sem plano (ligado): "1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha.", 1 pessoa, a dupla da OS, nada faltando, sem espera',
    a ->> 'texto' = '1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha.'
    and (a ->> 'pessoas')::int = 1 and a #>> '{dupla,fonte}' = 'regra' and (a #>> '{dupla,inicio}')::int = 2
    and a -> 'falta' = '[]'::jsonb and not (a ->> 'espera')::boolean and a ->> 'modo' = 'ligado' and a -> 'notas' = '[]'::jsonb,
    a::text);
  v_res := pg_temp.ok(v_res, 'L1b marcado com só o Alex (o bloco de 1 pessoa): "1 pessoa; nos 2 primeiros meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe)." e a falta nos 2 meios-dias',
    b ->> 'texto' = '1 pessoa; nos 2 primeiros meios-dias (ter 10/11) a troca do banco de baterias pede 2 — falta a 2ª pessoa (só Alex está na equipe).'
    and b -> 'falta' = '[{"dia": "2026-11-10", "onde": "inicio", "turno": "manha"}, {"dia": "2026-11-10", "onde": "inicio", "turno": "tarde"}]'::jsonb,
    b::text);
  -- L1c a dupla completa: o Mateus dito qua 11 e qui 12 vai com o Alex nos 2 primeiros (qua 11/11)
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']);
    perform pg_temp.marcar(array[v_len]);
    a := pg_temp.eq(v_len);
    b := public._agenda_dupla_no_plano(v_len, date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1c a dupla completa (o Mateus com o Alex nos 2 primeiros): o texto da dupla, nada faltando; _agenda_dupla_no_plano dá 10 meios-dias, ni 2, faltam []',
    a ->> 'texto' = '1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha.' and a -> 'falta' = '[]'::jsonb
    and (b ->> 'meios')::int = 10 and (b ->> 'ni')::int = 2 and b -> 'faltam' = '[]'::jsonb and b ->> 'fonte' = 'regra',
    concat_ws(' | ', a::text, b::text));
  -- L1d o tempo todo da Kalmar-33 e o início e o fim do Giancarlo, com o Alex sozinho no plano (inserido), na equipe real (só o Alex)
  -- e na de teste (o Rafael e o Bruno na grade: "ninguém mais está livre nesses meios-dias")
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.plano(pg_temp.os('OS-00033'), v_alex, array[date '2026-11-10', date '2026-11-11']);
    perform pg_temp.plano(pg_temp.os('OS-00130'), v_alex, array[date '2026-11-16', date '2026-11-17', date '2026-11-18']);
    a := pg_temp.eq(pg_temp.os('OS-00033'));
    b := pg_temp.eq(pg_temp.os('OS-00130'));
    perform pg_temp.so_alex();
    c := pg_temp.eq(pg_temp.os('OS-00033'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1d o tempo todo pelo orçamento (Kalmar-33, o Alex em 4 meios-dias): 2 pessoas e "1 pessoa; o serviço todo pede 2 (o orçamento previu 2 técnicos) — falta a 2ª pessoa em 4 meios-dias (…)" — só o Alex na grade: "(só Alex está na equipe)"; com mais gente: "(ninguém mais está livre nesses meios-dias)"',
    c ->> 'texto' = '1 pessoa; o serviço todo pede 2 (o orçamento previu 2 técnicos) — falta a 2ª pessoa em 4 meios-dias (só Alex está na equipe).'
    and a ->> 'texto' = '1 pessoa; o serviço todo pede 2 (o orçamento previu 2 técnicos) — falta a 2ª pessoa em 4 meios-dias (ninguém mais está livre nesses meios-dias).'
    and (a ->> 'pessoas')::int = 2 and jsonb_array_length(a -> 'falta') = 4
    and (select bool_and(e ->> 'onde' = 'todos') from jsonb_array_elements(a -> 'falta') e),
    concat_ws(' | ', a ->> 'texto', c ->> 'texto'));
  v_res := pg_temp.ok(v_res, 'L1e o início e o fim (Giancarlo, o Alex em 6 meios-dias): "1 pessoa; nos 2 primeiros meios-dias (seg 16/11) a troca do banco de baterias e nos 2 últimos meios-dias (qua 18/11) a ligação em 127/220 V pedem 2 — falta a 2ª pessoa (…)."',
    b ->> 'texto' = '1 pessoa; nos 2 primeiros meios-dias (seg 16/11) a troca do banco de baterias e nos 2 últimos meios-dias (qua 18/11) a ligação em 127/220 V pedem 2 — falta a 2ª pessoa (ninguém mais está livre nesses meios-dias).'
    and (select string_agg(e ->> 'onde', ',' order by e ->> 'dia', e ->> 'turno') from jsonb_array_elements(b -> 'falta') e) = 'inicio,inicio,fim,fim',
    b::text);
  -- L1f a dita pelo dono: no início (com o Mateus no horizonte, sem espera), "vai com um só", e a que espera a 2ª pessoa (só o Alex)
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']);
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2, dupla_em = pg_temp.em(date '2026-11-05', '10:00')
     where service_order_id = v_len;
    a := pg_temp.eq(v_len);
    update public.os_planejamento set dupla_dita = 'nao', dupla_meios = null where service_order_id = v_len;
    b := pg_temp.eq(v_len);
    perform pg_temp.so_alex();
    update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-05 11:00-03'
     where substituida_em is null and payee_id = pg_temp.pessoa('Mateus');
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2 where service_order_id = v_len;
    c := pg_temp.eq(v_len);
    d := pg_temp.eq(pg_temp.os('OS-97002'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1f a dita: "Em dupla nos 2 primeiros meios-dias (você disse)." (com a 2ª pessoa no horizonte, sem espera) e "1 pessoa (você disse)."',
    a ->> 'texto' = 'Em dupla nos 2 primeiros meios-dias (você disse).' and not (a ->> 'espera')::boolean and a #>> '{dupla,fonte}' = 'dono'
    and b ->> 'texto' = '1 pessoa (você disse).' and (b ->> 'pessoas')::int = 1,
    concat_ws(' | ', a::text, b::text));
  v_res := pg_temp.ok(v_res, 'L1g a dita que espera a 2ª pessoa (a classe 4 dupla, só o Alex): "Em dupla nos 2 primeiros meios-dias (você disse) — espero a 2ª pessoa: só Alex está na equipe." e "Em dupla o tempo todo (você disse) — espero a 2ª pessoa: só Alex está na equipe." (OS-97002)',
    c ->> 'texto' = 'Em dupla nos 2 primeiros meios-dias (você disse) — espero a 2ª pessoa: só Alex está na equipe.' and (c ->> 'espera')::boolean
    and d ->> 'texto' = 'Em dupla o tempo todo (você disse) — espero a 2ª pessoa: só Alex está na equipe.' and (d ->> 'espera')::boolean
    and (d ->> 'pessoas')::int = 2,
    concat_ws(' | ', c ->> 'texto', d ->> 'texto'));
  -- L1h a dita o tempo todo do Lenine com o Mateus só qua e qui (4 meios-dias de 6): a montagem a deixa no "fora" dupla e o cartão espera
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']);
    update public.os_planejamento set dupla_dita = 'todos', dupla_meios = null, dupla_em = pg_temp.em(date '2026-11-05', '10:00')
     where service_order_id = v_len;
    a := pg_temp.marcar(array[v_len]);
    b := pg_temp.eq(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1h a dita o tempo todo com o Mateus só qua e qui: o "fora" dupla da montagem vira a espera do cartão, com as datas dele',
    exists (select 1 from jsonb_array_elements(a -> 'fora') f where f ->> 'motivo' = 'dupla')
    and b ->> 'texto' = 'Em dupla o tempo todo (você disse) — espero a 2ª pessoa: precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante.'
    and (b ->> 'espera')::boolean,
    concat_ws(' | ', (a -> 'fora')::text, b ->> 'texto'));
  -- L1i em teste: com a regra uma_pessoa (o gestor ligado) e sem ela (o gestor desligado: 2 pessoas por serviço)
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('sombra');
    a := pg_temp.eq(v_len);
    perform pg_temp.gestor('desligado');
    b := pg_temp.eq(v_len);
    c := pg_temp.eq(pg_temp.os('OS-00104'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1i em teste: "Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre." (a regra uma_pessoa); sem ela, "… Hoje marco 2 pessoas." e "Em teste: eu marcaria 1 pessoa. Hoje marco 2 pessoas."',
    a ->> 'texto' = 'Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias (troca do banco de baterias). Hoje marco 1 pessoa e ponho a 2ª nesses meios-dias quando alguém está livre.'
    and a ->> 'modo' = 'sombra'
    and b ->> 'texto' = 'Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias (troca do banco de baterias). Hoje marco 2 pessoas.'
    and (b ->> 'pessoas')::int = 2
    and c ->> 'texto' = 'Em teste: eu marcaria 1 pessoa. Hoje marco 2 pessoas.',
    concat_ws(' | ', a ->> 'texto', b ->> 'texto', c ->> 'texto'));
  -- L1j a nota do espaço apertado (OS-97101), nada (OS-00104) e a equipe dita (o Lenine com o Alex o dia todo)
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    a := pg_temp.eq(pg_temp.os('OS-97101'));
    b := pg_temp.eq(pg_temp.os('OS-00104'));
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_len, v_alex, 'dia');
    c := pg_temp.eq(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1j a nota: notas ["Atenção: casa de máquinas — confira se precisa de duas pessoas."] e "1 pessoa."; nada: "1 pessoa."; a equipe dita: "Quem vai: Alex (você disse)."',
    a -> 'notas' = '["Atenção: casa de máquinas — confira se precisa de duas pessoas."]'::jsonb and a ->> 'texto' = '1 pessoa.'
    and b ->> 'texto' = '1 pessoa.' and b #>> '{dupla,fonte}' = 'nenhuma' and b -> 'notas' = '[]'::jsonb
    and c ->> 'texto' = 'Quem vai: Alex (você disse).' and (c ->> 'pessoas')::int = 1,
    concat_ws(' | ', a::text, b ->> 'texto', c ->> 'texto'));
  -- L1k desligado: a chave é nula e o resto do cartão de todas as OS é o de antes, byte a byte (a definição de 20261029100950 rodada
  -- como pg_temp); a OS concluída também é nula com o modo ligado
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_correcao_textos_fase6'), 'os_plano_da_os'),
                  'create or replace function public.os_plano_da_os(', 'create function pg_temp.plano_de_antes(');
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('desligado');
    select count(*), string_agg(so.service_order_number, ', ' order by so.service_order_number) filter (where
             pg_temp.cartao(so.id) -> 'equipe' <> 'null'::jsonb
             or (pg_temp.cartao(so.id) - 'equipe' - 'local')::text is distinct from pg_temp.plano_de_antes(so.id, date '2026-11-05')::text)
      into v_n, v_dif
      from public.service_orders so where so.service_order_number like 'OS-%';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1k desligado: a chave equipe é nula e o resto do cartão de todas as OS é o de antes, byte a byte',
    v_dif is null and v_n > 10, format('%s OS; diferentes: %s', v_n, coalesce(v_dif, '—')));
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    update public.service_orders set status = 'completed' where id = v_len;
    a := pg_temp.cartao(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1l a OS concluída: a chave equipe é nula (nada a marcar)', a -> 'equipe' = 'null'::jsonb, (a -> 'equipe')::text);
  perform pg_temp.gravar(v_res);
end
$l1$;

-- ── L2. A saúde ────────────────────────────────────────────────────────────────────────────────────────────────
create function pg_temp.saude() returns jsonb language sql stable as $f$
  select public.agenda_saude(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10'))
$f$;
-- uma mensagem à equipe inserida direto (o que o registro teria gravado)
create function pg_temp.msg(p_pessoa uuid, p_dia date, p_tipo text, p_enviar timestamptz, p_estado text default 'enfileirada',
                            p_recusa text default null, p_leitura jsonb default null) returns void language sql as $f$
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, recusa_motivo, dedupe_key, leitura,
                                              resposta_texto, resposta_em)
  values (p_pessoa, p_dia, p_tipo, 'ligado', 'Mensagem de teste', p_enviar, p_estado, p_recusa,
          format('teste:L2:%s:%s:%s:%s', p_pessoa, p_dia, p_tipo, p_enviar), p_leitura,
          case when p_estado = 'respondida' then 'seg ter' end, case when p_estado = 'respondida' then p_enviar + interval '5 minutes' end)
$f$;

do $l2$
declare
  v_res  jsonb := '[]'::jsonb;
  c_zeros constant text[] := array['dias_fora_da_janela', 'dias_duas_na_semana', 'dia_acima_do_teto', 'ficha_recusada_por_teto_com_dias',
                                   'dupla_com_uma_pessoa', 'dupla_incompleta_com_gente_livre', 'novato_sozinho', 'sabado_sem_prazo',
                                   'sabado_tarde', 'dono_em_vaga_sem_ok', 'resposta_sem_gravar'];
  v_raf  uuid;
  v_alex uuid;
  v_bru  uuid;
  v_dono uuid;
  v_len  uuid;
  v_z    text;
  s      jsonb;
  s0     jsonb;
  a      jsonb;
  b      jsonb;
  v_ok   boolean;
begin
  if not pg_temp.carregada() or coalesce(current_setting('agenda_teste.mig_rodada_fase7a', true), '') = '' then
    insert into _resultado values ('L2 (a saúde)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_raf := pg_temp.pessoa('Rafael');
  v_alex := pg_temp.pessoa('Alex');
  v_bru := pg_temp.pessoa('Bruno');
  v_dono := public._agenda_dono(null);
  v_len := pg_temp.os('OS-00074');
  -- L2a desligado: a saúde de antes (a definição de 20261031100600 rodada como pg_temp), byte a byte, mais a chave equipe_dias com os
  -- zeros 0 e o ok de antes
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_rodada_fase7a'), 'agenda_saude'),
                  'create or replace function public.agenda_saude(', 'create function pg_temp.saude_de_antes(');
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('desligado');
    s := pg_temp.saude();
    s0 := pg_temp.saude_de_antes(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2a desligado: a saúde de antes, byte a byte (fora a chave equipe_dias); equipe_dias com os 11 zeros em 0, zeros_ok, os modos desligados e o ok de antes',
    -- (Fase 7f, P7) a chave comunicacao (_agenda_saude_comunicacao) também fica de fora: os zeros dela entram no ok, e o ok continua o de antes
    -- (Fase 7e, P7) e a chave margem (_agenda_saude_margem), pela mesma razão
    (s - 'equipe_dias' - 'local' - 'comunicacao' - 'margem')::text = s0::text
    and (select bool_and((s -> 'equipe_dias' ->> z)::int = 0) from unnest(c_zeros) z)
    and (s #>> '{equipe_dias,zeros_ok}')::boolean and s #>> '{equipe_dias,modos,dupla}' = 'desligado' and s ->> 'ok' = s0 ->> 'ok',
    left((s -> 'equipe_dias')::text, 600));
  -- L2b cada zero forçado = 1, os outros 0, zeros_ok falso e o ok de agenda_saude falso
  foreach v_z in array c_zeros loop
    begin
      perform pg_temp.gestor('ligado');
      perform pg_temp.modos7b('desligado');
      case v_z
        when 'dias_fora_da_janela' then
          perform pg_temp.msg(v_raf, date '2026-11-16', 'dias', pg_temp.em(date '2026-11-08', '10:00'));     -- domingo
        when 'dias_duas_na_semana' then
          perform pg_temp.msg(v_raf, date '2026-11-16', 'dias', pg_temp.em(date '2026-11-05', '16:45'));
          perform pg_temp.msg(v_raf, date '2026-11-18', 'dias', pg_temp.em(date '2026-11-06', '16:45'));
        when 'dia_acima_do_teto' then
          perform pg_temp.msg(v_raf, date '2026-11-16', 'dias', pg_temp.em(date '2026-11-05', '16:45'));
          perform pg_temp.msg(v_raf, date '2026-11-05', 'como_foi', pg_temp.em(date '2026-11-05', '17:00'));
          perform pg_temp.msg(v_raf, date '2026-11-06', 'ficha', pg_temp.em(date '2026-11-05', '19:30'));
        when 'ficha_recusada_por_teto_com_dias' then
          perform pg_temp.msg(v_raf, date '2026-11-16', 'dias', pg_temp.em(date '2026-11-05', '16:45'));
          perform pg_temp.msg(v_raf, date '2026-11-06', 'ficha', pg_temp.em(date '2026-11-05', '19:30'), 'recusada', 'teto');
        when 'dupla_com_uma_pessoa' then
          perform pg_temp.modos7b('ligado');
          update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 1, dupla_em = pg_temp.em(date '2026-11-05', '10:00')
           where service_order_id = v_len;
          perform pg_temp.plano(v_len, v_alex, array[date '2026-11-10']);
        when 'dupla_incompleta_com_gente_livre' then
          perform pg_temp.modos7b('ligado');
          perform pg_temp.plano(v_len, v_alex, array[date '2026-11-10'], array['manha']);
          insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina,
                                                   modo_equipe, modo_diaria)
          select pg_temp.em(date '2026-11-05', '17:07'), date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'), c.modo_proposta, c.modo_vigia,
                 '{"dupla": {"completou": 0}, "modos": {"marcar": "ligado"}}'::jsonb, 0, 10, 'gestor', c.modo_equipe, c.modo_diaria
            from public.agenda_config c;
        when 'novato_sozinho' then
          perform pg_temp.modos7b('sombra');
          update public.agenda_config set modo_dupla = 'sombra', modo_sabado = 'desligado', modo_dias = 'desligado' where id;
          perform pg_temp.plano(pg_temp.os('OS-97101'), v_bru, array[date '2026-11-06'], array['manha']);
        when 'sabado_sem_prazo' then
          update public.agenda_config set modo_sabado = 'ligado', sabado_manha = 'so_prazo' where id;
          perform pg_temp.plano(pg_temp.os('OS-97101'), v_alex, array[date '2026-11-14'], array['manha']);
        when 'sabado_tarde' then
          perform pg_temp.plano(pg_temp.os('OS-97101'), v_alex, array[date '2026-11-14'], array['tarde']);
        when 'dono_em_vaga_sem_ok' then
          perform pg_temp.plano(v_len, v_dono, array[date '2026-11-10'], array['manha']);
        when 'resposta_sem_gravar' then
          perform pg_temp.msg(v_raf, date '2026-11-16', 'dias', pg_temp.em(date '2026-11-05', '16:45'), 'respondida', null,
                              '{"tipo": "dias", "dias": [1, 2], "mudou": true}'::jsonb);
      end case;
      s := pg_temp.saude();
      v_ok := (s -> 'equipe_dias' ->> v_z)::int = 1
              and (select bool_and((s -> 'equipe_dias' ->> z)::int = 0) from unnest(c_zeros) z where z <> v_z)
              and not (s #>> '{equipe_dias,zeros_ok}')::boolean and not (s ->> 'ok')::boolean;
      v_res := pg_temp.ok(v_res, format('L2b %s forçado = 1 (os outros 0; zeros_ok e o ok de agenda_saude falsos)', v_z), v_ok,
        left((s -> 'equipe_dias')::text, 700));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- L2c os números: o Lenine marcado com só o Alex (a dupla esperando o ajudante); a pergunta dos dias da semana de 16/11 ao Rafael,
  -- respondida, depois do prazo (qui 12/11 16:00); a semana passada (26 a 31/10) por pessoa
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.marcar(array[v_len]);
    a := pg_temp.saude() #> '{equipe_dias,numeros}';
    perform pg_temp.msg(v_raf, date '2026-11-16', 'dias', pg_temp.em(date '2026-11-05', '16:45'), 'respondida', null,
                        '{"tipo": "igual"}'::jsonb);
    b := public._agenda_saude_equipe7b(date '2026-11-12', pg_temp.em(date '2026-11-12', '16:30')) -> 'numeros';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2c os números: a dupla esperando o ajudante = 1 (o Lenine), as duplas da carteira (inferidas e ditas), a semana passada com o Alex; depois do prazo da quinta, a semana de 16/11 fechada com 1 perguntada, 1 respondida, 100%',
    (a ->> 'dupla_esperando_ajudante')::int = 1 and (a #>> '{duplas,inferidas}')::int >= 5 and (a #>> '{duplas,ditas}')::int >= 1
    and a #>> '{semana_passada,seg}' = '2026-10-26'
    and exists (select 1 from jsonb_array_elements(a #> '{semana_passada,pessoas}') p where p ->> 'pessoa' = 'Alex')
    and b ->> 'semana_fechada' = '2026-11-16' and (b ->> 'perguntadas')::int = 1 and (b ->> 'respondidas')::int = 1
    and (b ->> 'resposta_pct')::int = 100,
    concat_ws(' | ', a::text, b::text));
  perform pg_temp.gravar(v_res);
end
$l2$;

-- ── L3. O determinismo ─────────────────────────────────────────────────────────────────────────────────────────
do $l3$
declare
  v_res jsonb := '[]'::jsonb;
  a text;
  b text;
  c text;
  d text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('L3 (o determinismo)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.marcar(array[pg_temp.os('OS-00074')]);
    a := md5(pg_temp.cartao(pg_temp.os('OS-00074'))::text);
    b := md5(pg_temp.cartao(pg_temp.os('OS-00074'))::text);
    c := md5(public._agenda_saude_equipe7b(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10'))::text);
    d := md5(public._agenda_saude_equipe7b(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10'))::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3 o cartão e a saúde dos dias, duas vezes: o mesmo md5', a = b and c = d, concat_ws(' ', a, b, c, d));
  perform pg_temp.gravar(v_res);
end
$l3$;

-- ── L4. Quem lê ────────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'L4a o anon não executa as novas (42501): _agenda_dupla_no_plano e _agenda_saude_equipe7b',
       x like 'erro 42501%' and y like 'erro 42501%', concat_ws(' | ', x, y)
  from (select pg_temp.como('anon', 'select public._agenda_dupla_no_plano(gen_random_uuid(), date ''2026-11-05'')::text') as x,
               pg_temp.como('anon', 'select public._agenda_saude_equipe7b(date ''2026-11-05'', now())::text') as y) t;
do $l4$
declare
  v_tec uuid;
  v     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('L4b o técnico não lê o cartão', true, 'PULADO: sem técnico ou sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_tec := 'f7b00000-0000-4000-8000-0000000005f1';
  insert into public.app_users (id, full_name, email, role, active) values (v_tec, 'Téc Bancada 7b', 'tec7b@bancada.invalid', 'technician', true);
  v := pg_temp.como('authenticated', format('select public.os_plano_da_os(%L::uuid, date ''2026-11-05'')::text', pg_temp.os('OS-00074')), v_tec);
  insert into _resultado values ('L4b o técnico logado não lê o cartão (42501), também com o bloco Equipe', v like 'erro 42501%', v);
end
$l4$;
-- (a lição do P3: uma leitura invoker do painel que chama função nova sem grant dá 42501 ao admin logado) o admin logado lê a saúde
-- com a chave equipe_dias e o cartão com o bloco Equipe, com os modos da 7b ligados
do $l4c$
declare
  v_adm uuid;
  v     text;
  w     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('L4c o admin logado lê a saúde e o cartão', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  select u.id into v_adm from public.app_users u where u.role = 'admin' and u.active order by u.id limit 1;
  perform pg_temp.gestor('ligado');
  perform pg_temp.modos7b('ligado');
  v := pg_temp.como('authenticated', 'select (public.agenda_saude(date ''2026-11-05'', now()) -> ''equipe_dias'' ->> ''zeros_ok'')', v_adm);
  w := pg_temp.como('authenticated', format('select public.os_plano_da_os(%L::uuid, date ''2026-11-05'') #>> ''{equipe,texto}''',
                                            pg_temp.os('OS-00074')), v_adm);
  insert into _resultado values ('L4c o admin logado (authenticated) lê agenda_saude com a chave equipe_dias e o cartão com o bloco Equipe (nenhum 42501 das funções novas)',
    v in ('true', 'false') and w like '1 pessoa;%', concat_ws(' | ', v, w));
  perform pg_temp.modos7b('desligado');
  perform pg_temp.gestor('desligado');
end
$l4c$;

-- ── L5. As cópias ──────────────────────────────────────────────────────────────────────────────────────────────
do $l5$
declare
  v_res jsonb := '[]'::jsonb;
  r     record;
  v_src text;
begin
  for r in select * from (values
      ('os_plano_da_os', 'public.os_plano_da_os(uuid, date)', 'agenda_teste.mig_correcao_textos_fase6', 3),
      ('agenda_saude', 'public.agenda_saude(date, timestamptz)', 'agenda_teste.mig_rodada_fase7a', 1)) t(nome, sig, mig, blocos) loop
    v_src := coalesce(current_setting(r.mig, true), '');
    if v_src = '' then
      v_res := pg_temp.ok(v_res, format('L5 a cópia de %s', r.nome), true, 'PULADO: sem ' || r.mig || ' (rode pela bancada)');
      continue;
    end if;
    v_res := pg_temp.ok(v_res, format('L5 a cópia de %s só acrescenta %s bloco(s) da 7b (o resto é o corpo da origem, byte a byte)', r.nome, r.blocos),
      (select pg_temp.sem_7b(pg_temp.sem_7d(p.prosrc)) = pg_temp.corpo(v_src, r.nome)
              and (select count(*) from regexp_matches(p.prosrc, '-- FASE 7b( \(P5\))?: fim', 'g')) = r.blocos
         from pg_proc p where p.oid = r.sig::regprocedure),
      (select format('%s × %s linhas; %s blocos', cardinality(string_to_array(pg_temp.sem_7b(pg_temp.sem_7d(p.prosrc)), E'\n')),
                     cardinality(string_to_array(pg_temp.corpo(v_src, r.nome), E'\n')),
                     (select count(*) from regexp_matches(p.prosrc, '-- FASE 7b( \(P5\))?: fim', 'g')))
         from pg_proc p where p.oid = r.sig::regprocedure));
  end loop;
  perform pg_temp.gravar(v_res);
end
$l5$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
