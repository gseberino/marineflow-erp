-- Prova do envio ao cliente da Agenda de Produção, Fase 5 (pacote P2): a janela, a hora com o intervalo, o teto, as três
-- travas da origem agenda-cliente (o enfileirar, o gatilho da fila e o pode_sair do worker), a revalidação na saída, o
-- gatilho do envio (o que foi dito ao cliente) e o D9 (migration 20261028100200).
-- bancada: depende de 20261028100200
--
--   E0  portas: o pode_sair só para service_role; o registro, as travas, os passos e o gatilho para ninguém de fora (nem o
--       service_role); as leituras para authenticated e service_role; security definer só onde precisa; search_path fixo;
--       os gatilhos novos da fila (2 só para agenda-cliente; o do envio, AFTER, para agenda-cliente e agenda-confirmacao);
--       desligado = nada registrado
--   E1  a janela (seg 07:59 não, 08:00 sim, 18:59 sim, 19:00 não; sáb 12:59 sim, 13:00 não; domingo; Finados; o dia dela) e
--       o fim da janela de cada validade
--   E2  _agenda_cliente_quando: pula domingo e feriado; o intervalo de 30 a 60 s determinístico; a cadeia; empurra para o
--       próximo dia de janela; a própria mensagem não conta
--   E3  o registro e a ordem das recusas do enfileirar (uma por motivo): sombra, o tipo fora das ondas, desligado, a
--       aprovação (pedida, a do dono, a crítica, segurada, o tipo liberado em 3 dias), opt-out, sem conversa, sem telefone,
--       a revalidação, domingo/feriado/janela, o texto proibido
--   E4  o teto por cliente (a 2ª no dia; a 4ª na semana ISO; a da semana seguinte sai), o total do dia, o aviso que não cabe
--       vira pergunta crítica (d13), o intervalo
--   E5  a trava da fila: a linha por fora, sem registro, em teste, já decidida, sem aprovação, com outro texto, outra chave,
--       outro telefone, com o modo ou o tipo fora de ligado, fora da janela (e a última tentativa), domingo, feriado, acima
--       do teto, perto demais de outra, que a revalidação recusa; a linha não muda de texto nem de telefone; a nova tentativa
--       fora da janela falha, volta à hora e a mensagem fica recusada; as outras origens não mudam
--   E6  a revalidação: cada motivo (inclusive a véspera com a OS aguardando peça = status); a 1ª mensagem e o dia do envio
--       guardados não deixam a outra "desatualizada" à toa; a hora que mudou de dia deixa
--   E7  agenda_cliente_pode_sair: só service_role; pode; janela, modo, tipo, vencida, revalidação; a linha de outra origem
--   E8  o envio (sent): enviada, o prometido, a ação que conta no fechamento, uma vez; sem data não promete; o botão antigo
--       (agenda-confirmacao) grava o prometido; a linha de os_planejamento só com o prometido não muda a prontidão; o erro
--       no prometido não derruba o envio (vai a app_error_logs)
--   E9  D9: o botão com a OS aprovada e o plano (fora de ligado, como hoje); aguardando peça recusa; sem dia no plano recusa;
--       sem o plano ligado, a regra de 30/09; em ligado registra pela agenda (aprovada, sai na hora da janela; o pedido conta
--       do envio); a confirmação fora das ondas = como hoje; a recusa vira o erro com o motivo; o "sim" fixa as alocações
--   E9z as cópias de pedir_confirmacao_do_agendamento e registrar_confirmacao_do_cliente só mudam nos blocos "-- FASE 5:"
--       (e, no registrar, nas 3 linhas listadas)
--   E10 wa_test_mode: vai ao número de teste; sem ele, sem_telefone
--   E11 o passo "fila": a fila velha (janela), o modo e o tipo que saíram, a revalidação, o que é hora de mandar, a validade
--       que vence a aprovação (e a pergunta), a conversa viva (d19), e roda até desligado
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase5_envio.sql
--   E0 e E9z rodam em qualquer lugar (E9z só com as migrations antigas como texto); o resto só na bancada (a
--   fixture-fase5; fora dela, PULADO). Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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

create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text; v_det text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text, v_det = pg_exception_detail;
  return v_estado || ' ' || v_msg || coalesce(' [' || nullif(v_det, '') || ']', '');
end $f$;

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

-- A hora de Brasília escrita como se fala: pg_temp.em('2026-10-30 10:00') = timestamptz '2026-10-30 10:00-03'.
create function pg_temp.em(p_quando text) returns timestamptz language sql immutable as $f$
  select (p_quando::timestamp) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.hora(p_t timestamptz) returns text language sql immutable as $f$
  select to_char(p_t at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI:SS')
$f$;

-- Liga a mensagem ao cliente (todos os tipos, ou os dados) e a aprovação dos primeiros dias (0 = sem aprovação).
create function pg_temp.ligar(p_tipos text[] default null, p_aprov int default 0) returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = p_aprov,
         cliente_tipos_ligados = coalesce(p_tipos, array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento',
                                                          'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                                                          'pos_servico', 'mudanca_no_dia'])
   where id
$f$;

-- O registro (a rodada, salvo dito), com a hora alvo e o agora de Brasília.
create function pg_temp.reg(p_tipo text, p_var text, p_os uuid, p_dia date, p_dados jsonb, p_alvo text, p_agora text,
                            p_origem text default 'rodada', p_critica text default null, p_valida text default null)
returns jsonb language sql as $f$
  select public._agenda_cliente_registrar(p_tipo, p_var, p_os, p_dia, p_dados, pg_temp.em(p_alvo),
                                          case when p_valida is null then null else pg_temp.em(p_valida) end, p_origem,
                                          p_critica, pg_temp.em(p_agora), 'aa000000-0000-4000-8000-000000000001')
$f$;

-- Uma mensagem registrada direto (o que o passo teria gravado), para provar a trava e o enfileirar sozinhos.
create function pg_temp.direta(p_chave text, p_enviar text, p_cliente uuid default 'c1000000-0000-4000-8000-000000000012',
                               p_os uuid default '05000000-0000-4000-8000-000000000122', p_tipo text default 'andamento',
                               p_estado text default 'registrada', p_modo text default 'ligado')
returns uuid language sql as $f$
  insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, variante, origem, modo, texto, enviar_em,
                                               valida_ate, aprovacao, estado, recusa_motivo, dedupe_key, enviada_em, fila_id)
  values (p_cliente, p_os, p_tipo, case when p_tipo = 'andamento' then 'semanal' end, 'rodada', p_modo, 'mensagem de teste (AG5E)',
          pg_temp.em(p_enviar), pg_temp.em(p_enviar) + interval '9 hours', 'livre', p_estado,
          case when p_estado = 'recusada' then 'janela' end, p_chave,
          case when p_estado in ('enviada', 'respondida', 'sem_resposta') then pg_temp.em(p_enviar) end,
          case when p_estado = 'enfileirada' then gen_random_uuid() end)
  returning id
$f$;

create function pg_temp.msg(p_id uuid) returns jsonb language sql stable as $f$
  select to_jsonb(m) - 'base' - 'texto' from public.agenda_cliente_mensagens m where m.id = p_id
$f$;
create function pg_temp.n_fila() returns int language sql stable as $f$
  select count(*)::int from public.whatsapp_send_queue q where q.source = 'agenda-cliente'
$f$;
create function pg_temp.fila_de(p_msg uuid) returns jsonb language sql stable as $f$
  select to_jsonb(q) from public.whatsapp_send_queue q where q.source = 'agenda-cliente' and q.source_ref_id = p_msg
$f$;
-- Uma mensagem do WhatsApp (o que o webhook grava).
create function pg_temp.wa(p_fone text, p_dir text, p_em text) returns void language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status)
  values (p_dir, p_fone, 'text', 'mensagem de teste (AG5E)', pg_temp.em(p_em), case when p_dir = 'inbound' then 'received' else 'read' end)
$f$;
-- O corpo de uma função com corpo $$ numa migration antiga (entre "as $$" e "$$;").
create function pg_temp.corpo_dd(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $$\n' in v) + length(E'\nas $$'));
  return left(v, position(E'\n$$;' in v));
end $f$;
-- O corpo sem os blocos "-- FASE 5: … -- FASE 5: fim" (linhas).
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

-- ── E0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
do $e0$
declare
  v_res jsonb := '[]'::jsonb;
  f text;
  v_ninguem text[] := array[
    'public._agenda_cliente_quando(integer, timestamptz, timestamptz, uuid)',
    'public._agenda_cliente_conversou(uuid, timestamptz)', 'public._agenda_cliente_sem_mensagem(uuid)',
    'public._agenda_cliente_no_periodo(uuid, date, date, uuid)', 'public._agenda_cliente_dia_a_confirmar(uuid, timestamptz)',
    'public._agenda_cliente_texto_do_aviso(text, text, uuid, jsonb, date)',
    'public._agenda_cliente_perguntar(text, text, uuid, date, date, text, text, timestamptz, timestamptz)',
    'public._agenda_cliente_revalidar(uuid, timestamptz)', 'public._agenda_cliente_enfileirar(uuid, timestamptz)',
    'public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid)',
    'public._agenda_fila_do_cliente()', 'public._agenda_cliente_enviada()', 'public._agenda_cliente_fila(date, timestamptz)'];
  v_leitura text[] := array[
    'public._agenda_cliente_dia_de_janela(date)', 'public._agenda_cliente_fora_da_janela(timestamptz, timestamptz)',
    'public._agenda_cliente_fim_da_janela(date, integer)', 'public._agenda_cliente_tipo_liberado(text)',
    'public._agenda_cliente_tipo_texto(text)', 'public._agenda_cliente_quando_texto(timestamptz, timestamptz)',
    'public._agenda_cliente_o_que(text, date)'];
  v_definer text[] := array[
    'public._agenda_cliente_revalidar(uuid, timestamptz)', 'public.agenda_cliente_pode_sair(uuid, timestamptz)',
    'public._agenda_cliente_enfileirar(uuid, timestamptz)',
    'public._agenda_cliente_registrar(text, text, uuid, date, jsonb, timestamptz, timestamptz, text, text, timestamptz, uuid)',
    'public._agenda_fila_do_cliente()', 'public._agenda_cliente_enviada()',
    'public.pedir_confirmacao_do_agendamento(uuid, uuid)', 'public.registrar_confirmacao_do_cliente(text, text, uuid)'];
  v_ruins text := '';
  r jsonb;
begin
  v_res := pg_temp.ok(v_res, 'E0a o pode_sair do worker: só service_role',
    has_function_privilege('service_role', 'public.agenda_cliente_pode_sair(uuid, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_cliente_pode_sair(uuid, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_cliente_pode_sair(uuid, timestamptz)', 'execute')
    and pg_temp.como(null, 'authenticated', $q$select public.agenda_cliente_pode_sair(gen_random_uuid())::text$q$) like 'erro 42501:%');
  foreach f in array v_ninguem loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'E0b o registro, as travas, os passos, os gatilhos e as auxiliares: ninguém de fora (nem o service_role)',
    v_ruins = '', nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'E0c o service_role não registra nem enfileira direto (o único caminho até a fila é a agenda)',
    pg_temp.como(null, 'service_role', $q$select public._agenda_cliente_enfileirar(gen_random_uuid())::text$q$) like 'erro 42501:%'
    and pg_temp.como(null, 'service_role', $q$select public._agenda_cliente_registrar('pronto', null, gen_random_uuid(), null, '{}', now(), null, 'rodada')::text$q$) like 'erro 42501:%');
  v_ruins := '';
  foreach f in array v_leitura loop
    if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'E0d as leituras (a janela, a validade, o tipo liberado, os textos ao dono): authenticated e service_role, nunca anon',
    v_ruins = '', nullif(v_ruins, ''));
  v_ruins := '';
  foreach f in array v_definer loop
    if not (select p.prosecdef from pg_proc p where p.oid = f::regprocedure) then v_ruins := v_ruins || f || ' '; end if;
  end loop;
  foreach f in array v_ninguem || v_leitura loop
    if (select p.prosecdef from pg_proc p where p.oid = f::regprocedure) and not (f = any (v_definer)) then
      v_ruins := v_ruins || 'definer: ' || f || ' ';
    end if;
  end loop;
  foreach f in array v_definer || v_ninguem || v_leitura loop
    if coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = f::regprocedure), '') not like '%search_path=%' then
      v_ruins := v_ruins || 'sem search_path: ' || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'E0e security definer só a revalidação, o pode_sair, o enfileirar, o registro, os 2 gatilhos e o D9; search_path fixo em todas',
    v_ruins = '', nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'E0f os gatilhos da fila: a trava (INSERT e UPDATE de hora, texto, telefone, origem, ref, chave) só para agenda-cliente; o do envio AFTER UPDATE OF status, só as duas origens e só quando vira sent',
    (select count(*) from pg_trigger t where t.tgrelid = 'public.whatsapp_send_queue'::regclass and not t.tgisinternal
       and t.tgfoid = 'public._agenda_fila_do_cliente()'::regprocedure and pg_get_triggerdef(t.oid) like '%agenda-cliente%'
       and pg_get_triggerdef(t.oid) like '%BEFORE%') = 2
    and (select count(*) from pg_trigger t where t.tgrelid = 'public.whatsapp_send_queue'::regclass and not t.tgisinternal
           and t.tgfoid = 'public._agenda_cliente_enviada()'::regprocedure
           and pg_get_triggerdef(t.oid) like '%AFTER UPDATE OF status%' and pg_get_triggerdef(t.oid) like '%agenda-confirmacao%'
           and pg_get_triggerdef(t.oid) like '%''sent''%') = 1,
    (select string_agg(pg_get_triggerdef(t.oid), ' | ') from pg_trigger t
      where t.tgrelid = 'public.whatsapp_send_queue'::regclass
        and t.tgfoid in ('public._agenda_fila_do_cliente()'::regprocedure, 'public._agenda_cliente_enviada()'::regprocedure)));
  -- Desligado (a linha nasce assim): nada é registrado.
  begin
    update public.agenda_config set modo_cliente = 'desligado' where id;
    r := public._agenda_cliente_registrar('pronto', null, (select id from public.service_orders limit 1), null, '{}', now(), null, 'rodada');
    v_res := pg_temp.ok(v_res, 'E0g desligado: {criada: false}, nada gravado',
      r = '{"criada": false, "modo": "desligado"}'::jsonb and not exists (select 1 from public.agenda_cliente_mensagens), r::text);
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$e0$;

-- ── E1, E2, E3, E4, E10. A janela, a hora, o registro, o enfileirar e o teto (fixture-fase5) ────────────
do $e1$
declare
  v_res jsonb := '[]'::jsonb;
  c_fla  constant uuid := '05000000-0000-4000-8000-000000000104';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_nel  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_rob  constant uuid := '05000000-0000-4000-8000-000000000121';
  c_len  constant uuid := '05000000-0000-4000-8000-000000000074';
  c_dono_os constant uuid := '05000000-0000-4000-8000-000000000123';
  c_cli_luc constant uuid := 'c1000000-0000-4000-8000-000000000012';
  c_cli_nel constant uuid := 'c1000000-0000-4000-8000-000000000005';
  c_m6   constant jsonb := '{"peca_de": "2026-11-11", "peca_ate": "2026-11-11", "faixa_de": "2026-11-12", "faixa_ate": "2026-11-13"}';
  r jsonb; r2 jsonb; r3 jsonb;
  v_id uuid; v_id2 uuid;
  v_txt text;
  q jsonb;
  v_e text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('E1–E4, E10 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase5');
    perform set_config('agenda_teste.hoje', '2026-10-30', true);

    -- ── E1. A janela ──
    v_res := pg_temp.ok(v_res, 'E1a dia de janela: segunda a sábado sem feriado; domingo, Finados (02/11) e o 15/06 de Itajaí não',
      public._agenda_cliente_dia_de_janela('2026-11-09') and public._agenda_cliente_dia_de_janela('2026-11-07')
      and not public._agenda_cliente_dia_de_janela('2026-11-08') and not public._agenda_cliente_dia_de_janela('2026-11-02')
      and not public._agenda_cliente_dia_de_janela('2027-06-15') and not public._agenda_cliente_dia_de_janela(null));
    r := jsonb_build_object(
      'seg_0759', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-09 07:59'), pg_temp.em('2026-11-09 07:59:59')),
      'seg_0800', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-09 08:00'), pg_temp.em('2026-11-09 08:00')),
      'seg_1859', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-09 18:59'), pg_temp.em('2026-11-09 18:59:59')),
      'seg_1900', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-09 18:59'), pg_temp.em('2026-11-09 19:00')),
      'sab_1259', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-07 12:59'), pg_temp.em('2026-11-07 12:59:59')),
      'sab_1300', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-07 12:59'), pg_temp.em('2026-11-07 13:00')),
      'domingo', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-08 10:00'), pg_temp.em('2026-11-08 10:00')),
      'finados', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-02 10:00'), pg_temp.em('2026-11-02 10:00')),
      'outro_dia', public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-09 10:00'), pg_temp.em('2026-11-10 10:00')),
      'nulo', public._agenda_cliente_fora_da_janela(null, pg_temp.em('2026-11-10 10:00')));
    v_res := pg_temp.ok(v_res, 'E1b a janela: seg 07:59 não, 08:00 sim, 18:59 sim, 19:00 não; sáb 12:59 sim, 13:00 não; domingo; Finados = feriado; outro dia = janela',
      r = '{"seg_0759": "janela", "seg_0800": null, "seg_1859": null, "seg_1900": "janela", "sab_1259": null, "sab_1300": "janela",
            "domingo": "domingo", "finados": "feriado", "outro_dia": "janela", "nulo": "janela"}'::jsonb, r::text);
    r := jsonb_build_object(
      'sex_0', pg_temp.hora(public._agenda_cliente_fim_da_janela('2026-10-30', 0)),
      'sex_1', pg_temp.hora(public._agenda_cliente_fim_da_janela('2026-10-30', 1)),
      'sex_2', pg_temp.hora(public._agenda_cliente_fim_da_janela('2026-10-30', 2)),
      'dom_0', pg_temp.hora(public._agenda_cliente_fim_da_janela('2026-11-01', 0)));
    v_res := pg_temp.ok(v_res, 'E1c o fim da janela: o do dia (sex 19:00), do dia seguinte (sáb 13:00), do 3º dia de janela (ter 03/11: pula domingo e Finados); de um domingo, o do próximo dia de janela',
      r = '{"sex_0": "30/10 19:00:00", "sex_1": "31/10 13:00:00", "sex_2": "03/11 19:00:00", "dom_0": "03/11 19:00:00"}'::jsonb, r::text);
    begin
      update public.agenda_config set cliente_janela_fim = '18:00', cliente_sabado_fim = '12:00' where id;
      v_res := pg_temp.ok(v_res, 'E1d os horários são os do banco: com a janela até 18:00 (sáb 12:00), 18:00 e sáb 12:00 não saem; 17:59 sai',
        public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-09 10:00'), pg_temp.em('2026-11-09 18:00')) = 'janela'
        and public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-07 10:00'), pg_temp.em('2026-11-07 12:00')) = 'janela'
        and public._agenda_cliente_fora_da_janela(pg_temp.em('2026-11-09 10:00'), pg_temp.em('2026-11-09 17:59')) is null);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── E2. A hora (_agenda_cliente_quando) ──
    r := jsonb_build_object(
      'cedo', pg_temp.hora(public._agenda_cliente_quando(0, pg_temp.em('2026-10-30 07:00'), pg_temp.em('2026-10-30 06:00'))),
      'noite', pg_temp.hora(public._agenda_cliente_quando(0, pg_temp.em('2026-10-30 19:30'), pg_temp.em('2026-10-30 06:00'))),
      'sab_tarde', pg_temp.hora(public._agenda_cliente_quando(0, pg_temp.em('2026-10-31 13:10'), pg_temp.em('2026-10-30 06:00'))),
      'domingo', pg_temp.hora(public._agenda_cliente_quando(0, pg_temp.em('2026-11-01 10:00'), pg_temp.em('2026-10-30 06:00'))),
      'agora_depois', pg_temp.hora(public._agenda_cliente_quando(0, pg_temp.em('2026-10-30 10:00'), pg_temp.em('2026-10-30 10:20'))));
    v_res := pg_temp.ok(v_res, 'E2a sem outra marcada: antes da janela = 08:00; à noite = sáb 08:00; sáb depois das 13:00 e domingo = ter 03/11 08:00 (Finados pulado); o agora depois do alvo vale',
      r = '{"cedo": "30/10 08:00:00", "noite": "31/10 08:00:00", "sab_tarde": "03/11 08:00:00", "domingo": "03/11 08:00:00", "agora_depois": "30/10 10:20:00"}'::jsonb,
      r::text);
    begin
      perform pg_temp.ligar();
      v_id := pg_temp.direta('agenda-cliente:e2:1', '2026-10-30 09:00');
      r := jsonb_build_object(
        'h0', pg_temp.hora(public._agenda_cliente_quando(0, pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 08:00'))),
        'h15', pg_temp.hora(public._agenda_cliente_quando(15, pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 08:00'))),
        'h30', pg_temp.hora(public._agenda_cliente_quando(30, pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 08:00'))),
        'h31', pg_temp.hora(public._agenda_cliente_quando(31, pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 08:00'))),
        'hneg', pg_temp.hora(public._agenda_cliente_quando(-1, pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 08:00'))),
        'perto_antes', pg_temp.hora(public._agenda_cliente_quando(15, pg_temp.em('2026-10-30 08:59:40'), pg_temp.em('2026-10-30 08:00'))),
        'longe', pg_temp.hora(public._agenda_cliente_quando(15, pg_temp.em('2026-10-30 08:59:30'), pg_temp.em('2026-10-30 08:00'))),
        'ela_mesma', pg_temp.hora(public._agenda_cliente_quando(15, pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 08:00'), v_id)));
      v_res := pg_temp.ok(v_res, 'E2b o intervalo determinístico (d12): outra às 09:00 → 30 + (hash mod 31) s depois (30 a 60 s); o hash negativo também; a 30 s ou mais antes não conflita; a própria mensagem não conta',
        r = '{"h0": "30/10 09:00:30", "h15": "30/10 09:00:45", "h30": "30/10 09:01:00", "h31": "30/10 09:00:30", "hneg": "30/10 09:01:00",
              "perto_antes": "30/10 09:00:45", "longe": "30/10 08:59:30", "ela_mesma": "30/10 09:00:00"}'::jsonb, r::text);
      v_id2 := pg_temp.direta('agenda-cliente:e2:2', '2026-10-30 09:00:40');
      perform pg_temp.direta('agenda-cliente:e2:3', '2026-10-31 12:59:50');
      perform pg_temp.direta('agenda-cliente:e2:sombra', '2026-10-30 14:00', p_modo := 'sombra');
      r := jsonb_build_object(
        'cadeia', pg_temp.hora(public._agenda_cliente_quando(15, pg_temp.em('2026-10-30 09:00'), pg_temp.em('2026-10-30 08:00'))),
        'sab_fim', pg_temp.hora(public._agenda_cliente_quando(15, pg_temp.em('2026-10-31 12:59:40'), pg_temp.em('2026-10-30 08:00'))),
        'sombra', pg_temp.hora(public._agenda_cliente_quando(15, pg_temp.em('2026-10-30 14:00'), pg_temp.em('2026-10-30 08:00'))));
      v_res := pg_temp.ok(v_res, 'E2c a cadeia (09:00 e 09:00:40 → 09:01:25); perto do fim do sábado vai a ter 03/11 08:00; a mensagem em teste não ocupa lugar',
        r = '{"cadeia": "30/10 09:01:25", "sab_fim": "03/11 08:00:00", "sombra": "30/10 14:00:00"}'::jsonb, r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── E3. O registro e o enfileirar ──
    -- E3a ligado, livre: a Lucenira (OS concluída hoje, sem entrega): o M8 vai à fila na hora
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      q := pg_temp.fila_de((r ->> 'id')::uuid);
      v_txt := (select m.texto from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid);
      v_res := pg_temp.ok(v_res, 'E3a ligado, livre: enfileirada na hora — o telefone dela, o texto e a chave da mensagem, priority 5, 3 tentativas, às 10:00',
        r ->> 'estado' = 'enfileirada' and r ->> 'aprovacao' = 'livre' and r ->> 'modo' = 'ligado'
        and q ->> 'phone_normalized' = '5547900000312' and q ->> 'message' = v_txt and (q ->> 'priority')::int = 5
        and (q ->> 'max_attempts')::int = 3 and (q ->> 'scheduled_for')::timestamptz = pg_temp.em('2026-10-30 10:00')
        and q ->> 'dedupe_key' = 'agenda-cliente:pronto:' || c_luc || ':2026-10-30' and q ->> 'status' = 'pending'
        and v_txt = 'Olá, Lucenira! Aqui é o Gustavo, da HBR Marine Solutions. A troca das baterias está concluída. Quando fica bom para combinarmos a entrega?'
        and (select m.fila_id from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid) = (q ->> 'id')::uuid
        and (select m.base ->> 'primeira' from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid) = 'true',
        r::text || ' ' || coalesce(q::text, 'sem fila'));
      r2 := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:15');
      r3 := public._agenda_cliente_enfileirar((r ->> 'id')::uuid, pg_temp.em('2026-10-30 10:15'));
      v_res := pg_temp.ok(v_res, 'E3b idempotente: o mesmo registro devolve ja_existe; o enfileirar de novo devolve a mesma linha; a fila continua com uma',
        r2 ->> 'motivo' = 'ja_existe' and (r2 ->> 'id')::uuid = (r ->> 'id')::uuid and r3 ->> 'estado' = 'enfileirada'
        and (r3 ->> 'fila_id')::uuid = (q ->> 'id')::uuid and pg_temp.n_fila() = 1, r2::text || ' ' || r3::text);
      -- E3c a 1ª trava pela 2ª: a fila recusa a mesma mensagem de novo (já decidida)
      v_e := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id,
                                       scheduled_for, max_attempts, dedupe_key) values (%L, %L, 'agenda-cliente', %L, %L, 1, %L)$q$,
                                    q ->> 'phone_normalized', q ->> 'message', r ->> 'id', q ->> 'scheduled_for', 'agenda-cliente:outra'));
      v_res := pg_temp.ok(v_res, 'E3c a mesma mensagem na fila de novo, por fora: recusada (42501, já decidida)',
        v_e like '42501 A fila do cliente só aceita a mensagem que a agenda acabou de decidir mandar%' and pg_temp.n_fila() = 1, v_e);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- E3d em teste (sombra) e o tipo fora das ondas: só registrada, a chave :sombra, nada na fila; a ação "Em teste"
    begin
      update public.agenda_config set modo_cliente = 'sombra' where id;
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      perform pg_temp.ligar(array['confirmar']);
      r2 := pg_temp.reg('pos_servico', null, c_rob, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      v_res := pg_temp.ok(v_res, 'E3d sombra e o tipo fora das ondas em ligado: registrada em teste (chave :sombra), livre, nada na fila; a ação "Em teste: eu teria mandado…" (não executada)',
        r ->> 'modo' = 'sombra' and r ->> 'estado' = 'registrada' and r ->> 'aprovacao' = 'livre' and r2 ->> 'modo' = 'sombra'
        and (select m.dedupe_key from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid) like '%:sombra'
        and pg_temp.n_fila() = 0
        and (select a.texto from public.agenda_acoes a join public.agenda_cliente_mensagens m on m.acao_id = a.id
              where m.id = (r ->> 'id')::uuid and not a.executada and a.tipo = 'cliente')
            = 'Em teste: eu teria mandado ao Lucenira que o serviço ficou pronto (sairia agora).',
        (select string_agg(a.texto, ' | ') from public.agenda_acoes a where a.tipo = 'cliente'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- E3e a aprovação dos primeiros dias: pedida + a pergunta (o texto da §6.2); 3 dias aprovados liberam; o "segura" e a
    -- preparada pelo dono não contam; a do dono pede sempre; a crítica pergunta com 3 opções
    begin
      perform pg_temp.ligar(null, 3);
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      v_res := pg_temp.ok(v_res, 'E3e o tipo ainda não liberado: pedida, esperando o dono, a pergunta cliente_aprovar com o texto da mensagem; nada na fila',
        r ->> 'aprovacao' = 'pedida' and r ->> 'estado' = 'aguardando_dono' and pg_temp.n_fila() = 0
        and (select p.tipo || ' | ' || p.chave || ' | ' || p.texto || ' | ' || p.modo || ' | ' || pg_temp.hora(p.expira_em) || ' | ' || p.perda_em
               from public.agenda_perguntas p where p.id = (r ->> 'pergunta_id')::uuid)
            = 'cliente_aprovar | cliente_aprovar:' || (r ->> 'id') || ' | Mensagem para o Lucenira (ficou pronto), sai agora: "Olá, Lucenira! Aqui é o Gustavo, da HBR Marine Solutions. A troca das baterias está concluída. Quando fica bom para combinarmos a entrega?". *manda cliente Lucenira* ou *segura cliente Lucenira*. | ligado | 30/10 19:00:00 | 2026-10-30',
        (select p.texto from public.agenda_perguntas p where p.id = (r ->> 'pergunta_id')::uuid));
      -- 2 dias aprovados da rodada + 1 segurado + 1 da preparada pelo dono: ainda não
      insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                   aprovacao, aprovada_em, estado, recusa_motivo, dedupe_key, enviada_em)
      select c_cli_luc, c_luc, 'pronto', x.origem, 'ligado', 'mensagem de teste (AG5E)', x.em, x.em + interval '1 hour', x.aprov,
             x.em, case when x.aprov = 'aprovada' then 'enviada' else 'recusada' end,
             case when x.aprov = 'segurada' then 'segurada' end, 'agenda-cliente:e3e:' || x.n,
             case when x.aprov = 'aprovada' then x.em end
        from (values (1, 'rodada', 'aprovada', pg_temp.em('2026-09-01 10:00')), (2, 'rodada', 'aprovada', pg_temp.em('2026-09-02 10:00')),
                     (3, 'rodada', 'segurada', pg_temp.em('2026-09-03 10:00')), (4, 'dono', 'aprovada', pg_temp.em('2026-09-04 10:00')),
                     (5, 'rodada', 'aprovada', pg_temp.em('2026-09-02 15:00'))) x(n, origem, aprov, em);
      v_res := pg_temp.ok(v_res, 'E3f 2 dias distintos aprovados (o 2º com duas), 1 segurado e 1 preparado pelo dono: ainda não liberado; o 3º dia aprovado libera',
        not public._agenda_cliente_tipo_liberado('pronto'), null);
      insert into public.agenda_cliente_mensagens (client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                   aprovacao, aprovada_em, estado, dedupe_key, enviada_em)
      values (c_cli_luc, c_luc, 'pronto', 'rodada', 'ligado', 'mensagem de teste (AG5E)', pg_temp.em('2026-09-05 10:00'),
              pg_temp.em('2026-09-05 11:00'), 'aprovada', pg_temp.em('2026-09-05 10:00'), 'enviada', 'agenda-cliente:e3e:6',
              pg_temp.em('2026-09-05 10:00'));
      r2 := pg_temp.reg('pos_servico', null, c_rob, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      v_res := pg_temp.ok(v_res, 'E3g com 3 dias aprovados o tipo sai sozinho (livre); outro tipo (pós-serviço) continua pedindo',
        public._agenda_cliente_tipo_liberado('pronto') and r2 ->> 'aprovacao' = 'pedida' and not public._agenda_cliente_tipo_liberado('pos_servico'),
        r2::text);
      r3 := pg_temp.reg('pronto_lembrete', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00', 'dono');
      v_res := pg_temp.ok(v_res, 'E3h a preparada pelo dono pede sempre (pedida), com o texto "Pronto para o …" (sem assinatura: ela já recebeu em setembro; a hora longe das outras duas que esperam o dono)',
        r3 ->> 'aprovacao' = 'pedida'
        and (select p.texto from public.agenda_perguntas p where p.id = (r3 ->> 'pergunta_id')::uuid)
            = 'Pronto para o Lucenira, sai hoje às 10:01: "Lucenira, só para combinarmos a entrega da sua lancha: qual dia fica bom pra você?". Para mandar: *manda cliente Lucenira*.',
        (select p.texto from public.agenda_perguntas p where p.id = (r3 ->> 'pergunta_id')::uuid));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('pode_atrasar', 'peca', c_nel, date '2026-11-12', c_m6, '2026-10-30 10:00', '2026-10-30 10:00', 'rodada', 'segundo_atraso');
      v_res := pg_temp.ok(v_res, 'E3i a crítica (2º atraso): esperando o dono, a pergunta cliente_aviso crítica com 3 opções e a recomendação 1; nada na fila',
        r ->> 'aprovacao' = 'critica' and r ->> 'estado' = 'aguardando_dono' and pg_temp.n_fila() = 0
        and (select p.critica and p.tipo = 'cliente_aviso' and p.recomendacao = 1 and jsonb_array_length(p.opcoes) = 3
                    and p.chave = 'cliente_aviso:' || c_nel || ':2026-11-12'
                    and p.texto = 'O serviço no seu veleiro do Nelson vai atrasar de novo (qui 05/11 → qui 12 e sex 13/11). É o 2º atraso: recomendo você ligar. 1) Você liga e eu não mando nada (recomendo); 2) Eu mando o aviso escrito; 3) Não aviso agora.'
               from public.agenda_perguntas p where p.id = (r ->> 'pergunta_id')::uuid),
        (select p.texto from public.agenda_perguntas p where p.id = (r ->> 'pergunta_id')::uuid));
      -- o segurado (a resposta do dono): o enfileirar recusa
      v_id := pg_temp.direta('agenda-cliente:e3:seg', '2026-10-30 10:00');
      update public.agenda_cliente_mensagens set aprovacao = 'segurada', aprovada_em = pg_temp.em('2026-10-30 09:30') where id = v_id;
      r2 := public._agenda_cliente_enfileirar(v_id, pg_temp.em('2026-10-30 10:00'));
      v_res := pg_temp.ok(v_res, 'E3j a segurada pelo dono não sai (recusada/segurada)', r2 = '{"estado": "recusada", "motivo": "segurada"}'::jsonb, r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- E3k o canal: opt-out, número bloqueado, cadastro inativo, sem conversa, sem telefone (cada um no seu teste)
    begin
      perform pg_temp.ligar();
      r := jsonb_build_object();
      begin
        update public.clients set opt_out_whatsapp = true where id = c_cli_luc;
        r := r || jsonb_build_object('opt_out', pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00') ->> 'motivo');
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      begin
        insert into public.whatsapp_blocked_numbers (phone_normalized, reason) values ('47900000312', 'pediu');
        r := r || jsonb_build_object('bloqueado', pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00') ->> 'motivo');
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      begin
        update public.clients set active = false where id = c_cli_luc;
        r := r || jsonb_build_object('inativo', pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00') ->> 'motivo');
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      begin
        delete from public.whatsapp_messages where phone_normalized = '5547900000312';
        perform pg_temp.wa('5547900000312', 'outbound', '2026-10-29 10:00');
        perform pg_temp.wa('5547900000312', 'inbound', '2025-10-29 10:00');
        r := r || jsonb_build_object('sem_conversa', pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00') ->> 'motivo');
        update public.agenda_config set cliente_conversa_dias = 0 where id;
        r := r || jsonb_build_object('conversa_0', pg_temp.reg('pronto_lembrete', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00') ->> 'estado');
        raise exception 'desfaz' using errcode = 'P0097';
      exception when sqlstate 'P0097' then null;
      end;
      -- o Lenine (sem número) e o dono como cliente (o número dele é o do login): sem_telefone
      perform pg_temp.wa('5547900000210', 'inbound', '2026-10-29 10:00');
      r := r || jsonb_build_object(
        'lenine', pg_temp.reg('confirmar', 'unico', c_len, date '2026-11-06', '{"primeira": false}', '2026-10-30 10:00', '2026-10-30 10:00') ->> 'motivo',
        'dono', pg_temp.reg('pos_servico', null, c_dono_os, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00') ->> 'motivo');
      v_res := pg_temp.ok(v_res, 'E3k o canal: opt-out, número bloqueado e cadastro inativo = opt_out; só a HBR escreveu ou a dele tem mais de um ano = sem_conversa (0 dias = sem exigência); o Lenine (sem número) e o dono (o número do login) = sem_telefone; nada na fila',
        r = '{"opt_out": "opt_out", "bloqueado": "opt_out", "inativo": "opt_out", "sem_conversa": "sem_conversa", "conversa_0": "enfileirada",
              "lenine": "sem_telefone", "dono": "sem_telefone"}'::jsonb and pg_temp.n_fila() = 0, r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- E3l domingo, feriado e a janela (a hora posta à mão nesses dias numa mensagem que vale; quem marca nunca a põe lá)
    begin
      perform pg_temp.ligar();
      r := '{}'::jsonb;
      for v_txt, q in select * from (values ('domingo', '{"em": "2026-11-01 10:00", "agora": "2026-11-01 10:00"}'::jsonb),
                                            ('feriado', '{"em": "2026-11-02 10:00", "agora": "2026-11-02 10:00"}'),
                                            ('ontem', '{"em": "2026-10-29 10:00", "agora": "2026-10-30 10:00"}'),
                                            ('noite', '{"em": "2026-10-30 10:00", "agora": "2026-10-30 19:10"}')) x loop
        begin
          r2 := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-11-10 10:00', '2026-10-29 08:00', 'rodada', null, '2026-11-10 19:00');
          update public.agenda_cliente_mensagens set enviar_em = pg_temp.em(q ->> 'em') where id = (r2 ->> 'id')::uuid;
          r := r || jsonb_build_object(v_txt, public._agenda_cliente_enfileirar((r2 ->> 'id')::uuid, pg_temp.em(q ->> 'agora')) ->> 'motivo');
          raise exception 'desfaz' using errcode = 'P0097';
        exception when sqlstate 'P0097' then null;
        end;
      end loop;
      v_res := pg_temp.ok(v_res, 'E3l a mensagem marcada no domingo = domingo; no feriado = feriado; a de ontem (o tique parado) e a que chega depois das 19:00 = janela',
        r = '{"domingo": "domingo", "feriado": "feriado", "ontem": "janela", "noite": "janela"}'::jsonb and pg_temp.n_fila() = 0, r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- E3m o texto proibido: o registro recusa (22023) e nada é gravado
    begin
      perform pg_temp.ligar();
      update public.os_planejamento set servico_cliente = 'a troca do pix da bateria' where service_order_id = c_luc;
      v_e := pg_temp.erro_de(format($q$select public._agenda_cliente_registrar('pronto', null, %L, null, '{}', %L, null, 'rodada')$q$,
                                    c_luc, pg_temp.em('2026-10-30 10:00')));
      v_res := pg_temp.ok(v_res, 'E3m o texto que leva pagamento: 22023, nada registrado nem na fila',
        v_e like '22023 A mensagem ao cliente não pode levar pagamento%' and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_luc)
        and pg_temp.n_fila() = 0, v_e);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── E4. O teto e o intervalo ──
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      r2 := pg_temp.reg('pronto_lembrete', null, c_luc, null, '{}', '2026-10-30 11:00', '2026-10-30 11:00');
      v_res := pg_temp.ok(v_res, 'E4a o teto por cliente no dia: a 2ª à Lucenira no mesmo dia = teto_dia',
        r ->> 'estado' = 'enfileirada' and r2 ->> 'motivo' = 'teto_dia' and pg_temp.n_fila() = 1, r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.ligar();
      perform pg_temp.direta('agenda-cliente:e4:1', '2026-10-26 10:00', p_estado := 'enviada');
      perform pg_temp.direta('agenda-cliente:e4:2', '2026-10-27 10:00', p_estado := 'respondida');
      perform pg_temp.direta('agenda-cliente:e4:3', '2026-10-28 10:00', p_estado := 'enfileirada');
      perform pg_temp.direta('agenda-cliente:e4:4', '2026-10-29 10:00', p_estado := 'recusada');
      perform pg_temp.direta('agenda-cliente:e4:5', '2026-10-25 10:00', p_estado := 'enviada');
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      r2 := pg_temp.reg('pronto_lembrete', null, c_luc, null, '{}', '2026-11-03 09:00', '2026-11-03 09:00');
      v_res := pg_temp.ok(v_res, 'E4b o teto da semana ISO: 3 de seg 26 a qua 28/10 (a recusada e a do domingo 25 não contam) → a 4ª (sex 30) = teto_semana; na semana seguinte (ter 03/11) sai',
        r ->> 'motivo' = 'teto_semana' and r2 ->> 'estado' = 'enfileirada', r::text || ' ' || r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.ligar();
      update public.agenda_config set cliente_total_dia_max = 1 where id;
      r := pg_temp.reg('pos_servico', null, c_rob, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      r2 := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      v_res := pg_temp.ok(v_res, 'E4c o total do dia (cliente_total_dia_max = 1): o Robson sai; a Lucenira, no mesmo dia, = teto_total; a hora dela ficou a 30–60 s da dele',
        r ->> 'estado' = 'enfileirada' and r2 ->> 'motivo' = 'teto_total'
        and (r2 ->> 'enviar_em')::timestamptz - (r ->> 'enviar_em')::timestamptz between interval '30 seconds' and interval '60 seconds',
        r::text || ' ' || r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.ligar();
      perform pg_temp.direta('agenda-cliente:e4d:1', '2026-10-30 09:00', c_cli_nel, c_nel, 'andamento', 'enfileirada');
      r := pg_temp.reg('pode_atrasar', 'peca', c_nel, date '2026-11-12', c_m6, '2026-10-30 10:00', '2026-10-30 10:00');
      v_res := pg_temp.ok(v_res, 'E4d (d13) o aviso de atraso que não cabe no teto não fica mudo: a pergunta crítica cliente_aviso (teto), a mensagem esperando o dono; nada na fila',
        r ->> 'estado' = 'aguardando_dono' and r ->> 'motivo' = 'teto_dia' and pg_temp.n_fila() = 0
        and (select m.aprovacao = 'critica' and m.pergunta_id = (r ->> 'pergunta_id')::uuid
               from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid)
        and (select p.critica and p.texto = 'O aviso de atraso do Nelson não cabe: ele já recebeu 1 mensagem esta semana. Recomendo você ligar. 1) Você liga e eu não mando nada (recomendo); 2) Eu mando o aviso escrito; 3) Não aviso agora.'
               from public.agenda_perguntas p where p.id = (r ->> 'pergunta_id')::uuid),
        r::text || ' ' || coalesce((select p.texto from public.agenda_perguntas p where p.id = (r ->> 'pergunta_id')::uuid), '-'));
      -- o dono escolhe "eu mando" (aprovada): o teto continua cheio → aí é recusada
      update public.agenda_cliente_mensagens set aprovacao = 'aprovada', aprovada_em = pg_temp.em('2026-10-30 10:05')
       where id = (r ->> 'id')::uuid;
      r2 := public._agenda_cliente_enfileirar((r ->> 'id')::uuid, pg_temp.em('2026-10-30 10:05'));
      v_res := pg_temp.ok(v_res, 'E4e a opção "eu mando" com o teto ainda cheio: recusada (teto_dia), sem pergunta nova',
        r2 = '{"estado": "recusada", "motivo": "teto_dia"}'::jsonb
        and (select count(*) from public.agenda_perguntas p where p.tipo = 'cliente_aviso') = 1, r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('pos_servico', null, c_rob, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      r3 := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-11-10 10:00', '2026-10-30 10:00', 'rodada', null, '2026-11-10 19:00');
      v_id := (r3 ->> 'id')::uuid;
      update public.agenda_cliente_mensagens set enviar_em = pg_temp.em('2026-10-30 10:00:10') where id = v_id;
      r2 := public._agenda_cliente_enfileirar(v_id, pg_temp.em('2026-10-30 10:00'));
      v_res := pg_temp.ok(v_res, 'E4f o intervalo: a mensagem marcada a 10 s da linha do Robson na fila = intervalo',
        r ->> 'estado' = 'enfileirada' and r2 = '{"estado": "recusada", "motivo": "intervalo"}'::jsonb, r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── E10. O modo de teste do WhatsApp ──
    begin
      perform pg_temp.ligar();
      insert into public.app_settings (key, value) values ('wa_test_mode', 'true') on conflict (key) do update set value = excluded.value;
      insert into public.app_settings (key, value) values ('wa_test_number', '+55 (47) 99999-0000') on conflict (key) do update set value = excluded.value;
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      v_res := pg_temp.ok(v_res, 'E10a wa_test_mode: vai ao número de teste (a trava da fila aceita)',
        r ->> 'estado' = 'enfileirada' and (r ->> 'teste')::boolean
        and pg_temp.fila_de((r ->> 'id')::uuid) ->> 'phone_normalized' = '5547999990000', r::text);
      update public.app_settings set value = '' where key = 'wa_test_number';
      r2 := pg_temp.reg('pos_servico', null, c_rob, null, '{}', '2026-10-30 11:00', '2026-10-30 11:00');
      v_res := pg_temp.ok(v_res, 'E10b wa_test_mode sem número de teste: nada sai (sem_telefone)', r2 ->> 'motivo' = 'sem_telefone', r2::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$e1$;

-- ── E5, E6, E7. A trava da fila, a revalidação e o pode_sair (fixture-fase5) ────────────────────────────
-- A linha da fila de uma mensagem (os dados dela, salvo o que o caso troca), inserida por fora: o erro ou 'sem erro'.
create function pg_temp.ins(p_msg uuid, p_fone text default null, p_texto text default null, p_chave text default null,
                            p_em text default null, p_tent int default 1, p_ref uuid default null) returns text
language plpgsql as $f$
declare
  m public.agenda_cliente_mensagens%rowtype;
begin
  select * into m from public.agenda_cliente_mensagens where id = p_msg;
  return pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id,
                                     scheduled_for, max_attempts, dedupe_key) values (%L, %L, 'agenda-cliente', %L, %L, %s, %L)$q$,
                                coalesce(p_fone, public._agenda_cliente_telefone(m.client_id)), coalesce(p_texto, m.texto),
                                coalesce(p_ref, m.id), coalesce(pg_temp.em(p_em), m.enviar_em), p_tent, coalesce(p_chave, m.dedupe_key)));
end $f$;

do $e5$
declare
  v_res jsonb := '[]'::jsonb;
  c_fla  constant uuid := '05000000-0000-4000-8000-000000000104';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_nel  constant uuid := '05000000-0000-4000-8000-000000000112';
  c_van  constant uuid := '05000000-0000-4000-8000-000000000069';
  c_rob  constant uuid := '05000000-0000-4000-8000-000000000121';
  c_cli_fla constant uuid := 'c1000000-0000-4000-8000-000000000004';
  c_m6   constant jsonb := '{"peca_de": "2026-11-11", "peca_ate": "2026-11-11", "faixa_de": "2026-11-12", "faixa_ate": "2026-11-13"}';
  r jsonb; r2 jsonb;
  v_m uuid; v_m2 uuid;
  v_f uuid;
  q record;
  v_e text;
  e jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('E5–E7 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase5');
    perform set_config('agenda_teste.hoje', '2026-10-30', true);

    -- ── E5. A 2ª trava: o gatilho da fila ──
    perform pg_temp.ligar();
    -- a Lucenira, registrada na sex 10:00 para ter 03/11 09:00 (fica registrada: não é a hora)
    r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-11-03 09:00', '2026-10-30 10:00');
    v_m := (r ->> 'id')::uuid;
    v_res := pg_temp.ok(v_res, 'E5a de partida: a mensagem registrada em ligado, livre, para ter 03/11 09:00, nada na fila',
      r ->> 'estado' = 'registrada' and r ->> 'aprovacao' = 'livre' and (r ->> 'enviar_em')::timestamptz = pg_temp.em('2026-11-03 09:00')
      and pg_temp.n_fila() = 0, r::text);
    e := jsonb_build_object();
    begin
      e := e || jsonb_build_object('certa', pg_temp.ins(v_m));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    e := e || jsonb_build_object(
      'sem_registro', pg_temp.ins(v_m, p_ref := gen_random_uuid()),
      'outro_texto', pg_temp.ins(v_m, p_texto := 'Oi, Lucenira! Passa aqui amanhã.'),
      'outra_chave', pg_temp.ins(v_m, p_chave := 'agenda-cliente:pronto:outra'),
      'outro_fone', pg_temp.ins(v_m, p_fone := '5547900000304'),
      'as_19', pg_temp.ins(v_m, p_em := '2026-11-03 19:00'),
      'as_1855_3', pg_temp.ins(v_m, p_em := '2026-11-03 18:55', p_tent := 3),
      'domingo', pg_temp.ins(v_m, p_em := '2026-11-08 10:00'),
      'feriado', pg_temp.ins(v_m, p_em := '2026-11-02 10:00'));
    begin
      e := e || jsonb_build_object('as_1855_1', pg_temp.ins(v_m, p_em := '2026-11-03 18:55', p_tent := 1));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'E5b a linha certa entra; sem registro, outro texto, outra chave, outro telefone = 42501; 19:00, a última tentativa depois das 19:00, domingo e feriado = 23514 com o motivo; 18:55 com 1 tentativa entra',
      e ->> 'certa' = 'sem erro' and e ->> 'as_1855_1' = 'sem erro'
      and e ->> 'sem_registro' like '42501 A fila do cliente só aceita a mensagem registrada pela agenda%'
      and e ->> 'outro_texto' like '42501 A fila do cliente só aceita o texto registrado%'
      and e ->> 'outra_chave' like '42501 A fila do cliente só aceita a mensagem com a chave dela%'
      and e ->> 'outro_fone' like '42501 A fila do cliente só aceita o telefone do cliente da mensagem%'
      and e ->> 'as_19' like '23514 Mensagem ao cliente fora da janela%[janela]' and e ->> 'as_1855_3' like '23514 %[janela]'
      and e ->> 'domingo' like '23514 %[domingo]' and e ->> 'feriado' like '23514 %[feriado]', e::text);
    e := jsonb_build_object();
    begin
      update public.agenda_config set modo_cliente = 'sombra' where id;
      e := e || jsonb_build_object('modo_sombra', pg_temp.ins(v_m));
      perform pg_temp.ligar();
      r2 := pg_temp.reg('pronto_lembrete', null, c_luc, null, '{}', '2026-11-04 09:00', '2026-10-30 10:00');
      perform pg_temp.ligar(array['pronto']);
      e := e || jsonb_build_object('tipo_fora', pg_temp.ins((r2 ->> 'id')::uuid));
      update public.agenda_config set modo_cliente = 'sombra' where id;
      r2 := pg_temp.reg('pos_servico', null, c_rob, null, '{}', '2026-11-04 09:00', '2026-10-30 10:00');
      perform pg_temp.ligar();
      e := e || jsonb_build_object('mensagem_em_teste', pg_temp.ins((r2 ->> 'id')::uuid));
      perform pg_temp.ligar(null, 3);
      r2 := pg_temp.reg('pos_servico', null, c_rob, null, '{}', '2026-11-05 09:00', '2026-10-30 10:00');
      e := e || jsonb_build_object('pedida', pg_temp.ins((r2 ->> 'id')::uuid));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'E5c o modo fora de ligado, o tipo fora das ondas, a mensagem em teste e a que espera o dono (pedida): 42501',
      e ->> 'modo_sombra' like '42501 %modo_cliente ligado%' and e ->> 'tipo_fora' like '42501 %o tipo ligado%'
      and e ->> 'mensagem_em_teste' like '42501 %modo_cliente ligado%'
      and e ->> 'pedida' like '42501 A fila do cliente só aceita a mensagem livre ou aprovada pelo dono%', e::text);
    e := jsonb_build_object();
    begin
      perform pg_temp.direta('agenda-cliente:e5:teto', '2026-11-03 15:00', p_tipo := 'pronto_lembrete', p_estado := 'enfileirada');
      e := e || jsonb_build_object('teto', pg_temp.ins(v_m));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      r2 := pg_temp.reg('pos_servico', null, c_rob, null, '{}', '2026-11-03 09:00', '2026-10-30 10:00');
      e := e || jsonb_build_object('robson_10s', pg_temp.ins((r2 ->> 'id')::uuid, p_em := '2026-11-03 09:00:10'));
      e := e || jsonb_build_object('intervalo', pg_temp.ins(v_m));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      perform set_config('agenda.porta', 'on', true);
      update public.service_orders set delivered_at = pg_temp.em('2026-10-31 10:00') where id = c_luc;
      perform set_config('agenda.porta', 'off', true);
      e := e || jsonb_build_object('entregue', pg_temp.ins(v_m));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'E5d acima do teto (teto_dia), a 10 s de outra linha do cliente na fila (intervalo) e a que a revalidação recusa (entregue = status): 23514 com o motivo',
      e ->> 'teto' like '23514 Teto de mensagens ao cliente%[teto_dia]' and e ->> 'robson_10s' = 'sem erro'
      and e ->> 'intervalo' like '23514 Mensagem ao cliente perto demais de outra%[intervalo]'
      and e ->> 'entregue' like '23514 A mensagem ao cliente não vale mais (status)%[status]', e::text);
    -- a linha que entrou: não muda de texto nem de telefone; a nova tentativa fora da janela falha, volta à hora e a mensagem
    -- fica recusada; dentro da janela, fica
    begin
      perform pg_temp.ins(v_m, p_tent := 3);
      select x.* into q from public.whatsapp_send_queue x where x.source_ref_id = v_m;
      update public.agenda_cliente_mensagens set estado = 'enfileirada', fila_id = q.id where id = v_m;
      e := jsonb_build_object(
        'texto', pg_temp.erro_de(format($q$update public.whatsapp_send_queue set message = 'outra' where id = %L$q$, q.id)),
        'fone', pg_temp.erro_de(format($q$update public.whatsapp_send_queue set phone_normalized = '5547900000304' where id = %L$q$, q.id)));
      update public.whatsapp_send_queue set status = 'pending', attempts = 1, scheduled_for = pg_temp.em('2026-11-03 09:05') where id = q.id;
      e := e || jsonb_build_object('dentro', (select x.status || ' ' || pg_temp.hora(x.scheduled_for) from public.whatsapp_send_queue x where x.id = q.id));
      update public.whatsapp_send_queue set status = 'pending', attempts = 2, scheduled_for = pg_temp.em('2026-11-03 19:02') where id = q.id;
      e := e || jsonb_build_object('fora', (select x.status || ' ' || pg_temp.hora(x.scheduled_for) || ' ' || x.failed_reason
                                              from public.whatsapp_send_queue x where x.id = q.id),
                                   'mensagem', (select m.estado || ' ' || m.recusa_motivo from public.agenda_cliente_mensagens m where m.id = v_m));
      v_res := pg_temp.ok(v_res, 'E5e a linha não muda de texto nem de telefone (42501); a nova tentativa às 09:05 fica; a das 19:02 falha, volta às 09:05 e a mensagem fica recusada/janela',
        e ->> 'texto' like '42501 A linha da fila do cliente não muda%' and e ->> 'fone' like '42501 A linha da fila do cliente não muda%'
        and e ->> 'dentro' = 'pending 03/11 09:05:00'
        and e ->> 'fora' = 'failed 03/11 09:05:00 agenda-cliente: a nova tentativa não sai (janela)'
        and e ->> 'mensagem' = 'recusada janela', e::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_e := pg_temp.erro_de($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, scheduled_for)
                              values ('5547900000312', 'mensagem livre do assistente', 'reply-router', timestamptz '2026-11-01 23:00-03')$q$);
    v_res := pg_temp.ok(v_res, 'E5f as outras origens não mudam: a linha do assistente no domingo às 23:00 entra como sempre',
      v_e = 'sem erro', v_e);

    -- ── E6. A revalidação ──
    begin
      r := pg_temp.reg('acesso', null, c_fla, date '2026-11-03', '{}', '2026-10-31 09:00', '2026-10-30 17:00');
      v_m2 := (r ->> 'id')::uuid;
      e := jsonb_build_object(
        'sex_17', public._agenda_cliente_revalidar(v_m2, pg_temp.em('2026-10-30 17:00')),
        'sab_09', public._agenda_cliente_revalidar(v_m2, pg_temp.em('2026-10-31 09:00')));
      -- a 1ª mensagem guardada: outra mensagem ao Flávio sai antes — a assinatura desta continua valendo
      r2 := pg_temp.reg('confirmar', null, c_fla, date '2026-11-03', '{}', '2026-11-02 09:00', '2026-10-30 17:00');
      update public.agenda_cliente_mensagens set estado = 'enviada', enviada_em = pg_temp.em('2026-10-30 17:05') where id = (r2 ->> 'id')::uuid;
      e := e || jsonb_build_object(
        'outra_saiu', public._agenda_cliente_revalidar(v_m2, pg_temp.em('2026-10-31 09:00')),
        'contexto_mudou', (public._agenda_cliente_contexto(c_fla, date '2026-10-31') ->> 'primeira'));
      -- a hora que mudou de dia: o "Na terça" de sábado vira "Hoje" na terça
      update public.agenda_cliente_mensagens set enviar_em = pg_temp.em('2026-11-03 08:00') where id = v_m2;
      e := e || jsonb_build_object('outro_dia', public._agenda_cliente_revalidar(v_m2, pg_temp.em('2026-11-03 08:00')));
      v_res := pg_temp.ok(v_res, 'E6a a mensagem que vale: null na sex 17:00 e no sáb 09:00; outra ao Flávio que saiu antes (a 1ª deixa de ser) não a deixa desatualizada; a hora que mudou de dia, sim',
        e = '{"sex_17": null, "sab_09": null, "outra_saiu": null, "contexto_mudou": "false", "outro_dia": "desatualizada"}'::jsonb, e::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    e := jsonb_build_object();
    begin
      r := pg_temp.reg('vespera', null, c_fla, date '2026-11-03', '{}', '2026-10-31 09:00', '2026-10-30 17:00');
      r2 := pg_temp.reg('acesso', null, c_fla, date '2026-11-03', '{}', '2026-10-31 09:00', '2026-10-30 17:00');
      perform set_config('agenda.porta', 'on', true);
      update public.service_orders set status = 'awaiting_parts' where id = c_fla;
      perform set_config('agenda.porta', 'off', true);
      e := e || jsonb_build_object('vespera_peca', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-10-31 09:00')),
                                   'acesso_peca', public._agenda_cliente_revalidar((r2 ->> 'id')::uuid, pg_temp.em('2026-10-31 09:00')));
      update public.clients set opt_out_whatsapp = true where id = c_cli_fla;
      e := e || jsonb_build_object('opt_out_antes', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-10-31 09:00')));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      r := pg_temp.reg('acesso', null, c_fla, date '2026-11-03', '{}', '2026-10-31 09:00', '2026-10-30 17:00');
      update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito'
       where service_order_id = c_fla and dia = date '2026-11-03' and estado = 'publicada';
      e := e || jsonb_build_object('dia_saiu', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-10-31 09:00')));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      r := pg_temp.reg('confirmar', null, c_van, date '2026-11-03', '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      e := e || jsonb_build_object('material', r ->> 'motivo');
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      r := pg_temp.reg('pode_atrasar', 'peca', c_nel, date '2026-11-12', c_m6, '2026-10-31 09:00', '2026-10-30 17:00');
      e := e || jsonb_build_object('m6_vale', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-10-31 09:00')));
      update public.os_planejamento set prometido_ate = date '2026-10-29', prometido_de = date '2026-10-29' where service_order_id = c_nel;
      e := e || jsonb_build_object('passou', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-10-31 09:00')));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-11-03 09:00', '2026-10-30 10:00');
      e := e || jsonb_build_object('luc_vale', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-11-03 09:00')));
      perform pg_temp.direta('agenda-cliente:e6:mesmo', '2026-11-02 12:00', p_tipo := 'pronto', p_estado := 'enviada');
      e := e || jsonb_build_object('mesmo_tipo', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-11-03 09:00')),
                                   'mesmo_tipo_25h', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-11-03 12:01')));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-11-03 09:00', '2026-10-30 10:00');
      update public.os_planejamento set servico_cliente = 'a troca das baterias e do carregador' where service_order_id = c_luc;
      e := e || jsonb_build_object('servico_mudou', public._agenda_cliente_revalidar((r ->> 'id')::uuid, pg_temp.em('2026-11-03 09:00')));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    v_res := pg_temp.ok(v_res, 'E6b cada motivo: a véspera (M2) e o acesso (M4) com a OS aguardando peça = status (o opt-out vem antes); o dia que saiu do plano = data_mudou; o M1 do Vanderlei sem o material = material; o M6 vale, e com a data dita passada = passou_da_data; o mesmo tipo a ela em 24 h = mesmo_tipo_24h (com 25 h, não); o serviço dito de outro jeito = desatualizada',
      e = '{"vespera_peca": "status", "acesso_peca": "status", "opt_out_antes": "opt_out", "dia_saiu": "data_mudou", "material": "material",
            "m6_vale": null, "passou": "passou_da_data", "luc_vale": null, "mesmo_tipo": "mesmo_tipo_24h", "mesmo_tipo_25h": null,
            "servico_mudou": "desatualizada"}'::jsonb, e::text);

    -- ── E7. O pode_sair (a pergunta do worker) ──
    begin
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      v_f := (r ->> 'fila_id')::uuid;
      e := jsonb_build_object(
        'pode', public.agenda_cliente_pode_sair(v_f, pg_temp.em('2026-10-30 10:00:30')),
        'as_19', public.agenda_cliente_pode_sair(v_f, pg_temp.em('2026-10-30 19:00')) ->> 'motivo',
        'sabado', public.agenda_cliente_pode_sair(v_f, pg_temp.em('2026-10-31 09:00')) ->> 'motivo',
        'outra_fila', public.agenda_cliente_pode_sair(gen_random_uuid(), pg_temp.em('2026-10-30 10:00:30')) ->> 'motivo',
        'como_worker', pg_temp.como(null, 'service_role', format('select public.agenda_cliente_pode_sair(%L, %L)::text', v_f,
                                                                 pg_temp.em('2026-10-30 10:00:30'))));
      insert into public.whatsapp_send_queue (phone_normalized, message, source, scheduled_for)
      values ('5547900000312', 'outra coisa', 'reply-router', pg_temp.em('2026-10-30 10:00'))
      returning id into v_m2;
      e := e || jsonb_build_object('reply_router', public.agenda_cliente_pode_sair(v_m2, pg_temp.em('2026-10-30 10:00:30')) ->> 'motivo');
      begin
        update public.agenda_config set modo_cliente = 'sombra' where id;
        e := e || jsonb_build_object('modo', public.agenda_cliente_pode_sair(v_f, pg_temp.em('2026-10-30 10:00:30')) ->> 'motivo');
        perform pg_temp.ligar(array['confirmar']);
        e := e || jsonb_build_object('tipo', public.agenda_cliente_pode_sair(v_f, pg_temp.em('2026-10-30 10:00:30')) ->> 'motivo');
        perform pg_temp.ligar();
        perform set_config('agenda.porta', 'on', true);
        update public.service_orders set delivered_at = pg_temp.em('2026-10-30 10:00:10') where id = c_luc;
        perform set_config('agenda.porta', 'off', true);
        e := e || jsonb_build_object('entregue', public.agenda_cliente_pode_sair(v_f, pg_temp.em('2026-10-30 10:00:30')) ->> 'motivo');
        raise exception 'desfaz' using errcode = 'P0096';
      exception when sqlstate 'P0096' then null;
      end;
      v_res := pg_temp.ok(v_res, 'E7a o pode_sair: pode na janela (e o service_role chama); 19:00 = janela; no sábado = vencida (a validade era sex 19:00); a linha que não existe e a de outra origem = janela; o modo, o tipo e a OS entregue no meio tempo = modo, tipo_em_teste, status',
        e -> 'pode' = '{"pode": true, "motivo": null}'::jsonb and e ->> 'as_19' = 'janela' and e ->> 'sabado' = 'vencida'
        and e ->> 'outra_fila' = 'janela' and e ->> 'reply_router' = 'janela' and e ->> 'como_worker' like '{"pode": true%'
        and e ->> 'modo' = 'modo' and e ->> 'tipo' = 'tipo_em_teste' and e ->> 'entregue' = 'status', e::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$e5$;

-- ── E8, E11. O envio e o passo "fila" (fixture-fase5) ───────────────────────────────────────────────────
do $e8$
declare
  v_res jsonb := '[]'::jsonb;
  c_fla  constant uuid := '05000000-0000-4000-8000-000000000104';
  c_luc  constant uuid := '05000000-0000-4000-8000-000000000122';
  c_kal  constant uuid := '05000000-0000-4000-8000-000000000032';
  c_cli_luc constant uuid := 'c1000000-0000-4000-8000-000000000012';
  r jsonb; r2 jsonb;
  v_m uuid; v_f uuid;
  e jsonb;
  p public.os_planejamento;
  v_antes jsonb; v_depois jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('E8, E11 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase5');
    perform set_config('agenda_teste.hoje', '2026-10-30', true);

    -- ── E8. O envio ──
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('acesso', null, c_fla, date '2026-11-03', '{}', '2026-10-31 09:00', '2026-10-30 17:00');
      v_m := (r ->> 'id')::uuid;
      r2 := public._agenda_cliente_fila(date '2026-10-31', pg_temp.em('2026-10-31 08:50'));
      v_f := (select m.fila_id from public.agenda_cliente_mensagens m where m.id = v_m);
      update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-10-31 09:00:20'), attempts = 1 where id = v_f;
      select * into p from public.os_planejamento where service_order_id = c_fla;
      v_res := pg_temp.ok(v_res, 'E8a o envio do M4 do Flávio: enviada (a hora do envio); o prometido firme de ter 03/11 a qua 04/11 (fonte mensagem, o original na 1ª vez); a ação que conta no fechamento, sem desfaz',
        (r2 ->> 'enfileiradas')::int = 1
        and (select m.estado = 'enviada' and m.enviada_em = pg_temp.em('2026-10-31 09:00:20') and m.acao_id is not null
               from public.agenda_cliente_mensagens m where m.id = v_m)
        and p.prometido_tipo = 'firme' and p.prometido_de = date '2026-11-03' and p.prometido_ate = date '2026-11-04'
        and p.prometido_original_ate = date '2026-11-04' and p.prometido_fonte = 'mensagem' and p.prometido_mensagem_id = v_m
        and (select a.texto = 'Mandei ao Flávio a véspera com a pergunta do acesso (ter 03/11).' and a.executada and a.origem = 'vigia'
                    and a.tipo = 'cliente' and a.desfazivel_ate is null and a.dia = date '2026-10-31'
               from public.agenda_acoes a join public.agenda_cliente_mensagens m on m.acao_id = a.id where m.id = v_m),
        (select string_agg(a.texto, ' | ') from public.agenda_acoes a where a.tipo = 'cliente') || ' / ' || to_jsonb(p)::text);
      update public.whatsapp_send_queue set sent_at = pg_temp.em('2026-10-31 09:00:25') where id = v_f;
      update public.whatsapp_send_queue set status = 'sent' where id = v_f;
      v_res := pg_temp.ok(v_res, 'E8b o "sent" de novo não repete nada (uma ação, a hora do 1º envio)',
        (select count(*) from public.agenda_acoes a where a.tipo = 'cliente') = 1
        and (select m.enviada_em from public.agenda_cliente_mensagens m where m.id = v_m) = pg_temp.em('2026-10-31 09:00:20'), null);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 15:30', '2026-10-30 15:30');
      update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-10-30 15:30:10') where id = (r ->> 'fila_id')::uuid;
      v_res := pg_temp.ok(v_res, 'E8c a mensagem sem data (o pronto da Lucenira): enviada e a ação, sem prometido',
        (select m.estado from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid) = 'enviada'
        and (select p2.prometido_tipo is null from public.os_planejamento p2 where p2.service_order_id = c_luc)
        and exists (select 1 from public.agenda_acoes a where a.texto = 'Mandei ao Lucenira que o serviço ficou pronto.'), r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    -- o botão antigo (agenda-confirmacao): fora de ligado, como hoje — e o envio grava o prometido (D9)
    begin
      r := public.pedir_confirmacao_do_agendamento(c_fla, 'aa000000-0000-4000-8000-000000000001');
      v_f := (select q.id from public.whatsapp_send_queue q where q.source = 'agenda-confirmacao' and q.source_ref_id = c_fla);
      update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-10-30 10:00:20') where id = v_f;
      select * into p from public.os_planejamento where service_order_id = c_fla;
      v_res := pg_temp.ok(v_res, 'E8d o botão antigo (modo_cliente desligado): a linha agenda-confirmacao com o dia do plano (ter 03/11 às 13h00); ao sair, o prometido firme de ter 03/11 a qua 04/11 (fonte confirmacao)',
        (r ->> 'ok')::boolean and v_f is not null
        and (select q.message like '%Confirmando o atendimento no Motorhome terça (03/11) às 13h00.%' from public.whatsapp_send_queue q where q.id = v_f)
        and p.prometido_tipo = 'firme' and p.prometido_de = date '2026-11-03' and p.prometido_ate = date '2026-11-04'
        and p.prometido_fonte = 'confirmacao' and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_fla),
        r::text || ' / ' || to_jsonb(p)::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    -- a linha de os_planejamento que nasce só com o prometido (a OS sem planejamento, o Kalmar) não muda a prontidão nem o plano
    begin
      v_antes := jsonb_build_object('pront', public.os_prontidao(c_kal, date '2026-10-30'), 'plano', public._agenda_plano_da_os(c_kal, date '2026-10-30'),
                                    'carteira', exists (select 1 from public.os_carteira(date '2026-10-30') k where k.service_order_id = c_kal));
      r := public._agenda_cliente_prometer_confirmacao(c_kal, pg_temp.em('2026-11-05 08:00'), pg_temp.em('2026-10-30 10:00'));
      v_depois := jsonb_build_object('pront', public.os_prontidao(c_kal, date '2026-10-30'), 'plano', public._agenda_plano_da_os(c_kal, date '2026-10-30'),
                                     'carteira', exists (select 1 from public.os_carteira(date '2026-10-30') k where k.service_order_id = c_kal));
      v_res := pg_temp.ok(v_res, 'E8e a linha nova de os_planejamento só com o prometido (OS sem planejamento): vale como "sem estimativa" — a prontidão, o plano e a carteira iguais',
        (r ->> 'gravou')::boolean and v_antes = v_depois
        and (select p2.dias is null and p2.prometido_tipo = 'firme' from public.os_planejamento p2 where p2.service_order_id = c_kal),
        case when v_antes = v_depois then null else v_antes::text || ' ≠ ' || v_depois::text end);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    -- o erro no prometido (a mensagem firme sem o dia) não derruba o envio: enviada, a ação, e o erro no log
    begin
      perform pg_temp.ligar();
      insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, origem, modo, texto, enviar_em, valida_ate,
                                                   aprovacao, estado, dedupe_key, prometido_tipo)
      values ('d5000000-0000-4000-8000-0000000000e8', c_cli_luc, c_luc, 'pronto', 'rodada', 'ligado', 'mensagem de teste (AG5E)',
              pg_temp.em('2026-10-30 10:00'), pg_temp.em('2026-10-30 19:00'), 'livre', 'enfileirada', 'agenda-cliente:e8f', 'firme');
      set local session_replication_role = replica;
      insert into public.whatsapp_send_queue (id, phone_normalized, message, source, source_ref_id, scheduled_for, dedupe_key)
      values ('d5000000-0000-4000-8000-0000000000f8', '5547900000312', 'mensagem de teste (AG5E)', 'agenda-cliente',
              'd5000000-0000-4000-8000-0000000000e8', pg_temp.em('2026-10-30 10:00'), 'agenda-cliente:e8f');
      set local session_replication_role = origin;
      update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em('2026-10-30 10:00:20') where id = 'd5000000-0000-4000-8000-0000000000f8';
      v_res := pg_temp.ok(v_res, 'E8f o prometido que falha (firme sem o dia) não derruba o envio: a linha sent, a mensagem enviada, a ação; o erro em app_error_logs (agenda / cliente:enviada)',
        (select q.status from public.whatsapp_send_queue q where q.id = 'd5000000-0000-4000-8000-0000000000f8') = 'sent'
        and (select m.estado = 'enviada' and m.acao_id is not null from public.agenda_cliente_mensagens m where m.id = 'd5000000-0000-4000-8000-0000000000e8')
        and exists (select 1 from public.app_error_logs l where l.context = 'agenda' and l.action = 'cliente:enviada'
                     and l.message like 'mensagem ao cliente, o envio (o prometido):%'),
        (select string_agg(l.message, ' | ') from public.app_error_logs l where l.context = 'agenda'));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- ── E11. O passo "fila" ──
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      r2 := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 12:00'));
      e := jsonb_build_object('meio_dia', r2 ->> 'canceladas', 'fila_12', pg_temp.fila_de((r ->> 'id')::uuid) ->> 'status');
      r2 := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 19:30'));
      e := e || jsonb_build_object('noite', r2 ->> 'pela_janela', 'fila_19', pg_temp.fila_de((r ->> 'id')::uuid) ->> 'status',
                                   'msg', (select m.estado || ' ' || m.recusa_motivo from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid));
      v_res := pg_temp.ok(v_res, 'E11a a fila velha: ao meio-dia a linha das 10:00 fica (ainda na janela); às 19:30, failed e a mensagem recusada/janela',
        e = '{"meio_dia": "0", "fila_12": "pending", "noite": "1", "fila_19": "failed", "msg": "recusada janela"}'::jsonb, e::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      e := jsonb_build_object();
      begin
        update public.agenda_config set modo_cliente = 'desligado' where id;
        r2 := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
        e := e || jsonb_build_object('desligado', r2 ->> 'pelo_modo',
                                     'msg_modo', (select m.recusa_motivo from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid));
        raise exception 'desfaz' using errcode = 'P0096';
      exception when sqlstate 'P0096' then null;
      end;
      begin
        perform pg_temp.ligar(array['confirmar']);
        r2 := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
        e := e || jsonb_build_object('msg_tipo', (select m.recusa_motivo from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid));
        raise exception 'desfaz' using errcode = 'P0096';
      exception when sqlstate 'P0096' then null;
      end;
      begin
        perform set_config('agenda.porta', 'on', true);
        update public.service_orders set delivered_at = pg_temp.em('2026-10-30 10:02') where id = c_luc;
        perform set_config('agenda.porta', 'off', true);
        r2 := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 10:05'));
        e := e || jsonb_build_object('revalidadas', r2 ->> 'revalidadas',
                                     'msg_status', (select m.recusa_motivo from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid),
                                     'fila_status', pg_temp.fila_de((r ->> 'id')::uuid) ->> 'status');
        raise exception 'desfaz' using errcode = 'P0096';
      exception when sqlstate 'P0096' then null;
      end;
      v_res := pg_temp.ok(v_res, 'E11b a linha pendente com o modo desligado (o passo roda mesmo assim) = modo; o tipo fora das ondas = tipo_em_teste; a OS entregue antes de sair = status (failed)',
        e = '{"desligado": "1", "msg_modo": "modo", "msg_tipo": "tipo_em_teste", "revalidadas": "1", "msg_status": "status", "fila_status": "failed"}'::jsonb,
        e::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      perform pg_temp.ligar();
      r := pg_temp.reg('acesso', null, c_fla, date '2026-11-03', '{}', '2026-10-31 09:00', '2026-10-30 17:00');
      e := jsonb_build_object(
        'as_0840', public._agenda_cliente_fila(date '2026-10-31', pg_temp.em('2026-10-31 08:40')) ->> 'enfileiradas',
        'as_0850', public._agenda_cliente_fila(date '2026-10-31', pg_temp.em('2026-10-31 08:50')) ->> 'enfileiradas',
        'as_0855', public._agenda_cliente_fila(date '2026-10-31', pg_temp.em('2026-10-31 08:55')) ->> 'enfileiradas');
      -- (a leitura num comando à parte: a função STABLE no mesmo comando vê o retrato de antes dele)
      e := e || jsonb_build_object('fila', pg_temp.fila_de((r ->> 'id')::uuid) ->> 'scheduled_for');
      v_res := pg_temp.ok(v_res, 'E11c o que é hora de mandar: registrada na sex 17:00 para sáb 09:00 — às 08:40 não, às 08:50 entra na fila (marcada para 09:00), às 08:55 nada de novo',
        e ->> 'as_0840' = '0' and e ->> 'as_0850' = '1' and e ->> 'as_0855' = '0'
        and (e ->> 'fila')::timestamptz = pg_temp.em('2026-10-31 09:00'), e::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      perform pg_temp.ligar(null, 3);
      r := pg_temp.reg('acesso', null, c_fla, date '2026-11-03', '{}', '2026-10-31 09:00', '2026-10-30 17:00');
      r2 := public._agenda_cliente_fila(date '2026-10-31', pg_temp.em('2026-10-31 12:00'));
      e := jsonb_build_object('meio_dia', r2 ->> 'vencidas');
      r2 := public._agenda_cliente_fila(date '2026-10-31', pg_temp.em('2026-10-31 13:05'));
      e := e || jsonb_build_object('depois', r2 ->> 'vencidas',
        'msg', (select m.estado || ' ' || m.recusa_motivo || ' ' || m.aprovacao from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid),
        'pergunta', (select q.estado from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid));
      v_res := pg_temp.ok(v_res, 'E11d a que esperou o dono e passou da validade (sáb 13:00): recusada/vencida, a aprovação vencida e a pergunta vencida; antes disso, nada',
        e = '{"meio_dia": "0", "depois": "1", "msg": "recusada vencida vencida", "pergunta": "vencida"}'::jsonb, e::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      perform pg_temp.ligar();
      perform pg_temp.wa('5547900000312', 'inbound', '2026-10-30 09:40');
      r := pg_temp.reg('pronto', null, c_luc, null, '{}', '2026-10-30 10:00', '2026-10-30 10:00');
      e := jsonb_build_object('registro', r ->> 'motivo', 'estado', r ->> 'estado', 'fila', pg_temp.n_fila(),
        'nova_hora', (select pg_temp.hora(m.enviar_em) from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid));
      r2 := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 10:30'));
      e := e || jsonb_build_object('as_1030', r2 ->> 'enfileiradas', 'fila_1030', pg_temp.n_fila());
      r2 := public._agenda_cliente_fila(date '2026-10-30', pg_temp.em('2026-10-30 10:41'));
      e := e || jsonb_build_object('as_1041', r2 ->> 'enfileiradas', 'fila_1041', pg_temp.n_fila(),
        'msg', (select m.estado from public.agenda_cliente_mensagens m where m.id = (r ->> 'id')::uuid));
      v_res := pg_temp.ok(v_res, 'E11e (d19) a conversa viva: a Lucenira escreveu às 09:40 — às 10:00 a mensagem espera o próximo tique (10:15); às 10:30 ainda espera; às 10:41 (passou 1 h) entra na fila',
        e ->> 'registro' = 'conversa_viva' and e ->> 'estado' = 'registrada' and (e ->> 'fila')::int = 0
        and e ->> 'nova_hora' like '30/10 10:15:%' and e ->> 'as_1030' = '0' and (e ->> 'fila_1030')::int = 0
        and e ->> 'as_1041' = '1' and (e ->> 'fila_1041')::int = 1 and e ->> 'msg' = 'enfileirada', e::text);
      -- a conversa que não acaba antes do fim da validade: vencida
      perform pg_temp.wa('5547900000312', 'outbound', '2026-11-03 18:40');
      r := pg_temp.reg('pronto_lembrete', null, c_luc, null, '{}', '2026-11-03 18:45', '2026-11-03 18:45');
      v_res := pg_temp.ok(v_res, 'E11f a conversa viva que passaria da validade (o dono falando com ela às 18:40; a mensagem vale até as 19:00 e o próximo tique já é fora da janela): recusada/vencida',
        r ->> 'estado' = 'recusada' and r ->> 'motivo' = 'vencida', r::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$e8$;

-- ── E9. D9: o botão antigo e o "sim" (fixture-fase5; uma OS nova do Flávio, com o dia contado do relógio) ──────
do $e9$
declare
  v_res jsonb := '[]'::jsonb;
  c_os   constant uuid := '05000000-0000-4000-8000-000000000199';
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_d date;
  v_ini timestamptz;
  r jsonb; r2 jsonb;
  e jsonb;
  v_e text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('E9 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase5');
    -- o botão e o "sim" leem o relógio (now()): a OS nova do Flávio tem um dia, de manhã, numa quarta 3 semanas à frente
    perform set_config('agenda_teste.hoje', '', true);
    v_d := (select d::date from generate_series(current_date + 21, current_date + 35, interval '1 day') d
             where extract(isodow from d) = 3 and public.agenda_feriado(d::date) is null limit 1);
    perform set_config('agenda.porta', 'on', true);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at,
                                       updated_at, converted_to_os_at, grand_total)
    values (c_os, 'OS-00199', 'c1000000-0000-4000-8000-000000000004', 'f1000000-0000-4000-8000-000000000004', 'approved', 'approved',
            'repair', now() - interval '5 days', now() - interval '5 days', now() - interval '5 days', 100);
    perform set_config('agenda.porta', 'off', true);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, origem)
    values (c_os, 'bb000000-0000-4000-8000-000000000004', v_d, 'manha', 'publicada', 'dono');
    v_ini := (select min(lower(a.periodo)) from public.agenda_alocacoes a where a.service_order_id = c_os);

    begin
      r := public.pedir_confirmacao_do_agendamento(c_os, c_admin);
      v_res := pg_temp.ok(v_res, 'E9a o botão com a OS aprovada e o dia no plano (modo_cliente desligado): como hoje — a linha agenda-confirmacao com o dia do plano; o pedido anotado na OS',
        (r ->> 'ok')::boolean
        and exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-confirmacao' and q.source_ref_id = c_os
                      and q.phone_normalized = '5547900000304'
                      and q.message like '%' || public._agenda_cliente_dia(v_d) || ' às ' || to_char(v_ini at time zone 'America/Sao_Paulo', 'HH24"h"MI') || '.%')
        and (select so.client_confirmation_requested_at is not null from public.service_orders so where so.id = c_os)
        and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_os), r::text);
      r := public.registrar_confirmacao_do_cliente('5547900000304', 'sim, mas preciso remarcar', null);
      r2 := public.registrar_confirmacao_do_cliente('(47) 90000-0304', 'Sim!', null);
      v_res := pg_temp.ok(v_res, 'E9b o "sim" (D9, a OS aprovada): "sim, mas…" não confirma; "Sim!" confirma para o dia do plano, fixa as alocações dele (cliente_confirmou), registra a ação fixar (origem cliente) e avisa no sino',
        not (r ->> 'confirmou')::boolean and (r2 ->> 'confirmou')::boolean and r2 ->> 'os' = 'OS-00199'
        and (select so.client_confirmed_for = v_ini and so.client_confirmed_at is not null from public.service_orders so where so.id = c_os)
        and (select bool_and(a.estado = 'fixada' and a.fixado_por = 'cliente_confirmou') from public.agenda_alocacoes a where a.service_order_id = c_os)
        and (select a.texto = format('O Flávio confirmou %s.', public._dia_curto(v_d)) and a.origem = 'cliente' and a.executada
                    and a.desfazivel_ate is null
               from public.agenda_acoes a where a.tipo = 'fixar' and a.service_order_id = c_os)
        and exists (select 1 from public.app_notifications n where n.type = 'agendamento_confirmado' and n.navigate_to = '/v2/service-orders/' || c_os),
        r2::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    e := jsonb_build_object();
    begin
      perform set_config('agenda.porta', 'on', true);
      update public.service_orders set status = 'awaiting_parts' where id = c_os;
      perform set_config('agenda.porta', 'off', true);
      e := e || jsonb_build_object('peca', pg_temp.erro_de(format('select public.pedir_confirmacao_do_agendamento(%L, %L)', c_os, c_admin)));
      raise exception 'desfaz' using errcode = 'P0096';
    exception when sqlstate 'P0096' then null;
    end;
    begin
      update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'desfeito' where service_order_id = c_os;
      e := e || jsonb_build_object('sem_dia', pg_temp.erro_de(format('select public.pedir_confirmacao_do_agendamento(%L, %L)', c_os, c_admin)));
      raise exception 'desfaz' using errcode = 'P0096';
    exception when sqlstate 'P0096' then null;
    end;
    begin
      update public.agenda_config set modo_proposta = 'desligado' where id;
      e := e || jsonb_build_object('sem_plano', pg_temp.erro_de(format('select public.pedir_confirmacao_do_agendamento(%L, %L)', c_os, c_admin)));
      perform set_config('agenda.porta', 'on', true);
      update public.service_orders set status = 'scheduled', scheduled_start_at = v_ini, scheduled_end_at = v_ini + interval '4 hours' where id = c_os;
      perform set_config('agenda.porta', 'off', true);
      e := e || jsonb_build_object('sem_plano_agendada', pg_temp.erro_de(format('select public.pedir_confirmacao_do_agendamento(%L, %L)', c_os, c_admin)));
      raise exception 'desfaz' using errcode = 'P0096';
    exception when sqlstate 'P0096' then null;
    end;
    v_res := pg_temp.ok(v_res, 'E9c aguardando peça recusa (não promete o que não depende de nós); sem dia no plano recusa; sem o plano ligado, a regra de 30/09 (aprovada não; agendada no futuro sim)',
      e ->> 'peca' = 'P0001 A OS espera peça (ou o cliente): confirmar o dia agora seria prometer o que não depende de nós.'
      and e ->> 'sem_dia' = 'P0001 A OS OS-00199 não tem dia marcado no plano de amanhã em diante.'
      and e ->> 'sem_plano' = 'P0001 A OS OS-00199 não está agendada.' and e ->> 'sem_plano_agendada' = 'sem erro', e::text);
    begin
      perform pg_temp.ligar();
      r := public.pedir_confirmacao_do_agendamento(c_os, c_admin);
      e := (select to_jsonb(m) - 'base' from public.agenda_cliente_mensagens m where m.service_order_id = c_os);
      v_res := pg_temp.ok(v_res, 'E9d em ligado (com a confirmação nas ondas) o botão registra pela agenda: o M1 aprovado pelo clique (origem botao, aprovada_por o dono), o dia do plano; na fila ou esperando a hora da janela; nenhuma linha agenda-confirmacao; o pedido da OS ainda não anotado',
        (r ->> 'ok')::boolean and (r ->> 'agenda')::boolean
        and e ->> 'origem' = 'botao' and e ->> 'aprovacao' = 'aprovada' and (e ->> 'aprovada_por')::uuid = c_admin and e ->> 'tipo' = 'confirmar'
        and e ->> 'modo' = 'ligado' and (e ->> 'dia_alvo')::date = v_d and e ->> 'estado' in ('enfileirada', 'registrada')
        and e ->> 'texto' like 'Olá, Flávio! Aqui é o Gustavo, da HBR Marine Solutions. Conseguimos encaixar o serviço no seu motorhome para '
                               || public._agenda_cliente_dia(v_d) || ', pela manhã, com previsão de 1 dia de trabalho.%'
        and r ->> 'message' like 'Pedido de confirmação %'
        and not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-confirmacao')
        and (select so.client_confirmation_requested_at is null from public.service_orders so where so.id = c_os),
        r::text || ' / ' || e::text);
      -- quando sai (se a janela de agora deixou), o pedido conta do envio
      if e ->> 'estado' = 'enfileirada' then
        update public.whatsapp_send_queue set status = 'sent', sent_at = now() where id = (e ->> 'fila_id')::uuid;
      end if;
      v_res := pg_temp.ok(v_res, 'E9e ao sair, o pedido de confirmação da OS conta do envio e o prometido é o dia do plano (se a janela de agora deixou sair)',
        e ->> 'estado' = 'registrada'
        or ((select so.client_confirmation_requested_at is not null from public.service_orders so where so.id = c_os)
            and (select p.prometido_de = v_d and p.prometido_fonte = 'mensagem' from public.os_planejamento p where p.service_order_id = c_os)),
        e ->> 'estado');
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    e := jsonb_build_object();
    begin
      perform pg_temp.ligar(array['pronto']);
      r := public.pedir_confirmacao_do_agendamento(c_os, c_admin);
      e := e || jsonb_build_object('fora_das_ondas', exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-confirmacao' and q.source_ref_id = c_os)
                                                    and not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_os));
      raise exception 'desfaz' using errcode = 'P0096';
    exception when sqlstate 'P0096' then null;
    end;
    begin
      perform pg_temp.ligar();
      delete from public.whatsapp_messages where phone_normalized = '5547900000304';
      e := e || jsonb_build_object('sem_conversa', pg_temp.erro_de(format('select public.pedir_confirmacao_do_agendamento(%L, %L)', c_os, c_admin)),
                                   'nada_gravado', not exists (select 1 from public.agenda_cliente_mensagens m where m.service_order_id = c_os));
      raise exception 'desfaz' using errcode = 'P0096';
    exception when sqlstate 'P0096' then null;
    end;
    v_res := pg_temp.ok(v_res, 'E9f com a confirmação fora das ondas, o botão faz como hoje; a recusa da agenda (o Flávio nunca escreveu) vira o erro com o motivo, e nada fica gravado',
      (e ->> 'fora_das_ondas')::boolean
      and e ->> 'sem_conversa' = 'P0001 Flávio não escreveu para a HBR nos últimos 365 dias: mensagem automática a quem não escreve arrisca o número. Confirme por telefone.'
      and (e ->> 'nada_gravado')::boolean, e::text);

    raise exception 'desfaz tudo' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$e9$;

-- ── E9z. As cópias do D9 só mudam nos blocos "-- FASE 5:" ───────────────────────────────────────────────
do $e9z$
declare
  v_mig0930 text := coalesce(current_setting('agenda_teste.mig_confirmacao', true), '');
  v_mig1012 text := coalesce(current_setting('agenda_teste.mig_confirmacao_1012', true), '');
  -- registrar_confirmacao_do_cliente: as 3 linhas que mudam fora dos blocos (de → para; o montador tem a mesma lista)
  v_troc constant text[][] := array[
    array['   where s.status = ''scheduled'' and s.scheduled_start_at > now() - interval ''2 hours''',
          '   where public._agenda_cliente_dia_a_confirmar(s.id, now()) is not null'],
    array['     and s.client_confirmation_requested_at > now() - interval ''72 hours''',
          '     and s.client_confirmation_requested_at > now() - (public._agenda_cfg()).cliente_resposta_validade'],
    array['  select s.id, s.service_order_number, s.scheduled_start_at, c.name as cliente into v_os',
          '  select s.id, s.service_order_number, public._agenda_cliente_dia_a_confirmar(s.id, now()) as scheduled_start_at, c.name as cliente into v_os']];
  v_velho text[];
  v_novo text[];
  v_n int := 0;
  i int;
  j int;
begin
  if v_mig0930 = '' or v_mig1012 = '' then
    insert into _resultado values ('E9z as cópias do D9', true, 'PULADO: sem agenda_teste.mig_confirmacao(_1012) (rode pela bancada)');
    return;
  end if;
  v_velho := string_to_array(pg_temp.corpo_dd(v_mig0930, 'pedir_confirmacao_do_agendamento'), E'\n');
  v_novo := pg_temp.sem_fase5((select p.prosrc from pg_proc p where p.oid = 'public.pedir_confirmacao_do_agendamento(uuid, uuid)'::regprocedure));
  insert into _resultado values ('E9z-1 a cópia de pedir_confirmacao_do_agendamento só muda nos blocos "-- FASE 5:" (× 20260930130000)',
    v_novo = v_velho and cardinality(v_velho) > 40
    and (select count(*) from regexp_matches((select p.prosrc from pg_proc p where p.oid = 'public.pedir_confirmacao_do_agendamento(uuid, uuid)'::regprocedure),
                                             '-- FASE 5: fim', 'g')) = 4,
    format('linhas %s × %s', array_length(v_novo, 1), array_length(v_velho, 1)));
  v_velho := string_to_array(pg_temp.corpo_dd(v_mig1012, 'registrar_confirmacao_do_cliente'), E'\n');
  for i in 1 .. coalesce(array_length(v_velho, 1), 0) loop
    for j in 1 .. 3 loop
      if v_velho[i] = v_troc[j][1] then
        v_velho[i] := v_troc[j][2];
        v_n := v_n + 1;
      end if;
    end loop;
  end loop;
  v_novo := pg_temp.sem_fase5((select p.prosrc from pg_proc p where p.oid = 'public.registrar_confirmacao_do_cliente(text, text, uuid)'::regprocedure));
  insert into _resultado values ('E9z-2 a cópia de registrar_confirmacao_do_cliente só muda nos blocos "-- FASE 5:" e nas 5 linhas trocadas (× 20261012101000, a mais nova)',
    v_n = 5 and v_novo = v_velho
    and coalesce((select 'search_path=""' = any (p.proconfig) and p.prosecdef from pg_proc p
                    where p.oid = 'public.registrar_confirmacao_do_cliente(text, text, uuid)'::regprocedure), false),
    format('trocas %s; linhas %s × %s', v_n, array_length(v_novo, 1), array_length(v_velho, 1)));
end
$e9z$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
