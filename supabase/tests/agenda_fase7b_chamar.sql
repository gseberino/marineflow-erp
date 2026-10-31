-- Prova do quem chamar e da dupla completa da Agenda de Produção, Fase 7b (pacote P6): a sugestão de quem chamar (a dupla sem a 2ª
-- pessoa, o prazo firme que só fecha com um ajudante junto do técnico e o trabalho que passa a caber com mais uma pessoa), o passo
-- que põe a 2ª pessoa na dupla quando o dono diz os dias do ajudante (e marca a dupla dita que esperava) e o texto do corte que a
-- dupla completa encurta (migration 20261101100500).
-- bancada: depende de 20261101100500
--
--   C0  as portas: as 5 novas (invoker, search_path fixo, a volatilidade; sem grant a ninguém: anon, authenticated e service_role
--       recebem 42501) e as 6 recriadas com as de antes
--   C1  _agenda_dupla_faltando: o Lenine marcado só com o Alex = os 2 primeiros meios-dias (ter 10/11), com o motivo; com o Mateus
--       posto, []; a dita pelo dono e modo_dupla desligado, []; o dia já avisado sai como travado
--   C2  a sugestão de dupla: a pela tarefa marcada com 1 pessoa (o texto do foco byte a byte); a dita "o tempo todo" esperando (o
--       bloco do Alex de 6 meios-dias, não 12); a dita "no início" (os 2 primeiros); a dita que o Mateus só cobre em parte (o fora
--       dupla do R4.3(c): os meios-dias que faltam, sem os dele)
--   C3  a capacidade: as OS sem lugar com o Alex sozinho, a conta com mais uma pessoa (extra.meios_total, semanas, os[].ate) e os 3
--       textos byte a byte; os meios-dias são os das OS sem lugar que passam a caber (a pessoa a mais usada em outra OS não conta);
--       a carteira que cabe: dupla [], sem_lugar [] e "Quem chamar: ninguém — …"
--   C3b o prazo: Vanderlei com o prazo depois do bloco de 1 pessoa e dentro do de 2 → prazo[0] (fim_com_ajudante, os meios) e o texto
--       byte a byte; com o fim de 1 pessoa dentro do prazo, nada; com o de 2 pessoas também depois do prazo, nada (fica na
--       capacidade); e "Vanderlei com dupla" + "Mateus vem qui 19 a qua 25/11" + *grava* → o tique seguinte marca o Vanderlei com o
--       Alex e o Mateus nesses meios-dias, dentro do prazo
--   C4  a pessoa a mais nunca é gravada (nenhuma linha com _agenda_pessoa_extra_id() em tabela nenhuma; a variável vazia depois) e
--       só _agenda_quem_chamar escreve agenda.pessoa_extra (nada da vigia nem do motor)
--   C5  o passo dupla: "Mateus vem ter 10/11" + *grava* → o tique seguinte põe o Mateus com o Alex nos 2 meios-dias (a ação reparar,
--       o texto byte a byte, o *desfaz* volta); o Mateus nunca sozinho; o dia já avisado não muda; em teste, nada muda; a dita "no
--       início" que cabe nas datas dele é marcada no mesmo tique e a dita "o tempo todo" que ele não cobre continua esperando (o fora
--       dupla); a revisão do dia seguinte corta só o que a dupla encurtou, com o texto da dupla, e o *desfaz* volta; sem o Mateus,
--       nenhum corte; em teste, a dupla completada não é cortada
--   C6  a pergunta dias_semana com o motivo chamar: o texto byte a byte; uma por semana; sem a sugestão na semana, nenhuma; na
--       quinta, o tique das 16:45 espera o diário de hoje, o das 17:00 pergunta com o chamar das 16:53; a forma curta acima de 600
--   C7  o foco *agenda gestor* (ligado, em teste, sem conta, a conta de outro dia, a dupla de 1 pessoa no lugar do "Pode precisar de
--       dupla", o admin logado lendo o bloco sem 42501) e o *livre* (ligado; em teste, sem a linha)
--   C8  com modo_chamar e modo_dupla desligados, a rodada do gestor (os passos), o foco, o *livre*, o motivo da pergunta e o corte
--       são os de antes, byte a byte; o gravador com as chaves de antes; as cópias (tirados os blocos "-- FASE 7b:", o corpo da origem)
--   C9  o custo: a rodada diária com o passo chamar abaixo de gestor_tempo_max (os ms no detalhe)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7b_chamar.sql
--   Seguro em produção: termina em ROLLBACK. C0 roda em qualquer banco; C8 (as cópias) sai PULADO sem as migrations como texto; o
--   resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
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
create function pg_temp.sem_7b(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7b:' and l !~ '-- FASE 7b: fim' then 1
                                                when l ~ '^\s*-- FASE 7b: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7b: fim' as fecha
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

-- ── C0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────
with f(sig, vol) as (values
  ('public._agenda_meios_frase(jsonb, boolean)', 's'), ('public._agenda_dupla_faltando(uuid, date)', 's'),
  ('public._agenda_quem_chamar(date, timestamptz)', 'v'), ('public._agenda_gestor_chamar(date, timestamptz)', 'v'),
  ('public._agenda_gestor_dupla(date, timestamptz)', 'v'))
insert into _resultado
select 'C0a as 5 novas: invoker, search_path fixo, a volatilidade; sem grant a ninguém (nem anon, nem authenticated, nem service_role)',
       count(p.oid) = 5
       and bool_and(not p.prosecdef and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and not has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(format('%s %s definer=%s anon=%s auth=%s srv=%s', f.sig, p.provolatile, p.prosecdef,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'C0b o anon e o admin logado chamando quem chamar recebem 42501',
       a like 'erro 42501%' and b like 'erro 42501%', concat_ws(' | ', a, b)
  from (select pg_temp.como('anon', 'select public._agenda_quem_chamar(current_date, now())::text') as a,
               pg_temp.como('authenticated', 'select public._agenda_dupla_faltando(gen_random_uuid(), current_date)::text') as b) x;
with f(sig, quem, definer) as (values
  ('public.agenda_gestor_rodar(date, timestamptz)', 'servico', true),
  ('public._agenda_gestor_dia_gravar(date, text, jsonb, timestamptz)', 'ninguem', true),
  ('public._agenda_ver_gestor(date)', 'leitura', false), ('public.agenda_livre_de_verdade(date, timestamptz)', 'leitura', true),
  ('public._agenda_dias_semana_motivos(date, date)', 'ninguem', false), ('public._agenda_gestor_corte(uuid, date, timestamptz)', 'ninguem', false))
insert into _resultado
select 'C0c as 6 recriadas com as portas de antes (a rodada: só service_role, definer; o gravador: ninguém, definer; o foco e o livre: authenticated e service_role; o motivo da pergunta e o corte: ninguém; nunca anon)',
       count(p.oid) = 6
       and bool_and(p.prosecdef = f.definer and not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          when 'servico' then not has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute') end),
       string_agg(f.sig, '; ') filter (where p.oid is null or p.prosecdef <> f.definer or has_function_privilege('anon', p.oid, 'execute'))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── As fixtures (uma vez; cada caso abaixo roda numa subtransação desfeita) ────────────────────────────────────────
-- A base é a fixture da 7b com Mateus (sob demanda, sem linha), Rafael (diarista com padrão) e Bruno (o novato com ter 10/11), mais a
-- presença do dono do Lenine e do Vanderlei como em produção (abre e fecha). Cada caso põe o gestor da 7a e os modos da 7b, e tira o
-- Rafael e o Bruno da grade (só o Alex, a equipe de produção), como o teste do P4.
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
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
-- o gestor da 7a (os 5 modos dele), os modos da 7b, só o Alex na grade e a dupla dita do Sérgio (OS-97002, da fixture da 7a) fora
-- (cada caso que a quer põe de volta)
create function pg_temp.base(p_gestor text, p_7b text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_gestor, modo_encaixe_aprovacao = p_gestor, modo_revisao_diaria = p_gestor, modo_compre_ate = p_gestor,
         modo_vaga_fechamento = p_gestor, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_gestor = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         modo_dias = p_7b, modo_dupla = p_7b, modo_sabado = p_7b, modo_cadastro = p_7b, modo_chamar = p_7b
   where id;
  update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-05 10:00-03'
   where substituida_em is null and payee_id in (select id from public.payees where name in ('Rafael', 'Bruno'));
  update public.os_planejamento set dupla_dita = null, dupla_meios = null where service_order_id = pg_temp.os('OS-97002');
$f$;
-- as datas ditas pelo dono para quem vem sob demanda (o que o *grava* de "Mateus vem …" escreve), com a hora da fala
create function pg_temp.vem(p_nome text, p_dias date[], p_em timestamptz default timestamptz '2026-11-05 17:01-03') returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(d, d, '[]'), null, 'disponivel', 'dono', 'Você disse que vem (sob demanda)', p_em
    from public.payees p, unnest(p_dias) d where p.name = p_nome and p.active
$f$;
-- a fala do dono pelo rascunho e o *grava* (o caminho de verdade)
create function pg_temp.disse(p_pessoa text, p_dias text, p_hoje date default date '2026-11-05') returns text language plpgsql as $f$
declare
  v jsonb;
begin
  v := public.agenda_rascunho_disponibilidade(pg_temp.adm(), 'whatsapp', p_pessoa, 'vem', p_dias, false, p_pessoa || ' vem ' || p_dias, p_hoje, null);
  v := public.agenda_rascunho_gravar(pg_temp.adm(), p_hoje);
  return v ->> 'texto';
end $f$;
create function pg_temp.marcar(p_os uuid[], p_dia date default date '2026-11-05') returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  v_p := public.agenda_propor('os', null, null, p_os, '{}'::jsonb, true, 'vigia', null, p_dia, pg_temp.em(p_dia, '16:45'));
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, p_dia, pg_temp.em(p_dia, '16:45'));
end $f$;
create function pg_temp.qc(p_dia date default date '2026-11-05', p_hora text default '16:53') returns jsonb language sql as $f$
  select public._agenda_quem_chamar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
-- os meios-dias de turno vigentes da OS: "dd/mm t Nome+Nome; …"
create function pg_temp.vivas(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(x.d || ' ' || x.t || ' ' || x.n, '; ' order by x.d, x.t), '-')
    from (select to_char(a.dia, 'DD/MM') as d, case when a.turno = 'manha' then 'm' else 't' end as t,
                 string_agg(public._agenda_nome_curto(py.name), '+' order by py.name) as n
            from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
           group by 1, 2) x
$f$;
-- uma linha do foco (o 1º que começa com p_ini)
create function pg_temp.linha(p_texto text, p_ini text) returns text language sql immutable as $f$
  select l from unnest(string_to_array(coalesce(p_texto, ''), E'\n')) with ordinality u(l, o) where l like p_ini || '%' order by o limit 1
$f$;

-- ── C1. Os meios-dias da dupla sem a 2ª pessoa ─────────────────────────────────────────────────────────────────
do $c1$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  a     jsonb;
  b     jsonb;
  c     jsonb;
  d     jsonb;
  e     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C1 (os meios-dias da dupla sem a 2ª pessoa)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    a := public._agenda_dupla_faltando(v_len, date '2026-11-05');
    -- o dia já avisado (a ficha de ter 10/11 do Alex, enfileirada em ligado): travado
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
    values (pg_temp.pessoa('Alex'), date '2026-11-10', 'ficha', 'ligado', 'Ficha de teste', pg_temp.em(date '2026-11-09', '19:30'), 'enfileirada',
            'teste:C1:ficha:alex:2026-11-10');
    e := public._agenda_dupla_faltando(v_len, date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    perform pg_temp.vem('Mateus', array[date '2026-11-10']);
    perform public._agenda_gestor_dupla(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    b := public._agenda_dupla_faltando(v_len, date '2026-11-05');
    update public.agenda_config set modo_dupla = 'desligado' where id;
    c := public._agenda_dupla_faltando(v_len, date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    -- marcado com 1 pessoa e, depois, a dupla dita "no início" (o plano fica com a falta da dita)
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2, dupla_em = pg_temp.em(date '2026-11-05', '17:00')
     where service_order_id = v_len;
    d := jsonb_build_object('faltando', public._agenda_dupla_faltando(v_len, date '2026-11-05'), 'plano', public._agenda_dupla_no_plano(v_len, date '2026-11-05') -> 'faltam');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C1a o Lenine marcado só com o Alex: os 2 primeiros meios-dias (ter 10/11, manhã e tarde) sem a 2ª pessoa, com o que a tarefa pede',
    jsonb_array_length(a) = 2 and a -> 0 ->> 'dia' = '2026-11-10' and a -> 0 ->> 'turno' = 'manha' and a -> 1 ->> 'turno' = 'tarde'
    and a -> 0 ->> 'motivo' = 'a troca do banco de baterias' and a -> 0 ->> 'onde' = 'inicio' and (a -> 0 ->> 'tem')::int = 1
    and not (a -> 0 ->> 'travado')::boolean and a -> 0 -> 'pessoas' = jsonb_build_array(pg_temp.pessoa('Alex')::text),
    a::text);
  v_res := pg_temp.ok(v_res, 'C1b a ficha de ter 10/11 já na fila do Alex: os 2 meios-dias saem como travados (a zona travada da 7a)',
    jsonb_array_length(e) = 2 and (e -> 0 ->> 'travado')::boolean and (e -> 1 ->> 'travado')::boolean, e::text);
  v_res := pg_temp.ok(v_res, 'C1c com o Mateus posto pelo passo dupla: nada falta; com modo_dupla desligado: [] (sem dk)',
    b = '[]'::jsonb and c = '[]'::jsonb, concat_ws(' | ', b::text, c::text));
  v_res := pg_temp.ok(v_res, 'C1d a dupla dita pelo dono (no início, dita depois de marcar com 1) não é desta função: [] (o plano mostra a falta: é a do cartão)',
    d -> 'faltando' = '[]'::jsonb and jsonb_array_length(d -> 'plano') > 0, d::text);
  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C2. A sugestão de dupla ────────────────────────────────────────────────────────────────────────────────────
do $c2$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  a     jsonb;
  b     jsonb;
  c     jsonb;
  d     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C2 (a sugestão de dupla)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  -- a pela tarefa, marcada com 1 pessoa
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    a := pg_temp.qc();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- a dita "o tempo todo" esperando (só o Alex): o bloco dele com os dias de 2 pessoas
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dupla_dita = 'todos', dupla_meios = null where service_order_id = v_len;
    b := pg_temp.qc();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- a dita "no início" (2 meios-dias)
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2 where service_order_id = v_len;
    c := pg_temp.qc();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- a dita "o tempo todo" com o Mateus só qua 11 e qui 12/11 (o fora dupla do R4.3(c)): os meios-dias que faltam, sem os dele
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dupla_dita = 'todos', dupla_meios = null where service_order_id = v_len;
    perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']);
    d := pg_temp.qc();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C2a a dupla pela tarefa marcada só com o Alex: a sugestão {marcada, fonte regra, meios ter 10/11 m e t} e a linha do foco byte a byte',
    a -> 'dupla' -> 0 ->> 'os' = v_len::text and (a -> 'dupla' -> 0 ->> 'marcada')::boolean and a -> 'dupla' -> 0 ->> 'fonte' = 'regra'
    and jsonb_array_length(a -> 'dupla' -> 0 -> 'meios') = 2
    and pg_temp.linha(a ->> 'texto', '• Ajudante') = '• Ajudante para a dupla: Lenine em ter 10/11 (manhã e tarde) — a troca do banco de baterias pede 2 pessoas e só Alex está na equipe. Se chamar, diga: Mateus vem ter 10/11.'
    and split_part(a ->> 'texto', E'\n', 1) = 'Quem chamar (só sugiro; quem chama é você):',
    a ->> 'texto');
  v_res := pg_temp.ok(v_res, 'C2b a dita "o tempo todo" esperando a 2ª pessoa: o bloco que o Alex faria sozinho com os dias de 2 pessoas (6 meios-dias, não os 12 de 1 pessoa) e a linha do foco',
    b -> 'dupla' -> 0 ->> 'fonte' = 'dono' and not (b -> 'dupla' -> 0 ->> 'marcada')::boolean and jsonb_array_length(b -> 'dupla' -> 0 -> 'meios') = 6
    and b -> 'dupla' -> 0 ->> 'cabe_de' = '2026-11-09'
    and pg_temp.linha(b ->> 'texto', '• Lenine') = '• Lenine (você disse: dupla o tempo todo) espera a 2ª pessoa: com um ajudante de seg 09 a qua 11/11 (6 meios-dias), ele cabe.',
    b ->> 'texto');
  v_res := pg_temp.ok(v_res, 'C2c a dita "no início" (2 meios-dias): os 2 primeiros meios-dias do bloco do Alex',
    jsonb_array_length(c -> 'dupla' -> 0 -> 'meios') = 2
    and pg_temp.linha(c ->> 'texto', '• Lenine') = '• Lenine (você disse: dupla nos 2 primeiros meios-dias) espera a 2ª pessoa: com um ajudante em ter 10/11 (manhã e tarde), ele cabe.',
    c ->> 'texto');
  v_res := pg_temp.ok(v_res, 'C2d a dita "o tempo todo" que o Mateus só cobre em parte (o fora dupla): os meios-dias do bloco menos os que ele já tem livres (qua 11/11)',
    jsonb_array_length(d -> 'dupla' -> 0 -> 'meios') = 4
    and not exists (select 1 from jsonb_array_elements(d -> 'dupla' -> 0 -> 'meios') m where m ->> 'dia' = '2026-11-11')
    and pg_temp.linha(d ->> 'texto', '• Lenine') = '• Lenine (você disse: dupla o tempo todo) espera a 2ª pessoa: com um ajudante em seg 09 e ter 10/11 (4 meios-dias), ele cabe.',
    d ->> 'texto');
  v_res := pg_temp.ok(v_res, 'C2e a pergunta da quinta leva a dupla (as partes com os dias): a marcada e a dita, cada uma numa frase',
    exists (select 1 from jsonb_array_elements(a -> 'partes') p
             where p ->> 'tipo' = 'dupla' and p ->> 'texto' = 'Lenine precisa de um ajudante junto de Alex em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas.'
               and p -> 'dias' = '["2026-11-10"]'::jsonb)
    and exists (select 1 from jsonb_array_elements(b -> 'partes') p
                 where p ->> 'texto' = 'Lenine (você disse: dupla o tempo todo) só cabe com um ajudante de seg 09 a qua 11/11 (6 meios-dias).'),
    concat_ws(' | ', (a -> 'partes')::text, (b -> 'partes')::text));
  perform pg_temp.gravar(v_res);
end
$c2$;

-- ── C3. A capacidade ───────────────────────────────────────────────────────────────────────────────────────────
do $c3$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  a     jsonb;
  z     jsonb;
  v_p2  jsonb;
  v_ext int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C3 (a capacidade)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  -- o Lenine marcado (a dupla pela tarefa com 1 pessoa), o Sérgio (OS-97002) sem a dupla dita, Nelson e Giancarlo com 8 dias ditos
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dias = 8, estimativa_fonte = 'dono', estimativa_em = timestamptz '2026-11-05 10:00-03'
     where service_order_id in (pg_temp.os('OS-00112'), pg_temp.os('OS-00130'));
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00112', 'OS-00130')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste'
     where estado = 'aberta' and service_order_id in (pg_temp.os('OS-00112'), pg_temp.os('OS-00130'));
    perform pg_temp.marcar(array[v_len]);
    a := pg_temp.qc();
    -- a 2ª conta, de fora (como _agenda_quem_chamar a faz), para ver onde a pessoa a mais foi parar
    perform set_config('agenda.pessoa_extra', 'tecnico', true);
    v_p2 := public.agenda_propor('os', null, null,
              array(select k.service_order_id from public.os_carteira(date '2026-11-05') k
                     where not public._agenda_os_tem_dia(k.service_order_id, date '2026-11-05') order by k.numero, k.service_order_id),
              jsonb_build_object('aceitar_atraso', jsonb_build_array(pg_temp.os('OS-00069'), pg_temp.os('OS-97004'))),
              false, 'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    perform set_config('agenda.pessoa_extra', '', true);
    v_ext := (select count(*) from jsonb_array_elements(v_p2 -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') al
               where al ->> 'payee_id' = public._agenda_pessoa_extra_id()::text and al ->> 'presenca' = 'turno')::int;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- a carteira que cabe: sem a presença do dono no Lenine e no Vanderlei (ficam pela pergunta dos dias dele) e sem o prometido firme da
  -- Úrsula
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dono_presenca = null where service_order_id in (v_len, pg_temp.os('OS-00069'));
    update public.os_planejamento set prometido_tipo = null, prometido_de = null, prometido_ate = null, prometido_original_ate = null
     where service_order_id = pg_temp.os('OS-97004');
    z := pg_temp.qc();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C3a as OS sem lugar com o Alex sozinho (o fora sem encaixe e o Vanderlei que passa do prazo) e a conta com mais uma pessoa: extra {meios_total 8, semanas [09/11: 8], os [Sérgio até 11/11]}',
    (select string_agg(s ->> 'numero' || ':' || coalesce(s ->> 'fim_hoje', '-'), ',' order by s ->> 'numero') from jsonb_array_elements(a #> '{capacidade,sem_lugar}') s)
      = 'OS-00069:2026-12-02,OS-97002:-,OS-97004:-,OS-97005:-'
    and (a #>> '{capacidade,extra,meios_total}')::int = 8 and a #> '{capacidade,extra,semanas}' = '[{"seg": "2026-11-09", "meios": 8}]'::jsonb
    and a #> '{capacidade,extra,os}' = jsonb_build_array(jsonb_build_object('de', '2026-11-09', 'os', pg_temp.os('OS-97002'), 'ate', '2026-11-11'))
    and a #>> '{capacidade,horizonte}' = '2026-12-21',
    (a -> 'capacidade')::text);
  v_res := pg_temp.ok(v_res, 'C3b os 3 textos byte a byte: a linha do foco, a parte da pergunta da quinta e o *livre*',
    pg_temp.linha(a ->> 'texto', '• Sem lugar') = '• Sem lugar com a equipe de hoje: Sérgio, Úrsula e Vera (só depois de 21/12); Vanderlei (termina qua 02/12, depois do prazo de qua 18/11). Com mais uma pessoa que trabalhe sozinha em 8 meios-dias (semana de 09/11: 8), Sérgio cabe até 11/11.'
    and exists (select 1 from jsonb_array_elements(a -> 'partes') p where p ->> 'tipo' = 'capacidade'
                   and p ->> 'texto' = 'Com a equipe de hoje, Vanderlei, Sérgio, Úrsula e mais 1 ficam sem lugar ou passam do prazo; com mais uma pessoa que trabalhe sozinha em 8 meios-dias (semana de 09/11: 8), Sérgio cabe até 11/11.')
    and a ->> 'texto_livre' = 'Sem lugar com a equipe de hoje: Vanderlei, Sérgio, Úrsula e mais 1. Com mais uma pessoa 8 meios-dias, Sérgio cabe até 11/11 (*agenda gestor* diz quando).'
    and a ->> 'texto_pergunta' = 'Lenine precisa de um ajudante junto de Alex em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas. Com a equipe de hoje, Vanderlei, Sérgio, Úrsula e mais 1 ficam sem lugar ou passam do prazo; com mais uma pessoa que trabalhe sozinha em 8 meios-dias (semana de 09/11: 8), Sérgio cabe até 11/11. Quem chama é você.',
    concat_ws(' || ', a ->> 'texto', a ->> 'texto_pergunta', a ->> 'texto_livre'));
  v_res := pg_temp.ok(v_res, 'C3c os meios-dias são os das OS sem lugar que passam a caber: a pessoa a mais da 2ª conta também vai a outras OS (a reserva, a dupla), e isso não entra na conta',
    v_ext > (a #>> '{capacidade,extra,meios_total}')::int, format('a pessoa a mais em %s meios-dias na 2ª conta; a conta: %s', v_ext, a #>> '{capacidade,extra,meios_total}'));
  v_res := pg_temp.ok(v_res, 'C3d a carteira que cabe: dupla [], sem_lugar [], prazo [] e "Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta."; sem pergunta nem *livre*',
    z -> 'dupla' = '[]'::jsonb and z #> '{capacidade,sem_lugar}' = '[]'::jsonb and z -> 'prazo' = '[]'::jsonb
    and z #> '{capacidade,extra}' = 'null'::jsonb
    and z ->> 'texto' = 'Quem chamar: ninguém — a equipe de hoje dá conta da carteira que está pronta.'
    and z ->> 'texto_pergunta' is null and z ->> 'texto_livre' is null,
    z::text);
  perform pg_temp.gravar(v_res);
end
$c3$;

-- ── C3b. O prazo ───────────────────────────────────────────────────────────────────────────────────────────────
do $c3b$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_van uuid;
  a     jsonb;
  b     jsonb;
  c     jsonb;
  v_t   text;
  v_g   text;
  v_d   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C3b (o prazo)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  v_van := pg_temp.os('OS-00069');
  -- o Lenine marcado; o Vanderlei (material a caminho: começa qua 18/11; 15 meios-dias de 1 pessoa até qua 02/12) com o prazo em
  -- qua 25/11 (o de 1 pessoa passa, o de 2 cumpre), qua 02/12 + 2 (cumpre com 1) e sex 20/11 (nem com 2)
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    update public.os_planejamento set precisa_ate = date '2026-11-25' where service_order_id = v_van;
    a := pg_temp.qc();
    -- *Vanderlei com dupla* + "Mateus vem qui 19 a qua 25/11" + *grava* → o tique seguinte do gestor (a rodada diária das 16:53 já
    -- passou)
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    v_d := public.agenda_dupla_dita(pg_temp.adm(), 'Vanderlei', true, date '2026-11-05', pg_temp.em(date '2026-11-05', '17:05')) ->> 'texto';
    v_g := pg_temp.disse('Mateus', 'qui 19 a qua 25/11');
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    v_t := pg_temp.vivas(v_van);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    update public.os_planejamento set precisa_ate = date '2026-12-04' where service_order_id = v_van;
    b := pg_temp.qc();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    update public.os_planejamento set precisa_ate = date '2026-11-20' where service_order_id = v_van;
    c := pg_temp.qc();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C3b1 o prazo de qua 25/11: com o Alex sozinho termina qua 02/12; com um ajudante junto dele (ceil(15 / 2) = 8 meios-dias, de qui 19 a qua 25/11) termina no prazo — prazo[0] e a linha do foco byte a byte',
    jsonb_array_length(a -> 'prazo') = 1 and a -> 'prazo' -> 0 ->> 'os' = v_van::text and a -> 'prazo' -> 0 ->> 'fim_hoje' = '2026-12-02'
    and a -> 'prazo' -> 0 ->> 'fim_com_ajudante' = '2026-11-25' and (a -> 'prazo' -> 0 ->> 'pm')::int = 15
    and jsonb_array_length(a -> 'prazo' -> 0 -> 'meios') = 8 and a -> 'prazo' -> 0 -> 'meios' -> 0 ->> 'dia' = '2026-11-19'
    and pg_temp.linha(a ->> 'texto', '• Vanderlei') = '• Vanderlei (prazo qua 25/11): com Alex sozinho termina qua 02/12; com um ajudante junto dele de qui 19 a qua 25/11 (8 meios-dias), termina no prazo. Se chamar, diga: Vanderlei com dupla; Mateus vem qui 19 a qua 25/11.'
    and exists (select 1 from jsonb_array_elements(a -> 'partes') p where p ->> 'tipo' = 'prazo'
                   and p ->> 'texto' = 'Vanderlei só cumpre o prazo de qua 25/11 com um ajudante junto de Alex de qui 19 a qua 25/11.')
    and not exists (select 1 from jsonb_array_elements(a #> '{capacidade,sem_lugar}') s where s ->> 'os' = v_van::text),
    concat_ws(' || ', (a -> 'prazo')::text, a ->> 'texto'));
  v_res := pg_temp.ok(v_res, 'C3b2 com o fim de 1 pessoa dentro do prazo (qua 04/12): nada no prazo; com o de 2 pessoas também depois do prazo (sex 20/11): nada no prazo, o Vanderlei fica na capacidade (passa do prazo)',
    b -> 'prazo' = '[]'::jsonb and not exists (select 1 from jsonb_array_elements(b #> '{capacidade,sem_lugar}') s where s ->> 'os' = v_van::text)
    and c -> 'prazo' = '[]'::jsonb
    and exists (select 1 from jsonb_array_elements(c #> '{capacidade,sem_lugar}') s where s ->> 'os' = v_van::text and s ->> 'fim_hoje' = '2026-12-02'),
    concat_ws(' || ', (b -> 'prazo')::text, (c #> '{capacidade,sem_lugar}')::text));
  v_res := pg_temp.ok(v_res, 'C3b3 *Vanderlei com dupla* + "Mateus vem qui 19 a qua 25/11" + *grava*: o tique seguinte do gestor (17:07) marca o Vanderlei com o Alex e o Mateus nesses meios-dias, dentro do prazo (a dupla o tempo todo de pm 15: 7 meios-dias de 2 pessoas — o motor arredonda para baixo; a sugestão, ceil, para cima)',
    v_t = '19/11 m Alex+Mateus; 19/11 t Alex+Mateus; 23/11 m Alex+Mateus; 23/11 t Alex+Mateus; 24/11 m Alex+Mateus; 24/11 t Alex+Mateus; 25/11 m Alex+Mateus',
    concat_ws(' | ', v_d, v_g, v_t));
  perform pg_temp.gravar(v_res);
end
$c3b$;

-- ── C4. A pessoa a mais nunca é gravada ────────────────────────────────────────────────────────────────────────
do $c4$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_n   bigint := 0;
  v_k   bigint;
  v_var text;
  v_ond text;
  t     record;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C4 (a pessoa a mais nunca é gravada)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    perform public._agenda_gestor_chamar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    v_var := coalesce(current_setting('agenda.pessoa_extra', true), '') || '/' || coalesce(current_setting('agenda.gestor', true), '');
    -- toda tabela de public, linha por linha, pelo texto
    for t in select c.oid::regclass as tab from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' loop
      execute format('select count(*) from %s x where x::text like %L', t.tab, '%' || public._agenda_pessoa_extra_id()::text || '%') into v_k;
      if v_k > 0 then
        v_n := v_n + v_k;
        v_ond := concat_ws(', ', v_ond, t.tab::text);
      end if;
    end loop;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C4a depois do passo chamar e da rodada diária do gestor: nenhuma linha com o id da pessoa a mais em tabela nenhuma de public, e as variáveis vazias',
    v_n = 0 and v_var = '/', format('%s linhas (%s); variáveis "%s"', v_n, coalesce(v_ond, '-'), v_var));
  perform pg_temp.gravar(v_res);
end
$c4$;
-- só _agenda_quem_chamar escreve agenda.pessoa_extra (o texto de todas as funções de public, sem os comentários)
insert into _resultado
select 'C4b só _agenda_quem_chamar escreve a variável da pessoa a mais (agenda.pessoa_extra), em todo o public',
       coalesce(string_agg(p.proname, ', ' order by p.proname), '') = '_agenda_quem_chamar',
       string_agg(p.proname, ', ' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'set_config\(\s*''agenda\.pessoa_extra''';
-- nada que a vigia e o motor chamam (pelo nome, até o fim) chega a _agenda_quem_chamar nem escreve a variável (o molde do G3 do lote P5)
with recursive g(oid) as (
  select p.oid from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname in ('agenda_vigiar', 'agenda_propor', 'agenda_aplicar') or p.proname like '\_agenda\_vigia\_%')
  union
  select p2.oid
    from g join pg_proc p on p.oid = g.oid
    cross join lateral regexp_matches(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'), '([a-z_][a-z0-9_]*)\s*\(', 'g') m
    join pg_proc p2 on p2.proname = m[1] and p2.pronamespace = 'public'::regnamespace
)
insert into _resultado
select 'C4c nada da vigia nem do motor (' || count(*) || ' funções, pelo nome até o fim) escreve agenda.pessoa_extra nem chama _agenda_quem_chamar',
       count(*) > 50
       and bool_and(regexp_replace(p.prosrc, '--[^\n]*', '', 'g') !~* 'set_config\(\s*''agenda\.pessoa_extra''')
       and bool_and(p.proname <> '_agenda_quem_chamar'),
       string_agg(p.proname, ', ') filter (where regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'set_config\(\s*''agenda\.pessoa_extra'''
                                             or p.proname = '_agenda_quem_chamar')
  from g join pg_proc p on p.oid = g.oid;

-- ── C5. O passo dupla ──────────────────────────────────────────────────────────────────────────────────────────
do $c5$
declare
  v_res  jsonb := '[]'::jsonb;
  v_len  uuid;
  v_tan  uuid;
  v_mat  uuid;
  v_acao uuid;
  v_ac2  uuid;
  a      text;
  b      text;
  c      text;
  d      text;
  e      text;
  f      text;
  g      text;
  h      text;
  v      jsonb;
  w      jsonb;
  x      jsonb;
  y      jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C5 (o passo dupla)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  v_tan := pg_temp.os('OS-97003');
  v_mat := pg_temp.pessoa('Mateus');
  -- "Mateus vem ter 10/11" + *grava* → o tique seguinte (17:07) põe o Mateus com o Alex nos 2 meios-dias; o *desfaz* volta
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    -- a rodada diária das 16:53 já passou (o tique das 17:07 é só o de todo tique)
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    a := pg_temp.vivas(v_len);
    b := pg_temp.disse('Mateus', 'ter 10/11');
    v := public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    c := pg_temp.vivas(v_len);
    select ac.id into v_acao from public.agenda_acoes ac where ac.tipo = 'reparar' and ac.service_order_id = v_len order by ac.criada_em desc limit 1;
    d := (select ac.tipo || ' | ' || ac.texto || ' | ' || (ac.desfazivel_ate is not null)::text
               || ' | ' || (select pr.parametros #>> '{gestor,motivo}' from public.agenda_propostas pr where pr.id = ac.proposta_id)
               || ' | ' || (select string_agg(distinct al.motivos::text, ',') from public.agenda_alocacoes al where al.id = any (ac.alocacoes_criadas))
            from public.agenda_acoes ac where ac.id = v_acao);
    -- o Mateus nunca sozinho: nenhum meio-dia de turno vigente só com ele
    e := (select count(*)::text from (select al.service_order_id, al.dia, al.turno from public.agenda_alocacoes al
                                       where al.estado in ('publicada', 'fixada') and al.presenca = 'turno' and al.dia >= date '2026-11-05'
                                       group by 1, 2, 3 having bool_and(al.payee_id = v_mat)) q);
    -- o tique seguinte não refaz (nada mais falta)
    w := public._agenda_gestor_dupla(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:23'));
    perform public.agenda_desfazer(v_acao, pg_temp.adm(), 'dono', date '2026-11-05', pg_temp.em(date '2026-11-05', '17:30'));
    f := pg_temp.vivas(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C5a "Mateus vem ter 10/11" + *grava*: o tique seguinte do gestor põe o Mateus com o Alex nos 2 meios-dias da dupla (a ação reparar, desfazível, o texto byte a byte; a marca dupla_completa na proposta e nas alocações), e o *desfaz* volta como estava',
    a like '10/11 m Alex; 10/11 t Alex; %' and c like '10/11 m Alex+Mateus; 10/11 t Alex+Mateus; 11/11 m Alex; %'
    and d = 'reparar | Pus Mateus com Alex no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas. *desfaz Lenine* volta. | true | dupla_completa | ["dupla_completa"]'
    and (v #>> '{contagens,dupla,completadas}')::int = 1 and f = a,
    concat_ws(' | ', b, c, d, f, v #>> '{contagens,dupla}'));
  v_res := pg_temp.ok(v_res, 'C5b o Mateus nunca fica sozinho num meio-dia, e o tique seguinte não refaz nada (0 completadas)',
    e = '0' and (w ->> 'completadas')::int = 0, concat_ws(' | ', e, w::text));

  -- o dia já avisado não muda; em teste, nada muda
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
    values (pg_temp.pessoa('Alex'), date '2026-11-10', 'ficha', 'ligado', 'Ficha de teste', pg_temp.em(date '2026-11-09', '19:30'), 'enfileirada',
            'teste:C5:ficha:alex:2026-11-10');
    perform pg_temp.vem('Mateus', array[date '2026-11-10']);
    x := public._agenda_gestor_dupla(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    a := pg_temp.vivas(v_len);
    y := pg_temp.qc();
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C5c o dia já avisado (a ficha de ter 10/11 na fila do Alex) não muda: o passo não põe ninguém, e o foco diz que lá eu não mexo',
    (x ->> 'completadas')::int = 0 and a like '10/11 m Alex; 10/11 t Alex; %'
    and pg_temp.linha(y ->> 'texto', '• Ajudante') = '• Ajudante para a dupla: Lenine em ter 10/11 (manhã e tarde) — a troca do banco de baterias pede 2 pessoas. Em ter 10/11 eu não mexo: o dia já foi avisado.',
    concat_ws(' | ', x::text, a, y ->> 'texto'));
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    update public.agenda_config set modo_dupla = 'sombra' where id;
    perform pg_temp.vem('Mateus', array[date '2026-11-10']);
    x := public._agenda_gestor_dupla(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    a := pg_temp.vivas(v_len);
    b := (select count(*)::text from public.agenda_propostas pr where pr.parametros #>> '{gestor,motivo}' = 'dupla_completa');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C5d em teste (modo_dupla em sombra): o passo só conta (pulado, em_teste, o que completaria), nada gravado',
    (x ->> 'pulado')::boolean and (x ->> 'em_teste')::boolean and jsonb_array_length(x -> 'completaria') = 1
    and x -> 'completaria' -> 0 ->> 'texto' = 'Pus Mateus com Alex no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas. *desfaz Lenine* volta.'
    and a like '10/11 m Alex; 10/11 t Alex; %' and b = '0',
    concat_ws(' | ', x::text, a, b));

  -- a dita "no início" (a Tânia, OS-97003, 2 meios-dias) que cabe nas datas do Mateus é marcada no mesmo tique; a dita "o tempo todo"
  -- do Lenine (6 meios-dias de 2 pessoas) com o Mateus só em qua 11 e qui 12/11 (4) continua esperando
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dupla_dita = 'todos', dupla_meios = null where service_order_id = v_len;
    insert into public.os_planejamento (service_order_id, dupla_dita, dupla_meios)
    values (v_tan, 'inicio', 2)
    on conflict (service_order_id) do update set dupla_dita = 'inicio', dupla_meios = 2;
    g := (select string_agg(x2.n || '=' || (public._agenda_classe_agora(pg_temp.os(x2.n), date '2026-11-05') ->> 'classe'), ' ' order by x2.n)
            from unnest(array['OS-00074', 'OS-97003']) x2(n));
    -- os tiques de antes da hora da revisão (15:07 e 15:23: só os passos de todo tique; a rodada diária encaixaria o resto da
    -- carteira nos dias do Alex)
    h := pg_temp.disse('Mateus', 'qua e qui');
    v := public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '15:07'));
    a := pg_temp.vivas(v_tan);
    b := pg_temp.vivas(v_len);
    c := (select f2 ->> 'texto' from public.agenda_propostas pr cross join lateral jsonb_array_elements(pr.fora) f2
           where f2 ->> 'os' = v_len::text and f2 ->> 'motivo' = 'dupla' order by pr.criada_em desc limit 1);
    -- o tique seguinte (15:23), sem nada novo nos dias: não refaz
    w := public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '15:23'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C5e a dita "no início" que esperava (Tânia, classe 4 só com o Alex) e cabe nas datas do Mateus (qua 11 e qui 12/11) é marcada no mesmo tique, com o Alex e o Mateus',
    g = 'OS-00074=4 OS-97003=4' and a like '%Alex+Mateus%' and (v #> '{contagens,dupla,ditas}') @> jsonb_build_array(v_tan::text),
    concat_ws(' | ', g, h, a, v #>> '{contagens,dupla}'));
  v_res := pg_temp.ok(v_res, 'C5f a dita "o tempo todo" do Lenine (6 meios-dias de 2 pessoas) com o Mateus em 4 continua esperando: o fora dupla com o texto do R4.3(c), nunca sem lugar calado; o tique seguinte não refaz (os dias de ninguém mudaram)',
    b = '-' and c = 'Lenine (OS-00074): precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante.'
    and w #> '{contagens,dupla,ditas}' = '[]'::jsonb,
    concat_ws(' | ', b, c, w #>> '{contagens,dupla}'));

  -- a revisão do dia seguinte (sex 06/11, 16:53): o Lenine completo (14 contra 12) perde só os 2 últimos meios-dias, com o texto da
  -- dupla, e o *desfaz* volta; sem o Mateus (12), nada; em teste, a dupla completada (14) fica
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    perform pg_temp.vem('Mateus', array[date '2026-11-10']);
    perform public._agenda_gestor_dupla(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    v := public._agenda_gestor_revisao(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
    a := pg_temp.vivas(v_len);
    select ac.id into v_ac2 from public.agenda_acoes ac where ac.tipo = 'reestimar' and ac.service_order_id = v_len order by ac.criada_em desc limit 1;
    b := (select ac.texto from public.agenda_acoes ac where ac.id = v_ac2);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o *desfaz* do corte: o corte aplicado sozinho (a revisão também encaixa outra OS no meio-dia que sobrou, e aí o *desfaz* recusa,
  -- como na 7a)
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    perform pg_temp.vem('Mateus', array[date '2026-11-10']);
    perform public._agenda_gestor_dupla(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    y := public._agenda_gestor_reestimar(v_len, date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'), null);
    f := pg_temp.vivas(v_len);
    w := public.agenda_desfazer((y -> 'acao_ids' ->> 0)::uuid, pg_temp.adm(), 'dono', date '2026-11-06', pg_temp.em(date '2026-11-06', '17:30'));
    c := pg_temp.vivas(v_len) || ' | ' || (w ->> 'texto') || ' | ' || (y ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    w := public._agenda_gestor_revisao(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
    d := pg_temp.vivas(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('ligado', 'ligado');
    perform pg_temp.marcar(array[v_len]);
    perform pg_temp.vem('Mateus', array[date '2026-11-10']);
    perform public._agenda_gestor_dupla(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:07'));
    update public.agenda_config set modo_dupla = 'sombra' where id;
    x := public._agenda_gestor_revisao(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
    e := pg_temp.vivas(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C5g a revisão do dia seguinte: o Lenine com o Mateus nos 2 primeiros (14 contra 12) perde exatamente os 2 últimos meios-dias (ter 17/11), com o texto da dupla; o *desfaz* volta',
    a = '10/11 m Alex+Mateus; 10/11 t Alex+Mateus; 11/11 m Alex; 11/11 t Alex; 12/11 m Alex; 12/11 t Alex; 13/11 m Alex; 13/11 t Alex; 16/11 m Alex; 16/11 t Alex'
    and b = 'Lenine (OS-00074): com Mateus junto em ter 10/11, o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11.'
    and f = a and c like '%; 17/11 m Alex; 17/11 t Alex | %',
    concat_ws(' | ', a, b, f, c));
  v_res := pg_temp.ok(v_res, 'C5h sem o Mateus (o bloco de 1 pessoa, 12 meios-dias), a revisão não corta nem acrescenta; em teste (modo_dupla em sombra), a dupla completada (14) também fica',
    d like '%; 17/11 m Alex; 17/11 t Alex' and not exists (select 1 from jsonb_array_elements(coalesce(w #> '{reestimar,cortes}', '[]'::jsonb)) k
                                                            where k ->> 'os' = v_len::text)
    and e like '10/11 m Alex+Mateus; 10/11 t Alex+Mateus; %; 17/11 m Alex; 17/11 t Alex'
    and not exists (select 1 from jsonb_array_elements(coalesce(x #> '{reestimar,cortes}', '[]'::jsonb)) k where k ->> 'os' = v_len::text),
    concat_ws(' | ', d, e, (w -> 'reestimar')::text, (x -> 'reestimar')::text));
  perform pg_temp.gravar(v_res);
end
$c5$;

-- ── C6. A pergunta dias_semana com o motivo chamar ─────────────────────────────────────────────────────────────
do $c6$
declare
  v_res  jsonb := '[]'::jsonb;
  v_dono uuid := public._agenda_dono(null);
  a      text;
  b      text;
  c      text;
  d      jsonb;
  e      jsonb;
  v      jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C6 (a pergunta com o motivo chamar)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  -- a dita do Sérgio (OS-97002, da fixture da 7a) esperando a 2ª pessoa (o bloco do Alex nesta semana: fica fora da pergunta da de
  -- 16/11) e a capacidade (a Vera passa a caber em 16 e 17/11: entra); só o motivo chamar
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dupla_dita = 'todos' where service_order_id = pg_temp.os('OS-97002');
    update public.agenda_config set dias_semana_motivos = '{chamar}' where id;
    v := public.agenda_equipe_semana(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    a := coalesce(v #>> '{contagens,perguntar,dono}', '-');
    perform public._agenda_gestor_chamar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    v := public.agenda_equipe_semana(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:00'));
    a := a || '/' || coalesce(v #>> '{contagens,perguntar,dono}', '-') || ':' || coalesce(v #>> '{contagens,perguntar,motivos}', '-');
    b := (select q.texto from public.agenda_perguntas q where q.tipo = 'dias_semana' and q.estado = 'aberta' and q.chave = format('dias_semana:%s:2026-11-16', v_dono));
    v := public.agenda_equipe_semana(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:15'));
    a := a || '/' || coalesce(v #>> '{contagens,perguntar,dono}', '-') || '/'
         || (select count(*) from public.agenda_perguntas q where q.tipo = 'dias_semana')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C6a com quem chamar ligado: o tique das 16:45 espera o diário de hoje; o das 17:00 pergunta com o chamar das 16:53 (o texto byte a byte); o das 17:15 não repete (uma por semana)',
    a = 'espera_o_diario/perguntei:["chamar"]/-/1'
    and b = 'Semana de 16/11: conto com Alex de seg a sex (você disse). Com a equipe de hoje, Vanderlei, Úrsula e Vera ficam sem lugar ou passam do prazo; com mais uma pessoa que trabalhe sozinha em 4 meios-dias (semana de 16/11: 4), Vera cabe até 17/11. Quem chama é você. Se mudar algo, me diga (ex.: fico em campo seg a qua; Mateus vem ter e qua). 1) Fica assim.',
    concat_ws(' | ', a, b));
  -- sem a sugestão na semana perguntada (só a dupla do Lenine em ter 10/11, antes de 16/11): nenhuma
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.agenda_config set dias_semana_motivos = '{chamar}' where id;
    perform pg_temp.marcar(array[pg_temp.os('OS-00074')]);
    perform public._agenda_gestor_chamar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    v := public.agenda_equipe_semana(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:00'));
    c := coalesce(v #>> '{contagens,perguntar,dono}', '-') || '/'
         || (select count(*) from public.agenda_perguntas q where q.tipo = 'dias_semana' and q.estado = 'aberta')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C6b com a sugestão só antes da semana perguntada (a dupla do Lenine em ter 10/11): sem motivo, nada nasce',
    c = 'sem_motivo/0', c);
  -- a forma curta: um diário de hoje com as partes compridas demais
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.agenda_config set dias_semana_motivos = '{chamar}' where id;
    perform public._agenda_gestor_dia_gravar(date '2026-11-05', 'chamar', jsonb_build_object(
      'calculado_em', pg_temp.em(date '2026-11-05', '16:53'),
      'partes', jsonb_build_array(
        jsonb_build_object('tipo', 'dupla', 'os', jsonb_build_array(pg_temp.os('OS-00074')), 'nomes', jsonb_build_array('Lenine'),
                           'texto', repeat('Lenine precisa de um ajudante. ', 12), 'dias', jsonb_build_array('2026-11-17')),
        jsonb_build_object('tipo', 'prazo', 'os', jsonb_build_array(pg_temp.os('OS-00069')), 'nomes', jsonb_build_array('Vanderlei'),
                           'texto', repeat('Vanderlei só cumpre o prazo com um ajudante. ', 6), 'dias', jsonb_build_array('2026-11-19')),
        jsonb_build_object('tipo', 'dupla', 'os', jsonb_build_array(pg_temp.os('OS-00112')), 'nomes', jsonb_build_array('Nelson'),
                           'texto', 'Nelson antes da semana.', 'dias', jsonb_build_array('2026-11-10')))),
      pg_temp.em(date '2026-11-05', '16:53'));
    d := public._agenda_dias_semana_motivos(date '2026-11-16', date '2026-11-05');
    update public.agenda_config set modo_chamar = 'sombra' where id;
    e := public._agenda_dias_semana_motivos(date '2026-11-16', date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C6c a pergunta inteira acima de 600 letras: a parte chamar na forma curta, com os nomes das partes da semana (o Nelson, antes dela, fica de fora); com modo_chamar em teste, sem o motivo',
    d -> 'motivos' = '["chamar"]'::jsonb
    and d -> 'partes' -> 0 ->> 'texto' = 'Lenine e Vanderlei precisam de mais gente: *agenda gestor* diz quem chamar e quando.'
    and d -> 'partes' -> 0 -> 'os' = jsonb_build_array(pg_temp.os('OS-00074'), pg_temp.os('OS-00069'))
    and e -> 'motivos' = '[]'::jsonb,
    concat_ws(' | ', d::text, e::text));
  perform pg_temp.gravar(v_res);
end
$c6$;

-- ── C7. O foco *agenda gestor* e o *livre* ─────────────────────────────────────────────────────────────────────
do $c7$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  a     text;
  b     text;
  c     text;
  d     text;
  e     text;
  f     text;
  g     text;
  q     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C7 (o foco e o livre)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dias = 8, estimativa_fonte = 'dono', estimativa_em = timestamptz '2026-11-05 10:00-03'
     where service_order_id in (pg_temp.os('OS-00112'), pg_temp.os('OS-00130'));
    insert into public.os_planejamento (service_order_id, dono_presenca)
    select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00112', 'OS-00130')
    on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste'
     where estado = 'aberta' and service_order_id in (pg_temp.os('OS-00112'), pg_temp.os('OS-00130'));
    -- sem conta ainda
    a := public._agenda_ver_gestor(date '2026-11-05') ->> 'texto';
    perform pg_temp.marcar(array[v_len]);
    perform public._agenda_gestor_chamar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    q := (select g2.chamar from public.agenda_gestor_dia g2 where g2.dia = date '2026-11-05');
    b := public._agenda_ver_gestor(date '2026-11-05') ->> 'texto';
    c := public.agenda_livre_de_verdade(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10')) ->> 'texto_completo';
    -- o admin logado (o painel, authenticated): o foco e o *livre* com as linhas do P6, sem 42501
    g := pg_temp.como('authenticated', 'select public._agenda_ver_gestor(date ''2026-11-05'') ->> ''texto''', pg_temp.adm())
         || ' || ' || pg_temp.como('authenticated', 'select public.agenda_livre_de_verdade(date ''2026-11-05'', now()) ->> ''texto_completo''',
                                   pg_temp.adm());
    -- a conta de ontem, vista hoje
    d := public._agenda_ver_gestor(date '2026-11-06') ->> 'texto';
    update public.agenda_config set modo_chamar = 'sombra' where id;
    e := public._agenda_ver_gestor(date '2026-11-05') ->> 'texto';
    f := public.agenda_livre_de_verdade(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10')) ->> 'texto_completo';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C7a o foco *agenda gestor* sem a conta do dia: "Quem chamar: ainda não fiz a conta (faço todo dia útil no fim da tarde)."',
    a like '%' || E'\n' || 'Quem chamar: ainda não fiz a conta (faço todo dia útil no fim da tarde).' || E'\n' || '%', a);
  v_res := pg_temp.ok(v_res, 'C7b ligado: o bloco "Quem chamar" do diário (o mesmo texto do passo chamar), depois do "Perguntei antes de marcar" e antes do "Fora"; o "Pode precisar de dupla" do Lenine vira a frase da dupla de 1 pessoa, com as datas',
    position((q ->> 'texto') in b) > 0
    and position('Quem chamar (só sugiro; quem chama é você):' in b) < coalesce(nullif(position(E'\nFora: ' in b), 0), length(b) + 1)
    and b not like '%Pode precisar de dupla%'
    and b like '%• Lenine: ter 10 a ter 17/11, Alex — 6 dias (estimativa minha). Nos 2 primeiros meios-dias (ter 10/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem ter 10/11).%',
    b);
  v_res := pg_temp.ok(v_res, 'C7b2 o admin logado (authenticated, o painel) lê o foco com o bloco "Quem chamar" e o *livre* com a linha (o diário pela RLS do admin; nenhum 42501)',
    g like '%Quem chamar (só sugiro; quem chama é você):%' and g like '%• Ajudante para a dupla: Lenine em ter 10/11%'
    and g like '%Sem lugar com a equipe de hoje: Vanderlei, Sérgio, Úrsula e mais 1. Com mais uma pessoa 8 meios-dias%' and g not like '%erro %',
    left(g, 600));
  v_res := pg_temp.ok(v_res, 'C7c o *livre* com quem chamar ligado: a linha no fim, byte a byte',
    c like '%' || E'\n' || 'Sem lugar com a equipe de hoje: Vanderlei, Sérgio, Úrsula e mais 1. Com mais uma pessoa 8 meios-dias, Sérgio cabe até 11/11 (*agenda gestor* diz quando).',
    c);
  v_res := pg_temp.ok(v_res, 'C7d a conta de ontem vista hoje: "Quem chamar (pela conta de qui 05/11; só sugiro; quem chama é você):"',
    d like '%' || E'\n' || 'Quem chamar (pela conta de qui 05/11; só sugiro; quem chama é você):' || E'\n' || '• Ajudante para a dupla: %', d);
  v_res := pg_temp.ok(v_res, 'C7e em teste (modo_chamar em sombra): o foco com "Em teste: quem chamar …" e o *livre* sem a linha',
    e like '%' || E'\n' || 'Em teste: quem chamar (só sugiro; quem chama é você):' || E'\n' || '• Ajudante para a dupla: %'
    and f not like '%Sem lugar com a equipe de hoje%' and length(f) > 50,
    concat_ws(' || ', e, f));
  -- o gestor em teste: o "Pode precisar de dupla" da conta da sombra vira a forma curta (sem plano, sem as datas)
  begin
    perform pg_temp.base('sombra', 'sombra');
    perform public._agenda_gestor_sombra(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    g := public._agenda_ver_gestor(date '2026-11-05') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C7f o gestor em teste: o "Pode precisar de dupla (…): … diga *Lenine com dupla*" vira "Nos 2 primeiros meios-dias a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga os dias dele."',
    g not like '%Pode precisar de dupla%'
    and g like '%• Lenine: %. Nos 2 primeiros meios-dias a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga os dias dele.%',
    g);
  perform pg_temp.gravar(v_res);
end
$c7$;

-- ── C8. Desligados = os de antes; as cópias ────────────────────────────────────────────────────────────────────
do $c8$
declare
  v_res  jsonb := '[]'::jsonb;
  v_len  uuid;
  v_a    jsonb;
  v_b    jsonb;
  a      text;
  b      text;
  r      record;
begin
  if not pg_temp.carregada() or coalesce(current_setting('agenda_teste.mig_compras_fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_correcao2_fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_correcao_fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_pergunta_fase7b', true), '') = '' then
    insert into _resultado values ('C8 (desligados = os de antes)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  -- as definições de antes, no lugar (numa subtransação desfeita): a rodada, o foco, o livre, o motivo da pergunta e o corte
  begin
    perform pg_temp.base('ligado', 'desligado');
    perform pg_temp.marcar(array[v_len]);
    update public.os_planejamento set dupla_dita = 'todos' where service_order_id = pg_temp.os('OS-97002');
    v_a := jsonb_build_object(
      'rodar', (select jsonb_agg(k order by k) from jsonb_object_keys(public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53')) -> 'contagens') k),
      'ver', public._agenda_ver_gestor(date '2026-11-05'),
      'livre', public.agenda_livre_de_verdade(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10')) - 'ms',
      'motivos', public._agenda_dias_semana_motivos(date '2026-11-16', date '2026-11-05'),
      'corte', public._agenda_gestor_corte(v_len, date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute pg_temp.inteira(current_setting('agenda_teste.mig_compras_fase7a'), 'agenda_gestor_rodar');
    execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao2_fase7a'), '_agenda_ver_gestor');
    execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7a'), 'agenda_livre_de_verdade');
    execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7a'), '_agenda_gestor_corte');
    execute pg_temp.inteira(current_setting('agenda_teste.mig_pergunta_fase7b'), '_agenda_dias_semana_motivos');
    perform pg_temp.base('ligado', 'desligado');
    perform pg_temp.marcar(array[v_len]);
    update public.os_planejamento set dupla_dita = 'todos' where service_order_id = pg_temp.os('OS-97002');
    v_b := jsonb_build_object(
      'rodar', (select jsonb_agg(k order by k) from jsonb_object_keys(public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53')) -> 'contagens') k),
      'ver', public._agenda_ver_gestor(date '2026-11-05'),
      'livre', public.agenda_livre_de_verdade(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:10')) - 'ms',
      'motivos', public._agenda_dias_semana_motivos(date '2026-11-16', date '2026-11-05'),
      'corte', public._agenda_gestor_corte(v_len, date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C8a com modo_chamar e modo_dupla desligados (os 5 modos da 7b): a rodada diária do gestor (os passos: sem dupla nem chamar), o foco *agenda gestor*, o *livre*, o motivo da pergunta e o corte são os de antes, byte a byte (o gestor da 7a ligado, o Lenine marcado e a dita do Sérgio)',
    v_a is not null and v_a -> 'rodar' = v_b -> 'rodar' and not (v_a -> 'rodar') ? 'dupla' and not (v_a -> 'rodar') ? 'chamar'
    and v_a -> 'ver' = v_b -> 'ver' and v_a -> 'livre' = v_b -> 'livre' and v_a -> 'motivos' = v_b -> 'motivos' and v_a -> 'corte' = v_b -> 'corte',
    concat_ws(' | ', v_a -> 'rodar', v_b -> 'rodar', md5((v_a -> 'ver')::text), md5((v_b -> 'ver')::text), md5((v_a -> 'livre')::text),
              md5((v_b -> 'livre')::text), v_a ->> 'motivos', v_b ->> 'motivos'));
  -- com os dois em teste, a rodada leva o passo dupla (só conta) e o chamar
  begin
    perform pg_temp.base('ligado', 'sombra');
    v_a := public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C8b com os modos da 7b em teste: a rodada do gestor tem o passo dupla em todo tique (em teste: pulado, só conta) e o chamar nos diários, depois de sombra',
    v_a #>> '{contagens,dupla,motivo}' = 'em teste' and (v_a #>> '{contagens,dupla,pulado}')::boolean
    and v_a #>> '{contagens,chamar,modo}' = 'sombra' and (v_a ->> 'diaria')::boolean,
    concat_ws(' | ', v_a #>> '{contagens,dupla}', v_a #>> '{contagens,chamar}'));
  -- o gravador: as chaves de antes como antes; a chave nova é um objeto
  begin
    perform public._agenda_gestor_dia_gravar(date '2026-11-05', 'compras', '[{"texto": "teste"}]'::jsonb, pg_temp.em(date '2026-11-05', '16:53'));
    perform public._agenda_gestor_dia_gravar(date '2026-11-05', 'chamar', '{"calculado_em": "2026-11-05T19:53:00Z", "texto": "um"}'::jsonb,
                                             pg_temp.em(date '2026-11-05', '16:53'));
    perform public._agenda_gestor_dia_gravar(date '2026-11-05', 'chamar', '{"calculado_em": "2026-11-05T19:54:00Z", "texto": "dois"}'::jsonb,
                                             pg_temp.em(date '2026-11-05', '16:54'));
    a := (select g.compras::text || ' | ' || (g.chamar ->> 'texto') || ' | ' || (g.historico -> 0 ->> 'chave') || ':' || (g.historico #>> '{0,antes,texto}')
            from public.agenda_gestor_dia g where g.dia = date '2026-11-05');
    begin
      perform public._agenda_gestor_dia_gravar(date '2026-11-05', 'chamar', '[1]'::jsonb, pg_temp.em(date '2026-11-05', '16:55'));
      b := 'gravou';
    exception when others then
      b := sqlstate || ': ' || sqlerrm;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C8c o gravador do diário: compras como antes; chamar é um objeto (a de antes no histórico); lista em chamar = 22023',
    a = '[{"texto": "teste"}] | dois | chamar:um' and b = '22023: _agenda_gestor_dia_gravar: chamar é um objeto.', concat_ws(' | ', a, b));
  perform pg_temp.gravar(v_res);
end
$c8$;
do $copia$
declare
  f      record;
  v_mig  text;
  v_novo text;
  v_n    int;
begin
  for f in select * from (values
      ('agenda_gestor_rodar', 'public.agenda_gestor_rodar(date, timestamptz)', 'mig_compras_fase7a', '20261031100800', 1),
      ('_agenda_gestor_dia_gravar', 'public._agenda_gestor_dia_gravar(date, text, jsonb, timestamptz)', 'mig_base_fase7a', '20261031100000', 1),
      ('_agenda_ver_gestor', 'public._agenda_ver_gestor(date)', 'mig_correcao2_fase7a', '20261031100985', 5),
      ('agenda_livre_de_verdade', 'public.agenda_livre_de_verdade(date, timestamptz)', 'mig_correcao_fase7a', '20261031100980', 2),
      ('_agenda_dias_semana_motivos', 'public._agenda_dias_semana_motivos(date, date)', 'mig_pergunta_fase7b', '20261101100200', 2),
      ('_agenda_gestor_corte', 'public._agenda_gestor_corte(uuid, date, timestamptz)', 'mig_correcao_fase7a', '20261031100980', 2))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('C8d %s: a cópia', f.nome), true, format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7b: fim', 'g');
    insert into _resultado values (
      format('C8d %s: sem os %s blocos "-- FASE 7b:", é o corpo de %s', f.nome, f.blocos, f.versao),
      pg_temp.corpo(v_mig, f.nome) <> '' and pg_temp.sem_7b(v_novo) = pg_temp.corpo(v_mig, f.nome) and v_n = f.blocos,
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(v_mig, f.nome)), length(pg_temp.sem_7b(v_novo))));
  end loop;
end
$copia$;

-- ── C9. O custo ────────────────────────────────────────────────────────────────────────────────────────────────
do $c9$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  v_t0  timestamptz;
  v_ms  int;
  v_max int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C9 (o custo)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('ligado', 'ligado');
    update public.os_planejamento set dupla_dita = 'todos' where service_order_id = pg_temp.os('OS-97002');
    perform pg_temp.marcar(array[pg_temp.os('OS-00074')]);
    v_t0 := clock_timestamp();
    v := public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    v_max := (extract(epoch from (public._agenda_cfg()).gestor_tempo_max) * 1000)::int;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C9 a rodada diária do gestor com o passo chamar (duas voltas do motor e o encaixe da dita) e o dupla fica abaixo de gestor_tempo_max, sem falha',
    (v ->> 'diaria')::boolean and v -> 'falhas' = '[]'::jsonb and v_ms < v_max and v #>> '{contagens,chamar,modo}' = 'ligado',
    format('rodada %s ms (o passo chamar %s ms; o teto %s ms); dupla %s', v_ms, v #>> '{contagens,chamar,ms}', v_max, v #>> '{contagens,dupla}'));
  perform pg_temp.gravar(v_res);
end
$c9$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
