-- Prova de compras e OC da Agenda de Produção, Fase 4 (pacote P2): migration 20261027100200.
-- bancada: depende de 20261027100200
--
--   C1 o vínculo copiado da cotação (quote_request_items → purchase_order_items, o que a tela e o assistente fazem): o
--      texto livre passa a a caminho com a OC; a OC ligada à PEÇA continua abatendo pelo produto (com ou sem o vínculo, a
--      mesma conta)
--   C2 o ciclo do texto livre com OC ligada: falta → a caminho (a sincronização acha a OC: previsão, fornecedor, "comprado
--      em" = o dia da OC em Brasília) → recebida (na mão, fonte oc, o dia do recebimento) e, na outra linha, cancelada
--      (falta de novo, sem o "comprado em"); a falta do dono que ganhou OC ligada vira a caminho; a chegada pela nota só
--      em ligado (em sombra a linha fica igual)
--   C3 sem vínculo e sem linha do dono, a conta é a da Fase 1 (md5 em toda OS da carteira, antes e depois da
--      sincronização); a linha do dono entra na lista e na count_purchase_shortages (a R16); dispensado sai
--   C4 receive_po com texto livre: recebe sem movimento de estoque; a conta a pagar é a de hoje (a mesma soma: recebido ×
--      custo de todos os itens); OC só de catálogo = a mesma saída da versão de 07/10; a de 07/10 derrubava o recebimento
--      com o texto livre (product_id NOT NULL)
--   C5 agenda_ocs_com_material_vivo: só a pergunta "chegou?" aberta em ligado conta (sombra e resolvida não); tudo na
--      mão; a linha da peça ligada; meio na mão e OC sem linha de material ficam de fora; portas (só service_role)
--   C6 a OS-00104 da carteira (a OC-00004 sem vínculo) igual à Fase 1, com o "comprado em" da OC (13/10) a mais
--   C7 a prontidão: a OC ligada a caminho é B pela OC; recebida, o item aparece UMA vez (antes, duas)
--   C8 as cópias só mudam nos blocos "-- FASE 4:" (os_necessidade_bruta, aplicar_os_material, get_os_purchase_needs e
--      os_material_sincronizar × 20261024160300; receive_po × 20261007160000; os_prontidao × 20261027100100)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase4_compras.sql
--   Seguro em produção: produtos, fornecedor, OS, OC, cotação e nota de teste (TESTE AG4C, OS-TESTE-AG4C-*, OC-TESTE-AG4C-*)
--   só são inseridos ou mexidos dentro da transação; o recebimento de teste cria conta a pagar e movimento de estoque que
--   o ROLLBACK desfaz. C3, C6 e C8 rodam só na bancada (as migrations antigas como texto; fora dela, PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- O item de uma necessidade pelo id da linha de origem.
create function pg_temp.item(p jsonb, p_id uuid) returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(coalesce(p -> 'items', '[]'::jsonb)) i where i ->> 'sourceId' = p_id::text
$f$;

-- A linha de material de uma linha de origem (peça, serviço ou item de OC), sem a do dono.
create function pg_temp.linha(p_id uuid) returns public.os_material language sql stable as $f$
  select m.* from public.os_material m
   where p_id in (m.service_order_part_id, m.service_order_service_id, m.purchase_order_item_id) and m.origem <> 'dono'
   order by m.id limit 1
$f$;

-- O bloco "create or replace function public.<nome>(…) … $function$" de uma migration (sem o ";").
create function pg_temp.bloco(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  i int;
begin
  i := position(format('create or replace function public.%s(', p_nome) in v);
  if i = 0 then raise exception 'pg_temp.bloco: % não está na migration', p_nome; end if;
  v := substr(v, i);
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$') - 1);
end $f$;

-- O corpo (entre "as $function$" e "$function$;") de uma função numa migration.
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

-- A cópia: o corpo antigo (linhas) sem as trocadas (cada uma uma vez, na 1ª vez que aparece) = o novo sem os blocos.
-- 'ok' ou o que divergiu.
create function pg_temp.copia(p_antigo text[], p_novo text, p_trocadas text[]) returns text language plpgsql as $f$
declare
  v_a text[] := '{}'; v_b text[]; v_achadas text[] := '{}'; l text;
begin
  foreach l in array p_antigo loop
    if l = any (p_trocadas) and not (l = any (v_achadas)) then
      v_achadas := v_achadas || l;
      continue;
    end if;
    v_a := v_a || l;
  end loop;
  v_b := pg_temp.sem_fase4(p_novo);
  if cardinality(v_achadas) <> cardinality(p_trocadas) then
    return format('achadas %s de %s linhas trocadas', cardinality(v_achadas), cardinality(p_trocadas));
  end if;
  if v_a is distinct from v_b then
    return format('fora dos blocos, %s × %s linhas; 1ª diferente: %s', cardinality(v_a), cardinality(v_b),
                  (select min(i) from generate_series(1, greatest(cardinality(v_a), cardinality(v_b))) i
                    where v_a[i] is distinct from v_b[i]));
  end if;
  return 'ok';
end $f$;

-- As versões de antes, para comparar (só na bancada: as migrations antigas como texto). f1_* = a conta da Fase 1
-- (20261024160300); f0_receive_po = o recebimento de 07/10 (20261007160000).
create function pg_temp.instalar_antigas() returns boolean language plpgsql as $f$
declare
  v_m text := current_setting('agenda_teste.mig_material_fase1', true);
  v_r text := current_setting('agenda_teste.mig_receive_po', true);
begin
  if coalesce(v_m, '') = '' or coalesce(v_r, '') = '' then return false; end if;
  execute replace(pg_temp.bloco(v_m, 'os_necessidade_bruta'),
                  'create or replace function public.os_necessidade_bruta(', 'create function pg_temp.f1_bruta(');
  execute replace(pg_temp.bloco(v_m, 'aplicar_os_material'),
                  'create or replace function public.aplicar_os_material(', 'create function pg_temp.f1_aplicar(');
  execute replace(replace(replace(pg_temp.bloco(v_m, 'get_os_purchase_needs'),
                  'create or replace function public.get_os_purchase_needs(', 'create function pg_temp.f1_get('),
                  'public.aplicar_os_material(', 'pg_temp.f1_aplicar('), 'public.os_necessidade_bruta(', 'pg_temp.f1_bruta(');
  execute replace(pg_temp.bloco(v_r, 'receive_po'),
                  'create or replace function public.receive_po(', 'create function pg_temp.f0_receive_po(');
  return true;
end $f$;

do $teste$
declare
  c_hoje    constant date := date '2026-10-30';
  v_antigas boolean := pg_temp.instalar_antigas();
  v_barco   uuid := (select id from public.vessels where client_id is not null order by created_at, id limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
  v_forn uuid; v_p1 uuid; v_p2 uuid;
  v_c1 uuid; v_c2 uuid; v_c3 uuid; v_c4 uuid; v_c5 uuid; v_c7 uuid;
  pc uuid; sc uuid; t1 uuid; t2 uuid; t3 uuid; t4 uuid; t5 uuid; t6 uuid; t7 uuid; pk uuid; p7 uuid;
  v_q uuid; v_oc uuid; v_oc2 uuid; v_oc3 uuid; i1 uuid; i2 uuid; i3 uuid; i4 uuid;
  v_rem uuid; v_m public.os_material; v_m2 public.os_material;
  r jsonb; b jsonb; x jsonb; v_ok boolean; v_n int; v_txt text; v_md5 text;
  v_ret_novo json; v_ret_velho json; v_pa_novo record; v_pa_velho record;
  v_ocs uuid[]; v_vivas jsonb;
begin
  set constraints all immediate;
  if v_barco is null then raise exception 'FALHOU: nenhum barco cadastrado para montar as OS de teste'; end if;

  insert into public.suppliers (name) values ('TESTE AG4C — Fornecedor') returning id into v_forn;
  insert into public.products (name, stock_quantity) values ('TESTE AG4C — Bateria', 0) returning id into v_p1;
  insert into public.products (name, stock_quantity) values ('TESTE AG4C — Terminal', 0) returning id into v_p2;

  -- ── C1: o vínculo copiado da cotação ───────────────────────────────────────────────────────────────────
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG4C-1', 'awaiting_parts', 'approved') returning id into v_c1;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_c1, v_p1, 2, 900, 1500, 1800, 3000) returning id into pc;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot)
  values (v_c1, null, 'Cabo de bateria 35mm (AG4C)', 'unit', 3, 45) returning id into sc;
  b := public.get_os_purchase_needs(v_c1);
  insert into _resultado values ('C1a antes da OC: a peça falta 2 e o cabo (texto livre) falta 3',
    (b ->> 'shortageCount')::int = 2 and pg_temp.item(b, sc) ->> 'status' = 'uncatalogued'
    and (pg_temp.item(b, sc) ->> 'shortage')::numeric = 3, b::text);

  insert into public.quote_requests (code, service_order_id, status) values ('COT-TESTE-AG4C', v_c1, 'closed') returning id into v_q;
  insert into public.quote_request_items (quote_request_id, product_id, description, quantity, service_order_part_id, position)
  values (v_q, v_p1, 'Bateria TESTE AG4C', 2, pc, 1);
  insert into public.quote_request_items (quote_request_id, product_id, description, quantity, service_order_service_id, position)
  values (v_q, null, 'Cabo de bateria 35mm', 3, sc, 2);
  -- A OC da cotação, como useCreatePOsFromQuote e gerarOCDaCotacao gravam: os dois vínculos copiados.
  insert into public.purchase_orders (po_number, status, supplier_id, service_order_id, created_at)
  values ('OC-TESTE-AG4C-1', 'sent', v_forn, v_c1, '2026-10-28 10:00-03') returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost,
                                           service_order_part_id, service_order_service_id)
  select v_oc, q.product_id, q.description, q.quantity, 40, q.service_order_part_id, q.service_order_service_id
    from public.quote_request_items q where q.quote_request_id = v_q order by q.position;
  r := public.get_os_purchase_needs(v_c1);
  insert into _resultado values ('C1b com a OC da cotação: a peça já pedida (pelo produto) e o cabo a caminho pela OC ligada; nada a comprar',
    (r ->> 'shortageCount')::int = 0 and not (r ->> 'needsPurchase')::boolean
    and pg_temp.item(r, pc) ->> 'status' = 'on_order' and (pg_temp.item(r, pc) ->> 'onOrder')::numeric = 2
    and pg_temp.item(r, sc) ->> 'status' = 'on_order' and (pg_temp.item(r, sc) ->> 'onOrder')::numeric = 3
    and pg_temp.item(r, sc) ->> 'purchaseOrderNumber' = 'OC-TESTE-AG4C-1'
    and not exists (select 1 from jsonb_array_elements(r -> 'items') i where i ->> 'origin' = 'purchase_order'),
    r::text);
  v_md5 := md5(r::text);
  update public.purchase_order_items set service_order_part_id = null where purchase_order_id = v_oc and product_id = v_p1;
  insert into _resultado values ('C1c a OC ligada à peça abate pelo produto: sem o vínculo da peça, a mesma conta',
    md5(public.get_os_purchase_needs(v_c1)::text) = v_md5, null);

  -- ── C2: o ciclo do texto livre com OC ligada (a sincronização) ─────────────────────────────────────────
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG4C-2', 'awaiting_parts', 'approved') returning id into v_c2;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_c2, null, 'Inversor 3000W (AG4C)', 'unit', 1, 4000, now() - interval '40 seconds') returning id into t1;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_c2, null, 'Carregador DC-DC 30A (AG4C)', 'unit', 1, 1200, now() - interval '39 seconds') returning id into t2;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_c2, null, 'Bateria de lítio 100Ah (AG4C)', 'unit', 1, 5000, now() - interval '38 seconds') returning id into t3;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_c2, null, 'Central Cerbo GX (AG4C)', 'unit', 1, 1500, now() - interval '37 seconds') returning id into t4;
  -- O texto livre do teste não leva a palavra 'teste': o classificador a lê como verbo de serviço (diagnóstico).
  insert into _resultado values ('C0 o classificador: todo texto livre do teste é material (o cenário vale)',
    (select bool_and(public.free_text_is_material(t)) from unnest(array[
       'Cabo de bateria 35mm (AG4C)', 'Inversor 3000W (AG4C)', 'Carregador DC-DC 30A (AG4C)',
       'Bateria de lítio 100Ah (AG4C)', 'Central Cerbo GX (AG4C)', 'Bomba de porão 12V (AG4C)',
       'Chave geral 300A (AG4C)', 'Painel solar 200W (AG4C)']) t),
    (select string_agg(t, ', ') from unnest(array[
       'Cabo de bateria 35mm (AG4C)', 'Inversor 3000W (AG4C)', 'Carregador DC-DC 30A (AG4C)',
       'Bateria de lítio 100Ah (AG4C)', 'Central Cerbo GX (AG4C)', 'Bomba de porão 12V (AG4C)',
       'Chave geral 300A (AG4C)', 'Painel solar 200W (AG4C)']) t where not public.free_text_is_material(t)));
  perform public.os_material_sincronizar(v_c2, c_hoje);
  v_m := pg_temp.linha(t1);
  insert into _resultado values ('C2a sem OC: a linha do inversor nasce em falta, sem "comprado em"',
    v_m.situacao = 'falta' and v_m.fonte is null and v_m.comprado_em is null and v_m.comprado_fonte is null, to_jsonb(v_m)::text);

  -- O dono disse que a bateria falta (fato informado, fonte dono).
  update public.os_material set fonte = 'dono', trecho = 'a bateria ainda falta' where service_order_service_id = t3 and origem = 'texto_livre';

  insert into public.purchase_orders (po_number, status, supplier_id, service_order_id, expected_date, created_at)
  values ('OC-TESTE-AG4C-2', 'sent', v_forn, v_c2, '2026-11-04', '2026-10-28 10:00-03') returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost, service_order_service_id)
  values (v_oc, null, 'Inversor 3000W', 1, 3500, t1) returning id into i1;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost, service_order_service_id)
  values (v_oc, null, 'Bateria de lítio 100Ah', 1, 4500, t3) returning id into i3;
  insert into public.purchase_orders (po_number, status, supplier_id, service_order_id, created_at)
  values ('OC-TESTE-AG4C-3', 'draft', v_forn, v_c2, '2026-10-29 09:00-03') returning id into v_oc2;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost, service_order_service_id)
  values (v_oc2, null, 'Carregador DC-DC 30A', 1, 1000, t2) returning id into i2;

  r := public.get_os_purchase_needs(v_c2);
  insert into _resultado values ('C2b a conta: o inversor, a bateria e o carregador a caminho pela OC ligada (falta só o Cerbo); nenhum item de OC repetido',
    (r ->> 'shortageCount')::int = 1 and pg_temp.item(r, t4) ->> 'status' = 'uncatalogued'
    and pg_temp.item(r, t1) ->> 'status' = 'on_order' and pg_temp.item(r, t1) ->> 'purchaseOrderNumber' = 'OC-TESTE-AG4C-2'
    and pg_temp.item(r, t2) ->> 'status' = 'on_order' and pg_temp.item(r, t2) ->> 'purchaseOrderNumber' = 'OC-TESTE-AG4C-3'
    and pg_temp.item(r, t3) ->> 'status' = 'on_order'
    and not exists (select 1 from jsonb_array_elements(r -> 'items') i where i ->> 'origin' = 'purchase_order'),
    r::text);

  perform public.os_material_sincronizar(v_c2, c_hoje);
  v_m := pg_temp.linha(t1);
  insert into _resultado values ('C2c a sincronização acha a OC ligada: a caminho, fonte oc, previsão 04/11 da OC, o fornecedor dela, comprado em 28/10 (oc)',
    v_m.situacao = 'a_caminho' and v_m.fonte = 'oc' and v_m.previsao_ate = '2026-11-04' and v_m.previsao_fonte = 'oc'
    and v_m.fornecedor_id = v_forn and v_m.comprado_em = '2026-10-28' and v_m.comprado_fonte = 'oc'
    and v_m.historico -> -1 ->> 'nota' = 'pedido na OC-TESTE-AG4C-2' and v_m.previsao_original = '2026-11-04',
    to_jsonb(v_m)::text);
  v_m := pg_temp.linha(t3);
  insert into _resultado values ('C2d a falta do dono que ganhou a OC ligada vira a caminho (fonte oc, comprado em 28/10)',
    v_m.situacao = 'a_caminho' and v_m.fonte = 'oc' and v_m.comprado_em = '2026-10-28' and v_m.comprado_fonte = 'oc'
    and v_m.previsao_ate = '2026-11-04', to_jsonb(v_m)::text);
  select count(*) into v_n from public.os_material m where m.service_order_id = v_c2 and m.origem = 'oc';
  insert into _resultado values ('C2e a linha ligada não vira linha de item de OC (origem oc) na sincronização', v_n = 0, v_n::text);
  v_m := pg_temp.linha(t1);
  perform public.os_material_sincronizar(v_c2, c_hoje);
  insert into _resultado values ('C2f sincronizar de novo não muda nada (atualizado_em e histórico iguais)',
    (select m.atualizado_em = v_m.atualizado_em and m.historico = v_m.historico from public.os_material m where m.id = v_m.id), null);

  -- Recebida (receive_po): o inversor fica na mão pela OC, no dia do recebimento.
  perform public.receive_po(v_oc, jsonb_build_array(jsonb_build_object('po_item_id', i1, 'received_qty', 1),
                                                    jsonb_build_object('po_item_id', i3, 'received_qty', 1)), 30);
  update public.purchase_orders set received_date = '2026-10-29' where id = v_oc;
  r := public.get_os_purchase_needs(v_c2);
  insert into _resultado values ('C2g recebida: o inversor e a bateria ok na conta (1 disponível), com a OC; falta só o Cerbo',
    pg_temp.item(r, t1) ->> 'status' = 'ok' and (pg_temp.item(r, t1) ->> 'available')::numeric = 1
    and (pg_temp.item(r, t1) ->> 'onOrder')::numeric = 0 and pg_temp.item(r, t1) ->> 'purchaseOrderNumber' = 'OC-TESTE-AG4C-2'
    and pg_temp.item(r, t3) ->> 'status' = 'ok' and (r ->> 'shortageCount')::int = 1, r::text);
  perform public.os_material_sincronizar(v_c2, c_hoje);
  v_m := pg_temp.linha(t1);
  insert into _resultado values ('C2h a sincronização: na mão, fonte oc, chegou qui 29/10 (o recebimento), "recebido na OC-…", o comprado em fica',
    v_m.situacao = 'na_mao' and v_m.fonte = 'oc' and v_m.chegou_em = '2026-10-29' and v_m.quantidade_na_mao = 1
    and v_m.historico -> -1 ->> 'nota' = 'recebido na OC-TESTE-AG4C-2' and v_m.comprado_em = '2026-10-28',
    to_jsonb(v_m)::text);

  -- Cancelada: o carregador volta a faltar e perde o "comprado em" que o sistema gravou.
  perform public.os_material_sincronizar(v_c2, c_hoje);
  v_m := pg_temp.linha(t2);
  insert into _resultado values ('C2i antes de cancelar: o carregador a caminho, comprado em 29/10 (o dia da OC)',
    v_m.situacao = 'a_caminho' and v_m.comprado_em = '2026-10-29' and v_m.comprado_fonte = 'oc', to_jsonb(v_m)::text);
  update public.purchase_orders set status = 'cancelled' where id = v_oc2;
  r := public.get_os_purchase_needs(v_c2);
  perform public.os_material_sincronizar(v_c2, c_hoje);
  v_m := pg_temp.linha(t2);
  insert into _resultado values ('C2j cancelada: o carregador falta de novo na conta e na linha (sem previsão, sem "comprado em")',
    pg_temp.item(r, t2) ->> 'status' = 'uncatalogued' and (pg_temp.item(r, t2) ->> 'shortage')::numeric = 1
    and pg_temp.item(r, t2) ->> 'purchaseOrderNumber' is null
    and v_m.situacao = 'falta' and v_m.fonte is null and v_m.previsao_ate is null and v_m.comprado_em is null
    and v_m.comprado_fonte is null, to_jsonb(v_m)::text);

  -- A chegada pela nota (P3): a linha do Cerbo ligada a uma nota que chegou. Em sombra, igual; em ligado, na mão.
  insert into public.material_remessas (nfe_chave, emitente, numero, emitida_em, estado, chegou_em)
  values ('42261012345678000199550010000510381000000017', 'TESTE AG4C', '51038', '2026-10-26', 'chegou', '2026-10-29')
  returning id into v_rem;
  update public.os_material set situacao = 'a_caminho', fonte = 'nfe', remessa_id = v_rem, previsao_ate = '2026-10-30',
                                previsao_fonte = 'nfe'
   where service_order_service_id = t4 and origem = 'texto_livre';
  update public.agenda_config set modo_material = 'sombra' where id;
  v_m := pg_temp.linha(t4);
  perform public.os_material_sincronizar(v_c2, c_hoje);
  insert into _resultado values ('C2k a chegada pela nota em sombra: a linha fica igual',
    (select to_jsonb(m) = to_jsonb(v_m) from public.os_material m where m.id = v_m.id), null);
  update public.agenda_config set modo_material = 'ligado' where id;
  perform public.os_material_sincronizar(v_c2, c_hoje);
  v_m := pg_temp.linha(t4);
  insert into _resultado values ('C2l a chegada pela nota em ligado: na mão, fonte nfe, chegou 29/10, a quantidade toda, "chegou pela nota 51038"',
    v_m.situacao = 'na_mao' and v_m.fonte = 'nfe' and v_m.chegou_em = '2026-10-29' and v_m.quantidade_na_mao = 1
    and v_m.historico -> -1 ->> 'nota' = 'chegou pela nota 51038', to_jsonb(v_m)::text);
  v_m2 := v_m;
  perform public.os_material_sincronizar(v_c2, c_hoje);
  insert into _resultado values ('C2m de novo: nada muda (a nota não chega duas vezes)',
    (select to_jsonb(m) = to_jsonb(v_m2) from public.os_material m where m.id = v_m2.id), null);
  update public.agenda_config set modo_material = 'desligado' where id;

  -- ── C3: sem vínculo e sem linha do dono = a conta da Fase 1; a linha do dono na lista e na R16 ─────────
  if not v_antigas then
    insert into _resultado values ('C3a sem vínculo nem linha do dono = a conta da Fase 1', true,
      'PULADO: sem agenda_teste.mig_material_fase1 (rode pela bancada)');
  else
    select count(*), bool_and(md5(public.get_os_purchase_needs(so.id)::text) = md5(pg_temp.f1_get(so.id)::text)
                              and md5(public.os_necessidade_bruta(so.id)::text) = md5(pg_temp.f1_bruta(so.id)::text))
      into v_n, v_ok
      from public.service_orders so
     where so.service_order_number not like 'OS-TESTE-AG4C-%';
    insert into _resultado values ('C3a sem vínculo nem linha do dono, em toda OS da carteira: a conta bruta e a final iguais às da Fase 1 (md5)',
      v_ok and v_n > 10, format('%s OS', v_n));
    perform public.os_material_sincronizar_carteira(c_hoje);
    select count(*), bool_and(md5(public.get_os_purchase_needs(so.id)::text) = md5(pg_temp.f1_get(so.id)::text))
      into v_n, v_ok
      from public.service_orders so
     where so.service_order_number not like 'OS-TESTE-AG4C-%';
    insert into _resultado values ('C3b depois da sincronização da carteira: ainda igual à Fase 1 (a linha copiada não conta)',
      v_ok and v_n > 10, format('%s OS', v_n));
  end if;

  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG4C-3', 'approved', 'approved') returning id into v_c3;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_c3, v_p2, 10, 2, 4, 20, 40) returning id into pk;
  b := public.get_os_purchase_needs(v_c3);
  insert into _resultado values ('C3c a R16 antes: count_purchase_shortages = 1 (o terminal)',
    public.count_purchase_shortages(array[v_c3]) = jsonb_build_object(v_c3::text, 1), public.count_purchase_shortages(array[v_c3])::text);
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, situacao, fonte, trecho)
  values (v_c3, 'dono', 'Parafusos inox do suporte', 12, 'falta', 'dono', 'precisa de uns parafusos inox') returning * into v_m;
  r := public.get_os_purchase_needs(v_c3);
  insert into _resultado values ('C3d a linha do dono entra no fim da lista, sem preço, e na count_purchase_shortages (2)',
    pg_temp.item(r, v_m.id) ->> 'origin' = 'dono' and pg_temp.item(r, v_m.id) ->> 'status' = 'uncatalogued'
    and (pg_temp.item(r, v_m.id) ->> 'shortage')::numeric = 12 and (pg_temp.item(r, v_m.id) ->> 'unitCost')::numeric = 0
    and (pg_temp.item(r, v_m.id) -> 'semPreco') = 'true'::jsonb
    and pg_temp.item(r, v_m.id) ->> 'description' = 'Parafusos inox do suporte'
    and r -> 'items' -> -1 ->> 'sourceId' = v_m.id::text
    and (r ->> 'estimatedCost')::numeric = (b ->> 'estimatedCost')::numeric and (r ->> 'semPreco')::int = 1
    and public.count_purchase_shortages(array[v_c3]) = jsonb_build_object(v_c3::text, 2),
    r::text);
  insert into _resultado values ('C3e determinístico: duas leituras, o mesmo md5',
    md5(public.get_os_purchase_needs(v_c3)::text) = md5(public.get_os_purchase_needs(v_c3)::text), null);
  update public.os_material set situacao = 'comprado' where id = v_m.id;
  r := public.get_os_purchase_needs(v_c3);
  insert into _resultado values ('C3f comprado: já pedido, sai da falta (a R16 volta a 1), semPreco 0',
    pg_temp.item(r, v_m.id) ->> 'status' = 'on_order' and (pg_temp.item(r, v_m.id) ->> 'onOrder')::numeric = 12
    and (r ->> 'semPreco')::int = 0 and public.count_purchase_shortages(array[v_c3]) = jsonb_build_object(v_c3::text, 1),
    r::text);
  update public.os_material set situacao = 'dispensado' where id = v_m.id;
  r := public.get_os_purchase_needs(v_c3);
  insert into _resultado values ('C3g dispensado: sai da lista; a saída volta a ser a de antes, idêntica (md5)',
    pg_temp.item(r, v_m.id) is null and md5(r::text) = md5(b::text) and not (r ? 'semPreco'), r::text);

  -- ── C4: receive_po com texto livre ─────────────────────────────────────────────────────────────────────
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG4C-4', 'awaiting_parts', 'approved') returning id into v_c4;
  insert into public.purchase_orders (po_number, status, supplier_id, service_order_id)
  values ('OC-TESTE-AG4C-4', 'sent', v_forn, v_c4) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, v_p1, 'Bateria TESTE AG4C', 2, 900) returning id into i1;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, null, 'Cabo de bateria 35mm (texto livre)', 3, 40) returning id into i2;
  v_ret_novo := public.receive_po(v_oc, jsonb_build_array(jsonb_build_object('po_item_id', i1, 'received_qty', 2),
                                                          jsonb_build_object('po_item_id', i2, 'received_qty', 3)), 30);
  insert into _resultado values ('C4a o texto livre recebe junto: a OC completa (received), received_qty 3, nenhum movimento de estoque para ele',
    v_ret_novo ->> 'status' = 'received' and (v_ret_novo ->> 'all_received')::boolean
    and (select received_qty from public.purchase_order_items where id = i2) = 3
    and (select count(*) from public.inventory_movements where reference_id = v_oc) = 1
    and (select product_id = v_p1 and quantity_delta = 2 and movement_type = 'purchase'
           from public.inventory_movements where reference_id = v_oc),
    v_ret_novo::text);
  select pa.amount, pa.balance_amount, pa.status, pa.origin, pa.description, pa.due_date - pa.issue_date as prazo, pa.supplier_id
    into v_pa_novo
    from public.payables pa join public.purchase_orders po on po.payable_id = pa.id where po.id = v_oc;
  insert into _resultado values ('C4b a conta a pagar é a de hoje: recebido × custo de TODOS os itens (2 × 900 + 3 × 40 = 1.920), pendente, 30 dias (NOVO-agenda-32 não muda)',
    v_pa_novo.amount = 1920 and v_pa_novo.balance_amount = 1920 and v_pa_novo.status = 'pending'
    and v_pa_novo.origin = 'purchase_order' and v_pa_novo.description = 'Recebimento OC-TESTE-AG4C-4' and v_pa_novo.prazo = 30
    and v_pa_novo.supplier_id = v_forn, to_jsonb(v_pa_novo)::text);

  if not v_antigas then
    insert into _resultado values ('C4c a OC só de catálogo: a saída da versão de 07/10', true,
      'PULADO: sem agenda_teste.mig_receive_po (rode pela bancada)');
  else
    -- Duas OCs iguais, só de catálogo: a nova e a de 07/10 dão a mesma saída e a mesma conta.
    insert into public.purchase_orders (po_number, status, supplier_id) values ('OC-TESTE-AG4C-5', 'partial', v_forn)
    returning id into v_oc2;
    insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost)
    values (v_oc2, v_p2, 'Terminal TESTE AG4C', 10, 4, 2) returning id into i3;
    insert into public.purchase_orders (po_number, status, supplier_id) values ('OC-TESTE-AG4C-6', 'partial', v_forn)
    returning id into v_oc3;
    insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost)
    values (v_oc3, v_p2, 'Terminal TESTE AG4C', 10, 4, 2) returning id into i4;
    v_ret_novo := public.receive_po(v_oc2, jsonb_build_array(jsonb_build_object('po_item_id', i3, 'received_qty', 6)), 15);
    v_ret_velho := pg_temp.f0_receive_po(v_oc3, jsonb_build_array(jsonb_build_object('po_item_id', i4, 'received_qty', 6)), 15);
    select pa.amount, pa.status, pa.due_date - pa.issue_date as prazo into v_pa_novo
      from public.payables pa join public.purchase_orders po on po.payable_id = pa.id where po.id = v_oc2;
    select pa.amount, pa.status, pa.due_date - pa.issue_date as prazo into v_pa_velho
      from public.payables pa join public.purchase_orders po on po.payable_id = pa.id where po.id = v_oc3;
    insert into _resultado values ('C4c a OC só de catálogo: a mesma saída, a mesma conta a pagar e o mesmo movimento da versão de 07/10',
      (v_ret_novo::jsonb - 'payable_id') = (v_ret_velho::jsonb - 'payable_id')
      and to_jsonb(v_pa_novo) = to_jsonb(v_pa_velho) and v_pa_novo.amount = 20
      and (select array_agg(quantity_delta) from public.inventory_movements where reference_id = v_oc2)
          = (select array_agg(quantity_delta) from public.inventory_movements where reference_id = v_oc3),
      format('%s × %s | %s × %s', v_ret_novo, v_ret_velho, to_jsonb(v_pa_novo), to_jsonb(v_pa_velho)));
    -- A de 07/10 com o texto livre: derrubava o recebimento inteiro (o movimento sem produto).
    insert into public.purchase_orders (po_number, status, supplier_id) values ('OC-TESTE-AG4C-7', 'sent', v_forn)
    returning id into v_oc3;
    insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
    values (v_oc3, null, 'Cabo (texto livre)', 1, 40) returning id into i4;
    begin
      perform pg_temp.f0_receive_po(v_oc3, jsonb_build_array(jsonb_build_object('po_item_id', i4, 'received_qty', 1)), 30);
      v_txt := 'recebeu';
    exception when others then
      v_txt := sqlstate;
    end;
    insert into _resultado values ('C4d a versão de 07/10 derrubava o recebimento do texto livre (23502: product_id nulo no movimento)',
      v_txt = '23502' and (select received_qty from public.purchase_order_items where id = i4) = 0, v_txt);
  end if;

  -- ── C5: agenda_ocs_com_material_vivo ───────────────────────────────────────────────────────────────────
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG4C-5', 'awaiting_parts', 'approved') returning id into v_c5;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_c5, null, 'Bomba de porão 12V (AG4C)', 'unit', 1, 300, now() - interval '30 seconds') returning id into t5;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_c5, null, 'Chave geral 300A (AG4C)', 'unit', 1, 200, now() - interval '29 seconds') returning id into t6;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_c5, v_p2, 2, 2, 4, 4, 8) returning id into p7;
  -- OC-A: um item de texto livre SEM vínculo (a linha dele é origem oc), com "chegou?" aberta — em ligado e, noutra
  -- OC-B igual, em sombra. OC-C: ligada à bomba, na mão. OC-D: ligada à bomba e à chave (só a bomba na mão). OC-E: ligada
  -- à peça (o terminal), na mão. OC-F: sem linha de material nenhuma.
  insert into public.purchase_orders (po_number, status, service_order_id) values ('OC-TESTE-AG4C-A', 'sent', v_c5) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, null, 'Compressor TESTE AG4C', 1, 0) returning id into i1;
  v_ocs := array[v_oc];
  insert into public.purchase_orders (po_number, status, service_order_id) values ('OC-TESTE-AG4C-B', 'sent', v_c5) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, null, 'Suporte TESTE AG4C', 1, 0) returning id into i2;
  v_ocs := v_ocs || v_oc;
  perform public.os_material_sincronizar(v_c5, c_hoje);
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_material_id, texto, modo)
  values ('chegou', 'chegou:teste-ag4c-a', v_c5, (pg_temp.linha(i1)).id, 'O compressor chegou?', 'ligado');
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_material_id, texto, modo)
  values ('chegou', 'chegou:teste-ag4c-b', v_c5, (pg_temp.linha(i2)).id, 'O suporte chegou?', 'sombra');
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_material_id, texto, modo, estado, resolvida_motivo)
  values ('chegou', 'chegou:teste-ag4c-b2', v_c5, (pg_temp.linha(i2)).id, 'O suporte chegou?', 'ligado', 'resolvida', 'teste');

  update public.os_material set situacao = 'na_mao', fonte = 'dono', quantidade_na_mao = 1, chegou_em = '2026-10-28'
   where service_order_service_id = t5 and origem = 'texto_livre';
  update public.os_material set situacao = 'na_mao', fonte = 'dono', quantidade_na_mao = 2, chegou_em = '2026-10-28'
   where service_order_part_id = p7;
  insert into public.purchase_orders (po_number, status, service_order_id) values ('OC-TESTE-AG4C-C', 'sent', v_c5) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost, service_order_service_id)
  values (v_oc, null, 'Bomba de porão 12V', 1, 300, t5);
  v_ocs := v_ocs || v_oc;
  insert into public.purchase_orders (po_number, status, service_order_id) values ('OC-TESTE-AG4C-D', 'sent', v_c5) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost, service_order_service_id)
  values (v_oc, null, 'Bomba de porão 12V', 1, 300, t5), (v_oc, null, 'Chave geral 300A', 1, 200, t6);
  v_ocs := v_ocs || v_oc;
  insert into public.purchase_orders (po_number, status, service_order_id) values ('OC-TESTE-AG4C-E', 'sent', v_c5) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost, service_order_part_id)
  values (v_oc, v_p2, 'Terminal TESTE AG4C', 2, 2, p7);
  v_ocs := v_ocs || v_oc;
  insert into public.purchase_orders (po_number, status) values ('OC-TESTE-AG4C-F', 'sent') returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, v_p1, 'Bateria avulsa TESTE AG4C', 1, 900);
  v_ocs := v_ocs || v_oc;

  v_vivas := public.agenda_ocs_com_material_vivo(v_ocs);
  insert into _resultado values ('C5a "chegou?" aberta em ligado → "a agenda já pergunta se chegou"; em sombra ou resolvida, não',
    v_vivas ->> v_ocs[1]::text = 'a agenda já pergunta se chegou' and not (v_vivas ? v_ocs[2]::text), v_vivas::text);
  insert into _resultado values ('C5b tudo na mão (o texto livre ligado; a peça ligada) → "a agenda registrou que chegou"',
    v_vivas ->> v_ocs[3]::text = 'a agenda registrou que chegou' and v_vivas ->> v_ocs[5]::text = 'a agenda registrou que chegou',
    v_vivas::text);
  insert into _resultado values ('C5c meio na mão e OC sem linha de material ficam de fora; só as 3',
    not (v_vivas ? v_ocs[4]::text) and not (v_vivas ? v_ocs[6]::text)
    and (select count(*) from jsonb_object_keys(v_vivas)) = 3, v_vivas::text);
  insert into _resultado values ('C5d entrada vazia ou nula = {}',
    public.agenda_ocs_com_material_vivo('{}') = '{}'::jsonb and public.agenda_ocs_com_material_vivo(null) = '{}'::jsonb
    and public.agenda_ocs_com_material_vivo(array[null::uuid]) = '{}'::jsonb, null);

  -- ── C6: a OS-00104 da carteira (OC-00004 sem vínculo) ──────────────────────────────────────────────────
  perform public.os_material_sincronizar('05000000-0000-4000-8000-000000000104', c_hoje);
  v_m := pg_temp.linha('71000000-0000-4000-8000-000000000001');
  r := public.get_os_purchase_needs('05000000-0000-4000-8000-000000000104');
  insert into _resultado values ('C6a OS-00104: o compressor continua item da OC-00004 (a caminho, sem previsão), a conta sem falta — como na Fase 1',
    jsonb_array_length(r -> 'items') = 1 and r -> 'items' -> 0 ->> 'origin' = 'purchase_order'
    and r -> 'items' -> 0 ->> 'purchaseOrderNumber' = 'OC-00004' and (r ->> 'shortageCount')::int = 0
    and v_m.origem = 'oc' and v_m.situacao = 'a_caminho' and v_m.fonte = 'oc' and v_m.previsao_ate is null
    and v_m.fornecedor_id = 'dd000000-0000-4000-8000-000000000004',
    r::text || ' | ' || to_jsonb(v_m)::text);
  insert into _resultado values ('C6b a mais da Fase 4: comprado em ter 13/10 (o dia da OC-00004 em Brasília), fonte oc',
    v_m.comprado_em = '2026-10-13' and v_m.comprado_fonte = 'oc', to_jsonb(v_m)::text);

  -- ── C7: a prontidão ────────────────────────────────────────────────────────────────────────────────────
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG4C-7', 'awaiting_parts', 'approved') returning id into v_c7;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot)
  values (v_c7, null, 'Painel solar 200W (AG4C)', 'unit', 1, 900) returning id into t7;
  insert into public.purchase_orders (po_number, status, supplier_id, service_order_id, expected_date, created_at)
  values ('OC-TESTE-AG4C-8', 'sent', v_forn, v_c7, '2026-11-05', '2026-10-27 10:00-03') returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost, service_order_service_id)
  values (v_oc, null, 'Painel solar 200W', 1, 800, t7) returning id into i1;
  perform public.os_material_sincronizar(v_c7, c_hoje);
  r := public.os_prontidao(v_c7, c_hoje);
  insert into _resultado values ('C7a a caminho pela OC ligada: UM item, nível B, chega qui 05/11 (pela OC)',
    jsonb_array_length(r #> '{material,itens}') = 1 and r #>> '{material,itens,0,nivel}' = 'B'
    and r #>> '{material,itens,0,data}' = '2026-11-05' and r #>> '{material,itens,0,data_texto}' = 'chega qui 05/11 (pela OC)',
    (r -> 'material')::text);
  perform public.receive_po(v_oc, jsonb_build_array(jsonb_build_object('po_item_id', i1, 'received_qty', 1)), 30);
  update public.purchase_orders set received_date = '2026-10-29' where id = v_oc;
  perform public.os_material_sincronizar(v_c7, c_hoje);
  r := public.os_prontidao(v_c7, c_hoje);
  insert into _resultado values ('C7b recebida: o painel aparece UMA vez (não de novo como item da OC que já chegou), na mão desde qui 29/10',
    jsonb_array_length(r #> '{material,itens}') = 1 and r #>> '{material,itens,0,nivel}' = 'A'
    and r #>> '{material,itens,0,data_texto}' = 'na mão desde qui 29/10' and r #>> '{material,estado}' = 'completo',
    (r -> 'material')::text);
end
$teste$;

-- ── C8: as cópias só mudam nos blocos "-- FASE 4:" ───────────────────────────────────────────────────────
do $copia$
declare
  v_m text := current_setting('agenda_teste.mig_material_fase1', true);
  v_r text := current_setting('agenda_teste.mig_receive_po', true);
  v_p text := current_setting('agenda_teste.mig_fornecedores_fase4', true);
  v_res text;
  v_novo text;
begin
  if coalesce(v_m, '') = '' or coalesce(v_r, '') = '' or coalesce(v_p, '') = '' then
    insert into _resultado values ('C8 as cópias só mudam nos blocos "-- FASE 4:"', true,
      'PULADO: sem as migrations antigas como texto (rode pela bancada)');
    return;
  end if;
  -- As linhas que cada troca tirou (scratchpad f4p2/trocadas.json, escritas pelo montador da migration).
  v_res := pg_temp.copia(string_to_array(pg_temp.corpo(v_m, 'os_necessidade_bruta'), E'\n'),
    (select prosrc from pg_proc where oid = 'public.os_necessidade_bruta(uuid)'::regprocedure),
    array[$l$  select jsonb_set(n.r, '{items}', coalesce(n.r -> 'items', '[]'::jsonb) || a.itens)$l$,
          $l$    from necessidade n, a_caminho a;$l$]);
  insert into _resultado values ('C8a os_necessidade_bruta: fora dos blocos, linha a linha a de 20261024160300', v_res = 'ok', v_res);

  v_res := pg_temp.copia(string_to_array(pg_temp.corpo(v_m, 'aplicar_os_material'), E'\n'),
    (select prosrc from pg_proc where oid = 'public.aplicar_os_material(jsonb, jsonb)'::regprocedure),
    array[$l$    when not exists (select 1 from marcados where sai or mudou) then p_needs$l$]);
  insert into _resultado values ('C8b aplicar_os_material: fora dos blocos, linha a linha a de 20261024160300', v_res = 'ok', v_res);

  v_res := pg_temp.copia(string_to_array(pg_temp.corpo(v_m, 'get_os_purchase_needs'), E'\n'),
    (select prosrc from pg_proc where oid = 'public.get_os_purchase_needs(uuid)'::regprocedure),
    array[$l$        'quantidade_necessaria', m.quantidade_necessaria, 'quantidade_na_mao', m.quantidade_na_mao)$l$]);
  insert into _resultado values ('C8c get_os_purchase_needs: fora dos blocos, linha a linha a de 20261024160300', v_res = 'ok', v_res);

  v_res := pg_temp.copia(string_to_array(pg_temp.corpo(v_m, 'os_material_sincronizar'), E'\n'),
    (select prosrc from pg_proc where oid = 'public.os_material_sincronizar(uuid, date)'::regprocedure),
    array[$l$      select v.expected_date, po.supplier_id, v.po_number$l$,
          $l$        into v_oc_prev, v_oc_forn, v_oc_numero$l$,
          $l$        previsao_ate, previsao_original, previsao_fonte, chegou_em, historico)$l$,
          $l$        case v_ini_sit when 'na_mao' then 'estoque' when 'a_caminho' then 'oc' end,$l$,
          $l$        case when v_ini_sit = 'na_mao' then p_hoje end,$l$,
          $l$          'nota', case v_ini_sit when 'na_mao' then 'o estoque cobre'$l$,
          $l$                                 else 'a comprar' end)));$l$,
          $l$      v_nova.fonte := case v_ini_sit when 'na_mao' then 'estoque' when 'a_caminho' then 'oc' end;$l$,
          $l$                               else p_hoje end;$l$,
          $l$          when 'na_mao' then 'o estoque cobre'$l$,
          $l$        v_nova.fonte := 'estoque';$l$,
          $l$        v_nova.chegou_em := p_hoje;$l$,
          $l$        v_nota := coalesce(v_nota || '; ', '') || 'o estoque cobre';$l$,
          $l$        v_nova.previsao_ate, v_nova.previsao_original, v_nova.previsao_fonte, v_nova.chegou_em)$l$,
          $l$        v_velha.previsao_ate, v_velha.previsao_original, v_velha.previsao_fonte, v_velha.chegou_em) then$l$]);
  insert into _resultado values ('C8d os_material_sincronizar: fora dos blocos, linha a linha a de 20261024160300', v_res = 'ok', v_res);

  v_res := pg_temp.copia(string_to_array(pg_temp.corpo(v_r, 'receive_po'), E'\n'),
    (select prosrc from pg_proc where oid = 'public.receive_po(uuid, jsonb, integer)'::regprocedure), '{}'::text[]);
  insert into _resultado values ('C8e receive_po: só acréscimo (o "só com produto"); fora dos blocos, a de 20261007160000', v_res = 'ok', v_res);

  -- os_prontidao já vem da Fase 4 (P1): os dois sem os blocos "-- FASE 4:" (o do P2 é só acréscimo), e um bloco a mais.
  v_novo := (select prosrc from pg_proc where oid = 'public.os_prontidao(uuid, date)'::regprocedure);
  v_res := pg_temp.copia(pg_temp.sem_fase4(pg_temp.corpo(v_p, 'os_prontidao')), v_novo, '{}'::text[]);
  insert into _resultado values ('C8f os_prontidao: só acréscimo sobre a de 20261027100100 (um bloco "-- FASE 4:" a mais)',
    v_res = 'ok'
    and (select count(*) from regexp_matches(v_novo, '-- FASE 4: fim', 'g'))
        = (select count(*) from regexp_matches(pg_temp.corpo(v_p, 'os_prontidao'), '-- FASE 4: fim', 'g')) + 1,
    v_res);
end
$copia$;

-- ── Portas ──────────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado values
  ('C9a agenda_ocs_com_material_vivo: security definer, search_path fixo, só service_role (anon e authenticated sem execute)',
   (select p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=%'
      from pg_proc p where p.oid = 'public.agenda_ocs_com_material_vivo(uuid[])'::regprocedure)
   and not has_function_privilege('anon', 'public.agenda_ocs_com_material_vivo(uuid[])', 'execute')
   and not has_function_privilege('authenticated', 'public.agenda_ocs_com_material_vivo(uuid[])', 'execute')
   and has_function_privilege('service_role', 'public.agenda_ocs_com_material_vivo(uuid[])', 'execute'),
   null),
  ('C9b as recriadas mantêm a ACL: anon sem nada; a leitura e o recebimento para authenticated; a sincronização só service_role',
   not has_function_privilege('anon', 'public.os_necessidade_bruta(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.aplicar_os_material(jsonb, jsonb)', 'execute')
   and not has_function_privilege('anon', 'public.get_os_purchase_needs(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.receive_po(uuid, jsonb, integer)', 'execute')
   and not has_function_privilege('anon', 'public.os_prontidao(uuid, date)', 'execute')
   and not has_function_privilege('anon', 'public.os_material_sincronizar(uuid, date)', 'execute')
   and has_function_privilege('authenticated', 'public.get_os_purchase_needs(uuid)', 'execute')
   and has_function_privilege('authenticated', 'public.receive_po(uuid, jsonb, integer)', 'execute')
   and has_function_privilege('authenticated', 'public.os_prontidao(uuid, date)', 'execute')
   and not has_function_privilege('authenticated', 'public.os_material_sincronizar(uuid, date)', 'execute')
   and has_function_privilege('service_role', 'public.os_material_sincronizar(uuid, date)', 'execute'),
   null),
  ('C9c aplicar_os_material continua IMMUTABLE; a conta bruta e get_os_purchase_needs continuam STABLE e invoker',
   (select provolatile = 'i' from pg_proc where oid = 'public.aplicar_os_material(jsonb, jsonb)'::regprocedure)
   and (select provolatile = 's' and not prosecdef from pg_proc where oid = 'public.os_necessidade_bruta(uuid)'::regprocedure)
   and (select provolatile = 's' and not prosecdef from pg_proc where oid = 'public.get_os_purchase_needs(uuid)'::regprocedure),
   null);

select teste, ok, detalhe from _resultado order by teste;

rollback;
