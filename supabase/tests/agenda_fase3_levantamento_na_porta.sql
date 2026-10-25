-- Prova do D11 na porta, Agenda de Produção Fase 3 (pacote P7b; migration 20261026100700): concluir exige o levantamento
-- respondido nos serviços marcados "exige levantamento" em TODO caminho — a tela (formulário, lista rápida, kanbans), a
-- assinatura do cliente, o gestor pela palavra do técnico (equipe), o dono (palavra, conversa), o assistente e a entrega que
-- conclui junto —, com a frase do formulário, a que o dono já conhece (NOVO-agenda-24).
-- bancada: depende de 20261026100700
--
-- Sobre a carteira da Fase 3 (scripts/bancada-agenda/fixture-fase3.sql: qui 29/10/2026; Lenine OS-00074 com a linha
-- "Revisão do sistema elétrico", sem sinal, condição 50% + 50%; Vanderlei OS-00069 só com "Instalação de carregador DC-DC";
-- Robson ORÇ-00083, orçamento, com "Instalação de claraboia"):
--   C  a cópia: o corpo da porta é o de 20261026100600 fora do bloco "-- FASE 3 (P7b):" (sempre que a bancada passa a
--      migration como texto; fora dela, PULADO)
--   F  a frase do formulário (sempre)
--   L  os caminhos (só com a fixture): a tela com login (o administrador e o técnico da OS), a assinatura (service_role, sem
--      autor), o gestor (equipe) e o dono por os_registrar_marco, o assistente, a entrega que concluiria junto, o orçamento
--      que converteria e concluiria (a conversão também não fica) — todos recusam com a frase e nada muda (status, saída,
--      entrega, cobranças, ações, número); a conversão sozinha continua; com o levantamento fechado conclui; a OS sem serviço
--      que exige levantamento conclui; faturar a concluída não olha o levantamento; a lista rápida continua oferecendo
--      "Concluída" (o levantamento é dado: a porta decide na hora)
--   J  portas: a porta para authenticated e service_role (anon não), definer com search_path fixo; o espelho do D11 continua
--      só service_role (sempre)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100700
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_levantamento_na_porta.sql
--   Sem a fixture (produção) os cenários e a cópia saem PULADO e só F e J rodam. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- O Supabase roda em UTC (o gatilho do vencimento "na entrega" usa o fuso da sessão). A bancada fica igual.
set local timezone = 'UTC';
select set_config('agenda.hoje', '2026-10-29', true);

create function pg_temp.ok(p_nome text, p_ok boolean, p_detalhe text default null) returns void language sql as $f$
  insert into _resultado values (p_nome, coalesce(p_ok, false), case when not coalesce(p_ok, false) then p_detalhe end)
$f$;
-- Dentro das subtransações desfeitas o resultado vai num jsonb (a linha em _resultado seria desfeita junto) e é gravado no fim.
create function pg_temp.res(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false),
                                                      case when not coalesce(p_ok, false) then p_detalhe end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
-- Executa p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou o erro.
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
-- O que a conclusão mexe numa OS: status, número, saída, entrega, conversão, cobranças vivas e ações da agenda.
create function pg_temp.estado(p_os uuid) returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'status', so.status, 'numero', so.service_order_number, 'saida', so.check_out_at, 'entrega', so.delivered_at,
    'convertida', so.converted_to_os_at,
    'n_rec', (select count(*) from public.receivables r where r.service_order_id = so.id and r.status <> 'cancelled'),
    'n_acoes', (select count(*) from public.agenda_acoes a where a.service_order_id = so.id))
    from public.service_orders so where so.id = p_os
$f$;

-- ── F. A frase do formulário (sempre) ───────────────────────────────────────────────────────────────────
select pg_temp.ok('F1 a frase do D11 é a do formulário (ServiceOrderForm: "Para concluir, responda o levantamento de: …")',
  public._os_texto_do_levantamento(array['Revisão do sistema elétrico', 'Instalação de claraboia'])
  = 'Para concluir, responda o levantamento de: Revisão do sistema elétrico, Instalação de claraboia. Esses serviços estão marcados como "exige levantamento".',
  public._os_texto_do_levantamento(array['Revisão do sistema elétrico', 'Instalação de claraboia']));

-- ── C. A cópia: fora do bloco "-- FASE 3 (P7b):", o corpo de 20261026100600 ──────────────────────────────
do $copia$
declare
  v_mig   text := current_setting('agenda_teste.mig_telas_fase3', true);
  v_ini   int;
  v_fim   int;
  v_corpo text;
  v_novo  text := (select p.prosrc from pg_proc p
                    where p.pronamespace = 'public'::regnamespace and p.proname = 'os_transicionar_status');
  v_bloco text;
begin
  if coalesce(v_mig, '') = '' then
    insert into _resultado values ('C1 a cópia da porta só muda no bloco "-- FASE 3 (P7b):"', true,
      'PULADO: sem agenda_teste.mig_telas_fase3 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_ini := position('create or replace function public.os_transicionar_status(' in v_mig);
  v_corpo := substr(v_mig, v_ini);
  v_corpo := substr(v_corpo, position(E'as $function$\n' in v_corpo) + length(E'as $function$'));
  v_corpo := left(v_corpo, position(E'\n$function$;' in v_corpo));
  v_novo := replace(v_novo, E'\r\n', E'\n');
  v_ini := position('    -- FASE 3 (P7b): ' in v_novo);
  v_fim := position(E'    -- FASE 3 (P7b): fim\n' in v_novo);
  v_bloco := case when v_ini > 0 and v_fim > v_ini then substr(v_novo, v_ini, v_fim + length(E'    -- FASE 3 (P7b): fim\n') - v_ini) end;
  insert into _resultado values ('C1 a cópia da porta só muda no bloco "-- FASE 3 (P7b):" (o resto é o corpo de 20261026100600)',
    v_bloco is not null and replace(v_novo, v_bloco, '') = v_corpo,
    case when v_bloco is null then 'o bloco "-- FASE 3 (P7b):" não está na porta'
         when replace(v_novo, v_bloco, '') <> v_corpo
           then format('%s × %s caracteres', length(replace(v_novo, v_bloco, '')), length(v_corpo)) end);
  insert into _resultado values ('C2 o bloco é o D11 na conclusão: o espelho do formulário e a frase dele, uma vez cada',
    v_bloco is not null
    and (length(v_bloco) - length(replace(v_bloco, '_os_levantamentos_pendentes(', ''))) / length('_os_levantamentos_pendentes(') = 2
    and (length(v_bloco) - length(replace(v_bloco, '_os_texto_do_levantamento(', ''))) / length('_os_texto_do_levantamento(') = 1
    and position(E'  if v_para = ''completed'' then\n    -- FASE 3 (P7b): ' in v_novo) > 0,
    case when v_bloco is null then 'o bloco "-- FASE 3 (P7b):" não está na porta' end);
end
$copia$;

-- ── L. Os caminhos (só com a fixture) ───────────────────────────────────────────────────────────────────
do $l$
declare
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec    constant uuid := 'aa000000-0000-4000-8000-0000000000f7';
  c_lenine constant uuid := '05000000-0000-4000-8000-000000000074';
  c_vand   constant uuid := '05000000-0000-4000-8000-000000000069';
  c_robson constant uuid := '05000000-0000-4000-8000-000000000083';
  c_revisao   constant uuid := '5e000000-0000-4000-8000-000000000003';
  c_claraboia constant uuid := '5e000000-0000-4000-8000-000000000007';
  d29      constant date := date '2026-10-29';
  c_agora  constant timestamptz := timestamptz '2026-10-29 16:30-03';
  c_frase  constant text :=
    'Para concluir, responda o levantamento de: Revisão do sistema elétrico. Esses serviços estão marcados como "exige levantamento".';
  c_frase_robson constant text :=
    'Para concluir, responda o levantamento de: Instalação de claraboia. Esses serviços estão marcados como "exige levantamento".';
  v_antes  jsonb;
  v_antes2 jsonb;
  r        jsonb;
  v_txt    text;
  v_ids    text;
  v_res    jsonb := '[]'::jsonb;
  -- a chamada da tela (useUpdateServiceOrderStatus: via tela, p_check_out nulo), como texto para o pg_temp.como
  c_tela   constant text := $q$select public.os_transicionar_status(%L, 'completed', 'tela', null, null, null, %L, %L, null)::text$q$;
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('L0 os caminhos (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase3');
  -- O técnico ativo da OS do Lenine (o Roberto da fixture tem login inativo).
  insert into public.app_users (id, full_name, email, role, active)
  values (c_tec, 'Técnico P7b', 'tecnico-p7b@bancada.invalid', 'technician', true);
  insert into public.service_order_technicians (service_order_id, user_id) values (c_lenine, c_tec);
  -- O D11: a revisão do sistema elétrico (Lenine) e a claraboia (Robson) passam a exigir levantamento.
  update public.services set requires_survey = true where id in (c_revisao, c_claraboia);

  -- L1–L7: cada caminho recusa com a frase e nada muda.
  begin
    v_antes := pg_temp.estado(c_lenine);

    r := pg_temp.como(c_admin, 'authenticated', format(c_tela, c_lenine, d29, c_agora))::jsonb;
    v_res := pg_temp.res(v_res, 'L1 a tela (o administrador com login: formulário, lista rápida, kanbans): a frase do formulário, nada muda',
      not (r ->> 'ok')::boolean and not (r ->> 'mudou')::boolean and r ->> 'texto' = c_frase and r ->> 'para' = r ->> 'de'
      and pg_temp.estado(c_lenine) = v_antes, r::text);

    r := pg_temp.como(c_tec, 'authenticated', format(c_tela, c_lenine, d29, c_agora))::jsonb;
    v_res := pg_temp.res(v_res, 'L2 o técnico da OS pela tela (ele pode concluir): a frase do levantamento, não o 42501; nada muda',
      not (r ->> 'ok')::boolean and r ->> 'texto' = c_frase and pg_temp.estado(c_lenine) = v_antes, r::text);

    r := pg_temp.como(null, 'service_role',
      format($q$select public.os_transicionar_status(%L, 'completed', 'assinatura', null, null, null, %L, %L, null)::text$q$,
             c_lenine, d29, c_agora))::jsonb;
    v_res := pg_temp.res(v_res, 'L3 a assinatura do cliente (service_role, sem autor): a frase, nada muda (o submit-signature só registra a recusa)',
      not (r ->> 'ok')::boolean and r ->> 'texto' = c_frase and pg_temp.estado(c_lenine) = v_antes, r::text);

    r := public.os_registrar_marco(c_lenine, 'conclusao', 'equipe', null, null, 'O Roberto disse que terminou: "terminei"',
                                   d29, c_agora);
    v_res := pg_temp.res(v_res, 'L4 o gestor pela palavra do técnico (os_registrar_marco, via equipe): a frase, nada muda (a rotina pergunta ao dono com ela)',
      not (r ->> 'ok')::boolean and r ->> 'texto' = c_frase and pg_temp.estado(c_lenine) = v_antes, r::text);

    r := public.os_registrar_marco(c_lenine, 'conclusao', 'dono', null, c_admin, 'concluiu Lenine', d29, c_agora);
    v_res := pg_temp.res(v_res, 'L5 o dono (os_registrar_marco, via dono: a palavra e o *grava*): a frase, nada muda',
      not (r ->> 'ok')::boolean and r ->> 'texto' = c_frase and pg_temp.estado(c_lenine) = v_antes, r::text);

    r := public.os_transicionar_status(c_lenine, 'completed', 'assistente', null, c_admin, null, d29, c_agora, null);
    v_res := pg_temp.res(v_res, 'L6 o assistente (via assistente, com quem pediu): a frase, nada muda',
      not (r ->> 'ok')::boolean and r ->> 'texto' = c_frase and pg_temp.estado(c_lenine) = v_antes, r::text);

    r := public.os_registrar_marco(c_lenine, 'entrega', 'tela', null, c_admin, null, d29, c_agora);
    v_res := pg_temp.res(v_res, 'L7 a entrega de uma OS ainda aberta (conclui antes, pela porta): a frase, nem conclusão nem entrega',
      not (r ->> 'ok')::boolean and r ->> 'texto' = c_frase and pg_temp.estado(c_lenine) = v_antes
      and pg_temp.estado(c_lenine) ->> 'entrega' is null, r::text);

    -- L8: o orçamento que converteria e concluiria na mesma chamada — a conversão também não fica; a conversão sozinha segue.
    v_antes2 := pg_temp.estado(c_robson);
    r := public.os_transicionar_status(c_robson, 'completed', 'tela', null, c_admin, null, d29, c_agora, null);
    v_res := pg_temp.res(v_res, 'L8 o orçamento → concluída (converteria e concluiria): a frase; continua orçamento, ORÇ-00083, sem conversão nem ação',
      not (r ->> 'ok')::boolean and r ->> 'texto' = c_frase_robson
      and pg_temp.estado(c_robson) = v_antes2 and v_antes2 ->> 'status' = 'draft' and v_antes2 ->> 'numero' = 'ORÇ-00083', r::text);
    r := public.os_transicionar_status(c_robson, 'approved', 'tela', null, c_admin, null, d29, c_agora, null);
    v_res := pg_temp.res(v_res, 'L9 a conversão sozinha (orçamento → aprovada) não olha o levantamento: vira OS-00083',
      (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and pg_temp.estado(c_robson) ->> 'numero' = 'OS-00083'
      and pg_temp.estado(c_robson) ->> 'status' = 'approved', r::text);

    -- L10: a lista rápida continua oferecendo "Concluída" (o levantamento é dado; a porta decide na hora e o aviso traz a frase).
    v_ids := quote_literal(array[c_lenine]::text) || '::uuid[]';
    r := pg_temp.como(c_admin, 'authenticated', format('select public.os_status_da_tela(%s)::text', v_ids))::jsonb;
    v_res := pg_temp.res(v_res, 'L10 os_status_da_tela ainda oferece "Concluída" ao Lenine (a recusa vem da porta, com a frase)',
      r -> c_lenine::text ? 'completed', r::text);

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- L11: com o levantamento fechado, conclui pela tela (as duas cobranças e a saída); faturar depois não olha o levantamento.
  begin
    insert into public.service_surveys (service_order_id, service_id, trigger_reason, status)
    values (c_lenine, c_revisao, 'TESTE P7b', 'closed');
    r := pg_temp.como(c_admin, 'authenticated', format(c_tela, c_lenine, d29, c_agora))::jsonb;
    v_res := pg_temp.res(v_res, 'L11 com o levantamento fechado, a tela conclui: as duas cobranças e a saída',
      (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and pg_temp.estado(c_lenine) ->> 'status' = 'completed'
      and (pg_temp.estado(c_lenine) ->> 'n_rec')::int = 2 and pg_temp.estado(c_lenine) ->> 'saida' is not null, r::text);
    update public.service_surveys set status = 'sent' where service_order_id = c_lenine and trigger_reason = 'TESTE P7b';
    r := public.os_transicionar_status(c_lenine, 'invoiced', 'tela', null, c_admin, null, d29, c_agora, null);
    v_res := pg_temp.res(v_res, 'L12 faturar a concluída (levantamento reaberto depois) não olha o levantamento: faturada',
      (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and pg_temp.estado(c_lenine) ->> 'status' = 'invoiced', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- L13: a OS sem serviço que exige levantamento conclui como antes (o Vanderlei: só o carregador DC-DC).
  begin
    r := public.os_transicionar_status(c_vand, 'completed', 'tela', null, c_admin, null, d29, c_agora, null);
    v_res := pg_temp.res(v_res, 'L13 o Vanderlei (sem serviço que exige levantamento) conclui como antes, com o texto da porta',
      (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and pg_temp.estado(c_vand) ->> 'status' = 'completed'
      and r ->> 'texto' like 'Vanderlei (OS-00069): concluída — saída qui 29/10 16:30. As cobranças já existiam%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$l$;

-- ── J. Portas (sempre) ──────────────────────────────────────────────────────────────────────────────────
select pg_temp.ok('J1 a porta: authenticated e service_role executam; anon não',
  has_function_privilege('authenticated', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)', 'execute')
  and has_function_privilege('service_role', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)', 'execute')
  and not has_function_privilege('anon', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz, timestamptz)', 'execute'));
select pg_temp.ok('J2 o espelho do D11 continua só service_role (a porta, definer, o chama como dona)',
  not has_function_privilege('authenticated', 'public._os_levantamentos_pendentes(uuid)', 'execute')
  and not has_function_privilege('anon', 'public._os_levantamentos_pendentes(uuid)', 'execute')
  and has_function_privilege('service_role', 'public._os_levantamentos_pendentes(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public._os_texto_do_levantamento(text[])', 'execute')
  and not has_function_privilege('anon', 'public._os_texto_do_levantamento(text[])', 'execute'));
select pg_temp.ok('J3 a porta continua security definer com search_path fixo e uma só (a de 9 argumentos)',
  (select count(*) = 1 and bool_and(p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=%')
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'os_transicionar_status'));

select teste, ok, detalhe from _resultado order by teste;

rollback;
