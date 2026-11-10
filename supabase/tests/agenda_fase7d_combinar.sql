-- Prova do combinar com data da Agenda de Produção, Fase 7d (pacote P5; migration 20261107100400; spec-fase7d §5.5, §6.3, §8.3
-- agenda_fase7d_combinar.sql, bloco R, R1, R6.3-3, R6.5, R6.7b, R6.7c, R6.8-4 e R6.12).
-- bancada: depende de 20261107100400
--
--   C0a..  as portas: as 10 novas e as 5 recriadas
--   C0  o acesso (R1, R6.7c): toda OS em local de terceiro; combinado pelo acesso_ok_em ou pelos autorizados; D-2 = combinar, com "O prazo é hoje"; D-1 = a combinar
--       fecha ("virou decisão") e nasce a crítica com as 3 opções; a 3 remarca (o dia FORA do plano, não só a gravação); resolvida quando o acesso entra
--   C1  os 4 tipos, com para e ate; os textos da §6.3
--   C2  o vencido vira pergunta só com o modo ligado; em sombra, a ação executada = false, uma vez por chave; o freio (R6.7b)
--   C3  o decidir 1 grava com *desfaz*; o 2 não grava nada; as recusas; o caminho de verdade (agenda_rascunho_aplicar, *grava*)
--   C4  a pergunta resolvida pelo fato; o dia que passou; o plano que mudou; o modo que voltou a teste; o "amanhã eu pergunto de novo"
--   C5  a rodada uma vez por dia (cedo, ja_rodou, tudo desligado); com o freio ela roda; o passo que falha não derruba
--   C6  o passo calendario (R6.8-4): só com o modo ligado; a variável não vaza nem quando agenda_replanejar lança; o tique da vigia não chama a rodada
--   C7  os conflitos, um de cada; a função não lê modo
--   C8  o fechamento: a combinar a 75 com vaga garantida (R6.7c-3), a local em 30, o teto das 2 vezes só na combinar (R6.7c-4), a crítica a 100;
--       com os 6 modos em sombra, as linhas são as de antes, byte a byte (o remendo do achado 13, deliberado, é o C5 de agenda_fase77c_correcao2.sql)
--   C9  as cópias: as 4 recriadas por blocos só mudam nos blocos "-- FASE 7d:", vivas e na migration; a 5ª só na linha do where
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_combinar.sql
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
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim" e sem as marcas "-- (7d … -- (7d: fim)" de dentro dos blocos da 7c.
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro int := 0;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if v_dentro = 0 and l ~ '^\s*-- FASE 7[defg]:' and l !~ '^\s*-- FASE 7[defg]: fim' then
      v_dentro := 1;
      continue;
    end if;
    if v_dentro = 1 and l ~ '^\s*-- FASE 7[defg]: fim' then
      v_dentro := 0;
      continue;
    end if;
    if v_dentro = 0 and l ~ '^\s*-- \(7[defg] ' then
      v_dentro := 2;
      continue;
    end if;
    if v_dentro = 2 and l ~ '^\s*-- \(7[defg]: fim\)' then
      v_dentro := 0;
      continue;
    end if;
    if v_dentro = 0 then
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

-- ── C0. As portas (sem fixture) ───────────────────────────────────────────────────────────────────
with f(sig, definer, vol, papel) as (values
  ('public._agenda_combinar_texto(jsonb, text, date)', false, 's', 'servico'),
  ('public._agenda_combinar_da_os(uuid, date)', false, 's', 'servico'),
  ('public._agenda_local_conflitos(date)', false, 's', 'servico'),
  ('public.agenda_local_vigiar(date, timestamp with time zone)', true, 'v', 'servico'),
  ('public._agenda_local_resolver(date, timestamp with time zone)', false, 'v', 'ninguem'),
  ('public._agenda_local_calendario(date, timestamp with time zone)', false, 'v', 'ninguem'),
  ('public._agenda_local_combinar(date, timestamp with time zone)', true, 'v', 'ninguem'),
  ('public._agenda_local_restaurar(uuid, uuid, timestamp with time zone)', false, 'v', 'ninguem'),
  ('public._agenda_desfazer_local(uuid, uuid, text, date, timestamp with time zone)', false, 'v', 'ninguem'),
  ('public._agenda_local_decidir(uuid, smallint, uuid, text, text, date, timestamp with time zone)', true, 'v', 'ninguem'))
insert into _resultado
select 'C0a as 10 novas: a volatilidade, definer só nas 3 da rodada e da resposta, search_path fixo, nem public, nem anon, nem authenticated; o service_role só nas leituras e na rodada',
       count(p.oid) = 10
       and bool_and(p.prosecdef = f.definer and p.provolatile = f.vol
                    and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
                    and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                    and has_function_privilege('service_role', p.oid, 'execute') = (f.papel = 'servico')),
       string_agg(f.sig, '; ') filter (where p.oid is null or p.prosecdef <> f.definer or p.provolatile <> f.vol
                                             or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=public'
                                             or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                             or has_function_privilege('service_role', p.oid, 'execute') <> (f.papel = 'servico'))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

insert into _resultado
select 'C0b o anon não alcança a rodada nem a resposta (42501, rodando); o técnico logado também não',
       pg_temp.como('anon', $q$select public.agenda_local_vigiar(date '2027-07-16', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('authenticated', $q$select public.agenda_local_vigiar(date '2027-07-16', now())::text$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public._agenda_combinar_da_os(gen_random_uuid(), date '2027-07-16')::text$q$) like 'erro 42501%'
       and pg_temp.como('authenticated', $q$select public._agenda_local_conflitos(date '2027-07-16')::text$q$) like 'erro 42501%'
       and pg_temp.como('service_role', $q$select public._agenda_local_decidir(gen_random_uuid(), 1::smallint, null, 'whatsapp', null, date '2027-07-16', now())::text$q$) like 'erro 42501%',
       null;

insert into _resultado
select 'C0c as recriadas seguem com as portas e as assinaturas: agenda_decidir e agenda_desfazer só do service_role, _agenda_linhas_do_fechamento também do authenticated',
       has_function_privilege('service_role', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamp with time zone)', 'execute')
       and not has_function_privilege('authenticated', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamp with time zone)', 'execute')
       and not has_function_privilege('anon', 'public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamp with time zone)', 'execute')
       and has_function_privilege('service_role', 'public.agenda_desfazer(uuid, uuid, text, date, timestamp with time zone)', 'execute')
       and not has_function_privilege('authenticated', 'public.agenda_desfazer(uuid, uuid, text, date, timestamp with time zone)', 'execute')
       and has_function_privilege('authenticated', 'public._agenda_linhas_do_fechamento(date)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_linhas_do_fechamento(date)', 'execute'),
       null;

-- ── As fixtures ───────────────────────────────────────────────────────────────────────────────────
do $carga$
begin
  if coalesce(current_setting('agenda_teste.fase7d', true), '') = '' or coalesce(current_setting('agenda_teste.fase7c', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    return;
  end if;
  execute current_setting('agenda_teste.fase7d');
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-J1')
$f$;
create function pg_temp.textos_ok() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.mig_combinar_fase7d', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_correcao_fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_correcao2_fase7c', true), '') <> ''
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
-- O motor e a vigia ligados, sem o freio, e os 6 modos da 7d num valor só
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
-- A rodada direta (só o passo combinar), às 16:20 de p_hoje
create function pg_temp.combinar(p_hoje date) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_hoje::text, true);
  return public._agenda_local_combinar(p_hoje, pg_temp.em(p_hoje, '16:20'));
end $f$;
create function pg_temp.q(p_chave text) returns public.agenda_perguntas language sql stable as $f$
  select q from public.agenda_perguntas q where q.chave = p_chave order by q.criada_em desc limit 1
$f$;
create function pg_temp.chave(p_tipo text, p_os text, p_para date) returns text language sql stable as $f$
  select case when p_tipo = 'critica' then format('acesso:%s:%s', pg_temp.os(p_os), p_para)
              else format('combinar:%s:%s:%s', p_tipo, pg_temp.os(p_os), p_para) end
$f$;
create function pg_temp.decidir(p_q uuid, p_op int, p_hoje date, p_hora text default '17:40') returns jsonb language sql as $f$
  select public.agenda_decidir(p_q, p_op::smallint, pg_temp.adm(), 'whatsapp', p_op::text, p_hoje, pg_temp.em(p_hoje, p_hora))
$f$;
create function pg_temp.item(p_os text, p_tipo text, p_hoje date) returns jsonb language sql as $f$
  select e from jsonb_array_elements(public._agenda_combinar_da_os(pg_temp.os(p_os), p_hoje)) e where e ->> 'tipo' = p_tipo
$f$;
-- Os dias vigentes da OS (compromisso)
create function pg_temp.dias(p_os text) returns text language sql stable as $f$
  select coalesce(string_agg(distinct a.dia::text, ',' order by a.dia::text), '')
    from public.agenda_alocacoes a
   where a.service_order_id = pg_temp.os(p_os) and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
$f$;
create function pg_temp.dias_tudo(p_os text) returns text language sql stable as $f$
  select coalesce(string_agg(distinct a.dia::text, ',' order by a.dia::text), '')
    from public.agenda_alocacoes a
   where a.service_order_id = pg_temp.os(p_os) and a.estado in ('publicada', 'fixada')
$f$;
create function pg_temp.abertas(p_os text) returns text language sql stable as $f$
  select coalesce(string_agg(q.tipo, ',' order by q.tipo), '') from public.agenda_perguntas q
   where q.service_order_id = pg_temp.os(p_os) and q.estado = 'aberta' and q.tipo in ('combinar', 'acesso')
$f$;
-- Um meio-dia a mais de uma OS, com Rafael por padrão
create function pg_temp.aloca(p_os text, p_dia date, p_turno text, p_nome text default 'Rafael', p_reserva text default null) returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, reserva_de)
  values (pg_temp.os(p_os), case when p_nome = 'dono' then public._agenda_dono(null) else pg_temp.pessoa(p_nome) end, p_dia, p_turno, 'turno',
          case when p_reserva is null then 'execucao' else 'reserva' end, 'publicada', 'motor', timestamptz '2027-07-08 16:30-03', p_reserva)
  returning id into v;
  return v;
end $f$;
-- Alocação publicada não muda (o gatilho): cancela e cria
create function pg_temp.cancela(p_os text, p_filtro text default 'true') returns void language plpgsql as $f$
begin
  execute format($s$update public.agenda_alocacoes a set estado = 'cancelada', cancelada_motivo = 'pessoa'
                     where a.service_order_id = %L and a.estado = 'publicada' and %s$s$, pg_temp.os(p_os), p_filtro);
end $f$;

-- ── C0. O acesso ──────────────────────────────────────────────────────────────────────────────────
do $c0$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d2   constant date := date '2027-07-16';  -- sex: ter 20/07 menos 2 dias úteis
  c_d1   constant date := date '2027-07-19';  -- seg: a véspera
  c_para constant date := date '2027-07-20';
  q      public.agenda_perguntas;
  q2     public.agenda_perguntas;
  r      jsonb;
  r2     jsonb;
  t      text;
  v_n    int;
  a      public.agenda_acoes;
  pl     public.os_planejamento;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C0 o acesso', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;

  -- D-2: combinar, com "O prazo é hoje" (R6.7c-2); o local conferido que exige autorização pergunta pelo nome
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    r := pg_temp.combinar(c_d2);
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', c_para));
    v_res := pg_temp.ok(v_res, 'C0d D-2 no local que exige autorização: a combinar nasce (não crítica), "O prazo é hoje", perda_em = o dia, expira no fim do dia, sem veto (R6.7c-2, §6.3)',
      q.tipo = 'combinar' and not q.critica and q.estado = 'aberta' and q.modo = 'ligado' and q.perda_em = c_para
      and q.expira_em = timestamptz '2027-07-21 00:00-03' and q.veto_ate is null and q.service_order_id = pg_temp.os('OS-J2')
      and q.texto = 'Nelson já autorizou João na Marina Itajaí para ter 20/07? O prazo é hoje. 1) Já está (anoto); 2) Ainda não.'
      and jsonb_array_length(q.opcoes) = 2 and (r ->> 'abertas')::int = 1 and (r ->> 'criticas')::int = 0, q.texto || ' · ' || r::text);
    -- no local sem a exigência, o texto do acesso
    update public.agenda_perguntas set estado = 'descartada' where id = q.id;
    update public.agenda_locais set exige_autorizacao = false where nome = 'Marina Itajaí';
    r := pg_temp.combinar(date '2027-07-16');
    select x.* into q2 from public.agenda_perguntas x where x.chave = pg_temp.chave('acesso', 'OS-J2', c_para) and x.estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'C0e D-2 no local sem autorização com o nome: o texto do acesso (§6.3, R1), com quem falta',
      q2.texto = 'O acesso de João na Marina Itajaí para ter 20/07 (o serviço do Nelson) já está combinado? O prazo é hoje. 1) Já está (anoto); 2) Ainda não.', q2.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O prazo que já passou: a pergunta diz a data
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set autorizacao_antecedencia_du = 3 where id;
    r := pg_temp.combinar(c_d2);
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', c_para));
    v_res := pg_temp.ok(v_res, 'C0f com o prazo já vencido a pergunta diz "O prazo era"', q.texto = 'Nelson já autorizou João na Marina Itajaí para ter 20/07? O prazo era qui 15/07. 1) Já está (anoto); 2) Ainda não.', q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Antes do prazo, nada; o fim de semana conta como dias úteis
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    r := pg_temp.combinar(date '2027-07-15');
    v_res := pg_temp.ok(v_res, 'C0g D-3: ainda não venceu, nenhuma pergunta', pg_temp.abertas('OS-J2') = '' and (r ->> 'abertas')::int = 0, pg_temp.abertas('OS-J2'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- D-1: a combinar fecha ("virou decisão"), nasce a crítica com as 3 opções: o dono não recebe as duas
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d2);
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', c_para));
    r := pg_temp.combinar(c_d1);
    q2 := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    v_res := pg_temp.ok(v_res, 'C0h D-1: a crítica acesso (perda_em = o dia, recomendação 2, 3 opções, sem veto) com o texto da §6.3',
      q2.tipo = 'acesso' and q2.critica and q2.estado = 'aberta' and q2.perda_em = c_para and q2.recomendacao = 2 and q2.veto_ate is null
      and jsonb_array_length(q2.opcoes) = 3
      and q2.texto = 'Amanhã (ter 20/07) João vai ao Nelson na Marina Itajaí e o acesso ainda não está combinado. 1) Está combinado (anoto); 2) Vou combinar hoje (recomendo); 3) Segure o dia: eu remarco.'
      and (r ->> 'criticas')::int = 1 and (r ->> 'abertas')::int = 0, q2.texto || ' · ' || r::text);
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C0i a combinar fecha na mesma rodada, "virou decisão": o dono não recebe as duas (R6.7c-2)',
      q.estado = 'resolvida' and q.resolvida_motivo = 'virou decisão' and pg_temp.abertas('OS-J2') = 'acesso', q.estado || ' ' || pg_temp.abertas('OS-J2'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A véspera na sexta: o dia útil seguinte é a segunda, e "Amanhã" seria falso
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    r := pg_temp.combinar(date '2027-07-23');
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J12', date '2027-07-26'));
    v_res := pg_temp.ok(v_res, 'C0j a véspera na sexta não diz "Amanhã" (sex 23/07, o dia é seg 26/07)',
      q.texto like 'Seg 26/07 Rafael vai ao Beto na Marina Itajaí e o acesso ainda não está combinado. %', q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Mais de uma pessoa
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.os_autorizados set revogado_em = now() where service_order_id = pg_temp.os('OS-J2');
    r := pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    v_res := pg_temp.ok(v_res, 'C0k com 2 pessoas a crítica diz "João e Roberto vão"', q.texto like 'Amanhã (ter 20/07) João e Roberto vão ao Nelson na Marina Itajaí %', q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A opção 1 da crítica grava o acesso e, no local nominal, a linha de cada pessoa da pergunta, com *desfaz*
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 1, c_d1);
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    select * into a from public.agenda_acoes x where x.id = (r ->> 'acao_id')::uuid;
    v_res := pg_temp.ok(v_res, 'C0l a opção 1 da crítica: acesso_ok_em, a ação local desfazível com o texto da §6.3, a pergunta respondida, a linha do João (fonte dono, até o último dia)',
      (r ->> 'ok')::boolean and pl.acesso_ok_em = pg_temp.em(c_d1, '17:40') and a.tipo = 'local' and a.origem = 'dono' and a.executada and a.critica and a.pergunta_id = q.id
      and a.desfazivel_ate is not null and a.texto = 'Anotei: João autorizado na Marina Itajaí no serviço de Nelson. *desfaz* volta.'
      and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'respondida'
      and exists (select 1 from public.os_autorizados o where o.service_order_id = pg_temp.os('OS-J2') and o.payee_id = pg_temp.pessoa('João')
                     and o.fonte = 'dono' and o.valido_ate = c_para and o.revogado_em is null and o.local_id is not null),
      r::text);
    v_res := pg_temp.ok(v_res, 'C0m depois da opção 1 o item fica combinado e a rodada de amanhã não pergunta de novo',
      (pg_temp.item('OS-J2', 'acesso', c_d1) ->> 'combinado')::boolean and ((pg_temp.combinar(c_d1)) ->> 'criticas')::int = 0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Resolvida sozinha quando o acesso entra: por fora, no tique seguinte, antes do fechamento
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    r := public.agenda_local_vigiar(c_d1, pg_temp.em(c_d1, '16:20'));
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    update public.os_planejamento set acesso_ok_em = pg_temp.em(c_d1, '17:00') where service_order_id = pg_temp.os('OS-J2');
    r := public.agenda_local_vigiar(c_d1, pg_temp.em(c_d1, '17:15'));
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C0n o acesso que entra por fora (a resposta do cliente) resolve a crítica no tique seguinte, antes do fechamento (R1)',
      (r ->> 'ja_rodou')::boolean and q.estado = 'resolvida' and q.resolvida_motivo = 'o acesso foi anotado', q.estado || ' ' || coalesce(q.resolvida_motivo, ''));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Combinado pelos autorizados, no local nominal
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    r := public.agenda_local_vigiar(c_d1, pg_temp.em(c_d1, '16:20'));
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    insert into public.os_autorizados (service_order_id, payee_id, fonte) values (pg_temp.os('OS-J2'), pg_temp.pessoa('João'), 'dono');
    r := public.agenda_local_vigiar(c_d1, pg_temp.em(c_d1, '17:15'));
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C0o todas as pessoas autorizadas no local nominal: combinado, "a autorização foi anotada"',
      q.estado = 'resolvida' and q.resolvida_motivo = 'a autorização foi anotada', q.estado || ' ' || coalesce(q.resolvida_motivo, ''));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A opção 2 da crítica: fica aberta até o dia, não volta ao fechamento, e ainda aceita a 1 ou a 3
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 2, c_d1, '16:40');
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C0p a opção 2 da crítica responde e fica a pergunta do dia: aberta, com a opção anotada, sem ação nem gravação',
      (r ->> 'ok')::boolean and q.estado = 'aberta' and q.opcao_escolhida = 2 and r ->> 'texto' = 'Certo. Se não der, responda 3 que eu remarco.'
      and (select x.acesso_ok_em from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is null
      and not exists (select 1 from public.agenda_acoes x where x.pergunta_id = q.id), r::text);
    v_res := pg_temp.ok(v_res, 'C0q quem disse "vou combinar hoje" não recebe a mesma crítica no fechamento do mesmo dia',
      not exists (select 1 from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d1)) x where x ->> 'pergunta_id' = q.id::text), null);
    r2 := pg_temp.decidir(q.id, 3, c_d1, '18:00');
    v_res := pg_temp.ok(v_res, 'C0r depois da opção 2, a 3 ainda vale: não deu, ele segura o dia',
      (r2 ->> 'ok')::boolean and pg_temp.dias_tudo('OS-J2') !~ '2027-07-20', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A crítica no dia: o resolvedor fecha, porque ela diz "amanhã"
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := public.agenda_local_vigiar(c_para, pg_temp.em(c_para, '00:05'));
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C0s no dia, a crítica fecha no 1º tique: o texto dela diz "amanhã"',
      q.estado = 'resolvida' and q.resolvida_motivo = 'o dia passou' and pg_temp.abertas('OS-J2') = '', q.estado || ' ' || coalesce(q.resolvida_motivo, ''));
    r := pg_temp.combinar(c_para);
    v_res := pg_temp.ok(v_res, 'C0s2 e no dia a rodada não pergunta nada: nem a combinar, nem a crítica de novo',
      pg_temp.abertas('OS-J2') = '' and (r ->> 'abertas')::int = 0 and (r ->> 'criticas')::int = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A opção 3: "Segure o dia" tira o dia do plano de verdade (R6.7c-1)
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, c_d1);
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    select * into a from public.agenda_acoes x where x.id = (r ->> 'acao_id')::uuid;
    v_res := pg_temp.ok(v_res, 'C0t a opção 3 grava nao_antes_de = o dia útil seguinte e o motivo "sem acesso", com a ação local desfazível; a pergunta fica respondida',
      (r ->> 'ok')::boolean and pl.nao_antes_de = date '2027-07-21' and pl.nao_antes_motivo = 'sem acesso' and a.tipo = 'local' and a.origem = 'dono'
      and a.desfazivel_ate is not null and a.depois ->> 'efeito' = 'segurar' and jsonb_array_length(a.depois -> 'replano_acoes') >= 1
      and (select x.origem from public.agenda_acoes x where x.id = (a.depois -> 'replano_acoes' ->> 0)::uuid) = 'dono'
      and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'respondida', r::text);
    v_res := pg_temp.ok(v_res, 'C0u O DIA SAIU DO PLANO: ter 20/07 não está mais em nenhuma alocação vigente do Nelson (nem como reserva), as 4 de 20/07 cancelaram pelo motivo cliente e a OS foi para depois (R6.7c-1)',
      pg_temp.dias_tudo('OS-J2') = '2027-07-21,2027-07-22'
      and (select count(*) from public.agenda_alocacoes x where x.service_order_id = pg_temp.os('OS-J2') and x.dia = c_para and x.estado = 'cancelada'
                                                             and x.cancelada_motivo = 'cliente') = 4, pg_temp.dias_tudo('OS-J2'));
    v_res := pg_temp.ok(v_res, 'C0v o texto ao dono diz o que aconteceu',
      r ->> 'texto' like 'Segurei o dia: Nelson não começa antes de qua 21/07 (sem acesso). *desfaz* volta. Mudei: Nelson (OS-J2): de ter 20/07 para qua 21 e qui 22/07 %', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O nao_antes_de que já é maior fica: greatest
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.os_planejamento set nao_antes_de = date '2027-07-28', nao_antes_motivo = 'você disse' where service_order_id = pg_temp.os('OS-J2');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, c_d1);
    v_res := pg_temp.ok(v_res, 'C0w o "não antes de" que já era mais tarde não recua (greatest)',
      (select x.nao_antes_de from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) = date '2027-07-28', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O dia que o dono fixou fica, e o texto diz
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform set_config('agenda.mexe_fixado', 'on', true);
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where service_order_id = pg_temp.os('OS-J2');
    perform set_config('agenda.mexe_fixado', 'off', true);
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, c_d1);
    v_res := pg_temp.ok(v_res, 'C0x o fixado pelo dono fica no plano e o texto diz: "para tirar, me diga"',
      pg_temp.dias('OS-J2') like '%2027-07-20%' and r ->> 'texto' like '% Ter 20/07 fica no plano, porque foi você que marcou esse dia: para tirar, me diga.%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O *desfaz* do "Segure o dia": pela ação local, tudo volta
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, c_d1);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', c_d1, pg_temp.em(c_d1, '18:00'));
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C0y *desfaz* da ação local: o "não antes de" sai, o dia volta, as de depois saem, a ação fica desfeita e o replano também',
      (r2 ->> 'ok')::boolean and pl.nao_antes_de is null and pl.nao_antes_motivo is null and pg_temp.dias_tudo('OS-J2') = '2027-07-20'
      and (select x.desfeita_em from public.agenda_acoes x where x.id = (r ->> 'acao_id')::uuid) is not null
      and (select x.desfeita_em from public.agenda_acoes x where x.id = ((r -> 'acoes' ->> 0)::uuid)) is not null, r2::text || ' ' || pg_temp.dias('OS-J2'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O *desfaz* pelo nome e o replano desfeito direto
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, c_d1);
    r2 := public.agenda_acao_desfazivel(pg_temp.os('OS-J2')::text, c_d1, pg_temp.em(c_d1, '18:00'));
    v_res := pg_temp.ok(v_res, 'C0z1 *desfaz Nelson* acha a ação local, que é a última da OS: é ela que leva o replano junto',
      r2 ->> 'status' = 'ok' and (r2 ->> 'acao_id')::uuid = (r ->> 'acao_id')::uuid, r2::text);
    r2 := public.agenda_desfazer((r -> 'acoes' ->> 0)::uuid, pg_temp.adm(), 'dono', c_d1, pg_temp.em(c_d1, '18:00'));
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C0z2 o replano desfeito direto também tira o "não antes de" (senão a vigia tiraria o dia de novo) e deixa a ação local desfeita',
      (r2 ->> 'ok')::boolean and pl.nao_antes_de is null and pg_temp.dias_tudo('OS-J2') = '2027-07-20'
      and (select x.desfeita_em from public.agenda_acoes x where x.id = (r ->> 'acao_id')::uuid) is not null, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Depois de mudar o "não antes de" à mão, o *desfaz* não passa por cima
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, c_d1);
    update public.os_planejamento set nao_antes_de = date '2027-07-30', nao_antes_motivo = 'você disse' where service_order_id = pg_temp.os('OS-J2');
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', c_d1, pg_temp.em(c_d1, '18:00'));
    v_res := pg_temp.ok(v_res, 'C0z3 o que mudou depois da ação não é desfeito por cima: recusa, nada muda',
      not (r2 ->> 'ok')::boolean and r2 ->> 'texto' like 'Não desfaço: depois disso o plano do Nelson mudou.%'
      and (select x.nao_antes_de from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) = date '2027-07-30', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Passou o prazo do *desfaz*
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 1, c_d1);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', date '2027-08-20', timestamptz '2027-08-20 10:00-03');
    v_res := pg_temp.ok(v_res, 'C0z4 passou o prazo do *desfaz*: recusa, o acesso fica',
      not (r2 ->> 'ok')::boolean and r2 ->> 'texto' like 'Não dá mais para desfazer%'
      and (select x.acesso_ok_em from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is not null, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O "Segure o dia" com o freio: pedido do dono, o motor aplica
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.decidir(q.id, 3, c_d1);
    v_res := pg_temp.ok(v_res, 'C0z5 com *gestor, só propor*, a crítica já aberta segue respondível e a opção 3 é pedido do dono: o dia sai (R6.7b)',
      (r ->> 'ok')::boolean and pg_temp.dias_tudo('OS-J2') !~ '2027-07-20' and pg_temp.dias_tudo('OS-J2') <> '', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Com a agenda automática em teste, a opção 3 não faz de conta
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    update public.agenda_config set modo_proposta = 'sombra' where id;
    r := pg_temp.decidir(q.id, 3, c_d1);
    v_res := pg_temp.ok(v_res, 'C0z6 com modo_proposta em teste, a opção 3 recusa: nada grava, a pergunta segue aberta',
      not (r ->> 'ok')::boolean and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta'
      and (select x.nao_antes_de from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O replano que não dá: nada fica
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    create or replace function public.agenda_replanejar(p_os uuid[], p_motivo text default null, p_origem text default 'vigia', p_hoje date default public._hoje_brt(),
                                                        p_agora timestamptz default now(), p_autor uuid default null)
     returns jsonb language sql as $x$ select jsonb_build_object('ok', false, 'texto', 'A agenda mudou.') $x$;
    r := pg_temp.decidir(q.id, 3, c_d1);
    v_res := pg_temp.ok(v_res, 'C0z7 o replano que não aplica desfaz tudo: nada grava, a pergunta segue aberta',
      not (r ->> 'ok')::boolean and r ->> 'texto' like 'Não consegui segurar o dia: A agenda mudou.%'
      and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta'
      and (select x.nao_antes_de from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is null
      and not exists (select 1 from public.agenda_acoes x where x.pergunta_id = q.id), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$c0$;

-- ── C0b. O dia avisado ────────────────────────────────────────────────────────────────────────────
do $c0b$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d1   constant date := date '2027-07-19';
  c_para constant date := date '2027-07-20';
  q      public.agenda_perguntas;
  r      jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C0 o dia avisado', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03' where id;
    -- o prometido firme ao cliente cobre o dia
    update public.os_planejamento set prometido_tipo = 'firme', prometido_de = c_para, prometido_ate = c_para where service_order_id = pg_temp.os('OS-J2');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, c_d1);
    v_res := pg_temp.ok(v_res, 'C0B1 o fim prometido firme ao cliente: o dia sai, e a data nova abre a dia_prometido, o caminho de sempre: quem decide o novo fim é o dono (R6.7c-1)',
      (r ->> 'ok')::boolean and pg_temp.dias_tudo('OS-J2') !~ '2027-07-20' and r ->> 'texto' like '%Preciso de você: Nelson (OS-J2) só dá para terminar em qui 22/07%'
      and exists (select 1 from public.agenda_perguntas x
                   where x.service_order_id = pg_temp.os('OS-J2') and x.estado = 'aberta' and x.tipo = 'dia_prometido'), r::text || ' ' || pg_temp.dias_tudo('OS-J2'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- O dia dito só à equipe, sem promessa firme: o "não antes de" faz dele um dia impossível, a zona travada (7a) não o segura (_agenda_zona_fora). Ele cai sem pergunta:
  -- a decisão já é a opção 3 do dono. Desvio 2 das notas do P5.
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set modo_marcar_sozinho = 'ligado', marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03' where id;
    insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
    values (pg_temp.pessoa('João'), c_para, 'ficha', 'ligado', 'Ficha', pg_temp.em(c_d1, '12:00'), 'enfileirada', 'ficha:c0b');
    perform pg_temp.combinar(c_d1);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, c_d1);
    v_res := pg_temp.ok(v_res, 'C0B2 o dia dito só à equipe cai sem nova pergunta: a opção 3 já é a decisão do dono (desvio 2 das notas do P5)',
      (r ->> 'ok')::boolean and pg_temp.dias_tudo('OS-J2') !~ '2027-07-20'
      and not exists (select 1 from public.agenda_perguntas x
                       where x.service_order_id = pg_temp.os('OS-J2') and x.estado = 'aberta' and x.tipo in ('dia_avisado', 'dia_prometido')), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$c0b$;

-- ── C1. Os 4 tipos ────────────────────────────────────────────────────────────────────────────────
do $c1$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  e      jsonb;
  t      text;
  q      public.agenda_perguntas;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C1 os 4 tipos', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('sombra');
    e := pg_temp.item('OS-J2', 'acesso', c_hoje);
    v_res := pg_temp.ok(v_res, 'C1a acesso: para = o 1º dia de hoje em diante, ate = 2 dias úteis antes, quem falta autorizar (sem quem já está), nominal, o vencido em ate <= hoje',
      e ->> 'para' = '2027-07-20' and e ->> 'ate' = '2027-07-16' and e ->> 'quem' = 'cliente' and e -> 'nomes' = '["João"]'::jsonb
      and (e -> 'pessoas' ->> 0)::uuid = pg_temp.pessoa('João') and (e ->> 'nominal')::boolean and not (e ->> 'combinado')::boolean
      and (e ->> 'vencido')::boolean and e ->> 'modo' = 'sombra' and e ->> 'texto' = 'o acesso de João para ter 20/07, até hoje (sex 16/07)', e::text);
    e := pg_temp.item('OS-J2', 'reserva_marina', c_hoje);
    v_res := pg_temp.ok(v_res, 'C1b reserva_marina: garagem seca dita; ate = marina_reserva_antecedencia_du; o vencido em ate <= hoje (correção O10: no próprio ate, sim)',
      e ->> 'para' = '2027-07-20' and e ->> 'ate' = '2027-07-16' and e ->> 'quem' = 'marina' and (e ->> 'vencido')::boolean
      and e ->> 'texto' = 'a vaga de serviço com a marina, até sex 16/07', e::text);
    e := pg_temp.item('OS-J2', 'descida', c_hoje);
    v_res := pg_temp.ok(v_res, 'C1c descida: exige água (a palavra "Teste de mar") e em seco; para = o último dia; quem = descer_quem',
      e ->> 'para' = '2027-07-20' and e ->> 'quem' = 'a marina' and e ->> 'texto' = 'a descida para o teste na água em ter 20/07', e::text);
    e := pg_temp.item('OS-J1', 'entrada', c_hoje);
    v_res := pg_temp.ok(v_res, 'C1d entrada: local de pátio; ate = patio_entrada_antecedencia_du; o pátio não tem o item acesso (não é de terceiro)',
      e ->> 'para' = '2027-07-20' and e ->> 'ate' = '2027-07-16' and e ->> 'quem' = 'cliente'
      and e ->> 'texto' = 'a entrada do motorhome no pátio para ter 20/07, até sex 16/07' and pg_temp.item('OS-J1', 'acesso', c_hoje) is null, e::text);

    -- A vaga de vários dias, o último dia da descida, e a descida sem quem
    perform pg_temp.aloca('OS-J2', date '2027-07-21', 'manha');
    e := pg_temp.item('OS-J2', 'reserva_marina', date '2027-07-19');
    t := public._agenda_combinar_texto(e, 'pergunta', date '2027-07-19');
    v_res := pg_temp.ok(v_res, 'C1e a pergunta da vaga, com os dias do plano (§6.3)',
      t = 'A vaga de serviço na Marina Itajaí para o barco de Nelson (ter 20 a qua 21/07) já está combinada? O prazo era sex 16/07. 1) Já combinei; 2) Ainda não.', t);
    e := pg_temp.item('OS-J2', 'descida', date '2027-07-19');
    t := public._agenda_combinar_texto(e, 'pergunta', date '2027-07-19');
    v_res := pg_temp.ok(v_res, 'C1f a pergunta da descida: o último dia e quem desce (§6.3); o ate = o da marina a partir do último dia',
      t = 'A descida do barco de Nelson para o teste na água (qua 21/07) já está combinada? Quem desce: a marina. 1) Já combinei; 2) Ainda não.'
      and e ->> 'ate' = '2027-07-19', t);
    update public.os_planejamento set descer_quem = null where service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C1g sem quem desce, "o cliente ou a marina"', pg_temp.item('OS-J2', 'descida', date '2027-07-19') ->> 'quem' = 'o cliente ou a marina', null);
    e := pg_temp.item('OS-J1', 'entrada', date '2027-07-19');
    t := public._agenda_combinar_texto(e, 'pergunta', date '2027-07-19');
    v_res := pg_temp.ok(v_res, 'C1h a pergunta da entrada (§6.3)',
      t = 'Lenine já combinou trazer o motorhome ao pátio para ter 20/07? O prazo era sex 16/07. 1) Já combinou (anoto que chega ter 20/07); 2) Ainda não.', t);

    -- Limites: o mínimo de meios da vaga; o plano é só do que vale
    update public.agenda_config set garagem_reserva_min_meios = 10 where id;
    v_res := pg_temp.ok(v_res, 'C1i abaixo de garagem_reserva_min_meios, sem o item da vaga', pg_temp.item('OS-J2', 'reserva_marina', c_hoje) is null, null);
    update public.agenda_config set garagem_reserva_min_meios = 1 where id;
    update public.os_planejamento set bem_situacao = 'agua', bem_situacao_fonte = 'dono' where service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C1j o bem na água: sem a vaga e sem a descida',
      pg_temp.item('OS-J2', 'reserva_marina', c_hoje) is null and pg_temp.item('OS-J2', 'descida', c_hoje) is null, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    perform pg_temp.base('sombra');
    -- A reserva não conta, o que passou também não; sem plano, nada
    v_res := pg_temp.ok(v_res, 'C1k sem plano vigente, lista vazia; a OS com local pela cidade do cliente (sem tipo) não tem o acesso',
      public._agenda_combinar_da_os(pg_temp.os('OS-J9'), c_hoje) = '[]'::jsonb, null);
    perform pg_temp.cancela('OS-J12');
    perform pg_temp.aloca('OS-J12', date '2027-07-26', 'manha', 'Rafael', 'teto');
    v_res := pg_temp.ok(v_res, 'C1l a reserva não é o plano: sem item', public._agenda_combinar_da_os(pg_temp.os('OS-J12'), c_hoje) = '[]'::jsonb, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    perform pg_temp.base('sombra');
    v_res := pg_temp.ok(v_res, 'C1m depois do dia, o plano é o de hoje em diante: sem item', public._agenda_combinar_da_os(pg_temp.os('OS-J12'), date '2027-07-27') = '[]'::jsonb, null);
    -- J12 sem exigência conferida: o texto do item e o combinado por validade
    update public.os_planejamento set acesso_ok_em = pg_temp.em(date '2027-04-17', '10:00') where service_order_id = pg_temp.os('OS-J12');
    v_res := pg_temp.ok(v_res, 'C1n o acesso_ok_em dentro da validade é combinado (a régua da Fase 5, > hoje − 90)',
      (pg_temp.item('OS-J12', 'acesso', date '2027-07-15') ->> 'combinado')::boolean, null);
    v_res := pg_temp.ok(v_res, 'C1o no 90º dia exato, vencido: não é combinado',
      not (pg_temp.item('OS-J12', 'acesso', date '2027-07-16') ->> 'combinado')::boolean, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Local não conferido que pede autorização: a nota, o texto e a pergunta sem o nome
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_locais set conferido_em = null, conferido_por = null where nome = 'Marina Itajaí';
    e := pg_temp.item('OS-J2', 'acesso', c_hoje);
    v_res := pg_temp.ok(v_res, 'C1p o local que pede e não foi conferido: a nota é a regra (R1), não é nominal, e o foco diz "(regra a confirmar)"',
      e ->> 'nota' like 'Marina Itajaí: pede %(a confirmar com você).' and not (e ->> 'nominal')::boolean and e ->> 'texto' like '% (regra a confirmar)', e::text);
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', date '2027-07-20'));
    v_res := pg_temp.ok(v_res, 'C1q a pergunta do local não conferido é a do acesso, não a da autorização (a regra é nota, AG7-14)',
      q.texto like 'O acesso de João na Marina Itajaí para ter 20/07 (o serviço do Nelson) já está combinado?%', q.texto);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O dono não conta nas pessoas; sozinho no local nominal, nada a autorizar
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.cancela('OS-J12');
    perform pg_temp.aloca('OS-J12', date '2027-07-26', 'manha', 'dono');
    e := pg_temp.item('OS-J12', 'acesso', date '2027-07-23');
    v_res := pg_temp.ok(v_res, 'C1r o dono não entra em pessoas; só com ele no local nominal, não há quem autorizar: combinado',
      e -> 'pessoas' = '[]'::jsonb and (e ->> 'combinado')::boolean, e::text);
    update public.agenda_locais set exige_autorizacao = false where nome = 'Marina Itajaí';
    e := pg_temp.item('OS-J12', 'acesso', date '2027-07-23');
    v_res := pg_temp.ok(v_res, 'C1s só com o dono no local sem a exigência: o acesso segue a combinar, e a crítica diz "você vai"',
      not (e ->> 'combinado')::boolean and public._agenda_combinar_texto(e, 'urgente', date '2027-07-23') like 'Seg 26/07 você vai ao Beto na Marina Itajaí %', e::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A entrada combinada; a marina da OS sem local (a cadeia cai noutro lugar)
  begin
    perform pg_temp.base('sombra');
    update public.os_planejamento set entrada_em = date '2027-07-19', entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'C1t a entrada até o 1º dia é combinada; depois dele, não',
      (pg_temp.item('OS-J1', 'entrada', c_hoje) ->> 'combinado')::boolean, null);
    update public.os_planejamento set entrada_em = date '2027-07-21' where service_order_id = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'C1u a entrada depois do 1º dia não é combinada', not (pg_temp.item('OS-J1', 'entrada', c_hoje) ->> 'combinado')::boolean, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$c1$;

-- ── C2. O vencido: ligado, em teste e com o freio ─────────────────────────────────────────────────
do $c2$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-19';
  r      jsonb;
  r2     jsonb;
  v_n    int;
  v_t    text;
  a      public.agenda_acoes;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C2 o vencido', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- Em sombra: nenhuma pergunta, a ação uma vez por chave
  begin
    perform pg_temp.base('sombra');
    r := pg_temp.combinar(date '2027-07-16');
    select count(*) into v_n from public.agenda_perguntas x where x.tipo in ('combinar', 'acesso');
    -- (correção O10) a vaga e a descida nascem no prazo, como o acesso: a OS-J2 tem as 3; o caso aqui é o do acesso
    select * into a from public.agenda_acoes x where x.tipo = 'local' and x.service_order_id = pg_temp.os('OS-J2') and x.depois ->> 'chave' like 'combinar:acesso:%';
    v_res := pg_temp.ok(v_res, 'C2a em sombra, nenhuma pergunta: a ação local com executada = false, origem vigia, o texto com "o acesso" (R6.5) e a chave',
      v_n = 0 and not a.executada and a.origem = 'vigia' and a.desfazivel_ate is null and a.contada_em is not null
      and a.texto = 'Em teste: eu cobraria o acesso de João na Marina Itajaí até sex 16/07.'
      and a.depois ->> 'chave' = pg_temp.chave('acesso', 'OS-J2', date '2027-07-20') and (r ->> 'em_teste')::int >= 1, a.texto);
    v_res := pg_temp.ok(v_res, 'C2a2 a ação em teste aparece no "o que mudou" do foco (R6.3-6) e não entra no do fechamento: as linhas ficam byte a byte',
      public._agenda_mudancas(date '2027-07-10', date '2027-07-16', false, false, null)::text like '%Em teste: eu cobraria o acesso de João%'
      and public._agenda_mudancas(date '2027-07-10', date '2027-07-16', false, true, null)::text not like '%Em teste: eu cobraria%', null);
    v_n := (select count(*) from public.agenda_acoes x where x.tipo = 'local');
    r2 := pg_temp.combinar(date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C2b de novo no mesmo dia: nada a mais', (r2 ->> 'em_teste')::int = 0 and (select count(*) from public.agenda_acoes x where x.tipo = 'local') = v_n, r2::text);
    r2 := pg_temp.combinar(c_hoje);
    select string_agg(x.texto, ' | ' order by x.texto) into v_t from public.agenda_acoes x where x.tipo = 'local' and x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C2c na véspera, em sombra, nenhuma crítica e a mesma chave do acesso (uma vez só); a vaga e a descida vencem depois',
      not exists (select 1 from public.agenda_perguntas x where x.tipo in ('combinar', 'acesso'))
      and v_t = 'Em teste: eu cobraria a descida do barco de Nelson para o teste na água (ter 20/07). | Em teste: eu cobraria a vaga de serviço na Marina Itajaí para o barco de Nelson até sex 16/07. | Em teste: eu cobraria o acesso de João na Marina Itajaí até sex 16/07.', v_t);
    -- e a entrada do J1
    select string_agg(x.texto, ' | ' order by x.texto) into v_t from public.agenda_acoes x where x.tipo = 'local' and x.service_order_id = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'C2d o "Em teste" da entrada', v_t = 'Em teste: eu cobraria a entrada do motorhome de Lenine no pátio até sex 16/07.', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Desligado: nada de nada
  begin
    perform pg_temp.base('desligado');
    r := pg_temp.combinar(c_hoje);
    v_res := pg_temp.ok(v_res, 'C2e tudo desligado: nenhuma pergunta e nenhuma ação',
      (r ->> 'abertas')::int = 0 and (r ->> 'em_teste')::int = 0 and not exists (select 1 from public.agenda_acoes x where x.tipo = 'local'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Cada tipo com o seu interruptor
  begin
    perform pg_temp.base('desligado');
    perform pg_temp.modo('modo_bem', 'ligado');
    r := pg_temp.combinar(c_hoje);
    v_t := (select string_agg(split_part(x.chave, ':', 2), ',' order by x.chave) from public.agenda_perguntas x where x.tipo = 'combinar');
    v_res := pg_temp.ok(v_res, 'C2f modo_bem ligado: só a vaga e a descida (o acesso e a entrada têm o interruptor deles)', v_t = 'descida,reserva_marina', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('desligado');
    perform pg_temp.modo('modo_patio', 'ligado');
    r := pg_temp.combinar(c_hoje);
    v_t := (select string_agg(split_part(x.chave, ':', 2), ',' order by x.chave) from public.agenda_perguntas x where x.tipo = 'combinar' and x.service_order_id = pg_temp.os('OS-J1'));
    v_res := pg_temp.ok(v_res, 'C2g modo_patio ligado: a entrada, com o texto da §6.3',
      v_t = 'entrada' and (select x.texto from public.agenda_perguntas x where x.tipo = 'combinar' and x.service_order_id = pg_temp.os('OS-J1'))
      = 'Lenine já combinou trazer o motorhome ao pátio para ter 20/07? O prazo era sex 16/07. 1) Já combinou (anoto que chega ter 20/07); 2) Ainda não.', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O freio: ligado = teste. Nenhuma pergunta nova (nem a crítica), a ação "Em teste"
  begin
    perform pg_temp.base('ligado');
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.combinar(c_hoje);
    v_res := pg_temp.ok(v_res, 'C2h com *gestor, só propor*, os modos ligados valem teste: nenhuma pergunta nova, nem a crítica; a ação "Em teste" (R6.7b)',
      not exists (select 1 from public.agenda_perguntas x where x.tipo in ('combinar', 'acesso')) and (r ->> 'em_teste')::int >= 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O freio com a combinar aberta: ela não vira crítica, e não fecha
  begin
    perform pg_temp.base('ligado');
    perform pg_temp.combinar(date '2027-07-16');
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.combinar(c_hoje);
    v_res := pg_temp.ok(v_res, 'C2i com o freio em D-1, a combinar aberta fica (não há crítica para receber o lugar dela)',
      pg_temp.abertas('OS-J2') like '%combinar%' and pg_temp.abertas('OS-J2') not like '%acesso%', pg_temp.abertas('OS-J2'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A OS fora da carteira não pergunta
  begin
    perform pg_temp.base('ligado');
    update public.service_orders set status = 'completed' where id = pg_temp.os('OS-J2');
    r := pg_temp.combinar(date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C2j a OS fora da carteira não pergunta', pg_temp.abertas('OS-J2') = '', pg_temp.abertas('OS-J2'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then
    null;
  end;

  perform pg_temp.gravar(v_res);
end
$c2$;

-- ── C3. A resposta ────────────────────────────────────────────────────────────────────────────────
do $c3$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-19';
  c_para constant date := date '2027-07-20';
  q      public.agenda_perguntas;
  r      jsonb;
  r2     jsonb;
  pl     public.os_planejamento;
  v_t    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C3 a resposta', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;

  -- A vaga: 1 grava, com *desfaz*
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 1, c_hoje);
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C3a a opção 1 da vaga grava reserva_marina_ok_em, com a ação local desfazível',
      (r ->> 'ok')::boolean and pl.reserva_marina_ok_em = pg_temp.em(c_hoje, '17:40')
      and r ->> 'texto' = 'Anotei: a vaga de serviço na Marina Itajaí para o barco de Nelson está combinada. *desfaz* volta.', r::text);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', c_hoje, pg_temp.em(c_hoje, '18:00'));
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C3b o *desfaz* volta a coluna e o texto diz',
      (r2 ->> 'ok')::boolean and pl.reserva_marina_ok_em is null and r2 ->> 'texto' = 'Desfeito: a vaga de serviço para o barco de Nelson voltou a ficar sem combinar.', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A descida
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('descida', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 1, c_hoje);
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C3c a opção 1 da descida grava descida_ok_em',
      (r ->> 'ok')::boolean and pl.descida_ok_em is not null and r ->> 'texto' = 'Anotei: a descida do barco de Nelson para o teste na água está combinada. *desfaz* volta.', r::text);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', c_hoje, pg_temp.em(c_hoje, '18:00'));
    v_res := pg_temp.ok(v_res, 'C3d o *desfaz* da descida',
      (r2 ->> 'ok')::boolean and (select x.descida_ok_em from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is null
      and r2 ->> 'texto' = 'Desfeito: a descida do barco de Nelson voltou a ficar sem combinar.', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A entrada: entrada_em = o dia, fonte dono
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_patio', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('entrada', 'OS-J1', c_para));
    r := pg_temp.decidir(q.id, 1, c_hoje);
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'C3e a opção 1 da entrada grava entrada_em = o dia e entrada_fonte = dono, com o texto da §6.3',
      (r ->> 'ok')::boolean and pl.entrada_em = c_para and pl.entrada_fonte = 'dono' and r ->> 'texto' = 'Anotei: o motorhome de Lenine chega ter 20/07. *desfaz* volta.', r::text);
    v_res := pg_temp.ok(v_res, 'C3f a pergunta da entrada fica combinada: o item agora diz combinado',
      (pg_temp.item('OS-J1', 'entrada', c_hoje) ->> 'combinado')::boolean, null);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', c_hoje, pg_temp.em(c_hoje, '18:00'));
    select * into pl from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'C3g o *desfaz* da entrada', (r2 ->> 'ok')::boolean and pl.entrada_em is null and pl.entrada_fonte is null
      and r2 ->> 'texto' = 'Desfeito: a chegada do motorhome de Lenine saiu.', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A entrada com a retirada já dita antes do dia: o CHECK recusaria; a recusa diz por quê
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_patio', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('entrada', 'OS-J1', c_para));
    update public.os_planejamento set retirada_em = c_para, entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J1');
    r := pg_temp.decidir(q.id, 1, c_hoje);
    v_res := pg_temp.ok(v_res, 'C3h a retirada no dia da entrada: recusa com o motivo, sem erro; a pergunta segue aberta',
      not (r ->> 'ok')::boolean and r ->> 'texto' like 'Não anotei: você disse que o motorhome sai ter 20/07%'
      and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A autorização (combinar de acesso, local nominal): as linhas e o *desfaz*
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(date '2027-07-16');
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 1, date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C3i a opção 1 da combinar de acesso, no local nominal: acesso_ok_em e a linha do João, com a resposta do dono no trecho',
      (r ->> 'ok')::boolean and (select x.acesso_ok_em from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is not null
      and exists (select 1 from public.os_autorizados o where o.service_order_id = pg_temp.os('OS-J2') and o.payee_id = pg_temp.pessoa('João') and o.revogado_em is null), r::text);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'C3j o *desfaz*: a linha ganha revogado_em (nunca apagada), o acesso volta e o texto é o da §6.3',
      (r2 ->> 'ok')::boolean and r2 ->> 'texto' = 'Desfeito: a autorização de João saiu.'
      and exists (select 1 from public.os_autorizados o where o.service_order_id = pg_temp.os('OS-J2') and o.payee_id = pg_temp.pessoa('João') and o.revogado_em is not null)
      and (select x.acesso_ok_em from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is null
      and not (pg_temp.item('OS-J2', 'acesso', date '2027-07-16') ->> 'combinado')::boolean
      and exists (select 1 from public.os_autorizados o where o.service_order_id = pg_temp.os('OS-J2') and o.payee_id = pg_temp.pessoa('Roberto') and o.revogado_em is null), r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O acesso no local sem exigência: nenhuma linha
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_locais set exige_autorizacao = false where nome = 'Marina Itajaí';
    perform pg_temp.combinar(date '2027-07-16');
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 1, date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C3k no local sem a exigência, só acesso_ok_em: nenhuma linha em os_autorizados (R6.5)',
      (r ->> 'ok')::boolean and r ->> 'texto' = 'Anotei: o acesso de João na Marina Itajaí está combinado no serviço de Nelson. *desfaz* volta.'
      and not exists (select 1 from public.os_autorizados o where o.service_order_id = pg_temp.os('OS-J2') and o.payee_id = pg_temp.pessoa('João')), r::text);
    r2 := public.agenda_desfazer((r ->> 'acao_id')::uuid, pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'C3l o *desfaz* do acesso', r2 ->> 'texto' = 'Desfeito: o acesso no serviço de Nelson voltou a ficar sem combinar.', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A 2: só responde
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(date '2027-07-16');
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 2, date '2027-07-16');
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C3m a opção 2 só responde: nada gravado, "Amanhã eu pergunto de novo" (§6.3)',
      (r ->> 'ok')::boolean and r ->> 'texto' = 'Certo. Amanhã eu pergunto de novo.' and q.estado = 'respondida' and q.opcao_escolhida = 2
      and (select x.acesso_ok_em from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is null
      and not exists (select 1 from public.agenda_acoes x where x.pergunta_id = q.id), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A 2 na véspera da vaga: não há amanhã para perguntar
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 2, c_hoje);
    v_res := pg_temp.ok(v_res, 'C3n a opção 2 na véspera do dia não promete o que não vai fazer: amanhã não há pergunta', r ->> 'texto' = 'Certo, não anotei.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- As recusas
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(date '2027-07-16');
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 3, date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C3o a opção que não existe: recusa, dizendo as que existem', not (r ->> 'ok')::boolean
      and r ->> 'texto' = 'Essa opção não existe. As opções são: 1) Já está; 2) Ainda não.', r::text);
    -- fora de ligado pelo modo cru
    perform pg_temp.modo('modo_local_autorizacao', 'sombra');
    r := pg_temp.decidir(q.id, 1, date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C3p o modo cru fora de ligado: recusa com o motivo, nada grava', not (r ->> 'ok')::boolean and r ->> 'texto' like '%em teste%'
      and (select x.acesso_ok_em from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is null, r::text);
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    -- com o freio, a aberta continua respondível
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.decidir(q.id, 1, date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C3q com o freio, a pergunta aberta segue respondível: confere o modo cru (R6.7b)', (r ->> 'ok')::boolean, r::text);
    r := pg_temp.decidir(q.id, 1, date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C3r a pergunta fechada: recusa', not (r ->> 'ok')::boolean and r ->> 'texto' = 'Essa pergunta já foi respondida ou resolvida.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A ação em teste não se desfaz
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.combinar(date '2027-07-16');
    r := public.agenda_desfazer((select x.id from public.agenda_acoes x where x.tipo = 'local' limit 1), pg_temp.adm(), 'dono', date '2027-07-16', pg_temp.em(date '2027-07-16', '18:00'));
    v_res := pg_temp.ok(v_res, 'C3s a ação de teste não se desfaz', not (r ->> 'ok')::boolean and r ->> 'texto' like 'Isso foi só o teste%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O tipo local ainda não é daqui (P6)
  begin
    perform pg_temp.base('sombra');
    insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, opcoes, modo)
    values ('local', 'local:teste', pg_temp.os('OS-J2'), 'Teste?', '[{"n":1,"texto":"a"},{"n":2,"texto":"b"}]', 'ligado') returning * into q;
    r := pg_temp.decidir(q.id, 1, date '2027-07-16');
    -- (7d P6) o tipo local entrou: a opção sem efeito só responde (agenda_fase7d_cliente.sql, K5, prova o resto)
    v_res := pg_temp.ok(v_res, 'C3t agenda_decidir manda o tipo local a _agenda_local_decidir', (r ->> 'ok')::boolean and r ->> 'texto' = 'Certo, não gravei. Quando souber, me diga onde é.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O caminho de verdade: a conversa (agenda_ver foco decisoes → agenda_aplicar → *grava*)
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(date '2027-07-16');
    q := pg_temp.q(pg_temp.chave('acesso', 'OS-J2', c_para));
    v_t := public._agenda_ver_decisoes(date '2027-07-16', pg_temp.em(date '2027-07-16', '17:40')) ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C3u a combinar vem numerada no foco decisões, uma vez só, com o jeito de responder',
      v_t like '%Decisão 1: Nelson já autorizou João%' and v_t not like '%Também quero saber: Nelson já autorizou%' and v_t like '%na decisão 1, a opção 2%', v_t);
    r := public.agenda_rascunho_aplicar(pg_temp.adm(), 'whatsapp', null, null, '1', '1', 'já está combinado', date '2027-07-16', pg_temp.em(date '2027-07-16', '17:41'));
    v_res := pg_temp.ok(v_res, 'C3v agenda_aplicar acha a combinar pelo número e faz o rascunho (antes: "Não tenho decisão da agenda esperando você agora")',
      (r ->> 'ok')::boolean, r::text);
    r2 := public.agenda_rascunho_gravar(pg_temp.adm(), date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C3w o *grava* chega a agenda_decidir: o acesso fica anotado',
      (select x.acesso_ok_em from public.os_planejamento x where x.service_order_id = pg_temp.os('OS-J2')) is not null
      and (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'respondida', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Só a combinar entra na lista das decisões: a de fato continua fora
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(date '2027-07-16');
    insert into public.agenda_perguntas (tipo, chave, service_order_id, texto, modo)
    values ('duracao', 'duracao:teste', pg_temp.os('OS-J2'), 'Quanto dura?', 'ligado');
    v_res := pg_temp.ok(v_res, 'C3x agenda_decisoes_abertas: a combinar entra, a de fato não; e a que venceu sai',
      (select count(*) from jsonb_array_elements(public.agenda_decisoes_abertas(pg_temp.em(date '2027-07-16', '17:40'))) e where e ->> 'tipo' = 'combinar') = 1
      and (select count(*) from jsonb_array_elements(public.agenda_decisoes_abertas(pg_temp.em(date '2027-07-16', '17:40'))) e where e ->> 'tipo' = 'duracao') = 0
      and (select count(*) from jsonb_array_elements(public.agenda_decisoes_abertas(pg_temp.em(date '2027-07-21', '17:40'))) e where e ->> 'tipo' = 'combinar') = 0
      and (public._agenda_ver_decisoes(date '2027-07-16', pg_temp.em(date '2027-07-16', '17:40')) ->> 'texto') like '%Também quero saber: Quanto dura?%', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$c3$;

-- ── C4. A pergunta resolvida pelo fato ────────────────────────────────────────────────────────────
do $c4$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-19';
  c_para constant date := date '2027-07-20';
  q      public.agenda_perguntas;
  r      jsonb;
  v_n    int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C4 a pergunta resolvida', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;

  -- Combinado pelo fato
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    update public.os_planejamento set reserva_marina_ok_em = pg_temp.em(c_hoje, '17:00') where service_order_id = pg_temp.os('OS-J2');
    r := public._agenda_local_resolver(c_hoje, pg_temp.em(c_hoje, '17:15'));
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C4a o item combinado: resolvida, com o motivo', q.estado = 'resolvida' and q.resolvida_motivo = 'já foi combinado' and (r ->> 'resolvidas')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O dia passou
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    perform public._agenda_local_resolver(c_para, pg_temp.em(c_para, '10:00'));
    -- (correção O4) no 1º dia o serviço começou: a pergunta do preparo fecha, com o motivo verdadeiro. Antes ela ficava aberta até o fim do dia
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C4b no dia, a combinar fecha: o serviço começou (correção O4)', q.estado = 'resolvida' and q.resolvida_motivo = 'o serviço já começou', q.resolvida_motivo);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    -- sem ninguém rodar no dia: o resolvedor do dia seguinte
    perform public._agenda_local_resolver(c_para + 1, pg_temp.em(c_para + 1, '00:05'));
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C4c o dia passou: resolvida, "o dia passou"', q.estado = 'resolvida' and q.resolvida_motivo = 'o dia passou', q.estado);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O plano mudou
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    perform pg_temp.cancela('OS-J2');
    perform public._agenda_local_resolver(c_hoje, pg_temp.em(c_hoje, '17:15'));
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C4d o plano saiu: resolvida, "o plano mudou"', q.estado = 'resolvida' and q.resolvida_motivo = 'o plano mudou', q.estado);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O dia do plano mudou: a chave velha fecha e a nova abre
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    perform pg_temp.cancela('OS-J2');
    perform pg_temp.aloca('OS-J2', date '2027-07-21', 'manha');
    r := pg_temp.combinar(c_para);
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C4e o 1º dia andou: a velha fecha, a nova chave abre (nunca as duas sobre o mesmo item)',
      q.estado = 'resolvida' and q.resolvida_motivo = 'o plano mudou'
      and (select count(*) from public.agenda_perguntas x where x.service_order_id = pg_temp.os('OS-J2') and x.estado = 'aberta' and x.chave like 'combinar:reserva_marina:%') = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O modo voltou a teste: descartada, em qualquer tique. Com o freio, fica.
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_hoje);
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    update public.agenda_config set gestor_so_propor = true where id;
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '10:00'));
    v_res := pg_temp.ok(v_res, 'C4f com o freio, a pergunta aberta fica', (select x.estado from public.agenda_perguntas x where x.id = q.id) = 'aberta', r::text);
    update public.agenda_config set gestor_so_propor = false where id;
    perform pg_temp.base('desligado');
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '10:00'));
    q := (select x from public.agenda_perguntas x where x.id = q.id);
    v_res := pg_temp.ok(v_res, 'C4g o modo desligado: descartada no tique (o DESFAZER não deixa pergunta órfã), também com os 6 desligados',
      q.estado = 'descartada' and q.resolvida_motivo like 'o modo voltou a teste%' and r ->> 'rodou' = 'false', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- "Amanhã eu pergunto de novo"
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    update public.agenda_config set marina_reserva_antecedencia_du = 4 where id;
    perform pg_temp.combinar(date '2027-07-16');
    q := pg_temp.q(pg_temp.chave('reserva_marina', 'OS-J2', c_para));
    r := pg_temp.decidir(q.id, 2, date '2027-07-16', '10:00');
    v_res := pg_temp.ok(v_res, 'C4h respondida "ainda não": diz amanhã', r ->> 'texto' = 'Certo. Amanhã eu pergunto de novo.', r::text);
    r := pg_temp.combinar(date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C4i a rodada do mesmo dia não pergunta de novo', pg_temp.abertas('OS-J2') !~ 'combinar' or (select count(*) from public.agenda_perguntas x where x.chave = q.chave and x.estado = 'aberta') = 0, r::text);
    r := pg_temp.combinar(c_hoje);
    v_res := pg_temp.ok(v_res, 'C4j a rodada de amanhã pergunta de novo, com a contagem do zero',
      (select count(*) from public.agenda_perguntas x where x.chave = q.chave and x.estado = 'aberta' and x.mostrada_vezes = 0) = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A aberta não duplica
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(date '2027-07-16');
    r := pg_temp.combinar(date '2027-07-16');
    v_res := pg_temp.ok(v_res, 'C4k a rodada de novo não duplica', (r ->> 'abertas')::int = 0
      and (select count(*) from public.agenda_perguntas x where x.tipo = 'combinar') = (select count(*) from public.agenda_perguntas x where x.tipo = 'combinar' and x.estado = 'aberta'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$c4$;

-- ── C5. A rodada ──────────────────────────────────────────────────────────────────────────────────
do $c5$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  r      jsonb;
  r2     jsonb;
  v_n    int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C5 a rodada', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;

  begin
    perform pg_temp.base('sombra');
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:14'));
    v_res := pg_temp.ok(v_res, 'C5a antes de local_hora: {rodou: false, cedo: true}, sem linha de rodada',
      r ->> 'rodou' = 'false' and (r ->> 'cedo')::boolean and not exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'local'), r::text);
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C5b no 1º tique >= local_hora: {rodou: true}, com os modos e as contagens dos passos; calendario não roda em teste',
      (r ->> 'rodou')::boolean and r #>> '{modos,acesso}' = 'sombra' and r -> 'contagens' ? 'combinar' and r -> 'contagens' ? 'conflitos'
      and not (r -> 'contagens' ? 'calendario') and (r ->> 'erros')::int = 0 and r -> 'falhas' = '[]'::jsonb, r::text);
    v_res := pg_temp.ok(v_res, 'C5c grava a linha em agenda_vigia_rodadas (rotina local), com as contagens e os modos',
      (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'local' and x.p_hoje = c_hoje and x.contagens ? 'modos' and x.erros = 0) = 1, null);
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:30'));
    v_res := pg_temp.ok(v_res, 'C5d o 2º tique do dia: {rodou: false, ja_rodou: true}', r ->> 'rodou' = 'false' and (r ->> 'ja_rodou')::boolean, r::text);
    r := public.agenda_local_vigiar(c_hoje + 1, pg_temp.em(c_hoje + 1, '16:15'));
    v_res := pg_temp.ok(v_res, 'C5e no dia seguinte roda de novo', (r ->> 'rodou')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Tudo desligado
  begin
    perform pg_temp.base('desligado');
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C5f com os 6 desligados: {rodou: false} sem cedo nem ja_rodou, e sem linha',
      r ->> 'rodou' = 'false' and not (r ? 'cedo') and not (r ? 'ja_rodou') and not exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'local'), r::text);
    -- um só ligado já roda
    perform pg_temp.modo('modo_viagem', 'sombra');
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C5g um modo só fora de desligado: roda', (r ->> 'rodou')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Com o freio, roda: só lê e grava "Em teste"
  begin
    perform pg_temp.base('ligado');
    update public.agenda_config set gestor_so_propor = true where id;
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C5h com *gestor, só propor*, ela roda; os modos saem efetivos (ligado = sombra), nada de pergunta nem de calendario (R6.7b)',
      (r ->> 'rodou')::boolean and r #>> '{modos,calendario}' = 'sombra' and not (r -> 'contagens' ? 'calendario')
      and (r #>> '{contagens,combinar,abertas}')::int = 0 and (r #>> '{contagens,combinar,em_teste}')::int >= 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O passo que falha não derruba
  begin
    perform pg_temp.base('sombra');
    create or replace function public._agenda_local_combinar(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $x$
    begin
      raise exception 'quebrei o combinar';
    end $x$;
    v_n := (select count(*) from public.app_error_logs l where l.action = 'local:combinar');
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C5i o passo que falha vai a app_error_logs (agenda, local:combinar), a rodada não cai e os outros passos rodam',
      (r ->> 'rodou')::boolean and (r ->> 'erros')::int = 1 and r -> 'falhas' -> 0 ->> 'passo' = 'combinar' and r -> 'contagens' ? 'conflitos'
      and (select count(*) from public.app_error_logs l where l.action = 'local:combinar' and l.context = 'agenda') = v_n + 1, r::text);
    v_res := pg_temp.ok(v_res, 'C5j a rodada com erro também grava a linha, com erros = 1 (ela conta como rodada do dia)',
      (select x.erros from public.agenda_vigia_rodadas x where x.rotina = 'local' and x.p_hoje = c_hoje) = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  begin
    perform pg_temp.base('sombra');
    r := null;
    begin
      r := public.agenda_local_vigiar(null, now());
    exception when sqlstate '22023' then
      r := '{"recusou": true}';
    end;
    v_res := pg_temp.ok(v_res, 'C5k sem o dia: recusa (22023)', (r ->> 'recusou')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$c5$;

-- ── C6. O passo calendario (R6.8-4) ───────────────────────────────────────────────────────────────
do $c6$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  r      jsonb;
  v_n    int;
  v_v    text;
  v_chamou int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C6 o passo calendario', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;

  -- Ligado: o J1 sai de 20/07, com o motivo local
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6a com modo_local_calendario ligado, a rodada tira o dia fechado: o J1 sai de 20/07, cancelada_motivo = local, a ação da vigia com o texto do P4',
      (r #>> '{contagens,calendario,os}')::int = 1 and (r #>> '{contagens,calendario,replanejadas}')::int = 1 and pg_temp.dias('OS-J1') not like '%2027-07-20%'
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('OS-J1') and a.cancelada_motivo = 'local') = 2
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('OS-J1') and a.origem = 'vigia' and a.executada
                     and a.texto like '%ter 20/07%o local não recebe a equipe nesse dia%'), r::text);
    v_res := pg_temp.ok(v_res, 'C6b a variável fica vazia depois da rodada, na mesma transação', coalesce(current_setting('agenda.local_violacao', true), '') = '', current_setting('agenda.local_violacao', true));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Em teste, nada muda
  begin
    perform pg_temp.base('sombra');
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6c em teste, o dia fica; o passo só conta o conflito', pg_temp.dias('OS-J1') like '%2027-07-20%' and (r #>> '{contagens,conflitos,calendario}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Com o freio, nada muda
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    update public.agenda_config set gestor_so_propor = true where id;
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6d com o freio, ligado = teste: o dia fica (R6.7b)', pg_temp.dias('OS-J1') like '%2027-07-20%' and not (r -> 'contagens' ? 'calendario'), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O fixado pelo dono fica: nem chama o replano
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    perform set_config('agenda.mexe_fixado', 'on', true);
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where service_order_id = pg_temp.os('OS-J1');
    perform set_config('agenda.mexe_fixado', 'off', true);
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6e o dia que o dono fixou fica: o passo nem chama o replano (M2 do P4), e o conflito segue contado',
      (r #>> '{contagens,calendario,os}')::int = 0 and pg_temp.dias('OS-J1') like '%2027-07-20%' and (r #>> '{contagens,conflitos,calendario}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A variável com agenda_replanejar lançando: ela é vista ligada dentro, e fora dela não vaza
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    create or replace function public.agenda_replanejar(p_os uuid[], p_motivo text default null, p_origem text default 'vigia', p_hoje date default public._hoje_brt(),
                                                        p_agora timestamptz default now(), p_autor uuid default null)
     returns jsonb language plpgsql as $x$
    begin
      -- o que se vê lá dentro sai pela mensagem do erro
      raise exception 'variável %', current_setting('agenda.local_violacao', true);
    end $x$;
    v_n := (select count(*) from public.app_error_logs l where l.action = 'local:calendario');
    r := public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_v := (select l.message from public.app_error_logs l where l.action = 'local:calendario' order by l.last_seen_at desc limit 1);
    v_res := pg_temp.ok(v_res, 'C6f agenda_replanejar é chamada com a variável ligada (quem liga é o passo)', v_v like '%variável on%', v_v);
    v_res := pg_temp.ok(v_res, 'C6g agenda_replanejar lança: a rodada não cai, o erro vai a local:calendario e a variável NÃO vaza para o resto da transação',
      (r ->> 'rodou')::boolean and (r ->> 'erros')::int = 1 and coalesce(current_setting('agenda.local_violacao', true), '') = ''
      and (select count(*) from public.app_error_logs l where l.action = 'local:calendario') = v_n + 1, r::text || ' var=' || coalesce(current_setting('agenda.local_violacao', true), 'nulo'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Duas OS: a 1ª lança, a 2ª roda sem herdar nada; e a violação não existe depois
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    perform pg_temp.aloca('OS-J3', date '2027-07-20', 'manha');
    create or replace function public.agenda_replanejar(p_os uuid[], p_motivo text default null, p_origem text default 'vigia', p_hoje date default public._hoje_brt(),
                                                        p_agora timestamptz default now(), p_autor uuid default null)
     returns jsonb language plpgsql as $x$
    begin
      if p_os[1] = pg_temp.os('OS-J1') then
        raise exception 'a primeira quebrou';
      end if;
      return jsonb_build_object('ok', true, 'var', current_setting('agenda.local_violacao', true));
    end $x$;
    r := public._agenda_local_calendario(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6h cada OS no seu bloco: a que quebra não impede a seguinte',
      (r ->> 'os')::int = 2 and (r ->> 'replanejadas')::int = 1 and (r ->> 'erros')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Depois da rodada, outra chamada na mesma transação não vê a violação
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    perform public.agenda_local_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    perform pg_temp.aloca('OS-J3', date '2027-07-20', 'manha');
    r := public.agenda_replanejar(array[pg_temp.os('OS-J3')], 'teste', 'vigia', c_hoje, pg_temp.em(c_hoje, '16:30'));
    v_res := pg_temp.ok(v_res, 'C6i outra chamada de agenda_replanejar na mesma transação não vê a violação local: o dia fica (o tique da vigia fica igual, R6.8-4)',
      pg_temp.dias('OS-J3') like '%2027-07-20%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A variável já ligada por engano não sobrevive: quem liga desliga
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    perform public._agenda_local_calendario(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6j o passo sozinho também desliga', coalesce(current_setting('agenda.local_violacao', true), '') = '', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A retirada só com o pátio
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    update public.os_planejamento set retirada_em = date '2027-07-26', entrada_em = date '2027-07-12', entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J12');
    perform pg_temp.cancela('OS-J1');
    r := public._agenda_local_calendario(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6k a retirada, com o pátio fora de ligado, não chama o replano', (r ->> 'os')::int = 0, r::text);
    perform pg_temp.modo('modo_patio', 'ligado');
    r := public._agenda_local_calendario(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6l a retirada, com o pátio ligado, chama', (r ->> 'os')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O calendario vem antes do combinar: o combinar olha o plano já replanejado
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_calendario', 'ligado');
    perform pg_temp.modo('modo_patio', 'ligado');
    r := public.agenda_local_vigiar(date '2027-07-19', pg_temp.em(date '2027-07-19', '16:15'));
    v_res := pg_temp.ok(v_res, 'C6o o calendario roda antes do combinar: a entrada do J1 não é cobrada para o dia que acabou de sair do plano',
      not exists (select 1 from public.agenda_perguntas x where x.chave = pg_temp.chave('entrada', 'OS-J1', date '2027-07-20')), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- agenda_vigiar não chama a rodada: o tique da vigia não ganha peso
  begin
    perform pg_temp.base('sombra');
    create or replace function public.agenda_local_vigiar(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $x$
    begin
      raise exception 'a vigia me chamou';
    end $x$;
    create or replace function public._agenda_local_combinar(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $x$
    begin
      raise exception 'a vigia me chamou';
    end $x$;
    create or replace function public._agenda_local_conflitos(p_hoje date) returns jsonb language plpgsql as $x$
    begin
      raise exception 'a vigia me chamou';
    end $x$;
    create or replace function public._agenda_combinar_da_os(p_os uuid, p_hoje date) returns jsonb language plpgsql as $x$
    begin
      raise exception 'a vigia me chamou';
    end $x$;
    v_n := (select count(*) from public.app_error_logs l where l.message like '%a vigia me chamou%');
    perform set_config('agenda.hoje', c_hoje::text, true);
    r := public.agenda_vigiar(c_hoje, pg_temp.em(c_hoje, '16:15'));
    v_res := pg_temp.ok(v_res, 'C6m agenda_vigiar roda com as 4 da rodada lançando: nenhuma é chamada (o tique da vigia não ganha peso, R6.8-4)',
      r is not null and (select count(*) from public.app_error_logs l where l.message like '%a vigia me chamou%') = v_n, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'C6n nenhuma função de antes chama a rodada: só o passo 0b3 (pelo texto, nos corpos do banco)',
    not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname <> 'agenda_local_vigiar' and p.prosrc like '%agenda_local_vigiar%'), null);
  -- O tique seguinte é outra transação, que o begin/rollback daqui não enxerga: is_local = true é o que garante. O f7d/p5/vazamento.mjs prova rodando, sem transação em volta.
  v_res := pg_temp.ok(v_res, 'C6p só o passo calendario liga a variável, e sempre com is_local = true: ela acaba com a transação (o tique seguinte não a herda)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prosrc ~ 'set_config\(''agenda\.local_violacao'', ''on''') = 1
    and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.prosrc ~ 'set_config\(''agenda\.local_violacao'', ''on'', true\)') = 1
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.prosrc ~ 'set_config\(''agenda\.local_violacao'', [^)]*false\)'), null);

  perform pg_temp.gravar(v_res);
end
$c6$;

-- ── C7. Os conflitos ──────────────────────────────────────────────────────────────────────────────
do $c7$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2027-07-16';
  r      jsonb;
  e      jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C7 os conflitos', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.base('desligado');
    r := public._agenda_local_conflitos(c_hoje);
    select x into e from jsonb_array_elements(r) x where x ->> 'tipo' = 'calendario' and (x ->> 'os')::uuid = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'C7a o dia fechado, com os modos desligados (a função não lê modo): o J1 em 20/07, sem o parêntese da máscara, as alocações e fica = false',
      e ->> 'dia' = '2027-07-20' and e -> 'turno' = 'null'::jsonb and e ->> 'texto' = 'Lenine (OS-J1): ter 20/07 é feriado em Balneário Camboriú' and e ->> 'origem' = 'mascara'
      and jsonb_array_length(e -> 'alocacoes') = 2 and not (e ->> 'fica')::boolean, e::text);
    v_res := pg_temp.ok(v_res, 'C7b a Marina Itajaí fica em Itajaí: 20/07 não fecha para o J2', not exists (select 1 from jsonb_array_elements(r) x where (x ->> 'os')::uuid = pg_temp.os('OS-J2')), r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O acesso na véspera: conta, não tira ninguém
  begin
    perform pg_temp.base('desligado');
    r := public._agenda_local_conflitos(date '2027-07-19');
    select x into e from jsonb_array_elements(r) x where x ->> 'tipo' = 'acesso' and (x ->> 'os')::uuid = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C7c o acesso não combinado em D-1: só conta (fica = true), com o texto',
      e ->> 'texto' = 'Nelson (OS-J2): o acesso na Marina Itajaí para ter 20/07 ainda não está combinado' and (e ->> 'fica')::boolean and e ->> 'dia' = '2027-07-20', e::text);
    v_res := pg_temp.ok(v_res, 'C7d em D-2, ainda não', not exists (select 1 from jsonb_array_elements(public._agenda_local_conflitos(c_hoje)) x where x ->> 'tipo' = 'acesso'), null);
    update public.os_planejamento set acesso_ok_em = pg_temp.em(date '2027-07-19', '10:00') where service_order_id = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C7e combinado, sai', not exists (select 1 from jsonb_array_elements(public._agenda_local_conflitos(date '2027-07-19')) x where x ->> 'tipo' = 'acesso'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O pátio acima das vagas
  begin
    perform pg_temp.base('desligado');
    update public.agenda_locais set vagas = 1 where nome = 'MP Motorhomes';
    perform pg_temp.aloca('OS-J3', date '2027-07-21', 'manha');
    r := public._agenda_local_conflitos(c_hoje);
    select x into e from jsonb_array_elements(r) x where x ->> 'tipo' = 'patio';
    v_res := pg_temp.ok(v_res, 'C7f o pátio acima das vagas: quem chegou depois, com a frase do P4; o J1 ocupa até o dia útil seguinte (patio_retirada_du)',
      (e ->> 'os')::uuid = pg_temp.os('OS-J3') and e ->> 'dia' = '2027-07-21'
      and e ->> 'texto' = 'Vanderlei (OS-J3): qua 21/07: a MP Motorhomes está cheia nesse dia (1 vaga)', coalesce(e::text, r::text));
    update public.agenda_locais set vagas = null where nome = 'MP Motorhomes';
    v_res := pg_temp.ok(v_res, 'C7g sem vagas ditas, nada limita', not exists (select 1 from jsonb_array_elements(public._agenda_local_conflitos(c_hoje)) x where x ->> 'tipo' = 'patio'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A pernoite quebrada: o dia pulado e a equipe diferente
  begin
    perform pg_temp.base('desligado');
    perform pg_temp.aloca('OS-J6', date '2027-07-20', 'manha');
    perform pg_temp.aloca('OS-J6', date '2027-07-20', 'tarde');
    v_res := pg_temp.ok(v_res, 'C7h a pernoite em um dia só não quebra', not exists (select 1 from jsonb_array_elements(public._agenda_local_conflitos(c_hoje)) x where x ->> 'tipo' = 'viagem'), null);
    perform pg_temp.aloca('OS-J6', date '2027-07-22', 'manha');
    r := public._agenda_local_conflitos(c_hoje);
    select x into e from jsonb_array_elements(r) x where x ->> 'tipo' = 'viagem';
    v_res := pg_temp.ok(v_res, 'C7i a pernoite com o dia pulado: a viagem quebrada, com o texto da §6.2',
      e ->> 'texto' = 'Kalmar (OS-J6): a viagem precisa de 2 dias úteis seguidos com a mesma equipe', coalesce(e::text, r::text));
    perform pg_temp.cancela('OS-J6', $s$a.dia = date '2027-07-22'$s$);
    perform pg_temp.aloca('OS-J6', date '2027-07-21', 'manha');
    v_res := pg_temp.ok(v_res, 'C7j dias seguidos com a mesma equipe: sem conflito', not exists (select 1 from jsonb_array_elements(public._agenda_local_conflitos(c_hoje)) x where x ->> 'tipo' = 'viagem'), null);
    perform pg_temp.cancela('OS-J6', $s$a.dia = date '2027-07-21'$s$);
    perform pg_temp.aloca('OS-J6', date '2027-07-21', 'manha', 'Bruno');
    v_res := pg_temp.ok(v_res, 'C7k a equipe que muda quebra', exists (select 1 from jsonb_array_elements(public._agenda_local_conflitos(c_hoje)) x where x ->> 'tipo' = 'viagem'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O meio-dia fora do horário conferido, o fixado
  begin
    perform pg_temp.base('desligado');
    update public.agenda_locais set abre = time '13:00', fecha = time '18:00' where nome = 'Marina Itajaí';
    r := public._agenda_local_conflitos(c_hoje);
    select x into e from jsonb_array_elements(r) x where x ->> 'tipo' = 'calendario' and (x ->> 'os')::uuid = pg_temp.os('OS-J2');
    v_res := pg_temp.ok(v_res, 'C7l o meio-dia fora do horário do local conferido: um conflito do turno',
      e ->> 'turno' = 'manha' and e ->> 'motivo' like 'ter 20/07 de manhã: Marina Itajaí não recebe a equipe' and jsonb_array_length(e -> 'alocacoes') = 2, coalesce(e::text, r::text));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('desligado');
    perform set_config('agenda.mexe_fixado', 'on', true);
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where service_order_id = pg_temp.os('OS-J1');
    perform set_config('agenda.mexe_fixado', 'off', true);
    select x into e from jsonb_array_elements(public._agenda_local_conflitos(c_hoje)) x where x ->> 'tipo' = 'calendario' and (x ->> 'os')::uuid = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'C7m o fixado pelo dono aparece com fica = true', (e ->> 'fica')::boolean, e::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- O retirado
  begin
    perform pg_temp.base('desligado');
    update public.os_planejamento set retirada_em = date '2027-07-19', entrada_em = date '2027-07-12', entrada_fonte = 'dono' where service_order_id = pg_temp.os('OS-J1');
    perform pg_temp.cancela('OS-J1');
    perform pg_temp.aloca('OS-J1', date '2027-07-21', 'manha');
    select x into e from jsonb_array_elements(public._agenda_local_conflitos(c_hoje)) x where x ->> 'tipo' = 'calendario' and (x ->> 'os')::uuid = pg_temp.os('OS-J1');
    v_res := pg_temp.ok(v_res, 'C7n o dia depois da retirada: origem retirada', e ->> 'origem' = 'retirada' and e ->> 'motivo' = 'qua 21/07: o bem sai seg 19/07', e::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('desligado');
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'pessoa' where estado in ('publicada', 'fixada') and dia >= c_hoje;
    v_res := pg_temp.ok(v_res, 'C7o sem plano, lista vazia', public._agenda_local_conflitos(c_hoje) = '[]'::jsonb, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$c7$;

-- ── C8. O fechamento ──────────────────────────────────────────────────────────────────────────────
do $c8$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d1   constant date := date '2027-07-19';
  c_para constant date := date '2027-07-20';
  q      public.agenda_perguntas;
  r      jsonb;
  l      jsonb;
  v_ant  text;
  v_nov  text;
  v_dif  text;
  c      record;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('C8 o fechamento', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;

  -- 75 com perda em até 2 dias úteis, com vaga garantida
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    update public.agenda_config set modo_vaga_fechamento = 'ligado' where id;
    perform pg_temp.combinar(c_d1);
    perform set_config('agenda.hoje', c_d1::text, true);
    r := public._agenda_linhas_do_fechamento(c_d1);
    select x into l from jsonb_array_elements(r) x where x ->> 'tipo' = 'pergunta' and x ->> 'texto' like 'Agenda: %combinada?%';
    v_res := pg_temp.ok(v_res, 'C8a a combinar com perda_em até o 2º dia útil vai a 75, modo ligado, com a pergunta e o "(e mais 1)": uma linha só (R6.7c-3)',
      (l ->> 'perda')::int = 75 and l ->> 'modo' = 'ligado' and l ->> 'pergunta_id' is not null and l ->> 'texto' like '%(e mais % em *agenda pendências*)'
      and (select count(*) from jsonb_array_elements(r) x where x ->> 'texto' like 'Agenda: %combinada?%') = 1, l::text);
    r := public.agenda_textos_do_fechamento(c_d1, c_d1 + 1);
    v_res := pg_temp.ok(v_res, 'C8b os 75 dão a vaga garantida (agenda_textos_do_fechamento, a régua da 7a): com a carteira cheia ela cabe',
      (r ->> 'vagas_garantidas')::int >= 1
      and exists (select 1 from jsonb_array_elements(r -> 'linhas') x where (x ->> 'perda')::int = 75 and x ->> 'texto' like 'Agenda: %combinada?%'), r ->> 'vagas_garantidas');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O limite é o 2º dia útil: em D-2 sobe, em D-3 não
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    update public.agenda_config set marina_reserva_antecedencia_du = 6 where id;
    perform pg_temp.combinar(date '2027-07-15');
    perform set_config('agenda.hoje', '2027-07-15', true);
    select x into l from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2027-07-15')) x where x ->> 'texto' like 'Agenda: %combinada?%';
    v_res := pg_temp.ok(v_res, 'C8a2 em D-3 a combinar fica em 30', (l ->> 'perda')::int = 30, l::text);
    perform set_config('agenda.hoje', '2027-07-16', true);
    select x into l from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2027-07-16')) x where x ->> 'texto' like 'Agenda: %combinada?%';
    v_res := pg_temp.ok(v_res, 'C8a3 em D-2 a combinar sobe a 75 (perda_em até o 2º dia útil)', (l ->> 'perda')::int = 75, l::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Longe, fica em 30; a local fica em 30
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    update public.agenda_config set autorizacao_antecedencia_du = 3 where id;
    insert into public.agenda_perguntas (tipo, chave, service_order_id, perda_em, texto, opcoes, modo)
    values ('combinar', 'combinar:reserva_marina:teste:x', pg_temp.os('OS-J2'), date '2027-07-30', 'Combinar longe?', '[{"n":1,"texto":"a"},{"n":2,"texto":"b"}]', 'ligado');
    perform set_config('agenda.hoje', c_d1::text, true);
    select x into l from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d1)) x where x ->> 'texto' like 'Agenda: Combinar longe?%';
    v_res := pg_temp.ok(v_res, 'C8c a combinar longe do dia fica em 30', (l ->> 'perda')::int = 30, l::text);
    update public.agenda_perguntas set estado = 'descartada' where chave = 'combinar:reserva_marina:teste:x';
    insert into public.agenda_perguntas (tipo, chave, service_order_id, perda_em, texto, opcoes, modo)
    values ('local', 'local:teste', pg_temp.os('OS-J2'), c_para, 'Onde fica?', '[{"n":1,"texto":"a"},{"n":2,"texto":"b"}]', 'ligado');
    select x into l from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d1)) x where x ->> 'texto' like 'Agenda: Onde fica?%';
    v_res := pg_temp.ok(v_res, 'C8d a local fica em 30, mesmo perdendo perto: nada espera por ela (R6.7c-3)', (l ->> 'perda')::int = 30, l::text);
    update public.agenda_perguntas set estado = 'descartada' where chave = 'local:teste';
    insert into public.agenda_perguntas (tipo, chave, service_order_id, perda_em, texto, modo)
    values ('duracao', 'duracao:teste', pg_temp.os('OS-J2'), c_para, 'Quanto dura?', 'ligado');
    select x into l from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d1)) x where x ->> 'texto' like 'Agenda: Quanto dura?%';
    v_res := pg_temp.ok(v_res, 'C8e as outras perguntas de fato ficam em 30', (l ->> 'perda')::int = 30, l::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O teto: 2 vezes na combinar; a crítica não tem
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_bem', 'ligado');
    perform pg_temp.combinar(c_d1);
    perform set_config('agenda.hoje', c_d1::text, true);
    update public.agenda_perguntas set mostrada_vezes = 2 where tipo = 'combinar';
    r := public._agenda_linhas_do_fechamento(c_d1);
    v_res := pg_temp.ok(v_res, 'C8f a combinar mostrada 2 vezes sai da linha (perguntas_vezes_max vale para ela)',
      not exists (select 1 from jsonb_array_elements(r) x where x ->> 'texto' like 'Agenda: %combinada?%'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    perform set_config('agenda.hoje', c_d1::text, true);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    update public.agenda_perguntas set mostrada_vezes = 5 where id = q.id;
    select x into l from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d1)) x where x ->> 'pergunta_id' = q.id::text;
    v_res := pg_temp.ok(v_res, 'C8g a crítica não tem teto: mostrada 5 vezes, entra; na (a), perda 100 em D-1, tipo decisao, com o texto ao dono (R6.7c-4)',
      l ->> 'tipo' = 'decisao' and (l ->> 'perda')::int = 100 and l ->> 'modo' = 'ligado'
      and l ->> 'texto' = 'Agenda, preciso de você. Amanhã (ter 20/07) João vai ao Nelson na Marina Itajaí e o acesso ainda não está combinado. 1) Está combinado (anoto); 2) Vou combinar hoje (recomendo); 3) Segure o dia: eu remarco. Me responda aqui.', l::text);
    r := public.agenda_fechamento_registrar(c_d1, jsonb_build_array(jsonb_build_object('pergunta_id', q.id)), 'fechamento', pg_temp.em(c_d1, '17:30'));
    v_res := pg_temp.ok(v_res, 'C8h a linha mostrada conta como vista', (select x.mostrada_vezes from public.agenda_perguntas x where x.id = q.id) = 6, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Com o freio, ninguém vê pergunta nova; a ligada segue na linha dela
  begin
    perform pg_temp.base('sombra');
    perform pg_temp.modo('modo_local_autorizacao', 'ligado');
    perform pg_temp.combinar(c_d1);
    update public.agenda_config set gestor_so_propor = true where id;
    perform set_config('agenda.hoje', c_d1::text, true);
    q := pg_temp.q(pg_temp.chave('critica', 'OS-J2', c_para));
    select x into l from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d1)) x where x ->> 'pergunta_id' = q.id::text;
    v_res := pg_temp.ok(v_res, 'C8i com o freio, a crítica já aberta segue na linha: ela é respondível', l ->> 'modo' = 'ligado', l::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  if not pg_temp.textos_ok() then
    perform pg_temp.gravar(v_res);
    return;
  end if;

  -- Com os 6 modos em sombra e em desligado, depois da rodada: as linhas são as da função de antes, byte a byte
  for c in select * from (values ('sombra', date '2027-07-16'), ('sombra', date '2027-07-19'), ('desligado', date '2027-07-19'), ('sombra', date '2026-11-30')) t(modo, hoje) loop
    begin
      perform pg_temp.base(c.modo);
      perform set_config('agenda.hoje', c.hoje::text, true);
      -- antes da rodada
      v_nov := public._agenda_linhas_do_fechamento(c.hoje)::text;
      perform public.agenda_local_vigiar(c.hoje, pg_temp.em(c.hoje, '16:20'));
      v_ant := public._agenda_linhas_do_fechamento(c.hoje)::text;
      if v_nov is distinct from v_ant then
        v_dif := concat_ws('; ', v_dif, format('a rodada mudou as linhas em %s %s', c.modo, c.hoje));
      end if;
      execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_correcao2_fase7c'), '_agenda_linhas_do_fechamento'), E'\r\n', E'\n');
      v_ant := public._agenda_linhas_do_fechamento(c.hoje)::text;
      if v_nov is distinct from v_ant then
        v_dif := concat_ws('; ', v_dif, format('a função nova difere da de antes em %s %s: %s × %s', c.modo, c.hoje, left(v_nov, 300), left(v_ant, 300)));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'C8j com os 6 modos em sombra ou desligados, a rodada não acrescenta linha e as linhas são as da função de antes, byte a byte (4 retratos: sombra em J, em D-1, desligado e em dezembro)',
    v_dif is null, v_dif);

  perform pg_temp.gravar(v_res);
end
$c8$;

-- O remendo do achado 13 (R6.12) mora no cenário das etapas: o antes × depois é o C5a a C5g de agenda_fase77c_correcao2.sql (a função de antes rodando no lugar) e o T19c de
-- agenda_fase7c_tarefas.sql.

-- ── C9. As cópias ─────────────────────────────────────────────────────────────────────────────────
do $c9$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text;
  v_dec  text;
  v_cc   text;
  c      record;
  v_viva text;
  v_txt  text;
  v_org  text;
  v_dif  text;
begin
  if not pg_temp.textos_ok() or coalesce(current_setting('agenda_teste.mig_rascunho_fase2', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_acompanhamento_fase3', true), '') = '' then
    insert into _resultado values ('C9 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_mig := current_setting('agenda_teste.mig_combinar_fase7d');
  for c in select * from (values
      ('agenda_decidir', current_setting('agenda_teste.mig_correcao_fase7b')),
      ('agenda_desfazer', current_setting('agenda_teste.mig_correcao_fase7b')),
      ('_agenda_linhas_do_fechamento', current_setting('agenda_teste.mig_correcao2_fase7c')),
      ('_agenda_ver_decisoes', current_setting('agenda_teste.mig_acompanhamento_fase3'))) t(nome, origem) loop
    v_org := pg_temp.corpo(c.origem, c.nome);
    v_txt := pg_temp.corpo(v_mig, c.nome);
    select replace(p.prosrc, E'\r\n', E'\n') into v_viva from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = c.nome;
    if v_org = '' or v_txt = '' or pg_temp.sem_7d(v_txt) <> v_org or pg_temp.sem_7d(v_viva) <> v_org or v_txt = v_org then
      v_dif := concat_ws('; ', v_dif, c.nome);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'C9a as 4 recriadas por bloco só mudam nos blocos "-- FASE 7d:", vivas e na migration', v_dif is null, v_dif);
  v_org := pg_temp.corpo(current_setting('agenda_teste.mig_rascunho_fase2'), 'agenda_decisoes_abertas');
  v_txt := pg_temp.corpo(v_mig, 'agenda_decisoes_abertas');
  v_res := pg_temp.ok(v_res, 'C9b agenda_decisoes_abertas: só a linha do where (a combinar entra)',
    replace(v_txt, 'where (q.critica or q.tipo = ''combinar'') and', 'where q.critica and') = v_org and v_txt <> v_org, null);
  perform pg_temp.gravar(v_res);
end
$c9$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
