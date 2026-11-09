-- Prova do motor da Agenda de Produção, Fase 7c (pacote P2): a escolha de pessoa — o que cada pessoa faz no contexto, o responsável
-- que falta, o par do novo, o responsável da OS começada e a troca avisada, a ordem nova, o fora habilidade, o critério gravado em toda
-- alocação nova (o motor pelo item; os outros escritores pelo gatilho agenda_alocacoes_criterio) e a compatibilidade por ausência
-- (migration 20261102100100; spec-fase7c §3.4–§3.8, §5.2, §6.8, §8.3 agenda_fase7c_motor.sql, R5.3, R5.7-1/-2/-3/-6, R5.10-12).
-- bancada: depende de 20261102100100
--
--   M0  as portas: a nova (o aviso) e o gatilho sem grant; as 8 recriadas com as de antes; o gatilho BEFORE INSERT; agenda_propor definer
--   M1  desligado e em teste = antes: com os 3 modos da 7c desligados e em sombra, a saída inteira de agenda_propor('semana') e ('os', a
--       carteira e as OS da fixture), tirado só o critério das alocações, e o contexto, tiradas só as 3 chaves novas, são os do motor de
--       antes rodado no lugar (as 8 recriadas pelas origens) — com a 7b desligada e em teste e o gestor da 7a desligado e ligado; e
--       toda alocação nova tem critério (a regra antes)
--   M1r a equipe real (só o Alex e o dono, com e sem a linha dele; a 7b em teste e ligada): a 7c ligada não tira nenhuma OS nem muda
--       nenhuma alocação (a projeção igual à de teste); o Alex é responsável e continua sozinho onde ia; com a 7b ligada, a dupla
--       inferida do Lenine vai com o Alex e a 2ª pessoa que falta marcada (não vira lacuna)
--   M2  171 Lia (energizado no último dia): com o fechamento do dono que cobre, o menos qualificado (João) nos 6; sem ele, o João nos 5 e
--       quem instala sozinho no 6º (Roberto, critério habilidade) e o motivo "pede … : vai Roberto"
--   M3  172 Bia (o teto em todos): o João nos 2 (o Roberto não sobe), o motivo; sem quem sobe no dia, a OS vai a outro dia
--   M4  173 Caio (comissionamento em todos, o dono "nunca"): o fora habilidade com o texto; em teste ele entra (a regra de antes)
--   M5  174 Duda (nada): o João, critério habilidade (o menos qualificado ganhou do Roberto)
--   M6  175 Edu (o responsável que fez o 1º dia): o Roberto nos 4 (critério lider); ocupado até ter 10/11, a troca avisada (o João,
--       lider_trocado, o motivo); com lider_espera_max_du 10, espera o Roberto
--   M7  176 Fábio (o dono disse energizado em todos; dupla): o responsável primeiro (Roberto, habilidade) e o novo junto (Bruno)
--   M8  177 Gil (a equipe dita "só o João"): o João (dono_disse) e o aviso "— mas João iria sozinho, e o último dia pede …"; com o
--       fechamento que cobre, sem aviso
--   M8b 178 Hugo: só o Bruno livre na sex 06/11 → ele não vai sozinho e a OS começa seg 09/11 com o João; em teste (a 7b desligada), o
--       Bruno iria sozinho (a regra de antes)
--   M8c quem vem sob demanda (o Mateus dito só na sex 06/11, R5.3-2): nunca sozinho num meio-dia
--   M8d a pessoa a mais da 7b (R5.3-4): no contexto leva o padrão (instala 2, comissiona 0, altura 2, responsável), os 3 bits e 999999
--   M9  o critério gravado: as alocações da proposta persistida têm o critério e o detalhe do item (o gatilho não mexe), o dono
--       presenca_do_dono, regra antes em teste e 7c ligado, as suposições (pessoa_sem_etiqueta, exigencia_pelo_texto); a reserva também
--   M9d–M9i o gatilho com os outros 5 escritores, cada um chamado de verdade: a escada da 7a (escada), o corte da 7a (o fechamento do
--       dono presenca_do_dono, corte), a 2ª pessoa da dupla da 7b (dupla), o agenda_desfazer e o desfazer do cliente (fora_do_motor; o
--       dono presenca_do_dono); e a alocação que já chega com critério (não muda)
--   M10 a reserva: o que o turno do dono cobriria conta como atendido (com o dono o tempo todo, o Bruno guarda o lugar do Fábio — o
--       energizado e o par ficam com o turno do dono; sem ele, ninguém guarda); o responsável não é duro na reserva (o Edu reservado
--       sem o Roberto)
--   M11 a compatibilidade por ausência: agenda_encaixe_do_novo, agenda_ctp e agenda_simular byte a byte com o motor de antes, também
--       com a 7c ligada
--   M12 o "por que não cabe" do dia pedido: "Bia (OS-97172): não cabe ter 10/11: ninguém que sobe no teto fica livre nesse dia."
--   M13 _agenda_alocacoes_imutavel: o critério da publicada não muda; o da proposta, sim
--   M14 as cópias: tirados os blocos "-- FASE 7c:", o corpo vivo e o da migration de cada recriada são os da origem, com o número de
--       blocos
--   M15 a técnica logada que marca pela tela (agenda_marcar_os é de authenticated e chega ao motor): o motor não quebra no 42501 de
--       os_exigencias — para ela a OS não pede ninguém em especial (sem exigência no critério) —, e os_exigencias direto continua 42501;
--       com o admin logado, o motor lê o que a OS pede
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7c_motor.sql
--   Seguro em produção: termina em ROLLBACK. M0 roda em qualquer banco; M14 sai PULADO sem as migrations como texto; o resto usa as
--   fixtures e só roda na bancada (fora dela sai PULADO).
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
-- O texto sem os blocos "-- FASE 7c: … -- FASE 7c: fim" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7c(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[cdef]:' and l !~ '-- FASE 7[cdef]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[cdef]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[cdef]: fim' as fecha
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
-- A saída do motor sem o critério das alocações dos itens (o que a 7c acrescenta em qualquer modo: a projeção da §3.8 d8).
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
-- A projeção (OS, pessoa, dia, turno, presença, tipo) e o que fica de fora (OS, motivo).
create function pg_temp.projecao(p jsonb) returns text language sql immutable as $f$
  select coalesce((select string_agg(format('%s %s %s %s [%s]', i ->> 'op', i ->> 'numero', i ->> 'tipo', coalesce(i ->> 'reserva_de', '-'),
                                            (select string_agg(concat_ws(' ', a ->> 'payee_id', a ->> 'dia', a ->> 'turno', a ->> 'presenca'), ', '
                                                               order by a ->> 'dia', a ->> 'turno', a ->> 'presenca', a ->> 'payee_id')
                                               from jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) a)),
                                     ' | ' order by i ->> 'op', i ->> 'numero', i ->> 'tipo', i ->> 'reserva_de')
                     from jsonb_array_elements(coalesce(p -> 'itens', '[]'::jsonb)) i), '')
         || ' || ' || coalesce((select string_agg(format('%s %s', f ->> 'numero', f ->> 'motivo'), ', ' order by f ->> 'numero', f ->> 'motivo')
                                  from jsonb_array_elements(coalesce(p -> 'fora', '[]'::jsonb)) f), '')
$f$;
-- O motor de antes no lugar: as 8 recriadas pelas origens (dentro de uma subtransação desfeita por quem chama).
create function pg_temp.motor_de_antes() returns void language plpgsql as $f$
begin
  execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7b'), '_agenda_contexto');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7b'), '_agenda_tentar_bloco');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase7b'), '_agenda_encaixar');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase2'), '_agenda_so_diaristas');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_motor_fase2'), '_agenda_alocs_do_bloco');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_teto_fase7a'), '_agenda_por_que_nao');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7b'), 'agenda_propor');
  execute pg_temp.inteira(current_setting('agenda_teste.mig_tabelas_fase2'), '_agenda_alocacoes_imutavel');
end $f$;
create function pg_temp.textos_ok() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.mig_correcao_fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_motor_fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_teto_fase7a', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_tabelas_fase2', true), '') <> ''
$f$;

-- ── M0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'M0a a nova _agenda_aviso_da_habilidade: invoker, STABLE, search_path fixo, sem grant a ninguém (nem anon, nem authenticated, nem service_role)',
       p.oid is not null and not p.prosecdef and p.provolatile = 's' and array_to_string(p.proconfig, ',') like '%search_path=public%'
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute'),
       null
  from (select to_regprocedure('public._agenda_aviso_da_habilidade(uuid, jsonb, date)') as oid) x
  left join pg_proc p on p.oid = x.oid;
insert into _resultado
select 'M0b o gatilho agenda_alocacoes_criterio: BEFORE INSERT por linha em agenda_alocacoes, depois do agenda_alocacoes_antes e antes do agenda_alocacoes_fonte (a ordem do nome); a função sem grant',
       exists (select 1 from pg_trigger t where t.tgrelid = 'public.agenda_alocacoes'::regclass and t.tgname = 'agenda_alocacoes_criterio'
                  and t.tgfoid = 'public._agenda_alocacao_criterio()'::regprocedure and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4
                  and (t.tgtype & 1) = 1 and (t.tgtype & 16) = 0)
       and 'agenda_alocacoes_antes' < 'agenda_alocacoes_criterio' and 'agenda_alocacoes_criterio' < 'agenda_alocacoes_fonte'
       and not has_function_privilege('anon', 'public._agenda_alocacao_criterio()', 'execute')
       and not has_function_privilege('authenticated', 'public._agenda_alocacao_criterio()', 'execute'),
       (select string_agg(t.tgname || ' ' || t.tgtype, ', ' order by t.tgname) from pg_trigger t
         where t.tgrelid = 'public.agenda_alocacoes'::regclass and not t.tgisinternal);
with f(sig) as (values
  ('public._agenda_contexto(date, date, date, uuid[], uuid[])'),
  ('public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)'),
  ('public._agenda_so_diaristas(jsonb, integer)'), ('public._agenda_encaixar(jsonb, jsonb, jsonb)'),
  ('public._agenda_alocs_do_bloco(jsonb, jsonb)'), ('public._agenda_por_que_nao(jsonb, jsonb, integer, integer)'),
  ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)'))
insert into _resultado
select 'M0c as 7 recriadas do motor continuam só do service_role (nem anon nem authenticated); agenda_propor continua definer; a imutável sem grant',
       count(p.oid) = 7
       and bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and has_function_privilege('service_role', p.oid, 'execute'))
       and (select prosecdef from pg_proc where oid = to_regprocedure('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)'))
       and not has_function_privilege('authenticated', 'public._agenda_alocacoes_imutavel()', 'execute')
       and not has_function_privilege('anon', 'public._agenda_alocacoes_imutavel()', 'execute'),
       string_agg(f.sig, '; ') filter (where p.oid is null or has_function_privilege('anon', p.oid, 'execute')
                                          or has_function_privilege('authenticated', p.oid, 'execute'))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'M0d o anon e o técnico logado não chamam o motor (42501)',
       pg_temp.como('anon', 'select public.agenda_propor(''semana'')::text') like 'erro 42501%'
       and pg_temp.como('authenticated', 'select public.agenda_propor(''semana'')::text') like 'erro 42501%',
       pg_temp.como('anon', 'select public.agenda_propor(''semana'')::text');

-- ── As fixtures ────────────────────────────────────────────────────────────────────────────────────────────────
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97171')
     and exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97101')
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
-- o gestor da 7a (os 5 modos dele; com ele, a regra uma_pessoa e a sem_peca deixam as OS da fixture prontas, com 1 pessoa)
create function pg_temp.gestor(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end, modo_proposta = 'ligado'
   where id
$f$;
create function pg_temp.modos7b(p_modo text) returns void language sql as $f$
  update public.agenda_config set modo_dias = p_modo, modo_dupla = p_modo, modo_sabado = p_modo, modo_cadastro = p_modo,
                                  modo_chamar = p_modo where id
$f$;
create function pg_temp.modos7c(p_hab text, p_lid text) returns void language sql as $f$
  update public.agenda_config set modo_habilidade = p_hab, modo_lider = p_lid, modo_habilidade_propor = p_hab where id
$f$;
create function pg_temp.nao_vem(p_nome text, p_de date, p_ate date) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(p_de, p_ate, '[]'), null, 'indisponivel', 'dono', 'não vem (teste)', timestamptz '2026-11-04 10:01-03'
    from public.payees p where p.name = p_nome and p.active
$f$;
create function pg_temp.vem(p_nome text, p_dias date[]) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(d, d, '[]'), null, 'disponivel', 'dono', 'Você disse que vem (sob demanda)', timestamptz '2026-11-04 10:00-03'
    from public.payees p, unnest(p_dias) d where p.name = p_nome and p.active
$f$;
-- a 179 publicada com o João na ter 10/11 sai do caminho (cancelada), para o João ficar livre nesse dia
create function pg_temp.sem_179() returns void language sql as $f$
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado'
   where service_order_id = pg_temp.os('OS-97179') and estado in ('publicada', 'fixada')
$f$;
create function pg_temp.propor(p_numeros text[], p_restricoes jsonb default '{}'::jsonb) returns jsonb language sql as $f$
  select public.agenda_propor('os', null, null, array(select pg_temp.os(n) from unnest(p_numeros) n), p_restricoes, false, 'vigia', null,
                              date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'))
$f$;
create function pg_temp.marcar(p_numeros text[], p_restricoes jsonb default '{}'::jsonb, p_hora text default '16:15') returns jsonb
language plpgsql as $f$
declare
  v_p jsonb;
begin
  v_p := public.agenda_propor('os', null, null, array(select pg_temp.os(n) from unnest(p_numeros) n), p_restricoes, true, 'vigia', null,
                              date '2026-11-04', pg_temp.em(date '2026-11-04', p_hora));
  return public.agenda_aplicar((v_p ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-11-04', pg_temp.em(date '2026-11-04', p_hora));
end $f$;
-- o item de compromisso da OS e os meios-dias de turno dele, com o critério: "06/11m João:habilidade; 06/11t João:continuidade"
create function pg_temp.item(p_prop jsonb, p_numero text) returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(coalesce(p_prop -> 'itens', '[]'::jsonb)) i
   where i ->> 'numero' = p_numero and i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' limit 1
$f$;
create function pg_temp.reserva(p_prop jsonb, p_numero text) returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(coalesce(p_prop -> 'itens', '[]'::jsonb)) i
   where i ->> 'numero' = p_numero and i ->> 'op' = 'criar' and i ->> 'tipo' = 'reserva' limit 1
$f$;
create function pg_temp.mc(p_item jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(x.d || x.t || ' ' || x.n, '; ' order by x.d, x.t), '-')
    from (select to_char((a ->> 'dia')::date, 'DD/MM') as d, case when a ->> 'turno' = 'manha' then 'm' else 't' end as t,
                 string_agg((a ->> 'nome') || ':' || coalesce(a ->> 'criterio', '-'), '+' order by a ->> 'nome') as n
            from jsonb_array_elements(coalesce(p_item -> 'alocacoes', '[]'::jsonb)) a
           where a ->> 'presenca' = 'turno' group by 1, 2) x
$f$;
create function pg_temp.fora(p_prop jsonb, p_numero text) returns text language sql immutable as $f$
  select string_agg((f ->> 'motivo') || ': ' || (f ->> 'texto'), ' | ')
    from jsonb_array_elements(coalesce(p_prop -> 'fora', '[]'::jsonb)) f where f ->> 'numero' = p_numero
$f$;
create function pg_temp.vivas(p_numero text) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s%s %s %s %s %s', to_char(a.dia, 'DD/MM'), case when a.turno = 'manha' then 'm' else 't' end,
                                    public._agenda_nome_curto(py.name), a.presenca, coalesce(a.criterio, '-'), coalesce(a.criterio_detalhe ->> 'regra', '-')),
                             '; ' order by a.dia, a.turno = 'tarde', a.presenca, py.name), '-')
    from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
   where a.service_order_id = pg_temp.os(p_numero) and a.estado in ('publicada', 'fixada')
$f$;

-- ── M1r. A equipe real (só o Alex e o dono; antes da sintética: a variante é escolhida quando a 7b carrega) ───────────────────
do $m1r$
declare
  v_res  jsonb := '[]'::jsonb;
  c      record;
  v_s1   text;
  v_s2   text;
  v_l1   text;
  v_l2   text;
  v_alex text;
  v_dif  text;
  v_cart uuid[];
  v_raw  jsonb;
  v_len  text;
  v_lens text;
begin
  if coalesce(current_setting('agenda_teste.fase7c', true), '') = '' or coalesce(current_setting('agenda_teste.fase7b', true), '') = ''
     or exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    insert into _resultado values ('M1r a equipe real', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  for c in select * from (values ('sem a linha do dono, a 7b em teste', '', 'sombra'), ('com a linha do dono, a 7b em teste', 'campo', 'sombra'),
                                 ('com a linha do dono, a 7b ligada', 'campo', 'ligado')) t(nome, dono, m7b) loop
    begin
      perform set_config('agenda_teste.fase7b_equipe', 'real', true);
      perform set_config('agenda_teste.fase7b_dono', c.dono, true);
      execute current_setting('agenda_teste.fase7c');
      perform set_config('agenda_teste.fase7b_equipe', '', true);
      perform set_config('agenda_teste.fase7b_dono', '', true);
      perform pg_temp.gestor('ligado');
      perform pg_temp.modos7b(c.m7b);
      v_cart := array(select k.service_order_id from public.os_carteira(date '2026-11-04') k order by 1);
      perform pg_temp.modos7c('sombra', 'sombra');
      v_s1 := pg_temp.projecao(public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, date '2026-11-04',
                                                    pg_temp.em(date '2026-11-04', '16:15')));
      v_s2 := pg_temp.projecao(public.agenda_propor('os', null, null, v_cart, '{}'::jsonb, false, 'vigia', null, date '2026-11-04',
                                                    pg_temp.em(date '2026-11-04', '16:15')));
      perform pg_temp.modos7c('ligado', 'ligado');
      v_l1 := pg_temp.projecao(public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, date '2026-11-04',
                                                    pg_temp.em(date '2026-11-04', '16:15')));
      v_raw := public.agenda_propor('os', null, null, v_cart, '{}'::jsonb, false, 'vigia', null, date '2026-11-04',
                                    pg_temp.em(date '2026-11-04', '16:15'));
      v_l2 := pg_temp.projecao(v_raw);
      -- o Lenine (a troca do banco de baterias pede 2 nos 2 primeiros meios-dias): com a 7b ligada e só o Alex, vai com ele, com a
      -- dupla que falta marcada (a 7c ligada não o tira nem o torna lacuna)
      v_len := (select coalesce(string_agg(distinct a ->> 'nome', '+'), '-') || ' ' || coalesce(jsonb_array_length(i -> 'dupla_falta'), 0)
                  from jsonb_array_elements(v_raw -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                 where i ->> 'numero' = 'OS-00074' and i ->> 'op' = 'criar' and a ->> 'presenca' = 'turno'
                 group by i);
      select h.papel || '/' || h.instala into v_alex from public.agenda_habilidades(date '2026-11-04', array[pg_temp.pessoa('Alex')]) h;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    if v_s1 is distinct from v_l1 or v_s2 is distinct from v_l2 or v_alex is distinct from '0/2'
       or v_l2 like '%habilidade%' or v_s2 not like '%criar%'
       or (c.m7b = 'ligado' and v_len is distinct from 'Alex 2') then
      v_dif := concat_ws('; ', v_dif, format('%s: semana %s, carteira %s, Alex %s, Lenine %s', c.nome, v_s1 = v_l1, v_s2 = v_l2, v_alex,
                                              coalesce(v_len, '-')));
    end if;
    v_lens := concat_ws('; ', v_lens, c.nome || ': Lenine ' || coalesce(v_len, '-'));
  end loop;
  v_res := pg_temp.ok(v_res, 'M1r a equipe real (só o Alex e o dono, com e sem a linha dele; o gestor da 7a ligado; a 7b em teste e ligada: a dupla inferida que vai com o Alex sozinho não vira lacuna): a 7c ligada (a escolha e o responsável) dá a mesma projeção da semana e da carteira que em teste, nenhuma OS no fora habilidade, e o Alex é responsável (papel 0, instala 2); com a 7b ligada, o Lenine vai com o Alex e os 2 meios-dias da dupla que falta marcados',
    v_dif is null, coalesce(v_dif, v_lens));
  perform pg_temp.gravar(v_res);
end
$m1r$;

-- A sintética, com as etiquetas dos testes M e V (Roberto instala 2 e não sobe no teto; João ajudante 2; Bruno novo), uma vez; cada caso
-- abaixo roda numa subtransação desfeita.
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7c', true), '') = '' or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    return;
  end if;
  perform set_config('agenda_teste.fase7c_etiquetas', 'mv', true);
  execute current_setting('agenda_teste.fase7c');
end
$carga$;

-- ── M1. Desligado e em teste = antes ───────────────────────────────────────────────────────────────────────────
do $m1$
declare
  v_res   jsonb := '[]'::jsonb;
  c       record;
  v_cart  uuid[];
  v_a1    jsonb;
  v_a2    jsonb;
  v_novo  text;
  v_antes text;
  v_sem   int;
  v_n     int;
  v_dif   text;
  v_tot   int := 0;
begin
  if not pg_temp.carregada() or not pg_temp.textos_ok() then
    insert into _resultado values ('M1 desligado e em teste = antes', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_cart := array(select k.service_order_id from public.os_carteira(date '2026-11-04') k
                  union select so.id from public.service_orders so where so.service_order_number like 'OS-9717_' order by 1);
  for c in select * from (values
      ('7c desligada, 7b desligada, gestor desligado', 'desligado', 'desligado', 'desligado'),
      ('7c desligada, 7b desligada, gestor ligado', 'desligado', 'desligado', 'ligado'),
      ('7c desligada, 7b em teste, gestor ligado', 'desligado', 'sombra', 'ligado'),
      ('7c em teste, 7b desligada, gestor desligado', 'sombra', 'desligado', 'desligado'),
      ('7c em teste, 7b desligada, gestor ligado', 'sombra', 'desligado', 'ligado'),
      ('7c em teste, 7b em teste, gestor ligado', 'sombra', 'sombra', 'ligado')) t(nome, m7c, m7b, gestor) loop
    begin
      perform pg_temp.gestor(c.gestor);
      perform pg_temp.modos7b(c.m7b);
      perform pg_temp.modos7c(c.m7c, c.m7c);
      v_a1 := public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
      v_a2 := public.agenda_propor('os', null, null, v_cart, '{}'::jsonb, false, 'vigia', null, date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
      v_novo := md5(pg_temp.sem_criterio(v_a1)::text) || md5(pg_temp.sem_criterio(v_a2)::text)
                || md5((public._agenda_contexto(date '2026-11-02', date '2026-11-22', date '2026-11-04') - 'hab' - 'habf' - 'custo')::text);
      -- toda alocação nova tem o critério (a regra de antes) e nenhuma veio sem ele
      select count(*) filter (where a ->> 'criterio' is null or a #>> '{criterio_detalhe,regra}' is distinct from 'antes'), count(*)
        into v_sem, v_n
        from jsonb_array_elements((v_a1 -> 'itens') || (v_a2 -> 'itens')) i, jsonb_array_elements(i -> 'alocacoes') a
       where i ->> 'op' = 'criar';
      perform pg_temp.motor_de_antes();
      v_antes := md5(public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, date '2026-11-04',
                                          pg_temp.em(date '2026-11-04', '16:15'))::text)
                 || md5(public.agenda_propor('os', null, null, v_cart, '{}'::jsonb, false, 'vigia', null, date '2026-11-04',
                                             pg_temp.em(date '2026-11-04', '16:15'))::text)
                 || md5(public._agenda_contexto(date '2026-11-02', date '2026-11-22', date '2026-11-04')::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_tot := v_tot + v_n;
    if v_novo is distinct from v_antes or v_sem <> 0 or v_n = 0 then
      v_dif := concat_ws('; ', v_dif, format('%s (sem critério %s de %s; %s × %s)', c.nome, v_sem, v_n, v_novo, v_antes));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'M1 com os 3 modos da 7c desligados e em teste, a semana e a carteira (com as OS da fixture) do motor são as de antes, tirado só o critério das alocações, e o contexto o de antes, tiradas só hab/habf/custo — com a 7b desligada e em teste e o gestor da 7a desligado e ligado (o motor de antes rodado no lugar); toda alocação nova tem critério, a regra antes',
    v_dif is null, coalesce(v_dif, format('%s alocações com critério nas 6 combinações', v_tot)));
  perform pg_temp.gravar(v_res);
end
$m1$;

-- ── M2 a M8. A escolha com a 7c ligada (o gestor da 7a ligado: 1 pessoa por OS; a 7b desligada) ─────────────────────────────
do $m2$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  i     jsonb;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M2 a M8 a escolha com a 7c ligada', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- M2a: 171 Lia, o fechamento do dono cobre o último dia (o padrão): o menos qualificado nos 6
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    perform pg_temp.sem_179();
    i := pg_temp.item(pg_temp.propor(array['OS-97171']), 'OS-97171');
    t1 := pg_temp.mc(i);
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    perform pg_temp.nao_vem('Rafael', date '2026-11-10', date '2026-11-10');
    perform pg_temp.nao_vem('Alex', date '2026-11-10', date '2026-11-10');
    i := pg_temp.item(pg_temp.propor(array['OS-97171']), 'OS-97171');
    t2 := pg_temp.mc(i);
    t3 := (i -> 'motivos')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M2a 171 Lia com o fechamento do dono que cobre o último dia: o menos qualificado (João) nos 6 meios-dias — o 1º pelo nível (habilidade), os outros pela continuidade',
    t1 = '06/11m João:habilidade; 06/11t João:continuidade; 09/11m João:continuidade; 09/11t João:continuidade; 10/11m João:continuidade; 10/11t João:continuidade',
    t1);
  v_res := pg_temp.ok(v_res, 'M2b 171 Lia sem o fechamento que cobre: o João nos 5 primeiros e, no 6º (o último dia pede quem instala sozinho com 220 V ou banco de bateria), o Roberto (habilidade: o João, que vinha antes pela continuidade, não zerava); o motivo "pede … no último dia: vai Roberto"',
    t2 = '06/11m João:habilidade; 06/11t João:continuidade; 09/11m João:continuidade; 09/11t João:continuidade; 10/11m João:continuidade; 10/11t Roberto:habilidade'
    and t3 like '%"pede quem instala sozinho com 220 V ou banco de bateria, no último dia: vai Roberto"%',
    t2 || ' | ' || t3);

  -- M3: 172 Bia, o teto em todos os dias (o Roberto não sobe)
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    v := pg_temp.propor(array['OS-97172']);
    t1 := pg_temp.mc(pg_temp.item(v, 'OS-97172'));
    t2 := (pg_temp.item(v, 'OS-97172') -> 'motivos')::text;
    perform pg_temp.nao_vem('João', date '2026-11-06', date '2026-11-06');
    perform pg_temp.nao_vem('Alex', date '2026-11-06', date '2026-11-06');
    perform pg_temp.nao_vem('Rafael', date '2026-11-06', date '2026-11-06');
    t3 := pg_temp.mc(pg_temp.item(pg_temp.propor(array['OS-97172']), 'OS-97172'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M3a 172 Bia (o teto em todos os dias): o João nos 2 meios-dias (o menos qualificado que sobe; o Roberto não sobe) e o motivo "pede quem sobe no teto: vai João"',
    t1 = '06/11m João:habilidade; 06/11t João:continuidade' and t2 like '%"pede quem sobe no teto: vai João"%', t1 || ' | ' || t2);
  v_res := pg_temp.ok(v_res, 'M3b sem quem sobe no teto livre na sex 06/11 (o Roberto livre, mas não sobe; o Bruno é novo), a Bia vai para seg 09/11 com o João',
    t3 = '09/11m João:habilidade; 09/11t João:continuidade', t3);

  -- M4: 173 Caio (comissionamento em todos, o dono "nunca")
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    v := pg_temp.propor(array['OS-97173']);
    t1 := pg_temp.fora(v, 'OS-97173');
    t2 := coalesce(pg_temp.mc(pg_temp.item(v, 'OS-97173')), '-');
    perform pg_temp.modos7c('sombra', 'sombra');
    t3 := pg_temp.mc(pg_temp.item(pg_temp.propor(array['OS-97173']), 'OS-97173'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M4 173 Caio (comissionamento em todos os dias, o dono "nunca"): ligado, nenhum meio-dia e o fora habilidade "Caio (OS-97173): pede quem comissiona Victron em todos os dias e ninguém com isso fica livre junto nas próximas 6 semanas."; em teste, entra como antes',
    t1 = 'habilidade: Caio (OS-97173): pede quem comissiona Victron em todos os dias e ninguém com isso fica livre junto nas próximas 6 semanas.'
    and t2 = '-' and t3 <> '-',
    concat_ws(' | ', t1, t2, t3));

  -- M5: 174 Duda (nada)
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    t1 := pg_temp.mc(pg_temp.item(pg_temp.propor(array['OS-97174']), 'OS-97174'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M5 174 Duda (não pede ninguém em especial): o João, o menos qualificado (habilidade: ganhou do próximo pelo nível)',
    t1 = '06/11m João:habilidade', t1);

  -- M6: 175 Edu, o responsável que fez o 1º dia (Roberto, ter 03/11)
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    t1 := pg_temp.mc(pg_temp.item(pg_temp.propor(array['OS-97175']), 'OS-97175'));
    perform pg_temp.nao_vem('Roberto', date '2026-11-05', date '2026-11-10');
    i := pg_temp.item(pg_temp.propor(array['OS-97175']), 'OS-97175');
    t2 := pg_temp.mc(i) || ' | ' || coalesce((i -> 'motivos')::text, '')
          || ' | ' || (select string_agg(distinct a #>> '{criterio_detalhe,lider_trocado}', ',') from jsonb_array_elements(i -> 'alocacoes') a
                        where a ->> 'presenca' = 'turno');
    update public.agenda_config set lider_espera_max_du = 10 where id;
    i := pg_temp.item(pg_temp.propor(array['OS-97175']), 'OS-97175');
    t3 := pg_temp.mc(i) || ' | ' || (select string_agg(distinct a #>> '{criterio_detalhe,lider_trocado}', ',') from jsonb_array_elements(i -> 'alocacoes') a
                                      where a ->> 'presenca' = 'turno');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M6a 175 Edu (o Roberto fez o 1º dia): o Roberto nos 4 meios-dias que faltam, critério lider',
    t1 = '06/11m Roberto:lider; 06/11t Roberto:lider; 09/11m Roberto:lider; 09/11t Roberto:lider', t1);
  v_res := pg_temp.ok(v_res, 'M6b o Roberto fora de qui 05 a ter 10/11, esperar por ele atrasaria 3 dias úteis (> lider_espera_max_du 2): a troca avisada — o João (o menos qualificado), lider_trocado, e o motivo "troquei o responsável: Roberto não está livre até qua 11/11; segui com João"',
    t2 like '06/11m João:habilidade; 06/11t João:continuidade; 09/11m João:continuidade; 09/11t João:continuidade | %'
    and t2 like '%"troquei o responsável: Roberto não está livre até qua 11/11; segui com João"%' and t2 like '% | true',
    t2);
  v_res := pg_temp.ok(v_res, 'M6c com lider_espera_max_du 10, o motor espera o Roberto (qua 11 e qui 12/11, critério lider, sem troca)',
    t3 = '11/11m Roberto:lider; 11/11t Roberto:lider; 12/11m Roberto:lider; 12/11t Roberto:lider | false', t3);

  -- M7: 176 Fábio, o dono disse energizado em todos os dias e dupla (o Alex e o Rafael fora: o Roberto é o único que instala sozinho)
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    perform pg_temp.nao_vem('Alex', date '2026-11-05', date '2026-11-20');
    perform pg_temp.nao_vem('Rafael', date '2026-11-05', date '2026-11-20');
    i := pg_temp.item(pg_temp.propor(array['OS-97176']), 'OS-97176');
    t1 := pg_temp.mc(i);
    t2 := (i -> 'motivos')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M7 176 Fábio (o dono disse que pede energizado em todos os dias; com dupla): em cada meio-dia o responsável primeiro (o Roberto, habilidade: o Bruno e o João vinham antes e não instalam sozinhos) e o menor nível junto (o Bruno, o novo, que com ele já pode ir); o motivo "pede … : vai Roberto"',
    t1 = '06/11m Bruno:habilidade+Roberto:habilidade; 06/11t Bruno:continuidade+Roberto:habilidade; 09/11m Bruno:continuidade+Roberto:habilidade; 09/11t Bruno:continuidade+Roberto:habilidade'
    and t2 like '%"pede quem instala sozinho com 220 V ou banco de bateria: vai Roberto"%',
    t1 || ' | ' || t2);

  -- M8: 177 Gil, a equipe dita "só o João"
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    i := pg_temp.item(pg_temp.propor(array['OS-97177']), 'OS-97177');
    t1 := pg_temp.mc(i) || ' | ' || (i ->> 'texto');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    i := pg_temp.item(pg_temp.propor(array['OS-97177']), 'OS-97177');
    t2 := pg_temp.mc(i) || ' | ' || (i ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M8a 177 Gil (a equipe dita "só o João"), com o fechamento que cobre: o João nos 2 (dono_disse) e nenhum aviso',
    t1 = '06/11m João:dono_disse; 06/11t João:dono_disse | Gil (OS-97177): sex 06/11, você abre e fecha, João o dia todo.', t1);
  v_res := pg_temp.ok(v_res, 'M8b sem o fechamento que cobre: a palavra do dono vale (o João, dono_disse) e o item avisa "— mas João iria sozinho, e o último dia pede quem instala sozinho com 220 V ou banco de bateria."',
    t2 = '06/11m João:dono_disse; 06/11t João:dono_disse | Gil (OS-97177): sex 06/11, você abre e fecha, João o dia todo — mas João iria sozinho, e o último dia pede quem instala sozinho com 220 V ou banco de bateria.',
    t2);

  -- M8b/M8c: 178 Hugo, só o Bruno (o novo) livre na sex 06/11; e quem vem sob demanda
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    perform pg_temp.nao_vem('Roberto', date '2026-11-06', date '2026-11-06');
    perform pg_temp.nao_vem('João', date '2026-11-06', date '2026-11-06');
    perform pg_temp.nao_vem('Alex', date '2026-11-06', date '2026-11-06');
    perform pg_temp.nao_vem('Rafael', date '2026-11-06', date '2026-11-06');
    t1 := pg_temp.mc(pg_temp.item(pg_temp.propor(array['OS-97178']), 'OS-97178'));
    perform pg_temp.modos7c('sombra', 'sombra');
    t2 := pg_temp.mc(pg_temp.item(pg_temp.propor(array['OS-97178']), 'OS-97178'));
    perform pg_temp.modos7c('ligado', 'ligado');
    perform pg_temp.nao_vem('Bruno', date '2026-11-06', date '2026-11-06');
    perform pg_temp.vem('Mateus', array[date '2026-11-06']);
    t3 := pg_temp.mc(pg_temp.item(pg_temp.propor(array['OS-97178']), 'OS-97178'));
    t4 := (select h.papel || ' ' || (h.fonte ->> 'papel') from public.agenda_habilidades(date '2026-11-04', array[pg_temp.pessoa('Mateus')]) h);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M8c 178 Hugo com só o Bruno (o novo) livre na sex 06/11: ligado, o Bruno não vai sozinho e a OS começa seg 09/11 com o João; em teste (a 7b desligada), o Bruno iria sozinho na sex (a regra de antes)',
    t1 = '09/11m João:habilidade' and t2 = '06/11m Bruno:unico', t1 || ' | ' || t2);
  v_res := pg_temp.ok(v_res, 'M8d quem vem sob demanda (o Mateus dito só na sex 06/11, papel novo): nunca sozinho — com só ele livre nesse dia, o Hugo vai para seg 09/11 com o João',
    t3 = '09/11m João:habilidade' and t4 = '2 sob_demanda', t3 || ' | ' || coalesce(t4, '-'));

  -- M8e: a pessoa a mais da 7b (R5.3-4)
  begin
    perform set_config('agenda.pessoa_extra', 'tecnico', true);
    v := public._agenda_contexto(date '2026-11-02', date '2026-11-22', date '2026-11-04');
    perform set_config('agenda.pessoa_extra', '', true);
    t1 := format('%s %s %s', (select jsonb_agg(x) from jsonb_array_elements(v -> 'hab') with ordinality t(x, o)
                                where o > ((v ->> 'np')::int - 1) * 4),
                 v -> 'habf' -> ((v ->> 'np')::int - 1), v -> 'custo' -> ((v ->> 'np')::int - 1));
    t2 := format('%s %s %s', jsonb_array_length(v -> 'hab'), jsonb_array_length(v -> 'habf'), jsonb_array_length(v -> 'custo'));
    t3 := (v -> 'pessoas' ->> ((v ->> 'np')::int - 1));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M8e a pessoa a mais da 7b (agenda.pessoa_extra = tecnico, que não é payee): no contexto leva o padrão — instala 2, comissiona 0, altura 2, responsável —, os 3 bits do padrão e 999999; os 3 arrays alinhados com as pessoas',
    t1 = '[2, 0, 2, 0] 7 999999' and t3 = public._agenda_pessoa_extra_id()::text
    and t2 = format('%s %s %s', 4 * (select count(*) from jsonb_array_elements(v -> 'pessoas')), (select count(*) from jsonb_array_elements(v -> 'pessoas')),
                    (select count(*) from jsonb_array_elements(v -> 'pessoas'))),
    t1 || ' | ' || t2);
  perform pg_temp.gravar(v_res);
end
$m2$;

-- ── M9 e M9b. O critério gravado ───────────────────────────────────────────────────────────────────────────────
do $m9$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  a     jsonb;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
  t6    text;
  v_n   int;
  v_m   int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M9 o critério gravado', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- M9a: em teste (a regra antes) e ligado (a regra 7c), a alocação gravada é a do item
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('sombra', 'sombra');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97172'), pg_temp.os('OS-97174')], '{}'::jsonb, true, 'vigia', null,
                              date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    -- o gravado é o do item (o gatilho não mexe no que o motor mandou)
    select count(*) filter (where al.criterio is distinct from x.e ->> 'criterio' or al.criterio_detalhe is distinct from x.e -> 'criterio_detalhe'),
           count(*)
      into v_n, v_m
      from (select e from jsonb_array_elements(v -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') e where i ->> 'op' = 'criar') x
      join public.agenda_alocacoes al on al.id = (x.e ->> 'alocacao_id')::uuid;
    t1 := format('%s diferentes de %s', v_n, v_m);
    t2 := (select string_agg(distinct coalesce(al.criterio, '-') || '/' || coalesce(al.criterio_detalhe ->> 'regra', '-'), ',')
             from public.agenda_alocacoes al where al.proposta_id = (v ->> 'proposta_id')::uuid and al.payee_id = public._agenda_dono(null));
    t3 := (select string_agg(distinct coalesce(al.criterio_detalhe ->> 'regra', '-'), ',') from public.agenda_alocacoes al
            where al.proposta_id = (v ->> 'proposta_id')::uuid);
    t4 := (select count(*)::text from public.agenda_alocacoes al where al.proposta_id = (v ->> 'proposta_id')::uuid and al.criterio is null);
    perform pg_temp.modos7c('ligado', 'ligado');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97172')], '{}'::jsonb, true, 'vigia', null,
                              date '2026-11-04', pg_temp.em(date '2026-11-04', '16:20'));
    t5 := (select string_agg(public._agenda_nome_curto(py.name) || ' ' || al.turno || ' ' || coalesce(al.criterio, '-') || ' ' || (al.criterio_detalhe ->> 'regra')
                               || ' ' || (al.criterio_detalhe -> 'exigencias')::text || ' ' || (al.criterio_detalhe -> 'suposicoes')::text
                               || ' ' || (al.criterio_detalhe ->> 'lider_trocado'),
                             '; ' order by al.turno = 'tarde', py.name)
             from public.agenda_alocacoes al join public.payees py on py.id = al.payee_id
            where al.proposta_id = (v ->> 'proposta_id')::uuid and al.presenca = 'turno');
    -- a reserva (o gestor desligado: a 172 espera o "tem peça a comprar?" e vira reserva condicionada) também grava
    perform pg_temp.gestor('desligado');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97171')], '{}'::jsonb, true, 'vigia', null,
                              date '2026-11-04', pg_temp.em(date '2026-11-04', '16:25'));
    t6 := (select count(*) filter (where al.criterio is null) || ' de ' || count(*) || ' ' || string_agg(distinct al.tipo, ',')
             from public.agenda_alocacoes al where al.proposta_id = (v ->> 'proposta_id')::uuid);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M9a em teste, cada alocação gravada da proposta tem o critério e o detalhe da alocação do item (o gatilho não mexe no que o motor mandou), nenhuma sem critério, o dono presenca_do_dono, a regra antes',
    t1 like '0 diferentes de %' and t1 <> '0 diferentes de 0' and t2 = 'presenca_do_dono/antes' and t3 = 'antes' and t4 = '0',
    concat_ws(' | ', t1, t2, t3, t4));
  v_res := pg_temp.ok(v_res, 'M9b ligado, a regra 7c e o detalhe: a Bia com o João — habilidade, o teto pedido ("sobe no teto"), as suposições pessoa_sem_etiqueta (a altura dele é do padrão) e exigencia_pelo_texto (o teto veio da linha), lider_trocado false',
    t5 = 'João manha habilidade 7c ["sobe no teto"] ["pessoa_sem_etiqueta", "exigencia_pelo_texto"] false; João tarde continuidade 7c ["sobe no teto"] ["pessoa_sem_etiqueta", "exigencia_pelo_texto"] false',
    t5);
  v_res := pg_temp.ok(v_res, 'M9c a reserva condicionada (o gestor desligado) também grava o critério em toda alocação',
    t6 like '0 de % reserva' and t6 not like '0 de 0 %', t6);

  -- M9d: os outros escritores, pelo gatilho
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('sombra', 'sombra');
    -- a escada da revisão da 7a: o João não vem na ter 10/11 e a 179 (publicada com ele) troca de pessoa
    perform pg_temp.nao_vem('João', date '2026-11-10', date '2026-11-10');
    a := public._agenda_gestor_reparar(pg_temp.os('OS-97179'), date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    t1 := coalesce(a ->> 'reparado', '?') || ' ' || pg_temp.vivas('OS-97179');
    -- o corte da revisão da 7a: a Bia marcada em 1 dia passa a meio dia
    perform pg_temp.marcar(array['OS-97172', 'OS-97174']);
    update public.os_planejamento set dias = 0.5 where service_order_id = pg_temp.os('OS-97172');
    a := public._agenda_gestor_reestimar(pg_temp.os('OS-97172'), date '2026-11-04', pg_temp.em(date '2026-11-04', '16:20'));
    t2 := coalesce(a ->> 'reestimado', '?') || ' ' || pg_temp.vivas('OS-97172');
    -- o desfazer: a Duda vai para seg 09/11 a pedido do dono e volta
    a := pg_temp.marcar(array['OS-97174'], jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-97174'), 'de', '2026-11-09'))), '16:25');
    a := public.agenda_desfazer((a -> 'acoes' ->> 0)::uuid, null, 'dono', date '2026-11-04', pg_temp.em(date '2026-11-04', '16:30'));
    t3 := coalesce(a ->> 'ok', '?') || ' ' || pg_temp.vivas('OS-97174');
    -- a que já chega com critério (ou detalhe) não muda
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, motivos, criterio, criterio_detalhe)
    values (pg_temp.os('OS-97176'), pg_temp.pessoa('Rafael'), date '2026-11-16', 'manha', 'turno', 'execucao', 'publicada', 'motor', '[]'::jsonb,
            'unico', '{"regra": "teste"}'::jsonb);
    t6 := (select criterio || ' ' || (criterio_detalhe ->> 'regra') from public.agenda_alocacoes
            where service_order_id = pg_temp.os('OS-97176') and dia = date '2026-11-16');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- a 2ª pessoa da dupla da 7b (_agenda_gestor_dupla, modo_dupla ligado): a Lia (a troca do banco de baterias pede 2 nos 2 primeiros
  -- meios-dias) marcada com só o João livre; o Rafael fica livre e o passo dupla o põe junto
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('sombra', 'sombra');
    update public.agenda_config set modo_dupla = 'ligado' where id;
    perform pg_temp.nao_vem('Roberto', date '2026-11-05', date '2026-11-20');
    perform pg_temp.nao_vem('Alex', date '2026-11-05', date '2026-11-20');
    perform pg_temp.nao_vem('Rafael', date '2026-11-05', date '2026-11-20');
    perform pg_temp.nao_vem('Bruno', date '2026-11-05', date '2026-11-20');
    perform pg_temp.marcar(array['OS-97171']);
    update public.agenda_disponibilidade set substituida_em = pg_temp.em(date '2026-11-04', '16:20')
     where nota = 'não vem (teste)' and substituida_em is null and payee_id = pg_temp.pessoa('Rafael');
    a := public._agenda_gestor_dupla(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:22'));
    t4 := coalesce(a ->> 'completadas', '?') || ' ' || pg_temp.vivas('OS-97171');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- o desfazer do cliente (_agenda_desfazer_cliente): a Duda confirmou o dia (as alocações fixadas por cliente_confirmou) e o dono desfaz
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('sombra', 'sombra');
    perform pg_temp.marcar(array['OS-97174']);
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'cliente_confirmou'
     where service_order_id = pg_temp.os('OS-97174') and estado = 'publicada';
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, depois, texto, desfazivel_ate, criada_em)
    values (date '2026-11-04', true, 'sistema', 'fixar', pg_temp.os('OS-97174'), array[pg_temp.os('OS-97174')],
            jsonb_build_object('efeito', 'confirmou', 'alocacoes',
                               (select jsonb_agg(id) from public.agenda_alocacoes where service_order_id = pg_temp.os('OS-97174') and estado = 'fixada')),
            'Duda confirmou o dia (teste).', pg_temp.em(date '2026-11-05', '18:00'), pg_temp.em(date '2026-11-04', '16:20'))
    returning jsonb_build_object('id', id) into a;
    a := public._agenda_desfazer_cliente((a ->> 'id')::uuid, null, 'dono', date '2026-11-04', pg_temp.em(date '2026-11-04', '16:30'));
    t5 := coalesce(a ->> 'ok', '?') || ' ' || pg_temp.vivas('OS-97174');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M9d a escada da revisão da 7a (o João não vem; a 179 troca de pessoa): as alocações novas de turno sem critério, com a regra escada',
    t1 ~ '^true ' and t1 like '%10/11m Alex turno - escada%' and t1 like '%10/11t Alex turno - escada%', t1);
  v_res := pg_temp.ok(v_res, 'M9e o corte da revisão da 7a (a Bia de 1 dia passa a meio dia): o fechamento do dono que muda de lugar é presenca_do_dono, com a regra corte',
    t2 ~ '^true ' and t2 like '%06/11m Gustavo fechamento presenca_do_dono corte%', t2);
  v_res := pg_temp.ok(v_res, 'M9f o desfazer (a Duda volta a sex 06/11): as refeitas são fora_do_motor, a do dono presenca_do_dono',
    t3 ~ '^true ' and t3 like '%Bruno turno - fora_do_motor%' and t3 like '%Gustavo abertura presenca_do_dono fora_do_motor%', t3);
  v_res := pg_temp.ok(v_res, 'M9g a 2ª pessoa da dupla da 7b (_agenda_gestor_dupla põe o Rafael com o João nos 2 primeiros meios-dias da Lia): criterio nulo, a regra dupla',
    t4 ~ '^1 ' and t4 like '%06/11m Rafael turno - dupla%' and t4 like '%06/11t Rafael turno - dupla%', t4);
  v_res := pg_temp.ok(v_res, 'M9h o desfazer do cliente (a confirmação da Duda sai; o dia continua sem fixar): as refeitas são fora_do_motor, a do dono presenca_do_dono',
    t5 ~ '^true ' and t5 like '% turno - fora_do_motor%' and t5 like '%Gustavo abertura presenca_do_dono fora_do_motor%'
    and t5 not like '% turno % antes%', t5);
  v_res := pg_temp.ok(v_res, 'M9i a alocação que já chega com critério (ou detalhe) não muda (o gatilho só põe o que falta)', t6 = 'unico teste', t6);
  perform pg_temp.gravar(v_res);
end
$m9$;

-- ── M10. A reserva ──────────────────────────────────────────────────────────────────────────────────────────────
do $m10$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t1    text;
  t2    text;
  t3    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M10 a reserva', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- o gestor desligado: as OS da fixture esperam o "tem peça a comprar?" e só guardam lugar (a reserva condicionada, 2 pessoas)
  begin
    perform pg_temp.gestor('desligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    perform pg_temp.nao_vem('Alex', date '2026-11-05', date '2026-11-20');
    perform pg_temp.nao_vem('Rafael', date '2026-11-05', date '2026-11-20');
    perform pg_temp.nao_vem('Roberto', date '2026-11-05', date '2026-11-20');
    v := pg_temp.propor(array['OS-97176']);
    t1 := coalesce(pg_temp.mc(pg_temp.reserva(v, 'OS-97176')), '-') || ' | ' || coalesce(pg_temp.fora(v, 'OS-97176'), '-');
    update public.os_planejamento set dono_presenca = 'sempre' where service_order_id = pg_temp.os('OS-97176');
    v := pg_temp.propor(array['OS-97176']);
    t2 := coalesce(pg_temp.mc(pg_temp.reserva(v, 'OS-97176')), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M10a a reserva do Fábio (energizado em todos) com só o João (ajudante) e o Bruno (novo) livres: com o dono só abrindo e fechando, ninguém guarda o lugar (sem quem instala sozinho: sem_reserva); com o dono o tempo todo (o molde pede 1 diarista), o que o turno dele cobriria conta como atendido — o energizado e o par do novo — e o Bruno, o menos qualificado, guarda o lugar',
    t1 like '- | sem_reserva:%'
    and t2 = '06/11m Bruno:habilidade; 06/11t Bruno:continuidade; 09/11m Bruno:continuidade; 09/11t Bruno:continuidade',
    t1 || ' || ' || t2);
  begin
    perform pg_temp.gestor('desligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    perform pg_temp.nao_vem('Roberto', date '2026-11-05', date '2026-11-20');
    v := pg_temp.propor(array['OS-97175']);
    t3 := coalesce(pg_temp.mc(pg_temp.reserva(v, 'OS-97175')), '-') || ' | ' || coalesce(pg_temp.fora(v, 'OS-97175'), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M10b o responsável não é duro na reserva: com o Roberto (que fez o 1º dia) fora, o Edu guarda o lugar com outros',
    t3 not like '-%' and t3 not like '%Roberto%' and t3 like '% | -', t3);
  perform pg_temp.gravar(v_res);
end
$m10$;

-- ── M11. A compatibilidade por ausência ─────────────────────────────────────────────────────────────────────────
do $m11$
declare
  v_res   jsonb := '[]'::jsonb;
  v_novo  text;
  v_antes text;
  v_dif   text;
  c       record;
begin
  if not pg_temp.carregada() or not pg_temp.textos_ok() then
    insert into _resultado values ('M11 a compatibilidade por ausência', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  for c in select * from (values ('em teste', 'sombra'), ('ligada', 'ligado')) t(nome, m) loop
    begin
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c(c.m, c.m);
      v_novo := md5(public.agenda_encaixe_do_novo(2, '[]'::jsonb, null, date '2026-11-04')::text)
                || md5(public.agenda_encaixe_do_novo(1.5, jsonb_build_array(pg_temp.pessoa('João')), null, date '2026-11-04')::text)
                || md5(public.agenda_ctp(pg_temp.os('OS-97172'), date '2026-11-04')::text)
                || md5(public.agenda_ctp(pg_temp.os('OS-97176'), date '2026-11-04')::text)
                || md5(public.agenda_simular(2, '[]'::jsonb, null, null, date '2026-11-04')::text);
      perform pg_temp.motor_de_antes();
      v_antes := md5(public.agenda_encaixe_do_novo(2, '[]'::jsonb, null, date '2026-11-04')::text)
                 || md5(public.agenda_encaixe_do_novo(1.5, jsonb_build_array(pg_temp.pessoa('João')), null, date '2026-11-04')::text)
                 || md5(public.agenda_ctp(pg_temp.os('OS-97172'), date '2026-11-04')::text)
                 || md5(public.agenda_ctp(pg_temp.os('OS-97176'), date '2026-11-04')::text)
                 || md5(public.agenda_simular(2, '[]'::jsonb, null, null, date '2026-11-04')::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    if v_novo is distinct from v_antes then v_dif := concat_ws('; ', v_dif, c.nome || ': ' || v_novo || ' × ' || v_antes); end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'M11 as simulações que montam a própria entrada (agenda_encaixe_do_novo com e sem pessoa, agenda_ctp, agenda_simular) não mandam os parâmetros da 7c: a saída de antes, byte a byte, com a 7c em teste e ligada',
    v_dif is null, coalesce(v_dif, '—'));
  perform pg_temp.gravar(v_res);
end
$m11$;

-- ── M12. O "por que não cabe" do dia pedido ─────────────────────────────────────────────────────────────────────
do $m12$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t1    text;
  t2    text;
  t3    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M12 o por que não cabe', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    perform pg_temp.sem_179();
    perform pg_temp.nao_vem('João', date '2026-11-10', date '2026-11-10');
    perform pg_temp.nao_vem('Alex', date '2026-11-10', date '2026-11-10');
    perform pg_temp.nao_vem('Rafael', date '2026-11-10', date '2026-11-10');
    v := pg_temp.propor(array['OS-97172'], jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-97172'), 'de', '2026-11-10'))));
    t1 := pg_temp.fora(v, 'OS-97172');
    t2 := coalesce(pg_temp.mc(pg_temp.item(v, 'OS-97172')), '-');
    perform pg_temp.modos7c('sombra', 'sombra');
    t3 := pg_temp.mc(pg_temp.item(pg_temp.propor(array['OS-97172'], jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-97172'), 'de', '2026-11-10')))), 'OS-97172'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M12 o dono pede a Bia (o teto em todos) na ter 10/11 sem ninguém que sobe livre nesse dia (o Roberto não sobe; o Bruno é novo): ligado, o fora habilidade diz o porquê do dia — "Bia (OS-97172): não cabe ter 10/11: ninguém que sobe no teto fica livre nesse dia."; em teste, vai quem a regra de antes escolhe',
    t1 = 'habilidade: Bia (OS-97172): não cabe ter 10/11: ninguém que sobe no teto fica livre nesse dia.' and t2 = '-' and t3 like '10/11m %',
    concat_ws(' | ', t1, t2, t3));
  perform pg_temp.gravar(v_res);
end
$m12$;

-- ── M13. A imutável ─────────────────────────────────────────────────────────────────────────────────────────────
do $m13$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  v_id  uuid;
  v_p   uuid;
  e1    text;
  e2    text;
  e3    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M13 a imutável', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('sombra', 'sombra');
    perform pg_temp.marcar(array['OS-97174']);
    select id into v_id from public.agenda_alocacoes where service_order_id = pg_temp.os('OS-97174') and estado = 'publicada' and presenca = 'turno' limit 1;
    begin
      update public.agenda_alocacoes set criterio = 'custo' where id = v_id;
      e1 := 'mudou';
    exception when others then e1 := sqlerrm;
    end;
    begin
      update public.agenda_alocacoes set criterio_detalhe = criterio_detalhe || '{"regra": "7c"}' where id = v_id;
      e2 := 'mudou';
    exception when others then e2 := sqlerrm;
    end;
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97172')], '{}'::jsonb, true, 'vigia', null, date '2026-11-04', pg_temp.em(date '2026-11-04', '16:40'));
    select id into v_p from public.agenda_alocacoes where proposta_id = (v ->> 'proposta_id')::uuid and presenca = 'turno' limit 1;
    begin
      update public.agenda_alocacoes set criterio = 'custo' where id = v_p;
      e3 := (select criterio from public.agenda_alocacoes where id = v_p);
    exception when others then e3 := sqlerrm;
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'M13 o critério da alocação publicada não muda (nem o criterio nem o detalhe: "Alocação publicada não muda"); o da proposta, sim',
    e1 like 'Alocação publicada não muda%' and e2 like 'Alocação publicada não muda%' and e3 = 'custo', concat_ws(' | ', e1, e2, e3));
  perform pg_temp.gravar(v_res);
end
$m13$;

-- ── M15. Quem está logado ───────────────────────────────────────────────────────────────────────────────────────
do $m15$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t1    text;
  t2    text;
  t3    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M15 quem está logado', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado');
    -- a técnica logada (um login que não é admin nem financeiro), com os privilégios de sempre do caminho (a tela chama a definer)
    perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', 'c7c00000-0000-4000-8000-0000000ec001')::text, true);
    begin
      v := pg_temp.propor(array['OS-97172']);
      t1 := 'ok ' || pg_temp.mc(pg_temp.item(v, 'OS-97172')) || ' '
            || coalesce((select string_agg(distinct (a -> 'criterio_detalhe' -> 'exigencias')::text, ',') from jsonb_array_elements(pg_temp.item(v, 'OS-97172') -> 'alocacoes') a
                          where a ->> 'presenca' = 'turno'), '-');
    exception when others then t1 := 'erro ' || sqlstate || ': ' || sqlerrm;
    end;
    begin
      t2 := (public.os_exigencias(pg_temp.os('OS-97172'), date '2026-11-04'))::text;
    exception when others then t2 := 'erro ' || sqlstate;
    end;
    -- o admin logado
    perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub',
                         (select id from public.app_users where role = 'admin' and active order by id limit 1))::text, true);
    v := pg_temp.propor(array['OS-97172']);
    t3 := (select string_agg(distinct (a -> 'criterio_detalhe' -> 'exigencias')::text, ',') from jsonb_array_elements(pg_temp.item(v, 'OS-97172') -> 'alocacoes') a
            where a ->> 'presenca' = 'turno');
    perform set_config('request.jwt.claims', '', true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('request.jwt.claims', '', true);
  v_res := pg_temp.ok(v_res, 'M15 com o login da técnica (não é admin nem financeiro: agenda_marcar_os, de authenticated, chega ao motor), o motor não quebra no 42501 de os_exigencias — a Bia "não pede ninguém em especial" para ela (sem exigência no critério) — e os_exigencias direto continua 42501; com o admin logado, o motor lê o que a Bia pede ("sobe no teto")',
    t1 like 'ok 06/11m %' and t1 like '% []' and t2 = 'erro 42501' and t3 = '["sobe no teto"]', concat_ws(' | ', t1, t2, t3));
  perform pg_temp.gravar(v_res);
end
$m15$;

-- ── M14. As cópias ──────────────────────────────────────────────────────────────────────────────────────────────
do $m14$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_motor_fase7c', true), '');
  r      record;
  v_novo text;
  v_n    int;
  v_dif  text;
begin
  if not pg_temp.textos_ok() or v_mig = '' then
    insert into _resultado values ('M14 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('_agenda_contexto', 'public._agenda_contexto(date, date, date, uuid[], uuid[])', 'mig_correcao_fase7b', 2),
      ('_agenda_tentar_bloco', 'public._agenda_tentar_bloco(jsonb, boolean[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], integer[], jsonb, integer, boolean, integer)', 'mig_motor_fase7b', 10),
      ('_agenda_encaixar', 'public._agenda_encaixar(jsonb, jsonb, jsonb)', 'mig_motor_fase7b', 8),
      ('_agenda_so_diaristas', 'public._agenda_so_diaristas(jsonb, integer)', 'mig_motor_fase2', 1),
      ('_agenda_alocs_do_bloco', 'public._agenda_alocs_do_bloco(jsonb, jsonb)', 'mig_motor_fase2', 1),
      ('_agenda_por_que_nao', 'public._agenda_por_que_nao(jsonb, jsonb, integer, integer)', 'mig_teto_fase7a', 2),
      ('agenda_propor', 'public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', 'mig_correcao_fase7b', 8),
      ('_agenda_alocacoes_imutavel', 'public._agenda_alocacoes_imutavel()', 'mig_tabelas_fase2', 1)) t(nome, sig, fonte, blocos)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.sig::regprocedure;
    -- FASE 7c: (correção da revisão, 20261102100580) a correção recria agenda_propor só com acréscimos (2 blocos "-- FASE 7c: (7c
    -- correção …"; o K0 de agenda_fase77c_correcao.sql confere): os blocos do P2 se contam sem eles (o sem_7c já os tira junto)
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7c: fim', 'g');
    v_n := v_n - (select count(*) from regexp_matches(v_novo, '\n\s*-- FASE 7c: \(7c correção', 'g'));
    -- FASE 7c: fim
    if pg_temp.corpo(current_setting('agenda_teste.' || r.fonte), r.nome) = ''
       or pg_temp.sem_7c(v_novo) <> pg_temp.corpo(current_setting('agenda_teste.' || r.fonte), r.nome)
       or pg_temp.sem_7c(pg_temp.corpo(v_mig, r.nome)) <> pg_temp.corpo(current_setting('agenda_teste.' || r.fonte), r.nome)
       or v_n <> r.blocos then
      v_dif := concat_ws('; ', v_dif, format('%s (%s blocos; vivo sem eles %s × fonte %s letras)', r.nome, v_n, length(pg_temp.sem_7c(v_novo)),
                                              length(pg_temp.corpo(current_setting('agenda_teste.' || r.fonte), r.nome))));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'M14 as 8 recriadas: tirados os blocos "-- FASE 7c:", o corpo vivo e o da migration 20261102100100 são os da origem (as de 20261101100800, 20261101100300, 20261025100200, 20261031100400 e 20261025100000), byte a byte, com 2, 10, 8, 1, 1, 2, 8 e 1 blocos',
    v_dif is null, coalesce(v_dif, '—'));
  perform pg_temp.gravar(v_res);
end
$m14$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
