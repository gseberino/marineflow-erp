-- Prova da violação do publicado e da escada da revisão da Agenda de Produção, Fase 7c (pacote P3): com modo_habilidade ligado, o
-- meio-dia publicado cuja equipe não tem quem o serviço pede vira a violação habilidade (a vigia replaneja), e a escada da revisão
-- diária da 7a nunca põe sozinho quem nunca vai sozinho nem deixa o meio-dia de risco sem quem ele pede (migration 20261102100200;
-- spec-fase7c §3.1-6, §3.5, §5.3, §8.3 agenda_fase7c_violacao.sql, R5.3-2, R5.7-1/-3, R5.10-1).
-- bancada: depende de 20261102100200
--
--   V0  as portas: as 2 recriadas com as de antes (a violação só do service_role; a escada de ninguém; invoker, STABLE)
--   V1  desligado e em teste = antes: _agenda_violacoes, com os modos da 7c desligados e em sombra, sai byte a byte a de antes (a de
--       20261029100900 rodada como pg_temp) em 3 cenários (a 179 com o João sozinho no último meio-dia, com e sem o fechamento do dono
--       que cobre, e com o João que não vem); ligado sem nada faltando, também
--   V2  ligado: a 179 (o João sozinho no último meio-dia, que pede quem instala sozinho com 220 V ou banco de bateria) ganha a violação
--       habilidade, o resto do meio-dia e o depois do congelado saem junto (replanejado); o replano (o motor e a vigia) põe o Roberto no
--       último meio-dia (critério habilidade); o publicado sem o responsável da OS não é violação
--   V3  a equipe dita pelo dono (a 177, "só o João") não viola; sem a equipe dita, viola
--   V4  o fixado pelo dono não viola
--   V5  no congelado (a 179 em qui 05/11): é evento real — o replano fica no mesmo dia (hoje/amanhã), e a vigia manda o acorde
--   V6  o texto do cancelar: "Ivo (OS-97179): sai ter 10/11 — a equipe do dia não tinha quem o serviço pede."
--   V7  a cópia de _agenda_violacoes: tirados os 4 blocos "-- FASE 7c:", o corpo vivo e o da migration são o de 20261029100900
--   V8  a escada da revisão (R5.3-2): (a) a equipe real, o Alex fora qua 18/11 e o Mateus dito livre: com a 7c ligada (a 7b desligada)
--       o Mateus não entra sozinho em nenhum degrau (o Alex vai a outro dia; sem outro dia, sem conserto, e a revisão manda ao motor, que
--       nunca o deixa sozinho); em teste, a de antes (o Mateus sozinho, como a 7b desligada deixa); (b) o novo junto do técnico no mesmo
--       meio-dia entra; (c) o ajudante (o João) não entra sozinho no meio-dia de risco (o último, que pede 220 V), mas entra no que não
--       pede nada; (d) a conferência do fim: o degrau 3 que deixaria o João sozinho no último meio-dia que a OS fica tendo não vale; (e)
--       com os modos desligados (a 7b também) e com a 7c em teste e a 7b ligada, a escada de antes, byte a byte; (f) o dia fixo sem
--       diária (o Mateus com "toda terça", que na 7b conta como técnico) não entra sozinho com a 7c ligada; (g) com outro técnico
--       livre, o degrau 1 de antes, byte a byte, também com a 7c ligada
--   V9  a cópia de _agenda_gestor_reparo: tirados os 4 blocos "-- FASE 7c:" e a marca de dentro "-- (7c … -- (7c: fim)", o corpo vivo e
--       o da migration são o de 20261101100860
--   V10 quem está logado e quem chama direto: a técnica logada que marca pela tela (agenda_marcar_os → agenda_propor) não recebe o 42501
--       e não vê a violação habilidade; o admin logado vê; o service_role que chama _agenda_violacoes direto não quebra; na escada, a
--       técnica logada não quebra e o novo continua nunca sozinho
--   V11 ao ligar, com a equipe real (só o Alex e o dono, com e sem a linha dele; a 7b em teste e ligada): a carteira publicada com a 7c
--       em teste não tem nenhuma violação habilidade quando a 7c liga (nenhuma onda de replano por falta de etiqueta, R5.7-2)
--
-- Rodado sem a 20261102100200 (o harness f7c/p3/rodar-so.mjs --sem-p3), 19 das 27 linhas reprovam; passam só as que provam o byte a
-- byte e o que não é violação (V0, V1, V2d, V4, V8b, V8e, V8g e V11).
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7c_violacao.sql
--   Seguro em produção: termina em ROLLBACK. V0 roda em qualquer banco; V7 e V9 saem PULADO sem as migrations como texto; o resto usa
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
-- O texto sem os blocos "-- FASE 7c: … -- FASE 7c: fim" e sem a marca de dentro "-- (7c … -- (7c: fim)" (dentro de um bloco da 7b; R5.4
-- item 2): as linhas de abrir e de fechar saem junto.
create function pg_temp.sem_7c(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when (l ~ '^\s*-- FASE 7[cdef]:' and l !~ '^\s*-- FASE 7[cdef]: fim') or l ~ '^\s*-- \(7[cdef] ' then 1
                                                when l ~ '^\s*-- (FASE 7[cdef]: fim|\(7[cdef]: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7[cdef]: fim|\(7[cdef]: fim\))' as fecha
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
create function pg_temp.textos_ok() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.mig_correcao_calculo_fase6', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_correcao3_fase7b', true), '') <> ''
$f$;

-- ── V0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────
with f(sig, quem) as (values
  ('public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date)', 'service_role'),
  ('public._agenda_gestor_reparo(uuid, date, timestamptz)', 'ninguem'))
insert into _resultado
select 'V0 as 2 recriadas com as portas de antes: invoker, STABLE, search_path fixo; _agenda_violacoes só do service_role; _agenda_gestor_reparo de ninguém (nem do service_role); nunca anon nem authenticated',
       count(p.oid) = 2
       and bool_and(not p.prosecdef and p.provolatile = 's' and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and has_function_privilege('service_role', p.oid, 'execute') = (f.quem = 'service_role')),
       string_agg(format('%s definer=%s %s anon=%s auth=%s srv=%s', f.sig, p.prosecdef, p.provolatile,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── As definições de antes como pg_temp (a régua do byte a byte) ─────────────────────────────────────────────────
do $antes$
begin
  if not pg_temp.textos_ok() then
    return;
  end if;
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_correcao_calculo_fase6'), '_agenda_violacoes'),
                  'create or replace function public._agenda_violacoes(', 'create function pg_temp.violacoes_antes(');
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_correcao3_fase7b'), '_agenda_gestor_reparo'),
                  'create or replace function public._agenda_gestor_reparo(', 'create function pg_temp.reparo_antes(');
end
$antes$;

-- ── Os auxiliares das fixtures ─────────────────────────────────────────────────────────────────────────────────
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
-- o gestor da 7a (os 5 modos dele, com a regra escada e a revisão diária: a escada só corre com elas)
create function pg_temp.gestor(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end, modo_proposta = 'ligado',
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id
$f$;
create function pg_temp.modos7b(p_modo text) returns void language sql as $f$
  update public.agenda_config set modo_dias = p_modo, modo_dupla = p_modo, modo_sabado = p_modo, modo_cadastro = p_modo,
                                  modo_chamar = p_modo where id
$f$;
create function pg_temp.modos7c(p_modo text) returns void language sql as $f$
  update public.agenda_config set modo_habilidade = p_modo, modo_lider = p_modo, modo_habilidade_propor = p_modo where id
$f$;
create function pg_temp.nao_vem(p_nome text, p_de date, p_ate date, p_turno text default null) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(p_de, p_ate, '[]'), p_turno, 'indisponivel', 'dono', 'não vem (teste da 7c P3)', timestamptz '2026-11-04 10:01-03'
    from public.payees p where p.name = p_nome and p.active
$f$;
-- "o Mateus vem <data>": a data dita pelo dono (o que o *grava* escreve): vem sob demanda
create function pg_temp.vem(p_payee uuid, p_dia date) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  values (p_payee, daterange(p_dia, p_dia, '[]'), null, 'disponivel', 'dono', 'Você disse que vem', timestamptz '2026-11-04 10:00-03')
$f$;
-- o Mateus cadastrado agora (prestador, com telefone), como o dono faria na equipe de produção; na sintética ele já existe
create function pg_temp.mateus() returns uuid language plpgsql as $f$
declare v uuid := pg_temp.pessoa('Mateus');
begin
  if v is null then
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-04 08:00-03', timestamptz '2026-11-04 08:00-03') returning id into v;
  end if;
  return v;
end $f$;
-- uma OS do teste: aberta, aprovada, uma linha de serviço (R$ 382 por meio-dia), os dias ditos, o dono nunca (só a equipe)
create function pg_temp.nova_os(p_n text, p_nome text, p_linha text, p_dias numeric) returns uuid language plpgsql as $f$
declare v_cli uuid := md5('c7cp3:cli:' || p_n)::uuid; v_bem uuid := md5('c7cp3:bem:' || p_n)::uuid; v_os uuid := md5('c7cp3:os:' || p_n)::uuid;
begin
  insert into public.clients (id, type, name) values (v_cli, 'individual', p_nome);
  insert into public.vessels (id, client_id, name, asset_type) values (v_bem, v_cli, 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     created_at, updated_at, converted_to_os_at)
  values (v_os, 'OS-' || p_n, v_cli, v_bem, 'open', 'approved', 'repair', timestamptz '2026-10-20 10:00-03',
          timestamptz '2026-10-23 10:00-03', timestamptz '2026-10-23 10:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at, updated_at)
  values (md5('c7cp3:srv:' || p_n)::uuid, v_os, null, p_linha, 'unit', 1, 382 * p_dias * 2, 382 * p_dias * 2,
          timestamptz '2026-10-20 10:00-03', timestamptz '2026-10-20 10:00-03');
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca)
  values (v_os, p_dias, 'dono', timestamptz '2026-10-23 10:00-03', 'nunca');
  return v_os;
end $f$;
-- uma alocação publicada (ou fixada pelo dono)
create function pg_temp.pub(p_os uuid, p_payee uuid, p_dia date, p_turno text, p_presenca text default 'turno',
                            p_estado text default 'publicada') returns void language sql as $f$
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, fixado_por)
  values (p_os, p_payee, p_dia, p_turno, p_presenca, 'execucao', p_estado, 'motor', timestamptz '2026-11-02 16:30-03',
          case when p_estado = 'fixada' then 'dono' end)
$f$;
-- a OS sem nada vigente (o que estava publicado sai do caminho)
create function pg_temp.limpar(p_os uuid) returns void language sql as $f$
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado'
   where service_order_id = p_os and estado in ('publicada', 'fixada', 'proposta')
$f$;
-- a etapa da estabilidade como a vigia a chama (o vigente de hoje em diante, a carteira, a prontidão e os meios de cada OS)
create function pg_temp.viol(p_antes boolean, p_hoje date default date '2026-11-04') returns jsonb language plpgsql as $f$
declare
  v_escopo uuid[] := array(select distinct a.service_order_id from public.agenda_alocacoes a
                            where a.estado in ('publicada', 'fixada') and a.dia >= p_hoje and a.resultado is null order by 1);
  v_cart   uuid[] := array(select k.service_order_id from public.os_carteira(p_hoje) k);
  v_info   jsonb := '{}'::jsonb;
  v_cong   date := public.agenda_somar_du(p_hoje, (public._agenda_cfg()).congelamento_du);
  v_os     uuid;
begin
  foreach v_os in array v_escopo loop
    v_info := v_info || jsonb_build_object(v_os::text, jsonb_build_object('pront', public.os_prontidao(v_os, p_hoje),
                                                                          'meios', public.agenda_meios_da_os(v_os, p_hoje)));
  end loop;
  if p_antes then
    return pg_temp.violacoes_antes(v_escopo, v_cart, false, v_info, p_hoje, v_cong);
  end if;
  return public._agenda_violacoes(v_escopo, v_cart, false, v_info, p_hoje, v_cong);
end $f$;
-- as violações de uma OS em texto: "10/11t João turno habilidade*" (* = violada)
create function pg_temp.vtxt(p jsonb, p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s%s %s %s %s%s', to_char((c ->> 'dia')::date, 'DD/MM'), left(c ->> 'turno', 1),
                                    public._agenda_nome_curto(py.name), c ->> 'presenca', c ->> 'motivo',
                                    case when (c ->> 'violada')::boolean then '*' else '' end),
                             '; ' order by c ->> 'dia', c ->> 'turno' = 'tarde', c ->> 'presenca', py.name), '-')
    from jsonb_array_elements(coalesce(p, '[]'::jsonb)) c join public.payees py on py.id = (c ->> 'payee_id')::uuid
   where (c ->> 'os')::uuid = p_os
$f$;
-- o motor para as OS dadas, sem gravar, em qua 04/11 16:15
create function pg_temp.propor(p_numeros text[]) returns jsonb language sql as $f$
  select public.agenda_propor('os', null, null, array(select pg_temp.os(n) from unnest(p_numeros) n), '{}'::jsonb, false, 'vigia', null,
                              date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'))
$f$;
-- os itens de uma OS da proposta em texto: "cancelar habilidade: 10/11t João turno | criar: 06/11m João turno habilidade; …"
create function pg_temp.itens(p jsonb, p_numero text) returns text language sql immutable as $f$
  select coalesce(string_agg(format('%s %s: %s', i ->> 'op', coalesce(i ->> 'motivo', '-'),
           (select string_agg(format('%s%s %s %s%s', to_char((a ->> 'dia')::date, 'DD/MM'), left(a ->> 'turno', 1), a ->> 'nome',
                                     a ->> 'presenca', coalesce(' ' || (a ->> 'criterio'), '')), ', '
                              order by a ->> 'dia', a ->> 'turno' = 'tarde', a ->> 'presenca', a ->> 'nome')
              from jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) a)),
           ' | ' order by i ->> 'op', i ->> 'motivo'), '-')
    from jsonb_array_elements(coalesce(p -> 'itens', '[]'::jsonb)) i where i ->> 'numero' = p_numero
$f$;
-- os meios-dias vigentes da OS: "10/11m João turno -; 10/11t Roberto turno habilidade; …"
create function pg_temp.vivas(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s%s %s %s %s', to_char(a.dia, 'DD/MM'), left(a.turno, 1), public._agenda_nome_curto(py.name),
                                    a.presenca, coalesce(a.criterio, '-')), '; ' order by a.dia, a.turno = 'tarde', a.presenca, py.name), '-')
    from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
$f$;
-- a conta da escada em texto: "reparavel/degrau/motivo/Nome dd/mm t (degrau), …"
create function pg_temp.esc(r jsonb) returns text language sql immutable as $f$
  select format('%s/%s/%s/%s', r ->> 'reparavel', coalesce(r ->> 'degrau', '-'), coalesce(r ->> 'motivo', '-'),
                coalesce((select string_agg(format('%s %s %s (%s)', x #>> '{para,nome}', to_char((x #>> '{para,dia}')::date, 'DD/MM'),
                                                   left(x #>> '{para,turno}', 1), x ->> 'degrau'), ', ' order by x #>> '{para,dia}', x #>> '{para,turno}')
                            from jsonb_array_elements(coalesce(r -> 'reparos', '[]'::jsonb)) x), '-'))
         || coalesce(' falta_no_fim=' || (r ->> 'falta_no_fim'), '')
$f$;
-- os meios-dias de turno vigentes em que a pessoa está sozinha (sem outra pessoa de turno na OS)
create function pg_temp.sozinho(p_payee uuid) returns int language sql stable as $f$
  select count(*)::int from public.agenda_alocacoes a
   where a.payee_id = p_payee and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
     and not exists (select 1 from public.agenda_alocacoes b
                      where b.service_order_id = a.service_order_id and b.dia = a.dia and b.turno = a.turno and b.id <> a.id
                        and b.estado in ('publicada', 'fixada') and b.presenca = 'turno')
$f$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97171')
     and to_regprocedure('pg_temp.violacoes_antes(uuid[], uuid[], boolean, jsonb, date, date)') is not null
     and to_regprocedure('pg_temp.reparo_antes(uuid, date, timestamptz)') is not null
$f$;

-- ── V8a. A escada com a equipe real (só o Alex e o dono; antes da sintética: a variante é escolhida quando a 7b carrega) ─────
do $v8a$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-04';
  c_t    constant timestamptz := timestamptz '2026-11-04 16:53-03';
  v_alex uuid;
  v_mat  uuid;
  v_os   uuid;
  v_n    int;
  r      record;
  x      jsonb;
  y      jsonb;
  a      text := '';
  b      text := '';
  c      text := '';
begin
  if coalesce(current_setting('agenda_teste.fase7c', true), '') = '' or coalesce(current_setting('agenda_teste.fase7b', true), '') = ''
     or not pg_temp.textos_ok() or exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    insert into _resultado values ('V8a a escada com a equipe real', true, 'PULADO: sem as fixtures da 7b e da 7c e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- (i) o Alex fora qua 18/11 inteira; o Mateus (cadastrado agora) dito para qua 18/11: a 7b desligada, a 7c em teste e ligada
  for r in select * from (values (1, 'sombra'), (2, 'ligado')) t(o, m7c) order by o loop
    begin
      perform set_config('agenda_teste.fase7b_equipe', 'real', true);
      execute current_setting('agenda_teste.fase7c');
      perform set_config('agenda_teste.fase7b_equipe', '', true);
      v_alex := pg_temp.pessoa('Alex');
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c(r.m7c);
      v_mat := pg_temp.mateus();
      perform pg_temp.vem(v_mat, date '2026-11-18');
      v_os := pg_temp.nova_os('97301', 'Caio', 'Revisão elétrica', 0.5);
      perform pg_temp.pub(v_os, v_alex, date '2026-11-18', 'manha');
      perform pg_temp.nao_vem('Alex', date '2026-11-18', date '2026-11-18');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      a := a || format('[%s: %s | antes %s | papel do Mateus %s]', r.m7c, pg_temp.esc(x), pg_temp.esc(y),
                       (select h.papel || '/' || (h.fonte ->> 'papel') from public.agenda_habilidades(c_d, array[v_mat]) h));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- (ii) o Alex fora de seg 16 a qua 18/11; o Mateus dito para ter 17 e qua 18/11: a revisão (agenda_replanejar: a escada antes do
    -- motor) não conserta e o motor não deixa o Mateus sozinho
    begin
      perform set_config('agenda_teste.fase7b_equipe', 'real', true);
      execute current_setting('agenda_teste.fase7c');
      perform set_config('agenda_teste.fase7b_equipe', '', true);
      v_alex := pg_temp.pessoa('Alex');
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c(r.m7c);
      v_mat := pg_temp.mateus();
      perform pg_temp.vem(v_mat, date '2026-11-17');
      perform pg_temp.vem(v_mat, date '2026-11-18');
      v_os := pg_temp.nova_os('97301', 'Caio', 'Revisão elétrica', 0.5);
      perform pg_temp.pub(v_os, v_alex, date '2026-11-18', 'manha');
      perform pg_temp.nao_vem('Alex', date '2026-11-16', date '2026-11-18');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      perform public.agenda_replanejar(array[v_os], 'pessoa', 'vigia', c_d, c_t, null);
      v_n := (select count(*) from public.agenda_acoes ac where ac.service_order_id = v_os and ac.tipo = 'reparar');
      b := b || format('[%s: %s | ações reparar %s | o Mateus sozinho em %s meios-dias | fica %s]', r.m7c, pg_temp.esc(x), v_n,
                       pg_temp.sozinho(v_mat), pg_temp.vivas(v_os));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- (f) o dia fixo sem diária: o Mateus cadastrado agora, SEM perfil, com "toda terça" dita pelo dono (na 7b ele conta como técnico:
  -- o C2f da correção 3) — com a 7c ligada (e a 7b ligada) não entra sozinho; em teste, como a 7b (sozinho)
  for r in select * from (values (1, 'sombra'), (2, 'ligado')) t(o, m7c) order by o loop
    begin
      perform set_config('agenda_teste.fase7b_equipe', 'real', true);
      execute current_setting('agenda_teste.fase7c');
      perform set_config('agenda_teste.fase7b_equipe', '', true);
      v_alex := pg_temp.pessoa('Alex');
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('ligado'); perform pg_temp.modos7c(r.m7c);
      v_mat := pg_temp.mateus();
      insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_em)
      values (v_mat, '{2}', null, 'disponivel', 'dono', 'Você disse: toda terça', 'o Mateus vem toda terça', timestamptz '2026-11-04 10:00-03');
      v_os := pg_temp.nova_os('97301', 'Caio', 'Revisão elétrica', 0.5);
      perform pg_temp.pub(v_os, v_alex, date '2026-11-17', 'manha');
      perform pg_temp.nao_vem('Alex', date '2026-11-16', date '2026-11-20');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      c := c || format('[%s: %s | antes %s | papel %s]', r.m7c, pg_temp.esc(x), pg_temp.esc(y),
                       (select h.papel || '/' || (h.fonte ->> 'papel') from public.agenda_habilidades(c_d, array[v_mat]) h));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'V8a1 a equipe real, o Alex fora qua 18/11 e o Mateus (cadastrado agora) dito livre nesse dia, a 7b desligada: com a 7c ligada o Mateus (papel novo: vem sob demanda) não entra sozinho no degrau 1 nem no 2 — o Alex vai a outro dia da semana (degrau 3); em teste, a escada de antes (o Mateus sozinho, como a 7b desligada deixa), byte a byte',
    a = '[sombra: true/pessoa/-/Mateus 18/11 m (pessoa) | antes true/pessoa/-/Mateus 18/11 m (pessoa) | papel do Mateus 2/sob_demanda]'
        || '[ligado: true/dia/-/Alex 17/11 m (dia) | antes true/pessoa/-/Mateus 18/11 m (pessoa) | papel do Mateus 2/sob_demanda]', a);
  v_res := pg_temp.ok(v_res, 'V8a2 o Alex fora de seg 16 a qua 18/11 e o Mateus dito para ter 17 e qua 18/11: com a 7c ligada a escada não conserta (sem_lugar), a revisão manda ao motor, que nunca deixa o Mateus sozinho; em teste, a escada põe o Mateus sozinho (a de antes)',
    b like '[sombra: true/pessoa/-/Mateus 18/11 m (pessoa) | ações reparar 1 | o Mateus sozinho em 1 meios-dias | fica %'
    and b like '%[ligado: false/-/sem_lugar/- | ações reparar 0 | o Mateus sozinho em 0 meios-dias | fica %', b);
  v_res := pg_temp.ok(v_res, 'V8f o dia fixo sem diária (o Mateus cadastrado agora, sem perfil, com "toda terça" dita pelo dono; na 7b conta como técnico, o C2f da correção 3), a 7b ligada: com a 7c ligada (o papel novo dia_fixo) a escada não o põe sozinho; em teste, a de antes (sozinho, o limite da 7b)',
    c like '[sombra: true/pessoa/-/Mateus 17/11 m (pessoa) | antes true/pessoa/-/Mateus 17/11 m (pessoa) | papel %'
    and c like '%[ligado: false/-/sem_lugar/- | antes true/pessoa/-/Mateus 17/11 m (pessoa) | papel 2/dia_fixo]', c);
  perform pg_temp.gravar(v_res);
end
$v8a$;

-- ── V11. Ao ligar, com a equipe real: nenhuma violação habilidade (nenhuma onda de replano por falta de etiqueta) ──────────────────────
do $v11$
declare
  v_res  jsonb := '[]'::jsonb;
  c      record;
  v      jsonb;
  v_n    int;
  v_h    int;
  v_tot  text := '';
  v_ok   boolean := true;
begin
  if coalesce(current_setting('agenda_teste.fase7c', true), '') = '' or coalesce(current_setting('agenda_teste.fase7b', true), '') = ''
     or exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    insert into _resultado values ('V11 ao ligar, com a equipe real', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
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
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b(c.m7b); perform pg_temp.modos7c('sombra');
      -- a carteira inteira publicada em teste (o motor de hoje, com a 7c em teste), e a 7c ligada depois
      v := public.agenda_propor('os', null, null, array(select k.service_order_id from public.os_carteira(date '2026-11-04') k order by 1),
                                '{}'::jsonb, true, 'vigia', null, date '2026-11-04', pg_temp.em(date '2026-11-04', '16:30'));
      perform public.agenda_aplicar((v ->> 'proposta_id')::uuid, null, 'vigia', null, null, date '2026-11-04', pg_temp.em(date '2026-11-04', '16:30'));
      perform pg_temp.modos7c('ligado');
      v := pg_temp.viol(false);
      v_n := (select count(*) from public.agenda_alocacoes a where a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                                                              and a.presenca = 'turno' and a.dia >= date '2026-11-04');
      v_h := (select count(*) from jsonb_array_elements(v) x where x ->> 'motivo' = 'habilidade');
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_tot := v_tot || format('[%s: %s meios-dias de turno publicados, %s habilidade]', c.nome, v_n, v_h);
    v_ok := v_ok and v_n > 0 and v_h = 0;
  end loop;
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  perform set_config('agenda_teste.fase7b_dono', '', true);
  v_res := pg_temp.ok(v_res, 'V11 a equipe real (só o Alex e o dono, com e sem a linha dele; a 7b em teste e ligada): a carteira inteira publicada com a 7c em teste (13, 27 e 14 meios-dias de turno) não tem nenhuma violação habilidade quando a 7c liga — sem etiqueta vale o padrão (o Alex instala sozinho, sobe no teto) e o fechamento do dono cobre o último dia: nenhuma onda de replano ao ligar',
    v_ok, v_tot);
  perform pg_temp.gravar(v_res);
end
$v11$;

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

-- ── V1. Desligado e em teste = antes ───────────────────────────────────────────────────────────────────────────
do $v1$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  m     text;
  v_n   jsonb;
  v_a   jsonb;
  v_dif text;
  v_tot int := 0;
  v_hab text := '';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('V1 desligado e em teste = antes', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  for c in select * from (values ('a 179 com o fechamento que cobre', true, false), ('a 179 sem o fechamento que cobre', false, false),
                                 ('o João não vem ter 10/11', false, true)) t(nome, cobre, falta) loop
    foreach m in array array['desligado', 'sombra', 'ligado'] loop
      begin
        perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('sombra'); perform pg_temp.modos7c(m);
        update public.agenda_config set habilidade_fechamento_cobre = c.cobre where id;
        if c.falta then
          perform pg_temp.nao_vem('João', date '2026-11-10', date '2026-11-10');
        end if;
        v_n := pg_temp.viol(false);
        v_a := pg_temp.viol(true);
        raise exception 'desfaz' using errcode = 'P0099';
      exception when sqlstate 'P0099' then null;
      end;
      v_tot := v_tot + jsonb_array_length(v_n);
      if m <> 'ligado' or c.cobre or c.falta then
        if v_n is distinct from v_a then
          v_dif := concat_ws('; ', v_dif, format('%s, %s (%s × %s)', c.nome, m, jsonb_array_length(v_n), jsonb_array_length(v_a)));
        end if;
      else
        v_hab := pg_temp.vtxt(v_n, pg_temp.os('OS-97179')) || ' × antes ' || pg_temp.vtxt(v_a, pg_temp.os('OS-97179'));
      end if;
    end loop;
  end loop;
  v_res := pg_temp.ok(v_res, 'V1 com a 7c desligada e em teste, _agenda_violacoes sai byte a byte a de antes (a de 20261029100900 rodada no lugar), nos 3 cenários (a 179 com o João sozinho no último meio-dia, com e sem o fechamento do dono que cobre, e com o João que não vem: a pessoa vem antes da habilidade); ligada, também onde nada falta (o fechamento cobre) e onde a pessoa já saiu',
    v_dif is null and v_tot > 0, coalesce(v_dif, format('%s violações nas 9 combinações', v_tot)));
  v_res := pg_temp.ok(v_res, 'V1b (o controle) ligada e sem o fechamento que cobre, a 179 muda: a tarde do João vira habilidade e o resto sai junto',
    v_hab = '10/11m Gustavo abertura replanejado; 10/11m João turno replanejado; 10/11t Gustavo fechamento replanejado; 10/11t João turno habilidade* × antes -',
    v_hab);
  perform pg_temp.gravar(v_res);
end
$v1$;

-- ── V2–V6. Ligado: a violação habilidade, o replano, a equipe dita, o fixado, o congelado e o texto ─────────────────────────
do $v2$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  v179  uuid;
  v177  uuid;
  v175  uuid;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
  t6    text;
  t7    text;
  t8    text;
  t9    text;
  t10   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('V2 a V6 a violação habilidade', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v179 := pg_temp.os('OS-97179');
  v177 := pg_temp.os('OS-97177');
  v175 := pg_temp.os('OS-97175');
  -- V2: a 179 sem o fechamento que cobre; o Rafael e o Alex (que também instalam sozinhos) não vêm na sex 06/11, o 1º dia do replano
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    perform pg_temp.nao_vem('Rafael', date '2026-11-06', date '2026-11-06');
    perform pg_temp.nao_vem('Alex', date '2026-11-06', date '2026-11-06');
    t1 := pg_temp.vtxt(pg_temp.viol(false), v179);
    v := pg_temp.propor(array['OS-97179']);
    t2 := pg_temp.itens(v, 'OS-97179');
    t3 := (select string_agg(i ->> 'texto', ' | ' order by i ->> 'motivo') from jsonb_array_elements(v -> 'itens') i
            where i ->> 'numero' = 'OS-97179' and i ->> 'op' = 'cancelar');
    -- a vigia (a cada 15 minutos): replaneja e publica
    v := public._agenda_vigia_violacoes(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    t4 := format('violadas %s | %s | João sozinho no último meio-dia: %s', v ->> 'violadas', pg_temp.vivas(v179),
                 (select count(*) from public.agenda_alocacoes a
                   where a.service_order_id = v179 and a.estado in ('publicada', 'fixada') and a.presenca = 'turno'
                     and a.payee_id = pg_temp.pessoa('João')
                     and (a.dia, a.turno) = (select b.dia, b.turno from public.agenda_alocacoes b
                                              where b.service_order_id = v179 and b.estado in ('publicada', 'fixada') and b.presenca = 'turno'
                                              order by b.dia desc, b.turno = 'tarde' desc limit 1)
                     and not exists (select 1 from public.agenda_alocacoes b where b.service_order_id = v179 and b.dia = a.dia and b.turno = a.turno
                                       and b.id <> a.id and b.estado in ('publicada', 'fixada') and b.presenca = 'turno')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V2a ligado, a 179 Ivo (o último meio-dia pede quem instala sozinho com 220 V ou banco de bateria; o fechamento do dono não cobre): a tarde do João vira violação habilidade; a abertura e o fechamento do dono e a manhã do João (o depois do congelado e o resto do meio-dia) saem junto, replanejado',
    t1 = '10/11m Gustavo abertura replanejado; 10/11m João turno replanejado; 10/11t Gustavo fechamento replanejado; 10/11t João turno habilidade*', t1);
  v_res := pg_temp.ok(v_res, 'V2b o replano pelo motor (a 7c ligada): sai o que violou e o que vai junto; volta na sex 06/11, o João de manhã e o Roberto à tarde, no último meio-dia (critério habilidade), você abrindo e fechando',
    t2 = 'cancelar habilidade: 10/11t João turno | cancelar replanejado: 10/11m Gustavo abertura, 10/11m João turno, 10/11t Gustavo fechamento | criar -: 06/11m Gustavo abertura presenca_do_dono, 06/11m João turno habilidade, 06/11t Gustavo fechamento presenca_do_dono, 06/11t Roberto turno habilidade',
    t2);
  v_res := pg_temp.ok(v_res, 'V6 o texto do cancelar: "Ivo (OS-97179): sai ter 10/11 — a equipe do dia não tinha quem o serviço pede."',
    t3 = 'Ivo (OS-97179): sai ter 10/11 — a equipe do dia não tinha quem o serviço pede. | Ivo (OS-97179): sai ter 10/11 — replanejado junto.', t3);
  v_res := pg_temp.ok(v_res, 'V2c a vigia replaneja e publica: o Roberto no último meio-dia; o João nunca sozinho nele',
    t4 like 'violadas 1 | %06/11t Roberto turno habilidade% | João sozinho no último meio-dia: 0', t4);

  -- V2d: o publicado sem o responsável da OS (o Roberto fez o 1º dia da 175) não é violação (§3.8 d5): só a conferência da rodada o vê
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado');
    -- o João na seg 09/11 de manhã e de tarde, você fechando à tarde (o fechamento cobre o último dia: o meio-dia não pede nada)
    perform pg_temp.pub(v175, pg_temp.pessoa('João'), date '2026-11-09', 'manha');
    perform pg_temp.pub(v175, pg_temp.pessoa('João'), date '2026-11-09', 'tarde');
    perform pg_temp.pub(v175, public._agenda_dono(null), date '2026-11-09', 'tarde', 'fechamento');
    t5 := pg_temp.vtxt(pg_temp.viol(false), v175) || ' | sem o responsável: '
          || (select count(*) from public._agenda_lideres_ausentes(date '2026-11-04', date '2026-11-30', date '2026-11-04') l where l.os = v175);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V2d o publicado sem o responsável da OS (a 175: o Roberto fez o 1º dia; o João na seg 09/11, você fechando — nada falta pelo que a OS pede) não é violação, com modo_lider ligado — só a avaliação dos responsáveis ausentes (a rodada) vê os 2 meios-dias',
    t5 = '- | sem o responsável: 2', t5);

  -- V3: a equipe dita pelo dono (a 177 Gil, "só o João", o último meio-dia pede 220 V): sem violação; sem a equipe dita, viola
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    perform pg_temp.pub(v177, pg_temp.pessoa('João'), date '2026-11-11', 'manha');
    perform pg_temp.pub(v177, pg_temp.pessoa('João'), date '2026-11-11', 'tarde');
    t6 := pg_temp.vtxt(pg_temp.viol(false), v177);
    delete from public.os_planejamento_equipe where service_order_id = v177;
    t6 := t6 || ' | sem a equipe dita: ' || pg_temp.vtxt(pg_temp.viol(false), v177);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V3 a equipe dita pelo dono (a 177 Gil, "só o João", o João sozinho no último meio-dia que pede 220 V): sem violação (a palavra do dono vale); sem a equipe dita, a tarde viola e a manhã (depois do congelado) sai junto',
    t6 = '- | sem a equipe dita: 11/11m João turno replanejado; 11/11t João turno habilidade*', t6);

  -- V4: o fixado pelo dono (a tarde do João da 179 fixada por ele): sem violação
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado'
     where service_order_id = v179 and payee_id = pg_temp.pessoa('João') and turno = 'tarde' and estado = 'publicada';
    perform pg_temp.pub(v179, pg_temp.pessoa('João'), date '2026-11-10', 'tarde', 'turno', 'fixada');
    t7 := pg_temp.vtxt(pg_temp.viol(false), v179);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V4 o fixado pelo dono (a tarde do João da 179 fixada por ele): sem violação',
    t7 = '-', t7);

  -- V5: no congelado — a 179 em qui 05/11 (amanhã: o congelado vai até qui 05/11), o Rafael e o Alex sem vir nesse dia
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    perform pg_temp.nao_vem('Rafael', date '2026-11-05', date '2026-11-05');
    perform pg_temp.nao_vem('Alex', date '2026-11-05', date '2026-11-05');
    perform pg_temp.limpar(v179);
    perform pg_temp.pub(v179, pg_temp.pessoa('João'), date '2026-11-05', 'manha');
    perform pg_temp.pub(v179, pg_temp.pessoa('João'), date '2026-11-05', 'tarde');
    perform pg_temp.pub(v179, public._agenda_dono(null), date '2026-11-05', 'manha', 'abertura');
    perform pg_temp.pub(v179, public._agenda_dono(null), date '2026-11-05', 'tarde', 'fechamento');
    v := pg_temp.viol(false);
    t8 := pg_temp.vtxt(v, v179) || ' | congelado ' || (select string_agg(distinct c ->> 'congelado', ',') from jsonb_array_elements(v) c
                                                       where (c ->> 'os')::uuid = v179 and (c ->> 'violada')::boolean);
    v := pg_temp.propor(array['OS-97179']);
    t9 := pg_temp.itens(v, 'OS-97179') || ' | evento real '
          || (select i ->> 'evento_real' from jsonb_array_elements(v -> 'itens') i where i ->> 'numero' = 'OS-97179' and i ->> 'op' = 'criar');
    v := public._agenda_vigia_violacoes(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    t10 := (select string_agg(x ->> 'texto', ' | ') from jsonb_array_elements(coalesce(v -> 'acordes', '[]'::jsonb)) x
             where (x ->> 'os')::uuid = v179);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'V5a no congelado (a 179 em qui 05/11): a tarde do João viola (congelado) e o fechamento do dono sai junto; a manhã fica (o congelado só sai com a falta)',
    t8 = '05/11t Gustavo fechamento replanejado; 05/11t João turno habilidade* | congelado true', t8);
  v_res := pg_temp.ok(v_res, 'V5b é evento real: o replano fica no mesmo dia, amanhã (qui 05/11 à tarde, o Roberto, critério habilidade; você fecha)',
    t9 = 'cancelar habilidade: 05/11t João turno | cancelar replanejado: 05/11t Gustavo fechamento | criar -: 05/11t Gustavo fechamento presenca_do_dono, 05/11t Roberto turno habilidade | evento real true',
    t9);
  v_res := pg_temp.ok(v_res, 'V5c a vigia manda o acorde de amanhã com o porquê ("a equipe do dia não tinha quem o serviço pede")',
    t10 like 'Mudei a agenda de amanhã: Ivo (OS-97179): %a equipe do dia não tinha quem o serviço pede.%', t10);
  perform pg_temp.gravar(v_res);
end
$v2$;

-- ── V8b–V8e. A escada com a sintética ──────────────────────────────────────────────────────────────────────────────
do $v8$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-04';
  c_t    constant timestamptz := timestamptz '2026-11-04 16:53-03';
  v_os   uuid;
  v_mat  uuid;
  r      record;
  x      jsonb;
  y      jsonb;
  a      text;
  b      text := '';
  c      text := '';
  d      text := '';
  e      text := '';
  f      text := '';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('V8b a V8e a escada (sintética)', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- (b) o Caio com o Alex e o Rafael em qua 18/11 de manhã; o Rafael não vem; o Mateus dito para qua 18/11 é o único livre: entra junto
  -- do Alex (o responsável fica)
  for r in select * from (values (1, 'sombra'), (2, 'ligado')) t(o, m7c) order by o loop
    begin
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c(r.m7c);
      v_mat := pg_temp.pessoa('Mateus');
      perform pg_temp.vem(v_mat, date '2026-11-18');
      foreach a in array array['Roberto', 'João', 'Bruno'] loop
        perform pg_temp.nao_vem(a, date '2026-11-16', date '2026-11-20');
      end loop;
      v_os := pg_temp.nova_os('97301', 'Caio', 'Revisão elétrica', 1);
      perform pg_temp.pub(v_os, pg_temp.pessoa('Alex'), date '2026-11-18', 'manha');
      perform pg_temp.pub(v_os, pg_temp.pessoa('Rafael'), date '2026-11-18', 'manha');
      perform pg_temp.nao_vem('Rafael', date '2026-11-18', date '2026-11-18', 'manha');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      b := b || format('[%s: %s | igual %s]', r.m7c, pg_temp.esc(x), (x = y)::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- (c) o ajudante (o João) e o meio-dia de risco: a "Troca do banco de baterias" (pede quem instala sozinho com 220 V ou banco de
  -- bateria no último dia; o dono nunca vai), com o Roberto; o Roberto não vem; o Alex, o Rafael e o Bruno fora a semana toda
  for r in select * from (values (1, 'sombra'), (2, 'ligado')) t(o, m7c) order by o loop
    -- (c1) um meio-dia só (o último): o Roberto fora a semana toda; só o João livre
    begin
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c(r.m7c);
      foreach a in array array['Alex', 'Rafael', 'Bruno', 'Roberto'] loop
        perform pg_temp.nao_vem(a, date '2026-11-16', date '2026-11-20');
      end loop;
      v_os := pg_temp.nova_os('97302', 'Davi', 'Troca do banco de baterias', 0.5);
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'manha');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      c := c || format('[%s, o último: %s | antes %s]', r.m7c, pg_temp.esc(x), pg_temp.esc(y));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- (c2) dois meios-dias (qua 18/11 manhã e tarde, o Roberto); o Roberto não vem só de manhã: a manhã não é a última, não pede nada
    begin
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c(r.m7c);
      foreach a in array array['Alex', 'Rafael', 'Bruno'] loop
        perform pg_temp.nao_vem(a, date '2026-11-16', date '2026-11-20');
      end loop;
      v_os := pg_temp.nova_os('97302', 'Davi', 'Troca do banco de baterias', 1);
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'manha');
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'tarde');
      perform pg_temp.nao_vem('Roberto', date '2026-11-18', date '2026-11-18', 'manha');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      c := c || format('[%s, a manhã: %s]', r.m7c, pg_temp.esc(x));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- (d) a conferência do fim: o Davi com o João na ter 17/11 (manhã e tarde) e o Roberto na qua 18/11 de manhã (o último, que pede 220
  -- V); o Roberto não vem na qua 18/11; o Alex, o Rafael e o Bruno fora a semana toda. O degrau 1 e o 2 (o João) não valem (o último);
  -- o degrau 3 levaria o Roberto para seg 16/11 e deixaria o João sozinho na ter 17/11 à tarde, que passaria a ser o último
  for r in select * from (values (1, 'sombra'), (2, 'ligado')) t(o, m7c) order by o loop
    begin
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c(r.m7c);
      foreach a in array array['Alex', 'Rafael', 'Bruno'] loop
        perform pg_temp.nao_vem(a, date '2026-11-16', date '2026-11-20');
      end loop;
      v_os := pg_temp.nova_os('97302', 'Davi', 'Troca do banco de baterias', 1.5);
      perform pg_temp.pub(v_os, pg_temp.pessoa('João'), date '2026-11-17', 'manha');
      perform pg_temp.pub(v_os, pg_temp.pessoa('João'), date '2026-11-17', 'tarde');
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'manha');
      perform pg_temp.nao_vem('Roberto', date '2026-11-18', date '2026-11-18');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      d := d || format('[%s: %s | antes %s]', r.m7c, pg_temp.esc(x), pg_temp.esc(y));
      -- sem o João na ter 17/11 (o Roberto lá): o degrau 3 leva o Roberto e o último fica com quem atende
      perform pg_temp.limpar(v_os);
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-17', 'manha');
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-17', 'tarde');
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'manha');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      d := d || format('[%s, com o Roberto na ter 17/11: %s]', r.m7c, pg_temp.esc(x));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- (g) com outro técnico livre (R5.7-1 (ii)): o Caio só com o Rafael em qua 18/11 de manhã; o Rafael não vem; o Alex (e os outros)
  -- livres: com a 7c ligada, o degrau 1 de antes, byte a byte (com a 7b desligada e ligada)
  for r in select * from (values (1, 'desligado'), (2, 'ligado')) t(o, m7b) order by o loop
    begin
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b(r.m7b); perform pg_temp.modos7c('ligado');
      v_os := pg_temp.nova_os('97301', 'Caio', 'Revisão elétrica', 0.5);
      perform pg_temp.pub(v_os, pg_temp.pessoa('Rafael'), date '2026-11-18', 'manha');
      perform pg_temp.nao_vem('Rafael', date '2026-11-18', date '2026-11-18', 'manha');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      f := f || format('[7b %s: %s | igual %s]', r.m7b, pg_temp.esc(x), (x = y)::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- (e) os modos desligados (a 7b também) e a 7c em teste com a 7b ligada: a escada de antes, byte a byte, em 3 casos (o (b), o (c1)
  -- e o (d))
  for r in select * from (values (1, 'desligado', 'desligado'), (2, 'sombra', 'ligado'), (3, 'desligado', 'sombra')) t(o, m7c, m7b) order by o loop
    begin
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b(r.m7b); perform pg_temp.modos7c(r.m7c);
      v_mat := pg_temp.pessoa('Mateus');
      perform pg_temp.vem(v_mat, date '2026-11-18');
      foreach a in array array['Roberto', 'João', 'Bruno'] loop
        perform pg_temp.nao_vem(a, date '2026-11-16', date '2026-11-20');
      end loop;
      v_os := pg_temp.nova_os('97301', 'Caio', 'Revisão elétrica', 1);
      perform pg_temp.pub(v_os, pg_temp.pessoa('Alex'), date '2026-11-18', 'manha');
      perform pg_temp.pub(v_os, pg_temp.pessoa('Rafael'), date '2026-11-18', 'manha');
      perform pg_temp.nao_vem('Rafael', date '2026-11-18', date '2026-11-18', 'manha');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      e := e || format('[%s/%s caio %s', r.m7c, r.m7b, (x = y)::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    begin
      perform pg_temp.gestor('ligado'); perform pg_temp.modos7b(r.m7b); perform pg_temp.modos7c(r.m7c);
      foreach a in array array['Alex', 'Rafael', 'Bruno', 'Roberto'] loop
        perform pg_temp.nao_vem(a, date '2026-11-16', date '2026-11-20');
      end loop;
      v_os := pg_temp.nova_os('97302', 'Davi', 'Troca do banco de baterias', 0.5);
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'manha');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      e := e || format(', davi %s', (x = y)::text);
      perform pg_temp.limpar(v_os);
      perform pg_temp.pub(v_os, pg_temp.pessoa('João'), date '2026-11-17', 'manha');
      perform pg_temp.pub(v_os, pg_temp.pessoa('João'), date '2026-11-17', 'tarde');
      perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'manha');
      delete from public.agenda_disponibilidade where payee_id = pg_temp.pessoa('Roberto') and nota = 'não vem (teste da 7c P3)';
      perform pg_temp.nao_vem('Roberto', date '2026-11-18', date '2026-11-18');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      e := e || format(', fim %s (%s)]', (x = y)::text, pg_temp.esc(x));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'V8b o novo junto do técnico no mesmo meio-dia entra: o Caio com o Alex e o Rafael em qua 18/11 de manhã, o Rafael não vem e o Mateus (vem sob demanda, papel novo) é o único livre — entra no degrau 1 ao lado do Alex, com a 7c ligada como em teste (byte a byte)',
    b = '[sombra: true/pessoa/-/Mateus 18/11 m (pessoa) | igual true][ligado: true/pessoa/-/Mateus 18/11 m (pessoa) | igual true]', b);
  v_res := pg_temp.ok(v_res, 'V8c o ajudante e o meio-dia de risco (a "Troca do banco de baterias": o último meio-dia pede quem instala sozinho com 220 V ou banco de bateria; o dono nunca vai): com a 7c ligada, o João não entra sozinho no último (sem conserto: a OS vai ao motor), mas entra na manhã que não é a última (não pede nada); em teste, a de antes (o João no último)',
    c = '[sombra, o último: true/pessoa/-/João 18/11 m (pessoa) | antes true/pessoa/-/João 18/11 m (pessoa)][sombra, a manhã: true/pessoa/-/João 18/11 m (pessoa)]'
        || '[ligado, o último: false/-/sem_lugar/- | antes true/pessoa/-/João 18/11 m (pessoa)][ligado, a manhã: true/pessoa/-/João 18/11 m (pessoa)]', c);
  v_res := pg_temp.ok(v_res, 'V8d a conferência do fim (7c ligada): o degrau 3 que levaria o Roberto para seg 16/11 e deixaria o João sozinho no novo último meio-dia (ter 17/11 à tarde, que pede 220 V) não vale — sem conserto, falta energizado no fim; com o Roberto na ter 17/11, o degrau 3 vale; em teste, a de antes (o João no degrau 1)',
    d like '[sombra: true/pessoa/-/João 18/11 m (pessoa) | antes true/pessoa/-/João 18/11 m (pessoa)][sombra, com o Roberto na ter 17/11: %'
    and d like '%[ligado: false/-/sem_lugar/Roberto 16/11 m (dia) falta_no_fim=energizado | antes true/pessoa/-/João 18/11 m (pessoa)][ligado, com o Roberto na ter 17/11: true/dia/-/Roberto 16/11 m (dia)]', d);
  v_res := pg_temp.ok(v_res, 'V8e com os modos da 7c desligados (a 7b desligada e em teste) e com a 7c em teste e a 7b ligada, a escada é a de antes (a de 20261101100860 rodada no lugar), byte a byte, nos casos (b), (c) e (d)',
    e = '[desligado/desligado caio true, davi true, fim true (true/pessoa/-/João 18/11 m (pessoa))][sombra/ligado caio true, davi true, fim true (true/pessoa/-/João 18/11 m (pessoa))][desligado/sombra caio true, davi true, fim true (true/pessoa/-/João 18/11 m (pessoa))]', e);
  v_res := pg_temp.ok(v_res, 'V8g com outro técnico livre (o Caio só com o Rafael, que não vem em qua 18/11 de manhã; o Alex livre), com a 7c ligada: o degrau 1 de antes, byte a byte, com a 7b desligada e ligada (R5.7-1 (ii))',
    f = '[7b desligado: true/pessoa/-/Alex 18/11 m (pessoa) | igual true][7b ligado: true/pessoa/-/Alex 18/11 m (pessoa) | igual true]', f);
  perform pg_temp.gravar(v_res);
end
$v8$;

-- ── V10. Quem está logado e quem chama direto ─────────────────────────────────────────────────────────────────────
do $v10$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-04';
  c_t    constant timestamptz := timestamptz '2026-11-04 16:53-03';
  v      jsonb;
  v179   uuid;
  v_os   uuid;
  v_mat  uuid;
  a      text;
  t1     text;
  t2     text;
  t3     text;
  t4     text;
  t5     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('V10 quem está logado', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v179 := pg_temp.os('OS-97179');
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    -- a técnica logada (um login que não é admin nem financeiro), pelo caminho da tela (agenda_marcar_os → agenda_propor, definer)
    perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', 'c7c00000-0000-4000-8000-0000000ec003')::text, true);
    begin
      v := pg_temp.propor(array['OS-97179']);
      t1 := 'ok ' || pg_temp.itens(v, 'OS-97179');
    exception when others then t1 := 'erro ' || sqlstate || ': ' || sqlerrm;
    end;
    -- o admin logado
    perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', pg_temp.adm())::text, true);
    v := pg_temp.propor(array['OS-97179']);
    t2 := (select string_agg(i ->> 'motivo', ',' order by i ->> 'motivo') from jsonb_array_elements(v -> 'itens') i
            where i ->> 'numero' = 'OS-97179' and i ->> 'op' = 'cancelar');
    perform set_config('request.jwt.claims', '', true);
    -- o service_role que chama a violação direto (ela tem o grant dele; a avaliação do publicado não)
    t3 := pg_temp.como('service_role', format(
            'select public._agenda_violacoes(array[%L]::uuid[], array(select k.service_order_id from public.os_carteira(date ''2026-11-04'') k), false, ''{}''::jsonb, date ''2026-11-04'', date ''2026-11-05'')::text',
            v179));
    t3 := case when t3 like 'erro%' then t3
               else 'ok ' || coalesce((select string_agg(distinct c ->> 'motivo', ',') from jsonb_array_elements(t3::jsonb) c), '-') end;
    t4 := (select string_agg(distinct c ->> 'motivo', ',') from jsonb_array_elements(
             public._agenda_violacoes(array[v179], array(select k.service_order_id from public.os_carteira(date '2026-11-04') k), false,
                                      '{}'::jsonb, date '2026-11-04', date '2026-11-05')) c);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('request.jwt.claims', '', true);
  -- a escada com a técnica logada: o Davi (o último pede 220 V) só com o João livre, e o Mateus (o novo) dito livre num outro caso
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado');
    foreach a in array array['Alex', 'Rafael', 'Bruno', 'Roberto'] loop
      perform pg_temp.nao_vem(a, date '2026-11-16', date '2026-11-20');
    end loop;
    v_os := pg_temp.nova_os('97302', 'Davi', 'Troca do banco de baterias', 0.5);
    perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'manha');
    perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', 'c7c00000-0000-4000-8000-0000000ec003')::text, true);
    begin
      t5 := 'davi ' || pg_temp.esc(public._agenda_gestor_reparo(v_os, c_d, c_t));
    exception when others then t5 := 'erro ' || sqlstate || ': ' || sqlerrm;
    end;
    perform set_config('request.jwt.claims', '', true);
    perform pg_temp.limpar(v_os);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado'
     where payee_id = pg_temp.pessoa('João') and estado in ('publicada', 'fixada') and dia between date '2026-11-16' and date '2026-11-20';
    perform pg_temp.nao_vem('João', date '2026-11-16', date '2026-11-20');
    v_mat := pg_temp.pessoa('Mateus');
    perform pg_temp.vem(v_mat, date '2026-11-18');
    perform pg_temp.pub(v_os, pg_temp.pessoa('Roberto'), date '2026-11-18', 'manha');
    perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', 'c7c00000-0000-4000-8000-0000000ec003')::text, true);
    begin
      t5 := t5 || ' | mateus ' || pg_temp.esc(public._agenda_gestor_reparo(v_os, c_d, c_t));
    exception when others then t5 := t5 || ' | erro ' || sqlstate || ': ' || sqlerrm;
    end;
    perform set_config('request.jwt.claims', '', true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('request.jwt.claims', '', true);
  v_res := pg_temp.ok(v_res, 'V10a com o login da técnica (não é admin nem financeiro: agenda_marcar_os, de authenticated, chega ao motor), o motor não quebra no 42501 de os_exigencias e não vê a violação habilidade da 179 (a vigia a vê); com o admin logado, vê',
    t1 = 'ok -' and t2 = 'habilidade,replanejado', concat_ws(' | ', t1, t2));
  v_res := pg_temp.ok(v_res, 'V10b o service_role que chama _agenda_violacoes direto (ela tem o grant dele; a avaliação do publicado é só dos definer) não quebra e não vê a violação habilidade; o dono das funções (o caminho do motor e da vigia) vê',
    t3 = 'ok -' and t4 = 'habilidade,replanejado', concat_ws(' | ', t3, t4));
  v_res := pg_temp.ok(v_res, 'V10c a escada com o login da técnica não quebra: o que a OS pede não é lido (o João entra no último meio-dia do Davi, como no motor para ela), e o novo continua nunca sozinho (o Mateus não entra)',
    t5 = 'davi true/pessoa/-/João 18/11 m (pessoa) | mateus false/-/sem_lugar/-', t5);
  perform pg_temp.gravar(v_res);
end
$v10$;

-- ── V7 e V9. As cópias ─────────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_violacao_fase7c', true), '');
  r      record;
  v_novo text;
  v_n    int;
  v_m    int;
  v_dif  text;
begin
  if not pg_temp.textos_ok() or v_mig = '' then
    insert into _resultado values ('V7 e V9 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for r in select * from (values
      ('V7', '_agenda_violacoes', 'public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date)', 'mig_correcao_calculo_fase6', '20261029100900', 4, 0),
      ('V9', '_agenda_gestor_reparo', 'public._agenda_gestor_reparo(uuid, date, timestamptz)', 'mig_correcao3_fase7b', '20261101100860', 4, 1))
      t(id, nome, sig, fonte, versao, blocos, marcas)
  loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = r.sig::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7c: fim', 'g');
    select count(*) into v_m from regexp_matches(v_novo, '-- \(7c: fim\)', 'g');
    v_dif := null;
    if pg_temp.corpo(current_setting('agenda_teste.' || r.fonte), r.nome) = ''
       or pg_temp.sem_7c(v_novo) <> pg_temp.corpo(current_setting('agenda_teste.' || r.fonte), r.nome)
       or pg_temp.sem_7c(pg_temp.corpo(v_mig, r.nome)) <> pg_temp.corpo(current_setting('agenda_teste.' || r.fonte), r.nome)
       or v_n <> r.blocos or v_m <> r.marcas then
      v_dif := format('%s blocos, %s marcas; vivo sem eles %s × fonte %s letras', v_n, v_m, length(pg_temp.sem_7c(v_novo)),
                      length(pg_temp.corpo(current_setting('agenda_teste.' || r.fonte), r.nome)));
    end if;
    v_res := pg_temp.ok(v_res, format('%s a cópia de %s: tirados os %s blocos "-- FASE 7c:"%s, o corpo vivo e o da migration 20261102100200 são o de %s, byte a byte',
                                      r.id, r.nome, r.blocos, case when r.marcas > 0 then format(' e a %s marca de dentro "-- (7c … -- (7c: fim)" (no bloco da correção 3 da 7b)', r.marcas) else '' end,
                                      r.versao),
                        v_dif is null, coalesce(v_dif, format('%s blocos, %s marcas', v_n, v_m)));
  end loop;
  perform pg_temp.gravar(v_res);
end
$copia$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
