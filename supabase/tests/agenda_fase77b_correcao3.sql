-- Prova da correção 3 da Agenda de Produção, Fase 7b (migration 20261101100860): o R5.9 da spec da 7c ("para o fio principal") e o
-- W3a da correção 2. Rodado sem a 20261101100860 (o harness f7b/c3/rodar.mjs --sem-c3), 18 das 27 linhas reprovam (C0, C0b, C1, C2a,
-- C2b, C3a, C3b, C4a e C4b); passam só as que provam o byte a byte (C2c, C2d, C2e, C2f, C3c, C3d, C4c, C9a e C9b).
-- bancada: depende de 20261101100860
--
--   C0  as cópias e as portas: as 5 recriadas, tirados os blocos "(correção 3)", são o corpo da definição mais nova (100300, 100750,
--       100800 duas vezes e 20261025100200), com o número de blocos; as 2 novas e as 5 recriadas com as portas certas
--   C1  o técnico declarado nunca é novato (_agenda_tecnico_declarado dentro de _agenda_e_novato): (a) o Alex de produção sem perfil não
--       é novato (igual antes); (b) com um perfil de diária novo (desde seg 02/11, 0 diárias) não é (antes era); (c) depois de responder os
--       próprios dias (o padrão do dono substituído por um de origem diarista) não é; (d) o Mateus cadastrado agora com "toda terça" dita
--       pelo dono (e um perfil de hoje) é; (e) o Bruno da fixture é; (f) o motor na carteira inteira, com o perfil novo do Alex e a dupla em
--       teste e ligada, marca o mesmo que sem o perfil (antes, nada: a agenda inteira parava)
--   C2  a escada da revisão da 7a nunca põe sozinho quem nunca vai sozinho (o Mateus dito numa data: vem sob demanda), com a dupla em
--       teste e ligada: (a) o Alex fora o dia todo e o Mateus livre no mesmo dia — nem no degrau 1 nem no 2: o Alex vai a outro dia da
--       semana (degrau 3); o Mateus só noutro dia da semana — nem no degrau 3: sem conserto (a OS vai ao motor); (b) com o Mateus livre
--       no meio-dia e na véspera: sem conserto, nenhuma ação reparar, e o motor não deixa o Mateus sozinho; (c) com a dupla desligada, a
--       escada de antes, byte a byte (o Mateus sozinho, como antes); (d) o Mateus junto de outra pessoa que pode ficar sozinha no mesmo
--       meio-dia (o Rafael sai, o Alex fica) entra, byte a byte o de antes; (e) com outro técnico livre, o degrau 1 de antes, byte a byte;
--       (f) o limite da 7b (a revisão da correção 3): o Mateus SEM perfil de diária com "toda terça" dita pelo dono (um dia fixo) não é
--       novato nem vem sob demanda — conta como técnico: a escada o põe como antes, byte a byte, e o motor também (o roteiro pede as datas)
--   C3  o prazo na forma curta da linha (n): (a) a chamada com o cadastro ligado: o texto_curto diz "— sem resposta até ter 10/11 às 18:00,
--       sigo assim" e, depois do registro e da rodada seguinte, o veto_ate gravado é ter 10/11 18:00; (b) com a pergunta dos dias da semana
--       (os dias ligados): "— sem resposta até qui 12/11 às 16:00, sigo assim", e ela vence exatamente então (15:59 aberta, 16:00
--       vencida); (c) a forma longa e as outras linhas, byte a byte; o texto_curto até 300 letras e mais curto que o longo; (d) com o
--       cadastro desligado (a chamada da 7a, que não vence) e com o telefone, a saída inteira de antes, byte a byte
--   C4  (o W3a da correção 2) com a linha dos dias do dono, o Lenine com você o tempo todo e a 7b como o ligar a deixa: (a) o Mateus
--       que o dono chamou para ter 10/11 entra na dupla com o Alex e você, e a revisão do dia seguinte tira só ter 17/11 com o texto da
--       dupla; (b) _agenda_dupla_sem_falta_voce tira só a regra 4 "falta você" do meio-dia em que o dono já está de turno; (c)
--       agenda_validar de uma proposta do motor (não da dupla), byte a byte
--   C9  sem os casos: _agenda_e_novato de cada pessoa das duas fixtures, em dois dias, = o de antes; a saída de
--       _agenda_linhas_do_fechamento com os modos da 7b desligados e em teste (sem perguntas da equipe) = a de antes
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase77b_correcao3.sql
--   Seguro em produção: termina em ROLLBACK. C0b (as portas) roda em qualquer banco; as cópias saem PULADO sem as migrations como
--   texto; o resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';
-- a equipe de produção (só o Alex e o dono): antes de carregar a fixture da 7b
select set_config('agenda_teste.fase7b_equipe', 'real', true);

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
-- O texto sem os blocos desta correção: "-- FASE 7b: (correção 3) … -- FASE 7b: fim (correção 3)" e, dentro de um bloco da 7b de
-- antes, "-- (correção 3) … -- (correção 3: fim)" (as linhas de abrir e de fechar saem junto). (FASE 7c: e os blocos "-- FASE 7c: …
-- -- FASE 7c: fim" de uma recriação depois desta — a 20261102100000 recria _agenda_e_novato, só acréscimo —: a cópia continua
-- conferida contra a fonte desta correção). (FASE 7c (P5): e as marcas de dentro "-- (7c … -- (7c: fim)" que a 20261102100400 põe
-- dentro do bloco da 7b da linha (n) de _agenda_linhas_do_fechamento — só acréscimo)
create function pg_temp.sem_c3(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- (FASE 7b: )?\(correção 3\)'
                                                     or (l ~ '^\s*-- FASE 7c:' and l !~ '^\s*-- FASE 7c: fim')
                                                     or (l ~ '^\s*-- \(7c ' and l !~ '^\s*-- \(7c: fim\)') then 1
                                                when l ~ '^\s*-- (FASE 7b: fim \(correção 3\)|\(correção 3: fim\)|FASE 7c: fim|\(7c: fim\))' then -1
                                                else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7b: fim \(correção 3\)|\(correção 3: fim\)|FASE 7c: fim|\(7c: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;

-- ── C0. As cópias e as portas ──────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  f      record;
  v_mig  text;
  v_novo text;
  v_n    int;
begin
  for f in select * from (values
      ('_agenda_e_novato', 'public._agenda_e_novato(uuid, date)', 'mig_motor_fase7b', '20261101100300', 1),
      ('_agenda_gestor_reparo', 'public._agenda_gestor_reparo(uuid, date, timestamptz)', 'mig_revisao_fase7a', '20261031100750', 1),
      ('_agenda_linhas_do_fechamento', 'public._agenda_linhas_do_fechamento(date)', 'mig_correcao_fase7b', '20261101100800', 2),
      ('_agenda_gestor_dupla', 'public._agenda_gestor_dupla(date, timestamptz)', 'mig_correcao_fase7b', '20261101100800', 1),
      ('agenda_validar', 'public.agenda_validar(uuid, uuid[], date, timestamptz, uuid)', 'mig_motor_fase2', '20261025100200', 1))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('C0 %s: a cópia', f.nome), true, format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    select count(*) into v_n from unnest(string_to_array(v_novo, E'\n')) l where l ~ '^\s*-- (FASE 7b: )?\(correção 3\)';
    insert into _resultado values (
      format('C0 %s: sem os %s blocos da correção 3, é o corpo de %s', f.nome, f.blocos, f.versao),
      pg_temp.corpo(v_mig, f.nome) <> '' and pg_temp.sem_c3(v_novo) = pg_temp.corpo(v_mig, f.nome) and v_n = f.blocos,
      format('blocos %s; fonte %s letras; novo sem os blocos %s letras', v_n, length(pg_temp.corpo(v_mig, f.nome)), length(pg_temp.sem_c3(v_novo))));
  end loop;
end
$copia$;
with f(sig, quem, vol) as (values
  ('public._agenda_tecnico_declarado(uuid, date)', 'leitura', 's'),
  ('public._agenda_dupla_sem_falta_voce(jsonb)', 'leitura', 's'),
  ('public._agenda_e_novato(uuid, date)', 'leitura', 's'),
  ('public._agenda_linhas_do_fechamento(date)', 'leitura', 's'),
  ('public.agenda_validar(uuid, uuid[], date, timestamptz, uuid)', 'leitura', 's'),
  ('public._agenda_gestor_reparo(uuid, date, timestamptz)', 'ninguem', 's'),
  ('public._agenda_gestor_dupla(date, timestamptz)', 'ninguem', 'v'))
insert into _resultado
select 'C0b as 2 novas e as 5 recriadas com as portas certas (invoker, search_path fixo; o novato, o declarado, a régua da dupla, o fechamento e agenda_validar: authenticated e service_role; a escada e o passo dupla: ninguém; nunca anon)',
       count(p.oid) = 7
       and bool_and(not p.prosecdef and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute') end),
       string_agg(format('%s %s definer=%s anon=%s auth=%s srv=%s', f.sig, p.provolatile, p.prosecdef,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── As fixtures e as definições de antes (uma vez; cada caso abaixo roda numa subtransação desfeita) ───────────────
do $carga$
declare
  v_m text;
begin
  if coalesce(current_setting('agenda_teste.fase7b', true), '') = '' or coalesce(current_setting('agenda_teste.fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    return;
  end if;
  execute current_setting('agenda_teste.fase7b');
  v_m := coalesce(current_setting('agenda_teste.mig_motor_fase7b', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, '_agenda_e_novato'), 'create or replace function public._agenda_e_novato(',
                    'create function pg_temp.novato_antes(');
  end if;
  v_m := coalesce(current_setting('agenda_teste.mig_revisao_fase7a', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, '_agenda_gestor_reparo'), 'create or replace function public._agenda_gestor_reparo(',
                    'create function pg_temp.reparo_antes(');
  end if;
  v_m := coalesce(current_setting('agenda_teste.mig_correcao_fase7b', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, '_agenda_linhas_do_fechamento'), 'create or replace function public._agenda_linhas_do_fechamento(',
                    'create function pg_temp.linhas_antes(');
  end if;
  v_m := coalesce(current_setting('agenda_teste.mig_motor_fase2', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, 'agenda_validar'), 'create or replace function public.agenda_validar(',
                    'create function pg_temp.validar_antes(');
  end if;
end
$carga$;

create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97101')
     and to_regprocedure('pg_temp.novato_antes(uuid, date)') is not null
     and to_regprocedure('pg_temp.reparo_antes(uuid, date, timestamptz)') is not null
     and to_regprocedure('pg_temp.linhas_antes(date)') is not null
     and to_regprocedure('pg_temp.validar_antes(uuid, uuid[], date, timestamptz, uuid)') is not null
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
-- a fixture da 7b de novo (o que ainda não está, entra): equipe '' = a sintética (Mateus, Rafael, Bruno); dono 'campo' = a linha
-- seg–sex do dono
create function pg_temp.carregar(p_equipe text, p_dono text) returns void language plpgsql as $f$
begin
  perform set_config('agenda_teste.fase7b_equipe', coalesce(p_equipe, ''), true);
  perform set_config('agenda_teste.fase7b_dono', coalesce(p_dono, ''), true);
  execute current_setting('agenda_teste.fase7b');
  perform set_config('agenda_teste.fase7b_dono', '', true);
end $f$;
-- o declarado (null sem a função: a régua de antes da correção 3)
create function pg_temp.declarado(p_payee uuid, p_dia date) returns boolean language plpgsql as $f$
declare v boolean;
begin
  if to_regprocedure('public._agenda_tecnico_declarado(uuid, date)') is null then return null; end if;
  execute 'select public._agenda_tecnico_declarado($1, $2)' into v using p_payee, p_dia;
  return v;
end $f$;
-- um perfil de diária (do pagamento) desde p_desde, sem diárias
create function pg_temp.perfil(p_payee uuid, p_desde date) returns void language sql as $f$
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, jornada_diaria_horas, meia_diaria_ate_horas,
                                    vigencia_inicio, vigencia_fim, created_at, updated_at)
  values (p_payee, 'diarista', 'diaria', 200, 8, 4, p_desde, null, (p_desde + time '10:00') at time zone 'America/Sao_Paulo',
          (p_desde + time '10:00') at time zone 'America/Sao_Paulo')
$f$;
-- o gestor da 7a (os 5 modos dele, com a regra escada) e os modos da 7b
create function pg_temp.modos7a(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'
   where id
$f$;
-- uma OS do teste: aberta, aprovada, uma linha de serviço (R$ 382 por meio-dia), os dias ditos, você nunca (só a equipe)
create function pg_temp.c3_os(p_n text, p_nome text, p_dias numeric) returns uuid language plpgsql as $f$
declare v_cli uuid := md5('c3:cli:' || p_n)::uuid; v_bem uuid := md5('c3:bem:' || p_n)::uuid; v_os uuid := md5('c3:os:' || p_n)::uuid;
begin
  insert into public.clients (id, type, name) values (v_cli, 'individual', p_nome);
  insert into public.vessels (id, client_id, name, asset_type) values (v_bem, v_cli, 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     created_at, updated_at, converted_to_os_at)
  values (v_os, 'OS-' || p_n, v_cli, v_bem, 'open', 'approved', 'repair', timestamptz '2026-10-20 10:00-03',
          timestamptz '2026-10-23 10:00-03', timestamptz '2026-10-23 10:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at, updated_at)
  values (md5('c3:srv:' || p_n)::uuid, v_os, null, 'Revisão elétrica', 'unit', 1, 382 * p_dias * 2, 382 * p_dias * 2,
          timestamptz '2026-10-20 10:00-03', timestamptz '2026-10-20 10:00-03');
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca)
  values (v_os, p_dias, 'dono', timestamptz '2026-10-23 10:00-03', 'nunca');
  return v_os;
end $f$;
create function pg_temp.c3_aloc(p_os uuid, p_payee uuid, p_dia date, p_turno text) returns void language sql as $f$
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  values (p_os, p_payee, p_dia, p_turno, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-05 16:30-03')
$f$;
create function pg_temp.c3_fora(p_payee uuid, p_de date, p_ate date, p_turno text default null) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  values (p_payee, daterange(p_de, p_ate, '[]'), p_turno, 'indisponivel', 'dono', 'não vem (correção 3)', timestamptz '2026-11-05 10:01-03')
$f$;
-- "o Mateus vem <data>": a data dita pelo dono (o que o *grava* escreve), sob demanda
create function pg_temp.c3_vem(p_payee uuid, p_dia date) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  values (p_payee, daterange(p_dia, p_dia, '[]'), null, 'disponivel', 'dono', 'Você disse que vem', timestamptz '2026-11-05 10:00-03')
$f$;
-- o Mateus cadastrado agora (prestador, com telefone), como o dono faria na equipe de produção; na sintética ele já existe
create function pg_temp.c3_mateus() returns uuid language plpgsql as $f$
declare v uuid := pg_temp.pessoa('Mateus');
begin
  if v is null then
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-05 08:00-03', timestamptz '2026-11-05 08:00-03') returning id into v;
  end if;
  return v;
end $f$;
-- a conta da escada em texto: "reparavel/degrau/motivo/Nome dd/mm t (degrau), …"
create function pg_temp.esc(r jsonb) returns text language sql immutable as $f$
  select format('%s/%s/%s/%s', r ->> 'reparavel', coalesce(r ->> 'degrau', '-'), coalesce(r ->> 'motivo', '-'),
                coalesce((select string_agg(format('%s %s %s (%s)', x #>> '{para,nome}', to_char((x #>> '{para,dia}')::date, 'DD/MM'),
                                                   left(x #>> '{para,turno}', 1), x ->> 'degrau'), ', ' order by x #>> '{para,dia}', x #>> '{para,turno}')
                            from jsonb_array_elements(coalesce(r -> 'reparos', '[]'::jsonb)) x), '-'))
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
-- os meios-dias de turno vigentes em que a pessoa está sozinha (sem outra pessoa de turno na OS)
create function pg_temp.sozinho(p_payee uuid) returns int language sql stable as $f$
  select count(*)::int from public.agenda_alocacoes a
   where a.payee_id = p_payee and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva' and a.presenca = 'turno'
     and not exists (select 1 from public.agenda_alocacoes b
                      where b.service_order_id = a.service_order_id and b.dia = a.dia and b.turno = a.turno and b.id <> a.id
                        and b.estado in ('publicada', 'fixada') and b.presenca = 'turno')
$f$;
-- o motor na carteira inteira, sem gravar, em texto: os itens de criar e os meios-dias do Alex (e quantos sozinho)
create function pg_temp.motor(p_alex uuid) returns text language plpgsql as $f$
declare v_p jsonb;
begin
  v_p := public.agenda_propor('os', null, null, array(select k.service_order_id from public.os_carteira(date '2026-11-05') k),
                              '{}'::jsonb, false, 'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
  return (with a as (select i ->> 'numero' as num, al ->> 'payee_id' as p, al ->> 'dia' as dia, al ->> 'turno' as turno,
                            al ->> 'presenca' as pres
                       from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) i, jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) al
                      where i ->> 'op' = 'criar')
          select format('criar %s: %s', (select count(*) from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) i where i ->> 'op' = 'criar'),
                        coalesce(string_agg(format('%s %s %s', num, to_char(dia::date, 'DD/MM'), left(turno, 1)), ', ' order by num, dia, turno)
                                   filter (where p = p_alex::text and pres = 'turno'), '-'))
            from a);
end $f$;
-- as linhas do fechamento sem a forma curta da linha (n) (a que a correção 3 muda)
create function pg_temp.sem_n(l jsonb) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg(case when x ->> 'texto_curto' like 'Agenda, equipe:%' then x - 'texto_curto' else x end order by o), '[]'::jsonb)
    from jsonb_array_elements(coalesce(l, '[]'::jsonb)) with ordinality t(x, o)
$f$;

-- ── C1. O técnico declarado nunca é novato ──────────────────────────────────────────────────────────────────────
do $c1$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-05';
  v_alex uuid;
  v_mat  uuid;
  v      jsonb;
  a      text;
  b      text;
  c      text;
  d      text;
  e      text;
  f      text;
  g      text;
  r      record;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C1 (o técnico declarado)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_alex := pg_temp.pessoa('Alex');
  begin
    a := format('novato %s, antes %s, declarado %s', public._agenda_e_novato(v_alex, c_d), pg_temp.novato_antes(v_alex, c_d),
                pg_temp.declarado(v_alex, c_d));
    perform pg_temp.perfil(v_alex, date '2026-11-02');
    b := format('novato %s, antes %s, declarado %s', public._agenda_e_novato(v_alex, c_d), pg_temp.novato_antes(v_alex, c_d),
                pg_temp.declarado(v_alex, c_d));
    -- o próprio Alex responde a semana com outros dias: o padrão do dono sai (substituída), entra um de origem diarista
    v := public._agenda_equipe_dias_gravar(v_alex, date '2026-11-09', '{1,2,3,4}'::smallint[], false, 'diarista', 'seg a qui',
                                           timestamptz '2026-11-04 17:00-03');
    c := format('novato %s, antes %s, declarado %s, padrões vivos %s', public._agenda_e_novato(v_alex, c_d), pg_temp.novato_antes(v_alex, c_d),
                pg_temp.declarado(v_alex, c_d),
                (select string_agg(x.dias_semana::text || ':' || x.origem, ' ') from public.agenda_disponibilidade x
                  where x.payee_id = v_alex and x.substituida_em is null and x.dias_semana is not null));
    -- o Mateus cadastrado agora, "o Mateus vem toda terça" pelo rascunho e o *grava* (com a 7b em teste, como o dado 100900 a deixa:
    -- quem está no cadastro e não na equipe entra pelo rascunho), e um perfil de diária de hoje
    execute current_setting('agenda_teste.mig_sombra_fase7b');
    v_mat := pg_temp.c3_mateus();
    v := public.agenda_rascunho_disponibilidade(pg_temp.adm(), 'whatsapp', 'Mateus', 'vem', 'terça', true, 'o Mateus vem toda terça', c_d, null);
    v := public.agenda_rascunho_gravar(pg_temp.adm(), c_d);
    perform pg_temp.perfil(v_mat, c_d);
    d := format('novato %s, antes %s, declarado %s, padrões vivos %s', public._agenda_e_novato(v_mat, c_d), pg_temp.novato_antes(v_mat, c_d),
                pg_temp.declarado(v_mat, c_d),
                coalesce((select string_agg(x.dias_semana::text || ':' || x.origem, ' ') from public.agenda_disponibilidade x
                           where x.payee_id = v_mat and x.substituida_em is null and x.dias_semana is not null), '-'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.carregar('', '');
    e := format('novato %s, antes %s, declarado %s', public._agenda_e_novato(pg_temp.pessoa('Bruno'), c_d),
                pg_temp.novato_antes(pg_temp.pessoa('Bruno'), c_d), pg_temp.declarado(pg_temp.pessoa('Bruno'), c_d));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C1a o Alex de produção (sem perfil de diária, o padrão do dono seg a sex desde 30/10, cadastro 05/08) não é novato, igual antes, e é o técnico declarado',
    a = 'novato f, antes f, declarado t', a);
  v_res := pg_temp.ok(v_res, 'C1b com um perfil de diária novo (desde seg 02/11, 0 diárias) o Alex não é novato (antes era: a agenda inteira parava com a dupla fora de desligado)',
    b = 'novato f, antes t, declarado t', b);
  v_res := pg_temp.ok(v_res, 'C1c depois de o próprio Alex responder os dias (o padrão do dono substituído por um de origem diarista), com o perfil novo, continua não novato (a linha do dono substituída conta)',
    c = 'novato f, antes t, declarado t, padrões vivos {1,2,3,4}:diarista', c);
  v_res := pg_temp.ok(v_res, 'C1d o Mateus cadastrado agora com "toda terça" dita pelo dono (o padrão de origem dono) e um perfil de hoje é novato (o cadastro não é de 30 dias antes da linha): igual antes',
    d = 'novato t, antes t, declarado f, padrões vivos {2}:dono', d);
  v_res := pg_temp.ok(v_res, 'C1e o Bruno da fixture (perfil desde 20/10, 3 diárias, só uma data dita) é novato, igual antes',
    e = 'novato t, antes t, declarado f', e);

  -- o motor na carteira (só o Alex e o dono; a 7a ligada): com o perfil novo e a dupla em teste e ligada, o mesmo que sem o perfil
  f := '';
  g := 'true';
  for r in select * from (values (1, 'sombra'), (2, 'ligado')) t(o, dupla) order by o loop
    begin
      perform pg_temp.modos7a('ligado');
      update public.agenda_config set modo_dupla = r.dupla where id;
      a := pg_temp.motor(v_alex);
      perform pg_temp.perfil(v_alex, date '2026-11-02');
      b := pg_temp.motor(v_alex);
      c := (not (public._agenda_contexto(date '2026-11-02', date '2026-11-30', date '2026-11-05') ? 'novato'))::text;
      f := f || format('[%s: sem perfil %s | com perfil %s | contexto sem quem nunca fica sozinho %s]', r.dupla, a, b, c);
      g := (g::boolean and a = b and a like 'criar 4: %' and c = 'true')::text;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'C1f o motor na carteira inteira, com o perfil novo do Alex e a dupla em teste e ligada, marca o mesmo que sem o perfil (4 OS com o Alex; antes, nenhuma: a agenda inteira parava) e o contexto não tem o Alex como quem nunca fica sozinho',
    g = 'true', f);
  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C2. A escada da revisão nunca põe sozinho quem nunca vai sozinho ───────────────────────────────────────────────
do $c2$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-05';
  c_t    constant timestamptz := timestamptz '2026-11-05 16:53-03';
  v_alex uuid;
  v_mat  uuid;
  v_rafa uuid;
  v_os   uuid;
  v_n    int;
  r      record;
  x      jsonb;
  y      jsonb;
  a      text := '';
  b      text := '';
  c      text := '';
  d      text;
  e      text;
  f      text;
  g      text := '';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C2 (a escada)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_alex := pg_temp.pessoa('Alex');
  -- a equipe de produção + o Mateus cadastrado agora; o Caio (OS-97301) com o Alex em qua 18/11 de manhã
  for r in select * from (values (1, 'sombra'), (2, 'ligado')) t(o, dupla) order by o loop
    -- (i) o Alex fora qua 18/11 inteira; o Mateus dito para qua 18/11
    begin
      perform pg_temp.modos7a('ligado');
      update public.agenda_config set modo_dupla = r.dupla where id;
      v_mat := pg_temp.c3_mateus();
      perform pg_temp.c3_vem(v_mat, date '2026-11-18');
      v_os := pg_temp.c3_os('97301', 'Caio', 0.5);
      perform pg_temp.c3_aloc(v_os, v_alex, date '2026-11-18', 'manha');
      perform pg_temp.c3_fora(v_alex, date '2026-11-18', date '2026-11-18');
      a := a || format('[%s: %s | antes %s]', r.dupla, pg_temp.esc(public._agenda_gestor_reparo(v_os, c_d, c_t)),
                       pg_temp.esc(pg_temp.reparo_antes(v_os, c_d, c_t)));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- (ii) o Alex fora de seg 16 a qua 18/11; o Mateus dito só para ter 17/11
    begin
      perform pg_temp.modos7a('ligado');
      update public.agenda_config set modo_dupla = r.dupla where id;
      v_mat := pg_temp.c3_mateus();
      perform pg_temp.c3_vem(v_mat, date '2026-11-17');
      v_os := pg_temp.c3_os('97301', 'Caio', 0.5);
      perform pg_temp.c3_aloc(v_os, v_alex, date '2026-11-18', 'manha');
      perform pg_temp.c3_fora(v_alex, date '2026-11-16', date '2026-11-18');
      a := a || format('[%s só ter 17: %s | antes %s]', r.dupla, pg_temp.esc(public._agenda_gestor_reparo(v_os, c_d, c_t)),
                       pg_temp.esc(pg_temp.reparo_antes(v_os, c_d, c_t)));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- (iii) o Alex fora de seg 16 a qua 18/11; o Mateus dito para ter 17 e qua 18/11: a revisão (agenda_replanejar, a escada antes do motor)
    begin
      perform pg_temp.modos7a('ligado');
      update public.agenda_config set modo_dupla = r.dupla where id;
      v_mat := pg_temp.c3_mateus();
      perform pg_temp.c3_vem(v_mat, date '2026-11-17');
      perform pg_temp.c3_vem(v_mat, date '2026-11-18');
      v_os := pg_temp.c3_os('97301', 'Caio', 0.5);
      perform pg_temp.c3_aloc(v_os, v_alex, date '2026-11-18', 'manha');
      perform pg_temp.c3_fora(v_alex, date '2026-11-16', date '2026-11-18');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      perform public.agenda_replanejar(array[v_os], 'pessoa', 'vigia', c_d, c_t, null);
      v_n := (select count(*) from public.agenda_acoes ac where ac.service_order_id = v_os and ac.tipo = 'reparar');
      b := b || format('[%s: %s | antes %s | ações reparar %s | o Mateus sozinho em %s meios-dias | fica %s]', r.dupla, pg_temp.esc(x),
                       pg_temp.esc(y), v_n, pg_temp.sozinho(v_mat), pg_temp.vivas(v_os));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- (iii) com a dupla desligada: a escada de antes, byte a byte
  begin
    perform pg_temp.modos7a('ligado');
    update public.agenda_config set modo_dupla = 'desligado' where id;
    v_mat := pg_temp.c3_mateus();
    perform pg_temp.c3_vem(v_mat, date '2026-11-17');
    perform pg_temp.c3_vem(v_mat, date '2026-11-18');
    v_os := pg_temp.c3_os('97301', 'Caio', 0.5);
    perform pg_temp.c3_aloc(v_os, v_alex, date '2026-11-18', 'manha');
    perform pg_temp.c3_fora(v_alex, date '2026-11-16', date '2026-11-18');
    x := public._agenda_gestor_reparo(v_os, c_d, c_t);
    y := pg_temp.reparo_antes(v_os, c_d, c_t);
    c := format('%s | igual %s', pg_temp.esc(x), x = y);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- a fixture sintética (o Rafael, de seg a sex por ele, perfil desde 01/09; o Mateus da fixture, dito para qua 18/11)
  begin
    perform pg_temp.carregar('', '');
    perform pg_temp.modos7a('ligado');
    update public.agenda_config set modo_dupla = 'ligado' where id;
    v_rafa := pg_temp.pessoa('Rafael');
    v_mat := pg_temp.pessoa('Mateus');
    perform pg_temp.c3_vem(v_mat, date '2026-11-18');
    -- (d) o Caio com o Alex e o Rafael em qua 18/11 de manhã; o Rafael não vem: o Mateus entra junto do Alex
    v_os := pg_temp.c3_os('97301', 'Caio', 1);
    perform pg_temp.c3_aloc(v_os, v_alex, date '2026-11-18', 'manha');
    perform pg_temp.c3_aloc(v_os, v_rafa, date '2026-11-18', 'manha');
    perform pg_temp.c3_fora(v_rafa, date '2026-11-18', date '2026-11-18', 'manha');
    x := public._agenda_gestor_reparo(v_os, c_d, c_t);
    y := pg_temp.reparo_antes(v_os, c_d, c_t);
    d := format('%s | igual %s', pg_temp.esc(x), x = y);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.carregar('', '');
    perform pg_temp.modos7a('ligado');
    update public.agenda_config set modo_dupla = 'ligado' where id;
    v_rafa := pg_temp.pessoa('Rafael');
    v_mat := pg_temp.pessoa('Mateus');
    perform pg_temp.c3_vem(v_mat, date '2026-11-18');
    -- (e) o Caio só com o Rafael em qua 18/11 de manhã; o Rafael não vem; o Alex está livre: o degrau 1 de antes
    v_os := pg_temp.c3_os('97301', 'Caio', 0.5);
    perform pg_temp.c3_aloc(v_os, v_rafa, date '2026-11-18', 'manha');
    perform pg_temp.c3_fora(v_rafa, date '2026-11-18', date '2026-11-18', 'manha');
    x := public._agenda_gestor_reparo(v_os, c_d, c_t);
    y := pg_temp.reparo_antes(v_os, c_d, c_t);
    e := format('%s | igual %s', pg_temp.esc(x), x = y);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- (f) o limite da 7b (a revisão da correção 3): o Mateus cadastrado agora, SEM perfil de diária, com "toda terça" dita pelo dono (o
  -- padrão de origem dono que o *grava* escreve: o C1d) — um dia fixo, não as datas — não é novato nem vem sob demanda: conta como
  -- técnico. A escada o põe como antes, byte a byte, e o motor também (a mesma régua). O roteiro pede ao dono as datas (C2a e C2b);
  -- o "ajudante nunca sozinho" com dia fixo é da 7c (a etiqueta).
  for r in select * from (values (1, 'sombra'), (2, 'ligado')) t(o, dupla) order by o loop
    begin
      perform pg_temp.modos7a('ligado');
      update public.agenda_config set modo_dupla = r.dupla where id;
      v_mat := pg_temp.c3_mateus();
      insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, criado_em)
      values (v_mat, '{2}', null, 'disponivel', 'dono', 'Você disse: toda terça', timestamptz '2026-11-05 10:00-03');
      v_os := pg_temp.c3_os('97301', 'Caio', 0.5);
      perform pg_temp.c3_aloc(v_os, v_alex, date '2026-11-17', 'manha');
      perform pg_temp.c3_fora(v_alex, date '2026-11-16', date '2026-11-20');
      x := public._agenda_gestor_reparo(v_os, c_d, c_t);
      y := pg_temp.reparo_antes(v_os, c_d, c_t);
      g := g || format('[%s: novato %s, sob demanda %s, declarado %s | escada %s | igual %s', r.dupla,
                       public._agenda_e_novato(v_mat, date '2026-11-17'), public._agenda_e_sob_demanda(v_mat, date '2026-11-17'),
                       case when pg_temp.declarado(v_mat, date '2026-11-17') then 'sim' else 'não' end, pg_temp.esc(x), x = y);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    -- o motor com o Caio sem marcação e o Alex fora de seg 09 a sex 27/11: quem ele marca em cada meio-dia de turno
    begin
      perform pg_temp.modos7a('ligado');
      update public.agenda_config set modo_dupla = r.dupla where id;
      v_mat := pg_temp.c3_mateus();
      insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, criado_em)
      values (v_mat, '{2}', null, 'disponivel', 'dono', 'Você disse: toda terça', timestamptz '2026-11-05 10:00-03');
      v_os := pg_temp.c3_os('97301', 'Caio', 0.5);
      perform pg_temp.c3_fora(v_alex, date '2026-11-09', date '2026-11-27');
      x := public.agenda_propor('os', null, null, array[v_os], '{}'::jsonb, false, 'vigia', null, c_d, pg_temp.em(c_d, '16:45'));
      g := g || format(' | motor %s]',
                       coalesce((select string_agg(format('%s %s %s', coalesce(public._agenda_nome_curto(py.name), '?'),
                                                          to_char((al ->> 'dia')::date, 'DD/MM'), left(al ->> 'turno', 1)), ', '
                                                   order by al ->> 'dia', al ->> 'turno', py.name)
                                   from jsonb_array_elements(coalesce(x -> 'itens', '[]'::jsonb)) i
                                   cross join lateral jsonb_array_elements(coalesce(i -> 'alocacoes', '[]'::jsonb)) al
                                   left join public.payees py on py.id = (al ->> 'payee_id')::uuid
                                  where i ->> 'op' = 'criar' and al ->> 'presenca' = 'turno'), '-'));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'C2a com a dupla em teste e ligada, o Mateus (dito numa data: vem sob demanda) não entra sozinho em nenhum degrau — o Alex fora qua 18/11 inteira: nem no degrau 1 nem no 2, o Alex vai a ter 17/11 (degrau 3; antes o Mateus no degrau 1); o Mateus só em ter 17/11: nem no degrau 3, sem conserto (antes o Mateus em ter 17/11)',
    a = '[sombra: true/dia/-/Alex 17/11 m (dia) | antes true/pessoa/-/Mateus 18/11 m (pessoa)]'
        || '[sombra só ter 17: false/-/sem_lugar/- | antes true/dia/-/Mateus 17/11 m (dia)]'
        || '[ligado: true/dia/-/Alex 17/11 m (dia) | antes true/pessoa/-/Mateus 18/11 m (pessoa)]'
        || '[ligado só ter 17: false/-/sem_lugar/- | antes true/dia/-/Mateus 17/11 m (dia)]', a);
  v_res := pg_temp.ok(v_res, 'C2b com o Mateus livre em ter 17 e qua 18/11 e o Alex fora a semana: a escada não conserta (sem_lugar), nenhuma ação reparar, a OS vai ao motor e o Mateus não fica sozinho em nenhum meio-dia (antes a escada o punha em qua 18/11 de manhã)',
    b like '[sombra: false/-/sem_lugar/- | antes true/pessoa/-/Mateus 18/11 m (pessoa) | ações reparar 0 | o Mateus sozinho em 0 meios-dias | fica %]'
           || '[ligado: false/-/sem_lugar/- | antes true/pessoa/-/Mateus 18/11 m (pessoa) | ações reparar 0 | o Mateus sozinho em 0 meios-dias | fica %]'
    and b not like '%Mateus 18/11 m (pessoa) | ações reparar 1%', b);
  v_res := pg_temp.ok(v_res, 'C2c com a dupla desligada, a escada de antes, byte a byte (o Mateus em qua 18/11 de manhã, como antes)',
    c = 'true/pessoa/-/Mateus 18/11 m (pessoa) | igual t', c);
  v_res := pg_temp.ok(v_res, 'C2d o Mateus junto de outra pessoa que pode ficar sozinha no mesmo meio-dia (o Rafael não vem, o Alex fica) entra no degrau 1, byte a byte o de antes',
    d = 'true/pessoa/-/Mateus 18/11 m (pessoa) | igual t', d);
  v_res := pg_temp.ok(v_res, 'C2e com outro técnico livre (o Alex), o degrau 1 de antes, byte a byte',
    e = 'true/pessoa/-/Alex 18/11 m (pessoa) | igual t', e);
  v_res := pg_temp.ok(v_res, 'C2f o limite da 7b (a revisão da correção 3): o Mateus cadastrado agora SEM perfil de diária e com "toda terça" dita pelo dono (um dia fixo, não as datas) não é novato, nem vem sob demanda, nem é técnico declarado: conta como técnico — a escada o põe sozinho como antes, byte a byte (degrau 1, ter 17/11), como o motor (ter 10/11, com o Alex fora), com a dupla em teste e ligada. Por isso o roteiro pede ao dono as datas (C2a e C2b); a 7c fecha o dia fixo com a etiqueta ajudante',
    g = '[sombra: novato f, sob demanda f, declarado não | escada true/pessoa/-/Mateus 17/11 m (pessoa) | igual t | motor Mateus 10/11 m]'
        || '[ligado: novato f, sob demanda f, declarado não | escada true/pessoa/-/Mateus 17/11 m (pessoa) | igual t | motor Mateus 10/11 m]', g);
  perform pg_temp.gravar(v_res);
end
$c2$;

-- ── C3. O prazo na forma curta da linha (n) ─────────────────────────────────────────────────────────────────────
do $c3$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-05';
  v      jsonb;
  l      jsonb;
  n      jsonb;
  q      public.agenda_perguntas%rowtype;
  v_ate  text;
  a      text;
  a2     text;
  b      text;
  b2     text;
  c      text := '';
  d      text := '';
  v_seg  jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C3 (a forma curta)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- (a) a chamada com o cadastro ligado (o ligar de qua 04/11; os dias em teste)
  begin
    perform pg_temp.modos7a('ligado');
    update public.agenda_config set modo_cadastro = 'ligado', modo_dupla = 'ligado', modo_chamar = 'ligado', modo_sabado = 'ligado',
                                    modo_dias = 'sombra' where id;
    v := public.agenda_equipe_semana(c_d, pg_temp.em(c_d, '16:45'));
    select x.* into q from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:%' and x.estado = 'aberta' and x.modo = 'ligado';
    l := public._agenda_linhas_do_fechamento(c_d);
    select x into n from jsonb_array_elements(l) x where x ->> 'tipo' = 'pergunta' and x ->> 'pergunta_id' = q.id::text;
    a := n ->> 'texto_curto';
    c := c || format('[a: igual %s; curta %s < longa %s]', pg_temp.sem_n(l) = pg_temp.sem_n(pg_temp.linhas_antes(c_d)),
                     char_length(n ->> 'texto_curto'), char_length(n ->> 'texto'));
    -- o fechamento das 17:30 sai com a forma curta: o registro conta as pergunta_ids; a rodada seguinte grava o prazo
    v := public.agenda_fechamento_registrar(c_d, jsonb_build_array(n), 'fechamento', pg_temp.em(c_d, '17:30'));
    v := public.agenda_equipe_semana(c_d, pg_temp.em(c_d, '17:37'));
    select x.* into q from public.agenda_perguntas x where x.id = q.id;
    v_ate := public._dia_curto((q.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às ' || to_char(q.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI');
    a2 := format('vista %s; prazo gravado %s; no texto: %s', q.mostrada_vezes, v_ate,
                 position('sem resposta até ' || v_ate || ', sigo assim' in coalesce(a, '')) > 0);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- (b) com a pergunta dos dias da semana do dono (os dias ligados) e o telefone do Alex na mesma linha
  begin
    perform pg_temp.modos7a('ligado');
    update public.agenda_config set modo_cadastro = 'ligado', modo_dias = 'ligado', dias_semana_motivos = '{sempre}' where id;
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave = 'padrao_do_dono:sem_dias' and estado = 'aberta';
    v := public.agenda_equipe_semana(c_d, pg_temp.em(c_d, '16:45'));
    insert into public.agenda_perguntas (tipo, chave, payee_id, texto, modo, criada_em)
    values ('equipe_cadastro', 'equipe_cadastro:telefone:' || pg_temp.pessoa('Alex'), pg_temp.pessoa('Alex'),
            'Alex não tem telefone no cadastro: sem ele não mando a ficha da véspera. Para pôr, diga: o telefone do Alex é …', 'ligado',
            pg_temp.em(c_d, '16:46'));
    select x.* into q from public.agenda_perguntas x where x.tipo = 'dias_semana' and x.estado = 'aberta';
    l := public._agenda_linhas_do_fechamento(c_d);
    select x into n from jsonb_array_elements(l) x where x ->> 'tipo' = 'pergunta' and x ->> 'modo' = 'ligado' and x ->> 'texto_curto' like 'Agenda, equipe:%';
    b := n ->> 'texto_curto';
    v_seg := public._agenda_semana_perguntada(c_d);
    c := c || format('[b: igual %s; curta %s < longa %s]', pg_temp.sem_n(l) = pg_temp.sem_n(pg_temp.linhas_antes(c_d)),
                     char_length(n ->> 'texto_curto'), char_length(n ->> 'texto'));
    v := public.agenda_equipe_semana(date '2026-11-12', pg_temp.em(date '2026-11-12', '15:59'));
    b2 := (select x.estado from public.agenda_perguntas x where x.id = q.id);
    v := public.agenda_equipe_semana(date '2026-11-12', pg_temp.em(date '2026-11-12', '16:00'));
    b2 := format('prazo da semana %s; 15:59 %s; 16:00 %s',
                 public._dia_curto(((v_seg ->> 'prazo_em')::timestamptz at time zone 'America/Sao_Paulo')::date) || ' às '
                 || to_char((v_seg ->> 'prazo_em')::timestamptz at time zone 'America/Sao_Paulo', 'HH24:MI'),
                 b2, (select x.estado from public.agenda_perguntas x where x.id = q.id));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- (d) com o cadastro desligado: a chamada da 7a (sem opções, não vence) e o telefone na linha (os dias em teste) — a de antes
  begin
    perform pg_temp.modos7a('ligado');
    update public.agenda_config set modo_cadastro = 'desligado', modo_dias = 'sombra' where id;
    insert into public.agenda_perguntas (tipo, chave, texto, modo, criada_em)
    values ('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-16', 'Para marcar a semana de 16/11 eu conto com Alex (seg a sex), como você disse. Se a equipe mudou, me diga quem vem e em que dias.', 'ligado', pg_temp.em(c_d, '16:52'));
    insert into public.agenda_perguntas (tipo, chave, payee_id, texto, modo, criada_em)
    values ('equipe_cadastro', 'equipe_cadastro:telefone:' || pg_temp.pessoa('Alex'), pg_temp.pessoa('Alex'),
            'Alex não tem telefone no cadastro: sem ele não mando a ficha da véspera. Para pôr, diga: o telefone do Alex é …', 'ligado',
            pg_temp.em(c_d, '16:46'));
    l := public._agenda_linhas_do_fechamento(c_d);
    d := format('igual %s; curta %s', l = pg_temp.linhas_antes(c_d),
                coalesce((select x ->> 'texto_curto' from jsonb_array_elements(l) x where x ->> 'texto_curto' like 'Agenda, equipe:%' limit 1), '-'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C3a a chamada com o cadastro ligado: a forma curta da linha (n) diz o prazo e o "sigo assim" ("Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra."), e o prazo que a rodada grava depois do registro é o mesmo (ter 10/11 às 18:00)',
    a = 'Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim. *agenda pendências* mostra.'
    and a2 = 'vista 1; prazo gravado ter 10/11 às 18:00; no texto: t', concat_ws(' | ', a, a2));
  v_res := pg_temp.ok(v_res, 'C3b com a pergunta dos dias da semana e o telefone: os dias dizem o prazo da semana (qui 12/11 às 16:00), a pergunta vence exatamente então, e o telefone (que não vence) fica como antes',
    b = 'Agenda, equipe: a equipe da agenda está certa? — sem resposta até ter 10/11 às 18:00, sigo assim; os dias da semana de 16/11 — sem resposta até qui 12/11 às 16:00, sigo assim; o telefone do Alex. *agenda pendências* mostra.'
    and b2 = 'prazo da semana qui 12/11 às 16:00; 15:59 aberta; 16:00 vencida', concat_ws(' | ', b, b2));
  v_res := pg_temp.ok(v_res, 'C3c a forma longa e as outras linhas, byte a byte; a forma curta mais curta que a longa e até 300 letras',
    c ~ '^\[a: igual t; curta (\d+) < longa (\d+)\]\[b: igual t; curta (\d+) < longa (\d+)\]$'
    and (select bool_and(m[1]::int < m[2]::int and m[1]::int <= 300) from (select regexp_matches(c, 'curta (\d+) < longa (\d+)', 'g') as m) z), c);
  v_res := pg_temp.ok(v_res, 'C3d com o cadastro desligado (a chamada da 7a, que não vence) e o telefone na linha: a saída inteira de antes, byte a byte',
    d = 'igual t; curta Agenda, equipe: a equipe da agenda está certa?; o telefone do Alex. *agenda pendências* mostra.', d);
  perform pg_temp.gravar(v_res);
end
$c3$;

-- ── C4. (o W3a) a dupla pela tarefa com você junto o tempo todo ──────────────────────────────────────────────────
do $c4$
declare
  v_res  jsonb := '[]'::jsonb;
  v_len  uuid;
  v      jsonb;
  v_p    jsonb;
  a      text;
  b      text;
  c      text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C4 (a dupla com o dono junto)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  begin
    perform pg_temp.carregar('real', 'campo');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_vaga_fechamento = 'ligado', modo_encaixe_aprovacao = 'ligado',
           modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado', marcar_sozinho_desde = timestamptz '2026-11-03 16:46-03',
           gestor_so_propor = false where id;
    execute current_setting('agenda_teste.mig_sombra_fase7b');
    update public.agenda_config set modo_dupla = 'ligado', modo_sabado = 'ligado', modo_cadastro = 'ligado', modo_chamar = 'ligado' where id;
    perform public.agenda_rotina_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:30'));
    perform public.agenda_vigiar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:30'));
    perform public.agenda_gestor_rodar(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:53'));
    a := pg_temp.vivas(v_len);
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-06 08:00-03', timestamptz '2026-11-06 08:00-03');
    v := public.agenda_rascunho_disponibilidade(pg_temp.adm(), 'whatsapp', 'Mateus', 'vem', 'ter 10/11', false, 'o Mateus vem ter 10/11',
                                               date '2026-11-06', null);
    v := public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-06');
    v := public.agenda_gestor_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '08:07'));
    b := coalesce((select string_agg(ac.texto, ' | ' order by ac.criada_em) from public.agenda_acoes ac
                    where ac.service_order_id = v_len and ac.tipo = 'reparar'), '-');
    v := public.agenda_gestor_rodar(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:53'));
    c := pg_temp.vivas(v_len) || ' || ' || coalesce((select string_agg(ac.texto, ' | ' order by ac.criada_em) from public.agenda_acoes ac
                                                      where ac.service_order_id = v_len and ac.tipo = 'reestimar'), '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C4a com a linha dos dias do dono, o Lenine com você o tempo todo e a 7b como o ligar a deixa: o Mateus que o dono chamou para ter 10/11 entra na dupla com o Alex e você ("Pus Mateus com Alex e você no Lenine em ter 10/11 (manhã e tarde) …") e a revisão do dia seguinte tira só ter 17/11 com o texto da dupla (antes: a regra 4 "falta você" segurava a dupla para sempre)',
    a = '10/11 m Alex+Gustavo; 10/11 t Alex+Gustavo; 11/11 m Alex+Gustavo; 11/11 t Alex+Gustavo; 12/11 m Alex+Gustavo; 12/11 t Alex+Gustavo; 13/11 m Alex+Gustavo; 13/11 t Alex+Gustavo; 16/11 m Alex+Gustavo; 16/11 t Alex+Gustavo; 17/11 m Alex+Gustavo; 17/11 t Alex+Gustavo'
    and b = 'Pus Mateus com Alex e você no Lenine em ter 10/11 (manhã e tarde): a troca do banco de baterias pede 2 pessoas. *desfaz Lenine* volta.'
    and c = '10/11 m Alex+Gustavo+Mateus; 10/11 t Alex+Gustavo+Mateus; 11/11 m Alex+Gustavo; 11/11 t Alex+Gustavo; 12/11 m Alex+Gustavo; 12/11 t Alex+Gustavo; 13/11 m Alex+Gustavo; 13/11 t Alex+Gustavo; 16/11 m Alex+Gustavo; 16/11 t Alex+Gustavo || Lenine (OS-00074): com Mateus junto em ter 10/11, o serviço acaba antes (são as mesmas diárias). Tirei ter 17/11.',
    concat_ws(' ## ', a, b, c));

  -- (b) a régua: tira só a regra 4 "falta você" do meio-dia em que o dono já está de turno na OS; (c) agenda_validar de uma proposta
  -- do motor, byte a byte
  begin
    perform pg_temp.carregar('real', 'campo');
    perform pg_temp.modos7a('ligado');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_len, public._agenda_dono(null), date '2026-11-10', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-05 16:30-03');
    v := jsonb_build_array(
      jsonb_build_object('regra', 4, 'os', v_len, 'numero', 'OS-00074', 'dia', '2026-11-10', 'turno', 'manha', 'texto', 'OS-00074: falta você ter 10/11 de manhã.'),
      jsonb_build_object('regra', 4, 'os', v_len, 'numero', 'OS-00074', 'dia', '2026-11-10', 'turno', 'tarde', 'texto', 'OS-00074: falta você ter 10/11 à tarde.'),
      jsonb_build_object('regra', 1, 'os', v_len, 'numero', 'OS-00074', 'dia', '2026-11-10', 'turno', 'manha', 'texto', 'Mateus não está livre ter 10/11 de manhã.'));
    if to_regprocedure('public._agenda_dupla_sem_falta_voce(jsonb)') is not null then
      execute 'select public._agenda_dupla_sem_falta_voce($1)' into v_p using v;
    end if;
    a := coalesce((select string_agg((e ->> 'regra') || ' ' || (e ->> 'turno'), ', ' order by o) from jsonb_array_elements(v_p) with ordinality t(e, o)), '-');
    v_p := public.agenda_propor('os', null, null, array(select k.service_order_id from public.os_carteira(date '2026-11-05') k), '{}'::jsonb,
                                true, 'vigia', null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:45'));
    if v_p ->> 'proposta_id' is null then
      b := 'sem proposta: ' || left(v_p::text, 200);
    else
    b := format('%s | igual %s', jsonb_array_length(public.agenda_validar((v_p ->> 'proposta_id')::uuid, null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:46'))),
                public.agenda_validar((v_p ->> 'proposta_id')::uuid, null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:46'))
                = pg_temp.validar_antes((v_p ->> 'proposta_id')::uuid, null, date '2026-11-05', pg_temp.em(date '2026-11-05', '16:46')));
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C4b _agenda_dupla_sem_falta_voce tira só a regra 4 "falta você" do meio-dia em que o dono já está de turno na OS (fica a da tarde, sem o dono, e a regra 1)',
    a = '4 tarde, 1 manha', a);
  v_res := pg_temp.ok(v_res, 'C4c agenda_validar de uma proposta do motor (não da dupla): a de antes, byte a byte',
    b ~ '^\d+ \| igual t$', b);
  perform pg_temp.gravar(v_res);
end
$c4$;

-- ── C9. Sem os casos: as de antes ───────────────────────────────────────────────────────────────────────────────
do $c9$
declare
  v_res  jsonb := '[]'::jsonb;
  a      text := '';
  b      text := '';
  m      text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C9 (sem os casos)', true, 'PULADO: sem as fixtures da 7b e as migrations como texto (rode pela bancada)');
    return;
  end if;
  begin
    -- a equipe de produção e, por cima, a sintética: cada pessoa ativa, em qui 05/11 e ter 01/12
    a := a || coalesce((select string_agg(py.name, ',' order by py.name) from public.payees py, unnest(array[date '2026-11-05', date '2026-12-01']) dd
                         where py.active and public._agenda_e_novato(py.id, dd) is distinct from pg_temp.novato_antes(py.id, dd)), '') || '/';
    perform pg_temp.carregar('', '');
    a := a || coalesce((select string_agg(py.name, ',' order by py.name) from public.payees py, unnest(array[date '2026-11-05', date '2026-12-01']) dd
                         where py.active and public._agenda_e_novato(py.id, dd) is distinct from pg_temp.novato_antes(py.id, dd)), '')
         || '/' || (select count(*) from public.payees py where py.active and public._agenda_e_novato(py.id, date '2026-11-05'));
    -- as linhas do fechamento sem perguntas da equipe: o gestor ligado, a 7b desligada e em teste
    foreach m in array array['desligado', 'sombra'] loop
      perform pg_temp.modos7a('ligado');
      update public.agenda_config set modo_dias = m, modo_dupla = m, modo_sabado = m, modo_cadastro = m, modo_chamar = m where id;
      b := b || m || ' ' || (public._agenda_linhas_do_fechamento(date '2026-11-05') = pg_temp.linhas_antes(date '2026-11-05'))
           || ' ' || (public._agenda_linhas_do_fechamento(date '2026-11-06') = pg_temp.linhas_antes(date '2026-11-06')) || '; ';
    end loop;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C9a _agenda_e_novato de cada pessoa ativa das duas fixtures, em qui 05/11 e ter 01/12, = o de antes (ninguém com perfil novo é técnico declarado nelas), e o Bruno continua novato',
    a ~ '^//[1-9]', a);
  v_res := pg_temp.ok(v_res, 'C9b as linhas do fechamento sem perguntas da equipe, com a 7b desligada e em teste, = as de antes, byte a byte',
    b = 'desligado true true; sombra true true; ', b);
  perform pg_temp.gravar(v_res);
end
$c9$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
