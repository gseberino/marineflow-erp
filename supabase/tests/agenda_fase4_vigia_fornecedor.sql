-- Prova da vigia do material e da mensagem ao fornecedor da Agenda de Produção, Fase 4 (pacote P5): migration
-- 20261027100500.
-- bancada: depende de 20261027100500
--
--   V0 portas: a rodada só para service_role; o registro, as duas travas do banco e os passos novos para ninguém de fora (o
--      service_role não chama o passo dos terços direto: o único caminho até a fila é a rodada); as leituras para
--      authenticated e service_role; security definer só a rodada, o registro, o enfileirar e o gatilho; search_path fixo;
--      os gatilhos novos da fila só para source agenda-fornecedor; desligado = {rodou: false} e nada gravado
--   V1 a rodada por modo (fixture-fase4): cada passo só com o modo dele; um passo que falha não derruba os outros (vai a
--      app_error_logs, context agenda, action material:<passo>); agenda_vigia_rodadas com rotina material; o sincronizar só
--      em ligado e só das OS que a nota ou a mensagem mudaram nesta rodada
--   T1 os terços nos dias certos (o painel do Nelson: comprado qui 15/10, previsão qua 04/11, 13 dias úteis → qui 22/10 e
--      qua 28/10), uma vez cada; só o terço de agora; prazo de 10 dias úteis não, de 11 sim; a hora fora da janela vai ao
--      próximo dia de janela (pula sábado, domingo e o feriado de 02/11); nunca no dia da previsão
--   T2 sombra só registra (nada na fila; a ação em teste); ligado enfileira (o telefone, o texto, a chave, as tentativas que
--      cabem na janela; a ação "Perguntei à …"); as recusas da 1ª trava: opt-out, cadastro desativado, sem conversa (só a
--      mensagem DELE conta; 0 dias = sem exigência), sábado, domingo, janela, teto por fornecedor no dia e na semana e o
--      total do dia, sem telefone, o telefone do dono e do cliente com OS, wa_test_mode com e sem número de teste
--   T3 a 2ª trava (o gatilho da fila): a inserção por fora sem a mensagem, em sombra, já decidida, com outro texto, outra
--      chave, outro telefone, fora da janela (e a última tentativa), no sábado, acima do teto; a nova tentativa fora da
--      janela falha e volta à hora de antes; a linha não muda de texto, telefone nem origem; as outras origens não mudam;
--      a fila velha (o que não saiu na janela; o modo que saiu de ligado)
--   T4 idempotência: o tique seguinte não duplica a mensagem, a linha da fila nem a ação; o enfileirar de novo não refaz
--   T5 o texto: a mensagem-modelo exata; nenhuma mensagem gerada tem valor, pagamento, OS, link ou o cliente; o registro
--      recusa (22023) cada um deles
--   V2 a carona leva as perguntas da Fase 4 da OS (o Pix) e nunca a de cadastro
--   V3 agenda_saude().material: os zeros obrigatórios e o ok; forçar cada um (vínculo sem o dono, a fila em sombra, fora da
--      janela, acima do teto, texto com valor) dá 1 e o ok cai; o administrador lê; o técnico, como antes, não lê
--   V4 os cadastros: a Kamell repetida e o Mateus sem cidade (fornecedor_cadastro:<id>), a pergunta dos principais
--      (fornecedores_prazo), uma vez; a limpeza quando o dono diz; a Kamell de Itajaí inativa (produção) não pergunta
--   V6 a cópia de agenda_saude só muda nos blocos "-- FASE 4:" e nas 2 linhas da vírgula (× 20261026100300)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase4_vigia_fornecedor.sql
--   Seguro em produção: tudo termina em ROLLBACK. V1–V4 e T1–T5 rodam só na bancada (fixture-fase4; fora dela, PULADO);
--   V6 só com as migrations antigas como texto.
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

-- O bloco "create or replace function public.<nome>(…)" de uma migration: o corpo (entre "as $function$" e "$function$;").
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'as $function$\n' in v) + length(E'as $function$'));
  return left(v, position(E'\n$function$;' in v));
end $f$;

-- O corpo sem os blocos "-- FASE 4: … -- FASE 4: fim" (linhas).
create function pg_temp.sem_fase4(p_corpo text) returns text[] language plpgsql as $f$
declare
  v_b text[] := '{}'; v_bloco boolean := false; l text;
begin
  foreach l in array string_to_array(replace(p_corpo, E'\r\n', E'\n'), E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE 4:' and l !~ '^\s*-- FASE 4: fim' then v_bloco := true; continue; end if;
    if v_bloco then
      if l ~ '^\s*-- FASE 4: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  return v_b;
end $f$;

create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.modos(p_material text, p_detector text, p_fornecedor text) returns void language sql as $f$
  update public.agenda_config set modo_material = p_material, modo_detector = p_detector, modo_fornecedor = p_fornecedor where id
$f$;
create function pg_temp.vig(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_material_vigiar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
-- A linha do painel do Nelson (OS-00112, AliExpress) e a fila do fornecedor.
create function pg_temp.painel() returns uuid language sql stable as $f$
  select m.id from public.os_material m where m.service_order_part_id = md5('peca:112:4')::uuid
$f$;
create function pg_temp.n_fila() returns int language sql stable as $f$
  select count(*)::int from public.whatsapp_send_queue q where q.source = 'agenda-fornecedor'
$f$;
create function pg_temp.msgs() returns jsonb language sql stable as $f$
  select coalesce(jsonb_agg(jsonb_build_object('terco', m.terco, 'modo', m.modo, 'estado', m.estado, 'motivo', m.recusa_motivo,
                                               'enviar_em', to_char(m.enviar_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'))
                            order by m.enviar_em, m.terco, m.criada_em), '[]'::jsonb)
    from public.agenda_fornecedor_mensagens m
$f$;
-- Uma mensagem do WhatsApp (o que o webhook grava).
create function pg_temp.wa(p_fone text, p_dir text, p_em timestamptz) returns void language sql as $f$
  insert into public.whatsapp_messages (direction, phone_normalized, message_type, body, occurred_at, delivery_status)
  values (p_dir, p_fone, 'text', 'mensagem de teste (AG4V)', p_em, case when p_dir = 'inbound' then 'received' else 'read' end)
$f$;
-- O registro direto (a 1ª trava sozinha), numa linha de material qualquer (a chave é por linha e terço).
create function pg_temp.reg(p_forn uuid, p_linha uuid, p_terco int, p_dia date, p_hora text, p_texto text default null)
returns jsonb language sql as $f$
  select public._agenda_fornecedor_registrar(p_forn, p_linha, (select m.service_order_id from public.os_material m where m.id = p_linha),
                                             p_terco, coalesce(p_texto, 'Olá! Aqui é da HBR Marine. A entrega continua prevista? Obrigado!'),
                                             pg_temp.em(p_dia, p_hora))
$f$;
-- As linhas de material da fixture, numeradas (para dar uma chave diferente a cada registro direto).
create function pg_temp.linha(p_n int) returns uuid language sql stable as $f$
  select x.id from (select m.id, row_number() over (order by m.id) as n from public.os_material m) x where x.n = p_n
$f$;

-- ── V0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
do $v0$
declare
  v_res jsonb := '[]'::jsonb;
  f text;
  v_ninguem text[] := array[
    'public._agenda_fornecedor_registrar(uuid, uuid, uuid, integer, text, timestamptz)',
    'public._agenda_fornecedor_enfileirar(uuid)', 'public._agenda_fila_do_fornecedor()',
    'public._agenda_material_fila(date, timestamptz)', 'public._agenda_material_tercos(date, timestamptz)',
    'public._agenda_material_cadastros(date, timestamptz)', 'public._agenda_fornecedor_telefone(uuid)',
    'public._agenda_fornecedor_conversou(uuid, timestamptz)', 'public._agenda_fornecedor_no_periodo(uuid, date, date, uuid)'];
  v_leitura text[] := array[
    'public._agenda_fornecedor_dia_de_janela(date)', 'public._agenda_fornecedor_fora_da_janela(timestamptz, timestamptz)',
    'public._agenda_fornecedor_quando(timestamptz)', 'public._agenda_fornecedor_texto_proibido(text, uuid)',
    'public._agenda_fornecedor_texto(uuid)', 'public.agenda_saude(date, timestamptz)'];
  v_definer text[] := array[
    'public.agenda_material_vigiar(date, timestamptz)',
    'public._agenda_fornecedor_registrar(uuid, uuid, uuid, integer, text, timestamptz)',
    'public._agenda_fornecedor_enfileirar(uuid)', 'public._agenda_fila_do_fornecedor()'];
  v_invoker text[] := array[
    'public._agenda_material_fila(date, timestamptz)', 'public._agenda_material_tercos(date, timestamptz)',
    'public._agenda_material_cadastros(date, timestamptz)', 'public._agenda_fornecedor_telefone(uuid)',
    'public._agenda_fornecedor_conversou(uuid, timestamptz)', 'public._agenda_fornecedor_no_periodo(uuid, date, date, uuid)',
    'public._agenda_fornecedores_principais(date)', 'public._agenda_fornecedor_dia_de_janela(date)',
    'public._agenda_fornecedor_fora_da_janela(timestamptz, timestamptz)', 'public._agenda_fornecedor_quando(timestamptz)',
    'public._agenda_fornecedor_texto_proibido(text, uuid)', 'public._agenda_fornecedor_texto(uuid)',
    'public.agenda_saude(date, timestamptz)'];
  v_ruins text := '';
  r jsonb;
begin
  v_res := pg_temp.ok(v_res, 'V0a a rodada do material: só service_role',
    has_function_privilege('service_role', 'public.agenda_material_vigiar(date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_material_vigiar(date, timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_material_vigiar(date, timestamptz)', 'execute'));
  foreach f in array v_ninguem loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'V0b o registro, as duas travas do banco, os passos novos e o telefone: ninguém de fora (nem o service_role)',
    v_ruins = '', nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'V0c o service_role não chama o passo dos terços direto (o único caminho até a fila é a rodada)',
    pg_temp.como(null, 'service_role', $q$select public._agenda_material_tercos(date '2026-10-28', timestamptz '2026-10-28 10:00-03')::text$q$) like 'erro 42501:%');
  v_ruins := '';
  foreach f in array v_leitura loop
    if has_function_privilege('anon', f, 'execute') or not has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'V0d as leituras e os textos (e a saúde): authenticated e service_role, nunca anon; os principais só service_role',
    v_ruins = '' and has_function_privilege('service_role', 'public._agenda_fornecedores_principais(date)', 'execute')
    and not has_function_privilege('authenticated', 'public._agenda_fornecedores_principais(date)', 'execute')
    and not has_function_privilege('anon', 'public._agenda_fornecedores_principais(date)', 'execute'), nullif(v_ruins, ''));
  v_ruins := '';
  foreach f in array v_definer loop
    if not (select p.prosecdef from pg_proc p where p.oid = f::regprocedure) then v_ruins := v_ruins || f || ' '; end if;
  end loop;
  foreach f in array v_invoker loop
    if (select p.prosecdef from pg_proc p where p.oid = f::regprocedure) then v_ruins := v_ruins || f || ' '; end if;
  end loop;
  foreach f in array v_definer || v_invoker loop
    if coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = f::regprocedure), '') not like '%search_path=%' then
      v_ruins := v_ruins || 'sem search_path: ' || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'V0e security definer só a rodada, o registro, o enfileirar e o gatilho; search_path fixo em todas',
    v_ruins = '', nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'V0f os gatilhos novos da fila: INSERT e UPDATE (hora, texto, telefone, origem, ref, chave), só para source agenda-fornecedor',
    (select count(*) from pg_trigger t where t.tgrelid = 'public.whatsapp_send_queue'::regclass and not t.tgisinternal
       and t.tgfoid = 'public._agenda_fila_do_fornecedor()'::regprocedure
       and pg_get_triggerdef(t.oid) like '%agenda-fornecedor%') = 2,
    (select string_agg(pg_get_triggerdef(t.oid), ' | ') from pg_trigger t
      where t.tgrelid = 'public.whatsapp_send_queue'::regclass and t.tgfoid = 'public._agenda_fila_do_fornecedor()'::regprocedure));
  -- Desligado (a linha nasce assim): a rodada não roda, nada é gravado.
  r := public.agenda_material_vigiar(date '2026-10-28', timestamptz '2026-10-28 10:00-03');
  v_res := pg_temp.ok(v_res, 'V0g os três modos desligados: {rodou: false}, a fila velha rodou, nada gravado (nem a rodada)',
    (select modo_material || modo_detector || modo_fornecedor from public.agenda_config where id) = 'desligadodesligadodesligado'
    and not (r ->> 'rodou')::boolean and r ? 'fila' and (r ->> 'erros')::int = 0
    and not exists (select 1 from public.agenda_fornecedor_mensagens)
    and not exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'material'), r::text);
  perform pg_temp.gravar(v_res);
end
$v0$;

-- ── V1, T1, V4. A rodada, os terços e os cadastros (fixture-fase4) ──────────────────────────────────────
do $v1$
declare
  v_res jsonb := '[]'::jsonb;
  c_ali    constant uuid := 'dd000000-0000-4000-8000-000000000005';
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_ksc    constant uuid := 'dd000000-0000-4000-8000-000000000003';
  c_nelson constant uuid := '05000000-0000-4000-8000-000000000112';
  c_van    constant uuid := '05000000-0000-4000-8000-000000000069';
  d21 constant date := date '2026-10-21';
  d22 constant date := date '2026-10-22';
  d23 constant date := date '2026-10-23';
  d27 constant date := date '2026-10-27';
  d28 constant date := date '2026-10-28';
  d31 constant date := date '2026-10-31';
  r jsonb; r2 jsonb; r3 jsonb;
  v_m jsonb;
  v_txt text;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('V1 a rodada (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');

    -- ── V1: cada passo só com o modo dele
    begin
      perform pg_temp.modos('desligado', 'desligado', 'sombra');
      r := pg_temp.vig(d28, '10:00');
      perform pg_temp.modos('desligado', 'sombra', 'desligado');
      r2 := pg_temp.vig(d28, '10:15');
      perform pg_temp.modos('sombra', 'desligado', 'desligado');
      r3 := pg_temp.vig(d28, '10:30');
      v_res := pg_temp.ok(v_res, 'V1a cada passo só com o modo dele: fornecedor = terços; detector = sinais; material = notas, pix e cadastros (sem sincronizar em sombra); a fila sempre',
        (r ->> 'rodou')::boolean and (select array_agg(k order by k) from jsonb_object_keys(r -> 'contagens') k) = array['fila', 'tercos']
        and (select array_agg(k order by k) from jsonb_object_keys(r2 -> 'contagens') k) = array['fila', 'sinais']
        and (select array_agg(k order by k) from jsonb_object_keys(r3 -> 'contagens') k) = array['cadastros', 'fila', 'notas', 'pix']
        and (r ->> 'erros')::int = 0 and (r2 ->> 'erros')::int = 0 and (r3 ->> 'erros')::int = 0,
        jsonb_build_array(r -> 'contagens', r2 -> 'contagens', r3 -> 'contagens')::text);
      v_res := pg_temp.ok(v_res, 'V1b uma linha em agenda_vigia_rodadas por rodada, rotina material, com os modos e os passos nas contagens',
        (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'material') = 3
        and (select bool_and(x.contagens ? 'modos' and x.contagens ? 'fila' and x.erros = 0 and x.modo_vigia is not null)
               from public.agenda_vigia_rodadas x where x.rotina = 'material')
        and (select x.contagens #>> '{modos,fornecedor}' from public.agenda_vigia_rodadas x
              where x.rotina = 'material' and x.p_agora = pg_temp.em(d28, '10:00')) = 'sombra'
        -- a vigia da Fase 2 continua lendo só as dela
        and (public.agenda_saude(d28, pg_temp.em(d28, '10:31')) #>> '{vigia,rodadas_24h}')::int
            = (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'vigia'
                and x.p_agora > pg_temp.em(d28, '10:31') - interval '1 day' and x.p_agora <= pg_temp.em(d28, '10:31')), null);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- um passo que falha (o Pix, de mentira) não derruba os outros
    begin
      create or replace function public._agenda_material_pix(p_hoje date, p_agora timestamptz) returns jsonb
      language plpgsql as $q$ begin raise exception 'Pix de teste quebrou (AG4V)' using errcode = 'XX000'; end $q$;
      perform pg_temp.modos('sombra', 'sombra', 'sombra');
      r := pg_temp.vig(d28, '10:00');
      v_res := pg_temp.ok(v_res, 'V1c o passo que falha (pix) vai a app_error_logs (agenda / material:pix) e os outros rodam: os terços registraram',
        (r ->> 'erros')::int = 1 and r #>> '{falhas,0,passo}' = 'pix' and r #>> '{falhas,0,sqlstate}' = 'XX000'
        and not (r -> 'contagens' ? 'pix') and r -> 'contagens' ? 'cadastros' and (r #>> '{contagens,tercos,registradas}')::int = 1
        and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'material:pix'
                     and e.message like '%Pix de teste quebrou%')
        and (select x.erros from public.agenda_vigia_rodadas x where x.rotina = 'material') = 1
        and (select count(*) from public.agenda_fornecedor_mensagens) = 1, r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- o sincronizar: só em ligado, só as OS da ação material (nota ou fornecedor) gravada NESTA rodada
    begin
      perform pg_temp.modos('ligado', 'desligado', 'desligado');
      insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto)
      values (pg_temp.em(d28, '10:00'), d28, true, 'nota', 'material', c_nelson, array[c_nelson], '{}', '{}', 'ação desta rodada (AG4V)'),
             (pg_temp.em(d27, '10:00'), d27, true, 'nota', 'material', c_van, array[c_van], '{}', '{}', 'ação de ontem (AG4V)');
      r := pg_temp.vig(d28, '10:00');
      v_res := pg_temp.ok(v_res, 'V1d o sincronizar em ligado: só a OS da ação material desta rodada (a de ontem não)',
        (r #>> '{contagens,sincronizar,oss}')::int = 1 and (r ->> 'erros')::int = 0, r -> 'contagens' ->> 'sincronizar');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── T1: os terços nos dias certos (só o fornecedor em sombra)
    begin
      perform pg_temp.modos('desligado', 'desligado', 'sombra');
      r := pg_temp.vig(d21, '10:00');
      v_res := pg_temp.ok(v_res, 'T1a qua 21/10 (antes do 1º terço): nada',
        (r #>> '{contagens,tercos,alvos}')::int = 0 and not exists (select 1 from public.agenda_fornecedor_mensagens),
        r -> 'contagens' ->> 'tercos');
      r := pg_temp.vig(d22, '10:00');
      r2 := pg_temp.vig(d23, '10:00');
      r3 := pg_temp.vig(d27, '16:00');
      v_res := pg_temp.ok(v_res, 'T1b qui 22/10: o 1º terço, às 10:00 (dentro da janela); sex 23/10 e ter 27/10: o mesmo terço, nada novo',
        pg_temp.msgs() = '[{"terco": 1, "modo": "sombra", "estado": "registrada", "motivo": null, "enviar_em": "22/10 10:00"}]'::jsonb
        and (r2 #>> '{contagens,tercos,ja_existiam}')::int = 1 and (r3 #>> '{contagens,tercos,ja_existiam}')::int = 1,
        pg_temp.msgs()::text);
      r := pg_temp.vig(d28, '19:00');
      v_res := pg_temp.ok(v_res, 'T1c qua 28/10 às 19:00 (fora da janela): o 2º terço, para qui 29/10 às 08:00',
        pg_temp.msgs() -> 1 = '{"terco": 2, "modo": "sombra", "estado": "registrada", "motivo": null, "enviar_em": "29/10 08:00"}'::jsonb
        and jsonb_array_length(pg_temp.msgs()) = 2, pg_temp.msgs()::text);
      r := pg_temp.vig(date '2026-11-03', '10:00');
      r2 := pg_temp.vig(date '2026-11-04', '10:00');
      v_res := pg_temp.ok(v_res, 'T1d ter 03/11 nada novo (o 2º já foi); qua 04/11 (o dia da previsão): não é mais alvo',
        jsonb_array_length(pg_temp.msgs()) = 2 and (r #>> '{contagens,tercos,ja_existiam}')::int = 1
        and (r2 #>> '{contagens,tercos,alvos}')::int = 0, jsonb_build_array(r -> 'contagens', r2 -> 'contagens')::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- só o terço de AGORA: a agenda ligada em qua 28/10 manda só o 2º (o 1º passou)
      perform pg_temp.modos('desligado', 'desligado', 'sombra');
      r := pg_temp.vig(d28, '10:00');
      v_res := pg_temp.ok(v_res, 'T1e ligada em qua 28/10: só o 2º terço (o 1º, que passou, não sai atrasado)',
        pg_temp.msgs() = '[{"terco": 2, "modo": "sombra", "estado": "registrada", "motivo": null, "enviar_em": "28/10 10:00"}]'::jsonb,
        pg_temp.msgs()::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- sábado às 10:00: a hora vai a ter 03/11 (segunda 02/11 é Finados); o tique de ter 03/11 às 19:00 cairia na previsão
      perform pg_temp.modos('desligado', 'desligado', 'sombra');
      r := pg_temp.vig(d31, '10:00');
      v_res := pg_temp.ok(v_res, 'T1f sáb 31/10: a mensagem do 2º terço vai para ter 03/11 às 08:00 (pula o domingo e o feriado de 02/11)',
        pg_temp.msgs() = '[{"terco": 2, "modo": "sombra", "estado": "registrada", "motivo": null, "enviar_em": "03/11 08:00"}]'::jsonb,
        pg_temp.msgs()::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      perform pg_temp.modos('desligado', 'desligado', 'sombra');
      r := pg_temp.vig(date '2026-11-03', '19:00');
      v_res := pg_temp.ok(v_res, 'T1g ter 03/11 às 19:00: sairia qua 04/11, o dia da previsão — não sai (tarde)',
        (r #>> '{contagens,tercos,tarde}')::int = 1 and not exists (select 1 from public.agenda_fornecedor_mensagens),
        r -> 'contagens' ->> 'tercos');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o prazo longo é MAIS de prazo_longo_du (10): 10 dias úteis não; 11 sim (comprado qui 15/10)
      perform pg_temp.modos('desligado', 'desligado', 'sombra');
      update public.os_material set previsao_ate = public.agenda_somar_du(date '2026-10-15', 10) where id = pg_temp.painel();
      r := pg_temp.vig(d28, '10:00');
      update public.os_material set previsao_ate = public.agenda_somar_du(date '2026-10-15', 11) where id = pg_temp.painel();
      r2 := pg_temp.vig(d28, '10:15');
      v_res := pg_temp.ok(v_res, 'T1h prazo de 10 dias úteis não tem terço; de 11 tem',
        (r #>> '{contagens,tercos,alvos}')::int = 0 and (r2 #>> '{contagens,tercos,alvos}')::int = 1
        and public.agenda_du_entre(date '2026-10-15', date '2026-11-04') = 13,
        jsonb_build_array(r -> 'contagens' -> 'tercos', r2 -> 'contagens' -> 'tercos')::text);
      -- sem fornecedor (nem da linha, nem da OC, nem da nota): alvo, mas nada sai
      update public.os_material set fornecedor_id = null, previsao_ate = date '2026-11-04' where id = pg_temp.painel();
      r := pg_temp.vig(date '2026-11-02', '10:00');
      v_res := pg_temp.ok(v_res, 'T1i a linha sem fornecedor: conta como alvo, nada é registrado',
        (r #>> '{contagens,tercos,sem_fornecedor}')::int = 1
        and (select count(*) from public.agenda_fornecedor_mensagens) = 1, r -> 'contagens' ->> 'tercos');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── V4: os cadastros (só o material em sombra)
    begin
      perform pg_temp.modos('sombra', 'desligado', 'desligado');
      r := pg_temp.vig(date '2026-10-30', '10:00');
      v_res := pg_temp.ok(v_res, 'V4a a Kamell repetida (a pergunta é do cadastro de Itajaí, com o de Vila Velha): o texto do banco',
        (select q.texto from public.agenda_perguntas q where q.chave = 'fornecedor_cadastro:' || c_ksc)
          = 'O fornecedor Kamell está cadastrado mais de uma vez: Vila Velha/ES (com CNPJ e 1 produto) e Itajaí/SC (sem CNPJ). Para prever a chegada, conto pelo cadastro de Vila Velha. O de Itajaí é o mesmo fornecedor?'
        and (select q.tipo || '/' || q.modo || '/' || q.estado from public.agenda_perguntas q where q.chave = 'fornecedor_cadastro:' || c_ksc)
            = 'fornecedor_cadastro/sombra/aberta',
        (select q.texto from public.agenda_perguntas q where q.chave = 'fornecedor_cadastro:' || c_ksc));
      v_res := pg_temp.ok(v_res, 'V4b o Mateus sem cidade (sem compra viva: sem a linha no texto); a dos principais, uma (faltam 4), um áudio só',
        (select q.texto from public.agenda_perguntas q where q.chave = 'fornecedor_cadastro:' || c_mateus)
          = 'O fornecedor Mateus está sem cidade no cadastro. Como você compra desse fornecedor e em quantos dias chega?'
        and (select q.texto from public.agenda_perguntas q where q.chave = 'fornecedores_prazo' and q.tipo = 'fornecedores_prazo')
          = 'Para eu prever quando chega o material, me diga como você compra dos fornecedores principais e em quantos dias chega de cada um (faltam 4). Pode ser um áudio só; *agenda fornecedores* mostra a lista com o meu chute pela cidade.'
        and (select count(*) from public.agenda_perguntas q where q.tipo in ('fornecedor_cadastro', 'fornecedores_prazo')) = 3
        and not (select bool_or(q.critica) from public.agenda_perguntas q where q.tipo in ('fornecedor_cadastro', 'fornecedores_prazo')),
        (select string_agg(q.chave || ': ' || q.texto, ' | ' order by q.chave) from public.agenda_perguntas q
          where q.tipo in ('fornecedor_cadastro', 'fornecedores_prazo')));
      r := pg_temp.vig(date '2026-10-30', '10:15');
      v_res := pg_temp.ok(v_res, 'V4c o tique seguinte não pergunta de novo',
        (r #>> '{contagens,cadastros,perguntas}')::int = 0
        and (select count(*) from public.agenda_perguntas q where q.tipo in ('fornecedor_cadastro', 'fornecedores_prazo')) = 3,
        r -> 'contagens' ->> 'cadastros');
      -- o dono disse como compra do Mateus (o *grava* do P1 resolve; aqui a limpeza também, se ele disse por outro caminho)
      update public.suppliers set modalidade = 'entrega_local', prazo_dias_uteis = 1, prazo_fonte = 'dono' where id = c_mateus;
      r := pg_temp.vig(date '2026-10-30', '10:30');
      v_res := pg_temp.ok(v_res, 'V4d com a modalidade dita, a pergunta do Mateus se resolve; a dos principais fica (faltam 3)',
        (select q.estado || ' / ' || q.resolvida_motivo from public.agenda_perguntas q where q.chave = 'fornecedor_cadastro:' || c_mateus)
          = 'resolvida / o cadastro já não tem dúvida'
        and (select q.estado from public.agenda_perguntas q where q.tipo = 'fornecedores_prazo') = 'aberta',
        r -> 'contagens' ->> 'cadastros');
      update public.suppliers set modalidade = 'balcao', prazo_fonte = 'dono' where id = 'dd000000-0000-4000-8000-000000000001';
      r := pg_temp.vig(date '2026-10-30', '10:45');
      v_res := pg_temp.ok(v_res, 'V4e com menos de 3 principais sem a modalidade, a dos principais se resolve',
        (select q.estado || ' / ' || q.resolvida_motivo from public.agenda_perguntas q where q.tipo = 'fornecedores_prazo')
          = 'resolvida / você já disse como compra dos principais', r -> 'contagens' ->> 'cadastros');
      -- a Kamell de Itajaí desativada (como em produção): a pergunta dela se resolve e não volta
      update public.suppliers set active = false where id = c_ksc;
      r := pg_temp.vig(date '2026-10-30', '11:00');
      v_res := pg_temp.ok(v_res, 'V4f a Kamell de Itajaí desativada (produção, NOVO-agenda-36): a pergunta se resolve e nenhuma nova',
        (select q.estado from public.agenda_perguntas q where q.chave = 'fornecedor_cadastro:' || c_ksc) = 'resolvida'
        and (r #>> '{contagens,cadastros,perguntas}')::int = 0, r -> 'contagens' ->> 'cadastros');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- o fornecedor sem cidade COM compra viva: o texto diz de quem se fala; desligado: nada
      update public.os_material set fornecedor_id = c_mateus where id = (select m.id from public.os_material m
        where m.service_order_id = c_van order by m.id limit 1);
      perform pg_temp.modos('sombra', 'desligado', 'desligado');
      r := pg_temp.vig(date '2026-10-30', '10:00');
      v_txt := (select q.texto from public.agenda_perguntas q where q.chave = 'fornecedor_cadastro:' || c_mateus);
      v_res := pg_temp.ok(v_res, 'V4g o Mateus com uma linha do Vanderlei: "— é o do "…" do Vanderlei"; a pergunta ligada à OS',
        v_txt like 'O fornecedor Mateus está sem cidade no cadastro — é o do "%" do Vanderlei. Como você compra desse fornecedor e em quantos dias chega?'
        and (select q.service_order_id from public.agenda_perguntas q where q.chave = 'fornecedor_cadastro:' || c_mateus) = c_van, v_txt);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── V2: a carona (vigia ligada na fixture): o Pix do Vanderlei vai; a de cadastro nunca
    begin
      update public.os_material set fornecedor_id = c_mateus where id = (select m.id from public.os_material m
        where m.service_order_id = c_van order by m.id limit 1);
      perform pg_temp.modos('ligado', 'desligado', 'desligado');
      r := pg_temp.vig(date '2026-10-30', '10:00');
      r2 := public.agenda_carona('aa000000-0000-4000-8000-000000000001', array['Vanderlei'], 'whatsapp', date '2026-10-30',
                                 pg_temp.em(date '2026-10-30', '11:00'));
      v_res := pg_temp.ok(v_res, 'V2a de carona numa conversa sobre o Vanderlei: a pergunta do Pix (Fase 4), não a do cadastro dele',
        r2 ->> 'tipo' = 'pix_material' and r2 ->> 'texto' like 'Aproveitando: O Pix de R$ 480,00 à Premel%'
        and exists (select 1 from public.agenda_perguntas q where q.tipo = 'fornecedor_cadastro' and q.service_order_id = c_van
                     and q.modo = 'ligado' and q.estado = 'aberta'), coalesce(r2::text, 'null'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      -- sem a pergunta do Pix (pix_perguntas_semana_max = 0), a única aberta em ligado do Vanderlei é a de cadastro
      update public.os_material set fornecedor_id = c_mateus where id = (select m.id from public.os_material m
        where m.service_order_id = c_van order by m.id limit 1);
      update public.agenda_config set pix_perguntas_semana_max = 0 where id;
      perform pg_temp.modos('ligado', 'desligado', 'desligado');
      r := pg_temp.vig(date '2026-10-30', '10:00');
      r2 := public.agenda_carona('aa000000-0000-4000-8000-000000000001', array['Vanderlei'], 'whatsapp', date '2026-10-30',
                                 pg_temp.em(date '2026-10-30', '11:00'));
      v_res := pg_temp.ok(v_res, 'V2b a pergunta de cadastro (aberta, em ligado, da OS do Vanderlei) não vai de carona',
        exists (select 1 from public.agenda_perguntas q where q.tipo = 'fornecedor_cadastro' and q.service_order_id = c_van
                 and q.modo = 'ligado' and q.estado = 'aberta')
        and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'pix_material')
        and (r2 is null or r2 ->> 'tipo' not in ('fornecedor_cadastro', 'fornecedores_prazo')), coalesce(r2::text, 'null'));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v1$;

-- ── T2, T4, T5. A 1ª trava, a idempotência e o texto (fixture-fase4) ────────────────────────────────────
do $t2$
declare
  v_res jsonb := '[]'::jsonb;
  c_ali    constant uuid := 'dd000000-0000-4000-8000-000000000005';
  c_toli   constant uuid := 'dd000000-0000-4000-8000-000000000006';
  c_correa constant uuid := 'dd000000-0000-4000-8000-000000000008';
  c_dono   constant uuid := 'dd000000-0000-4000-8000-000000000009';
  c_souper constant uuid := 'dd000000-0000-4000-8000-000000000010';
  c_nelson constant uuid := '05000000-0000-4000-8000-000000000112';
  d28 constant date := date '2026-10-28';
  r jsonb; r2 jsonb; r3 jsonb;
  q record;
  v_m public.agenda_fornecedor_mensagens%rowtype;
  v_txt text;
  v_e text;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('T2 a 1ª trava (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    -- a AliExpress com telefone e contato, e uma mensagem DELA de qui 15/10 (a conversa recente)
    update public.suppliers set phone = '5547900000205', contact_name = 'Lia Souza' where id = c_ali;
    perform pg_temp.wa('5547900000205', 'inbound', timestamptz '2026-10-15 11:00-03');

    -- ── T2a/T5a: sombra só registra
    begin
      perform pg_temp.modos('desligado', 'desligado', 'sombra');
      r := pg_temp.vig(d28, '10:00');
      v_res := pg_temp.ok(v_res, 'T2a sombra: a mensagem só registrada (chave :sombra), nada na fila; a ação em teste (executada = false)',
        pg_temp.msgs() = '[{"terco": 2, "modo": "sombra", "estado": "registrada", "motivo": null, "enviar_em": "28/10 10:00"}]'::jsonb
        and pg_temp.n_fila() = 0
        and (select m.dedupe_key from public.agenda_fornecedor_mensagens m) = 'agenda-fornecedor:terco:' || pg_temp.painel() || ':2:sombra'
        and (select a.texto from public.agenda_acoes a where a.tipo = 'fornecedor' and not a.executada)
            = 'Em teste: eu perguntaria à Aliexpress, qua 28/10, se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11.',
        (select a.texto from public.agenda_acoes a where a.tipo = 'fornecedor'));
      v_res := pg_temp.ok(v_res, 'T5a a mensagem-modelo exata (o contato, quem fala, a empresa sem company_name, o item, o dia da compra, a previsão)',
        (select m.texto from public.agenda_fornecedor_mensagens m)
          = 'Olá, Lia! Aqui é o Gustavo, da HBR Marine. Sobre o pedido de Painel Touch (feito em 15/10): a entrega continua prevista para qua 04/11? Obrigado!',
        (select m.texto from public.agenda_fornecedor_mensagens m));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── T2b/T4: ligado enfileira, uma vez
    begin
      perform pg_temp.modos('desligado', 'desligado', 'ligado');
      insert into public.app_settings (key, value) values ('company_name', 'HBR Marine Solutions')
        on conflict (key) do update set value = excluded.value;
      r := pg_temp.vig(d28, '10:00');
      select x.* into q from public.whatsapp_send_queue x where x.source = 'agenda-fornecedor';
      select m.* into v_m from public.agenda_fornecedor_mensagens m;
      v_res := pg_temp.ok(v_res, 'T2b ligado: enfileirada — o telefone dela, o texto e a chave da mensagem, prioridade 5, às 10:00, 3 tentativas',
        v_m.estado = 'enfileirada' and v_m.modo = 'ligado' and v_m.fila_id = q.id
        and q.phone_normalized = '5547900000205' and q.message = v_m.texto and q.dedupe_key = v_m.dedupe_key
        and q.dedupe_key = 'agenda-fornecedor:terco:' || pg_temp.painel() || ':2' and q.source_ref_id = v_m.id
        and q.priority = 5 and q.max_attempts = 3 and q.scheduled_for = pg_temp.em(d28, '10:00') and q.status = 'pending'
        and v_m.texto like 'Olá, Lia! Aqui é o Gustavo, da HBR Marine Solutions. Sobre o pedido de Painel Touch (feito em 15/10):%',
        to_jsonb(q)::text);
      v_res := pg_temp.ok(v_res, 'T2c a ação que conta no fechamento: tipo fornecedor, origem vigia, executada, sem desfaz, "Perguntei à …"',
        (select a.texto from public.agenda_acoes a where a.tipo = 'fornecedor' and a.executada and a.origem = 'vigia'
            and a.desfazivel_ate is null and a.service_order_id = c_nelson)
          = 'Perguntei à Aliexpress se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11.'
        and exists (select 1 from jsonb_array_elements(public._agenda_mudancas(d28, d28, true, true)) g
                     where g -> 'itens' ? 'Perguntei à Aliexpress se a entrega de "Painel Touch de…" do Nelson continua para qua 04/11.'),
        (select string_agg(a.texto, ' | ') from public.agenda_acoes a where a.tipo = 'fornecedor'));
      r2 := pg_temp.vig(d28, '10:15');
      r3 := public._agenda_fornecedor_enfileirar(v_m.id);
      v_res := pg_temp.ok(v_res, 'T4a o tique seguinte não duplica (mensagem, linha da fila, ação); o enfileirar de novo devolve a mesma linha',
        (r2 #>> '{contagens,tercos,ja_existiam}')::int = 1 and pg_temp.n_fila() = 1
        and (select count(*) from public.agenda_fornecedor_mensagens) = 1
        and (select count(*) from public.agenda_acoes a where a.tipo = 'fornecedor') = 1
        and r3 ->> 'estado' = 'enfileirada' and (r3 ->> 'fila_id')::uuid = q.id, r3::text);
      -- a mesma linha na fila outra vez (a chave): nada entra (a trava recusa a mensagem já decidida)
      v_e := pg_temp.erro_de(format($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id,
                                       scheduled_for, max_attempts, dedupe_key) values (%L, %L, 'agenda-fornecedor', %L, %L, 1, %L)$q$,
                                    q.phone_normalized, q.message, v_m.id, q.scheduled_for, q.dedupe_key));
      v_res := pg_temp.ok(v_res, 'T4b a mesma mensagem na fila de novo, por fora: recusada (42501, já decidida), a fila continua com uma',
        v_e like '42501 A fila do fornecedor só aceita a mensagem que a agenda acabou de decidir mandar%' and pg_temp.n_fila() = 1, v_e);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── T2d: as tentativas que cabem na janela (17:50 → 2; 17:59 → 1)
    begin
      perform pg_temp.modos('desligado', 'desligado', 'ligado');
      r := pg_temp.reg(c_ali, pg_temp.linha(1), 1, d28, '17:50');
      r2 := pg_temp.reg(c_ali, pg_temp.linha(2), 1, date '2026-10-29', '17:59');
      v_res := pg_temp.ok(v_res, 'T2d as tentativas (+5 min) que cabem antes das 18:00: às 17:50, 2; às 17:59, 1',
        r ->> 'estado' = 'enfileirada' and (r ->> 'tentativas')::int = 2
        and r2 ->> 'estado' = 'enfileirada' and (r2 ->> 'tentativas')::int = 1, jsonb_build_array(r, r2)::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── T2e: as recusas da janela (cada uma no seu teste; o registro direto)
    begin
      perform pg_temp.modos('desligado', 'desligado', 'ligado');
      r := jsonb_build_object(
        'sabado', pg_temp.reg(c_ali, pg_temp.linha(1), 1, date '2026-10-31', '10:00') ->> 'motivo',
        'domingo', pg_temp.reg(c_ali, pg_temp.linha(2), 1, date '2026-11-01', '10:00') ->> 'motivo',
        'as_19', pg_temp.reg(c_ali, pg_temp.linha(3), 1, d28, '19:00') ->> 'motivo',
        'as_07_59', pg_temp.reg(c_ali, pg_temp.linha(4), 1, d28, '07:59') ->> 'motivo',
        'as_18', pg_temp.reg(c_ali, pg_temp.linha(5), 1, d28, '18:00') ->> 'motivo');
      v_res := pg_temp.ok(v_res, 'T2e sábado = fim_de_semana; domingo = domingo; 19:00, 07:59 e 18:00 = janela; nada na fila',
        r = '{"sabado": "fim_de_semana", "domingo": "domingo", "as_19": "janela", "as_07_59": "janela", "as_18": "janela"}'::jsonb
        and pg_temp.n_fila() = 0, r::text);
      update public.agenda_config set fornecedor_sabado = true where id;
      r := pg_temp.reg(c_ali, pg_temp.linha(6), 1, date '2026-10-31', '10:00');
      v_res := pg_temp.ok(v_res, 'T2f com fornecedor_sabado, o sábado sai (na mesma janela)', r ->> 'estado' = 'enfileirada', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── T2g: o fornecedor (opt-out, desativado, sem conversa)
    begin
      perform pg_temp.modos('desligado', 'desligado', 'ligado');
      update public.suppliers set opt_out_whatsapp = true where id = c_ali;
      r := pg_temp.reg(c_ali, pg_temp.linha(1), 1, d28, '10:00');
      update public.suppliers set opt_out_whatsapp = false, active = false where id = c_ali;
      r2 := pg_temp.reg(c_ali, pg_temp.linha(2), 1, d28, '10:00');
      -- a Toli: só a HBR escreveu (enviada) e uma mensagem dela de 100 dias atrás
      perform pg_temp.wa('5541900000206', 'outbound', timestamptz '2026-10-27 10:00-03');
      perform pg_temp.wa('5541900000206', 'inbound', timestamptz '2026-07-20 10:00-03');
      r3 := pg_temp.reg(c_toli, pg_temp.linha(3), 1, d28, '10:00');
      v_res := pg_temp.ok(v_res, 'T2g opt-out = opt_out; cadastro desativado = opt_out; só a HBR escreveu, ou a dele tem 100 dias = sem_conversa',
        r ->> 'motivo' = 'opt_out' and r2 ->> 'motivo' = 'opt_out' and r3 ->> 'motivo' = 'sem_conversa' and pg_temp.n_fila() = 0,
        jsonb_build_array(r, r2, r3)::text);
      update public.agenda_config set fornecedor_conversa_dias = 0 where id;
      r := pg_temp.reg(c_toli, pg_temp.linha(4), 1, d28, '10:00');
      v_res := pg_temp.ok(v_res, 'T2h fornecedor_conversa_dias = 0: sem essa exigência (a Toli sai)', r ->> 'estado' = 'enfileirada', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── T2i: o teto (por fornecedor no dia e na semana; o total do dia)
    begin
      perform pg_temp.modos('desligado', 'desligado', 'ligado');
      perform pg_temp.wa('5547900000208', 'inbound', timestamptz '2026-10-20 10:00-03');   -- a Correa conversou
      r := jsonb_build_object(
        'qua_1', pg_temp.reg(c_ali, pg_temp.linha(1), 1, d28, '10:00') ->> 'estado',
        'qua_2', pg_temp.reg(c_ali, pg_temp.linha(2), 1, d28, '11:00') ->> 'motivo',
        'qui', pg_temp.reg(c_ali, pg_temp.linha(3), 1, date '2026-10-29', '10:00') ->> 'estado',
        'sex', pg_temp.reg(c_ali, pg_temp.linha(4), 1, date '2026-10-30', '10:00') ->> 'motivo',
        'seg_seguinte', pg_temp.reg(c_ali, pg_temp.linha(5), 1, date '2026-11-03', '10:00') ->> 'estado');
      v_res := pg_temp.ok(v_res, 'T2i teto: a 2ª à AliExpress no dia = teto; a 2ª da semana sai, a 3ª = teto; a semana seguinte sai',
        r = '{"qua_1": "enfileirada", "qua_2": "teto", "qui": "enfileirada", "sex": "teto", "seg_seguinte": "enfileirada"}'::jsonb
        and pg_temp.n_fila() = 3, r::text);
      update public.agenda_config set fornecedor_total_dia_max = 1 where id;
      r := pg_temp.reg(c_correa, pg_temp.linha(6), 1, d28, '15:00');
      v_res := pg_temp.ok(v_res, 'T2j o total do dia (fornecedor_total_dia_max = 1): a 1ª à Correa no dia em que a AliExpress já recebeu = teto',
        r ->> 'motivo' = 'teto', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── T2k: o telefone (o do dono, o do cliente com OS, sem telefone, wa_test_mode)
    begin
      perform pg_temp.modos('desligado', 'desligado', 'ligado');
      update public.suppliers set active = true where id = c_dono;
      perform pg_temp.wa('5547900000210', 'inbound', timestamptz '2026-10-20 10:00-03');
      perform pg_temp.wa('5547900000211', 'inbound', timestamptz '2026-10-20 10:00-03');
      perform pg_temp.wa('5547900000208', 'inbound', timestamptz '2026-10-20 10:00-03');
      update public.suppliers set phone = null where id = c_correa;
      r := jsonb_build_object(
        'dono', pg_temp.reg(c_dono, pg_temp.linha(1), 1, d28, '10:00') ->> 'motivo',
        'cliente', pg_temp.reg(c_souper, pg_temp.linha(2), 1, d28, '10:00') ->> 'motivo');
      update public.agenda_config set fornecedor_conversa_dias = 0 where id;
      r := r || jsonb_build_object('sem_telefone', pg_temp.reg(c_correa, pg_temp.linha(3), 1, d28, '10:00') ->> 'motivo');
      v_res := pg_temp.ok(v_res, 'T2k o telefone do dono e o do cliente com OS (mesmo cadastrados como fornecedor ativo) e o sem telefone = sem_telefone',
        r = '{"dono": "sem_telefone", "cliente": "sem_telefone", "sem_telefone": "sem_telefone"}'::jsonb and pg_temp.n_fila() = 0, r::text);
      insert into public.app_settings (key, value) values ('wa_test_mode', 'true'), ('wa_test_number', '5547911112222')
        on conflict (key) do update set value = excluded.value;
      r := pg_temp.reg(c_ali, pg_temp.linha(4), 1, d28, '10:00');
      v_res := pg_temp.ok(v_res, 'T2l wa_test_mode: vai ao número de teste (a trava da fila aceita)',
        r ->> 'estado' = 'enfileirada'
        and (select x.phone_normalized from public.whatsapp_send_queue x where x.source = 'agenda-fornecedor') = '5547911112222', r::text);
      delete from public.app_settings where key = 'wa_test_number';
      r := pg_temp.reg(c_ali, pg_temp.linha(5), 1, date '2026-11-03', '10:00');
      v_res := pg_temp.ok(v_res, 'T2m wa_test_mode sem número de teste: nada sai (sem_telefone)', r ->> 'motivo' = 'sem_telefone', r::text);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    -- ── T5b: o que a mensagem nunca leva (o registro recusa) e as geradas
    begin
      perform pg_temp.modos('desligado', 'desligado', 'ligado');
      r := '{}'::jsonb;
      foreach v_txt in array array['Olá! O valor é R$ 30,00.', 'Olá! O pagamento saiu?', 'Olá! Segue o boleto.',
                                   'Olá! Mandei o Pix.', 'Olá! É da OS-00112.', 'Olá! Do ORÇ-00083.',
                                   'Olá! É do barco do Nelson.', 'Olá! Veja http://exemplo.test'] loop
        v_e := pg_temp.erro_de(format('select public._agenda_fornecedor_registrar(%L, %L, %L, 1, %L, %L)', c_ali, pg_temp.linha(1),
                                      c_nelson, v_txt, pg_temp.em(d28, '10:00')));
        r := r || jsonb_build_object(v_txt, v_e);
      end loop;
      v_res := pg_temp.ok(v_res, 'T5b o registro recusa (22023) valor, pagamento, boleto, Pix, OS, orçamento, o cliente e link; nada registrado',
        (select bool_and(e.value #>> '{}' like '22023 A mensagem ao fornecedor não pode levar %') from jsonb_each(r) e)
        and not exists (select 1 from public.agenda_fornecedor_mensagens), r::text);
      -- todas as que as rodadas geram na fixture (sombra e ligado, os dois terços)
      perform pg_temp.vig(date '2026-10-22', '10:00');
      perform pg_temp.modos('desligado', 'desligado', 'sombra');
      perform pg_temp.vig(d28, '10:00');
      v_res := pg_temp.ok(v_res, 'T5c as mensagens geradas: sem R$, pag, boleto, pix, OS-/ORÇ-, o cliente (Nelson) e http',
        (select count(*) from public.agenda_fornecedor_mensagens) = 2
        and not exists (select 1 from public.agenda_fornecedor_mensagens m
                         where m.texto ~* '(R\$|\mpag|boleto|pix|\mOS-|ORÇ-|nelson|http)'
                            or public._agenda_fornecedor_texto_proibido(m.texto, m.service_order_id) is not null),
        (select string_agg(m.texto, ' | ') from public.agenda_fornecedor_mensagens m));
      -- sem previsão e com a nota ligada: as outras formas da mensagem
      update public.os_material set previsao_ate = null, previsao_fonte = null where id = pg_temp.painel();
      v_txt := public._agenda_fornecedor_texto(pg_temp.painel());
      v_res := pg_temp.ok(v_res, 'T5d sem previsão: "qual a previsão de entrega?"',
        v_txt = 'Olá, Lia! Aqui é o Gustavo, da HBR Marine. Sobre o pedido de Painel Touch (feito em 15/10): qual a previsão de entrega? Obrigado!',
        v_txt);
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;

    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$t2$;

-- ── T3. A 2ª trava: o gatilho da fila; e a fila velha (fixture-fase4) ────────────────────────────────────
do $t3$
declare
  v_res jsonb := '[]'::jsonb;
  c_ali constant uuid := 'dd000000-0000-4000-8000-000000000005';
  d28 constant date := date '2026-10-28';
  r jsonb;
  q record;
  v_m public.agenda_fornecedor_mensagens%rowtype;
  v_reg uuid;
  v_som uuid;
  v_e jsonb;
  v_ins text := $q$insert into public.whatsapp_send_queue (phone_normalized, message, source, source_ref_id, scheduled_for,
                                                         max_attempts, dedupe_key) values (%L, %L, 'agenda-fornecedor', %L, %L, %s, %L)$q$;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('T3 a 2ª trava (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.suppliers set phone = '5547900000205', contact_name = 'Lia' where id = c_ali;
    perform pg_temp.wa('5547900000205', 'inbound', timestamptz '2026-10-15 11:00-03');
    perform pg_temp.modos('desligado', 'desligado', 'ligado');
    -- uma mensagem registrada em ligado, ainda não decidida (o teste escreve direto, como um caminho novo faria), e uma em
    -- sombra
    insert into public.agenda_fornecedor_mensagens (id, fornecedor_id, os_material_id, tipo, terco, modo, texto, enviar_em, dedupe_key)
    values ('d4000000-0000-4000-8000-0000000005a1', c_ali, pg_temp.linha(1), 'confirmar_prazo', 1, 'ligado', 'Olá! A entrega continua?',
            pg_temp.em(d28, '10:00'), 'agenda-fornecedor:terco:teste:1'),
           ('d4000000-0000-4000-8000-0000000005a2', c_ali, pg_temp.linha(2), 'confirmar_prazo', 1, 'sombra', 'Olá! A entrega continua?',
            pg_temp.em(d28, '10:00'), 'agenda-fornecedor:terco:teste:1:sombra');
    v_reg := 'd4000000-0000-4000-8000-0000000005a1';
    v_som := 'd4000000-0000-4000-8000-0000000005a2';
    v_e := jsonb_build_object(
      'sem_mensagem', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! A entrega continua?', gen_random_uuid(), pg_temp.em(d28, '10:00'), 1, 'x1')),
      'sem_ref', pg_temp.erro_de($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, scheduled_for, dedupe_key)
                                    values ('5547900000205', 'Olá!', 'agenda-fornecedor', timestamptz '2026-10-28 10:00-03', 'x2')$q$),
      'sombra', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! A entrega continua?', v_som, pg_temp.em(d28, '10:00'), 1,
                                       'agenda-fornecedor:terco:teste:1:sombra')),
      'outro_texto', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! Pode mandar o boleto?', v_reg, pg_temp.em(d28, '10:00'), 1,
                                            'agenda-fornecedor:terco:teste:1')),
      'outra_chave', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! A entrega continua?', v_reg, pg_temp.em(d28, '10:00'), 1, 'x3')),
      'outro_telefone', pg_temp.erro_de(format(v_ins, '5547900000210', 'Olá! A entrega continua?', v_reg, pg_temp.em(d28, '10:00'), 1,
                                               'agenda-fornecedor:terco:teste:1')),
      'as_22', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! A entrega continua?', v_reg, pg_temp.em(d28, '22:00'), 1,
                                      'agenda-fornecedor:terco:teste:1')),
      'ultima_18_05', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! A entrega continua?', v_reg, pg_temp.em(d28, '17:55'), 3,
                                             'agenda-fornecedor:terco:teste:1')),
      'sabado', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! A entrega continua?', v_reg, pg_temp.em(date '2026-10-31', '10:00'), 1,
                                       'agenda-fornecedor:terco:teste:1')));
    v_res := pg_temp.ok(v_res, 'T3a a fila recusa por fora: sem a mensagem, sem ref, em sombra, outro texto, outra chave, outro telefone (42501)',
      v_e ->> 'sem_mensagem' like '42501 A fila do fornecedor só aceita a mensagem registrada%'
      and v_e ->> 'sem_ref' like '42501 A fila do fornecedor só aceita a mensagem registrada%'
      and v_e ->> 'sombra' like '42501 A fila do fornecedor só aceita a mensagem registrada%'
      and v_e ->> 'outro_texto' like '42501 A fila do fornecedor só aceita o texto registrado (nunca mensagem livre)%'
      and v_e ->> 'outra_chave' like '42501 A fila do fornecedor só aceita a mensagem com a chave dela%'
      and v_e ->> 'outro_telefone' like '42501 A fila do fornecedor só aceita o telefone do fornecedor da mensagem%',
      v_e::text);
    v_res := pg_temp.ok(v_res, 'T3b a fila recusa fora da janela (22:00; a 3ª tentativa às 18:05) e no sábado (23514, o motivo no detail)',
      v_e ->> 'as_22' like '23514 Mensagem ao fornecedor fora da janela (08:00 às 18:00, de segunda a sexta): 28/10 22:00. [janela]'
      and v_e ->> 'ultima_18_05' like '23514 Mensagem ao fornecedor fora da janela%[janela]'
      and v_e ->> 'sabado' like '23514 Mensagem ao fornecedor fora da janela%[fim_de_semana]' and pg_temp.n_fila() = 0, v_e::text);
    -- a mesma mensagem, certa: entra
    r := public._agenda_fornecedor_enfileirar(v_reg);
    select x.* into q from public.whatsapp_send_queue x where x.source = 'agenda-fornecedor';
    v_res := pg_temp.ok(v_res, 'T3c a mensagem registrada em ligado, com o texto, a chave e o telefone dela, na janela: entra',
      r ->> 'estado' = 'enfileirada' and q.source_ref_id = v_reg and q.status = 'pending', r::text);
    -- o teto também na fila: outra mensagem registrada à AliExpress no mesmo dia
    insert into public.agenda_fornecedor_mensagens (id, fornecedor_id, os_material_id, tipo, terco, modo, texto, enviar_em, dedupe_key)
    values ('d4000000-0000-4000-8000-0000000005a3', c_ali, pg_temp.linha(3), 'confirmar_prazo', 1, 'ligado', 'Olá! A entrega continua?',
            pg_temp.em(d28, '15:00'), 'agenda-fornecedor:terco:teste:3');
    v_e := jsonb_build_object('teto', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! A entrega continua?',
             'd4000000-0000-4000-8000-0000000005a3', pg_temp.em(d28, '15:00'), 1, 'agenda-fornecedor:terco:teste:3')));
    update public.agenda_fornecedor_mensagens set estado = 'recusada', recusa_motivo = 'teto' where id = 'd4000000-0000-4000-8000-0000000005a3';
    v_e := v_e || jsonb_build_object('ja_decidida', pg_temp.erro_de(format(v_ins, '5547900000205', 'Olá! A entrega continua?',
             'd4000000-0000-4000-8000-0000000005a3', pg_temp.em(date '2026-11-03', '10:00'), 1, 'agenda-fornecedor:terco:teste:3')));
    v_res := pg_temp.ok(v_res, 'T3d a fila recusa acima do teto (23514 teto) e a mensagem já recusada (42501)',
      v_e ->> 'teto' like '23514 Teto de mensagens ao fornecedor (1 por dia, 2 por semana, 5 no dia a todos)%[teto]'
      and v_e ->> 'ja_decidida' like '42501 A fila do fornecedor só aceita a mensagem que a agenda acabou de decidir mandar%',
      v_e::text);
    -- a linha que entrou não muda de texto, telefone nem origem
    v_e := jsonb_build_object(
      'texto', pg_temp.erro_de(format($q$update public.whatsapp_send_queue set message = 'Olá! Mande o boleto.' where id = %L$q$, q.id)),
      'telefone', pg_temp.erro_de(format($q$update public.whatsapp_send_queue set phone_normalized = '5547900000210' where id = %L$q$, q.id)),
      'origem', pg_temp.erro_de(format($q$update public.whatsapp_send_queue set source = 'manual' where id = %L$q$, q.id)),
      'para_fornecedor', pg_temp.erro_de($q$update public.whatsapp_send_queue set source = 'agenda-fornecedor' where source = 'manual'$q$));
    v_res := pg_temp.ok(v_res, 'T3e a linha da fila do fornecedor não muda de texto, telefone, origem; outra linha não vira do fornecedor (42501)',
      (select bool_and(e.value #>> '{}' like '42501 A linha da fila do fornecedor não muda%') from jsonb_each(v_e) e
        where e.key <> 'para_fornecedor')
      and (v_e ->> 'para_fornecedor' = 'sem erro' or v_e ->> 'para_fornecedor' like '42501 A linha da fila do fornecedor não muda%'),
      v_e::text);
    -- a nova tentativa: dentro da janela fica; às 18:03 falha e volta à hora de antes
    update public.whatsapp_send_queue set scheduled_for = pg_temp.em(d28, '10:05'), attempts = 1 where id = q.id;
    v_res := pg_temp.ok(v_res, 'T3f a nova tentativa às 10:05: continua pendente',
      (select x.status = 'pending' and x.scheduled_for = pg_temp.em(d28, '10:05') from public.whatsapp_send_queue x where x.id = q.id));
    update public.whatsapp_send_queue set scheduled_for = pg_temp.em(d28, '18:03'), attempts = 2 where id = q.id;
    v_res := pg_temp.ok(v_res, 'T3g a nova tentativa que cairia às 18:03 vira falha, com a hora de antes (10:05)',
      (select x.status = 'failed' and x.failed_reason like 'agenda-fornecedor:%' and x.scheduled_for = pg_temp.em(d28, '10:05')
         from public.whatsapp_send_queue x where x.id = q.id),
      (select to_jsonb(x)::text from public.whatsapp_send_queue x where x.id = q.id));
    -- as outras origens não mudam: domingo às 23:00, sem mensagem nenhuma
    v_e := jsonb_build_object(
      'manual', pg_temp.erro_de($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, scheduled_for)
                                   values ('5547900000099', 'Olá (AG4V)', 'manual', timestamptz '2026-11-01 23:00-03')$q$),
      'reply_router', pg_temp.erro_de($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, scheduled_for, dedupe_key)
                                         values ('5547900000099', 'Olá (AG4V)', 'reply-router', timestamptz '2026-11-01 23:00-03', 'rr-ag4v')$q$),
      'equipe_sem_mensagem', pg_temp.erro_de($q$insert into public.whatsapp_send_queue (phone_normalized, message, source, scheduled_for, dedupe_key)
                                                values ('5547900000001', 'teste', 'agenda-equipe', timestamptz '2026-10-28 10:00-03', 'eq-ag4v')$q$));
    v_res := pg_temp.ok(v_res, 'T3h as outras origens não mudam: manual e reply-router entram (domingo às 23:00); a da equipe recusa como antes',
      v_e ->> 'manual' = 'sem erro' and v_e ->> 'reply_router' = 'sem erro'
      and v_e ->> 'equipe_sem_mensagem' like '42501 A fila da equipe só aceita%', v_e::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A fila velha: o que não saiu na janela; o modo que saiu de ligado
  begin
    execute current_setting('agenda_teste.fase4');
    update public.suppliers set phone = '5547900000205' where id = c_ali;
    perform pg_temp.wa('5547900000205', 'inbound', timestamptz '2026-10-15 11:00-03');
    perform pg_temp.modos('desligado', 'desligado', 'ligado');
    r := pg_temp.vig(d28, '10:00');
    select x.* into q from public.whatsapp_send_queue x where x.source = 'agenda-fornecedor';
    r := pg_temp.vig(d28, '17:00');
    v_res := pg_temp.ok(v_res, 'T3i fila velha: às 17:00 a linha das 10:00 ainda está na janela (fica)',
      (select x.status from public.whatsapp_send_queue x where x.id = q.id) = 'pending' and (r #>> '{contagens,fila,canceladas}')::int = 0,
      r -> 'contagens' ->> 'fila');
    r := pg_temp.vig(d28, '18:30');
    v_res := pg_temp.ok(v_res, 'T3j fila velha: a linha que o worker não mandou até o fim da janela vira falha às 18:30 e a mensagem fica recusada/janela',
      (select x.status = 'failed' and x.failed_reason = 'agenda-fornecedor: não saiu dentro da janela' from public.whatsapp_send_queue x where x.id = q.id)
      and (select m.estado || '/' || m.recusa_motivo from public.agenda_fornecedor_mensagens m where m.fila_id = q.id) = 'recusada/janela'
      and (r #>> '{contagens,fila,canceladas}')::int = 1, r -> 'contagens' ->> 'fila');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.suppliers set phone = '5547900000205' where id = c_ali;
    perform pg_temp.wa('5547900000205', 'inbound', timestamptz '2026-10-15 11:00-03');
    perform pg_temp.modos('desligado', 'desligado', 'ligado');
    r := pg_temp.vig(d28, '19:00');           -- marcada para qui 29/10 às 08:00
    select x.* into q from public.whatsapp_send_queue x where x.source = 'agenda-fornecedor';
    perform pg_temp.modos('desligado', 'desligado', 'desligado');
    r := pg_temp.vig(d28, '19:15');
    v_res := pg_temp.ok(v_res, 'T3k o dono desliga o fornecedor com a mensagem de amanhã na fila: a rodada não roda, mas a linha vira falha e a mensagem fica recusada/modo',
      not (r ->> 'rodou')::boolean and (r #>> '{fila,pelo_modo}')::int = 1
      and (select x.status from public.whatsapp_send_queue x where x.id = q.id) = 'failed'
      and (select m.estado || '/' || m.recusa_motivo from public.agenda_fornecedor_mensagens m where m.fila_id = q.id) = 'recusada/modo',
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$t3$;

-- ── V3. A saúde: o bloco do material e os zeros obrigatórios (fixture-fase4) ────────────────────────────
do $v3$
declare
  v_res jsonb := '[]'::jsonb;
  c_ali constant uuid := 'dd000000-0000-4000-8000-000000000005';
  d28 constant date := date '2026-10-28';
  r jsonb;
  s jsonb;
  q record;
  v_txt text;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('V3 a saúde (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.suppliers set phone = '5547900000205' where id = c_ali;
    perform pg_temp.wa('5547900000205', 'inbound', timestamptz '2026-10-15 11:00-03');
    perform pg_temp.modos('ligado', 'sombra', 'ligado');
    r := pg_temp.vig(d28, '10:00');
    select x.* into q from public.whatsapp_send_queue x where x.source = 'agenda-fornecedor';
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d28, '10:01') where id = q.id;
    s := public.agenda_saude(d28, pg_temp.em(d28, '10:05'));
    v_res := pg_temp.ok(v_res, 'V3a depois de uma rodada em ligado (uma mensagem enviada às 10:01): os zeros obrigatórios e o ok',
      (s ->> 'ok')::boolean
      and (s #>> '{material,vinculo_sem_resposta_do_dono}')::int = 0 and (s #>> '{material,previsao_sem_original}')::int = 0
      and (s #>> '{material,fornecedor,na_fila_em_sombra}')::int = 0 and (s #>> '{material,fornecedor,fora_da_janela}')::int = 0
      and (s #>> '{material,fornecedor,acima_do_teto}')::int = 0 and (s #>> '{material,fornecedor,com_valor_ou_cliente}')::int = 0
      and (s #>> '{material,fornecedor,enfileiradas_7d}')::int = 1 and (s #>> '{material,rodou_nas_ultimas_2h}')::boolean
      and s #>> '{material,modos,fornecedor}' = 'ligado' and (s #>> '{material,erros_24h}')::int = 0
      and s -> 'material' ? 'cobertura' and s -> 'material' ? 'espera' and s #> '{material,detector}' ? 'pronto_para_ligar'
      and s #> '{material,perguntas,abertas_por_tipo}' ? 'fornecedor_cadastro',
      (s -> 'material')::text);
    -- cada zero forçado dá 1 e derruba o ok (cada um na sua subtransação)
    begin
      update public.os_material set fonte = 'pix', evidencia = '{}' where id = (select m.id from public.os_material m
        where m.service_order_id = '05000000-0000-4000-8000-000000000069' order by m.id limit 1);
      s := public.agenda_saude(d28, pg_temp.em(d28, '10:05'));
      v_res := pg_temp.ok(v_res, 'V3b uma linha ligada a Pix sem a palavra do dono: vinculo_sem_resposta_do_dono = 1 e o ok cai',
        (s #>> '{material,vinculo_sem_resposta_do_dono}')::int = 1 and not (s ->> 'ok')::boolean, s -> 'material' ->> 'vinculo_sem_resposta_do_dono');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      update public.whatsapp_send_queue set sent_at = pg_temp.em(d28, '19:10') where id = q.id;
      s := public.agenda_saude(d28, pg_temp.em(d28, '19:15'));
      v_res := pg_temp.ok(v_res, 'V3c a mensagem que saiu às 19:10 (o worker atrasado): fora_da_janela = 1 e o ok cai',
        (s #>> '{material,fornecedor,fora_da_janela}')::int = 1 and not (s ->> 'ok')::boolean, s #>> '{material,fornecedor}');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      insert into public.agenda_fornecedor_mensagens (fornecedor_id, os_material_id, service_order_id, tipo, terco, modo, texto,
                                                      enviar_em, dedupe_key, fila_id)
      values (c_ali, pg_temp.linha(1), '05000000-0000-4000-8000-000000000112', 'confirmar_prazo', 1, 'sombra',
              'Olá! O Nelson pagou R$ 30,00.', pg_temp.em(d28, '11:00'), 'agenda-fornecedor:terco:teste:1:sombra', gen_random_uuid());
      s := public.agenda_saude(d28, pg_temp.em(d28, '11:05'));
      v_res := pg_temp.ok(v_res, 'V3d uma mensagem em sombra com fila e com valor e cliente: na_fila_em_sombra = 1, com_valor_ou_cliente = 1, o ok cai',
        (s #>> '{material,fornecedor,na_fila_em_sombra}')::int = 1 and (s #>> '{material,fornecedor,com_valor_ou_cliente}')::int = 1
        and not (s ->> 'ok')::boolean, s #>> '{material,fornecedor}');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    begin
      insert into public.agenda_fornecedor_mensagens (fornecedor_id, os_material_id, tipo, terco, modo, texto, enviar_em, dedupe_key,
                                                      estado, fila_id)
      values (c_ali, pg_temp.linha(2), 'confirmar_prazo', 1, 'ligado', 'Olá! A entrega continua?', pg_temp.em(d28, '15:00'),
              'agenda-fornecedor:terco:teste:2', 'enfileirada', gen_random_uuid());
      s := public.agenda_saude(d28, pg_temp.em(d28, '15:05'));
      v_res := pg_temp.ok(v_res, 'V3e duas mensagens à AliExpress que entraram na fila no mesmo dia: acima_do_teto = 1 e o ok cai',
        (s #>> '{material,fornecedor,acima_do_teto}')::int = 1 and not (s ->> 'ok')::boolean, s #>> '{material,fornecedor}');
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    -- o administrador lê pelo painel (a RLS dele); o técnico não recebe 42501 da precisão do detector
    v_txt := pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
      $q$select (public.agenda_saude(date '2026-10-28', timestamptz '2026-10-28 10:05-03') -> 'material')::text$q$);
    v_res := pg_temp.ok(v_res, 'V3f o administrador lê o bloco material (com a precisão do detector)',
      v_txt not like 'erro%' and (v_txt::jsonb #> '{detector}') ? 'julgados_14d'
      and (v_txt::jsonb #>> '{detector,julgados_14d}') is not null, v_txt);
    v_txt := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
      $q$select (public.agenda_saude(date '2026-10-28', timestamptz '2026-10-28 10:05-03') -> 'material' -> 'detector')::text$q$);
    v_res := pg_temp.ok(v_res, 'V3g o técnico continua sem ler a saúde como na Fase 3 (agenda_config é fechada a ele: P0002), nunca o 42501 da precisão',
      v_txt like 'erro P0002:%', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$v3$;

-- ── V6. A cópia de agenda_saude só muda nos blocos "-- FASE 4:" (× 20261026100300) ──────────────────────
do $v6$
declare
  v_mig text := coalesce(current_setting('agenda_teste.mig_equipe_fase3', true), '');
  v_velho text[];
  v_novo text[];
  v_troc constant text[][] := array[
    array['          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0,',
          '          and v_teto = 0 and v_janela = 0 and v_semconf = 0 and v_sobre = 0 and coalesce(v_semrec, 0) = 0 and v_pay = 0'],
    array['    ''modos_fase3'', jsonb_build_object(''equipe'', cf.modo_equipe, ''diaria'', cf.modo_diaria));',
          '    ''modos_fase3'', jsonb_build_object(''equipe'', cf.modo_equipe, ''diaria'', cf.modo_diaria),']];
  i int;
  j int;
  v_n int := 0;
begin
  if v_mig = '' then
    insert into _resultado values ('V6 a cópia de agenda_saude', true, 'PULADO: sem agenda_teste.mig_equipe_fase3 (rode pela bancada)');
    return;
  end if;
  v_velho := string_to_array(pg_temp.corpo(v_mig, 'agenda_saude'), E'\n');
  for i in 1 .. coalesce(array_length(v_velho, 1), 0) loop
    for j in 1 .. 2 loop
      if v_velho[i] = v_troc[j][1] then
        v_velho[i] := v_troc[j][2];
        v_n := v_n + 1;
      end if;
    end loop;
  end loop;
  v_novo := pg_temp.sem_fase4((select p.prosrc from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure));
  insert into _resultado values ('V6 a cópia de agenda_saude só muda nos blocos "-- FASE 4:" e nas 2 linhas da vírgula (× 20261026100300)',
    v_n = 2 and v_novo = v_velho
    and (select count(*) from regexp_matches((select p.prosrc from pg_proc p where p.oid = 'public.agenda_saude(date, timestamptz)'::regprocedure),
                                             '-- FASE 4: fim', 'g')) = 4,
    format('trocas %s; linhas %s × %s', v_n, array_length(v_novo, 1), array_length(v_velho, 1)));
end
$v6$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
