-- Prova das leituras do local da Agenda de Produção, Fase 7d (pacote P8; migration 20261107100700; spec-fase7d §5.8, §6.2, §6.4, §8.3 agenda_fase7d_leituras.sql, §11, R1, R6.3-6,
-- R6.3-11, R6.3-12, R6.9-1).
-- bancada: depende de 20261107100700
--
--   V0  as portas: as 4 novas e as 7 recriadas; o foco e a saúde definer com a porta dentro; o anon não chama; a das palavras ninguém chama de fora
--   V1  o foco locais, byte a byte: em teste, ligado, com o freio, desligado, o vazio, uma OS só; cada modo sozinho; as notas que cabem; o cadastro; o "Em teste" de cada tipo; o corte
--   V2  o cartão: o bloco local; nulo com os 6 desligados e na OS que já foi feita; a resposta ao M11 no bloco cliente
--   V3  a ficha: o lugar só sem suposição, o de antes byte a byte nas outras (a função da 7c rodando como pg_temp); a frase do acesso, nas 2 saídas, em texto_curto, dentro dos 590
--   V4  a ação local no "o que mudou", sem recriar _agenda_mudancas (R6.3-6): a de vigia em teste entra pelo foco e não pelo fechamento; a do dono não entra
--   V5  a saúde: os zeros, cada violação forçada = 1, o ok, o freio, o M11 em tipos_liberados, os números
--   V6  o determinismo (md5 2×) e as cópias: tirados os blocos, as 7 recriadas são a origem, byte a byte
--   V7  quem lê: a técnica logada recebe 42501; o admin logado e o service_role leem; agenda_ver (a OS que não existe, a leitura desligada, sem p_hoje)
--   V8  a resposta em palavras (os evals S24 e K57): com mais de uma pergunta esperando, o número solto segue perguntando; as palavras que dizem a pergunta e a opção passam
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_leituras.sql
--   Seguro em produção: termina em ROLLBACK. As portas (V0) rodam em qualquer banco; o resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
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
create function pg_temp.igual(p_res jsonb, p_nome text, p_veio text, p_esperado text) returns jsonb
language sql immutable as $f$
  select pg_temp.ok(p_res, p_nome, p_veio is not distinct from p_esperado, case when p_veio is distinct from p_esperado then 'veio: ' || coalesce(p_veio, '(nulo)') end)
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
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim" e sem as marcas "-- (7d … -- (7d: fim)".
-- FASE 7f: o texto sem os blocos "-- FASE 7f: … -- FASE 7f: fim" e sem as marcas "-- (7f … -- (7f: fim)": quem recria uma destas na 7f só acrescenta, e a viva continua sendo a desta migration
-- (7e P7: e os da 7e, "-- FASE 7e:" e "-- (7e", que recria agenda_saude e os_plano_da_os depois da 7f, só acrescentando)
-- (7g P6: e os da 7g, "-- FASE 7g:" e "-- (7g", que recria agenda_saude depois da 7e, só acrescentando)
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
create function pg_temp.sem_7d(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when (l ~ '^\s*-- FASE 7[defg]:' and l !~ '^\s*-- FASE 7[defg]: fim')
                                                     or (l ~ '^\s*-- \(7[defg] ' and l !~ '^\s*-- \(7[defg]: fim\)') then 1
                                                when l ~ '^\s*-- (FASE 7[defg]: fim|\(7[defg]: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7[defg]: fim|\(7[defg]: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
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
create function pg_temp.os(p_num text) returns uuid language sql stable as $f$
  select id from public.service_orders where service_order_number = p_num
$f$;
create function pg_temp.modos(p text) returns void language sql as $f$
  update public.agenda_config set modo_local_calendario = p, modo_local_autorizacao = p, modo_bem = p, modo_patio = p, modo_viagem = p, modo_mesmo_local = p where id
$f$;
create function pg_temp.foco(p_hoje date, p_os uuid default null) returns text language sql stable as $f$
  select public._agenda_ver_locais(p_hoje, p_os) ->> 'texto'
$f$;
-- (correção O1) O foco por OS das que têm plano nas próximas 3 semanas, uma linha por OS: o texto longo saiu do foco geral, e estes testes são do texto longo
create function pg_temp.focos(p_hoje date) returns text language sql stable as $f$
  select string_agg(public._agenda_ver_locais(p_hoje, x.os) ->> 'texto', E'\n' order by x.ini, public._agenda_rotulo_da_os(x.os), x.os)
    from (select a.service_order_id as os, min(a.dia) as ini
            from public.agenda_alocacoes a join public.os_carteira(p_hoje) k on k.service_order_id = a.service_order_id
           where a.estado in ('publicada', 'fixada') and a.dia between p_hoje and p_hoje + 21
           group by 1) x
$f$;
-- Uma alocação publicada, com o que o teste precisa.
create function pg_temp.aloc(p_os uuid, p_payee uuid, p_dia date, p_turno text) returns void language sql as $f$
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  values (md5('v:' || p_os || p_payee || p_dia || p_turno)::uuid, p_os, p_payee, p_dia, p_turno, 'turno', 'execucao', 'publicada', 'motor', timestamptz '2027-07-08 16:30-03')
$f$;
-- O M11 que saiu de verdade.
create function pg_temp.m11(p_os uuid, p_quando timestamptz, p_estado text default 'enviada', p_modo text default 'ligado', p_dedupe text default '') returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
  select so.client_id, so.id, 'onde_fica', 'motorhome', 'rodada', p_modo, 'o texto do M11', '{"dados": {"uso": true}}'::jsonb, p_quando, p_quando + interval '1 day', 'livre', p_estado,
         'v:' || so.id || p_dedupe, p_quando, p_quando
    from public.service_orders so where so.id = p_os
  returning id into v;
  return v;
end $f$;

-- ── V0. As portas (sem fixture) ────────────────────────────────────────────────────────────────
with f(sig, quem, definer, vol) as (values
  ('public._agenda_ver_locais(date, uuid)', 'leitura', true, 's'),
  ('public._agenda_saude_local(date, timestamp with time zone)', 'leitura', true, 's'),
  ('public._agenda_local_bloco(uuid, date)', 'servico', false, 's'),
  ('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)', 'leitura', false, 's'),
  ('public.os_plano_da_os(uuid, date)', 'leitura', true, 's'),
  ('public.agenda_saude(date, timestamp with time zone)', 'leitura', false, 's'),
  ('public.agenda_equipe_ficha(uuid, date, date)', 'servico', true, 's'),
  ('public._agenda_local_da_os(uuid)', 'leitura', false, 's'),
  ('public._agenda_cliente_da_os(uuid, date)', 'ninguem', false, 's'),
  ('public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamp with time zone)', 'leitura', true, 'v'))
insert into _resultado
select 'V0a as portas: o foco e a saúde definer (a porta dentro), o bloco só do service_role, as recriadas como antes; nunca anon; search_path fixo',
       count(p.oid) = 10
       and coalesce(bool_and(p.prosecdef = f.definer and p.provolatile = f.vol and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                             and not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute') = (f.quem <> 'ninguem')
                             and has_function_privilege('authenticated', p.oid, 'execute') = (f.quem = 'leitura')), false),
       string_agg(format('%s def=%s vol=%s cfg=%s anon=%s auth=%s srv=%s', f.sig, p.prosecdef, p.provolatile, p.proconfig, has_function_privilege('anon', p.oid, 'execute'),
                         has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'V0b o anon não chama o foco, a saúde nem o bloco (rodando, não só pelo catálogo)',
       pg_temp.como(null, 'anon', 'select public._agenda_ver_locais(date ''2027-07-16'')::text') like 'erro 42501%'
       and pg_temp.como(null, 'anon', 'select public._agenda_saude_local(date ''2027-07-16'', timestamptz ''2027-07-16 16:20-03'')::text') like 'erro 42501%'
       and pg_temp.como(null, 'anon', 'select public._agenda_local_bloco(null::uuid, date ''2027-07-16'')::text') like 'erro 42501%',
       pg_temp.como(null, 'anon', 'select public._agenda_ver_locais(date ''2027-07-16'')::text');

insert into _resultado
select 'V0c _agenda_disse_em_palavras: immutable, invoker, search_path fixo; nem anon, nem authenticated, nem service_role chamam (só agenda_rascunho_aplicar, que é definer)',
       p.oid is not null and p.provolatile = 'i' and not p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute'),
       format('vol=%s def=%s cfg=%s anon=%s auth=%s srv=%s', p.provolatile, p.prosecdef, p.proconfig, has_function_privilege('anon', p.oid, 'execute'),
              has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute'))
  from (select to_regprocedure('public._agenda_disse_em_palavras(text, text, text, text[])') as o) x
  left join pg_proc p on p.oid = x.o;

-- ── V1 a V5, V7. Com a fixture ─────────────────────────────────────────────────────────────────
do $v$
declare
  v_res    jsonb := '[]'::jsonb;
  v_fix    text := coalesce(current_setting('agenda_teste.fase7d', true), '');
  d_hoje   constant date := date '2027-07-16';
  v_alex   uuid;
  v_roberto uuid;
  v_joao   uuid;
  v_rafael uuid;
  v_dono   uuid;
  v_tec    uuid;
  v_t      text;
  v_t2     text;
  v_j      jsonb;
  v_k      jsonb;
  v_id     uuid;
  v_id2    uuid;
  v_n      int;
  v_i      int;
  v_mig    text;
begin
  if v_fix = '' then
    insert into _resultado values ('V1 a V7', true, 'PULADO: sem a fixture da 7d (rode pela bancada)');
    return;
  end if;
  execute v_fix;
  select id into strict v_alex from public.payees where name = 'Alex' and active;
  select id into strict v_roberto from public.payees where name = 'Roberto' and active;
  select id into strict v_joao from public.payees where name = 'João' and active;
  select id into strict v_rafael from public.payees where name = 'Rafael' and active;
  select id into strict v_dono from public.app_users where role = 'admin' and active order by id limit 1;
  update public.agenda_config set modo_leitura = 'ligado', modo_proposta = 'ligado', gestor_so_propor = false where id;

  begin
  -- ── V1. O foco locais ──
  -- Em teste: o "Combinar" vira "Em teste, eu cobraria"; a linha do que eu faria; os 6 modos em sombra
  perform pg_temp.modos('sombra');
  v_t := pg_temp.focos(d_hoje);
  v_res := pg_temp.igual(v_res, 'V1a o foco de cada OS, em teste, byte a byte (§6.2): a OS que começa primeiro antes, o "Em teste" dela', v_t, $t$Júlio (OS-J13): não sei onde é o serviço.
Lenine (OS-J1): MP Motorhomes, em Balneário Camboriú (pela OS). Em teste, eu cobraria: a entrada do motorhome no pátio para ter 20/07, até sex 16/07.
Em teste: com o calendário do local ligado, eu não marcaria ter 20/07 para Lenine (feriado em Balneário Camboriú).
Nelson (OS-J2): Marina Itajaí (pela OS). O barco: em seco (garagem), quem desce: a marina; o teste final é na água. Em teste, eu cobraria: o acesso de João para ter 20/07, até hoje (sex 16/07); a vaga de serviço com a marina, até sex 16/07; a descida para o teste na água em ter 20/07. Autorizados nesse serviço: Roberto. Supus o teste final na água (pela linha de serviço).
Beto (OS-J12): Marina Itajaí (pela OS). Em teste, eu cobraria: o acesso de Rafael para seg 26/07, até qui 22/07.$t$);
  v_j := public._agenda_ver_locais(d_hoje);
  -- (correção O1) uma linha por OS da carteira, com plano ou sem
  v_res := pg_temp.ok(v_res, 'V1b a saída: ok, linhas (uma por OS aberta, com o rótulo e o local), cadastro e em_teste', (v_j ->> 'ok')::boolean
                      and jsonb_array_length(v_j -> 'linhas') = (select count(*) from public.os_carteira(d_hoje))
                      and (select e -> 'local' ->> 'fonte' from jsonb_array_elements(v_j -> 'linhas') e where e ->> 'rotulo' = 'Lenine (OS-J1)') = 'os'
                      and (v_j -> 'cadastro' ->> 'locais')::int = 5 and (v_j -> 'cadastro' ->> 'conferidos')::int = 1
                      and jsonb_array_length(v_j -> 'em_teste') = 1, v_j::text);

  -- O freio: ligado + freio = em teste, byte a byte (R6.7b)
  perform pg_temp.modos('ligado');
  update public.agenda_config set gestor_so_propor = true where id;
  v_res := pg_temp.igual(v_res, 'V1c os 6 ligados com *gestor, só propor*: o texto de em teste, byte a byte (R6.7b)', pg_temp.focos(d_hoje), v_t);
  update public.agenda_config set gestor_so_propor = false where id;

  -- O resto do V1 olha o texto inteiro: o corte tem o caso dele (V1at)
  update public.agenda_config set texto_max = 3000 where id;

  -- Ligado: o "Combinar", a viagem, o "Perguntei", sem o "Em teste"
  perform pg_temp.aloc(pg_temp.os('OS-J6'), v_rafael, date '2027-07-21', 'manha');
  perform pg_temp.aloc(pg_temp.os('OS-J6'), v_rafael, date '2027-07-21', 'tarde');
  perform pg_temp.aloc(pg_temp.os('OS-J3'), v_alex, date '2027-07-22', 'manha');
  perform pg_temp.m11(pg_temp.os('OS-J3'), timestamptz '2027-07-15 10:00-03');
  v_t := pg_temp.focos(d_hoje);
  v_res := pg_temp.igual(v_res, 'V1d os 6 ligados, byte a byte: "Combinar:", o "Perguntei" do M11 que saiu, a viagem, sem nenhum "Em teste"', v_t, $t$Júlio (OS-J13): não sei onde é o serviço.
Lenine (OS-J1): MP Motorhomes, em Balneário Camboriú (pela OS). Combinar: a entrada do motorhome no pátio para ter 20/07, até sex 16/07.
Nelson (OS-J2): Marina Itajaí (pela OS). O barco: em seco (garagem), quem desce: a marina; o teste final é na água. Combinar: o acesso de João para ter 20/07, até hoje (sex 16/07); a vaga de serviço com a marina, até sex 16/07; a descida para o teste na água em ter 20/07. Autorizados nesse serviço: Roberto. Supus o teste final na água (pela linha de serviço).
Kalmar (OS-J6): Iate Clube Caiobá, em Guaratuba (PR). Viagem com pernoite (suposição: outro estado): a equipe vai e volta junta, em dias seguidos; a ida e a volta ocupam 1 meio-dia cada. Combinar: o acesso de Rafael para qua 21/07, até seg 19/07.
Vanderlei (OS-J3): MP Motorhomes (suposição: motorhome vem ao pátio). Perguntei ao cliente em 15/07. Combinar: a entrada do motorhome no pátio para qui 22/07, até ter 20/07.
Beto (OS-J12): Marina Itajaí (pela OS). Combinar: o acesso de Rafael para seg 26/07, até qui 22/07.$t$);

  -- O M11 que não saiu de verdade não diz "perguntei" (a lição do plano falso)
  update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'teto_dia', enviada_em = null where service_order_id = pg_temp.os('OS-J3') and tipo = 'onde_fica';
  v_res := pg_temp.ok(v_res, 'V1e o M11 recusado não vira "Perguntei"', pg_temp.focos(d_hoje) !~ 'Perguntei', null);
  update public.agenda_cliente_mensagens set estado = 'enviada', recusa_motivo = null, enviada_em = timestamptz '2027-07-15 10:00-03' where service_order_id = pg_temp.os('OS-J3') and tipo = 'onde_fica';
  begin
    perform pg_temp.m11(pg_temp.os('OS-J13'), timestamptz '2027-07-15 10:00-03', 'enviada', 'sombra');
    v_res := pg_temp.ok(v_res, 'V1e2 o M11 em teste não vira "Perguntei"', pg_temp.foco(d_hoje, pg_temp.os('OS-J13')) !~ 'Perguntei', null);
    perform pg_temp.m11(pg_temp.os('OS-J3'), timestamptz '2027-07-12 10:00-03', 'enviada', 'ligado', ':velha');
    v_res := pg_temp.ok(v_res, 'V1e3 dois M11 da mesma OS: a data do mais novo', pg_temp.focos(d_hoje) ~ 'Perguntei ao cliente em 15/07\.', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- Dito o local, o "Perguntei" sai: a pergunta já foi respondida
  update public.os_planejamento set local_id = (select id from public.agenda_locais where nome = 'Veleiros da Ilha'), local_fonte = 'cliente', local_em = now()
   where service_order_id = pg_temp.os('OS-J3');
  v_t2 := pg_temp.focos(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1f o local dito pelo cliente: "(o cliente disse)" e sem "Perguntei"', v_t2 ~ 'Vanderlei \(OS-J3\): Veleiros da Ilha, em Florianópolis \(o cliente disse\)' and v_t2 !~ 'Perguntei', v_t2);
  update public.os_planejamento set local_id = null, local_fonte = null, local_em = null where service_order_id = pg_temp.os('OS-J3');

  -- Cada modo sozinho: o que ele mostra some com ele
  update public.agenda_config set modo_bem = 'desligado' where id;
  v_t2 := pg_temp.focos(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1g sem modo_bem: nem o estado do bem, nem a vaga, nem a descida, nem a suposição do bem', v_t2 !~ 'O barco:' and v_t2 !~ 'a vaga de serviço' and v_t2 !~ 'a descida' and v_t2 !~ 'Supus o teste' and v_t2 ~ 'o acesso de João', v_t2);
  update public.agenda_config set modo_bem = 'ligado', modo_viagem = 'desligado' where id;
  v_t2 := pg_temp.focos(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1h sem modo_viagem: a linha da viagem some', v_t2 !~ 'Viagem' and v_t2 ~ 'Kalmar \(OS-J6\): Iate Clube Caiobá', v_t2);
  update public.agenda_config set modo_viagem = 'sombra' where id;
  v_t2 := pg_temp.focos(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1i modo_viagem em teste: "Em teste: viagem com pernoite…"', v_t2 ~ 'Em teste: viagem com pernoite \(suposição: outro estado\)', v_t2);
  update public.agenda_config set modo_viagem = 'ligado', modo_patio = 'desligado' where id;
  v_t2 := pg_temp.focos(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1j sem modo_patio: a entrada some', v_t2 !~ 'a entrada do motorhome', v_t2);
  update public.agenda_config set modo_patio = 'ligado', modo_local_autorizacao = 'desligado' where id;
  v_t2 := pg_temp.focos(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1k sem o preparo do acesso: nem o acesso nem os autorizados', v_t2 !~ 'o acesso de' and v_t2 !~ 'Autorizados', v_t2);
  update public.agenda_config set modo_local_autorizacao = 'sombra' where id;
  v_t2 := pg_temp.focos(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1l um modo ligado e outro em teste, na mesma linha: "Combinar:" e "Em teste, eu cobraria:"',
                      v_t2 ~ 'Combinar: a vaga de serviço com a marina, até sex 16/07; a descida para o teste na água em ter 20/07\. Em teste, eu cobraria: o acesso de João', v_t2);
  update public.agenda_config set modo_local_autorizacao = 'ligado' where id;

  -- Os 6 desligados: nada disto existe para o dono
  perform pg_temp.modos('desligado');
  v_j := public._agenda_ver_locais(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1m os 6 desligados: a frase, e nada na saída', v_j ->> 'texto' = 'Os locais ainda estão desligados na agenda.' and v_j -> 'linhas' = '[]'::jsonb
                      and v_j -> 'em_teste' = '[]'::jsonb, v_j::text);
  -- Só um em teste: a leitura já aparece
  update public.agenda_config set modo_mesmo_local = 'sombra' where id;
  v_res := pg_temp.ok(v_res, 'V1n um modo só fora de desligado: o foco aparece (qualquer um dos 6)', pg_temp.foco(d_hoje) ~ '^Onde é cada serviço', null);
  perform pg_temp.modos('ligado');

  -- O vazio: nenhum serviço; a conferência vencida vira nota
  -- (correção O1) a carteira não fica vazia em 2030: o vazio de verdade é o S da correção; aqui, a conferência vencida
  v_t2 := pg_temp.foco(date '2030-01-07');
  v_res := pg_temp.ok(v_res, 'V1o a conferência vencida (mais de 1 ano) não conta', v_t2 ~ 'Locais: 5 no cadastro; nenhum conferido por você\. Só como nota: Marina Itajaí pede autorização, no sábado só abre de manhã e tem garagem seca \(a conferir de novo\); Tedesco Marina Garden Plaza tem garagem seca \(pesquisa\)\.', v_t2);

  -- No dia, não há mais o que combinar (a régua de _agenda_local_combinar)
  v_res := pg_temp.ok(v_res, 'V1o2 no próprio dia, nada a combinar', pg_temp.foco(date '2027-07-20', pg_temp.os('OS-J1')) !~ 'Combinar', null);
  -- (correção O1) Quem entra: todas as OS abertas, com plano ou sem. O foco por OS das 3 semanas segue só o dos testes acima
  begin
    v_res := pg_temp.ok(v_res, 'V1o3 sem plano, entra', pg_temp.foco(d_hoje) ~ 'OS-J14', null);
    perform pg_temp.aloc(pg_temp.os('OS-J14'), v_rafael, date '2027-08-09', 'manha');
    v_res := pg_temp.ok(v_res, 'V1o3a o plano que começa depois das 3 semanas entra também', pg_temp.foco(d_hoje) ~ 'OS-J14', null);
    perform pg_temp.aloc(pg_temp.os('OS-J14'), v_rafael, date '2027-07-20', 'manha');
    v_res := pg_temp.ok(v_res, 'V1o3b dentro das 3 semanas, entra (o controle)', pg_temp.foco(d_hoje) ~ 'OS-J14', null);
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = now(), cancelada_motivo = 'replanejado' where service_order_id = pg_temp.os('OS-J14');
    v_res := pg_temp.ok(v_res, 'V1o4 a alocação cancelada não tira a OS', pg_temp.foco(d_hoje) ~ 'OS-J14', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Uma OS só: sem o cabeçalho, sem o cadastro, sem o "- "
  v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J12'));
  v_res := pg_temp.igual(v_res, 'V1p com p_os: só a linha da OS', v_t, 'Beto (OS-J12): Marina Itajaí (pela OS). Combinar: o acesso de Rafael para seg 26/07, até qui 22/07.');
  v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J14'));
  v_res := pg_temp.igual(v_res, 'V1q com p_os e sem plano: o local dito pelo dono, sem nada a combinar', v_t, 'Nuno (OS-J14): Tedesco Marina Garden Plaza, em Balneário Camboriú (você disse). Tedesco Marina Garden Plaza: tem garagem seca (a confirmar com você).');

  -- As notas: o barco noutro lugar, a casa do cliente, as que cabem
  update public.vessels set marina_id = (select marina_id from public.agenda_locais where nome = 'Tedesco Marina Garden Plaza') where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-J12'));
  v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J12'));
  v_res := pg_temp.ok(v_res, 'V1r a nota do barco cadastrado noutro lugar (NOVO-agenda-63): com a maiúscula e o ponto', v_t ~ ' O barco está cadastrado na Tedesco Marina Garden Plaza\.$', v_t);
  update public.os_planejamento set trecho = 'o serviço do Júlio é na casa do cliente' where service_order_id = pg_temp.os('OS-J13');
  v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J13'));
  -- (correção O3) a casa virou local: o trecho não é mais lido
  v_res := pg_temp.ok(v_res, 'V1s "na casa do cliente" no trecho velho não vale: o foco lê o local (correção O3)', v_t = 'Júlio (OS-J13): não sei onde é o serviço.', v_t);
  update public.os_planejamento set trecho = 'na casa de máquinas do barco' where service_order_id = pg_temp.os('OS-J13');
  v_res := pg_temp.ok(v_res, 'V1t "casa de máquinas" não é a casa do cliente', pg_temp.foco(d_hoje, pg_temp.os('OS-J13')) !~ 'casa do cliente', null);
  update public.os_planejamento set trecho = 'é na casa dele', local_id = (select id from public.agenda_locais where nome = 'Veleiros da Ilha'), local_fonte = 'dono', local_em = now() where service_order_id = pg_temp.os('OS-J13');
  v_res := pg_temp.ok(v_res, 'V1u com o local dito, a casa do trecho velho não vale', pg_temp.foco(d_hoje, pg_temp.os('OS-J13')) !~ 'casa do cliente', null);
  update public.os_planejamento set trecho = null, local_id = null, local_fonte = null, local_em = null where service_order_id = pg_temp.os('OS-J13');

  -- O autorizado com o local nulo conta (P7: os_autorizados.local_id pode ser nulo)
  insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho, criado_em, criado_por)
  values (pg_temp.os('OS-J12'), v_rafael, null, null, 'dono', 'o Rafael está autorizado', timestamptz '2027-07-01 10:15-03', v_dono);
  v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J12'));
  v_res := pg_temp.ok(v_res, 'V1v o autorizado com o local nulo aparece', v_t ~ 'Autorizados nesse serviço: Rafael\.', v_t);
  update public.os_autorizados set revogado_em = timestamptz '2027-07-02 10:00-03' where service_order_id = pg_temp.os('OS-J12');
  v_res := pg_temp.ok(v_res, 'V1w revogado não aparece', pg_temp.foco(d_hoje, pg_temp.os('OS-J12')) !~ 'Autorizados', null);

  -- A linha até 400 letras: as notas saem inteiras, o que falta combinar nunca sai por causa delas
  update public.agenda_locais
     set exige_autorizacao = true, autorizacao_texto = repeat('autorização escrita ', 9), abre = time '08:00', fecha = time '18:00', sabado = 'dia', seguro_exigido = true,
         seguro_texto = repeat('seguro de responsabilidade ', 7), conferido_em = date '2026-10-29', conferido_por = 'pesquisa'
   where nome = 'Iate Clube Caiobá';
  v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J6'));
  v_res := pg_temp.ok(v_res, 'V1x a linha até 400 letras: a nota que não cabe sai inteira, nada cortado no meio', char_length(v_t) <= 400 and v_t ~ 'Combinar: o acesso de Rafael' and v_t ~ '\.$' and v_t !~ 'autorização escrita', v_t);
  update public.agenda_locais set exige_autorizacao = null, autorizacao_texto = null, abre = null, fecha = null, sabado = null, seguro_exigido = null, seguro_texto = null,
         conferido_em = null, conferido_por = null where nome = 'Iate Clube Caiobá';
  begin
    update public.clients c set name = repeat('x', 420) from public.service_orders so where so.id = pg_temp.os('OS-J12') and c.id = so.client_id;
    v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J12'));
    v_res := pg_temp.ok(v_res, 'V1x2 sem nota nenhuma, a linha que passa de 400 é cortada', char_length(v_t) <= 400 and v_t ~ 'x{200}', format('%s letras: %s', char_length(v_t), left(v_t, 60)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- As suposições do motor na última montagem: só as que o texto não diz, só com modo ligado
  insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, itens, criada_em)
  values ('os', daterange(d_hoje, d_hoje + 7), 1, 'ligado', '{"p_hoje": "2027-07-16"}'::jsonb, 'motor', pg_temp.em(d_hoje, '23:00'),
          jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-J12'), 'suposicoes', jsonb_build_array('juntei com Marcos (OS-J9) no mesmo dia, na Marina Itajaí', 'supus o motorhome na MP Motorhomes',
                                                                                                           'Iate Clube Caiobá fica em Guaratuba (PR): supus viagem com pernoite; a ida e a volta ocupam 1 meio-dia cada'))),
          pg_temp.em(d_hoje - 2, '10:00'));
  v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J12'));
  v_res := pg_temp.ok(v_res, 'V1y a suposição do motor na linha (§6.2), sem repetir a do pátio nem a da viagem', v_t ~ 'Juntei com Marcos \(OS-J9\) no mesmo dia, na Marina Itajaí\.' and v_t !~ 'upus o motorhome' and v_t !~ 'supus viagem', v_t);
  insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, itens, criada_em)
  values ('os', daterange(d_hoje, d_hoje + 7), 1, 'ligado', '{"p_hoje": "2027-07-16"}'::jsonb, 'motor', pg_temp.em(d_hoje, '23:00'),
          jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-J12'), 'suposicoes', jsonb_build_array('evitei pôr a mesma pessoa em Itajaí e em Penha no mesmo dia (temporada)'))),
          pg_temp.em(d_hoje - 1, '10:00'));
  v_t := pg_temp.foco(d_hoje, pg_temp.os('OS-J12'));
  v_res := pg_temp.ok(v_res, 'V1z a última montagem da OS é a que vale', v_t ~ 'Evitei pôr a mesma pessoa' and v_t !~ 'Juntei', v_t);
  perform pg_temp.modos('sombra');
  v_res := pg_temp.ok(v_res, 'V1aa em teste, as chaves da proposta não são lidas (o motor em teste não as grava: R6.8-3)', pg_temp.foco(d_hoje, pg_temp.os('OS-J12')) !~ 'Evitei', null);
  perform pg_temp.modos('ligado');

  -- Quem ficou de fora porque o pátio encheu
  insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, fora, criada_em)
  values ('semana', daterange(d_hoje, d_hoje + 7), 1, 'ligado', '{"p_hoje": "2027-07-16"}'::jsonb, 'motor', pg_temp.em(d_hoje, '23:00'),
          jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-J5'), 'motivo', 'sem_encaixe', 'patio_cheio', true,
                                               'texto', 'Vanderlei (OS-J5): a MP Motorhomes fica cheia nas próximas semanas (3 vagas). Me diga se cabe mais um, ou quando outro motorhome sai.')),
          pg_temp.em(d_hoje - 1, '11:00'));
  v_t := pg_temp.foco(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1ab o de fora pelo pátio cheio (§6.2), como o motor escreveu', v_t ~ E'\n- Vanderlei \\(OS-J5\\): a MP Motorhomes fica cheia nas próximas semanas \\(3 vagas\\)\\. Me diga se cabe mais um, ou quando outro motorhome sai\\.\nLocais:', v_t);
  update public.agenda_config set modo_patio = 'sombra' where id;
  v_res := pg_temp.ok(v_res, 'V1ac em teste o motor não diz isso: a linha não sai', pg_temp.foco(d_hoje) !~ 'fica cheia', null);
  update public.agenda_config set modo_patio = 'ligado' where id;
  insert into public.agenda_propostas (escopo, periodo, versao_base, modo, parametros, criada_por, expira_em, itens, criada_em)
  values ('os', daterange(d_hoje, d_hoje + 7), 1, 'ligado', '{"p_hoje": "2027-07-16"}'::jsonb, 'motor', pg_temp.em(d_hoje, '23:00'),
          jsonb_build_array(jsonb_build_object('os', pg_temp.os('OS-J5'))), pg_temp.em(d_hoje - 1, '12:00'));
  v_res := pg_temp.ok(v_res, 'V1ad a montagem seguinte que encaixou a OS tira a linha', pg_temp.foco(d_hoje) !~ 'fica cheia', null);

  -- Sem vagas ditas, o foco só conta
  update public.agenda_locais set vagas = null where tipo = 'patio_hbr';
  v_t := pg_temp.foco(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1ae sem número de vagas, só conta (§3.1-9, R6.11)', v_t ~ E'\nMP Motorhomes: 2 serviços nas próximas 3 semanas \\(sem número de vagas, só conto\\)\\.', v_t);
  update public.agenda_config set modo_patio = 'desligado' where id;
  v_res := pg_temp.ok(v_res, 'V1af sem modo_patio, não conta', pg_temp.foco(d_hoje) !~ 'só conto', null);
  update public.agenda_config set modo_patio = 'ligado' where id;
  update public.agenda_locais set vagas = 3 where tipo = 'patio_hbr';
  v_res := pg_temp.ok(v_res, 'V1ag com vagas ditas, não é "só conto"', pg_temp.foco(d_hoje) !~ 'só conto', null);

  -- O cadastro: mais de um conferido, a marina, mais do que cabe
  update public.agenda_locais set conferido_em = date '2027-07-02', conferido_por = 'dono' where nome = 'Veleiros da Ilha';
  update public.agenda_locais set conferido_em = date '2027-07-03', conferido_por = 'marina' where nome = 'Iate Clube Caiobá';
  v_t := pg_temp.foco(date '2030-01-07');
  v_res := pg_temp.ok(v_res, 'V1ah vencidos, a conferência de 3 anos atrás não conta nem para a marina', v_t ~ 'nenhum conferido por você\.' and v_t !~ 'pela marina', v_t);
  v_t := pg_temp.foco(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1ai 2 conferidos por você, a mais nova primeiro, e 1 pela marina',
                      v_t ~ 'Locais: 5 no cadastro; 2 conferidos por você \(Veleiros da Ilha, em 02/07; Marina Itajaí, em 01/07\), 1 pela marina\.', v_t);
  insert into public.agenda_locais (nome, tipo, municipio, conferido_em, conferido_por) values ('Local A', 'marina', 'Penha', date '2027-07-04', 'dono'), ('Local B', 'marina', 'Penha', date '2027-07-05', 'dono');
  v_t := pg_temp.foco(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1aj mais de 3: "e mais N"', v_t ~ '4 conferidos por você \(Local B, em 05/07; Local A, em 04/07; Veleiros da Ilha, em 02/07; e mais 1\)', v_t);
  update public.agenda_locais set ativo = false where nome in ('Local A', 'Local B');
  v_t := pg_temp.foco(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1ak local inativo não conta', v_t ~ 'Locais: 5 no cadastro; 2 conferidos' and v_t !~ 'Local A', v_t);
  insert into public.agenda_locais (nome, tipo, municipio, sabado, seguro_exigido, conferido_em, conferido_por)
  values ('Nota 0', 'marina', 'Penha', null, null, date '2026-10-30', 'pesquisa'),   -- sem regra nenhuma: não há o que dizer dela
         ('Nota 1', 'marina', 'Penha', 'nao', true, date '2026-10-29', 'pesquisa'), ('Nota 2', 'marina', 'Penha', 'dia', null, date '2026-10-28', 'pesquisa'),
         ('Nota 3', 'marina', 'Penha', null, null, date '2026-10-27', 'pesquisa');
  update public.agenda_locais set tem_garagem_seca = true where nome = 'Nota 3';
  v_t := pg_temp.foco(d_hoje);
  v_res := pg_temp.ok(v_res, 'V1al as notas: as frases de cada regra, até 3, e "e mais N"',
                      v_t ~ 'Só como nota: Nota 1 pede seguro e não abre no sábado \(pesquisa\); Tedesco Marina Garden Plaza tem garagem seca \(pesquisa\); Nota 2 abre no sábado \(pesquisa\) \(e mais 1\)\.', v_t);
  update public.agenda_locais set ativo = false where nome like 'Nota %';
  update public.agenda_locais set conferido_em = null, conferido_por = null where nome = 'Veleiros da Ilha';
  update public.agenda_locais set conferido_em = null, conferido_por = null where nome = 'Iate Clube Caiobá';

  -- O "Em teste" de cada tipo, com o tipo em sombra
  perform pg_temp.modos('sombra');
  update public.agenda_locais set vagas = 1 where tipo = 'patio_hbr';
  perform pg_temp.aloc(pg_temp.os('OS-J6'), v_rafael, date '2027-07-23', 'manha');
  perform pg_temp.aloc(pg_temp.os('OS-J3'), v_alex, date '2027-07-21', 'manha');
  v_j := public._agenda_ver_locais(date '2027-07-19');
  v_t := (v_j ->> 'texto');
  v_t2 := (select string_agg(e, ' | ') from jsonb_array_elements_text(v_j -> 'em_teste') e);
  v_res := pg_temp.ok(v_res, 'V1am o que eu faria, um de cada tipo: o calendário, o acesso, a viagem e o pátio',
                      v_t2 ~ 'Em teste: com o calendário do local ligado, eu não marcaria ter 20/07 para Lenine \(feriado em Balneário Camboriú\)\.'
                      and v_t2 ~ 'Em teste: eu perguntaria a você hoje sobre Nelson \(OS-J2\): o acesso na Marina Itajaí para ter 20/07 ainda não está combinado\.'
                      and v_t2 ~ 'Em teste: com a viagem ligada, eu remarcaria Kalmar \(OS-J6\): a viagem precisa de 2 dias úteis seguidos com a mesma equipe\.'
                      and v_t2 ~ 'Em teste: com o pátio ligado, eu não marcaria [a-zé]+ [0-9/]+ para Vanderlei: a MP Motorhomes está cheia nesse dia \(1 vaga\)\.', v_t2);
  v_n := jsonb_array_length(v_j -> 'em_teste');
  v_res := pg_temp.ok(v_res, 'V1an no texto, até 3 linhas "Em teste" e "e mais N"; em_teste leva todas',
                      v_n >= 4 and (select count(*) from regexp_split_to_table(v_t, E'\n') l where l ~ '^Em teste: ') <= 4
                      and v_t ~ format('Em teste: e mais %s\.$', v_n - 3), v_t);
  -- Com o modo ligado (ou desligado), a linha daquele tipo não sai
  update public.agenda_config set modo_local_calendario = 'ligado', modo_patio = 'desligado', modo_viagem = 'desligado', modo_local_autorizacao = 'desligado' where id;
  v_j := public._agenda_ver_locais(date '2027-07-19');
  v_res := pg_temp.ok(v_res, 'V1ao tipo ligado ou desligado: nenhum "Em teste" (só em sombra; R6.3-6)', v_j -> 'em_teste' = '[]'::jsonb, v_j::text);
  -- Cada um ligado e os outros em teste: só a linha dele some (com os outros desligados, a conta de cima não separa)
  for v_t2 in select x from unnest(array['modo_local_calendario|com o calendário', 'modo_local_autorizacao|eu perguntaria', 'modo_patio|com o pátio', 'modo_viagem|com a viagem']) x loop
    perform pg_temp.modos('sombra');
    execute format('update public.agenda_config set %I = ''ligado'' where id', split_part(v_t2, '|', 1));
    v_j := public._agenda_ver_locais(date '2027-07-19');
    v_t := (select string_agg(e, ' | ') from jsonb_array_elements_text(v_j -> 'em_teste') e);
    v_res := pg_temp.ok(v_res, format('V1ao2 %s ligado: a linha dele some, as outras ficam', split_part(v_t2, '|', 1)),
                        v_t !~ ('Em teste: ' || split_part(v_t2, '|', 2)) and v_t ~ 'Em teste: ', v_t);
  end loop;
  -- Com p_os, só o dela
  perform pg_temp.modos('sombra');
  v_j := public._agenda_ver_locais(date '2027-07-19', pg_temp.os('OS-J6'));
  v_res := pg_temp.ok(v_res, 'V1ap com p_os, só o "Em teste" dela', jsonb_array_length(v_j -> 'em_teste') = 1 and v_j ->> 'texto' ~ E'\nEm teste: com a viagem ligada, eu remarcaria Kalmar', v_j::text);
  -- O meio-dia e a retirada
  update public.agenda_locais set abre = time '14:00', fecha = time '18:00' where nome = 'Marina Itajaí';
  update public.os_planejamento set retirada_em = date '2027-07-19', entrada_em = date '2027-07-10', entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J1');
  v_j := public._agenda_ver_locais(date '2027-07-19');
  v_t2 := (select string_agg(e, ' | ') from jsonb_array_elements_text(v_j -> 'em_teste') e);
  v_res := pg_temp.ok(v_res, 'V1aq o meio-dia fora do horário e a retirada, com o dia certo',
                      v_t2 ~ 'eu não marcaria ter 20/07 de manhã para Nelson \(Marina Itajaí não recebe a equipe\)\.'
                      and v_t2 ~ 'eu não marcaria ter 20/07 para Lenine \(feriado em Balneário Camboriú\)\.', v_t2);
  update public.agenda_config set modo_patio = 'desligado' where id;
  update public.agenda_locais set municipio = 'Penha' where tipo = 'patio_hbr';
  v_j := public._agenda_ver_locais(date '2027-07-19');
  v_t2 := (select string_agg(e, ' | ') from jsonb_array_elements_text(v_j -> 'em_teste') e);
  v_res := pg_temp.ok(v_res, 'V1ar a retirada só com o pátio fora de desligado', coalesce(v_t2, '') !~ 'o bem sai', v_t2);
  update public.agenda_config set modo_patio = 'sombra' where id;
  v_j := public._agenda_ver_locais(date '2027-07-19');
  v_t2 := (select string_agg(e, ' | ') from jsonb_array_elements_text(v_j -> 'em_teste') e);
  v_res := pg_temp.ok(v_res, 'V1as a retirada com o pátio em teste', v_t2 ~ 'eu não marcaria ter 20/07 para Lenine \(o bem sai seg 19/07\)\.', v_t2);
  update public.agenda_locais set municipio = 'Balneário Camboriú', abre = null, fecha = null where tipo = 'patio_hbr';
  update public.agenda_locais set abre = time '08:00', fecha = time '18:00' where nome = 'Marina Itajaí';
  update public.os_planejamento set retirada_em = null, entrada_em = null, entrada_fonte = null where service_order_id = pg_temp.os('OS-J1');
  update public.agenda_locais set vagas = 3 where tipo = 'patio_hbr';

  -- O corte: o texto até texto_max, por linhas inteiras
  update public.agenda_config set texto_max = 1000 where id;
  perform pg_temp.modos('ligado');
  v_t := pg_temp.foco(d_hoje);
  -- (correção O1) o corte: as notas, depois as ditas, por último as supostas, com "(e mais N)" (a ordem é provada em agenda_fase7d_correcao.sql)
  v_res := pg_temp.ok(v_res, 'V1at o corte tira as linhas de OS do fim e fica o cadastro: "(e mais N)", até texto_max',
                      char_length(v_t) <= 1000 and v_t ~ E'\n\\(e mais [0-9]+\\)\n' and v_t ~ E'\nLocais: 5 no cadastro' and v_t ~ '^Onde é cada serviço', v_t);
  update public.agenda_config set texto_max = 400 where id;
  perform pg_temp.modos('sombra');
  v_t := pg_temp.foco(date '2027-07-19');
  v_res := pg_temp.ok(v_res, 'V1au sem caber nem o rodapé: o corte de sempre, por linha inteira', char_length(v_t) <= 400 and v_t ~ E'\n\\(e mais [0-9]+ linhas?\\)$', v_t);
  update public.agenda_config set texto_max = 1000 where id;

  -- ── V2. O cartão ──
  perform pg_temp.modos('ligado');
  v_j := public.os_plano_da_os(pg_temp.os('OS-J2'), d_hoje);
  v_k := v_j -> 'local';
  v_res := pg_temp.igual(v_res, 'V2a o bloco local do cartão (§5.8), byte a byte', v_k::text,
    '{"nome": "Marina Itajaí", "tipo": "marina", "fonte": "os", "notas": ["Autorizados nesse serviço: Roberto.", "Supus o teste final na água (pela linha de serviço)."], "texto": "Marina Itajaí (pela OS)", "vagas": null, "combinar": [{"ate": "2027-07-16", "texto": "o acesso de João para ter 20/07, até hoje (sex 16/07)", "vencido": true, "em_teste": false}, {"ate": "2027-07-16", "texto": "a vaga de serviço com a marina, até sex 16/07", "vencido": true, "em_teste": false}, {"ate": "2027-07-16", "texto": "a descida para o teste na água em ter 20/07", "vencido": true, "em_teste": false}], "bem_texto": "O barco: em seco (garagem), quem desce: a marina; o teste final é na água.", "perguntei": null, "suposicao": false, "viagem_texto": null}');
  update public.os_planejamento set acesso_ok_em = pg_temp.em(d_hoje, '09:00') where service_order_id = pg_temp.os('OS-J2');
  v_k := public.os_plano_da_os(pg_temp.os('OS-J2'), d_hoje) -> 'local';
  v_res := pg_temp.ok(v_res, 'V2b o que ficou combinado sai da lista', jsonb_array_length(v_k -> 'combinar') = 2 and (v_k -> 'combinar')::text !~ 'o acesso', v_k::text);
  update public.os_planejamento set acesso_ok_em = null where service_order_id = pg_temp.os('OS-J2');
  v_k := public.os_plano_da_os(pg_temp.os('OS-J3'), d_hoje) -> 'local';
  v_res := pg_temp.ok(v_res, 'V2c a suposição: fonte patio, o "Perguntei" do M11 que saiu, as vagas do pátio', v_k ->> 'fonte' = 'patio' and (v_k ->> 'suposicao')::boolean and v_k ->> 'perguntei' = 'Perguntei ao cliente em 15/07.'
                      and (v_k ->> 'vagas')::int = 3 and v_k ->> 'tipo' = 'patio_hbr', v_k::text);
  v_k := public.os_plano_da_os(pg_temp.os('OS-J6'), d_hoje) -> 'local';
  v_res := pg_temp.ok(v_res, 'V2d a viagem fora da região, sem nenhum valor', v_k ->> 'viagem_texto' ~ '^Viagem com pernoite \(suposição: outro estado\)' and v_k::text !~ 'R\$', v_k::text);
  perform pg_temp.modos('sombra');
  v_k := public.os_plano_da_os(pg_temp.os('OS-J2'), d_hoje) -> 'local';
  v_res := pg_temp.ok(v_res, 'V2e em teste: o bloco aparece, com o que combinar marcado em_teste (§10, passo 3)', (v_k -> 'combinar' -> 0 ->> 'em_teste')::boolean, v_k::text);
  perform pg_temp.modos('desligado');
  v_j := public.os_plano_da_os(pg_temp.os('OS-J2'), d_hoje);
  v_res := pg_temp.ok(v_res, 'V2f os 6 desligados: a chave nula, o resto do cartão de pé', v_j ? 'local' and v_j -> 'local' = 'null'::jsonb and v_j ->> 'numero' = 'OS-J2', (v_j -> 'local')::text);
  perform pg_temp.modos('ligado');
  update public.service_orders set status = 'completed' where id = pg_temp.os('OS-J8');
  v_j := public.os_plano_da_os(pg_temp.os('OS-J8'), d_hoje);
  v_res := pg_temp.ok(v_res, 'V2g a OS concluída: nulo', v_j -> 'local' = 'null'::jsonb, (v_j -> 'local')::text);
  update public.service_orders set status = 'open' where id = pg_temp.os('OS-J8');
  -- O bloco cliente: a resposta ao M11 não é o acesso (o recado do P6)
  v_id := (select m.id from public.agenda_cliente_mensagens m where m.service_order_id = pg_temp.os('OS-J3') and m.tipo = 'onde_fica');
  insert into public.agenda_cliente_respostas (id, client_id, service_order_id, mensagem_id, recebida_em, tipo_msg, texto, intencao, efeito, modo)
  select gen_random_uuid(), m.client_id, m.service_order_id, m.id, timestamptz '2027-07-15 11:00-03', 'text', 'trago dia 20', 'outro', 'anotou_acesso', 'ligado'
    from public.agenda_cliente_mensagens m where m.id = v_id returning id into v_id2;
  update public.agenda_cliente_mensagens set estado = 'respondida', resposta_id = v_id2 where id = v_id;
  v_t := public.os_plano_da_os(pg_temp.os('OS-J3'), d_hoje) -> 'cliente' ->> 'mensagens';
  v_res := pg_temp.ok(v_res, 'V2h o cartão: a resposta ao M11 "disse onde fica", não "disse o acesso"', v_t ~ 'mandada; respondeu: disse onde fica, e eu anotei e perguntei a você' and v_t !~ 'disse o acesso', v_t);

  -- ── V4. A ação local no "o que mudou" (R6.3-6) ──
  perform pg_temp.modos('sombra');
  perform set_config('agenda.agora', pg_temp.em(d_hoje, '16:20')::text, true);
  v_j := public.agenda_local_vigiar(d_hoje, pg_temp.em(d_hoje, '16:20'));
  v_res := pg_temp.ok(v_res, 'V4a a rodada em teste gravou a ação: vigia, não executada, já contada (nota do P5, desvio 8)',
                      exists (select 1 from public.agenda_acoes a where a.tipo = 'local' and a.origem = 'vigia' and not a.executada and a.contada_em is not null and a.texto = 'Em teste: eu cobraria o acesso de João na Marina Itajaí até sex 16/07.'), v_j::text);
  v_res := pg_temp.ok(v_res, 'V4b a de vigia em teste entra em _agenda_mudancas (o foco), sem recriar nada (R6.3-6)',
                      public._agenda_mudancas(d_hoje - 6, d_hoje, false, false, null)::text like '%Em teste: eu cobraria o acesso de João%', null);
  update public.agenda_config set modo_proposta = 'sombra' where id;
  v_t := public.agenda_ver(null, null, null, 'mudancas', null, null, false, d_hoje) ->> 'texto';
  v_res := pg_temp.ok(v_res, 'V4b2 com a proposta em teste, o foco mudancas a mostra', v_t ~ 'Em teste: eu cobraria o acesso de João na Marina Itajaí até sex 16/07', v_t);
  update public.agenda_config set modo_proposta = 'ligado' where id;
  v_t := public.agenda_ver(null, null, null, 'mudancas', null, null, false, d_hoje) ->> 'texto';
  v_t2 := pg_temp.foco(d_hoje, pg_temp.os('OS-J2'));
  v_res := pg_temp.ok(v_res, 'V4b3 com a proposta ligada (produção), o foco mudancas só mostra o que valeu: o "em teste" do local fica no foco locais (notas do P8)',
                      v_t !~ 'eu cobraria' and v_t2 ~ 'Em teste, eu cobraria: o acesso de João', v_t);
  v_t := (select string_agg(l ->> 'texto', ' | ') from jsonb_array_elements(public._agenda_linhas_do_fechamento(d_hoje) -> 'linhas') l);
  v_res := pg_temp.ok(v_res, 'V4c o fechamento não a leva (contada): byte a byte', coalesce(v_t, '') !~ 'eu cobraria', v_t);
  -- a do dono não entra, como as outras ações do dono
  insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, critica, antes, depois, texto, motivo, autor, desfazivel_ate)
  values (pg_temp.em(d_hoje, '16:25'), d_hoje, true, 'dono', 'local', pg_temp.os('OS-J8'), array[pg_temp.os('OS-J8')], false, '{}'::jsonb, '{"efeito": "planejar"}'::jsonb,
          'Tiago: Local: Marina Itajaí.', 'você disse', v_dono, pg_temp.em(d_hoje, '23:00'));
  v_t := public.agenda_ver(null, null, null, 'mudancas', null, null, false, d_hoje) ->> 'texto';
  v_res := pg_temp.ok(v_res, 'V4d a ação local do dono não entra no "o que mudou" (R6.3-6)', v_t !~ 'Tiago: Local', v_t);
  v_res := pg_temp.ok(v_res, 'V4e nenhuma migration da 7d recria _agenda_mudancas (R6.3-6)',
                      not exists (select 1 from unnest(array['mig_tabelas_fase7d', 'mig_motor_fase7d', 'mig_combinar_fase7d', 'mig_cliente_fase7d', 'mig_responder_fase7d', 'mig_rascunho_fase7d', 'mig_leituras_fase7d']) n
                                   where position('function public._agenda_mudancas(' in coalesce(current_setting('agenda_teste.' || n, true), '')) > 0), null);
  delete from public.agenda_vigia_rodadas where rotina = 'local';

  -- ── V5. A saúde ──
  perform pg_temp.modos('desligado');
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '16:20'));
  v_res := pg_temp.ok(v_res, 'V5a tudo desligado: os zeros, nenhuma leitura de número, sem rodada atrasada', (v_j ->> 'zeros_ok')::boolean and v_j -> 'numeros' = '{}'::jsonb
                      and (v_j ->> 'rodada_local_atrasada')::int = 0 and (v_j ->> 'rodadas_24h')::int = 0, v_j::text);
  v_res := pg_temp.ok(v_res, 'V5b a chave local em agenda_saude, com os mesmos zeros', (public.agenda_saude(d_hoje, pg_temp.em(d_hoje, '16:20')) -> 'local' ->> 'zeros_ok')::boolean, null);
  update public.agenda_config set onde_fica_desde = date '2027-07-01' where id;
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '16:20'));
  v_res := pg_temp.ok(v_res, 'V5a2 tudo desligado, com a data do dado antiga: sem rodada atrasada', (v_j ->> 'rodada_local_atrasada')::int = 0, v_j::text);
  update public.agenda_config set onde_fica_desde = null where id;

  -- A rodada atrasada: conta de onde_fica_desde antes da 1ª; depois, da última
  perform pg_temp.modos('sombra');
  update public.agenda_config set onde_fica_desde = d_hoje where id;
  v_j := public._agenda_saude_local(d_hoje + 1, pg_temp.em(d_hoje + 1, '18:00'));
  v_res := pg_temp.ok(v_res, 'V5c antes da 1ª rodada, dentro das 26 h: nada (publicar à noite não acusa)', (v_j ->> 'rodada_local_atrasada')::int = 0, v_j::text);
  v_j := public._agenda_saude_local(d_hoje + 1, pg_temp.em(d_hoje + 1, '18:16'));
  v_res := pg_temp.ok(v_res, 'V5d sem rodada 26 h depois de onde_fica_desde às 16:15: 1, e o zeros_ok cai', (v_j ->> 'rodada_local_atrasada')::int = 1 and not (v_j ->> 'zeros_ok')::boolean, v_j::text);
  v_res := pg_temp.ok(v_res, 'V5e o ok de agenda_saude cai junto', not (public.agenda_saude(d_hoje + 1, pg_temp.em(d_hoje + 1, '18:16')) ->> 'ok')::boolean, null);
  -- A fixture já dá ok falso por outras razões: a prova troca o ok de antes por true, numa cópia, e olha só o que a 7d acrescenta
  v_t := (select p.prosrc from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure);
  execute 'create function pg_temp.saude_ok(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable set search_path to ''public'' as $x$'
          || replace(v_t, '  -- (7d P8; §11, R6.3-11;', E'  v_gr := jsonb_set(v_gr, ''{ok}'', ''true'');\n  -- (7d P8; §11, R6.3-11;') || '$x$';
  v_res := pg_temp.ok(v_res, 'V5e2 só o zero do local derruba o ok', not (pg_temp.saude_ok(d_hoje + 1, pg_temp.em(d_hoje + 1, '18:16')) ->> 'ok')::boolean, null);
  v_res := pg_temp.ok(v_res, 'V5e3 sem o zero, o ok fica', (pg_temp.saude_ok(d_hoje + 1, pg_temp.em(d_hoje + 1, '18:00')) ->> 'ok')::boolean, null);
  v_j := public.agenda_local_vigiar(d_hoje, pg_temp.em(d_hoje, '16:20'));
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '16:40'));
  v_res := pg_temp.ok(v_res, 'V5f com a rodada: nada atrasado; a última rodada e as 24 h', (v_j ->> 'rodada_local_atrasada')::int = 0 and (v_j ->> 'rodadas_24h')::int = 1
                      and (v_j ->> 'ultima_rodada')::timestamptz = pg_temp.em(d_hoje, '16:20'), v_j::text);
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '16:10'));
  v_res := pg_temp.ok(v_res, 'V5f2 a rodada depois de p_agora não conta', v_j -> 'ultima_rodada' = 'null'::jsonb and (v_j ->> 'rodadas_24h')::int = 0, v_j::text);
  v_j := public._agenda_saude_local(d_hoje + 1, pg_temp.em(d_hoje + 1, '18:21'));
  v_res := pg_temp.ok(v_res, 'V5g 26 h depois da última: 1', (v_j ->> 'rodada_local_atrasada')::int = 1 and (v_j ->> 'rodadas_24h')::int = 0, v_j::text);
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
  select pg_temp.em(d_hoje + 1, '18:00'), d_hoje + 1, pg_temp.em(d_hoje + 1, '18:00'), c.modo_proposta, c.modo_vigia, '{"modos": {}}'::jsonb, 0, 1, 'habilidade', c.modo_equipe, c.modo_diaria
    from public.agenda_config c;
  v_j := public._agenda_saude_local(d_hoje + 1, pg_temp.em(d_hoje + 1, '18:21'));
  v_res := pg_temp.ok(v_res, 'V5g2 a rodada de outra rotina não conta: segue 1', (v_j ->> 'rodada_local_atrasada')::int = 1, v_j::text);
  delete from public.agenda_vigia_rodadas where rotina = 'habilidade' and p_agora = pg_temp.em(d_hoje + 1, '18:00');
  update public.agenda_config set onde_fica_desde = null where id;
  delete from public.agenda_vigia_rodadas where rotina = 'local';
  v_j := public._agenda_saude_local(d_hoje + 1, pg_temp.em(d_hoje + 1, '18:21'));
  v_res := pg_temp.ok(v_res, 'V5h sem rodada e sem onde_fica_desde (o dado não foi aplicado): 0', (v_j ->> 'rodada_local_atrasada')::int = 0, v_j::text);

  -- acesso_sem_preparo: véspera, sem acesso, sem a pergunta, depois da rodada do dia
  perform pg_temp.modos('ligado');
  v_j := public._agenda_saude_local(date '2027-07-19', pg_temp.em(date '2027-07-19', '10:00'));
  v_res := pg_temp.ok(v_res, 'V5i a véspera antes da rodada do dia: 0 (a crítica nasce nela)', (v_j ->> 'acesso_sem_preparo')::int = 0, v_j::text);
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
  select pg_temp.em(date '2027-07-19', '16:20'), date '2027-07-19', pg_temp.em(date '2027-07-19', '16:20'), c.modo_proposta, c.modo_vigia, '{"modos": {}}'::jsonb, 0, 1, 'local', c.modo_equipe, c.modo_diaria
    from public.agenda_config c;
  v_j := public._agenda_saude_local(date '2027-07-19', pg_temp.em(date '2027-07-19', '17:00'));
  v_res := pg_temp.ok(v_res, 'V5j a véspera sem a pergunta, depois da rodada: 1 por OS (Nelson)', (v_j ->> 'acesso_sem_preparo')::int = 1 and not (v_j ->> 'zeros_ok')::boolean, v_j::text);
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, recomendacao, versao_base, modo, criada_em, expira_em)
  values ('acesso', format('acesso:%s:2027-07-20', pg_temp.os('OS-J2')), pg_temp.os('OS-J2'), array[pg_temp.os('OS-J2')], date '2027-07-20', date '2027-07-20', 'a crítica',
          '[{"n": 1, "texto": "Está combinado"}, {"n": 2, "texto": "Vou combinar hoje"}]'::jsonb, 2, 1, 'ligado', pg_temp.em(date '2027-07-19', '16:20'), pg_temp.em(date '2027-07-21', '00:00'));
  v_j := public._agenda_saude_local(date '2027-07-19', pg_temp.em(date '2027-07-19', '17:00'));
  v_res := pg_temp.ok(v_res, 'V5k com a pergunta aberta: 0', (v_j ->> 'acesso_sem_preparo')::int = 0, v_j::text);
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where chave like 'acesso:%' and service_order_id = pg_temp.os('OS-J2');
  v_j := public._agenda_saude_local(date '2027-07-19', pg_temp.em(date '2027-07-19', '17:00'));
  v_res := pg_temp.ok(v_res, 'V5k2 a pergunta resolvida não tira: volta a 1', (v_j ->> 'acesso_sem_preparo')::int = 1, v_j::text);
  update public.agenda_config set gestor_so_propor = true where id;
  v_j := public._agenda_saude_local(date '2027-07-19', pg_temp.em(date '2027-07-19', '17:00'));
  v_res := pg_temp.ok(v_res, 'V5l com o freio: ligado conta como em teste, 0 (R6.7b)', (v_j ->> 'acesso_sem_preparo')::int = 0 and v_j #>> '{modos,acesso}' = 'sombra', v_j::text);
  update public.agenda_config set gestor_so_propor = false where id;
  update public.os_planejamento set acesso_ok_em = pg_temp.em(d_hoje, '09:00') where service_order_id = pg_temp.os('OS-J2');
  v_j := public._agenda_saude_local(date '2027-07-19', pg_temp.em(date '2027-07-19', '17:00'));
  v_res := pg_temp.ok(v_res, 'V5m o acesso combinado: 0', (v_j ->> 'acesso_sem_preparo')::int = 0, v_j::text);
  update public.os_planejamento set acesso_ok_em = null where service_order_id = pg_temp.os('OS-J2');
  update public.agenda_config set modo_local_autorizacao = 'sombra' where id;
  v_j := public._agenda_saude_local(date '2027-07-19', pg_temp.em(date '2027-07-19', '17:00'));
  v_res := pg_temp.ok(v_res, 'V5n em teste, o acesso que falta não conta', (v_j ->> 'acesso_sem_preparo')::int = 0, v_j::text);
  update public.agenda_config set modo_local_autorizacao = 'ligado' where id;
  delete from public.agenda_vigia_rodadas where rotina = 'local';

  -- feriado_local_marcado: J1 em 20/07, publicada antes da rodada com o passo calendario
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5o sem rodada com o passo calendario: 0 (a reação é em até 24 h, R6.8-4)', (v_j ->> 'feriado_local_marcado')::int = 0, v_j::text);
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
  select pg_temp.em(d_hoje, '16:20'), d_hoje, pg_temp.em(d_hoje, '16:20'), c.modo_proposta, c.modo_vigia, '{"modos": {}}'::jsonb, 0, 1, 'local', c.modo_equipe, c.modo_diaria
    from public.agenda_config c;
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5o2 a rodada que não passou pelo calendário não conta: 0', (v_j ->> 'feriado_local_marcado')::int = 0, v_j::text);
  delete from public.agenda_vigia_rodadas where rotina = 'local';
  insert into public.agenda_vigia_rodadas (rodou_em, p_hoje, p_agora, modo_proposta, modo_vigia, contagens, erros, duracao_ms, rotina, modo_equipe, modo_diaria)
  select pg_temp.em(d_hoje, '16:20'), d_hoje, pg_temp.em(d_hoje, '16:20'), c.modo_proposta, c.modo_vigia, '{"calendario": {"os": 0}}'::jsonb, 0, 1, 'local', c.modo_equipe, c.modo_diaria
    from public.agenda_config c;
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5p a publicada que a rodada deixou no feriado do município: 1', (v_j ->> 'feriado_local_marcado')::int = 1 and not (v_j ->> 'zeros_ok')::boolean, v_j::text);
  update public.agenda_vigia_rodadas set p_agora = timestamptz '2027-07-07 16:20-03', p_hoje = date '2027-07-07' where rotina = 'local';
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5q a publicada depois da rodada: 0, a de amanhã trata', (v_j ->> 'feriado_local_marcado')::int = 0, v_j::text);
  update public.agenda_vigia_rodadas set p_agora = pg_temp.em(d_hoje, '16:20'), p_hoje = d_hoje where rotina = 'local';
  begin
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where service_order_id = pg_temp.os('OS-J1');
    v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'V5r o que o dono fixou fica de fora: foi ele que marcou', (v_j ->> 'feriado_local_marcado')::int = 0, v_j::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  update public.agenda_config set modo_local_calendario = 'sombra' where id;
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5s em teste, não conta como violação, mas entra nos números', (v_j ->> 'feriado_local_marcado')::int = 0 and (v_j #>> '{numeros,feriado_em_teste}')::int = 1, v_j::text);
  update public.agenda_config set modo_local_calendario = 'ligado' where id;
  update public.agenda_locais set abre = time '14:00', fecha = time '18:00' where nome = 'Marina Itajaí';
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5t o horário do local não é feriado: fica de fora deste zero', (v_j ->> 'feriado_local_marcado')::int = 1, v_j::text);
  update public.agenda_locais set abre = time '08:00', fecha = time '18:00' where nome = 'Marina Itajaí';

  -- patio_acima_das_vagas e viagem_quebrada
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5u com 3 vagas e 3 no pátio: 0; a pernoite quebrada de J6 (21 e 23/07): 1', (v_j ->> 'patio_acima_das_vagas')::int = 0 and (v_j ->> 'viagem_quebrada')::int = 1, v_j::text);
  update public.agenda_locais set vagas = 1 where tipo = 'patio_hbr';
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5v com 1 vaga: acima das vagas', (v_j ->> 'patio_acima_das_vagas')::int >= 1, v_j::text);
  update public.agenda_config set modo_patio = 'sombra', modo_viagem = 'sombra' where id;
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5w em teste: 0 nos dois', (v_j ->> 'patio_acima_das_vagas')::int = 0 and (v_j ->> 'viagem_quebrada')::int = 0, v_j::text);
  update public.agenda_config set modo_patio = 'ligado', modo_viagem = 'ligado' where id;
  update public.agenda_locais set vagas = 3 where tipo = 'patio_hbr';

  -- Os erros da rodada e os números
  perform public.log_app_error('db', 'teste', 'agenda', 'local:combinar', 'error', '{}'::jsonb);
  v_j := public._agenda_saude_local(d_hoje, now());
  v_res := pg_temp.ok(v_res, 'V5x os erros de local:% em 24 h', (v_j ->> 'erros_24h')::int >= 1, v_j::text);
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5y os números: as chaves da §11', v_j -> 'numeros' ?& array['acesso', 'dias_perdidos_semana', 'feriado_em_teste', 'mesmo_local', 'carteira', 'm11', 'combinar'], v_j::text);
  -- acesso: até D-2, só em D-1, sem acesso no dia (local de terceiro, pelo plano que já começou)
  perform pg_temp.aloc(pg_temp.os('OS-J9'), v_alex, date '2027-07-12', 'manha');
  perform pg_temp.aloc(pg_temp.os('OS-J10'), v_rafael, date '2027-07-12', 'manha');
  perform pg_temp.aloc(pg_temp.os('OS-J7'), v_joao, date '2027-07-13', 'manha');
  perform pg_temp.aloc(pg_temp.os('OS-J1'), v_joao, date '2027-07-12', 'manha');   -- no pátio da HBR: não é de terceiro (R1), não entra
  perform pg_temp.aloc(pg_temp.os('OS-J12'), v_rafael, date '2027-07-13', 'manha');   -- sem nada anotado: sem acesso
  update public.os_planejamento set acesso_ok_em = pg_temp.em(date '2027-07-13', '07:00') where service_order_id = pg_temp.os('OS-J7');   -- no próprio dia: sem acesso, não "só em D-1"
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em)   -- a reserva não é o começo do plano: não entra
  values (gen_random_uuid(), pg_temp.os('OS-J2'), v_joao, date '2027-07-14', 'manha', 'turno', 'reserva', 'teto', 'publicada', 'motor', timestamptz '2027-07-08 16:30-03');
  update public.os_planejamento set acesso_ok_em = pg_temp.em(date '2027-07-08', '10:00') where service_order_id = pg_temp.os('OS-J9');
  update public.os_planejamento set acesso_ok_em = pg_temp.em(date '2027-07-09', '10:00') where service_order_id = pg_temp.os('OS-J10');
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5z o acesso nas OS que começaram: até D-2 = 1, só em D-1 = 1, sem acesso = 2 (nada anotado, e anotado no próprio dia); fora: o pátio e a reserva', v_j #> '{numeros,acesso}' = '{"so_d1": 1, "ate_d2": 1, "sem_acesso": 2}'::jsonb, (v_j #> '{numeros,acesso}')::text);
  -- os dias perdidos: não cumprido por cliente_ou_bem em marina
  update public.agenda_alocacoes set resultado = 'nao_cumprido', motivo = 'cliente_ou_bem' where service_order_id = pg_temp.os('OS-J9');
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5aa os dias perdidos da semana', (v_j #>> '{numeros,dias_perdidos_semana}')::int = 1, (v_j -> 'numeros')::text);
  -- o mesmo local: J2 (20/07) e J12 (26/07) na Marina Itajaí, semanas diferentes; J1 e J3 no pátio, mesma semana, dias diferentes
  v_res := pg_temp.ok(v_res, 'V5ab os pares do mesmo local na mesma semana', (v_j #>> '{numeros,mesmo_local,pares}')::int = 1 and (v_j #>> '{numeros,mesmo_local,juntos}')::int = 0, (v_j -> 'numeros')::text);
  -- O M11: 2 enviados na janela, 1 respondido em 48 h; fora: o em teste, o velho, o recusado
  v_id := pg_temp.m11(pg_temp.os('OS-J9'), pg_temp.em(date '2027-07-10', '10:00'));
  v_id2 := pg_temp.m11(pg_temp.os('OS-J7'), pg_temp.em(date '2027-07-11', '10:00'));
  perform pg_temp.m11(pg_temp.os('OS-J4'), pg_temp.em(date '2027-07-11', '10:00'), 'enviada', 'sombra');
  perform pg_temp.m11(pg_temp.os('OS-J5'), pg_temp.em(date '2027-06-01', '10:00'));
  update public.agenda_cliente_mensagens set estado = 'recusada', recusa_motivo = 'teto_dia', enviada_em = null where service_order_id = pg_temp.os('OS-J3') and tipo = 'onde_fica';   -- o do V1
  insert into public.agenda_cliente_respostas (client_id, service_order_id, mensagem_id, recebida_em, tipo_msg, intencao, efeito, modo)
  select so.client_id, so.id, m.id, m.enviada_em + case when m.id = v_id then interval '47 hours' else interval '49 hours' end, 'text', 'acesso', 'nada', 'ligado'
    from public.agenda_cliente_mensagens m join public.service_orders so on so.id = m.service_order_id
   where m.id in (v_id, v_id2);
  -- As perguntas do local: com a leitura do cliente (mais de uma opção), sem ela, e a velha fora
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, modo, criada_em, expira_em)
  select 'local', format('local:v5:%s', x.n), pg_temp.os('OS-J2'), array[pg_temp.os('OS-J2')], d_hoje, d_hoje, 'o local', x.op, 'ligado', x.quando, pg_temp.em(date '2027-08-30', '00:00')
    from (values (1, '[{"n": 1, "texto": "Marina Itajaí"}, {"n": 2, "texto": "Outro"}]'::jsonb, pg_temp.em(date '2027-07-10', '10:00')),
                 (2, '[{"n": 1, "texto": "Outro"}]'::jsonb, pg_temp.em(date '2027-07-11', '10:00')),
                 (3, '[{"n": 1, "texto": "Outro"}]'::jsonb, pg_temp.em(date '2027-07-12', '10:00')),
                 (4, '[{"n": 1, "texto": "Marina Itajaí"}, {"n": 2, "texto": "Outro"}]'::jsonb, pg_temp.em(date '2027-06-01', '10:00'))) x(n, op, quando);
  -- As perguntas de combinar: aberta, combinada de cada jeito, a do dia que passou; fora: a em teste e a velha
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, modo, criada_em, expira_em, estado, respondida_em, opcao_escolhida, resolvida_motivo)
  select 'combinar', format('combinar:v5:%s', x.n), pg_temp.os('OS-J2'), array[pg_temp.os('OS-J2')], d_hoje, d_hoje, 'combinar', '[{"n": 1, "texto": "Já combinei"}, {"n": 2, "texto": "Falta"}]'::jsonb,
         x.modo, x.quando, pg_temp.em(date '2027-08-30', '00:00'), x.estado, case when x.estado = 'respondida' then x.quando end, x.op, x.mot
    from (values (1, 'ligado', pg_temp.em(date '2027-07-10', '10:00'), 'aberta', null::smallint, null::text),
                 (2, 'ligado', pg_temp.em(date '2027-07-10', '10:00'), 'respondida', 1::smallint, null),
                 (3, 'ligado', pg_temp.em(date '2027-07-10', '10:00'), 'respondida', 2::smallint, null),
                 (4, 'ligado', pg_temp.em(date '2027-07-10', '10:00'), 'resolvida', null, 'já foi combinado'),
                 (5, 'ligado', pg_temp.em(date '2027-07-10', '10:00'), 'resolvida', null, 'o acesso foi anotado'),
                 (6, 'ligado', pg_temp.em(date '2027-07-10', '10:00'), 'resolvida', null, 'a autorização foi anotada'),
                 (7, 'ligado', pg_temp.em(date '2027-07-10', '10:00'), 'vencida', null, 'o dia passou'),
                 (8, 'sombra', pg_temp.em(date '2027-07-10', '10:00'), 'aberta', null, null),
                 (9, 'ligado', pg_temp.em(date '2027-06-01', '10:00'), 'aberta', null, null)) x(n, modo, quando, estado, op, mot);
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5ac o M11 dos 30 dias: 2 enviados, 1 respondido em 48 h, 1 pergunta com leitura e 2 sem (fora: o em teste, o velho, o recusado)',
                      v_j #> '{numeros,m11}' = '{"enviados": 2, "respondidos_48h": 1, "com_leitura": 1, "sem_leitura": 2}'::jsonb, (v_j #> '{numeros,m11}')::text);
  v_res := pg_temp.ok(v_res, 'V5ad o combinar dos 30 dias: 1 aberta, 4 combinadas, 1 vencida (fora: a em teste, a velha, a opção 2)',
                      v_j #> '{numeros,combinar}' = '{"abertas": 1, "combinadas": 4, "vencidas": 1}'::jsonb, (v_j #> '{numeros,combinar}')::text);
  -- A carteira: dito pelo cliente, sai das supostas e entra em pelo_cliente
  v_k := v_j #> '{numeros,carteira}';
  update public.os_planejamento set local_id = (select id from public.agenda_locais where nome = 'Veleiros da Ilha'), local_fonte = 'cliente', local_em = now()
   where service_order_id = pg_temp.os('OS-J3');
  v_j := public._agenda_saude_local(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5ae a carteira: o local dito pelo cliente sai das supostas e entra em pelo_cliente',
                      (v_j #>> '{numeros,carteira,supostas}')::int = (v_k ->> 'supostas')::int - 1 and (v_j #>> '{numeros,carteira,pelo_cliente}')::int = (v_k ->> 'pelo_cliente')::int + 1,
                      format('%s -> %s', v_k, v_j #> '{numeros,carteira}'));
  -- O M11 em tipos_liberados (o recado do P6): só quando o tipo já sai sozinho, sempre depois dos outros
  update public.agenda_config set cliente_aprovacao_dias = 2 where id;
  v_j := public.agenda_saude(d_hoje, pg_temp.em(d_hoje, '17:00'));
  v_res := pg_temp.ok(v_res, 'V5af onde_fica sem aprovação do dono: fora de tipos_liberados', not (v_j #> '{cliente,tipos_liberados}') ? 'onde_fica', (v_j #> '{cliente,tipos_liberados}')::text);
  update public.agenda_config set cliente_aprovacao_dias = 0 where id;
  v_j := public.agenda_saude(d_hoje, pg_temp.em(d_hoje, '17:00'));
  -- (7f P6) a semana prevista, liberada, entra depois do M11: fora da conta do "por último" (com e sem o P6 no banco)
  v_res := pg_temp.ok(v_res, 'V5ag onde_fica liberado: entra em tipos_liberados, por último', ((v_j #> '{cliente,tipos_liberados}') - 'semana') ->> (jsonb_array_length((v_j #> '{cliente,tipos_liberados}') - 'semana') - 1) = 'onde_fica', (v_j #> '{cliente,tipos_liberados}')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── V3. A ficha ──
  begin
    -- A ficha da 7c e o lugar da Fase 3, rodando como pg_temp: o "byte a byte" é contra elas
    execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_equipe_fase3'), '_agenda_local_da_os'), 'function public._agenda_local_da_os(', 'function pg_temp.local_antes(');
    execute replace(replace(pg_temp.inteira(current_setting('agenda_teste.mig_tarefas_fase7c'), 'agenda_equipe_ficha'), 'function public.agenda_equipe_ficha(', 'function pg_temp.ficha_antes('),
                    'public._agenda_local_da_os(', 'pg_temp.local_antes(');
    perform pg_temp.aloc(pg_temp.os('OS-J3'), v_alex, date '2027-07-22', 'manha');
    perform pg_temp.aloc(pg_temp.os('OS-J8'), v_alex, date '2027-07-23', 'manha');
    perform pg_temp.aloc(pg_temp.os('OS-J14'), v_alex, date '2027-07-26', 'manha');
    for v_i in 1 .. 2 loop
      perform pg_temp.modos(case v_i when 1 then 'sombra' else 'desligado' end);
      v_t := (select string_agg(format('%s %s', p.name, d), ', ')
                from public.payees p, unnest(array[date '2027-07-19', date '2027-07-20', date '2027-07-22', date '2027-07-23', date '2027-07-26']) d
               where p.id = any (array[v_alex, v_roberto, v_joao, v_rafael])
                 and public.agenda_equipe_ficha(p.id, d, date '2027-07-16') is distinct from pg_temp.ficha_antes(p.id, d, date '2027-07-16')
                 and not (p.id = v_alex and d = date '2027-07-26'));
      v_res := pg_temp.ok(v_res, format('V3a%s %s: a ficha de todo mundo em todo dia é a de antes, byte a byte (fora o local dito pelo dono, V3d)', v_i, case v_i when 1 then 'em teste' else 'desligado' end),
                          v_t is null, v_t);
    end loop;
    perform pg_temp.modos('sombra');
    v_j := public.agenda_equipe_ficha(v_alex, date '2027-07-20', date '2027-07-19');
    v_res := pg_temp.igual(v_res, 'V3b o lugar pela OS, byte a byte (§6.4)', v_j ->> 'texto_ficha', 'Alex, amanhã (ter 20/07): 8h no motorhome do Lenine, na MP Motorhomes. Serviço: troca do inversor. Responde OK se tá certo.');
    v_t := public.agenda_equipe_ficha(v_alex, date '2027-07-22', date '2027-07-19') ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'V3c suposto no pátio: sem lugar, como hoje', v_t !~ 'MP Motorhomes' and v_t ~ 'motorhome do Vanderlei\.', v_t);
    v_t := public.agenda_equipe_ficha(v_alex, date '2027-07-23', date '2027-07-19') ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'V3c2 suposto pela cidade do cliente: a cidade, como hoje', v_t ~ ', em Penha\.', v_t);
    v_t := public.agenda_equipe_ficha(v_alex, date '2027-07-26', date '2027-07-19') ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'V3d o local dito pelo dono vai à ficha (não é suposição; §6.4)', v_t ~ ', na Tedesco Marina Garden Plaza\.', v_t);
    v_t := pg_temp.como('c7c00000-0000-4000-8000-0000000ec006', 'authenticated', format('select public._agenda_local_da_os(%L::uuid)', pg_temp.os('OS-J14')));
    v_res := pg_temp.ok(v_res, 'V3d2 direto, pelo técnico, a cadeia lança (a leitura não vira "não sei"): quem chama é a ficha, definer', v_t like 'erro %', v_t);

    -- A frase do acesso: só ligado, antes do "Responde OK"; texto_curto também; texto_confirmar não muda
    v_k := public.agenda_equipe_ficha(v_joao, date '2027-07-20', date '2027-07-19');
    perform pg_temp.modos('ligado');
    v_j := public.agenda_equipe_ficha(v_joao, date '2027-07-20', date '2027-07-19');
    v_res := pg_temp.igual(v_res, 'V3e a frase do acesso em texto_ficha, antes do "Responde OK", byte a byte (R1)', v_j ->> 'texto_ficha',
      'João, amanhã (ter 20/07): 8h no barco do Nelson, na Marina Itajaí, com o Roberto. Serviço: teste de mar e revisão do banco de baterias. O acesso na Marina Itajaí ainda não está confirmado: eu te aviso. Responde OK se tá certo.');
    v_res := pg_temp.igual(v_res, 'V3f e em texto_curto (R6.9-1)', v_j ->> 'texto_curto',
      'Amanhã (ter 20/07): 8h no barco do Nelson, na Marina Itajaí, com o Roberto. O acesso na Marina Itajaí ainda não está confirmado: eu te aviso.');
    v_res := pg_temp.ok(v_res, 'V3g o resto igual: texto_confirmar, texto_resposta, texto_como_foi, os turnos', v_j - 'texto_ficha' - 'texto_curto' = v_k - 'texto_ficha' - 'texto_curto', v_j::text);
    update public.os_planejamento set acesso_ok_em = pg_temp.em(date '2027-07-16', '09:00') where service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'V3h com o acesso combinado: a de antes, byte a byte', public.agenda_equipe_ficha(v_joao, date '2027-07-20', date '2027-07-19') = v_k, null);
    update public.os_planejamento set acesso_ok_em = null where service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'V3i com os autorizados, o acesso combinado também', public.agenda_equipe_ficha(v_rafael, date '2027-07-26', date '2027-07-19') ->> 'texto_ficha' ~ 'O acesso na Marina Itajaí', null);
    insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho, criado_em, criado_por)
    values (pg_temp.os('OS-J12'), v_rafael, null, null, 'dono', 'o Rafael está autorizado', timestamptz '2027-07-01 10:15-03', v_dono);
    v_res := pg_temp.ok(v_res, 'V3i2 no local que pede o nome, todos autorizados: sem a frase', public.agenda_equipe_ficha(v_rafael, date '2027-07-26', date '2027-07-19') ->> 'texto_ficha' !~ 'O acesso', null);
    v_t := public.agenda_equipe_ficha(v_alex, date '2027-07-20', date '2027-07-19') ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'V3j no pátio da HBR não há acesso a combinar (R1): sem a frase', v_t !~ 'O acesso', v_t);
    v_t := public.agenda_equipe_ficha(v_alex, date '2027-07-22', date '2027-07-19') ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'V3j2 local suposto no pátio: sem a frase', v_t !~ 'O acesso', v_t);
    -- 2 locais no dia, os 2 na frase; 2 OS no mesmo local, ele uma vez
    perform pg_temp.aloc(pg_temp.os('OS-J9'), v_roberto, date '2027-07-27', 'manha');
    perform pg_temp.aloc(pg_temp.os('OS-J7'), v_roberto, date '2027-07-27', 'tarde');
    v_t := public.agenda_equipe_ficha(v_roberto, date '2027-07-27', date '2027-07-19') ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'V3k 2 locais no dia: os 2 na frase, na ordem do dia', v_t ~ ' O acesso na Marina Itajaí e na Veleiros da Ilha ainda não está confirmado: eu te aviso\. Responde OK se tá certo\.$', v_t);
    perform pg_temp.aloc(pg_temp.os('OS-J10'), v_joao, date '2027-07-27', 'manha');
    perform pg_temp.aloc(pg_temp.os('OS-J12'), v_joao, date '2027-07-27', 'tarde');
    update public.os_autorizados set revogado_em = timestamptz '2027-07-02 10:00-03' where service_order_id = pg_temp.os('OS-J12');
    v_t := public.agenda_equipe_ficha(v_joao, date '2027-07-27', date '2027-07-19') ->> 'texto_ficha';
    v_res := pg_temp.ok(v_res, 'V3k2 2 OS no mesmo local: ele uma vez só', v_t ~ ' O acesso na Marina Itajaí ainda não está confirmado' and v_t !~ 'Marina Itajaí e na', v_t);
    update public.agenda_config set gestor_so_propor = true where id;
    v_res := pg_temp.ok(v_res, 'V3l com o freio, em teste: sem a frase (R6.7b)', public.agenda_equipe_ficha(v_joao, date '2027-07-20', date '2027-07-19') = v_k, null);
    update public.agenda_config set gestor_so_propor = false where id;

    -- A saída da 7c: "O que fazer", e a frase nos 590. O dia cheio: o João hoje (ter 20/07) no Nelson e amanhã (qua 21/07) em 2 OS, com o nome do local no teto e várias etapas
    update public.agenda_locais set nome = rpad('Marina Itajaí, píer de serviço do lado sul', 80, ' do canal') where nome = 'Marina Itajaí';
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
    select md5('v3:' || so || g)::uuid, so, null, format('Revisão geral do circuito %s de bordo com o multímetro', g), 'unit', 1, 382, 382, timestamptz '2027-06-30 10:00-03'
      from unnest(array[pg_temp.os('OS-J9'), pg_temp.os('OS-J10')]) so, generate_series(1, 3) g;
    perform pg_temp.aloc(pg_temp.os('OS-J9'), v_joao, date '2027-07-21', 'manha');
    perform pg_temp.aloc(pg_temp.os('OS-J10'), v_joao, date '2027-07-21', 'tarde');
    update public.agenda_config set modo_tarefas = 'ligado', modo_equipe = 'ligado' where id;
    perform public.agenda_tarefas_rodar(date '2027-07-20', pg_temp.em(date '2027-07-20', '07:10'));
    v_j := public.agenda_equipe_ficha(v_joao, date '2027-07-21', date '2027-07-20');
    v_t := public.agenda_equipe_ficha(v_joao, date '2027-07-20', date '2027-07-20') ->> 'texto_como_foi';
    v_res := pg_temp.ok(v_res, 'V3m a saída da 7c: a frase depois de "O que fazer", antes do "Responde OK"', v_j ? 'tarefas' and v_j ->> 'texto_ficha' ~ ' O que fazer: .* O acesso na Marina Itajaí, píer .* ainda não está confirmado: eu te aviso\. Responde OK se tá certo\.$', v_j ->> 'texto_ficha');
    v_n := char_length(v_t) + 1 + char_length(v_j ->> 'texto_curto');
    v_res := pg_temp.ok(v_res, 'V3n texto_curto com a frase e com "O que fazer", e o "como foi" de hoje com ele em até 590 (a frase descontada)',
                        v_j ->> 'texto_curto' ~ ' ainda não está confirmado: eu te aviso\.$' and v_j ->> 'texto_curto' ~ 'O que fazer:' and v_n between 500 and 590, format('%s letras: %s', v_n, v_j ->> 'texto_curto'));
    perform pg_temp.modos('sombra');
    update public.agenda_locais set nome = 'Marina Itajaí' where nome like 'Marina Itajaí, píer%';
    v_k := public.agenda_equipe_ficha(v_joao, date '2027-07-21', date '2027-07-20');
    v_res := pg_temp.ok(v_res, 'V3o a saída da 7c em teste: a de antes, byte a byte', v_k = pg_temp.ficha_antes(v_joao, date '2027-07-21', date '2027-07-20') and v_k ->> 'texto_ficha' !~ 'O acesso', v_k ->> 'texto_ficha');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── V6. O determinismo e as cópias ──
  perform pg_temp.modos('sombra');
  v_res := pg_temp.ok(v_res, 'V6a o foco e o cartão duas vezes: o mesmo md5', md5(public._agenda_ver_locais(d_hoje)::text) = md5(public._agenda_ver_locais(d_hoje)::text)
                      and md5(public.os_plano_da_os(pg_temp.os('OS-J2'), d_hoje)::text) = md5(public.os_plano_da_os(pg_temp.os('OS-J2'), d_hoje)::text), null);
  v_mig := coalesce(current_setting('agenda_teste.mig_leituras_fase7d', true), '');
  select string_agg(f.nome, ', ') into v_t
    from (values ('agenda_ver', 'mig_leituras_fase7c'), ('os_plano_da_os', 'mig_leituras_fase7b'), ('agenda_saude', 'mig_leituras_fase7b'),
                 ('agenda_equipe_ficha', 'mig_tarefas_fase7c'), ('_agenda_cliente_da_os', 'mig_acabamento_fase6')) f(nome, origem)
   where pg_temp.sem_7d(pg_temp.corpo(v_mig, f.nome)) is distinct from replace(pg_temp.corpo(current_setting('agenda_teste.' || f.origem), f.nome), E'\r\n', E'\n')
      or pg_temp.corpo(v_mig, f.nome) = pg_temp.sem_7d(pg_temp.corpo(v_mig, f.nome));
  v_res := pg_temp.ok(v_res, 'V6b as 5 recriadas por blocos: tirados, são a origem, byte a byte (e cada uma tem bloco)', v_mig <> '' and v_t is null, v_t);
  -- agenda_rascunho_aplicar já vinha da 7d: o bloco do P8 é o único a mais
  v_t := replace(pg_temp.corpo(current_setting('agenda_teste.mig_responder_fase7d'), 'agenda_rascunho_aplicar'), E'\r\n', E'\n');
  v_t2 := pg_temp.corpo(v_mig, 'agenda_rascunho_aplicar');
  v_res := pg_temp.ok(v_res, 'V6b2 agenda_rascunho_aplicar: a do P6b mais um bloco, só inserido', pg_temp.sem_7d(v_t2) = pg_temp.sem_7d(v_t) and char_length(v_t2) > char_length(v_t)
                      and (select count(*) from regexp_matches(v_t2, '-- FASE 7d: fim', 'g')) = (select count(*) from regexp_matches(v_t, '-- FASE 7d: fim', 'g')) + 1, null);
  select string_agg(p.proname, ', ') into v_t
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname in ('agenda_ver', 'os_plano_da_os', 'agenda_saude', 'agenda_equipe_ficha', '_agenda_cliente_da_os', '_agenda_local_da_os')
     and pg_temp.sem_7f(p.prosrc) is distinct from pg_temp.corpo(v_mig, p.proname);
  v_res := pg_temp.ok(v_res, 'V6c no banco está a desta migration', v_t is null, v_t);
  v_t := regexp_replace(pg_temp.sem_7d(pg_temp.corpo(v_mig, '_agenda_local_da_os')), '\s+', ' ', 'g');
  v_res := pg_temp.ok(v_res, 'V6d _agenda_local_da_os: tirado o bloco, o select da Fase 3 (só o espaço mudou)', replace(v_t, 'coalesce( ', 'coalesce(') = regexp_replace(pg_temp.corpo(current_setting('agenda_teste.mig_equipe_fase3'), '_agenda_local_da_os'), '\s+', ' ', 'g'), v_t);
  v_res := pg_temp.ok(v_res, 'V6e a migration cria ou recria 11 funções: as 4 novas e as 7 recriadas', (select count(*) from regexp_matches(v_mig, '^create or replace function public\.', 'gm')) = 11, null);

  -- ── V7. Quem lê e o agenda_ver ──
  v_t := pg_temp.como('c7c00000-0000-4000-8000-0000000ec006', 'authenticated', 'select public.agenda_ver(null, null, null, ''locais'', null, null, false, date ''2027-07-16'')::text');
  v_t2 := pg_temp.como('c7c00000-0000-4000-8000-0000000ec006', 'authenticated', 'select public._agenda_ver_locais(date ''2027-07-16'')::text');
  v_res := pg_temp.ok(v_res, 'V7a a técnica logada recebe 42501 no agenda_ver e direto no foco', v_t = 'erro 42501: Os locais dos serviços são com o administrador ou o financeiro.' and v_t2 = v_t, v_t || ' · ' || v_t2);
  v_t := pg_temp.como('c7c00000-0000-4000-8000-0000000ec006', 'authenticated', 'select public._agenda_saude_local(date ''2027-07-16'', timestamptz ''2027-07-16 16:20-03'')::text');
  v_res := pg_temp.ok(v_res, 'V7b e na saúde', v_t = 'erro 42501: A saúde da agenda é com o administrador ou o financeiro.', v_t);
  v_t := pg_temp.como(v_dono, 'authenticated', 'select public.agenda_ver(null, null, null, ''locais'', null, null, false, date ''2027-07-16'') ->> ''rota''');
  v_t2 := pg_temp.como(null, 'service_role', 'select public.agenda_ver(null, null, null, ''locais'', null, null, false, date ''2027-07-16'') ->> ''rota''');
  v_res := pg_temp.ok(v_res, 'V7c o admin logado (o painel) e o service_role (o WhatsApp) leem pelo agenda_ver', v_t = 'locais' and v_t2 = 'locais', v_t || ' · ' || v_t2);
  v_t := pg_temp.como(null, 'authenticated', 'select public._agenda_ver_locais(date ''2027-07-16'')::text');
  v_res := pg_temp.ok(v_res, 'V7d authenticated sem login: 42501 (a porta dentro)', v_t like 'erro 42501%', v_t);
  v_t := pg_temp.como(null, 'authenticated', 'select public._agenda_saude_local(date ''2027-07-16'', timestamptz ''2027-07-16 16:20-03'')::text');
  v_res := pg_temp.ok(v_res, 'V7d2 e na saúde', v_t like 'erro 42501%', v_t);
  v_j := public.agenda_ver(null, null, null, 'locais', 'Igor', null, false, d_hoje);
  v_res := pg_temp.ok(v_res, 'V7e agenda_ver com a OS pelo nome: rota locais, só a OS', v_j ->> 'rota' = 'locais' and v_j ->> 'texto' ~ '^Igor \(OS-J10\): Marina Itajaí', v_j::text);
  v_j := public.agenda_ver(null, null, null, 'locais', 'Fulano de Tal', null, false, d_hoje);
  v_res := pg_temp.ok(v_res, 'V7f a OS que não existe: a frase do resolvedor', v_j ->> 'rota' = 'os' and not (v_j ->> 'ok')::boolean, v_j::text);
  begin
    perform public.agenda_ver(null, null, null, 'locais', null, null, false, null);
    v_t := 'passou';
  exception when others then
    v_t := sqlstate;
  end;
  v_res := pg_temp.ok(v_res, 'V7g sem p_hoje: 22004', v_t = '22004', v_t);
  begin
    perform public._agenda_ver_locais(null);
    v_t := 'passou';
  exception when others then
    v_t := sqlstate;
  end;
  v_res := pg_temp.ok(v_res, 'V7g2 direto também', v_t = '22004', v_t);
  begin
    perform public._agenda_saude_local(null, null);
    v_t := 'passou';
  exception when others then
    v_t := sqlstate;
  end;
  v_res := pg_temp.ok(v_res, 'V7g3 a saúde também', v_t = '22004', v_t);
  update public.agenda_config set modo_leitura = 'desligado' where id;
  v_j := public.agenda_ver(null, null, null, 'locais', null, null, false, d_hoje);
  v_res := pg_temp.ok(v_res, 'V7h a leitura desligada: a frase de sempre', v_j ->> 'rota' = 'desligada' and v_j ->> 'texto' = 'A agenda de produção está desligada agora.', v_j::text);
  update public.agenda_config set modo_leitura = 'ligado' where id;
  begin
    perform public.agenda_ver(null, null, null, 'nao_existe', null, null, false, d_hoje);
    v_t := 'passou';
  exception when others then
    v_t := sqlstate || ': ' || left(sqlerrm, 40);
  end;
  v_res := pg_temp.ok(v_res, 'V7i o foco que não existe continua com a mensagem de antes', v_t like '22023: agenda_ver: foco "nao_existe" não existe%', v_t);

  -- ── V8. A resposta em palavras ──
  begin
    delete from public.agenda_perguntas where tipo = 'combinar';
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, modo, criada_em, expira_em)
    values ('combinar', 'combinar:descida:v8a:2027-07-20', pg_temp.os('OS-J2'), array[pg_temp.os('OS-J2')], date '2027-07-20', date '2027-07-20', 'A descida do barco de Nelson está combinada? 1) Já combinei; 2) Ainda não.',
            '[{"n": 1, "texto": "Já combinei", "efeito": {"local": "nada"}}, {"n": 2, "texto": "Ainda não", "efeito": {"local": "nada"}}]'::jsonb, 'ligado', pg_temp.em(d_hoje, '16:20'), pg_temp.em(date '2027-07-21', '00:00')),
           ('combinar', 'combinar:descida:v8b:2027-07-26', pg_temp.os('OS-J12'), array[pg_temp.os('OS-J12')], date '2027-07-26', date '2027-07-26', 'A descida do barco de Beto está combinada? 1) Já combinei; 2) Ainda não.',
            '[{"n": 1, "texto": "Já combinei", "efeito": {"local": "nada"}}, {"n": 2, "texto": "Ainda não", "efeito": {"local": "nada"}}]'::jsonb, 'ligado', pg_temp.em(d_hoje, '16:21'), pg_temp.em(date '2027-07-27', '00:00'));
    update public.agenda_config set modo_bem = 'ligado', modo_local_autorizacao = 'ligado', modo_patio = 'ligado' where id;
    v_j := public.agenda_rascunho_aplicar(v_dono, 'whatsapp', null, null, '1', '1', '1', d_hoje, pg_temp.em(d_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'V8a "1", e o modelo preenche os 2: pergunta qual (a régua do P6b segue)', v_j ->> 'motivo' = 'decisao_ambigua', v_j::text);
    v_j := public.agenda_rascunho_aplicar(v_dono, 'whatsapp', null, null, '1', '1', 'pode ser', d_hoje, pg_temp.em(d_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'V8b "pode ser": não diz a pergunta nem a opção, pergunta', v_j ->> 'motivo' = 'decisao_ambigua', v_j::text);
    v_j := public.agenda_rascunho_aplicar(v_dono, 'whatsapp', null, null, '1', '1', 'o Nelson já está combinado', d_hoje, pg_temp.em(d_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'V8c as palavras dizem a pergunta e a opção: vira rascunho, e a releitura diz qual', (v_j ->> 'ok')::boolean and v_j ->> 'releitura' like '%na pergunta "A descida do barco de Nelson%: Já combinei.%', v_j::text);
    v_j := public.agenda_rascunho_aplicar(v_dono, 'whatsapp', null, null, '1', '1', 'o Nelson ainda não', d_hoje, pg_temp.em(d_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'V8d só a pergunta nas palavras, não a opção que veio: pergunta', v_j ->> 'motivo' = 'decisao_ambigua', v_j::text);
    v_j := public.agenda_rascunho_aplicar(v_dono, 'whatsapp', null, null, '1', '1', 'já combinei', d_hoje, pg_temp.em(d_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'V8e a palavra está nas 2 perguntas: não identifica nenhuma, pergunta', v_j ->> 'motivo' = 'decisao_ambigua', v_j::text);
    -- A pergunta sem número (a nota) também espera: a palavra que é dela não identifica a outra
    update public.agenda_perguntas set estado = 'descartada', resolvida_motivo = 'o teste' where chave like 'combinar:descida:v8%';
    insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, dia, perda_em, texto, opcoes, modo, criada_em, expira_em)
    values ('combinar', 'combinar:descida:v8g:2027-07-20', pg_temp.os('OS-J2'), array[pg_temp.os('OS-J2')], date '2027-07-20', date '2027-07-20', 'A descida do barco de Nelson? 1) Já combinei; 2) Ainda não.',
            '[{"n": 1, "texto": "Já combinei", "efeito": {"local": "nada"}}, {"n": 2, "texto": "Ainda não", "efeito": {"local": "nada"}}]'::jsonb, 'ligado', pg_temp.em(d_hoje, '16:20'), pg_temp.em(date '2027-07-21', '00:00')),
           ('nfe_vincular', 'nfe:v8g', pg_temp.os('OS-J2'), array[pg_temp.os('OS-J2')], date '2027-07-20', date '2027-07-20', 'A nota de Nelson é de qual serviço? 1) OS-J2; 2) Nenhum',
            '[{"n": 1, "texto": "OS-J2"}, {"n": 2, "texto": "Nenhum"}]'::jsonb, 'ligado', pg_temp.em(d_hoje, '16:22'), pg_temp.em(date '2027-07-21', '00:00'));
    v_j := public.agenda_rascunho_aplicar(v_dono, 'whatsapp', null, null, '1', '1', 'Nelson, combinei', d_hoje, pg_temp.em(d_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'V8g a palavra é também da pergunta sem número: não identifica, pergunta', v_j ->> 'motivo' = 'decisao_ambigua', v_j::text);
    v_j := public.agenda_rascunho_aplicar(v_dono, 'whatsapp', null, null, '1', '1', 'a descida, combinei', d_hoje, pg_temp.em(d_hoje, '17:00'));
    v_res := pg_temp.ok(v_res, 'V8h a palavra só desta pergunta: vira rascunho (o controle)', v_j ->> 'motivo' is distinct from 'decisao_ambigua', v_j::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  select count(*) into v_n
    from (values ('lança meia pro Roberto', 'O Roberto respondeu "fiquei só de manhã". 1) meia diária, como o Roberto disse; 2) dia inteiro', 'meia diária, como o Roberto disse', array['Não cabe tudo. Qual aceita atrasar? 1) Nelson atrasa'], true),
                 ('pode ser', 'Pode ser assim?', 'Pode ser', '{}'::text[], false), ('1', 'Decisão 1', 'opção 1', '{}'::text[], false),
                 ('na decisão 1', 'Decisão 1', 'Mandar', '{}'::text[], false), ('na decisão, mandar', 'Decisão sobre o aviso', 'Mandar', '{}'::text[], false), ('pode mandar o aviso do Nelson', 'O aviso do Nelson', 'Eu mando o aviso', '{}'::text[], true),
                 ('o Nelson', 'O aviso do Nelson', null, '{}'::text[], false), ('o Nelson', null, 'Nelson', '{}'::text[], false), (null, 'x', 'y', '{}'::text[], false),
                 ('pode mandar o aviso do Nelson', 'O aviso do Nelson', 'Eu mando', array['O aviso do Nelson de amanhã'], false),
                 ('pode mandar o aviso do Nelson', 'O aviso do Nelson', 'Eu mando', null, true),
                 ('o Nelson mando', 'O aviso do Beto. 1) Nelson; 2) não', 'Eu mando', '{}'::text[], false)) c(t, q, o, x, espera)
   where public._agenda_disse_em_palavras(c.t, c.q, c.o, c.x) is distinct from c.espera;
  v_res := pg_temp.ok(v_res, 'V8f _agenda_disse_em_palavras: a pergunta entre as que esperam, a opção; o que não diz nada não conta; a pergunta só até a 1ª opção; nulo não passa', v_n = 0, v_n::text);

  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(pg_temp.ok(v_res, 'V quebrou', false, sqlstate || ': ' || sqlerrm));
end
$v$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
