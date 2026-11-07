-- Prova da correção da 7d, Onda 1, da Agenda de Produção ("saber onde é e não cobrar errado"; migration 20261107100800; decisoes-do-fio.md, seção Onda 1). Um bloco por item: cada um falha sem a
-- migration e passa com ela (o "antes" está nas notas). Tudo pelo caminho real: agenda_rascunho_planejar → *grava* → *desfaz*; agenda_resposta_do_cliente; agenda_local_vigiar.
-- bancada: depende de 20261107100800
--
--   T0   as portas das novas e as cópias: nas funções de antes da 7d, tirados os blocos, a origem; agenda_data_dita não muda
--   O1   *agenda locais*: todas as OS abertas, curtas, as supostas primeiro; o corte: notas, ditas, supostas; o vazio
--   O2   o lugar fora do cadastro entra pelo *grava*; a cidade conhecida ou nula; o *desfaz*; as recusas; a cidade com locais; o M11 não cria
--   O3   a casa do cliente é um local: 1 linha por cliente; o foco; a frase seguinte; o *desfaz*; o pátio não cobra; o acesso segue o R1; o M11 não pergunta de novo
--   O4   serviço começado não é cobrado: entrada, vaga, descida e acesso não nascem; o foco e a ficha seguem a mesma fonte
--   O5   "eu te aviso": sai pelo caminho da ficha, na janela dela, uma vez por pessoa e dia; só com os 2 modos ligados
--   O6   autorizados com local suposto: local_id nulo; a lista sobrevive ao dono dizer o local
--   O7   a data sem mês: verbo no passado e chegada depois da saída dita na mesma frase
--   O10  vaga, descida e entrada nascem no prazo: "O prazo é hoje."; a crítica não dobra
--   O14  viagem dita com local suposto: sem o feriado do pátio; a pernoite sem encaixe diz o motivo
--   O15  o feriado do município diz o motivo
--   O18  a releitura da crítica diz qual é
--   O19  o exemplo da pergunta local é lugar; quem disse data e não lugar
--   O21  bem_livre fecha pelo pátio e pelo estado livre
--   C1   a rede K no calendário; o motivo local na onda
--   C2   parar o M11 recusa o que está na fila
--   C7   a semente depois do DESFAZER reativa os locais
--   C9   a recomendação de tirar o apelido
--   R3   a resposta ao M11 sem lugar não vira acesso; a desistência; o "sim" do M1 vai ao M1
--   R4   "Sim, na Marina Itajaí"
--   R5   o M11 em teste nasce contado
--   R6   a rodada do local: isola por OS; 3 tentativas por dia; o registro
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
           select l from (select l, o, sum(case when (l ~ '^\s*-- FASE 7f:' and l !~ '^\s*-- FASE 7f: fim')
                                                     or (l ~ '^\s*-- \(7f ' and l !~ '^\s*-- \(7f: fim\)') then 1
                                                when l ~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7f: fim|\(7f: fim\))' as fecha
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
    if v_dentro = 0 and l ~ '^\s*-- FASE 7[df]:' and l !~ '^\s*-- FASE 7[df]: fim' then v_dentro := 1; continue; end if;
    if v_dentro = 1 and l ~ '^\s*-- FASE 7[df]: fim' then v_dentro := 0; continue; end if;
    if v_dentro = 0 and l ~ '^\s*-- \(7[df] ' then v_dentro := 2; continue; end if;
    if v_dentro = 2 and l ~ '^\s*-- \(7[df]: fim\)' then v_dentro := 0; continue; end if;
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

-- ── T0. As portas e as cópias ─────────────────────────────────────────────────────────────
with f(sig, vol) as (values
  ('public._agenda_data_sem_mes(text)', 'i'),
  ('public._agenda_local_novo(text)', 'i'),
  ('public._agenda_municipio_conhecido(text, uuid)', 's'),
  ('public._agenda_local_criar(text, text, text, uuid)', 'v'),
  ('public._agenda_local_da_casa(uuid, uuid)', 'v'),
  ('public._agenda_feriado_do_bloco(jsonb, date, date, date)', 's'),
  ('public._agenda_local_avisar_acesso(date, timestamp with time zone)', 'v'))
insert into _resultado
select 'T0a as 7 novas: invoker, a volatilidade, search_path fixo, e ninguém de fora (nem o service_role): quem chama é definer',
       count(p.oid) = 7
       and bool_and(not p.prosecdef and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and not has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(f.sig, '; ') filter (where p.oid is null)
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

insert into _resultado
select 'T0b rodando: o anon e o técnico não alcançam o que cria local nem o aviso (42501)',
       pg_temp.como('anon', $q$select public._agenda_local_criar('x', null, null, null)::text$q$) like 'erro 42501%'
       and pg_temp.como('authenticated', $q$select public._agenda_local_criar('x', null, null, null)::text$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_local_avisar_acesso(date '2027-07-16', now())::text$q$) like 'erro 42501%', null;

insert into _resultado
select 'T0c agenda_locais: municipio aceita nulo, a chave por cliente é nullable, só na casa, e uma casa por cliente',
       (select not a.attnotnull from pg_attribute a where a.attrelid = 'public.agenda_locais'::regclass and a.attname = 'municipio')
       and exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_locais'::regclass and a.attname = 'client_id' and not a.attnotnull)
       and exists (select 1 from pg_constraint c where c.conname = 'local_cliente_so_na_casa')
       and exists (select 1 from pg_index i join pg_class k on k.oid = i.indexrelid where k.relname = 'agenda_locais_uma_casa_por_cliente' and i.indisunique), null;

do $t0$
declare
  c      record;
  v_viva text;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_correcao_fase7d', true), '');
begin
  if v_mig = '' then
    insert into _resultado values ('T0d as cópias', true, 'PULADO: sem a migration como texto (rode pela bancada)');
    return;
  end if;
  -- As funções que vêm de antes da 7d: tirados os blocos, a origem. O agenda_data_dita e o que a sessão do retorno chama não aparecem na migration.
  for c in select * from (values
      ('agenda_propor', 'mig_motor_fase7d'), ('agenda_resposta_do_cliente', 'mig_cliente_fase7d'), ('_agenda_cliente_revalidar', 'mig_cliente_fase7d'),
      ('agenda_rascunho_planejar', 'mig_rascunho_fase7d'), ('_agenda_aplicar_planejar', 'mig_rascunho_fase7d'), ('agenda_rascunho_aplicar', 'mig_leituras_fase7d')) t(nome, fonte) loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_viva from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = c.nome;
    v_viva := pg_temp.sem_7f(v_viva);  -- FASE 7f: a régua (R8.13)
    -- (correção da 7d, Ondas 2 e 3) agenda_rascunho_planejar, agenda_rascunho_aplicar e _agenda_aplicar_planejar passaram a viver nas seguintes: a viva é a da migration mais nova que a define
    insert into _resultado values ('T0d ' || c.nome || ': a viva é a da migration; sem os blocos, a origem, byte a byte',
      v_viva = coalesce(nullif(pg_temp.corpo(coalesce(current_setting('agenda_teste.mig_correcao4_fase7d', true), ''), c.nome), ''),
                        nullif(pg_temp.corpo(coalesce(current_setting('agenda_teste.mig_correcao3_fase7d', true), ''), c.nome), ''),
                        nullif(pg_temp.corpo(coalesce(current_setting('agenda_teste.mig_correcao2_fase7d', true), ''), c.nome), ''), pg_temp.corpo(v_mig, c.nome))
      and pg_temp.sem_7d(v_viva) = pg_temp.sem_7d(pg_temp.corpo(current_setting('agenda_teste.' || c.fonte), c.nome)), null);
  end loop;
  insert into _resultado values ('T0e a sessão do retorno: agenda_data_dita, _agenda_chave_telefone, agenda_dia_util, agenda_somar_du, agenda_feriado, _agenda_cliente_dia e _agenda_nome_curto ficam de fora',
    v_mig !~ 'function public\.(agenda_data_dita|_agenda_chave_telefone|agenda_dia_util|agenda_somar_du|agenda_feriado|_agenda_cliente_dia|_agenda_nome_curto)\(', null);
end
$t0$;

-- ── O1. *agenda locais* ───────────────────────────────────────────────────────────────────
do $o1$
declare
  v_res jsonb := '[]'::jsonb;
  v_t   text;
  v_j   jsonb;
  v_h   date := date '2027-07-16';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O1', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    update public.agenda_config set texto_max = 3000 where id;
    v_j := public._agenda_ver_locais(v_h);
    v_t := v_j ->> 'texto';
    v_res := pg_temp.ok(v_res, 'O1a todas as OS abertas, com plano ou sem: uma linha por OS da carteira', jsonb_array_length(v_j -> 'linhas') = (select count(*) from public.os_carteira(v_h))
                        and v_t ~ E'\n- Carla \\(OS-J11\\): MP Motorhomes \\(suposição\\)\\.' and v_t ~ E'\n- Nuno \\(OS-J14\\): Tedesco Marina Garden Plaza \\(você disse\\)\\.', v_t);
    v_res := pg_temp.ok(v_res, 'O1b as supostas e as que não sei vêm antes das ditas, com o aviso de corrigir', v_t ~ '^Onde é cada serviço:' and strpos(v_t, 'Estou supondo ou não sei (me corrija):') > 0
                        and strpos(v_t, 'Júlio (OS-J13): não sei onde é o serviço.') < strpos(v_t, 'Já ditos:')
                        and strpos(v_t, 'Tiago (OS-J8): em Penha (suposição).') < strpos(v_t, 'Já ditos:')
                        and strpos(v_t, 'Lenine (OS-J1): MP Motorhomes (pela OS).') > strpos(v_t, 'Já ditos:')
                        and strpos(v_t, 'Kalmar (OS-J6): Iate Clube Caiobá (PR).') > strpos(v_t, 'Já ditos:'), v_t);
    v_res := pg_temp.ok(v_res, 'O1c a linha é curta: nada do texto longo do foco por OS', v_t !~ 'Em teste, eu cobraria' and v_t !~ 'Combinar:' and v_t !~ 'O barco:' and v_t !~ 'Viagem com pernoite', v_t);
    v_res := pg_temp.ok(v_res, 'O1d o resto do foco fica: o cadastro e o "Em teste"', v_t ~ E'\nLocais: 5 no cadastro; 1 conferido por você' and v_t ~ E'\nEm teste: ', v_t);
    v_res := pg_temp.ok(v_res, 'O1e o foco por OS segue longo', pg_temp.foco(v_h, pg_temp.os('OS-J2')) ~ 'Em teste, eu cobraria: o acesso de João', null);
    -- Dita pelo dono, sai das supostas
    perform pg_temp.plan('OS-J11', '{"local": "Marina Itajaí"}'::jsonb, 'o serviço da Carla é na Marina Itajaí');
    perform pg_temp.grava();
    v_t := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'O1f o que o dono disse passa para as ditas', strpos(v_t, 'Carla (OS-J11): Marina Itajaí (você disse).') > strpos(v_t, 'Já ditos:'), v_t);

    -- O teto: primeiro as notas, depois as ditas, por último as supostas
    insert into public.agenda_locais (nome, tipo, municipio, sabado, conferido_em, conferido_por)
    select 'Nota ' || g, 'marina', 'Penha', 'nao', date '2026-10-29', 'pesquisa' from generate_series(1, 5) g;
    update public.agenda_config set texto_max = 3000 where id;
    v_t := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'O1g com folga, as notas até 3 e "(e mais N)"', v_t ~ '\(e mais 3\)\.', v_t);
    update public.agenda_config set texto_max = (select char_length(pg_temp.foco()) - 60 from public.agenda_config where id) where id;
    v_t := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'O1h passou do teto: saem as notas, com "(e mais N)", e nenhuma OS', v_t ~ 'Só como nota: [^\n]*\(e mais [0-9]+\)\.' and v_t !~ E'\n\\(e mais [0-9]+\\)\n' and v_t ~ 'Lenine \(OS-J1\)', v_t);
    update public.agenda_config set texto_max = (select char_length(pg_temp.foco()) - 300 from public.agenda_config where id) where id;
    v_t := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'O1i ainda não cabe: saem as ditas, com "(e mais N)"; as supostas ficam', v_t ~ E'Já ditos:\n(- [^\n]*\n)*\\(e mais [0-9]+\\)\n' and v_t !~ E'me corrija\\):\n(- [^\n]*\n)*\\(e mais', v_t);
    update public.agenda_config set texto_max = 500 where id;
    v_t := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'O1j por último as supostas, também com "(e mais N)"', char_length(v_t) <= 500 and v_t ~ E'me corrija\\):\n(- [^\n]*\n)*\\(e mais [0-9]+\\)\n' and v_t ~ 'Locais:', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O1 quebrou', false, sqlerrm);
  end;
  -- O vazio
  begin
    perform pg_temp.base('sombra');
    set local session_replication_role = replica;
    update public.service_orders set status = 'cancelled';
    set local session_replication_role = origin;
    v_t := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'O1k sem nenhuma OS aberta: a frase e o cadastro', v_t ~ '^Nenhum serviço em aberto\.' and v_t ~ E'\nLocais: 5 no cadastro' and v_t !~ 'me corrija', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O1k quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o1$;

-- ── O2. O lugar fora do cadastro ───────────────────────────────────────────────────────────
do $o2$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  r2    jsonb;
  l     public.agenda_locais;
  v_id  uuid;
  v_t   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O2', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J3', 'Nova Trento');
    r := pg_temp.plan('OS-J3', '{"local": "Nova Trento"}'::jsonb, 'o serviço do Vanderlei é em Nova Trento');
    v_res := pg_temp.ok(v_res, 'O2a a releitura, byte a byte', r ->> 'item' = 'Planejamento: Vanderlei (OS-J3): Local: Nova Trento (lugar novo: entra no cadastro quando você gravar).' or r ->> 'item' like '%Local: Nova Trento (lugar novo: entra no cadastro quando você gravar).', r::text);
    v_res := pg_temp.ok(v_res, 'O2b antes do *grava*, nada no cadastro', pg_temp.local('Nova Trento') is null, null);
    r2 := pg_temp.grava();
    select * into l from public.agenda_locais x where x.nome = 'Nova Trento';
    v_res := pg_temp.ok(v_res, 'O2c o *grava* cria: tipo outro, sem conferir, a cidade e a UF pelo caminho da cidade do cliente', (r2 ->> 'ok')::boolean and l.tipo = 'outro' and l.conferido_por is null and l.conferido_em is null
                        and l.municipio = 'Nova Trento' and l.uf = 'SC' and l.ativo and l.client_id is null, to_jsonb(l)::text);
    v_res := pg_temp.ok(v_res, 'O2d o local_id como sempre, fonte dono', (pg_temp.pl('OS-J3')).local_id = l.id and (pg_temp.pl('OS-J3')).local_fonte = 'dono', null);
    v_res := pg_temp.ok(v_res, 'O2e foco e cartão concordam: é um local como os outros', pg_temp.foco(date '2027-07-16', pg_temp.os('OS-J3')) ~ '^Vanderlei \(OS-J3\): Nova Trento \(você disse\)\.'
                        and public.os_plano_da_os(pg_temp.os('OS-J3'), date '2027-07-16') -> 'local' ->> 'nome' = 'Nova Trento', pg_temp.foco(date '2027-07-16', pg_temp.os('OS-J3')));
    v_res := pg_temp.ok(v_res, 'O2f a ficha: "em Nova Trento", não "na Nova Trento"', public._agenda_local_da_os(pg_temp.os('OS-J3')) = 'em Nova Trento', public._agenda_local_da_os(pg_temp.os('OS-J3')));
    v_res := pg_temp.ok(v_res, 'O2g a 2ª vez, a linha existe: nome dela, sem "lugar novo", sem outra linha', (select count(*) from public.agenda_locais x where x.nome = 'Nova Trento') = 1
                        and pg_temp.plan('OS-J4', '{"local": "nova trento"}'::jsonb, 'o do Renato é em nova trento') ->> 'item' like '%Local: Nova Trento.', null);
    perform pg_temp.grava();
    r := pg_temp.desfaz('OS-J3');
    v_res := pg_temp.ok(v_res, 'O2h o *desfaz* volta o plano; a linha fica: outra OS usa', (pg_temp.pl('OS-J3')).local_id is null and (select x.ativo from public.agenda_locais x where x.id = l.id), r::text);
    r := pg_temp.desfaz('OS-J4');
    v_res := pg_temp.ok(v_res, 'O2i sem ninguém usando, ela some (sai por ativo; a linha nunca se apaga) e o foco volta a supor', (pg_temp.pl('OS-J4')).local_id is null and not (select x.ativo from public.agenda_locais x where x.id = l.id), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O2 quebrou', false, sqlerrm);
  end;
  -- Quem criou a linha desfaz com outra OS usando: fica. Dizer de novo reativa a mesma linha
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "Porto Belo"}'::jsonb, 'é em Porto Belo');
    perform pg_temp.grava();
    v_id := pg_temp.local('Porto Belo');
    perform pg_temp.desfaz('OS-J3');
    perform pg_temp.plan('OS-J3', '{"local": "Porto Belo"}'::jsonb, 'é em Porto Belo');
    perform pg_temp.grava(date '2027-07-16', '19:00');
    v_res := pg_temp.ok(v_res, 'O2j dizer de novo reativa a mesma linha, não cria outra', (select count(*) from public.agenda_locais x where x.nome = 'Porto Belo') = 1 and (select x.ativo from public.agenda_locais x where x.id = v_id)
                        and (pg_temp.pl('OS-J3')).local_id = v_id, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O2j quebrou', false, sqlerrm);
  end;
  -- A cidade do cliente da OS manda sobre a dos outros (a grafia e a UF mais comuns)
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J3', 'Porto Belo', 'SC');
    update public.clients c set city = 'PORTO BELO', state = 'PR' where c.id in (select so.client_id from public.service_orders so where so.service_order_number in ('OS-J6', 'OS-J7', 'OS-J8'));
    v_res := pg_temp.ok(v_res, 'O2j2 a cidade do cliente da OS vem primeiro', public._agenda_municipio_conhecido('Porto Belo', pg_temp.os('OS-J3')) = '{"municipio": "Porto Belo", "uf": "SC"}'::jsonb,
                        (public._agenda_municipio_conhecido('Porto Belo', pg_temp.os('OS-J3')))::text);
    v_res := pg_temp.ok(v_res, 'O2j3 sem ela, a mais comum dos outros clientes', public._agenda_municipio_conhecido('Porto Belo', pg_temp.os('OS-J1')) = '{"municipio": "PORTO BELO", "uf": "PR"}'::jsonb,
                        (public._agenda_municipio_conhecido('Porto Belo', pg_temp.os('OS-J1')))::text);
    v_res := pg_temp.ok(v_res, 'O2j4 o fim do nome também: "… em Porto Belo"', public._agenda_municipio_conhecido('Marina do João em Porto Belo', pg_temp.os('OS-J3')) ->> 'municipio' = 'Porto Belo', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O2j2 quebrou', false, sqlerrm);
  end;
  -- A cidade desconhecida
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "sítio do zé"}'::jsonb, 'é no sítio do zé');
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.tipo = 'outro';
    v_res := pg_temp.ok(v_res, 'O2k fora dos municípios conhecidos: cidade e UF nulas, o nome com a caixa arrumada', l.nome = 'Sítio do Zé' and l.municipio is null and l.uf is null, to_jsonb(l)::text);
    v_t := pg_temp.foco(date '2027-07-16', pg_temp.os('OS-J3'));
    v_res := pg_temp.ok(v_res, 'O2l o nulo não apaga o texto: o foco diz o nome', v_t ~ '^Vanderlei \(OS-J3\): Sítio do Zé \(você disse\)\.', v_t);
    v_res := pg_temp.ok(v_res, 'O2m feriado: cidade desconhecida (nenhum dia fechado em 20/07)', public._agenda_local_mascara(pg_temp.os('OS-J3'), date '2027-07-19', date '2027-07-21', date '2027-07-16') -> 'dias' = '[]'::jsonb, null);
    v_res := pg_temp.ok(v_res, 'O2n viagem: cidade desconhecida segue o km e o padrão, sem nulo', public._agenda_viagem_da_os(pg_temp.os('OS-J3'), date '2027-07-16') ->> 'tipo' = 'regional', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O2k quebrou', false, sqlerrm);
  end;
  -- As recusas, a caixa, a cidade com locais
  begin
    perform pg_temp.base('sombra');
    for r in select jsonb_build_object('l', x.l, 'm', x.m, 'o', x.o) from (values
        ('dia 5', 'local_data', 'parece uma data'), ('5', 'local_data', 'não é um lugar'), ('13/11', 'local_data', 'não é um lugar'), ('dia cinco', 'local_data', 'parece uma data'),
        ('sexta', 'local_data', 'parece uma data'), ('amanhã', 'local_data', 'parece uma data'), ('não sei', 'local_vazio', 'Não entendi o lugar'),
        ('com o cliente', 'local_vazio', 'Não entendi o lugar'), ('casa', 'local_vazio', 'Não entendi o lugar'), (repeat('a', 61), 'local_longo', 'passa de 60 letras')) x(l, m, o) loop
      r2 := pg_temp.plan('OS-J3', jsonb_build_object('local', r ->> 'l'), 'é ' || (r ->> 'l'));
      v_res := pg_temp.ok(v_res, format('O2o "%s" recusa com a frase que explica', left(r ->> 'l', 12)), not (r2 ->> 'ok')::boolean and r2 ->> 'motivo' = r ->> 'm' and r2 ->> 'texto' like '%' || (r ->> 'o') || '%', r2::text);
    end loop;
    r2 := pg_temp.plan('OS-J3', jsonb_build_object('local', repeat('a', 60)), 'é ' || repeat('a', 60));
    v_res := pg_temp.ok(v_res, 'O2p 60 letras passam', (r2 ->> 'ok')::boolean, r2::text);
    update public.agenda_rascunho set estado = 'substituido' where estado = 'aberto';
    for r in select jsonb_build_object('l', x.l, 'n', x.n) from (values ('nova trento', 'Nova Trento'), ('NOVA TRENTO', 'Nova Trento'), ('em Nova Trento', 'Nova Trento'), ('fica no Sítio do Zé', 'Sítio do Zé'),
        ('posto BR de Itapema', 'Posto BR de Itapema'), ('galpão do joão.', 'Galpão do João'), ('outro lugar em Tijucas', 'Tijucas')) x(l, n) loop
      v_res := pg_temp.ok(v_res, format('O2q "%s" → "%s"', r ->> 'l', r ->> 'n'), public._agenda_local_novo(r ->> 'l') ->> 'nome' = r ->> 'n', public._agenda_local_novo(r ->> 'l')::text);
    end loop;
    r2 := pg_temp.plan('OS-J3', '{"local": "Balneário Camboriú"}'::jsonb, 'é em Balneário Camboriú');
    v_res := pg_temp.ok(v_res, 'O2r cidade com locais pergunta qual, com a saída "outro lugar em {cidade}"', not (r2 ->> 'ok')::boolean and r2 ->> 'motivo' = 'local_ambiguo' and r2 ->> 'texto' like 'Qual deles: MP Motorhomes (Balneário Camboriú), Tedesco Marina Garden Plaza (Balneário Camboriú) ou outro lugar em Balneário Camboriú?', r2::text);
    r2 := pg_temp.plan('OS-J3', '{"local": "Guaratuba"}'::jsonb, 'é em Guaratuba');
    v_res := pg_temp.ok(v_res, 'O2s com 1 local, também: "Penha" pode ser a casa do cliente, e o dono tem a saída', r2 ->> 'motivo' = 'local_ambiguo' and r2 ->> 'texto' = 'Qual deles: Iate Clube Caiobá (Guaratuba) ou outro lugar em Guaratuba?', r2::text);
    r2 := pg_temp.plan('OS-J3', '{"local": "outro lugar em Balneário Camboriú"}'::jsonb, 'é outro lugar em Balneário Camboriú');
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.tipo = 'outro';
    v_res := pg_temp.ok(v_res, 'O2t a saída entra: a cidade, com feriado e tudo', l.nome = 'Balneário Camboriú' and l.municipio = 'Balneário Camboriú' and l.uf = 'SC', to_jsonb(l)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O2o quebrou', false, sqlerrm);
  end;
  -- Só o dono cria: o M11 só pergunta
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    perform pg_temp.mandado('OS-J11');
    r := pg_temp.resp('OS-J11', 'está na marina do joão', 'outro');
    v_res := pg_temp.ok(v_res, 'O2u pelo M11 não muda: vira a pergunta local, e nenhuma linha nasce', r ->> 'efeito' = 'anotou_acesso' and not exists (select 1 from public.agenda_locais x where x.tipo = 'outro')
                        and exists (select 1 from public.agenda_perguntas q where q.chave = 'local:' || pg_temp.os('OS-J11') and q.estado = 'aberta'), r::text);
    r2 := pg_temp.plan('OS-J11', '{"local": "Marina do João"}'::jsonb, 'é na Marina do João');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'O2v ele repete pela conversa: entra, e a pergunta local fecha', pg_temp.local('Marina do João') is not null
                        and not exists (select 1 from public.agenda_perguntas q where q.chave = 'local:' || pg_temp.os('OS-J11') and q.estado = 'aberta'), r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O2u quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o2$;

-- ── O3. A casa do cliente ──────────────────────────────────────────────────────────────────
do $o3$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  l     public.agenda_locais;
  v_t   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O3', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cidade('OS-J3', 'Itapema');
    perform pg_temp.plan('OS-J3', '{"local": "na casa do cliente"}'::jsonb, 'o serviço do Vanderlei é na casa do cliente');
    perform pg_temp.grava();
    select * into l from public.agenda_locais x where x.tipo = 'casa_cliente';
    v_res := pg_temp.ok(v_res, 'O3a vira local: tipo casa_cliente, "casa de {nome curto}", a cidade e a UF do cliente, a chave por cliente', l.nome = 'casa de Vanderlei' and l.municipio = 'Itapema' and l.uf = 'SC'
                        and l.client_id = (select so.client_id from public.service_orders so where so.id = pg_temp.os('OS-J3')) and (pg_temp.pl('OS-J3')).local_id = l.id and (pg_temp.pl('OS-J3')).local_fonte = 'dono', to_jsonb(l)::text);
    v_res := pg_temp.ok(v_res, 'O3a2 sai o trecho: ele guarda só o que foi dito, sem nota', (pg_temp.pl('OS-J3')).trecho = 'o serviço do Vanderlei é na casa do cliente', (pg_temp.pl('OS-J3')).trecho);
    perform pg_temp.plan('OS-J5', '{"local": "na casa do cliente"}'::jsonb, 'é com ele');
    perform pg_temp.grava(date '2027-07-16', '17:05');
    v_res := pg_temp.ok(v_res, 'O3a3 sem a palavra "casa" no que ele disse, nada de nota também', (pg_temp.pl('OS-J5')).trecho = 'é com ele', (pg_temp.pl('OS-J5')).trecho);
    perform pg_temp.desfaz('OS-J5', date '2027-07-16', '17:06');
    v_t := pg_temp.foco(date '2027-07-16', pg_temp.os('OS-J3'));
    v_res := pg_temp.ok(v_res, 'O3b o foco diz o que ele disse', v_t like 'Vanderlei (OS-J3): na casa do cliente, em Itapema (você disse).%', v_t);
    v_res := pg_temp.ok(v_res, 'O3c a ficha também', public._agenda_local_da_os(pg_temp.os('OS-J3')) = 'na casa do cliente, em Itapema', public._agenda_local_da_os(pg_temp.os('OS-J3')));
    perform pg_temp.plan('OS-J3', '{"dias": 3}'::jsonb, 'o serviço do Vanderlei leva 3 dias');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_res := pg_temp.ok(v_res, 'O3d não some na frase seguinte', pg_temp.foco(date '2027-07-16', pg_temp.os('OS-J3')) = v_t and (pg_temp.pl('OS-J3')).dias = 3, null);
    v_res := pg_temp.ok(v_res, 'O3e o trecho guarda só o que ele disse: nada de nota lá', (pg_temp.pl('OS-J3')).trecho = 'o serviço do Vanderlei leva 3 dias', (pg_temp.pl('OS-J3')).trecho);
    -- A 2ª OS do mesmo cliente: a mesma linha
    perform pg_temp.plan('OS-J5', '{"local": "casa dele"}'::jsonb, 'o outro do Vanderlei é na casa dele');
    perform pg_temp.grava(date '2027-07-16', '17:20');
    v_res := pg_temp.ok(v_res, 'O3f 1 linha por cliente: a 2ª OS usa a mesma', (select count(*) from public.agenda_locais x where x.tipo = 'casa_cliente') = 1 and (pg_temp.pl('OS-J5')).local_id = l.id, null);
    r := pg_temp.desfaz('OS-J5', date '2027-07-16', '17:30');
    v_res := pg_temp.ok(v_res, 'O3g o *desfaz* volta, e a linha fica: a outra OS usa', (pg_temp.pl('OS-J5')).local_id is null and (select x.ativo from public.agenda_locais x where x.id = l.id), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O3 quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J3', '{"local": "na casa do cliente"}'::jsonb, 'o serviço do Vanderlei é na casa do cliente');
    perform pg_temp.grava();
    r := pg_temp.desfaz('OS-J3');
    v_res := pg_temp.ok(v_res, 'O3h o *desfaz* responde e volta a supor; a linha criada some', (pg_temp.pl('OS-J3')).local_id is null and not exists (select 1 from public.agenda_locais x where x.tipo = 'casa_cliente' and x.ativo)
                        and r #>> '{gravou,ok}' = 'true', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O3h quebrou', false, sqlerrm);
  end;
  -- O pátio não cobra, o acesso segue o R1, o M11 não pergunta
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_patio', 'ligado');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.aloca('OS-J3', date '2027-07-27', 'manha');
    v_res := pg_temp.ok(v_res, 'O3i o contraste: no pátio suposto, a entrada nasce', pg_temp.item('OS-J3', 'entrada', date '2027-07-16') is not null, null);
    perform pg_temp.plan('OS-J3', '{"local": "na casa do cliente"}'::jsonb, 'é na casa do cliente');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'O3j na casa do cliente, o pátio não cobra entrada', pg_temp.item('OS-J3', 'entrada', date '2027-07-16') is null, null);
    r := pg_temp.item('OS-J3', 'acesso', date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'O3k o acesso de casa_cliente segue o R1: preparo, com o texto do local', r is not null and r ->> 'texto' like 'o acesso de Rafael para ter 27/07%' and not (r ->> 'combinado')::boolean, r::text);
    v_res := pg_temp.ok(v_res, 'O3l o M11 não pergunta de novo', public._agenda_cliente_onde_falta(pg_temp.os('OS-J3'), date '2027-07-16') is null, null);
    v_res := pg_temp.ok(v_res, 'O3m a casa de um cliente não é local de outro: o resolvedor não a acha', public.agenda_resolver_local('Vanderlei', date '2027-07-16') ->> 'status' = 'nao_achei'
                        and public._agenda_local_proposto(pg_temp.os('OS-J4'), 'fica na casa de Vanderlei', date '2027-07-16') ->> 'local_id' is null, null);
    v_res := pg_temp.ok(v_res, 'O3n o cadastro não conta a casa', pg_temp.foco() ~ 'Locais: 5 no cadastro', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O3i quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o3$;

-- ── O4. Serviço começado ───────────────────────────────────────────────────────────────────
do $o4$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-26';
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O4', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('ligado');
    -- J1 no pátio, J2 na Marina Itajaí em garagem seca com teste na água: as 4 cobranças. Os 2 com um dia passado e um dia à frente.
    perform pg_temp.aloca('OS-J1', date '2027-07-27', 'manha', 'Alex');
    perform pg_temp.aloca('OS-J2', date '2027-07-27', 'manha', 'Roberto');
    perform pg_temp.aloca('OS-J2', date '2027-07-27', 'tarde', 'Roberto');
    v_res := pg_temp.ok(v_res, 'O4a a régua: com o plano por começar, as 4 nascem', pg_temp.item('OS-J1', 'entrada', date '2027-07-19') is not null and pg_temp.item('OS-J2', 'acesso', date '2027-07-19') is not null
                        and pg_temp.item('OS-J2', 'reserva_marina', date '2027-07-19') is not null and pg_temp.item('OS-J2', 'descida', date '2027-07-19') is not null, null);
    v_res := pg_temp.ok(v_res, 'O4b no 1º dia, o serviço começou: nada nasce (plano_comecou: min(dia) <= hoje)', public._agenda_combinar_da_os(pg_temp.os('OS-J1'), date '2027-07-20') = '[]'::jsonb
                        and public._agenda_combinar_da_os(pg_temp.os('OS-J2'), date '2027-07-20') = '[]'::jsonb, null);
    v_res := pg_temp.ok(v_res, 'O4c com o serviço em curso e um dia à frente: nada nasce', public._agenda_combinar_da_os(pg_temp.os('OS-J1'), v_h) = '[]'::jsonb and public._agenda_combinar_da_os(pg_temp.os('OS-J2'), v_h) = '[]'::jsonb, null);
    perform pg_temp.combinar(v_h);
    v_res := pg_temp.ok(v_res, 'O4d a rodada não pergunta nem a entrada nem o acesso a quem já está lá', not exists (select 1 from public.agenda_perguntas q where q.tipo in ('combinar', 'acesso') and q.service_order_id in (pg_temp.os('OS-J1'), pg_temp.os('OS-J2'))), null);
    v_res := pg_temp.ok(v_res, 'O4e nem a ação em teste', not exists (select 1 from public.agenda_acoes a where a.tipo = 'local' and a.service_order_id in (pg_temp.os('OS-J1'), pg_temp.os('OS-J2'))), null);
    v_res := pg_temp.ok(v_res, 'O4f o foco segue a mesma fonte: nem "Combinar" nem "Em teste, eu cobraria"', pg_temp.foco(v_h, pg_temp.os('OS-J2')) !~ '(Combinar|eu cobraria)' and pg_temp.foco(v_h, pg_temp.os('OS-J1')) !~ '(Combinar|eu cobraria)', pg_temp.foco(v_h, pg_temp.os('OS-J2')));
    perform pg_temp.base('sombra');
    v_res := pg_temp.ok(v_res, 'O4g o foco em teste também', pg_temp.foco(v_h, pg_temp.os('OS-J1')) !~ 'eu cobraria', null);
    perform pg_temp.base('ligado');
    v_res := pg_temp.ok(v_res, 'O4h a ficha do dia à frente não diz que o acesso não está confirmado', public.agenda_equipe_ficha(pg_temp.pessoa('Roberto'), date '2027-07-27', date '2027-07-26') ->> 'texto_ficha' !~ 'O acesso', null);
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, modo, criada_em, expira_em)
    values ('combinar', format('combinar:entrada:%s:%s', pg_temp.os('OS-J1'), date '2027-07-27'), pg_temp.os('OS-J1'), array[pg_temp.os('OS-J1')], date '2027-07-27', date '2027-07-27', 'Lenine já combinou trazer o motorhome ao pátio?',
            '[{"n":1,"texto":"Já combinou"},{"n":2,"texto":"Ainda não"}]'::jsonb, 'ligado', pg_temp.em(v_h, '09:00'), pg_temp.em(date '2027-07-28', '00:00'));
    perform public._agenda_local_resolver(v_h, pg_temp.em(v_h, '16:20'));
    v_res := pg_temp.ok(v_res, 'O4h2 a pergunta que estava aberta fecha, com o motivo verdadeiro', (select q.resolvida_motivo from public.agenda_perguntas q where q.chave = format('combinar:entrada:%s:%s', pg_temp.os('OS-J1'), date '2027-07-27')) = 'o serviço já começou', null);
    -- Só a OS que começou sai: a do lado segue sendo cobrada
    v_res := pg_temp.ok(v_res, 'O4i quem não começou segue cobrado', pg_temp.item('OS-J12', 'acesso', date '2027-07-19') is not null, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O4 quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o4$;

-- ── O5. "Eu te aviso" ─────────────────────────────────────────────────────────────────────
do $o5$
declare
  v_res  jsonb := '[]'::jsonb;
  v_rob  uuid;
  v_txt  text;
  v_h    date := date '2027-07-19';
  v_d    date := date '2027-07-20';
  r      jsonb;
  m      public.agenda_equipe_mensagens;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O5', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set modo_equipe = 'ligado' where id;
    perform set_config('agenda.hoje', v_h::text, true);
    perform pg_temp.contato('Roberto');
    v_rob := pg_temp.pessoa('Roberto');
    v_txt := public.agenda_equipe_ficha(v_rob, v_d, v_h) ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'O5a a régua: a ficha sai com a frase', v_txt ~ 'O acesso na Marina Itajaí ainda não está confirmado: eu te aviso\.', v_txt);
    r := public._agenda_equipe_registrar(v_rob, v_d, 'ficha', v_txt, pg_temp.em(v_h, '19:30'));
    v_res := pg_temp.ok(v_res, 'O5b ela foi à fila', r ->> 'estado' = 'enfileirada', r::text);
    r := public._agenda_local_avisar_acesso(v_h, pg_temp.em(v_h, '19:45'));
    v_res := pg_temp.ok(v_res, 'O5c sem o acesso combinado, nada sai', (r ->> 'avisos')::int = 0, r::text);
    update public.os_planejamento set acesso_ok_em = pg_temp.em(v_h, '19:40') where service_order_id = pg_temp.os('OS-J2');
    r := public._agenda_local_avisar_acesso(v_h, pg_temp.em(v_h, '19:45'));
    select * into m from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.dedupe_key like '%:acesso:%';
    v_res := pg_temp.ok(v_res, 'O5d combinado: sai à pessoa, o texto da decisão, pelo caminho da ficha', (r ->> 'avisos')::int = 1 and m.texto = 'O acesso na Marina Itajaí está confirmado para amanhã (ter 20/07).' and m.estado = 'enfileirada'
                        and exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-equipe' and q.source_ref_id = m.id), to_jsonb(m)::text);
    r := public._agenda_local_avisar_acesso(v_h, pg_temp.em(v_h, '19:50'));
    v_res := pg_temp.ok(v_res, 'O5e uma vez só por pessoa e dia', (r ->> 'avisos')::int = 0 and (select count(*) from public.agenda_equipe_mensagens x where x.payee_id = v_rob and x.dedupe_key like '%:acesso:%') = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O5 quebrou', false, sqlerrm);
  end;
  -- As travas
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set modo_equipe = 'ligado' where id;
    perform set_config('agenda.hoje', v_h::text, true);
    perform pg_temp.contato('Roberto');
    v_rob := pg_temp.pessoa('Roberto');
    perform public._agenda_equipe_registrar(v_rob, v_d, 'ficha', public.agenda_equipe_ficha(v_rob, v_d, v_h) ->> 'texto_ficha', pg_temp.em(v_h, '19:30'));
    update public.os_planejamento set acesso_ok_em = pg_temp.em(v_h, '19:40') where service_order_id = pg_temp.os('OS-J2');
    r := public._agenda_local_avisar_acesso(v_h, pg_temp.em(v_h, '20:10'));
    v_res := pg_temp.ok(v_res, 'O5f fora da janela da ficha, espera: nem registra', r ->> 'pulado' = 'janela' and not exists (select 1 from public.agenda_equipe_mensagens x where x.dedupe_key like '%:acesso:%'), r::text);
    update public.agenda_config set gestor_so_propor = true where id;
    r := public.agenda_local_vigiar(v_d, pg_temp.em(v_d, '07:45'));
    v_res := pg_temp.ok(v_res, 'O5g com o freio, o modo é sombra: a vigia não avisa', not exists (select 1 from public.agenda_equipe_mensagens x where x.dedupe_key like '%:acesso:%'), r::text);
    update public.agenda_config set gestor_so_propor = false, modo_local_autorizacao = 'sombra' where id;
    r := public.agenda_local_vigiar(v_d, pg_temp.em(v_d, '07:45'));
    v_res := pg_temp.ok(v_res, 'O5h em teste, a vigia não avisa', not exists (select 1 from public.agenda_equipe_mensagens x where x.dedupe_key like '%:acesso:%'), r::text);
    update public.agenda_config set modo_local_autorizacao = 'ligado', modo_equipe = 'sombra' where id;
    r := public.agenda_local_vigiar(v_d, pg_temp.em(v_d, '07:45'));
    v_res := pg_temp.ok(v_res, 'O5i sem a ficha ligada, não avisa', not exists (select 1 from public.agenda_equipe_mensagens x where x.dedupe_key like '%:acesso:%'), r::text);
    update public.agenda_config set modo_equipe = 'ligado' where id;
    r := public.agenda_local_vigiar(v_d, pg_temp.em(v_d, '07:45'));
    select * into m from public.agenda_equipe_mensagens x where x.dedupe_key like '%:acesso:%';
    v_res := pg_temp.ok(v_res, 'O5j ligados, no tique da manhã do próprio dia (a OS é lida com o dia da ficha): sai', m.texto = 'O acesso na Marina Itajaí está confirmado para hoje (ter 20/07).', to_jsonb(m)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O5f quebrou', false, sqlerrm);
  end;
  -- A ficha colada no "como foi" (quem trabalha hoje e amanhã): leva a frase em texto_curto
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set modo_equipe = 'ligado' where id;
    perform set_config('agenda.hoje', v_h::text, true);
    perform pg_temp.contato('Roberto');
    v_rob := pg_temp.pessoa('Roberto');
    perform public._agenda_equipe_registrar(v_rob, v_h, 'como_foi', 'Como foi hoje?' || coalesce(public.agenda_equipe_ficha(v_rob, v_d, v_h) ->> 'texto_curto', ''), pg_temp.em(v_h, '17:00'), v_d);
    update public.os_planejamento set acesso_ok_em = pg_temp.em(v_h, '17:10') where service_order_id = pg_temp.os('OS-J2');
    r := public._agenda_local_avisar_acesso(v_h, pg_temp.em(v_h, '17:15'));
    select * into m from public.agenda_equipe_mensagens x where x.dedupe_key like '%:acesso:%';
    v_res := pg_temp.ok(v_res, 'O5k a ficha colada no "como foi" também: leva_ficha_de', (r ->> 'avisos')::int = 1 and m.dia = v_d, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O5k quebrou', false, sqlerrm);
  end;
  -- A ficha que não saiu não promete nada; a que saiu sem a frase, também não
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set modo_equipe = 'ligado' where id;
    perform set_config('agenda.hoje', v_h::text, true);
    perform pg_temp.contato('Roberto');
    v_rob := pg_temp.pessoa('Roberto');
    perform public._agenda_equipe_registrar(v_rob, v_d, 'ficha', 'Roberto, amanhã: sem a frase. Responde OK se tá certo.', pg_temp.em(v_h, '19:30'));
    update public.os_planejamento set acesso_ok_em = pg_temp.em(v_h, '19:40') where service_order_id = pg_temp.os('OS-J2');
    r := public._agenda_local_avisar_acesso(v_h, pg_temp.em(v_h, '19:45'));
    v_res := pg_temp.ok(v_res, 'O5l a ficha sem a frase não prometeu nada: nada sai', (r ->> 'avisos')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O5l quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o5$;

-- ── O6. Os autorizados ─────────────────────────────────────────────────────────────────────
do $o6$
declare
  v_res jsonb := '[]'::jsonb;
  v_a   record;
  v_t   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O6', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.plan('OS-J3', '{"autorizados": ["Roberto", "João"]}'::jsonb, 'Roberto e João estão autorizados no serviço do Vanderlei');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'O6a com o local suposto, grava local_id nulo', (select count(*) from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J3') and x.local_id is null and x.revogado_em is null) = 2, null);
    perform pg_temp.plan('OS-J3', '{"local": "Marina Itajaí"}'::jsonb, 'o serviço do Vanderlei é na Marina Itajaí');
    perform pg_temp.grava(date '2027-07-16', '17:10');
    v_t := public._agenda_autorizacao_da_os(pg_temp.os('OS-J3'), date '2027-07-16') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'O6b dito o local depois, a lista sobrevive: não some em silêncio', v_t = 'Autorizados nesse serviço: João e Roberto.', v_t);
    v_res := pg_temp.ok(v_res, 'O6c e aparece no foco', pg_temp.foco(date '2027-07-16', pg_temp.os('OS-J3')) ~ 'Autorizados nesse serviço: João e Roberto\.', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O6 quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.plan('OS-J12', '{"autorizados": ["Roberto"]}'::jsonb, 'o Roberto está autorizado');
    perform pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'O6d com o local dito (a OS diz), fica o local', (select x.local_id from public.os_autorizados x where x.service_order_id = pg_temp.os('OS-J12') and x.payee_id = pg_temp.pessoa('Roberto')) = pg_temp.local('Marina Itajaí'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O6d quebrou', false, sqlerrm);
  end;
  -- A opção 1 da pergunta do acesso, com o local suposto pela marina do bem: a mesma regra
  begin
    perform pg_temp.base('sombra');
    update public.service_orders set marina_id = (select id from public.marinas where name = 'Marina do Teste O6') where id = pg_temp.os('OS-J12');
    update public.vessels set marina_id = (select marina_id from public.agenda_locais where nome = 'Marina Itajaí') where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-J12'));
    insert into public.marinas (name, city, active) values ('Marina Fora do Cadastro', 'Itajaí', true);
    update public.service_orders set marina_id = (select id from public.marinas where name = 'Marina Fora do Cadastro') where id = pg_temp.os('OS-J12');
    v_res := pg_temp.ok(v_res, 'O6e o item do acesso com o local suposto leva local_id nulo', (public._agenda_local_resolvido(pg_temp.os('OS-J12'), date '2027-07-16') ->> 'suposicao')::boolean
                        and pg_temp.item('OS-J12', 'acesso', date '2027-07-16') ->> 'local_id' is null, (pg_temp.item('OS-J12', 'acesso', date '2027-07-16'))::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O6e quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o6$;

-- ── O7. A data sem mês ─────────────────────────────────────────────────────────────────────
do $o7$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  r     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O7', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_res := pg_temp.ok(v_res, 'O7a agenda_data_dita não muda: "dia 5" no sentido futuro segue indo ao mês que vem', public.agenda_data_dita('dia 5', date '2026-11-06', 'futuro') ->> 'de' = '2026-12-05', null);
  begin
    v_res := pg_temp.ok(v_res, 'O7b quem tem mês não é "sem mês"', public._agenda_data_sem_mes('dia 5') and public._agenda_data_sem_mes('5') and public._agenda_data_sem_mes('terça') and public._agenda_data_sem_mes('no dia cinco')
                        and not public._agenda_data_sem_mes('05/11') and not public._agenda_data_sem_mes('dia 05/11') and not public._agenda_data_sem_mes('5 de novembro') and not public._agenda_data_sem_mes('amanhã') and not public._agenda_data_sem_mes('daqui a 3 dias'), null);
  exception when others then v_res := pg_temp.ok(v_res, 'O7b quebrou', false, sqlerrm);
  end;
  for c in select * from (values
      -- hoje, chega_em, sai_em, trecho, entrada esperada, saída esperada
      (date '2026-11-06', 'dia 5', 'dia 13', 'o motorhome do Lenine chega dia 5 e ele busca dia 13', date '2026-11-05', date '2026-11-13', 'a frase do roteiro: chegada depois da saída dita na mesma frase'),
      (date '2026-11-06', 'dia 5', null, 'o motorhome chegou dia 5', date '2026-11-05', null::date, 'verbo no passado: o mês corrente'),
      (date '2026-11-06', 'dia 20', null, 'ele veio dia 20', date '2026-10-20', null, 'passou de hoje: o mês anterior'),
      (date '2026-11-06', 'dia 5', null, 'entrou dia 5', date '2026-11-05', null, '"entrou"'),
      (date '2026-11-06', 'dia 5', null, 'trouxe dia 5', date '2026-11-05', null, '"trouxe"'),
      (date '2026-11-06', 'dia 5', null, 'deixou aqui dia 5', date '2026-11-05', null, '"deixou"'),
      (date '2026-11-06', 'dia 5', null, 'já está aí desde dia 5', date '2026-11-05', null, '"já está"'),
      (date '2026-11-06', 'terça', null, 'chegou terça', date '2026-11-03', null, 'o dia da semana também não tem mês: a terça que passou'),
      (date '2026-11-06', 'dia 5', null, 'chega dia 5', date '2026-12-05', null, 'sem verbo no passado e sem saída: o futuro, como sempre'),
      (date '2026-11-06', '05/11', null, 'chegou 05/11', date '2026-11-05', null, 'com o mês, a data dita'),
      (date '2026-11-06', '05/12', null, 'chegou 05/12', date '2026-12-05', null, 'com o mês, nem o verbo muda a data'),
      (date '2026-11-06', 'dia 20', 'dia 28', 'chega dia 20 e sai dia 28', date '2026-11-20', date '2026-11-28', 'sem conflito, nada muda'),
      (date '2026-11-06', 'dia 5', '20/11', 'chega dia 5 e sai 20/11', date '2026-11-05', date '2026-11-20', 'a saída com mês puxa a chegada'),
      (date '2026-11-06', 'dia 5', 'dia 5', 'chega dia 5 e sai dia 5', date '2026-11-05', date '2026-12-05', 'o mesmo dia: a chegada fica antes')
    ) t(hoje, chega, sai, trecho, ent, sai_esp, nome) loop
    begin
      perform pg_temp.base('sombra');
      update public.agenda_rascunho set estado = 'substituido' where estado = 'aberto';
      r := pg_temp.plan('OS-J11', jsonb_strip_nulls(jsonb_build_object('chega_em', c.chega, 'sai_em', c.sai)), c.trecho, c.hoje);
      v_res := pg_temp.ok(v_res, format('O7c %s', c.nome), (r ->> 'ok')::boolean
                          and (select (x.dados ->> 'entrada_em')::date from public.agenda_rascunho x where x.estado = 'aberto' and x.tipo = 'planejar') = c.ent
                          and (select (x.dados ->> 'retirada_em')::date from public.agenda_rascunho x where x.estado = 'aberto' and x.tipo = 'planejar') is not distinct from c.sai_esp, r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, format('O7c %s quebrou', c.nome), false, sqlerrm);
    end;
  end loop;
  begin
    perform pg_temp.base('sombra');
    r := pg_temp.plan('OS-J11', '{"chega_em": "dia 31", "sai_em": "dia 10"}'::jsonb, 'chega dia 31 e sai dia 10', date '2027-05-05');
    -- (correção da 7d, Onda 3, T7) era a recusa: agora a saída sem mês anda para depois da chegada
    v_res := pg_temp.ok(v_res, 'O7c2 nem o mês da saída nem o anterior têm o dia antes dela: a saída sem mês anda para depois da chegada', r ->> 'item' like '%O motorhome chega seg 31/05 e sai qui 10/06.%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O7c2 quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    r := pg_temp.plan('OS-J11', '{"chega_em": "dia 5", "sai_em": "dia 13"}'::jsonb, 'o motorhome chega dia 5 e ele busca dia 13', date '2026-11-06');
    v_res := pg_temp.ok(v_res, 'O7d a data aparece na releitura, por extenso, antes do *grava*', r ->> 'item' like '%O motorhome chega qui 05/11 e sai sex 13/11. %', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O7d quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o7$;

-- ── O10. Cobrar antes de vencer ────────────────────────────────────────────────────────────
do $o10$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  v_q   public.agenda_perguntas;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O10', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('ligado');
    -- J2: vaga e descida com ate = hoje; J1: entrada com ate = hoje
    v_res := pg_temp.ok(v_res, 'O10a os 3 vencem no próprio prazo', (pg_temp.item('OS-J2', 'reserva_marina', v_h) ->> 'vencido')::boolean and (pg_temp.item('OS-J2', 'descida', v_h) ->> 'vencido')::boolean
                        and (pg_temp.item('OS-J1', 'entrada', v_h) ->> 'vencido')::boolean and pg_temp.item('OS-J2', 'reserva_marina', v_h) ->> 'ate' = v_h::text, null);
    v_res := pg_temp.ok(v_res, 'O10b um dia antes do prazo, não', not (pg_temp.item('OS-J2', 'reserva_marina', v_h - 1) ->> 'vencido')::boolean and not (pg_temp.item('OS-J1', 'entrada', v_h - 1) ->> 'vencido')::boolean, null);
    perform pg_temp.combinar(v_h);
    select * into v_q from public.agenda_perguntas q where q.tipo = 'combinar' and q.chave like 'combinar:reserva_marina:%' and q.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'O10c a vaga nasce no prazo: "O prazo é hoje."', v_q.texto like '%O prazo é hoje.%' and v_q.texto not like '%O prazo era%', v_q.texto);
    select * into v_q from public.agenda_perguntas q where q.tipo = 'combinar' and q.chave like 'combinar:entrada:%' and q.service_order_id = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'O10d a entrada também', v_q.texto = 'Lenine já combinou trazer o motorhome ao pátio para ter 20/07? O prazo é hoje. 1) Já combinou (anoto que chega ter 20/07); 2) Ainda não.', v_q.texto);
    v_res := pg_temp.ok(v_res, 'O10e a descida nasce', exists (select 1 from public.agenda_perguntas q where q.chave like 'combinar:descida:%' and q.service_order_id = pg_temp.os('OS-J2')), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O10 quebrou', false, sqlerrm);
  end;
  -- A crítica da véspera não dobra a mesma pergunta: em D-1 a combinar do acesso fecha, a crítica nasce; a vaga é outra pergunta
  begin
    perform pg_temp.base('ligado');
    perform pg_temp.combinar(v_h);
    perform pg_temp.combinar(date '2027-07-19');
    v_res := pg_temp.ok(v_res, 'O10f D-1: uma pergunta só do acesso, a crítica', (select count(*) from public.agenda_perguntas q where q.estado = 'aberta' and q.service_order_id = pg_temp.os('OS-J2') and q.tipo in ('combinar', 'acesso') and (q.tipo = 'acesso' or q.chave like 'combinar:acesso:%')) = 1
                        and exists (select 1 from public.agenda_perguntas q where q.estado = 'aberta' and q.tipo = 'acesso' and q.service_order_id = pg_temp.os('OS-J2')), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O10f quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o10$;

-- ── O14 e O15. O calendário e o motivo ─────────────────────────────────────────────────────
do $o14$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-15';
  v_ag  timestamptz := pg_temp.em(date '2027-07-15', '16:20');
  v     jsonb;
  v_t   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O14', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    v_res := pg_temp.ok(v_res, 'O14a a régua: suposto no pátio sem viagem dita, o feriado de BC vale', public._agenda_local_mascara(pg_temp.os('OS-J3'), date '2027-07-19', date '2027-07-21', v_h) -> 'dias' = '[2]'::jsonb, null);
    update public.os_planejamento set viagem = 'regional' where service_order_id = pg_temp.os('OS-J3');
    insert into public.os_planejamento (service_order_id, viagem) values (pg_temp.os('OS-J3'), 'regional') on conflict (service_order_id) do update set viagem = 'regional';
    v_res := pg_temp.ok(v_res, 'O14b viagem regional dita: segue no pátio, o feriado vale', public._agenda_local_mascara(pg_temp.os('OS-J3'), date '2027-07-19', date '2027-07-21', v_h) -> 'dias' = '[2]'::jsonb, null);
    update public.os_planejamento set viagem = 'pernoite' where service_order_id = pg_temp.os('OS-J3');
    v_res := pg_temp.ok(v_res, 'O14c viagem dita com o local suposto: lugar desconhecido para o calendário', public._agenda_local_mascara(pg_temp.os('OS-J3'), date '2027-07-19', date '2027-07-21', v_h) -> 'dias' = '[]'::jsonb, null);
    update public.os_planejamento set viagem = 'bate_volta' where service_order_id = pg_temp.os('OS-J3');
    v_res := pg_temp.ok(v_res, 'O14d ida e volta dita, também', public._agenda_local_mascara(pg_temp.os('OS-J3'), date '2027-07-19', date '2027-07-21', v_h) -> 'dias' = '[]'::jsonb, null);
    update public.os_planejamento set viagem = 'pernoite', local_id = pg_temp.local('MP Motorhomes'), local_fonte = 'dono', local_em = now() where service_order_id = pg_temp.os('OS-J3');
    v_res := pg_temp.ok(v_res, 'O14e o local DITO no pátio segue fechando: só o suposto sai', public._agenda_local_mascara(pg_temp.os('OS-J3'), date '2027-07-19', date '2027-07-21', v_h) -> 'dias' = '[2]'::jsonb, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O14 quebrou', false, sqlerrm);
  end;
  -- O motor sem encaixe diz o motivo: 40 dias de viagem não cabem no horizonte
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_viagem', 'ligado');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado', modo_vaga_fechamento = 'ligado',
           marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03' where id;
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado', cancelada_em = v_ag where service_order_id = pg_temp.os('OS-J1');
    insert into public.os_planejamento (service_order_id, viagem, dias, estimativa_fonte) values (pg_temp.os('OS-J1'), 'pernoite', 40, 'dono')
    on conflict (service_order_id) do update set viagem = 'pernoite', dias = 40, estimativa_fonte = 'dono';
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-J1')], '{}'::jsonb, false, 'vigia', null, v_h, v_ag);
    v_t := (select string_agg(f ->> 'texto', ' | ') from jsonb_array_elements(v -> 'fora') f);
    v_res := pg_temp.ok(v_res, 'O14f a pernoite sem encaixe diz o motivo, não "a equipe de hoje"', v_t ~ '^Lenine \(OS-J1\): a viagem precisa de [0-9]+ dias úteis seguidos com a mesma equipe, e não achei essa janela em [0-9]+ semanas\.$', coalesce(v_t, v::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O14f quebrou', false, sqlerrm);
  end;
  -- O15: o feriado do município no texto do item
  begin
    perform pg_temp.base('sombra');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado', modo_vaga_fechamento = 'ligado',
           marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03' where id;
    update public.os_planejamento set dono_presenca = 'nunca' where service_order_id in (pg_temp.os('OS-J3'), pg_temp.os('OS-J4'), pg_temp.os('OS-J5'), pg_temp.os('OS-J9'), pg_temp.os('OS-J10'));
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado', cancelada_em = v_ag where dia = date '2027-07-20';
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    perform set_config('agenda.hoje', v_h::text, true);
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-J3')], '{}'::jsonb, false, 'vigia', null, v_h, v_ag);
    v_t := (select i ->> 'texto' from jsonb_array_elements(v -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'os' = pg_temp.os('OS-J3')::text order by i ->> 'tipo' = 'reserva' limit 1);
    v_res := pg_temp.ok(v_res, 'O15a o item diz o motivo, como o nacional', v_t ~ '\(ter 20 é feriado em Balneário Camboriú\)', coalesce(v_t, v::text));
    perform pg_temp.modo('modo_local_calendario', 'sombra');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-J3')], '{}'::jsonb, false, 'vigia', null, v_h, v_ag);
    v_t := (select i ->> 'texto' from jsonb_array_elements(v -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'os' = pg_temp.os('OS-J3')::text limit 1);
    v_res := pg_temp.ok(v_res, 'O15b em teste, o texto é o de antes', v_t !~ 'feriado', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O15 quebrou', false, sqlerrm);
  end;
  begin
    v_res := pg_temp.ok(v_res, 'O15c a função: só o feriado dentro do bloco, sem o parêntese da máscara; sábado do local não entra',
      public._agenda_feriado_do_bloco('{"5": "ter 20/07 é feriado em Balneário Camboriú (aniversário da cidade)", "9": "sáb 24/07: X não abre no sábado"}'::jsonb, date '2027-07-16', date '2027-07-19', date '2027-07-26') = 'ter 20 é feriado em Balneário Camboriú'
      and public._agenda_feriado_do_bloco('{"5": "ter 20/07 é feriado em Balneário Camboriú (aniversário da cidade)"}'::jsonb, date '2027-07-16', date '2027-07-21', date '2027-07-26') is null, null);
  exception when others then v_res := pg_temp.ok(v_res, 'O15c quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o14$;

-- ── O18. A releitura da crítica ────────────────────────────────────────────────────────────
do $o18$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-19';
  r     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O18', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_perguntas set estado = 'descartada', resolvida_motivo = 'teste' where estado = 'aberta';
    perform pg_temp.combinar(v_h);
    r := public.agenda_rascunho_aplicar(pg_temp.adm(), 'whatsapp', null, null, null, '1', '1', v_h, pg_temp.em(v_h, '17:40'));
    v_res := pg_temp.ok(v_res, 'O18a a releitura da crítica diz qual é', r ->> 'item' like 'Decisão: na pergunta "Amanhã (ter 20/07) %": Está combinado', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O18 quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o18$;

-- ── O19 e R3, R4, R5. O M11 ────────────────────────────────────────────────────────────────
do $m11$
declare
  v_res jsonb := '[]'::jsonb;
  m     public.agenda_cliente_mensagens;
  m1    uuid;
  r     jsonb;
  q     public.agenda_perguntas;
  c     record;
  v_ctx jsonb;
  v_antes jsonb;
  v_dep jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('M11', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- O19, o exemplo
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    perform pg_temp.mandado('OS-J11');
    r := pg_temp.resp('OS-J11', 'está no sítio do meu irmão', 'outro');
    select * into q from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J11');
    v_res := pg_temp.ok(v_res, 'O19a o exemplo é lugar, não data', q.texto like '%por exemplo: "o serviço do Carla é na Marina Itajaí".' and q.texto not like '%chega dia 5%', q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O19a quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    perform pg_temp.mandado('OS-J11');
    r := pg_temp.resp('OS-J11', 'posso levar dia 20', 'data');
    select * into q from public.agenda_perguntas x where x.tipo = 'cliente_resposta' and x.service_order_id = pg_temp.os('OS-J11') and x.estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'O19b disse data e não lugar: a pergunta diz que ele respondeu sem dizer onde, com o exemplo de lugar', r ->> 'efeito' = 'ao_dono'
                        and q.texto = 'Carla respondeu sem dizer onde fica o motorhome: "posso levar dia 20". Me diga onde é, por exemplo: "o serviço de Carla é na Marina Itajaí".', coalesce(q.texto, r::text));
    v_res := pg_temp.ok(v_res, 'O19c nada anotado', pg_temp.site_access('OS-J11') is null and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'local'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O19b quebrou', false, sqlerrm);
  end;
  -- R3
  for c in select * from (values ('sim', 'confirma', 'não disse onde fica'), ('quanto vai custar o serviço?', 'pergunta', 'é uma pergunta'), ('não quero mais o serviço', 'outro', 'parece que desistiu do serviço'),
                                 ('desisti', 'outro', 'parece que desistiu do serviço'), ('obrigado', 'outro', 'não disse onde fica')) t(frase, intencao, o_que) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.prepara();
      perform pg_temp.mandado('OS-J11');
      r := pg_temp.resp('OS-J11', c.frase, c.intencao);
      v_res := pg_temp.ok(v_res, format('R3a "%s": vai ao dono como resposta comum, com o que é', c.frase), r ->> 'efeito' = 'ao_dono' and r ->> 'texto' like '%: ' || c.o_que || '.%', r::text);
      v_res := pg_temp.ok(v_res, format('R3b "%s": nada anotado: nem site_access, nem pergunta local, nem ação', c.frase), pg_temp.site_access('OS-J11') is null
                          and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'local')
                          and not exists (select 1 from public.agenda_acoes a where a.tipo = 'cliente' and a.depois ->> 'efeito' = 'anotou_acesso'), null);
      v_ctx := public._agenda_cliente_contexto(pg_temp.os('OS-J11'), date '2027-07-16');
      v_res := pg_temp.ok(v_res, format('R3c "%s": acesso_conhecido fica falso', c.frase), not coalesce((v_ctx ->> 'acesso_conhecido')::boolean, false), v_ctx::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, format('R3 "%s" quebrou', c.frase), false, sqlerrm);
    end;
  end loop;
  -- Com lugar, segue anotando: o que o leitor acha e as palavras de lugar
  for c in select * from (values ('na marina itajai', 'outro'), ('está na marina do joão', 'outro'), ('fica em seco', 'outro'), ('tá na minha casa em Porto Belo', 'outro'), ('na casa do meu irmão', 'outro'), ('já está aí', 'outro'), ('está em Itajaí', 'outro')) t(frase, intencao) loop
    begin
      perform pg_temp.base('sombra');
      perform pg_temp.prepara();
      perform pg_temp.mandado('OS-J11');
      r := pg_temp.resp('OS-J11', c.frase, c.intencao);
      v_res := pg_temp.ok(v_res, format('R3d "%s": fala de lugar, anota', c.frase), r ->> 'efeito' = 'anotou_acesso' and pg_temp.site_access('OS-J11') like '%' || c.frase, r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, format('R3d "%s" quebrou', c.frase), false, sqlerrm);
    end;
  end loop;
  -- O "sim" atrasado do M1
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    update public.agenda_config set modo_proposta = 'ligado' where id;
    m := pg_temp.mandado('OS-J12');
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, dia_alvo, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, criada_em, enviada_em)
    values (m.client_id, m.service_order_id, 'confirmar', 'seguinte', 'rodada', date '2027-07-26', 'ligado', 'Podemos confirmar seg 26/07?', jsonb_build_object('dia_alvo', date '2027-07-26'),
            pg_temp.em(date '2027-07-16', '09:00'), pg_temp.em(date '2027-07-16', '19:00'), 'livre', 'enviada', 'teste:m1', pg_temp.em(date '2027-07-16', '09:00'), pg_temp.em(date '2027-07-16', '09:00'))
    returning id into m1;
    r := pg_temp.resp('OS-J12', 'sim', 'confirma');
    v_res := pg_temp.ok(v_res, 'R3e o "sim" atrasado do M1, com o M11 mais novo: vai ao M1, não ao M11', r ->> 'mensagem_id' = m1::text and (select x.estado from public.agenda_cliente_mensagens x where x.id = m.id) <> 'respondida', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'R3e quebrou', false, sqlerrm);
  end;
  -- R4
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    perform pg_temp.mandado('OS-J12');
    r := pg_temp.resp('OS-J12', 'Sim, na Marina Itajaí', 'acordo');
    v_res := pg_temp.ok(v_res, 'R4a "Sim, na Marina Itajaí": o acordo entra no leitor, com M11 pendente', r ->> 'efeito' = 'anotou_acesso' and exists (select 1 from public.agenda_perguntas x where x.chave = 'local:' || pg_temp.os('OS-J12') and x.texto like '%Entendi: Marina Itajaí%'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'R4a quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    perform pg_temp.mandado('OS-J12');
    r := pg_temp.resp('OS-J12', 'combinado então', 'acordo');
    v_res := pg_temp.ok(v_res, 'R4b o acordo sem lugar segue a frase de sempre', r ->> 'efeito' = 'ao_dono' and r ->> 'texto' like '%parece que concorda, mas não é um SIM claro%' and pg_temp.site_access('OS-J12') is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'R4b quebrou', false, sqlerrm);
  end;
  -- R5: em teste nasce contado
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    update public.agenda_config set cliente_tipos_ligados = array_remove(cliente_tipos_ligados, 'onde_fica') where id;
    perform set_config('agenda.hoje', '2027-07-16', true);
    v_antes := public._agenda_linhas_do_fechamento(date '2027-07-16');
    r := pg_temp.passo();
    v_res := pg_temp.ok(v_res, 'R5a a régua: o M11 em teste foi registrado', (r ->> 'registradas')::int >= 1, r::text);
    v_res := pg_temp.ok(v_res, 'R5b a ação nasce contada, como a rodada do local', not exists (select 1 from public.agenda_acoes a where a.tipo = 'cliente' and a.contada_em is null and a.texto like 'Em teste: eu teria mandado%onde fica%')
                        and exists (select 1 from public.agenda_acoes a where a.tipo = 'cliente' and a.contada_em is not null and a.texto like 'Em teste: eu teria mandado%onde fica%'), null);
    v_dep := public._agenda_linhas_do_fechamento(date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'R5c não ocupa linha do fechamento: byte a byte', v_antes = v_dep, v_dep::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'R5 quebrou', false, sqlerrm);
  end;
  -- C2
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.prepara();
    perform pg_temp.passo();
    m := pg_temp.m('OS-J11');
    v_res := pg_temp.ok(v_res, 'C2a a régua: com a data, a revalidação deixa sair', public._agenda_cliente_revalidar(m.id, pg_temp.em(date '2027-07-16', '16:40')) is null, null);
    update public.agenda_config set onde_fica_desde = null where id;
    v_res := pg_temp.ok(v_res, 'C2b parar o M11: a revalidação devolve o motivo de recusa', public._agenda_cliente_revalidar(m.id, pg_temp.em(date '2027-07-16', '16:40')) = 'tipo_em_teste', null);
    r := public._agenda_cliente_fila(date '2027-07-16', pg_temp.em(date '2027-07-16', '16:40'));
    v_res := pg_temp.ok(v_res, 'C2c o passo fila recusa o que está na fila; nada sai', (select x.estado from public.agenda_cliente_mensagens x where x.id = m.id) = 'recusada'
                        and not exists (select 1 from public.whatsapp_send_queue w where w.source_ref_id = m.id and w.status = 'pending'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C2 quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$m11$;

-- ── O21. bem_livre ─────────────────────────────────────────────────────────────────────────
do $o21$
declare
  v_res jsonb := '[]'::jsonb;
  c     record;
  v_q   uuid;
  v_est text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('O21', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  for c in select * from (values
      ('{"local": "MP", "bem_onde": "patio"}'::jsonb, 'está no pátio, na MP', 'resolvida', 'o local do bem com o pátio'),
      ('{"local": "pátio"}'::jsonb, 'está no pátio', 'resolvida', 'o local é o pátio'),
      ('{"bem_onde": "patio"}'::jsonb, 'já está no pátio', 'resolvida', 'o pátio, sem o local'),
      ('{"bem_livre_em": "hoje"}'::jsonb, 'está livre hoje', 'resolvida', 'o estado livre'),
      ('{"bem_onde": "seco"}'::jsonb, 'está em seco', 'resolvida', 'o estado, fora do cliente'),
      ('{"bem_onde": "com_cliente"}'::jsonb, 'está com o cliente', 'aberta', 'com o cliente: ela segue, falta dizer até quando'),
      ('{"dias": 2}'::jsonb, 'leva 2 dias', 'aberta', 'o que não fala do bem')) t(d, trecho, estado, nome) loop
    begin
      perform pg_temp.base('sombra');
      insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, modo, criada_em, expira_em)
      values ('bem_livre', 'bem_livre:' || pg_temp.os('OS-J3'), pg_temp.os('OS-J3'), array[pg_temp.os('OS-J3')], date '2027-07-23', 'contando que o motorhome está livre', '[]'::jsonb, 'ligado', pg_temp.em(date '2027-07-16', '10:00'), pg_temp.em(date '2027-07-23', '10:00'))
      returning id into v_q;
      perform pg_temp.plan('OS-J3', c.d, c.trecho);
      perform pg_temp.grava();
      select q.estado into v_est from public.agenda_perguntas q where q.id = v_q;
      v_res := pg_temp.ok(v_res, format('O21a %s: %s', c.nome, c.estado), v_est = c.estado, v_est);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
              when others then v_res := pg_temp.ok(v_res, format('O21a %s quebrou', c.nome), false, sqlerrm);
    end;
  end loop;
  begin
    perform pg_temp.base('sombra');
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, perda_em, texto, opcoes, modo, criada_em, expira_em)
    values ('bem_livre', 'bem_livre:' || pg_temp.os('OS-J3'), pg_temp.os('OS-J3'), array[pg_temp.os('OS-J3')], date '2027-07-23', 'contando que o motorhome está livre', '[]'::jsonb, 'ligado', pg_temp.em(date '2027-07-16', '10:00'), pg_temp.em(date '2027-07-23', '10:00'));
    perform pg_temp.plan('OS-J3', '{"local": "pátio"}'::jsonb, 'está no pátio');
    perform pg_temp.grava();
    perform pg_temp.desfaz('OS-J3');
    v_res := pg_temp.ok(v_res, 'O21b o *desfaz* a devolve', exists (select 1 from public.agenda_perguntas q where q.chave = 'bem_livre:' || pg_temp.os('OS-J3') and q.estado = 'aberta'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'O21b quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$o21$;

-- ── C1. A rede K no calendário ─────────────────────────────────────────────────────────────
do $c1$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  r     jsonb;
  v_t   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C1', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_sozinho_desde = timestamptz '2027-07-01 10:00-03', modo_revisao_diaria = 'ligado' where id;
    update public.agenda_config set marcar_regras = marcar_regras || array['onda'] where id and not ('onda' = any (marcar_regras));
    perform pg_temp.aloca('OS-J3', date '2027-07-20', 'manha', 'Rafael');
    perform pg_temp.aloca('OS-J3', date '2027-07-20', 'tarde', 'Rafael');
    perform pg_temp.aloca('OS-J4', date '2027-07-20', 'manha', 'Bruno');
    perform pg_temp.aloca('OS-J4', date '2027-07-20', 'tarde', 'Bruno');
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:15'));
    v_res := pg_temp.ok(v_res, 'C1a 3 OS no feriado, acima de gestor_k_os (2): UMA chamada, e a onda nasce; nada move', (r #>> '{contagens,calendario,onda}')::boolean and exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda' and q.estado = 'aberta')
                        and (select count(*) from public.agenda_alocacoes a where a.dia = date '2027-07-20' and a.estado in ('publicada', 'fixada') and a.service_order_id in (pg_temp.os('OS-J1'), pg_temp.os('OS-J3'), pg_temp.os('OS-J4'))) >= 6, r::text);
    v_t := (select q.texto from public.agenda_perguntas q where q.tipo = 'onda' and q.estado = 'aberta');
    v_res := pg_temp.ok(v_res, 'C1b a onda diz o motivo local', v_t ~ 'o local não recebe a equipe nesses dias', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C1a quebrou', false, sqlerrm);
  end;
  -- Até o K, OS por OS: uma falha não derruba a outra
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_sozinho_desde = timestamptz '2027-07-01 10:00-03', modo_revisao_diaria = 'ligado', gestor_k_os = 5 where id;
    update public.agenda_config set marcar_regras = marcar_regras || array['onda'] where id and not ('onda' = any (marcar_regras));
    perform pg_temp.aloca('OS-J3', date '2027-07-20', 'manha', 'Rafael');
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:15'));
    v_res := pg_temp.ok(v_res, 'C1c abaixo do K, OS por OS, sem onda', not coalesce((r #>> '{contagens,calendario,onda}')::boolean, false) and (r #>> '{contagens,calendario,replanejadas}')::int = (r #>> '{contagens,calendario,os}')::int
                        and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C1c quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_sozinho_desde = timestamptz '2027-07-01 10:00-03', modo_revisao_diaria = 'ligado', gestor_k_os = 5 where id;
    perform pg_temp.aloca('OS-J3', date '2027-07-20', 'manha', 'Rafael');
    alter function public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid) rename to agenda_replanejar_ok;
    execute $f$
      create function public.agenda_replanejar(p_os uuid[], p_motivo text default null, p_origem text default 'vigia', p_hoje date default null, p_agora timestamptz default null, p_autor uuid default null)
      returns jsonb language plpgsql as $b$
      begin
        if (select id from public.service_orders where service_order_number = 'OS-J3') = any (p_os) then
          raise exception 'falha de teste nesta OS';
        end if;
        return public.agenda_replanejar_ok(p_os, p_motivo, p_origem, p_hoje, p_agora, p_autor);
      end $b$
    $f$;
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:15'));
    v_res := pg_temp.ok(v_res, 'C1c2 abaixo do K, a OS que falha não leva a outra', (r #>> '{contagens,calendario,erros}')::int = 1 and (r #>> '{contagens,calendario,replanejadas}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C1c2 quebrou', false, sqlerrm);
  end;
  -- Os dias avisados contam também
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_sozinho_desde = timestamptz '2027-07-01 10:00-03', modo_revisao_diaria = 'ligado', gestor_k_os = 5, gestor_k_dias_avisados = 0 where id;
    update public.agenda_config set marcar_regras = marcar_regras || array['onda'] where id and not ('onda' = any (marcar_regras));
    perform pg_temp.modo('modo_patio', 'ligado');
    update public.agenda_config set gestor_k_dias_avisados = 1 where id;
    -- A retirada tira os dois do plano, um dia cada: OS por OS, cada proposta veria 1 dia
    update public.os_planejamento set retirada_em = date '2027-07-19', entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J1');
    insert into public.os_planejamento (service_order_id, retirada_em, entrada_fonte) values (pg_temp.os('OS-J3'), date '2027-07-19', 'dono')
    on conflict (service_order_id) do update set retirada_em = date '2027-07-19', entrada_fonte = 'dono';
    perform pg_temp.aloca('OS-J3', date '2027-07-21', 'manha', 'Rafael');
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key, criada_em)
    select a.payee_id, a.dia, 'ficha', 'ligado', 'ficha de teste', pg_temp.em(date '2027-07-16', '19:30'), 'enfileirada', 'teste:' || a.id, pg_temp.em(date '2027-07-16', '19:30')
      from public.agenda_alocacoes a
     where a.estado = 'publicada' and ((a.service_order_id = pg_temp.os('OS-J1') and a.dia = date '2027-07-20' and a.turno = 'manha')
                                       or (a.service_order_id = pg_temp.os('OS-J3') and a.dia = date '2027-07-21'));
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:15'));
    v_res := pg_temp.ok(v_res, 'C1d os dias avisados contam: 2 OS, 1 dia cada, acima de gestor_k_dias_avisados (1): UMA chamada', (r #>> '{contagens,calendario,onda}')::boolean
                        and exists (select 1 from public.agenda_perguntas q where q.tipo = 'onda'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C1d quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C7. A semente depois do DESFAZER ───────────────────────────────────────────────────────
create function pg_temp.desfazer_semente(p_mig text) returns text language sql immutable as $f$
  select string_agg(substr(l, 6), E'\n' order by o)
    from (select l, o, sum(case when l like '-- DESFAZER-INICIO%' then 1 when l like '-- DESFAZER-FIM%' then -1 else 0 end) over (order by o) as dentro
            from unnest(string_to_array(replace(p_mig, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
   where dentro = 1 and l not like '-- DESFAZER-INICIO%'
$f$;
do $c7$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_semente_fase7d', true), '');
  v_n   int;
  v_id  uuid;
  v_foto text;
begin
  if not pg_temp.carregada() or v_mig = '' then
    insert into _resultado values ('C7', true, 'PULADO: sem as fixtures e a semente como texto (rode pela bancada)');
    return;
  end if;
  begin
    update public.agenda_config set modo_local_calendario = 'desligado', modo_local_autorizacao = 'desligado', modo_bem = 'desligado', modo_patio = 'desligado', modo_viagem = 'desligado', modo_mesmo_local = 'desligado', onde_fica_desde = null where id;
    alter table public.agenda_locais disable trigger agenda_locais_nao_apaga;
    update public.os_planejamento set local_id = null, local_fonte = null, local_em = null where local_id is not null;
    update public.os_autorizados set local_id = null where local_id is not null;
    delete from public.agenda_locais;
    alter table public.agenda_locais enable trigger agenda_locais_nao_apaga;
    execute v_mig;
    select count(*) into v_n from public.agenda_locais where ativo;
    v_res := pg_temp.ok(v_res, 'C7a a régua: a semente põe os locais', v_n > 0, v_n::text);
    -- O lugar que o dono criou não é da semente
    insert into public.agenda_locais (nome, tipo) values ('Lugar do Dono', 'outro') returning id into v_id;
    execute pg_temp.desfazer_semente(v_mig);
    v_res := pg_temp.ok(v_res, 'C7b o DESFAZER inativa os da semente; o lugar do dono fica', not exists (select 1 from public.agenda_locais l where l.ativo and l.marina_id is not null)
                        and (select l.ativo from public.agenda_locais l where l.id = v_id), null);
    execute v_mig;
    v_res := pg_temp.ok(v_res, 'C7c a semente de novo reativa os locais', (select count(*) from public.agenda_locais l where l.ativo and l.marina_id is not null) = v_n, (select count(*)::text from public.agenda_locais l where l.ativo));
    v_res := pg_temp.ok(v_res, 'C7d a MP volta a ser o pátio da HBR ativo', exists (select 1 from public.agenda_locais l where l.ativo and l.tipo = 'patio_hbr'), null);
    -- Idempotente: de novo não mexe (nem a hora: now() não anda dentro da transação, então a hora é envelhecida antes, sem o gatilho que a põe)
    alter table public.agenda_locais disable trigger agenda_locais_historico;
    update public.agenda_locais set atualizado_em = timestamptz '2026-01-01 10:00-03';
    alter table public.agenda_locais enable trigger agenda_locais_historico;
    v_foto := (select md5(string_agg(to_jsonb(l)::text, '|' order by l.nome)) from public.agenda_locais l);
    execute v_mig;
    v_res := pg_temp.ok(v_res, 'C7e de novo não muda nada', (select md5(string_agg(to_jsonb(l)::text, '|' order by l.nome)) from public.agenda_locais l) = v_foto, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C7 quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$c7$;

-- ── C9. A recomendação do apelido ──────────────────────────────────────────────────────────
-- Uma gravação do local desfeita: a ação e a sua volta, como o *desfaz* deixa
create function pg_temp.desfeita(p_os text, p_dia date, p_local uuid) returns void language plpgsql as $f$
declare
  v_a uuid;
  v_d uuid;
begin
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
  values (pg_temp.em(p_dia, '10:00'), p_dia, true, 'dono', 'local', pg_temp.os(p_os), array[pg_temp.os(p_os)], '{"local_id": null}'::jsonb,
          jsonb_build_object('local_id', p_local, 'efeito', 'planejar'), 'gravei o local')
  returning id into v_a;
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, desfaz_a)
  values (pg_temp.em(p_dia, '11:00'), p_dia, true, 'dono', 'desfazer', pg_temp.os(p_os), array[pg_temp.os(p_os)], jsonb_build_object('acao', v_a), '{}'::jsonb, 'desfeito', v_a)
  returning id into v_d;
  update public.agenda_acoes set desfeita_em = pg_temp.em(p_dia, '11:00'), desfeita_por = pg_temp.adm(), desfeita_pela = v_d where id = v_a;
end $f$;
do $c9$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  v_id  uuid;
  v_t   text;
  i     int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C9', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    update public.agenda_config set texto_max = 3000 where id;
    v_id := pg_temp.local('Marina Itajaí');
    update public.agenda_locais set apelidos = array['marina de itajai'] where id = v_id;
    perform pg_temp.desfeita('OS-J3', v_h - 3, v_id);
    v_res := pg_temp.ok(v_res, 'C9a 1 gravação desfeita: nada', pg_temp.foco() !~ 'apelido', null);
    perform pg_temp.desfeita('OS-J4', v_h - 40, v_id);
    v_res := pg_temp.ok(v_res, 'C9b a 2ª fora das 4 semanas: nada', pg_temp.foco() !~ 'apelido', null);
    perform pg_temp.desfeita('OS-J4', v_h - 2, v_id);
    v_t := pg_temp.foco();
    v_res := pg_temp.ok(v_res, 'C9c 2 do mesmo local em 4 semanas: a linha no foco; a decisão é dele', v_t ~ E'\nMarina Itajaí: você desfez 2 gravações desse local em 4 semanas\\. Recomendo tirar o apelido; a decisão é sua\\.', v_t);
    v_res := pg_temp.ok(v_res, 'C9d no foco por OS, não', pg_temp.foco(v_h, pg_temp.os('OS-J3')) !~ 'apelido', null);
    update public.agenda_locais set apelidos = '{}' where id = v_id;
    v_res := pg_temp.ok(v_res, 'C9e sem apelido, não há o que tirar', pg_temp.foco() !~ 'apelido', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'C9 quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$c9$;

-- ── R6. A rodada com erro ──────────────────────────────────────────────────────────────────
do $r6$
declare
  v_res jsonb := '[]'::jsonb;
  v_h   date := date '2027-07-16';
  r     jsonb;
  r2    jsonb;
  v_c   jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R6', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.modo('modo_patio', 'ligado');
    alter function public._agenda_combinar_da_os(uuid, date) rename to _agenda_combinar_da_os_ok;
    execute $f$
      create function public._agenda_combinar_da_os(p_os uuid, p_hoje date) returns jsonb language plpgsql stable as $b$
      begin
        if p_os = (select id from public.service_orders where service_order_number = 'OS-J2') and current_setting('agenda_teste.falhar', true) = 'on' then
          raise exception 'falha de teste só nesta OS';
        end if;
        return public._agenda_combinar_da_os_ok(p_os, p_hoje);
      end $b$
    $f$;
    perform set_config('agenda_teste.falhar', 'on', true);
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:20'));
    v_res := pg_temp.ok(v_res, 'R6a uma OS que falha não derruba as outras: a pergunta do J1 nasce', (r ->> 'erros')::int >= 1 and exists (select 1 from public.agenda_perguntas q where q.tipo = 'combinar' and q.service_order_id = pg_temp.os('OS-J1'))
                        and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'combinar' and q.service_order_id = pg_temp.os('OS-J2')), r::text);
    v_res := pg_temp.ok(v_res, 'R6b conflitos fica de pé: conta o erro, e o resto da lista segue', (r -> 'contagens' -> 'conflitos' ->> 'erro')::int = 1 and jsonb_array_length(r -> 'falhas') = 0, r::text);
    v_res := pg_temp.ok(v_res, 'R6c o erro fica em app_error_logs, com local: no prefixo', exists (select 1 from public.app_error_logs e where e.action = 'local:combinar' and e.message like '%Nelson%falha de teste%'), null);
    r2 := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:35'));
    v_res := pg_temp.ok(v_res, 'R6d a rodada com erro não vale como ja_rodou: tenta no tique seguinte', (r2 ->> 'rodou')::boolean, r2::text);
    r2 := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:50'));
    v_res := pg_temp.ok(v_res, 'R6e a 3ª tentativa', (r2 ->> 'rodou')::boolean, r2::text);
    v_res := pg_temp.ok(v_res, 'R6f depois da 3ª, registra', exists (select 1 from public.app_error_logs e where e.action = 'local:rodada' and e.message like '%falhou 3 vezes%'), null);
    r2 := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '17:05'));
    v_res := pg_temp.ok(v_res, 'R6g no máximo 3 vezes por dia', not (r2 ->> 'rodou')::boolean and (r2 ->> 'ja_rodou')::boolean, r2::text);
    v_res := pg_temp.ok(v_res, 'R6h no dia seguinte, tenta de novo', (public.agenda_local_vigiar(v_h + 3, pg_temp.em(v_h + 3, '16:20')) ->> 'rodou')::boolean, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'R6 quebrou', false, sqlerrm);
  end;
  -- Cada passo conta o erro dele: só o combinar falha (a pergunta), só os conflitos falham (a máscara)
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    alter function public._agenda_combinar_texto(jsonb, text, date) rename to _agenda_combinar_texto_ok;
    execute $f$
      create function public._agenda_combinar_texto(p_item jsonb, p_forma text, p_hoje date) returns text language plpgsql stable as $b$
      begin
        if p_forma = 'pergunta' and p_item ->> 'cliente' = 'Nelson' then
          raise exception 'falha de teste só na pergunta';
        end if;
        return public._agenda_combinar_texto_ok(p_item, p_forma, p_hoje);
      end $b$
    $f$;
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:20'));
    v_res := pg_temp.ok(v_res, 'R6k só o combinar falha: a rodada conta o erro, e o tique seguinte tenta', (r ->> 'erros')::int >= 1 and (r #>> '{contagens,combinar,erros}')::int >= 1 and r #>> '{contagens,conflitos,erro}' is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'R6k quebrou', false, sqlerrm);
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    alter function public._agenda_local_mascara(uuid, date, date, date, jsonb) rename to _agenda_local_mascara_ok;
    execute $f$
      create function public._agenda_local_mascara(p_os uuid, p_d_ini date, p_d_fim date, p_hoje date, p_local jsonb default null) returns jsonb language plpgsql stable as $b$
      begin
        if p_os = (select id from public.service_orders where service_order_number = 'OS-J2') then
          raise exception 'falha de teste só na máscara';
        end if;
        return public._agenda_local_mascara_ok(p_os, p_d_ini, p_d_fim, p_hoje, p_local);
      end $b$
    $f$;
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:20'));
    v_res := pg_temp.ok(v_res, 'R6l só os conflitos falham: a rodada conta o erro', (r ->> 'erros')::int = 1 and (r #>> '{contagens,conflitos,erro}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'R6l quebrou', false, sqlerrm);
  end;
  -- A 2ª tentativa sem erro encerra o dia
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    alter function public._agenda_combinar_da_os(uuid, date) rename to _agenda_combinar_da_os_ok;
    execute $f$
      create function public._agenda_combinar_da_os(p_os uuid, p_hoje date) returns jsonb language plpgsql stable as $b$
      begin
        if p_os = (select id from public.service_orders where service_order_number = 'OS-J2') and current_setting('agenda_teste.falhar', true) = 'on' then
          raise exception 'falha de teste só nesta OS';
        end if;
        return public._agenda_combinar_da_os_ok(p_os, p_hoje);
      end $b$
    $f$;
    perform set_config('agenda_teste.falhar', 'on', true);
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:20'));
    perform set_config('agenda_teste.falhar', 'off', true);
    r := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:35'));
    v_res := pg_temp.ok(v_res, 'R6i a tentativa sem erro faz o trabalho', (r ->> 'rodou')::boolean and (r ->> 'erros')::int = 0 and exists (select 1 from public.agenda_perguntas q where q.tipo = 'combinar' and q.service_order_id = pg_temp.os('OS-J2')), r::text);
    r2 := public.agenda_local_vigiar(v_h, pg_temp.em(v_h, '16:50'));
    v_res := pg_temp.ok(v_res, 'R6j e aí vale como ja_rodou', (r2 ->> 'ja_rodou')::boolean, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
            when others then v_res := pg_temp.ok(v_res, 'R6i quebrou', false, sqlerrm);
  end;
  perform pg_temp.gravar(v_res);
end
$r6$;

select teste, ok, detalhe from _resultado order by ok, teste;

rollback;
