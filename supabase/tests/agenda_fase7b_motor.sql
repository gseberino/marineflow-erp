-- Prova do motor da Agenda de Produção, Fase 7b (pacote P4): a dupla por meio-dia (a inferida pela tarefa vai com 1 pessoa quando
-- falta a 2ª e diz em que meios-dias chamar um ajudante; a dita pelo dono espera a 2ª pessoa, também em teste; o "fora" dupla quando
-- quem vem sob demanda não cobre), o novato e quem vem sob demanda nunca sozinhos, o dono técnico com o teto dele, o sábado de manhã
-- de quem se ofereceu, o gancho da pessoa a mais e a revisão do dia seguinte que não corta o bloco de 1 pessoa nem a dupla (migration
-- 20261101100300).
-- bancada: depende de 20261101100300
--
--   M0  as portas: as 4 novas (invoker, volatilidade, authenticated e service_role, nunca anon: 42501) e as recriadas com as de antes
--   M1  _agenda_dupla_da_os nas linhas reais (a tabela da §2: o nome do serviço que casou, o gatilho, onde); o Starlink da ORÇ-00119,
--       o "12V" e o "ar-condicionado 12 V" sem nada; a nota de espaço apertado (OS-97101); a dita pelo dono
--   M2  agenda_meios_da_os: desligado = a de antes byte a byte (a carteira toda); em teste sem a regra uma_pessoa (2 pessoas) = igual;
--       em teste com ela = dk com 2 nos meios-dias da dupla e o total de antes; ligado = as diárias-pessoa conservadas (Lenine 12 → 10,
--       Vanderlei 15 → 13, Kalmar-33 o tempo todo)
--   M3a só o Alex (ligado): Lenine com o Alex nos 12 meios-dias, dupla_falta nos 2 primeiros e o texto byte a byte; nenhuma pergunta
--   M3b o Mateus dito nos dias: Alex e Mateus nos 2 primeiros, o Alex no resto (10 meios-dias)
--   M3c o Mateus nunca sozinho: com o Alex fora nos dias dele, nenhum meio-dia do Mateus sem o Alex
--   M3d a espera: a dupla 3 dias úteis depois vence; 6 dias úteis depois perde para o de 1 pessoa; e o prazo firme
--   M3e a revisão do dia seguinte: o bloco de 1 pessoa (12) e o em dupla (12) com precisa 12, nada cortado nem faltando (ligado); em
--       teste, o de 1 pessoa (12) e a dupla acrescentada (14) também; sem dk, a conta de antes
--   M4  o novato (_agenda_e_novato) e quem vem sob demanda (_agenda_e_sob_demanda); o Bruno nunca sozinho num meio-dia
--   M5  o dono técnico: sem dono_como_tecnico, nunca numa vaga; com ele, por último, nos dias de campo dele, e o serviço acaba antes
--   M5b o teto do dono com a linha: ligado 5 meios-dias de turno por semana; em teste e desligado 8 (correção da revisão da 7b, achado 14);
--       ligado, o aprendido acima de 0,50 não passa
--   M6  o sábado: so_prazo + ligado = Vanderlei com sáb 21/11 de manhã e o texto; em teste nenhuma alocação no sábado e a linha "Em
--       teste"; nunca e desligado = nada; sem prazo = nada; nunca à tarde, nunca o 1º passo
--   M7  o validador: a regra 6 com a manhã de sábado oferecida (ligado) e sem ela; o sábado não conta como dia parado (regra 13)
--   M8  as cópias: tirados os blocos "-- FASE 7b:", o corpo de cada recriada é o da origem, com o número de blocos
--   M9  com os 5 modos da 7b desligados, o motor (a semana, a carteira), o contexto, o molde e a classe = os de antes, byte a byte — com o
--       gestor da 7a desligado e ligado, com a linha do dono e com quem vem sob demanda com datas
--   M10 a dupla dita esperando (o tempo todo e no início) com só o Alex = classe 4 dupla em ligado E em teste; com o Mateus dito no
--       horizonte = classe 2; modo_dupla desligado = a correção 2 da 7a
--   M11 dk_dono_conta: a Kalmar-33 (o dono sempre, o orçamento com 2 técnicos) pede 2 técnicos e o dono junto; o dono que só abre e
--       fecha não conta; o diagnóstico com o dono conta
--   M12 a dupla dita o tempo todo do Lenine com o Mateus só qua e qui: classe 2 pela régua, nenhum bloco → fora com o motivo dupla e o
--       texto, nunca sem_encaixe
--   M13 _agenda_gestor_sabado com modo_sabado ligado = {pulado: modo_sabado}
--   M14 o gancho da pessoa a mais: sem a variável, nada; com ela, a "mais uma pessoa" livre nos dias úteis, aceita pelo validador, e
--       nada gravado com o id dela
--   M15 o aceite (§11.3 do R4.8): com só o Alex, Lenine e Vanderlei entram no plano com o Alex e a sugestão do ajudante (nenhum espera pela dupla)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7b_motor.sql
--   Seguro em produção: termina em ROLLBACK. M0 e M8 rodam em qualquer banco (M8 sai PULADO sem as migrations como texto); o resto usa
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
-- FASE 7c: (7c P2) a 20261102100100 recria o motor de novo, com os blocos "-- FASE 7c: … -- FASE 7c: fim" (no nível de fora, só
-- acréscimo): o M8 os tira antes; e o motor da 7c grava em cada alocação do item o critério que decidiu a pessoa (criterio e
-- criterio_detalhe, em qualquer modo) e o contexto ganha hab, habf e custo: o M9 compara sem eles (a projeção da spec-fase7c §3.8 d8)
create function pg_temp.sem_7c(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[cdef]:' and l !~ '-- FASE 7[cdef]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[cdef]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[cdef]: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
create function pg_temp.sem_criterio(p jsonb) returns jsonb language sql immutable as $f$
  select case when jsonb_typeof(p -> 'itens') <> 'array' then p
              else jsonb_set(p, '{itens}', coalesce((
                     select jsonb_agg(case when jsonb_typeof(i -> 'alocacoes') = 'array'
                                           then jsonb_set(i, '{alocacoes}', coalesce((
                                                  select jsonb_agg(a - 'criterio' - 'criterio_detalhe' order by o)
                                                    from jsonb_array_elements(i -> 'alocacoes') with ordinality u(a, o)), '[]'::jsonb))
                                           else i end order by k)
                       from jsonb_array_elements(p -> 'itens') with ordinality t(i, k)), '[]'::jsonb)) end
$f$;
-- FASE 7c: fim
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

-- ── M0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────
with f(sig, vol) as (values
  ('public._agenda_pessoa_extra_id()', 'i'), ('public._agenda_e_novato(uuid, date)', 's'),
  ('public._agenda_e_sob_demanda(uuid, date)', 's'), ('public._agenda_dupla_da_os(uuid)', 's'))
insert into _resultado
select 'M0a as 4 novas: invoker, search_path fixo, a volatilidade, authenticated e service_role, nunca anon',
       count(p.oid) = 4
       and bool_and(not p.prosecdef and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                    and not has_function_privilege('anon', p.oid, 'execute')),
       string_agg(format('%s %s definer=%s anon=%s', f.sig, p.provolatile, p.prosecdef, has_function_privilege('anon', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'M0b o anon chamando a dupla da OS recebe 42501', v like 'erro 42501%', v
  from (select pg_temp.como('anon', 'select public._agenda_dupla_da_os(gen_random_uuid())::text') as v) x;
with f(sig, quem) as (values
  ('public.os_duracao_sugerida(uuid)', 'leitura'), ('public.agenda_meios_da_os(uuid, date)', 'leitura'),
  ('public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', 'leitura'), ('public._agenda_tecnicos_da_grade(date)', 'leitura'),
  ('public._agenda_carga_da_pessoa(uuid)', 'leitura'),
  ('public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)', 'leitura'),
  ('public._agenda_contexto(date, date, date, uuid[], uuid[])', 'servico'),
  ('public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)', 'servico'),
  ('public._agenda_melhor(jsonb, jsonb)', 'servico'), ('public._agenda_encaixar(jsonb, jsonb, jsonb)', 'servico'),
  ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'servico'),
  ('public._agenda_gestor_pessoa_meios(uuid, date, jsonb)', 'ninguem'), ('public._agenda_gestor_sabado(date, timestamptz)', 'ninguem'))
insert into _resultado
select 'M0c as 13 recriadas com as portas de antes (leitura: authenticated e service_role; o motor: só service_role; os passos do gestor: ninguém; nunca anon); agenda_propor continua definer',
       count(p.oid) = 13
       and bool_and(not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          when 'servico' then not has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute') end)
       and (select prosecdef from pg_proc where oid = to_regprocedure('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)')),
       string_agg(f.sig, '; ') filter (where p.oid is null or has_function_privilege('anon', p.oid, 'execute'))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── As fixtures (uma vez; cada caso abaixo roda numa subtransação desfeita) ────────────────────────────────────────
-- A base é a fixture da 7b com Mateus (sob demanda, sem linha), Rafael (diarista com padrão) e Bruno (o novato com ter 10/11), mais a
-- presença do dono do Lenine e do Vanderlei como em produção (abre e fecha) e o gestor da 7a ligado (a regra uma_pessoa).
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
create function pg_temp.nao_vem(p_nome text, p_de date, p_ate date) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(p_de, p_ate, '[]'), null, 'indisponivel', 'dono', 'não vem (teste)', timestamptz '2026-11-05 10:01-03'
    from public.payees p where p.name = p_nome and p.active
$f$;
create function pg_temp.propor(p_os uuid[]) returns jsonb language sql as $f$
  select public.agenda_propor('os', null, null, p_os, '{}'::jsonb, false, 'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'))
$f$;
create function pg_temp.marcar(p_os uuid[]) returns jsonb language plpgsql as $f$
declare
  v_p jsonb;
begin
  v_p := public.agenda_propor('os', null, null, p_os, '{}'::jsonb, true, 'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
end $f$;
-- o item de compromisso da OS: "dd/mm t Nome+Nome; …" (os meios-dias de turno, na ordem)
create function pg_temp.meios(p_item jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(x.d || ' ' || x.t || ' ' || x.n, '; ' order by x.d, x.t), '-')
    from (select to_char((a ->> 'dia')::date, 'DD/MM') as d, case when a ->> 'turno' = 'manha' then 'm' else 't' end as t,
                 string_agg(a ->> 'nome', '+' order by a ->> 'nome') as n
            from jsonb_array_elements(coalesce(p_item -> 'alocacoes', '[]'::jsonb)) a
           where a ->> 'presenca' = 'turno' group by 1, 2) x
$f$;
create function pg_temp.item(p_prop jsonb, p_os uuid) returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(coalesce(p_prop -> 'itens', '[]'::jsonb)) i
   where (i ->> 'os')::uuid = p_os and i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' limit 1
$f$;
create function pg_temp.vivas(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(x.d || ' ' || x.t || ' ' || x.n, '; ' order by x.d, x.t), '-')
    from (select to_char(a.dia, 'DD/MM') as d, case when a.turno = 'manha' then 'm' else 't' end as t,
                 string_agg(public._agenda_nome_curto(py.name), '+' order by py.name) as n
            from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
           where a.service_order_id = p_os and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
           group by 1, 2) x
$f$;

-- ── M1. A dupla da OS nas linhas reais ─────────────────────────────────────────────────────────────────────────
do $m1$
declare
  v_res jsonb := '[]'::jsonb;
  v_ruim text;
  d     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M1 (a dupla da OS)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  with c(numero, fonte, ini, fim, todos, mots) as (values
    ('OS-00074', 'regra', 2, 0, false, 'banco_cc'), ('OS-00069', 'regra', 2, 0, false, 'banco_cc'),
    ('OS-00112', 'regra', 2, 0, false, 'banco_cc'), ('OS-00130', 'regra', 2, 2, false, 'banco_cc,ca_energizado'),
    ('OS-00032', 'regra', 2, 2, false, 'ca_energizado,icamento'), ('OS-00033', 'regra', 2, 0, true, 'icamento,orcamento'),
    ('ORÇ-00095', 'regra', 2, 0, false, 'icamento'), ('ORÇ-00125', 'regra', 2, 2, false, 'banco_cc,ca_energizado'),
    ('ORÇ-00126', 'regra', 2, 2, false, 'banco_cc,ca_energizado'), ('OS-00104', 'nenhuma', 0, 0, false, ''),
    ('OS-00076', 'nenhuma', 0, 0, false, ''), ('OS-00096', 'nenhuma', 0, 0, false, ''), ('ORÇ-00083', 'nenhuma', 0, 0, false, ''),
    ('ORÇ-00119', 'nenhuma', 0, 0, false, ''), ('OS-97101', 'nenhuma', 0, 0, false, ''), ('OS-97002', 'dono', 0, 0, true, ''))
  select string_agg(format('%s: %s %s/%s/%s [%s]', c.numero, x.d ->> 'fonte', x.d ->> 'inicio', x.d ->> 'fim', x.d ->> 'todos',
                           (select string_agg(m ->> 'motivo', ',' order by m ->> 'motivo') from jsonb_array_elements(x.d -> 'motivos') m)), '; ')
         filter (where x.d ->> 'fonte' <> c.fonte or (x.d ->> 'inicio')::int <> c.ini or (x.d ->> 'fim')::int <> c.fim
                       or (x.d ->> 'todos')::boolean <> c.todos
                       or coalesce((select string_agg(m ->> 'motivo', ',' order by m ->> 'motivo') from jsonb_array_elements(x.d -> 'motivos') m), '') <> c.mots)
    into v_ruim
    from c cross join lateral (select public._agenda_dupla_da_os(pg_temp.os(c.numero)) as d) x;
  v_res := pg_temp.ok(v_res, 'M1a as 16 OS da tabela da §2: Lenine, Vanderlei e Nelson o banco de baterias nos 2 primeiros; Giancarlo e as ORÇ-00125/126 o banco e a 127/220 V (2 + 2); Kalmar-32 o gerador e o quadro AC; Kalmar-33 a parelha de motores e o orçamento com 2 técnicos (o tempo todo); ORÇ-00095 o gerador; os de 12 V, o Starlink da ORÇ-00119 e o diagnóstico sem nada; a dupla dita da OS-97002',
    v_ruim is null, coalesce(v_ruim, '—'));
  v_res := pg_temp.ok(v_res, 'M1b a linha que casou é o NOME do serviço (antes de " — "): o Lenine casa "SUBSTITUIÇÃO BATERIAS - CHUMBO PARA LITIO"; o Starlink "… alimentado pelo banco de baterias" da ORÇ-00119 não casa nada',
    (select string_agg(m ->> 'nome', ',') from jsonb_array_elements(public._agenda_dupla_da_os(pg_temp.os('OS-00074')) -> 'motivos') m)
      = 'SUBSTITUIÇÃO BATERIAS - CHUMBO PARA LITIO'
    and jsonb_array_length(public._agenda_dupla_da_os(pg_temp.os('ORÇ-00119')) -> 'motivos') = 0,
    (public._agenda_dupla_da_os(pg_temp.os('OS-00074')) -> 'motivos')::text);
  d := public._agenda_dupla_da_os(pg_temp.os('OS-97101'));
  v_res := pg_temp.ok(v_res, 'M1c a casa de máquinas vira só nota (nada muda): "Atenção: casa de máquinas — confira se precisa de duas pessoas."',
    d ->> 'fonte' = 'nenhuma' and d -> 'notas' -> 0 ->> 'texto' = 'Atenção: casa de máquinas — confira se precisa de duas pessoas.'
    and d ->> 'texto' = '1 pessoa.', d::text);
  v_res := pg_temp.ok(v_res, 'M1d os textos do cartão (§6.4): o início, o início e o fim, o tempo todo pelo orçamento, a dita',
    public._agenda_dupla_da_os(pg_temp.os('OS-00074')) ->> 'texto' = '1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha.'
    and public._agenda_dupla_da_os(pg_temp.os('OS-00130')) ->> 'texto'
        = '1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) e nos 2 últimos (ligação em 127/220 V) — suposição minha.'
    and public._agenda_dupla_da_os(pg_temp.os('OS-00033')) ->> 'texto' = 'Em dupla o tempo todo (o orçamento previu 2 técnicos) — suposição minha.'
    and public._agenda_dupla_da_os(pg_temp.os('OS-97002')) ->> 'texto' = 'Em dupla o tempo todo (você disse).',
    concat_ws(' | ', public._agenda_dupla_da_os(pg_temp.os('OS-00130')) ->> 'texto', public._agenda_dupla_da_os(pg_temp.os('OS-00033')) ->> 'texto'));
  begin
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 1, dupla_em = pg_temp.em(date '2026-11-05', '10:00')
     where service_order_id = pg_temp.os('OS-00069');
    d := public._agenda_dupla_da_os(pg_temp.os('OS-00069'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M1e a dita vence a regra: dupla no 1º meio-dia (você disse), sem os gatilhos',
    d ->> 'fonte' = 'dono' and (d ->> 'inicio')::int = 1 and jsonb_array_length(d -> 'motivos') = 0
    and d ->> 'texto' = 'Em dupla no primeiro meio-dia (você disse).', d::text);
  perform pg_temp.gravar(v_res);
end
$m1$;

-- ── M2. O molde com a dupla por meio-dia ───────────────────────────────────────────────────────────────────────
do $m2$
declare
  v_res  jsonb := '[]'::jsonb;
  v_len  uuid;
  v_van  uuid;
  v_k33  uuid;
  v_dif  text;
  a      jsonb;
  b      jsonb;
  c      jsonb;
  v_os   uuid;
begin
  if not pg_temp.carregada() or coalesce(current_setting('agenda_teste.mig_correcao2_fase7a', true), '') = '' then
    insert into _resultado values ('M2 (o molde)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  v_van := pg_temp.os('OS-00069');
  v_k33 := pg_temp.os('OS-00033');
  -- desligado: a carteira toda contra a definição de antes (rodada no lugar, numa subtransação desfeita)
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('desligado');
    select jsonb_object_agg(k.service_order_id::text, public.agenda_meios_da_os(k.service_order_id, date '2026-11-05')) into a
      from public.os_carteira(date '2026-11-05') k;
    execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao2_fase7a'), 'agenda_meios_da_os');
    select jsonb_object_agg(k.service_order_id::text, public.agenda_meios_da_os(k.service_order_id, date '2026-11-05')) into b
      from public.os_carteira(date '2026-11-05') k;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M2a com modo_dupla desligado, o molde de cada OS da carteira é o de antes, byte a byte (o gestor da 7a ligado)',
    a is not null and a = b and (select count(*) from jsonb_object_keys(a)) >= 15, format('%s OS; iguais: %s', (select count(*) from jsonb_object_keys(a)), a = b));
  begin
    perform pg_temp.gestor('desligado');
    perform pg_temp.modos7b('sombra');
    a := public.agenda_meios_da_os(v_len, date '2026-11-05');
    perform pg_temp.modos7b('desligado');
    b := public.agenda_meios_da_os(v_len, date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M2b em teste sem a regra uma_pessoa (2 pessoas por serviço: a dupla já está lá), o molde é o de desligado, sem dk',
    a = b and not a ? 'dk' and (a ->> 'pessoas_sugeridas')::int = 2, format('dk %s; pessoas %s', a ? 'dk', a ->> 'pessoas_sugeridas'));
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('sombra');
    a := public.agenda_meios_da_os(v_len, date '2026-11-05');
    perform pg_temp.modos7b('ligado');
    b := public.agenda_meios_da_os(v_len, date '2026-11-05');
    c := public.agenda_meios_da_os(v_van, date '2026-11-05') || jsonb_build_object('k33', public.agenda_meios_da_os(v_k33, date '2026-11-05'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M2c em teste com a regra uma_pessoa: o total de antes (Lenine 12 meios-dias) e dk com 2 nos 2 primeiros (a dupla só acrescenta: pm 14); dk_dono_conta (o dono só abre e fecha)',
    (a ->> 'total')::int = 12 and a -> 'dk' = '[2,2,1,1,1,1,1,1,1,1,1,1]'::jsonb and (a #>> '{dupla,pm}')::int = 14
    and (a ->> 'dk_dono_conta')::boolean and a #>> '{dupla,fonte}' = 'regra',
    format('total %s dk %s pm %s', a ->> 'total', a -> 'dk', a #>> '{dupla,pm}'));
  v_res := pg_temp.ok(v_res, 'M2d ligado: as diárias-pessoa conservadas — Lenine 12 → 10 meios-dias (2 em dupla + 8), Vanderlei 15 → 13; pm = 12 e 15; o por_turno de antes (1)',
    (b ->> 'total')::int = 10 and b -> 'dk' = '[2,2,1,1,1,1,1,1,1,1]'::jsonb and (b #>> '{dupla,pm}')::int = 12
    and (c ->> 'total')::int = 13 and (c #>> '{dupla,pm}')::int = 15 and (b #>> '{por_turno,manha,desejado}')::int = 1,
    format('Lenine total %s pm %s; Vanderlei total %s pm %s', b ->> 'total', b #>> '{dupla,pm}', c ->> 'total', c #>> '{dupla,pm}'));
  v_res := pg_temp.ok(v_res, 'M2e ligado, a Kalmar-33 (o orçamento previu 2 técnicos): o tempo todo em dupla (dk só 2) e o total = metade das diárias-pessoa',
    (select bool_and(x::int = 2) from jsonb_array_elements_text(c #> '{k33,dk}') x) and c #>> '{k33,dupla,todos}' = 'true'
    and (c #>> '{k33,dupla,pm}')::int = 2 * (c #>> '{k33,total}')::int,
    format('total %s pm %s dk %s', c #>> '{k33,total}', c #>> '{k33,dupla,pm}', c #> '{k33,dk}'));
  begin
    perform pg_temp.gestor('desligado');
    perform pg_temp.modos7b('ligado');
    a := public.os_duracao_sugerida(v_len);
    b := public.agenda_meios_da_os(v_len, date '2026-11-05');
    perform pg_temp.modos7b('sombra');
    c := public.os_duracao_sugerida(v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M2f com a dupla ligada e sem a regra uma_pessoa do 7a, a duração é de 1 pessoa (a dupla vem por meio-dia: Lenine 10 meios-dias, 2 em dupla); em teste, a de antes (2 pessoas)',
    (a ->> 'pessoas')::int = 1 and (b ->> 'total')::int = 10 and b -> 'dk' = '[2,2,1,1,1,1,1,1,1,1]'::jsonb and (c ->> 'pessoas')::int = 2,
    concat_ws(' | ', a ->> 'pessoas', b ->> 'total', b -> 'dk', c ->> 'pessoas'));
  perform pg_temp.gravar(v_res);
end
$m2$;

-- ── M3. O motor com a dupla inferida ───────────────────────────────────────────────────────────────────────────
do $m3$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_p   jsonb;
  v_i   jsonb;
  v_t   text;
  v_t2  text;
  v_t3  text;
  v_n   int;
  x     jsonb;
  y     jsonb;
  z     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M3 (a dupla inferida no motor)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  -- M3a só o Alex
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    v_p := pg_temp.propor(array[v_len]);
    v_i := pg_temp.item(v_p, v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M3a só o Alex, ligado: o Lenine vai com o Alex nos 12 meios-dias (a duração de 1 pessoa, não 10), dupla_falta = os 2 primeiros, o texto diz quando chamar um ajudante; nenhuma pergunta nasce',
    pg_temp.meios(v_i) = '10/11 m Alex; 10/11 t Alex; 11/11 m Alex; 11/11 t Alex; 12/11 m Alex; 12/11 t Alex; 13/11 m Alex; 13/11 t Alex; 16/11 m Alex; 16/11 t Alex; 17/11 m Alex; 17/11 t Alex'
    and v_i -> 'dupla_falta' = '[{"dia": "2026-11-10", "onde": "inicio", "turno": "manha"}, {"dia": "2026-11-10", "onde": "inicio", "turno": "tarde"}]'::jsonb
    and v_i ->> 'texto' = 'Lenine (OS-00074): ter 10 a ter 17/11, você abre e fecha, Alex os 6 dias (estimativa minha: 6 dias). Nos 2 primeiros meios-dias (ter 10/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem ter 10/11).'
    and v_i ->> 'dupla' = '1 pessoa; em dupla nos 2 primeiros meios-dias (troca do banco de baterias) — suposição minha.'
    and jsonb_array_length(v_p -> 'perguntas') = 0 and jsonb_array_length(v_p -> 'fora') = 0,
    concat_ws(' | ', pg_temp.meios(v_i), v_i ->> 'texto', v_i -> 'dupla_falta'));
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('sombra');
    perform pg_temp.so_alex();
    v_p := pg_temp.propor(array[v_len]);
    x := pg_temp.item(v_p, v_len);
    perform pg_temp.modos7b('desligado');
    y := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M3a2 em teste, o plano é o de antes (os mesmos meios-dias e o mesmo texto de desligado) e a linha "Em teste" diz em que meio-dia eu pediria um ajudante (textos.em_teste e o fim do texto)',
    pg_temp.meios(x) = pg_temp.meios(y) and x ->> 'texto' = y ->> 'texto'
    and v_p #> '{textos,em_teste}' = '["Em teste: no Lenine eu pediria um ajudante em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas."]'::jsonb
    and v_p ->> 'texto' like '%' || E'
' || 'Em teste: no Lenine eu pediria um ajudante em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas.',
    concat_ws(' | ', (v_p #> '{textos,em_teste}')::text, x ->> 'texto'));
  -- M3b o Mateus dito nos dias
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']);
    v_p := pg_temp.propor(array[v_len]);
    v_i := pg_temp.item(v_p, v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M3b o Mateus dito qua e qui: Alex e Mateus nos 2 primeiros meios-dias (qua 11/11), o Alex no resto — 10 meios-dias, as mesmas 12 diárias-pessoa; sem dupla_falta nem o texto do ajudante',
    pg_temp.meios(v_i) = '11/11 m Alex+Mateus; 11/11 t Alex+Mateus; 12/11 m Alex; 12/11 t Alex; 13/11 m Alex; 13/11 t Alex; 16/11 m Alex; 16/11 t Alex; 17/11 m Alex; 17/11 t Alex'
    and not v_i ? 'dupla_falta' and v_i ->> 'texto' like '%Alex os 5 dias, Mateus (qua 11/11) (estimativa minha: 6 dias).',
    concat_ws(' | ', pg_temp.meios(v_i), v_i ->> 'texto'));
  -- M3c o Mateus nunca sozinho
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']);
    perform pg_temp.nao_vem('Alex', date '2026-11-11', date '2026-11-12');
    v_p := pg_temp.propor(array[v_len]);
    v_i := pg_temp.item(v_p, v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M3c com o Alex fora nos dias do Mateus, o Mateus nunca fica sozinho num meio-dia (os dias dele viram lacuna) e o Lenine vai com o Alex depois, com a sugestão na forma curta (a inteira passaria de 320 letras no item: a ação junta os itens da OS e vai até 400)',
    pg_temp.meios(v_i) not like '%Mateus%' and pg_temp.meios(v_i) like '13/11 m Alex%'
    and v_i ->> 'texto' = 'Lenine (OS-00074): sex 13, seg 16, ter 17, qua 18, seg 23 e ter 24/11, você abre e fecha, Alex os 6 dias (estimativa minha: 6 dias). Nos 2 primeiros meios-dias a troca do banco de baterias pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
    concat_ws(' | ', pg_temp.meios(v_i), v_i ->> 'texto'));
  -- M3d a espera: o bloco de 1 pessoa termina ter 17/11; a dupla com o Mateus na seg 16 termina ter 24 (4 dias úteis depois); com ele na
  -- qui 19, termina qui 26 (6 dias úteis depois); com o prazo firme ter 17/11, a dupla da seg 16 passa do prazo e o de 1 pessoa cumpre
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.vem('Mateus', array[date '2026-11-16']);
    x := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.vem('Mateus', array[date '2026-11-19']);
    y := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    perform pg_temp.vem('Mateus', array[date '2026-11-16']);
    update public.os_planejamento set precisa_ate = date '2026-11-17' where service_order_id = v_len;
    z := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M3d a espera da dupla (dupla_espera_max_du 5): 4 dias úteis depois do de 1 pessoa, a dupla vence (Mateus na seg 16, até ter 24: o teto da equipe na semana do feriado empurra a qui 19); 6 dias úteis depois, vale o de 1 pessoa (até ter 17) com a sugestão; com o prazo firme ter 17/11, a dupla da seg 16 passaria do prazo e vale o de 1 pessoa',
    pg_temp.meios(x) like '16/11 m Alex+Mateus; 16/11 t Alex+Mateus; %' and x ->> 'ate' = '2026-11-24' and not x ? 'dupla_falta'
    and pg_temp.meios(y) not like '%Mateus%' and y ->> 'ate' = '2026-11-17' and y ? 'dupla_falta'
    and pg_temp.meios(z) not like '%Mateus%' and z ->> 'ate' = '2026-11-17' and z ? 'dupla_falta',
    concat_ws(' | ', x ->> 'ate', pg_temp.meios(x), y ->> 'ate', z ->> 'ate'));
  -- M3e a revisão do dia seguinte (16:53 da sex 06/11, a revisão diária ligada): nada cortado nem faltando
  v_t := '';
  for x in select jsonb_build_object('modo', m, 'mateus', mt) from unnest(array['ligado', 'sombra']) m, unnest(array['nenhum', 'qua', 'ter']) mt loop
    continue when x ->> 'modo' = 'ligado' and x ->> 'mateus' = 'ter';
    begin
      perform pg_temp.gestor('ligado');
      perform pg_temp.modos7b(x ->> 'modo');
      perform pg_temp.so_alex();
      if x ->> 'mateus' = 'qua' then perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']); end if;
      -- (com o Mateus de seg 09 a qua 11, o teto da equipe na semana tem folga para a 2ª pessoa: a dupla termina junto do bloco de 1
      -- pessoa e, em teste, entra; com menos folga, em teste fica o de 1 pessoa — a dupla só acrescenta quando não atrasa)
      if x ->> 'mateus' = 'ter' then perform pg_temp.vem('Mateus', array[date '2026-11-09', date '2026-11-10', date '2026-11-11']); end if;
      perform pg_temp.marcar(array[v_len]);
      v_t2 := pg_temp.vivas(v_len);
      y := public._agenda_gestor_pessoa_meios(v_len, date '2026-11-06', public.agenda_meios_da_os(v_len, date '2026-11-06'));
      z := public._agenda_gestor_revisao(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
      v_t := v_t || format('[%s %s: %s; tem %s precisa %s; cortes %s faltando %s; depois %s] ', x ->> 'modo', x ->> 'mateus',
                           (select count(*) from public.agenda_alocacoes a where a.service_order_id = v_len and a.estado in ('publicada', 'fixada')
                              and a.tipo <> 'reserva' and a.presenca = 'turno'),
                           y ->> 'tem', y ->> 'precisa',
                           (select count(*) from jsonb_array_elements(coalesce(z #> '{reestimar,cortes}', '[]'::jsonb)) e where (e ->> 'os')::uuid = v_len),
                           (select count(*) from jsonb_array_elements(coalesce(z #> '{reestimar,faltando}', '[]'::jsonb)) e where (e ->> 'os')::uuid = v_len),
                           case when pg_temp.vivas(v_len) = v_t2 then 'igual' else 'mudou' end);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'M3e a revisão do dia seguinte não corta nem acrescenta: ligado, o bloco de 1 pessoa (12) e o em dupla com o Mateus (2 × 2 + 8 = 12) têm o que a estimativa pede (12); em teste, o de 1 pessoa (12) e a dupla acrescentada com o Mateus na seg 09 (2 × 2 + 10 = 14) ficam',
    v_t = '[ligado nenhum: 12; tem 12 precisa 12; cortes 0 faltando 0; depois igual] [ligado qua: 12; tem 12 precisa 12; cortes 0 faltando 0; depois igual] [sombra nenhum: 12; tem 12 precisa 12; cortes 0 faltando 0; depois igual] [sombra qua: 12; tem 12 precisa 12; cortes 0 faltando 0; depois igual] [sombra ter: 14; tem 14 precisa 14; cortes 0 faltando 0; depois igual] ',
    v_t);
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('desligado');
    perform pg_temp.so_alex();
    perform pg_temp.marcar(array[v_len]);
    y := public._agenda_gestor_pessoa_meios(v_len, date '2026-11-06', public.agenda_meios_da_os(v_len, date '2026-11-06'));
    execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7a'), '_agenda_gestor_pessoa_meios');
    z := public._agenda_gestor_pessoa_meios(v_len, date '2026-11-06', public.agenda_meios_da_os(v_len, date '2026-11-06'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M3e2 sem dk (modo_dupla desligado), a conta da revisão é a de antes, byte a byte', y = z and y is not null,
    concat_ws(' × ', y::text, z::text));
  perform pg_temp.gravar(v_res);
end
$m3$;

-- ── M4. O novato e quem vem sob demanda ────────────────────────────────────────────────────────────────────────
do $m4$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_i   jsonb;
  v_j   jsonb;
  v_n   boolean;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M4 (o novato)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  v_res := pg_temp.ok(v_res, 'M4a _agenda_e_novato: o Bruno (perfil desde 20/10, 3 diárias) é novato; o Rafael (perfil desde 01/09) não; o Alex (sem perfil) e o dono nunca',
    public._agenda_e_novato(pg_temp.pessoa('Bruno'), date '2026-11-05') and not public._agenda_e_novato(pg_temp.pessoa('Rafael'), date '2026-11-05')
    and not public._agenda_e_novato(pg_temp.pessoa('Alex'), date '2026-11-05')
    and not public._agenda_e_novato(public._agenda_dono(null), date '2026-11-05')
    and not public._agenda_e_novato(pg_temp.pessoa('Bruno'), date '2026-12-01'),
    null);
  begin
    perform pg_temp.vem('Mateus', array[date '2026-11-11']);
    v_n := public._agenda_e_sob_demanda(pg_temp.pessoa('Mateus'), date '2026-11-05') and public._agenda_e_sob_demanda(pg_temp.pessoa('Bruno'), date '2026-11-05')
           and not public._agenda_e_sob_demanda(pg_temp.pessoa('Rafael'), date '2026-11-05')
           and not public._agenda_e_sob_demanda(pg_temp.pessoa('Alex'), date '2026-11-05')
           and not public._agenda_e_sob_demanda(pg_temp.pessoa('Roberto'), date '2026-11-05')
           and not public._agenda_e_sob_demanda(public._agenda_dono(null), date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M4b _agenda_e_sob_demanda: o Mateus com datas e o Bruno (só a data dita) vêm sob demanda; o Rafael e o Alex têm dias fixos; o Roberto saiu (fora da grade) e o dono nunca',
    v_n and not public._agenda_e_sob_demanda(pg_temp.pessoa('Mateus'), date '2026-11-05'), null);
  -- o Bruno (novato, só ter 10/11) e o Alex: com o Alex livre na ter 10, o Bruno só entra junto dele; com o Alex fora na ter 10, o
  -- Bruno não fica sozinho (a ter 10 é lacuna)
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-05 10:00-03'
     where substituida_em is null and payee_id = pg_temp.pessoa('Rafael');
    v_i := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
    perform pg_temp.nao_vem('Alex', date '2026-11-10', date '2026-11-10');
    v_j := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M4c o Bruno (novato) nunca sozinho: na ter 10 ele vai junto do Alex (a dupla do banco de baterias); com o Alex fora na ter 10, o Bruno não entra sozinho e o Lenine começa depois',
    pg_temp.meios(v_i) like '10/11 m Alex+Bruno; 10/11 t Alex+Bruno; 11/11 m Alex;%'
    and pg_temp.meios(v_j) not like '%Bruno%' and pg_temp.meios(v_j) not like '10/11%',
    concat_ws(' | ', pg_temp.meios(v_i), pg_temp.meios(v_j)));
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('desligado');
    update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-05 10:00-03'
     where substituida_em is null and payee_id = pg_temp.pessoa('Rafael');
    perform pg_temp.nao_vem('Alex', date '2026-11-10', date '2026-11-10');
    v_i := public._agenda_contexto(date '2026-11-02', date '2026-11-15', date '2026-11-05');
    perform pg_temp.modos7b('sombra');
    v_j := public._agenda_contexto(date '2026-11-02', date '2026-11-15', date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M4d o contexto só marca quem nunca fica sozinho (novato) com modo_dupla fora de desligado: desligado, nenhuma chave nova; em teste, o Bruno',
    not v_i ? 'novato' and not v_i ? 'sab' and not v_i ? 'dono_tec'
    and (select array_agg(v_j -> 'nomes' ->> (x::int - 1)) from jsonb_array_elements_text(v_j -> 'novato') x) = array['Bruno'],
    concat_ws(' | ', v_j -> 'novato', v_j -> 'nomes'));
  perform pg_temp.gravar(v_res);
end
$m4$;

-- ── M5. O dono técnico e o teto do dono ────────────────────────────────────────────────────────────────────────
do $m5$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_i   jsonb;
  v_j   jsonb;
  v_c   jsonb;
  v_t   text := '';
  v_dono uuid;
  v_k   int;
  m     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M5 (o dono)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  v_dono := public._agenda_dono(null);
  -- a linha do dono (seg a sex, origem dono) e o Alex fora na qua 11: sem o dono técnico, o Lenine para na qua 11 (a interrupção);
  -- com ele, o dono faz a qua 11 e o serviço acaba antes
  begin
    perform set_config('agenda_teste.fase7b_dono', 'campo', true);
    execute current_setting('agenda_teste.fase7b');
    perform set_config('agenda_teste.fase7b_dono', '', true);
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('sombra');
    update public.agenda_config set modo_dupla = 'desligado' where id;
    perform pg_temp.so_alex();
    perform pg_temp.nao_vem('Alex', date '2026-11-11', date '2026-11-11');
    v_i := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
    update public.agenda_config set dono_como_tecnico = true where id;
    v_j := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M5a sem dono_como_tecnico, o dono nunca numa vaga (a qua 11 sem o Alex fica parada); com ele, o dono entra por último na qua 11 (os 2 meios-dias, nos dias de campo dele) e o Lenine acaba antes',
    pg_temp.meios(v_i) not like '%Gustavo%' and pg_temp.meios(v_i) not like '%11/11%'
    and pg_temp.meios(v_j) like '%11/11 m Gustavo; 11/11 t Gustavo;%' and (v_j ->> 'ate')::date < (v_i ->> 'ate')::date,
    concat_ws(' | ', v_i ->> 'ate', pg_temp.meios(v_i), v_j ->> 'ate', pg_temp.meios(v_j)));
  -- M5b o teto do dono com a linha (10 meios-dias esperados na semana de 09/11): o teto80 dele no contexto
  begin
    perform set_config('agenda_teste.fase7b_dono', 'campo', true);
    execute current_setting('agenda_teste.fase7b');
    perform set_config('agenda_teste.fase7b_dono', '', true);
    perform pg_temp.gestor('desligado');
    foreach m in array array['sombra', 'ligado', 'desligado'] loop
      update public.agenda_config set modo_dias = m where id;
      v_c := public._agenda_contexto(date '2026-11-09', date '2026-11-15', date '2026-11-05');
      v_k := array_position(array(select x from jsonb_array_elements_text(v_c -> 'pessoas') x), v_dono::text);
      v_t := v_t || format('%s %s %s; ', m, public._agenda_carga_da_pessoa(v_dono), v_c -> 'teto80' -> ((v_k - 1) * (v_c ->> 'nw')::int));
    end loop;
    -- o aprendido acima de 0,50 (0,70) em uso não passa da metade; o abaixo (0,40) vale
    update public.agenda_config set modo_dias = 'sombra', modo_aprendizado = 'ligado',
           aprendizado_ligados = (select array_agg(distinct x) from unnest(aprendizado_ligados || array['capacidade_dono']) x) where id;
    -- FASE 7b: (correção da revisão da 7b, achado 14) a meia capacidade (e o aprendido que não passa dela) só com modo_dias ligado:
    -- em teste o teto do dono é o de antes (a linha de cima, de antes, põe sombra)
    update public.agenda_config set modo_dias = 'ligado' where id;
    -- FASE 7b: fim
    insert into public.agenda_aprendizado (item, chave, nivel, padrao, em_uso, n_min, estado, calculado_em, em_uso_desde)
    values ('capacidade_dono', 'dono', 'dono', 0.80, 0.70, 4, 'em_uso', now(), now())
    on conflict (item, chave) do update set em_uso = 0.70, estado = 'em_uso', em_uso_desde = now(), travado_ate = null;
    v_t := v_t || format('aprendido 0,70: %s; ', public._agenda_carga_da_pessoa(v_dono));
    update public.agenda_aprendizado set em_uso = 0.40 where item = 'capacidade_dono' and chave = 'dono';
    v_t := v_t || format('aprendido 0,40: %s', public._agenda_carga_da_pessoa(v_dono));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- FASE 7b: (correção da revisão da 7b, achado 14) em teste (sombra) o teto do dono é o de antes (0,80: 8); a meia capacidade só ligado
  v_res := pg_temp.ok(v_res, 'M5b o teto do dono com a linha: com modo_dias ligado, meia capacidade (0,50: 5 meios-dias de turno na semana); em teste e desligado, o de antes (0,80: 8); ligado, o aprendido acima de 0,50 não passa, o abaixo vale',
    v_t = 'sombra 0.80 8; ligado 0.50 5; desligado 0.80 8; aprendido 0,70: 0.50; aprendido 0,40: 0.40', v_t);
  -- FASE 7b: fim
  perform pg_temp.gravar(v_res);
end
$m5$;

-- ── M6 e M7. O sábado de manhã e o validador ───────────────────────────────────────────────────────────────────
-- O Vanderlei (o material chega para qua 18/11) com 3,5 dias ditos e o prazo firme seg 23/11; só o Rafael, que se ofereceu para o
-- sáb 21/11 de manhã (a semana dita de 16/11). Sem o sábado: qua 18, qui 19 (sex 20 é feriado), seg 23 e ter 24 de manhã — passa do
-- prazo. Com o sábado: qua 18, qui 19, sáb 21 de manhã e seg 23 — no prazo.
create function pg_temp.cena_sabado(p_turno text default 'manha') returns void language plpgsql as $f$
begin
  perform pg_temp.gestor('ligado');
  update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-05 10:00-03'
   where substituida_em is null and payee_id in (select id from public.payees where name in ('Alex', 'Bruno'));
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em, semana_dita)
  select p.id, daterange(date '2026-11-21', date '2026-11-21', '[]'), p_turno, 'disponivel', 'diarista', 'Disse que pode (semana de 16/11)',
         timestamptz '2026-11-05 10:00-03', date '2026-11-16'
    from public.payees p where p.name = 'Rafael';
  update public.os_planejamento set dias = 3.5, estimativa_fonte = 'dono', precisa_ate = date '2026-11-23'
   where service_order_id = pg_temp.os('OS-00069');
end $f$;
do $m6$
declare
  v_res jsonb := '[]'::jsonb;
  v_van uuid;
  v_t   text := '';
  v_p   jsonb;
  v_i   jsonb;
  v_lig jsonb;
  v_som jsonb;
  m     text[];
  v_v1  jsonb;
  v_v2  jsonb;
  v_it  jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M6 (o sábado)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_van := pg_temp.os('OS-00069');
  for m in select array[a, b] from (values ('ligado', 'so_prazo'), ('sombra', 'so_prazo'), ('desligado', 'so_prazo'), ('ligado', 'nunca'),
                                           ('ligado', 'sem_prazo'), ('ligado', 'dia_todo')) t(a, b) loop
    begin
      perform pg_temp.cena_sabado(case when m[2] = 'dia_todo' then null end);
      update public.agenda_config set modo_sabado = m[1], sabado_manha = case when m[2] in ('sem_prazo', 'dia_todo') then 'so_prazo' else m[2] end where id;
      if m[2] = 'sem_prazo' then
        update public.os_planejamento set precisa_ate = null where service_order_id = v_van;
      end if;
      v_p := pg_temp.propor(array[v_van]);
      v_i := pg_temp.item(v_p, v_van);
      if m[1] = 'ligado' and m[2] = 'so_prazo' then v_lig := v_p; end if;
      if m[1] = 'sombra' then v_som := v_p; end if;
      v_t := v_t || format('[%s %s: %s; fora %s] ', m[1], m[2], coalesce(pg_temp.meios(v_i), '-'),
                           (select string_agg(f ->> 'motivo', ',') from jsonb_array_elements(v_p -> 'fora') f));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'M6a o sábado de manhã: so_prazo + ligado = o Vanderlei com sáb 21/11 de manhã (o Rafael, que se ofereceu) e no prazo; em teste, desligado e "nunca" = sem sábado (o "não cabe" de antes); sem prazo firme = sem sábado; oferecido o dia todo, só a manhã (nunca à tarde); nunca o 1º passo (o bloco começa na qua 18)',
    v_t = '[ligado so_prazo: 18/11 m Rafael; 18/11 t Rafael; 19/11 m Rafael; 19/11 t Rafael; 21/11 m Rafael; 23/11 m Rafael; 23/11 t Rafael; fora ] '
          || '[sombra so_prazo: -; fora nao_cabe] [desligado so_prazo: -; fora nao_cabe] [ligado nunca: -; fora nao_cabe] '
          || '[ligado sem_prazo: 18/11 m Rafael; 18/11 t Rafael; 19/11 m Rafael; 19/11 t Rafael; 23/11 m Rafael; 23/11 t Rafael; 24/11 m Rafael; fora ] '
          || '[ligado dia_todo: 18/11 m Rafael; 18/11 t Rafael; 19/11 m Rafael; 19/11 t Rafael; 21/11 m Rafael; 23/11 m Rafael; 23/11 t Rafael; fora ] ',
    v_t);
  v_i := pg_temp.item(v_lig, v_van);
  v_res := pg_temp.ok(v_res, 'M6b o texto da marcação com o sábado (§6.3): "… — com sáb 21/11 de manhã (Rafael se ofereceu), para cumprir o prazo de seg 23/11."; o item leva sabado',
    v_i ->> 'texto' like '% — com sáb 21/11 de manhã (Rafael se ofereceu), para cumprir o prazo de seg 23/11.' and (v_i ->> 'sabado')::boolean,
    v_i ->> 'texto');
  v_res := pg_temp.ok(v_res, 'M6c em teste: nenhuma alocação no sábado e a linha "Em teste" (textos.em_teste e no fim do texto)',
    v_som #> '{textos,em_teste}' = '["Em teste: para cumprir o prazo de Vanderlei (seg 23/11), eu usaria sáb 21/11 de manhã com Rafael, que se ofereceu."]'::jsonb
    and v_som ->> 'texto' like '%Em teste: para cumprir o prazo de Vanderlei (seg 23/11), eu usaria sáb 21/11 de manhã com Rafael, que se ofereceu.%'
    and not exists (select 1 from jsonb_array_elements(v_som -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                     where extract(isodow from (a ->> 'dia')::date) = 6),
    (v_som #> '{textos,em_teste}')::text);
  -- M6d o sábado com a dupla inferida (o banco de baterias do Vanderlei) e só o Rafael: o bloco de 1 pessoa (os 3,5 dias ditos, sem a
  -- conservação) com a manhã de sábado; os meios-dias que pediam 2 são os deste bloco
  begin
    perform pg_temp.cena_sabado();
    perform pg_temp.modos7b('ligado');
    v_p := pg_temp.propor(array[v_van]);
    v_i := pg_temp.item(v_p, v_van);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M6d o sábado com a dupla inferida de 1 pessoa: os mesmos meios-dias do M6a (os 3,5 dias ditos, sem a conservação), dupla_falta nos 2 primeiros (qua 18/11) e o texto com o sábado e o ajudante (a forma curta)',
    pg_temp.meios(v_i) = '18/11 m Rafael; 18/11 t Rafael; 19/11 m Rafael; 19/11 t Rafael; 21/11 m Rafael; 23/11 m Rafael; 23/11 t Rafael'
    and v_i -> 'dupla_falta' = '[{"dia": "2026-11-18", "onde": "inicio", "turno": "manha"}, {"dia": "2026-11-18", "onde": "inicio", "turno": "tarde"}]'::jsonb
    and v_i ->> 'texto' = 'Vanderlei (OS-00069): qua 18, qui 19, sáb 21 e seg 23/11, você abre e fecha, Rafael os 4 dias — com sáb 21/11 de manhã (Rafael se ofereceu), para cumprir o prazo de seg 23/11. Nos 2 primeiros meios-dias a troca do banco de baterias pede 2 pessoas: se chamar um ajudante, me diga os dias dele.',
    concat_ws(' | ', pg_temp.meios(v_i), v_i -> 'dupla_falta', v_i ->> 'texto'));
  -- M7 o validador: o item com o sábado (o da proposta ligada) com o Rafael na semana de 16/11 acima do teto sem o sábado
  v_it := (select jsonb_agg(i) from jsonb_array_elements(v_lig -> 'itens') i where i ->> 'op' = 'criar');
  begin
    perform pg_temp.cena_sabado();
    update public.agenda_config set modo_sabado = 'ligado' where id;
    -- o Rafael já tem 2 meios-dias de compromisso na seg 16 (a equipe fica com 2 + 5 = 7: acima do teto da semana do feriado, 6, sem o
    -- sábado; no teto, 7, com a manhã de sábado que ele ofereceu)
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select pg_temp.os('OS-00112'), pg_temp.pessoa('Rafael'), d, t, 'turno', 'execucao', 'publicada', 'motor', now()
      from (values (date '2026-11-16', 'manha'), (date '2026-11-16', 'tarde')) x(d, t);
    v_v1 := public._agenda_validar_itens(v_it, '{}'::jsonb, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    update public.agenda_config set modo_sabado = 'sombra' where id;
    v_v2 := public._agenda_validar_itens(v_it, '{}'::jsonb, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M7 o validador: a proposta com o sábado sai válida (a regra 13 não conta o sábado nem o feriado como dia parado); com o Rafael perto do teto, a manhã de sábado que ele ofereceu soma 1 ao teto dele e ao da equipe (ligado) — em teste, a regra 6 de antes acusa',
    jsonb_array_length(v_lig -> 'itens') > 0 and v_v1 = '[]'::jsonb
    and v_v2 = '[{"dia": "2026-11-16", "regra": 6, "texto": "A equipe passaria do limite da semana de 16/11: 7 meios-dias de serviço para 6.", "pessoa": null}]'::jsonb,
    concat_ws(' | ', v_v1::text, v_v2::text));
  perform pg_temp.gravar(v_res);
end
$m6$;

-- ── M8. As cópias ────────────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  f      record;
  v_mig  text;
  v_novo text;
  v_n    int;
begin
  -- FASE 7b: (correção da revisão da 7b) a correção 20261101100800 recria _agenda_carga_da_pessoa (+1 bloco), _agenda_contexto (+1) e
  -- agenda_propor (+1; os outros 2 ficam dentro de blocos da 7b, com a marca de dentro, e saem junto com eles); os blocos dela de
  -- fora também são "-- FASE 7b:" (tirados todos, o corpo de antes da 7b)
  -- FASE 7b: fim
  for f in select * from (values
      ('os_duracao_sugerida', 'public.os_duracao_sugerida(uuid)', 'mig_correcao_fase7a', '20261031100980', 1),
      ('agenda_meios_da_os', 'public.agenda_meios_da_os(uuid, date)', 'mig_correcao2_fase7a', '20261031100985', 3),
      ('_agenda_classe_da_os', 'public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', 'mig_correcao2_fase7a', '20261031100985', 2),
      ('_agenda_tecnicos_da_grade', 'public._agenda_tecnicos_da_grade(date)', 'mig_correcao2_fase7a', '20261031100985', 1),
      ('_agenda_carga_da_pessoa', 'public._agenda_carga_da_pessoa(uuid)', 'mig_dono_fase6', '20261029100400', 2),
      -- FASE 7b: (correção 2 da 7b, achado 26) + os 2 blocos de cima da 20261101100850 (também "-- FASE 7b:"; o de dentro sai com o do P4)
      ('_agenda_gestor_pessoa_meios', 'public._agenda_gestor_pessoa_meios(uuid, date, jsonb)', 'mig_correcao_fase7a', '20261031100980', 3),
      -- FASE 7b: fim
      ('_agenda_contexto', 'public._agenda_contexto(date, date, date, uuid[], uuid[])', 'mig_teto_fase7a', '20261031100400', 6),
      ('_agenda_tentar_bloco', 'public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)', 'mig_teto_fase7a', '20261031100400', 10),
      ('_agenda_melhor', 'public._agenda_melhor(jsonb, jsonb)', 'mig_motor_fase2', '20261025100200', 1),
      ('_agenda_encaixar', 'public._agenda_encaixar(jsonb, jsonb, jsonb)', 'mig_teto_fase7a', '20261031100400', 9),
      ('_agenda_validar_itens', 'public._agenda_validar_itens(jsonb, jsonb, date, timestamptz, boolean, jsonb)', 'mig_sinal_sabado_fase7a', '20261031100900', 4),
      ('agenda_propor', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'mig_encaixe_fase7a', '20261031100700', 8),
      ('_agenda_gestor_sabado', 'public._agenda_gestor_sabado(date, timestamptz)', 'mig_sinal_sabado_fase7a', '20261031100900', 1))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('M8 %s: a cópia', f.nome), true, format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    v_novo := pg_temp.sem_7c(v_novo);  -- FASE 7c: (7c P2) os blocos da 20261102100100 saem antes
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7b: fim', 'g');
    insert into _resultado values (
      format('M8 %s: sem os %s blocos "-- FASE 7b:", é o corpo de %s', f.nome, f.blocos, f.versao),
      pg_temp.corpo(v_mig, f.nome) <> '' and pg_temp.sem_7b(v_novo) = pg_temp.corpo(v_mig, f.nome) and v_n = f.blocos,
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(v_mig, f.nome)), length(pg_temp.sem_7b(v_novo))));
  end loop;
end
$copia$;

-- ── M9. Com os 5 modos da 7b desligados, byte a byte ───────────────────────────────────────────────────────────
create function pg_temp.conta_m9() returns text language plpgsql as $f$
declare
  v_cart uuid[] := array(select k.service_order_id from public.os_carteira(date '2026-11-05') k order by 1);
  v      text;
begin
  -- FASE 7c: (7c P2) sem o critério das alocações e sem hab/habf/custo no contexto (pg_temp.sem_criterio, acima)
  -- FASE 7c: fim
  select md5(pg_temp.sem_criterio(public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, date '2026-11-05',
                                  pg_temp.em(date '2026-11-05', '16:45')))::text)
         || md5(pg_temp.sem_criterio(public.agenda_propor('os', null, null, v_cart, '{}'::jsonb, false, 'vigia', null, date '2026-11-05',
                                     pg_temp.em(date '2026-11-05', '16:45')))::text)
         || md5((public._agenda_contexto(date '2026-11-02', date '2026-11-22', date '2026-11-05') - 'hab' - 'habf' - 'custo')::text)
         || md5(coalesce((select jsonb_agg(public.agenda_meios_da_os(x, date '2026-11-05') order by x) from unnest(v_cart) x), '[]'::jsonb)::text)
         || md5(coalesce((select jsonb_agg(public._agenda_classe_agora(x, date '2026-11-05') - 'pront' order by x) from unnest(v_cart) x), '[]'::jsonb)::text)
         || md5(public._agenda_carga_da_pessoa(public._agenda_dono(null))::text)
    into v;
  return v;
end $f$;
do $m9$
declare
  v_res  jsonb := '[]'::jsonb;
  c      record;
  v_novo text;
  v_antes text;
  v_dif  text;
  v_n    int := 0;
begin
  if not pg_temp.carregada() or coalesce(current_setting('agenda_teste.mig_encaixe_fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_teto_fase7a', true), '') = '' then
    insert into _resultado values ('M9 (os modos desligados)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  for c in select * from (values ('gestor desligado', 'desligado', false), ('gestor ligado', 'ligado', false),
                                 ('gestor ligado, a linha do dono e o Mateus com datas', 'ligado', true)) t(nome, gestor, mais) loop
    begin
      perform pg_temp.gestor(c.gestor);
      perform pg_temp.modos7b('desligado');
      update public.agenda_config set dono_como_tecnico = true where id;   -- sem modo_dias, não vale
      if c.mais then
        perform set_config('agenda_teste.fase7b_dono', 'campo', true);
        execute current_setting('agenda_teste.fase7b');
        perform set_config('agenda_teste.fase7b_dono', '', true);
        perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']);
      end if;
      v_novo := pg_temp.conta_m9();
      execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7a'), 'os_duracao_sugerida');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7a'), '_agenda_gestor_pessoa_meios');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao2_fase7a'), 'agenda_meios_da_os');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao2_fase7a'), '_agenda_classe_da_os');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao2_fase7a'), '_agenda_tecnicos_da_grade');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_dono_fase6'), '_agenda_carga_da_pessoa');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_teto_fase7a'), '_agenda_contexto');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_teto_fase7a'), '_agenda_tentar_bloco');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_teto_fase7a'), '_agenda_encaixar');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase2'), '_agenda_melhor');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_sinal_sabado_fase7a'), '_agenda_validar_itens');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_sinal_sabado_fase7a'), '_agenda_gestor_sabado');
      execute pg_temp.inteira(current_setting('agenda_teste.mig_encaixe_fase7a'), 'agenda_propor');
      v_n := (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%-- FASE 7b: (7b P4%');
      v_antes := pg_temp.conta_m9();
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    if v_novo is distinct from v_antes or v_n <> 0 then v_dif := concat_ws('; ', v_dif, format('%s (%s funções da 7b P4 ainda)', c.nome, v_n)); end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'M9 com os 5 modos da 7b desligados (e dono_como_tecnico ligado, que sem modo_dias não vale), o motor da semana e da carteira, o contexto de 3 semanas, o molde, a classe e a carga do dono são os de antes, byte a byte — com o gestor da 7a desligado e ligado, com a linha do dono e com o Mateus com datas',
    v_dif is null, coalesce(v_dif, '—'));
  perform pg_temp.gravar(v_res);
end
$m9$;

-- ── M10, M11 e M12. A dupla dita e o dono na conta da dupla ─────────────────────────────────────────────────────
do $m10$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_t   text := '';
  v_u   text := '';
  v_f   jsonb;
  v_i   jsonb;
  d     text;
  m     text;
  r     jsonb;
  v_x   jsonb;
  v_y   jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M10 (a dupla dita)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  foreach d in array array['todos', 'inicio'] loop
    foreach m in array array['desligado', 'sombra', 'ligado'] loop
      begin
        perform pg_temp.gestor('ligado');
        perform pg_temp.modos7b(m);
        perform pg_temp.so_alex();
        update public.os_planejamento set dupla_dita = d, dupla_meios = case when d = 'inicio' then 2 end,
               dupla_em = pg_temp.em(date '2026-11-05', '10:00') where service_order_id = v_len;
        r := public._agenda_classe_agora(v_len, date '2026-11-05');
        v_t := v_t || format('%s %s: %s %s; ', d, m, r ->> 'classe', r ->> 'motivo');
        perform pg_temp.vem('Mateus', array[date '2026-11-11', date '2026-11-12']);
        r := public._agenda_classe_agora(v_len, date '2026-11-05');
        v_u := v_u || format('%s %s: %s %s; ', d, m, r ->> 'classe', r ->> 'motivo');
        if d = 'todos' and m = 'ligado' then
          v_f := pg_temp.propor(array[v_len]);
        end if;
        if d = 'inicio' and m = 'ligado' then
          v_i := pg_temp.item(pg_temp.propor(array[v_len]), v_len);
        end if;
        raise exception 'desfaz' using errcode = 'P0099';
      exception when sqlstate 'P0099' then null;
      end;
    end loop;
  end loop;
  v_res := pg_temp.ok(v_res, 'M10a a dupla dita com só o Alex espera o dono (classe 4 dupla): o tempo todo em todos os modos (a correção 2 da 7a); no início em teste E ligado (desligado, a correção 2 não a vê: a de antes)',
    v_t = 'todos desligado: 4 dupla; todos sombra: 4 dupla; todos ligado: 4 dupla; inicio desligado: 2 pronta; inicio sombra: 4 dupla; inicio ligado: 4 dupla; ',
    v_t);
  v_res := pg_temp.ok(v_res, 'M10b com o Mateus dito no horizonte, a régua dos técnicos tem a 2ª pessoa: classe 2 em teste e ligado; desligado, a correção 2 byte a byte (o tempo todo continua 4)',
    v_u = 'todos desligado: 4 dupla; todos sombra: 2 pronta; todos ligado: 2 pronta; inicio desligado: 2 pronta; inicio sombra: 2 pronta; inicio ligado: 2 pronta; ',
    v_u);
  v_res := pg_temp.ok(v_res, 'M12 a dita o tempo todo do Lenine (6 meios-dias de 2 pessoas) com o Mateus só qua e qui (4): classe 2 pela régua, nenhum bloco → fora com o motivo dupla e o texto, nunca sem_encaixe',
    jsonb_array_length(v_f -> 'itens') = 0 and v_f -> 'fora' -> 0 ->> 'motivo' = 'dupla'
    and v_f -> 'fora' -> 0 ->> 'texto' = 'Lenine (OS-00074): precisa de 2 pessoas em 6 meios-dias e Mateus só vem qua 11 e qui 12/11 (4 meios-dias): me diga mais dias dele ou chame outro ajudante.',
    (v_f -> 'fora')::text);
  v_res := pg_temp.ok(v_res, 'M10c a dita no início que cabe nas datas do Mateus é marcada: Alex e Mateus na qua 11, o Alex no resto',
    pg_temp.meios(v_i) like '11/11 m Alex+Mateus; 11/11 t Alex+Mateus; 12/11 m Alex;%', pg_temp.meios(v_i));
  -- M11 o dono na conta da dupla
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    v_x := public.agenda_meios_da_os(pg_temp.os('OS-00033'), date '2026-11-05');
    insert into public.os_planejamento (service_order_id, dupla_dita, dupla_meios, dupla_em)
    values (pg_temp.os('OS-00096'), 'inicio', 1, pg_temp.em(date '2026-11-05', '10:00'))
    on conflict (service_order_id) do update set dupla_dita = 'inicio', dupla_meios = 1, dupla_em = excluded.dupla_em;
    v_y := public.agenda_meios_da_os(pg_temp.os('OS-00096'), date '2026-11-05');
    v_i := public.agenda_meios_da_os(v_len, date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M11 dk_dono_conta: a Kalmar-33 (o dono sempre, marina nova; o orçamento com 2 técnicos) pede 2 técnicos com o dono junto (não conta); o Lenine (o dono só abre e fecha) conta o dono — que nunca está no turno; o diagnóstico do Rodrigo (OS-00096) com o dono no turno conta o dono como uma das 2',
    not (v_x ->> 'dk_dono_conta')::boolean and (select bool_and(x::int = 2) from jsonb_array_elements_text(v_x -> 'dk') x)
    and (v_i ->> 'dk_dono_conta')::boolean and (v_y ->> 'dk_dono_conta')::boolean and v_y #>> '{dupla,fonte}' = 'dono'
    and (v_y #>> '{dono_turno,manha}')::boolean,
    concat_ws(' | ', v_x ->> 'dk_dono_conta', v_x -> 'dk', v_y ->> 'dk_dono_conta', v_y -> 'dk', v_y -> 'dono_turno'));
  perform pg_temp.gravar(v_res);
end
$m10$;

-- ── M13 e M14. O sábado do 7a e o gancho da pessoa a mais ──────────────────────────────────────────────────────
do $m13$
declare
  v_res jsonb := '[]'::jsonb;
  v_a   jsonb;
  v_b   jsonb;
  v_c   jsonb;
  v_d   jsonb;
  v_p   jsonb;
  v_v   jsonb;
  v_k   int;
  v_n   int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M13 e M14', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado');
    update public.agenda_config set modo_sabado = 'ligado' where id;
    v_a := public._agenda_gestor_sabado(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:52'));
    update public.agenda_config set modo_sabado = 'sombra' where id;
    v_b := public._agenda_gestor_sabado(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:52'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M13 _agenda_gestor_sabado: com modo_sabado ligado, {pulado: modo_sabado} (a pergunta crítica sabado do 7a não nasce); fora de ligado, a de antes',
    v_a = '{"pulado": "modo_sabado"}'::jsonb and not v_b ? 'pulado' and v_b ? 'quem_vem_sabado', concat_ws(' | ', v_a::text, left(v_b::text, 200)));
  -- M14 o gancho da pessoa a mais
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    v_a := public._agenda_contexto(date '2026-11-16', date '2026-11-22', date '2026-11-05');
    perform set_config('agenda.pessoa_extra', 'tecnico', true);
    v_b := public._agenda_contexto(date '2026-11-16', date '2026-11-22', date '2026-11-05');
    v_p := public.agenda_propor('os', null, null, array(select k.service_order_id from public.os_carteira(date '2026-11-05') k), '{}'::jsonb, false,
                                'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    v_v := public._agenda_validar_itens(jsonb_build_array(jsonb_build_object('op', 'criar', 'os', pg_temp.os('OS-00074'), 'numero', 'OS-00074',
             'tipo', 'reserva', 'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', public._agenda_pessoa_extra_id(), 'nome', 'mais uma pessoa',
             'dia', date '2026-11-17', 'turno', 'manha', 'presenca', 'turno'))))::jsonb, '{}'::jsonb, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    perform set_config('agenda.pessoa_extra', '', true);
    v_c := public._agenda_contexto(date '2026-11-16', date '2026-11-22', date '2026-11-05');
    v_n := (select count(*) from public.agenda_alocacoes a where a.payee_id = public._agenda_pessoa_extra_id())
           + (select count(*) from public.payees py where py.id = public._agenda_pessoa_extra_id())
           + (select count(*) from public.agenda_disponibilidade d where d.payee_id = public._agenda_pessoa_extra_id());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_k := (v_b ->> 'np')::int;
  v_res := pg_temp.ok(v_res, 'M14 o gancho da pessoa a mais (inerte sem a variável): com agenda.pessoa_extra = tecnico, a "mais uma pessoa" entra por último, livre nas manhãs e tardes dos dias úteis (sex 20 é feriado), com o teto de quem é da equipe (100% com o teto da equipe do 7a: 8) e na soma dela (6 → 12); o motor roda com ela sem gravar e o validador a aceita; sem a variável, o contexto de antes; nada gravado com o id dela',
    (v_b ->> 'np')::int = (v_a ->> 'np')::int + 1 and v_b -> 'nomes' ->> (v_k - 1) = 'mais uma pessoa'
    and v_b -> 'pessoas' ->> (v_k - 1) = public._agenda_pessoa_extra_id()::text
    and (select string_agg((v_b -> 'cap' ->> ((v_k - 1) * (v_b ->> 'nh')::int + h - 1)), '' order by h)
           from generate_series(1, (v_b ->> 'nh')::int) h) = '11111111000000'
    and (v_b -> 'teto80' ->> ((v_k - 1) * (v_b ->> 'nw')::int))::int = 8
    and (v_b -> 'teto_equipe' ->> 0)::int = 12 and (v_a -> 'teto_equipe' ->> 0)::int = 6
    and v_c = v_a and v_p ->> 'ok' = 'true' and v_v = '[]'::jsonb and v_n = 0,
    format('np %s→%s; cap %s; teto80 %s; validar %s; gravado %s', v_a ->> 'np', v_b ->> 'np',
           (select string_agg((v_b -> 'cap' ->> ((v_k - 1) * (v_b ->> 'nh')::int + h - 1)), '' order by h) from generate_series(1, (v_b ->> 'nh')::int) h),
           v_b -> 'teto80' ->> ((v_k - 1) * (v_b ->> 'nw')::int), v_v, v_n));
  perform pg_temp.gravar(v_res);
end
$m13$;

-- ── M15. O aceite: com só o Alex, Lenine e Vanderlei entram no plano com a sugestão do ajudante ─────────────────────
do $m15$
declare
  v_res jsonb := '[]'::jsonb;
  v_p   jsonb;
  v_l   jsonb;
  v_v   jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M15 (o aceite)', true, 'PULADO: sem as fixtures da 7b (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado');
    perform pg_temp.modos7b('ligado');
    perform pg_temp.so_alex();
    update public.os_planejamento set precisa_ate = null where service_order_id = pg_temp.os('OS-00069');
    v_p := pg_temp.propor(array[pg_temp.os('OS-00074'), pg_temp.os('OS-00069')]);
    v_l := (select i from jsonb_array_elements(v_p -> 'itens') i where (i ->> 'os')::uuid = pg_temp.os('OS-00074') and i ->> 'op' = 'criar' limit 1);
    v_v := (select i from jsonb_array_elements(v_p -> 'itens') i where (i ->> 'os')::uuid = pg_temp.os('OS-00069') and i ->> 'op' = 'criar' limit 1);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M15 com só o Alex (ligado), Lenine e Vanderlei entram no plano com o Alex (o Vanderlei em compromisso; o Lenine, com o teto da equipe do 7a cheio na semana dos dois, como reserva acima da carga) — nenhum espera pela dupla nem fica de fora por ela — e cada texto diz em que meios-dias chamar um ajudante (o do Vanderlei na forma curta: até 320 letras)',
    v_l is not null and v_v is not null and pg_temp.meios(v_l) not like '%+%' and pg_temp.meios(v_v) not like '%+%'
    and v_l ->> 'texto' like '%Nos 2 primeiros meios-dias (seg 09/11, manhã e tarde) a troca do banco de baterias pede 2 pessoas e só Alex está na equipe: se chamar um ajudante, me diga (ex.: Mateus vem seg 09/11).'
    and v_v ->> 'texto' like '%Nos 2 primeiros meios-dias a troca do banco de baterias pede 2 pessoas: se chamar um ajudante, me diga os dias dele.'
    and char_length(v_l ->> 'texto') <= 320 and char_length(v_v ->> 'texto') <= 320
    and not exists (select 1 from jsonb_array_elements(v_p -> 'fora') f where f ->> 'motivo' in ('dupla', 'sem_encaixe')),
    concat_ws(' | ', v_l ->> 'texto', v_v ->> 'texto', (v_p -> 'fora')::text));
  perform pg_temp.gravar(v_res);
end
$m15$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
