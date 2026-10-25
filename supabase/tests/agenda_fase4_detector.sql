-- Prova do detector da conversa do fornecedor da Agenda de Produção, Fase 4 (pacote P4): migration 20261027100400.
-- bancada: depende de 20261027100400
--
--   D0 portas: a leitura das mensagens, o registro do sinal, o passo e as auxiliares só para service_role; a precisão para
--      authenticated (o técnico recebe 42501); o desfazer do material sem grant; nunca anon; security definer só a leitura,
--      o registro e os desfazeres (e o gatilho do original); search_path fixo; desligado = nada (lista vazia, {pulado})
--   D1 quem é lido (fixture-fase4): só o fornecedor com compra viva (o contador e a Toli sem compra não); o telefone do dono,
--      da equipe e do cliente com OS nunca, mesmo cadastrado como fornecedor ativo com OC (NOVO-agenda-34/35); opt-out não;
--      fora da janela de detector_janela_horas, depois de agora ou já com sinal não; as compras de cada um no rótulo sem
--      valor; o "Recebeu o compressor?" de 20/10 com o material já na mão não vira pergunta
--   D2 o sinal: a data pela expressão no dia da MENSAGEM em Brasília (não no p_hoje): amanhã, faixa, "3 a 5 dias úteis" com
--      Finados, "5 dias" (úteis), corridos, despacho pelo prazo do fornecedor (Kamell: 4 dias úteis), sem classe = sem data,
--      expressão ruim = "não entendi a data"; uma vez por mensagem e tipo; a escolhida só se for candidata; tipo errado 22023
--   D3 o replay da OS-00104 (a conversa real, tique a tique): às 14:15 a chegada condicional espera; às 17:30 o "Já foi
--      coletado" sai com a previsão qua 14/10, fonte fornecedor, os dois trechos; em sombra nada muda; em ligado a linha fica
--      a caminho (nível B), o original guardado e a ação material com o *desfaz*, no "o que mudou"; a sincronização do dia
--      seguinte não apaga; a condição que não se confirma sai
--   D4 o que vira pergunta: mais de uma compra (as opções), o modelo que escolheu (não grava sozinho), a linha em falta (com a
--      data), o material desligado (não pergunta), o que a HBR disse sem compra ligada (não pergunta); a resposta do dono pelo
--      aviso (P3) grava a previsão da mensagem
--   D5 o "Recebeu o compressor?" vira o chegou? uma vez (o 2º não), sem duplicar o da vigia da Fase 2 (nos dois sentidos); a
--      limpeza o mantém até a linha chegar
--   D6 o julgamento pelo fato (certo, errado, sem como saber, a previsão do dono, a outra compra) e agenda_detector_precisao
--      (o portão: 5 conferidas e 70% — com menos, continua em teste)
--   D7 o desfazer: *desfaz OS-00104* volta a linha inteira (o original junto) e julga o sinal errado; a linha que mudou depois
--      recusa e nada muda; passou o prazo recusa; a chegada pela nota (P3) volta e a nota deixa de valer para a linha
--   D8 as cópias só acrescentam os blocos "-- FASE 4:" (agenda_desfazer × 20261026100300; _agenda_vigia_limpeza e
--      _agenda_vigia_chegou × 20261025100300; _os_material_previsao_original × 20261027100000; _agenda_data_um ×
--      20261024160100, C1)
--   D9 C1 da revisão da Fase 4: a única compra de verdade (a OC de estoque, a nota sem resposta e o Pix aberto do
--      fornecedor rebaixam unico para nenhum); o pedido da HBR descartado (a chegada que ela afirma continua); o despacho
--      com o prazo chutado pela cidade vira pergunta (nunca o nível B, nem pela resposta do dono) e não entra na precisão;
--      com o prazo do dono, a previsão vale. (D1h/D1i: o WhatsApp do cliente e outras_vivas; D2k–D2n: o dia útil e o dia da
--      semana com o número; D6d: a previsão do dono não julga)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase4_detector.sql
--   Seguro em produção: tudo termina em ROLLBACK. D1–D7 rodam só na bancada (fixture-fase4 e o replay; fora dela, PULADO);
--   D8 só com as migrations antigas como texto.
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

-- Uma mensagem do WhatsApp (o que o webhook grava).
create function pg_temp.msg(p_id uuid, p_fone text, p_dir text, p_texto text, p_em timestamptz) returns uuid language sql as $f$
  insert into public.whatsapp_messages (id, direction, phone_normalized, message_type, body, occurred_at, delivery_status)
  values (p_id, p_dir, p_fone, 'text', p_texto, p_em, case when p_dir = 'inbound' then 'received' else 'read' end)
  returning id
$f$;

-- O registro como o acompanhar-conversas faz (o parser já achou tipo/expressão; as candidatas são as linhas dadas).
create function pg_temp.reg(p_msg uuid, p_forn uuid, p_tipo text, p_expr text, p_cond boolean, p_trecho text, p_linhas uuid[],
                            p_casou text, p_escolhida uuid, p_hoje date, p_agora timestamptz) returns jsonb language sql as $f$
  select public.material_sinal_registrar(p_msg, p_forn, p_tipo, p_expr, p_cond, p_trecho,
           coalesce((select jsonb_agg(jsonb_build_object('n', t.o, 'os', m.service_order_id, 'os_material_id', m.id,
                                                         'rotulo', 'rótulo ' || t.o) order by t.o)
                       from unnest(p_linhas) with ordinality t(l, o) join public.os_material m on m.id = t.l), '[]'::jsonb),
           p_escolhida, p_casou, null, p_hoje, p_agora)
$f$;

-- A linha do compressor (a da OC-00004).
create function pg_temp.compressor() returns uuid language sql stable as $f$
  select m.id from public.os_material m where m.purchase_order_item_id = '71000000-0000-4000-8000-000000000001'
$f$;

-- Fotografia das linhas de material (sem a hora da última mudança).
create function pg_temp.foto_material() returns text language sql stable as $f$
  select md5(coalesce(string_agg((to_jsonb(m) - 'atualizado_em')::text, '|' order by m.id), '')) from public.os_material m
$f$;

-- ── D0. Portas ──────────────────────────────────────────────────────────────────────────────────────────
do $d0$
declare
  v_res jsonb := '[]'::jsonb;
  f text;
  v_so_service text[] := array[
    'public._agenda_chave_telefone(text)', 'public._agenda_fones_que_nao_sao_fornecedor()',
    'public._agenda_compras_vivas(date)', 'public.agenda_mensagens_de_fornecedor(date, timestamptz)',
    'public.material_sinal_registrar(uuid, uuid, text, text, boolean, text, jsonb, uuid, text, numeric, date, timestamptz)',
    'public._agenda_material_sinais(date, timestamptz)', 'public._agenda_fornecedor_outras_vivas(uuid, date, timestamptz)'];
  v_definer text[] := array[
    'public.agenda_mensagens_de_fornecedor(date, timestamptz)',
    'public.material_sinal_registrar(uuid, uuid, text, text, boolean, text, jsonb, uuid, text, numeric, date, timestamptz)',
    'public._agenda_desfazer_material(uuid, uuid, text, date, timestamptz)',
    'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'public._os_material_previsao_original()'];
  v_invoker text[] := array[
    'public._agenda_chave_telefone(text)', 'public._agenda_fones_que_nao_sao_fornecedor()',
    'public._agenda_compras_vivas(date)', 'public._agenda_material_sinais(date, timestamptz)',
    'public._agenda_fornecedor_outras_vivas(uuid, date, timestamptz)', 'public._agenda_data_um(text, date, text, boolean, date, date)',
    'public.agenda_detector_precisao(date, date)', 'public._agenda_vigia_limpeza(date, timestamptz)',
    'public._agenda_vigia_chegou(date, timestamptz)'];
  v_ruins text := '';
  r jsonb;
begin
  foreach f in array v_so_service loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')
       or not has_function_privilege('service_role', f, 'execute') then
      v_ruins := v_ruins || f || ' ';
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'D0a a leitura das mensagens, o registro do sinal, o passo e as auxiliares: só service_role',
    v_ruins = '', nullif(v_ruins, ''));
  v_res := pg_temp.ok(v_res, 'D0b a precisão: authenticated e service_role, nunca anon',
    has_function_privilege('authenticated', 'public.agenda_detector_precisao(date, date)', 'execute')
    and has_function_privilege('service_role', 'public.agenda_detector_precisao(date, date)', 'execute')
    and not has_function_privilege('anon', 'public.agenda_detector_precisao(date, date)', 'execute'));
  v_res := pg_temp.ok(v_res, 'D0c o desfazer do material sem grant a ninguém de fora; agenda_desfazer só service_role; a vigia recriada fechada',
    not has_function_privilege('anon', 'public._agenda_desfazer_material(uuid, uuid, text, date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public._agenda_desfazer_material(uuid, uuid, text, date, timestamptz)', 'execute')
    and not has_function_privilege('service_role', 'public._agenda_desfazer_material(uuid, uuid, text, date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'execute')
    and has_function_privilege('service_role', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', 'execute')
    and not has_function_privilege('service_role', 'public._agenda_vigia_limpeza(date, timestamptz)', 'execute')
    and not has_function_privilege('service_role', 'public._agenda_vigia_chegou(date, timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public._os_material_previsao_original()', 'execute'));
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
  v_res := pg_temp.ok(v_res, 'D0d security definer só a leitura, o registro, os desfazeres e o gatilho do original; search_path fixo em todas',
    v_ruins = '', nullif(v_ruins, ''));
  -- O técnico (login que não é administrador nem financeiro) recebe 42501; o administrador lê.
  v_res := pg_temp.ok(v_res, 'D0e a precisão: o técnico recebe 42501; o administrador lê o texto',
    pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
      $q$select public.agenda_detector_precisao(date '2026-10-13', date '2026-10-26')::text$q$) like 'erro 42501:%'
    and pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
      $q$select public.agenda_detector_precisao(date '2026-10-13', date '2026-10-26') ->> 'texto'$q$)
        = 'De ter 13/10 a seg 26/10 não li mensagem de fornecedor com prazo. Continua em teste: preciso de pelo menos 5 conferidas, com 70% de acerto.',
    pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
      $q$select public.agenda_detector_precisao(date '2026-10-13', date '2026-10-26') ->> 'texto'$q$));
  -- Desligado (a linha nasce assim): a lista vazia, o registro e o passo pulados, nada gravado.
  r := public.material_sinal_registrar(gen_random_uuid(), null, 'despacho', null, false, 'Já foi coletado', '[]'::jsonb, null,
                                       'nenhum', null, date '2026-10-13', timestamptz '2026-10-13 18:00-03');
  v_res := pg_temp.ok(v_res, 'D0f modo_detector desligado: [] / {pulado} / {pulado}, nada gravado',
    (select modo_detector from public.agenda_config where id) = 'desligado'
    and public.agenda_mensagens_de_fornecedor(date '2026-10-13', timestamptz '2026-10-13 18:00-03') = '[]'::jsonb
    and r = '{"pulado": true}'::jsonb
    and public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 18:00-03') = '{"pulado": true}'::jsonb
    and not exists (select 1 from public.material_sinais), r::text);
  perform pg_temp.gravar(v_res);
end
$d0$;

-- ── D1. Quem é lido (fixture-fase4, sex 30/10, 10:00) ───────────────────────────────────────────────────
do $d1$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-30';
  c_agora  constant timestamptz := timestamptz '2026-10-30 10:00-03';
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_kes    constant uuid := 'dd000000-0000-4000-8000-000000000002';
  v_l jsonb;
  v_ids text[];
  v_r jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('D1 quem é lido (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.agenda_config set modo_detector = 'sombra' where id;
    -- O dono como fornecedor ATIVO e com OC aberta (o telefone dele é o que segura); a Souper (o telefone do Rodrigo, cliente
    -- com OS) com OC aberta; um fornecedor com o telefone do Roberto (payee); um com opt-out; o contador sem compra.
    update public.suppliers set active = true where id = 'dd000000-0000-4000-8000-000000000009';
    insert into public.suppliers (id, name, phone, active, opt_out_whatsapp) values
      ('dd000000-0000-4000-8000-0000000004f1', 'SR CONTABILIDADE (AG4D)', '5547900000241', true, false),
      ('dd000000-0000-4000-8000-0000000004f2', 'ROBERTO PECAS (AG4D)', '5547900000001', true, false),
      ('dd000000-0000-4000-8000-0000000004f3', 'NAO ME MANDE (AG4D)', '5547900000243', true, true);
    insert into public.purchase_orders (id, po_number, status, supplier_id, created_at, updated_at)
    select ('d4000000-0000-4000-8000-0000000004b' || x.n)::uuid, 'OC-AG4D-' || x.n, 'draft', x.f::uuid,
           timestamptz '2026-10-29 10:00-03', timestamptz '2026-10-29 10:00-03'
      from (values (1, 'dd000000-0000-4000-8000-000000000009'), (2, 'dd000000-0000-4000-8000-000000000010'),
                   (3, 'dd000000-0000-4000-8000-0000000004f2'), (4, 'dd000000-0000-4000-8000-0000000004f3')) x(n, f);
    -- As mensagens, todas com prazo (qui 29/10, 15:00), de cada telefone.
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a1', '5547900000201', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a2', '5547900000202', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a3', '5547900000210', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a4', '5547900000211', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a5', '5547900000001', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a6', '5547900000241', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a7', '5547900000243', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a8', '5547900000201', 'inbound', 'Chega amanhã', timestamptz '2026-10-27 09:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004a9', '5547900000201', 'inbound', 'Chega amanhã', timestamptz '2026-10-30 11:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004aa', '5547900000201', 'outbound', 'chega aqui sexta?', timestamptz '2026-10-29 16:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004ab', '5541900000206', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');
    -- (C1 da revisão, item 10) o WhatsApp do cliente com OS (clients.whatsapp, diferente do telefone dele) num fornecedor
    -- ativo com OC aberta: também nunca é lido.
    update public.clients set whatsapp = '5547900000244' where id = 'c1000000-0000-4000-8000-000000000001';
    insert into public.suppliers (id, name, phone, active, opt_out_whatsapp) values
      ('dd000000-0000-4000-8000-0000000004f4', 'WHATS DO CLIENTE (AG4D)', '5547900000244', true, false);
    insert into public.purchase_orders (id, po_number, status, supplier_id, created_at, updated_at)
    values ('d4000000-0000-4000-8000-0000000004b5', 'OC-AG4D-5', 'draft', 'dd000000-0000-4000-8000-0000000004f4',
            timestamptz '2026-10-29 10:00-03', timestamptz '2026-10-29 10:00-03');
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004ac', '5547900000244', 'inbound', 'Chega amanhã', timestamptz '2026-10-29 15:00-03');

    v_l := public.agenda_mensagens_de_fornecedor(c_hoje, c_agora);
    v_ids := array(select e ->> 'msg_id' from jsonb_array_elements(v_l) e);
    v_res := pg_temp.ok(v_res, 'D1a só o Mateus (OC-00004 aberta) e a Kamell (o Cerbo em falta): as duas direções, em ordem',
      v_ids = array['d4000000-0000-4000-8000-0000000004a1', 'd4000000-0000-4000-8000-0000000004a2',
                    'd4000000-0000-4000-8000-0000000004aa'], array_to_string(v_ids, ', '));
    v_res := pg_temp.ok(v_res, 'D1b o dono, o Rodrigo (cliente com OS) e o Roberto (equipe) nunca, mesmo como fornecedor ativo com OC',
      not (v_ids && array['d4000000-0000-4000-8000-0000000004a3', 'd4000000-0000-4000-8000-0000000004a4',
                         'd4000000-0000-4000-8000-0000000004a5']));
    v_res := pg_temp.ok(v_res, 'D1c sem compra viva não lê (o contador, a Toli); opt-out não; fora da janela de 48 h e depois de agora não',
      not (v_ids && array['d4000000-0000-4000-8000-0000000004a6', 'd4000000-0000-4000-8000-0000000004ab',
                         'd4000000-0000-4000-8000-0000000004a7', 'd4000000-0000-4000-8000-0000000004a8',
                         'd4000000-0000-4000-8000-0000000004a9']));
    v_res := pg_temp.ok(v_res, 'D1d as compras de cada um: a Kamell com o Cerbo do Nelson (sem valor); o Mateus sem linha viva (o compressor está na mão)',
      (select jsonb_agg(c ->> 'rotulo') from jsonb_array_elements(v_l) e, jsonb_array_elements(e -> 'compras') c
        where e ->> 'msg_id' = 'd4000000-0000-4000-8000-0000000004a2') = '["Nelson: Central de controle… (a comprar)"]'::jsonb
      and (select jsonb_array_length(e -> 'compras') from jsonb_array_elements(v_l) e
            where e ->> 'msg_id' = 'd4000000-0000-4000-8000-0000000004a1') = 0
      and (select e ->> 'fornecedor' || '/' || (e ->> 'direcao') from jsonb_array_elements(v_l) e
            where e ->> 'msg_id' = 'd4000000-0000-4000-8000-0000000004aa') = 'Mateus/enviada'
      and position('R$' in v_l::text) = 0,
      v_l::text);
    v_res := pg_temp.ok(v_res, 'D1h (C1) o WhatsApp do cliente com OS (clients.whatsapp) nunca é lido nem recebe a pergunta ao fornecedor',
      not (v_ids && array['d4000000-0000-4000-8000-0000000004ac'])
      and public._agenda_fornecedor_telefone('dd000000-0000-4000-8000-0000000004f4') is null
      and exists (select 1 from public._agenda_fones_que_nao_sao_fornecedor() k where k = '00000244'),
      array_to_string(v_ids, ', '));
    v_res := pg_temp.ok(v_res, 'D1i (C1) outras_vivas: o Mateus tem a OC-00004 aberta sem linha viva (o compressor está na mão) = 1; a Kamell, só o Cerbo = 0',
      (select (e ->> 'outras_vivas')::int from jsonb_array_elements(v_l) e
        where e ->> 'msg_id' = 'd4000000-0000-4000-8000-0000000004a1') = 1
      and (select (e ->> 'outras_vivas')::int from jsonb_array_elements(v_l) e
            where e ->> 'msg_id' = 'd4000000-0000-4000-8000-0000000004a2') = 0,
      v_l::text);
    -- A mensagem que já virou sinal sai da lista.
    perform pg_temp.reg('d4000000-0000-4000-8000-0000000004a2', c_kes, 'chegada', 'amanhã', false, 'Chega amanhã', '{}', 'nenhum',
                        null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D1e a mensagem que já tem sinal não volta',
      not exists (select 1 from jsonb_array_elements(public.agenda_mensagens_de_fornecedor(c_hoje, c_agora)) e
                   where e ->> 'msg_id' = 'd4000000-0000-4000-8000-0000000004a2'));
    -- desligado: nada
    update public.agenda_config set modo_detector = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'D1f desligado: lista vazia',
      public.agenda_mensagens_de_fornecedor(c_hoje, c_agora) = '[]'::jsonb);
    -- O "Recebeu o compressor? Deu tudo certo?" de ter 20/10 (fixture-fase4): lido em 20/10, o compressor já está na mão
    -- (desde qua 14/10) — não vira pergunta.
    update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado' where id;
    v_l := public.agenda_mensagens_de_fornecedor(date '2026-10-20', timestamptz '2026-10-20 10:30-03');
    v_r := pg_temp.reg('d4000000-0000-4000-8000-000000000420', c_mateus, 'perguntou_chegou', null, false, 'Recebeu o compressor?',
                       array[pg_temp.compressor()], 'unico', pg_temp.compressor(), date '2026-10-20', timestamptz '2026-10-20 10:30-03');
    perform public._agenda_material_sinais(date '2026-10-20', timestamptz '2026-10-20 10:30-03');
    v_res := pg_temp.ok(v_res, 'D1g a fixture-fase4 tem a conversa do Mateus (20/10); com o compressor na mão, o "Recebeu?" não pergunta',
      exists (select 1 from jsonb_array_elements(v_l) e where e ->> 'msg_id' = 'd4000000-0000-4000-8000-000000000420')
      and (select s.estado || ' / ' || s.motivo from public.material_sinais s where s.id = (v_r ->> 'id')::uuid)
          = 'descartado / o material já está na mão'
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'chegou' and q.chave like 'chegou:fornecedor:%'),
      (select s.estado || ' / ' || coalesce(s.motivo, '-') from public.material_sinais s where s.id = (v_r ->> 'id')::uuid));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d1$;

-- ── D2. O sinal: a data pela expressão, no dia da mensagem ──────────────────────────────────────────────
do $d2$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje   constant date := date '2026-10-30';
  c_agora  constant timestamptz := timestamptz '2026-10-30 10:00-03';
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_kes    constant uuid := 'dd000000-0000-4000-8000-000000000002';
  c_toli   constant uuid := 'dd000000-0000-4000-8000-000000000006';
  r jsonb; r2 jsonb;
  v_cerbo uuid;
  v_painel uuid;
  v_err text;
begin
  if coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('D2 o sinal (fixture-fase4)', true, 'PULADO: sem agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.fase4');
    update public.agenda_config set modo_detector = 'sombra' where id;
    v_cerbo := (select m.id from public.os_material m where m.service_order_part_id = md5('peca:112:2')::uuid);
    v_painel := (select m.id from public.os_material m where m.service_order_part_id = md5('peca:112:4')::uuid);

    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c1', '5547900000202', 'inbound', 'Despachado hoje', timestamptz '2026-10-26 16:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004c1', c_kes, 'despacho', null, false, 'Despachado hoje', array[v_cerbo],
                     'unico', v_cerbo, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2a despacho da Kamell seg 26/10: o prazo dela (outro estado, 4 dias úteis) = sex 30/10; a escolhida, unico',
      r ->> 'data_ate' = '2026-10-30' and r ->> 'data_de' = '2026-10-30' and (r ->> 'novo')::boolean
      and (select s.casou_por || ' ' || s.os_material_id || ' ' || s.dia || ' ' || s.direcao || ' ' || s.modo
             from public.material_sinais s where s.id = (r ->> 'id')::uuid)
          = format('unico %s 2026-10-26 recebida sombra', v_cerbo), r::text);
    -- de novo: o mesmo sinal (uma vez por mensagem e tipo)
    r2 := pg_temp.reg('d4000000-0000-4000-8000-0000000004c1', c_kes, 'despacho', null, false, 'Despachado hoje', array[v_cerbo],
                      'unico', v_cerbo, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2b o mesmo sinal de novo: novo = false, uma linha só',
      not (r2 ->> 'novo')::boolean and r2 ->> 'id' = r ->> 'id'
      and (select count(*) from public.material_sinais where whatsapp_message_id = 'd4000000-0000-4000-8000-0000000004c1') = 1);

    -- "amanhã" dito ter 27/10 às 23:30 de Brasília (já 28/10 em UTC): é o dia da MENSAGEM em Brasília, não o p_hoje
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c2', '5547900000201', 'inbound', 'Chega amanhã', timestamptz '2026-10-27 23:30-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004c2', c_mateus, 'chegada', 'amanhã', false, 'Chega amanhã', '{}', 'nenhum',
                     null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2c "amanhã" dito ter 27/10 às 23:30 = qua 28/10 (o dia da mensagem em Brasília, não o p_hoje)',
      r ->> 'data_ate' = '2026-10-28' and (select s.dia from public.material_sinais s where s.id = (r ->> 'id')::uuid) = date '2026-10-27',
      r::text);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c3', '5547900000201', 'inbound', 'dava para entregar na sexta ou no sábado',
                        timestamptz '2026-10-28 09:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004c3', c_mateus, 'chegada', 'sexta ou sábado', false,
                     'dava para entregar na sexta ou no sábado', '{}', 'nenhum', null, c_hoje, c_agora);
    -- (C1 da revisão, item 12) o sábado vai ao próximo dia útil: seg 02/11 é Finados, então ter 03/11
    v_res := pg_temp.ok(v_res, 'D2d a faixa "sexta ou sábado" dita qua 28/10 = sex 30/10 a ter 03/11 (o sábado vai ao dia útil; seg 02/11 é Finados)',
      r ->> 'data_de' = '2026-10-30' and r ->> 'data_ate' = '2026-11-03', r::text);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c4', '5541900000206', 'inbound', 'De 3 a 5 dias úteis', timestamptz '2026-10-30 09:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004c4', c_toli, 'prazo', '3 a 5 dias úteis', false, 'De 3 a 5 dias úteis', '{}',
                     'nenhum', null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2e "3 a 5 dias úteis" dito sex 30/10 (Finados na seg 02/11) = qui 05/11 a seg 09/11',
      r ->> 'data_de' = '2026-11-05' and r ->> 'data_ate' = '2026-11-09'
      and r ->> 'data_de' = public.agenda_somar_du(c_hoje, 3)::text and r ->> 'data_ate' = public.agenda_somar_du(c_hoje, 5)::text, r::text);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c5', '5541900000206', 'inbound', 'Prazo de 5 dias', timestamptz '2026-10-30 09:10-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004c5', c_toli, 'prazo', '5 dias', false, 'Prazo de 5 dias', '{}', 'nenhum', null,
                     c_hoje, c_agora);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c6', '5541900000206', 'inbound', 'em 10 dias corridos', timestamptz '2026-10-30 09:20-03');
    r2 := pg_temp.reg('d4000000-0000-4000-8000-0000000004c6', c_toli, 'prazo', '10 dias corridos', false, 'em 10 dias corridos', '{}',
                      'nenhum', null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2f "5 dias" conta como dias úteis (seg 09/11); "10 dias corridos" = seg 09/11 pelo calendário',
      r ->> 'data_ate' = public.agenda_somar_du(c_hoje, 5)::text and r2 ->> 'data_ate' = (c_hoje + 10)::text,
      r::text || ' ' || r2::text);
    -- (C1 da revisão, item 12) a data do sinal nunca cai em sábado, domingo ou feriado: vai ao próximo dia útil.
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004cb', '5547900000201', 'inbound', 'Chega amanhã', timestamptz '2026-10-30 08:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004cb', c_mateus, 'chegada', 'amanhã', false, 'Chega amanhã', '{}', 'nenhum', null,
                     c_hoje, c_agora);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004cc', '5547900000201', 'inbound', 'Chega dia 2', timestamptz '2026-10-29 08:00-03');
    r2 := pg_temp.reg('d4000000-0000-4000-8000-0000000004cc', c_mateus, 'chegada', 'dia 2', false, 'Chega dia 2', '{}', 'nenhum', null,
                      c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2k (C1) "amanhã" dito na sex 30/10 (sábado) e "dia 2" dito qui 29/10 (Finados) = ter 03/11, o próximo dia útil',
      r ->> 'data_de' = '2026-11-03' and r ->> 'data_ate' = '2026-11-03' and r2 ->> 'data_ate' = '2026-11-03'
      and public.agenda_data_dita('amanhã', c_hoje, 'futuro') ->> 'ate' = '2026-10-31'
      and public.agenda_feriado(date '2026-11-02') is not null,
      r::text || ' ' || r2::text);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004cd', '5541900000206', 'inbound', 'em 10 dias corridos', timestamptz '2026-10-22 09:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004cd', c_toli, 'prazo', '10 dias corridos', false, 'em 10 dias corridos', '{}',
                     'nenhum', null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2l (C1) "10 dias corridos" dito qui 22/10 cai no dom 01/11 (e seg 02/11 é Finados) = ter 03/11',
      r ->> 'data_ate' = '2026-11-03' and r ->> 'data_de' = '2026-11-03', r::text);
    -- (C1 da revisão, item 3) o dia da semana com a data: o parser manda só a data ("chega quarta dia 04/11" → "dia 04/11",
    -- "entrega na quarta 04/11" → "04/11", "quarta dia 4" → "dia 4"); o banco, quando recebe os dois, fica com o número.
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004ce', '5547900000201', 'inbound', 'chega quarta dia 04/11', timestamptz '2026-10-26 10:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004ce', c_mateus, 'chegada', 'dia 04/11', false, 'chega quarta dia 04/11', '{}',
                     'nenhum', null, c_hoje, c_agora);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004cf', '5547900000201', 'inbound', 'entrega na quarta 04/11', timestamptz '2026-10-26 10:05-03');
    r2 := pg_temp.reg('d4000000-0000-4000-8000-0000000004cf', c_mateus, 'chegada', '04/11', false, 'entrega na quarta 04/11', '{}',
                      'nenhum', null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2m (C1) "chega quarta dia 04/11" e "entrega na quarta 04/11" ditos seg 26/10 = qua 04/11 (não qua 28/10)',
      r ->> 'data_ate' = '2026-11-04' and r2 ->> 'data_ate' = '2026-11-04', r::text || ' ' || r2::text);
    v_res := pg_temp.ok(v_res, 'D2n (C1) no banco o dia da semana com o número vale o número: "quarta dia 4", "quarta, dia 4", "quarta 4" (seg 26/10) = qua 04/11; "quarta" sozinha = qua 28/10',
      public.agenda_data_dita('quarta dia 4', date '2026-10-26', 'futuro') ->> 'ate' = '2026-11-04'
      and public.agenda_data_dita('quarta, dia 4', date '2026-10-26', 'futuro') ->> 'ate' = '2026-11-04'
      and public.agenda_data_dita('quarta 4', date '2026-10-26', 'futuro') ->> 'ate' = '2026-11-04'
      and public.agenda_data_dita('quarta dia 04/11', date '2026-10-26', 'futuro') ->> 'ate' = '2026-11-04'
      and public.agenda_data_dita('quarta', date '2026-10-26', 'futuro') ->> 'ate' = '2026-10-28'
      and public.agenda_data_dita('terça da semana que vem', date '2026-10-26', 'futuro') ->> 'ate' = '2026-11-03',
      public.agenda_data_dita('quarta dia 4', date '2026-10-26', 'futuro')::text);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c7', '5547900000201', 'inbound', 'Já foi coletado', timestamptz '2026-10-30 09:30-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004c7', c_mateus, 'despacho', null, false, 'Já foi coletado', '{}', 'nenhum', null,
                     c_hoje, c_agora);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c8', '5547900000201', 'inbound', 'chega no final do mês', timestamptz '2026-10-30 09:40-03');
    r2 := pg_temp.reg('d4000000-0000-4000-8000-0000000004c8', c_mateus, 'chegada', 'final do mês', false, 'chega no final do mês', '{}',
                      'nenhum', null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2g o Mateus sem cidade no cadastro: despacho sem data ("não sei em quantos dias chega dele"); expressão ruim = "não entendi a data"',
      r ->> 'data_ate' is null and r2 ->> 'data_ate' is null
      and (select s.motivo from public.material_sinais s where s.id = (r ->> 'id')::uuid) = 'não sei em quantos dias chega dele'
      and (select s.motivo from public.material_sinais s where s.id = (r2 ->> 'id')::uuid) = 'não entendi a data');
    -- a escolhida só vale se for uma das candidatas; "unico" com duas candidatas não é único
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004c9', '5547900000202', 'inbound', 'Postei hoje', timestamptz '2026-10-30 09:50-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004c9', c_kes, 'despacho', null, false, 'Postei hoje', array[v_cerbo], 'unico',
                     v_painel, c_hoje, c_agora);
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004ca', '5547900000202', 'inbound', 'Coletaram', timestamptz '2026-10-30 09:55-03');
    r2 := pg_temp.reg('d4000000-0000-4000-8000-0000000004ca', c_kes, 'despacho', null, false, 'Coletaram', array[v_cerbo, v_painel],
                      'unico', v_cerbo, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'D2h a escolhida fora das candidatas = nenhuma; "unico" com duas candidatas = nenhum (a linha fica como dica)',
      (select coalesce(s.os_material_id::text, '-') || ' ' || s.casou_por from public.material_sinais s where s.id = (r ->> 'id')::uuid) = '- nenhum'
      and (select s.os_material_id::text || ' ' || s.casou_por from public.material_sinais s where s.id = (r2 ->> 'id')::uuid)
          = v_cerbo::text || ' nenhum');
    begin
      perform pg_temp.reg('d4000000-0000-4000-8000-0000000004ca', c_kes, 'boleto', null, false, 'Coletaram', '{}', 'nenhum', null,
                          c_hoje, c_agora);
      v_err := 'passou';
    exception when sqlstate '22023' then v_err := 'recusou';
    end;
    v_res := pg_temp.ok(v_res, 'D2i tipo que não existe: 22023', v_err = 'recusou', v_err);
    v_res := pg_temp.ok(v_res, 'D2j nada do que o sinal grava muda a OS: os_material e as perguntas iguais',
      not exists (select 1 from public.agenda_perguntas q where q.tipo in ('previsao_fornecedor', 'chegou'))
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'material'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d2$;

-- ── D3. O replay da OS-00104: a conversa real, tique a tique ────────────────────────────────────────────
do $d3$
declare
  v_res jsonb := '[]'::jsonb;
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_os     constant uuid := '05000000-0000-4000-8000-000000000104';
  v_l uuid;
  v_lista jsonb;
  v_foto text;
  p jsonb;
  ch public.material_sinais;
  de public.material_sinais;
  m public.os_material;
  a public.agenda_acoes;
  v_modo text;
  v_item jsonb;
begin
  if coalesce(current_setting('agenda_teste.replay_fornecedor_0104', true), '') = '' then
    insert into _resultado values ('D3 o replay da OS-00104', true, 'PULADO: sem agenda_teste.replay_fornecedor_0104 (rode pela bancada)');
    return;
  end if;
  foreach v_modo in array array['sombra', 'ligado'] loop
    begin
      execute current_setting('agenda_teste.replay_fornecedor_0104');
      update public.agenda_config set modo_detector = v_modo, modo_material = v_modo where id;
      v_l := pg_temp.compressor();
      v_foto := pg_temp.foto_material();
      if v_modo = 'sombra' then
        v_lista := public.agenda_mensagens_de_fornecedor(date '2026-10-13', timestamptz '2026-10-13 18:00-03');
        v_res := pg_temp.ok(v_res, 'D3a às 18:00 de 13/10 o detector lê as 9 mensagens do dia (não as de 20/10), com a única compra viva do Mateus',
          jsonb_array_length(v_lista) = 9
          and (select bool_and(jsonb_array_length(e -> 'compras') = 1 and e -> 'compras' -> 0 ->> 'os_material_id' = v_l::text
                               and e -> 'compras' -> 0 ->> 'rotulo' = 'Flávio: Compressor 12V de… (comprado 13/10)')
                 from jsonb_array_elements(v_lista) e)
          and (v_lista -> 2 ->> 'texto') = 'chega aqui amanha se eles retirarem hoje' and (v_lista -> 2 ->> 'direcao') = 'enviada'
          and (v_lista -> 8 ->> 'texto') = 'Já foi coletado',
          jsonb_array_length(v_lista)::text);
      end if;
      -- 14:15: o tique depois da mensagem da HBR (o parser: chegada "amanhã", condicional)
      perform pg_temp.reg('d4000000-0000-4000-8000-000000000403', c_mateus, 'chegada', 'amanhã', true,
                          'chega aqui amanha se eles retirarem hoje', array[v_l], 'unico', v_l, date '2026-10-13',
                          timestamptz '2026-10-13 14:15-03');
      perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 14:15-03');
      select * into ch from public.material_sinais where whatsapp_message_id = 'd4000000-0000-4000-8000-000000000403';
      v_res := pg_temp.ok(v_res, format('D3b (%s) 14:15: a chegada condicional da HBR espera o despacho (até qua 14/10)', v_modo),
        ch.estado = 'esperando' and ch.data_ate = date '2026-10-14' and ch.condicional and ch.direcao = 'enviada'
        and ch.motivo = 'espero o fornecedor confirmar o despacho até qua 14/10' and pg_temp.foto_material() = v_foto,
        ch.estado || ' / ' || coalesce(ch.motivo, '-'));
      -- 17:30: o tique depois do "Já foi coletado" (o parser: despacho)
      perform pg_temp.reg('d4000000-0000-4000-8000-000000000409', c_mateus, 'despacho', null, false, 'Já foi coletado', array[v_l],
                          'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      p := public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      select * into de from public.material_sinais where whatsapp_message_id = 'd4000000-0000-4000-8000-000000000409';
      select * into ch from public.material_sinais where whatsapp_message_id = 'd4000000-0000-4000-8000-000000000403';
      v_res := pg_temp.ok(v_res, format('D3c (%s) 17:30: sai a previsão qua 14/10, fonte fornecedor, com os dois trechos; a chegada vai junto', v_modo),
        de.faria ->> 'acao' = 'previsao' and de.faria ->> 'data_ate' = '2026-10-14' and de.faria ->> 'fonte' = 'fornecedor'
        and de.faria ->> 'trecho' = '"chega aqui amanha se eles retirarem hoje" + "Já foi coletado"'
        and de.data_ate = date '2026-10-14' and de.faria ->> 'junto' = ch.id::text
        and ch.estado = 'descartado' and ch.faria ->> 'acao' = 'junto' and ch.faria ->> 'sinal' = de.id::text,
        de.faria::text);
      if v_modo = 'sombra' then
        v_res := pg_temp.ok(v_res, 'D3d (sombra) só registrado: "em teste: anotaria qua 14/10…"; a linha, as ações e as perguntas iguais',
          de.estado = 'registrado' and de.motivo = 'em teste: anotaria qua 14/10 para "Compressor 12V de…" do Flávio'
          and pg_temp.foto_material() = v_foto
          and not exists (select 1 from public.agenda_acoes where tipo = 'material')
          and not exists (select 1 from public.agenda_perguntas)
          and (p ->> 'em_teste')::int = 1 and (p ->> 'aplicados')::int = 0, de.estado || ' / ' || coalesce(de.motivo, '-'));
        p := public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:45-03');
        v_res := pg_temp.ok(v_res, 'D3e (sombra) o tique seguinte não refaz nada',
          (p ->> 'em_teste')::int = 0 and (p ->> 'esperando')::int = 0
          and (select faria from public.material_sinais where id = de.id) = de.faria, p::text);
        p := public._agenda_material_sinais(date '2026-10-21', timestamptz '2026-10-21 10:00-03');
        v_res := pg_temp.ok(v_res, 'D3f (sombra) com mais de 7 dias o teste sai da fila (descartado, para o julgamento)',
          (select estado from public.material_sinais where id = de.id) = 'descartado' and (p ->> 'vencidos')::int = 1, p::text);
      else
        select * into m from public.os_material where id = v_l;
        select * into a from public.agenda_acoes where tipo = 'material';
        v_res := pg_temp.ok(v_res, 'D3g (ligado) a linha a caminho, previsão qua 14/10 do fornecedor, o trecho e a evidência compra_ligada',
          m.situacao = 'a_caminho' and m.previsao_ate = date '2026-10-14' and m.previsao_fonte = 'fornecedor' and m.fonte = 'fornecedor'
          and m.previsao_de is null and m.trecho = de.faria ->> 'trecho' and m.evidencia ->> 'vinculo_por' = 'compra_ligada'
          and m.evidencia ->> 'whatsapp_message_id' = 'd4000000-0000-4000-8000-000000000409'
          and m.historico -> -1 ->> 'por' = 'fornecedor' and m.historico -> -1 ->> 'nota' = 'chega qua 14/10, pela mensagem do Mateus',
          to_jsonb(m)::text);
        v_res := pg_temp.ok(v_res, 'D3h (ligado) o original da previsão guardado: qua 14/10, fonte fornecedor, gravado ter 13/10',
          m.previsao_original = date '2026-10-14' and m.previsao_original_fonte = 'fornecedor' and m.previsao_original_em = date '2026-10-13');
        v_res := pg_temp.ok(v_res, 'D3i (ligado) a ação material, origem fornecedor, com o *desfaz* (24 h) e o texto',
          a.executada and a.origem = 'fornecedor' and a.service_order_id = c_os
          and a.desfazivel_ate = timestamptz '2026-10-13 17:30-03' + (select desfazer_validade from public.agenda_config where id)
          and a.texto = 'Flávio (OS-00104): "Compressor 12V de…" chega qua 14/10 — Mateus escreveu "Já foi coletado". *desfaz OS-00104* volta como estava.'
          and a.antes -> 'linhas' -> 0 ->> 'id' = v_l::text and a.antes -> 'linhas' -> 0 ->> 'previsao_ate' is null
          and a.depois -> 'linhas' -> 0 ->> 'previsao_ate' = '2026-10-14'
          and de.estado = 'aplicado' and de.acao_id = a.id and (p ->> 'aplicados')::int = 1, a.texto);
        v_item := (select e from jsonb_array_elements(public.os_prontidao(c_os, date '2026-10-13') #> '{material,itens}') e
                    where e ->> 'id' = v_l::text);
        v_res := pg_temp.ok(v_res, 'D3j (ligado) a prontidão: nível B, "chega qua 14/10 (o fornecedor disse)"; no "o que mudou" do dia',
          v_item ->> 'nivel' = 'B' and v_item ->> 'data_texto' = 'chega qua 14/10 (o fornecedor disse)'
          and position('chega qua 14/10 — Mateus escreveu' in public._agenda_mudancas(date '2026-10-13', date '2026-10-13', true,
                                                          false, timestamptz '2026-10-13 18:00-03')::text) > 0,
          v_item::text);
        perform public.os_material_sincronizar(c_os, date '2026-10-14');
        v_res := pg_temp.ok(v_res, 'D3k (ligado) a sincronização do dia seguinte (a OC sem data) não apaga a previsão do fornecedor',
          (select previsao_ate = date '2026-10-14' and fonte = 'fornecedor' from public.os_material where id = v_l));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- A condição que não se confirma: só a mensagem da HBR, nenhum despacho até o fim de qua 14/10.
  begin
    execute current_setting('agenda_teste.replay_fornecedor_0104');
    update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado' where id;
    perform pg_temp.reg('d4000000-0000-4000-8000-000000000403', c_mateus, 'chegada', 'amanhã', true,
                        'chega aqui amanha se eles retirarem hoje', array[pg_temp.compressor()], 'unico', pg_temp.compressor(),
                        date '2026-10-13', timestamptz '2026-10-13 14:15-03');
    perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 14:15-03');
    perform public._agenda_material_sinais(date '2026-10-14', timestamptz '2026-10-14 17:00-03');
    p := public._agenda_material_sinais(date '2026-10-15', timestamptz '2026-10-15 09:00-03');
    select * into ch from public.material_sinais where whatsapp_message_id = 'd4000000-0000-4000-8000-000000000403';
    v_res := pg_temp.ok(v_res, 'D3l sem despacho até o fim do dia útil seguinte, a chegada condicional sai e a linha fica igual',
      ch.estado = 'descartado' and ch.motivo = 'a condição não se confirmou: o fornecedor não avisou que despachou'
      and (select previsao_ate is null from public.os_material where id = pg_temp.compressor())
      and not exists (select 1 from public.agenda_acoes where tipo = 'material'), ch.estado || ' / ' || coalesce(ch.motivo, '-'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d3$;

-- ── D4. O que vira pergunta ─────────────────────────────────────────────────────────────────────────────
do $d4$
declare
  v_res jsonb := '[]'::jsonb;
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_l uuid;
  v_p uuid;
  r jsonb;
  s public.material_sinais;
  q public.agenda_perguntas;
  v_foto text;
begin
  if coalesce(current_setting('agenda_teste.replay_fornecedor_0104', true), '') = '' then
    insert into _resultado values ('D4 o que vira pergunta', true, 'PULADO: sem agenda_teste.replay_fornecedor_0104 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.replay_fornecedor_0104');
    update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado' where id;
    -- Uma segunda compra viva do Mateus: o painel solar do Nelson (OC de texto livre da OS-00112, 13/10).
    insert into public.purchase_orders (id, po_number, status, supplier_id, service_order_id, created_at, updated_at)
    values ('d4000000-0000-4000-8000-0000000004d0', 'OC-AG4D-9', 'draft', c_mateus, '05000000-0000-4000-8000-000000000112',
            timestamptz '2026-10-13 12:00-03', timestamptz '2026-10-13 12:00-03');
    insert into public.purchase_order_items (id, purchase_order_id, product_id, description, quantity, unit_cost, received_qty)
    values ('d4000000-0000-4000-8000-0000000004d1', 'd4000000-0000-4000-8000-0000000004d0', null, 'Painel solar 100W (AG4D)', 1, 0, 0);
    perform set_config('agenda.hoje', '2026-10-13', true);
    perform public.os_material_sincronizar('05000000-0000-4000-8000-000000000112', date '2026-10-13');
    v_l := pg_temp.compressor();
    v_p := (select m.id from public.os_material m where m.purchase_order_item_id = 'd4000000-0000-4000-8000-0000000004d1');
    v_foto := pg_temp.foto_material();
    -- (a) duas compras, o modelo não escolheu: a pergunta com as opções (sem data: o Mateus não tem prazo no cadastro)
    r := pg_temp.reg('d4000000-0000-4000-8000-000000000409', c_mateus, 'despacho', null, false, 'Já foi coletado', array[v_l, v_p],
                     'nenhum', null, date '2026-10-13', timestamptz '2026-10-13 17:30-03');
    perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:30-03');
    select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
    select * into q from public.agenda_perguntas where chave = 'sinal:' || s.id;
    v_res := pg_temp.ok(v_res, 'D4a duas compras vivas e nenhuma escolhida: a pergunta previsao_fornecedor com as opções e "nenhuma delas"',
      s.estado = 'perguntado' and s.pergunta_id = q.id and q.tipo = 'previsao_fornecedor' and q.modo = 'ligado'
      and q.texto = 'Mateus escreveu "Já foi coletado" (ter 13/10, 17:19). É de qual compra? 1) rótulo 1; 2) rótulo 2; 3) nenhuma delas. Me diga o número ou o nome.'
      and jsonb_array_length(q.opcoes) = 3 and q.opcoes -> 2 ->> 'texto' = 'nenhuma delas' and q.opcoes -> 2 -> 'os' = 'null'::jsonb
      and q.os_ids @> array['05000000-0000-4000-8000-000000000104'::uuid, '05000000-0000-4000-8000-000000000112'::uuid]
      and q.expira_em = timestamptz '2026-10-13 17:30-03' + (select material_pergunta_validade from public.agenda_config where id)
      and pg_temp.foto_material() = v_foto and not exists (select 1 from public.agenda_acoes where tipo = 'material'),
      coalesce(q.texto, s.estado || ' ' || coalesce(s.motivo, '-')));
    -- (b) o modelo escolheu (casou_por modelo): pergunta, nunca grava sozinho
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004d2', '5547900000201', 'inbound', 'O compressor foi postado hoje',
                        timestamptz '2026-10-13 17:40-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004d2', c_mateus, 'despacho', null, false, 'O compressor foi postado hoje',
                     array[v_l, v_p], 'modelo', v_l, date '2026-10-13', timestamptz '2026-10-13 17:45-03');
    perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:45-03');
    select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
    select * into q from public.agenda_perguntas where chave = 'sinal:' || s.id;
    v_res := pg_temp.ok(v_res, 'D4b o modelo apontou o compressor: vira pergunta ("É do Flávio…? Em quantos dias…"), a linha não muda',
      s.casou_por = 'modelo' and s.estado = 'perguntado'
      and q.texto = 'Mateus escreveu "O compressor foi postado hoje" (ter 13/10, 17:40). É do Flávio ("Compressor 12V de…")? Em quantos dias costuma chegar dele?'
      and q.os_material_id = v_l and pg_temp.foto_material() = v_foto, coalesce(q.texto, s.estado));
    -- (c) a linha em falta, única do fornecedor, com data: pergunta com a data
    update public.os_material set situacao = 'falta', fonte = 'dono', comprado_em = null, comprado_fonte = null, previsao_ate = null,
                                  previsao_fonte = null where id = v_p;
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004d3', '5547900000201', 'inbound', 'Chega amanhã', timestamptz '2026-10-13 18:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004d3', c_mateus, 'chegada', 'amanhã', false, 'Chega amanhã', array[v_p],
                     'unico', v_p, date '2026-10-13', timestamptz '2026-10-13 18:15-03');
    perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 18:15-03');
    select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
    select * into q from public.agenda_perguntas where chave = 'sinal:' || s.id;
    v_res := pg_temp.ok(v_res, 'D4c a linha ainda em falta (sem compra ligada): pergunta "Se for, chega por volta de qua 14/10."',
      s.estado = 'perguntado'
      and q.texto = 'Mateus escreveu "Chega amanhã" (ter 13/10, 18:00). É do Nelson ("Painel solar 100W…")? Se for, chega por volta de qua 14/10.'
      and (select situacao from public.os_material where id = v_p) = 'falta', coalesce(q.texto, s.estado));
    -- (d) a resposta do dono pelo aviso (P3): a previsão da mensagem entra na linha no *grava* (as outras duas perguntas do
    -- Mateus saem antes, para o aviso não ficar ambíguo — o ambíguo é do P3)
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste'
     where tipo = 'previsao_fornecedor' and estado = 'aberta' and id <> q.id;
    r := public.agenda_rascunho_material(c_admin, 'whatsapp', 'OS-00112', array['Painel solar'], 'a_caminho', null, null, null, false,
                                         'é o painel do Nelson, já comprei', date '2026-10-13', 'a mensagem do Mateus');
    v_res := pg_temp.ok(v_res, 'D4d o dono responde pelo aviso ("a mensagem do Mateus"): nada muda antes do *grava*',
      coalesce((r ->> 'ok')::boolean, false) and (select situacao from public.os_material where id = v_p) = 'falta', r::text);
    r := public.agenda_rascunho_gravar(c_admin, date '2026-10-13');
    v_res := pg_temp.ok(v_res, 'D4e o *grava*: a linha a caminho com a previsão qua 14/10 da mensagem (fonte fornecedor), o sinal aplicado',
      coalesce((r ->> 'ok')::boolean, false)
      and (select situacao = 'a_caminho' and previsao_ate = date '2026-10-14' and previsao_fonte = 'fornecedor'
             from public.os_material where id = v_p)
      and (select estado from public.material_sinais where whatsapp_message_id = 'd4000000-0000-4000-8000-0000000004d3') = 'aplicado'
      and (select estado from public.agenda_perguntas where id = q.id) = 'respondida', r::text);
    -- (e) o que a HBR escreveu sem compra ligada não pergunta ao dono
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004d4', '5547900000201', 'outbound', 'chega amanhã então', timestamptz '2026-10-13 18:20-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004d4', c_mateus, 'chegada', 'amanhã', false, 'chega amanhã então', array[v_l, v_p],
                     'nenhum', null, date '2026-10-13', timestamptz '2026-10-13 18:30-03');
    perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 18:30-03');
    select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
    v_res := pg_temp.ok(v_res, 'D4f a HBR escreveu, sem compra ligada: descartado, sem pergunta',
      s.estado = 'descartado' and s.motivo = 'dito pela HBR, sem compra ligada: não pergunto'
      and not exists (select 1 from public.agenda_perguntas where chave = 'sinal:' || s.id), s.estado || ' / ' || coalesce(s.motivo, '-'));
    -- (f) o material desligado: não pergunta
    update public.agenda_config set modo_material = 'desligado' where id;
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004d5', '5547900000201', 'inbound', 'Coletaram hoje', timestamptz '2026-10-13 18:40-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004d5', c_mateus, 'despacho', null, false, 'Coletaram hoje', array[v_l, v_p],
                     'nenhum', null, date '2026-10-13', timestamptz '2026-10-13 18:45-03');
    perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 18:45-03');
    select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
    v_res := pg_temp.ok(v_res, 'D4g modo_material desligado: o sinal sai ("não pergunto"), nenhuma pergunta',
      s.estado = 'descartado' and s.motivo = 'o material está desligado: não pergunto'
      and not exists (select 1 from public.agenda_perguntas where chave = 'sinal:' || s.id), s.estado || ' / ' || coalesce(s.motivo, '-'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d4$;

-- ── D5. "Recebeu o compressor?" vira o chegou? uma vez, sem duplicar o da vigia ─────────────────────────
do $d5$
declare
  v_res jsonb := '[]'::jsonb;
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  v_l uuid;
  r jsonb;
  q public.agenda_perguntas;
  s public.material_sinais;
  p jsonb;
  v_n int;
begin
  if coalesce(current_setting('agenda_teste.replay_fornecedor_0104', true), '') = '' then
    insert into _resultado values ('D5 o chegou? do fornecedor', true, 'PULADO: sem agenda_teste.replay_fornecedor_0104 (rode pela bancada)');
    return;
  end if;
  begin
    execute current_setting('agenda_teste.replay_fornecedor_0104');
    update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado', modo_vigia = 'ligado' where id;
    v_l := pg_temp.compressor();
    -- 13/10: a previsão qua 14/10 pela conversa (D3)
    perform pg_temp.reg('d4000000-0000-4000-8000-000000000403', c_mateus, 'chegada', 'amanhã', true,
                        'chega aqui amanha se eles retirarem hoje', array[v_l], 'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 14:15-03');
    perform pg_temp.reg('d4000000-0000-4000-8000-000000000409', c_mateus, 'despacho', null, false, 'Já foi coletado', array[v_l],
                        'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 17:30-03');
    perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:30-03');
    -- ter 20/10, 10:00: "Recebeu o compressor?" (o parser) e "Deu tudo certo?" (nada)
    r := pg_temp.reg('d4000000-0000-4000-8000-000000000410', c_mateus, 'perguntou_chegou', null, false, 'Recebeu o compressor?',
                     array[v_l], 'unico', v_l, date '2026-10-20', timestamptz '2026-10-20 10:00-03');
    p := public._agenda_material_sinais(date '2026-10-20', timestamptz '2026-10-20 10:00-03');
    select * into q from public.agenda_perguntas where chave = format('chegou:fornecedor:%s:2026-10-20', v_l);
    select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
    v_res := pg_temp.ok(v_res, 'D5a o "Recebeu o compressor?" vira o chegou? (chegou:fornecedor:<linha>:20/10), no modo do material, com validade',
      q.tipo = 'chegou' and q.estado = 'aberta' and q.modo = 'ligado' and q.os_material_id = v_l
      and q.texto = 'Mateus perguntou se chegou o "Compressor 12V de…" do Flávio (ter 20/10). Chegou?'
      and q.expira_em = timestamptz '2026-10-20 10:00-03' + (select material_pergunta_validade from public.agenda_config where id)
      and s.estado = 'perguntado' and s.pergunta_id = q.id and (p ->> 'chegou')::int = 1, coalesce(q.texto, s.estado));
    -- um 2º "Chegou?" no mesmo dia: não pergunta de novo
    perform pg_temp.msg('d4000000-0000-4000-8000-0000000004e1', '5547900000201', 'inbound', 'Chegou?', timestamptz '2026-10-20 15:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-0000000004e1', c_mateus, 'perguntou_chegou', null, false, 'Chegou?', array[v_l], 'unico', v_l,
                     date '2026-10-20', timestamptz '2026-10-20 15:15-03');
    perform public._agenda_material_sinais(date '2026-10-20', timestamptz '2026-10-20 15:15-03');
    v_res := pg_temp.ok(v_res, 'D5b o 2º "Chegou?" não pergunta de novo ("já perguntei se chegou")',
      (select estado || ' / ' || motivo from public.material_sinais where id = (r ->> 'id')::uuid) = 'descartado / já perguntei se chegou'
      and (select count(*) from public.agenda_perguntas where tipo = 'chegou') = 1);
    -- a vigia da Fase 2 (a previsão qua 14/10 passou): não abre o seu chegou? da mesma linha
    p := public._agenda_vigia_chegou(date '2026-10-20', timestamptz '2026-10-20 15:30-03');
    v_res := pg_temp.ok(v_res, 'D5c a vigia da Fase 2 não duplica: com o chegou? do fornecedor aberto, nenhum chegou:<linha>:14/10',
      (p ->> 'criadas')::int = 0
      and not exists (select 1 from public.agenda_perguntas where chave = format('chegou:%s:2026-10-14', v_l)), p::text);
    -- o controle: sem o do fornecedor (resolvido), a vigia pergunta
    begin
      update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = q.id;
      p := public._agenda_vigia_chegou(date '2026-10-20', timestamptz '2026-10-20 15:30-03');
      v_n := (select count(*) from public.agenda_perguntas where chave = format('chegou:%s:2026-10-14', v_l));
      raise exception 'desfaz' using errcode = 'P0098';
    exception when sqlstate 'P0098' then null;
    end;
    v_res := pg_temp.ok(v_res, 'D5d (controle) sem o chegou? do fornecedor a vigia abre o dela (chegou:<linha>:14/10)',
      v_n = 1 and (p ->> 'criadas')::int = 1, p::text);
    -- a limpeza da vigia mantém o do fornecedor aberto; quando a linha chega, resolve
    p := public._agenda_vigia_limpeza(date '2026-10-20', timestamptz '2026-10-20 16:00-03');
    v_res := pg_temp.ok(v_res, 'D5e a limpeza da vigia não resolve o chegou? do fornecedor enquanto a linha não chega',
      (select estado from public.agenda_perguntas where id = q.id) = 'aberta', p::text);
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-10-20',
                                  fonte = 'dono', previsao_de = null, compra_prevista_em = null
     where id = v_l;
    perform public._agenda_vigia_limpeza(date '2026-10-20', timestamptz '2026-10-20 17:00-03');
    v_res := pg_temp.ok(v_res, 'D5f a linha chegou: a limpeza resolve o chegou? do fornecedor com o fato',
      (select estado || ' / ' || resolvida_motivo from public.agenda_perguntas where id = q.id) = 'resolvida / "Compressor 12V de…" chegou',
      (select estado || ' / ' || coalesce(resolvida_motivo, '-') from public.agenda_perguntas where id = q.id));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- O outro sentido: a vigia perguntou primeiro (a previsão venceu); o "Recebeu?" do fornecedor não abre outro.
  begin
    execute current_setting('agenda_teste.replay_fornecedor_0104');
    update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado', modo_vigia = 'ligado' where id;
    v_l := pg_temp.compressor();
    perform pg_temp.reg('d4000000-0000-4000-8000-000000000403', c_mateus, 'chegada', 'amanhã', true,
                        'chega aqui amanha se eles retirarem hoje', array[v_l], 'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 14:15-03');
    perform pg_temp.reg('d4000000-0000-4000-8000-000000000409', c_mateus, 'despacho', null, false, 'Já foi coletado', array[v_l],
                        'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 17:30-03');
    perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:30-03');
    perform public._agenda_vigia_chegou(date '2026-10-16', timestamptz '2026-10-16 10:00-03');
    r := pg_temp.reg('d4000000-0000-4000-8000-000000000410', c_mateus, 'perguntou_chegou', null, false, 'Recebeu o compressor?',
                     array[v_l], 'unico', v_l, date '2026-10-20', timestamptz '2026-10-20 10:00-03');
    perform public._agenda_material_sinais(date '2026-10-20', timestamptz '2026-10-20 10:00-03');
    v_res := pg_temp.ok(v_res, 'D5g a vigia já perguntou (chegou:<linha>:14/10): o "Recebeu?" não abre outro',
      exists (select 1 from public.agenda_perguntas where chave = format('chegou:%s:2026-10-14', v_l) and estado = 'aberta')
      and not exists (select 1 from public.agenda_perguntas where chave like 'chegou:fornecedor:%')
      and (select estado || ' / ' || motivo from public.material_sinais where id = (r ->> 'id')::uuid) = 'descartado / já perguntei se chegou',
      (select estado || ' / ' || coalesce(motivo, '-') from public.material_sinais where id = (r ->> 'id')::uuid));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d5$;

-- ── D6. O julgamento pelo fato e a precisão ─────────────────────────────────────────────────────────────
do $d6$
declare
  v_res jsonb := '[]'::jsonb;
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  v_l uuid;
  v_sinal uuid;
  v_caso text;
  v_j text;
  r jsonb;
  k int;
begin
  if coalesce(current_setting('agenda_teste.replay_fornecedor_0104', true), '') = '' then
    insert into _resultado values ('D6 o julgamento e a precisão', true, 'PULADO: sem agenda_teste.replay_fornecedor_0104 (rode pela bancada)');
    return;
  end if;
  foreach v_caso in array array['chegou_no_dia', 'chegou_tarde', 'sem_fato', 'previsao_do_dono', 'outra_compra'] loop
    begin
      execute current_setting('agenda_teste.replay_fornecedor_0104');
      update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado' where id;
      v_l := pg_temp.compressor();
      perform pg_temp.reg('d4000000-0000-4000-8000-000000000403', c_mateus, 'chegada', 'amanhã', true,
                          'chega aqui amanha se eles retirarem hoje', array[v_l], 'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 14:15-03');
      r := pg_temp.reg('d4000000-0000-4000-8000-000000000409', c_mateus, 'despacho', null, false, 'Já foi coletado', array[v_l],
                       'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      v_sinal := (r ->> 'id')::uuid;
      perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      if v_caso in ('chegou_no_dia', 'chegou_tarde') then
        update public.os_material
           set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, fonte = 'dono',
               chegou_em = case when v_caso = 'chegou_no_dia' then date '2026-10-15' else date '2026-10-20' end
         where id = v_l;
        perform public._agenda_material_sinais(date '2026-10-21', timestamptz '2026-10-21 10:00-03');
      elsif v_caso = 'sem_fato' then
        perform public._agenda_material_sinais(public.agenda_somar_du(date '2026-10-14', 14), timestamptz '2026-11-04 10:00-03');
        v_j := (select coalesce(julgamento, '-') from public.material_sinais where id = v_sinal);
        perform public._agenda_material_sinais(public.agenda_somar_du(date '2026-10-14', 16), timestamptz '2026-11-06 10:00-03');
      elsif v_caso = 'previsao_do_dono' then
        update public.os_material set previsao_ate = date '2026-10-15', previsao_fonte = 'dono', fonte = 'dono', atualizado_por = c_admin
         where id = v_l;
        perform public._agenda_material_sinais(date '2026-10-15', timestamptz '2026-10-15 10:00-03');
        -- (C1 da revisão, item 6) a previsão do dono não é chegada: nenhum veredito ainda; quem julga é a chegada (qui 15/10)
        v_j := (select coalesce(julgamento, '-') from public.material_sinais where id = v_sinal);
        update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-10-15'
         where id = v_l;
        perform public._agenda_material_sinais(date '2026-10-16', timestamptz '2026-10-16 10:00-03');
      else
        perform public.os_material_sincronizar('05000000-0000-4000-8000-000000000112', date '2026-10-13');
        update public.material_sinais set os_material_id = (select m.id from public.os_material m
                                                             where m.service_order_id <> '05000000-0000-4000-8000-000000000104'
                                                             order by m.id limit 1)
         where id = v_sinal;
        perform public._agenda_material_sinais(date '2026-10-15', timestamptz '2026-10-15 10:00-03');
      end if;
      v_res := pg_temp.ok(v_res, 'D6 ' || case v_caso
          when 'chegou_no_dia' then 'a chegou qui 15/10 (qua 14/10 ± 1 dia útil): certo, pelo fato'
          when 'chegou_tarde' then 'b chegou ter 20/10: errado'
          when 'sem_fato' then 'c 15 dias úteis depois da data, sem fato: sem como saber (antes, nada)'
          when 'previsao_do_dono' then 'd (C1) o dono disse qui 15/10: não julga (não é chegada); a chegada qui 15/10 julga certo'
          else 'e o dono ligou a mensagem a outra compra: errado' end,
        (select julgamento || ' ' || julgado_por from public.material_sinais where id = v_sinal)
          = case v_caso when 'chegou_no_dia' then 'certo fato' when 'chegou_tarde' then 'errado fato'
                        when 'sem_fato' then 'sem_como_saber fato' when 'previsao_do_dono' then 'certo fato' else 'errado fato' end
        and (v_caso not in ('sem_fato', 'previsao_do_dono') or v_j = '-')
        and not exists (select 1 from public.material_sinais where whatsapp_message_id = 'd4000000-0000-4000-8000-000000000403'
                         and julgamento is not null),
        (select coalesce(julgamento, '-') || ' ' || coalesce(julgado_por, '-') from public.material_sinais where id = v_sinal));
      if v_caso = 'chegou_no_dia' then
        r := public.agenda_detector_precisao(date '2026-10-13', date '2026-10-26');
        v_res := pg_temp.ok(v_res, 'D6f a precisão com 1 caso: 1 de 1, mas continua em teste (o mínimo é 5); o sinal junto não conta 2 vezes',
          (r ->> 'sinais')::int = 1 and (r ->> 'julgados')::int = 1 and (r ->> 'certos')::int = 1 and (r ->> 'precisao')::numeric = 1
          and not (r ->> 'pronto_para_ligar')::boolean
          and r ->> 'texto' = 'De ter 13/10 a seg 26/10 li 1 mensagem de fornecedor com prazo: acertei 1 de 1 que deu para conferir. Continua em teste: preciso de pelo menos 5 conferidas, com 70% de acerto.',
          r::text);
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- O portão: 4 certos + 1 errado (80%) liga; 3 + 2 (60%) não; 4 certos só (4 conferidos) não.
  foreach v_caso in array array['4+1', '3+2', '4+0'] loop
    begin
      execute current_setting('agenda_teste.replay_fornecedor_0104');
      update public.agenda_config set modo_detector = 'sombra' where id;
      for k in 1 .. (split_part(v_caso, '+', 1)::int + split_part(v_caso, '+', 2)::int) loop
        perform pg_temp.msg(('d4000000-0000-4000-8000-0000000004f' || k)::uuid, '5547900000201', 'inbound', 'Chega amanhã',
                            timestamptz '2026-10-14 10:00-03' + make_interval(days => k));
        insert into public.material_sinais (whatsapp_message_id, fornecedor_id, direcao, ocorreu_em, dia, tipo, expressao, trecho,
                                            data_de, data_ate, os_material_id, casou_por, modo, estado, faria, julgamento, julgado_em,
                                            julgado_por)
        values (('d4000000-0000-4000-8000-0000000004f' || k)::uuid, c_mateus, 'recebida', timestamptz '2026-10-14 10:00-03' + make_interval(days => k),
                date '2026-10-14' + k, 'chegada', 'amanhã', 'Chega amanhã', date '2026-10-15' + k, date '2026-10-15' + k,
                pg_temp.compressor(), 'unico', 'sombra', 'descartado', '{"acao": "previsao"}',
                case when k <= split_part(v_caso, '+', 1)::int then 'certo' else 'errado' end, now(), 'fato');
      end loop;
      r := public.agenda_detector_precisao(date '2026-10-13', date '2026-10-26');
      v_res := pg_temp.ok(v_res, 'D6g o portão ' || v_caso || ': ' || case v_caso when '4+1' then '80% em 5 conferidas: pronto para ligar'
                                                                    when '3+2' then '60%: não' else '4 conferidas (menos de 5): não' end,
        (r ->> 'pronto_para_ligar')::boolean = (v_caso = '4+1')
        and (v_caso <> '4+1' or r ->> 'texto' like '%acertei 4 de 5 que deu para conferir. Já dá para ligar, com o seu OK.')
        and (v_caso <> '3+2' or (r ->> 'precisao')::numeric = 0.6),
        r::text);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$d6$;

-- ── D7. O desfazer ──────────────────────────────────────────────────────────────────────────────────────
do $d7$
declare
  v_res jsonb := '[]'::jsonb;
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_os     constant uuid := '05000000-0000-4000-8000-000000000104';
  v_l uuid;
  v_antes jsonb;
  v_acao uuid;
  v_rem uuid;
  v_dep jsonb;
  r jsonb;
  m public.os_material;
  v_caso text;
  v_foto text;
begin
  if coalesce(current_setting('agenda_teste.replay_fornecedor_0104', true), '') = '' then
    insert into _resultado values ('D7 o desfazer', true, 'PULADO: sem agenda_teste.replay_fornecedor_0104 (rode pela bancada)');
    return;
  end if;
  foreach v_caso in array array['dito', 'mudou', 'prazo'] loop
    begin
      execute current_setting('agenda_teste.replay_fornecedor_0104');
      update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado' where id;
      v_l := pg_temp.compressor();
      v_antes := (select to_jsonb(x) - 'historico' - 'atualizado_em' - 'atualizado_por' from public.os_material x where x.id = v_l);
      perform pg_temp.reg('d4000000-0000-4000-8000-000000000403', c_mateus, 'chegada', 'amanhã', true,
                          'chega aqui amanha se eles retirarem hoje', array[v_l], 'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 14:15-03');
      perform pg_temp.reg('d4000000-0000-4000-8000-000000000409', c_mateus, 'despacho', null, false, 'Já foi coletado', array[v_l],
                          'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      v_acao := (select id from public.agenda_acoes where tipo = 'material');
      if v_caso = 'dito' then
        r := public.agenda_desfazer_dito(c_admin, 'OS-00104', 'whatsapp', date '2026-10-13', timestamptz '2026-10-13 19:00-03');
        select * into m from public.os_material where id = v_l;
        v_res := pg_temp.ok(v_res, 'D7a *desfaz OS-00104*: "Desfeito: "Compressor 12V de…" do Flávio voltou a "a caminho, sem previsão", como estava."',
          coalesce((r ->> 'ok')::boolean, false)
          and r ->> 'texto' = 'Desfeito: "Compressor 12V de…" do Flávio voltou a "a caminho, sem previsão", como estava.', r::text);
        v_res := pg_temp.ok(v_res, 'D7b a linha volta inteira, o original da previsão junto (nulo, como antes); o histórico conta',
          (to_jsonb(m) - 'historico' - 'atualizado_em' - 'atualizado_por') = v_antes
          and m.previsao_original is null and m.previsao_original_fonte is null and m.previsao_original_em is null
          and m.historico -> -1 ->> 'nota' = 'desfeito: volta como estava' and m.historico -> -1 ->> 'por' = 'dono'
          and coalesce(current_setting('agenda.desfazer_material', true), '') <> 'on',
          (to_jsonb(m) - 'historico')::text);
        v_res := pg_temp.ok(v_res, 'D7c a ação desfazer, a original desfeita e o sinal julgado errado pelo dono',
          exists (select 1 from public.agenda_acoes d where d.tipo = 'desfazer' and d.desfaz_a = v_acao and d.service_order_id = c_os)
          and (select desfeita_em is not null from public.agenda_acoes where id = v_acao)
          and (select julgamento || ' ' || julgado_por from public.material_sinais where acao_id = v_acao) = 'errado dono');
        r := public.agenda_desfazer(v_acao, c_admin, 'dono', date '2026-10-13', timestamptz '2026-10-13 19:05-03');
        v_res := pg_temp.ok(v_res, 'D7d de novo: "Isso já foi desfeito."', r ->> 'texto' = 'Isso já foi desfeito.', r::text);
      elsif v_caso = 'mudou' then
        update public.os_material set previsao_ate = date '2026-10-16', previsao_fonte = 'dono', fonte = 'dono', atualizado_por = c_admin
         where id = v_l;
        v_foto := pg_temp.foto_material();
        r := public.agenda_desfazer(v_acao, c_admin, 'dono', date '2026-10-13', timestamptz '2026-10-13 19:00-03');
        v_res := pg_temp.ok(v_res, 'D7e a linha mudou depois: "A linha mudou depois (você ou a nota): não desfiz." e nada muda',
          not (r ->> 'ok')::boolean and r ->> 'texto' = 'A linha mudou depois (você ou a nota): não desfiz.'
          and pg_temp.foto_material() = v_foto and (select desfeita_em is null from public.agenda_acoes where id = v_acao)
          and (select julgamento is null from public.material_sinais where acao_id = v_acao), r::text);
        -- (controle) sem a chave local do desfazer, o gatilho segura o original (a exceção é só dele)
        update public.os_material set previsao_ate = null, previsao_fonte = null, fonte = 'oc', previsao_original = null,
                                      previsao_original_fonte = null
         where id = v_l;
        v_res := pg_temp.ok(v_res, 'D7h (controle) fora do desfazer, apagar o original não pega: o gatilho mantém qua 14/10',
          (select previsao_original = date '2026-10-14' and previsao_original_fonte = 'fornecedor' from public.os_material where id = v_l));
      else
        r := public.agenda_desfazer(v_acao, c_admin, 'dono', date '2026-10-14', timestamptz '2026-10-14 18:00-03');
        v_res := pg_temp.ok(v_res, 'D7f passou o prazo (24 h): recusa e nada muda',
          not (r ->> 'ok')::boolean
          and r ->> 'texto' = 'Não dá mais para desfazer o material do Flávio: passou o prazo. Se está errado, me diga como está.'
          and (select previsao_ate from public.os_material where id = v_l) = date '2026-10-14', r::text);
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- A chegada pela nota (o formato do P3: antes/depois = {linhas[], remessa_id}): volta, e a nota deixa de valer para a linha.
  begin
    execute current_setting('agenda_teste.replay_fornecedor_0104');
    update public.agenda_config set modo_material = 'ligado' where id;
    v_l := pg_temp.compressor();
    insert into public.material_remessas (id, nfe_chave, fornecedor_id, emitente, numero, emitida_em, estado, chegou_em)
    values ('d4000000-0000-4000-8000-0000000004e9', '42261000000000000000550010000018101000000019', c_mateus, 'MATEUS HONORIO', '1810',
            date '2026-10-13', 'chegou', date '2026-10-15')
    returning id into v_rem;
    update public.os_material set remessa_id = v_rem, fonte = 'nfe', previsao_ate = date '2026-10-14', previsao_fonte = 'nfe'
     where id = v_l;
    v_antes := (select to_jsonb(x) - 'historico' from public.os_material x where x.id = v_l);
    perform public.os_material_sincronizar(c_os, date '2026-10-15');
    v_dep := (select to_jsonb(x) - 'historico' from public.os_material x where x.id = v_l);
    insert into public.agenda_acoes (criada_em, dia, executada, origem, tipo, service_order_id, os_ids, antes, depois, texto, desfazivel_ate)
    values (timestamptz '2026-10-15 10:00-03', date '2026-10-15', true, 'nota', 'material', c_os, array[c_os],
            jsonb_build_object('linhas', jsonb_build_array(v_antes), 'remessa_id', v_rem),
            jsonb_build_object('linhas', jsonb_build_array(v_dep), 'remessa_id', v_rem),
            'Flávio (OS-00104): a nota 1810 da Mateus entrou no estoque — Compressor 12V de… está na mão. *desfaz OS-00104* volta como estava.',
            timestamptz '2026-10-16 10:00-03')
    returning id into v_acao;
    r := public.agenda_desfazer(v_acao, c_admin, 'dono', date '2026-10-15', timestamptz '2026-10-15 11:00-03');
    perform public.os_material_sincronizar(c_os, date '2026-10-16');
    select * into m from public.os_material where id = v_l;
    v_res := pg_temp.ok(v_res, 'D7g a chegada pela nota desfeita: a linha volta a caminho e a nota sai dela (a sincronização não a põe na mão de novo)',
      v_dep ->> 'situacao' = 'na_mao' and coalesce((r ->> 'ok')::boolean, false)
      and r ->> 'texto' = 'Desfeito: "Compressor 12V de…" do Flávio voltou a "a caminho, chega qua 14/10", como estava. A nota 1810 da Mateus não conta mais para o Flávio.'
      and m.situacao = 'a_caminho' and m.remessa_id is null and m.previsao_ate = date '2026-10-14'
      and m.historico -> -1 ->> 'nota' = 'desfeito: a nota deixa de valer para esta linha',
      coalesce(r::text, '-') || ' ' || m.situacao);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$d7$;

-- ── D9. C1 da revisão da Fase 4: a única compra de verdade, o pedido da HBR e o despacho chutado ─────────
do $d9$
declare
  v_res jsonb := '[]'::jsonb;
  c_mateus constant uuid := 'dd000000-0000-4000-8000-000000000004';
  c_admin  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_os     constant uuid := '05000000-0000-4000-8000-000000000104';
  v_caso text;
  v_l uuid;
  v_lista jsonb;
  v_foto text;
  r jsonb;
  s public.material_sinais;
  q public.agenda_perguntas;
  m public.os_material;
  v_item jsonb;
  v_t text;
  k int := 0;
begin
  if coalesce(current_setting('agenda_teste.replay_fornecedor_0104', true), '') = ''
     or coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('D9 C1 da revisão', true, 'PULADO: sem agenda_teste.replay_fornecedor_0104/fase4 (rode pela bancada)');
    return;
  end if;
  -- (a/b) x1 e x1b: o Mateus tem OUTRA compra viva além da linha do compressor — uma OC de estoque aberta (sem linha de OS)
  -- ou a nota de outra compra a caminho sem resposta. O TS manda unico (1 compra); o banco rebaixa para nenhum e pergunta.
  foreach v_caso in array array['oc_de_estoque', 'nota_sem_resposta'] loop
    begin
      execute current_setting('agenda_teste.replay_fornecedor_0104');
      update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado' where id;
      if v_caso = 'oc_de_estoque' then
        insert into public.purchase_orders (id, po_number, status, supplier_id, service_order_id, expected_date, created_at, updated_at)
        values ('70000000-0000-4000-8000-0000000000f1', 'OC-00099', 'sent', c_mateus, null, null, '2026-10-12 10:00-03', '2026-10-12 10:00-03');
        insert into public.purchase_order_items (id, purchase_order_id, product_id, description, quantity, unit_cost, received_qty, created_at)
        values ('71000000-0000-4000-8000-0000000000f1', '70000000-0000-4000-8000-0000000000f1', null, 'Gás R134a 13kg (estoque)', 1, 0, 0,
                '2026-10-12 10:00-03');
      else
        insert into public.material_remessas (id, nfe_chave, fornecedor_id, emitente, numero, emitida_em, estado, vinculo)
        values ('d4000000-0000-4000-8000-0000000004f9', '42261000000000000000550010000018991000000019', c_mateus, 'MATEUS HONORIO',
                '1899', date '2026-10-12', 'a_caminho', 'sem_resposta');
      end if;
      v_l := pg_temp.compressor();
      v_foto := pg_temp.foto_material();
      v_lista := public.agenda_mensagens_de_fornecedor(date '2026-10-13', timestamptz '2026-10-13 18:00-03');
      perform pg_temp.reg('d4000000-0000-4000-8000-000000000403', c_mateus, 'chegada', 'amanhã', true,
                          'chega aqui amanha se eles retirarem hoje', array[v_l], 'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 14:15-03');
      r := pg_temp.reg('d4000000-0000-4000-8000-000000000409', c_mateus, 'despacho', null, false, 'Já foi coletado', array[v_l],
                       'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
      select * into q from public.agenda_perguntas where chave = 'sinal:' || s.id;
      v_res := pg_temp.ok(v_res, format('D9%s (C1, item 1) %s: o TS recebe 1 compra e outras_vivas = 1; o banco rebaixa unico para nenhum (a linha de dica), pergunta e não grava',
                                        case v_caso when 'oc_de_estoque' then 'a' else 'b' end,
                                        case v_caso when 'oc_de_estoque' then 'a OC de estoque aberta' else 'a nota de outra compra a caminho' end),
        (select bool_and(jsonb_array_length(e -> 'compras') = 1 and (e ->> 'outras_vivas')::int = 1) from jsonb_array_elements(v_lista) e)
        and s.casou_por = 'nenhum' and s.os_material_id = v_l and s.estado = 'perguntado'
        and q.texto = 'Mateus escreveu "Já foi coletado" (ter 13/10, 17:19). É do Flávio ("Compressor 12V de…")? Se for, chega por volta de qua 14/10.'
        and pg_temp.foto_material() = v_foto and not exists (select 1 from public.agenda_acoes where tipo = 'material'),
        coalesce(q.texto, s.estado || ' ' || s.casou_por));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- (c) o Pix aberto também é outra compra viva (fixture-fase4: o Pix de R$ 480,00 à Premel, seg 26/10)
  begin
    execute current_setting('agenda_teste.fase4');
    update public.agenda_config set modo_material = 'sombra' where id;
    v_t := public._agenda_fornecedor_outras_vivas('dd000000-0000-4000-8000-000000000001', date '2026-10-26', timestamptz '2026-10-26 10:00-03')::text;
    perform public._agenda_material_pix(date '2026-10-26', timestamptz '2026-10-26 10:00-03');
    v_res := pg_temp.ok(v_res, 'D9c (C1, item 1) a pergunta do Pix aberta à Premel é outra compra viva dela (0 → 1); as 4 linhas do Vanderlei não contam',
      v_t = '0'
      and public._agenda_fornecedor_outras_vivas('dd000000-0000-4000-8000-000000000001', date '2026-10-26', timestamptz '2026-10-26 10:00-03') = 1
      and public._agenda_fornecedor_outras_vivas(null, date '2026-10-26', timestamptz '2026-10-26 10:00-03') = 0, v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- (d) x3: a HBR PEDE, com a compra ligada e única — nunca vira previsão (antes: "você escreveu para Mateus …", gravado)
  foreach v_t in array array['preciso que chegue em 3 dias uteis', 'consegue entregar amanhã', 'chega amanhã então'] loop
    k := k + 1;
    begin
      execute current_setting('agenda_teste.replay_fornecedor_0104');
      update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado' where id;
      v_l := pg_temp.compressor();
      v_foto := pg_temp.foto_material();
      perform pg_temp.msg(('d4000000-0000-4000-8000-0000000005a' || k)::uuid, '5547900000201', 'outbound', v_t, timestamptz '2026-10-13 14:30-03');
      r := pg_temp.reg(('d4000000-0000-4000-8000-0000000005a' || k)::uuid, c_mateus,
                       case k when 1 then 'prazo' else 'chegada' end, case k when 1 then '3 dias úteis' else 'amanhã' end, false, v_t,
                       array[v_l], 'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 14:45-03');
      perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 14:45-03');
      select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
      if k < 3 then
        v_res := pg_temp.ok(v_res, format('D9d%s (C1, item 4) a HBR escreveu "%s": descartado, a linha igual, nenhuma ação', k, v_t),
          s.estado = 'descartado'
          and s.motivo = case k when 1 then 'dito pela HBR: só a chegada que ela afirma conta'
                                else 'dito pela HBR: é o pedido dela, não a palavra do fornecedor' end
          and pg_temp.foto_material() = v_foto and not exists (select 1 from public.agenda_acoes where tipo = 'material')
          and not exists (select 1 from public.agenda_perguntas where chave = 'sinal:' || s.id),
          s.estado || ' / ' || coalesce(s.motivo, '-'));
      else
        -- (controle) a chegada que a HBR AFIRMA, com a compra ligada e única, continua a previsão do dono (C)
        v_res := pg_temp.ok(v_res, 'D9d3 (C1, controle) a HBR afirma "chega amanhã então": a previsão qua 14/10, fonte dono',
          s.estado = 'aplicado'
          and (select previsao_ate = date '2026-10-14' and previsao_fonte = 'dono' from public.os_material where id = v_l),
          s.estado || ' / ' || coalesce(s.motivo, '-'));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- (e/f/g/h) x8: o "Já foi coletado" sozinho do Mateus com a cidade no cadastro (Blumenau/SC = entrega local, o CHUTE pela
  -- cidade): a data é a conta da agenda, não a palavra dele. Vira pergunta (nunca o nível B); com o prazo que o dono disse,
  -- a previsão vale.
  foreach v_caso in array array['chute', 'resposta', 'dono_disse'] loop
    begin
      execute current_setting('agenda_teste.replay_fornecedor_0104');
      update public.agenda_config set modo_detector = 'ligado', modo_material = 'ligado' where id;
      update public.suppliers set city = 'Blumenau', state = 'SC' where id = c_mateus;
      if v_caso = 'dono_disse' then
        update public.suppliers set modalidade = 'entrega_local', prazo_dias_uteis = 1, prazo_fonte = 'dono' where id = c_mateus;
      end if;
      v_l := pg_temp.compressor();
      v_foto := pg_temp.foto_material();
      r := pg_temp.reg('d4000000-0000-4000-8000-000000000409', c_mateus, 'despacho', null, false, 'Já foi coletado', array[v_l],
                       'unico', v_l, date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      perform public._agenda_material_sinais(date '2026-10-13', timestamptz '2026-10-13 17:30-03');
      select * into s from public.material_sinais where id = (r ->> 'id')::uuid;
      select * into q from public.agenda_perguntas where chave = 'sinal:' || s.id;
      if v_caso = 'chute' then
        v_item := (select e from jsonb_array_elements(public.os_prontidao(c_os, date '2026-10-13') #> '{material,itens}') e
                    where e ->> 'id' = v_l::text);
        v_res := pg_temp.ok(v_res, 'D9e (C1, item 5) o despacho com o prazo chutado pela cidade: a pergunta "… Se for, chega por volta de qua 14/10.", nada gravado, a prontidão não diz "o fornecedor disse"',
          s.data_ate = date '2026-10-14' and s.estado = 'perguntado' and (s.faria ->> 'chute')::boolean
          and q.texto = 'Mateus escreveu "Já foi coletado" (ter 13/10, 17:19). É do Flávio ("Compressor 12V de…")? Se for, chega por volta de qua 14/10.'
          and pg_temp.foto_material() = v_foto and not exists (select 1 from public.agenda_acoes where tipo = 'material')
          and v_item ->> 'nivel' = 'D' and position('o fornecedor disse' in v_item ->> 'data_texto') = 0,
          coalesce(q.texto, s.estado) || ' / ' || coalesce(v_item::text, '-'));
        -- a chegada não julga o chute (a data não foi dita pelo fornecedor)
        update public.os_material set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-10-14',
                                      fonte = 'dono'
         where id = v_l;
        perform public._agenda_material_sinais(date '2026-10-15', timestamptz '2026-10-15 10:00-03');
        v_res := pg_temp.ok(v_res, 'D9g (C1, item 6) o despacho chutado não entra na precisão: a chegada não o julga',
          (select julgamento is null from public.material_sinais where id = s.id));
      elsif v_caso = 'resposta' then
        -- o dono responde pelo aviso ("é do Flávio"): a linha fica a caminho SEM a previsão do fornecedor (nível D)
        r := public.agenda_rascunho_material(c_admin, 'whatsapp', 'OS-00104', array['Compressor'], 'a_caminho', null, null, null, false,
                                             'é do Flávio', date '2026-10-13', 'a mensagem do Mateus');
        r := public.agenda_rascunho_gravar(c_admin, date '2026-10-13');
        select * into m from public.os_material where id = v_l;
        v_item := (select e from jsonb_array_elements(public.os_prontidao(c_os, date '2026-10-13') #> '{material,itens}') e
                    where e ->> 'id' = v_l::text);
        v_res := pg_temp.ok(v_res, 'D9f (C1, item 5) o dono confirma pelo aviso: a linha a caminho sem previsão do fornecedor (nível D, não B), o sinal aplicado',
          coalesce((r ->> 'ok')::boolean, false) and m.situacao = 'a_caminho' and m.previsao_ate is null
          and m.previsao_fonte is null and v_item ->> 'nivel' = 'D'
          and (select estado from public.material_sinais where id = s.id) = 'aplicado'
          and (select estado from public.agenda_perguntas where id = q.id) = 'respondida',
          r::text || ' / ' || coalesce(v_item::text, '-'));
      else
        v_res := pg_temp.ok(v_res, 'D9h (C1, controle) com o prazo que o dono disse (entrega local, 1 dia útil), o despacho grava a previsão qua 14/10 do fornecedor',
          s.estado = 'aplicado' and not coalesce((s.faria ->> 'chute')::boolean, false)
          and (select previsao_ate = date '2026-10-14' and previsao_fonte = 'fornecedor' from public.os_material where id = v_l),
          s.estado || ' / ' || coalesce(s.motivo, '-'));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$d9$;

-- ── D8. As cópias: fora dos blocos "-- FASE 4:", iguais às da migration de onde vieram ─────────────────
do $d8$
declare
  v_f3 text := current_setting('agenda_teste.mig_equipe_fase3', true);
  v_f2 text := current_setting('agenda_teste.mig_conferencia_fase2', true);
  v_p1 text := current_setting('agenda_teste.mig_tabelas_fase4', true);
  v_f1 text := current_setting('agenda_teste.mig_calendario_fase1', true);
  v_ruins text := '';
  f record;
begin
  if coalesce(v_f3, '') = '' or coalesce(v_f2, '') = '' or coalesce(v_p1, '') = '' or coalesce(v_f1, '') = '' then
    insert into _resultado values ('D8 as cópias só acrescentam os blocos "-- FASE 4:"', true,
      'PULADO: sem agenda_teste.mig_equipe_fase3/mig_conferencia_fase2/mig_tabelas_fase4/mig_calendario_fase1 (rode pela bancada)');
    return;
  end if;
  for f in select * from (values
      ('agenda_desfazer', 'public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', v_f3, '_agenda_desfazer_material'),
      ('_agenda_vigia_limpeza', 'public._agenda_vigia_limpeza(date, timestamptz)', v_f2, 'chegou:fornecedor'),
      ('_agenda_vigia_chegou', 'public._agenda_vigia_chegou(date, timestamptz)', v_f2, 'chegou:fornecedor:'),
      ('_os_material_previsao_original', 'public._os_material_previsao_original()', v_p1, 'agenda.desfazer_material'),
      -- C1 da revisão: a data dita da Fase 1, com o dia da semana e o número
      ('_agenda_data_um', 'public._agenda_data_um(text, date, text, boolean, date, date)', v_f1, 'v_num_dito')) as x(nome, sig, mig, marca) loop
    if pg_temp.sem_fase4(pg_temp.corpo(f.mig, f.nome))
         is distinct from pg_temp.sem_fase4((select p.prosrc from pg_proc p where p.oid = f.sig::regprocedure))
       or position(f.marca in (select p.prosrc from pg_proc p where p.oid = f.sig::regprocedure)) = 0
       or position(f.marca in pg_temp.corpo(f.mig, f.nome)) > 0
    then
      v_ruins := v_ruins || f.nome || ' ';
    end if;
  end loop;
  insert into _resultado values ('D8 as 5 cópias só acrescentam os blocos "-- FASE 4:" (e têm o bloco do P4 e o da C1)', v_ruins = '',
    nullif(v_ruins, ''));
end
$d8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
