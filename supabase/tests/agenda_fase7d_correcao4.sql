-- Prova da correção da 7d, Onda 4, da Agenda de Produção (o fecho da 3ª revisão; migration 20261107100870; f7d/corr/decisoes-onda4.md). Um bloco por achado: cada um falha sem a migration e passa com ela (o "antes"
-- está nas notas). As entradas são as do revisor (f7d/rev3/achados.md). Tudo pelo caminho real: agenda_rascunho_planejar → *grava* → *desfaz*; agenda_entregar_dito → agenda_vigiar → agenda_desfazer_dito.
-- bancada: depende de 20261107100870
--
--   T0   a porta da nova e as cópias: tirados os blocos, a origem; nenhuma estrutura; o que a sessão do retorno, o dinheiro e a vigia chamam fica de fora
--   A1   a cidade da casa não sobrevive à frase seguinte, nas 3 ordens, e o lugar novo não passa a dele à casa
--   M5   a saída da recusa: "lugar novo: X" passa por cima de recado, data, estado e pergunta; seguem o vazio, as 60 letras e o T5
--   M2   São Paulo e Rio de Janeiro são cidade. M3: a UF da base sem município não diz viagem
--   M4   frases inteiras que não são lugar. M6: o "contém" só na semente, no começo, sem "não" nem " ou "
--   M7   as datas: " que " depois da data e "foi dia". M8: o *grava* não aponta para linha inativa
--   M9   o *desfaz* do *entreguei*: a regra única. M1: a releitura diz o que o *grava* faz. M10: a casa do cliente
--
-- B1 (a trava do "1") não tem banco: _shared/ai/whatsapp-channel_test.ts. O prompt: prompt-ferramentas_test.ts e os evals.
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora dela sai PULADO (usa as fixtures da 7d). Termina em ROLLBACK.
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
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim" e sem as marcas "-- (7d … -- (7d: fim)".
-- FASE 7f: o texto sem os blocos "-- FASE 7f: … -- FASE 7f: fim" e sem as marcas "-- (7f … -- (7f: fim)": quem recria uma destas na 7f só acrescenta, e a viva continua sendo a desta migration
create function pg_temp.sem_7f(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when (l ~ '^\s*-- FASE 7[efg]:' and l !~ '^\s*-- FASE 7[efg]: fim')
                                                     or (l ~ '^\s*-- \(7[efg] ' and l !~ '^\s*-- \(7[efg]: fim\)') then 1
                                                when l ~ '^\s*-- (FASE 7[efg]: fim|\(7[efg]: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7[efg]: fim|\(7[efg]: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- FASE 7f: fim
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro int := 0;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if v_dentro = 0 and l ~ '^\s*-- FASE 7[defg]:' and l !~ '^\s*-- FASE 7[defg]: fim' then v_dentro := 1; continue; end if;
    if v_dentro = 1 and l ~ '^\s*-- FASE 7[defg]: fim' then v_dentro := 0; continue; end if;
    if v_dentro = 0 and l ~ '^\s*-- \(7[defg] ' then v_dentro := 2; continue; end if;
    if v_dentro = 2 and l ~ '^\s*-- \(7[defg]: fim\)' then v_dentro := 0; continue; end if;
    if v_dentro = 0 then v_fora := v_fora || l; end if;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
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

-- ── As fixtures e os atalhos ──────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7d', true), '') = '' or coalesce(current_setting('agenda_teste.fase7c', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    return;
  end if;
  execute current_setting('agenda_teste.fase7d');
  insert into public.app_settings (key, value) values ('company_name', 'HBR Marine Solutions') on conflict (key) do nothing;
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-J1')
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
create function pg_temp.local(p_nome text) returns uuid language sql stable as $f$
  select id from public.agenda_locais where nome = p_nome
$f$;
create function pg_temp.cidade(p_os text, p_cidade text, p_uf text default 'SC') returns void language sql as $f$
  update public.clients c set city = p_cidade, state = p_uf where c.id = (select so.client_id from public.service_orders so where so.service_order_number = p_os)
$f$;
-- O motor e a vigia ligados, sem o freio, e os 6 modos da 7d num valor só
create function pg_temp.base(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_leitura = 'ligado', modo_proposta = 'ligado', modo_vigia = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         modo_local_calendario = p_modo, modo_local_autorizacao = p_modo, modo_bem = p_modo, modo_patio = p_modo, modo_viagem = p_modo, modo_mesmo_local = p_modo
   where id
$f$;
create function pg_temp.modo(p_coluna text, p_modo text) returns void language plpgsql as $f$
begin
  execute format('update public.agenda_config set %I = %L where id', p_coluna, p_modo);
end $f$;
-- O que o modelo chama e o *grava* do dono
create function pg_temp.plan(p_os text, p_dados jsonb, p_trecho text, p_hoje date default date '2027-07-16') returns jsonb language sql as $f$
  select public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', pg_temp.os(p_os)::text, p_dados, p_trecho, p_hoje)
$f$;
create function pg_temp.grava(p_hoje date default date '2027-07-16', p_hora text default '17:00') returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', pg_temp.em(p_hoje, p_hora)::text, true);
  perform set_config('agenda.hoje', p_hoje::text, true);
  return public.agenda_rascunho_gravar(pg_temp.adm(), p_hoje);
end $f$;
create function pg_temp.pl(p_os text) returns public.os_planejamento language sql stable as $f$
  select x from public.os_planejamento x where x.service_order_id = pg_temp.os(p_os)
$f$;
create function pg_temp.desfaz(p_os text, p_hoje date default date '2027-07-16', p_hora text default '18:00') returns jsonb language plpgsql as $f$
declare
  r jsonb;
begin
  r := public.agenda_rascunho_desfazer(pg_temp.adm(), 'whatsapp', pg_temp.os(p_os)::text, 'desfaz', p_hoje, pg_temp.em(p_hoje, p_hora));
  if not coalesce((r ->> 'ok')::boolean, false) then
    return r;
  end if;
  return r || jsonb_build_object('gravou', pg_temp.grava(p_hoje, p_hora));
end $f$;
create function pg_temp.foco(p_hoje date default date '2027-07-16', p_os uuid default null) returns text language sql stable as $f$
  select public._agenda_ver_locais(p_hoje, p_os) ->> 'texto'
$f$;
create function pg_temp.combinar(p_hoje date) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  return public._agenda_local_combinar(p_hoje, pg_temp.em(p_hoje, '16:20'));
end $f$;
create function pg_temp.item(p_os text, p_tipo text, p_hoje date) returns jsonb language sql as $f$
  select e from jsonb_array_elements(public._agenda_combinar_da_os(pg_temp.os(p_os), p_hoje)) e where e ->> 'tipo' = p_tipo
$f$;
create function pg_temp.aloca(p_os text, p_dia date, p_turno text, p_nome text default 'Rafael') returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  values (pg_temp.os(p_os), pg_temp.pessoa(p_nome), p_dia, p_turno, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-07-08 16:30-03')
  returning id into v;
  return v;
end $f$;
-- O M11
create function pg_temp.prepara(p_desde date default date '2027-06-01') returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = 0, cliente_conversa_dias = 0, gestor_so_propor = false, gestor_so_propor_em = null, onde_fica_desde = p_desde,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico',
                                       'mudanca_no_dia', 'onde_fica']
   where id
$f$;
create function pg_temp.passo(p_hoje date default date '2027-07-16', p_hora text default '16:20') returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  return public._agenda_cliente_onde_fica(p_hoje, pg_temp.em(p_hoje, p_hora));
end $f$;
create function pg_temp.m(p_os text) returns public.agenda_cliente_mensagens language sql stable as $f$
  select m from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_os) and m.tipo = 'onde_fica' order by m.criada_em desc limit 1
$f$;
create function pg_temp.mandado(p_os text) returns public.agenda_cliente_mensagens language plpgsql as $f$
declare
  v_m public.agenda_cliente_mensagens;
begin
  perform pg_temp.passo();
  v_m := pg_temp.m(p_os);
  update public.whatsapp_send_queue set status = 'sent', sent_at = v_m.enviar_em + interval '1 minute' where source_ref_id = v_m.id;
  return pg_temp.m(p_os);
end $f$;
create function pg_temp.resp(p_os text, p_body text, p_int text, p_agora timestamptz default timestamptz '2027-07-16 18:00-03') returns jsonb language sql as $f$
  select public.agenda_resposta_do_cliente((select c.phone from public.service_orders so join public.clients c on c.id = so.client_id where so.service_order_number = p_os),
                                           p_body, gen_random_uuid(), 'text', p_int, null, p_agora)
$f$;
create function pg_temp.site_access(p_os text) returns text language sql stable as $f$
  select so.site_access from public.service_orders so where so.id = pg_temp.os(p_os)
$f$;
-- A equipe recebe de verdade: contato e telefone
create function pg_temp.contato(p_nome text) returns void language plpgsql as $f$
begin
  if not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = pg_temp.pessoa(p_nome)) then
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em) values (pg_temp.pessoa(p_nome), true, 'dono', now());
  end if;
  update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null, parou_motivo = null where payee_id = pg_temp.pessoa(p_nome);
  update public.payees set phone = '47900000199' where id = pg_temp.pessoa(p_nome);
end $f$;

-- Atalhos da Onda 3
create function pg_temp.limpa() returns void language sql as $f$
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where estado = 'aberta'
$f$;
create function pg_temp.perg(p_tipo text, p_chave text, p_texto text, p_opcoes jsonb, p_os uuid default null, p_perda date default null) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, perda_em, modo, criada_em)
  values (p_tipo, p_chave, p_os, case when p_os is null then '{}'::uuid[] else array[p_os] end, p_texto, p_opcoes, p_perda, 'ligado', timestamptz '2027-07-16 08:00-03')
  returning id
$f$;
create function pg_temp.ver(p_hoje date default date '2027-07-16') returns jsonb language sql stable as $f$
  select public._agenda_ver_decisoes(p_hoje, pg_temp.em(p_hoje, '17:40'))
$f$;
-- O que a frase virou: novo:<nome>, local:<nome>, casa, qual, ou a recusa inteira
create function pg_temp.virou(p_os text, p_local text) returns text language plpgsql as $f$
declare
  r jsonb;
  i text;
begin
  r := pg_temp.plan(p_os, jsonb_build_object('local', p_local), 'o serviço é ' || p_local);
  if not coalesce((r ->> 'ok')::boolean, false) then
    return case when r ->> 'texto' like 'Qual deles:%' then 'qual' else r ->> 'texto' end;
  end if;
  i := substring(r ->> 'item' from 'Local: (.*)$');
  return case when i like '%(lugar novo: entra no cadastro quando você gravar).' then 'novo:' || replace(i, ' (lugar novo: entra no cadastro quando você gravar).', '')
              when i like 'na casa do cliente%' then 'casa:' || rtrim(i, '.')
              else 'local:' || rtrim(i, '.') end;
end $f$;
create function pg_temp.rascunhos() returns int language sql stable as $f$
  select count(*)::int from public.agenda_rascunho r where r.autor = pg_temp.adm() and r.estado = 'aberto'
$f$;
create function pg_temp.rascunho(p_os text) returns jsonb language sql stable as $f$
  select r.dados from public.agenda_rascunho r
   where r.autor = pg_temp.adm() and r.chave = 'planejar:' || pg_temp.os(p_os)::text and r.estado = 'aberto'
$f$;
-- As datas do rascunho aberto da OS
create function pg_temp.datas(p_os text) returns text language sql stable as $f$
  select coalesce(r.dados ->> 'entrada_em', '-') || ' ' || coalesce(r.dados ->> 'retirada_em', '-') from public.agenda_rascunho r
   where r.autor = pg_temp.adm() and r.chave = 'planejar:' || pg_temp.os(p_os)::text and r.estado = 'aberto'
$f$;
create function pg_temp.trava_tomada() returns int language sql stable as $f$
  select count(*)::int from pg_locks where locktype = 'advisory' and objid::bigint = (hashtext('agenda_local_criar')::bigint & 4294967295)
$f$;

-- Atalhos da Onda 4
-- A frase da saída, a mesma nas 3 recusas e no "Qual deles"
create function pg_temp.saida(p_texto text) returns text language sql immutable as $f$
  select format(' Se é mesmo um lugar, diga "lugar novo: %s".', p_texto)
$f$;
create function pg_temp.uma_linha(p_nome text) returns public.agenda_locais language sql stable as $f$
  select x from public.agenda_locais x where x.nome = p_nome order by x.criado_em desc limit 1
$f$;
create function pg_temp.dias(p_os text, p_hoje date) returns int language sql stable as $f$
  select count(*)::int from public.agenda_alocacoes a where a.service_order_id = pg_temp.os(p_os) and a.estado in ('publicada', 'fixada') and a.dia >= p_hoje
$f$;
create function pg_temp.status(p_os text) returns text language sql stable as $f$
  select so.status from public.service_orders so where so.id = pg_temp.os(p_os)
$f$;
create function pg_temp.cancelar(p_os text) returns uuid language sql stable as $f$
  select a.id from public.agenda_acoes a where a.service_order_id = pg_temp.os(p_os) and a.tipo = 'cancelar' and a.origem = 'vigia' and a.desfeita_em is null order by a.criada_em desc limit 1
$f$;
-- O relógio anda em produção: a ação da vigia é a mais nova do que veio antes
create function pg_temp.adianta(p_acao uuid) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  update public.agenda_acoes set criada_em = criada_em + interval '15 minutes' where id = p_acao;
  set local session_replication_role = origin;
end $f$;
create function pg_temp.vence_marcos(p_os text, p_ate timestamptz) returns void language plpgsql as $f$
begin
  set local session_replication_role = replica;
  update public.agenda_acoes set desfazivel_ate = p_ate where service_order_id = pg_temp.os(p_os) and tipo in ('entregar', 'concluir');
  set local session_replication_role = origin;
end $f$;
-- Sem linha: o *desfaz* como o dono manda
create function pg_temp.desfaz_dito(p_os text, p_hoje date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_desfazer_dito(pg_temp.adm(), pg_temp.os(p_os)::text, 'whatsapp', p_hoje, pg_temp.em(p_hoje, p_hora))
$f$;

-- ── T0. A porta da nova e as cópias ───────────────────────────────────────────────────────
insert into _resultado
select 'T0a _agenda_local_forcado: invoker, imutável, search_path fixo, e ninguém de fora (nem o service_role): quem chama é definer',
       not p.prosecdef and p.provolatile = 'i' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
       and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute'), null
  from pg_proc p where p.oid = to_regprocedure('public._agenda_local_forcado(text)');

insert into _resultado
select 'T0b rodando: anon, o técnico e o service_role não alcançam',
       pg_temp.como('anon', $q$select public._agenda_local_forcado('x')$q$) like 'erro 42501%'
       and pg_temp.como('authenticated', $q$select public._agenda_local_forcado('x')$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_local_forcado('x')$q$) like 'erro 42501%', null;

insert into _resultado
select 'T0c a assinatura de _agenda_local_novo não muda, e nem a de agenda_resolver_local', to_regprocedure('public._agenda_local_novo(text)') is not null and to_regprocedure('public.agenda_resolver_local(text,date)') is not null, null;

do $t0$
declare
  c      record;
  v_viva text;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_correcao4_fase7d', true), '');
begin
  if v_mig = '' then
    insert into _resultado values ('T0d as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)');
    return;
  end if;
  -- As funções que vêm de antes da 7d: tirados os blocos, a origem (a definição mais nova).
  for c in select * from (values
      ('agenda_rascunho_planejar', 'mig_correcao3_fase7d'), ('_agenda_aplicar_planejar', 'mig_correcao3_fase7d'), ('agenda_desfazer', 'mig_correcao3_fase7d'),
      ('agenda_rascunho_desfazer', 'mig_rascunho_fase2')) t(nome, fonte) loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_viva from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = c.nome;
    v_viva := pg_temp.sem_7f(v_viva);  -- FASE 7f: a régua (R8.13)
    insert into _resultado values ('T0d ' || c.nome || ': a viva é a da migration; sem os blocos, a origem, byte a byte',
      v_viva = pg_temp.corpo(v_mig, c.nome) and pg_temp.sem_7d(v_viva) = pg_temp.sem_7d(pg_temp.corpo(current_setting('agenda_teste.' || c.fonte), c.nome)), null);
  end loop;
  insert into _resultado values ('T0e fora: a sessão do retorno, a data dita, o dinheiro, a diária, a vigia, _agenda_desfazer_marco, _agenda_uf_dita, _agenda_local_criar e agenda_resolver_os',
    v_mig !~ 'function public\.(agenda_data_dita|_agenda_data_um|_agenda_data_conferida|_agenda_chave_telefone|agenda_dia_util|agenda_somar_du|agenda_feriado|_agenda_cliente_dia|_agenda_nome_curto|_agenda_desfazer_marco|_agenda_desfazer_diaria|_agenda_uf_dita|_agenda_local_criar|agenda_resolver_os|handle_quote_deposit_payment|_agenda_vigia_[a-z_]+|agenda_vigiar)\(', null);
  insert into _resultado values ('T0f só funções: nenhuma tabela, coluna, índice, gatilho nem dado na migration',
    v_mig !~* '(^|\n)\s*(alter table|create table|create index|create unique index|create trigger|drop )', null);
end
$t0$;

-- ── A1. A cidade da casa não sobrevive à frase seguinte ───────────────────────────────────
do $a1$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  v_cli uuid;
  l     public.agenda_locais;
  d     jsonb;
  r     jsonb;
  v_n   int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('A1', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- casa com cidade → lugar novo: a linha com a cidade dela. A saída exata do achado: Penha | Penha | SC
  begin
    perform pg_temp.base('sombra');
    select so.client_id into v_cli from public.service_orders so where so.id = pg_temp.os('OS-J3');
    update public.clients set city = null, state = null where id = v_cli;
    perform pg_temp.cidade('OS-J7', 'Bombinhas');
    perform pg_temp.cidade('OS-J1', 'Penha');
    r := pg_temp.plan('OS-J3', '{"local": "na casa dele em Bombinhas"}', 'na casa dele em Bombinhas');
    v_res := pg_temp.ok(v_res, 'A1a a régua: a casa leva a cidade', r ->> 'item' like '%Local: na casa do cliente, em Bombinhas.' and (pg_temp.rascunho('OS-J3') ->> 'local_casa_dita')::boolean, r ->> 'item');
    r := pg_temp.plan('OS-J3', '{"local": "em Penha"}', 'não, é em Penha');
    d := pg_temp.rascunho('OS-J3');
    v_res := pg_temp.ok(v_res, 'A1b o lugar novo zera as 3 chaves da casa', not (d ->> 'local_casa_dita')::boolean and d ->> 'local_casa_em' is null and d ->> 'local_casa_uf' is null and d ->> 'local_novo' = 'Penha', d::text);
    perform pg_temp.grava();
    l := pg_temp.uma_linha('Penha');
    v_res := pg_temp.ok(v_res, 'A1c a linha nova tem a cidade dela: Penha, Penha, SC', l.municipio = 'Penha' and l.uf = 'SC' and l.tipo = 'outro', to_jsonb(l)::text);
    v_res := pg_temp.ok(v_res, 'A1d a cadeia diz Penha, sem Bombinhas', public._agenda_local_resolvido(pg_temp.os('OS-J3'), v_h) ->> 'texto' = 'Penha (você disse)', public._agenda_local_resolvido(pg_temp.os('OS-J3'), v_h) ->> 'texto');
    v_res := pg_temp.ok(v_res, 'A1e nenhuma casa nasceu', not exists (select 1 from public.agenda_locais x where x.tipo = 'casa_cliente' and x.client_id = v_cli), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'A1a quebrou', false, sqlerrm);
  end;
  -- casa com cidade → local do cadastro
  begin
    perform pg_temp.base('sombra');
    select so.client_id into v_cli from public.service_orders so where so.id = pg_temp.os('OS-J3');
    update public.clients set city = null, state = null where id = v_cli;
    perform pg_temp.cidade('OS-J7', 'Bombinhas');
    perform pg_temp.plan('OS-J3', '{"local": "na casa dele em Bombinhas"}', 'na casa dele em Bombinhas');
    r := pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}', 'é na Marina Itajaí');
    d := pg_temp.rascunho('OS-J3');
    v_res := pg_temp.ok(v_res, 'A1f o local do cadastro zera as 3 chaves', not (d ->> 'local_casa_dita')::boolean and d ->> 'local_casa_em' is null and d ->> 'local_casa_uf' is null and r ->> 'item' like '%Local: Marina Itajaí.', d::text);
    perform pg_temp.grava();
    l := pg_temp.uma_linha('Marina Itajaí');
    v_res := pg_temp.ok(v_res, 'A1g a linha do cadastro não muda de cidade', l.municipio = 'Itajaí' and (pg_temp.pl('OS-J3')).local_id = l.id, to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'A1f quebrou', false, sqlerrm);
  end;
  -- casa com cidade → limpar
  begin
    perform pg_temp.base('sombra');
    select so.client_id into v_cli from public.service_orders so where so.id = pg_temp.os('OS-J3');
    update public.clients set city = null, state = null where id = v_cli;
    perform pg_temp.cidade('OS-J7', 'Bombinhas');
    perform pg_temp.plan('OS-J3', '{"local": "na casa dele em Bombinhas"}', 'na casa dele em Bombinhas');
    r := pg_temp.plan('OS-J3', '{"limpar": ["local"]}', 'tira o local');
    d := pg_temp.rascunho('OS-J3');
    v_res := pg_temp.ok(v_res, 'A1h o limpar zera as 3 chaves', not (d ->> 'local_casa_dita')::boolean and d ->> 'local_casa_em' is null and d ->> 'local_casa_uf' is null and not (d ->> 'local_casa')::boolean, d::text);
    r := pg_temp.plan('OS-J3', '{"local": "em Penha"}', 'é em Penha');
    d := pg_temp.rascunho('OS-J3');
    v_res := pg_temp.ok(v_res, 'A1i depois do limpar, a cidade da casa não volta', d ->> 'local_casa_em' is null, d::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'A1h quebrou', false, sqlerrm);
  end;
  -- lugar novo com cidade → casa: não herda
  begin
    perform pg_temp.base('sombra');
    select so.client_id into v_cli from public.service_orders so where so.id = pg_temp.os('OS-J3');
    update public.clients set city = null, state = null where id = v_cli;
    perform pg_temp.cidade('OS-J1', 'Penha');
    perform pg_temp.plan('OS-J3', '{"local": "em Penha"}', 'é em Penha');
    v_res := pg_temp.ok(v_res, 'A1j a régua: o lugar novo tem cidade', pg_temp.rascunho('OS-J3') ->> 'local_municipio' = 'Penha', null);
    r := pg_temp.plan('OS-J3', '{"local": "na casa dele"}', 'não, é na casa dele');
    d := pg_temp.rascunho('OS-J3');
    v_res := pg_temp.ok(v_res, 'A1k a casa não herda local_municipio nem local_uf', d ->> 'local_municipio' is null and d ->> 'local_uf' is null, d::text);
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
    v_res := pg_temp.ok(v_res, 'A1l a linha da casa sem cidade, e Penha não nasceu', l.tipo = 'casa_cliente' and l.municipio is null and not exists (select 1 from public.agenda_locais x where x.nome = 'Penha'), to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'A1j quebrou', false, sqlerrm);
  end;
  -- O 2º conserto, sozinho: o rascunho velho ainda com a chave (aberto antes da migration) não contamina o lugar novo
  begin
    perform pg_temp.base('sombra');
    perform public._agenda_aplicar_planejar(pg_temp.adm(), pg_temp.os('OS-J3'),
      '{"local_novo": "Penha", "local_municipio": "Penha", "local_uf": "SC", "local_id": null, "local_casa": false, "local_casa_dita": true, "local_casa_em": "Bombinhas", "local_casa_uf": "SC"}'::jsonb, 'x', v_h);
    l := pg_temp.uma_linha('Penha');
    v_res := pg_temp.ok(v_res, 'A1m o *grava* só usa a cidade na linha da casa', l.municipio = 'Penha' and l.uf = 'SC', to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'A1m quebrou', false, sqlerrm);
  end;
  -- A casa com cidade, sozinha, segue como na Onda 3
  begin
    perform pg_temp.base('sombra');
    select so.client_id into v_cli from public.service_orders so where so.id = pg_temp.os('OS-J3');
    update public.clients set city = null, state = null where id = v_cli;
    perform pg_temp.cidade('OS-J7', 'Porto Belo');
    perform pg_temp.plan('OS-J3', '{"local": "na casa dele em Porto Belo"}', 'é na casa dele em Porto Belo');
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
    v_res := pg_temp.ok(v_res, 'A1n o contraste: a casa com cidade grava a cidade', l.tipo = 'casa_cliente' and l.municipio = 'Porto Belo' and l.uf = 'SC', to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'A1n quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$a1$;

-- ── M5. A saída da recusa ─────────────────────────────────────────────────────────────────
do $m5$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  r     jsonb;
  l     public.agenda_locais;
  v_v   text;
  v_n   int;
  c_nao  constant text := 'Não entendi o lugar: me diga o nome do lugar (por exemplo, "Nova Trento").';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M5', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- O prefixo: com ou sem dois-pontos, em qualquer caixa, só no começo
  insert into _resultado
  select format('M5a o prefixo em "%s"', t.e), public._agenda_local_forcado(t.e) is not distinct from t.s, public._agenda_local_forcado(t.e)
    from (values ('lugar novo: Água Doce', 'Água Doce'), ('LUGAR NOVO: Água Doce', 'Água Doce'), ('Lugar Novo Água Doce', 'Água Doce'), ('lugar novo:Água Doce', 'Água Doce'), ('  lugar   novo :  Água Doce ', 'Água Doce'),
                 ('lugar novo', ''), ('lugar novo:', ''), ('Água Doce', null), ('o lugar novo: Água Doce', null), ('lugar novos: X', null), ('lugar novo-x', null), (null, null)) t(e, s);
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J7', 'Porto Belo');
    -- Passa por cima de tudo: as frases do achado, cada uma com a recusa de antes como contraste
    for c in select * from (values
        ('Água Doce', c_nao || pg_temp.saida('Água Doce'), 'lugar novo: Água Doce', 'novo:Água Doce'),
        ('Água Doce, SC', c_nao || pg_temp.saida('Água Doce, SC'), 'lugar novo: Água Doce, SC', 'novo:Água Doce'),
        ('Água Verde em Curitiba', c_nao || pg_temp.saida('Água Verde em Curitiba'), 'LUGAR NOVO: Água Verde em Curitiba', 'novo:Água Verde em Curitiba'),
        ('Garagem Náutica Porto Belo', c_nao || pg_temp.saida('Garagem Náutica Porto Belo'), 'lugar novo Garagem Náutica Porto Belo', 'novo:Garagem Náutica Porto Belo'),
        ('Garagem do Zé', c_nao || pg_temp.saida('Garagem do Zé'), 'lugar novo: Garagem do Zé', 'novo:Garagem do Zé'),
        ('Quinta do Sol', '"Quinta do Sol" parece uma data, não um lugar: me diga o nome do lugar (por exemplo, "Nova Trento").' || pg_temp.saida('Quinta do Sol'), 'Lugar Novo:Quinta do Sol', 'novo:Quinta do Sol'),
        ('Rua Domingo Rampelotti', '"Rua Domingo Rampelotti" parece uma data, não um lugar: me diga o nome do lugar (por exemplo, "Nova Trento").' || pg_temp.saida('Rua Domingo Rampelotti'), 'lugar novo: Rua Domingo Rampelotti', 'novo:Rua Domingo Rampelotti'),
        ('dia 5', '"dia 5" parece uma data, não um lugar: me diga o nome do lugar (por exemplo, "Nova Trento").' || pg_temp.saida('dia 5'), 'lugar novo: dia 5', 'novo:Dia 5'),
        ('Santa Catarina', '"Santa Catarina" é um estado: me diga a cidade ou o nome do lugar.' || pg_temp.saida('Santa Catarina'), 'lugar novo: Santa Catarina', 'novo:Santa Catarina'),
        ('na garagem', c_nao || pg_temp.saida('na garagem'), 'lugar novo: em Penha', 'novo:Penha')) t(frase, recusa, com, espera) loop
      v_v := pg_temp.virou('OS-J3', c.frase);
      v_res := pg_temp.ok(v_res, format('M5b a recusa de "%s" diz a saída', c.frase), v_v = c.recusa, v_v);
      v_v := pg_temp.virou('OS-J3', c.com);
      v_res := pg_temp.ok(v_res, format('M5c "%s" passa', c.com), v_v = c.espera, v_v);
    end loop;
    v_res := pg_temp.ok(v_res, 'M5d número com "lugar novo:" passa: só o vazio segue', pg_temp.virou('OS-J3', 'lugar novo: 12') = 'novo:12', null);
    v_res := pg_temp.ok(v_res, 'M5e "lugar novo: na casa dele" é um nome, não a casa', pg_temp.virou('OS-J3', 'lugar novo: na casa dele') = 'novo:Casa Dele', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M5b quebrou', false, sqlerrm);
  end;
  -- O que pergunta: o "Qual deles" sem saída ganha a frase, só na recusa do rascunho; com "outro lugar em", não
  begin
    perform pg_temp.base('sombra');
    for c in select * from (values ('pátio da Tedesco'), ('Iate Clube de Itajaí')) t(frase) loop
      r := pg_temp.plan('OS-J3', jsonb_build_object('local', c.frase), 'é ' || c.frase);
      v_res := pg_temp.ok(v_res, format('M5f "%s": "Qual deles" sem outro lugar ganha a saída; as opções ficam', c.frase),
                          r ->> 'texto' like 'Qual deles: %' and right(r ->> 'texto', char_length(pg_temp.saida(c.frase))) = pg_temp.saida(c.frase)
                          and r ->> 'motivo' = 'local_ambiguo' and jsonb_array_length(r -> 'opcoes') >= 2, r::text);
      v_res := pg_temp.ok(v_res, format('M5g "%s": o texto do resolver não muda: ele tem outros leitores', c.frase), public.agenda_resolver_local(c.frase, date '2027-07-16') ->> 'texto' not like '%lugar novo%', null);
      v_v := pg_temp.virou('OS-J3', 'lugar novo: ' || c.frase);
      v_res := pg_temp.ok(v_res, format('M5h "lugar novo: %s" passa por cima da pergunta', c.frase), v_v like 'novo:%', v_v);
    end loop;
    r := pg_temp.plan('OS-J3', '{"local": "Balneário"}', 'é em Balneário');
    v_res := pg_temp.ok(v_res, 'M5i com "outro lugar em", a saída é ela: sem a frase', r ->> 'texto' like '%outro lugar em Balneário Camboriú?', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M5f quebrou', false, sqlerrm);
  end;
  -- Continuam: o vazio, as 60 letras e o cadastro vazio (T5)
  begin
    perform pg_temp.base('sombra');
    for c in select * from (values ('lugar novo:'), ('lugar novo'), ('lugar novo: na'), ('lugar novo: ali'), ('lugar novo: .')) t(frase) loop
      v_v := pg_temp.virou('OS-J3', c.frase);
      v_res := pg_temp.ok(v_res, format('M5j "%s" é vazio', c.frase), v_v = 'Diga qual local: o nome da marina ou do estaleiro, ou "pátio".', v_v);
    end loop;
    v_v := pg_temp.virou('OS-J3', 'lugar novo: ' || repeat('a', 61));
    v_res := pg_temp.ok(v_res, 'M5k 61 letras recusa, com "lugar novo:"', v_v like 'Esse nome passa de 60 letras:%', v_v);
    v_v := pg_temp.virou('OS-J3', 'lugar novo: ' || repeat('a', 60));
    v_res := pg_temp.ok(v_res, 'M5l 60 letras passa', v_v like 'novo:%', v_v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M5j quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    update public.agenda_locais set ativo = false where ativo;
    r := pg_temp.plan('OS-J3', '{"local": "lugar novo: Nova Trento"}', 'lugar novo: Nova Trento');
    v_res := pg_temp.ok(v_res, 'M5m T5: com o cadastro vazio, "lugar novo:" segue recusando, sem rascunho e com o nome limpo',
                        r ->> 'ok' = 'false' and r ->> 'texto' = 'Não achei "Nova Trento" no cadastro.' and r ->> 'motivo' = 'local_nao_achei' and pg_temp.rascunhos() = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M5m quebrou', false, sqlerrm);
  end;
  -- O município, como no lugar novo normal; o mesmo nome reaproveita
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J7', 'Água Doce', 'SC');
    perform pg_temp.plan('OS-J3', '{"local": "lugar novo: Água Doce"}', 'lugar novo: Água Doce');
    perform pg_temp.grava();
    l := pg_temp.uma_linha('Água Doce');
    v_res := pg_temp.ok(v_res, 'M5n o município sai de _agenda_municipio_conhecido', l.municipio = 'Água Doce' and l.uf = 'SC' and l.tipo = 'outro', to_jsonb(l)::text);
    v_n := (select count(*) from public.agenda_locais);
    perform pg_temp.plan('OS-J5', '{"local": "lugar novo: Marina Itajaí"}', 'lugar novo: Marina Itajaí');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_res := pg_temp.ok(v_res, 'M5o mesmo nome: _agenda_local_criar reaproveita, sem linha nova', (select count(*) from public.agenda_locais) = v_n and (pg_temp.pl('OS-J5')).local_id = pg_temp.local('Marina Itajaí'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M5n quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m5$;

-- ── M2. São Paulo e Rio de Janeiro são cidade ──────────────────────────────────────────────
do $m2$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  l     public.agenda_locais;
  v_v   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M2', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  for c in select * from (values ('em São Paulo', 'São Paulo', 'SP'), ('no Rio de Janeiro', 'Rio de Janeiro', 'RJ'), ('São Paulo', 'São Paulo', 'SP')) t(frase, cidade, uf) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.cidade('OS-J7', c.cidade, c.uf);
      v_v := pg_temp.virou('OS-J3', c.frase);
      v_res := pg_temp.ok(v_res, format('M2a "%s" segue como lugar novo', c.frase), v_v = 'novo:' || c.cidade, v_v);
      perform pg_temp.grava();
      l := pg_temp.uma_linha(c.cidade);
      v_res := pg_temp.ok(v_res, format('M2b "%s": a cidade vem dos clientes, e a viagem é pernoite, como antes da 100860', c.frase),
                          l.municipio = c.cidade and l.uf = c.uf and public._agenda_viagem_por_municipio(l.municipio, l.uf) = 'pernoite', to_jsonb(l)::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, 'M2a quebrou', false, sqlerrm);
    end;
  end loop;
  begin
    perform pg_temp.base('sombra');
    -- só esses 2: os outros estados seguem recusados, e _agenda_uf_dita não muda
    for c in select * from (values ('Santa Catarina', 'SC'), ('Paraná', 'PR'), ('Rio Grande do Sul', 'RS'), ('Minas Gerais', 'MG')) t(frase, uf) loop
      v_v := pg_temp.virou('OS-J3', c.frase);
      v_res := pg_temp.ok(v_res, format('M2c "%s" segue estado', c.frase), v_v like '"%" é um estado: %', v_v);
    end loop;
    v_res := pg_temp.ok(v_res, 'M2d _agenda_uf_dita não muda', public._agenda_uf_dita('São Paulo') = 'SP' and public._agenda_uf_dita('Rio de Janeiro') = 'RJ', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M2c quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m2$;

-- ── M3. A UF da base sem município não diz viagem ──────────────────────────────────────────
do $m3$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  c     record;
  l     public.agenda_locais;
  d     jsonb;
  v     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M3', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  for c in select * from (values ('Cabeçudas, SC', 'Cabeçudas'), ('Praia Brava/SC', 'Praia Brava'), ('Rua Hercílio Luz, 12 - Itajaí/SC', 'Rua Hercílio Luz, 12 - Itajaí'), ('Marina Nova sc', 'Marina Nova')) t(frase, nome) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.plan('OS-J3', jsonb_build_object('local', c.frase), 'é ' || c.frase);
      d := pg_temp.rascunho('OS-J3');
      v_res := pg_temp.ok(v_res, format('M3a "%s": UF da base sem município não vai ao rascunho', c.frase), d ->> 'local_novo' = c.nome and d ->> 'local_uf' is null and d ->> 'local_municipio' is null, d::text);
      perform pg_temp.grava();
      l := pg_temp.uma_linha(c.nome);
      v := public._agenda_viagem_da_os(pg_temp.os('OS-J3'), v_h);
      v_res := pg_temp.ok(v_res, format('M3b "%s": regional, fonte padrão, como antes da 100860', c.frase), l.uf is null and v ->> 'tipo' = 'regional' and v ->> 'fonte' = 'padrao', v::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, 'M3a quebrou', false, sqlerrm);
    end;
  end loop;
  -- UF de fora sem município segue; a base com município conhecido, idem
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Sítio do Zé, PR"}', 'é no Sítio do Zé, PR');
    perform pg_temp.grava();
    l := pg_temp.uma_linha('Sítio do Zé');
    v := public._agenda_viagem_da_os(pg_temp.os('OS-J3'), v_h);
    v_res := pg_temp.ok(v_res, 'M3c UF de fora sem município segue: pernoite', l.uf = 'PR' and l.municipio is null and v ->> 'tipo' = 'pernoite', v::text);
    v_res := pg_temp.ok(v_res, 'M3d a cadeia diz o estado', public._agenda_local_resolvido(pg_temp.os('OS-J3'), v_h) ->> 'texto' like 'Sítio do Zé (PR)%', public._agenda_local_resolvido(pg_temp.os('OS-J3'), v_h) ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M3c quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J7', 'Laguna', 'SC');
    perform pg_temp.plan('OS-J3', '{"local": "Laguna, SC"}', 'é em Laguna, SC');
    perform pg_temp.grava();
    l := pg_temp.uma_linha('Laguna');
    v_res := pg_temp.ok(v_res, 'M3e a UF da base com município conhecido fica: bate-volta', l.municipio = 'Laguna' and l.uf = 'SC' and public._agenda_viagem_por_municipio(l.municipio, l.uf) = 'bate_volta', to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M3e quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m3$;

-- ── M4. Frases inteiras que não são lugar ──────────────────────────────────────────────────
do $m4$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  v_v   text;
  c_nao constant text := 'Não entendi o lugar: me diga o nome do lugar (por exemplo, "Nova Trento").';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M4', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    for c in select * from (values ('a combinar'), ('sem local'), ('indefinido'), ('não definido'), ('vou confirmar'), ('preciso confirmar'), ('aguardando cliente'), ('o cliente vai dizer'), ('ele me avisa'), ('te falo depois'),
        ('nenhum deles'), ('nenhum desses'), ('não sei qual'), ('o primeiro'), ('a primeira'), ('opção 1'), ('essa'), ('aquela'), ('qualquer um'), ('onde estiver'),
        ('É ESSA'), ('nenhuma dessas'), ('a última'), ('é a primeira'), ('ela me avisa'), ('esperando o cliente'), ('lá em cima')) t(frase) loop
      v_v := pg_temp.virou('OS-J3', c.frase);
      v_res := pg_temp.ok(v_res, format('M4a "%s": recusa, com a saída', c.frase), v_v = c_nao || pg_temp.saida(c.frase), v_v);
    end loop;
    -- Só o texto INTEIRO: nunca "no começo"
    for c in select * from (values ('Essa Marina', 'novo:Essa Marina'), ('Aguardando Cliente Ltda', 'novo:Aguardando Cliente Ltda'), ('O Primeiro Porto', 'novo:O Primeiro Porto'), ('Combinar Náutica', 'novo:Combinar Náutica')) t(frase, espera) loop
      v_v := pg_temp.virou('OS-J3', c.frase);
      v_res := pg_temp.ok(v_res, format('M4b "%s" passa: a frase não é o texto inteiro', c.frase), v_v = c.espera, v_v);
    end loop;
    v_res := pg_temp.ok(v_res, 'M4c a saída passa por cima da lista', pg_temp.virou('OS-J3', 'lugar novo: a combinar') = 'novo:A Combinar', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M4a quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m4$;

-- ── M6. O "contém" do resolver ─────────────────────────────────────────────────────────────
do $m6$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  r     jsonb;
  v_v   text;
  c_nao constant text := 'Não entendi o lugar: me diga o nome do lugar (por exemplo, "Nova Trento").';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M6', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    for c in select * from (values
        -- Tem de seguir valendo
        ('Marina Itajaí em seco', 'local:Marina Itajaí'), ('garagem da Marina Itajaí', 'local:Marina Itajaí'), ('Tedesco em seco', 'local:Tedesco Marina Garden Plaza'), ('MP em Balneário', 'local:MP Motorhomes'),
        ('vaga 12 da Marina Itajaí', 'local:Marina Itajaí'), ('Marina Itajaí vaga 12', 'local:Marina Itajaí'), ('box 3 da Marina Itajaí', 'local:Marina Itajaí'), ('pier 2 da Marina Itajaí', 'local:Marina Itajaí'), ('no píer da Marina Itajaí', 'local:Marina Itajaí'),
        -- Deixam de casar: viram lugar novo, e a releitura mostra
        ('Avenida Normando Tedesco, 100', 'novo:Avenida Normando Tedesco, 100'), ('Hotel Tedesco', 'novo:Hotel Tedesco'), ('Posto MP', 'novo:Posto MP'), ('Posto HBR', 'novo:Posto HBR'), ('Rua Kalmar, 12', 'novo:Rua Kalmar, 12'),
        -- A negação e o " ou ": recusa, com a saída
        ('não é na Kalmar', c_nao || pg_temp.saida('não é na Kalmar')), ('Marina Itajaí não, Penha', c_nao || pg_temp.saida('Marina Itajaí não, Penha')), ('Marina Itajaí ou Penha', c_nao || pg_temp.saida('Marina Itajaí ou Penha')),
        ('Itajaí ou Navegantes', c_nao || pg_temp.saida('Itajaí ou Navegantes'))) t(frase, espera) loop
      v_v := pg_temp.virou('OS-J3', c.frase);
      v_res := pg_temp.ok(v_res, format('M6a "%s"', c.frase), v_v = c.espera, v_v);
    end loop;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M6a quebrou', false, sqlerrm);
  end;
  -- A linha que o dono criou só casa pelas regras de sempre: sem saída, qualquer variação contém a palavra
  for c in select * from (values ('Centro', 'Centro de Porto Belo'), ('Centro', 'Rua do Centro, 10'), ('Porto', 'Porto Belo'), ('Porto', 'Marina Porto Belo'), ('João', 'Galpão do João'), ('João', 'casa do João')) t(base, frase) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.plan('OS-J3', jsonb_build_object('local', c.base), 'é ' || c.base);
      perform pg_temp.grava();
      v_v := pg_temp.virou('OS-J7', c.frase);
      v_res := pg_temp.ok(v_res, format('M6b com a linha "%s", "%s" é lugar novo', c.base, c.frase), v_v like 'novo:%', v_v);
      v_v := pg_temp.virou('OS-J7', c.base);
      v_res := pg_temp.ok(v_res, format('M6c "%s" é a linha dele', c.base), v_v = 'local:' || c.base, v_v);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, 'M6b quebrou', false, sqlerrm);
    end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$m6$;

-- ── M7. As datas ───────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('M7a "%s" (%s): %s', t.trecho, t.lado, case when t.passado then 'passado' else 'futuro' end),
       public._agenda_data_no_passado(t.trecho, t.dito, t.lado) = t.passado, null
  from (values
    -- O achado: " que " depois da data, e "foi dia" colado
    ('foi dia 5 que chegou', 'dia 5', 'chega', true), ('foi dia 5 que ele chegou', 'dia 5', 'chega', true), ('dia 5 foi que chegou', 'dia 5', 'chega', true),
    ('chegou aqui, foi dia 5', 'dia 5', 'chega', true), ('veio pra cá, foi dia 5', 'dia 5', 'chega', true), ('o motorhome chegou e foi dia 5', 'dia 5', 'chega', true),
    ('entrou mas foi dia 5', 'dia 5', 'chega', true), ('chegou mas foi no dia 5', 'dia 5', 'chega', true), ('veio, deixou o barco e foi dia 4', 'dia 4', 'chega', true),
    -- Nos 2 lados
    ('foi dia 5 que saiu', 'dia 5', 'sai', true), ('o barco foi no dia 5', 'dia 5', 'sai', true), ('foi dia 5', 'dia 5', 'sai', true), ('foi dia 5', 'dia 5', 'chega', true),
    -- "foi" solto não; a vírgula não muda; o " que " antes da data segue cortando
    ('foi marcado para dia 20', 'dia 20', 'chega', false), ('foi marcado para dia 20', 'dia 20', 'sai', false), ('chegou, o do Nelson dia 20', 'dia 20', 'chega', false),
    ('o cliente deixou combinado que chega dia 20', 'dia 20', 'chega', false), ('chegou, acho que dia 5', 'dia 5', 'chega', false),
    -- A oração segue cortando em " e " e " mas " depois da data, e a negação tira
    ('dia 20 e o outro chegou ontem', 'dia 20', 'chega', false), ('dia 20 mas o outro chegou', 'dia 20', 'chega', false), ('não foi dia 5', 'dia 5', 'chega', false), ('foi dia 5 que não chegou', 'dia 5', 'chega', false),
    ('chegou dia 5', 'dia 5', 'chega', true), ('dia 5 chegou', 'dia 5', 'chega', true)) t(trecho, dito, lado, passado);

do $m7$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2026-11-06';
  r     jsonb;
  c     record;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M7', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- Pelo caminho real: a data que aparece antes do *grava*
  for c in select * from (values ('foi dia 5 que chegou', 'chega_em', 'dia 5', 'entrada_em', '2026-11-05'), ('chegou mas foi no dia 5', 'chega_em', 'dia 5', 'entrada_em', '2026-11-05'),
                                 ('foi marcado para dia 20', 'chega_em', 'dia 20', 'entrada_em', '2026-11-20'), ('chegou, o do Nelson dia 20', 'chega_em', 'dia 20', 'entrada_em', '2026-11-20')) t(trecho, campo, dito, chave, espera) loop
    begin
      perform pg_temp.base('sombra');
      r := public.agenda_rascunho_planejar(pg_temp.adm(), 'whatsapp', pg_temp.os('OS-J3')::text, jsonb_build_object(c.campo, c.dito), c.trecho, v_h);
      v_res := pg_temp.ok(v_res, format('M7b "%s" vira %s', c.trecho, c.espera), pg_temp.rascunho('OS-J3') ->> c.chave = c.espera, r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, 'M7b quebrou', false, sqlerrm);
    end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$m7$;

-- ── M8. O *grava* não aponta para linha inativa ────────────────────────────────────────────
do $m8$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  r     jsonb;
  l     public.agenda_locais;
  v_id  uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M8', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- A sequência do achado: a linha sai de uso entre a releitura e o *grava*
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Nova Trento"}', 'é em Nova Trento');
    perform pg_temp.grava();
    l := pg_temp.uma_linha('Nova Trento');
    r := pg_temp.plan('OS-J7', '{"local": "Nova Trento"}', 'é em Nova Trento');
    v_res := pg_temp.ok(v_res, 'M8a a régua: a linha ativa vem como ela', r ->> 'item' like '%Local: Nova Trento.', r ->> 'item');
    r := pg_temp.desfaz_dito('OS-J3', v_h, '17:10');
    v_res := pg_temp.ok(v_res, 'M8b a régua: o *desfaz* recolheu a linha', coalesce((r ->> 'ok')::boolean, false) and not (pg_temp.uma_linha('Nova Trento')).ativo, r::text);
    r := pg_temp.grava(v_h, '17:20');
    l := pg_temp.uma_linha('Nova Trento');
    v_res := pg_temp.ok(v_res, 'M8c o *grava* reativa a linha', l.ativo and (pg_temp.pl('OS-J7')).local_id = l.id, r::text);
    v_res := pg_temp.ok(v_res, 'M8d a cadeia diz o lugar, sem suposição', public._agenda_local_resolvido(pg_temp.os('OS-J7'), v_h) ->> 'texto' like 'Nova Trento (você disse)%', public._agenda_local_resolvido(pg_temp.os('OS-J7'), v_h) ->> 'texto');
    v_res := pg_temp.ok(v_res, 'M8e sem linha nova', (select count(*) from public.agenda_locais x where x.nome = 'Nova Trento') = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M8a quebrou', false, sqlerrm);
  end;
  -- A casa do cliente, a mesma regra
  begin
    perform pg_temp.base('sombra');
    insert into public.agenda_locais (nome, tipo, client_id, ativo) select 'casa de Vanderlei', 'casa_cliente', so.client_id, false from public.service_orders so where so.id = pg_temp.os('OS-J3') returning id into v_id;
    perform public._agenda_aplicar_planejar(pg_temp.adm(), pg_temp.os('OS-J3'), jsonb_build_object('local_id', v_id), 'x', v_h);
    v_res := pg_temp.ok(v_res, 'M8g a linha da casa, inativa, volta', (select x.ativo from public.agenda_locais x where x.id = v_id), null);
    v_res := pg_temp.ok(v_res, 'M8f a reativação toma a trava de _agenda_local_criar: aqui nada mais a toma', pg_temp.trava_tomada() = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M8g quebrou', false, sqlerrm);
  end;
  -- Linha ativa não toma trava nova; o local de semente inativo não se reativa aqui
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}', 'é na Marina Itajaí');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'M8h linha ativa: nenhuma trava nova', pg_temp.trava_tomada() = 0 and (pg_temp.pl('OS-J3')).local_id = pg_temp.local('Marina Itajaí'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M8h quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    update public.agenda_locais set ativo = false where id = pg_temp.local('Marina Itajaí');
    perform public._agenda_aplicar_planejar(pg_temp.adm(), pg_temp.os('OS-J3'), jsonb_build_object('local_id', pg_temp.local('Marina Itajaí')), 'x', v_h);
    v_res := pg_temp.ok(v_res, 'M8i a semente inativa não volta: só outro e casa_cliente', not (select x.ativo from public.agenda_locais x where x.id = pg_temp.local('Marina Itajaí')) and pg_temp.trava_tomada() = 0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M8i quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m8$;

-- ── M9 + M1. O *desfaz* do *entreguei* e a releitura ───────────────────────────────────────
do $m9$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  r     jsonb;
  v_ac  uuid;
  v_n   int;
  v_nc  int;
  v_st  text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M9', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- *concluí* e *entreguei* separados, os 2 antes do tique: o 1º *desfaz* tira a entrega, o plano não volta; o 2º acha a conclusão
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    v_st := pg_temp.status('OS-J1');
    v_n := pg_temp.dias('OS-J1', v_h);
    r := public.agenda_concluir_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    r := public.agenda_entregar_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:01'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    v_ac := pg_temp.cancelar('OS-J1');
    perform pg_temp.adianta(v_ac);
    v_res := pg_temp.ok(v_res, 'M9a a régua: o tique tirou os dias', v_ac is not null and pg_temp.dias('OS-J1', v_h) = 0, r::text);
    r := public.agenda_rascunho_desfazer(pg_temp.adm(), 'whatsapp', pg_temp.os('OS-J1')::text, 'desfaz', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'M1a sem a conclusão no marco, só a entrega volta: a releitura não promete a conclusão nem a cobrança', r ->> 'releitura' not like '%volta junto%' and r ->> 'releitura' not like '%voltam junto%', r ->> 'releitura');
    r := pg_temp.grava(v_h, '14:20');
    v_res := pg_temp.ok(v_res, 'M9b o *desfaz* devolve o que o marco fez e diz o que falta', r ->> 'texto' like '%Desfeito: tirei a entrega do Lenine (OS-J1). O Lenine segue concluído: mande *desfaz OS-J1* de novo para voltar a conclusão.%', r::text);
    v_res := pg_temp.ok(v_res, 'M9c a OS segue concluída, sem a entrega, e o plano NÃO volta', pg_temp.status('OS-J1') = 'completed' and pg_temp.dias('OS-J1', v_h) = 0
                        and (select so.delivered_at is null from public.service_orders so where so.id = pg_temp.os('OS-J1')), null);
    v_res := pg_temp.ok(v_res, 'M9d o cancelar segue desfazível', (select a.desfeita_em is null from public.agenda_acoes a where a.id = v_ac), null);
    v_nc := (select count(*) from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo = 'cancelar');
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:30'));
    v_res := pg_temp.ok(v_res, 'M9e o tique seguinte não cancela de novo: não voltou nada', (select count(*) from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo = 'cancelar') = v_nc, null);
    -- O 2º acha a conclusão, e a releitura diz
    r := public.agenda_rascunho_desfazer(pg_temp.adm(), 'whatsapp', pg_temp.os('OS-J1')::text, 'desfaz', v_h, pg_temp.em(v_h, '14:40'));
    v_res := pg_temp.ok(v_res, 'M1b o 2º *desfaz*: a releitura diz que a conclusão volta e a cobrança', r ->> 'releitura' like '%A conclusão volta junto; a cobrança da conclusão, se houver, é cancelada.%', r ->> 'releitura');
    r := pg_temp.grava(v_h, '14:40');
    v_res := pg_temp.ok(v_res, 'M9f o 2º *desfaz* acha a conclusão: a OS volta, e o plano também', pg_temp.status('OS-J1') <> 'completed' and pg_temp.dias('OS-J1', v_h) = v_n
                        and not exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo in ('entregar', 'concluir', 'cancelar') and a.desfeita_em is null), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M9a quebrou', false, sqlerrm);
  end;
  -- *entreguei* que concluiu junto: 1 *desfaz*, e a releitura diz os 2
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    v_n := pg_temp.dias('OS-J1', v_h);
    r := public.agenda_entregar_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    perform pg_temp.adianta(pg_temp.cancelar('OS-J1'));
    r := public.agenda_rascunho_desfazer(pg_temp.adm(), 'whatsapp', pg_temp.os('OS-J1')::text, 'desfaz', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'M1c o marco com a conclusão: a frase da decisão', r ->> 'releitura' like '%(mudei hoje às %). A entrega e a conclusão voltam junto; a cobrança da conclusão, se houver, é cancelada.%', r ->> 'releitura');
    r := pg_temp.grava(v_h, '14:20');
    v_res := pg_temp.ok(v_res, 'M9g 1 *desfaz* volta tudo, como na Onda 3', pg_temp.status('OS-J1') <> 'completed' and pg_temp.dias('OS-J1', v_h) = v_n, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M9g quebrou', false, sqlerrm);
  end;
  -- Só a conclusão no marco: o *concluí* sem entrega
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    v_n := pg_temp.dias('OS-J1', v_h);
    r := public.agenda_concluir_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    perform pg_temp.adianta(pg_temp.cancelar('OS-J1'));
    r := pg_temp.desfaz_dito('OS-J1', v_h, '14:20');
    v_res := pg_temp.ok(v_res, 'M9h *concluí* sem entrega: 1 *desfaz* volta a conclusão e o plano', coalesce((r ->> 'ok')::boolean, false) and pg_temp.status('OS-J1') <> 'completed' and pg_temp.dias('OS-J1', v_h) = v_n, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M9h quebrou', false, sqlerrm);
  end;
  -- Tela concluiu + *entreguei*: só a entrega é desfazível
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    perform public.os_transicionar_status(pg_temp.os('OS-J1'), 'completed', 'tela', null, pg_temp.adm(), null, v_h, pg_temp.em(v_h, '13:50'));
    r := public.agenda_entregar_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    perform pg_temp.adianta(pg_temp.cancelar('OS-J1'));
    r := pg_temp.desfaz_dito('OS-J1', v_h, '14:20');
    v_res := pg_temp.ok(v_res, 'M9i tela concluiu: sem conclusão desfazível, o texto diz que só reabrindo', coalesce((r ->> 'ok')::boolean, false)
                        and r ->> 'texto' = 'Desfeito: tirei a entrega do Lenine (OS-J1). O Lenine segue concluído: os dias só voltam reabrindo a OS.', r::text);
    v_res := pg_temp.ok(v_res, 'M9j o plano não volta', pg_temp.status('OS-J1') = 'completed' and pg_temp.dias('OS-J1', v_h) = 0, null);
    r := pg_temp.desfaz_dito('OS-J1', v_h, '14:25');
    v_res := pg_temp.ok(v_res, 'M9k o 2º *desfaz* recusa: não há mais marco', r ->> 'ok' = 'false' and r ->> 'texto' = 'Não dá para voltar os dias do Lenine: ele segue concluído. Reabra a OS primeiro.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M9i quebrou', false, sqlerrm);
  end;
  -- O laço do prazo vencido: nada muda, nem no tique seguinte, e a releitura não promete
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    r := public.agenda_entregar_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    v_ac := pg_temp.cancelar('OS-J1');
    perform pg_temp.vence_marcos('OS-J1', pg_temp.em(v_h, '14:01'));
    r := public.agenda_rascunho_desfazer(pg_temp.adm(), 'whatsapp', pg_temp.os('OS-J1')::text, 'desfaz', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'M1d sem marco, a releitura não promete', r ->> 'releitura' not like '%volta%junto%', r ->> 'releitura');
    r := pg_temp.grava(v_h, '14:20');
    v_res := pg_temp.ok(v_res, 'M9l prazo vencido: nada muda, e o *grava* diz por quê', r ->> 'texto' like '%Não dá para voltar os dias do Lenine: ele segue concluído. Reabra a OS primeiro.%' and pg_temp.dias('OS-J1', v_h) = 0
                        and (select a.desfeita_em is null from public.agenda_acoes a where a.id = v_ac), r::text);
    v_nc := (select count(*) from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo = 'cancelar');
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:30'));
    v_res := pg_temp.ok(v_res, 'M9m o laço acabou: nenhum cancelar novo', (select count(*) from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo = 'cancelar') = v_nc, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M9l quebrou', false, sqlerrm);
  end;
  -- Concluída pela tela, sem *entreguei*: sem marco
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    perform public.os_transicionar_status(pg_temp.os('OS-J1'), 'completed', 'tela', null, pg_temp.adm(), null, v_h, pg_temp.em(v_h, '13:50'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    v_ac := pg_temp.cancelar('OS-J1');
    r := public.agenda_desfazer(v_ac, pg_temp.adm(), 'dono', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'M9n concluída fora do *entreguei*: ok false, nada muda', r ->> 'ok' = 'false' and r ->> 'texto' = 'Não dá para voltar os dias do Lenine: ele segue concluído. Reabra a OS primeiro.' and pg_temp.dias('OS-J1', v_h) = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M9n quebrou', false, sqlerrm);
  end;
  -- OS que não está concluída: o *desfaz* do cancelar da vigia segue como sempre
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, desfazivel_ate)
    values (clock_timestamp(), v_h, true, 'vigia', 'cancelar', pg_temp.os('OS-J1'), array[pg_temp.os('OS-J1')], '{}'::jsonb, '{}'::jsonb, 'teste', pg_temp.em(v_h, '20:00')) returning id into v_ac;
    r := public.agenda_rascunho_desfazer(pg_temp.adm(), 'whatsapp', pg_temp.os('OS-J1')::text, 'desfaz', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'M1e fora do bloco G5, a releitura é a de sempre', r ->> 'releitura' not like '%junto%', r ->> 'releitura');
    r := public.agenda_desfazer(v_ac, pg_temp.adm(), 'dono', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'M9o o contraste: OS não concluída desfaz como sempre', coalesce((r ->> 'ok')::boolean, false) and r ->> 'texto' like 'Desfeito%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M9o quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m9$;

-- ── M10. A casa do cliente ─────────────────────────────────────────────────────────────────
do $m10$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  r     jsonb;
  l     public.agenda_locais;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M10', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  for c in select * from (values ('N/D'), ('n/d'), ('.'), ('-'), (''), ('  ')) t(cidade) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.cidade('OS-J3', c.cidade, null);
      perform pg_temp.cidade('OS-J7', 'Porto Belo');
      r := pg_temp.plan('OS-J3', '{"local": "na casa dele em Porto Belo"}', 'é na casa dele em Porto Belo');
      v_res := pg_temp.ok(v_res, format('M10a cidade "%s": vale a que ele disse', c.cidade), r ->> 'item' like '%Local: na casa do cliente, em Porto Belo.', r ->> 'item');
      perform pg_temp.grava();
      select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
      v_res := pg_temp.ok(v_res, format('M10b cidade "%s": a linha da casa leva a cidade dita', c.cidade), l.tipo = 'casa_cliente' and l.municipio = 'Porto Belo' and l.uf = 'SC', to_jsonb(l)::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, 'M10a quebrou', false, sqlerrm);
    end;
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.cidade('OS-J3', c.cidade, null);
      perform pg_temp.plan('OS-J3', '{"local": "na casa dele"}', 'é na casa dele');
      perform pg_temp.grava();
      select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
      v_res := pg_temp.ok(v_res, format('M10c cidade "%s": sem cidade dita, a linha fica sem cidade', c.cidade), l.tipo = 'casa_cliente' and l.municipio is null and l.uf is null, to_jsonb(l)::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, 'M10c quebrou', false, sqlerrm);
    end;
  end loop;
  -- A UF no candidato
  for c in select * from (values ('na casa dele em Bombinhas, SC'), ('na casa dele em Bombinhas/SC'), ('na casa dele em Bombinhas - SC')) t(frase) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.cidade('OS-J3', null, null);
      perform pg_temp.cidade('OS-J7', 'Bombinhas');
      r := pg_temp.plan('OS-J3', jsonb_build_object('local', c.frase), 'é ' || c.frase);
      v_res := pg_temp.ok(v_res, format('M10d "%s": a cidade não se perde', c.frase), r ->> 'item' like '%Local: na casa do cliente, em Bombinhas.', r ->> 'item');
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, 'M10d quebrou', false, sqlerrm);
    end;
  end loop;
  begin
    perform pg_temp.cidade('OS-J7', 'Bombinhas');
    v_res := pg_temp.ok(v_res, 'M10e _agenda_municipio_conhecido tira a UF do candidato', public._agenda_municipio_conhecido('Bombinhas, SC', pg_temp.os('OS-J3')) ->> 'municipio' = 'Bombinhas', null);
    v_res := pg_temp.ok(v_res, 'M10f o nome que termina em sigla sem ser UF fica', public._agenda_municipio_conhecido('Bombinhas', pg_temp.os('OS-J3')) ->> 'uf' = 'SC', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M10e quebrou', false, sqlerrm);
  end;
  -- O contraste: cliente com cidade de verdade
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J3', 'Itapema');
    perform pg_temp.cidade('OS-J7', 'Porto Belo');
    r := pg_temp.plan('OS-J3', '{"local": "na casa dele em Porto Belo"}', 'é na casa dele em Porto Belo');
    v_res := pg_temp.ok(v_res, 'M10g o contraste: cidade de verdade no cliente segue valendo', r ->> 'item' like '%Local: na casa do cliente, em Itapema.', r ->> 'item');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'M10g quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m10$;

select teste, ok, detalhe from _resultado order by ok, teste;

rollback;
