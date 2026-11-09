-- Prova do prazo real da Agenda de Produção, Fase 7e (pacote P5; migration 20261111100400; spec-fase7e §5.4, §8.2, §8.3 e o bloco R7: R7.3-1, R7.6, R7.12-2, R7.12-4, R7.13).
-- bancada: depende de 20261111100400
--
--   P0  as funções: portas, tipo; o comentário de fator_promessa; a migration só cria as 2 e não fala do cliente
--   P1  o aprendido: os números da §8.2 (1,40; 1,24; 1,38; 1,43), o P80 no detalhe, os limites, a janela, a amostra, o mínimo, a volta a medir, o erro de uma chave, o texto; nunca em uso, nem com modo_promessa ligado
--   P2  agenda_promessa_da_os: as saídas (sem plano, OS que não existe, padrão, geral, classe), os dias (5 → 7; 3 → 4; 1 → 1), o plano que acaba no sábado, a reserva, sem modos, quem vê
--   P5  a ficha da equipe nunca diz a data com folga (U1), com a guarda de R7.12-4
--   P6  nada de cliente: nenhum leitor em _agenda_cliente_*, nem na equipe, nem no motor
--
-- ═══ COMO RODAR ═══  Na bancada: node scripts/bancada-agenda/rodar.mjs. Em produção, só DEPOIS de aplicar a migration, com o OK: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_promessa.sql
--   Tudo dentro de begin/rollback. O que usa fixture só roda na bancada (fora dela sai PULADO). Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ── P0. As funções (sem fixture) ───────────────────────────────────────────────────────────────────
insert into _resultado
select 'P0a as 2 funções existem; a leitura tem porta para authenticated e service_role; o passo sem grant nem service_role; anon nada',
       has_function_privilege('authenticated', 'public.agenda_promessa_da_os(uuid, date)', 'execute')
       and has_function_privilege('service_role', 'public.agenda_promessa_da_os(uuid, date)', 'execute')
       and not has_function_privilege('anon', 'public.agenda_promessa_da_os(uuid, date)', 'execute')
       and not has_function_privilege('authenticated', 'public._agenda_aprender_promessa(date, timestamptz)', 'execute')
       and not has_function_privilege('service_role', 'public._agenda_aprender_promessa(date, timestamptz)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_aprender_promessa(date, timestamptz)', 'execute'),
       null;

insert into _resultado
select 'P0b a leitura é stable e invoker; o passo é volatile e definer; as duas com search_path fixo',
       (select p.provolatile = 's' and not p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
          from pg_proc p where p.oid = 'public.agenda_promessa_da_os(uuid, date)'::regprocedure)
       and (select p.provolatile = 'v' and p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')
              from pg_proc p where p.oid = 'public._agenda_aprender_promessa(date, timestamptz)'::regprocedure),
       null;

insert into _resultado
select 'P0c o comentário de fator_promessa: ganha leitor, é só para o dono e não diz nem que não tem leitor nem que liga com modo_promessa',
       v like '%ponto de partida do prazo real%' and v like '%agenda_promessa_da_os%' and v like '%Nunca vai ao cliente%'
       and v not like '%SEM LEITOR%' and v not like '%vale com modo_promessa ligado%',
       v
  from (select col_description('public.agenda_config'::regclass, a.attnum) v from pg_attribute a
         where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'fator_promessa') x;

do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  v_m   text := coalesce(current_setting('agenda_teste.mig_promessa_fase7e', true), '');
  v_dif text;
begin
  if v_m = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P0d a migration', true, 'PULADO: sem agenda_teste.mig_promessa_fase7e (rode pela bancada)'));
    return;
  end if;
  select string_agg(distinct m[1], ',' order by m[1]) into v_dif
    from regexp_matches(v_m, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
  v_res := pg_temp.ok(v_res, 'P0d a migration só cria as 2 funções: nenhuma recriada, nenhuma de cliente (R7.13)', v_dif = '_agenda_aprender_promessa,agenda_promessa_da_os', v_dif);
  v_res := pg_temp.ok(v_res, 'P0e a migration não altera tabela nem grava dado',
    v_m !~* '(^|\n)\s*(alter table|insert into|update public|delete from|create table)', null);
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── A fixture e os ajudantes ───────────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' then
    execute current_setting('agenda_teste.fase7e');
  end if;
end
$carga$;

create function pg_temp.fx() returns boolean language sql stable as $f$ select coalesce(current_setting('agenda_teste.fase7e', true), '') <> '' $f$;
create function pg_temp.os(p_num text) returns uuid language sql stable as $f$ select id from public.service_orders where service_order_number = p_num $f$;
create function pg_temp.zeca() returns uuid language sql immutable as $f$ select 'e7e00000-0000-4000-8000-00000000aa02'::uuid $f$;
-- A razão do prazo gravada de um jeito que o gatilho aceita (versão + 1 e uma entrada no histórico)
create function pg_temp.razao(p_num text, p_r numeric) returns void language sql as $f$
  update public.agenda_medidas_os m set razao_prazo = p_r, versao = m.versao + 1, historico = m.historico || '[{"t": "teste"}]'::jsonb
   where m.service_order_id = pg_temp.os(p_num)
$f$;
-- As 8 razões da §8.2 nas 8 OS do viés, e as outras medidas sem razão: o P80 fica o da spec
create function pg_temp.medidas_da_spec() returns void language plpgsql as $f$
declare
  r record;
begin
  update public.agenda_config set modo_aprendizado = 'ligado' where id;
  perform public._agenda_aprender_congelar(date '2027-01-07');
  perform public._agenda_aprender_medir(date '2027-01-07');
  update public.agenda_medidas_os m set razao_prazo = null, versao = m.versao + 1, historico = m.historico || '[{"t": "teste"}]'::jsonb where m.razao_prazo is not null;
  for r in select * from (values ('OS-7E-E1', 1.0), ('OS-7E-E2', 1.0), ('OS-7E-E3', 1.0), ('OS-7E-E4', 1.1),
                                 ('OS-7E-G1', 1.2), ('OS-7E-G2', 1.25), ('OS-7E-G3', 1.4), ('OS-7E-B1', 1.6)) t(num, v) loop
    perform pg_temp.razao(r.num, r.v);
  end loop;
end $f$;
-- Uma OS aberta nova (rv:energia, pelo serviço e pelo veículo da fixture)
create function pg_temp.aberta(p_n int, p_servico text default 'Instalação de inversor e baterias', p_veiculo uuid default 'e7e00000-0000-4000-8000-000000000b02') returns uuid language plpgsql as $f$
declare
  v_os uuid := md5('e7e:p5:' || p_n)::uuid;
begin
  perform set_config('agenda.porta', 'on', true);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at, grand_total)
  values (v_os, 'OS-7EP' || p_n, 'e7e00000-0000-4000-8000-000000000c02', p_veiculo, 'approved', 'approved', 'repair',
          timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-01 10:00-03', timestamptz '2026-12-02 10:00-03', 3820);
  insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (v_os, p_servico, 'visit', 1, 3820, 3820, timestamptz '2026-12-01 10:00-03');
  perform set_config('agenda.porta', 'off', true);
  return v_os;
end $f$;
-- Um dia de plano (o turno da manhã de uma pessoa só desta OS, ou de quem vier), com o tipo e o resultado dados
create function pg_temp.dia(p_os uuid, p_dia date, p_tipo text default 'execucao', p_res text default null, p_payee uuid default null) returns void language plpgsql as $f$
declare
  v_p uuid := coalesce(p_payee, md5('e7e:p5:pessoa:' || p_os)::uuid);
begin
  perform set_config('agenda.porta', 'on', true);
  insert into public.payees (id, name, kind, active) values (v_p, 'Pessoa', 'prestador', true) on conflict (id) do nothing;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, resultado, motivo, reserva_de)
  values (p_os, v_p, p_dia, 'manha', 'turno', p_tipo, 'publicada', 'motor', timestamptz '2027-01-07 10:00-03', p_res, case when p_res is not null then 'clima' end, case when p_tipo = 'reserva' then 'teto' end);
  perform set_config('agenda.porta', 'off', true);
end $f$;
-- Uma linha do prazo real pronta, como o gravador deixa
create function pg_temp.linha(p_chave text, p_calc numeric, p_n int) returns void language sql as $f$
  insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, estado, calculado_em)
  values ('promessa', p_chave, case when p_chave = 'todas' then 'todas' else 'fina' end, 1.5, 1, p_n, p_calc, case when p_calc is null then 'medindo' else 'sombra' end, now())
  on conflict (item, chave) do update set calculado = excluded.calculado, n = excluded.n, estado = excluded.estado
$f$;

-- ── P1. O aprendido ────────────────────────────────────────────────────────────────────────────────
do $p1$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-01-07';
  c_agora constant timestamptz := timestamptz '2027-01-07 16:05-03';
  r jsonb;
  a public.agenda_aprendizado;
  v_ac int;
  v_pe int;
  v_eq int;
  v_fi int;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P1 o aprendido', true, 'PULADO: sem a fixture (rode pela bancada)'));
    return;
  end if;
  begin
    v_res := pg_temp.ok(v_res, 'P1z o dia e a hora são obrigatórios',
      (select count(*) = 2 from (select 1) x cross join lateral (values (1), (2)) y(i)
        where pg_temp.como(null, 'postgres', case i when 1 then 'select public._agenda_aprender_promessa(null, now())::text' else 'select public._agenda_aprender_promessa(current_date, null)::text' end) like 'erro 22023%'), null);
    update public.agenda_config set modo_promessa = 'sombra', gestor_so_propor = true where id;
    perform pg_temp.medidas_da_spec();
    select count(*) into v_ac from public.agenda_acoes;
    select count(*) into v_pe from public.agenda_perguntas;
    select count(*) into v_eq from public.agenda_equipe_mensagens;
    select count(*) into v_fi from public.whatsapp_send_queue;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1a sem erro em nenhuma chave; 4 chaves (o geral e as 3 classes), todas em teste', (r ->> 'erros')::int = 0 and (r ->> 'chaves')::int = 4 and (r #>> '{estados,sombra}')::int = 4 and jsonb_array_length(jsonb_path_query_array(r -> 'estados', '$.keyvalue()')) = 1, r::text);
    select * into a from public.agenda_aprendizado where item = 'promessa' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'P1b o geral: P80 1,34, Z = 8/13, base 1,5 → 1,40 (a §8.2)', a.calculado = 1.40 and a.nivel = 'todas' and a.padrao = 1.5 and a.n = 8, format('%s %s %s %s', a.calculado, a.nivel, a.padrao, a.n));
    v_res := pg_temp.ok(v_res, 'P1c o detalhe do geral: p80, z e n', (a.detalhe ->> 'p80')::numeric = 1.34 and (a.detalhe ->> 'z')::numeric = 0.6154 and (a.detalhe ->> 'n')::int = 8, a.detalhe::text);
    v_res := pg_temp.ok(v_res, 'P1d a amostra guarda as 8 OS, a mais recente primeiro (OS-7E-B1, 1,6)', jsonb_array_length(a.amostra) = 8 and a.amostra #>> '{0,numero}' = 'OS-7E-B1' and (a.amostra #>> '{0,razao}')::numeric = 1.6, a.amostra::text);
    select * into a from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:energia';
    v_res := pg_temp.ok(v_res, 'P1e rv:energia: P80 1,04, Z = 4/9, base o geral sem arredondar → 1,24; o padrão é fator_promessa', a.calculado = 1.24 and a.nivel = 'fina' and a.padrao = 1.5 and a.n = 4 and (a.detalhe ->> 'p80')::numeric = 1.04, format('%s %s', a.calculado, a.detalhe));
    v_res := pg_temp.ok(v_res, 'P1f rv:geral: P80 1,34, Z = 3/8 → 1,38', (select calculado = 1.38 from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:geral'), null);
    v_res := pg_temp.ok(v_res, 'P1g barco:energia: 1,6, Z = 1/6 → 1,43', (select calculado = 1.43 from public.agenda_aprendizado where item = 'promessa' and chave = 'barco:energia'), null);
    -- R7.12-9: o texto é o que está no banco, com os números da §6.2 e da R7.3
    select * into a from public.agenda_aprendizado where item = 'promessa' and chave = 'todas';
    v_res := pg_temp.ok(v_res, 'P1h o texto do geral é o da R7.3, byte a byte',
      a.texto = 'Prazo real: 8 em cada 10 OS terminaram em até 1,34× os dias planejados (8 OS). Com essa folga, um serviço de 5 dias acaba em até 7 dias úteis. Só para você: ao cliente não digo data de pronto.', a.texto);
    -- AG7-32: nada em uso, nada de ação, de pergunta nem de mensagem
    v_res := pg_temp.ok(v_res, 'P1i nada em uso e nenhuma ação, pergunta, mensagem da equipe nem item de fila',
      (select bool_and(em_uso is null and estado = 'sombra') from public.agenda_aprendizado where item = 'promessa')
      and (select count(*) = v_ac from public.agenda_acoes) and (select count(*) = v_pe from public.agenda_perguntas)
      and (select count(*) = v_eq from public.agenda_equipe_mensagens) and (select count(*) = v_fi from public.whatsapp_send_queue),
      format('acoes %s/%s perguntas %s/%s', (select count(*) from public.agenda_acoes), v_ac, (select count(*) from public.agenda_perguntas), v_pe));
    -- com o interruptor forçado na linha e sem o freio: continua em teste (AG7-32, R7.6)
    update public.agenda_config set modo_promessa = 'ligado', gestor_so_propor = false where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1j com modo_promessa ligado na linha e sem o freio: nunca em uso, nenhuma ação',
      (select bool_and(em_uso is null and estado = 'sombra') from public.agenda_aprendizado where item = 'promessa') and (select count(*) = v_ac from public.agenda_acoes),
      r::text);
    update public.agenda_config set modo_promessa = 'sombra', gestor_so_propor = true where id;
    -- 2ª rodada: igual; o histórico não anda
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1k 2ª rodada igual (1,40; o histórico não ganha entrada)',
      (select calculado = 1.40 and jsonb_array_length(historico) = 1 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas'), (select historico::text from public.agenda_aprendizado where item = 'promessa' and chave = 'todas'));
    -- os limites
    update public.agenda_config set fator_max = 1.50, fator_promessa = 2.50 where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1l fator_max (1,50) corta o geral (1,79), e a base da classe é o geral já cortado: rv:energia 1,30 (com o 1,79 daria 1,46)',
      (select calculado = 1.50 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas') and (select calculado = 1.30 from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:energia'),
      (select string_agg(chave || '=' || calculado, ' ') from public.agenda_aprendizado where item = 'promessa'));
    -- o texto usa o número arredondado: 1,30 × 5 = 6,5 → 7 (sem arredondar, 1,2956 × 5 daria 6)
    v_res := pg_temp.ok(v_res, 'P1l2 o texto da classe sai do calculado de 2 casas (1,30: um serviço de 5 dias, até 7)',
      (select texto like '%acaba em até 7 dias úteis%' from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:energia'), (select texto from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:energia'));
    update public.agenda_config set fator_max = 2.50, fator_promessa = 1.50, promessa_min = 1.45 where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1m promessa_min (1,45) sobe o geral e a classe; a base da classe é o geral já no piso',
      (select calculado = 1.45 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas')
      and (select calculado = 1.45 from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:energia'), r::text);
    update public.agenda_config set promessa_min = 1.00 where id;
    update public.agenda_config set fator_amostra_max = 6 where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1n fator_amostra_max: só as 6 mais recentes de cada chave (o geral com 8 fica com n = 6, com a OS-7E-B1 e sem a OS-7E-E1; rv:energia, com 4, fica com 4)',
      (select n = 6 and amostra::text like '%OS-7E-B1%' and amostra::text not like '%OS-7E-E1%' from public.agenda_aprendizado where item = 'promessa' and chave = 'todas') and (select n = 4 from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:energia'), r::text);
    update public.agenda_config set fator_amostra_max = 20, credibilidade_k = 1 where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1o credibilidade_k vem da config: k = 1, Z = 8/9 → 1,36 (1,3578)', (select calculado = 1.36 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas'), r::text);
    update public.agenda_config set credibilidade_k = 5, fator_percentil = 0.5 where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1p fator_percentil vem da config: 0,5 = a mediana 1,15, Z = 8/13 → 1,28', (select calculado = 1.28 and (detalhe ->> 'p80')::numeric = 1.15 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas'), r::text);
    update public.agenda_config set fator_percentil = 0.80, fator_promessa = 1.20 where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1q o ponto de partida vem de fator_promessa: 1,20, Z = 8/13 → 1,29 (1,2862); o padrão das 2 chaves é ele',
      (select calculado = 1.29 and padrao = 1.20 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas') and (select padrao = 1.20 from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:energia'), r::text);
    -- a base da classe é o geral sem arredondar: com o ponto de partida 1,35, o geral dá 1,34385; barco:energia sai 1,39 (com a base arredondada, 1,34, sairia 1,38)
    update public.agenda_config set fator_promessa = 1.35 where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1q2 a base da classe é o geral sem arredondar: barco:energia 1,39 (arredondado daria 1,38)', (select calculado = 1.39 from public.agenda_aprendizado where item = 'promessa' and chave = 'barco:energia'), r::text);
    update public.agenda_config set fator_promessa = 1.50 where id;
    -- o mínimo de OS: com 5, as classes de menos voltam a medindo, sem número em uso
    update public.agenda_config set promessa_n_min = 5 where id;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    select * into a from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:energia';
    v_res := pg_temp.ok(v_res, 'P1r n_min 5: o geral (8) em teste, a classe (4) medindo; o texto diz "4 de 5 OS medidas"',
      (select estado = 'sombra' from public.agenda_aprendizado where item = 'promessa' and chave = 'todas') and a.estado = 'medindo'
      and a.texto = 'Prazo real: 4 de 5 OS medidas. Só para você: ao cliente não digo data de pronto.', a.texto);
    update public.agenda_config set promessa_n_min = 1 where id;
    -- medida fora da janela e razão nula não entram
    perform pg_temp.razao('OS-7E-B1', null);
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1s a razão nula não entra (7 OS no geral) e a classe que ficou sem medida volta a medindo, sem apagar a linha, com o texto de n = 0',
      (select n = 7 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas')
      and (select n = 0 and calculado is null and estado = 'medindo' and texto = 'Prazo real: nenhuma OS medida ainda. Só para você: ao cliente não digo data de pronto.' from public.agenda_aprendizado where item = 'promessa' and chave = 'barco:energia'),
      (select format('%s %s %s', n, estado, texto) from public.agenda_aprendizado where item = 'promessa' and chave = 'barco:energia'));
    perform pg_temp.razao('OS-7E-B1', 1.6);
    update public.agenda_config set aprender_janela_dias = 150 where id;
    r := public._agenda_aprender_promessa(date '2027-02-08', c_agora);     -- 150 dias antes de 08/02/2027 é 11/09/2026: saem E1 a E4 e G1 (concluídas até 09/09), ficam G2, G3 e B1
    v_res := pg_temp.ok(v_res, 'P1t só as concluídas na janela (150 dias até 08/02: 3 das 8)', (select n = 3 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas'), r::text);
    r := public._agenda_aprender_promessa(date '2026-09-14', c_agora);     -- só até p_hoje: 14/09 ainda não viu G3 (22/09) nem B1 (29/09)
    v_res := pg_temp.ok(v_res, 'P1u concluída depois de p_hoje não entra (até 14/09: E1 a G2, 6 das 8)', (select n = 6 from public.agenda_aprendizado where item = 'promessa' and chave = 'todas'), r::text);
    update public.agenda_config set aprender_janela_dias = 365 where id;
    r := public._agenda_aprender_promessa(date '2031-01-07', c_agora);
    v_res := pg_temp.ok(v_res, 'P1v sem medida na janela: todas as chaves voltam a medindo (n = 0, sem calculado), sem apagar', (select count(*) = 4 and bool_and(n = 0 and estado = 'medindo' and calculado is null) from public.agenda_aprendizado where item = 'promessa'), r::text);
    -- ponta a ponta, com a medida da função de verdade: o plano de 1 dia que levou 2 (OS-7E-G2 tem 2 de real): razão 2,00 (a medida do P2 lê prazo_plano_no_inicio)
    update public.os_planejamento set prazo_plano_no_inicio = 1 where service_order_id = pg_temp.os('OS-7E-G2');
    perform public._agenda_aprender_medir(c_hoje);
    v_res := pg_temp.ok(v_res, 'P1w ponta a ponta: a medida da função de verdade dá razão 2,00 e o passo a lê (o P80 da classe rv:geral sobe)',
      (select razao_prazo = 2.00 and prazo_real_du = 2 and prazo_plano_du = 1 from public.agenda_medidas_os where service_order_id = pg_temp.os('OS-7E-G2')), (select format('%s %s %s', razao_prazo, prazo_real_du, prazo_plano_du) from public.agenda_medidas_os where service_order_id = pg_temp.os('OS-7E-G2')));
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1x a amostra da classe traz a razão medida (2,00, OS-7E-G2)',
      (select exists (select 1 from jsonb_array_elements(amostra) e where e ->> 'numero' = 'OS-7E-G2' and (e ->> 'razao')::numeric = 2.00) from public.agenda_aprendizado where item = 'promessa' and chave = 'rv:geral'), r::text);
    -- o erro de uma chave vai ao log e o resto segue
    execute $f$create or replace function public._agenda_aprendizado_gravar(p_item text, p_chave text, p_nivel text, p_calculado numeric, p_n integer, p_amostra jsonb, p_padrao numeric, p_detalhe jsonb, p_agora timestamp with time zone)
      returns jsonb language plpgsql as $g$ begin if p_chave = 'rv:energia' then raise exception 'estouro'; end if; return '{"estado":"sombra"}'::jsonb; end $g$;$f$;
    r := public._agenda_aprender_promessa(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'P1y o erro de uma chave vai a aprender:promessa e as outras seguem (erros = 1; as demais em teste)',
      (r ->> 'erros')::int = 1 and (r ->> 'chaves')::int >= 4 and (r #>> '{estados,sombra}')::int = (r ->> 'chaves')::int - 1
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'aprender:promessa' and e.message like '%prazo real rv:energia: estouro%'),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$p1$;

-- ── P2. agenda_promessa_da_os ──────────────────────────────────────────────────────────────────────
do $p2$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-03-01';
  c_seg constant date := date '2027-03-08';  -- segunda; a semana de 08 a 12/03 não tem feriado
  v_os uuid;
  v_ob uuid;
  v   jsonb;
  v2  jsonb;
  m   text;
  f   boolean;
  v_dif int := 0;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P2 a leitura', true, 'PULADO: sem a fixture'));
    return;
  end if;
  begin
    v_os := pg_temp.aberta(1);                                                           -- rv:energia
    -- sem plano
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2a sem alocação: {ok: true, sem_plano: true}, só isso', v = '{"ok": true, "sem_plano": true}'::jsonb, v::text);
    v_ob := pg_temp.aberta(20);
    perform pg_temp.dia(v_ob, c_seg, 'reserva');
    v := public.agenda_promessa_da_os(v_ob, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2b só com reserva: o plano tem linha e não tem dia = sem plano', v = '{"ok": true, "sem_plano": true}'::jsonb and public._agenda_plano_da_os(v_ob, c_hoje) is not null, v::text);
    v := public.agenda_promessa_da_os('e7e00000-0000-4000-8000-0000000fffff'::uuid, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2c OS que não existe: ok false, com o que dizer', v = jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.'), v::text);
    v := public.agenda_promessa_da_os(null, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2d OS nula: como a que não existe', (v ->> 'ok')::boolean = false, v::text);
    -- 5 dias planejados, sem nada aprendido
    for k in 0 .. 4 loop perform pg_temp.dia(v_os, c_seg + k); end loop;
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2e sem medida: o padrão (1,5; 5 → 8 dias: qua 17/03), fonte padrao, chave todas, n 0',
      v = jsonb_build_object('ok', true, 'os', v_os, 'inicio', c_seg, 'fim_plano', c_seg + 4, 'prazo_du', 5, 'fator', 1.5, 'fonte', 'padrao', 'chave', 'todas', 'n', 0, 'fim_com_folga', date '2027-03-17'), v::text);
    v_res := pg_temp.ok(v_res, 'P2f as chaves são só estas (R7.3-1): nada de fim_promessa, teria_fim, modo nem texto',
      (select array_agg(k order by k) from jsonb_object_keys(v) k) = '{chave,fator,fim_com_folga,fim_plano,fonte,inicio,n,ok,os,prazo_du}', v::text);
    -- o geral (a §8.2: 5 → 7; 3 → 4; 1 → 1)
    perform pg_temp.linha('todas', 1.40, 8);
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2g o geral (1,40, 8 OS): 5 → 7 dias, fim_com_folga ter 16/03',
      (v ->> 'fator')::numeric = 1.40 and v ->> 'fonte' = 'aprendido' and v ->> 'chave' = 'todas' and (v ->> 'n')::int = 8 and (v ->> 'prazo_du')::int = 5 and (v ->> 'fim_com_folga')::date = date '2027-03-16', v::text);
    v_ob := pg_temp.aberta(2);
    for k in 0 .. 2 loop perform pg_temp.dia(v_ob, c_seg + k); end loop;
    v2 := public.agenda_promessa_da_os(v_ob, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2h 3 → 4 dias: fim_com_folga qui 11/03', (v2 ->> 'prazo_du')::int = 3 and (v2 ->> 'fim_plano')::date = c_seg + 2 and (v2 ->> 'fim_com_folga')::date = c_seg + 3, v2::text);
    v_ob := pg_temp.aberta(3);
    perform pg_temp.dia(v_ob, c_seg);
    v2 := public.agenda_promessa_da_os(v_ob, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2i 1 → 1 dia: o arredondamento apaga, e a data é a do plano', (v2 ->> 'prazo_du')::int = 1 and (v2 ->> 'fim_com_folga')::date = c_seg and (v2 ->> 'fim_com_folga') = (v2 ->> 'fim_plano'), v2::text);
    -- a classe vem antes do geral, a do serviço certo
    perform pg_temp.linha('rv:energia', 1.20, 4);
    perform pg_temp.linha('barco:energia', 2.00, 4);
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2j a classe fina vem antes do geral (rv:energia 1,20, 4 OS): 5 → 6 dias, seg 15/03; a chave e o n dela',
      (v ->> 'fator')::numeric = 1.20 and v ->> 'chave' = 'rv:energia' and (v ->> 'n')::int = 4 and (v ->> 'fim_com_folga')::date = date '2027-03-15', v::text);
    -- a classe com menos medidas que o mínimo, ou sem calculado, não vale
    update public.agenda_config set promessa_n_min = 5 where id;
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2k n_min 5: a classe (4) não vale, fica o geral (8)', (v ->> 'fator')::numeric = 1.40 and v ->> 'chave' = 'todas' and (v ->> 'n')::int = 8, v::text);
    update public.agenda_config set promessa_n_min = 9 where id;
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2l n_min 9: nem o geral vale, volta o padrão, e o n diz quantas o geral já tem (8)', (v ->> 'fator')::numeric = 1.5 and v ->> 'fonte' = 'padrao' and (v ->> 'n')::int = 8, v::text);
    update public.agenda_config set promessa_n_min = 1 where id;
    perform pg_temp.linha('rv:energia', null, 4);
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2m a classe sem calculado não vale: fica o geral', (v ->> 'fator')::numeric = 1.40 and v ->> 'chave' = 'todas', v::text);
    perform pg_temp.linha('rv:energia', 1.20, 4);
    -- o calculado abaixo de 1 (só à mão: o passo nunca grava abaixo de promessa_min) não encurta o plano
    perform pg_temp.linha('rv:energia', 0.70, 4);
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2n um fator abaixo de 1 não encurta o plano: a data é a do fim do plano', (v ->> 'fim_com_folga')::date = c_seg + 4, v::text);
    perform pg_temp.linha('rv:energia', 1.20, 4);
    -- o que o plano conta: a reserva e o não cumprido não entram; o dia já feito entra
    v_ob := pg_temp.aberta(4);
    perform set_config('agenda.hoje', '2027-03-06', true);
    perform pg_temp.dia(v_ob, c_seg - 3, 'execucao', 'nao_cumprido');   -- sex 05/03, não cumprido: não é o início
    perform set_config('agenda.hoje', '', true);
    perform pg_temp.dia(v_ob, c_seg);
    perform pg_temp.dia(v_ob, c_seg + 1);
    perform pg_temp.dia(v_ob, c_seg + 2, 'reserva');
    v2 := public.agenda_promessa_da_os(v_ob, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2o o plano conta os dias vigentes: fora o não cumprido e a reserva (de seg a ter, 2 dias)',
      (v2 ->> 'inicio')::date = c_seg and (v2 ->> 'fim_plano')::date = c_seg + 1 and (v2 ->> 'prazo_du')::int = 2, v2::text);
    v2 := public.agenda_promessa_da_os(v_ob, c_seg + 1);
    v_res := pg_temp.ok(v_res, 'P2o2 com a OS já em andamento o início segue o 1º dia do plano, não o próximo', (v2 ->> 'inicio')::date = c_seg and (v2 ->> 'prazo_du')::int = 2, v2::text);
    -- o feriado: a contagem pula (sexta-feira santa, 26/03/2027)
    perform pg_temp.linha('rv:energia', 2.00, 4);
    v_ob := pg_temp.aberta(5);
    for k in 0 .. 3 loop perform pg_temp.dia(v_ob, date '2027-03-22' + k); end loop;   -- seg 22 a qui 25
    v2 := public.agenda_promessa_da_os(v_ob, date '2027-03-01');
    v_res := pg_temp.ok(v_res, 'P2p o feriado não conta: 4 × 2 = 8 dias a partir de seg 22/03 terminam qui 01/04, pulando a sexta santa',
      (v2 ->> 'fim_com_folga')::date = date '2027-04-01', v2::text);
    perform pg_temp.linha('rv:energia', 1.20, 4);
    -- o sábado, sem sabado_util: nos planos que usam sábado, a data não pode cair antes do fim do plano, nem depois quando a conta não acrescenta dia
    v_ob := pg_temp.aberta(6);
    perform pg_temp.dia(v_ob, date '2027-03-13');                        -- só o sábado
    v2 := public.agenda_promessa_da_os(v_ob, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2q plano só no sábado (sabado_util falso), sem dia a mais: a data é o próprio sábado, e não a segunda',
      not (public._agenda_cfg()).sabado_util and (v2 ->> 'prazo_du')::int = 1 and (v2 ->> 'fim_com_folga')::date = date '2027-03-13', v2::text);
    v_ob := pg_temp.aberta(7);
    perform pg_temp.dia(v_ob, date '2027-03-12');
    perform pg_temp.dia(v_ob, date '2027-03-13');                        -- sex e sáb: o du_entre não conta o sábado
    v2 := public.agenda_promessa_da_os(v_ob, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2r plano de sex e sáb, sem dia a mais: a data não cai antes do sábado', (v2 ->> 'prazo_du')::int = 1 and (v2 ->> 'fim_com_folga')::date = date '2027-03-13', v2::text);
    perform pg_temp.linha('rv:energia', 2.00, 4);
    v2 := public.agenda_promessa_da_os(v_ob, c_hoje);
    v_res := pg_temp.ok(v_res, 'P2s o mesmo plano com 1 dia a mais (× 2): passa do sábado, seg 15/03', (v2 ->> 'fim_com_folga')::date = date '2027-03-15', v2::text);
    perform pg_temp.linha('rv:energia', 1.20, 4);
    -- sem modos (R7.3-1): modo_promessa nos 3 estados, com e sem freio, e modo_aprendizado desligado: o mesmo JSON
    v := public.agenda_promessa_da_os(v_os, c_hoje);
    for m, f in select * from (values ('desligado', true), ('sombra', true), ('ligado', true), ('desligado', false), ('sombra', false), ('ligado', false)) x(a, b) loop
      update public.agenda_config set modo_promessa = m, gestor_so_propor = f where id;
      if public.agenda_promessa_da_os(v_os, c_hoje) is distinct from v then v_dif := v_dif + 1; end if;
    end loop;
    update public.agenda_config set modo_aprendizado = 'desligado', modo_promessa = 'sombra', gestor_so_propor = true where id;
    if public.agenda_promessa_da_os(v_os, c_hoje) is distinct from v then v_dif := v_dif + 1; end if;
    update public.agenda_config set modo_aprendizado = 'ligado' where id;
    v_res := pg_temp.ok(v_res, 'P2t sem modos: modo_promessa nos 3 estados, com e sem freio, e modo_aprendizado desligado: o mesmo JSON', v_dif = 0, format('diferentes: %s', v_dif));
    -- o padrão de p_hoje
    perform set_config('agenda.hoje', c_hoje::text, true);
    v_res := pg_temp.ok(v_res, 'P2u p_hoje tem padrão', (public.agenda_promessa_da_os(v_os) ->> 'ok')::boolean, null);
    -- quem vê
    declare
      v_adm uuid := (select id from public.app_users where role = 'admin' and active order by created_at limit 1);
      v_tec uuid := (select id from public.app_users where role = 'technician' order by created_at limit 1);
      v_fin uuid := md5('e7e:p5:financeiro')::uuid;
      v_sql text := format($q$select public.agenda_promessa_da_os(%L, date '2027-03-01')::text$q$, v_os);
      x text;
    begin
      insert into public.app_users (id, full_name, email, role, active) values (v_fin, 'Fia', 'fia@teste.invalid', 'financial', true);
      x := pg_temp.como(v_adm, 'authenticated', v_sql);
      v_res := pg_temp.ok(v_res, 'P2v o administrador logado lê: plano, classe e aprendizado', x = v::text, x);
      x := pg_temp.como(v_fin, 'authenticated', v_sql);
      v_res := pg_temp.ok(v_res, 'P2w o financeiro logado lê', x = v::text, x);
      x := pg_temp.como(null, 'service_role', v_sql);
      v_res := pg_temp.ok(v_res, 'P2x o service_role lê', x = v::text, x);
      x := pg_temp.como(v_tec, 'authenticated', v_sql);
      v_res := pg_temp.ok(v_res, 'P2y o técnico leva 42501', x like 'erro 42501%', x);
      x := pg_temp.como(null, 'authenticated', v_sql);
      v_res := pg_temp.ok(v_res, 'P2z um JWT de outro papel sem login leva 42501', x like 'erro 42501%', x);
      x := pg_temp.como(null, 'anon', v_sql);
      v_res := pg_temp.ok(v_res, 'P2za anon leva 42501', x like 'erro 42501%', x);
      -- O JSON malformado na claim não passa: quem lança é auth.uid(), antes de tudo
      perform set_config('request.jwt.claims', 'nao-e-json', true);
      begin
        v2 := public.agenda_promessa_da_os(v_os, c_hoje);
        v_res := pg_temp.ok(v_res, 'P2zb claims malformado não lê', false, v2::text);
      exception when others then
        v_res := pg_temp.ok(v_res, 'P2zb claims malformado não lê', true, sqlstate);
      end;
      perform set_config('request.jwt.claims', '', true);
    end;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$p2$;

-- ── P5. A ficha da equipe nunca diz a data com folga (U1, com a guarda de R7.12-4) ─────────────────
create function pg_temp.diz_a_data(p_texto text, p_dia date) returns boolean language sql immutable as $f$
  select p_texto like '%' || to_char(p_dia, 'DD/MM') || '%'
$f$;

do $p5$
declare
  v_res jsonb := '[]'::jsonb;
  c_seg constant date := date '2027-03-08';
  c_sex constant date := date '2027-03-05';
  v_os uuid;
  v_pr jsonb;
  v_fim date;
  v_ficha text;
  v_msg text;
  v_tem boolean;
begin
  if not pg_temp.fx() then
    perform pg_temp.gravar(pg_temp.ok('[]', 'P5 a ficha', true, 'PULADO: sem a fixture'));
    return;
  end if;
  begin
    update public.agenda_config set modo_equipe = 'ligado', gestor_so_propor = false, modo_promessa = 'ligado' where id;
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por) values (pg_temp.zeca(), true, 'dono')
    on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;
    v_os := pg_temp.aberta(10);
    for k in 0 .. 2 loop perform pg_temp.dia(v_os, c_seg + k, 'execucao', null, pg_temp.zeca()); end loop;
    perform pg_temp.linha('todas', 2.00, 8);                             -- 3 → 6 dias: bem mais que o plano, e a data com folga é outra
    v_pr := public.agenda_promessa_da_os(v_os, date '2027-03-01');
    v_fim := (v_pr ->> 'fim_com_folga')::date;
    v_res := pg_temp.ok(v_res, 'P5a o caso tem data com folga diferente do fim do plano (seg 15/03 × qua 10/03)', v_fim = date '2027-03-15' and (v_pr ->> 'fim_plano')::date = c_seg + 2, v_pr::text);
    v_ficha := public.agenda_equipe_ficha(pg_temp.zeca(), c_seg, c_sex) ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'P5b a ficha existe e tem o serviço (a varredura não passa vazia)', v_ficha is not null and length(v_ficha) > 0 and v_ficha like '%08/03%', v_ficha);
    v_res := pg_temp.ok(v_res, 'P5c a ficha não diz a data com folga', not pg_temp.diz_a_data(v_ficha, v_fim), v_ficha);
    -- a rotina das 19:30 de verdade: o texto gravado para ir à fila
    perform public._agenda_rotina_ficha(c_sex, timestamptz '2027-03-05 19:30-03');
    select m.texto into v_msg from public.agenda_equipe_mensagens m where m.payee_id = pg_temp.zeca() and m.tipo = 'ficha' and m.dia = c_seg;
    v_res := pg_temp.ok(v_res, 'P5d a rotina gravou a ficha (a varredura não passa vazia)', v_msg is not null and length(v_msg) > 0, coalesce(v_msg, '(nada)'));
    v_res := pg_temp.ok(v_res, 'P5e a ficha da rotina não diz a data com folga', not pg_temp.diz_a_data(v_msg, v_fim), v_msg);
    -- o contraste: a mesma varredura reprova um texto plantado com a data
    v_tem := pg_temp.diz_a_data(v_ficha || ' Pronto até 15/03.', v_fim);
    v_res := pg_temp.ok(v_res, 'P5f a varredura reprova o texto plantado com a data', v_tem, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$p5$;

-- ── P6. Nada de cliente ────────────────────────────────────────────────────────────────────────────
insert into _resultado
-- As 2 funções são achadas pela própria varredura (o contraste, R7.12-4). Função recriada pelos pacotes seguintes leva a marca da 7e e sai sozinha (o P7 chama as 2 de agenda_aprender e do cartão); o P6c continua valendo para ela.
select 'P6a quem lê o prazo real é só o que a migration criou: nenhuma função de antes chama agenda_promessa_da_os, _agenda_aprender_promessa nem lê fator_promessa',
       coalesce(string_agg(p.proname, ',' order by p.proname), '') = '_agenda_aprender_promessa,agenda_promessa_da_os',
       string_agg(p.proname, ',' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.prosrc ~ '_agenda_aprender_promessa|agenda_promessa_da_os|fator_promessa'
   and not (p.prosrc ~ '-- FASE 7e:|-- \(7e');

insert into _resultado
select 'P6b as 2 funções não falam do que AG7-32 tirou: fim_promessa, teria_fim, pronto_ate nem modo_promessa',
       count(*) = 2 and bool_and(p.prosrc !~ 'fim_promessa|teria_fim|pronto_ate|modo_promessa'),
       string_agg(p.proname, ',') filter (where p.prosrc ~ 'fim_promessa|teria_fim|pronto_ate|modo_promessa')
  from pg_proc p
 where p.oid in ('public._agenda_aprender_promessa(date, timestamptz)'::regprocedure, 'public.agenda_promessa_da_os(uuid, date)'::regprocedure);

insert into _resultado
select 'P6c nenhuma função de cliente nem da equipe sabe do prazo real ou de fim_com_folga',
       count(*) > 0 and bool_and(p.prosrc !~ 'fim_com_folga|agenda_promessa_da_os|_agenda_aprender_promessa'),
       format('%s funções olhadas', count(*))
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and (p.proname like '_agenda_cliente%' or p.proname like 'agenda_cliente%' or p.proname like 'agenda_equipe%' or p.proname like '_agenda_equipe%' or p.proname like '_agenda_rotina%' or p.proname like 'agenda_comunicar%' or p.proname like '_agenda_comunicar%');

select teste, ok, detalhe from _resultado order by teste;

rollback;
