-- Prova da conversa e da tela, Fase 7g (pacote P7; migration 20261112100600; spec-fase7g §5.7, §8.3 agenda_fase7g_tela.sql e o bloco R9: R9.5-10, 18 e 19,
-- R9.12, R9.13 — "T3 com os focos fora da lista dos 19; os smokes com chave ausente").
-- bancada: depende de 20261112100600
--
-- O cenário: o do motor (scripts/bancada-agenda/cenario-motor.sql, qui 29/10/2026), publicado pela vigia às 16:30 com modo_porque em sombra (o porquê gravado
-- pelo P2) — A = Antônio OS-00201 (ter 03 e qua 04/11), B = Beatriz OS-00202 (qui 05/11 de manhã), C = Caio OS-00203 (reserva, qui 05 a ter 10/11) —; por cima, o
-- Daniel (OS-00204, marcado pelo gestor na qui 05/11 à tarde, com o porquê gravado à mão), a Elisa (OS-00205, marcada por você, seg 09 a qua 11/11, com a reserva
-- de qui 12/11) e o Hugo (OS-00208, só a sua reserva de sex 13/11): os mesmos de agenda_fase7g_como_pensei.sql (C4), que fixa os textos do porquê de cada um.
-- O Fábio (OS-00206) não tem nada marcado: de fora.
--
--   T0  as cópias: a migration recria só as 3 (nenhuma nova, nenhum grant); tiradas os blocos da 7g, cada uma é a origem, byte a byte; a viva é a desta migration
--   T1  a Semana: com modo_porque ligado, quem, quem_texto e porque_texto por bloco (o gestor, você, a reserva sua e a do gestor, a linha cortada, de antes do
--       porquê); ligado sem as 3 chaves = a de antes; desligado e sombra, as chaves ausentes e a tela de antes byte a byte (a origem rodada como pg_temp); a
--       sombra do motor (modo_proposta em sombra), ausentes
--   T2  o cartão: a chave porque (gestor, você, a reserva sua e a do gestor, de antes do porquê); de fora e a OS concluída, ausente; ligado sem a chave = o de
--       antes; desligado e sombra, ausente e o cartão de antes byte a byte (a origem rodada como pg_temp)
--   T3  agenda_ver: os 3 focos fora da lista dos 19 (a mensagem dos 19 igual); como_pensou, porque e placar desligados (a leitura de antes byte a byte, contra a
--       origem rodada como pg_temp; a frase com a saída), em sombra (a de antes e dados.teste) e ligados (o texto da 7g); sem os; a OS que não existe; o período
--       que não se entende; a leitura desligada; sem o dia
--   T4  a porta: o técnico com login 42501 nos 3 focos, pela porta daqui; o admin com login lê; o service_role lê
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7g_tela.sql
--   Seguro em produção: termina em ROLLBACK. O que usa o cenário ou a migration como texto só roda na bancada (fora dela sai PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- FASE 7g: (7g P5b, 20261112100700) o corpo sem os blocos do P5b (que recria agenda_decidir, agenda_desfazer e agenda_tela_semana): o tirador do montador
create function pg_temp.sem_p5b(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(p, E'\n') loop
    if not v_dentro and l ~ '^\s*-- FASE 7g: \(7g P5b' then v_dentro := true; continue; end if;
    if v_dentro and l ~ '^\s*-- FASE 7g: fim\s*$' then v_dentro := false; continue; end if;
    if v_dentro then continue; end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- FASE 7g: fim
create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- p_sql com o login de p_uid (authenticated) ou sem login (p_uid nulo) no papel p_papel: o resultado em texto, ou 'erro <estado>: <mensagem>'
create function pg_temp.como(p_papel text, p_uid uuid, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then json_build_object('role', p_papel)::text
                                                else json_build_object('role', p_papel, 'sub', p_uid)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    reset role;
    perform set_config('request.jwt.claims', '', true);
    return 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;
-- A função inteira (do "create or replace" ao fecho) de p_nome na migration p_mig; o corpo (prosrc); o corpo sem os blocos -- FASE 7g: (7g P7 … -- FASE 7g: fim.
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return null; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := pg_temp.inteira(p_mig, p_nome);
begin
  if v is null then return null; end if;
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.sem7g(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_den  boolean := false;
  x      text;
begin
  foreach x in array string_to_array(replace(p, chr(13), ''), E'\n') loop
    if not v_den and x ~ '^\s*-- FASE 7g: \(7g P7' then v_den := true; continue; end if;
    if v_den and x ~ '^\s*-- FASE 7g: fim' then v_den := false; continue; end if;
    continue when v_den;
    v_fora := v_fora || x;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
-- Uma OS a mais no cenário (o molde de agenda_fase7g_como_pensei.sql): sinal pago, aprovada em 20/10, com os dias.
create function pg_temp.os_extra(p_n text, p_cliente text, p_dias numeric) returns uuid language plpgsql as $f$
declare
  v_os uuid := pg_temp.os(p_n);
  v_cl uuid := ('c4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid;
begin
  insert into public.clients (id, type, name) values (v_cl, 'individual', p_cliente);
  insert into public.vessels (id, client_id, name, asset_type) values (('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, v_cl, 'Lancha', 'Lancha');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
  values (v_os, 'OS-' || lpad(p_n, 5, '0'), v_cl, ('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, 'approved', 'approved', 'repair',
          timestamptz '2026-10-15 12:00-03', timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 2160);
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (md5('cen:servico:' || p_n)::uuid, v_os, '5e000000-0000-4000-8000-000000000003', 'Revisão do sistema elétrico', 'unit', 1, 2160, 2160, timestamptz '2026-10-15 12:00-03');
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount, balance_amount, is_deposit)
  values (md5('cen:sinal:' || p_n)::uuid, v_cl, v_os, 'Sinal', date '2026-10-20', date '2026-10-20', 500, 'paid', 500, 0, true);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em)
  values (v_os, p_dias, case when p_dias is not null then 'dono' end, case when p_dias is not null then timestamptz '2026-10-28 18:00-03' end, 'nunca',
          timestamptz '2026-10-28 18:00-03');
  return v_os;
end $f$;
-- O cenário do motor publicado pela vigia na qui 29/10 às 16:30, com modo_porque = p_porque (o porquê gravado pelo P2), sem o freio e com o gestor desligado; os 4
-- modos da 7g desligados depois (cada caso liga o seu).
create function pg_temp.publicado(p_porque text default 'sombra') returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.cenario_motor');
  update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_porque = p_porque, gestor_so_propor = false,
         modo_marcar_sozinho = 'desligado' where id;
  perform public.agenda_vigiar(date '2026-10-29', pg_temp.em(date '2026-10-29', '16:30'));
  update public.agenda_config set modo_porque = 'desligado', modo_explicar = 'desligado', modo_placar = 'desligado', modo_rebaixar = 'desligado' where id;
end $f$;
-- O Daniel, a Elisa e o Hugo de agenda_fase7g_como_pensei.sql (C4), com as mesmas linhas (os textos do porquê de cada um estão fixados lá), e o Fábio de fora.
create function pg_temp.por_cima() returns void language plpgsql as $f$
declare
  v_os   uuid := pg_temp.os_extra('204', 'Daniel', 1);
  v_ac   uuid := md5('7g:p3:acao:daniel')::uuid;
  v_al   uuid := 'ffffffff-0000-4000-8000-000000000204';
  v_ab   uuid := '00000000-0000-4000-8000-000000000204';
  c_pub  constant timestamptz := pg_temp.em(date '2026-10-29', '16:40');
begin
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas, payee_id, antes, depois,
                                   texto, desfazivel_ate, zona, degrau)
  values (v_ac, c_pub, date '2026-10-29', true, 'vigia', 'mover', v_os, array[v_os], array[v_al, v_ab], '{}', 'bb000000-0000-4000-8000-000000000003',
          '{"alocacoes": [], "fim": null}'::jsonb, '{"alocacoes": [], "fim": null}'::jsonb, 'Mudei Daniel para qui 05/11 com João.', c_pub + interval '24 hours',
          'firme', 'dia');
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, acao_id, duracao_fonte, criterio,
                                       motivos, criado_em, suposicoes, degrau)
  values (v_al, v_os, 'bb000000-0000-4000-8000-000000000003', date '2026-11-05', 'tarde', 'turno', 'execucao', 'publicada', 'motor', c_pub, v_ac, 'orcamento', 'unico',
          '[]', c_pub,
          '[{"codigo": "prazo_padrao_peca", "detalhe": {"itens": ["Cabo"], "du": 7}}, {"codigo": "local_suposto", "detalhe": {"local": "na MP Motorhomes", "fonte": "patio"}},
            {"codigo": "duracao_orcamento", "detalhe": {"dias": 1, "mo": 2160}}, {"codigo": "uma_pessoa", "detalhe": {}}]'::jsonb, 'pessoa'),
         (v_ab, v_os, 'bb000000-0000-4000-8000-000000000001', date '2026-11-05', 'tarde', 'abertura', 'execucao', 'publicada', 'motor', c_pub, v_ac, 'orcamento', null,
          '[]', c_pub, '[]'::jsonb, null);
  perform pg_temp.os_extra('205', 'Elisa', null);
  perform pg_temp.os_extra('208', 'Hugo', null);
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em, motivos, criado_em, suposicoes)
  select md5('7g:p3:' || x.n || ':' || x.d || x.p)::uuid, pg_temp.os(x.n), x.p::uuid, x.d::date, 'tarde', 'turno', x.t, case when x.t = 'reserva' then 'teto' end,
         'publicada', x.o, pg_temp.em(date '2026-10-26', '16:30'), '[]', pg_temp.em(date '2026-10-26', '16:30'), '[]'::jsonb
    from (values ('205', '2026-11-09', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'dono'), ('205', '2026-11-10', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'dono'),
                 ('205', '2026-11-11', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'dono'), ('205', '2026-11-09', 'bb000000-0000-4000-8000-000000000001', 'execucao', 'dono'),
                 ('205', '2026-11-12', 'bb000000-0000-4000-8000-000000000003', 'reserva', 'dono'),
                 ('208', '2026-11-13', 'bb000000-0000-4000-8000-000000000003', 'reserva', 'dono'), ('208', '2026-10-27', 'bb000000-0000-4000-8000-000000000003', 'execucao', 'motor')) x(n, d, p, t, o);
  perform pg_temp.os_extra('206', 'Fábio', 1);
end $f$;
create function pg_temp.modos(p_porque text, p_explicar text, p_placar text) returns void language sql as $f$
  update public.agenda_config set modo_porque = p_porque, modo_explicar = p_explicar, modo_placar = p_placar where id
$f$;
create function pg_temp.tela(p_de date) returns jsonb language sql as $f$
  select public.agenda_tela_semana(p_de, date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'))
$f$;
-- O bloco de uma OS num dia, da tela
create function pg_temp.bloco(p_tela jsonb, p_dia date, p_os uuid) returns jsonb language sql immutable as $f$
  select b from jsonb_array_elements(p_tela -> 'dias') d, jsonb_array_elements(d -> 'blocos') b
   where (d ->> 'dia')::date = p_dia and (b ->> 'os')::uuid = p_os
$f$;
-- A tela sem as 3 chaves da 7g nos blocos
create function pg_temp.sem_chaves(p_tela jsonb) returns jsonb language sql immutable as $f$
  select p_tela || jsonb_build_object('dias', coalesce((
           select jsonb_agg(d || jsonb_build_object('blocos', coalesce((select jsonb_agg(b - 'quem' - 'quem_texto' - 'porque_texto' order by bo)
                                                                         from jsonb_array_elements(d -> 'blocos') with ordinality y(b, bo)), '[]'::jsonb)) order by o)
             from jsonb_array_elements(p_tela -> 'dias') with ordinality x(d, o)), '[]'::jsonb))
$f$;
-- Quantos blocos da tela têm alguma das 3 chaves
create function pg_temp.com_chave(p_tela jsonb) returns int language sql immutable as $f$
  select count(*)::int from jsonb_array_elements(p_tela -> 'dias') d, jsonb_array_elements(d -> 'blocos') b
   where b ? 'quem' or b ? 'quem_texto' or b ? 'porque_texto'
$f$;
-- Sem o tempo de cada leitura (ms, duracao_ms, tempo): a semana traz o tempo da simulação (livre_de_verdade.ms), que muda a cada chamada (o molde de agenda_fase7e_dado.sql)
create function pg_temp.limpa(p jsonb) returns jsonb language plpgsql immutable as $f$
begin
  return case jsonb_typeof(p)
    when 'object' then coalesce((select jsonb_object_agg(e.k, pg_temp.limpa(e.v)) from jsonb_each(p) e(k, v) where e.k !~ '^(ms|duracao_ms|tempo)$'), '{}'::jsonb)
    when 'array' then coalesce((select jsonb_agg(pg_temp.limpa(a.v) order by a.o) from jsonb_array_elements(p) with ordinality a(v, o)), '[]'::jsonb)
    else p end;
end $f$;
create function pg_temp.ver(p_foco text, p_os text default null, p_periodo text default null) returns jsonb language sql as $f$
  select public.agenda_ver(null, p_periodo, null, p_foco, p_os, null, false, date '2026-10-29')
$f$;

-- As definições de ANTES (as origens da cópia), rodadas como pg_temp: a régua do que não muda fora de ligado.
do $antes$
declare
  v_ver   text := coalesce(current_setting('agenda_teste.mig_leituras_fase7d', true), '');
  v_tela  text := coalesce(current_setting('agenda_teste.mig_telas_fase3', true), '');
  v_plano text := coalesce(current_setting('agenda_teste.mig_rodada_fase7e', true), '');
begin
  if v_ver = '' or v_tela = '' or v_plano = '' then return; end if;
  execute replace(pg_temp.inteira(v_ver, 'agenda_ver'), 'create or replace function public.agenda_ver(', 'create function pg_temp.ver_antes(');
  execute replace(pg_temp.inteira(v_tela, 'agenda_tela_semana'), 'create or replace function public.agenda_tela_semana(', 'create function pg_temp.tela_antes(');
  execute replace(pg_temp.inteira(v_plano, 'os_plano_da_os'), 'create or replace function public.os_plano_da_os(', 'create function pg_temp.plano_antes(');
end
$antes$;

-- ── T0. As cópias ────────────────────────────────────────────────────────────────────────────────────
do $t0$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_tela_fase7g', true), '');
  v     text;
begin
  if v_mig = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'T0 as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)'));
    return;
  end if;
  v := (select string_agg(m[1], ',' order by m[1]) from regexp_matches(v_mig, '^create or replace function public\.([a-z_0-9]+)\(', 'gm') m);
  v_res := pg_temp.ok(v_res, 'T0a a migration recria só as 3 (nenhuma nova, nenhuma tabela, coluna, gatilho, policy nem grant)',
    v = 'agenda_tela_semana,agenda_ver,os_plano_da_os'
    and v_mig !~* '(?n)^\s*(create table|alter table|create trigger|create policy|grant |revoke |drop )', v);
  select string_agg(x.nome, ', ') into v
    from (values ('agenda_ver', 'mig_leituras_fase7d'), ('agenda_tela_semana', 'mig_telas_fase3'), ('os_plano_da_os', 'mig_rodada_fase7e')) x(nome, origem)
   where pg_temp.sem7g(pg_temp.corpo(v_mig, x.nome)) is distinct from replace(pg_temp.corpo(current_setting('agenda_teste.' || x.origem), x.nome), E'\r\n', E'\n')
      or pg_temp.corpo(v_mig, x.nome) = pg_temp.sem7g(pg_temp.corpo(v_mig, x.nome));
  v_res := pg_temp.ok(v_res, 'T0b tirados os blocos da 7g, cada recriada é a origem, byte a byte (agenda_ver 20261107100700, agenda_tela_semana 20261026100600, os_plano_da_os 20261111100600), e cada uma tem bloco',
    v is null, v);
  select string_agg(p.proname, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('agenda_ver', 'agenda_tela_semana', 'os_plano_da_os')
     -- FASE 7g: (7g P5b) tirados os blocos do P5b (20261112100700 recria agenda_tela_semana; agenda_fase7g_ok_do_dono.sql K0b confere a cópia)
     and pg_temp.sem_p5b(replace(p.prosrc, E'\r\n', E'\n')) is distinct from pg_temp.corpo(v_mig, p.proname);
     -- FASE 7g: fim
  v_res := pg_temp.ok(v_res, 'T0c no banco está a desta migration', v is null, v);
  v := (select string_agg(format('%s:%s:%s', p.proname, p.prosecdef, p.provolatile), ' ' order by p.proname) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname in ('agenda_ver', 'agenda_tela_semana', 'os_plano_da_os'));
  v_res := pg_temp.ok(v_res, 'T0d as 3 seguem como eram: agenda_ver invoker, a tela e o cartão definer, as 3 estáveis',
    v = 'agenda_tela_semana:t:s agenda_ver:f:s os_plano_da_os:t:s', v);
  perform pg_temp.gravar(v_res);
end
$t0$;

-- ── T1. A Semana ─────────────────────────────────────────────────────────────────────────────────────
do $t1$
declare
  v_res jsonb := '[]'::jsonb;
  t     jsonb;
  t2    jsonb;
  b     jsonb;
  v     text;
  c_daniel constant text := '1 dia pelo orçamento (R$ 2.160 de mão de obra; estimativa minha); Cabo: contei 7 dias úteis de entrega (não sei de quem comprar)';
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' or to_regprocedure('pg_temp.tela_antes(date, date, timestamptz)') is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'T1 a Semana', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.por_cima();
    -- desligado e sombra: a tela de antes, byte a byte, sem as chaves (as 2 semanas)
    perform pg_temp.modos('desligado', 'desligado', 'desligado');
    t := pg_temp.tela(date '2026-11-02');
    t2 := pg_temp.tela(date '2026-11-09');
    v_res := pg_temp.ok(v_res, 'T1a desligado: a tela de antes, byte a byte (as 2 semanas), sem as 3 chaves',
      t = pg_temp.tela_antes(date '2026-11-02', date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'))
      and t2 = pg_temp.tela_antes(date '2026-11-09', date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'))
      and pg_temp.com_chave(t) = 0 and pg_temp.com_chave(t2) = 0 and jsonb_array_length(t -> 'dias') > 0, t::text);
    perform pg_temp.modos('sombra', 'sombra', 'sombra');
    v_res := pg_temp.ok(v_res, 'T1b sombra: a tela de antes, byte a byte, sem as 3 chaves',
      pg_temp.tela(date '2026-11-02') = t and pg_temp.tela(date '2026-11-09') = t2, null);
    -- ligado
    perform pg_temp.modos('ligado', 'desligado', 'desligado');
    t := pg_temp.tela(date '2026-11-02');
    t2 := pg_temp.tela(date '2026-11-09');
    b := pg_temp.bloco(t, date '2026-11-05', pg_temp.os('204'));
    v_res := pg_temp.ok(v_res, 'T1c o Daniel (gestor): quem, "marcado pelo gestor" e a linha do porquê cortada em 120 letras',
      b ->> 'quem' = 'gestor' and b ->> 'quem_texto' = 'marcado pelo gestor'
      and b ->> 'porque_texto' = public._agenda_corta(c_daniel, 120) and char_length(b ->> 'porque_texto') <= 120 and char_length(c_daniel) > 120
      and b ->> 'porque_texto' like '1 dia pelo orçamento (R$ 2.160 de mão de obra; estimativa minha); Cabo: contei 7 dias úteis%…', b::text);
    b := pg_temp.bloco(t, date '2026-11-03', pg_temp.os('201'));
    v_res := pg_temp.ok(v_res, 'T1d o Antônio (a vigia, com o porquê gravado pelo P2): gestor, a fonte que você disse e o 1 motivo',
      b ->> 'quem' = 'gestor' and b ->> 'quem_texto' = 'marcado pelo gestor'
      and b ->> 'porque_texto' = 'você disse 2 dias; o barco livre nesses dias (ninguém disse que está em uso)', b::text);
    b := pg_temp.bloco(t, date '2026-11-05', pg_temp.os('203'));
    v_res := pg_temp.ok(v_res, 'T1e a reserva do Caio (do gestor): "reservado pelo gestor", sem a fonte (a reserva não tem)',
      (b ->> 'reserva')::boolean and b ->> 'quem' = 'gestor' and b ->> 'quem_texto' = 'reservado pelo gestor'
      and b ->> 'porque_texto' = 'o barco livre nesses dias (ninguém disse que está em uso)', b::text);
    b := pg_temp.bloco(t2, date '2026-11-09', pg_temp.os('205'));
    v_res := pg_temp.ok(v_res, 'T1f a Elisa (marcada por você): "marcado por você" e a duração pelo tamanho do bloco',
      b ->> 'quem' = 'dono' and b ->> 'quem_texto' = 'marcado por você' and b ->> 'porque_texto' = '1,5 dia (estimativa minha, só para reservar)', b::text);
    b := pg_temp.bloco(t2, date '2026-11-12', pg_temp.os('205'));
    v := b::text;
    b := pg_temp.bloco(t2, date '2026-11-13', pg_temp.os('208'));
    v_res := pg_temp.ok(v_res, 'T1g as reservas suas (a da Elisa ao lado e a do Hugo): "reservado por você", sem linha (nem fonte nem suposição)',
      v::jsonb ->> 'quem_texto' = 'reservado por você' and b ->> 'quem' = 'dono' and b ->> 'quem_texto' = 'reservado por você'
      and b ? 'porque_texto' and b -> 'porque_texto' = 'null'::jsonb, v || ' · ' || b::text);
    v_res := pg_temp.ok(v_res, 'T1h ligado: todo bloco tem as 3 chaves, e sem elas a tela é a de antes, byte a byte',
      pg_temp.com_chave(t) = (select count(*) from jsonb_array_elements(t -> 'dias') d, jsonb_array_elements(d -> 'blocos') x)
      and pg_temp.com_chave(t) > 0
      and pg_temp.sem_chaves(t) = pg_temp.tela_antes(date '2026-11-02', date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00'))
      and pg_temp.sem_chaves(t2) = pg_temp.tela_antes(date '2026-11-09', date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00')), null);
    -- a sombra do motor (modo_proposta em sombra): os blocos são os da proposta, sem alocação vigente: as chaves ficam fora
    update public.agenda_config set modo_proposta = 'sombra' where id;
    t := pg_temp.tela(date '2026-11-02');
    v_res := pg_temp.ok(v_res, 'T1i com a agenda automática em teste (os blocos da sombra do motor), as chaves ficam ausentes',
      pg_temp.com_chave(t) = 0 and t = pg_temp.tela_antes(date '2026-11-02', date '2026-10-29', pg_temp.em(date '2026-10-29', '17:00')), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- de antes do porquê: publicado com modo_porque desligado (a coluna nula, como as marcações de antes da 7g)
    perform pg_temp.publicado('desligado');
    perform pg_temp.modos('ligado', 'desligado', 'desligado');
    b := pg_temp.bloco(pg_temp.tela(date '2026-11-02'), date '2026-11-03', pg_temp.os('201'));
    v_res := pg_temp.ok(v_res, 'T1j a marcação de antes do porquê: "de antes de eu guardar o porquê"',
      b ->> 'quem_texto' = 'marcado pelo gestor' and b ->> 'porque_texto' = 'de antes de eu guardar o porquê', b::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$t1$;

-- ── T2. O cartão ─────────────────────────────────────────────────────────────────────────────────────
do $t2$
declare
  v_res jsonb := '[]'::jsonb;
  p     jsonb;
  v     text;
  r     record;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' or to_regprocedure('pg_temp.plano_antes(uuid, date)') is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'T2 o cartão', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.por_cima();
    -- desligado e sombra: o cartão de antes, byte a byte, sem a chave
    for r in select x.m, x.n from (values ('desligado', '204'), ('desligado', '205'), ('desligado', '203'), ('sombra', '204'), ('sombra', '208')) x(m, n) loop
      perform pg_temp.modos(r.m, r.m, r.m);
      p := public.os_plano_da_os(pg_temp.os(r.n), date '2026-10-29');
      if p ? 'porque' or p is distinct from pg_temp.plano_antes(pg_temp.os(r.n), date '2026-10-29') then
        v := concat_ws(' · ', v, r.m || ' ' || r.n);
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'T2a desligado e sombra: o cartão de antes, byte a byte, sem a chave porque', v is null, v);
    perform pg_temp.modos('ligado', 'desligado', 'desligado');
    p := public.os_plano_da_os(pg_temp.os('204'), date '2026-10-29');
    v_res := pg_temp.ok(v_res, 'T2b o Daniel (gestor): quem, a fonte, as 3 suposições, o critério e a última mudança, sem o texto longo',
      p -> 'porque' = jsonb_build_object('quem_texto', 'marcado pelo gestor', 'fonte_texto', '1 dia pelo orçamento (R$ 2.160 de mão de obra; estimativa minha)',
        'suposicoes', '["Cabo: contei 7 dias úteis de entrega (não sei de quem comprar)", "na MP Motorhomes (supus pelo tipo do bem)", "1 pessoa (dupla só quando o serviço pede)"]'::jsonb,
        'criterio_texto', 'só ele estava livre', 'degrau_texto', 'mudei o dia, dentro da semana combinada')
      and (p ->> 'os')::uuid = pg_temp.os('204') and (p - 'porque') = pg_temp.plano_antes(pg_temp.os('204'), date '2026-10-29'), (p -> 'porque')::text);
    v := (public.os_plano_da_os(pg_temp.os('205'), date '2026-10-29') -> 'porque')::text;
    v_res := pg_temp.ok(v_res, 'T2c a Elisa (marcada por você): "marcado por você" e a duração, sem suposição nem critério (são do gestor)',
      v::jsonb = '{"quem_texto": "marcado por você", "fonte_texto": "1,5 dia (estimativa minha, só para reservar)", "suposicoes": [], "criterio_texto": null, "degrau_texto": null}'::jsonb, v);
    v := (public.os_plano_da_os(pg_temp.os('208'), date '2026-10-29') -> 'porque')::text || ' · '
         || (public.os_plano_da_os(pg_temp.os('203'), date '2026-10-29') -> 'porque')::text;
    v_res := pg_temp.ok(v_res, 'T2d as reservas: a sua (Hugo) "reservado por você", sem fonte; a do gestor (Caio) "reservado pelo gestor", com o que contei e o critério',
      split_part(v, ' · ', 1)::jsonb = '{"quem_texto": "reservado por você", "fonte_texto": null, "suposicoes": [], "criterio_texto": null, "degrau_texto": null}'::jsonb
      and split_part(v, ' · ', 2)::jsonb = '{"quem_texto": "reservado pelo gestor", "fonte_texto": null, "suposicoes": ["o barco livre nesses dias (ninguém disse que está em uso)"], "criterio_texto": "quem você disse", "degrau_texto": null}'::jsonb, v);
    p := public.os_plano_da_os(pg_temp.os('206'), date '2026-10-29');
    v_res := pg_temp.ok(v_res, 'T2e de fora (o Fábio, nada marcado): sem a chave, o cartão de antes',
      not p ? 'porque' and p = pg_temp.plano_antes(pg_temp.os('206'), date '2026-10-29'), p::text);
    update public.service_orders set status = 'completed' where id = pg_temp.os('204');
    p := public.os_plano_da_os(pg_temp.os('204'), date '2026-10-29');
    v_res := pg_temp.ok(v_res, 'T2f a OS concluída: sem a chave (como o campo, a equipe e o local)', not p ? 'porque', p::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado('desligado');
    perform pg_temp.modos('ligado', 'desligado', 'desligado');
    p := public.os_plano_da_os(pg_temp.os('201'), date '2026-10-29');
    v_res := pg_temp.ok(v_res, 'T2g a marcação de antes do porquê: "de antes de eu guardar o porquê" (não a duração de hoje), sem suposição nem critério',
      p -> 'porque' = '{"quem_texto": "marcado pelo gestor", "fonte_texto": "de antes de eu guardar o porquê", "suposicoes": [], "criterio_texto": null, "degrau_texto": null}'::jsonb,
      (p -> 'porque')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$t2$;

-- ── T3. agenda_ver: os 3 focos ───────────────────────────────────────────────────────────────────────
do $t3$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  a     jsonb;
  v     text;
  m     text;
  c_pq  constant text := 'Daniel (OS-00204): marquei qui 05/11 com João. Duração: 1 dia pelo orçamento (R$ 2.160 de mão de obra; estimativa minha). Contei: Cabo: contei 7 dias úteis de entrega (não sei de quem comprar); na MP Motorhomes (supus pelo tipo do bem); 1 pessoa (dupla só quando o serviço pede). João: só ele estava livre. Última mudança: mudei o dia, dentro da semana combinada. Se algo estiver errado, me diga o certo.';
  c_19  constant text := 'tudo, livre, o_que_fazer, riscos, material, atrasos, aprontar, decisoes, mudancas, plano, ppc, diarias, marcos, comissao, equipe, compras, fornecedores, clientes ou aprendizado';
  c_ag  constant timestamptz := timestamptz '2026-10-29 17:00-03';
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' or to_regprocedure('pg_temp.ver_antes(uuid, text, text, text, text, jsonb, boolean, date)') is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'T3 agenda_ver', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  v := pg_temp.erro_de($s$select public.agenda_ver(null, null, null, 'porquee', null, null, false, date '2026-10-29')$s$);
  v_res := pg_temp.ok(v_res, 'T3a o foco que não existe: a mensagem dos 19, igual (os 3 novos ficam fora da conferência, R9.5-18)',
    v = format('22023 agenda_ver: foco "porquee" não existe (%s)', c_19), v);
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.por_cima();
    perform set_config('agenda.agora', c_ag::text, true);
    -- ── desligado ──
    perform pg_temp.modos('desligado', 'desligado', 'desligado');
    r := pg_temp.ver('como_pensou');
    a := pg_temp.ver_antes(null, 'proxima_semana', null, null, null, null, false, date '2026-10-29');
    v_res := pg_temp.ok(v_res, 'T3b como_pensou desligado: a semana que vem de antes, byte a byte (contra a origem), rota semana; com a semana dita, a dela',
      pg_temp.limpa(r) = pg_temp.limpa(a) and r ->> 'rota' = 'semana' and (r ->> 'ok')::boolean and pg_temp.limpa(r) = pg_temp.limpa(pg_temp.ver(null, null, 'proxima_semana'))
      and pg_temp.limpa(pg_temp.ver('como_pensou', null, 'semana')) = pg_temp.limpa(pg_temp.ver_antes(null, 'semana', null, null, null, null, false, date '2026-10-29'))
      and not (r ? 'dados' and r -> 'dados' ? 'teste'), left(r::text, 300));
    r := pg_temp.ver('porque', 'Daniel');
    v_res := pg_temp.ok(v_res, 'T3c porque desligado com a OS: a leitura de antes da OS, byte a byte (contra a origem), rota os',
      r = pg_temp.ver_antes(null, null, null, null, 'Daniel', null, false, date '2026-10-29') and r ->> 'rota' = 'os' and (r ->> 'ok')::boolean, left(r::text, 300));
    v := concat_ws(' | ', pg_temp.ver('porque') ->> 'texto', pg_temp.ver('porque', ' ') ->> 'ok');
    v_res := pg_temp.ok(v_res, 'T3d porque sem a OS (em qualquer modo): a pergunta, com a saída', v = 'De qual serviço? Me diga o nome do cliente. | false', v);
    r := pg_temp.ver('placar');
    v_res := pg_temp.ok(v_res, 'T3e placar desligado: a frase com a saída (*como foi a semana*), sem dados',
      r = '{"ok": true, "rota": "placar", "texto": "O placar da semana ainda não está ligado. O plano cumprido da semana passada está em *como foi a semana*."}'::jsonb, r::text);
    -- ── sombra ──
    perform pg_temp.modos('desligado', 'sombra', 'sombra');
    r := pg_temp.ver('como_pensou');
    a := pg_temp.ver_antes(null, 'proxima_semana', null, null, null, null, false, date '2026-10-29');
    v_res := pg_temp.ok(v_res, 'T3f como_pensou em sombra: a de antes, byte a byte, e o novo em dados.teste ("Em teste: Como pensei a semana de 02 a 06/11")',
      pg_temp.limpa(r #- '{dados,teste}') = pg_temp.limpa(a) and r #>> '{dados,teste,texto}' like 'Em teste: Como pensei a semana de 02 a 06/11:%'
      and r #> '{dados,teste}' = public.agenda_como_pensei(date '2026-11-02', date '2026-10-29', c_ag), left(r::text, 400));
    r := pg_temp.ver('porque', 'Daniel');
    v_res := pg_temp.ok(v_res, 'T3g porque em sombra: a de antes da OS, byte a byte, e o porquê em dados.teste',
      r #- '{dados,teste}' = pg_temp.ver_antes(null, null, null, null, 'Daniel', null, false, date '2026-10-29') and r #>> '{dados,teste,texto}' = c_pq, left(r::text, 300));
    r := pg_temp.ver('placar');
    v_res := pg_temp.ok(v_res, 'T3h placar em sombra: a frase de desligado e o placar em dados.teste ("Em teste: ")',
      r - 'dados' = '{"ok": true, "rota": "placar", "texto": "O placar da semana ainda não está ligado. O plano cumprido da semana passada está em *como foi a semana*."}'::jsonb
      and r #>> '{dados,teste,modo}' = 'sombra' and r #>> '{dados,teste,texto}' like 'Em teste: %', left(r::text, 300));
    r := pg_temp.ver('como_pensou', null, 'mês que vem que não existe');
    v_res := pg_temp.ok(v_res, 'T3i em sombra, o período que não se entende: a resposta de antes (a frase do período), sem teste',
      r = pg_temp.ver_antes(null, 'mês que vem que não existe', null, null, null, null, false, date '2026-10-29') and r ->> 'rota' = 'periodo', r::text);
    -- ── ligado ──
    perform pg_temp.modos('desligado', 'ligado', 'ligado');
    r := pg_temp.ver('como_pensou');
    a := public.agenda_como_pensei(date '2026-11-02', date '2026-10-29', c_ag);
    v_res := pg_temp.ok(v_res, 'T3j como_pensou ligado: o texto de agenda_como_pensei (a semana que vem), rota como_pensou, os dados sem o texto',
      r = jsonb_build_object('ok', true, 'texto', a ->> 'texto', 'dados', a - 'texto', 'rota', 'como_pensou') and r ->> 'texto' like 'Como pensei a semana de 02 a 06/11:%', left(r::text, 300));
    r := pg_temp.ver('como_pensou', null, 'semana');
    v_res := pg_temp.ok(v_res, 'T3k como_pensou ligado com a semana dita: a semana dela',
      r ->> 'texto' = public.agenda_como_pensei(date '2026-10-29', date '2026-10-29', c_ag) ->> 'texto' and r ->> 'texto' like 'Como pensei a semana de 26 a 30/10:%', left(r::text, 200));
    r := pg_temp.ver('porque', 'Daniel');
    v_res := pg_temp.ok(v_res, 'T3l porque ligado: o porquê da OS, rota porque, os dados sem o texto',
      r ->> 'texto' = c_pq and r ->> 'rota' = 'porque' and (r ->> 'ok')::boolean and r #>> '{dados,estado}' = 'marcada' and not (r -> 'dados' ? 'texto'), left(r::text, 300));
    v := pg_temp.ver('porque', 'Fábio') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'T3m porque ligado de uma OS de fora: o motivo de agora (não "ainda não guardo", R9.12-1)',
      v like 'Fábio (OS-00206) ficou de fora%' and v not like '%guardo%', v);
    r := pg_temp.ver('porque', 'Fulano de Tal');
    v_res := pg_temp.ok(v_res, 'T3n porque ligado de uma OS que não existe: a frase do resolvedor, rota os',
      r ->> 'rota' = 'os' and not (r ->> 'ok')::boolean and r ->> 'texto' = public.agenda_resolver_os('Fulano de Tal', date '2026-10-29', false) ->> 'texto', r::text);
    r := pg_temp.ver('placar');
    v_res := pg_temp.ok(v_res, 'T3o placar ligado: o texto de agenda_placar (a semana da janela), rota placar',
      r ->> 'texto' = public.agenda_placar(null, date '2026-10-29', c_ag) ->> 'texto' and r ->> 'rota' = 'placar' and r #>> '{dados,modo}' = 'ligado'
      and coalesce(r ->> 'texto', '') <> '', left(r::text, 300));
    r := pg_temp.ver('placar', null, 'semana');
    v_res := pg_temp.ok(v_res, 'T3p placar ligado com a semana dita: a dela',
      r ->> 'texto' = public.agenda_placar(date '2026-10-29', date '2026-10-29', c_ag) ->> 'texto' and r #>> '{dados,de}' = '2026-10-26', left(r::text, 300));
    r := pg_temp.ver('como_pensou', null, 'mês que vem que não existe');
    v_res := pg_temp.ok(v_res, 'T3q ligado, o período que não se entende: a frase do período (rota periodo), como a semana',
      r = pg_temp.ver_antes(null, 'mês que vem que não existe', null, null, null, null, false, date '2026-10-29') and r ->> 'rota' = 'periodo', r::text);
    -- a leitura desligada e sem o dia
    update public.agenda_config set modo_leitura = 'desligado' where id;
    v := (select string_agg(pg_temp.ver(f, 'Daniel') ->> 'rota', ',' order by f) from unnest(array['como_pensou', 'placar', 'porque']) f);
    v_res := pg_temp.ok(v_res, 'T3r a leitura desligada: a frase de sempre nos 3', v = 'desligada,desligada,desligada', v);
    v := pg_temp.erro_de($s$select public.agenda_ver(null, null, null, 'como_pensou', null, null, false, null)$s$);
    v_res := pg_temp.ok(v_res, 'T3s sem o dia: 22004', v = '22004 agenda_ver: sem o dia de hoje', v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$t3$;

-- ── T4. A porta ──────────────────────────────────────────────────────────────────────────────────────
do $t4$
declare
  v_res     jsonb := '[]'::jsonb;
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tecnico constant uuid := 'aa000000-0000-4000-8000-000000000002';
  v         text;
  f         text;
  c_sql     constant text := $s$select public.agenda_ver(null, null, null, %L, 'Daniel', null, false, date '2026-10-29') ->> 'rota'$s$;
begin
  if coalesce(current_setting('agenda_teste.cenario_motor', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'T4 a porta', true, 'PULADO: sem o cenário do motor (rode pela bancada)'));
    return;
  end if;
  begin
    perform pg_temp.publicado('sombra');
    perform pg_temp.por_cima();
    perform pg_temp.modos('desligado', 'ligado', 'ligado');
    v := null;
    foreach f in array array['como_pensou', 'porque', 'placar'] loop
      v := concat_ws(' | ', v, pg_temp.como('authenticated', c_tecnico, format(c_sql, f)));
    end loop;
    v_res := pg_temp.ok(v_res, 'T4a o técnico com login: 42501 nos 3 focos, pela porta daqui (antes de ler a config)',
      v = 'erro 42501: Como pensei a agenda é com o administrador ou o financeiro. | erro 42501: O porquê da agenda é com o administrador ou o financeiro. | erro 42501: O placar da agenda é com o administrador ou o financeiro.', v);
    v := null;
    foreach f in array array['como_pensou', 'porque', 'placar'] loop
      v := concat_ws(' | ', v, pg_temp.como('authenticated', c_admin, format(c_sql, f)));
    end loop;
    v_res := pg_temp.ok(v_res, 'T4b o administrador com login (o painel) lê os 3', v = 'como_pensou | porque | placar', v);
    v := null;
    foreach f in array array['como_pensou', 'porque', 'placar'] loop
      v := concat_ws(' | ', v, pg_temp.como('service_role', null, format(c_sql, f)));
    end loop;
    v_res := pg_temp.ok(v_res, 'T4c o service_role (o WhatsApp) lê os 3', v = 'como_pensou | porque | placar', v);
    perform pg_temp.modos('ligado', 'ligado', 'ligado');
    v := pg_temp.como('authenticated', c_tecnico, $s$select public.agenda_tela_semana(date '2026-11-02', date '2026-10-29', now())::text$s$) || ' | '
         || pg_temp.como('authenticated', c_tecnico, format($s$select public.os_plano_da_os(%L, date '2026-10-29')::text$s$, pg_temp.os('204')));
    v_res := pg_temp.ok(v_res, 'T4d a tela e o cartão com o técnico: 42501, a porta de antes',
      v = 'erro 42501: A agenda de produção é com o administrador. | erro 42501: O plano da OS é com o administrador.', v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$t4$;

select teste, ok, detalhe from _resultado order by teste collate "C";
rollback;
