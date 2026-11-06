-- Prova das leituras do local, da viagem e do bem, Agenda de Produção, Fase 7d (pacote P3; migration 20261107100200; spec-fase7d §3.1 itens 3 a
-- 10, §5.3, §8.3 e R6.5, R6.7b, R6.8).
-- bancada: depende de 20261107100200
--
--   L0  as portas das 8 funções: STABLE (a preposição, IMMUTABLE), invoker, search_path fixo, revoke de public E de anon, provado no catálogo e
--       rodando; o administrador e o serviço leem, o técnico recebe o P0002 da agenda, anon 42501
--   L1  a cadeia do local nas 6 fontes, com o texto byte a byte, a preposição (R6.5), o local inativo, a marina da OS sem local, e a ficha de
--       hoje: o texto_equipe é o que _agenda_local_da_os já diz
--   L2  o deslocamento: coordenadas (regional, ida e volta, pernoite), o tempo dito, a viagem dita, sem coordenada pelo município, a UF, sem base
--   L3  a viagem da OS: dono > local > coordenadas > município > km > regional; o km cobrado (812 = 4 × 203) nunca vira distância
--   L4  o estado do bem: as palavras nas linhas reais de produção, as fontes, a temporada, as suposições e o texto
--   L5  a máscara: 20/07 em BC; sábado e horário só conferidos; a retirada e a entrada; as notas; não lê os modos da 7d
--   L6  a autorização só como leitura: sem filtro, quem conta e quem não conta
--   L7  as fronteiras: a migration só cria as 8; ninguém chama as 8 (motor e vigia de fora, R6.8); os nomes já usados, byte a byte
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Só na bancada: usa a fixture da 7d, que recusa a equipe real e nunca roda em produção; fora dela sai uma linha PULADO. Em produção, a
--   prova do que foi publicado é agenda_fase7d_pos_deploy.sql (P8). Termina em ROLLBACK.
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

-- O que difere entre o resultado e o esperado (só as chaves do esperado; chave ausente conta). Null = bate.
create function pg_temp.dif(p_v jsonb, p_esp jsonb) returns text language sql immutable as $f$
  select string_agg(format('%s: %s, esperava %s', e.key, coalesce((p_v -> e.key)::text, '(ausente)'), e.value), '; ' order by e.key)
    from jsonb_each(p_esp) e
   where (p_v -> e.key) is distinct from e.value
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

create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;

create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7d', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_local_fase7d', true), '') <> ''
$f$;

-- A OS e o local pelo nome (na fixture, um de cada).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select id from public.service_orders where service_order_number = p_numero
$f$;
create function pg_temp.loc(p_nome text) returns uuid language sql stable as $f$
  select id from public.agenda_locais where nome = p_nome
$f$;

-- As linhas de serviço de uma OS trocadas por estas: [[nome, valor], …], em ordem de criação.
create function pg_temp.linhas(p_os uuid, p_linhas jsonb) returns void language plpgsql as $f$
declare
  e jsonb;
  k int := 0;
begin
  delete from public.service_order_services s where s.service_order_id = p_os;
  for e in select x from jsonb_array_elements(p_linhas) x loop
    k := k + 1;
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot,
                                               line_total, created_at)
    values (p_os, e ->> 0, 'visit', 1, (e ->> 1)::numeric, (e ->> 1)::numeric, timestamptz '2027-06-01 12:00-03' + make_interval(secs => k));
  end loop;
end $f$;

do $carga$
begin
  if pg_temp.na_bancada() then
    execute current_setting('agenda_teste.fase7d');
  end if;
end
$carga$;

-- ── L0. As portas ──────────────────────────────────────────────────────────────────────────────────
-- Sem o coalesce, o null do proconfig some no bool_and (notas do P2): a função sem search_path passaria.
with f(sig, vol) as (values
  ('public._agenda_local_no(text)', 'i'),
  ('public._agenda_viagem_por_municipio(text, text)', 's'),
  ('public._agenda_local_resolvido(uuid, date)', 's'),
  ('public._agenda_local_deslocamento(uuid)', 's'),
  ('public._agenda_viagem_da_os(uuid, date, jsonb)', 's'),
  ('public._agenda_estado_do_bem(uuid, date)', 's'),
  ('public._agenda_local_mascara(uuid, date, date, date, jsonb)', 's'),
  ('public._agenda_autorizacao_da_os(uuid, date, jsonb)', 's'))
insert into _resultado
select 'L0a as 8 funções: STABLE (a preposição, IMMUTABLE), invoker, search_path fixo; revoke de public e de anon; authenticated e service_role executam',
       count(p.oid) = 8
       and bool_and(not p.prosecdef and p.provolatile = f.vol
                    and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and p.proacl is not null
                    and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and has_function_privilege('authenticated', p.oid, 'execute')
                    and has_function_privilege('service_role', p.oid, 'execute')),
       string_agg(format('%s %s definer=%s cfg=%s anon=%s auth=%s srv=%s', f.sig, p.provolatile, p.prosecdef, array_to_string(p.proconfig, ','),
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
         filter (where p.oid is null or p.prosecdef or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=public'
                       or has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute'))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

do $l0$
declare
  v_res jsonb := '[]'::jsonb;
  c_j2  uuid;
  v_adm text; v_tec text; v_ano text; v_srv text;
  v_chamadas text[] := array[
    $q$select public._agenda_local_resolvido('%1$s', date '2027-07-16') ->> 'fonte'$q$,
    $q$select public._agenda_viagem_da_os('%1$s', date '2027-07-16') ->> 'tipo'$q$,
    $q$select public._agenda_estado_do_bem('%1$s', date '2027-07-16') ->> 'exige'$q$,
    $q$select public._agenda_local_mascara('%1$s', date '2027-07-19', date '2027-07-23', date '2027-07-16') ->> 'sai'$q$,
    $q$select public._agenda_autorizacao_da_os('%1$s', date '2027-07-16') ->> 'exige'$q$];
  q text;
  v_erros text := '';
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('L0b as 8 rodando', true, 'PULADO: a fixture só existe na bancada');
    return;
  end if;
  c_j2 := pg_temp.os('OS-J2');

  -- anon não entra em nenhuma, e o motivo é o privilégio da função, não a RLS.
  foreach q in array v_chamadas loop
    v_ano := pg_temp.como(null, 'anon', format(q, c_j2));
    if v_ano not like 'erro 42501%' then v_erros := v_erros || ' ' || left(q, 40) || '=' || coalesce(v_ano, 'null'); end if;
  end loop;
  v_ano := pg_temp.como(null, 'anon', format($q$select public._agenda_local_deslocamento('%s') ->> 'fonte'$q$, pg_temp.loc('Marina Itajaí')));
  if v_ano not like 'erro 42501%' then v_erros := v_erros || ' deslocamento=' || coalesce(v_ano, 'null'); end if;
  v_ano := pg_temp.como(null, 'anon', $q$select public._agenda_local_no('x')$q$);
  if v_ano not like 'erro 42501%' then v_erros := v_erros || ' preposição=' || coalesce(v_ano, 'null'); end if;
  v_ano := pg_temp.como(null, 'anon', $q$select public._agenda_viagem_por_municipio('x', 'SC')$q$);
  if v_ano not like 'erro 42501%' then v_erros := v_erros || ' município=' || coalesce(v_ano, 'null'); end if;
  v_res := pg_temp.ok(v_res, 'L0b anon 42501 nas 8', v_erros = '', nullif(v_erros, ''));

  -- As leituras entram para quem tem a tela; a RLS de agenda_locais é que separa.
  v_erros := '';
  foreach q in array v_chamadas loop
    v_adm := pg_temp.como(pg_temp.adm(), 'authenticated', format(q, c_j2));
    if v_adm like 'erro%' then v_erros := v_erros || ' ' || v_adm; end if;
    v_srv := pg_temp.como(null, 'service_role', format(q, c_j2));
    if v_srv like 'erro%' or v_srv is distinct from v_adm then v_erros := v_erros || ' srv ' || coalesce(v_srv, 'null') || ' adm ' || coalesce(v_adm, 'null'); end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'L0c o administrador e o serviço leem as 5 da OS, com o mesmo resultado', v_erros = '', nullif(v_erros, ''));

  -- O técnico não lê a agenda: _agenda_cfg lança, como nas outras leituras da agenda (P0002, agenda_config fora do alcance). Invoker de verdade.
  v_tec := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
    format($q$select coalesce(public._agenda_local_resolvido('%s', date '2027-07-16') ->> 'local_id', 'sem local')$q$, c_j2));
  v_res := pg_temp.ok(v_res, 'L0d o técnico sem cargo não lê: a agenda fica fora do alcance dele (invoker; a leitura lança, não vira "não sei")', v_tec like 'erro P0002%', v_tec);

  perform pg_temp.gravar(v_res);
end
$l0$;

-- ── L1. A cadeia do local ──────────────────────────────────────────────────────────────────────────
do $l1$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  v jsonb; v_d text; v_ted uuid; v_it uuid; v_mp uuid; v_ficha text; v_marina uuid;
  v_t int; v_igual int; v_nulo int; v_lista text;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('L1 a cadeia do local', true, 'PULADO: a fixture só existe na bancada');
    return;
  end if;
  v_ted := pg_temp.loc('Tedesco Marina Garden Plaza');
  v_it := pg_temp.loc('Marina Itajaí');
  v_mp := pg_temp.loc('MP Motorhomes');

  -- As 6 fontes, com os textos byte a byte.
  v := public._agenda_local_resolvido(pg_temp.os('OS-J14'), c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('local_id', v_ted, 'nome', 'Tedesco Marina Garden Plaza', 'tipo', 'marina', 'municipio', 'Balneário Camboriú',
    'uf', 'SC', 'fonte', 'dono', 'suposicao', false, 'chave', 'l:' || v_ted::text, 'conferido', false, 'nota_bem', null,
    'texto', 'Tedesco Marina Garden Plaza, em Balneário Camboriú (você disse)', 'texto_curto', 'na Tedesco Marina Garden Plaza',
    'texto_equipe', 'na Tedesco Marina Garden Plaza'));
  v_res := pg_temp.ok(v_res, 'L1a fonte dono: o local dito vale, com todas as chaves do contrato', v_d is null, v_d);

  begin
    update public.os_planejamento set local_id = v_it, local_fonte = 'cliente', local_em = now() where service_order_id = pg_temp.os('OS-J8');
    v := public._agenda_local_resolvido(pg_temp.os('OS-J8'), c_hoje);
    v_d := pg_temp.dif(v, jsonb_build_object('fonte', 'cliente', 'suposicao', false, 'conferido', true, 'texto', 'Marina Itajaí (o cliente disse)',
      'texto_curto', 'na Marina Itajaí', 'texto_equipe', 'na Marina Itajaí'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1b fonte cliente: o município sai quando o nome já o diz', v_d is null, v_d);

  v := public._agenda_local_resolvido(pg_temp.os('OS-J1'), c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('local_id', v_mp, 'tipo', 'patio_hbr', 'municipio', 'Balneário Camboriú', 'fonte', 'os', 'suposicao', false,
    'chave', 'l:' || v_mp::text, 'texto', 'MP Motorhomes, em Balneário Camboriú (pela OS)', 'texto_curto', 'na MP Motorhomes', 'texto_equipe', 'na MP Motorhomes'));
  v_res := pg_temp.ok(v_res, 'L1c fonte os: o exemplo da §5.3, "MP Motorhomes, em Balneário Camboriú (pela OS)", e "na", como a ficha de hoje (R6.5)', v_d is null, v_d);

  v := public._agenda_local_resolvido(pg_temp.os('OS-J2'), c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('fonte', 'os', 'conferido', true, 'texto', 'Marina Itajaí (pela OS)', 'texto_equipe', 'na Marina Itajaí'));
  v := public._agenda_local_resolvido(pg_temp.os('OS-J6'), c_hoje);
  v_d := coalesce(v_d, pg_temp.dif(v, jsonb_build_object('fonte', 'os', 'uf', 'PR', 'texto', 'Iate Clube Caiobá, em Guaratuba (PR)',
    'texto_curto', 'na Iate Clube Caiobá', 'texto_equipe', 'na Iate Clube Caiobá')));
  v := public._agenda_local_resolvido(pg_temp.os('OS-J7'), c_hoje);
  v_d := coalesce(v_d, pg_temp.dif(v, jsonb_build_object('fonte', 'os', 'uf', 'SC', 'texto', 'Veleiros da Ilha, em Florianópolis (pela OS)')));
  v_res := pg_temp.ok(v_res, 'L1d os textos da §6.2: "Marina Itajaí (pela OS)"; fora do estado, a UF no lugar da fonte: "Iate Clube Caiobá, em Guaratuba (PR)"', v_d is null, v_d);

  begin
    update public.service_orders set marina_id = null where id = pg_temp.os('OS-J9');
    v := public._agenda_local_resolvido(pg_temp.os('OS-J9'), c_hoje);
    v_ficha := public._agenda_local_da_os(pg_temp.os('OS-J9'));
    v_d := pg_temp.dif(v, jsonb_build_object('local_id', v_it, 'fonte', 'bem', 'suposicao', false, 'nota_bem', null,
      'texto', 'Marina Itajaí (pelo cadastro do barco)', 'texto_curto', 'na Marina Itajaí', 'texto_equipe', v_ficha));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1e fonte bem: a marina do barco, sem suposição; o texto_equipe é o da ficha de hoje', v_d is null and v_ficha = 'na Marina Itajaí', coalesce(v_d, v_ficha));

  v := public._agenda_local_resolvido(pg_temp.os('OS-J3'), c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('local_id', v_mp, 'tipo', 'patio_hbr', 'fonte', 'patio', 'suposicao', true, 'chave', 'l:' || v_mp::text,
    'texto', 'MP Motorhomes (suposição: motorhome vem ao pátio)', 'texto_curto', 'na MP Motorhomes', 'texto_equipe', null));
  v_res := pg_temp.ok(v_res, 'L1f fonte patio: motorhome sem local é suposição, e o texto_equipe fica nulo (§6.4)', v_d is null, v_d);

  v := public._agenda_local_resolvido(pg_temp.os('OS-J8'), c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('local_id', null, 'nome', null, 'tipo', null, 'municipio', 'Penha', 'uf', null, 'fonte', 'cidade', 'suposicao', true,
    'chave', 'c:penha', 'conferido', false, 'texto', 'em Penha (suposição: pela cidade do cliente)', 'texto_curto', 'em Penha', 'texto_equipe', null));
  v := public._agenda_local_resolvido(pg_temp.os('OS-D3'), c_hoje);
  v_d := coalesce(v_d, pg_temp.dif(v, jsonb_build_object('fonte', 'cidade', 'chave', 'c:balneario camboriu',
    'texto', 'em Balneário Camboriú (suposição: pela cidade do cliente)')));
  v_res := pg_temp.ok(v_res, 'L1g fonte cidade: sem local_id, a chave c:<município normalizado>, suposição', v_d is null, v_d);

  v := public._agenda_local_resolvido(pg_temp.os('OS-J13'), c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('local_id', null, 'municipio', null, 'fonte', 'nenhum', 'suposicao', false, 'chave', null, 'conferido', false,
    'nota_bem', null, 'texto', 'não sei onde é o serviço', 'texto_curto', null, 'texto_equipe', null));
  v_res := pg_temp.ok(v_res, 'L1h fonte nenhum: "não sei onde é o serviço"', v_d is null, v_d);

  -- A ordem da cadeia: o dito vence a OS; a OS vence o barco (OS-00032: a OS diz Marina Itajaí, o barco diz Kalmar; NOVO-agenda-63).
  begin
    update public.vessels set marina_id = (select marina_id from public.agenda_locais where id = v_ted)
     where id = (select vessel_id from public.service_orders where id = pg_temp.os('OS-J9'));
    v := public._agenda_local_resolvido(pg_temp.os('OS-J9'), c_hoje);
    v_d := pg_temp.dif(v, jsonb_build_object('local_id', v_it, 'fonte', 'os', 'suposicao', false, 'texto_equipe', 'na Marina Itajaí',
      'nota_bem', 'o barco está cadastrado na Tedesco Marina Garden Plaza'));
    update public.os_planejamento set local_id = v_mp, local_fonte = 'dono', local_em = now() where service_order_id = pg_temp.os('OS-J9');
    v := public._agenda_local_resolvido(pg_temp.os('OS-J9'), c_hoje);
    v_d := coalesce(v_d, pg_temp.dif(v, jsonb_build_object('local_id', v_mp, 'fonte', 'dono', 'nota_bem', 'o barco está cadastrado na Tedesco Marina Garden Plaza')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1i a ordem: o dito vence a OS, a OS vence o barco, e o barco noutro lugar vira nota_bem', v_d is null, v_d);

  -- A marina da OS que não virou local: a ficha de hoje diz o nome dela; a cadeia não pode pôr outro lugar no texto_equipe.
  begin
    insert into public.marinas (name, city, state) values ('Porto Novo', 'Navegantes', 'SC') returning id into v_marina;
    update public.service_orders set marina_id = v_marina where id = pg_temp.os('OS-J9');
    v := public._agenda_local_resolvido(pg_temp.os('OS-J9'), c_hoje);
    v_ficha := public._agenda_local_da_os(pg_temp.os('OS-J9'));
    v_d := pg_temp.dif(v, jsonb_build_object('local_id', v_it, 'fonte', 'bem', 'suposicao', true, 'texto_equipe', null,
      'texto', 'Marina Itajaí (suposição: pelo cadastro do barco)', 'nota_bem', 'a OS diz Porto Novo, que não está no cadastro de locais'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1j a marina da OS sem local, com o barco noutra: suposição, sem texto_equipe; a ficha segue na marina da OS', v_d is null and v_ficha = 'na Porto Novo', coalesce(v_d, v_ficha));

  -- Local inativo não entra.
  begin
    update public.agenda_locais set ativo = false where id in (v_it, v_ted, v_mp);
    v_d := pg_temp.dif(public._agenda_local_resolvido(pg_temp.os('OS-J9'), c_hoje), jsonb_build_object('local_id', null, 'fonte', 'nenhum',
      'nota_bem', 'a OS diz Marina Itajaí, que não está no cadastro de locais'));
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_resolvido(pg_temp.os('OS-J14'), c_hoje), jsonb_build_object('local_id', null, 'fonte', 'nenhum')));
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_resolvido(pg_temp.os('OS-J3'), c_hoje), jsonb_build_object('local_id', null, 'fonte', 'nenhum')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1k local inativo não entra na cadeia: nem o dito, nem o da OS, nem o pátio', v_d is null, v_d);

  -- A cidade: grafias, a UF e o caractere quebrado.
  begin
    update public.clients set city = 'Balneario Camboriu', state = 'sc' where id = (select client_id from public.service_orders where id = pg_temp.os('OS-J13'));
    v_d := pg_temp.dif(public._agenda_local_resolvido(pg_temp.os('OS-J13'), c_hoje), jsonb_build_object('fonte', 'cidade', 'chave', 'c:balneario camboriu', 'uf', 'SC',
      'municipio', 'Balneario Camboriu'));
    update public.clients set city = '  ' || normalize('Balneário Camboriú', nfd) || ' ', state = 'Santa Catarina' where id = (select client_id from public.service_orders where id = pg_temp.os('OS-J13'));
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_resolvido(pg_temp.os('OS-J13'), c_hoje), jsonb_build_object('chave', 'c:balneario camboriu', 'uf', null)));
    update public.clients set city = 'Itaja' || chr(65533) where id = (select client_id from public.service_orders where id = pg_temp.os('OS-J13'));
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_resolvido(pg_temp.os('OS-J13'), c_hoje), jsonb_build_object('fonte', 'nenhum', 'chave', null)));
    update public.clients set city = '   ' where id = (select client_id from public.service_orders where id = pg_temp.os('OS-J13'));
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_resolvido(pg_temp.os('OS-J13'), c_hoje), jsonb_build_object('fonte', 'nenhum')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1l a cidade: as grafias dão a mesma chave (com o acento decomposto), UF só em sigla, o caractere quebrado e o vazio não servem', v_d is null, v_d);

  v_res := pg_temp.ok(v_res, 'L1m a OS que não existe: null, sem erro',
    public._agenda_local_resolvido('00000000-0000-4000-8000-0000000000ff', c_hoje) is null);

  -- R6.5: a preposição. "no" só com o nome começando por Pátio.
  select string_agg(format('%s → %s', t.nome, public._agenda_local_no(t.nome)), '; ') into v_lista
    from (values ('MP Motorhomes', 'na MP Motorhomes'), ('Marina Itajaí', 'na Marina Itajaí'), ('Kalmar Estaleiro', 'na Kalmar Estaleiro'),
                 ('Iate Clube Caiobá', 'na Iate Clube Caiobá'), ('Pátio da HBR', 'no Pátio da HBR'), ('Patio da HBR', 'no Patio da HBR'),
                 ('PÁTIO DO PORTO', 'no PÁTIO DO PORTO'), ('  Pátio da HBR ', 'no Pátio da HBR'), (normalize('Pátio da HBR', nfd), 'no ' || normalize('Pátio da HBR', nfd)),
                 ('Patiobá Marina', 'na Patiobá Marina'), ('Marina do Pátio', 'na Marina do Pátio')) t(nome, esp)
   where public._agenda_local_no(t.nome) is distinct from t.esp;
  v_res := pg_temp.ok(v_res, 'L1n R6.5, a preposição: "no" só com o nome começando pela palavra Pátio, com ou sem acento; o resto, "na"', v_lista is null, v_lista);

  begin
    update public.agenda_locais set nome = 'Pátio da HBR' where id = v_mp;
    v_d := pg_temp.dif(public._agenda_local_resolvido(pg_temp.os('OS-J3'), c_hoje), jsonb_build_object('texto', 'Pátio da HBR (suposição: motorhome vem ao pátio)', 'texto_curto', 'no Pátio da HBR'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L1o o nome vem do cadastro: renomeado, o exemplo da §5.3, "Pátio da HBR (suposição: motorhome vem ao pátio)"', v_d is null, v_d);

  -- A ficha de hoje, byte a byte: nas 17 OS da fixture, onde a cadeia dá texto_equipe ele é o que _agenda_local_da_os já diz (fora o local dito,
  -- que é novo de propósito); onde não dá, é nulo, e o P8 mantém o de hoje.
  select count(*),
         count(*) filter (where x.v ->> 'fonte' <> 'dono' and x.v ->> 'texto_equipe' = public._agenda_local_da_os(x.id)),
         count(*) filter (where x.v ->> 'texto_equipe' is null),
         string_agg(x.num || ': ' || coalesce(x.v ->> 'texto_equipe', '(nulo)') || ' / ' || coalesce(public._agenda_local_da_os(x.id), '(nulo)'), '; ' order by x.num)
           filter (where x.v ->> 'fonte' <> 'dono' and (x.v ->> 'texto_equipe') is distinct from public._agenda_local_da_os(x.id) and x.v ->> 'texto_equipe' is not null)
    into v_t, v_igual, v_nulo, v_lista
    from (select so.id, so.service_order_number as num, public._agenda_local_resolvido(so.id, c_hoje) as v
            from public.service_orders so where so.service_order_number ~ '^OS-[JD][0-9]+$') x;
  v_res := pg_temp.ok(v_res, 'L1p a ficha: nas 17 OS, 8 iguais à de hoje byte a byte, 8 nulas (o P8 mantém a de hoje) e 1 dita pelo dono; nenhuma diferente',
    v_t = 17 and v_igual = 8 and v_nulo = 8 and v_lista is null, format('%s OS, %s iguais, %s nulas; %s', v_t, v_igual, v_nulo, coalesce(v_lista, 'nenhuma diferente')));

  perform pg_temp.gravar(v_res);
end
$l1$;

-- ── L2. O deslocamento ─────────────────────────────────────────────────────────────────────────────
do $l2$
declare
  v_res jsonb := '[]'::jsonb;
  v_d text;
  v_id uuid;
  r record;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('L2 o deslocamento', true, 'PULADO: a fixture só existe na bancada');
    return;
  end if;

  v_d := pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Marina Itajaí')), jsonb_build_object('ida_min', 3, 'fonte', 'coordenadas', 'viagem', 'regional',
    'texto', 'A ida leva cerca de 3 min (pelas coordenadas).'));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Tedesco Marina Garden Plaza')), jsonb_build_object('ida_min', 15, 'fonte', 'coordenadas', 'viagem', 'regional')));
  v_res := pg_temp.ok(v_res, 'L2a coordenadas, regional: as 2 marinas reais da §2, ≈ 3 e ≈ 15 min', v_d is null, v_d);

  -- As coordenadas reais de Marina do Sol (Guaratuba: 151 min na §2) e uma em Florianópolis.
  begin
    insert into public.agenda_locais (nome, tipo, municipio, uf, latitude, longitude)
    values ('Marina do Sol', 'marina', 'Guaratuba', 'PR', -25.877819, -48.588825) returning id into v_id;
    v_d := pg_temp.dif(public._agenda_local_deslocamento(v_id), jsonb_build_object('ida_min', 151, 'fonte', 'coordenadas', 'viagem', 'pernoite'));
    insert into public.agenda_locais (nome, tipo, municipio, uf, latitude, longitude)
    values ('Ponto em Florianópolis', 'marina', 'Florianópolis', 'SC', -27.5954, -48.548) returning id into v_id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(v_id), jsonb_build_object('ida_min', 100, 'fonte', 'coordenadas', 'viagem', 'bate_volta')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2b coordenadas, pernoite (151 min, o número da §2) e ida e volta', v_d is null, v_d);

  -- O tempo dito, nas pontas dos limites (45 e 120); fora dele o cadastro e as coordenadas não contam.
  v_d := null;
  for r in select * from (values (0, 'regional'), (45, 'regional'), (46, 'bate_volta'), (120, 'bate_volta'), (121, 'pernoite')) as t(m, esp) loop
    begin
      update public.agenda_locais set deslocamento_min = r.m where id = pg_temp.loc('Tedesco Marina Garden Plaza');
      v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Tedesco Marina Garden Plaza')),
        jsonb_build_object('ida_min', r.m, 'fonte', 'dito', 'viagem', r.esp, 'texto', format('A ida leva %s min.', r.m))));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'L2c o tempo dito vale sobre as coordenadas, nos limites: 45 regional, 46 ida e volta, 120 ida e volta, 121 pernoite', v_d is null, v_d);

  v_d := pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('MP Motorhomes')), jsonb_build_object('ida_min', 0, 'fonte', 'dito', 'viagem', 'regional'));
  v_res := pg_temp.ok(v_res, 'L2d a MP, com deslocamento 0 (R6.5): regional', v_d is null, v_d);

  begin
    update public.agenda_locais set viagem = 'pernoite' where id = pg_temp.loc('Tedesco Marina Garden Plaza');
    v_d := pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Tedesco Marina Garden Plaza')), jsonb_build_object('ida_min', 15, 'fonte', 'dito', 'viagem', 'pernoite'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2e a viagem dita no cadastro vale sobre o tempo, e o tempo continua na saída', v_d is null, v_d);

  v_d := pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Iate Clube Caiobá')), jsonb_build_object('ida_min', null, 'fonte', 'municipio', 'viagem', 'pernoite',
    'texto', 'Sem o tempo de ida: conto pelo município.'));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Veleiros da Ilha')), jsonb_build_object('ida_min', null, 'fonte', 'municipio', 'viagem', 'bate_volta')));
  begin
    insert into public.agenda_locais (nome, tipo, municipio, uf) values ('Kalmar', 'estaleiro', 'Itajaí', 'SC') returning id into v_id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(v_id), jsonb_build_object('ida_min', null, 'fonte', 'municipio', 'viagem', 'regional')));
    update public.agenda_locais set municipio = 'Itaja' || chr(65533) where id = v_id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(v_id), jsonb_build_object('fonte', 'municipio', 'viagem', 'regional')));
    update public.agenda_locais set municipio = normalize('Balneário Camboriú', nfd) where id = v_id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(v_id), jsonb_build_object('fonte', 'municipio', 'viagem', 'regional')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2f sem coordenada, pelo município: outra UF pernoite, SC fora da região ida e volta, da região regional (tolerante ao caractere quebrado e ao acento decomposto)', v_d is null, v_d);

  begin
    insert into public.agenda_locais (nome, tipo, municipio) values ('Sem UF', 'marina', 'Lugar Nenhum') returning id into v_id;
    v_d := pg_temp.dif(public._agenda_local_deslocamento(v_id), jsonb_build_object('ida_min', null, 'fonte', 'nenhum', 'viagem', null, 'texto', 'Não sei o deslocamento até lá.'));
    update public.agenda_locais set uf = 'SC' where id = v_id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(v_id), jsonb_build_object('fonte', 'municipio', 'viagem', 'bate_volta')));
    update public.agenda_config set viagem_uf_bate_volta = '{SC,PR}' where id;
    update public.agenda_locais set uf = 'PR' where id = v_id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(v_id), jsonb_build_object('fonte', 'municipio', 'viagem', 'bate_volta')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2g a UF: sem ela, fonte nenhum e viagem nula (não sei não é regional); a lista de UF é parâmetro', v_d is null, v_d);

  begin
    delete from public.app_settings where key = 'travel_base_lat';
    v_d := pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Tedesco Marina Garden Plaza')), jsonb_build_object('ida_min', null, 'fonte', 'municipio', 'viagem', 'regional'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.app_settings set value = 'não é número' where key = 'travel_base_lng';
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Tedesco Marina Garden Plaza')), jsonb_build_object('fonte', 'municipio', 'viagem', 'regional')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2h sem a base, ou com a base fora de número: fonte municipio, sem erro', v_d is null, v_d);

  -- Os parâmetros mandam (nenhum literal): dobrar o fator e cair a velocidade pela metade quadruplica o tempo.
  begin
    update public.agenda_config set deslocamento_fator_estrada = 2.00, deslocamento_kmh = 30, deslocamento_regional_max_min = 10, deslocamento_bate_volta_max_min = 30 where id;
    v_d := pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Tedesco Marina Garden Plaza')), jsonb_build_object('ida_min', 45, 'viagem', 'pernoite'));
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Marina Itajaí')), jsonb_build_object('ida_min', 10, 'viagem', 'regional')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L2i fator, velocidade e limites são parâmetros', v_d is null, v_d);

  begin
    update public.agenda_locais set ativo = false where id = pg_temp.loc('Marina Itajaí');
    v_d := pg_temp.dif(public._agenda_local_deslocamento(pg_temp.loc('Marina Itajaí')), jsonb_build_object('fonte', 'nenhum', 'viagem', null));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento('00000000-0000-4000-8000-0000000000ff'), jsonb_build_object('fonte', 'nenhum', 'viagem', null)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_deslocamento(null), jsonb_build_object('fonte', 'nenhum', 'viagem', null)));
  v_res := pg_temp.ok(v_res, 'L2j local inativo, inexistente ou nulo: fonte nenhum', v_d is null, v_d);

  perform pg_temp.gravar(v_res);
end
$l2$;

-- ── L3. A viagem da OS ─────────────────────────────────────────────────────────────────────────────
do $l3$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  c_j2 uuid; c_j6 uuid; c_j7 uuid; c_j8 uuid; c_j13 uuid;
  v_d text;
  r record;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('L3 a viagem da OS', true, 'PULADO: a fixture só existe na bancada');
    return;
  end if;
  c_j2 := pg_temp.os('OS-J2'); c_j6 := pg_temp.os('OS-J6'); c_j7 := pg_temp.os('OS-J7'); c_j8 := pg_temp.os('OS-J8'); c_j13 := pg_temp.os('OS-J13');

  -- A ordem, descendo a cadeia na mesma OS (J6, Caiobá, PR): cada fonte some e a seguinte responde.
  begin
    update public.os_planejamento set viagem = 'bate_volta' where service_order_id = c_j6;
    update public.agenda_locais set viagem = 'regional', deslocamento_min = 130 where id = pg_temp.loc('Iate Clube Caiobá');
    update public.service_orders set travel_distance_km = 900 where id = c_j6;
    v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j6, c_hoje), jsonb_build_object('tipo', 'bate_volta', 'fonte', 'dono', 'suposicao', false));
    update public.os_planejamento set viagem = null where service_order_id = c_j6;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j6, c_hoje), jsonb_build_object('tipo', 'regional', 'fonte', 'local', 'suposicao', false, 'ida_min', 130)));
    update public.agenda_locais set viagem = null where id = pg_temp.loc('Iate Clube Caiobá');
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j6, c_hoje), jsonb_build_object('tipo', 'pernoite', 'fonte', 'local', 'suposicao', true, 'ida_min', 130)));
    update public.agenda_locais set deslocamento_min = null, latitude = -26.910923, longitude = -48.651596 where id = pg_temp.loc('Iate Clube Caiobá');
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j6, c_hoje), jsonb_build_object('tipo', 'regional', 'fonte', 'coordenadas', 'suposicao', true, 'ida_min', 3)));
    update public.agenda_locais set latitude = null, longitude = null where id = pg_temp.loc('Iate Clube Caiobá');
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j6, c_hoje), jsonb_build_object('tipo', 'pernoite', 'fonte', 'municipio', 'suposicao', true, 'ida_min', null)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3a a ordem: dono > local (dito) > tempo dito (fonte local, suposição: da 3ª fonte em diante) > coordenadas > município', v_d is null, v_d);

  -- O que a viagem custa e os textos.
  v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j6, c_hoje), jsonb_build_object('tipo', 'pernoite', 'fonte', 'municipio', 'suposicao', true, 'ida_min', null,
    'extra_por', 2, 'imax_os', 0, 'sem_abre_fecha', true, 'tecnicos_cobrados', 1,
    'texto', 'Viagem com pernoite (suposição: outro estado): a equipe vai e volta junta, em dias seguidos; a ida e a volta ocupam 1 meio-dia cada.'));
  v_res := pg_temp.ok(v_res, 'L3b pernoite: extra 2 × pernoite_ida_meios, imax_os 0, sem abre e fecha, o texto da §6.2 byte a byte', v_d is null, v_d);

  v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j7, c_hoje), jsonb_build_object('tipo', 'bate_volta', 'fonte', 'municipio', 'suposicao', true, 'extra_por', 1, 'imax_os', null,
    'sem_abre_fecha', true, 'texto', 'Viagem de ida e volta no mesmo dia (suposição: fora da região): cada dia rende meio dia de serviço.'));
  v_res := pg_temp.ok(v_res, 'L3c ida e volta: extra bate_volta_meios_dia, imax_os null (o global), sem abre e fecha', v_d is null, v_d);

  v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j2, c_hoje), jsonb_build_object('tipo', 'regional', 'fonte', 'coordenadas', 'suposicao', true, 'ida_min', 3, 'extra_por', 0,
    'imax_os', null, 'sem_abre_fecha', false, 'texto', 'Sem viagem (aqui na região).'));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(pg_temp.os('OS-J1'), c_hoje), jsonb_build_object('tipo', 'regional', 'fonte', 'local', 'suposicao', true, 'ida_min', 0)));
  v_res := pg_temp.ok(v_res, 'L3d regional: nada de extra; a MP pelo deslocamento 0', v_d is null, v_d);

  begin
    update public.os_planejamento set viagem = 'pernoite' where service_order_id = c_j2;
    v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j2, c_hoje), jsonb_build_object('tipo', 'pernoite', 'fonte', 'dono', 'suposicao', false,
      'texto', 'Viagem com pernoite: a equipe vai e volta junta, em dias seguidos; a ida e a volta ocupam 1 meio-dia cada.'));
    update public.os_planejamento set viagem = 'bate_volta' where service_order_id = c_j2;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j2, c_hoje), jsonb_build_object('tipo', 'bate_volta', 'fonte', 'dono', 'suposicao', false,
      'texto', 'Viagem de ida e volta no mesmo dia: cada dia rende meio dia de serviço.')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3e dita pelo dono: sem a marca de suposição no texto', v_d is null, v_d);

  -- O parâmetro muda o custo e o texto; o 0 existe nos 2.
  begin
    update public.agenda_config set pernoite_ida_meios = 2, bate_volta_meios_dia = 0 where id;
    v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j6, c_hoje), jsonb_build_object('extra_por', 4,
      'texto', 'Viagem com pernoite (suposição: outro estado): a equipe vai e volta junta, em dias seguidos; a ida e a volta ocupam 2 meios-dias cada.'));
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j7, c_hoje), jsonb_build_object('extra_por', 0,
      'texto', 'Viagem de ida e volta no mesmo dia (suposição: fora da região): a estrada não tira meio-dia de serviço.')));
    update public.agenda_config set pernoite_ida_meios = 0 where id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j6, c_hoje), jsonb_build_object('extra_por', 0,
      'texto', 'Viagem com pernoite (suposição: outro estado): a equipe vai e volta junta, em dias seguidos; a ida e a volta não ocupam meio-dia.')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3f pernoite_ida_meios e bate_volta_meios_dia são parâmetros, com os textos que os acompanham', v_d is null, v_d);

  -- O km cobrado: só sem local, com os limites; o total cobrado (812 = 4 × 203) nunca vira distância.
  v_d := null;
  for r in select * from (values (0::numeric, 'regional', 'padrao'), (119.99, 'regional', 'padrao'), (120, 'bate_volta', 'km'), (299.99, 'bate_volta', 'km'),
                                 (300, 'pernoite', 'km'), (812, 'pernoite', 'km')) as t(km, tipo, fonte) loop
    begin
      update public.service_orders set travel_distance_km = r.km where id = c_j13;
      v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j13, c_hoje), jsonb_build_object('tipo', r.tipo, 'fonte', r.fonte, 'suposicao', true, 'ida_min', null)));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'L3g sem local: km ≥ 300 pernoite, ≥ 120 ida e volta, senão regional (padrão), sempre suposição e nunca ida_min', v_d is null, v_d);

  begin
    update public.service_orders set travel_distance_km = 812 where id = c_j13;
    v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j13, c_hoje), jsonb_build_object('texto',
      'Viagem com pernoite (suposição: pelo km cobrado na OS, que pode somar várias idas): a equipe vai e volta junta, em dias seguidos; a ida e a volta ocupam 1 meio-dia cada.'));
    -- Com local, o km nem é lido: a Ponta do Poço real tem 812 cobrados e o motivo é o estado (J6, igual); Penha fica na região e 812 km não mudam isso.
    update public.service_orders set travel_distance_km = 812 where id = c_j8;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j8, c_hoje), jsonb_build_object('tipo', 'regional', 'fonte', 'municipio', 'ida_min', null)));
    update public.service_orders set travel_distance_km = 812 where id = c_j2;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j2, c_hoje), jsonb_build_object('tipo', 'regional', 'fonte', 'coordenadas', 'ida_min', 3)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3h 812 = 4 × 203: o texto diz que o km pode somar várias idas; com local, o km não é lido', v_d is null, v_d);

  begin
    update public.agenda_config set viagem_km_bate_volta = 50, viagem_km_pernoite = 100 where id;
    update public.service_orders set travel_distance_km = 100 where id = c_j13;
    v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j13, c_hoje), jsonb_build_object('tipo', 'pernoite', 'fonte', 'km'));
    update public.service_orders set travel_distance_km = 50 where id = c_j13;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j13, c_hoje), jsonb_build_object('tipo', 'bate_volta', 'fonte', 'km')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3i os limites do km são parâmetros', v_d is null, v_d);

  -- O município pela cidade do cliente (conflito 6c do AG7-18: Itapema só com a cidade vira ida e volta).
  begin
    update public.clients set city = 'Itapema', state = 'SC' where id = (select client_id from public.service_orders where id = c_j13);
    v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j13, c_hoje), jsonb_build_object('tipo', 'bate_volta', 'fonte', 'municipio', 'suposicao', true));
    update public.clients set city = 'Curitiba', state = 'PR' where id = (select client_id from public.service_orders where id = c_j13);
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j13, c_hoje), jsonb_build_object('tipo', 'pernoite', 'fonte', 'municipio')));
    update public.clients set city = 'Curitiba', state = null where id = (select client_id from public.service_orders where id = c_j13);
    update public.service_orders set travel_distance_km = 120 where id = c_j13;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_viagem_da_os(c_j13, c_hoje), jsonb_build_object('tipo', 'bate_volta', 'fonte', 'km')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3j a cidade do cliente passa pelo município: SC fora da região ida e volta, outra UF pernoite; sem UF, segue para o km', v_d is null, v_d);

  -- O técnico cobrado só explica (a dupla é do 7b).
  begin
    update public.service_orders set technician_count_for_travel = 2 where id = c_j2;
    v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j2, c_hoje), jsonb_build_object('tipo', 'regional', 'extra_por', 0, 'tecnicos_cobrados', 2,
      'texto', 'Sem viagem (aqui na região). O orçamento cobra deslocamento de 2 técnicos.'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L3k technician_count_for_travel só na explicação: não muda tipo nem custo', v_d is null, v_d);

  -- p_local: quem já tem não recalcula.
  v_d := pg_temp.dif(public._agenda_viagem_da_os(c_j2, c_hoje, jsonb_build_object('fonte', 'cidade', 'municipio', 'Curitiba', 'uf', 'PR')),
                     jsonb_build_object('tipo', 'pernoite', 'fonte', 'municipio'));
  v_res := pg_temp.ok(v_res, 'L3l p_local vale no lugar da cadeia: quem já tem não recalcula', v_d is null, v_d);

  v_res := pg_temp.ok(v_res, 'L3m a OS que não existe: null, sem erro', public._agenda_viagem_da_os('00000000-0000-4000-8000-0000000000ff', c_hoje) is null);

  perform pg_temp.gravar(v_res);
end
$l3$;

-- ── L4. O estado do bem ────────────────────────────────────────────────────────────────────────────
do $l4$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  c_barco uuid; c_rv uuid; c_cli uuid;
  v jsonb; v_d text; v_err text := '';
  r record;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('L4 o estado do bem', true, 'PULADO: a fixture só existe na bancada');
    return;
  end if;
  c_barco := pg_temp.os('OS-J9');   -- Lancha na Marina Itajaí, sem nada dito
  c_rv := pg_temp.os('OS-J11');     -- Motorhome sem local
  select client_id into c_cli from public.service_orders where id = c_barco;

  -- As palavras nas linhas reais (f6-03_linhas_das_os e wf7dd_p3_fatos, 05/11), byte a byte como estão em produção. A 1ª é a única linha de barco que
  -- casa: "teste em navegação". A da hélice é de um motorhome e é o motivo de as palavras só valerem para barco.
  for r in select * from (values
    (1, 'barco', 'Instalação do transdutor passante, com passagem de cabo, configuração da sonda e teste em navegação', 'agua', 'palavra'),
    (2, 'rv', 'Substituição da hélice do exaustor da claraboia', 'tanto_faz', 'padrao'),
    (3, 'barco', 'Pré-comissionamento, testes de partida, carga, vazamentos, ruído, vibração e checklist final', 'tanto_faz', 'padrao'),
    (4, 'barco', 'Instalação hidráulica/mecânica de água salgada, mangueiras, registros, conexões e bomba, se aplicável', 'tanto_faz', 'padrao'),
    (5, 'barco', 'Sistema elétrico AC: disjuntor, transferência, intertravamento, conexão ao quadro e testes', 'tanto_faz', 'padrao'),
    (6, 'barco', 'Teste Funcional OK', 'tanto_faz', 'padrao'),
    (7, 'barco', 'DIAGNÓSTICO REPARAÇÃO TÉCNICA DE MÓDULOS ELETRÔNICOS SEAKEEPER', 'tanto_faz', 'padrao'),
    (8, 'barco', 'INSTALAÇÃO TÉCNICA DE PARELHA DE MOTORES MERCURY V8 300HP CMS', 'tanto_faz', 'padrao'),
    (9, 'barco', 'Posicionamento, alinhamento, base, coxins e fixação do gerador', 'tanto_faz', 'padrao'),
    (10, 'barco', 'Comissionamento e validação de garantia e instalação (autorizada)', 'tanto_faz', 'padrao'),
    (11, 'barco', 'Ajuste de ligação elétrica de carregador de baterias', 'tanto_faz', 'padrao'),
    (12, 'rv', 'Instalação e conversão do sistema de baterias de chumbo para lítio', 'tanto_faz', 'padrao'),
    (13, 'rv', 'Reparo de vazamento no teto (2 furos passa-cabos)', 'tanto_faz', 'padrao'),
    -- As 2 listas, palavra por palavra: não há linha de barco real com as palavras do seco, e estas são só as da lista, numa frase.
    (14, 'barco', 'Teste de mar', 'agua', 'palavra'),
    (15, 'barco', 'Prova de mar do piloto', 'agua', 'palavra'),
    (16, 'barco', 'Teste no mar', 'agua', 'palavra'),
    (17, 'barco', 'Instrumentos navegando', 'agua', 'palavra'),
    (18, 'barco', 'Conferência com motor ligado', 'agua', 'palavra'),
    (19, 'barco', 'Sea trial', 'agua', 'palavra'),
    (20, 'barco', 'Pintura do casco', 'seco', 'palavra'),
    (21, 'barco', 'Troca de anodo', 'seco', 'palavra'),
    (22, 'barco', 'Troca do transdutor de casco', 'seco', 'palavra'),
    (23, 'barco', 'Revisão do passa casco', 'seco', 'palavra'),
    (24, 'barco', 'Limpeza do fundo do barco', 'seco', 'palavra'),
    (25, 'barco', 'Troca da HÉLICE', 'seco', 'palavra'),
    (26, 'barco', 'Alinhamento do eixo', 'seco', 'palavra'),
    (27, 'barco', 'Revisão do pé de galinha', 'seco', 'palavra'),
    -- As armadilhas do \m…\M: palavra dentro de outra não casa.
    (28, 'barco', 'Revisão do feixe de cabos', 'tanto_faz', 'padrao'),
    (29, 'barco', 'Teste de maré', 'tanto_faz', 'padrao'),
    (30, 'barco', 'Troca de cascos', 'tanto_faz', 'padrao'),
    (31, 'barco', 'Troca de hélices', 'tanto_faz', 'padrao'),
    (32, 'barco', 'Deixo o barco revisado', 'tanto_faz', 'padrao'),
    (33, 'barco', 'Reteste de mar', 'tanto_faz', 'padrao')
  ) as t(n, classe, linha, exige, fonte) loop
    begin
      perform pg_temp.linhas(case r.classe when 'rv' then c_rv else c_barco end, jsonb_build_array(jsonb_build_array(r.linha, 500)));
      v := public._agenda_estado_do_bem(case r.classe when 'rv' then c_rv else c_barco end, c_hoje);
      if v ->> 'exige' is distinct from r.exige or v ->> 'exige_fonte' is distinct from r.fonte or v ->> 'classe' is distinct from r.classe then
        v_err := v_err || format('[%s %s: %s/%s/%s] ', r.n, r.linha, v ->> 'classe', v ->> 'exige', v ->> 'exige_fonte');
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'L4a as palavras: 13 linhas reais de produção, as 2 listas palavra por palavra e as armadilhas do \m…\M; a hélice do exaustor, num motorhome, não pede o bem em seco', v_err = '', nullif(v_err, ''));

  -- Quais linhas contam: as 2 primeiras e a de maior valor. A água pesa mais que o seco.
  v_d := null;
  for r in select * from (values
    (1, '[["Teste de mar", 100], ["Revisão", 100], ["Limpeza", 100]]'::jsonb, 'agua'),
    (2, '[["Revisão", 100], ["Teste de mar", 100], ["Limpeza", 100]]'::jsonb, 'agua'),
    (3, '[["Revisão", 100], ["Limpeza", 100], ["Teste de mar", 900]]'::jsonb, 'agua'),
    (4, '[["Revisão", 100], ["Limpeza", 100], ["Teste de mar", 50]]'::jsonb, 'tanto_faz'),
    (5, '[["Revisão", 100], ["Limpeza", 100], ["Outra", 900], ["Teste de mar", 50]]'::jsonb, 'tanto_faz'),
    (6, '[["Pintura do casco", 100], ["Teste de mar", 100]]'::jsonb, 'agua'),
    (7, '[]'::jsonb, 'tanto_faz')
  ) as t(n, linhas, exige) loop
    begin
      perform pg_temp.linhas(c_barco, r.linhas);
      v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('exige', r.exige)));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'L4b as 2 primeiras linhas e a de maior valor contam; a 3ª pequena e a 4ª não; a água vence o seco (é ela que pede a descida); sem linha, tanto faz', v_d is null, v_d);

  -- As palavras são parâmetro.
  begin
    update public.agenda_config set bem_seco_palavras = 'teste funcional' where id;
    perform pg_temp.linhas(c_barco, '[["Teste Funcional OK", 100]]'::jsonb);
    v_d := pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('exige', 'seco', 'exige_fonte', 'palavra'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L4c as palavras vêm de agenda_config', v_d is null, v_d);

  -- J2, o exemplo do foco (§6.2), byte a byte.
  v := public._agenda_estado_do_bem(pg_temp.os('OS-J2'), c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('classe', 'barco', 'situacao', 'garagem_seca', 'situacao_fonte', 'dono', 'exige', 'agua', 'exige_fonte', 'palavra',
    'descer_quem', 'a marina', 'temporada', false, 'entrada_em', null, 'retirada_em', null, 'entrada_fonte', null,
    'suposicoes', jsonb_build_array('supus o teste final na água (pela linha de serviço)'),
    'texto', 'O barco: em seco (garagem), quem desce: a marina; o teste final é na água.'));
  v_res := pg_temp.ok(v_res, 'L4d J2: o texto da §6.2 byte a byte, com todas as chaves do contrato', v_d is null, v_d);

  -- As fontes da situação e do exige.
  v_d := pg_temp.dif(public._agenda_estado_do_bem(pg_temp.os('OS-J1'), c_hoje), jsonb_build_object('classe', 'rv', 'situacao', 'patio', 'situacao_fonte', 'local', 'suposicoes', '[]'::jsonb, 'texto', null));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(pg_temp.os('OS-J3'), c_hoje), jsonb_build_object('situacao', 'patio', 'situacao_fonte', 'local',
    'suposicoes', jsonb_build_array('supus o motorhome na MP Motorhomes'), 'texto', null)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('situacao', null, 'situacao_fonte', null, 'exige', 'tanto_faz', 'exige_fonte', 'padrao', 'texto', null)));
  begin
    update public.agenda_locais set tipo = 'patio_parceiro' where id = pg_temp.loc('Marina Itajaí');
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('situacao', 'patio', 'situacao_fonte', 'local')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L4e a situação: pelo tipo do local (o pátio da HBR ou o de parceiro, pela OS ou suposto), senão não sei', v_d is null, v_d);

  begin
    update public.os_planejamento set bem_situacao = 'agua', bem_situacao_fonte = 'cliente', bem_situacao_em = now(), bem_exige = 'tanto_faz', descer_quem = ' o marinheiro ' where service_order_id = c_barco;
    perform pg_temp.linhas(c_barco, '[["Teste de mar", 100]]'::jsonb);
    v_d := pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('situacao', 'agua', 'situacao_fonte', 'cliente', 'exige', 'tanto_faz', 'exige_fonte', 'dono',
      'descer_quem', 'o marinheiro', 'suposicoes', '[]'::jsonb, 'texto', 'O barco: na água, quem desce: o marinheiro.'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L4f o dito vence a palavra e o local, sem suposição', v_d is null, v_d);

  -- O texto nas outras combinações.
  v_d := null;
  for r in select * from (values
    (1, 'seco', 'dono', 'seco', null, 'O barco: em seco; o serviço é com o barco em seco.'),
    (2, 'garagem_seca', 'dono', 'tanto_faz', null, 'O barco: em seco (garagem).'),
    (3, 'com_cliente', 'cliente', 'agua', 'o cliente', 'O barco: com o cliente, quem desce: o cliente; o teste final é na água.'),
    (4, 'patio', 'dono', 'tanto_faz', null, 'O barco: no pátio.'),
    (5, null, null, 'agua', null, 'O teste final é na água.'),
    (6, null, null, 'seco', 'a marina', 'Quem desce: a marina; o serviço é com o barco em seco.'),
    (7, null, null, 'tanto_faz', 'a marina', 'Quem desce: a marina.')
  ) as t(n, sit, sit_f, exige, quem, texto) loop
    begin
      update public.os_planejamento set bem_situacao = r.sit, bem_situacao_fonte = r.sit_f, bem_situacao_em = case when r.sit is not null then now() end,
                                        bem_exige = r.exige, descer_quem = r.quem where service_order_id = c_barco;
      v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('texto', r.texto)));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'L4g o texto só diz o que foi dito ou o que o serviço pede, em cada combinação', v_d is null, v_d);

  -- A entrada e a retirada (o texto da releitura da §6.2).
  begin
    update public.os_planejamento set entrada_em = date '2027-11-05', retirada_em = date '2027-11-13', entrada_fonte = 'dono' where service_order_id = c_rv;
    v_d := pg_temp.dif(public._agenda_estado_do_bem(c_rv, c_hoje), jsonb_build_object('entrada_em', '2027-11-05', 'retirada_em', '2027-11-13', 'entrada_fonte', 'dono',
      'texto', format('O motorhome chega %s e sai %s.', public._dia_curto(date '2027-11-05'), public._dia_curto(date '2027-11-13'))));
    update public.os_planejamento set retirada_em = null where service_order_id = c_rv;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_rv, c_hoje), jsonb_build_object('texto', format('O motorhome chega %s.', public._dia_curto(date '2027-11-05')))));
    update public.os_planejamento set entrada_em = null, retirada_em = date '2027-11-13' where service_order_id = c_rv;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_rv, c_hoje), jsonb_build_object('texto', format('O motorhome sai %s.', public._dia_curto(date '2027-11-13')))));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L4h a entrada e a retirada, com o dia pelo _dia_curto', v_d is null, v_d);

  -- A temporada: temporada_meses, a fonte única (AG7-20).
  v_err := '';
  for r in select * from (values (date '2026-11-01', true), (date '2026-12-31', true), (date '2027-01-15', true), (date '2027-03-31', true),
                                 (date '2027-04-01', false), (date '2027-07-16', false), (date '2027-10-31', false)) as t(d, esp) loop
    v := public._agenda_estado_do_bem(c_barco, r.d);
    if (v ->> 'temporada')::boolean is distinct from r.esp then v_err := v_err || r.d::text || ' '; end if;
  end loop;
  begin
    update public.agenda_config set temporada_meses = '{7}' where id;
    if (public._agenda_estado_do_bem(c_barco, c_hoje) ->> 'temporada')::boolean is distinct from true then v_err := v_err || 'parâmetro '; end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L4i a temporada: novembro a março, pelas pontas, e o parâmetro manda', v_err = '', nullif(v_err, ''));

  -- A suposição do barco na temporada: "perguntei" só com o M11 que saiu. Nada de plano falso ao dono.
  v := public._agenda_estado_do_bem(c_barco, date '2026-12-01');
  v_d := pg_temp.dif(v, jsonb_build_object('suposicoes', jsonb_build_array('supus o barco livre nos dias úteis (temporada: ainda não sei os dias de uso)')));
  begin
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate, aprovacao, estado, dedupe_key)
    values (c_cli, c_barco, 'onde_fica', 'rodada', 'sombra', 'em teste', now(), now(), 'livre', 'registrada', 'teste:p3:1');
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, date '2026-12-01'),
      jsonb_build_object('suposicoes', jsonb_build_array('supus o barco livre nos dias úteis (temporada: ainda não sei os dias de uso)'))));
    -- (7d P6, R6.9-5) "perguntei" só com o M11 que levava o {uso}: sem ele, a mensagem saiu e não perguntou
    update public.agenda_cliente_mensagens set estado = 'enviada', enviada_em = now() where dedupe_key = 'teste:p3:1';
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, date '2026-12-01'),
      jsonb_build_object('suposicoes', jsonb_build_array('supus o barco livre nos dias úteis (temporada: ainda não sei os dias de uso)'))));
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em)
    values (c_cli, c_barco, 'onde_fica', 'rodada', 'ligado', 'com o uso', '{"dados": {"uso": true}}', now(), now(), 'livre', 'enviada', 'teste:p3:2', now());
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, date '2026-12-01'),
      jsonb_build_object('suposicoes', jsonb_build_array('supus o barco livre nos dias úteis (temporada: perguntei ao cliente os dias de uso)'))));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.os_planejamento set bem_indisponivel = datemultirange(daterange(date '2026-12-05', date '2026-12-07')) where service_order_id = c_barco;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, date '2026-12-01'), jsonb_build_object('suposicoes', '[]'::jsonb)));
    update public.os_planejamento set bem_indisponivel = '{}', bem_situacao = 'com_cliente', bem_situacao_fonte = 'cliente', bem_situacao_em = now() where service_order_id = c_barco;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, date '2026-12-01'), jsonb_build_object('suposicoes', '[]'::jsonb)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('suposicoes', '[]'::jsonb)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_rv, date '2026-12-01'), jsonb_build_object('suposicoes', jsonb_build_array('supus o motorhome na MP Motorhomes'))));
  v_res := pg_temp.ok(v_res, 'L4j o barco suposto livre só na temporada e sem os dias ditos; "perguntei" só com o M11 enviado (o em teste não conta); motorhome não', v_d is null, v_d);

  -- Bem de outra classe e OS sem plano.
  begin
    update public.vessels set asset_type = 'Equipamento' where id = (select vessel_id from public.service_orders where id = c_barco);
    perform pg_temp.linhas(c_barco, '[["Troca do eixo", 100]]'::jsonb);
    v_d := pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('classe', 'outro', 'exige', 'tanto_faz', 'exige_fonte', 'padrao'));
    update public.os_planejamento set bem_situacao = 'seco', bem_situacao_fonte = 'dono', bem_situacao_em = now(), bem_exige = 'seco' where service_order_id = c_barco;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('texto', 'O bem: em seco; o serviço é com o bem em seco.')));
    update public.os_planejamento set bem_situacao = null, bem_situacao_fonte = null, bem_situacao_em = null, bem_exige = null where service_order_id = c_barco;
    delete from public.os_planejamento where service_order_id = c_barco;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_estado_do_bem(c_barco, c_hoje), jsonb_build_object('situacao', null, 'exige', 'tanto_faz', 'descer_quem', null)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L4k bem de outra classe não lê as palavras; OS sem linha de planejamento não quebra', v_d is null, v_d);

  v_res := pg_temp.ok(v_res, 'L4l a OS que não existe: null, sem erro', public._agenda_estado_do_bem('00000000-0000-4000-8000-0000000000ff', c_hoje) is null);

  perform pg_temp.gravar(v_res);
end
$l4$;

-- ── L5. A máscara ──────────────────────────────────────────────────────────────────────────────────
do $l5$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  c_j1 uuid; c_j2 uuid; c_j3 uuid; c_j8 uuid; c_d3 uuid; c_j13 uuid;
  c_seg constant date := date '2027-07-19';
  c_sex constant date := date '2027-07-23';
  c_sab constant date := date '2027-07-24';
  v jsonb; v_d text; v_it uuid; v_ted uuid; v_mp uuid;
  r record;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('L5 a máscara', true, 'PULADO: a fixture só existe na bancada');
    return;
  end if;
  c_j1 := pg_temp.os('OS-J1'); c_j2 := pg_temp.os('OS-J2'); c_j3 := pg_temp.os('OS-J3'); c_j8 := pg_temp.os('OS-J8'); c_d3 := pg_temp.os('OS-D3'); c_j13 := pg_temp.os('OS-J13');
  v_it := pg_temp.loc('Marina Itajaí'); v_ted := pg_temp.loc('Tedesco Marina Garden Plaza'); v_mp := pg_temp.loc('MP Motorhomes');

  -- O exemplo da §5.3: ter 20/07/2027 em BC, 2º dia da janela.
  v := public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('dias', jsonb_build_array(2), 'meios', '[]'::jsonb, 'notas', '[]'::jsonb, 'ent', 0, 'sai', 0,
    'motivos', jsonb_build_object('2', 'ter 20/07 é feriado em Balneário Camboriú (aniversário da cidade)')));
  v_res := pg_temp.ok(v_res, 'L5a 20/07 em BC: o índice do dia e o motivo byte a byte; sem entrada nem retirada, ent e sai 0 (greatest ignora nulo)', v_d is null, v_d);

  v_d := pg_temp.dif(public._agenda_local_mascara(c_j3, c_seg, c_sex, c_hoje), jsonb_build_object('dias', jsonb_build_array(2)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_d3, c_seg, c_sex, c_hoje), jsonb_build_object('dias', jsonb_build_array(2))));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sex, c_hoje), jsonb_build_object('dias', '[]'::jsonb, 'motivos', '{}'::jsonb)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j8, c_seg, c_sex, c_hoje), jsonb_build_object('dias', '[]'::jsonb)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j13, c_seg, c_sex, c_hoje), jsonb_build_object('dias', '[]'::jsonb)));
  v_res := pg_temp.ok(v_res, 'L5b o feriado segue o município do local: o suposto no pátio de BC e a cidade do cliente em BC caem; Itajaí, Penha e o sem lugar, não', v_d is null, v_d);

  v_d := pg_temp.dif(public._agenda_local_mascara(c_j1, date '2027-06-14', date '2027-06-16', c_hoje), jsonb_build_object('dias', '[]'::jsonb));
  v_res := pg_temp.ok(v_res, 'L5c 15/06 não entra na máscara: é do calendário da HBR, que o motor já respeita (o P2: agenda_feriado_municipal)', v_d is null, v_d);

  -- Só o local conferido pode dizer que abre no feriado.
  begin
    update public.agenda_locais set feriado = 'abre' where id = v_mp;
    v_d := pg_temp.dif(public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje), jsonb_build_object('dias', jsonb_build_array(2)));
    update public.agenda_locais set conferido_por = 'dono', conferido_em = date '2027-07-01' where id = v_mp;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje), jsonb_build_object('dias', '[]'::jsonb, 'motivos', '{}'::jsonb)));
    update public.agenda_locais set feriado = 'fecha' where id = v_mp;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje), jsonb_build_object('dias', jsonb_build_array(2))));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L5d feriado = abre só vale conferido; sem conferir, o feriado fecha', v_d is null, v_d);

  -- O sábado (24/07 é o 6º dia a partir de seg 19/07): manhã = 11, tarde = 12. Marina Itajaí, conferida, sábado de manhã.
  v_d := pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', '[]'::jsonb, 'meios', '[]'::jsonb));
  begin
    update public.agenda_config set sabado_util = true where id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', '[]'::jsonb, 'meios', jsonb_build_array(12))));
    update public.agenda_locais set sabado = 'nao' where id = v_it;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', jsonb_build_array(6), 'meios', '[]'::jsonb,
      'motivos', jsonb_build_object('6', 'sáb 24/07: Marina Itajaí não abre no sábado'))));
    update public.agenda_locais set sabado = 'dia' where id = v_it;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', '[]'::jsonb, 'meios', '[]'::jsonb)));
    update public.agenda_locais set sabado = null where id = v_it;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', '[]'::jsonb, 'meios', '[]'::jsonb)));
    -- Sem conferir, sábado 'nao' não fecha nada: vira nota.
    update public.agenda_locais set sabado = 'nao', conferido_por = 'pesquisa' where id = v_it;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', '[]'::jsonb, 'meios', '[]'::jsonb)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L5e o sábado só com o local conferido e com a HBR trabalhando: com a HBR fechada, nada; manha fecha a tarde; nao fecha o dia; dia e nulo, nada', v_d is null, v_d);

  -- O sábado do 7b também conta como a HBR trabalhando; o feriado da HBR não.
  begin
    update public.agenda_locais set sabado = 'nao' where id = v_it;
    update public.agenda_config set modo_sabado = 'sombra', sabado_manha = 'so_prazo' where id;
    v_d := pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', jsonb_build_array(6)));
    update public.agenda_config set modo_sabado = 'desligado' where id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', '[]'::jsonb)));
    perform set_config('agenda.sabado', 'on', true);
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', jsonb_build_array(6))));
    perform set_config('agenda.sabado', '', true);
    update public.agenda_config set modo_sabado = 'ligado', sabado_manha = 'nunca' where id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sab, c_hoje), jsonb_build_object('dias', '[]'::jsonb)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda.sabado', '', true);
  v_res := pg_temp.ok(v_res, 'L5f o sábado do 7b (modo_sabado fora de desligado) e o gancho do 7a (agenda.sabado) contam como a HBR trabalhando; sabado_manha = nunca, não', v_d is null, v_d);

  -- O horário, com a tolerância de 30 min: manhã 08–12, tarde 13–17. 19/07 = dia 1: manhã 1, tarde 2. Janela de um dia.
  v_d := null;
  for r in select * from (values
    (1, time '08:00', time '18:00', '[]'),
    (2, time '08:30', time '16:30', '[]'),
    (3, time '08:31', time '16:30', '[1]'),
    (4, time '08:30', time '16:29', '[2]'),
    (5, time '14:00', time '18:00', '[1, 2]'),
    (6, time '08:00', time '11:30', '[2]'),
    (7, time '08:00', time '11:29', '[1, 2]')
  ) as t(n, abre, fecha, meios) loop
    begin
      update public.agenda_locais set abre = r.abre, fecha = r.fecha where id = v_it;
      v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_seg, c_hoje), jsonb_build_object('meios', r.meios::jsonb, 'dias', '[]'::jsonb)));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'L5g o horário conferido fecha o meio-dia que não cobre, com a tolerância: 08:30 cobre, 08:31 não; 16:30 cobre, 16:29 não', v_d is null, v_d);

  begin
    update public.agenda_locais set abre = time '09:30', fecha = time '15:00' where id = v_it;
    v_d := pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, date '2027-07-20', c_hoje), jsonb_build_object('meios', jsonb_build_array(1, 2, 3, 4)));
    -- Domingo e sábado da HBR fechada não entram: o horário é de segunda a sexta.
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_sab, date '2027-07-25', c_hoje), jsonb_build_object('meios', '[]'::jsonb)));
    update public.agenda_config set horario_tolerancia_min = 120 where id;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_seg, c_hoje), jsonb_build_object('meios', '[]'::jsonb)));
    -- Sem conferir, o horário não fecha nada: vira nota.
    update public.agenda_config set horario_tolerancia_min = 0 where id;
    update public.agenda_locais set conferido_por = 'pesquisa' where id = v_it;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_seg, c_hoje), jsonb_build_object('meios', '[]'::jsonb)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L5h o índice dos meios (2·(d−1)+1 manhã, +1 tarde); só de segunda a sexta; a tolerância é parâmetro; sem conferir, nada fecha', v_d is null, v_d);

  -- A conferência venceu (local_conferencia_validade_dias): volta a ser nota.
  begin
    update public.agenda_locais set abre = time '10:00', fecha = time '11:00', conferido_em = date '2026-07-16' where id = v_it;
    v_d := pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_seg, c_hoje), jsonb_build_object('meios', jsonb_build_array(1, 2)));
    update public.agenda_locais set conferido_em = date '2026-07-15' where id = v_it;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_seg, c_hoje), jsonb_build_object('meios', '[]'::jsonb)));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L5i a conferência vale 1 ano: no limite conta, um dia depois vira nota', v_d is null, v_d);

  -- A entrada e a retirada: dentro da janela, antes (preso em 1) e depois (passa da janela de propósito). A retirada não entra em dias.
  v_d := null;
  for r in select * from (values
    (1, date '2027-07-21', date '2027-07-23', 3, 5),
    (2, date '2027-07-10', date '2027-07-12', 1, 1),
    (3, date '2027-07-19', date '2027-07-22', 1, 4),
    (4, date '2027-08-02', date '2027-08-20', 15, 33),
    (5, null, date '2027-07-21', 0, 3),
    (6, date '2027-07-21', null, 3, 0)
  ) as t(n, ent, sai, e_ent, e_sai) loop
    begin
      update public.os_planejamento set entrada_em = r.ent, retirada_em = r.sai, entrada_fonte = 'dono' where service_order_id = c_j1;
      v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje), jsonb_build_object('ent', r.e_ent, 'sai', r.e_sai, 'dias', jsonb_build_array(2))));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'L5j ent e sai: o índice, preso em 1 antes da janela (0 é "não há"), passando dela depois; a retirada fica fora de dias (o P4 só a aplica com modo_patio)', v_d is null, v_d);

  -- As notas: as regras não conferidas, no máximo 3, na ordem.
  begin
    update public.agenda_locais set conferido_por = 'pesquisa', conferido_em = date '2026-10-29', seguro_exigido = true, seguro_texto = 'seguro de responsabilidade civil',
                                    taxa_texto = 'taxa de prestador', tomada_max_w = 1200 where id = v_it;
    v := public._agenda_local_mascara(c_j2, c_seg, c_sex, c_hoje);
    v_d := pg_temp.dif(v, jsonb_build_object('notas', jsonb_build_array(
      'Marina Itajaí: pede autorização escrita do dono do barco com nome e documento de quem vai e as datas (a confirmar com você).',
      'Marina Itajaí: abre das 08:00 às 18:00 (a confirmar com você).',
      'Marina Itajaí: no sábado, só de manhã (a confirmar com você).')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(pg_temp.os('OS-D1'), c_seg, c_sex, c_hoje), jsonb_build_object('notas',
    jsonb_build_array('Tedesco Marina Garden Plaza: tem garagem seca (a confirmar com você).'))));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sex, c_hoje), jsonb_build_object('notas', '[]'::jsonb)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j8, c_seg, c_sex, c_hoje), jsonb_build_object('notas', '[]'::jsonb)));
  begin
    update public.agenda_locais set tipo = 'estaleiro' where id = v_ted;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(pg_temp.os('OS-D1'), c_seg, c_sex, c_hoje), jsonb_build_object('notas', jsonb_build_array(
      'Tedesco Marina Garden Plaza: tem garagem seca (a confirmar com você).', 'No estaleiro, combine com eles quando o barco fica livre para a elétrica.'))));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L5k as notas: as regras não conferidas, no máximo 3; conferido e sem local, nenhuma; a do estaleiro (§6.2)', v_d is null, v_d);

  -- Não lê os modos da 7d: o mesmo resultado desligado, em sombra, ligado e com o freio.
  v := public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje);
  begin
    update public.agenda_config set modo_local_calendario = 'sombra', modo_patio = 'sombra' where id;
    v_d := case when public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje) = v then null else 'sombra' end;
    update public.agenda_config set modo_local_calendario = 'ligado', modo_patio = 'ligado', gestor_so_propor = false where id;
    v_d := coalesce(v_d, case when public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje) = v then null else 'ligado' end);
    update public.agenda_config set gestor_so_propor = true where id;
    v_d := coalesce(v_d, case when public._agenda_local_mascara(c_j1, c_seg, c_sex, c_hoje) = v then null else 'freio' end);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L5l a máscara não muda com os modos: quem chama decide (§5.3)', v_d is null, v_d);

  -- p_local: quem já tem não recalcula; janela vazia; a OS que não existe.
  v_d := pg_temp.dif(public._agenda_local_mascara(c_j2, c_seg, c_sex, c_hoje, jsonb_build_object('municipio', 'Balneário Camboriú')), jsonb_build_object('dias', jsonb_build_array(2)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_local_mascara(c_j1, c_sex, c_seg, c_hoje), jsonb_build_object('dias', '[]'::jsonb, 'meios', '[]'::jsonb, 'motivos', '{}'::jsonb)));
  v_res := pg_temp.ok(v_res, 'L5m p_local vale no lugar da cadeia; janela invertida não dá erro nem dia', v_d is null, v_d);
  v_res := pg_temp.ok(v_res, 'L5n a OS que não existe: null, sem erro', public._agenda_local_mascara('00000000-0000-4000-8000-0000000000ff', c_seg, c_sex, c_hoje) is null);

  perform pg_temp.gravar(v_res);
end
$l5$;

-- ── L6. A autorização, só leitura ──────────────────────────────────────────────────────────────────
do $l6$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  c_j2 uuid; v_rob uuid; v_joao uuid; v_it uuid;
  v jsonb; v_d text;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('L6 a autorização', true, 'PULADO: a fixture só existe na bancada');
    return;
  end if;
  c_j2 := pg_temp.os('OS-J2');
  v_it := pg_temp.loc('Marina Itajaí');
  select id into v_rob from public.payees where name = 'Roberto' and active;
  select id into v_joao from public.payees where name = 'João' and active;

  v := public._agenda_autorizacao_da_os(c_j2, c_hoje);
  v_d := pg_temp.dif(v, jsonb_build_object('exige', true, 'conferido', true, 'autorizados', jsonb_build_array(v_rob), 'nomes', jsonb_build_array('Roberto'), 'nota', null,
    'texto', 'Autorizados nesse serviço: Roberto.'));
  v_res := pg_temp.ok(v_res, 'L6a J2: só o Roberto autorizado, com todas as chaves do contrato', v_d is null, v_d);

  v_res := pg_temp.ok(v_res, 'L6b só leitura: sem filtro, sem livre_a_partir, nenhuma chave além das 6 do contrato (AG7-14: o acesso não é filtro de pessoa)',
    not (v ? 'filtro') and not (v ? 'livre_a_partir') and (select count(*) from jsonb_object_keys(v)) = 6, v::text);

  begin
    insert into public.os_autorizados (service_order_id, payee_id, local_id, fonte) values (c_j2, v_joao, v_it, 'dono');
    v_d := pg_temp.dif(public._agenda_autorizacao_da_os(c_j2, c_hoje), jsonb_build_object('nomes', jsonb_build_array('João', 'Roberto'), 'texto', 'Autorizados nesse serviço: João e Roberto.'));
    update public.os_autorizados set revogado_em = now() where service_order_id = c_j2 and payee_id = v_joao;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(c_j2, c_hoje), jsonb_build_object('nomes', jsonb_build_array('Roberto'))));
    update public.os_autorizados set revogado_em = null, valido_ate = date '2027-07-15' where service_order_id = c_j2 and payee_id = v_joao;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(c_j2, c_hoje), jsonb_build_object('nomes', jsonb_build_array('Roberto'))));
    update public.os_autorizados set valido_ate = c_hoje where service_order_id = c_j2 and payee_id = v_joao;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(c_j2, c_hoje), jsonb_build_object('nomes', jsonb_build_array('João', 'Roberto'))));
    update public.os_autorizados set valido_ate = null, local_id = pg_temp.loc('Tedesco Marina Garden Plaza') where service_order_id = c_j2 and payee_id = v_joao;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(c_j2, c_hoje), jsonb_build_object('nomes', jsonb_build_array('Roberto'))));
    update public.os_autorizados set local_id = null where service_order_id = c_j2 and payee_id = v_joao;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(c_j2, c_hoje), jsonb_build_object('nomes', jsonb_build_array('João', 'Roberto'))));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L6c quem conta: revogada e vencida não; o dia do valido_ate sim; de outro local não; sem local sim', v_d is null, v_d);

  -- A regra não conferida é nota (R1: nota = a regra de autorização do local quando não conferida).
  begin
    update public.agenda_locais set conferido_por = 'pesquisa', conferido_em = date '2026-10-29' where id = v_it;
    v_d := pg_temp.dif(public._agenda_autorizacao_da_os(c_j2, c_hoje), jsonb_build_object('exige', true, 'conferido', false,
      'nota', 'Marina Itajaí: pede autorização escrita do dono do barco com nome e documento de quem vai e as datas (a confirmar com você).'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L6d sem conferir, a regra vira nota', v_d is null, v_d);

  v_d := pg_temp.dif(public._agenda_autorizacao_da_os(pg_temp.os('OS-J9'), c_hoje), jsonb_build_object('exige', true, 'autorizados', '[]'::jsonb,
    'texto', 'Marina Itajaí pede autorização com o nome de quem vai: ninguém anotado ainda.'));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(pg_temp.os('OS-J6'), c_hoje), jsonb_build_object('exige', null, 'conferido', false, 'nota', null,
    'texto', 'Não sei se Iate Clube Caiobá pede autorização com o nome de quem vai.')));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(pg_temp.os('OS-J1'), c_hoje), jsonb_build_object('exige', null, 'texto', null)));
  v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(pg_temp.os('OS-J8'), c_hoje), jsonb_build_object('exige', null, 'autorizados', '[]'::jsonb, 'texto', null)));
  begin
    update public.agenda_locais set exige_autorizacao = false where id = v_it;
    v_d := coalesce(v_d, pg_temp.dif(public._agenda_autorizacao_da_os(pg_temp.os('OS-J9'), c_hoje), jsonb_build_object('exige', false,
      'texto', 'Marina Itajaí não pede autorização com o nome de quem vai.')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'L6e exige true, false e não sei; o pátio da HBR e o sem local não têm o que dizer', v_d is null, v_d);

  v_d := pg_temp.dif(public._agenda_autorizacao_da_os(c_j2, c_hoje, jsonb_build_object('local_id', null, 'conferido', false)), jsonb_build_object('exige', null, 'autorizados', '[]'::jsonb));
  v_res := pg_temp.ok(v_res, 'L6f p_local vale no lugar da cadeia', v_d is null, v_d);
  v_res := pg_temp.ok(v_res, 'L6g a OS que não existe tem cadeia nula: null, sem erro', public._agenda_autorizacao_da_os('00000000-0000-4000-8000-0000000000ff', c_hoje) is null);

  perform pg_temp.gravar(v_res);
end
$l6$;

-- ── L7. As fronteiras ──────────────────────────────────────────────────────────────────────────────
do $l7$
declare
  v_mig text := nullif(current_setting('agenda_teste.mig_local_fase7d', true), '');
  v_eq  text := nullif(current_setting('agenda_teste.mig_equipe_fase3', true), '');
  v_res jsonb := '[]'::jsonb;
  v_t text;
  v_8 text[] := array['_agenda_local_no', '_agenda_viagem_por_municipio', '_agenda_local_resolvido', '_agenda_local_deslocamento', '_agenda_viagem_da_os',
                      '_agenda_estado_do_bem', '_agenda_local_mascara', '_agenda_autorizacao_da_os'];
begin
  if v_mig is null then
    insert into _resultado values ('L7 as fronteiras', true, 'PULADO: a migration como texto só existe na bancada');
    return;
  end if;

  select string_agg(a.x[1], ',' order by a.x[1]) into v_t
    from regexp_matches(regexp_replace(v_mig, '--[^\n]*', '', 'g'),
                        '\m(?:create(?: or replace)? function public\.\w+|alter table|create table|create trigger|create view|create policy|insert into|update public|delete from|drop \w+)', 'gi') a(x);
  v_res := pg_temp.ok(v_res, 'L7a a migration só cria as 8: nenhuma recriada, nenhuma tabela, nenhum gatilho, nenhum dado',
    v_t = (select string_agg('create or replace function public.' || n, ',' order by 'create or replace function public.' || n) from unnest(v_8) n), v_t);

  -- As 8 só se chamam entre si, e agora ninguém de fora: nada do motor, da vigia nem da ficha (R6.8). Vale até o P4, que chama de propósito: com
  -- _agenda_patio_cabe (dele), esta linha sai sozinha, no molde do F6b.
  if not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_agenda_patio_cabe') then
    select string_agg(p.proname, ',' order by p.proname) into v_t
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.prosrc ~ ('\m(' || array_to_string(v_8, '|') || ')\M')
       and not p.proname = any (v_8);
    v_res := pg_temp.ok(v_res, 'L7b ninguém de fora chama as 8: nada no caminho da vigia em sombra nem do motor (R6.8; a linha sai sozinha com o P4)', v_t is null, v_t);
  end if;

  -- Nenhuma lê o modo da 7d por fora de _agenda_local_modo (R6.7b): aqui nenhuma lê modo nenhum da 7d.
  select string_agg(p.proname, ',' order by p.proname) into v_t
    from pg_proc p
   where p.oid in (select p2.oid from pg_proc p2 where p2.pronamespace = 'public'::regnamespace and p2.proname = any (v_8))
     and regexp_replace(p.prosrc, '--[^
]*', '', 'g') ~ 'modo_local_calendario|modo_local_autorizacao|modo_bem|modo_patio|modo_viagem|modo_mesmo_local|_agenda_local_modo';
  v_res := pg_temp.ok(v_res, 'L7c nenhuma das 8 lê os modos da 7d (quem chama decide; o sábado do 7b é outra coisa)', v_t is null, v_t);

  -- Nenhuma escreve: nenhum comando de escrita no corpo das 8.
  select string_agg(p.proname, ',' order by p.proname) into v_t
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = any (v_8)
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* '\m(insert\s+into|update\s+public|delete\s+from|perform\s+public)\M';
  v_res := pg_temp.ok(v_res, 'L7d nenhuma escreve', v_t is null, v_t);

  -- Os nomes já usados, byte a byte (o texto da ficha de hoje). _agenda_local_da_os é recriada pelo P8 de propósito: com _agenda_ver_locais (dele),
  -- ela sai desta conta; _agenda_bem_da_os fica sempre.
  select string_agg(n, ',') into v_t
    from unnest(array['_agenda_local_da_os', '_agenda_bem_da_os']) n
   where (n = '_agenda_bem_da_os' or not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_agenda_ver_locais'))
     and position((select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = n) in replace(v_eq, E'\r\n', E'\n')) = 0;
  v_res := pg_temp.ok(v_res, 'L7e _agenda_local_da_os e _agenda_bem_da_os: o corpo é o da Fase 3, byte a byte', v_eq is not null and v_t is null, v_t);

  select string_agg(n, ',') into v_t
    from unnest(array['_agenda_local_da_os', '_agenda_bem_da_os', '_agenda_nome_curto', '_agenda_cliente_dia', '_agenda_chave_telefone', 'agenda_dia_util',
                      'agenda_somar_du', 'agenda_feriado', '_agenda_normal', '_agenda_lugar_casa', '_agenda_classe_de_campo', '_agenda_local_conferido',
                      'agenda_feriado_municipal']) n
   where position('function public.' || n || '(' in regexp_replace(v_mig, '--[^\n]*', '', 'g')) > 0;
  v_res := pg_temp.ok(v_res, 'L7f a migration não recria nada do que a sessão do retorno chama, nem os nomes já usados', v_t is null, v_t);

  perform pg_temp.gravar(v_res);
end
$l7$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
