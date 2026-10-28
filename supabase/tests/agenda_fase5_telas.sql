-- Prova da tela da Agenda de Produção, Fase 5 (pacote P6): a chave cliente do cartão "Plano" da OS (os_plano_da_os →
-- _agenda_cliente_da_os) — o contato, o que foi dito ao cliente e se ainda vale, a confirmação, as mensagens desta OS e o
-- que espera o dono (migration 20261028100600).
-- bancada: depende de 20261028100600
--
--   T0  portas: os_plano_da_os para authenticated e service_role (nunca anon), definer; a chave (_agenda_cliente_da_os)
--       invoker e sem grant a ninguém; search_path fixo
--   T1  a chave cliente com a fixture-fase5 (sex 30/10, 17:30): desligado (sem mensagem; o contato); em teste (o Flávio com
--       a véspera do acesso, "em teste: sairia"; o Nelson com o que foi dito, o risco e o "sem resposta"); o Lenine sem
--       telefone; o Kalmar que não recebe; ligado (o que espera você, com a palavra; nenhuma OS nem valor no texto); depois
--       de *manda cliente Nelson* (aprovou) e de *segura cliente Flávio* (segurou); a confirmação; a resposta (o efeito); a
--       lista curta (5 e "mais"); determinismo; o técnico 42501
--   T2  a cópia de os_plano_da_os só acrescenta o bloco "-- FASE 5:" (fora dele, linha a linha, a de 20261026100600)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_telas.sql
--   T0 roda em qualquer lugar; T2 só com a migration antiga como texto; T1 só na bancada (a fixture-fase5; fora dela,
--   PULADO). Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), case when not coalesce(p_ok, false) then p_detalhe end))
$f$;

create function pg_temp.igual(p_res jsonb, p_nome text, p_veio text, p_esperado text) returns jsonb
language sql immutable as $f$
  select pg_temp.ok(p_res, p_nome, p_veio is not distinct from p_esperado, coalesce(p_veio, '(nulo)'))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

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

create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;

create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'as $function$\n' in v) + length(E'as $function$'));
  return left(v, position(E'\n$function$;' in v));
end $f$;

create function pg_temp.sem_fase5(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 5:' and l !~ '^\s*-- FASE 5: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 5: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

-- A chave cliente do cartão de uma OS da fixture (pelo fim do id: '104' = Flávio), sex 30/10.
create function pg_temp.cli(p_n text) returns jsonb language sql stable as $f$
  select public.os_plano_da_os(('05000000-0000-4000-8000-000000000' || p_n)::uuid, date '2026-10-30') -> 'cliente'
$f$;

-- As mensagens da chave numa linha só ("Tipo | quando | estado" separadas por " / ").
create function pg_temp.lista(p_c jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(concat_ws(' | ', m ->> 'tipo_texto', m ->> 'quando_texto', m ->> 'estado_texto'), ' / ' order by o), '')
    from jsonb_array_elements(coalesce(p_c -> 'mensagens', '[]'::jsonb)) with ordinality t(m, o)
$f$;

create function pg_temp.ligar(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_leitura = 'ligado', modo_cliente = p_modo,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar',
                                       'nova_data', 'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;

-- ── T0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'T0a os_plano_da_os: authenticated e service_role, nunca anon; definer com search_path fixo',
       has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
       and not has_function_privilege('anon', p.oid, 'execute') and p.prosecdef
       and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%', null
  from pg_proc p where p.oid = 'public.os_plano_da_os(uuid, date)'::regprocedure;

insert into _resultado
select 'T0b a chave (_agenda_cliente_da_os): invoker, STABLE, search_path fixo e sem grant a ninguém (nem service_role): só o cartão a chama',
       not p.prosecdef and p.provolatile = 's' and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute'), null
  from pg_proc p where p.oid = 'public._agenda_cliente_da_os(uuid, date)'::regprocedure;

-- ── T1. A chave cliente (a fixture-fase5) ───────────────────────────────────────────────────────────────
do $t1$
declare
  v_res jsonb := '[]'::jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec   constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_flav  constant uuid := '05000000-0000-4000-8000-000000000104';
  c_nel   constant uuid := '05000000-0000-4000-8000-000000000112';
  c_van   constant uuid := '05000000-0000-4000-8000-000000000069';
  c       jsonb;
  c2      jsonb;
  v_t     text;
  v_id    uuid;
  r       jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('T1 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase5');
  perform set_config('agenda_teste.hoje', '2026-10-30', true);
  perform set_config('agenda.agora', '2026-10-30 17:30-03', true);
  update public.agenda_config set modo_leitura = 'ligado' where id;

  -- ── T1a: desligado — a chave sai (o contato; o prometido vale sempre), sem mensagem
  c := pg_temp.cli('104');
  v_res := pg_temp.ok(v_res, 'T1a desligado: a chave sai com o contato do Flávio (telefone, conversou), sem mensagem, sem prometido e sem "em teste"',
    c ->> 'modo' = 'desligado' and c ->> 'nome' = 'Flávio' and (c ->> 'telefone_ok')::boolean and (c ->> 'conversou')::boolean
    and not (c ->> 'opt_out')::boolean and c ->> 'contato_texto' is null and c -> 'prometido' = 'null'::jsonb
    and jsonb_array_length(c -> 'mensagens') = 0 and not (c ->> 'em_teste')::boolean and c ->> 'em_teste_texto' is null
    and c ->> 'servico' = 'a instalação do compressor' and (c #>> '{esperando_voce,n}')::int = 0, c::text);
  c := pg_temp.cli('112');
  v_res := pg_temp.igual(v_res, 'T1b desligado: o que foi dito ao Nelson aparece mesmo assim (por mensagem da agenda em 22/10)',
    c #>> '{prometido,texto}', 'qui 05/11 (data firme, por mensagem da agenda em qui 22/10)');

  -- ── T1c–T1f: em teste (a rodada das 17:00 em sombra)
  begin
    perform pg_temp.ligar('sombra');
    perform public.agenda_cliente_vigiar(date '2026-10-30', pg_temp.em('2026-10-30 17:00'));
    c := pg_temp.cli('104');
    v_res := pg_temp.ok(v_res, 'T1c em teste: o Flávio com "Em teste: nada sai ainda" e a véspera do acesso que sairia amanhã às 09:00 (o texto do banco, inteiro)',
      (c ->> 'em_teste')::boolean and c ->> 'em_teste_texto' = 'Em teste: nada sai ainda. Aqui fica o que eu teria mandado.'
      and pg_temp.lista(c) = 'Véspera, com a pergunta do acesso | amanhã às 09:00 | em teste: sairia'
      and c #>> '{mensagens,0,texto}' like 'Bom dia, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. Na terça (03/11) chegamos à tarde%'
      and (c #>> '{mensagens,0,em_teste}')::boolean and not (c #>> '{mensagens,0,espera_voce}')::boolean
      and (c #>> '{esperando_voce,n}')::int = 0 and c #>> '{esperando_voce,texto}' is null, c::text);
    c := pg_temp.cli('112');
    v_res := pg_temp.igual(v_res, 'T1d em teste: o Nelson — o aviso de atraso que sairia, depois a confirmação mandada em 22/10 sem resposta',
      pg_temp.lista(c), 'Aviso de atraso | amanhã às 09:00 | em teste: sairia / Confirmação | qui 22/10 às 10:00 | mandada; sem resposta');
    v_res := pg_temp.ok(v_res, 'T1e o que foi dito ao Nelson: firme qui 05/11, de mensagem, o original, e o risco (a peça em 11/11 → de qui 12/11 a sex 13/11)',
      c -> 'prometido' = jsonb_build_object('tipo', 'firme', 'de', '2026-11-05', 'ate', '2026-11-05', 'original_ate', '2026-11-05',
                                           'fonte', 'mensagem',
                                           'texto', 'qui 05/11 (data firme, por mensagem da agenda em qui 22/10)',
                                           'risco_texto', 'Pode atrasar: agora a previsão é de qui 12/11 a sex 13/11.'),
      c -> 'prometido' ->> 0);
    c := pg_temp.cli('074');
    v_res := pg_temp.ok(v_res, 'T1f o Lenine: sem telefone no cadastro (telefone_ok false), nenhuma mensagem, nada dito',
      not (c ->> 'telefone_ok')::boolean and c ->> 'contato_texto' = 'sem telefone no cadastro'
      and jsonb_array_length(c -> 'mensagens') = 0 and c -> 'prometido' = 'null'::jsonb, c::text);
    c := pg_temp.cli('032');
    v_res := pg_temp.ok(v_res, 'T1g o Kalmar: não recebe (opt_out) — "pediu para não receber mensagens"',
      (c ->> 'opt_out')::boolean and c ->> 'contato_texto' = 'pediu para não receber mensagens', c::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── T1h–T1l: ligado (todos os tipos, a aprovação dos 3 primeiros dias) e a rodada das 17:00
  perform pg_temp.ligar('ligado');
  perform public.agenda_cliente_vigiar(date '2026-10-30', pg_temp.em('2026-10-30 17:00'));
  c := pg_temp.cli('112');
  v_res := pg_temp.igual(v_res, 'T1h ligado: o aviso do Nelson espera você (sai amanhã às 09:01)', pg_temp.lista(c),
    'Aviso de atraso | amanhã às 09:01 | espera você / Confirmação | qui 22/10 às 10:00 | mandada; sem resposta');
  v_res := pg_temp.ok(v_res, 'T1i ligado: o que espera você com a palavra (*manda cliente Nelson* / *segura cliente Nelson*), sem "em teste"',
    (c #>> '{esperando_voce,n}')::int = 1
    and c #>> '{esperando_voce,texto}' = '1 mensagem esperando você: *manda cliente Nelson* manda; *segura cliente Nelson* segura.'
    and (c #>> '{mensagens,0,espera_voce}')::boolean and not (c ->> 'em_teste')::boolean and c ->> 'em_teste_texto' is null,
    c::text);
  c := pg_temp.cli('122');
  v_res := pg_temp.igual(v_res, 'T1j ligado: o "ficou pronto" da Lucenira, já na hora, sai "agora" quando você mandar', pg_temp.lista(c),
    'Ficou pronto | agora | espera você');
  v_t := (select string_agg(concat_ws(' ', m ->> 'texto', m ->> 'estado_texto', m ->> 'quando_texto'), ' ')
            from public.service_orders so, jsonb_array_elements(pg_temp.cli(right(so.id::text, 3)) -> 'mensagens') m
           where so.id in (c_flav, c_nel, '05000000-0000-4000-8000-000000000122', '05000000-0000-4000-8000-000000000096',
                           '05000000-0000-4000-8000-000000000121'));
  v_res := pg_temp.ok(v_res, 'T1k nenhuma mensagem do cartão leva número de OS, valor ou link',
    v_t is not null and v_t !~ 'OS-\d' and v_t !~ 'R\$' and v_t !~* 'http', v_t);

  -- *manda cliente Nelson*: a mensagem aprovada (sai na hora dela; *segura* ainda a para); nada mais espera você
  r := public.agenda_cliente_decidir_dito(c_admin, 'manda', 'Nelson', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:35'));
  perform set_config('agenda.agora', '2026-10-30 17:36-03', true);
  c := pg_temp.cli('112');
  v_res := pg_temp.ok(v_res, 'T1l depois de *manda cliente Nelson*: "você aprovou (para não mandar: *segura cliente Nelson*)" e nada espera você',
    pg_temp.lista(c) like 'Aviso de atraso | amanhã às 09:01 | você aprovou (para não mandar: *segura cliente Nelson*) / %'
    and (c #>> '{esperando_voce,n}')::int = 0 and c #>> '{esperando_voce,texto}' is null, concat_ws(' | ', r, pg_temp.lista(c)));
  -- *segura cliente Flávio*: segurou, não sai
  r := public.agenda_cliente_decidir_dito(c_admin, 'segura', 'Flávio', 'whatsapp', date '2026-10-30', pg_temp.em('2026-10-30 17:37'));
  perform set_config('agenda.agora', '2026-10-30 17:38-03', true);
  c := pg_temp.cli('104');
  v_res := pg_temp.igual(v_res, 'T1m depois de *segura cliente Flávio*: "você segurou: não saiu"', pg_temp.lista(c),
    'Véspera, com a pergunta do acesso | sáb 31/10 às 09:00 | você segurou: não saiu');

  -- a confirmação (client_confirmed_for) e a resposta do cliente (o efeito)
  begin
    update public.service_orders set client_confirmed_for = pg_temp.em('2026-11-03 13:00'), client_confirmed_at = pg_temp.em('2026-10-30 16:00')
     where id = c_flav;
    v_res := pg_temp.igual(v_res, 'T1n a confirmação do cliente: "Ele confirmou ter 03/11."', pg_temp.cli('104') ->> 'confirmado_texto',
                           'Ele confirmou ter 03/11.');
    insert into public.agenda_cliente_respostas (client_id, service_order_id, mensagem_id, recebida_em, tipo_msg, texto, intencao,
                                                 efeito, modo)
    values ('c1000000-0000-4000-8000-000000000005', c_nel, 'd5000000-0000-4000-8000-0000000000a1', pg_temp.em('2026-10-30 17:20'),
            'text', 'sim', 'confirma', 'confirmou', 'ligado')
    returning id into v_id;
    update public.agenda_cliente_mensagens set estado = 'respondida', resposta_id = v_id where id = 'd5000000-0000-4000-8000-0000000000a1';
    v_res := pg_temp.ok(v_res, 'T1o a resposta do cliente: "mandada; respondeu: confirmou" (o efeito como o dono lê)',
      pg_temp.lista(pg_temp.cli('112')) like '% / Confirmação | qui 22/10 às 10:00 | mandada; respondeu: confirmou',
      pg_temp.lista(pg_temp.cli('112')));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- a lista curta: 5 e "mais" (6 mensagens em teste do Vanderlei, uma por dia)
  begin
    insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, dia_alvo, modo, texto, base, enviar_em,
                                                 valida_ate, aprovacao, estado, dedupe_key, criada_em)
    select 'c1000000-0000-4000-8000-000000000001', c_van, 'andamento', 'rodada', date '2026-10-20' + g, 'sombra',
           'Vanderlei, teste ' || g || '.', '{}'::jsonb, pg_temp.em('2026-10-20 09:00') + make_interval(days => g),
           pg_temp.em('2026-10-20 19:00') + make_interval(days => g), 'livre', 'registrada',
           'agenda-cliente:teste:lista:' || g || ':sombra', pg_temp.em('2026-10-20 08:00')
      from generate_series(1, 6) g;
    c := pg_temp.cli('069');
    v_res := pg_temp.ok(v_res, 'T1p a lista curta: as 5 mais recentes (da mais nova para a mais velha) e mensagens_mais = 1',
      jsonb_array_length(c -> 'mensagens') = 5 and (c ->> 'mensagens_mais')::int = 1
      and c #>> '{mensagens,0,texto}' = 'Vanderlei, teste 6.' and c #>> '{mensagens,4,texto}' = 'Vanderlei, teste 2.'
      and c #>> '{mensagens,0,quando_texto}' = 'seg 26/10 às 09:00'
      and c #>> '{mensagens,0,estado_texto}' = 'em teste: teria saído', c::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- determinismo e quem vê
  c := public.os_plano_da_os(c_nel, date '2026-10-30');
  c2 := public.os_plano_da_os(c_nel, date '2026-10-30');
  v_res := pg_temp.ok(v_res, 'T1q duas leituras seguidas dão o mesmo cartão (md5)', md5(c::text) = md5(c2::text), null);
  v_res := pg_temp.ok(v_res, 'T1r o administrador com login lê a mesma chave; o técnico recebe 42501 (a porta do cartão não mudou)',
    pg_temp.como(c_admin, 'authenticated', format($q$select (public.os_plano_da_os(%L, '2026-10-30') -> 'cliente')::text$q$, c_nel))
      = (c -> 'cliente')::text
    and pg_temp.como(c_tec, 'authenticated', format($q$select public.os_plano_da_os(%L, '2026-10-30')::text$q$, c_nel)) like 'erro 42501:%',
    null);
  v_res := pg_temp.ok(v_res, 'T1s sem o cliente na OS a chave é nula (e o cartão sai do mesmo jeito)',
    public._agenda_cliente_da_os('05000000-0000-4000-8000-000000009999', date '2026-10-30') is null, null);

  perform pg_temp.gravar(v_res);
end
$t1$;

-- ── T2. A cópia só acrescenta o bloco ───────────────────────────────────────────────────────────────────
do $t2$
declare
  v_mig text := current_setting('agenda_teste.mig_telas_fase3', true);
  v_novo text;
begin
  if coalesce(v_mig, '') = '' then
    insert into _resultado values ('T2 a cópia de os_plano_da_os', true, 'PULADO: sem agenda_teste.mig_telas_fase3 (rode pela bancada)');
    return;
  end if;
  v_novo := (select p.prosrc from pg_proc p where p.oid = 'public.os_plano_da_os(uuid, date)'::regprocedure);
  insert into _resultado
  select 'T2 os_plano_da_os sem o bloco "-- FASE 5:" é a de 20261026100600, linha a linha (o bloco existe e só põe a chave cliente)',
         pg_temp.sem_fase5(v_novo) = string_to_array(pg_temp.corpo(v_mig, 'os_plano_da_os'), E'\n')
         and v_novo like '%-- FASE 5:%' and v_novo like '%''cliente'', public._agenda_cliente_da_os(p_os, p_hoje),%',
         format('linhas %s × %s', array_length(pg_temp.sem_fase5(v_novo), 1),
                array_length(string_to_array(pg_temp.corpo(v_mig, 'os_plano_da_os'), E'\n'), 1));
end
$t2$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
