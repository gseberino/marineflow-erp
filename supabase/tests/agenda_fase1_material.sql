-- Prova de material e compras da Agenda de Produção, Fase 1 (pacote P2): migration 20261024160300.
-- bancada: depende de 20261024160300
--
--   A  sem fato informado nada muda: aplicar_os_material(bruto, '[]') = bruto; get_os_purchase_needs =
--      os_necessidade_bruta em toda OS sem fato informado (antes e depois da sincronização: a linha que o
--      sistema copiou não mexe na conta); p_linhas nulo ou torto também devolve idêntico
--   B  o MESMO cenário numérico de src/lib/purchase-needs.test.ts e src/hooks/use-purchase-needs.test.ts (OS M):
--      na_mao → ok; parcial 3 de 8 → partial com falta 5; dispensado some (de items e de shortages);
--      a_caminho e comprado → on_order; shortageCount 1, estimatedCost 125, needsPurchase; informado por item.
--      Mais: parcial 1 de 2 no texto livre; ordem determinística dos shortages (rank, falta desc, posição
--      original); a linha do dono (origem 'dono') não entra na compra; leitura 2× = mesmo md5
--   C  count_purchase_shortages deixa de acusar a OS com tudo comprado (é o que fecha a R16)
--   D  sincronização (OS S): cria uma linha por item com a situação inicial (estoque → na_mao, OC de catálogo →
--      a_caminho com a previsão e o fornecedor da OC, OC de texto livre → a_caminho, resto → falta); reaplicar
--      não duplica nem toca atualizado_em; o estoque que deixa de cobrir derruba a linha do sistema; o fato do
--      dono fica; a quantidade que sobe derruba o na_mao do dono (e a conta já acusa antes da sincronização);
--      OC recebida → na_mao; OC cancelada → falta; falta do dono que ganhou OC → a_caminho; histórico ≤ 20;
--      apagar o item da OC apaga a linha (FK CASCADE)
--   E  carteira: o erro de uma OS sai em erros e não derruba as outras
--   F  portas: anon sem nada; as leituras para authenticated (invoker); a sincronização só service_role
--      (definer); aplicar_os_material IMMUTABLE; search_path fixo; o técnico (sem ler os_material) recebe a
--      conta bruta, sem erro
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261024160300
--   Em produção, só DEPOIS de aplicar 160000..160300, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase1_material.sql
--   Seguro em produção: produtos, fornecedor, OS e OC de teste (TESTE AG2, OS-TESTE-AG2-*, OC-TESTE-AG2-*) só
--   são inseridos ou mexidos dentro da transação; o estoque entra por entrada_de_estoque; o caso E cria um
--   gatilho de teste em os_material que some com o ROLLBACK (trava a tabela por menos de 1 s); a sincronização
--   da carteira passa pelas OS reais e também é desfeita. Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- O item de uma necessidade pelo id da linha de origem.
create function pg_temp.item(p jsonb, p_id uuid) returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(coalesce(p -> 'items', '[]'::jsonb)) i where i ->> 'sourceId' = p_id::text
$f$;

-- A linha de material de uma linha de origem (peça, serviço ou item de OC).
create function pg_temp.linha(p_id uuid) returns public.os_material language sql stable as $f$
  select m.* from public.os_material m
   where p_id in (m.service_order_part_id, m.service_order_service_id, m.purchase_order_item_id)
   order by m.origem = 'dono', m.id limit 1
$f$;

do $teste$
declare
  c_hoje    constant date := date '2026-10-23';
  v_barco   uuid := (select id from public.vessels where client_id is not null order by created_at, id limit 1);
  v_cliente uuid := (select client_id from public.vessels where id = v_barco);
  v_forn uuid;
  v_p1 uuid; v_p2 uuid; v_p3 uuid; v_p4 uuid; v_p5 uuid; v_p6 uuid; v_p7 uuid;
  v_m uuid; v_n uuid; v_s uuid; v_r uuid; v_e uuid; v_f uuid;
  m1 uuid; m2 uuid; m3 uuid; m4 uuid; m5 uuid; n1 uuid; n2 uuid;
  s1 uuid; s2 uuid; s4 uuid; s5 uuid; s3 uuid; s3b uuid; s6 uuid;
  v_oc1 uuid; v_oc2 uuid; v_oc3 uuid; v_oc4 uuid; f1 uuid;
  r jsonb; b jsonb; x jsonb; v_lin public.os_material; v_ok boolean; v_txt text; v_n_antes int;
  v_puro jsonb;
begin
  set constraints all immediate;   -- o saldo do estoque é recalculado na hora (gatilho adiado)
  if v_barco is null then raise exception 'FALHOU: nenhum barco cadastrado para montar as OS de teste'; end if;

  insert into public.suppliers (name) values ('TESTE AG2 — Fornecedor') returning id into v_forn;
  insert into public.products (name, stock_quantity) values ('TESTE AG2 — Cerbo', 0)    returning id into v_p1;
  insert into public.products (name, stock_quantity) values ('TESTE AG2 — Fusível', 0)  returning id into v_p2;
  insert into public.products (name, stock_quantity) values ('TESTE AG2 — Cabo', 0)     returning id into v_p3;
  insert into public.products (name, stock_quantity) values ('TESTE AG2 — Painel', 0)   returning id into v_p4;
  insert into public.products (name, stock_quantity) values ('TESTE AG2 — Terminal', 0) returning id into v_p5;
  insert into public.products (name, stock_quantity) values ('TESTE AG2 — Orion', 0)    returning id into v_p6;
  insert into public.products (name, stock_quantity) values ('TESTE AG2 — Bateria', 0)  returning id into v_p7;
  perform public.entrada_de_estoque(v_p5, 5, 10, 'TESTE AG2');

  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG2-M', 'open', 'approved') returning id into v_m;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG2-N', 'open', 'approved') returning id into v_n;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG2-S', 'open', 'approved') returning id into v_s;

  -- ── OS M: o cenário numérico (o mesmo dos dois testes vitest) ──────────────────────────────────────────
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, created_at)
  values (v_m, v_p1, 1, 1900, 3000, 1900, 3000, now() - interval '50 seconds') returning id into m1;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, created_at)
  values (v_m, v_p2, 8, 25, 45, 200, 360, now() - interval '49 seconds') returning id into m2;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, created_at)
  values (v_m, v_p3, 1, 210, 350, 210, 350, now() - interval '48 seconds') returning id into m3;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, created_at)
  values (v_m, v_p4, 1, 1250, 2088, 1250, 2088, now() - interval '47 seconds') returning id into m4;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot,
                                             quantity, unit_price_snapshot, created_at)
  values (v_m, null, 'Conector de cabo de dados AG2', 'unit', 2, 120, now() - interval '46 seconds')
  returning id into m5;

  -- A1: sem linhas, idêntico
  b := public.os_necessidade_bruta(v_m);
  insert into _resultado values ('A0 bruto da OS M: 5 itens, 5 faltas, custo 3800',
    jsonb_array_length(b -> 'items') = 5 and (b ->> 'shortageCount')::int = 5 and (b ->> 'estimatedCost')::numeric = 3800,
    b::text);
  insert into _resultado values ('A1 aplicar_os_material sem linhas = idêntico',
    public.aplicar_os_material(b, '[]'::jsonb) = b and public.get_os_purchase_needs(v_m) = b, null);
  insert into _resultado values ('A2 p_linhas nulo ou torto = idêntico; p_needs nulo = nulo',
    public.aplicar_os_material(b, null) = b and public.aplicar_os_material(b, '{"x":1}'::jsonb) = b
    and public.aplicar_os_material(null, '[]'::jsonb) is null, null);
  select bool_and(public.get_os_purchase_needs(so.id) = public.os_necessidade_bruta(so.id)), count(*)
    into v_ok, v_n_antes
    from public.service_orders so;
  insert into _resultado values ('A3 sem os_material, get_os_purchase_needs = os_necessidade_bruta em toda OS',
    coalesce(v_ok, true) and not exists (select 1 from public.os_material m where m.fonte in ('dono','fornecedor','nfe','pix')),
    format('%s OS', v_n_antes));

  -- B: o que o dono disse (como o *grava* do P5 gravaria)
  insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                  quantidade_na_mao, situacao, fonte, chegou_em, trecho)
  values (v_m, m1, 'peca', 'TESTE AG2 — Cerbo', 1, 1, 'na_mao', 'dono', '2026-10-14', 'o Cerbo tá aqui');
  insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                  quantidade_na_mao, situacao, fonte)
  values (v_m, m2, 'peca', 'TESTE AG2 — Fusível', 8, 3, 'falta', 'dono');
  insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                  situacao, fonte)
  values (v_m, m3, 'peca', 'TESTE AG2 — Cabo', 1, 'dispensado', 'dono');
  insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria,
                                  situacao, fonte, previsao_ate, previsao_original, previsao_fonte)
  values (v_m, m4, 'peca', 'TESTE AG2 — Painel', 1, 'a_caminho', 'dono', '2026-11-03', '2026-11-03', 'dono');
  insert into public.os_material (service_order_id, service_order_service_id, origem, descricao, quantidade_necessaria,
                                  situacao, fonte, comprado_em)
  values (v_m, m5, 'texto_livre', 'Conector de cabo de dados AG2', 2, 'comprado', 'dono', '2026-10-20');
  -- A linha do DONO que cita a mesma linha de serviço (peça embutida) não entra na compra nesta fase.
  insert into public.os_material (service_order_id, service_order_service_id, origem, descricao, quantidade_necessaria,
                                  situacao, fonte)
  values (v_m, m5, 'dono', 'parafusos do conector', 4, 'dispensado', 'dono');

  r := public.get_os_purchase_needs(v_m);
  insert into _resultado values ('B1 na_mao → ok, disponível 1, informado na_mao',
    pg_temp.item(r, m1) ->> 'status' = 'ok' and (pg_temp.item(r, m1) ->> 'available')::numeric = 1
    and (pg_temp.item(r, m1) ->> 'shortage')::numeric = 0 and pg_temp.item(r, m1) ->> 'informado' = 'na_mao',
    pg_temp.item(r, m1)::text);
  insert into _resultado values ('B2 parcial 3 de 8 → partial, disponível 3, falta 5, informado parcial',
    pg_temp.item(r, m2) ->> 'status' = 'partial' and (pg_temp.item(r, m2) ->> 'available')::numeric = 3
    and (pg_temp.item(r, m2) ->> 'shortage')::numeric = 5 and pg_temp.item(r, m2) ->> 'informado' = 'parcial',
    pg_temp.item(r, m2)::text);
  insert into _resultado values ('B3 dispensado some de items e de shortages',
    pg_temp.item(r, m3) is null
    and not exists (select 1 from jsonb_array_elements(r -> 'shortages') s where s ->> 'sourceId' = m3::text)
    and jsonb_array_length(r -> 'items') = 4,
    (r -> 'items')::text);
  insert into _resultado values ('B4 a_caminho → on_order (já pedido 1), informado a_caminho',
    pg_temp.item(r, m4) ->> 'status' = 'on_order' and (pg_temp.item(r, m4) ->> 'onOrder')::numeric = 1
    and (pg_temp.item(r, m4) ->> 'shortage')::numeric = 0 and pg_temp.item(r, m4) ->> 'informado' = 'a_caminho',
    pg_temp.item(r, m4)::text);
  insert into _resultado values ('B5 comprado (texto livre) → on_order (já pedido 2), informado comprado; a linha do dono não conta',
    pg_temp.item(r, m5) ->> 'status' = 'on_order' and (pg_temp.item(r, m5) ->> 'onOrder')::numeric = 2
    and (pg_temp.item(r, m5) ->> 'shortage')::numeric = 0 and pg_temp.item(r, m5) ->> 'informado' = 'comprado',
    pg_temp.item(r, m5)::text);
  insert into _resultado values ('B6 o cenário fecha: shortageCount 1, estimatedCost 125, needsPurchase, shortages = [fusível]',
    (r ->> 'shortageCount')::int = 1 and (r ->> 'estimatedCost')::numeric = 125 and (r ->> 'needsPurchase')::boolean
    and (select array_agg(s ->> 'sourceId') from jsonb_array_elements(r -> 'shortages') s) = array[m2::text]
    and (select array_agg(i ->> 'sourceId') from jsonb_array_elements(r -> 'items') i)
        = array[m1::text, m2::text, m4::text, m5::text]
    and r ->> 'serviceOrderId' = v_m::text,
    format('%s · %s', r ->> 'shortageCount', r ->> 'estimatedCost'));
  insert into _resultado values ('B7 determinístico: duas leituras, mesmo md5',
    md5(public.get_os_purchase_needs(v_m)::text) = md5(public.get_os_purchase_needs(v_m)::text), null);

  -- B8 parcial 1 de 2 no texto livre: falta 1 e continua "sem cadastro"
  update public.os_material set situacao = 'falta', quantidade_na_mao = 1, comprado_em = null
   where service_order_service_id = m5 and origem = 'texto_livre';
  r := public.get_os_purchase_needs(v_m);
  insert into _resultado values ('B8 parcial 1 de 2 (texto livre) → disponível 1, falta 1, uncatalogued, informado parcial',
    pg_temp.item(r, m5) ->> 'status' = 'uncatalogued' and (pg_temp.item(r, m5) ->> 'available')::numeric = 1
    and (pg_temp.item(r, m5) ->> 'shortage')::numeric = 1 and pg_temp.item(r, m5) ->> 'informado' = 'parcial'
    and (r ->> 'shortageCount')::int = 2 and (r ->> 'estimatedCost')::numeric = 245,
    pg_temp.item(r, m5)::text);

  -- B9 ordem determinística com empate (o mesmo JSON do vitest): rank, falta desc, posição original
  v_puro := '{"serviceOrderId":"os-t","items":[
     {"sourceId":"x1","origin":"part","productId":"p1","description":"A","unit":null,"required":1,"available":0,"onOrder":0,"shortage":1,"status":"missing","unitCost":10},
     {"sourceId":"x2","origin":"part","productId":"p2","description":"B","unit":null,"required":1,"available":0,"onOrder":0,"shortage":1,"status":"missing","unitCost":10},
     {"sourceId":"x3","origin":"part","productId":"p3","description":"C","unit":null,"required":2,"available":0,"onOrder":0,"shortage":2,"status":"missing","unitCost":5},
     {"sourceId":"x4","origin":"free_text","productId":null,"description":"D","unit":null,"required":3,"available":0,"onOrder":0,"shortage":3,"status":"uncatalogued","unitCost":1},
     {"sourceId":"x5","origin":"part","productId":"p5","description":"E","unit":null,"required":4,"available":0,"onOrder":0,"shortage":4,"status":"missing","unitCost":2}],
   "shortages":[],"shortageCount":5,"estimatedCost":0,"needsPurchase":true}'::jsonb;
  x := public.aplicar_os_material(v_puro, '[{"service_order_part_id":"x5","origem":"peca","situacao":"falta","fonte":"dono","quantidade_necessaria":4,"quantidade_na_mao":1}]'::jsonb);
  insert into _resultado values ('B9 shortages em ordem: x3 (falta 2), x1, x2 (empate pela posição), x5 (parcial), x4 (sem cadastro)',
    (select array_agg(s ->> 'sourceId') from jsonb_array_elements(x -> 'shortages') s) = array['x3','x1','x2','x5','x4']
    and (x ->> 'estimatedCost')::numeric = 39 and (x ->> 'shortageCount')::int = 5,
    (x -> 'shortages')::text);
  insert into _resultado values ('B10 a linha copiada pelo sistema (fonte nula, estoque, oc) não muda a conta',
    public.aplicar_os_material(v_puro, '[{"service_order_part_id":"x1","origem":"peca","situacao":"na_mao","fonte":"estoque","quantidade_necessaria":1,"quantidade_na_mao":1},
                                          {"service_order_part_id":"x2","origem":"peca","situacao":"a_caminho","fonte":"oc","quantidade_necessaria":1,"quantidade_na_mao":0},
                                          {"service_order_part_id":"x3","origem":"peca","situacao":"comprado","fonte":null,"quantidade_necessaria":2,"quantidade_na_mao":0}]'::jsonb) = v_puro,
    null);
  insert into _resultado values ('B11 fato que não muda nada (falta sem quantidade na mão) devolve idêntico',
    public.aplicar_os_material(v_puro, '[{"service_order_part_id":"x1","origem":"peca","situacao":"falta","fonte":"dono","quantidade_necessaria":1,"quantidade_na_mao":0}]'::jsonb) = v_puro,
    null);

  -- ── C: count_purchase_shortages deixa de acusar a OS com tudo comprado ─────────────────────────────────
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_n, v_p1, 1, 1900, 3000, 1900, 3000) returning id into n1;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_n, v_p7, 2, 2000, 3200, 4000, 6400) returning id into n2;
  insert into _resultado values ('C1 antes: a OS N acusa 2 itens',
    (public.count_purchase_shortages(array[v_n]) ->> v_n::text)::int = 2, public.count_purchase_shortages(array[v_n])::text);
  insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria, situacao, fonte)
  values (v_n, n1, 'peca', 'TESTE AG2 — Cerbo', 1, 'comprado', 'dono');
  insert into _resultado values ('C2 meio comprado: a OS N ainda acusa 1',
    (public.count_purchase_shortages(array[v_n]) ->> v_n::text)::int = 1, public.count_purchase_shortages(array[v_n])::text);
  insert into public.os_material (service_order_id, service_order_part_id, origem, descricao, quantidade_necessaria, situacao, fonte)
  values (v_n, n2, 'peca', 'TESTE AG2 — Bateria', 2, 'a_caminho', 'dono');
  insert into _resultado values ('C3 tudo comprado: count_purchase_shortages não acusa a OS N (a R16 fecha a tarefa)',
    not (public.count_purchase_shortages(array[v_n]) ? v_n::text)
    and not (public.get_os_purchase_needs(v_n) ->> 'needsPurchase')::boolean,
    public.count_purchase_shortages(array[v_n])::text);

  -- ── D: sincronização (OS S) ────────────────────────────────────────────────────────────────────────────
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, created_at)
  values (v_s, v_p5, 2, 10, 20, 20, 40, now() - interval '40 seconds') returning id into s1;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, created_at)
  values (v_s, v_p6, 1, 900, 1500, 900, 1500, now() - interval '39 seconds') returning id into s2;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale, created_at)
  values (v_s, v_p7, 1, 2000, 3200, 2000, 3200, now() - interval '38 seconds') returning id into s4;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot,
                                             quantity, unit_price_snapshot, created_at)
  values (v_s, null, 'Conector de cabo de dados AG2 (S)', 'unit', 1, 120, now() - interval '37 seconds')
  returning id into s5;
  -- OC-1: de catálogo (o Orion), enviada, com previsão. OC-2 e OC-3: texto livre da própria OS, rascunho.
  insert into public.purchase_orders (po_number, status, supplier_id, service_order_id, expected_date)
  values ('OC-TESTE-AG2-1', 'sent', v_forn, v_s, '2026-11-03') returning id into v_oc1;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc1, v_p6, 'TESTE AG2 — Orion', 1, 900);
  insert into public.purchase_orders (po_number, status, supplier_id, service_order_id)
  values ('OC-TESTE-AG2-2', 'draft', v_forn, v_s) returning id into v_oc2;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc2, null, 'Compressor TESTE AG2', 1, 0) returning id into s3;
  insert into public.purchase_orders (po_number, status, service_order_id)
  values ('OC-TESTE-AG2-3', 'draft', v_s) returning id into v_oc3;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc3, null, 'Suporte TESTE AG2', 1, 5) returning id into s3b;

  r := public.os_material_sincronizar(v_s, c_hoje);
  insert into _resultado values ('D1 cria uma linha por item (4 da OS + 2 de OC de texto livre)',
    (r ->> 'criadas')::int = 6 and (r ->> 'atualizadas')::int = 0 and (r ->> 'linhas')::int = 6, r::text);
  v_lin := pg_temp.linha(s1);
  insert into _resultado values ('D2 estoque cobrindo → na_mao, fonte estoque, quantidade completa, chegou hoje',
    v_lin.situacao = 'na_mao' and v_lin.fonte = 'estoque' and v_lin.quantidade_na_mao = 2 and v_lin.chegou_em = c_hoje,
    to_jsonb(v_lin)::text);
  v_lin := pg_temp.linha(s2);
  insert into _resultado values ('D3 OC de catálogo → a_caminho, fonte oc, previsão e fornecedor da OC',
    v_lin.situacao = 'a_caminho' and v_lin.fonte = 'oc' and v_lin.previsao_ate = '2026-11-03'
    and v_lin.previsao_fonte = 'oc' and v_lin.previsao_original = '2026-11-03' and v_lin.fornecedor_id = v_forn,
    to_jsonb(v_lin)::text);
  v_lin := pg_temp.linha(s3);
  insert into _resultado values ('D4 OC de texto livre da OS → linha oc a_caminho, sem previsão, fornecedor da OC',
    v_lin.origem = 'oc' and v_lin.situacao = 'a_caminho' and v_lin.fonte = 'oc' and v_lin.previsao_ate is null
    and v_lin.previsao_fonte is null and v_lin.fornecedor_id = v_forn and v_lin.descricao = 'Compressor TESTE AG2',
    to_jsonb(v_lin)::text);
  insert into _resultado values ('D5 sem estoque nem OC → falta, sem fonte (peça e texto livre); histórico com 1 entrada do sistema',
    (pg_temp.linha(s4)).situacao = 'falta' and (pg_temp.linha(s4)).fonte is null
    and (pg_temp.linha(s5)).situacao = 'falta' and (pg_temp.linha(s5)).origem = 'texto_livre'
    and (select bool_and(jsonb_array_length(m.historico) = 1 and m.historico -> 0 ->> 'por' = 'sistema'
                         and m.historico -> 0 ->> 'em' = c_hoje::text)
           from public.os_material m where m.service_order_id = v_s),
    null);
  insert into _resultado values ('D6 a linha copiada pelo sistema não muda a conta: get_os_purchase_needs = bruto',
    public.get_os_purchase_needs(v_s) = public.os_necessidade_bruta(v_s), null);

  update public.os_material set atualizado_em = '2026-01-01 00:00-03' where service_order_id = v_s;
  r := public.os_material_sincronizar(v_s, c_hoje);
  insert into _resultado values ('D7 reaplicar não duplica nem toca atualizado_em',
    (r ->> 'criadas')::int = 0 and (r ->> 'atualizadas')::int = 0 and (r ->> 'linhas')::int = 6
    and (select bool_and(m.atualizado_em = '2026-01-01 00:00-03') from public.os_material m where m.service_order_id = v_s),
    r::text);

  -- O estoque deixa de cobrir: outra OS (aprovada) reserva os 5 terminais.
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG2-R', 'approved', 'approved') returning id into v_r;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_r, v_p5, 5, 10, 20, 50, 100);
  r := public.os_material_sincronizar(v_s, c_hoje);
  v_lin := pg_temp.linha(s1);
  insert into _resultado values ('D8 estoque que deixou de cobrir: a linha do sistema volta a falta (e só ela muda)',
    (r ->> 'atualizadas')::int = 1 and v_lin.situacao = 'falta' and v_lin.fonte is null and v_lin.quantidade_na_mao = 0
    and v_lin.chegou_em is null and v_lin.historico -> -1 ->> 'nota' = 'o estoque deixou de cobrir'
    and v_lin.historico -> -1 ->> 'de' = 'na_mao' and v_lin.atualizado_em > '2026-01-01 00:00-03'
    and (select count(*) from public.os_material m where m.service_order_id = v_s
          and m.atualizado_em = '2026-01-01 00:00-03') = 5,
    to_jsonb(v_lin)::text);

  -- O fato do dono fica.
  update public.os_material set situacao = 'comprado', fonte = 'dono', comprado_em = '2026-10-21'
   where service_order_part_id = s4;
  r := public.os_material_sincronizar(v_s, c_hoje);
  insert into _resultado values ('D9 o fato do dono (comprado) fica e a conta o lê como já pedido',
    (pg_temp.linha(s4)).situacao = 'comprado' and (pg_temp.linha(s4)).fonte = 'dono'
    and pg_temp.item(public.get_os_purchase_needs(v_s), s4) ->> 'status' = 'on_order'
    and pg_temp.item(public.get_os_purchase_needs(v_s), s4) ->> 'informado' = 'comprado',
    r::text);

  -- A quantidade que sobe derruba o "na mão" do dono — e a conta já acusa antes da sincronização.
  update public.os_material set situacao = 'na_mao', fonte = 'dono', quantidade_na_mao = 1, chegou_em = '2026-10-14'
   where service_order_service_id = s5 and origem = 'texto_livre';
  update public.service_order_services set quantity = 2 where id = s5;
  x := pg_temp.item(public.get_os_purchase_needs(v_s), s5);
  insert into _resultado values ('D10 antes de sincronizar: na mão 1 de 2 já deixa 1 faltando',
    (x ->> 'available')::numeric = 1 and (x ->> 'shortage')::numeric = 1 and x ->> 'status' = 'uncatalogued'
    and x ->> 'informado' = 'na_mao', x::text);
  r := public.os_material_sincronizar(v_s, c_hoje);
  v_lin := pg_temp.linha(s5);
  x := pg_temp.item(public.get_os_purchase_needs(v_s), s5);
  insert into _resultado values ('D11 depois: falta com 1 na mão, sem chegada, fonte dono, "a quantidade subiu de 1 para 2"',
    v_lin.situacao = 'falta' and v_lin.quantidade_necessaria = 2 and v_lin.quantidade_na_mao = 1
    and v_lin.chegou_em is null and v_lin.fonte = 'dono'
    and v_lin.historico -> -1 ->> 'nota' = 'a quantidade subiu de 1 para 2'
    and x ->> 'informado' = 'parcial' and (x ->> 'shortage')::numeric = 1,
    to_jsonb(v_lin)::text);

  -- OC recebida → na mão; OC cancelada → falta (a de texto livre e a de catálogo).
  update public.purchase_order_items set received_qty = 1 where id = s3;
  update public.purchase_orders set status = 'cancelled' where id in (v_oc1, v_oc3);
  r := public.os_material_sincronizar(v_s, c_hoje);
  v_lin := pg_temp.linha(s3);
  insert into _resultado values ('D12 item da OC recebido → na_mao, fonte oc, chegou hoje',
    v_lin.situacao = 'na_mao' and v_lin.fonte = 'oc' and v_lin.quantidade_na_mao = 1 and v_lin.chegou_em = c_hoje
    and v_lin.historico -> -1 ->> 'nota' = 'recebido na OC-TESTE-AG2-2',
    to_jsonb(v_lin)::text);
  insert into _resultado values ('D13 OC cancelada → a linha do sistema volta a falta (texto livre e catálogo); a previsão original fica',
    (pg_temp.linha(s3b)).situacao = 'falta' and (pg_temp.linha(s3b)).fonte is null
    and (pg_temp.linha(s3b)).historico -> -1 ->> 'nota' = 'a OC-TESTE-AG2-3 foi cancelada'
    and (pg_temp.linha(s2)).situacao = 'falta' and (pg_temp.linha(s2)).previsao_ate is null
    and (pg_temp.linha(s2)).previsao_original = '2026-11-03'
    and (pg_temp.linha(s2)).historico -> -1 ->> 'nota' = 'a OC deixou de cobrir',
    r::text);

  -- "Vou comprar na Premel" que virou OC: a OC é o fato mais novo.
  update public.os_material set fonte = 'dono', compra_prevista_em = '2026-10-27', fornecedor_nome = 'Premel'
   where service_order_part_id = s2;
  insert into public.purchase_orders (po_number, status, supplier_id, service_order_id, expected_date)
  values ('OC-TESTE-AG2-4', 'sent', v_forn, v_s, '2026-11-05') returning id into v_oc4;
  insert into public.purchase_order_items (purchase_order_id, product_id, description, quantity, unit_cost)
  values (v_oc4, v_p6, 'TESTE AG2 — Orion', 1, 900);
  r := public.os_material_sincronizar(v_s, c_hoje);
  v_lin := pg_temp.linha(s2);
  insert into _resultado values ('D14 falta do dono que ganhou OC → a_caminho pela OC (compra combinada sai)',
    v_lin.situacao = 'a_caminho' and v_lin.fonte = 'oc' and v_lin.compra_prevista_em is null
    and v_lin.previsao_ate = '2026-11-05' and v_lin.fornecedor_id = v_forn
    and v_lin.historico -> -1 ->> 'nota' = 'pedido na OC-TESTE-AG2-4',
    to_jsonb(v_lin)::text);

  -- Histórico com os 20 mais novos; comprado do dono + quantidade que sobe = falta.
  update public.os_material
     set historico = (select jsonb_agg(jsonb_build_object('n', g) order by g) from generate_series(1, 20) g)
   where service_order_part_id = s4;
  update public.service_order_parts set quantity = 2, line_total_cost = 4000, line_total_sale = 6400 where id = s4;
  r := public.os_material_sincronizar(v_s, c_hoje);
  v_lin := pg_temp.linha(s4);
  insert into _resultado values ('D15 histórico fica nos 20 mais novos; comprado do dono derrubado pela quantidade',
    jsonb_array_length(v_lin.historico) = 20 and (v_lin.historico -> 0 ->> 'n')::int = 2
    and v_lin.historico -> -1 ->> 'nota' = 'a quantidade subiu de 1 para 2'
    and v_lin.historico -> -1 ->> 'de' = 'comprado' and v_lin.situacao = 'falta',
    jsonb_array_length(v_lin.historico)::text);

  -- Apagar o item da OC apaga a linha (FK CASCADE; com SET NULL o CHECK origem_coerente recusaria o delete).
  begin
    delete from public.purchase_order_items where id = s3b;
    insert into _resultado values ('D16 apagar o item da OC apaga a linha de material, sem erro',
      not exists (select 1 from public.os_material where purchase_order_item_id = s3b), null);
  exception when others then
    insert into _resultado values ('D16 apagar o item da OC apaga a linha de material, sem erro', false, sqlerrm);
  end;

  -- ── E: carteira, com o erro de uma OS isolado ──────────────────────────────────────────────────────────
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG2-E', 'open', 'approved') returning id into v_e;
  insert into public.service_orders (client_id, vessel_id, service_order_number, status, quote_status)
  values (v_cliente, v_barco, 'OS-TESTE-AG2-F', 'open', 'approved') returning id into v_f;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_e, v_p7, 1, 2000, 3200, 2000, 3200);
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot,
                                          line_total_cost, line_total_sale)
  values (v_f, v_p7, 1, 2000, 3200, 2000, 3200) returning id into f1;
  perform set_config('agenda_teste.os_falha', v_e::text, true);
  create function public._teste_ag2_falha() returns trigger language plpgsql as $f$
  begin
    if new.service_order_id::text = current_setting('agenda_teste.os_falha', true) then
      raise exception 'TESTE AG2: falha de propósito';
    end if;
    return new;
  end $f$;
  create trigger _teste_ag2_falha before insert or update on public.os_material
    for each row execute function public._teste_ag2_falha();
  r := public.os_material_sincronizar_carteira(c_hoje);
  drop trigger _teste_ag2_falha on public.os_material;
  drop function public._teste_ag2_falha();
  insert into _resultado values ('E1 o erro de uma OS sai em erros, com o número e a mensagem',
    jsonb_array_length(r -> 'erros') = 1 and r -> 'erros' -> 0 ->> 'os' = 'OS-TESTE-AG2-E'
    and r -> 'erros' -> 0 ->> 'msg' like '%TESTE AG2: falha de propósito%',
    (r -> 'erros')::text);
  insert into _resultado values ('E2 as outras OS seguem: a F ganhou a linha, a E ficou sem nenhuma',
    exists (select 1 from public.os_material where service_order_part_id = f1)
    and not exists (select 1 from public.os_material where service_order_id = v_e)
    and (r ->> 'criadas')::int >= 1,
    r::text);
  insert into _resultado values ('E3 percorre a carteira inteira (OS ativas + orçamento aprovado ou esperando sinal)',
    (r ->> 'oss')::int = (select count(*) from public.service_orders so
                           where so.merged_into_id is null
                             and (so.status in ('open','approved','scheduled','in_progress','awaiting_parts','awaiting_client')
                                  or (so.status = 'draft' and so.quote_status in ('approved','awaiting_deposit')))),
    r ->> 'oss');
  r := public.os_material_sincronizar_carteira(c_hoje);
  insert into _resultado values ('E4 a carteira reaplicada só cria a linha da OS E (a que falhou) e não muda mais nada',
    (r ->> 'criadas')::int = 1 and (r ->> 'atualizadas')::int = 0 and jsonb_array_length(r -> 'erros') = 0,
    r::text);
  select bool_and(public.get_os_purchase_needs(so.id) = public.os_necessidade_bruta(so.id)) into v_ok
    from public.service_orders so
   where not exists (select 1 from public.os_material m
                      where m.service_order_id = so.id and m.fonte in ('dono','fornecedor','nfe','pix'));
  insert into _resultado values ('E5 depois da carteira sincronizada, a conta só muda onde há fato informado',
    coalesce(v_ok, true), null);

  -- ── F8: o técnico (não lê os_material) recebe a conta bruta, sem erro ──────────────────────────────────
  begin
    perform set_config('request.jwt.claim.sub', 'aa000000-0000-4000-8000-0000000000ff', true);
    perform set_config('request.jwt.claims', json_build_object('sub', 'aa000000-0000-4000-8000-0000000000ff',
                                                               'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_n_antes from public.os_material;
    r := public.get_os_purchase_needs(v_m);
    b := public.os_necessidade_bruta(v_m);
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('F8 quem não lê os_material (técnico) recebe a conta bruta, sem erro',
      v_n_antes = 0 and r = b and not exists (select 1 from jsonb_array_elements(r -> 'items') i where i ? 'informado'),
      format('linhas visíveis %s', v_n_antes));
  exception when others then
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('F8 quem não lê os_material (técnico) recebe a conta bruta, sem erro', false, sqlerrm);
  end;
end
$teste$;

-- ── F: portas ──────────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'F1 anon não executa nenhuma função nova',
       not bool_or(has_function_privilege('anon', f, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f, 'execute'))
  from unnest(array['public.os_necessidade_bruta(uuid)', 'public.aplicar_os_material(jsonb, jsonb)',
                    'public.get_os_purchase_needs(uuid)', 'public.os_material_sincronizar(uuid, date)',
                    'public.os_material_sincronizar_carteira(date)', 'public._os_material_qtd(numeric)',
                    'public._os_material_historico(jsonb, jsonb)']) f;

insert into _resultado
select 'F2 authenticated lê (bruta, aplicar, get) e não sincroniza',
       bool_and(has_function_privilege('authenticated', f, 'execute') = (f in ('public.os_necessidade_bruta(uuid)',
                 'public.aplicar_os_material(jsonb, jsonb)', 'public.get_os_purchase_needs(uuid)'))),
       string_agg(f || '=' || has_function_privilege('authenticated', f, 'execute'), ', ')
  from unnest(array['public.os_necessidade_bruta(uuid)', 'public.aplicar_os_material(jsonb, jsonb)',
                    'public.get_os_purchase_needs(uuid)', 'public.os_material_sincronizar(uuid, date)',
                    'public.os_material_sincronizar_carteira(date)', 'public._os_material_qtd(numeric)',
                    'public._os_material_historico(jsonb, jsonb)']) f;

insert into _resultado
select 'F3 service_role executa todas',
       bool_and(has_function_privilege('service_role', f, 'execute')), null
  from unnest(array['public.os_necessidade_bruta(uuid)', 'public.aplicar_os_material(jsonb, jsonb)',
                    'public.get_os_purchase_needs(uuid)', 'public.os_material_sincronizar(uuid, date)',
                    'public.os_material_sincronizar_carteira(date)', 'public._os_material_qtd(numeric)',
                    'public._os_material_historico(jsonb, jsonb)']) f;

insert into _resultado
select 'F4 só a sincronização é security definer; aplicar IMMUTABLE, leituras STABLE, sincronização VOLATILE; search_path fixo',
       bool_and(p.prosecdef = (p.proname in ('os_material_sincronizar', 'os_material_sincronizar_carteira')))
       and bool_and(p.provolatile = case p.proname
             when 'aplicar_os_material' then 'i' when '_os_material_qtd' then 'i' when '_os_material_historico' then 'i'
             when 'os_necessidade_bruta' then 's' when 'get_os_purchase_needs' then 's' else 'v' end)
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and count(*) = 7,
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('os_necessidade_bruta', 'aplicar_os_material', 'get_os_purchase_needs', 'os_material_sincronizar',
                     'os_material_sincronizar_carteira', '_os_material_qtd', '_os_material_historico');

insert into _resultado
select 'F5 count_purchase_shortages segue a mesma (assinatura e portas)',
       to_regprocedure('public.count_purchase_shortages(uuid[])') is not null
       and not has_function_privilege('anon', 'public.count_purchase_shortages(uuid[])', 'execute')
       and has_function_privilege('authenticated', 'public.count_purchase_shortages(uuid[])', 'execute'),
       null;

insert into _resultado
select 'F6 a FK do item de OC é ON DELETE CASCADE',
       c.confdeltype = 'c', c.confdeltype::text
  from pg_constraint c
 where c.conrelid = 'public.os_material'::regclass and c.contype = 'f'
   and c.conkey = array[(select a.attnum from pg_attribute a
                          where a.attrelid = 'public.os_material'::regclass and a.attname = 'purchase_order_item_id')];

select teste, ok, detalhe from _resultado order by teste;

rollback;
