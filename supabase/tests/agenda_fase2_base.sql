-- Prova da base da Agenda de Produção, Fase 2 (pacote P1): o modelo de dados e as invariantes no banco
-- (migration 20261025100000).
-- bancada: depende de 20261025100000
--
--   A  estrutura e portas: as 5 tabelas com RLS; policies só de leitura e TO authenticated; anon sem privilégio;
--      authenticated só lê; service_role escreve; os 10 parâmetros novos e os modos nascendo 'sombra'; as 2 EXCLUDE
--      por gist; os gatilhos ligados; adiantavel_patio_dias
--   B  cada CHECK (e EXCLUDE, índice único, FK) das 5 tabelas e os CHECKs novos de agenda_config e os_planejamento
--      recusam uma linha errada; a cobrança de que nenhum ficou sem caso; as linhas certas entram
--   C  agenda_periodo: manhã 08–12, tarde 13–17, abertura 08–09 e fechamento 16–17 em Brasília (e a presença curta
--      pelo parâmetro); turno/presença fora da lista = 22023; _agenda_hoje pelo agenda.hoje
--   D  gatilhos da alocação: período só pelo dia/turno/presença; pessoa inativa; presença curta só do sócio;
--      publicada_em/cancelada_em uma vez; publicada não muda; transições; fixada só sai com a chave; resultado só de
--      dia que chegou, com histórico na correção; o que vigorou não se apaga; cancelar quem saiu da equipe
--   E  as 2 EXCLUDE: ninguém em dois lugares no vigente; proposta viável por dentro; abrir e fechar no mesmo turno
--   F  versão do plano: sobe 1 por linha que entra ou sai do vigente, sob a trava (advisory lock)
--   G  propostas, perguntas e ações não se apagam e só mudam no que podem; a referência que some vira nula e o
--      registro fica; apagar a OS com meio-dia vigente é recusado
--   H  ação crítica só com a decisão do dono (pergunta crítica respondida; executada só em ligado)
--   I  RLS de verdade: admin e financeiro veem tudo; o técnico só o próprio payee (payees é fechada para ele);
--      quem não tem cadastro nada; ninguém escreve; anon não lê
--   J  portas das funções: leitura para authenticated/service_role, nunca anon; gatilhos sem grant; só
--      _agenda_payees_do_login é security definer; search_path fixo
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261025100000
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase2_base.sql
--   Seguro em produção: as pessoas, os logins, as OS e as linhas de teste ("TESTE AG2", OS-TESTE-AG2-*) só são
--   inseridos, nada real é tocado (o "hoje" vem de agenda.hoje, local à transação); termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, da EXCLUDE, do índice único ou da FK; 'aceitou'
-- quando entrou (e desfaz, para não sujar os casos seguintes); 'erro <estado>: <mensagem>' para o resto.
create function pg_temp.recusa(p_sql text) returns text language plpgsql as $f$
declare
  v_nome text; v_estado text; v_msg text;
begin
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = '__aceitou__';
  exception when others then
    get stacked diagnostics v_nome = constraint_name, v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg = '__aceitou__' then return 'aceitou'; end if;
    if v_estado in ('23514', '23505', '23503', '23502', '23P01') then return coalesce(nullif(v_nome, ''), v_estado); end if;
    return 'erro ' || v_estado || ': ' || v_msg;
  end;
end $f$;

-- Executa de verdade e devolve o erro ('<sqlstate> <mensagem>'), ou 'sem erro'.
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

-- Executa p_sql (que devolve um valor) como o papel p_papel com o login p_uid (o JWT do Supabase): o resultado em
-- texto, ou 'erro <estado>: <mensagem>'. Volta ao dono do teste no fim, dê certo ou não.
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

-- O dia de quem age (o gatilho do resultado confere "esse dia já chegou?" por ele): quinta 29/10/2026.
select set_config('agenda.hoje', '2026-10-29', true);

-- ── Montagem: logins, pessoas, OS, propostas, perguntas e uma ação de teste ─────────────────────────────
do $m$
declare
  v_barco   uuid := (select id from public.vessels where client_id is not null order by created_at, id limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
begin
  if v_barco is null then raise exception 'FALHOU: nenhum barco cadastrado para montar a OS de teste'; end if;

  insert into public.app_users (id, full_name, email, role, active) values
    ('a2000000-0000-4000-8000-000000000001', 'TESTE AG2 admin', 'teste-ag2-admin@teste.invalid', 'admin', true),
    ('a2000000-0000-4000-8000-000000000002', 'TESTE AG2 técnico', 'teste-ag2-tecnico@teste.invalid', 'technician', true),
    ('a2000000-0000-4000-8000-000000000003', 'TESTE AG2 outro técnico', 'teste-ag2-outro@teste.invalid', 'technician', true),
    ('a2000000-0000-4000-8000-000000000004', 'TESTE AG2 sem cadastro', 'teste-ag2-sem@teste.invalid', 'technician', true),
    ('a2000000-0000-4000-8000-000000000005', 'TESTE AG2 financeiro', 'teste-ag2-fin@teste.invalid', 'financial', true),
    -- o 1º admin é apagado na seção G (prova do ON DELETE SET NULL); a seção I lê como este
    ('a2000000-0000-4000-8000-000000000006', 'TESTE AG2 admin 2', 'teste-ag2-admin2@teste.invalid', 'admin', true);

  insert into public.payees (id, name, kind, active, app_user_id) values
    ('b2000000-0000-4000-8000-000000000001', 'TESTE AG2 dono', 'socio', true, null),
    ('b2000000-0000-4000-8000-000000000002', 'TESTE AG2 Roberto', 'prestador', true, 'a2000000-0000-4000-8000-000000000002'),
    ('b2000000-0000-4000-8000-000000000003', 'TESTE AG2 João', 'prestador', true, 'a2000000-0000-4000-8000-000000000003'),
    ('b2000000-0000-4000-8000-000000000004', 'TESTE AG2 inativo', 'prestador', false, null),
    ('b2000000-0000-4000-8000-000000000005', 'TESTE AG2 Mickael', 'prestador', true, null);

  insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status) values
    ('c2000000-0000-4000-8000-000000000001', v_cliente, v_barco, 'OS-TESTE-AG2-1', 'approved', 'approved'),
    ('c2000000-0000-4000-8000-000000000002', v_cliente, v_barco, 'OS-TESTE-AG2-2', 'open', 'approved'),
    ('c2000000-0000-4000-8000-000000000003', v_cliente, v_barco, 'OS-TESTE-AG2-3', 'open', 'approved');

  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte)
  values ('c2000000-0000-4000-8000-000000000001', 2, 'dono');
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria)
  values ('97000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000003', 'dono', 'TESTE AG2 painel', 1);

  insert into public.agenda_propostas (id, escopo, periodo, versao_base, modo, parametros, criada_por, autor, expira_em) values
    ('d2000000-0000-4000-8000-000000000001', 'os', '[2026-11-03,2026-11-14)', 0, 'sombra', '{"p_hoje":"2026-10-29"}',
     'motor', 'a2000000-0000-4000-8000-000000000001', now() + interval '72 hours'),
    ('d2000000-0000-4000-8000-000000000002', 'os', '[2026-11-03,2026-11-14)', 0, 'sombra', '{"p_hoje":"2026-10-29"}',
     'motor', null, now() + interval '72 hours');

  insert into public.agenda_perguntas (id, tipo, chave, texto, modo, opcoes, recomendacao, service_order_id, os_material_id) values
    ('e2000000-0000-4000-8000-000000000001', 'chegou', 'chegou:teste-ag2', 'O painel chegou?', 'sombra', '[]', null,
     'c2000000-0000-4000-8000-000000000003', '97000000-0000-4000-8000-000000000001'),
    ('e2000000-0000-4000-8000-000000000002', 'nao_cabe', 'nao_cabe:teste-ag2', 'Não cabe tudo: qual atrasa?', 'sombra',
     '[{"n":1,"texto":"Nelson"},{"n":2,"texto":"Vanderlei"}]', 2, null, null);

  insert into public.agenda_acoes (id, dia, executada, origem, tipo, texto, service_order_id, os_ids, autor, desfazivel_ate) values
    ('f2000000-0000-4000-8000-000000000001', '2026-10-29', true, 'motor', 'mover', 'TESTE AG2: mudei o Nelson.',
     'c2000000-0000-4000-8000-000000000003', '{c2000000-0000-4000-8000-000000000003}', 'a2000000-0000-4000-8000-000000000001',
     now() + interval '24 hours');
end
$m$;

-- ── A. Estrutura e portas ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('A1 RLS ligada: %s', t),
       coalesce((select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.' || t)), false), null
  from unnest(array['agenda_propostas', 'agenda_perguntas', 'agenda_acoes', 'agenda_alocacoes', 'agenda_vigia_rodadas']) t;

insert into _resultado
select format('A2 policies de %s: só leitura e TO authenticated', t),
       count(p.policyname) >= 1 and coalesce(bool_and(p.roles = '{authenticated}'::name[] and p.cmd = 'SELECT'), false),
       string_agg(p.policyname || ' ' || p.cmd || ' ' || p.roles::text, '; ')
  from unnest(array['agenda_propostas', 'agenda_perguntas', 'agenda_acoes', 'agenda_alocacoes', 'agenda_vigia_rodadas']) t
  left join pg_policies p on p.schemaname = 'public' and p.tablename = t
 group by t;

insert into _resultado
select format('A3 anon sem privilégio: %s', t),
       not (has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('anon', 'public.' || t, 'insert')
            or has_table_privilege('anon', 'public.' || t, 'update') or has_table_privilege('anon', 'public.' || t, 'delete')
            or has_table_privilege('anon', 'public.' || t, 'truncate')), null
  from unnest(array['agenda_propostas', 'agenda_perguntas', 'agenda_acoes', 'agenda_alocacoes', 'agenda_vigia_rodadas']) t;

insert into _resultado
select format('A4 authenticated só lê, service_role escreve: %s', t),
       has_table_privilege('authenticated', 'public.' || t, 'select')
       and not (has_table_privilege('authenticated', 'public.' || t, 'insert')
                or has_table_privilege('authenticated', 'public.' || t, 'update')
                or has_table_privilege('authenticated', 'public.' || t, 'delete'))
       and has_table_privilege('service_role', 'public.' || t, 'insert')
       and has_table_privilege('service_role', 'public.' || t, 'update'), null
  from unnest(array['agenda_propostas', 'agenda_perguntas', 'agenda_acoes', 'agenda_alocacoes', 'agenda_vigia_rodadas']) t;

insert into _resultado
select format('A5 agenda_config nasce com %s = %s', x.coluna, x.esperado),
       pg_get_expr(d.adbin, d.adrelid) = x.esperado, pg_get_expr(d.adbin, d.adrelid)
  from (values ('hora_do_plano', '''16:30:00''::time without time zone'),
               ('presenca_curta', '''01:00:00''::interval'), ('desfazer_validade', '''24:00:00''::interval'),
               ('interrupcoes_max', '1'), ('inicios_tentados_du', '10'), ('atraso_longo_dias', '7'),
               ('remarcar_confirmado_du', '2'), ('sem_registro_du', '2'), ('backlog_minimo_semanas', '1.0'),
               ('perguntas_vezes_max', '2'),
               ('modo_proposta', '''sombra''::text'), ('modo_vigia', '''sombra''::text')) as x(coluna, esperado)
  left join pg_attribute a on a.attrelid = 'public.agenda_config'::regclass and a.attname = x.coluna
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

insert into _resultado
select 'A6 a linha de agenda_config ganhou os 10 parâmetros com o DEFAULT (a linha dos modos não muda aqui)',
       c.hora_do_plano = time '16:30' and c.presenca_curta = interval '1 hour' and c.desfazer_validade = interval '24 hours'
       and c.interrupcoes_max = 1 and c.inicios_tentados_du = 10 and c.atraso_longo_dias = 7
       and c.remarcar_confirmado_du = 2 and c.sem_registro_du = 2 and c.backlog_minimo_semanas = 1.0
       and c.perguntas_vezes_max = 2,
       format('modo_proposta %s, modo_vigia %s', c.modo_proposta, c.modo_vigia)
  from public.agenda_config c;

insert into _resultado
select 'A7 as duas EXCLUDE de agenda_alocacoes existem, por gist',
       count(*) = 2 and bool_and(pg_get_constraintdef(c.oid) like 'EXCLUDE USING gist%'),
       string_agg(c.conname || ': ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname)
  from pg_constraint c
 where c.conrelid = 'public.agenda_alocacoes'::regclass and c.contype = 'x'
   and c.conname in ('sem_choque_vigente', 'sem_choque_na_proposta');

insert into _resultado
select 'A8 os 11 gatilhos das invariantes existem e estão ligados',
       count(*) = 11 and bool_and(t.tgenabled = 'O'),
       string_agg(t.tgname, ', ' order by t.tgname)
  from pg_trigger t
 where not t.tgisinternal
   and t.tgrelid in ('public.agenda_alocacoes'::regclass, 'public.agenda_propostas'::regclass,
                     'public.agenda_perguntas'::regclass, 'public.agenda_acoes'::regclass)
   and t.tgname in ('agenda_alocacoes_antes', 'agenda_alocacoes_imutavel', 'agenda_alocacoes_nao_apaga',
                    'agenda_alocacoes_versao', 'agenda_propostas_nao_apaga', 'agenda_propostas_so_fecha',
                    'agenda_perguntas_nao_apaga', 'agenda_perguntas_antes', 'agenda_acoes_nao_apaga',
                    'agenda_acoes_so_desfaz', 'agenda_acoes_critica_decidida');

insert into _resultado
select 'A9 os_planejamento.adiantavel_patio_dias existe (numeric(3,1))',
       format_type(a.atttypid, a.atttypmod) = 'numeric(3,1)', format_type(a.atttypid, a.atttypmod)
  from pg_attribute a
 where a.attrelid = 'public.os_planejamento'::regclass and a.attname = 'adiantavel_patio_dias' and not a.attisdropped;

insert into _resultado
select 'A10 agenda_perguntas.critica é gerada pelo tipo (stored)',
       a.attgenerated = 's', a.attgenerated::text
  from pg_attribute a where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica';

-- ── B. Cada CHECK recusa uma linha errada ───────────────────────────────────────────────────────────────
do $b$
declare
  r record; v text; v_cmd text;
  v_testados text[] := '{}';
  v_sem_caso text;
  -- As linhas certas de cada tabela, com o que o caso troca entre chaves.
  c_prop text := $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em) values $q$;
  c_perg text := $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao, estado, respondida_em, opcao_escolhida, dia) values $q$;
  c_acao text := $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, critica, pergunta_id, desfaz_a, desfazivel_ate, desfeita_em, desfeita_pela, antes, depois, motivo, contada_via) values $q$;
  c_aloc text := $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, proposta_id, fixado_por, reserva_de, condicao, condicao_tipo, condicao_ate, resultado, motivo, resultado_via, resultado_trecho, cancelada_em, cancelada_motivo, motivos, historico) values $q$;
  c_rod  text := $q$insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms) values $q$;
begin
  for r in
    select * from (values
      -- agenda_config: os 10 parâmetros novos pelos limites
      ('agenda_config_hora_do_plano_check', 'plano às 18:00', $q$update public.agenda_config set hora_do_plano = '18:00'$q$),
      ('agenda_config_presenca_curta_check', 'presença curta de 3 h', $q$update public.agenda_config set presenca_curta = '3 hours'$q$),
      ('agenda_config_desfazer_validade_check', 'desfazer por 30 min', $q$update public.agenda_config set desfazer_validade = '30 minutes'$q$),
      ('agenda_config_interrupcoes_max_check', '3 interrupções', $q$update public.agenda_config set interrupcoes_max = 3$q$),
      ('agenda_config_inicios_tentados_du_check', '2 inícios', $q$update public.agenda_config set inicios_tentados_du = 2$q$),
      ('agenda_config_atraso_longo_dias_check', 'atraso longo de 2 dias', $q$update public.agenda_config set atraso_longo_dias = 2$q$),
      ('agenda_config_remarcar_confirmado_du_check', 'remarcar 6 du', $q$update public.agenda_config set remarcar_confirmado_du = 6$q$),
      ('agenda_config_sem_registro_du_check', 'sem registro 0', $q$update public.agenda_config set sem_registro_du = 0$q$),
      ('agenda_config_backlog_minimo_semanas_check', 'fila mínima 0,4', $q$update public.agenda_config set backlog_minimo_semanas = 0.4$q$),
      ('agenda_config_perguntas_vezes_max_check', 'pergunta 6 vezes', $q$update public.agenda_config set perguntas_vezes_max = 6$q$),
      ('agenda_config_modo_proposta_check', 'modo talvez', $q$update public.agenda_config set modo_proposta = 'talvez'$q$),
      ('aceitou', 'presença curta de 30 min e desfazer por 72 h', $q$update public.agenda_config set presenca_curta = '30 minutes', desfazer_validade = '72 hours'$q$),
      -- os_planejamento.adiantavel_patio_dias (a OS de teste tem 2 dias ditos)
      ('adiantavel_coerente', 'adiantável 0,3 (não é meio dia)', $q$update public.os_planejamento set adiantavel_patio_dias = 0.3 where service_order_id = {os}$q$),
      ('adiantavel_coerente', 'adiantável 0', $q$update public.os_planejamento set adiantavel_patio_dias = 0 where service_order_id = {os}$q$),
      ('adiantavel_coerente', 'adiantável 3 numa OS de 2 dias', $q$update public.os_planejamento set adiantavel_patio_dias = 3 where service_order_id = {os}$q$),
      ('aceitou', 'adiantável 1,5 numa OS de 2 dias', $q$update public.os_planejamento set adiantavel_patio_dias = 1.5 where service_order_id = {os}$q$),
      -- agenda_propostas
      ('agenda_propostas_escopo_check', 'escopo mês', '{ins_prop}' || $q$('mes', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day')$q$),
      ('agenda_propostas_periodo_check', 'período vazio', '{ins_prop}' || $q$('os', 'empty', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day')$q$),
      ('agenda_propostas_modo_check', 'modo desligado', '{ins_prop}' || $q$('os', '[2026-11-03,2026-11-07)', 0, 'desligado', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day')$q$),
      ('agenda_propostas_parametros_check', 'parâmetros sem p_hoje', '{ins_prop}' || $q$('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_agora":"x"}', 'motor', now() + interval '1 day')$q$),
      ('agenda_propostas_parametros_check', 'parâmetros em lista', '{ins_prop}' || $q$('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '["p_hoje"]', 'motor', now() + interval '1 day')$q$),
      ('agenda_propostas_criada_por_check', 'criada pelo chute', '{ins_prop}' || $q$('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'chute', now() + interval '1 day')$q$),
      ('expira_depois', 'expira antes de nascer', '{ins_prop}' || $q$('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() - interval '1 hour')$q$),
      ('agenda_propostas_estado_check', 'estado talvez', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, estado) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', 'talvez')$q$),
      ('agenda_propostas_itens_check', 'itens objeto', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, itens) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', '{}')$q$),
      ('agenda_propostas_fora_check', 'fora objeto', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, fora) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', '{}')$q$),
      ('agenda_propostas_carga_check', 'carga lista', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, carga) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', '[]')$q$),
      ('agenda_propostas_textos_check', 'textos lista', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, textos) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', '[]')$q$),
      ('agenda_propostas_decidida_via_check', 'decidida por sms', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, estado, decidida_em, decidida_via) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', 'aplicada', now(), 'sms')$q$),
      ('agenda_propostas_motivo_fim_check', 'motivo de 201', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, estado, motivo_fim) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', 'expirada', repeat('x', 201))$q$),
      ('decidida_coerente', 'aplicada sem decidida_em', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, estado) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', 'aplicada')$q$),
      ('decidida_coerente', 'aberta com decidida_em', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, decidida_em) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day', now())$q$),
      ('agenda_propostas_semana_aberta', 'duas semanas abertas no mesmo modo', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em) values ('semana', '[2026-11-02,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day'), ('semana', '[2026-11-02,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'vigia', now() + interval '1 day')$q$),
      ('agenda_propostas_autor_fkey', 'autor que não existe', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, autor) values ('os', '[2026-11-03,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'dono', now() + interval '1 day', gen_random_uuid())$q$),
      ('aceitou', 'uma semana aberta em sombra e outra em ligado', $q$insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em) values ('semana', '[2026-11-02,2026-11-07)', 0, 'sombra', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day'), ('semana', '[2026-11-02,2026-11-07)', 0, 'ligado', '{"p_hoje":"2026-10-29"}', 'motor', now() + interval '1 day')$q$),
      -- agenda_perguntas
      ('agenda_perguntas_tipo_check', 'tipo outro', '{ins_perg}' || $q$('outro', 'outro:t', 'Pergunta?', 'sombra', '[]', null, 'aberta', null, null, null)$q$),
      ('agenda_perguntas_chave_check', 'chave de 2', '{ins_perg}' || $q$('chegou', 'ab', 'Pergunta?', 'sombra', '[]', null, 'aberta', null, null, null)$q$),
      ('agenda_perguntas_texto_check', 'texto de 2', '{ins_perg}' || $q$('chegou', 'chegou:t', 'ok', 'sombra', '[]', null, 'aberta', null, null, null)$q$),
      ('agenda_perguntas_opcoes_check', 'opções objeto', '{ins_perg}' || $q$('chegou', 'chegou:t', 'Pergunta?', 'sombra', '{}', null, 'aberta', null, null, null)$q$),
      ('agenda_perguntas_modo_check', 'modo desligado', '{ins_perg}' || $q$('chegou', 'chegou:t', 'Pergunta?', 'desligado', '[]', null, 'aberta', null, null, null)$q$),
      ('agenda_perguntas_estado_check', 'estado talvez', '{ins_perg}' || $q$('chegou', 'chegou:t', 'Pergunta?', 'sombra', '[]', null, 'talvez', null, null, null)$q$),
      ('critica_tem_opcoes', 'crítica com 1 opção', '{ins_perg}' || $q$('nao_cabe', 'nao_cabe:t', 'Qual atrasa?', 'sombra', '[{"n":1}]', 1, 'aberta', null, null, null)$q$),
      ('critica_tem_opcoes', 'crítica sem recomendação', '{ins_perg}' || $q$('atraso_longo', 'atraso_longo:t', 'Sigo?', 'sombra', '[{"n":1},{"n":2}]', null, 'aberta', null, null, null)$q$),
      ('respondida_coerente', 'respondida sem respondida_em', '{ins_perg}' || $q$('chegou', 'chegou:t', 'Pergunta?', 'sombra', '[]', null, 'respondida', null, null, null)$q$),
      ('respondida_coerente', 'aberta com respondida_em', '{ins_perg}' || $q$('chegou', 'chegou:t', 'Pergunta?', 'sombra', '[]', null, 'aberta', now(), null, null)$q$),
      ('critica_decidida', 'crítica respondida sem a opção', '{ins_perg}' || $q$('nao_cabe', 'nao_cabe:t', 'Qual atrasa?', 'ligado', '[{"n":1},{"n":2}]', 2, 'respondida', now(), null, null)$q$),
      ('conferencia_tem_dia', 'conferência sem o dia', '{ins_perg}' || $q$('conferencia', 'conferencia:t', 'Foi isso?', 'sombra', '[]', null, 'aberta', null, null, null)$q$),
      ('agenda_perguntas_viva', 'duas abertas com a mesma chave no mesmo modo', '{ins_perg}' || $q$('chegou', 'chegou:t', 'Pergunta?', 'sombra', '[]', null, 'aberta', null, null, null), ('chegou', 'chegou:t', 'De novo?', 'sombra', '[]', null, 'aberta', null, null, null)$q$),
      ('agenda_perguntas_recomendacao_texto_check', 'recomendação de 301', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, recomendacao_texto) values ('chegou', 'chegou:t', 'Pergunta?', 'sombra', repeat('x', 301))$q$),
      ('agenda_perguntas_mostrada_vezes_check', 'mostrada 51 vezes', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, mostrada_vezes) values ('chegou', 'chegou:t', 'Pergunta?', 'sombra', 51)$q$),
      ('agenda_perguntas_mostrada_via_check', 'mostrada por sms', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, mostrada_via) values ('chegou', 'chegou:t', 'Pergunta?', 'sombra', 'sms')$q$),
      ('agenda_perguntas_respondida_via_check', 'respondida por sms', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, estado, respondida_em, respondida_via) values ('chegou', 'chegou:t', 'Pergunta?', 'sombra', 'respondida', now(), 'sms')$q$),
      ('agenda_perguntas_resposta_check', 'resposta de 501', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, estado, respondida_em, resposta) values ('chegou', 'chegou:t', 'Pergunta?', 'sombra', 'respondida', now(), repeat('x', 501))$q$),
      ('agenda_perguntas_resolvida_motivo_check', 'resolvida com motivo de 201', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, estado, resolvida_motivo) values ('chegou', 'chegou:t', 'Pergunta?', 'sombra', 'resolvida', repeat('x', 201))$q$),
      ('agenda_perguntas_service_order_id_fkey', 'OS que não existe', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, service_order_id) values ('chegou', 'chegou:t', 'Pergunta?', 'sombra', gen_random_uuid())$q$),
      ('agenda_perguntas_os_material_id_fkey', 'linha de material que não existe', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo, os_material_id) values ('chegou', 'chegou:t', 'Pergunta?', 'sombra', gen_random_uuid())$q$),
      ('aceitou', 'a mesma chave em sombra e em ligado; crítica com 2 opções e a recomendação', '{ins_perg}' || $q$('chegou', 'chegou:t', 'Pergunta?', 'sombra', '[]', null, 'aberta', null, null, null), ('chegou', 'chegou:t', 'Pergunta?', 'ligado', '[]', null, 'aberta', null, null, null), ('nao_cabe', 'nao_cabe:t2', 'Qual atrasa?', 'ligado', '[{"n":1},{"n":2}]', 2, 'respondida', now(), 1, null)$q$),
      ('aceitou', 'conferência com o dia', '{ins_perg}' || $q$('conferencia', 'conferencia:2026-11-03', 'Foi isso?', 'sombra', '[]', null, 'aberta', null, null, '2026-11-03')$q$),
      -- agenda_acoes
      ('agenda_acoes_origem_check', 'origem chute', '{ins_acao}' || $q$('2026-10-29', false, 'chute', 'mover', 'Mudei.', false, null, null, null, null, null, '{}', '{}', null, null)$q$),
      ('agenda_acoes_tipo_check', 'tipo outro', '{ins_acao}' || $q$('2026-10-29', false, 'motor', 'outro', 'Mudei.', false, null, null, null, null, null, '{}', '{}', null, null)$q$),
      ('agenda_acoes_texto_check', 'texto de 2', '{ins_acao}' || $q$('2026-10-29', false, 'motor', 'mover', 'ok', false, null, null, null, null, null, '{}', '{}', null, null)$q$),
      ('agenda_acoes_antes_check', 'antes em lista', '{ins_acao}' || $q$('2026-10-29', false, 'motor', 'mover', 'Mudei.', false, null, null, null, null, null, '[]', '{}', null, null)$q$),
      ('agenda_acoes_depois_check', 'depois em lista', '{ins_acao}' || $q$('2026-10-29', false, 'motor', 'mover', 'Mudei.', false, null, null, null, null, null, '{}', '[]', null, null)$q$),
      ('agenda_acoes_motivo_check', 'motivo de 201', '{ins_acao}' || $q$('2026-10-29', false, 'motor', 'mover', 'Mudei.', false, null, null, null, null, null, '{}', '{}', repeat('x', 201), null)$q$),
      ('agenda_acoes_contada_via_check', 'contada por sms', '{ins_acao}' || $q$('2026-10-29', false, 'motor', 'mover', 'Mudei.', false, null, null, null, null, null, '{}', '{}', null, 'sms')$q$),
      ('critica_tem_pergunta', 'crítica sem a pergunta', '{ins_acao}' || $q$('2026-10-29', false, 'motor', 'mover', 'Mudei.', true, null, null, null, null, null, '{}', '{}', null, null)$q$),
      ('desfazer_aponta', 'desfazer sem dizer o quê', '{ins_acao}' || $q$('2026-10-29', true, 'dono', 'desfazer', 'Desfeito.', false, null, null, null, null, null, '{}', '{}', null, null)$q$),
      ('desfazer_aponta', 'mover apontando uma ação a desfazer', '{ins_acao}' || $q$('2026-10-29', true, 'motor', 'mover', 'Mudei.', false, null, {acao_id}, null, null, null, '{}', '{}', null, null)$q$),
      ('desfeita_coerente', 'desfeita sem a ação que desfez', '{ins_acao}' || $q$('2026-10-29', true, 'motor', 'mover', 'Mudei.', false, null, null, now() + interval '1 day', now(), null, '{}', '{}', null, null)$q$),
      ('sombra_nao_desfaz', 'sombra com prazo de desfazer', '{ins_acao}' || $q$('2026-10-29', false, 'motor', 'mover', 'Mudei.', false, null, null, now() + interval '1 day', null, null, '{}', '{}', null, null)$q$),
      ('agenda_acoes_pergunta_id_fkey', 'pergunta que não existe', '{ins_acao}' || $q$('2026-10-29', true, 'motor', 'mover', 'Mudei.', false, gen_random_uuid(), null, null, null, null, '{}', '{}', null, null)$q$),
      ('agenda_acoes_service_order_id_fkey', 'OS que não existe', $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, service_order_id) values ('2026-10-29', false, 'motor', 'mover', 'Mudei.', gen_random_uuid())$q$),
      ('aceitou', 'executada e desfazível; o desfazer apontando a ação', '{ins_acao}' || $q$('2026-10-29', true, 'motor', 'mover', 'Mudei.', false, null, null, now() + interval '1 day', null, null, '{}', '{}', null, null), ('2026-10-29', true, 'dono', 'desfazer', 'Desfeito.', false, null, {acao_id}, null, null, null, '{}', '{}', null, 'fechamento')$q$),
      -- agenda_alocacoes (dia futuro: qui 12/11; o passado: ter 27/10)
      ('agenda_alocacoes_turno_check', 'turno noite', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'noite', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_presenca_check', 'presença no meio', '{ins_aloc}' || $q$({os}, {dono}, '2026-11-12', 'manha', 'meio', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_tipo_check', 'tipo outro', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'outro', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_estado_check', 'estado talvez', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'talvez', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_origem_check', 'origem chute', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'chute', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_fixado_por_check', 'fixada pelo chute', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'fixada', 'dono', null, 'chute', null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_reserva_de_check', 'reserva de chute', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'reserva', 'proposta', 'motor', {prop}, null, 'chute', null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_condicao_check', 'condição de 161', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'reserva', 'proposta', 'motor', {prop}, null, 'condicionada', repeat('x', 161), 'compra', '2026-11-10', null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_condicao_tipo_check', 'condição de chute', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'reserva', 'proposta', 'motor', {prop}, null, 'condicionada', 'se chegar', 'chute', '2026-11-10', null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_resultado_check', 'resultado talvez', '{ins_aloc}' || $q$({os}, {rob}, '2026-10-27', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, 'talvez', null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_motivo_check', 'motivo chute', '{ins_aloc}' || $q$({os}, {rob}, '2026-10-27', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, 'parcial', 'chute', null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_resultado_via_check', 'resultado por sms', '{ins_aloc}' || $q$({os}, {rob}, '2026-10-27', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, 'cumprido', null, 'sms', null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_resultado_trecho_check', 'trecho de 301', '{ins_aloc}' || $q$({os}, {rob}, '2026-10-27', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, 'cumprido', null, 'conversa', repeat('x', 301), null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_cancelada_motivo_check', 'cancelada por chute', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'cancelada', 'motor', null, null, null, null, null, null, null, null, null, null, null, 'chute', '[]', '[]')$q$),
      ('agenda_alocacoes_motivos_check', 'motivos objeto', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '{}', '[]')$q$),
      ('agenda_alocacoes_historico_check', 'histórico objeto', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '{}')$q$),
      ('agenda_alocacoes_historico_check', 'histórico com 21', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', (select jsonb_agg(g) from generate_series(1, 21) g))$q$),
      ('proposta_tem_origem', 'proposta sem a proposta', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', null, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('fixado_tem_motivo', 'fixada sem dizer por quê', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'fixada', 'dono', null, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('fixado_tem_motivo', 'publicada com fixado_por', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'publicada', 'dono', null, 'dono', null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('resultado_so_vigente', 'proposta com resultado', '{ins_aloc}' || $q$({os}, {rob}, '2026-10-27', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, 'cumprido', null, null, null, null, null, '[]', '[]')$q$),
      ('falha_tem_motivo', 'parcial sem o motivo', '{ins_aloc}' || $q$({os}, {rob}, '2026-10-27', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, 'parcial', null, null, null, null, null, '[]', '[]')$q$),
      ('condicao_completa', 'condição sem tipo nem data', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'reserva', 'proposta', 'motor', {prop}, null, 'condicionada', 'se chegar', null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('condicao_so_reserva', 'condição numa execução', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, 'se chegar', 'compra', '2026-11-10', null, null, null, null, null, null, '[]', '[]')$q$),
      ('reserva_tem_razao', 'reserva sem razão', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'reserva', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('reserva_tem_razao', 'execução com razão de reserva', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, 'teto', null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('curta_nao_e_reserva', 'abertura do dono como reserva', '{ins_aloc}' || $q$({os}, {dono}, '2026-11-12', 'manha', 'abertura', 'reserva', 'proposta', 'motor', {prop}, null, 'teto', null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('cancelada_coerente', 'publicada com data de cancelamento', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, null, null, null, null, now(), null, '[]', '[]')$q$),
      ('agenda_alocacoes_payee_id_fkey', 'pessoa que não existe', '{ins_aloc}' || $q$({os}, gen_random_uuid(), '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('agenda_alocacoes_service_order_id_fkey', 'OS que não existe', '{ins_aloc}' || $q$(gen_random_uuid(), {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('sem_choque_vigente', 'o Roberto publicado duas vezes na mesma manhã', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]'), ({os2}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('sem_choque_na_proposta', 'a mesma proposta com o Roberto duas vezes na manhã', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]'), ({os2}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('aceitou', 'proposta; publicada; fixada pelo dono; reserva condicionada; o dono abre', '{ins_aloc}' || $q$({os}, {rob}, '2026-11-12', 'manha', 'turno', 'execucao', 'proposta', 'motor', {prop}, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]'), ({os}, {joao}, '2026-11-12', 'tarde', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]'), ({os2}, {joao}, '2026-11-13', 'tarde', 'turno', 'execucao', 'fixada', 'dono', null, 'dono', null, null, null, null, null, null, null, null, null, null, '[]', '[]'), ({os2}, {rob}, '2026-11-13', 'manha', 'turno', 'reserva', 'proposta', 'motor', {prop}, null, 'condicionada', 'se o painel chegar', 'material', '2026-11-11', null, null, null, null, null, null, '[]', '[]'), ({os}, {dono}, '2026-11-12', 'manha', 'abertura', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, null, null, null, null, null, null, '[]', '[]')$q$),
      ('aceitou', 'passado com resultado e o motivo da falha', '{ins_aloc}' || $q$({os}, {rob}, '2026-10-27', 'manha', 'turno', 'execucao', 'publicada', 'motor', null, null, null, null, null, null, 'nao_cumprido', 'clima', 'dia_feito', 'choveu', null, null, '[]', '[]')$q$),
      -- vigente_tem_data: o gatilho sempre preenche publicada_em; com ele desligado, o CHECK é a última porta
      ('vigente_tem_data', 'publicada sem publicada_em (gatilho desligado)', $q$alter table public.agenda_alocacoes disable trigger agenda_alocacoes_antes; insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, periodo, estado) values ({os}, {rob}, '2026-11-12', 'manha', public.agenda_periodo('2026-11-12', 'manha'), 'publicada')$q$),
      -- agenda_vigia_rodadas
      ('agenda_vigia_rodadas_modo_proposta_check', 'modo talvez', '{ins_rod}' || $q$('2026-10-29', now(), 'talvez', 'sombra', '{}', 0, 10)$q$),
      ('agenda_vigia_rodadas_modo_vigia_check', 'modo talvez', '{ins_rod}' || $q$('2026-10-29', now(), 'sombra', 'talvez', '{}', 0, 10)$q$),
      ('agenda_vigia_rodadas_contagens_check', 'contagens em lista', '{ins_rod}' || $q$('2026-10-29', now(), 'sombra', 'sombra', '[]', 0, 10)$q$),
      ('agenda_vigia_rodadas_erros_check', 'erros −1', '{ins_rod}' || $q$('2026-10-29', now(), 'sombra', 'sombra', '{}', -1, 10)$q$),
      ('agenda_vigia_rodadas_duracao_ms_check', 'duração −1', '{ins_rod}' || $q$('2026-10-29', now(), 'sombra', 'sombra', '{}', 0, -1)$q$),
      ('aceitou', 'uma rodada', '{ins_rod}' || $q$('2026-10-29', now(), 'ligado', 'sombra', '{"publicadas":0}', 0, 120)$q$)
    ) as c(esperado, caso, comando)
  loop
    v_cmd := r.comando;
    v_cmd := replace(replace(replace(replace(replace(v_cmd,
               '{ins_prop}', c_prop), '{ins_perg}', c_perg), '{ins_acao}', c_acao), '{ins_aloc}', c_aloc), '{ins_rod}', c_rod);
    v_cmd := replace(replace(replace(replace(replace(replace(replace(v_cmd,
               '{os2}', quote_literal('c2000000-0000-4000-8000-000000000002')),
               '{os}', quote_literal('c2000000-0000-4000-8000-000000000001')),
               '{rob}', quote_literal('b2000000-0000-4000-8000-000000000002')),
               '{joao}', quote_literal('b2000000-0000-4000-8000-000000000003')),
               '{dono}', quote_literal('b2000000-0000-4000-8000-000000000001')),
               '{prop}', quote_literal('d2000000-0000-4000-8000-000000000001')),
               '{acao_id}', quote_literal('f2000000-0000-4000-8000-000000000001'));
    v := pg_temp.recusa(v_cmd);
    v_testados := v_testados || r.esperado;
    insert into _resultado values (
      format('B %s: %s', case when r.esperado = 'aceitou' then 'entra' else 'recusa' end, r.caso),
      v = r.esperado,
      case when v = r.esperado then r.esperado else format('esperava %s, veio %s', r.esperado, v) end);
  end loop;

  -- Nenhum CHECK nem EXCLUDE das 5 tabelas, e nenhum dos que a Fase 2 pôs em agenda_config e os_planejamento,
  -- ficou sem caso (um CHECK novo sem teste reprova aqui).
  select string_agg(c.conname, ', ' order by c.conname) into v_sem_caso
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
   where n.nspname = 'public' and c.contype in ('c', 'x')
     and (t.relname in ('agenda_propostas', 'agenda_perguntas', 'agenda_acoes', 'agenda_alocacoes', 'agenda_vigia_rodadas')
          or c.conname in ('agenda_config_hora_do_plano_check', 'agenda_config_presenca_curta_check',
                           'agenda_config_desfazer_validade_check', 'agenda_config_interrupcoes_max_check',
                           'agenda_config_inicios_tentados_du_check', 'agenda_config_atraso_longo_dias_check',
                           'agenda_config_remarcar_confirmado_du_check', 'agenda_config_sem_registro_du_check',
                           'agenda_config_backlog_minimo_semanas_check', 'agenda_config_perguntas_vezes_max_check',
                           'adiantavel_coerente'))
     and not (c.conname = any (v_testados))
     -- FASE 3: os 3 que a Fase 3 pôs em agenda_vigia_rodadas (20261026100000: a rotina e os modos da equipe e da diária)
     -- têm o caso deles em agenda_fase3_base.sql, que cobra a lista; sem esta linha, este teste reprovaria por um CHECK
     -- que não é da Fase 2. As listas fechadas que a Fase 3 ampliou (tipo e origem da ação, tipo da pergunta, resultado_via
     -- da alocação) continuam com o mesmo nome e o caso daqui continua valendo.
     and not (c.conname = any (array['agenda_vigia_rodadas_rotina_check', 'agenda_vigia_rodadas_modo_equipe_check',
                                     'agenda_vigia_rodadas_modo_diaria_check']));
  insert into _resultado values ('B todo CHECK e EXCLUDE da Fase 2 tem um caso que ele recusa', v_sem_caso is null, v_sem_caso);
end
$b$;

-- ── C. agenda_periodo e _agenda_hoje ────────────────────────────────────────────────────────────────────
insert into _resultado
select format('C1 %s', x.caso), x.ok, x.detalhe
  from (values
    ('manhã = [08:00, 12:00) em Brasília',
     public.agenda_periodo('2026-11-03', 'manha') = tstzrange('2026-11-03 08:00-03', '2026-11-03 12:00-03', '[)'),
     public.agenda_periodo('2026-11-03', 'manha')::text),
    ('tarde = [13:00, 17:00)',
     public.agenda_periodo('2026-11-03', 'tarde') = tstzrange('2026-11-03 13:00-03', '2026-11-03 17:00-03', '[)'),
     public.agenda_periodo('2026-11-03', 'tarde')::text),
    ('abertura da manhã = [08:00, 09:00)',
     public.agenda_periodo('2026-11-03', 'manha', 'abertura') = tstzrange('2026-11-03 08:00-03', '2026-11-03 09:00-03', '[)'),
     public.agenda_periodo('2026-11-03', 'manha', 'abertura')::text),
    ('fechamento da tarde = [16:00, 17:00)',
     public.agenda_periodo('2026-11-03', 'tarde', 'fechamento') = tstzrange('2026-11-03 16:00-03', '2026-11-03 17:00-03', '[)'),
     public.agenda_periodo('2026-11-03', 'tarde', 'fechamento')::text),
    ('abertura da tarde = [13:00, 14:00) e fechamento da manhã = [11:00, 12:00)',
     public.agenda_periodo('2026-11-03', 'tarde', 'abertura') = tstzrange('2026-11-03 13:00-03', '2026-11-03 14:00-03', '[)')
     and public.agenda_periodo('2026-11-03', 'manha', 'fechamento') = tstzrange('2026-11-03 11:00-03', '2026-11-03 12:00-03', '[)'),
     null),
    ('sem a presença é o turno inteiro',
     public.agenda_periodo('2026-11-03', 'tarde') = public.agenda_periodo('2026-11-03', 'tarde', 'turno'), null),
    ('abrir e fechar no mesmo turno não se tocam; o turno cobre os dois',
     not (public.agenda_periodo('2026-11-03', 'manha', 'abertura') && public.agenda_periodo('2026-11-03', 'manha', 'fechamento'))
     and public.agenda_periodo('2026-11-03', 'manha') @> public.agenda_periodo('2026-11-03', 'manha', 'abertura')
     and public.agenda_periodo('2026-11-03', 'manha') @> public.agenda_periodo('2026-11-03', 'manha', 'fechamento'), null),
    ('_agenda_hoje = agenda.hoje (qui 29/10)', public._agenda_hoje() = date '2026-10-29', public._agenda_hoje()::text)
  ) as x(caso, ok, detalhe);

insert into _resultado values
  ('C2 turno fora da lista = 22023, com a frase',
   pg_temp.erro_de($q$select public.agenda_periodo('2026-11-03', 'noite')$q$) = '22023 Turno desconhecido: "noite" (manha ou tarde).',
   pg_temp.erro_de($q$select public.agenda_periodo('2026-11-03', 'noite')$q$)),
  ('C2 presença fora da lista = 22023',
   pg_temp.erro_de($q$select public.agenda_periodo('2026-11-03', 'manha', 'meio')$q$)
     = '22023 Presença desconhecida: "meio" (turno, abertura ou fechamento).',
   pg_temp.erro_de($q$select public.agenda_periodo('2026-11-03', 'manha', 'meio')$q$)),
  ('C2 sem o dia = 22023',
   pg_temp.erro_de($q$select public.agenda_periodo(null, 'manha')$q$) = '22023 Falta o dia do meio-dia.',
   pg_temp.erro_de($q$select public.agenda_periodo(null, 'manha')$q$));

do $c3$
declare
  v_ab tstzrange; v_fe tstzrange; v_sem date;
begin
  -- A presença curta vem do parâmetro (30 min); volta a 1 h no fim.
  update public.agenda_config set presenca_curta = '30 minutes';
  v_ab := public.agenda_periodo('2026-11-03', 'manha', 'abertura');
  v_fe := public.agenda_periodo('2026-11-03', 'tarde', 'fechamento');
  update public.agenda_config set presenca_curta = '1 hour';
  insert into _resultado values ('C3 com presenca_curta 30 min: abertura 08:00–08:30 e fechamento 16:30–17:00',
    v_ab = tstzrange('2026-11-03 08:00-03', '2026-11-03 08:30-03', '[)')
    and v_fe = tstzrange('2026-11-03 16:30-03', '2026-11-03 17:00-03', '[)'), v_ab::text || ' ' || v_fe::text);
  -- Sem agenda.hoje, o dia de Brasília.
  perform set_config('agenda.hoje', '', true);
  v_sem := public._agenda_hoje();
  perform set_config('agenda.hoje', '2026-10-29', true);
  insert into _resultado values ('C4 sem agenda.hoje, _agenda_hoje é o dia de Brasília', v_sem = public._hoje_brt(), v_sem::text);
end
$c3$;

-- ── D. Gatilhos da alocação ─────────────────────────────────────────────────────────────────────────────
do $d$
declare
  v_os   uuid := 'c2000000-0000-4000-8000-000000000001';
  v_os2  uuid := 'c2000000-0000-4000-8000-000000000002';
  v_rob  uuid := 'b2000000-0000-4000-8000-000000000002';
  v_dono uuid := 'b2000000-0000-4000-8000-000000000001';
  v_inat uuid := 'b2000000-0000-4000-8000-000000000004';
  v_mick uuid := 'b2000000-0000-4000-8000-000000000005';
  v_prop uuid := 'd2000000-0000-4000-8000-000000000001';
  v_trava boolean;
  a uuid; b uuid; p uuid; m uuid; f uuid;
  x record; v text; v_pub timestamptz;
begin
  -- F0: antes de qualquer meio-dia vigente nesta transação, a trava do plano não está tomada.
  select exists (select 1 from pg_locks l
                  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.objsubid = 1
                    and l.classid::bigint = ((hashtext('agenda_plano')::bigint >> 32) & 4294967295)
                    and l.objid::bigint = (hashtext('agenda_plano')::bigint & 4294967295)) into v_trava;
  insert into _resultado values ('F0 antes de mexer no vigente, a trava do plano não está tomada', not v_trava, null);

  -- D1: o período vem do dia e do turno, mesmo com um período escrito à mão.
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id, periodo)
  values (v_os, v_rob, '2026-11-03', 'tarde', 'proposta', v_prop, tstzrange('2026-01-01', '2026-01-02'))
  returning id into a;
  select * into x from public.agenda_alocacoes where id = a;
  insert into _resultado values
    ('D1 o período vem do dia e do turno (o escrito à mão é ignorado)',
     x.periodo = public.agenda_periodo('2026-11-03', 'tarde'), x.periodo::text),
    ('D1 a proposta nasce sem publicada_em nem cancelada_em', x.publicada_em is null and x.cancelada_em is null, null);

  -- D2: pessoa inativa não entra.
  v := pg_temp.erro_de(format($q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id)
                               values (%L, %L, '2026-11-03', 'manha', 'proposta', %L)$q$, v_os, v_inat, v_prop));
  insert into _resultado values ('D2 pessoa inativa não entra', v = 'P0001 Essa pessoa não está ativa: não entra na agenda.', v);

  -- D3: abrir e fechar é só do sócio.
  v := pg_temp.erro_de(format($q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, estado)
                               values (%L, %L, '2026-11-04', 'manha', 'abertura', 'publicada')$q$, v_os, v_rob));
  insert into _resultado values ('D3 abrir e fechar (presença curta) é só do sócio',
    v = 'P0001 Abrir e fechar (presença curta) é só do sócio; a equipe ocupa o turno inteiro.', v);
  v := pg_temp.erro_de(format($q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, estado)
                               values (%L, %L, '2026-11-04', 'manha', 'abertura', 'publicada')$q$, v_os, v_dono));
  insert into _resultado values ('D3 o dono abre a manhã', v = 'sem erro', v);

  -- D4: entra em vigor com a data; publicada não muda (só o "por quê"); período e publicada_em ficam.
  update public.agenda_alocacoes set estado = 'publicada' where id = a;
  select * into x from public.agenda_alocacoes where id = a;
  v_pub := x.publicada_em;
  insert into _resultado values ('D4 ao entrar em vigor ganha publicada_em', x.publicada_em is not null, null);
  insert into _resultado
  select format('D4 publicada não muda: %s', c.campo),
         pg_temp.erro_de(format('update public.agenda_alocacoes set %s where id = %L', c.mudanca, a))
           = 'P0001 Alocação publicada não muda: cancele e crie outra (fica o rastro).',
         pg_temp.erro_de(format('update public.agenda_alocacoes set %s where id = %L', c.mudanca, a))
    from (values ('dia', $q$dia = '2026-11-04'$q$), ('pessoa', format('payee_id = %L', v_mick)),
                 ('turno', $q$turno = 'manha'$q$), ('OS', format('service_order_id = %L', v_os2)),
                 ('tipo', $q$tipo = 'diagnostico'$q$), ('origem', $q$origem = 'dono'$q$)) as c(campo, mudanca);
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set motivos = '["o material chegou"]' where id = %L$q$, a));
  insert into _resultado values ('D4 publicada aceita mudar o "por quê" (motivos)', v = 'sem erro', v);
  update public.agenda_alocacoes set periodo = tstzrange('2026-01-01', '2026-01-02'), publicada_em = null where id = a;
  select * into x from public.agenda_alocacoes where id = a;
  insert into _resultado values ('D4 período e publicada_em não se reescrevem à mão',
    x.periodo = public.agenda_periodo('2026-11-03', 'tarde') and x.publicada_em = v_pub, x.periodo::text);

  -- D5: as transições.
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set estado = 'proposta', proposta_id = %L where id = %L$q$, v_prop, a));
  insert into _resultado values ('D5 publicada não volta a proposta', v = 'P0001 Essa troca de estado não existe: publicada → proposta.', v);
  update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where id = a;
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set estado = 'publicada', fixado_por = null where id = %L$q$, a));
  insert into _resultado values ('D5 fixada não volta a publicada', v = 'P0001 Essa troca de estado não existe: fixada → publicada.', v);
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono' where id = %L$q$, a));
  insert into _resultado values ('D5 fixada não sai sem a chave de mexer no fixado',
    v = 'P0001 Esse meio-dia está fixado: só sai com a decisão de mexer no fixado.', v);
  perform set_config('agenda.mexe_fixado', 'on', true);
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono' where id = %L$q$, a));
  perform set_config('agenda.mexe_fixado', 'off', true);
  select * into x from public.agenda_alocacoes where id = a;
  insert into _resultado values ('D5 com a chave, a fixada é cancelada, com a data e guardando por quem foi fixada',
    v = 'sem erro' and x.estado = 'cancelada' and x.cancelada_em is not null and x.fixado_por = 'dono', v);
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set estado = 'publicada' where id = %L$q$, a));
  insert into _resultado values ('D5 cancelada não volta', v = 'P0001 Alocação cancelada não volta nem muda: crie outra.', v);
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set dia = '2026-11-05' where id = %L$q$, a));
  insert into _resultado values ('D5 cancelada não muda', v = 'P0001 Alocação cancelada não volta nem muda: crie outra.', v);

  -- D6: o resultado é do dia que chegou; a correção vai para o histórico; com resultado não se cancela.
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_os, v_rob, '2026-11-04', 'tarde', 'publicada') returning id into b;
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set resultado = 'cumprido', resultado_via = 'dia_feito' where id = %L$q$, b));
  insert into _resultado values ('D6 dia que ainda não chegou não tem resultado (qua 04/11 com hoje qui 29/10)',
    v = 'P0001 Esse dia ainda não chegou: não dá para dizer como foi.', v);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_os, v_rob, '2026-10-27', 'manha', 'publicada') returning id into p;
  update public.agenda_alocacoes set resultado = 'cumprido', resultado_via = 'dia_feito' where id = p;
  select * into x from public.agenda_alocacoes where id = p;
  insert into _resultado values ('D6 dia passado ganha o resultado, com a hora', x.resultado = 'cumprido' and x.resultado_em is not null, null);
  update public.agenda_alocacoes set resultado = 'parcial', motivo = 'clima', resultado_via = 'conversa' where id = p;
  select * into x from public.agenda_alocacoes where id = p;
  insert into _resultado values ('D6 corrigir o resultado fica no histórico (de cumprido para parcial, pela conversa)',
    jsonb_array_length(x.historico) = 1 and x.historico -> 0 ->> 'de' = 'cumprido' and x.historico -> 0 ->> 'para' = 'parcial'
    and x.historico -> 0 ->> 'via' = 'conversa', x.historico::text);
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado' where id = %L$q$, p));
  insert into _resultado values ('D6 com resultado não se cancela', v = 'P0001 Esse meio-dia já aconteceu: corrija o resultado, não cancele.', v);

  -- D7: o que vigorou não se apaga; a proposta que nunca vigorou, sim.
  v := pg_temp.erro_de(format('delete from public.agenda_alocacoes where id = %L', b));
  insert into _resultado values ('D7 vigente não se apaga', v = 'P0001 Esse meio-dia já esteve no plano: não se apaga (cancele, e fica o rastro).', v);
  v := pg_temp.erro_de(format('delete from public.agenda_alocacoes where id = %L', a));
  insert into _resultado values ('D7 cancelada que vigorou não se apaga', v = 'P0001 Esse meio-dia já esteve no plano: não se apaga (cancele, e fica o rastro).', v);
  v := pg_temp.erro_de(format('delete from public.agenda_alocacoes where id = %L', p));
  insert into _resultado values ('D7 com resultado não se apaga', v = 'P0001 Esse meio-dia já esteve no plano: não se apaga (cancele, e fica o rastro).', v);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id)
  values (v_os2, v_rob, '2026-11-04', 'manha', 'proposta', v_prop) returning id into m;
  v := pg_temp.erro_de(format('delete from public.agenda_alocacoes where id = %L', m));
  insert into _resultado values ('D7 proposta que nunca vigorou se apaga', v = 'sem erro', v);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id)
  values (v_os2, v_rob, '2026-11-04', 'manha', 'proposta', v_prop) returning id into m;
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado' where id = m;
  v := pg_temp.erro_de(format('delete from public.agenda_alocacoes where id = %L', m));
  insert into _resultado values ('D7 cancelada que nunca vigorou se apaga', v = 'sem erro', v);

  -- D8: quem saiu da equipe — o meio-dia dele ainda pode ser cancelado; um novo não entra.
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_os2, v_mick, '2026-11-04', 'tarde', 'publicada') returning id into f;
  update public.payees set active = false where id = v_mick;
  v := pg_temp.erro_de(format($q$update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'pessoa' where id = %L$q$, f));
  insert into _resultado values ('D8 o meio-dia de quem saiu da equipe ainda é cancelado', v = 'sem erro', v);
  v := pg_temp.erro_de(format($q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
                               values (%L, %L, '2026-11-06', 'tarde', 'publicada')$q$, v_os2, v_mick));
  insert into _resultado values ('D8 quem saiu não entra de novo', v = 'P0001 Essa pessoa não está ativa: não entra na agenda.', v);
  update public.payees set active = true where id = v_mick;

  -- F1: a trava foi tomada (o vigente mudou nesta transação).
  select exists (select 1 from pg_locks l
                  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.objsubid = 1
                    and l.classid::bigint = ((hashtext('agenda_plano')::bigint >> 32) & 4294967295)
                    and l.objid::bigint = (hashtext('agenda_plano')::bigint & 4294967295)) into v_trava;
  insert into _resultado values ('F1 mexer no vigente toma a trava do plano (pg_advisory_xact_lock de hashtext(''agenda_plano''))', v_trava, null);
end
$d$;

-- ── E. As duas EXCLUDE ──────────────────────────────────────────────────────────────────────────────────
do $e$
declare
  v_os    uuid := 'c2000000-0000-4000-8000-000000000001';
  v_os2   uuid := 'c2000000-0000-4000-8000-000000000002';
  v_rob   uuid := 'b2000000-0000-4000-8000-000000000002';
  v_joao  uuid := 'b2000000-0000-4000-8000-000000000003';
  v_dono  uuid := 'b2000000-0000-4000-8000-000000000001';
  v_prop  uuid := 'd2000000-0000-4000-8000-000000000001';
  v_prop2 uuid := 'd2000000-0000-4000-8000-000000000002';
  a uuid; q uuid;
  ins constant text := $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, estado, proposta_id) values (%L, %L, %L, %L, %L, %L, %L)$q$;
  fix constant text := $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, fixado_por, origem) values (%L, %L, %L, 'manha', 'fixada', 'dono', 'dono')$q$;
begin
  -- Sex 05/11: o Roberto publicado na OS 1 de manhã; o dono abrindo a OS 1.
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_os, v_rob, '2026-11-05', 'manha', 'publicada') returning id into a;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, estado)
  values (v_os, v_dono, '2026-11-05', 'manha', 'abertura', 'publicada');

  insert into _resultado
  select format('E %s', c.caso), pg_temp.recusa(c.cmd) = c.esperado,
         format('esperava %s, veio %s', c.esperado, pg_temp.recusa(c.cmd))
    from (values
      ('ninguém em dois lugares: o Roberto de novo na mesma manhã (outra OS)', 'sem_choque_vigente',
       format(ins, v_os2, v_rob, '2026-11-05', 'manha', 'turno', 'publicada', null)),
      ('fixada também é vigente: choca com a publicada da mesma pessoa', 'sem_choque_vigente',
       format(fix, v_os2, v_rob, '2026-11-05')),
      ('a proposta não choca com o vigente (ela é que vai ser validada)', 'aceitou',
       format(ins, v_os2, v_rob, '2026-11-05', 'manha', 'turno', 'proposta', v_prop)),
      ('manhã e tarde do mesmo dia não se tocam', 'aceitou',
       format(ins, v_os2, v_rob, '2026-11-05', 'tarde', 'turno', 'publicada', null)),
      ('outra pessoa na mesma manhã', 'aceitou',
       format(ins, v_os2, v_joao, '2026-11-05', 'manha', 'turno', 'publicada', null)),
      ('o dono fecha outra OS no mesmo turno em que abriu a 1ª', 'aceitou',
       format(ins, v_os2, v_dono, '2026-11-05', 'manha', 'fechamento', 'publicada', null)),
      ('o dono o turno inteiro onde já está abrindo', 'sem_choque_vigente',
       format(ins, v_os2, v_dono, '2026-11-05', 'manha', 'turno', 'publicada', null)),
      ('o dono abrindo duas OS ao mesmo tempo', 'sem_choque_vigente',
       format(ins, v_os2, v_dono, '2026-11-05', 'manha', 'abertura', 'publicada', null))
    ) as c(caso, esperado, cmd);

  -- Dentro de uma proposta: viável por dentro; propostas diferentes não se chocam.
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id)
  values (v_os, v_rob, '2026-11-06', 'manha', 'proposta', v_prop2);
  insert into _resultado values
    ('E a mesma proposta com o Roberto em duas OS na mesma manhã',
     pg_temp.recusa(format(ins, v_os2, v_rob, '2026-11-06', 'manha', 'turno', 'proposta', v_prop2)) = 'sem_choque_na_proposta',
     pg_temp.recusa(format(ins, v_os2, v_rob, '2026-11-06', 'manha', 'turno', 'proposta', v_prop2))),
    ('E outra proposta com o mesmo Roberto na mesma manhã',
     pg_temp.recusa(format(ins, v_os2, v_rob, '2026-11-06', 'manha', 'turno', 'proposta', v_prop)) = 'aceitou',
     pg_temp.recusa(format(ins, v_os2, v_rob, '2026-11-06', 'manha', 'turno', 'proposta', v_prop)));

  -- Cancelada não segura o lugar.
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado' where id = a;
  insert into _resultado values ('E cancelada não segura o lugar: outra OS na manhã que ficou livre',
    pg_temp.recusa(format(ins, v_os2, v_rob, '2026-11-05', 'manha', 'turno', 'publicada', null)) = 'aceitou',
    pg_temp.recusa(format(ins, v_os2, v_rob, '2026-11-05', 'manha', 'turno', 'publicada', null)));

  -- Publicar uma proposta que bate no vigente é recusado na hora de publicar.
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_os, v_joao, '2026-11-06', 'tarde', 'publicada');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id)
  values (v_os2, v_joao, '2026-11-06', 'tarde', 'proposta', v_prop) returning id into q;
  insert into _resultado values ('E publicar a proposta que bate no vigente',
    pg_temp.recusa(format($q$update public.agenda_alocacoes set estado = 'publicada' where id = %L$q$, q)) = 'sem_choque_vigente',
    pg_temp.recusa(format($q$update public.agenda_alocacoes set estado = 'publicada' where id = %L$q$, q)));
end
$e$;

-- ── F. A versão do plano ────────────────────────────────────────────────────────────────────────────────
do $f$
declare
  v_os   uuid := 'c2000000-0000-4000-8000-000000000001';
  v_os2  uuid := 'c2000000-0000-4000-8000-000000000002';
  v_rob  uuid := 'b2000000-0000-4000-8000-000000000002';
  v_joao uuid := 'b2000000-0000-4000-8000-000000000003';
  v_prop uuid := 'd2000000-0000-4000-8000-000000000001';
  v0 bigint := (select versao_plano from public.agenda_config);
  a uuid; b uuid;
begin
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id)
  values (v_os, v_rob, '2026-11-09', 'manha', 'proposta', v_prop) returning id into a;
  insert into _resultado select 'F2 proposta nova não muda a versão', versao_plano = v0, versao_plano::text from public.agenda_config;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_os, v_joao, '2026-11-09', 'manha', 'publicada') returning id into b;
  insert into _resultado select 'F2 publicada nova: +1', versao_plano = v0 + 1, versao_plano::text from public.agenda_config;
  update public.agenda_alocacoes set estado = 'publicada' where id = a;
  insert into _resultado select 'F2 proposta → publicada: +1', versao_plano = v0 + 2, versao_plano::text from public.agenda_config;
  update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'congelamento' where id = a;
  insert into _resultado select 'F2 publicada → fixada continua vigente: +0', versao_plano = v0 + 2, versao_plano::text from public.agenda_config;
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado' where id = b;
  insert into _resultado select 'F2 publicada → cancelada: +1', versao_plano = v0 + 3, versao_plano::text from public.agenda_config;
  perform set_config('agenda.mexe_fixado', 'on', true);
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono' where id = a;
  perform set_config('agenda.mexe_fixado', 'off', true);
  insert into _resultado select 'F2 fixada → cancelada (com a chave): +1', versao_plano = v0 + 4, versao_plano::text from public.agenda_config;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_os, v_joao, '2026-11-10', 'manha', 'cancelada');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, proposta_id)
  values (v_os, v_joao, '2026-11-10', 'tarde', 'proposta', v_prop) returning id into a;
  delete from public.agenda_alocacoes where id = a;
  insert into _resultado select 'F2 nascer cancelada, nascer e morrer proposta: +0', versao_plano = v0 + 4, versao_plano::text from public.agenda_config;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (v_os, v_rob, '2026-11-10', 'manha', 'publicada'), (v_os2, v_rob, '2026-11-10', 'tarde', 'publicada');
  insert into _resultado select 'F2 duas publicadas no mesmo comando: +2 (uma por linha)', versao_plano = v0 + 6, versao_plano::text from public.agenda_config;
end
$f$;

-- ── G. O registro não se apaga e só muda no que pode ────────────────────────────────────────────────────
do $g$
declare
  v_prop  uuid := 'd2000000-0000-4000-8000-000000000001';
  v_prop2 uuid := 'd2000000-0000-4000-8000-000000000002';
  v_perg  uuid := 'e2000000-0000-4000-8000-000000000001';
  v_crit  uuid := 'e2000000-0000-4000-8000-000000000002';
  v_acao  uuid := 'f2000000-0000-4000-8000-000000000001';
  v_admin uuid := 'a2000000-0000-4000-8000-000000000001';
  v_des   uuid;
  v text; x record;
begin
  insert into _resultado
  select format('G1 não se apaga: %s', c.t),
         pg_temp.erro_de(format('delete from public.%s where id = %L', c.t, c.id)) = 'P0001 O registro da agenda não se apaga.',
         pg_temp.erro_de(format('delete from public.%s where id = %L', c.t, c.id))
    from (values ('agenda_propostas', v_prop), ('agenda_perguntas', v_perg), ('agenda_acoes', v_acao)) as c(t, id);

  -- Proposta: aberta não muda o que calculou; fecha (aplicada, com itens[].aplicado); fechada não muda.
  insert into _resultado
  select format('G2 a proposta aberta não muda: %s', c.campo),
         pg_temp.erro_de(format('update public.agenda_propostas set %s where id = %L', c.mudanca, v_prop))
           = 'P0001 A proposta não muda depois de calculada: só fecha (aplicada, expirada, obsoleta ou descartada).',
         pg_temp.erro_de(format('update public.agenda_propostas set %s where id = %L', c.mudanca, v_prop))
    from (values ('itens sem fechar', $q$itens = '[{"os":"x"}]'$q$), ('textos', $q$textos = '{"semana":"x"}'$q$),
                 ('período', $q$periodo = '[2026-11-10,2026-11-14)'$q$), ('versão', 'versao_base = 9'),
                 ('parâmetros', $q$parametros = '{"p_hoje":"2026-10-30"}'$q$)) as c(campo, mudanca);
  v := pg_temp.erro_de(format($q$update public.agenda_propostas set estado = 'aplicada', decidida_em = now(), decidida_via = 'motor',
                                 decidida_por = %L, itens = '[{"os":"x","aplicado":true}]' where id = %L$q$, v_admin, v_prop));
  insert into _resultado values ('G2 aplicar fecha a proposta e marca itens[].aplicado no mesmo update', v = 'sem erro', v);
  v := pg_temp.erro_de(format($q$update public.agenda_propostas set estado = 'aberta', decidida_em = null where id = %L$q$, v_prop));
  insert into _resultado values ('G2 aplicada não reabre',
    v = 'P0001 A proposta não muda depois de calculada: só fecha (aplicada, expirada, obsoleta ou descartada).', v);
  v := pg_temp.erro_de(format($q$update public.agenda_propostas set motivo_fim = 'depois' where id = %L$q$, v_prop));
  insert into _resultado values ('G2 aplicada não muda nem o motivo',
    v = 'P0001 A proposta não muda depois de calculada: só fecha (aplicada, expirada, obsoleta ou descartada).', v);
  v := pg_temp.erro_de(format($q$update public.agenda_propostas set estado = 'expirada', motivo_fim = 'passou das 72 h' where id = %L$q$, v_prop2));
  insert into _resultado values ('G2 aberta expira com o motivo', v = 'sem erro', v);

  -- Pergunta: aberta só se mostra/responde/resolve; a opção tem de existir; fechada não muda.
  v := pg_temp.erro_de(format($q$update public.agenda_perguntas set texto = 'Outra coisa?' where id = %L$q$, v_perg));
  insert into _resultado values ('G3 a pergunta aberta não muda o que pergunta',
    v = 'P0001 A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.', v);
  v := pg_temp.erro_de(format($q$update public.agenda_perguntas set mostrada_vezes = mostrada_vezes + 1, mostrada_em = now(), mostrada_via = 'fechamento' where id = %L$q$, v_perg));
  insert into _resultado values ('G3 a pergunta aberta é mostrada', v = 'sem erro', v);
  v := pg_temp.erro_de(format($q$update public.agenda_perguntas set estado = 'respondida', respondida_em = now(), opcao_escolhida = 9 where id = %L$q$, v_crit));
  insert into _resultado values ('G3 responder com uma opção que não existe', v = 'P0001 Essa opção não existe nesta pergunta.', v);
  v := pg_temp.erro_de($q$insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao) values ('nao_cabe', 'nao_cabe:teste-ag2-rec', 'Qual atrasa?', 'sombra', '[{"n":1},{"n":2}]', 3)$q$);
  insert into _resultado values ('G3 a recomendação tem de ser uma das opções', v = 'P0001 A recomendação tem de ser uma das opções da pergunta.', v);
  v := pg_temp.erro_de(format($q$update public.agenda_perguntas set estado = 'respondida', respondida_em = now(), respondida_por = %L,
                                 respondida_via = 'whatsapp', opcao_escolhida = 1, resposta = 'pode atrasar o Nelson' where id = %L$q$, v_admin, v_crit));
  insert into _resultado values ('G3 a crítica é respondida com a opção e as palavras do dono', v = 'sem erro', v);
  insert into _resultado
  select format('G3 respondida não muda: %s', c.campo),
         pg_temp.erro_de(format('update public.agenda_perguntas set %s where id = %L', c.mudanca, v_crit))
           = 'P0001 A pergunta fechada não muda: a decisão registrada fica como foi.',
         pg_temp.erro_de(format('update public.agenda_perguntas set %s where id = %L', c.mudanca, v_crit))
    from (values ('reabrir', $q$estado = 'aberta', respondida_em = null$q$), ('trocar a opção', 'opcao_escolhida = 2'),
                 ('trocar as palavras', $q$resposta = 'outra coisa'$q$),
                 ('contar de novo', 'mostrada_vezes = mostrada_vezes + 1')) as c(campo, mudanca);

  -- Ação: só o desfazer (uma vez) e o "contada".
  v := pg_temp.erro_de(format($q$update public.agenda_acoes set texto = 'Outra frase.' where id = %L$q$, v_acao));
  insert into _resultado values ('G4 a ação não muda a frase', v = 'P0001 A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.', v);
  v := pg_temp.erro_de(format($q$update public.agenda_acoes set executada = false, desfazivel_ate = null where id = %L$q$, v_acao));
  insert into _resultado values ('G4 a ação não deixa de ter sido executada', v = 'P0001 A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.', v);
  insert into public.agenda_acoes (dia, executada, origem, tipo, texto, desfaz_a, autor)
  values ('2026-10-29', true, 'dono', 'desfazer', 'Desfeito: o Nelson volta como estava.', v_acao, v_admin) returning id into v_des;
  v := pg_temp.erro_de(format($q$update public.agenda_acoes set desfeita_em = now(), desfeita_por = %L, desfeita_pela = %L where id = %L$q$, v_admin, v_des, v_acao));
  insert into _resultado values ('G4 a ação é desfeita', v = 'sem erro', v);
  v := pg_temp.erro_de(format($q$update public.agenda_acoes set desfeita_em = now() + interval '1 hour', desfeita_pela = %L where id = %L$q$, v_des, v_acao));
  insert into _resultado values ('G4 desfeita uma vez só', v = 'P0001 A ação registrada não muda: só se desfaz (uma vez) ou se marca como contada.', v);
  v := pg_temp.erro_de(format($q$update public.agenda_acoes set contada_em = now(), contada_via = 'fechamento' where id = %L$q$, v_acao));
  insert into _resultado values ('G4 a desfeita ainda é marcada como contada', v = 'sem erro', v);

  -- A referência que some vira nula e o registro fica (o ON DELETE SET NULL passa pelos gatilhos).
  v := pg_temp.erro_de($q$delete from public.os_material where id = '97000000-0000-4000-8000-000000000001'$q$);
  select * into x from public.agenda_perguntas where id = v_perg;
  insert into _resultado values ('G5 tirar a linha de material da OS deixa a pergunta, sem a linha',
    v = 'sem erro' and x.id is not null and x.os_material_id is null, v);
  v := pg_temp.erro_de($q$delete from public.service_orders where id = 'c2000000-0000-4000-8000-000000000003'$q$);
  insert into _resultado values ('G5 apagar a OS sem meio-dia no plano deixa a pergunta e a ação, sem a OS',
    v = 'sem erro'
    and (select service_order_id is null from public.agenda_perguntas where id = v_perg)
    and (select service_order_id is null from public.agenda_acoes where id = v_acao), v);
  v := pg_temp.erro_de(format('delete from public.app_users where id = %L', v_admin));
  insert into _resultado values ('G5 apagar o login deixa a proposta, a pergunta e as ações, sem o autor',
    v = 'sem erro'
    and (select autor is null and decidida_por is null from public.agenda_propostas where id = v_prop)
    and (select respondida_por is null and opcao_escolhida = 1 from public.agenda_perguntas where id = v_crit)
    and (select autor is null and desfeita_por is null and desfeita_em is not null from public.agenda_acoes where id = v_acao), v);
  v := pg_temp.erro_de($q$delete from public.service_orders where id = 'c2000000-0000-4000-8000-000000000001'$q$);
  insert into _resultado values ('G6 apagar a OS com meio-dia que vigorou é recusado',
    v = 'P0001 Esse meio-dia já esteve no plano: não se apaga (cancele, e fica o rastro).', v);
end
$g$;

-- ── H. Ação crítica só com a decisão do dono ────────────────────────────────────────────────────────────
do $h$
declare
  h_aberta uuid; h_sombra uuid; h_ligado uuid; h_fato uuid; h_vencida uuid;
  ins constant text := $q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto, critica, pergunta_id) values ('2026-10-29', %s, 'motor', 'mover', 'Atrasei o Nelson.', true, %L)$q$;
begin
  insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao)
  values ('nao_cabe', 'nao_cabe:teste-ag2-h1', 'Qual atrasa?', 'ligado', '[{"n":1},{"n":2}]', 2) returning id into h_aberta;
  insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao, estado, respondida_em, opcao_escolhida)
  values ('segundo_atraso', 'segundo_atraso:teste-ag2', 'Atraso de novo?', 'sombra', '[{"n":1},{"n":2}]', 1, 'respondida', now(), 1)
  returning id into h_sombra;
  insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao, estado, respondida_em, opcao_escolhida)
  values ('atraso_longo', 'atraso_longo:teste-ag2', 'Sigo assim?', 'ligado', '[{"n":1},{"n":2}]', 1, 'respondida', now(), 2)
  returning id into h_ligado;
  insert into public.agenda_perguntas (tipo, chave, texto, modo, estado, respondida_em, resposta)
  values ('chegou', 'chegou:teste-ag2-h', 'Chegou?', 'ligado', 'respondida', now(), 'chegou') returning id into h_fato;
  insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao, estado)
  values ('remarcar_confirmado', 'remarcar:teste-ag2', 'Remarco?', 'ligado', '[{"n":1},{"n":2}]', 1, 'vencida') returning id into h_vencida;

  insert into _resultado
  select format('H %s', c.caso), pg_temp.erro_de(format(ins, c.executada, c.pergunta)) = c.esperado,
         pg_temp.erro_de(format(ins, c.executada, c.pergunta))
    from (values
      ('crítica com a pergunta ainda aberta', 'true', h_aberta, 'P0001 Ação crítica sem decisão do dono: nada foi feito.'),
      ('crítica apoiada numa pergunta que não é crítica', 'true', h_fato, 'P0001 Ação crítica sem decisão do dono: nada foi feito.'),
      ('crítica executada com a decisão dada só em sombra', 'true', h_sombra, 'P0001 Ação crítica sem decisão do dono: nada foi feito.'),
      ('crítica com a pergunta vencida sem resposta', 'true', h_vencida, 'P0001 Ação crítica sem decisão do dono: nada foi feito.'),
      ('crítica em sombra (não executada) com a decisão de sombra', 'false', h_sombra, 'sem erro'),
      ('crítica executada com a decisão do dono (ligado, respondida, opção 2)', 'true', h_ligado, 'sem erro')
    ) as c(caso, executada, pergunta, esperado);

  insert into _resultado
  select 'H a métrica: nenhuma ação crítica executada sem pergunta crítica respondida em ligado', count(*) = 0, count(*)::text
    from public.agenda_acoes a
    left join public.agenda_perguntas p on p.id = a.pergunta_id
   where a.critica and a.executada
     and (p.id is null or not p.critica or p.estado <> 'respondida' or p.opcao_escolhida is null or p.modo <> 'ligado');
end
$h$;

-- ── I. RLS de verdade ───────────────────────────────────────────────────────────────────────────────────
do $i$
declare
  v_admin uuid := 'a2000000-0000-4000-8000-000000000006';
  v_tec   uuid := 'a2000000-0000-4000-8000-000000000002';
  v_sem   uuid := 'a2000000-0000-4000-8000-000000000004';
  v_fin   uuid := 'a2000000-0000-4000-8000-000000000005';
  v_rob   uuid := 'b2000000-0000-4000-8000-000000000002';
  c_total constant text := $q$select count(*) from public.agenda_alocacoes where service_order_id in ('c2000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000002')$q$;
  c_outros constant text := $q$select count(*) from public.agenda_alocacoes where payee_id <> 'b2000000-0000-4000-8000-000000000002'$q$;
  c_registro constant text := $q$select (select count(*) from public.agenda_propostas) + (select count(*) from public.agenda_perguntas) + (select count(*) from public.agenda_acoes) + (select count(*) from public.agenda_vigia_rodadas)$q$;
  c_meus constant text := $q$select array_to_string(public._agenda_payees_do_login(), ',')$q$;
  c_criar constant text := $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado) values ('c2000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000002', '2026-11-20', 'manha', 'publicada') returning 1$q$;
  c_mudar constant text := $q$update public.agenda_alocacoes set motivos = '[]' where service_order_id = 'c2000000-0000-4000-8000-000000000001' returning 1$q$;
  n_total bigint; n_rob bigint;
begin
  execute c_total into n_total;
  select count(*) into n_rob from public.agenda_alocacoes
   where payee_id = v_rob and service_order_id in ('c2000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000002');

  insert into _resultado values
    ('I1 o admin vê todos os meio-dias', pg_temp.como(v_admin, 'authenticated', c_total) = n_total::text,
     format('viu %s de %s', pg_temp.como(v_admin, 'authenticated', c_total), n_total)),
    ('I1 o financeiro vê todos os meio-dias', pg_temp.como(v_fin, 'authenticated', c_total) = n_total::text,
     format('viu %s de %s', pg_temp.como(v_fin, 'authenticated', c_total), n_total)),
    ('I2 o técnico vê só os do próprio cadastro',
     n_rob > 0 and n_rob < n_total and pg_temp.como(v_tec, 'authenticated', c_total) = n_rob::text
     and pg_temp.como(v_tec, 'authenticated', c_outros) = '0',
     format('viu %s; dele %s; de %s', pg_temp.como(v_tec, 'authenticated', c_total), n_rob, n_total)),
    ('I2 …mesmo sem ler payees (fechada para ele: quem acha o cadastro é a função security definer)',
     pg_temp.como(v_tec, 'authenticated', $q$select count(*) from public.payees where name like 'TESTE AG2%'$q$) = '0'
     and pg_temp.como(v_tec, 'authenticated', c_meus) = v_rob::text,
     pg_temp.como(v_tec, 'authenticated', c_meus)),
    ('I3 o técnico não lê propostas, perguntas, ações nem rodadas', pg_temp.como(v_tec, 'authenticated', c_registro) = '0',
     pg_temp.como(v_tec, 'authenticated', c_registro)),
    ('I4 quem tem login sem cadastro de pessoa não vê nenhum meio-dia', pg_temp.como(v_sem, 'authenticated', c_total) = '0',
     pg_temp.como(v_sem, 'authenticated', c_total)),
    ('I5 ninguém escreve pela API: o técnico tentando criar um meio-dia',
     pg_temp.como(v_tec, 'authenticated', c_criar) like 'erro 42501:%', pg_temp.como(v_tec, 'authenticated', c_criar)),
    ('I5 …nem o admin muda um meio-dia direto',
     pg_temp.como(v_admin, 'authenticated', c_mudar) like 'erro 42501:%', pg_temp.como(v_admin, 'authenticated', c_mudar)),
    ('I6 anon não lê', pg_temp.como(null, 'anon', c_total) like 'erro 42501:%', pg_temp.como(null, 'anon', c_total)),
    ('I6 anon não chama _agenda_payees_do_login', pg_temp.como(null, 'anon', c_meus) like 'erro 42501:%',
     pg_temp.como(null, 'anon', c_meus));

  -- O técnico desligado (login inativo) deixa de ver.
  update public.app_users set active = false where id = v_tec;
  insert into _resultado values ('I7 técnico com o login desligado não vê mais nada', pg_temp.como(v_tec, 'authenticated', c_total) = '0',
    pg_temp.como(v_tec, 'authenticated', c_total));
  update public.app_users set active = true where id = v_tec;
end
$i$;

-- ── J. Portas das funções ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'J1 agenda_periodo, _agenda_hoje e _agenda_payees_do_login: authenticated e service_role executam; anon nunca',
       bool_and(has_function_privilege('authenticated', f::regprocedure, 'execute')
                and has_function_privilege('service_role', f::regprocedure, 'execute')
                and not has_function_privilege('anon', f::regprocedure, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f::regprocedure, 'execute')
                                      or not has_function_privilege('authenticated', f::regprocedure, 'execute'))
  from unnest(array['public.agenda_periodo(date, text, text)', 'public._agenda_hoje()', 'public._agenda_payees_do_login()']) f;

insert into _resultado
select 'J2 as funções de gatilho: nem anon nem authenticated',
       bool_and(not has_function_privilege('anon', f::regprocedure, 'execute')
                and not has_function_privilege('authenticated', f::regprocedure, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f::regprocedure, 'execute')
                                      or has_function_privilege('authenticated', f::regprocedure, 'execute'))
  from unnest(array['public._agenda_alocacoes_antes()', 'public._agenda_alocacoes_imutavel()',
                    'public._agenda_alocacoes_nao_apaga()', 'public._agenda_alocacoes_versao()',
                    'public._agenda_registro_nao_apaga()', 'public._agenda_so_mudou(jsonb, jsonb, text[], text[])',
                    'public._agenda_propostas_so_fecha()', 'public._agenda_perguntas_antes()',
                    'public._agenda_acoes_so_desfaz()', 'public._agenda_acoes_critica_decidida()']) f;

insert into _resultado
select 'J3 só _agenda_payees_do_login é security definer; leituras STABLE, _agenda_so_mudou IMMUTABLE; search_path fixo',
       count(*) = 13
       and bool_and(p.prosecdef = (p.proname = '_agenda_payees_do_login'))
       and bool_and(case p.proname when 'agenda_periodo' then p.provolatile = 's' when '_agenda_hoje' then p.provolatile = 's'
                                   when '_agenda_payees_do_login' then p.provolatile = 's'
                                   when '_agenda_so_mudou' then p.provolatile = 'i' else true end)
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       count(*)::text || ' | ' || string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('agenda_periodo', '_agenda_hoje', '_agenda_payees_do_login', '_agenda_alocacoes_antes',
                     '_agenda_alocacoes_imutavel', '_agenda_alocacoes_nao_apaga', '_agenda_alocacoes_versao',
                     '_agenda_registro_nao_apaga', '_agenda_so_mudou', '_agenda_propostas_so_fecha',
                     '_agenda_perguntas_antes', '_agenda_acoes_so_desfaz', '_agenda_acoes_critica_decidida');

select teste, ok, detalhe from _resultado order by teste;

rollback;
