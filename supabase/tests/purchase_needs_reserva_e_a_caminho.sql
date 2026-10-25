-- Prova: necessidade de compra com reserva própria, "já pedido" honesto e o que vem a caminho
-- (migrations 20261024150000, 20261024150100 e 20261024150200 — Agenda de Produção, Fase 0, P5).
--
--   A  OS aprovada com 1 Cerbo, físico 1 e reservado 1 por ELA MESMA → 'ok' (antes: 'missing')
--   B  OS aberta (não reserva) com a mesma peça, reservada pela A → 'missing'
--   C  reservado defasado (0) com reserva própria 1 e físico 1 → disponível 1, nunca 2
--   D  duas linhas do mesmo produto somam a reserva própria → as duas 'ok'
--   E1 OC aberta de OS FATURADA não abate a falta
--   E2 OC aberta de 61 dias não abate a falta
--   E3 OC aberta recente, sem OS, abate (1 de 2)
--   F  OC de texto livre da própria OS aparece em items como 'on_order' (origin purchase_order, com o
--      número da OC), sem mudar shortageCount, estimatedCost nem needsPurchase; linha toda recebida e
--      OC cancelada não aparecem
--   F2 a mesma linha de texto livre da própria OS em OC de 61 dias CONTINUA a caminho: o corte de idade é só
--      do "já pedido" de catálogo (coluna conta_como_ja_pedido da view), não do que a OS espera chegar
--   G  o caso da OS-00104 em miniatura: "Conversão…" é serviço, a falta é 0 e o compressor fica a caminho;
--      count_purchase_shortages não acusa a OS
--   H  free_text_is_material: Conversão… = false; Conversor DC-DC… = true; Kit de conversão… = true
--   I  anon sem execute nas 3 funções e sem select na view; authenticated com os dois e só leitura na view;
--      view security_invoker
--   L  (Agenda de Produção, Fase 4, P2 — migration 20261027100200) a OC desta OS LIGADA ao item de texto livre: em parte
--      (6 de 10) = falta o resto; recebida em parte (1 de 4) = 1 disponível e 3 já pedidos; marcada recebida sem
--      received_qty = na mão; cancelada não conta; o número da OC no item; a linha ligada à "Conversão…" (serviço, fora da
--      conta) e a sem vínculo continuam a caminho; shortages, contagem e custo recontados; count_purchase_shortages segue
--   O  (Fase 4, P2) o material citado pelo dono (origem 'dono') entra no fim, sem preço: falta = uncatalogued, comprado e
--      a caminho = já pedido (necessário − na mão), dispensado e na mão fora; shortages, contagem, custo (sem ele) e
--      semPreco; count_purchase_shortages conta
--   (L e O só rodam com a migration 20261027100200: sem ela, nenhuma linha deles entra na tabela.)
--
-- Os MESMOS números estão em src/hooks/use-purchase-needs.test.ts (A, B, D, E, G, L, O) e em
-- src/lib/purchase-needs.test.ts (a–e, L, O).
--
-- ═══ COMO RODAR ═══ (só DEPOIS de aplicar as 3 migrations, com o OK nomeado do dono)
--
--   npx supabase db query --linked -f supabase/tests/purchase_needs_reserva_e_a_caminho.sql
--
-- Seguro em produção: produtos, OS e OC de teste (números OS-TESTE-P5-*, OC-TESTE-P5-*), só inseridos —
-- nenhum gatilho de mudança de status roda; o estoque entra por entrada_de_estoque (movimento), como em
-- estoque_so_por_movimento.sql; termina em ROLLBACK. Usa um barco cadastrado só como chave da OS.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $teste$
declare
  v_barco   uuid := (select id from public.vessels where client_id is not null order by created_at limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
  v_p1 uuid; v_p2 uuid; v_p3 uuid;
  v_a uuid; v_b uuid; v_d uuid; v_e uuid; v_f uuid; v_g uuid;
  v_oc uuid;
  r jsonb; antes jsonb; itens jsonb;
begin
  set constraints all immediate;   -- o saldo do estoque é recalculado na hora (gatilho adiado)
  if v_barco is null then raise exception 'FALHOU: nenhum barco cadastrado para montar as OS de teste'; end if;

  insert into public.products (name, stock_quantity) values ('TESTE P5 — Cerbo GX', 0) returning id into v_p1;
  insert into public.products (name, stock_quantity) values ('TESTE P5 — Fusível MIDI', 0) returning id into v_p2;
  insert into public.products (name, stock_quantity) values ('TESTE P5 — Cabo 16mm', 0) returning id into v_p3;
  perform public.entrada_de_estoque(v_p1, 1, 1500, 'TESTE P5');
  perform public.entrada_de_estoque(v_p2, 2, 30, 'TESTE P5');

  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-P5-A', 'approved', 'approved') returning id into v_a;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-P5-B', 'open', 'approved') returning id into v_b;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-P5-D', 'approved', 'approved') returning id into v_d;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-P5-E', 'open', 'approved') returning id into v_e;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-P5-F', 'invoiced', 'approved') returning id into v_f;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-P5-G', 'awaiting_parts', 'approved') returning id into v_g;

  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, created_at)
  values (v_a, v_p1, 1, 1500, 2500, 1500, 2500, now() - interval '5 seconds'),
         (v_b, v_p1, 1, 1500, 2500, 1500, 2500, now() - interval '4 seconds'),
         (v_d, v_p2, 1, 30, 60, 30, 60, now() - interval '3 seconds'),
         (v_d, v_p2, 1, 30, 60, 30, 60, now() - interval '2 seconds'),
         (v_e, v_p3, 2, 30, 60, 60, 120, now() - interval '1 second');
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot,
                                             quantity, unit_price_snapshot)
  values (v_g, null, 'Conversão do sistema de refrigeração para 12V — Refrigerador TESTE', 'unit', 1, 2500);

  -- O estoque v2 reservou: P1 = 1 (só a A reserva; a B está aberta), P2 = 2 (as duas linhas da D).
  insert into _resultado values ('00 reserva montada pelo estoque v2',
    (select reserved_quantity from public.products where id = v_p1) = 1
    and (select reserved_quantity from public.products where id = v_p2) = 2,
    format('P1 %s, P2 %s', (select reserved_quantity from public.products where id = v_p1),
                           (select reserved_quantity from public.products where id = v_p2)));

  -- A
  r := public.get_os_purchase_needs(v_a);
  insert into _resultado values ('A aprovada, peça reservada para ela mesma = ok',
    r->'items'->0->>'status' = 'ok' and (r->'items'->0->>'available')::numeric = 1 and (r->>'shortageCount')::int = 0,
    (r->'items'->0)::text);

  -- B
  r := public.get_os_purchase_needs(v_b);
  insert into _resultado values ('B aberta, peça reservada pela A = missing',
    r->'items'->0->>'status' = 'missing' and (r->'items'->0->>'available')::numeric = 0
    and (r->'items'->0->>'shortage')::numeric = 1,
    (r->'items'->0)::text);

  -- D
  r := public.get_os_purchase_needs(v_d);
  insert into _resultado values ('D duas linhas somam a reserva própria',
    jsonb_array_length(r->'items') = 2
    and (select count(*) from jsonb_array_elements(r->'items') i
          where i->>'status' = 'ok' and (i->>'available')::numeric = 1) = 2
    and (r->>'shortageCount')::int = 0,
    (r->'items')::text);

  -- C (por último no P1: mexe no reservado à mão e devolve no fim)
  update public.products set reserved_quantity = 0 where id = v_p1;
  r := public.get_os_purchase_needs(v_a);
  insert into _resultado values ('C reservado defasado: disponível 1, nunca 2',
    (r->'items'->0->>'available')::numeric = 1 and r->'items'->0->>'status' = 'ok',
    (r->'items'->0)::text);
  perform public.recompute_product_reservations(v_p1);

  -- E1: OC aberta da OS faturada não abate
  insert into public.purchase_orders (po_number, status, service_order_id)
  values ('OC-TESTE-P5-1', 'sent', v_f) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, v_p3, 'TESTE P5 — Cabo 16mm', 2, 12);
  r := public.get_os_purchase_needs(v_e);
  insert into _resultado values ('E1 OC de OS faturada não abate',
    (r->'items'->0->>'onOrder')::numeric = 0 and (r->'items'->0->>'shortage')::numeric = 2,
    (r->'items'->0)::text);

  -- E2: OC aberta de 61 dias não abate
  insert into public.purchase_orders (po_number, status, created_at)
  values ('OC-TESTE-P5-2', 'sent', now() - interval '61 days') returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, v_p3, 'TESTE P5 — Cabo 16mm', 2, 12);
  r := public.get_os_purchase_needs(v_e);
  insert into _resultado values ('E2 OC de 61 dias não abate',
    (r->'items'->0->>'onOrder')::numeric = 0 and (r->'items'->0->>'shortage')::numeric = 2,
    (r->'items'->0)::text);

  -- E3: OC recente, sem OS, abate 1 de 2
  insert into public.purchase_orders (po_number, status)
  values ('OC-TESTE-P5-3', 'sent') returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, v_p3, 'TESTE P5 — Cabo 16mm', 1, 12);
  r := public.get_os_purchase_needs(v_e);
  insert into _resultado values ('E3 OC recente abate (1 de 2)',
    (r->'items'->0->>'onOrder')::numeric = 1 and (r->'items'->0->>'shortage')::numeric = 1
    and (r->>'shortageCount')::int = 1 and (r->>'estimatedCost')::numeric = 30,
    r::text);
  antes := r;

  -- F: OC de texto livre da própria OS → items ganha o 'a caminho', o resto não muda
  insert into public.purchase_orders (po_number, status, service_order_id)
  values ('OC-TESTE-P5-4', 'draft', v_e) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost)
  values (v_oc, null, 'Compressor TESTE P5', 1, 0, 900),
         (v_oc, null, 'Suporte TESTE P5 (já chegou)', 1, 1, 5);
  insert into public.purchase_orders (po_number, status, service_order_id)
  values ('OC-TESTE-P5-5', 'cancelled', v_e) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, null, 'Bomba TESTE P5 (OC cancelada)', 1, 50);
  r := public.get_os_purchase_needs(v_e);
  select jsonb_agg(i) into itens from jsonb_array_elements(r->'items') i where i->>'origin' = 'purchase_order';
  insert into _resultado values ('F texto livre de OC da OS aparece a caminho',
    jsonb_array_length(coalesce(itens, '[]')) = 1
    and itens->0->>'description' = 'Compressor TESTE P5'
    and itens->0->>'status' = 'on_order'
    and itens->0->>'purchaseOrderNumber' = 'OC-TESTE-P5-4'
    and (itens->0->>'shortage')::numeric = 0
    and (itens->0->>'onOrder')::numeric = 1
    and itens->0->'productId' = 'null'::jsonb,
    coalesce(itens::text, '(nenhum)'));
  insert into _resultado values ('F o a caminho não muda shortages, contagem, custo nem precisa',
    r->'shortages' = antes->'shortages'
    and r->'shortageCount' = antes->'shortageCount'
    and (r->>'estimatedCost')::numeric = (antes->>'estimatedCost')::numeric
    and r->'needsPurchase' = antes->'needsPurchase'
    and jsonb_array_length(r->'items') = jsonb_array_length(antes->'items') + 1,
    r::text);
  insert into _resultado values ('F count_purchase_shortages segue a mesma contagem',
    public.count_purchase_shortages(array[v_e]) = jsonb_build_object(v_e::text, 1),
    public.count_purchase_shortages(array[v_e])::text);

  -- F2: o "a caminho" de texto livre da própria OS não tem idade (revisão de 23/10). O corte de 60 dias
  -- é do "já pedido" de catálogo (E2); aqui ele só esconderia o item, como a OC-00004 da OS-00104 em 12/12.
  antes := r;
  insert into public.purchase_orders (po_number, status, service_order_id, created_at)
  values ('OC-TESTE-P5-7', 'draft', v_e, now() - interval '61 days') returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost)
  values (v_oc, null, 'Bomba TESTE P5 (OC de 61 dias)', 1, 0, 50);
  r := public.get_os_purchase_needs(v_e);
  select jsonb_agg(i) into itens from jsonb_array_elements(r->'items') i
   where i->>'origin' = 'purchase_order' and i->>'purchaseOrderNumber' = 'OC-TESTE-P5-7';
  insert into _resultado values ('F2 texto livre de OC da OS com 61 dias continua a caminho',
    jsonb_array_length(coalesce(itens, '[]')) = 1
    and itens->0->>'description' = 'Bomba TESTE P5 (OC de 61 dias)'
    and itens->0->>'status' = 'on_order'
    and (itens->0->>'shortage')::numeric = 0
    and (itens->0->>'onOrder')::numeric = 1,
    coalesce(itens::text, '(nenhum)'));
  insert into _resultado values ('F2 a OC velha da própria OS não muda falta, contagem nem custo',
    r->'shortages' = antes->'shortages'
    and r->'shortageCount' = antes->'shortageCount'
    and (r->>'estimatedCost')::numeric = (antes->>'estimatedCost')::numeric
    and jsonb_array_length(r->'items') = jsonb_array_length(antes->'items') + 1,
    r::text);
  insert into _resultado values ('F2 a view marca a OC de 61 dias fora do já pedido e a recente dentro',
    (select bool_and(not v.conta_como_ja_pedido) from public.v_oc_itens_a_caminho v where v.purchase_order_id = v_oc)
    and (select bool_and(v.conta_como_ja_pedido) from public.v_oc_itens_a_caminho v where v.po_number = 'OC-TESTE-P5-3'),
    null);

  -- G: a OS-00104 em miniatura
  insert into public.purchase_orders (po_number, status, service_order_id)
  values ('OC-TESTE-P5-6', 'draft', v_g) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc, null, 'Compressor 12V TESTE', 1, 0);
  r := public.get_os_purchase_needs(v_g);
  insert into _resultado values ('G conversão é serviço; falta 0 e o compressor a caminho',
    (r->>'shortageCount')::int = 0 and (r->>'needsPurchase')::boolean = false
    and jsonb_array_length(r->'items') = 1
    and r->'items'->0->>'origin' = 'purchase_order'
    and r->'items'->0->>'purchaseOrderNumber' = 'OC-TESTE-P5-6',
    r::text);
  insert into _resultado values ('G count_purchase_shortages não acusa a OS',
    public.count_purchase_shortages(array[v_g]) = '{}'::jsonb,
    public.count_purchase_shortages(array[v_g])::text);
end
$teste$;

-- L e O: Agenda de Produção, Fase 4 (P2). Só com a migration 20261027100200 (a função nova dela é o marco).
do $fase4$
declare
  v_barco   uuid := (select id from public.vessels where client_id is not null order by created_at limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
  v_l uuid; v_o uuid; v_po uuid; v_p uuid;
  l1 uuid; l2 uuid; l3 uuid; l4 uuid; l5 uuid; i_l3 uuid; i_l6 uuid; o1 uuid;
  r jsonb; itens jsonb;
begin
  if to_regprocedure('public.agenda_ocs_com_material_vivo(uuid[])') is null then return; end if;
  set constraints all immediate;

  -- ── L: a OC ligada ao item de texto livre ──────────────────────────────────────────────────────────────
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-P5-L', 'awaiting_parts', 'approved') returning id into v_l;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_l, null, 'Cabo PP 2x2,5mm (caso L)', 'unit', 10, 12, now() - interval '50 seconds') returning id into l1;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_l, null, 'Terminal olhal 6mm (caso L)', 'unit', 4, 3, now() - interval '49 seconds') returning id into l2;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_l, null, 'Conversão do sistema de refrigeração para 12V — TESTE L', 'unit', 1, 2500, now() - interval '48 seconds')
  returning id into l3;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_l, null, 'Bomba de porão 12V (caso L)', 'unit', 2, 300, now() - interval '47 seconds') returning id into l4;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, created_at)
  values (v_l, null, 'Fusível MIDI 100A (caso L)', 'unit', 3, 40, now() - interval '46 seconds') returning id into l5;
  -- O material do caso não leva a palavra 'teste' no nome: o classificador a lê como verbo de serviço (diagnóstico).
  insert into _resultado values ('L0 o classificador: os 4 são material e a Conversão é serviço (o cenário vale)',
    public.free_text_is_material('Cabo PP 2x2,5mm (caso L)') and public.free_text_is_material('Terminal olhal 6mm (caso L)')
    and public.free_text_is_material('Bomba de porão 12V (caso L)') and public.free_text_is_material('Fusível MIDI 100A (caso L)')
    and not public.free_text_is_material('Conversão do sistema de refrigeração para 12V — TESTE L'), null);

  -- OC-L1 enviada: 6 do cabo (dos 10). OC-L2 recebida em parte: 1 de 4 terminais. OC-L3 rascunho: o compressor ligado à
  -- Conversão (serviço, fora da conta). OC-L4 marcada recebida à mão (received_qty 0): as 2 bombas. OC-L5 cancelada: 5 do
  -- cabo. OC-L6 rascunho: um suporte sem vínculo.
  insert into public.purchase_orders (po_number, status, service_order_id, created_at)
  values ('OC-TESTE-P5-L1', 'sent', v_l, now() - interval '6 minutes') returning id into v_po;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost,
                                           service_order_service_id)
  values (v_po, null, 'Cabo PP 2x2,5mm', 6, 0, 12, l1);
  insert into public.purchase_orders (po_number, status, service_order_id, created_at)
  values ('OC-TESTE-P5-L2', 'partial', v_l, now() - interval '5 minutes') returning id into v_po;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost,
                                           service_order_service_id)
  values (v_po, null, 'Terminal olhal 6mm', 4, 1, 3, l2);
  insert into public.purchase_orders (po_number, status, service_order_id, created_at)
  values ('OC-TESTE-P5-L3', 'draft', v_l, now() - interval '4 minutes') returning id into v_po;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost,
                                           service_order_service_id)
  values (v_po, null, 'Compressor TESTE L', 1, 0, 0, l3) returning id into i_l3;
  insert into public.purchase_orders (po_number, status, service_order_id, created_at)
  values ('OC-TESTE-P5-L4', 'received', v_l, now() - interval '3 minutes') returning id into v_po;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost,
                                           service_order_service_id)
  values (v_po, null, 'Bomba de porão 12V', 2, 0, 300, l4);
  insert into public.purchase_orders (po_number, status, service_order_id, created_at)
  values ('OC-TESTE-P5-L5', 'cancelled', v_l, now() - interval '2 minutes') returning id into v_po;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost,
                                           service_order_service_id)
  values (v_po, null, 'Cabo PP 2x2,5mm (cancelada)', 5, 0, 12, l1);
  insert into public.purchase_orders (po_number, status, service_order_id, created_at)
  values ('OC-TESTE-P5-L6', 'draft', v_l, now() - interval '1 minute') returning id into v_po;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, received_qty, unit_cost)
  values (v_po, null, 'Suporte TESTE L', 1, 0, 5) returning id into i_l6;

  r := public.get_os_purchase_needs(v_l);
  select jsonb_agg(jsonb_build_array(i ->> 'sourceId', i ->> 'origin', i ->> 'status', (i ->> 'available')::numeric,
                                     (i ->> 'onOrder')::numeric, (i ->> 'shortage')::numeric, i ->> 'purchaseOrderNumber')
                   order by o)
    into itens
    from jsonb_array_elements(r -> 'items') with ordinality as x(i, o);
  insert into _resultado values ('L1 items: cabo falta 4 (OC-L1), terminal 1 na mão + 3 pedidos (OC-L2), bomba ok (OC-L4), fusível falta 3; a caminho só o compressor (OC-L3) e o suporte (OC-L6)',
    itens = jsonb_build_array(
      jsonb_build_array(l1::text, 'free_text', 'uncatalogued', 0, 6, 4, 'OC-TESTE-P5-L1'),
      jsonb_build_array(l2::text, 'free_text', 'on_order', 1, 3, 0, 'OC-TESTE-P5-L2'),
      jsonb_build_array(l4::text, 'free_text', 'ok', 2, 0, 0, 'OC-TESTE-P5-L4'),
      jsonb_build_array(l5::text, 'free_text', 'uncatalogued', 0, 0, 3, null),
      jsonb_build_array(i_l3::text, 'purchase_order', 'on_order', 0, 1, 0, 'OC-TESTE-P5-L3'),
      jsonb_build_array(i_l6::text, 'purchase_order', 'on_order', 0, 1, 0, 'OC-TESTE-P5-L6')),
    itens::text);
  insert into _resultado values ('L2 shortages [cabo (4), fusível (3)], contagem 2, custo 168, precisa comprar',
    (select jsonb_agg(s ->> 'sourceId' order by o) from jsonb_array_elements(r -> 'shortages') with ordinality as x(s, o))
      = jsonb_build_array(l1::text, l5::text)
    and (r ->> 'shortageCount')::int = 2 and (r ->> 'estimatedCost')::numeric = 168 and (r ->> 'needsPurchase')::boolean,
    format('%s · %s · %s', r -> 'shortages', r ->> 'shortageCount', r ->> 'estimatedCost'));
  insert into _resultado values ('L3 count_purchase_shortages segue a conta (2)',
    public.count_purchase_shortages(array[v_l]) = jsonb_build_object(v_l::text, 2),
    public.count_purchase_shortages(array[v_l])::text);

  -- ── O: o material citado pelo dono ─────────────────────────────────────────────────────────────────────
  insert into public.products (name, stock_quantity) values ('TESTE P5 — Cabo O', 0) returning id into v_p;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-P5-O', 'open', 'approved') returning id into v_o;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_o, v_p, 1, 100, 180, 100, 180) returning id into o1;
  -- ids em ordem: a conta lê as linhas por id (a ordem do fim de items).
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao,
                                  situacao, fonte, chegou_em)
  values ('f5000000-0000-4000-8000-000000000001', v_o, 'dono', 'Parafuso inox M6 (citado)', 8, 0, 'falta', 'dono', null),
         ('f5000000-0000-4000-8000-000000000002', v_o, 'dono', 'Abraçadeira (citada)', 2, 0, 'comprado', 'dono', null),
         ('f5000000-0000-4000-8000-000000000003', v_o, 'dono', 'Fita de autofusão (citada)', 3, 1, 'a_caminho', 'dono', null),
         ('f5000000-0000-4000-8000-000000000004', v_o, 'dono', 'Graxa (citada)', 1, 0, 'dispensado', 'dono', null),
         ('f5000000-0000-4000-8000-000000000005', v_o, 'dono', 'Silicone (citado)', 1, 1, 'na_mao', 'dono', '2026-10-20'),
         ('f5000000-0000-4000-8000-000000000006', v_o, 'dono', 'Lixa (citada)', 5, 2, 'falta', 'dono', null);

  r := public.get_os_purchase_needs(v_o);
  select jsonb_agg(jsonb_build_array(i ->> 'sourceId', i ->> 'origin', i ->> 'status', (i ->> 'required')::numeric,
                                     (i ->> 'available')::numeric, (i ->> 'onOrder')::numeric, (i ->> 'shortage')::numeric,
                                     (i ->> 'unitCost')::numeric, i -> 'semPreco')
                   order by o)
    into itens
    from jsonb_array_elements(r -> 'items') with ordinality as x(i, o);
  insert into _resultado values ('O1 items: a peça; parafuso falta 8; abraçadeira e fita já pedidas (a fita com 1 na mão); lixa 2 na mão e falta 3 — sem preço; graxa (dispensada) e silicone (na mão) fora',
    itens = jsonb_build_array(
      jsonb_build_array(o1::text, 'part', 'missing', 1, 0, 0, 1, 100, null),
      jsonb_build_array('f5000000-0000-4000-8000-000000000001', 'dono', 'uncatalogued', 8, 0, 0, 8, 0, true),
      jsonb_build_array('f5000000-0000-4000-8000-000000000002', 'dono', 'on_order', 2, 0, 2, 0, 0, true),
      jsonb_build_array('f5000000-0000-4000-8000-000000000003', 'dono', 'on_order', 3, 1, 2, 0, 0, true),
      jsonb_build_array('f5000000-0000-4000-8000-000000000006', 'dono', 'uncatalogued', 5, 2, 0, 3, 0, true)),
    itens::text);
  insert into _resultado values ('O2 shortages [peça, parafuso, lixa], contagem 3, custo 100 (o do dono fora), semPreco 2',
    (select jsonb_agg(s ->> 'sourceId' order by o) from jsonb_array_elements(r -> 'shortages') with ordinality as x(s, o))
      = jsonb_build_array(o1::text, 'f5000000-0000-4000-8000-000000000001', 'f5000000-0000-4000-8000-000000000006')
    and (r ->> 'shortageCount')::int = 3 and (r ->> 'estimatedCost')::numeric = 100 and (r ->> 'semPreco')::int = 2
    and (r ->> 'needsPurchase')::boolean
    and (select bool_and(i ->> 'description' like '%(citad%' and i -> 'productId' = 'null'::jsonb)
           from jsonb_array_elements(r -> 'items') i where i ->> 'origin' = 'dono'),
    format('%s · %s · %s · %s', r -> 'shortages', r ->> 'shortageCount', r ->> 'estimatedCost', r ->> 'semPreco'));
  insert into _resultado values ('O3 count_purchase_shortages conta o material citado (3; a R16 herda)',
    public.count_purchase_shortages(array[v_o]) = jsonb_build_object(v_o::text, 3),
    public.count_purchase_shortages(array[v_o])::text);
end
$fase4$;

-- H: o classificador
insert into _resultado values
  ('H Conversão… é serviço',
   public.free_text_is_material('Conversão do sistema de refrigeração para 12V — Refrigerador Consul') = false,
   public.classify_service_text('Conversão do sistema de refrigeração para 12V — Refrigerador Consul')::text),
  ('H Conversor DC-DC… é material',
   public.free_text_is_material('Conversor DC-DC 12/24V 20A') = true,
   public.classify_service_text('Conversor DC-DC 12/24V 20A')::text),
  ('H Kit de conversão… é material (o prefixo vence)',
   public.free_text_is_material('Kit de conversão LED') = true,
   public.classify_service_text('Kit de conversão LED')::text),
  ('H conversão vira o verbo adequacao',
   public.classify_service_text('Conversão do sistema de refrigeração para 12V')->>'verbo' = 'adequacao',
   null);

-- I: portas
insert into _resultado values
  ('I anon sem execute (3 funções)',
   not has_function_privilege('anon', 'public.get_os_purchase_needs(uuid)', 'execute')
   and not has_function_privilege('anon', 'public.count_purchase_shortages(uuid[])', 'execute')
   and not has_function_privilege('anon', 'public.classify_service_text(text)', 'execute'),
   null),
  ('I anon sem select na view',
   not has_table_privilege('anon', 'public.v_oc_itens_a_caminho', 'select'),
   null),
  ('I authenticated com execute e select',
   has_function_privilege('authenticated', 'public.get_os_purchase_needs(uuid)', 'execute')
   and has_function_privilege('authenticated', 'public.count_purchase_shortages(uuid[])', 'execute')
   and has_function_privilege('authenticated', 'public.classify_service_text(text)', 'execute')
   and has_table_privilege('authenticated', 'public.v_oc_itens_a_caminho', 'select'),
   null),
  ('I authenticated só lê a view',
   not has_table_privilege('authenticated', 'public.v_oc_itens_a_caminho', 'insert')
   and not has_table_privilege('authenticated', 'public.v_oc_itens_a_caminho', 'update')
   and not has_table_privilege('authenticated', 'public.v_oc_itens_a_caminho', 'delete'),
   null),
  ('I view com security_invoker',
   exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relname = 'v_oc_itens_a_caminho'
              and 'security_invoker=on' = any (coalesce(c.reloptions, '{}'))),
   null);

select teste, ok, detalhe from _resultado order by teste;

rollback;
