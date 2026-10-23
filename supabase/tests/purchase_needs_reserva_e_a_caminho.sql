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
--
-- Os MESMOS números estão em src/hooks/use-purchase-needs.test.ts (A, B, D, E, G) e em
-- src/lib/purchase-needs.test.ts (a–e).
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
