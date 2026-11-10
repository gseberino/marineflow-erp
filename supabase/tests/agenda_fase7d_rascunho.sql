-- Prova do rascunho do dono da Agenda de Produção, Fase 7d (pacote P7; migration 20261107100600; spec-fase7d §5.7, §6.2, §8.3 agenda_fase7d_rascunho.sql, R6.1, R6.3-10,
-- R6.5, R6.7b, R6.10). Tudo pelo CAMINHO REAL: agenda_rascunho_planejar → *grava* (agenda_rascunho_gravar) → _agenda_aplicar_planejar → *desfaz*.
-- bancada: depende de 20261107100600
--
--   R0  as portas e as cópias: as 3 novas, as 5 recriadas só mudam nos blocos "-- FASE 7d:", 25 campos, a migration não escreve dado
--   R1  agenda_resolver_local com os 8 locais reais: ok, ambíguo, não achei, casa do cliente e o pátio contra o patio_hbr; a preposição
--   R2  os 8 campos → a releitura byte a byte; o *grava* grava; o limpar; a linha de antes não muda
--   R3  as recusas: local ambíguo, local que não existe, pessoa que não existe, chega >= sai, a faixa, fora do trecho; nada no rascunho
--   R4  o *desfaz*: pelo caminho da conversa e por agenda_desfazer; volta tudo, linha por linha; o histórico até 20; o que mudou depois recusa
--   R5  em teste: gravar com os 6 modos em sombra não muda agenda_propor (md5), com o contraste; com o freio grava igual
--   R6  o dono vence (o recado do P6): a pergunta local fecha, o sim dela não sobrescreve, o *desfaz* a devolve; a combinar e a acesso fecham na hora
--   R7  a linha que mistura: prometido, dupla, dias; a tela não ganha ação
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_rascunho.sql
--   Seguro em produção: termina em ROLLBACK. As portas rodam em qualquer banco; o resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
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
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim".
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- FASE 7[defg]:' and l !~ '^\s*-- FASE 7[defg]: fim' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro and l ~ '^\s*-- FASE 7[defg]: fim' then
      v_dentro := false;
      continue;
    end if;
    if not v_dentro then
      v_fora := v_fora || l;
    end if;
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

-- ── R0. As portas (sem fixture) ──────────────────────────────────────────────────────
insert into _resultado
select 'R0a agenda_resolver_local: invoker, STABLE, search_path fixo, sem public nem anon, com authenticated e service_role',
       p.oid is not null and not p.prosecdef and p.provolatile = 's' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
       and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
       and not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute')
       and has_function_privilege('service_role', p.oid, 'execute'),
       null
  from pg_proc p where p.oid = 'public.agenda_resolver_local(text, date)'::regprocedure;
insert into _resultado
select 'R0b _agenda_local_palavras acompanha a resolvedora: invoker, IMMUTABLE, search_path fixo, sem public nem anon, com authenticated (a invoker a chama)',
       p.oid is not null and not p.prosecdef and p.provolatile = 'i' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
       and not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute'),
       null
  from pg_proc p where p.oid = 'public._agenda_local_palavras(text)'::regprocedure;
insert into _resultado
select 'R0c _agenda_planejar_linhas é interna: invoker, IMMUTABLE, search_path fixo, nem public, nem anon, nem authenticated',
       p.oid is not null and not p.prosecdef and p.provolatile = 'i' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and has_function_privilege('service_role', p.oid, 'execute'),
       null
  from pg_proc p where p.oid = 'public._agenda_planejar_linhas(jsonb)'::regprocedure;
insert into _resultado
select 'R0d anon não chega (42501), rodando de verdade: a resolvedora, as palavras, as linhas e o rascunho',
       pg_temp.como('anon', $q$select public.agenda_resolver_local('patio', date '2027-07-16')::text$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public._agenda_local_palavras('patio')::text$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public._agenda_planejar_linhas('{}')::text$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public.agenda_rascunho_planejar(gen_random_uuid(), 'whatsapp', 'x', '{}', 'x', date '2027-07-16')::text$q$) like 'erro 42501%',
       pg_temp.como('anon', $q$select public.agenda_resolver_local('patio', date '2027-07-16')::text$q$);
insert into _resultado
select 'R0e as recriadas mantêm o que eram: definer e volatile as 2 do rascunho; a frase, immutable; o restaurar e o desfazer, invoker; search_path fixo',
       (select bool_and(p.prosecdef and p.provolatile = 'v' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public') from pg_proc p
         where p.oid in ('public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)'::regprocedure, 'public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)'::regprocedure))
       and (select not p.prosecdef and p.provolatile = 'i' from pg_proc p where p.oid = 'public._agenda_rascunho_frase(text, jsonb)'::regprocedure)
       and (select bool_and(not p.prosecdef and p.provolatile = 'v' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public') from pg_proc p
             where p.oid in ('public._agenda_local_restaurar(uuid, uuid, timestamptz)'::regprocedure, 'public._agenda_desfazer_local(uuid, uuid, text, date, timestamptz)'::regprocedure)),
       null;
insert into _resultado
select 'R0f c_campos tem 25 (R6.3-10): os 17 de antes + os 8',
       (select count(*) from regexp_matches(substring(p.prosrc from 'c_campos constant text\[\] := array\[(.*?)\];'), '''([a-z_]+)''', 'g')) = 25,
       (select string_agg(m[1], ',') from regexp_matches(substring(p.prosrc from 'c_campos constant text\[\] := array\[(.*?)\];'), '''([a-z_]+)''', 'g') m)
  from pg_proc p where p.oid = 'public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)'::regprocedure;

do $r0$
declare
  c      record;
  v_viva text;
  v_orig text;
  v_mig  text := replace(coalesce(current_setting('agenda_teste.mig_rascunho_fase7d', true), ''), E'\r\n', E'\n');
begin
  if v_mig = '' then
    insert into _resultado values ('R0g as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for c in select * from (values
      ('_agenda_rascunho_frase', 'public._agenda_rascunho_frase(text, jsonb)', 'mig_tarefas_fase7c'),
      ('agenda_rascunho_planejar', 'public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)', 'mig_disponibilidade_fase7b'),
      ('_agenda_aplicar_planejar', 'public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)', 'mig_disponibilidade_fase7b'),
      ('_agenda_local_restaurar', 'public._agenda_local_restaurar(uuid, uuid, timestamptz)', 'mig_cliente_fase7d'),
      ('_agenda_desfazer_local', 'public._agenda_desfazer_local(uuid, uuid, text, date, timestamptz)', 'mig_cliente_fase7d')) t(nome, assinatura, fonte) loop
    select p.prosrc into v_viva from pg_proc p where p.oid = c.assinatura::regprocedure;
    v_orig := pg_temp.corpo(current_setting('agenda_teste.' || c.fonte), c.nome);
    insert into _resultado values ('R0g ' || c.nome || ': viva = a da migration; tirados os blocos da 7d, é a origem da R6.1, byte a byte',
      -- (correção da 7d, Onda 1) 3 destas passaram a viver na 20261107100800: a viva e a desta migration são comparadas sem os blocos
      v_orig <> '' and pg_temp.sem_7d(v_viva) = pg_temp.sem_7d(pg_temp.corpo(v_mig, c.nome)) and pg_temp.sem_7d(v_viva) = pg_temp.sem_7d(v_orig), null);
  end loop;
  insert into _resultado values ('R0h a migration não escreve dado: só funções, comentários, revoke e grant',
    regexp_replace(v_mig, '\$function\$.*?\$function\$', '', 'g') !~* '^\s*(insert|update|delete|alter|drop|truncate)\s', null);
end
$r0$;

-- ── As fixtures ─────────────────────────────────────────────────────────────────────
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
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active
$f$;
create function pg_temp.local(p_nome text) returns uuid language sql stable as $f$
  select id from public.agenda_locais where nome = p_nome
$f$;
-- Os 8 locais reais (R6.5, §6.5): a fixture tem 5; os outros 3 com o nome, a cidade e os apelidos de produção (sql/wf7dd_p7_marinas).
create function pg_temp.oito() returns void language sql as $f$
  insert into public.agenda_locais (nome, apelidos, tipo, municipio, uf)
  select * from (values
    ('Kalmar Estaleiro', '{kalmar,estaleiro kalmar}'::text[], 'estaleiro', 'Itajaí', 'SC'),
    ('Marina do Sol', '{marina do sol}'::text[], 'marina', 'Guaratuba', 'PR'),
    ('Ponta do Poço Marina Clube', '{ponta do poco}'::text[], 'marina', 'Pontal do Paraná', 'PR')) t(nome, apelidos, tipo, municipio, uf)
   where not exists (select 1 from public.agenda_locais l where l.nome = t.nome)
$f$;
create function pg_temp.base(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_proposta = 'ligado', modo_vigia = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         modo_local_calendario = p_modo, modo_local_autorizacao = p_modo, modo_bem = p_modo, modo_patio = p_modo, modo_viagem = p_modo, modo_mesmo_local = p_modo
   where id
$f$;
create function pg_temp.modo(p_coluna text, p_modo text) returns void language plpgsql as $f$
begin
  execute format('update public.agenda_config set %I = %L where id', p_coluna, p_modo);
end $f$;
-- O que o modelo chama e o *grava* do dono. A OS vai pelo id: o resolver de OS só lê número com dígitos (a fixture usa OS-J1).
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
-- A linha inteira, menos o que só registra a mudança: o que o *desfaz* tem de devolver
create function pg_temp.linha(p_os text) returns jsonb language sql stable as $f$
  select to_jsonb(x) - 'historico' - 'atualizado_em' - 'atualizado_por' from public.os_planejamento x where x.service_order_id = pg_temp.os(p_os)
$f$;
create function pg_temp.aut(p_os text) returns text language sql stable as $f$
  select coalesce(string_agg(to_jsonb(x)::text, E'\n' order by x.payee_id), '') from public.os_autorizados x where x.service_order_id = pg_temp.os(p_os)
$f$;
-- Quem está autorizado agora, pelos nomes
create function pg_temp.vig(p_os text) returns text language sql stable as $f$
  select coalesce(string_agg(p.name, ',' order by p.name), '') from public.os_autorizados x join public.payees p on p.id = x.payee_id
   where x.service_order_id = pg_temp.os(p_os) and x.revogado_em is null
$f$;
create function pg_temp.abertos() returns int language sql stable as $f$
  select count(*)::int from public.agenda_rascunho r where r.autor = pg_temp.adm() and r.estado = 'aberto'
$f$;
create function pg_temp.acao(p_os text) returns public.agenda_acoes language sql stable as $f$
  select a from public.agenda_acoes a where a.service_order_id = pg_temp.os(p_os) and a.tipo = 'local' and a.depois ->> 'efeito' = 'planejar' order by a.criada_em desc, a.id desc limit 1
$f$;
-- O *desfaz* do dono pela conversa: "desfaz" vira rascunho, e o *grava* chama agenda_desfazer
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
-- O M11 de verdade até a pergunta local (o molde do K5 de agenda_fase7d_cliente.sql)
create function pg_temp.prepara() returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = 0, cliente_conversa_dias = 0, gestor_so_propor = false, gestor_so_propor_em = null,
         onde_fica_desde = date '2027-06-01',
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data', 'pronto',
                                       'pronto_lembrete', 'pos_servico', 'mudanca_no_dia', 'onde_fica']
   where id
$f$;
create function pg_temp.j2_sem_situacao() returns void language sql as $f$
  update public.os_planejamento set bem_situacao = null, bem_situacao_fonte = null, bem_situacao_em = null, descer_quem = null
   where service_order_id = pg_temp.os('OS-J2');
  update public.service_orders set converted_to_os_at = timestamptz '2027-07-15 10:00-03' where id = pg_temp.os('OS-J2');
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where service_order_id = pg_temp.os('OS-J2');
$f$;
create function pg_temp.pergunta_local(p_os text, p_disse text) returns public.agenda_perguntas language plpgsql as $f$
declare
  v_m public.agenda_cliente_mensagens;
  q   public.agenda_perguntas;
begin
  perform set_config('agenda.hoje', '2027-07-16', true);
  perform public._agenda_cliente_onde_fica(date '2027-07-16', pg_temp.em(date '2027-07-16', '16:20'));
  select * into v_m from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os(p_os) and m.tipo = 'onde_fica' order by m.criada_em desc limit 1;
  update public.whatsapp_send_queue set status = 'sent', sent_at = v_m.enviar_em + interval '1 minute' where source_ref_id = v_m.id;
  perform public.agenda_resposta_do_cliente((select c.phone from public.service_orders so join public.clients c on c.id = so.client_id where so.id = pg_temp.os(p_os)),
                                            p_disse, gen_random_uuid(), 'text', 'outro', null, pg_temp.em(date '2027-07-16', '16:40'));
  select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os(p_os) order by x.criada_em desc limit 1;
  return q;
end $f$;
-- O retrato do motor, em md5 (o molde do M1 de agenda_fase7d_motor.sql): agenda_propor semana e OS, o contexto e o que fica gravado
create function pg_temp.sem_ids(p text) returns text language sql immutable as $f$
  select regexp_replace(regexp_replace(p, '"alocacao_id": "[0-9a-f-]{36}"', '"alocacao_id": "U"', 'g'),
                        '"proposta_id": "[0-9a-f-]{36}"', '"proposta_id": "U"', 'g')
$f$;
create function pg_temp.gestor() returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado',
         modo_vaga_fechamento = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03', modo_proposta = 'ligado'
   where id
$f$;
create function pg_temp.retrato(p_hoje date, p_oss uuid[], p_ini date) returns text language plpgsql as $f$
declare
  v_ag timestamptz := pg_temp.em(p_hoje, '16:20');
  v1   text;
  v2   text;
  v3   text;
  v4   text;
  v5   text;
begin
  v1 := public.agenda_propor('semana', null, null, null, '{}'::jsonb, false, 'motor', null, p_hoje, v_ag)::text;
  v2 := public.agenda_propor('os', null, null, p_oss, '{}'::jsonb, false, 'vigia', null, p_hoje, v_ag)::text;
  v3 := public._agenda_contexto(p_ini, p_ini + 41, p_hoje, '{}'::uuid[], p_oss)::text;
  perform public.agenda_propor('os', null, null, p_oss, '{}'::jsonb, true, 'vigia', null, p_hoje, v_ag);
  select string_agg(pg_temp.sem_ids(concat_ws('|', p.escopo, p.modo, p.estado, p.itens::text, p.parametros::text, p.fora::text, p.carga::text,
                                              p.textos::text, p.pontuacao::text)), E'\n' order by p.criada_em, p.os_alvo::text)
    into v4 from public.agenda_propostas p where p.criada_em = v_ag;
  select coalesce(string_agg(concat_ws('|', q.tipo, q.chave, q.texto, q.opcoes::text, q.recomendacao, q.modo, q.estado), E'\n' order by q.chave), '')
    into v5 from public.agenda_perguntas q where q.criada_em = v_ag;
  return md5(v1) || md5(v2) || md5(v3) || md5(coalesce(v4, '')) || md5(v5) || ':' || length(v2) || ':' || length(coalesce(v4, ''));
end $f$;

-- ── R1. agenda_resolver_local, com os 8 locais reais ────────────────────────────────
do $r1$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  r     jsonb;
  v_got text;
  v_h   constant date := date '2027-07-16';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R1 agenda_resolver_local', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.oito();
    v_res := pg_temp.ok(v_res, 'R1a a prova é com os 8 locais reais, e a MP é o único patio_hbr (AG7-18)',
      (select count(*) from public.agenda_locais l where l.ativo) = 8
      and (select string_agg(l.nome, ',') from public.agenda_locais l where l.tipo = 'patio_hbr') = 'MP Motorhomes', null);
    for c in select * from (values
        -- pelo nome e pelos apelidos
        ('Marina Itajaí', 'ok', 'Marina Itajaí'), ('marina itajai', 'ok', 'Marina Itajaí'), ('na Marina Itajaí', 'ok', 'Marina Itajaí'),
        ('MARINA DE ITAJAÍ', 'ok', 'Marina Itajaí'), ('marina em Itajaí', 'ok', 'Marina Itajaí'),
        ('Kalmar', 'ok', 'Kalmar Estaleiro'), ('estaleiro kalmar', 'ok', 'Kalmar Estaleiro'), ('no estaleiro', 'ok', 'Kalmar Estaleiro'),
        ('Kalmar em Itajaí', 'ok', 'Kalmar Estaleiro'),
        ('Tedesco', 'ok', 'Tedesco Marina Garden Plaza'), ('garden plaza', 'ok', 'Tedesco Marina Garden Plaza'), ('tedesco marina', 'ok', 'Tedesco Marina Garden Plaza'),
        ('Caiobá', 'ok', 'Iate Clube Caiobá'), ('iate clube', 'ok', 'Iate Clube Caiobá'), ('no iate clube caiobá', 'ok', 'Iate Clube Caiobá'),
        ('Marina do Sol', 'ok', 'Marina do Sol'), ('sol', 'ok', 'Marina do Sol'), ('marina em Guaratuba', 'ok', 'Marina do Sol'),
        ('Ponta do Poço', 'ok', 'Ponta do Poço Marina Clube'), ('ponta do poco', 'ok', 'Ponta do Poço Marina Clube'), ('marina clube', 'ok', 'Ponta do Poço Marina Clube'),
        ('Veleiros da Ilha', 'ok', 'Veleiros da Ilha'), ('veleiros', 'ok', 'Veleiros da Ilha'),
        ('MP Motorhomes', 'ok', 'MP Motorhomes'), ('mp', 'ok', 'MP Motorhomes'), ('na MP', 'ok', 'MP Motorhomes'), ('mp motor home', 'ok', 'MP Motorhomes'),
        -- as palavras do pátio → o local patio_hbr (§5.7, R6.5)
        ('pátio', 'ok', 'MP Motorhomes'), ('patio', 'ok', 'MP Motorhomes'), ('no pátio', 'ok', 'MP Motorhomes'), ('PÁTIO DA HBR', 'ok', 'MP Motorhomes'),
        ('oficina', 'ok', 'MP Motorhomes'), ('na oficina', 'ok', 'MP Motorhomes'), ('na hbr', 'ok', 'MP Motorhomes'), ('hbr', 'ok', 'MP Motorhomes'),
        ('aqui na hbr', 'ok', 'MP Motorhomes'), ('com vocês', 'ok', 'MP Motorhomes'), ('pátio da MP', 'ok', 'MP Motorhomes'),
        ('pátio em Balneário Camboriú', 'ok', 'MP Motorhomes'),
        -- o pátio nunca é escolhido quando há outro nome na frase
        ('pátio da Kalmar', 'ambiguo', 'Kalmar Estaleiro|MP Motorhomes'), ('oficina da Tedesco', 'ambiguo', 'MP Motorhomes|Tedesco Marina Garden Plaza'),
        ('pátio da marina', 'ambiguo', 'Marina do Sol|Marina Itajaí|MP Motorhomes|Ponta do Poço Marina Clube|Tedesco Marina Garden Plaza'),
        ('pátio em Itajaí', 'ambiguo', 'Marina Itajaí|MP Motorhomes'),
        -- ambíguos
        ('marina', 'ambiguo', 'Marina do Sol|Marina Itajaí|Ponta do Poço Marina Clube|Tedesco Marina Garden Plaza'), ('a marina', 'ambiguo', 'Marina do Sol|Marina Itajaí|Ponta do Poço Marina Clube|Tedesco Marina Garden Plaza'),
        ('clube', 'ambiguo', 'Iate Clube Caiobá|Ponta do Poço Marina Clube'), ('Marina Itajaí e Kalmar', 'ambiguo', 'Kalmar Estaleiro|Marina do Sol|Marina Itajaí|Ponta do Poço Marina Clube|Tedesco Marina Garden Plaza'),
        -- a cidade não identifica: 2 locais nela é pergunta (a Marina Itajaí não ganha por ter a cidade no nome)
        ('Itajaí', 'ambiguo', 'Kalmar Estaleiro|Marina Itajaí'), ('em Balneário Camboriú', 'ambiguo', 'MP Motorhomes|Tedesco Marina Garden Plaza'),
        ('Guaratuba', 'ambiguo', 'Iate Clube Caiobá|Marina do Sol'),
        -- (correção O2) a cidade com 1 local também pergunta, com a saída "outro lugar em {cidade}": não é o local, mas é cidade com local cadastrado
        ('Florianópolis', 'ambiguo', 'Veleiros da Ilha'), ('Pontal do Paraná', 'ambiguo', 'Ponta do Poço Marina Clube'),
        -- não achei: cidade sem local; palavra que ninguém explica; o que não é local; a marina de teste, fora da semente; Camboriú é outro município
        ('Penha', 'nao_achei', null), ('Camboriú', 'nao_achei', null),
        ('marina do joão', 'nao_achei', null), ('marina nova', 'nao_achei', null), ('pátio do João', 'nao_achei', null), ('oficina do Zé', 'nao_achei', null),
        ('pátio do cliente', 'nao_achei', null), ('estaleiro do Zé', 'nao_achei', null), ('Marina Teste Auditoria', 'nao_achei', null), ('garagem', 'nao_achei', null),
        ('marinas', 'nao_achei', null), ('casa', 'nao_achei', null), ('casa do Nelson', 'nao_achei', null), ('casa do delegado', 'nao_achei', null),
        ('marina perto da casa do cliente', 'nao_achei', null),
        -- casa do cliente
        ('casa do cliente', 'casa_cliente', null), ('na casa do cliente', 'casa_cliente', null), ('na casa dele', 'casa_cliente', null), ('na casa dela', 'casa_cliente', null),
        ('na casa do cliente em Penha', 'casa_cliente', null)) t(ref, status, nomes) loop
      r := public.agenda_resolver_local(c.ref, v_h);
      v_got := case when c.status = 'ok' then r ->> 'nome'
                    when c.status = 'ambiguo' then (select string_agg(e ->> 'nome', '|' order by o) from jsonb_array_elements(r -> 'opcoes') with ordinality u(e, o)) end;
      v_res := pg_temp.ok(v_res, format('R1b "%s" → %s %s', c.ref, c.status, coalesce(c.nomes, '')),
        r ->> 'status' = c.status and v_got is not distinct from c.nomes, r::text);
    end loop;
    r := public.agenda_resolver_local(E'pátio', v_h);
    v_res := pg_temp.ok(v_res, 'R1c o acento decomposto (NFD) acha o mesmo: o nfc vem antes de _agenda_normal', r ->> 'nome' = 'MP Motorhomes', r::text);
    r := public.agenda_resolver_local('MP Motorhomes', v_h);
    v_res := pg_temp.ok(v_res, 'R1d ok: o id do local, as opções vazias e o texto com a preposição de _agenda_local_no (R6.5): "na MP Motorhomes", nunca "no"',
      (r ->> 'id')::uuid = pg_temp.local('MP Motorhomes') and r -> 'opcoes' = '[]'::jsonb and r ->> 'texto' = 'na MP Motorhomes', r::text);
    r := public.agenda_resolver_local('Marina Itajaí', v_h);
    v_res := pg_temp.ok(v_res, 'R1e na Marina Itajaí', r ->> 'texto' = 'na Marina Itajaí', r::text);
    r := public.agenda_resolver_local('marina', v_h);
    v_res := pg_temp.ok(v_res, 'R1f ambíguo: as opções com id, nome e município, e a pergunta pronta, com a cidade',
      r ->> 'id' is null and r -> 'opcoes' -> 0 ?& array['id', 'nome', 'municipio'] and r -> 'opcoes' -> 0 ->> 'municipio' = 'Guaratuba'
      and r ->> 'texto' = 'Qual deles: Marina do Sol (Guaratuba), Marina Itajaí (Itajaí), Ponta do Poço Marina Clube (Pontal do Paraná) ou Tedesco Marina Garden Plaza (Balneário Camboriú)?', r::text);
    r := public.agenda_resolver_local('marina do joão', v_h);
    v_res := pg_temp.ok(v_res, 'R1g não achei: lista os ativos, até 6, pelo nome',
      r ->> 'texto' = 'Não achei "marina do joão" no cadastro. Os locais que tenho: Iate Clube Caiobá, Kalmar Estaleiro, Marina do Sol, Marina Itajaí, MP Motorhomes, Ponta do Poço Marina Clube e mais 2.', r::text);
    r := public.agenda_resolver_local('na casa do cliente', v_h);
    v_res := pg_temp.ok(v_res, 'R1h casa do cliente: sem local, com a nota', r ->> 'id' is null and r ->> 'nome' is null and r ->> 'texto' = 'na casa do cliente' and r -> 'opcoes' = '[]'::jsonb, r::text);
    r := public.agenda_resolver_local('', v_h);
    v_res := pg_temp.ok(v_res, 'R1i vazio pede o local', r ->> 'status' = 'nao_achei' and r ->> 'texto' = 'Diga qual local: o nome da marina ou do estaleiro, ou "pátio".', r::text);
    r := public.agenda_resolver_local('aqui', v_h);
    v_res := pg_temp.ok(v_res, 'R1j só palavra sem local pede o local', r ->> 'status' = 'nao_achei' and r ->> 'texto' like 'Diga qual local%', r::text);
    r := public.agenda_resolver_local(null, v_h);
    v_res := pg_temp.ok(v_res, 'R1k nulo não quebra', r ->> 'status' = 'nao_achei', r::text);

    -- Outro pátio no cadastro: "pátio" sozinho passa a ser pergunta; pelo nome, é ele; a preposição dele é "no"
    insert into public.agenda_locais (nome, tipo, municipio, uf) values ('Pátio do Porto', 'patio_parceiro', 'Navegantes', 'SC');
    r := public.agenda_resolver_local('pátio', v_h);
    v_res := pg_temp.ok(v_res, 'R1l com um pátio de parceiro, "pátio" é pergunta, nunca o motor escolhendo', r ->> 'status' = 'ambiguo' and r ->> 'texto' = 'Qual deles: MP Motorhomes (Balneário Camboriú) ou Pátio do Porto (Navegantes)?', r::text);
    r := public.agenda_resolver_local('pátio do porto', v_h);
    v_res := pg_temp.ok(v_res, 'R1m pelo nome, é ele, com "no" (R6.5)', r ->> 'nome' = 'Pátio do Porto' and r ->> 'texto' = 'no Pátio do Porto', r::text);
    r := public.agenda_resolver_local('oficina', v_h);
    v_res := pg_temp.ok(v_res, 'R1m2 as palavras são do tipo patio_hbr: o pátio de parceiro não ganha "oficina"', r ->> 'status' = 'ok' and r ->> 'nome' = 'MP Motorhomes', r::text);
    update public.agenda_locais set ativo = false where nome = 'Pátio do Porto';
    r := public.agenda_resolver_local('pátio do porto', v_h);
    v_res := pg_temp.ok(v_res, 'R1n local inativo não entra', r ->> 'status' = 'nao_achei' and r ->> 'texto' not like '%Pátio do Porto no%', r::text);
    update public.agenda_locais set ativo = false where nome = 'MP Motorhomes';
    r := public.agenda_resolver_local('pátio', v_h);
    v_res := pg_temp.ok(v_res, 'R1o sem o patio_hbr ativo, "pátio" é não achei: as palavras são do tipo, não de um nome fixo', r ->> 'status' = 'nao_achei', r::text);
    update public.agenda_locais set ativo = true where nome = 'MP Motorhomes';
    update public.agenda_locais set apelidos = '{}' where nome = 'MP Motorhomes';
    r := public.agenda_resolver_local('oficina', v_h);
    v_res := pg_temp.ok(v_res, 'R1p as palavras do pátio valem sem o apelido (§5.7)', r ->> 'nome' = 'MP Motorhomes', r::text);
    update public.agenda_locais set ativo = false;
    r := public.agenda_resolver_local('qualquer', v_h);
    v_res := pg_temp.ok(v_res, 'R1q cadastro vazio não quebra e não inventa lista', r ->> 'texto' = 'Não achei "qualquer" no cadastro.', r::text);
    update public.agenda_locais set ativo = true where nome <> 'Pátio do Porto';
    r := public.agenda_resolver_local('ma', v_h);
    v_res := pg_temp.ok(v_res, 'R1r o "começa com" só de 3 letras em diante', r ->> 'status' = 'nao_achei', r::text);
    r := public.agenda_resolver_local('mar', v_h);
    v_res := pg_temp.ok(v_res, 'R1s de 3 em diante, começa com', r ->> 'status' = 'ambiguo', r::text);
    insert into public.agenda_locais (nome, tipo, municipio, uf) values ('Solar Marina', 'marina', 'Penha', 'SC');
    r := public.agenda_resolver_local('sol', v_h);
    v_res := pg_temp.ok(v_res, 'R1t a palavra inteira vence o "começa com" (Marina do Sol × Solar Marina)', r ->> 'nome' = 'Marina do Sol', r::text);
    v_res := pg_temp.ok(v_res, 'R1u autenticado sem ser admin ou financeiro não lê o cadastro (RLS): não achei, não erro',
      pg_temp.como('authenticated', $q$select public.agenda_resolver_local('marina', date '2027-07-16') ->> 'status'$q$) = 'nao_achei',
      pg_temp.como('authenticated', $q$select public.agenda_resolver_local('marina', date '2027-07-16') ->> 'status'$q$));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    -- depois da volta: dentro do bloco, a gravação das linhas voltaria junto
    perform pg_temp.gravar(v_res);
  end;
end
$r1$;

-- ── R2. Os 8 campos → a releitura byte a byte; o *grava* grava; o limpar ─────────────
do $r2$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  r2    jsonb;
  pl    public.os_planejamento;
  a     public.agenda_acoes;
  v_it  uuid;
  v_ag  timestamptz := pg_temp.em(date '2027-07-16', '17:00');
  v_h   jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R2 os 8 campos', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    v_it := pg_temp.local('Marina Itajaí');
    -- Beto, lancha na Marina Itajaí, sem nada dito
    r := pg_temp.plan('OS-J12', jsonb_build_object('local', 'Marina Itajaí', 'bem_onde', 'garagem_seca', 'descer_quem', 'a marina', 'bem_exige', 'agua',
                                                   'viagem', 'regional', 'autorizados', jsonb_build_array('Roberto', 'João')),
                      'a lancha do Beto está na Marina Itajaí, na garagem, quem desce é a marina, o teste é na água, Roberto e João estão autorizados');
    v_res := pg_temp.ok(v_res, 'R2a os campos do barco → a releitura da §6.2, byte a byte, uma linha por campo, na ordem',
      (r ->> 'ok')::boolean and r ->> 'releitura' = E'Entendi assim, confere?\n• Beto (OS-J12): Local: Marina Itajaí.\nO barco: em seco (garagem).\nQuem desce: a marina.\nO teste final é na água.\nSem viagem (aqui na região).\nAutorizados nesse serviço: Roberto e João. Só muda o plano quando isso for ligado.\nResponda *grava* ou corrija o que estiver errado.', r::text);
    pl := pg_temp.pl('OS-J12');
    v_res := pg_temp.ok(v_res, 'R2b nada gravado antes do *grava*', pl.local_id is null and pl.bem_situacao is null and pl.descer_quem is null and pg_temp.vig('OS-J12') = '', to_jsonb(pl)::text);
    r2 := pg_temp.grava();
    pl := pg_temp.pl('OS-J12');
    v_res := pg_temp.ok(v_res, 'R2c o *grava* grava o local, com a fonte dono e a hora', (r2 ->> 'ok')::boolean and pl.local_id = v_it and pl.local_fonte = 'dono' and pl.local_em = v_ag, r2::text);
    v_res := pg_temp.ok(v_res, 'R2d o bem, com a fonte dono e a hora; o que o serviço pede; quem desce; a viagem',
      pl.bem_situacao = 'garagem_seca' and pl.bem_situacao_fonte = 'dono' and pl.bem_situacao_em = v_ag and pl.bem_exige = 'agua' and pl.descer_quem = 'a marina' and pl.viagem = 'regional', to_jsonb(pl)::text);
    v_res := pg_temp.ok(v_res, 'R2e os_autorizados: fonte dono, local_id = o local dito na mesma linha, valido_ate nulo, o trecho e quem disse',
      (select count(*) = 2 and bool_and(x.fonte = 'dono' and x.local_id = v_it and x.valido_ate is null and x.revogado_em is null and x.criado_em = v_ag and x.criado_por = pg_temp.adm()
                                        and x.trecho like 'a lancha do Beto%')
         from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J12')) and pg_temp.vig('OS-J12') = 'João,Roberto', pg_temp.aut('OS-J12'));
    v_h := pl.historico -> -1;
    v_res := pg_temp.ok(v_res, 'R2f tudo no histórico: antes e depois de cada coluna, os autorizados, o autor e o trecho',
      v_h -> 'depois' ->> 'local_id' = v_it::text and v_h -> 'depois' ->> 'local_fonte' = 'dono' and v_h -> 'antes' ? 'local_id' and v_h -> 'antes' ->> 'local_id' is null
      and v_h -> 'depois' ->> 'bem_situacao' = 'garagem_seca' and v_h -> 'depois' ->> 'bem_exige' = 'agua' and v_h -> 'depois' ->> 'descer_quem' = 'a marina'
      and v_h -> 'depois' ->> 'viagem' = 'regional' and jsonb_array_length(v_h -> 'depois' -> 'autorizados') = 2 and v_h -> 'antes' -> 'autorizados' = '[]'::jsonb
      and (v_h ->> 'autor')::uuid = pg_temp.adm() and v_h ->> 'trecho' like 'a lancha do Beto%', v_h::text);
    a := pg_temp.acao('OS-J12');
    v_res := pg_temp.ok(v_res, 'R2g a ação local: do dono, executada, desfazível, com o texto da releitura numa linha só',
      a.executada and a.origem = 'dono' and a.tipo = 'local' and a.desfazivel_ate > v_ag and a.desfeita_em is null and a.autor = pg_temp.adm() and not a.critica and a.motivo = 'você disse'
      and a.texto = 'Beto: Local: Marina Itajaí. O barco: em seco (garagem). Quem desce: a marina. O teste final é na água. Sem viagem (aqui na região). Autorizados nesse serviço: Roberto e João.', a.texto);
    v_res := pg_temp.ok(v_res, 'R2h a ação do dono não entra no "o que mudou" (R6.3-6)', public._agenda_mudancas(date '2027-07-10', date '2027-07-16', true, true, null)::text not like '%Local: Marina Itajaí%' and public._agenda_mudancas(date '2027-07-10', date '2027-07-16', true, false, null)::text not like '%Local: Marina Itajaí%', null);
    v_res := pg_temp.ok(v_res, 'R2i a cadeia passa a dizer o que o dono disse: o local, o bem, a viagem, os autorizados',
      public._agenda_local_resolvido(pg_temp.os('OS-J12'), date '2027-07-16') ->> 'fonte' = 'dono'
      and public._agenda_estado_do_bem(pg_temp.os('OS-J12'), date '2027-07-16') ->> 'situacao_fonte' = 'dono'
      and public._agenda_estado_do_bem(pg_temp.os('OS-J12'), date '2027-07-16') ->> 'exige_fonte' = 'dono'
      and public._agenda_viagem_da_os(pg_temp.os('OS-J12'), date '2027-07-16') ->> 'fonte' = 'dono'
      and public._agenda_autorizacao_da_os(pg_temp.os('OS-J12'), date '2027-07-16') -> 'nomes' = '["João", "Roberto"]'::jsonb, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    -- Carla, motorhome sem local
    r := pg_temp.plan('OS-J11', '{"chega_em": "dia 20", "sai_em": "dia 28"}'::jsonb, 'o motorhome da Carla chega dia 20 e sai dia 28');
    v_res := pg_temp.ok(v_res, 'R2j a chegada e a saída: "O motorhome chega … e sai …", as datas pelo banco', (r ->> 'releitura') like E'%• Carla (OS-J11): O motorhome chega ter 20/07 e sai qua 28/07. Só muda o plano quando isso for ligado.\n%', r::text);
    perform pg_temp.grava();
    pl := pg_temp.pl('OS-J11');
    v_res := pg_temp.ok(v_res, 'R2k entrada_em, retirada_em e entrada_fonte = dono', pl.entrada_em = date '2027-07-20' and pl.retirada_em = date '2027-07-28' and pl.entrada_fonte = 'dono', to_jsonb(pl)::text);
    r := pg_temp.plan('OS-J11', '{"local": "pátio"}'::jsonb, 'fica no pátio');
    v_res := pg_temp.ok(v_res, 'R2l "Local:" diz o nome do patio_hbr (R6.5)', (r ->> 'releitura') like '%• Carla (OS-J11): Local: MP Motorhomes.%', r::text);
    perform pg_temp.grava();
    r := pg_temp.plan('OS-J11', '{"sai_em": "dia 30"}'::jsonb, 'agora sai dia 30');
    v_res := pg_temp.ok(v_res, 'R2m só a saída', (r ->> 'releitura') like '%• Carla (OS-J11): O motorhome sai sex 30/07.%', r::text);
    perform pg_temp.grava();
    pl := pg_temp.pl('OS-J11');
    v_res := pg_temp.ok(v_res, 'R2n só a saída muda; a chegada fica; a fonte segue dono', pl.entrada_em = date '2027-07-20' and pl.retirada_em = date '2027-07-30' and pl.entrada_fonte = 'dono', to_jsonb(pl)::text);
    r := pg_temp.plan('OS-J11', '{"chega_em": "dia 21"}'::jsonb, 'chega dia 21');
    v_res := pg_temp.ok(v_res, 'R2o só a chegada', (r ->> 'releitura') like '%• Carla (OS-J11): O motorhome chega qua 21/07.%', r::text);
    perform pg_temp.grava();
    -- o limpar
    r := pg_temp.plan('OS-J11', '{"limpar": ["local", "entrada", "retirada"]}'::jsonb, 'tira o local e as datas');
    v_res := pg_temp.ok(v_res, 'R2p o limpar: as frases da §6.2, na ordem',
      (r ->> 'releitura') like E'%• Carla (OS-J11): Tirei o local que eu tinha (volto a supor).\nTirei a data de chegada.\nTirei a data de saída.\n%', r::text);
    r2 := pg_temp.grava();
    pl := pg_temp.pl('OS-J11');
    v_res := pg_temp.ok(v_res, 'R2q o *grava* limpa: local e fonte nulos (local_coerente), datas e fonte nulas (entrada_coerente); volta a supor',
      (r2 ->> 'ok')::boolean and pl.local_id is null and pl.local_fonte is null and pl.local_em is null and pl.entrada_em is null and pl.retirada_em is null and pl.entrada_fonte is null
      and public._agenda_local_resolvido(pg_temp.os('OS-J11'), date '2027-07-16') ->> 'fonte' = 'patio', r2::text);
    r := pg_temp.plan('OS-J11', '{"chega_em": "dia 20", "sai_em": "dia 28"}'::jsonb, 'chega dia 20 e sai dia 28');
    perform pg_temp.grava();
    perform pg_temp.plan('OS-J11', '{"limpar": ["entrada"]}'::jsonb, 'tira a chegada');
    r2 := pg_temp.grava();
    pl := pg_temp.pl('OS-J11');
    v_res := pg_temp.ok(v_res, 'R2r limpar só a chegada: a saída fica e a fonte também (entrada_coerente)', (r2 ->> 'ok')::boolean and pl.entrada_em is null and pl.retirada_em = date '2027-07-28' and pl.entrada_fonte = 'dono', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    -- os textos que faltam, um a um
    r := pg_temp.plan('OS-J12', '{"viagem": "bate_volta"}'::jsonb, 'é ida e volta');
    v_res := pg_temp.ok(v_res, 'R2s viagem ida e volta', (r ->> 'releitura') like '%: Viagem: ida e volta no mesmo dia.%', r::text);
    r := pg_temp.plan('OS-J12', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá');
    v_res := pg_temp.ok(v_res, 'R2t a correção na mesma releitura vale: viagem com pernoite', (r ->> 'releitura') like '%: Viagem com pernoite: a equipe vai e volta junta, em dias seguidos.%' and (r ->> 'releitura') not like '%ida e volta%', r::text);
    r := pg_temp.plan('OS-J12', '{"limpar": ["viagem"]}'::jsonb, 'não é viagem');
    v_res := pg_temp.ok(v_res, 'R2u limpar na mesma releitura apaga o que estava (a viagem)', (r ->> 'releitura') like '%: Tirei a viagem que eu tinha (volto a supor).%' and (r ->> 'releitura') not like '%pernoite%', r::text);
    r := pg_temp.plan('OS-J12', '{"local": "casa do cliente"}'::jsonb, 'o barco está na casa do cliente');
    v_res := pg_temp.ok(v_res, 'R2v casa do cliente: a releitura não diz que anotou', (r ->> 'releitura') like '%Local: na casa do cliente.%', r::text);
    r := pg_temp.plan('OS-J12', '{"autorizados": ["eu", "Roberto"]}'::jsonb, 'eu e o Roberto');
    v_res := pg_temp.ok(v_res, 'R2w "eu" = o dono: "você"', (r ->> 'releitura') like '%Autorizados nesse serviço: você e Roberto.%', r::text);
    r := pg_temp.plan('OS-J12', '{"bem_onde": "agua"}'::jsonb, 'está na água');
    v_res := pg_temp.ok(v_res, 'R2x na água', (r ->> 'releitura') like '%O barco: na água.%', r::text);
    r := pg_temp.plan('OS-J12', '{"bem_onde": "seco"}'::jsonb, 'está no seco');
    v_res := pg_temp.ok(v_res, 'R2y em seco', (r ->> 'releitura') like '%O barco: em seco.%' and (r ->> 'releitura') not like '%(garagem)%', r::text);
    r := pg_temp.plan('OS-J12', '{"bem_onde": "patio"}'::jsonb, 'está no pátio');
    v_res := pg_temp.ok(v_res, 'R2z no pátio', (r ->> 'releitura') like '%O barco: no pátio.%', r::text);
    r := pg_temp.plan('OS-J12', '{"bem_onde": "com_cliente"}'::jsonb, 'está com ele');
    v_res := pg_temp.ok(v_res, 'R2aa com o cliente', (r ->> 'releitura') like '%O barco: com o cliente.%', r::text);
    r := pg_temp.plan('OS-J12', '{"bem_exige": "seco"}'::jsonb, 'é em seco');
    v_res := pg_temp.ok(v_res, 'R2ab o serviço é com o barco em seco', (r ->> 'releitura') like '%O serviço é com o barco em seco.%', r::text);
    r := pg_temp.plan('OS-J12', '{"bem_exige": "tanto_faz"}'::jsonb, 'tanto faz');
    v_res := pg_temp.ok(v_res, 'R2ac tanto faz', (r ->> 'releitura') like '%Tanto faz na água ou em seco.%', r::text);
    r := pg_temp.plan('OS-J12', '{"descer_quem": "  o   marinheiro "}'::jsonb, 'quem desce é o marinheiro');
    v_res := pg_temp.ok(v_res, 'R2ad quem desce: o texto aparado', (r ->> 'releitura') like '%Quem desce: o marinheiro.%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    -- os autorizados: a lista substitui; limpar revoga; a linha nunca se apaga
    perform pg_temp.plan('OS-J2', '{"autorizados": ["João"]}'::jsonb, 'agora é só o João');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R2ae a lista dita substitui a anterior: Roberto, que estava na fixture, sai com revogado_em; a linha fica',
      pg_temp.vig('OS-J2') = 'João' and (select x.revogado_em from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J2') and x.payee_id = pg_temp.pessoa('Roberto')) is not null, pg_temp.aut('OS-J2'));
    perform pg_temp.plan('OS-J2', '{"autorizados": ["João", "Roberto"]}'::jsonb, 'João e Roberto');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R2af quem volta à lista perde o revogado_em; a mesma pessoa não duplica', pg_temp.vig('OS-J2') = 'João,Roberto' and (select count(*) from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J2')) = 2, pg_temp.aut('OS-J2'));
    r := pg_temp.plan('OS-J2', '{"limpar": ["autorizados"]}'::jsonb, 'tira os autorizados');
    v_res := pg_temp.ok(v_res, 'R2ag limpar: "Tirei a lista de autorizados."', (r ->> 'releitura') like '%Tirei a lista de autorizados.%', r::text);
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R2ah limpar revoga a lista; nada se apaga', pg_temp.vig('OS-J2') = '' and (select count(*) from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J2')) = 2, pg_temp.aut('OS-J2'));
    r := pg_temp.plan('OS-J12', '{"autorizados": ["Roberto", "Roberto", "roberto"]}'::jsonb, 'o Roberto');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R2ai a mesma pessoa dita 3 vezes é uma, na releitura e na tabela', (r ->> 'releitura') like '%Autorizados nesse serviço: Roberto.%' and pg_temp.vig('OS-J12') = 'Roberto', r::text);
    -- sem o local dito, o local resolvido
    v_res := pg_temp.ok(v_res, 'R2aj sem local na linha, o local_id da linha é o local resolvido da OS', (select x.local_id from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J12')) = pg_temp.local('Marina Itajaí'), pg_temp.aut('OS-J12'));
    perform pg_temp.plan('OS-J3', '{"local": "Tedesco", "autorizados": ["Roberto"]}'::jsonb, 'na Tedesco, com o Roberto autorizado');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R2ak com o local na mesma linha, ele manda sobre a suposição', (select x.local_id from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J3')) = pg_temp.local('Tedesco Marina Garden Plaza'), pg_temp.aut('OS-J3'));
    -- casa do cliente
    perform pg_temp.plan('OS-J14', '{"local": "na casa do cliente"}'::jsonb, 'o barco ficou lá com ele');
    r2 := pg_temp.grava();
    pl := pg_temp.pl('OS-J14');
    -- (correção O3) a casa virou local: o trecho guarda só o que ele disse
    v_res := pg_temp.ok(v_res, 'R2al casa do cliente: vira a linha de agenda_locais, sobrepõe o que havia (correção O3)', (r2 ->> 'ok')::boolean and pl.local_fonte = 'dono'
                        and (select l.tipo from public.agenda_locais l where l.id = pl.local_id) = 'casa_cliente' and pl.trecho = 'o barco ficou lá com ele', to_jsonb(pl)::text);
    perform pg_temp.plan('OS-J10', '{"local": "casa do cliente"}'::jsonb, 'está na casa do cliente');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R2am o trecho é o que o dono disse', (pg_temp.pl('OS-J10')).trecho = 'está na casa do cliente', (pg_temp.pl('OS-J10')).trecho);
    -- quem já tinha linha: a palavra do dono vale inteira
    insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho)
    values (pg_temp.os('OS-J13'), pg_temp.pessoa('Roberto'), pg_temp.local('Tedesco Marina Garden Plaza'), date '2027-08-01', 'cliente', 'o cliente disse');
    perform pg_temp.plan('OS-J13', '{"local": "Marina Itajaí", "autorizados": ["Roberto"]}'::jsonb, 'na Marina Itajaí, com o Roberto');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R2an quem já tinha linha: o local, a validade, a fonte e o trecho passam a ser os do dono',
      (select x.local_id = pg_temp.local('Marina Itajaí') and x.valido_ate is null and x.fonte = 'dono' and x.trecho = 'na Marina Itajaí, com o Roberto'
         from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J13')), pg_temp.aut('OS-J13'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
  end;
end
$r2$;

-- ── R3. As recusas ──────────────────────────────────────────────────────────────────
do $r3$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  r2    jsonb;
  v_cod text;
  v_msg text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R3 as recusas', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    r := pg_temp.plan('OS-J12', '{"local": "marina"}'::jsonb, 'na marina');
    v_res := pg_temp.ok(v_res, 'R3a local ambíguo: a pergunta dela, com as opções; nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'local_ambiguo' and r ->> 'texto' like 'Qual deles: Marina do Sol (Guaratuba),%' and jsonb_array_length(r -> 'opcoes') = 4 and r -> 'opcoes' ->> 0 = 'Marina do Sol' and pg_temp.abertos() = 0, r::text);
    r := pg_temp.plan('OS-J12', '{"local": "marina do joão"}'::jsonb, 'na marina do joão');
    -- (correção O2) o lugar fora do cadastro entra na releitura; a recusa é do que não é nome: dia 5, número, vazio, mais de 60 letras (agenda_fase7d_correcao.sql)
    v_res := pg_temp.ok(v_res, 'R3b local que não existe e é nome plausível: entra na releitura (correção O2)',
      (r ->> 'ok')::boolean and r ->> 'item' like '%Local: Marina do João (lugar novo: entra no cadastro quando você gravar).%' and pg_temp.abertos() = 1, r::text);
    update public.agenda_rascunho set estado = 'substituido' where estado = 'aberto';
    r := pg_temp.plan('OS-J12', '{"local": "dia 5"}'::jsonb, 'é dia 5');
    v_res := pg_temp.ok(v_res, 'R3b2 o que não é nome: a recusa que explica; nada no rascunho (correção O2)',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'local_data' and r ->> 'texto' like '"dia 5" parece uma data%' and pg_temp.abertos() = 0, r::text);
    r := pg_temp.plan('OS-J12', '{"local": "pátio da Kalmar"}'::jsonb, 'no pátio da Kalmar');
    v_res := pg_temp.ok(v_res, 'R3c "pátio da Kalmar" não vira o pátio da HBR', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'local_ambiguo' and pg_temp.abertos() = 0, r::text);
    r := pg_temp.plan('OS-J12', '{"autorizados": ["Zé Ninguém"]}'::jsonb, 'o Zé Ninguém está autorizado');
    v_res := pg_temp.ok(v_res, 'R3d pessoa que não existe: a frase do resolvedor; nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'pessoa_nao_achei' and r ->> 'texto' = 'Não conheço ninguém chamado Zé Ninguém na equipe.' and pg_temp.abertos() = 0, r::text);
    r := pg_temp.plan('OS-J12', '{"autorizados": ["Roberto", "Zé Ninguém"]}'::jsonb, 'Roberto e Zé Ninguém');
    v_res := pg_temp.ok(v_res, 'R3e uma pessoa que não existe na lista recusa a lista inteira', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'pessoa_nao_achei' and pg_temp.abertos() = 0, r::text);
    -- (correção O7b) com o mês dito: sem ele, a chegada cai no mês da saída ou no anterior
    r := pg_temp.plan('OS-J11', '{"chega_em": "28/07", "sai_em": "20/07"}'::jsonb, 'chega 28/07 e sai 20/07');
    v_res := pg_temp.ok(v_res, 'R3f chega > sai: recusa com as duas datas; nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'chega_depois_de_sai' and r ->> 'texto' = 'Não anotei: a saída (ter 20/07) tem de ser depois da chegada (qua 28/07). Me diga as datas certas.' and pg_temp.abertos() = 0, r::text);
    r := pg_temp.plan('OS-J11', '{"chega_em": "20/07", "sai_em": "20/07"}'::jsonb, 'chega 20/07 e sai 20/07');
    v_res := pg_temp.ok(v_res, 'R3g chega = sai: recusa (entrada_antes_saida é estrito)', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'chega_depois_de_sai' and pg_temp.abertos() = 0, r::text);
    -- contra o que está gravado
    perform pg_temp.plan('OS-J11', '{"chega_em": "dia 20"}'::jsonb, 'chega dia 20');
    perform pg_temp.grava();
    r := pg_temp.plan('OS-J11', '{"sai_em": "dia 19"}'::jsonb, 'sai dia 19');
    v_res := pg_temp.ok(v_res, 'R3h a saída contra a chegada já gravada', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'chega_depois_de_sai', r::text);
    -- contra o rascunho aberto
    perform pg_temp.plan('OS-J9', '{"chega_em": "dia 25"}'::jsonb, 'chega dia 25');
    r := pg_temp.plan('OS-J9', '{"sai_em": "dia 22"}'::jsonb, 'sai dia 22');
    v_res := pg_temp.ok(v_res, 'R3i a saída contra a chegada do rascunho aberto', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'chega_depois_de_sai', r::text);
    r := pg_temp.plan('OS-J9', '{"chega_em": "dia 21", "sai_em": "dia 22"}'::jsonb, 'chega dia 21 e sai dia 22');
    v_res := pg_temp.ok(v_res, 'R3j corrigir as duas passa', (r ->> 'ok')::boolean, r::text);
    -- limpar a saída libera a chegada depois dela
    perform pg_temp.plan('OS-J8', '{"chega_em": "dia 20", "sai_em": "dia 22"}'::jsonb, 'chega dia 20 e sai dia 22');
    perform pg_temp.grava();
    perform pg_temp.plan('OS-J8', '{"limpar": ["retirada"]}'::jsonb, 'tira a saída');
    r := pg_temp.plan('OS-J8', '{"chega_em": "dia 23"}'::jsonb, 'chega dia 23');
    v_res := pg_temp.ok(v_res, 'R3k a saída limpa no rascunho aberto não conta', (r ->> 'ok')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    r := pg_temp.plan('OS-J11', '{"chega_em": "até dia 20"}'::jsonb, 'chega até dia 20');
    v_res := pg_temp.ok(v_res, 'R3l "até dia 20" é uma faixa que começa hoje: pede um dia só (o de seria hoje, que ninguém disse)', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'data_faixa' and r ->> 'texto' = 'Que dia chega? Diga um dia só (por exemplo, "dia 13").' and pg_temp.abertos() = 0, r::text);
    r := pg_temp.plan('OS-J11', '{"sai_em": "até dia 20"}'::jsonb, 'sai até dia 20');
    v_res := pg_temp.ok(v_res, 'R3m idem na saída', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'data_faixa' and r ->> 'texto' = 'Que dia sai? Diga um dia só (por exemplo, "dia 13").', r::text);
    r := pg_temp.plan('OS-J11', '{"chega_em": "entre dia 20 e dia 22"}'::jsonb, 'chega entre dia 20 e dia 22');
    v_res := pg_temp.ok(v_res, 'R3n a faixa de verdade fica com o de (§5.7)', (r ->> 'ok')::boolean and (r ->> 'releitura') like '%O motorhome chega ter 20/07.%', r::text);
    r := pg_temp.plan('OS-J4', '{"sai_em": "entre dia 23 e dia 26"}'::jsonb, 'sai entre dia 23 e dia 26');
    v_res := pg_temp.ok(v_res, 'R3n2 a faixa da saída também', (r ->> 'ok')::boolean and (r ->> 'releitura') like '%O motorhome sai sex 23/07.%', r::text);
    r := pg_temp.plan('OS-J8', '{"chega_em": "hoje"}'::jsonb, 'chega hoje');
    v_res := pg_temp.ok(v_res, 'R3o hoje é um dia só: passa', (r ->> 'ok')::boolean and (r ->> 'releitura') like '%chega sex 16/07.%', r::text);
    r := pg_temp.plan('OS-J7', '{"chega_em": "dia 5"}'::jsonb, 'chega dia 20');
    v_res := pg_temp.ok(v_res, 'R3p a data tem de estar no que o dono disse', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'fora_do_trecho' and r ->> 'texto' = 'Não achei "dia 5" no que você disse; me diga de novo.', r::text);
    r := pg_temp.plan('OS-J7', '{"sai_em": "quando der"}'::jsonb, 'sai quando der');
    v_res := pg_temp.ok(v_res, 'R3q a data que o banco não entende volta a frase dele', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'data', r::text);
    r := pg_temp.plan('OS-J7', '{"descer_quem": "x"}'::jsonb, 'quem desce é x');
    v_res := pg_temp.ok(v_res, 'R3r quem desce: o CHECK de 2 letras vira pergunta, não erro no *grava*', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'descer_quem', r::text);
    r := pg_temp.plan('OS-J7', jsonb_build_object('descer_quem', repeat('a', 81)), 'quem desce');
    v_res := pg_temp.ok(v_res, 'R3s quem desce: o CHECK de 80 também', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'descer_quem', r::text);
    r := pg_temp.plan('OS-J7', jsonb_build_object('descer_quem', repeat('a', 80)), 'quem desce');
    v_res := pg_temp.ok(v_res, 'R3t 80 passa', (r ->> 'ok')::boolean, r::text);
    -- o rascunho que já foi gravado e o que expirou não contam: a chegada dele saiu
    perform pg_temp.plan('OS-J6', '{"chega_em": "dia 20"}'::jsonb, 'chega dia 20');
    perform pg_temp.grava();
    perform pg_temp.plan('OS-J6', '{"limpar": ["entrada"]}'::jsonb, 'tira a chegada');
    perform pg_temp.grava();
    r := pg_temp.plan('OS-J6', '{"sai_em": "dia 19"}'::jsonb, 'sai dia 19');
    v_res := pg_temp.ok(v_res, 'R3w o rascunho já gravado não conta: a chegada dele foi tirada', (r ->> 'ok')::boolean, r::text);
    perform pg_temp.plan('OS-J5', '{"chega_em": "dia 25"}'::jsonb, 'chega dia 25');
    update public.agenda_rascunho set criado_em = now() - interval '2 hours', expira_em = now() - interval '1 minute' where chave = 'planejar:' || pg_temp.os('OS-J5') and estado = 'aberto';
    r := pg_temp.plan('OS-J5', '{"sai_em": "dia 22"}'::jsonb, 'sai dia 22');
    v_res := pg_temp.ok(v_res, 'R3x o rascunho expirado não conta', (r ->> 'ok')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  -- erro de quem chamou
  for r2 in select * from jsonb_array_elements('[
      {"nome": "bem_onde fora da lista", "d": {"bem_onde": "garagem"}, "msg": "agenda_rascunho_planejar: bem_onde \"garagem\" inválido (agua, seco, garagem_seca, patio ou com_cliente)"},
      {"nome": "bem_exige fora da lista", "d": {"bem_exige": "molhado"}, "msg": "agenda_rascunho_planejar: bem_exige \"molhado\" inválido (agua, seco ou tanto_faz)"},
      {"nome": "viagem fora da lista", "d": {"viagem": "longe"}, "msg": "agenda_rascunho_planejar: viagem \"longe\" inválida (regional, bate_volta ou pernoite)"},
      {"nome": "autorizados não é lista", "d": {"autorizados": "Roberto"}, "msg": "agenda_rascunho_planejar: autorizados tem de ser a lista de nomes"},
      {"nome": "autorizados vazio", "d": {"autorizados": []}, "msg": "agenda_rascunho_planejar: autorizados tem de ser a lista de nomes"},
      {"nome": "limpar local e local", "d": {"local": "Tedesco", "limpar": ["local"]}, "msg": "agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada"},
      {"nome": "limpar entrada e chega_em", "d": {"chega_em": "dia 20", "limpar": ["entrada"]}, "msg": "agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada"},
      {"nome": "limpar retirada e sai_em", "d": {"sai_em": "dia 20", "limpar": ["retirada"]}, "msg": "agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada"},
      {"nome": "limpar viagem e viagem", "d": {"viagem": "regional", "limpar": ["viagem"]}, "msg": "agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada"},
      {"nome": "limpar autorizados e autorizados", "d": {"autorizados": ["Roberto"], "limpar": ["autorizados"]}, "msg": "agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada"},
      {"nome": "limpar o que não existe, com os novos", "d": {"limpar": ["local", "tudo"]}, "msg": "agenda_rascunho_planejar: limpar \"tudo\" não existe (espera, nao_antes, prazo ou escopo)"},
      {"nome": "campo que não existe", "d": {"onde": "Tedesco"}, "msg": "agenda_rascunho_planejar: o campo \"onde\" não existe"}
    ]'::jsonb) loop
    begin
      perform pg_temp.plan('OS-J12', r2 -> 'd', 'dia 20');
      v_cod := 'sem erro';
      v_msg := '';
    exception when others then
      v_cod := sqlstate;
      v_msg := sqlerrm;
    end;
    v_res := pg_temp.ok(v_res, 'R3u ' || (r2 ->> 'nome') || ': 22023, erro de quem chamou', v_cod = '22023' and v_msg = r2 ->> 'msg', v_cod || ' ' || v_msg);
  end loop;
  perform pg_temp.gravar(v_res);
  v_res := '[]'::jsonb;

  -- O que mudou entre a releitura e o *grava*: a frase, não "o banco recusou"
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J11', '{"sai_em": "dia 20"}'::jsonb, 'sai dia 20');
    update public.os_planejamento set entrada_em = date '2027-07-25', entrada_fonte = 'cliente' where service_order_id = pg_temp.os('OS-J11');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R3v a chegada que mudou depois da releitura: não grava nada, com a frase das datas',
      not (r ->> 'ok')::boolean and r ->> 'texto' like 'Não gravei nada: a saída (ter 20/07) tem de ser depois da chegada (dom 25/07) (%' and (pg_temp.pl('OS-J11')).retirada_em is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
  end;
end
$r3$;

-- ── R4. O *desfaz* ──────────────────────────────────────────────────────────────────
do $r4$
declare
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  r2     jsonb;
  a      public.agenda_acoes;
  a2     public.agenda_acoes;
  v_lin  jsonb;
  v_aut  text;
  v_tudo constant jsonb := '{"local": "Tedesco", "bem_onde": "agua", "bem_exige": "seco", "descer_quem": "o marinheiro", "chega_em": "dia 20", "sai_em": "dia 28", "viagem": "pernoite", "autorizados": ["João"]}';
  c_tr   constant text := 'na Tedesco, na água, o serviço é em seco, quem desce é o marinheiro, chega dia 20 e sai dia 28, dormindo lá, só o João autorizado';
  i      int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R4 o desfaz', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    -- J2 tem de tudo já dito (a situação, quem desce, Roberto autorizado): o *desfaz* devolve o que havia, não o vazio
    update public.os_planejamento
       set local_id = pg_temp.local('Marina Itajaí'), local_fonte = 'cliente', local_em = timestamptz '2027-07-02 10:00-03',
           bem_exige = 'agua', viagem = 'regional', entrada_em = date '2027-07-19', retirada_em = date '2027-07-27', entrada_fonte = 'cliente', trecho = 'o de antes'
     where service_order_id = pg_temp.os('OS-J2');
    update public.os_autorizados set valido_ate = date '2027-08-01' where service_order_id = pg_temp.os('OS-J2') and payee_id = pg_temp.pessoa('Roberto');
    v_lin := pg_temp.linha('OS-J2');
    v_aut := pg_temp.aut('OS-J2');
    r := pg_temp.plan('OS-J2', v_tudo, c_tr);
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R4a o *grava* mudou tudo', (r2 ->> 'ok')::boolean and (pg_temp.pl('OS-J2')).viagem = 'pernoite' and (pg_temp.pl('OS-J2')).local_fonte = 'dono' and pg_temp.vig('OS-J2') = 'João'
      and (pg_temp.pl('OS-J2')).entrada_fonte = 'dono' and (pg_temp.pl('OS-J2')).retirada_em = date '2027-07-28', r2::text);
    a := pg_temp.acao('OS-J2');
    r := pg_temp.desfaz('OS-J2');
    v_res := pg_temp.ok(v_res, 'R4b a conversa: "desfaz" mostra a releitura com o texto da ação e o *grava* chama agenda_desfazer',
      (r ->> 'ok')::boolean and r ->> 'releitura' like '%Desfaço: Nelson: Local: Tedesco Marina Garden Plaza.%' and (r -> 'gravou' ->> 'ok')::boolean, r::text);
    v_res := pg_temp.ok(v_res, 'R4c a linha volta INTEIRA: local e fonte de antes, a situação, o que o serviço pede, quem desce, as datas, a fonte delas, a viagem, o trecho',
      pg_temp.linha('OS-J2') = v_lin, jsonb_build_object('agora', pg_temp.linha('OS-J2'), 'antes', v_lin)::text);
    v_res := pg_temp.ok(v_res, 'R4d os_autorizados volta linha por linha: Roberto como era, João revogado (a linha fica)',
      pg_temp.vig('OS-J2') = 'Roberto'
      and (select to_jsonb(x)::text from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J2') and x.payee_id = pg_temp.pessoa('Roberto')) = v_aut
      and (select x.revogado_em from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J2') and x.payee_id = pg_temp.pessoa('João')) is not null, pg_temp.aut('OS-J2'));
    select * into a2 from public.agenda_acoes x where x.id = a.id;
    v_res := pg_temp.ok(v_res, 'R4e a ação fica desfeita, com o texto de uma linha', a2.desfeita_em is not null and a2.desfeita_pela is not null
      and (select x.texto from public.agenda_acoes x where x.id = a2.desfeita_pela) = 'Desfeito: o serviço de Nelson voltou como estava.', (select x.texto from public.agenda_acoes x where x.id = a2.desfeita_pela));
    v_res := pg_temp.ok(v_res, 'R4f o histórico guarda o desfeito', (pg_temp.pl('OS-J2')).historico -> -1 ->> 'motivo' = 'desfeito', null);
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:10'));
    v_res := pg_temp.ok(v_res, 'R4g não desfaz duas vezes', not (r ->> 'ok')::boolean and r ->> 'texto' = 'Isso já foi desfeito.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    -- Sem nada antes: volta ao vazio. Direto em agenda_desfazer, o que o *grava* chama
    v_lin := pg_temp.linha('OS-J11');
    perform pg_temp.plan('OS-J11', '{"local": "Tedesco"}'::jsonb, 'na Tedesco');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J11');
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4h só o local suposto: o texto da §6.3', (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfeito: o local do serviço de Carla voltou a ser o que eu supunha.', r::text);
    v_res := pg_temp.ok(v_res, 'R4i a linha volta', (to_jsonb(pg_temp.pl('OS-J11')) ->> 'local_id') is null and (pg_temp.pl('OS-J11')).local_fonte is null and (pg_temp.pl('OS-J11')).local_em is null and (pg_temp.pl('OS-J11')).trecho is not distinct from v_lin ->> 'trecho', null);
    perform pg_temp.plan('OS-J11', '{"local": "Tedesco", "viagem": "pernoite"}'::jsonb, 'na Tedesco, dormindo lá');
    perform pg_temp.grava();
    r := public.agenda_desfazer((pg_temp.acao('OS-J11')).id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4i2 o local e mais alguma coisa: a frase de uma linha, não só a do local', (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfeito: o serviço de Carla voltou como estava.', r::text);

    perform pg_temp.plan('OS-J12', '{"autorizados": ["Roberto"]}'::jsonb, 'o Roberto');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J12');
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4j só quem entrou na lista: o texto da §6.3, com o nome', (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfeito: a autorização de Roberto saiu.' and pg_temp.vig('OS-J12') = '', r::text);

    -- o limpar também volta
    perform pg_temp.plan('OS-J2', '{"limpar": ["autorizados"]}'::jsonb, 'tira os autorizados');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R4k limpou', pg_temp.vig('OS-J2') = '', null);
    a := pg_temp.acao('OS-J2');
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4l o *desfaz* do limpar devolve a lista', (r ->> 'ok')::boolean and pg_temp.vig('OS-J2') = 'Roberto', r::text);

    -- a recusa: mudou depois
    perform pg_temp.plan('OS-J9', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J9');
    perform pg_temp.plan('OS-J9', '{"viagem": "bate_volta"}'::jsonb, 'é ida e volta');
    perform pg_temp.grava();
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4m o que mudou depois recusa: a viagem de agora fica', not (r ->> 'ok')::boolean and r ->> 'texto' like 'Não desfaço: depois disso o plano do%' and (pg_temp.pl('OS-J9')).viagem = 'bate_volta', r::text);
    perform pg_temp.plan('OS-J10', '{"bem_exige": "agua"}'::jsonb, 'teste na água');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J10');
    perform pg_temp.plan('OS-J10', '{"bem_exige": "seco"}'::jsonb, 'em seco');
    perform pg_temp.grava();
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4n idem no que o serviço pede', not (r ->> 'ok')::boolean and (pg_temp.pl('OS-J10')).bem_exige = 'seco', r::text);
    perform pg_temp.plan('OS-J8', '{"sai_em": "dia 28"}'::jsonb, 'sai dia 28');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J8');
    perform pg_temp.plan('OS-J8', '{"sai_em": "dia 29"}'::jsonb, 'sai dia 29');
    perform pg_temp.grava();
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4o idem na saída', not (r ->> 'ok')::boolean and (pg_temp.pl('OS-J8')).retirada_em = date '2027-07-29', r::text);
    perform pg_temp.plan('OS-J7', '{"autorizados": ["Roberto"]}'::jsonb, 'Roberto');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J7');
    perform pg_temp.plan('OS-J7', '{"autorizados": ["João"]}'::jsonb, 'João');
    perform pg_temp.grava();
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4p a lista de autorizados que mudou depois recusa', not (r ->> 'ok')::boolean and pg_temp.vig('OS-J7') = 'João', r::text);
    -- outra fala depois não some: o trecho só volta se ainda é o da ação
    perform pg_temp.plan('OS-J6', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J6');
    perform pg_temp.plan('OS-J6', '{"prioridade": 2}'::jsonb, 'prioridade 2');
    perform pg_temp.grava();
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4q outra fala depois, em outro campo: o *desfaz* passa e o trecho dela fica', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J6')).viagem is null and (pg_temp.pl('OS-J6')).trecho = 'prioridade 2', r::text);
    -- o que não é do local não volta: dias não têm *desfaz*
    perform pg_temp.plan('OS-J3', '{"dias": 3, "viagem": "pernoite"}'::jsonb, 'são 3 dias e a gente dorme lá');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J3');
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4r na mesma linha, os dias ficam: não têm *desfaz*, como sempre; o da ação volta', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J3')).viagem is null and (pg_temp.pl('OS-J3')).dias = 3, r::text);
    -- o prazo
    perform pg_temp.plan('OS-J4', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá');
    perform pg_temp.grava();
    a := pg_temp.acao('OS-J4');
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-20', a.desfazivel_ate + interval '1 minute');
    v_res := pg_temp.ok(v_res, 'R4s passou o prazo: recusa', not (r ->> 'ok')::boolean and r ->> 'texto' like 'Não dá mais para desfazer%' and (pg_temp.pl('OS-J4')).viagem = 'pernoite', r::text);
    -- repetir o que já está não vira ação
    perform pg_temp.plan('OS-J5', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá');
    perform pg_temp.grava();
    perform pg_temp.plan('OS-J5', '{"viagem": "pernoite"}'::jsonb, 'a gente dorme lá, sim');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R4t dizer de novo o mesmo não vira ação nova', (select count(*) from public.agenda_acoes x where x.service_order_id = pg_temp.os('OS-J5') and x.tipo = 'local') = 1, null);
    -- a mesma coluna, outra fonte: o dono confirma o que o cliente disse, e o *desfaz* devolve a fonte
    update public.os_planejamento set local_id = pg_temp.local('Tedesco Marina Garden Plaza'), local_fonte = 'cliente', local_em = timestamptz '2027-07-02 10:00-03' where service_order_id = pg_temp.os('OS-J13');
    perform pg_temp.plan('OS-J13', '{"local": "Tedesco"}'::jsonb, 'é na Tedesco mesmo');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R4w1 o mesmo local, com a fonte de quem disse por último', (pg_temp.pl('OS-J13')).local_fonte = 'dono', null);
    r := public.agenda_desfazer((pg_temp.acao('OS-J13')).id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4w o *desfaz* devolve a fonte e a hora, mesmo com o local igual', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J13')).local_fonte = 'cliente' and (pg_temp.pl('OS-J13')).local_em = timestamptz '2027-07-02 10:00-03', r::text);
    -- "voltou a ser o que eu supunha" só quando não havia local
    perform pg_temp.plan('OS-J13', '{"local": "Marina Itajaí"}'::jsonb, 'é na Marina Itajaí');
    perform pg_temp.grava();
    r := public.agenda_desfazer((pg_temp.acao('OS-J13')).id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4x havia local: a frase de uma linha, não "o que eu supunha"', (r ->> 'ok')::boolean and r ->> 'texto' = 'Desfeito: o serviço de Júlio voltou como estava.' and (pg_temp.pl('OS-J13')).local_id = pg_temp.local('Tedesco Marina Garden Plaza'), r::text);
    -- idem nas datas
    update public.os_planejamento set entrada_em = date '2027-07-20', entrada_fonte = 'cliente' where service_order_id = pg_temp.os('OS-J7');
    perform pg_temp.plan('OS-J7', '{"chega_em": "dia 20"}'::jsonb, 'chega dia 20 mesmo');
    perform pg_temp.grava();
    r := public.agenda_desfazer((pg_temp.acao('OS-J7')).id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4y a mesma data, outra fonte: o *desfaz* devolve a fonte', (pg_temp.pl('OS-J7')).entrada_fonte = 'cliente', r::text);
    -- a mesma lista, com a linha mudada por dentro: o *desfaz* devolve a linha
    insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho)
    values (pg_temp.os('OS-J10'), pg_temp.pessoa('Roberto'), pg_temp.local('Tedesco Marina Garden Plaza'), date '2027-08-01', 'cliente', 'o cliente disse');
    v_aut := pg_temp.aut('OS-J10');
    perform pg_temp.plan('OS-J10', '{"autorizados": ["Roberto"]}'::jsonb, 'o Roberto está autorizado');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R4z1 a mesma pessoa: a linha passa a ser a do dono', pg_temp.aut('OS-J10') is distinct from v_aut and (select x.fonte from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J10')) = 'dono', pg_temp.aut('OS-J10'));
    r := public.agenda_desfazer((pg_temp.acao('OS-J10')).id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4z a mesma lista, a linha mudada por dentro: o *desfaz* devolve a linha inteira (validade, local, fonte, trecho, quando)', (r ->> 'ok')::boolean and pg_temp.aut('OS-J10') = v_aut, pg_temp.aut('OS-J10') || ' ≠ ' || v_aut);
    -- dizer de novo a lista que já está: nada muda, nem ação nasce
    perform pg_temp.plan('OS-J9', '{"autorizados": ["João"]}'::jsonb, 'o João está autorizado');
    perform pg_temp.grava();
    v_aut := pg_temp.aut('OS-J9');
    a := pg_temp.acao('OS-J9');
    perform pg_temp.plan('OS-J9', '{"autorizados": ["João"]}'::jsonb, 'o João está autorizado, sim');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R4aa dizer de novo a mesma lista não mexe na linha e não vira ação nova', pg_temp.aut('OS-J9') = v_aut and (pg_temp.acao('OS-J9')).id = a.id, pg_temp.aut('OS-J9'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  -- O histórico até 20
  begin
    perform pg_temp.base('sombra');
    for i in 1 .. 25 loop
      perform pg_temp.plan('OS-J12', jsonb_build_object('descer_quem', 'pessoa ' || i), 'quem desce é a pessoa ' || i);
      perform pg_temp.grava();
    end loop;
    v_res := pg_temp.ok(v_res, 'R4u histórico até 20: as 20 mais novas', jsonb_array_length((pg_temp.pl('OS-J12')).historico) = 20 and (pg_temp.pl('OS-J12')).historico -> -1 -> 'depois' ->> 'descer_quem' = 'pessoa 25'
      and (pg_temp.pl('OS-J12')).historico -> 0 -> 'depois' ->> 'descer_quem' = 'pessoa 6', (pg_temp.pl('OS-J12')).historico::text);
    a := pg_temp.acao('OS-J12');
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'R4v o *desfaz* da última passa, com o histórico cheio, e o histórico segue em 20', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J12')).descer_quem = 'pessoa 24' and jsonb_array_length((pg_temp.pl('OS-J12')).historico) = 20, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
  end;
end
$r4$;

-- ── R5. Em teste: grava, e o motor não muda ─────────────────────────────────────────
do $r5$
declare
  v_res  jsonb := '[]'::jsonb;
  c      record;
  v_oss  uuid[];
  v_a    text;
  v_b    text;
  r      jsonb;
  v_d    constant jsonb := '{"local": "Marina Itajaí", "bem_onde": "seco", "bem_exige": "agua", "descer_quem": "a marina", "chega_em": "dia 26", "sai_em": "dia 30", "viagem": "pernoite", "autorizados": ["João"]}';
  c_tr   constant text := 'na Marina Itajaí, em seco, teste na água, quem desce é a marina, chega dia 26 e sai dia 30, dormindo lá, João autorizado';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R5 em teste', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_oss := array(select so.id from public.service_orders so where so.service_order_number ~ '^OS-(J|D)[0-9]+$' or so.service_order_number like 'OS-9717_' order by 1);
  for c in select * from (values ('sombra', 'sombra'), ('desligado', 'desligado')) t(nome, modo) loop
    begin
      perform pg_temp.gestor();
      perform pg_temp.base(c.modo);
      v_a := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    begin
      perform pg_temp.gestor();
      perform pg_temp.base(c.modo);
      r := pg_temp.plan('OS-J3', v_d, c_tr);
      r := pg_temp.plan('OS-J12', '{"local": "pátio", "viagem": "bate_volta"}'::jsonb, 'no pátio, ida e volta') || jsonb_build_object('j3', r);
      r := r || jsonb_build_object('grava', pg_temp.grava());
      v_res := pg_temp.ok(v_res, format('R5a com os 6 modos em %s, o *grava* grava o que o dono disse: ele é a fonte', c.nome),
        (r -> 'grava' ->> 'ok')::boolean and (pg_temp.pl('OS-J3')).local_fonte = 'dono' and (pg_temp.pl('OS-J3')).viagem = 'pernoite' and (pg_temp.pl('OS-J3')).entrada_em = date '2027-07-26'
        and pg_temp.vig('OS-J3') = 'João', r::text);
      v_b := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_res := pg_temp.ok(v_res, format('R5b com os 6 modos em %s, agenda_propor (semana e OS), o contexto, os itens e as perguntas: md5 igual antes e depois de gravar', c.nome),
      v_a is not distinct from v_b, v_a || ' ≠ ' || v_b);
  end loop;

  -- O contraste: a mesma gravação com o modo ligado muda o motor. Sem isso, o R5b não provaria nada.
  begin
    perform pg_temp.gestor();
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_viagem', 'ligado');
    v_a := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.gestor();
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_viagem', 'ligado');
    perform pg_temp.plan('OS-J3', v_d, c_tr);
    perform pg_temp.grava();
    v_b := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R5c o contraste: com modo_viagem ligado, a mesma gravação muda agenda_propor', v_a is distinct from v_b, v_a);

  -- O freio: ligado + freio = em teste (R6.7b); a palavra do dono grava igual
  begin
    perform pg_temp.gestor();
    perform pg_temp.base('ligado');
    update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = timestamptz '2027-07-15 23:43-03' where id;
    v_a := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.gestor();
    perform pg_temp.base('ligado');
    update public.agenda_config set gestor_so_propor = true, gestor_so_propor_em = timestamptz '2027-07-15 23:43-03' where id;
    perform pg_temp.plan('OS-J3', v_d, c_tr);
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R5d com *gestor, só propor*, o *grava* grava', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J3')).viagem = 'pernoite', r::text);
    v_b := pg_temp.retrato(date '2027-07-16', v_oss, date '2027-07-12');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R5e os 6 ligados + freio = em teste (R6.7b): a gravação não muda agenda_propor, md5 igual', v_a is not distinct from v_b, v_a || ' ≠ ' || v_b);
  perform pg_temp.gravar(v_res);
end
$r5$;

-- ── R6. O dono vence ────────────────────────────────────────────────────────────────
do $r6$
declare
  v_res jsonb := '[]'::jsonb;
  q     public.agenda_perguntas;
  q2    public.agenda_perguntas;
  r     jsonb;
  r2    jsonb;
  a     public.agenda_acoes;
  v_ag  timestamptz := pg_temp.em(date '2027-07-16', '18:00');
  v_h   constant date := date '2027-07-16';
  c_d   constant text := 'na marina itajai, fica na garagem, quem desce é a marina';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R6 o dono vence', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    q := pg_temp.pergunta_local('OS-J2', c_d);
    v_res := pg_temp.ok(v_res, 'R6a a pergunta local nasceu do M11 de verdade, com a leitura', q.estado = 'aberta' and q.opcoes -> 0 #>> '{efeito,item,local_nome}' = 'Marina Itajaí', to_jsonb(q)::text);
    perform pg_temp.plan('OS-J2', '{"local": "Tedesco"}'::jsonb, 'o barco do Nelson está na Tedesco');
    v_res := pg_temp.ok(v_res, 'R6b no rascunho, ela segue aberta: só o *grava* vale', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta', null);
    r := pg_temp.grava(v_h, '18:00');
    select * into q2 from public.agenda_perguntas x where x.id = q.id;
    v_res := pg_temp.ok(v_res, 'R6c o *grava* fecha a pergunta: resolvida, "você disse onde é", sem opção escolhida', (r ->> 'ok')::boolean and q2.estado = 'resolvida' and q2.resolvida_motivo = 'você disse onde é' and q2.opcao_escolhida is null, to_jsonb(q2)::text);
    v_res := pg_temp.ok(v_res, 'R6d ela sai da lista de decisões', (select count(*) from jsonb_array_elements(public.agenda_decisoes_abertas(v_ag)) e where e ->> 'tipo' = 'local') = 0, null);
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, v_ag);
    v_res := pg_temp.ok(v_res, 'R6e o sim dela não sobrescreve: recusa, e o dono vence', not (r ->> 'ok')::boolean and r ->> 'texto' = 'Essa pergunta já foi respondida ou resolvida.'
      and (pg_temp.pl('OS-J2')).local_id = pg_temp.local('Tedesco Marina Garden Plaza') and (pg_temp.pl('OS-J2')).local_fonte = 'dono' and (pg_temp.pl('OS-J2')).bem_situacao is null, r::text);
    r := public.agenda_rascunho_aplicar(pg_temp.adm(), 'whatsapp', null, null, '1', '1', '1', v_h, v_ag);
    v_res := pg_temp.ok(v_res, 'R6f "1" pela conversa: não tem mais o que responder', not (r ->> 'ok')::boolean and r ->> 'motivo' = 'sem_decisao', r::text);
    -- O *desfaz*: o local volta e a pergunta espera de novo
    a := pg_temp.acao('OS-J2');
    v_res := pg_temp.ok(v_res, 'R6g a ação guarda a pergunta que fechou', a.depois -> 'perguntas_fechadas' = jsonb_build_array(q.id), a.depois::text);
    r := pg_temp.desfaz('OS-J2', v_h, '18:30');
    select * into q2 from public.agenda_perguntas x where x.chave = q.chave and x.estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'R6h o *desfaz* volta o local e devolve a pergunta: outra linha, com o mesmo texto, as mesmas opções e o mesmo prazo',
      (r -> 'gravou' ->> 'ok')::boolean and (pg_temp.pl('OS-J2')).local_id is null and q2.id is not null and q2.id <> q.id and q2.texto = q.texto and q2.opcoes = q.opcoes and q2.recomendacao = q.recomendacao
      and q2.expira_em = q.expira_em and q2.modo = q.modo and q2.tipo = 'local', r::text);
    v_res := pg_temp.ok(v_res, 'R6i a de antes fica como foi: fechada não muda', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'resolvida', null);
    r := public.agenda_decidir(q2.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, pg_temp.em(v_h, '18:40'));
    v_res := pg_temp.ok(v_res, 'R6j e aí o sim dela vale: grava o que o cliente disse', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J2')).local_id = pg_temp.local('Marina Itajaí') and (pg_temp.pl('OS-J2')).local_fonte = 'cliente', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    q := pg_temp.pergunta_local('OS-J2', c_d);
    perform pg_temp.plan('OS-J2', '{"local": "casa do cliente"}'::jsonb, 'está na casa do cliente');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6k a casa do cliente também é dizer onde é: fecha', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'resolvida', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    q := pg_temp.pergunta_local('OS-J2', c_d);
    perform pg_temp.plan('OS-J2', '{"bem_onde": "agua"}'::jsonb, 'está na água');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6l a situação que a pergunta gravaria também fecha: o sim a sobrescreveria', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'resolvida', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    q := pg_temp.pergunta_local('OS-J2', c_d);
    perform pg_temp.plan('OS-J2', '{"descer_quem": "o marinheiro"}'::jsonb, 'quem desce é o marinheiro');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6m quem desce que a pergunta gravaria também fecha', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'resolvida', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    -- A leitura só achou o local: o que ele disser do bem não colide, e ela segue
    q := pg_temp.pergunta_local('OS-J2', 'na marina itajai');
    v_res := pg_temp.ok(v_res, 'R6n a leitura só com o local', q.opcoes -> 0 #>> '{efeito,item,local_nome}' = 'Marina Itajaí' and q.opcoes -> 0 #>> '{efeito,item,situacao}' is null and q.opcoes -> 0 #>> '{efeito,item,descer_quem}' is null, to_jsonb(q)::text);
    perform pg_temp.plan('OS-J2', '{"bem_onde": "agua", "descer_quem": "o marinheiro", "viagem": "regional"}'::jsonb, 'na água, quem desce é o marinheiro');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6o o que a pergunta não gravaria não a fecha: o sim dela não colide', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta', null);
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', v_h, v_ag);
    v_res := pg_temp.ok(v_res, 'R6p o sim grava só o local, e o que o dono disse fica', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J2')).local_fonte = 'cliente' and (pg_temp.pl('OS-J2')).bem_situacao = 'agua' and (pg_temp.pl('OS-J2')).bem_situacao_fonte = 'dono' and (pg_temp.pl('OS-J2')).descer_quem = 'o marinheiro', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    q := pg_temp.pergunta_local('OS-J2', c_d);
    perform pg_temp.plan('OS-J2', '{"limpar": ["local"]}'::jsonb, 'tira o local');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6q "tirei o local" não diz onde é: ela fica', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta', null);
    perform pg_temp.plan('OS-J12', '{"local": "Tedesco"}'::jsonb, 'na Tedesco');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6r a pergunta de outra OS não fecha', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    -- Sem leitura: ela pede "me diga onde é", e a resposta do exemplo do motorhome é a chegada
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where service_order_id = pg_temp.os('OS-J11');
    q := pg_temp.pergunta_local('OS-J11', 'na marina do joão');
    v_res := pg_temp.ok(v_res, 'R6s a pergunta sem leitura', q.estado = 'aberta' and q.opcoes -> 0 #> '{efeito,item}' is null, to_jsonb(q)::text);
    perform pg_temp.plan('OS-J11', '{"chega_em": "dia 20"}'::jsonb, 'o motorhome da Carla chega dia 20');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6t a chegada responde a sem leitura', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'resolvida', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    q := pg_temp.pergunta_local('OS-J2', c_d);
    -- a pergunta vence antes do *desfaz*: o local volta, e a pergunta, não
    update public.agenda_perguntas set expira_em = pg_temp.em(v_h, '18:10') where id = q.id;
    perform pg_temp.plan('OS-J2', '{"local": "Tedesco"}'::jsonb, 'na Tedesco');
    perform pg_temp.grava(v_h, '18:00');
    r := public.agenda_desfazer((pg_temp.acao('OS-J2')).id, pg_temp.adm(), 'dono', v_h, pg_temp.em(v_h, '18:20'));
    v_res := pg_temp.ok(v_res, 'R6u a pergunta que já venceu não volta; o local volta', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J2')).local_id is null
      and not exists (select 1 from public.agenda_perguntas x where x.chave = q.chave and x.estado = 'aberta'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    q := pg_temp.pergunta_local('OS-J2', c_d);
    perform pg_temp.plan('OS-J2', '{"chega_em": "dia 20"}'::jsonb, 'chega dia 20');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6ag com leitura, a chegada não fecha: o sim não grava chegada nenhuma', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where service_order_id = pg_temp.os('OS-J11');
    q := pg_temp.pergunta_local('OS-J11', 'na marina do joão');
    perform pg_temp.plan('OS-J11', '{"bem_onde": "patio"}'::jsonb, 'está no pátio');
    perform pg_temp.grava(v_h, '18:00');
    v_res := pg_temp.ok(v_res, 'R6ah o bem também responde a sem leitura', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'resolvida', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.prepara();
    perform pg_temp.j2_sem_situacao();
    q := pg_temp.pergunta_local('OS-J2', c_d);
    -- O local já é o que o dono diz: nenhuma coluna muda, a pergunta fecha, e a ação existe para o *desfaz* devolvê-la
    update public.os_planejamento set local_id = pg_temp.local('Tedesco Marina Garden Plaza'), local_fonte = 'dono', local_em = v_ag where service_order_id = pg_temp.os('OS-J2');
    perform pg_temp.plan('OS-J2', '{"local": "Tedesco"}'::jsonb, 'na Tedesco, como eu disse');
    perform pg_temp.grava(v_h, '18:00');
    a := pg_temp.acao('OS-J2');
    v_res := pg_temp.ok(v_res, 'R6ai sem coluna mudada, a pergunta fecha e a ação nasce para devolvê-la', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'resolvida' and a.id is not null and a.depois -> 'perguntas_fechadas' = jsonb_build_array(q.id), null);
    r := public.agenda_desfazer(a.id, pg_temp.adm(), 'dono', v_h, pg_temp.em(v_h, '18:20'));
    v_res := pg_temp.ok(v_res, 'R6aj e o *desfaz* a devolve', (r ->> 'ok')::boolean and (select count(*) from public.agenda_perguntas x where x.chave = q.chave and x.estado = 'aberta') = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  -- A combinar e a acesso: o equivalente. O sim delas é a palavra do próprio dono, com a data escrita, mas o que ele disse pode já ter resolvido: fecha na hora, não no tique.
  begin
    perform pg_temp.oito();
    perform pg_temp.base('ligado');
    perform set_config('agenda.hoje', '2027-07-19', true);
    perform public._agenda_local_combinar(date '2027-07-19', pg_temp.em(date '2027-07-19', '16:20'));
    select * into q from public.agenda_perguntas x where x.chave like 'combinar:entrada:' || pg_temp.os('OS-J1') || ':%' and x.estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'R6v a combinar da entrada está aberta', q.id is not null, null);
    perform pg_temp.plan('OS-J1', '{"chega_em": "hoje"}'::jsonb, 'o motorhome do Lenine chega hoje', date '2027-07-19');
    r := pg_temp.grava(date '2027-07-19', '16:30');
    select * into q2 from public.agenda_perguntas x where x.id = q.id;
    v_res := pg_temp.ok(v_res, 'R6w a chegada dita resolve a combinar na hora, sem esperar o tique, pelo mesmo resolvedor', (r ->> 'ok')::boolean and q2.estado = 'resolvida' and q2.resolvida_motivo = 'já foi combinado', to_jsonb(q2)::text);
    r := public.agenda_decidir(q.id, 1::smallint, pg_temp.adm(), 'whatsapp', '1', date '2027-07-19', pg_temp.em(date '2027-07-19', '16:40'));
    v_res := pg_temp.ok(v_res, 'R6x o sim dela não troca a data que o dono disse', not (r ->> 'ok')::boolean and (pg_temp.pl('OS-J1')).entrada_em = date '2027-07-19', r::text);
    a := pg_temp.acao('OS-J1');
    v_res := pg_temp.ok(v_res, 'R6y a ação guarda a combinar que fechou', a.depois -> 'perguntas_fechadas' = jsonb_build_array(q.id), a.depois::text);
    r := pg_temp.desfaz('OS-J1', date '2027-07-19', '16:50');
    v_res := pg_temp.ok(v_res, 'R6z o *desfaz* devolve a combinar', (r -> 'gravou' ->> 'ok')::boolean and (pg_temp.pl('OS-J1')).entrada_em is null
      and (select count(*) from public.agenda_perguntas x where x.chave = q.chave and x.estado = 'aberta') = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.base('ligado');
    perform set_config('agenda.hoje', '2027-07-19', true);
    perform public._agenda_local_combinar(date '2027-07-19', pg_temp.em(date '2027-07-19', '16:20'));
    select * into q from public.agenda_perguntas x where x.chave like 'combinar:entrada:' || pg_temp.os('OS-J1') || ':%' and x.estado = 'aberta';
    -- Depois do 1º dia, a chegada não combina nada: a pergunta fica, e ela é do próprio dono, com a data escrita
    perform pg_temp.plan('OS-J1', '{"chega_em": "dia 22"}'::jsonb, 'o motorhome do Lenine chega dia 22', date '2027-07-19');
    perform pg_temp.grava(date '2027-07-19', '16:30');
    v_res := pg_temp.ok(v_res, 'R6aa a chegada depois do 1º dia não resolve: a combinar fica aberta', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta' and (pg_temp.pl('OS-J1')).entrada_em = date '2027-07-22', null);
    r := public.agenda_decidir(q.id, 2::smallint, pg_temp.adm(), 'whatsapp', '2', date '2027-07-19', pg_temp.em(date '2027-07-19', '16:40'));
    v_res := pg_temp.ok(v_res, 'R6ab "ainda não" não mexe no que ele disse', (r ->> 'ok')::boolean and (pg_temp.pl('OS-J1')).entrada_em = date '2027-07-22', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  begin
    perform pg_temp.oito();
    perform pg_temp.base('ligado');
    -- A crítica de D-1: a Marina Itajaí exige autorização nominal, e J2 (Roberto e João) só tem o Roberto
    perform set_config('agenda.hoje', '2027-07-19', true);
    perform public._agenda_local_combinar(date '2027-07-19', pg_temp.em(date '2027-07-19', '16:20'));
    select * into q from public.agenda_perguntas x where x.chave like 'acesso:' || pg_temp.os('OS-J2') || ':%' and x.estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'R6ac a crítica acesso está aberta', q.id is not null, null);
    perform pg_temp.plan('OS-J2', '{"autorizados": ["Roberto", "João"]}'::jsonb, 'o Roberto e o João estão autorizados', date '2027-07-19');
    r := pg_temp.grava(date '2027-07-19', '16:30');
    select * into q2 from public.agenda_perguntas x where x.id = q.id;
    v_res := pg_temp.ok(v_res, 'R6ad os autorizados ditos resolvem a crítica na hora', (r ->> 'ok')::boolean and q2.estado = 'resolvida' and q2.resolvida_motivo = 'a autorização foi anotada', to_jsonb(q2)::text);
    r := pg_temp.desfaz('OS-J2', date '2027-07-19', '16:50');
    v_res := pg_temp.ok(v_res, 'R6ae o *desfaz* devolve a crítica, com a recomendação', (r -> 'gravou' ->> 'ok')::boolean and pg_temp.vig('OS-J2') = 'Roberto'
      and (select x.recomendacao from public.agenda_perguntas x where x.chave = q.chave and x.estado = 'aberta') = q.recomendacao, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;

  -- Sem pergunta aberta da OS, o resolvedor nem é chamado: o *grava* não varre as perguntas de todo mundo
  begin
    perform pg_temp.base('sombra');
    execute $s$create or replace function public._agenda_local_resolver(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $b$ begin raise exception 'não devia rodar'; end $b$;$s$;
    perform pg_temp.plan('OS-J12', '{"viagem": "regional"}'::jsonb, 'é aqui na região');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R6af sem combinar nem acesso aberta da OS, o resolvedor não roda', (r ->> 'ok')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
  end;
end
$r6$;

-- ── R7. A linha que mistura ─────────────────────────────────────────────────────────
do $r7$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  r2    jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R7 a linha que mistura', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.oito();
    perform pg_temp.base('sombra');
    r := pg_temp.plan('OS-J12', '{"dias": 2, "precisa_ate": "dia 30", "local": "Tedesco", "viagem": "regional"}'::jsonb, 'são 2 dias, ele precisa até dia 30, na Tedesco, aqui na região');
    v_res := pg_temp.ok(v_res, 'R7a a frase de sempre primeiro, com o ponto, e as linhas novas depois',
      (r ->> 'releitura') like E'%• Beto (OS-J12): 2 dias; o cliente precisa até sex 30/07.\nLocal: Tedesco Marina Garden Plaza.\nSem viagem (aqui na região).\n%', r::text);
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R7b os campos de antes e os novos gravam juntos', (r2 ->> 'ok')::boolean and (pg_temp.pl('OS-J12')).dias = 2 and (pg_temp.pl('OS-J12')).precisa_ate = date '2027-07-30'
      and (pg_temp.pl('OS-J12')).local_fonte = 'dono' and (pg_temp.pl('OS-J12')).viagem = 'regional', r2::text);
    -- O prometido sozinho volta cedo, em _agenda_aplicar_planejar: com o local na mesma linha, a volta perderia o local
    r := pg_temp.plan('OS-J11', '{"prometido": "dia 20", "local": "Tedesco"}'::jsonb, 'falei que é dia 20, na Tedesco');
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R7c o prometido e o local na mesma linha: os dois gravam', (r2 ->> 'ok')::boolean and (pg_temp.pl('OS-J11')).prometido_ate = date '2027-07-20' and (pg_temp.pl('OS-J11')).local_id = pg_temp.local('Tedesco Marina Garden Plaza'), r2::text);
    r := pg_temp.plan('OS-J9', '{"prometido": "dia 20", "dupla": "nao", "viagem": "pernoite"}'::jsonb, 'falei que é dia 20, vai com um só, a gente dorme lá');
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R7d o prometido, a dupla e a viagem na mesma linha: os três gravam', (r2 ->> 'ok')::boolean and (pg_temp.pl('OS-J9')).prometido_ate = date '2027-07-20' and (pg_temp.pl('OS-J9')).dupla_dita = 'nao' and (pg_temp.pl('OS-J9')).viagem = 'pernoite', r2::text);
    r := pg_temp.plan('OS-J8', '{"prometido": "dia 20"}'::jsonb, 'falei que é dia 20');
    v_res := pg_temp.ok(v_res, 'R7e a linha só com o prometido: a releitura de antes', (r ->> 'releitura') like '%: você disse ao Tiago: ter 20/07 (data firme).%', r::text);
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R7f e sem ação nova: as linhas de antes não têm *desfaz*', (r2 ->> 'ok')::boolean and not exists (select 1 from public.agenda_acoes x where x.service_order_id = pg_temp.os('OS-J8') and x.tipo = 'local'), r2::text);
    r := pg_temp.plan('OS-J7', '{"dias": 2}'::jsonb, 'são 2 dias');
    v_res := pg_temp.ok(v_res, 'R7g a linha só com os campos de antes: a releitura de antes, sem ponto a mais no meio', (r ->> 'releitura') like E'%• Sílvio (OS-J7): 2 dias.\nResponda%', r::text);
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'R7h sem ação', not exists (select 1 from public.agenda_acoes x where x.service_order_id = pg_temp.os('OS-J7') and x.tipo = 'local'), null);
    perform public._agenda_aplicar_planejar(pg_temp.adm(), pg_temp.os('OS-J6'), '{"dias": 4, "estimativa_fonte": "dono"}'::jsonb, 'Duração corrigida pela tela', date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'R7i a tela (dias) passa pelo mesmo caminho, sem ação', (pg_temp.pl('OS-J6')).dias = 4 and not exists (select 1 from public.agenda_acoes x where x.service_order_id = pg_temp.os('OS-J6') and x.tipo = 'local'), null);
    r := pg_temp.plan('OS-J5', '{"limpar": ["local", "espera"]}'::jsonb, 'tira o local e pode voltar');
    v_res := pg_temp.ok(v_res, 'R7j o limpar novo e o de antes na mesma lista', (r ->> 'releitura') like E'%sai da espera.\nTirei o local que eu tinha (volto a supor).\n%', r::text);
    r := pg_temp.plan('OS-J4', '{"dupla": "todos", "viagem": "regional"}'::jsonb, 'precisa de dois, aqui na região');
    v_res := pg_temp.ok(v_res, 'R7k a dupla com o aviso de pouca gente segue antes das linhas novas', (r ->> 'ok')::boolean and (r ->> 'releitura') like '%vai em dupla o tempo todo%' and (r ->> 'releitura') like E'%\nSem viagem (aqui na região).%', r::text);
    v_res := pg_temp.ok(v_res, 'R7l com o aviso da dupla, a frase de antes inteira, o ponto e as linhas novas',
      public._agenda_rascunho_frase('planejar', jsonb_build_object('dupla', 'todos', 'dupla_aviso', 'Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine', 'viagem', 'regional'))
      = E'vai em dupla o tempo todo. Hoje só Alex está na equipe: até você chamar alguém e me dizer os dias, eu não marco Lenine.\nSem viagem (aqui na região).', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    perform pg_temp.gravar(v_res);
    v_res := '[]'::jsonb;
  end;
end
$r7$;

select * from _resultado order by teste collate "C";
rollback;
