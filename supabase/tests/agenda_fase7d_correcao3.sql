-- Prova da correção da 7d, Onda 3, da Agenda de Produção (o fecho da 2ª revisão; migration 20261107100860; decisoes-do-fio.md, seção Onda 3). Um bloco por item: cada um falha sem a migration e passa com
-- ela (o "antes" está nas notas). As tabelas de frases são as dos revisores (f7d/rev2-objetivo/achados.md, item 3; f7d/rev2-regressao/o2.out). Tudo pelo caminho real: agenda_rascunho_planejar → *grava* → *desfaz*;
-- agenda_resposta_do_cliente; agenda_entregar_dito → agenda_vigiar → agenda_desfazer_dito.
-- bancada: depende de 20261107100860
--
--   T0   as portas das 4 novas e as cópias: tirados os blocos, a origem; nenhuma estrutura; o que a sessão do retorno e o dinheiro chamam fica de fora
--   T4   *agenda pendências*: o corte não esconde: a última linha diz o que ficou de fora, dentro das 1.800 letras
--   T5   lugar fora do cadastro com o cadastro vazio: recusa como antes
--   T6   o aviso do acesso que nasce recusado não conta e vai a app_error_logs
--   G6   o detector de lugar novo (T8): recados, estados, data, o nome inteiro, Balneário e BC, a UF no fim, a casa do cliente, corrigir limpa
--   T10  a região não some sem cliente naquela cidade
--   T11  o *desfaz* e a limpeza tomam a trava de _agenda_local_criar
--   T7   as datas (G10, G11): a oração da data, a negação, os 7 dias, a saída no passado
--   G7   resposta ao M11 com cidade
--   G5   *desfaz OS-…* depois do tique volta a entrega junto
--
-- T1, T2, T3 e T9 (a trava do "1") não têm banco: _shared/ai/whatsapp-channel_test.ts e ai-agent/index_test.ts. O prompt: prompt-ferramentas_test.ts e os evals.
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
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro int := 0;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if v_dentro = 0 and l ~ '^\s*-- FASE 7d:' and l !~ '^\s*-- FASE 7d: fim' then v_dentro := 1; continue; end if;
    if v_dentro = 1 and l ~ '^\s*-- FASE 7d: fim' then v_dentro := 0; continue; end if;
    if v_dentro = 0 and l ~ '^\s*-- \(7d ' then v_dentro := 2; continue; end if;
    if v_dentro = 2 and l ~ '^\s*-- \(7d: fim\)' then v_dentro := 0; continue; end if;
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

-- ── T0. As portas e as cópias ─────────────────────────────────────────────────────────────
with f(sig, vol) as (values
  ('public._agenda_local_recolher(uuid,uuid)', 'v'),
  ('public._agenda_data_no_passado(text,text,text)', 'i'))
insert into _resultado
select 'T0a as 2 internas: invoker, a volatilidade, search_path fixo, e ninguém de fora (nem o service_role): quem chama é definer',
       count(p.oid) = 2
       and bool_and(not p.prosecdef and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and not has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(f.sig, '; ') filter (where p.oid is null)
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

insert into _resultado
select 'T0a2 as 2 de apoio seguem com agenda_resolver_local, que é invoker: authenticated e service_role sim, anon e public não',
       count(p.oid) = 2
       and bool_and(not p.prosecdef and p.provolatile = 'i' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute')
                    and has_function_privilege('service_role', p.oid, 'execute')), null
  from unnest(array['public._agenda_uf_dita(text)', 'public._agenda_local_sem_uf(text)']) s(sig) left join pg_proc p on p.oid = to_regprocedure(s.sig);

insert into _resultado
select 'T0b rodando: anon não alcança; o técnico alcança a leitura do lugar e não o que recolhe',
       pg_temp.como('anon', $q$select public._agenda_uf_dita('sc')$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public._agenda_local_sem_uf('x')::text$q$) like 'erro 42501%'
       and pg_temp.como('authenticated', $q$select public._agenda_uf_dita('sc')$q$) = 'SC'
       and pg_temp.como('authenticated', $q$select public._agenda_local_recolher(gen_random_uuid(), null)::text$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_data_no_passado('a', 'b', 'chega')::text$q$) like 'erro 42501%', null;

do $t0$
declare
  c      record;
  v_viva text;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_correcao3_fase7d', true), '');
begin
  if v_mig = '' then
    insert into _resultado values ('T0d as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)');
    return;
  end if;
  -- As funções que vêm de antes da 7d: tirados os blocos, a origem (a definição mais nova).
  for c in select * from (values
      ('_agenda_ver_decisoes', 'mig_correcao2_fase7d'), ('agenda_rascunho_planejar', 'mig_correcao2_fase7d'), ('_agenda_aplicar_planejar', 'mig_correcao_fase7d'),
      ('agenda_desfazer', 'mig_combinar_fase7d')) t(nome, fonte) loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_viva from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = c.nome;
    -- (correção da 7d, Onda 4) agenda_rascunho_planejar, _agenda_aplicar_planejar e agenda_desfazer passaram a viver na 20261107100870: a viva é a da migration mais nova que a define
    insert into _resultado values ('T0d ' || c.nome || ': a viva é a da migration; sem os blocos, a origem, byte a byte',
      v_viva = coalesce(nullif(pg_temp.corpo(coalesce(current_setting('agenda_teste.mig_correcao4_fase7d', true), ''), c.nome), ''), pg_temp.corpo(v_mig, c.nome)) and pg_temp.sem_7d(v_viva) = pg_temp.sem_7d(pg_temp.corpo(current_setting('agenda_teste.' || c.fonte), c.nome)), null);
  end loop;
  insert into _resultado values ('T0e a sessão do retorno, a data dita e o dinheiro ficam de fora: agenda_data_dita, _agenda_data_um, _agenda_data_conferida, _agenda_chave_telefone, agenda_dia_util, agenda_somar_du, agenda_feriado, _agenda_cliente_dia, _agenda_nome_curto, _agenda_desfazer_marco, os_registrar_marco',
    v_mig !~ 'function public\.(agenda_data_dita|_agenda_data_um|_agenda_data_conferida|_agenda_chave_telefone|agenda_dia_util|agenda_somar_du|agenda_feriado|_agenda_cliente_dia|_agenda_nome_curto|_agenda_desfazer_marco|os_registrar_marco|handle_quote_deposit_payment)\(', null);
  insert into _resultado values ('T0f só funções: nenhuma tabela, coluna, índice, gatilho nem dado na migration',
    v_mig !~* '(^|\n)\s*(alter table|create table|create index|create unique index|create trigger|drop )', null);
end
$t0$;

-- ── T4 (O8). O corte não esconde ────────────────────────────────────────────────────────────
do $t4$
declare
  v_res  jsonb := '[]'::jsonb;
  c_ops  constant jsonb := '[{"n":1,"texto":"Está certo (recomendo)"},{"n":2,"texto":"Mudou"}]';
  c_txt  constant text := 'Uma pergunta da agenda com umas cento e vinte letras, para a soma passar das mil letras do teto dos outros focos sem cortar nada aqui.';
  v      jsonb;
  v_t    text;
  v_ult  text;
  k      int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T4', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('equipe_cadastro', 't4:1', 'Decida a primeira. 1) Está certo; 2) Mudou.', c_ops);
    for k in 1 .. 16 loop
      perform pg_temp.perg('bem_livre', 't4:sem:' || k, format('Sem número %s, a história dela. ', k) || c_txt, '[]'::jsonb, null, date '2027-07-01' + k);
    end loop;
    v := pg_temp.ver();
    v_t := v ->> 'texto';
    v_ult := (regexp_match(v_t, E'[^\n]*$'))[1];
    v_res := pg_temp.ok(v_res, 'T4a no corte, a última linha diz o que ficou de fora, pelo título curto, e cabe nas 1.800 letras',
      char_length(v_t) <= 1800 and v_ult like 'Também esperam: Sem número %, a história dela; %' and v_ult like '%Sem número 16, a história dela.', char_length(v_t)::text || ' ' || v_ult);
    v_res := pg_temp.ok(v_res, 'T4b sai o "Para ver por assunto" e o "(e mais N linhas)": nada some sem nome', v_t not like '%por assunto%' and v_t not like '%(e mais%', null);
    v_res := pg_temp.ok(v_res, 'T4c cada pergunta aparece uma vez: inteira ou pelo título', (select count(*) from regexp_matches(v_t, 'Sem número \d+, a história dela', 'g')) = 16, null);
    v_res := pg_temp.ok(v_res, 'T4d as linhas que ficam são inteiras', v_t like '%Também quero saber: Sem número 1, a história dela. ' || c_txt || '%', null);
    v_res := pg_temp.ok(v_res, 'T4e dados segue com todas', jsonb_array_length(v #> '{dados,abertas}') = 16, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T4a quebrou', false, sqlerrm);
  end;
  -- A linha do fim também conta: tirar uma a uma até caber, com ela dentro
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('equipe_cadastro', 't4:1', 'Decida. 1) Está certo; 2) Mudou.', c_ops);
    for k in 1 .. 9 loop
      perform pg_temp.perg('bem_livre', 't4:sem:' || k, format('Sem número %s. ', k) || repeat('Texto da pergunta. ', 9), '[]'::jsonb, null, date '2027-07-01' + k);
    end loop;
    v_t := pg_temp.ver() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'T4f a conta inclui a linha do fim', char_length(v_t) <= 1800 and char_length(array_to_string((string_to_array(v_t, E'\n'))[1:cardinality(string_to_array(v_t, E'\n')) - 1], E'\n')) > 1000 and v_t like '%Também esperam: %', char_length(v_t)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T4f quebrou', false, sqlerrm);
  end;
  -- Sem corte, sem a linha; só decisões grandes: não há "Também quero saber" a tirar, o corte de sempre
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('bem_livre', 't4:um', 'Uma só. ' || c_txt, '[]'::jsonb);
    v_t := pg_temp.ver() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'T4g sem corte, sem a linha do fim', v_t not like '%Também esperam%', null);
    perform pg_temp.limpa();
    for k in 1 .. 14 loop
      perform pg_temp.perg('equipe_cadastro', 't4:dec:' || k, format('Decisão grande %s. ', k) || repeat('Texto grande de decisão. ', 9) || '1) Está certo; 2) Mudou.', c_ops);
    end loop;
    v_t := pg_temp.ver() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'T4h só decisões: o corte de sempre, no teto', char_length(v_t) <= 1800 and v_t ~ '\(e mais \d+ linhas?\)$' and v_t not like '%Também esperam%', char_length(v_t)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T4g quebrou', false, sqlerrm);
  end;
  -- Títulos demais: a linha do fim tem teto, e o texto fica nas 1.800
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    perform pg_temp.perg('equipe_cadastro', 't4:1', 'Decida. ' || repeat('Texto grande de decisão. ', 20) || '1) Está certo; 2) Mudou.', c_ops);
    for k in 1 .. 40 loop
      perform pg_temp.perg('bem_livre', 't4:sem:' || k, format('Pergunta %s com um título bem comprido, que vai até o corte das noventa letras do título curto', k), '[]'::jsonb, null, date '2027-07-01' + k);
    end loop;
    v_t := pg_temp.ver() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'T4j 40 perguntas de fora: a linha do fim tem teto, e o foco fica nas 1.800', char_length(v_t) <= 1800 and v_t like '%Decida.%' and v_t like '%Também esperam: %', char_length(v_t)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T4j quebrou', false, sqlerrm);
  end;
  -- Decisões grandes e a linha do fim: o que sobra é cortado para ela caber
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.limpa();
    for k in 1 .. 14 loop
      perform pg_temp.perg('equipe_cadastro', 't4:dec:' || k, format('Decisão grande %s. ', k) || repeat('Texto grande de decisão. ', 9) || '1) Está certo; 2) Mudou.', c_ops);
    end loop;
    perform pg_temp.perg('bem_livre', 't4:pix', 'Pix de R$ 97,00 da Zeflex. De qual serviço é?', '[]'::jsonb, null, date '2027-07-01');
    perform pg_temp.perg('bem_livre', 't4:campo', 'Para marcar um serviço de diagnóstico, preciso saber em que dias você fica em campo nesta semana', '[]'::jsonb, null, date '2027-07-02');
    perform pg_temp.perg('bem_livre', 't4:outra', 'Para fechar a conta da semana, preciso saber quem foi no serviço de segunda e quem ficou na oficina', '[]'::jsonb, null, date '2027-07-03');
    v_t := pg_temp.ver() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'T4i decisões que enchem o teto: a linha do fim fica, dentro das 1.800', char_length(v_t) <= 1800 and v_t like '%(e mais % linhas)' || E'\n' || 'Também esperam: Pix de R$ 97,00 da Zeflex; %', char_length(v_t)::text || right(v_t, 120));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T4i quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$t4$;

-- ── T5. O cadastro vazio ────────────────────────────────────────────────────────────────────
do $t5$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T5', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    update public.agenda_locais set ativo = false where ativo;
    r := pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}', 'é na Marina Itajaí');
    v_res := pg_temp.ok(v_res, 'T5a nenhum local ativo: recusa como antes, sem lugar novo', r ->> 'ok' = 'false' and r ->> 'texto' = 'Não achei "Marina Itajaí" no cadastro.' and r ->> 'motivo' = 'local_nao_achei' and pg_temp.rascunhos() = 0, r::text);
    -- a casa de um cliente não é cadastro: a linha dela não abre a porta
    insert into public.agenda_locais (nome, tipo, client_id, atualizado_por)
    select 'casa de Vanderlei', 'casa_cliente', so.client_id, null from public.service_orders so where so.id = pg_temp.os('OS-J3');
    r := pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}', 'é na Marina Itajaí');
    v_res := pg_temp.ok(v_res, 'T5b só a casa de um cliente ativa também recusa', r ->> 'motivo' = 'local_nao_achei', r::text);
    r := pg_temp.plan('OS-J3', '{"local": "na casa do cliente"}', 'é na casa do cliente');
    v_res := pg_temp.ok(v_res, 'T5c a casa do cliente passa: ela não depende do cadastro', coalesce((r ->> 'ok')::boolean, false), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T5 quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$t5$;

-- ── T6. O aviso que nasce recusado ──────────────────────────────────────────────────────────
do $t6$
declare
  v_res  jsonb := '[]'::jsonb;
  v_rob  uuid;
  v_h    date := date '2027-07-19';
  v_d    date := date '2027-07-20';
  r      jsonb;
  m      public.agenda_equipe_mensagens;
  i      int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T6', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set modo_equipe = 'ligado' where id;
    perform set_config('agenda.hoje', v_h::text, true);
    perform pg_temp.contato('Roberto');
    v_rob := pg_temp.pessoa('Roberto');
    perform public._agenda_equipe_registrar(v_rob, v_d, 'ficha', public.agenda_equipe_ficha(v_rob, v_d, v_h) ->> 'texto_ficha', pg_temp.em(v_h, '09:30'));
    for i in 1 .. 4 loop
      perform public._agenda_equipe_registrar(v_rob, v_h, 'resposta', 'Tá bom ' || i, pg_temp.em(v_h, '10:0' || i), null, 'wa-' || i);
    end loop;
    update public.os_planejamento set acesso_ok_em = pg_temp.em(v_h, '19:40') where service_order_id = pg_temp.os('OS-J2');
    r := public._agenda_local_avisar_acesso(v_h, pg_temp.em(v_h, '19:45'));
    select * into m from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.dedupe_key like '%:acesso:%';
    v_res := pg_temp.ok(v_res, 'T6a a régua: com o teto cheio, ela nasce recusada', m.estado = 'recusada' and m.recusa_motivo = 'teto', to_jsonb(m)::text);
    v_res := pg_temp.ok(v_res, 'T6b não conta em avisos', (r ->> 'avisos')::int = 0, r::text);
    v_res := pg_temp.ok(v_res, 'T6c fica em app_error_logs, com local: no prefixo, o dia e o motivo', exists (select 1 from public.app_error_logs e where e.action = 'local:aviso' and e.message like '%aviso do acesso de 20/07 não saiu (teto)%'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T6 quebrou', false, sqlerrm);
  end;
  -- Sem recusa: conta e não loga
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set modo_equipe = 'ligado' where id;
    perform set_config('agenda.hoje', v_h::text, true);
    perform pg_temp.contato('Roberto');
    v_rob := pg_temp.pessoa('Roberto');
    perform public._agenda_equipe_registrar(v_rob, v_d, 'ficha', public.agenda_equipe_ficha(v_rob, v_d, v_h) ->> 'texto_ficha', pg_temp.em(v_h, '09:30'));
    update public.os_planejamento set acesso_ok_em = pg_temp.em(v_h, '19:40') where service_order_id = pg_temp.os('OS-J2');
    r := public._agenda_local_avisar_acesso(v_h, pg_temp.em(v_h, '19:45'));
    v_res := pg_temp.ok(v_res, 'T6d o aviso que saiu conta, e não vai ao registro de erro', (r ->> 'avisos')::int = 1 and not exists (select 1 from public.app_error_logs e where e.action = 'local:aviso' and e.message like '%aviso do acesso%'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T6d quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$t6$;

-- ── G6 + T8. O detector de lugar novo: as tabelas dos revisores ─────────────────────────────
do $g6$
declare
  v_res  jsonb := '[]'::jsonb;
  c      record;
  v_v    text;
  c_nao  constant text := 'Não entendi o lugar: me diga o nome do lugar (por exemplo, "Nova Trento").';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('G6', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J7', 'Navegantes');
    for c in select * from (values
      -- Recados: recusa, sozinhos ou no começo
      ('sim', c_nao), ('ok', c_nao), ('tanto faz', c_nao), ('depois te digo', c_nao), ('depois eu digo', c_nao), ('a definir', c_nao), ('a confirmar', c_nao), ('vou ver', c_nao),
      ('pergunta pra ele', c_nao), ('talvez em Penha', c_nao), ('acho que em Penha', c_nao), ('longe', c_nao), ('perto', c_nao), ('fora', c_nao), ('por aí', c_nao), ('de sempre', c_nao),
      ('no lugar de sempre', c_nao), ('lugar de sempre', c_nao), ('onde sempre fica', c_nao), ('onde sempre', c_nao), ('na mesma marina', c_nao), ('mesmo lugar', c_nao), ('no mesmo lugar', c_nao),
      ('em seco', c_nao), ('no seco', c_nao), ('na água', c_nao), ('na garagem', c_nao), ('na garagem dele', c_nao), ('na residência dele', c_nao), ('no endereço dele', c_nao),
      ('lá mesmo', c_nao), ('é aqui', c_nao), ('é onde ele está', c_nao), ('não sei', c_nao), ('ainda não sei', c_nao), ('sei lá', c_nao), ('em casa', c_nao), ('no cliente', c_nao), ('com ele', c_nao),
      ('com o cliente', c_nao), ('aí', c_nao), ('ali', c_nao), ('outro lugar', c_nao), ('Itajaí ou Navegantes', c_nao),
      -- Estado
      ('em Santa Catarina', '"Santa Catarina" é um estado: me diga a cidade ou o nome do lugar.'), ('no Paraná', '"Paraná" é um estado: me diga a cidade ou o nome do lugar.'),
      ('em SC', '"SC" é um estado: me diga a cidade ou o nome do lugar.'), ('SC', '"SC" é um estado: me diga a cidade ou o nome do lugar.'), ('PR', '"PR" é um estado: me diga a cidade ou o nome do lugar.'),
      ('no Rio Grande do Sul', '"Rio Grande do Sul" é um estado: me diga a cidade ou o nome do lugar.'), ('São Paulo', 'novo:São Paulo'),
      ('Água Verde', c_nao), ('Garagem do Zé', c_nao),
      -- Data
      ('semana que vem', '"semana que vem" parece uma data, não um lugar: me diga o nome do lugar (por exemplo, "Nova Trento").'), ('mês que vem', '"mês que vem" parece uma data, não um lugar: me diga o nome do lugar (por exemplo, "Nova Trento").'),
      ('no mes que vem', '"no mes que vem" parece uma data, não um lugar: me diga o nome do lugar (por exemplo, "Nova Trento").'), ('dia 5', '"dia 5" parece uma data, não um lugar: me diga o nome do lugar (por exemplo, "Nova Trento").'),
      ('3', '"3" não é um lugar: me diga o nome do lugar (por exemplo, "Nova Trento").'),
      -- O nome inteiro de 1 local, com palavra a mais
      ('Marina Itajaí em seco', 'local:Marina Itajaí'), ('Marina Itajaí na água', 'local:Marina Itajaí'), ('Marina Itajaí, vaga 12', 'local:Marina Itajaí'), ('garagem da Marina Itajaí', 'local:Marina Itajaí'),
      ('Tedesco em seco', 'local:Tedesco Marina Garden Plaza'), ('Garden Plaza, hangar 2', 'local:Tedesco Marina Garden Plaza'), ('MP em Balneário', 'local:MP Motorhomes'), ('MP em BC', 'local:MP Motorhomes'), ('na MP em seco', 'local:MP Motorhomes'),
      ('pátio da HBR em Balneário', 'local:MP Motorhomes'), ('Marina Itajaí, SC', 'local:Marina Itajaí'), ('Veleiros da Ilha em seco', 'local:Veleiros da Ilha'),
      -- Com 2 nomes, e a cidade
      ('Marina Itajaí ou Tedesco', c_nao), ('Balneário', 'qual'), ('em BC', 'qual'), ('BC', 'qual'), ('Balneário, SC', 'qual'), ('em Itajaí', 'qual'), ('na marina', 'qual'),
      -- Continua passando: o lugar novo de verdade, e a palavra do recado fora do começo
      ('Praia de Fora', 'novo:Praia de Fora'), ('Nova Trento', 'novo:Nova Trento'), ('Nova Trento, SC', 'novo:Nova Trento'), ('Nova Trento/SC', 'novo:Nova Trento'), ('Nova Trento SC', 'novo:Nova Trento'), ('nova trento sc', 'novo:Nova Trento'),
      ('Nova Trento - SC', 'novo:Nova Trento'), ('Curitiba, PR', 'novo:Curitiba'), ('Porto de Itajaí', 'novo:Porto de Itajaí'), ('Rua 1500, 200', 'novo:Rua 1500, 200'), ('na oficina do João', 'novo:Oficina do João'),
      ('no pátio dele', 'novo:Pátio Dele'), ('no sítio dele', 'novo:Sítio Dele'), ('Marina Itajay', 'novo:Marina Itajay'), ('Porto Belo', 'novo:Porto Belo'), ('Marina do João', 'novo:Marina do João'), ('Rio do Sul', 'novo:Rio do Sul'), ('na cidade de São Paulo', 'novo:Cidade de São Paulo'), ('Bairro Água Verde', 'novo:Bairro Água Verde'), ('Simão Dias', 'novo:Simão Dias'), ('Foragido Beach', 'novo:Foragido Beach'),
      ('outro lugar em Balneário', 'novo:Balneário Camboriú'), ('outro lugar em BC', 'novo:Balneário Camboriú'), ('outro lugar em Itajaí', 'novo:Itajaí'),
      -- A casa
      ('na casa do Vanderlei', 'casa:na casa do cliente'), ('na casa dele', 'casa:na casa do cliente'), ('na casa do Lenine', 'novo:Casa do Lenine'), ('na casa da mãe dele', 'novo:Casa da Mãe Dele'),
      -- O que já valia
      ('marina itajai', 'local:Marina Itajaí'), ('MP', 'local:MP Motorhomes'), ('pátio', 'local:MP Motorhomes'), ('na oficina', 'local:MP Motorhomes'), ('na hbr', 'local:MP Motorhomes'), ('com vocês', 'local:MP Motorhomes')
      ) t(frase, espera) loop
      v_v := pg_temp.virou('OS-J3', c.frase);
      -- (correção da 7d, Onda 4, M5) as 3 recusas dizem a saída; o texto dela é o que o dono disse. A prova da saída: agenda_fase7d_correcao4.sql
      v_res := pg_temp.ok(v_res, format('G6a "%s"', c.frase),
                          v_v = c.espera || case when c.espera ~ '^(Não entendi|"[^"]*" (parece uma data|é um estado))' then format(' Se é mesmo um lugar, diga "lugar novo: %s".', c.frase) else '' end, v_v);
    end loop;
    v_v := pg_temp.virou('OS-J3', 'pátio da Tedesco');
    v_res := pg_temp.ok(v_res, 'G6a2 "pátio da Tedesco": cada palavra é de um local: pergunta, nunca escolho sozinho', v_v = 'qual', v_v);
    perform pg_temp.cidade('OS-J7', 'Porto Belo');
    v_v := pg_temp.virou('OS-J3', 'na casa do Vanderlei em Porto Belo');
    v_res := pg_temp.ok(v_res, 'G6a2b "na casa do Vanderlei em Porto Belo": a casa, mesmo com a cidade junto', v_v like 'casa:na casa do cliente%', v_v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6a quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$g6$;

do $g6b$
declare
  v_res  jsonb := '[]'::jsonb;
  r      jsonb;
  l      public.agenda_locais;
  v_id   uuid;
  v_id2  uuid;
  v_cli  uuid;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('G6b', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- A UF: sai do nome antes de procurar duplicata e entra como UF
  begin
    perform pg_temp.base('sombra');
    r := pg_temp.plan('OS-J3', '{"local": "Sítio do Zé, PR"}', 'é no Sítio do Zé, PR');
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
    v_res := pg_temp.ok(v_res, 'G6b a UF sai do nome e entra como UF, sem cidade', l.nome = 'Sítio do Zé' and l.uf = 'PR' and l.municipio is null, to_jsonb(l)::text);
    v_res := pg_temp.ok(v_res, 'G6b2 a UF sem cidade não quebra a cadeia: o foco diz o nome, com o estado', public._agenda_local_resolvido(pg_temp.os('OS-J3'), date '2027-07-16') ->> 'texto' = 'Sítio do Zé (PR)', public._agenda_local_resolvido(pg_temp.os('OS-J3'), date '2027-07-16')::text);
    perform pg_temp.cidade('OS-J7', 'Porto Belo', 'SC');
    r := pg_temp.plan('OS-J4', '{"local": "Porto Belo, PR"}', 'é em Porto Belo, PR');
    v_res := pg_temp.ok(v_res, 'G6b3 a UF dita vence a do cadastro de clientes', pg_temp.rascunho('OS-J4') ->> 'local_uf' = 'PR', r::text);
    r := pg_temp.plan('OS-J5', '{"local": "Sítio do Zé, PR"}', 'é no Sítio do Zé, PR');
    v_res := pg_temp.ok(v_res, 'G6c "Nova Trento, SC" reaproveita a linha "Nova Trento": a duplicata é procurada sem a UF', r ->> 'item' like '%Local: Sítio do Zé.' and (pg_temp.rascunho('OS-J5') ->> 'local_id')::uuid = l.id, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6b quebrou', false, sqlerrm);
  end;
  -- "Nova Trento, SC" depois de "Nova Trento": uma linha só, e "Nova Trent" não pergunta entre grafias
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Nova Trento"}', 'é em Nova Trento');
    perform pg_temp.grava();
    perform pg_temp.plan('OS-J5', '{"local": "Nova Trento, SC"}', 'é em Nova Trento, SC');
    perform pg_temp.plan('OS-J4', '{"local": "Nova Trento/SC"}', 'é em Nova Trento/SC');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'G6d nada de 3 grafias: 1 linha, 3 OS', (select count(*) from public.agenda_locais x where public._agenda_normal(x.nome) like 'nova trento%') = 1
                        and (pg_temp.pl('OS-J3')).local_id = (pg_temp.pl('OS-J5')).local_id and (pg_temp.pl('OS-J3')).local_id = (pg_temp.pl('OS-J4')).local_id,
                        (select string_agg(x.nome, '; ') from public.agenda_locais x where public._agenda_normal(x.nome) like 'nova trento%'));
    r := public.agenda_resolver_local('Nova Trent');
    v_res := pg_temp.ok(v_res, 'G6e "Nova Trent" acha a linha', r ->> 'nome' = 'Nova Trento', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6d quebrou', false, sqlerrm);
  end;
  -- A linha com o nome da cidade não engole um lugar dentro dela
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Nova Trento"}', 'é em Nova Trento');
    perform pg_temp.grava();
    update public.agenda_locais set municipio = 'Nova Trento' where nome = 'Nova Trento';
    r := public.agenda_resolver_local('Marina do João em Nova Trento');
    v_res := pg_temp.ok(v_res, 'G6f "Marina do João em Nova Trento" não vira a linha "Nova Trento"', r ->> 'status' = 'nao_achei', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6f quebrou', false, sqlerrm);
  end;
  -- A casa: com a cidade dita, sem cidade no cliente; o cliente não muda
  begin
    perform pg_temp.base('sombra');
    select so.client_id into v_cli from public.service_orders so where so.id = pg_temp.os('OS-J3');
    update public.clients set city = null, state = null where id = v_cli;
    perform pg_temp.cidade('OS-J7', 'Porto Belo');
    r := pg_temp.plan('OS-J3', '{"local": "na casa dele em Porto Belo"}', 'é na casa dele em Porto Belo');
    v_res := pg_temp.ok(v_res, 'G6g a releitura mostra a cidade: não some', r ->> 'item' like '%Local: na casa do cliente, em Porto Belo.', r ->> 'item');
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
    v_res := pg_temp.ok(v_res, 'G6h a linha da casa leva a cidade e a UF', l.tipo = 'casa_cliente' and l.municipio = 'Porto Belo' and l.uf = 'SC', to_jsonb(l)::text);
    v_res := pg_temp.ok(v_res, 'G6i o cliente não muda', (select c.city is null and c.state is null from public.clients c where c.id = v_cli), null);
    v_res := pg_temp.ok(v_res, 'G6j o foco diz a cidade', public._agenda_local_resolvido(pg_temp.os('OS-J3'), date '2027-07-16') ->> 'texto' = 'na casa do cliente, em Porto Belo (você disse)', null);
    -- a palavra mais nova vale: a releitura diz Navegantes, e a linha tem de dizer o mesmo
    perform pg_temp.plan('OS-J5', '{"local": "na casa dele em Navegantes"}', 'é na casa dele em Navegantes');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
    v_res := pg_temp.ok(v_res, 'G6j2 dizer outra cidade troca a da linha, sem cidade no cliente', l.municipio = 'Navegantes', to_jsonb(l)::text);
    perform pg_temp.plan('OS-J5', '{"local": "na casa dele"}', 'é na casa dele');
    perform pg_temp.grava(date '2027-07-16', '17:20');
    select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
    v_res := pg_temp.ok(v_res, 'G6j3 dizer só "na casa dele" não apaga a cidade da linha', l.municipio = 'Navegantes', to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6g quebrou', false, sqlerrm);
  end;
  -- A casa do cliente com cidade: vale a dele, e a releitura mostra; a linha sem cidade já existente ganha a cidade dita; "na casa do {nome}" sem cidade fica como antes
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J3', 'Itapema');
    perform pg_temp.cidade('OS-J7', 'Porto Belo');
    r := pg_temp.plan('OS-J3', '{"local": "na casa dele em Porto Belo"}', 'é na casa dele em Porto Belo');
    v_res := pg_temp.ok(v_res, 'G6k o cliente tem cidade: a releitura mostra a dele', r ->> 'item' like '%Local: na casa do cliente, em Itapema.', r ->> 'item');
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.id = (pg_temp.pl('OS-J3')).local_id;
    v_res := pg_temp.ok(v_res, 'G6l a linha fica com a cidade do cliente, e com a UF dele', l.municipio = 'Itapema' and l.uf = 'SC', to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6k quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    select so.client_id into v_cli from public.service_orders so where so.id = pg_temp.os('OS-J3');
    update public.clients set city = null, state = null where id = v_cli;
    perform pg_temp.cidade('OS-J7', 'Porto Belo');
    r := pg_temp.plan('OS-J3', '{"local": "na casa do Vanderlei"}', 'é na casa do Vanderlei');
    v_res := pg_temp.ok(v_res, 'G6m sem cidade dita, a frase de sempre', r ->> 'item' like '%Local: na casa do cliente.', r ->> 'item');
    perform pg_temp.grava();
    v_id := (pg_temp.pl('OS-J3')).local_id;
    v_res := pg_temp.ok(v_res, 'G6n "na casa do {cliente da OS}" é a casa dele, tipo casa_cliente', (select x.tipo from public.agenda_locais x where x.id = v_id) = 'casa_cliente', null);
    r := pg_temp.plan('OS-J5', '{"local": "na casa dele em Porto Belo"}', 'é na casa dele em Porto Belo');
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.id = v_id;
    v_res := pg_temp.ok(v_res, 'G6o a linha sem cidade ganha a que ele disse depois: mesma linha, mesma casa', (pg_temp.pl('OS-J5')).local_id = v_id and l.municipio = 'Porto Belo' and l.uf = 'SC', to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6m quebrou', false, sqlerrm);
  end;
  -- Corrigir limpa
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Tanto Mar"}', 'é em Tanto Mar');
    perform pg_temp.grava();
    v_id := (pg_temp.pl('OS-J3')).local_id;
    perform pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}', 'não, é na Marina Itajaí');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_res := pg_temp.ok(v_res, 'G6p trocar o local inativa a linha sem uso', not (select x.ativo from public.agenda_locais x where x.id = v_id) and (pg_temp.pl('OS-J3')).local_id = pg_temp.local('Marina Itajaí'), null);
    r := pg_temp.desfaz('OS-J3', date '2027-07-16', '17:20');
    v_res := pg_temp.ok(v_res, 'G6q o *desfaz* dessa troca a reativa, e a OS volta a ela', (select x.ativo from public.agenda_locais x where x.id = v_id) and (pg_temp.pl('OS-J3')).local_id = v_id, r::text);
    v_res := pg_temp.ok(v_res, 'G6q2 a linha de cadastro que saiu não é tocada', (select x.ativo from public.agenda_locais x where x.id = pg_temp.local('Marina Itajaí')), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6p quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Tanto Mar"}', 'é em Tanto Mar');
    perform pg_temp.grava();
    v_id := (pg_temp.pl('OS-J3')).local_id;
    perform pg_temp.plan('OS-J3', '{"limpar": ["local"]}', 'tira o local');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_res := pg_temp.ok(v_res, 'G6r tirar o local inativa a linha sem uso', not (select x.ativo from public.agenda_locais x where x.id = v_id) and (pg_temp.pl('OS-J3')).local_id is null, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6r quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Tanto Mar"}', 'é em Tanto Mar');
    perform pg_temp.plan('OS-J5', '{"local": "Tanto Mar"}', 'é em Tanto Mar');
    perform pg_temp.grava();
    v_id := (pg_temp.pl('OS-J3')).local_id;
    perform pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}', 'é na Marina Itajaí');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_res := pg_temp.ok(v_res, 'G6s com outra OS na linha, ela fica', (select x.ativo from public.agenda_locais x where x.id = v_id), null);
    update public.agenda_locais set conferido_por = 'dono', conferido_em = date '2027-07-16' where id = v_id;
    perform pg_temp.plan('OS-J5', '{"local": "Marina Itajaí"}', 'é na Marina Itajaí');
    perform pg_temp.grava(date '2027-07-16', '17:20');
    v_res := pg_temp.ok(v_res, 'G6t a conferida fica, mesmo sem uso', (select x.ativo from public.agenda_locais x where x.id = v_id), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6s quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "na casa dele"}', 'é na casa dele');
    perform pg_temp.grava();
    v_id := (pg_temp.pl('OS-J3')).local_id;
    perform pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}', 'é na Marina Itajaí');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_res := pg_temp.ok(v_res, 'G6u a casa sem uso também sai', not (select x.ativo from public.agenda_locais x where x.id = v_id), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6u quebrou', false, sqlerrm);
  end;
  -- A linha de cadastro que saiu fica, conferida ou não
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Veleiros da Ilha"}', 'é no Veleiros da Ilha');
    perform pg_temp.grava();
    perform pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}', 'é na Marina Itajaí');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_res := pg_temp.ok(v_res, 'G6q3 a marina do cadastro, sem conferir e sem uso, fica ativa', (select x.ativo from public.agenda_locais x where x.id = pg_temp.local('Veleiros da Ilha')), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6q3 quebrou', false, sqlerrm);
  end;
  -- Só trocar de novo pelo mesmo não limpa nada: nem a ação ganha a chave
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Tanto Mar"}', 'é em Tanto Mar');
    perform pg_temp.grava();
    v_id := (pg_temp.pl('OS-J3')).local_id;
    perform pg_temp.plan('OS-J3', '{"local": "Tanto Mar", "dias": 2}', 'é em Tanto Mar, 2 dias');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_res := pg_temp.ok(v_res, 'G6v o mesmo local de novo: a linha fica', (select x.ativo from public.agenda_locais x where x.id = v_id) and not exists (select 1 from public.agenda_acoes a where a.tipo = 'local' and a.depois ? 'local_recolhido'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G6v quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$g6b$;

-- ── T11. A trava: uma conexão só não mostra a corrida; a trava tomada mostra ─────────────────
do $t11$
declare
  v_res jsonb := '[]'::jsonb;
  v_id  uuid;
  v_ac  uuid;
  r     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T11', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    v_res := pg_temp.ok(v_res, 'T11a a régua: sem nada, nenhuma trava', pg_temp.trava_tomada() = 0, null);
    perform public._agenda_local_recolher(gen_random_uuid(), pg_temp.adm());
    v_res := pg_temp.ok(v_res, 'T11b a limpeza toma a trava de _agenda_local_criar', pg_temp.trava_tomada() = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T11b quebrou', false, sqlerrm);
  end;
  -- Sem troca de local, o *grava* não toma a trava
  begin
    perform pg_temp.base('sombra');
    insert into public.agenda_locais (nome, tipo, ativo) values ('Linha de Antes', 'outro', true) returning id into v_id;
    insert into public.os_planejamento (service_order_id, local_id, local_fonte) values (pg_temp.os('OS-J3'), v_id, 'dono')
    on conflict (service_order_id) do update set local_id = excluded.local_id, local_fonte = excluded.local_fonte;
    perform pg_temp.plan('OS-J3', '{"viagem": "regional"}', 'é aqui na região');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'T11e sem troca de local, o *grava* não toma a trava', pg_temp.trava_tomada() = 0 and (pg_temp.pl('OS-J3')).viagem = 'regional', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T11e quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    insert into public.agenda_locais (nome, tipo, ativo) values ('Linha Recolhida', 'outro', false) returning id into v_id;
    insert into public.os_planejamento (service_order_id) values (pg_temp.os('OS-J3')) on conflict (service_order_id) do nothing;
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, desfazivel_ate)
    values (clock_timestamp(), date '2027-07-16', true, 'dono', 'local', pg_temp.os('OS-J3'), array[pg_temp.os('OS-J3')], '{}'::jsonb,
            jsonb_build_object('local_recolhido', v_id, 'efeito', 'planejar'), 'Vanderlei: tirei o local.', pg_temp.em(date '2027-07-20', '12:00'))
    returning id into v_ac;
    v_res := pg_temp.ok(v_res, 'T11c a régua, antes do *desfaz*', pg_temp.trava_tomada() = 0, null);
    r := public._agenda_desfazer_local(v_ac, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'T11d o *desfaz* que reativa toma a mesma trava', pg_temp.trava_tomada() = 1 and (select x.ativo from public.agenda_locais x where x.id = v_id), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T11c quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$t11$;

-- ── T10 = G16. A região não some ────────────────────────────────────────────────────────────
do $t10$
declare
  v_res jsonb := '[]'::jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T10', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    update public.agenda_config set municipios_locais = municipios_locais || '{Cidade Sem Cliente}'::text[] where id;
    v_res := pg_temp.ok(v_res, 'T10a município da região sem nenhum cliente: fica, sem UF', public._agenda_municipio_conhecido('Cidade Sem Cliente', pg_temp.os('OS-J3')) = '{"municipio": "Cidade Sem Cliente", "uf": null}'::jsonb,
                        public._agenda_municipio_conhecido('Cidade Sem Cliente', pg_temp.os('OS-J3'))::text);
    perform pg_temp.cidade('OS-J7', 'Cidade Sem Cliente', 'RS');
    v_res := pg_temp.ok(v_res, 'T10b com cliente, a UF dele vem', public._agenda_municipio_conhecido('Cidade Sem Cliente', pg_temp.os('OS-J3')) = '{"municipio": "Cidade Sem Cliente", "uf": "RS"}'::jsonb, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T10 quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$t10$;

-- ── T7, G10, G11. As datas ──────────────────────────────────────────────────────────────────
do $t7$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  r     jsonb;
  v_v   text;
  c_h   constant date := date '2026-11-06';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T7', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  for c in select * from (values
    -- O verbo de outra oração (T7, G10)
    ('o cliente deixou combinado que chega dia 20', 'dia 20', null, '2026-11-20 -'),
    ('já está combinado que chega dia 20', 'dia 20', null, '2026-11-20 -'),
    ('o cliente veio dizer que chega dia 20', 'dia 20', null, '2026-11-20 -'),
    ('chegou a confirmar que vem dia 20', 'dia 20', null, '2026-11-20 -'),
    ('o do Lenine chegou ontem e o do Nelson chega dia 20', 'dia 20', null, '2026-11-20 -'),
    ('o do Lenine chegou ontem, o do Nelson chega dia 20', 'dia 20', null, '2026-11-20 -'),
    ('o do Lenine chegou ontem mas o do Nelson chega dia 20', 'dia 20', null, '2026-11-20 -'),
    ('dia 20 chega, e o outro chegou ontem', 'dia 20', null, '2026-11-20 -'),
    -- A negação (T7)
    ('ainda não chegou, chega dia 20', 'dia 20', null, '2026-11-20 -'),
    ('ainda não chegou dia 5', 'dia 5', null, '2026-12-05 -'),
    ('não chegou dia 5', 'dia 5', null, '2026-12-05 -'),
    -- O passado da chegada (G11)
    ('chegou dia 5', 'dia 5', null, '2026-11-05 -'), ('chegou dia 20', 'dia 20', null, '2026-10-20 -'), ('entrou dia 4', 'dia 4', null, '2026-11-04 -'), ('veio dia 4', 'dia 4', null, '2026-11-04 -'),
    ('trouxe dia 4', 'dia 4', null, '2026-11-04 -'), ('deixou dia 4', 'dia 4', null, '2026-11-04 -'), ('já está lá dia 2', 'dia 2', null, '2026-11-02 -'),
    ('chegaram dia 3', 'dia 3', null, '2026-11-03 -'), ('apareceu dia 4', 'dia 4', null, '2026-11-04 -'), ('entregaram dia 3', 'dia 3', null, '2026-11-03 -'),
    ('está lá desde dia 2', 'dia 2', null, '2026-11-02 -'), ('tá lá desde segunda', 'segunda', null, '2026-11-02 -'), ('dia 5 chegou', 'dia 5', null, '2026-11-05 -'),
    -- Sem verbo no passado: o futuro de sempre
    ('chega dia 5', 'dia 5', null, '2026-12-05 -'), ('vem dia 30', 'dia 30', null, '2026-11-30 -'),
    -- A saída no passado (G11)
    ('saiu dia 5', null, 'dia 5', '- 2026-11-05'), ('ele buscou dia 4', null, 'dia 4', '- 2026-11-04'), ('levou dia 3', null, 'dia 3', '- 2026-11-03'), ('retirou dia 3', null, 'dia 3', '- 2026-11-03'),
    ('já foi embora segunda', null, 'segunda', '- 2026-11-02'), ('já saiu terça', null, 'terça', '- 2026-11-03'), ('não saiu dia 5', null, 'dia 5', '- 2026-12-05'), ('sai dia 3', null, 'dia 3', '- 2026-12-03'),
    ('busca dia 2', null, 'dia 2', '- 2026-12-02'),
    -- A chegada e a saída juntas (T7)
    ('chega dia 20 e sai dia 10', 'dia 20', 'dia 10', '2026-11-20 2026-12-10'), ('chega dia 5 e ele busca dia 13', 'dia 5', 'dia 13', '2026-11-05 2026-11-13'),
    ('chega dia 13 e sai dia 13', 'dia 13', 'dia 13', '2026-11-13 2026-12-13'), ('chega dia 31 e sai dia 10', 'dia 31', 'dia 10', '2026-10-31 2026-11-10'),
    ('chega dia 28 e sai dia 3', 'dia 28', 'dia 3', '2026-11-28 2026-12-03'), ('chegou dia 5 e sai dia 13', 'dia 5', 'dia 13', '2026-11-05 2026-11-13'), ('chegou dia 13 e sai dia 13', 'dia 13', 'dia 13', '2026-10-13 2026-11-13'),
    ('chegou dia 1 e saiu dia 5', 'dia 1', 'dia 5', '2026-11-01 2026-11-05'), ('chega dia 8 e sai dia 7', 'dia 8', 'dia 7', '2026-11-08 2026-12-07'),
    -- O limite dos 7 dias: 30/10 ainda volta; 29/10, não
    ('chega dia 30 e sai dia 9', 'dia 30', 'dia 9', '2026-10-30 2026-11-09'), ('chega dia 29 e sai dia 9', 'dia 29', 'dia 9', '2026-11-29 2026-12-09')
    ) t(trecho, chega, sai, espera) loop
    begin
      perform pg_temp.base('sombra');
      r := pg_temp.plan('OS-J5', jsonb_strip_nulls(jsonb_build_object('chega_em', c.chega, 'sai_em', c.sai)), c.trecho, c_h);
      v_v := coalesce(pg_temp.datas('OS-J5'), r::text);
      v_res := pg_temp.ok(v_res, format('T7a "%s"', c.trecho), v_v = c.espera, v_v);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, format('T7a "%s" quebrou', c.trecho), false, sqlerrm);
    end;
  end loop;
  -- Saídas que não cabem: a recusa de sempre, com as datas
  begin
    perform pg_temp.base('sombra');
    r := pg_temp.plan('OS-J5', '{"chega_em": "dia 20", "sai_em": "dia 5"}', 'chega dia 20 e saiu dia 5', c_h);
    v_res := pg_temp.ok(v_res, 'T7b a saída no passado não anda: a recusa', r ->> 'motivo' = 'chega_depois_de_sai', r::text);
    r := pg_temp.plan('OS-J5', '{"chega_em": "dia 20", "sai_em": "10/11"}', 'chega dia 20 e sai 10/11', c_h);
    v_res := pg_temp.ok(v_res, 'T7c a saída com mês não anda: a recusa', r ->> 'motivo' = 'chega_depois_de_sai', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T7b quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    r := pg_temp.plan('OS-J5', '{"sai_em": "05/12"}', 'saiu 05/12', c_h);
    v_v := coalesce(pg_temp.datas('OS-J5'), r::text);
    v_res := pg_temp.ok(v_res, 'T7i a data com mês fica como foi dita', v_v = '- 2026-12-05', v_v);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'T7i quebrou', false, sqlerrm);
  end;
  -- A função: a oração, o lado, e o dito que não está no trecho
  v_res := pg_temp.ok(v_res, 'T7d o lado conta: "saiu" não é chegada, "chegou" não é saída',
    not public._agenda_data_no_passado('saiu dia 5', 'dia 5', 'chega') and not public._agenda_data_no_passado('chegou dia 5', 'dia 5', 'sai'), null);
  v_res := pg_temp.ok(v_res, 'T7e o verbo depois da data vale, até o fim da oração', public._agenda_data_no_passado('dia 5 chegou', 'dia 5', 'chega')
    and not public._agenda_data_no_passado('dia 5 sai, e o outro chegou', 'dia 5', 'chega'), null);
  v_res := pg_temp.ok(v_res, 'T7f a data não achada no trecho: não é passado', not public._agenda_data_no_passado('chegou', 'dia 5', 'chega'), null);
  v_res := pg_temp.ok(v_res, 'T7g "dia 5" não casa dentro de "dia 15"', not public._agenda_data_no_passado('chegou dia 15', 'dia 5', 'chega'), null);
  v_res := pg_temp.ok(v_res, 'T7h por extenso, como o trecho é conferido', public._agenda_data_no_passado('chegou dia cinco', 'dia 5', 'chega') and public._agenda_data_no_passado('chegou dia cinco', 'dia cinco', 'chega'), null);
  perform pg_temp.gravar(v_res);
end
$t7$;

-- ── G7. Resposta ao M11 com cidade ──────────────────────────────────────────────────────────
do $g7$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  q     public.agenda_perguntas;
  c     record;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('G7', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- Município conhecido: é sinal de lugar
  for c in select * from (values ('está em Navegantes'), ('em Penha'), ('fica em Bombinhas'), ('tá em Nova Trento agora'), ('no Rio do Sul'), ('na Penha')) t(frase) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.prepara();
      perform pg_temp.cidade('OS-J7', 'Bombinhas');
      perform pg_temp.cidade('OS-J8', 'Nova Trento');
      perform pg_temp.cidade('OS-J9', 'Rio do Sul');
      perform pg_temp.mandado('OS-J11');
      r := pg_temp.resp('OS-J11', c.frase, 'outro');
      select * into q from public.agenda_perguntas x where x.tipo = 'local' and x.service_order_id = pg_temp.os('OS-J11') and x.estado = 'aberta';
      v_res := pg_temp.ok(v_res, format('G7a "%s": vira a pergunta local e fica anotado', c.frase), q.texto like '%Não achei esse lugar no cadastro. Me diga onde é%' and pg_temp.site_access('OS-J11') like '%' || c.frase, coalesce(q.texto, r::text));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, format('G7a "%s" quebrou', c.frase), false, sqlerrm);
    end;
  end loop;
  -- Sem casar município, com em|no|na + palavra que não é data: perde o "não disse onde fica"
  for c in select * from (values ('fica em Piçarras'), ('tá em Garopaba')) t(frase) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.prepara();
      perform pg_temp.mandado('OS-J11');
      r := pg_temp.resp('OS-J11', c.frase, 'outro');
      select * into q from public.agenda_perguntas x where x.tipo = 'cliente_resposta' and x.service_order_id = pg_temp.os('OS-J11') and x.estado = 'aberta';
      v_res := pg_temp.ok(v_res, format('G7b "%s": a frase, sem "não disse onde fica"', c.frase), q.texto = format('Carla respondeu "%s" à mensagem da agenda. Não respondi nada; é com você.', c.frase), coalesce(q.texto, r::text));
      v_res := pg_temp.ok(v_res, format('G7c "%s": nada anotado', c.frase), pg_temp.site_access('OS-J11') is null and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'local'), null);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, format('G7b "%s" quebrou', c.frase), false, sqlerrm);
    end;
  end loop;
  -- Sem lugar: a frase de sempre (a palavra depois de "em" é data, ou não há "em")
  for c in select * from (values ('vou levar aí'), ('sim'), ('em dezembro'), ('na segunda'), ('no sábado'), ('em breve'), ('na semana que vem')) t(frase) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.prepara();
      perform pg_temp.mandado('OS-J11');
      r := pg_temp.resp('OS-J11', c.frase, 'outro');
      select * into q from public.agenda_perguntas x where x.tipo = 'cliente_resposta' and x.service_order_id = pg_temp.os('OS-J11') and x.estado = 'aberta';
      v_res := pg_temp.ok(v_res, format('G7d "%s": segue "não disse onde fica"', c.frase), q.texto like '%: não disse onde fica. Não respondi nada; é com você.', coalesce(q.texto, r::text));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, format('G7d "%s" quebrou', c.frase), false, sqlerrm);
    end;
  end loop;
  -- A desistência e a data continuam ganhando
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    perform pg_temp.mandado('OS-J11');
    r := pg_temp.resp('OS-J11', 'desisti, fica em aberto', 'outro');
    select * into q from public.agenda_perguntas x where x.tipo = 'cliente_resposta' and x.service_order_id = pg_temp.os('OS-J11') and x.estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'G7e a desistência segue desistência, mesmo com "em"', q.texto like '%parece que desistiu do serviço%', coalesce(q.texto, r::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G7e quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    perform pg_temp.mandado('OS-J11');
    r := pg_temp.resp('OS-J11', 'levo em casa dia 20', 'data');
    select * into q from public.agenda_perguntas x where x.service_order_id = pg_temp.os('OS-J11') and x.estado = 'aberta' and x.tipo in ('cliente_resposta', 'local');
    v_res := pg_temp.ok(v_res, 'G7f com lugar na frase, segue anotando', q.tipo = 'local', coalesce(q.texto, r::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G7f quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$g7$;

-- ── G5. *desfaz OS-…* depois do tique ───────────────────────────────────────────────────────
do $g5$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  r     jsonb;
  v_ac  uuid;
  v_st  text;
  v_n   int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('G5', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- O *entreguei*, o tique cancela o plano, e 1 *desfaz* volta tudo
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    select so.status into v_st from public.service_orders so where so.id = pg_temp.os('OS-J1');
    v_n := (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('OS-J1') and a.estado in ('publicada', 'fixada') and a.dia >= v_h);
    v_res := pg_temp.ok(v_res, 'G5a a régua: a OS tem plano', v_n > 0, v_n::text);
    r := public.agenda_entregar_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    v_res := pg_temp.ok(v_res, 'G5b o *entreguei* concluiu', (select so.status from public.service_orders so where so.id = pg_temp.os('OS-J1')) = 'completed', r::text);
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    select a.id into v_ac from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo = 'cancelar' and a.origem = 'vigia' and a.desfeita_em is null order by a.criada_em desc limit 1;
    v_res := pg_temp.ok(v_res, 'G5c o tique cancelou o plano', v_ac is not null and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('OS-J1') and a.estado in ('publicada', 'fixada') and a.dia >= v_h), r::text);
    -- o relógio anda em produção: a ação da vigia é a mais nova
    set local session_replication_role = replica;
    update public.agenda_acoes set criada_em = criada_em + interval '15 minutes' where id = v_ac;
    set local session_replication_role = origin;
    r := public.agenda_desfazer_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'G5d 1 *desfaz*: a resposta diz os 2', coalesce((r ->> 'ok')::boolean, false) and r ->> 'texto' like 'Desfeito: o Lenine (OS-J1) voltou para %, sem a entrega%. Desfeito: o Lenine (OS-J1) volta para %, como estava.', r::text);
    v_res := pg_temp.ok(v_res, 'G5e a OS volta ao status de antes (a aberta com plano, agendada: a regra de sempre do *desfaz*), sem a entrega', (select so.status = case when v_st = 'open' then 'scheduled' else v_st end and so.delivered_at is null and so.check_out_at is null from public.service_orders so where so.id = pg_temp.os('OS-J1')), v_st);
    v_res := pg_temp.ok(v_res, 'G5f o plano volta inteiro', (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('OS-J1') and a.estado in ('publicada', 'fixada') and a.dia >= v_h) = v_n, null);
    v_res := pg_temp.ok(v_res, 'G5g as ações da entrega e o cancelar ficam desfeitas', not exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo in ('entregar', 'concluir', 'cancelar') and a.desfeita_em is null), null);
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:30'));
    v_res := pg_temp.ok(v_res, 'G5h o tique seguinte não cancela de novo', (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('OS-J1') and a.estado in ('publicada', 'fixada') and a.dia >= v_h) = v_n, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G5a quebrou', false, sqlerrm);
  end;
  -- A entrega que já passou do prazo do *desfaz*: (correção da 7d, Onda 4, M9) o plano não volta, porque a OS segue concluída; o laço de voltar e sair a cada tique acabou
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    r := public.agenda_entregar_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    select a.id into v_ac from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo = 'cancelar' and a.origem = 'vigia' and a.desfeita_em is null order by a.criada_em desc limit 1;
    set local session_replication_role = replica;
    update public.agenda_acoes set desfazivel_ate = pg_temp.em(v_h, '14:01') where service_order_id = pg_temp.os('OS-J1') and tipo in ('entregar', 'concluir');
    set local session_replication_role = origin;
    r := public.agenda_desfazer(v_ac, pg_temp.adm(), 'dono', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'G5i a entrega fora do prazo não volta: nada muda, e o *desfaz* diz por quê', not coalesce((r ->> 'ok')::boolean, false) and r ->> 'texto' = 'Não dá para voltar os dias do Lenine: ele segue concluído. Reabra a OS primeiro.'
                        and (select so.status from public.service_orders so where so.id = pg_temp.os('OS-J1')) = 'completed', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G5i quebrou', false, sqlerrm);
  end;
  -- Só o cancelar da vigia, e a entrega de antes dele: o cancelar que veio antes do *entreguei* não encadeia
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    r := public.agenda_entregar_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    select a.id into v_ac from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo = 'cancelar' and a.origem = 'vigia' and a.desfeita_em is null order by a.criada_em desc limit 1;
    set local session_replication_role = replica;
    update public.agenda_acoes set criada_em = criada_em - interval '1 hour' where id = v_ac;
    set local session_replication_role = origin;
    r := public.agenda_desfazer(v_ac, pg_temp.adm(), 'dono', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'G5j o cancelar de antes da entrega volta sozinho', r ->> 'texto' not like '%sem a entrega%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G5j quebrou', false, sqlerrm);
  end;
  -- Se a entrega não volta, nada volta
  begin
    perform pg_temp.base('sombra');
    perform set_config('agenda.hoje', v_h::text, true);
    r := public.agenda_entregar_dito(pg_temp.adm(), pg_temp.os('OS-J1')::text, 'whatsapp', v_h, pg_temp.em(v_h, '14:00'));
    r := public.agenda_vigiar(v_h, pg_temp.em(v_h, '14:15'));
    select a.id into v_ac from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.tipo = 'cancelar' and a.origem = 'vigia' and a.desfeita_em is null order by a.criada_em desc limit 1;
    set local session_replication_role = replica;
    update public.service_orders set delivered_at = delivered_at + interval '1 hour' where id = pg_temp.os('OS-J1');
    set local session_replication_role = origin;
    r := public.agenda_desfazer(v_ac, pg_temp.adm(), 'dono', v_h, pg_temp.em(v_h, '14:20'));
    v_res := pg_temp.ok(v_res, 'G5k a entrega recusou: a recusa dela, e o plano não volta', r ->> 'ok' = 'false' and r ->> 'texto' like '%entrega%mudou depois%'
                        and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('OS-J1') and a.estado in ('publicada', 'fixada') and a.dia >= v_h)
                        and (select a.desfeita_em is null from public.agenda_acoes a where a.id = v_ac), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'G5k quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$g5$;

select teste, ok, detalhe from _resultado order by ok, teste;

rollback;
