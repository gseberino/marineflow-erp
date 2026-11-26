-- Prova do A1b do pacote 1 do assistente (24/11/2026; migration 20270301120100_agenda_p1_sinal_parado.sql; a chave nasce na 20270301120000): com
-- agenda_config.sinal_cobrar_max_dias preenchida, o orçamento (ainda draft) que espera o sinal há mais desses dias não ganha dia sozinho (a trava do
-- sinal volta a valer para ele: classe 4, motivo sinal, "esperando o sinal"). A OS convertida com sinal pendente continua AG7-09. Chave nula = o de
-- antes, byte a byte.
-- bancada: depende de 20270301120100
--
--   S0  a forma (vale em produção; nada grava): a porta de _agenda_sinal_parado (definer, STABLE, sql, search_path fixo; execute para
--       authenticated e service_role, nunca anon nem PUBLIC — e anon chamando de fato é recusado: "revoke de PUBLIC não fecha anon"); a porta
--       de _agenda_classe_da_os (a de antes); o corpo da classe com 1 bloco "-- P1 AGENDA:" e, tirado o bloco (devolvida a linha "--antes:"),
--       o de produção de 26/11/2026 (prosrc sem CR 9b4134d6…); o comentário com o trecho do A1b uma vez; as colunas de audit_log que a função lê
--       e o índice audit_log_registro_idx (na bancada só mostra: a migration do histórico fica fora dela)
--   Sobre o replay de qui 29/10 (agenda_teste.replay2910: o ORÇ-00095 da MP, draft, awaiting_deposit, criado em 09/09, sem audit_log) e a
--   sintética da 7a (agenda_teste.fase7a: a Vera, OS-97005, aberta, com o sinal de R$ 1.000 lançado e não pago), o gestor ligado com a regra
--   sinal_cobrar; datas fixas (hoje = qui 29/10/2026):
--   S1  chave nula: a classe das OS da carteira é a da definição de antes (o corpo sem o bloco, rodado como pg_temp), byte a byte, com o gestor
--       ligado, desligado e sem a regra, e com linhas velhas de audit_log; a função nova é false para todas; o controle: com a chave em 15,
--       só o ORÇ-00095 muda
--   S2  chave 15, o ORÇ-00095 virou awaiting_deposit há 60 dias (audit_log): classe 4, motivo sinal, "esperando o sinal"; com os dias ditos, o
--       motor não o marca (fica em "fora", motivo sinal); com a chave nula, marca (o controle)
--   S3  chave 15, o ORÇ-00095 virou awaiting_deposit de novo há 3 dias (criado há 50): a classe de antes e o motor marca — a idade conta do
--       audit_log, da virada mais nova, e não do created_at; a linha que já vinha de awaiting_deposit (a foto antiga do cabeçalho) não conta; a
--       data da virada é a de Brasília
--   S4  chave 15, a Vera (OS convertida, sinal lançado pendente, v_pend > 0), mesmo com uma virada a awaiting_deposit de 60 dias no audit_log e
--       com quote_status awaiting_deposit: a classe de antes (2, pronta) e o motor marca (AG7-09 intacto)
--   S5  sem audit_log: a idade conta de aprovada_em (09/09, 50 dias): 49 = parado, 50 = não (a borda é "mais de"); sem aprovada_em, de hoje
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_p1_sinal_parado.sql
--   Sem as fixtures (produção), S1 a S5 saem PULADO; S0 roda e não grava nada (só lê o catálogo e chama a função nova como anon e como
--   authenticated, com uma prontidão vazia). Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

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
-- O corpo (prosrc, sem CR) de uma função pela assinatura.
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- <marca>: … -- <marca>: fim" (p_marca é uma alternância de regex), devolvendo as linhas "--antes:" de dentro deles: o corpo
-- de antes (a régua de agenda_p1_terminei.sql).
create function pg_temp.sem_blocos(p text, p_marca text) returns text language sql immutable as $st$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ ('^\s*-- (' || p_marca || '):') and l !~ ('^\s*-- (' || p_marca || '): fim') then 1
                                         when l ~ ('^\s*-- (' || p_marca || '): fim') then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ ('^\s*-- (' || p_marca || '): fim') as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$st$;
-- A porta de uma função: "definer volatilidade | anon authenticated service_role public" (EXECUTE; t ou f).
create function pg_temp.porta(p_assinatura text) returns text language sql stable as $f$
  select format('%s %s | %s %s %s %s', p.prosecdef, p.provolatile, has_function_privilege('anon', p.oid, 'execute'),
                has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute'),
                coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false))
    from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- p_sql (que devolve um valor) como o papel p_papel: o resultado em texto, ou 'erro <estado>: <mensagem>' (o de agenda_fase7b_motor.sql).
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
-- A OS pelo número (os ids do replay são md5: nunca por id).
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
-- O gestor (os 5 modos) ligado, desligado ou sem a regra sinal_cobrar (a régua de agenda_fase7a_sinal_sabado.sql).
create function pg_temp.modos(p_modo text, p_sem_sinal boolean default false) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end,
         marcar_regras = case when p_sem_sinal
                              then '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada}'::text[]
                              else '{estimativa,mo_limpa,uma_pessoa,diagnostico,situacao,sem_peca,embutida_suposta,critico_por_valor,prazo_padrao,compra_firme,teto_equipe,zona_travada,onda,escada,sinal_cobrar}'::text[] end
   where id
$f$;
create function pg_temp.chave(p_dias int) returns void language sql as $f$
  update public.agenda_config set sinal_cobrar_max_dias = p_dias where id
$f$;
-- O replay e a sintética da 7a (uma vez por transação), sem o sábado.
create function pg_temp.fixtures() returns void language plpgsql as $f$
begin
  if pg_temp.os('OS-97006') is null then
    perform set_config('agenda_teste.fase7a_sabado', '', true);
    execute current_setting('agenda_teste.replay2910');
    execute current_setting('agenda_teste.fase7a');
  end if;
end $f$;
-- Uma linha de audit_log da OS: a situação do orçamento passou de p_antes (nulo = sem previous_value, como a troca pela tela) a p_depois em
-- p_quando. marineflow.historico_interno = on só para este insert: com o gatilho do histórico (produção), o carimbo guarda o changed_at dado.
create function pg_temp.virou(p_os uuid, p_quando timestamptz, p_antes text, p_depois text) returns void language plpgsql as $f$
begin
  perform set_config('marineflow.historico_interno', 'on', true);
  insert into public.audit_log (table_name, record_id, action, changed_by, changed_at, previous_value, new_value, reason)
  values ('service_orders', p_os, 'update', 'teste', p_quando,
          case when p_antes is not null then jsonb_build_object('quote_status', p_antes) end, jsonb_build_object('quote_status', p_depois),
          'agenda_p1_sinal_parado');
  perform set_config('marineflow.historico_interno', '', true);
end $f$;
-- Os dias ditos pelo dono (1 dia): sem eles o ORÇ-00095 (só kits, sem mão de obra) fica na classe 4 estimativa e o motor não o marca.
create function pg_temp.dias_ditos(p_os uuid) returns void language sql as $f$
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em)
  values (p_os, 1, 'dono', timestamptz '2026-10-29 10:00-03')
  on conflict (service_order_id) do update set dias = 1, estimativa_fonte = 'dono', estimativa_em = timestamptz '2026-10-29 10:00-03'
$f$;
-- A classe agora: "classe:motivo:texto".
create function pg_temp.classe(p_os uuid) returns text language sql stable as $f$
  select concat_ws(':', x ->> 'classe', x ->> 'motivo', x ->> 'texto') from public._agenda_classe_agora(p_os, date '2026-10-29') x
$f$;
-- O motor para uma OS, sem gravar: "marca" (o item criar de compromisso), "fora <motivo>" ou "nada".
create function pg_temp.motor(p_os uuid) returns text language plpgsql as $f$
declare
  v_p jsonb := public.agenda_propor('os', null, null, array[p_os], '{}'::jsonb, false, 'vigia', null, date '2026-10-29',
                                    pg_temp.em(date '2026-10-29', '17:40'));
begin
  if exists (select 1 from jsonb_array_elements(coalesce(v_p -> 'itens', '[]'::jsonb)) i
              where (i ->> 'os')::uuid = p_os and i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva') then
    return 'marca';
  end if;
  return coalesce((select 'fora ' || (f ->> 'motivo') from jsonb_array_elements(coalesce(v_p -> 'fora', '[]'::jsonb)) f
                    where (f ->> 'os')::uuid = p_os limit 1), 'nada');
end $f$;

-- ── S0. A forma (vale em produção; nada grava) ─────────────────────────────────────────────────────────────────────────────────────
do $s0$
declare
  v_res   jsonb := '[]'::jsonb;
  c_novo  constant text := 'public._agenda_sinal_parado(jsonb,date)';
  c_cls   constant text := 'public._agenda_classe_da_os(jsonb,jsonb,date,boolean,boolean)';
  v_txt   text;
  v_a     text;
  v_b     text;
  v_banc  boolean := coalesce(current_setting('agenda_teste.feriados', true), '') <> '';
begin
  v_res := pg_temp.ok(v_res, format('S0a %s: 1 assinatura, SECURITY DEFINER, STABLE, language sql, devolve boolean, search_path=public; execute para authenticated e service_role, nunca anon nem PUBLIC', c_novo),
    pg_temp.porta(c_novo) = 't s | f t t f'
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_agenda_sinal_parado') = 1
    and exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                 where p.oid = to_regprocedure(c_novo) and l.lanname = 'sql' and p.prorettype = 'boolean'::regtype
                   and array_to_string(p.proconfig, ',') = 'search_path=public'),
    coalesce(pg_temp.porta(c_novo), 'NÃO EXISTE') || ' config '
    || coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure(c_novo)), '-'));
  v_a := pg_temp.como('anon', 'select public._agenda_sinal_parado(''{}''::jsonb, date ''2026-10-29'')::text');
  v_b := pg_temp.como('authenticated', 'select public._agenda_sinal_parado(''{}''::jsonb, date ''2026-10-29'')::text');
  v_res := pg_temp.ok(v_res, 'S0b anon chamando de fato é recusado (42501: revoke de PUBLIC não fecha anon, o revoke de anon fecha); authenticated chama (a cadeia da classe) e, com uma prontidão vazia, é false',
    v_a like 'erro 42501:%_agenda_sinal_parado%' and v_b = 'false', 'anon: ' || coalesce(v_a, '-') || ' | authenticated: ' || coalesce(v_b, '-'));
  v_res := pg_temp.ok(v_res, format('S0c %s: a porta de antes (invoker, STABLE | anon f, authenticated t, service_role t, PUBLIC f) e search_path=public', c_cls),
    pg_temp.porta(c_cls) = 'f s | f t t f'
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure(c_cls) and array_to_string(p.proconfig, ',') = 'search_path=public'),
    coalesce(pg_temp.porta(c_cls), 'NÃO EXISTE'));
  v_txt := coalesce(pg_temp.src(c_cls), '');
  v_res := pg_temp.ok(v_res, 'S0d a classe tem 1 bloco "-- P1 AGENDA:" com a condição nova; sem ele (devolvida a linha "--antes:"), o corpo é o de produção de 26/11/2026 (prosrc sem CR 9b4134d6…); e o tirador morde (o corpo vivo não é esse)',
    (select count(*) from regexp_matches(v_txt, '-- P1 AGENDA: fim', 'g')) = 1
    and v_txt like '%     and not public._agenda_sinal_parado(p_pront, p_hoje) then%'
    and md5(pg_temp.sem_blocos(v_txt, 'P1 AGENDA')) = '9b4134d631d5b151a292599a7cf35f01'
    and md5(v_txt) <> '9b4134d631d5b151a292599a7cf35f01',
    format('%s blocos; sem eles %s', (select count(*) from regexp_matches(v_txt, '-- P1 AGENDA: fim', 'g')), md5(pg_temp.sem_blocos(v_txt, 'P1 AGENDA'))));
  v_txt := obj_description(to_regprocedure(c_cls), 'pg_proc');
  v_res := pg_temp.ok(v_res, 'S0e o comentário da classe: o de antes mais o trecho do A1b, uma vez só (a migration aplicada duas vezes não repete)',
    coalesce(v_txt, '') like 'Agenda de Produção (Fase 2, P2)%'
    and (select count(*) from regexp_matches(coalesce(v_txt, ''), 'P1 AGENDA \(A1b, 24/11/2026', 'g')) = 1,
    left(coalesce(v_txt, '(sem comentário)'), 60) || ' … ' || right(coalesce(v_txt, ''), 60));
  v_res := pg_temp.ok(v_res, 'S0f audit_log tem as colunas que a função lê, com os tipos (table_name text, record_id uuid, changed_at timestamptz, previous_value jsonb, new_value jsonb)',
    (select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' order by a.attname) from pg_attribute a
      where a.attrelid = 'public.audit_log'::regclass and not a.attisdropped
        and a.attname in ('table_name', 'record_id', 'changed_at', 'previous_value', 'new_value'))
    = 'changed_at timestamp with time zone, new_value jsonb, previous_value jsonb, record_id uuid, table_name text', null);
  v_txt := (select pg_get_indexdef(i.indexrelid) from pg_index i join pg_class c on c.oid = i.indexrelid
             where i.indrelid = 'public.audit_log'::regclass and c.relname = 'audit_log_registro_idx');
  v_res := pg_temp.ok(v_res, 'S0g o índice audit_log_registro_idx (table_name, record_id, changed_at DESC) existe (na bancada só mostra: a migration do histórico, 20270121100000, fica fora dela)',
    v_banc or coalesce(v_txt, '') like '%(table_name, record_id, changed_at DESC)%',
    coalesce(v_txt, 'não existe') || case when v_banc then ' (bancada)' else '' end);
  perform pg_temp.gravar(v_res);
end
$s0$;

-- ── S1 a S5. O replay de 29/10 e a sintética da 7a ───────────────────────────────────────────────────────────────────────────────────
do $s$
declare
  v_res  jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-10-29';
  c_cls  constant text := 'public._agenda_classe_da_os(jsonb,jsonb,date,boolean,boolean)';
  v_mp   uuid;
  v_vera uuid;
  v_a    text;
  v_b    text;
  v_c    text;
  v_t    text;
  v_m    text;
  v_pr   jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay2910', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
    insert into _resultado values ('S1–S5 (o replay de 29/10 e a sintética da 7a)', true, 'PULADO: sem agenda_teste.replay2910 e fase7a (rode pela bancada)');
    return;
  end if;
  -- a definição de antes: o corpo vivo sem o bloco do A1b (o S0d prova que é o de produção), como pg_temp
  execute format('create function pg_temp.classe_antes(p_pront jsonb, p_meios jsonb, p_hoje date, p_tem_fixada boolean default false, '
                 'p_fora_do_horizonte boolean default false) returns jsonb language plpgsql stable set search_path to ''public'' as $ca$%s$ca$',
                 pg_temp.sem_blocos(pg_temp.src(c_cls), 'P1 AGENDA'));
  begin
    perform pg_temp.fixtures();
    v_mp := pg_temp.os('ORÇ-00095');
    v_vera := pg_temp.os('OS-97005');
    v_res := pg_temp.ok(v_res, 'S1o o ponto de partida: a chave nasce nula; o ORÇ-00095 draft/awaiting_deposit aprovado (criado) em 09/09, sem linha em audit_log; a Vera aberta com o sinal de R$ 1.000 pendente',
      (select c.sinal_cobrar_max_dias is null from public.agenda_config c where c.id)
      and (select k.status = 'draft' and k.quote_status = 'awaiting_deposit' and k.eh_orcamento and k.aprovada_em = date '2026-09-09'
             from public.os_carteira(c_hoje) k where k.service_order_id = v_mp)
      and not exists (select 1 from public.audit_log a where a.record_id = v_mp)
      and (select k.status = 'open' and not k.eh_orcamento and k.sinal_pendente = 1000 from public.os_carteira(c_hoje) k where k.service_order_id = v_vera),
      null);

    -- ── S1. Chave nula: a de antes, byte a byte ──
    perform pg_temp.virou(v_mp, timestamptz '2026-08-30 15:00-03', 'approved', 'awaiting_deposit');
    perform pg_temp.virou(v_vera, timestamptz '2026-08-30 15:00-03', 'approved', 'awaiting_deposit');
    v_a := '';
    v_b := '';
    foreach v_m in array array['ligado', 'desligado', 'sem_regra'] loop
      perform pg_temp.modos(case when v_m = 'desligado' then 'desligado' else 'ligado' end, v_m = 'sem_regra');
      select v_a || string_agg(k.numero || '=' || public._agenda_classe_da_os(x.pr, x.me, c_hoje)::text, '|' order by k.numero),
             v_b || string_agg(k.numero || '=' || pg_temp.classe_antes(x.pr, x.me, c_hoje)::text, '|' order by k.numero)
        into v_a, v_b
        from public.os_carteira(c_hoje) k
        cross join lateral (select public.os_prontidao(k.service_order_id, c_hoje) as pr,
                                   public.agenda_meios_da_os(k.service_order_id, c_hoje) as me) x;
    end loop;
    perform pg_temp.modos('ligado');
    select string_agg(k.numero, ',' order by k.numero) filter (where public._agenda_sinal_parado(public.os_prontidao(k.service_order_id, c_hoje), c_hoje))
      into v_t from public.os_carteira(c_hoje) k;
    v_res := pg_temp.ok(v_res, 'S1a chave nula, com o gestor ligado (a regra sinal_cobrar), desligado e sem a regra, e com viradas velhas no audit_log: a classe das OS da carteira (o replay e a sintética) é a da definição de antes, byte a byte; a função nova é false para todas',
      v_a = v_b and length(v_a) > 1000 and v_t is null, md5(v_a) || ' / ' || md5(v_b) || ' | parado: ' || coalesce(v_t, 'nenhuma'));
    perform pg_temp.chave(15);
    select string_agg(k.numero, ',' order by k.numero) into v_c
      from public.os_carteira(c_hoje) k
      cross join lateral (select public.os_prontidao(k.service_order_id, c_hoje) as pr,
                                 public.agenda_meios_da_os(k.service_order_id, c_hoje) as me) x
     where public._agenda_classe_da_os(x.pr, x.me, c_hoje) is distinct from pg_temp.classe_antes(x.pr, x.me, c_hoje);
    v_res := pg_temp.ok(v_res, 'S1b o controle: com a chave em 15 (o gestor ligado), muda só a classe do ORÇ-00095 (a Vera, OS com sinal pendente, não)',
      v_c = 'ORÇ-00095', coalesce(v_c, '-'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S2. Chave 15, virou awaiting_deposit há 60 dias: espera o sinal; o motor não marca ──
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_mp := pg_temp.os('ORÇ-00095');
    perform pg_temp.virou(v_mp, timestamptz '2026-08-30 15:00-03', 'approved', 'awaiting_deposit');
    perform pg_temp.dias_ditos(v_mp);
    v_a := pg_temp.classe(v_mp) || ' | ' || pg_temp.motor(v_mp);
    perform pg_temp.chave(15);
    v_pr := public.os_prontidao(v_mp, c_hoje);
    v_b := pg_temp.classe(v_mp) || ' | ' || pg_temp.motor(v_mp);
    v_res := pg_temp.ok(v_res, 'S2a chave 15, o ORÇ-00095 virou awaiting_deposit em 30/08 (60 dias): parado; classe 4, motivo sinal, "esperando o sinal"; com os dias ditos, o motor não o marca (fora, motivo sinal)',
      public._agenda_sinal_parado(v_pr, c_hoje) and v_b = '4:sinal:esperando o sinal | fora sinal', v_b);
    v_res := pg_temp.ok(v_res, 'S2b o controle: com a chave nula, o mesmo orçamento com os dias ditos ganha classe de compromisso e o motor o marca (AG7-09 de antes)',
      v_a like '%| marca' and v_a not like '4:%', v_a);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S3. Chave 15, virou de novo há 3 dias: a idade conta do audit_log (a virada mais nova), em Brasília ──
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_mp := pg_temp.os('ORÇ-00095');
    perform pg_temp.dias_ditos(v_mp);
    perform pg_temp.chave(15);
    perform pg_temp.virou(v_mp, timestamptz '2026-08-30 15:00-03', 'approved', 'awaiting_deposit');
    perform pg_temp.virou(v_mp, timestamptz '2026-10-26 10:00-03', 'awaiting_deposit', 'rejected');
    perform pg_temp.virou(v_mp, timestamptz '2026-10-26 10:05-03', 'rejected', 'awaiting_deposit');
    v_pr := public.os_prontidao(v_mp, c_hoje);
    v_t := pg_temp.classe(v_mp) || ' | ' || pg_temp.motor(v_mp);
    v_res := pg_temp.ok(v_res, 'S3a chave 15, o ORÇ-00095 (criado há 50 dias, em 09/09) virou awaiting_deposit de novo em 26/10 (3 dias): não está parado, a classe é a de antes e o motor marca — a idade conta da virada mais nova do audit_log, não do created_at',
      not public._agenda_sinal_parado(v_pr, c_hoje)
      and (public._agenda_classe_agora(v_mp, c_hoje) - 'pront') = (pg_temp.classe_antes(v_pr, public.agenda_meios_da_os(v_mp, c_hoje), c_hoje) - 'pront')
      and v_t like '%| marca' and v_t not like '4:%',
      v_t);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_mp := pg_temp.os('ORÇ-00095');
    perform pg_temp.chave(15);
    perform pg_temp.virou(v_mp, timestamptz '2026-08-30 15:00-03', 'approved', 'awaiting_deposit');
    -- a foto antiga do cabeçalho (o formulário, antes do gatilho de 16/11): previous_value e new_value com a mesma situação
    perform set_config('marineflow.historico_interno', 'on', true);
    insert into public.audit_log (table_name, record_id, action, changed_by, changed_at, previous_value, new_value, reason)
    values ('service_orders', v_mp, 'update', 'sistema', timestamptz '2026-10-28 09:00-03',
            jsonb_build_object('quote_status', 'awaiting_deposit', 'grand_total', 14461, 'status', 'draft'),
            jsonb_build_object('quote_status', 'awaiting_deposit', 'grand_total', 14461, 'problem_description', 'kits'), 'agenda_p1_sinal_parado');
    -- e linhas que não são virada: o envio (outro kind de new_value) e o retrato da versão (quote_status dentro de retrato)
    insert into public.audit_log (table_name, record_id, action, changed_by, changed_at, previous_value, new_value, reason)
    values ('service_orders', v_mp, 'whatsapp_send', 'sistema', timestamptz '2026-10-28 09:10-03', null,
            jsonb_build_object('kind', 'link', 'public_url', 'x'), 'agenda_p1_sinal_parado'),
           ('service_orders', v_mp, 'update', 'sistema', timestamptz '2026-10-28 09:20-03', null,
            jsonb_build_object('versao', 3, 'retrato', jsonb_build_object('cabecalho', jsonb_build_object('quote_status', 'awaiting_deposit'))),
            'agenda_p1_sinal_parado');
    perform set_config('marineflow.historico_interno', '', true);
    v_res := pg_temp.ok(v_res, 'S3b a linha que já vinha de awaiting_deposit (a foto do cabeçalho de 28/10), o envio e o retrato não contam como virada: a idade continua de 30/08 (60 dias), parado, classe 4 sinal',
      public._agenda_sinal_parado(public.os_prontidao(v_mp, c_hoje), c_hoje) and pg_temp.classe(v_mp) = '4:sinal:esperando o sinal',
      pg_temp.classe(v_mp));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_mp := pg_temp.os('ORÇ-00095');
    -- a virada às 22:30 de dom 13/09 em Brasília é 01:30 de seg 14/09 em UTC: até qui 29/10, 46 dias por Brasília (45 por UTC)
    perform pg_temp.virou(v_mp, timestamptz '2026-09-14 01:30+00', 'approved', 'awaiting_deposit');
    v_pr := public.os_prontidao(v_mp, c_hoje);
    perform pg_temp.chave(45);
    v_a := public._agenda_sinal_parado(v_pr, c_hoje)::text;
    perform pg_temp.chave(46);
    v_b := public._agenda_sinal_parado(v_pr, c_hoje)::text;
    v_res := pg_temp.ok(v_res, 'S3c a data da virada é a de Brasília (sessão em UTC): virou dom 13/09 22:30 (seg 14/09 01:30 UTC) = 46 dias até qui 29/10; com 45, parado; com 46, não',
      v_a = 'true' and v_b = 'false', '45: ' || v_a || ' | 46: ' || v_b);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S4. Chave 15, a OS convertida com sinal lançado pendente: AG7-09 intacto ──
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_vera := pg_temp.os('OS-97005');
    perform pg_temp.dias_ditos(v_vera);
    perform pg_temp.chave(15);
    perform pg_temp.virou(v_vera, timestamptz '2026-08-30 15:00-03', 'approved', 'awaiting_deposit');
    v_pr := public.os_prontidao(v_vera, c_hoje);
    v_a := pg_temp.classe(v_vera) || ' | ' || pg_temp.motor(v_vera);
    v_res := pg_temp.ok(v_res, 'S4a chave 15, a Vera (OS-97005, aberta, sinal de R$ 1.000 lançado e não pago), mesmo com uma virada a awaiting_deposit de 60 dias no audit_log: não está parada, classe 2 pronta (a de antes) e o motor marca',
      not public._agenda_sinal_parado(v_pr, c_hoje) and (v_pr -> 'restricoes') @> '[{"tipo": "sinal"}]'::jsonb
      and (public._agenda_classe_agora(v_vera, c_hoje) - 'pront') = (pg_temp.classe_antes(v_pr, public.agenda_meios_da_os(v_vera, c_hoje), c_hoje) - 'pront')
      and v_a like '2:pronta:% | marca',
      v_a);
    update public.service_orders set quote_status = 'awaiting_deposit' where id = v_vera;
    v_pr := public.os_prontidao(v_vera, c_hoje);
    v_b := pg_temp.classe(v_vera) || ' | ' || pg_temp.motor(v_vera);
    v_res := pg_temp.ok(v_res, 'S4b e com a OS em quote_status awaiting_deposit (status aberta: não é orçamento): continua não parada, a mesma classe, e o motor marca',
      not public._agenda_sinal_parado(v_pr, c_hoje) and not (v_pr ->> 'eh_orcamento')::boolean and v_pr ->> 'quote_status' = 'awaiting_deposit'
      and v_b = v_a,
      v_b);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S5. Sem audit_log: aprovada_em ──
  begin
    perform pg_temp.fixtures();
    perform pg_temp.modos('ligado');
    v_mp := pg_temp.os('ORÇ-00095');
    v_pr := public.os_prontidao(v_mp, c_hoje);
    perform pg_temp.chave(49);
    v_a := public._agenda_sinal_parado(v_pr, c_hoje)::text || ' ' || pg_temp.classe(v_mp);
    perform pg_temp.chave(50);
    v_b := public._agenda_sinal_parado(v_pr, c_hoje)::text || ' ' || pg_temp.classe(v_mp);
    v_res := pg_temp.ok(v_res, 'S5a sem linha em audit_log, a idade conta de aprovada_em (09/09: 50 dias em 29/10): com 49, parado (classe 4 sinal); com 50, não (a borda é "mais de"), a classe de antes',
      v_pr ->> 'aprovada_em' = '2026-09-09' and not exists (select 1 from public.audit_log a where a.record_id = v_mp)
      and v_a = 'true 4:sinal:esperando o sinal'
      and v_b = 'false ' || concat_ws(':', pg_temp.classe_antes(v_pr, public.agenda_meios_da_os(v_mp, c_hoje), c_hoje) ->> 'classe',
                                         pg_temp.classe_antes(v_pr, public.agenda_meios_da_os(v_mp, c_hoje), c_hoje) ->> 'motivo',
                                         pg_temp.classe_antes(v_pr, public.agenda_meios_da_os(v_mp, c_hoje), c_hoje) ->> 'texto'),
      '49: ' || v_a || ' | 50: ' || v_b);
    perform pg_temp.chave(1);
    v_a := public._agenda_sinal_parado(v_pr - 'aprovada_em', c_hoje)::text;
    v_b := public._agenda_sinal_parado(v_pr - 'eh_orcamento', c_hoje)::text || ' ' || public._agenda_sinal_parado(v_pr - 'quote_status', c_hoje)::text;
    v_res := pg_temp.ok(v_res, 'S5b sem aprovada_em (e sem audit_log) a idade é 0 (de hoje): não parado nem com a chave em 1; sem eh_orcamento ou sem quote_status, também não',
      v_a = 'false' and v_b = 'false false', 'sem aprovada_em: ' || v_a || ' | sem eh_orcamento, sem quote_status: ' || v_b);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
