-- Agenda de Produção, Fase 4 ("Material em sincronia com o fornecedor"), pacote P2: compras e OC — o vínculo da linha da OC
-- com a linha da OS, o recebimento de item de texto livre, o material citado pelo dono na compra e a R7 que não cobra o que
-- a agenda já acompanha.
-- Spec: scratchpad agenda-pesquisa/spec-fase4.md (§5.2, §5.7, d9). Decisões do dono 23/10. Depende de 20261027100000 (as
-- colunas de vínculo em purchase_order_items, as de os_material e a view v_oc_itens_a_caminho com o vínculo no fim) e de
-- 20261027100100 (os_prontidao da Fase 4).
--
-- ═══ FUNÇÕES — OK NOMEADO ═══ (1 função nova; 6 recriadas; nenhuma tabela, nenhum dado)
-- NÃO APLICADA. Este arquivo foi MONTADO por scratchpad/agenda-pesquisa/f4p2/montar-migration.mjs: as partes escritas à mão
-- e os corpos copiados da migration MAIS NOVA de cada função recriada, com cada troca "-- FASE 4:" conferida (uma vez só).
--
-- POR QUE: a OC, quando o dono usa, passa a dizer DE QUAL LINHA DA OS ela compra (a cotação já sabia: quote_request_items
-- tem a peça e a linha de serviço; a OC perdia). Com o vínculo, o material de texto livre pedido numa OC deixa de aparecer
-- duas vezes (como falta "sem cadastro" e como item a caminho da OC) e passa a ser UM item: a caminho enquanto a OC está
-- aberta, na mão quando ela é recebida. O material que o dono citou e não está no orçamento (peça embutida, material novo)
-- entra na lista do que comprar e na R16, sem preço.
--
-- O QUE MUDA:
--   1. os_necessidade_bruta (corpo de 20261024160300): a linha de OC DESTA OS ligada a um item de texto livre da conta
--      (purchase_order_items.service_order_service_id), em OC fora de cancelada, refaz o item: disponível = o recebido (OC
--      recebida conta inteira), já pedido = o pendente das OCs abertas, falta = o resto; status pela régua (ok / on_order /
--      uncatalogued) e o número da OC (a aberta mais antiga; sem aberta, a mais antiga). A linha ligada sai do "a caminho"
--      (não se repete); shortages, shortageCount, estimatedCost e needsPurchase são refeitos (rank, falta desc, posição).
--      Sem OC ligada, a conta de antes, idêntica. OC ligada a peça de catálogo continua abatendo pelo produto (nada muda).
--   2. aplicar_os_material (corpo de 20261024160300): a linha que o DONO citou (origem 'dono') em falta, comprada ou a
--      caminho entra no fim de items — origin 'dono', productId nulo, a descrição dele, unitCost 0, semPreco true; o
--      comprado/a caminho conta como já pedido (necessário − na mão); falta com a régua do texto livre (uncatalogued).
--      Entra em shortages e em shortageCount (a R16 herda por count_purchase_shortages), não soma no custo estimado; a
--      chave nova semPreco (no topo) conta os itens a comprar sem preço. Dispensado e na mão não entram. Sem linha do dono,
--      a saída de antes, idêntica.
--   3. get_os_purchase_needs (corpo de 20261024160300): passa também o id e a descrição de cada linha de os_material (o
--      item do dono precisa dos dois). Mesma assinatura e ACL.
--   4. os_material_sincronizar (corpo de 20261024160300): o texto livre a caminho pela OC ligada acha essa OC (previsão,
--      fornecedor); recebido, fica na mão com fonte oc e o dia do recebimento; a linha a caminho (ou na mão pela OC ligada)
--      ganha comprado_em = o dia da OC em Brasília e comprado_fonte 'oc' (se não tinha), e a que volta a faltar perde o
--      "comprado em" que o sistema gravou; a chegada pela nota (P3): a linha com remessa_id cuja nota chegou fica na mão
--      (fonte nfe, o dia da chegada, a quantidade toda) — só com modo_material ligado (em sombra a linha fica igual).
--   5. receive_po (corpo de 20261007160000): item de texto livre (product_id nulo) recebe — received_qty sobe — sem tocar
--      products nem inventory_movements (product_id é NOT NULL lá: não há estoque de texto livre). Antes, um item assim
--      derrubava o recebimento inteiro.
--   6. os_prontidao (corpo de 20261027100100): a linha de OC recebida ligada a um item de texto livre da conta não entra de
--      novo como "item de OC que já chegou" (grupo 2) — ela já está no item (sem isto, o material apareceria duas vezes).
--   7. agenda_ocs_com_material_vivo (nova, só service_role): para a R7, as OCs cujo material a agenda já acompanha —
--      alguma linha com a pergunta "chegou?" aberta em ligado ("a agenda já pergunta se chegou"), ou todas na mão ("a
--      agenda registrou que chegou"). As linhas de uma OC: a do item de texto livre (origem oc) e a da linha da OS que o
--      item compra (o vínculo).
--
-- DINHEIRO — NÃO MUDA (NOVO-agenda-32, decisão do dono, spec §13 item 8): a OC já paga por Pix ganha conta a pagar ao ser
-- recebida. receive_po cria a conta a pagar ao completar EXATAMENTE como hoje: a mesma soma (recebido × custo de todos os
-- itens, os de texto livre inclusive) e o mesmo vencimento. A Fase 4 não corrige; só registra.
--
-- CORREÇÕES SOBRE A SPEC (provadas em supabase/tests/agenda_fase4_compras.sql e purchase_needs_reserva_e_a_caminho.sql):
--   · OC marcada "recebida" sem received_qty (a tela muda a situação à mão, useUpdatePurchaseOrder) conta como recebida
--     inteira no item ligado, como a Fase 0 (a OC recebida sai do "a caminho") e a sincronização da Fase 1 (OC recebida =
--     na mão) já tratavam. Pelo received_qty só, o material voltaria a pedir compra.
--   · A linha ligada só sai do "a caminho" quando o item de texto livre dela ESTÁ na conta. A ligada a uma linha que o
--     classificador lê como serviço (a "Conversão…" da OS-00104) continua a caminho, como hoje: sem isso, a OC sumiria da
--     conta e a OS pareceria pronta com o material no fornecedor (a lição da revisão de 23/10).
--   · get_os_purchase_needs também é recriada (a spec não listava): sem o id e a descrição da linha, aplicar_os_material
--     (pura) não teria como montar o item do dono.
--   · os_prontidao também é recriada (a spec não listava): a OC recebida ligada contaria duas vezes (no item e como item da
--     OC que já chegou).
--   · A chegada pela nota só vale com modo_material ligado: o P3 (§5.3) diz "em sombra a linha não muda". Quem registra a
--     ação com desfaz é o caminho da nota (P3); aqui é a rede idempotente.
--
-- O QUE NÃO MUDA: compute_purchase_needs (a fórmula pura), count_purchase_shortages (herda), v_oc_itens_a_caminho (P1), a
-- conta a pagar do recebimento, as OCs sem vínculo (a OC-00004 da OS-00104 continua igual) e as telas e ferramentas que não
-- criam OC. O espelho TS (src/lib/purchase-needs.ts + src/hooks/use-purchase-needs.ts) muda junto, com os mesmos casos nos
-- dois lados (src/lib/purchase-needs.test.ts × supabase/tests/purchase_needs_reserva_e_a_caminho.sql, casos L e O).
--
-- ORDEM DE LIGAR: depois de 20261027100000 e 100100; ANTES de o front ir para a main (a tela grava o vínculo nas colunas
-- novas de purchase_order_items) e do deploy de task-automations, ai-agent e erp-mcp (a R7 chama
-- agenda_ocs_com_material_vivo — sem ela, a R7 segue como hoje; as ferramentas gravam o vínculo). Aplicada sozinha: nenhuma
-- OC tem vínculo (as colunas nasceram vazias), então a conta só muda onde o dono citou material (origem 'dono').
--
-- PROVA: supabase/tests/agenda_fase4_compras.sql (C0–C9) e supabase/tests/purchase_needs_reserva_e_a_caminho.sql (L, O).
-- Na bancada:
--   node scripts/bancada-agenda/rodar.mjs
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 20261027100000 e 100100):
--   npx supabase db query --linked -f supabase/migrations/20261027100200_agenda_fase4_compras.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261027100200', 'agenda_fase4_compras');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 1. A conta bruta: a OC ligada ao item de texto livre ───────────────────────────────────────────────────
-- Corpo de 20261024160300 copiado; as mudanças estão marcadas "-- FASE 4:".

create or replace function public.os_necessidade_bruta(p_so_id uuid)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  -- A OS reserva estoque? A MESMA lista de recompute_product_reservations
  -- (20260724220000_stock_v2_status_sets_fix.sql). Fora dela, a reserva da OS é zero
  -- e não há o que devolver ao disponível.
  os as (
    select so.id,
           so.status in ('approved','scheduled','in_progress','awaiting_parts','awaiting_client','reopened') as reserva
      from service_orders so
     where so.id = p_so_id
  ),
  -- O que ESTA OS reservou, por produto: a soma das peças dela (é o que o recálculo soma).
  propria as (
    select sop.product_id, sum(sop.quantity) as q
      from service_order_parts sop
      join os on os.id = sop.service_order_id and os.reserva
     group by sop.product_id
  ),
  necessidade as (
    select public.compute_purchase_needs(
      p_so_id,
      coalesce((select jsonb_agg(jsonb_build_object(
          'id', sop.id, 'product_id', sop.product_id, 'quantity', sop.quantity,
          'unit_cost_snapshot', sop.unit_cost_snapshot,
          'product_name', p.name, 'product_unit', p.unit)
          order by sop.created_at, sop.id)
        from service_order_parts sop
        left join products p on p.id = sop.product_id
        where sop.service_order_id = p_so_id), '[]'::jsonb),
      coalesce((select jsonb_agg(jsonb_build_object(
          'id', s.id, 'service_id', s.service_id, 'name_snapshot', s.name_snapshot,
          'billing_unit_snapshot', s.billing_unit_snapshot, 'quantity', s.quantity,
          'unit_price_snapshot', s.unit_price_snapshot)
          order by s.created_at, s.id)
        from service_order_services s
        where s.service_order_id = p_so_id), '[]'::jsonb),
      -- O reservado que entra na conta é o de OUTRAS OS: a reserva desta sai. O piso em
      -- zero cobre o reservado defasado (menor que a reserva própria): o disponível nunca
      -- passa do físico.
      coalesce((select jsonb_agg(jsonb_build_object(
          'id', pa.id, 'stock_quantity', pa.stock_quantity,
          'reserved_quantity', greatest(coalesce(pa.reserved_quantity, 0) - coalesce(pr.q, 0), 0)))
        from product_availability pa
        left join propria pr on pr.product_id = pa.id
        where pa.id in (select sop.product_id from service_order_parts sop
                        where sop.service_order_id = p_so_id)), '[]'::jsonb),
      -- "Já pedido" só de OC viva (conta_como_ja_pedido: < 60 dias e OS não encerrada).
      coalesce((select jsonb_agg(jsonb_build_object(
          'product_id', v.product_id, 'quantity', v.quantity, 'received_qty', v.received_qty))
        from v_oc_itens_a_caminho v
        where v.conta_como_ja_pedido
          and v.product_id in (select sop.product_id from service_order_parts sop
                               where sop.service_order_id = p_so_id)), '[]'::jsonb)
    ) as r
  ),
  -- FASE 4: o item de texto livre com OC desta OS ligada a ele (purchase_order_items.service_order_service_id, P2).
  -- livres: os itens de texto livre da conta (só eles podem ter OC ligada).
  livres as (
    select (x.i ->> 'sourceId')::uuid as sid
      from necessidade n
     cross join lateral jsonb_array_elements(coalesce(n.r -> 'items', '[]'::jsonb)) as x(i)
     where x.i ->> 'origin' = 'free_text'
  ),
  -- ligadas: por item, o pendente das OCs abertas (draft/sent/partial), o recebido (a OC recebida conta inteira, mesmo sem
  -- received_qty: a Fase 0 a tira do "a caminho" e a Fase 1 a dá por chegada) e o número da OC (a aberta mais antiga;
  -- sem aberta, a mais antiga). OC cancelada não conta.
  ligadas as (
    select poi.service_order_service_id as sid,
           sum(case when po.status in ('draft', 'sent', 'partial')
                    then greatest(poi.quantity - coalesce(poi.received_qty, 0), 0) else 0 end) as pendente,
           sum(case when po.status = 'received' then greatest(poi.quantity, coalesce(poi.received_qty, 0))
                    else coalesce(poi.received_qty, 0) end) as recebido,
           coalesce((array_agg(po.po_number order by po.created_at, poi.id)
                       filter (where po.status in ('draft', 'sent', 'partial')
                                 and poi.quantity > coalesce(poi.received_qty, 0)))[1],
                    (array_agg(po.po_number order by po.created_at, poi.id))[1]) as numero
      from purchase_order_items poi
      join purchase_orders po on po.id = poi.purchase_order_id
     where po.service_order_id = p_so_id
       and po.status <> 'cancelled'
       and poi.service_order_service_id in (select l.sid from livres l)
     group by poi.service_order_service_id
  ),
  -- refeitos: o item ligado pela régua — disponível = o recebido, já pedido = o pendente, falta = o resto; status ok /
  -- on_order / uncatalogued e o número da OC. Os outros itens, como vieram.
  refeitos as (
    select x.ord, x.i, l.sid is not null as ligada, l.numero,
           coalesce((x.i ->> 'unitCost')::numeric, 0) as custo, q.r, q.a,
           least(q.r - q.a, coalesce(l.pendente, 0)) as o,
           greatest(q.r - q.a - least(q.r - q.a, coalesce(l.pendente, 0)), 0) as s
      from necessidade n
     cross join lateral jsonb_array_elements(coalesce(n.r -> 'items', '[]'::jsonb)) with ordinality as x(i, ord)
      left join ligadas l on x.i ->> 'origin' = 'free_text' and l.sid = (x.i ->> 'sourceId')::uuid
     cross join lateral (
       select coalesce((x.i ->> 'required')::numeric, 0) as r,
              least(coalesce((x.i ->> 'required')::numeric, 0), coalesce(l.recebido, 0)) as a) q
  ),
  refeitos_js as (
    select f.ord, f.custo, f.falta, f.js,
           case f.js ->> 'status' when 'missing' then 0 when 'partial' then 1 when 'uncatalogued' then 2
                                  when 'on_order' then 3 else 4 end as rank
      from (select r.ord, r.custo,
                   case when r.ligada then r.s else coalesce((r.i ->> 'shortage')::numeric, 0) end as falta,
                   case when not r.ligada then r.i
                        else r.i || jsonb_build_object(
                          'available', r.a, 'onOrder', r.o, 'shortage', r.s,
                          'status', case when r.s = 0 and r.r - r.a = 0 then 'ok' when r.s = 0 then 'on_order'
                                         else 'uncatalogued' end,
                          'purchaseOrderNumber', r.numero) end as js
              from refeitos r) f
  ),
  -- FASE 4: fim
  -- Linhas de texto livre de OC DESTA OS que ainda não chegaram. Entram em items como
  -- "a caminho" (shortage 0): não pedem compra, mas não deixam a OS parecer pronta.
  -- Sem corte de idade (conta_como_ja_pedido não entra aqui): o rascunho de 61 dias
  -- continua sendo o compressor que ainda não chegou.
  a_caminho as (
    select coalesce(jsonb_agg(jsonb_build_object(
        'sourceId', v.purchase_order_item_id, 'origin', 'purchase_order', 'productId', null,
        'description', v.description, 'unit', null, 'required', v.quantity,
        'available', 0, 'onOrder', v.pendente, 'shortage', 0, 'status', 'on_order',
        'unitCost', v.unit_cost, 'purchaseOrderNumber', v.po_number)
        order by v.po_criada_em, v.purchase_order_item_id), '[]'::jsonb) as itens
      from v_oc_itens_a_caminho v
     where v.service_order_id = p_so_id
       and v.product_id is null
       and v.pendente > 0
       -- FASE 4: a linha ligada a um item de texto livre da conta já está nele (ligadas): não se repete como item da OC.
       and (v.service_order_service_id is null
            or not exists (select 1 from livres l where l.sid = v.service_order_service_id))
       -- FASE 4: fim
  )
  -- FASE 4: sem OC ligada, a conta de antes, idêntica; com ela, o item refeito e a falta, a contagem, o custo e o "precisa
  -- comprar" recontados (shortages em rank, falta desc, posição).
  select case
    when not exists (select 1 from ligadas) then
      jsonb_set(n.r, '{items}', coalesce(n.r -> 'items', '[]'::jsonb) || a.itens)
    else n.r || jsonb_build_object(
      'items',         coalesce((select jsonb_agg(f.js order by f.ord) from refeitos_js f), '[]'::jsonb) || a.itens,
      'shortages',     coalesce((select jsonb_agg(f.js order by f.rank, f.falta desc, f.ord) from refeitos_js f
                                  where f.falta > 0), '[]'::jsonb),
      'shortageCount', (select count(*) from refeitos_js f where f.falta > 0),
      'estimatedCost', coalesce((select sum(f.falta * f.custo) from refeitos_js f where f.falta > 0), 0),
      'needsPurchase', exists (select 1 from refeitos_js f where f.falta > 0)) end
    from necessidade n, a_caminho a;
  -- FASE 4: fim
$function$;

comment on function public.os_necessidade_bruta(uuid) is
  'Agenda de Produção (Fase 1, P2; Fase 4, P2: a linha de OC desta OS ligada a um item de texto livre da conta — purchase_order_items.service_order_service_id, OC fora de cancelada — refaz o item: recebido = disponível, pendente = já pedido, status ok/on_order/uncatalogued e o número da OC; a ligada sai do "a caminho"; sem OC ligada, idêntica): a necessidade de compra BRUTA de uma OS, sem o que o dono informou em os_material. Na Fase 1, o corpo de get_os_purchase_needs de 20261024150100 sem mudança (reserva própria, já pedido de OC viva, itens a caminho por OC de texto livre da OS). get_os_purchase_needs = aplicar_os_material(os_necessidade_bruta, os_material).';


revoke all on function public.os_necessidade_bruta(uuid) from public, anon;
grant execute on function public.os_necessidade_bruta(uuid) to authenticated, service_role;

-- ── 2. O que o dono informou e o que ele citou ───────────────────────────────────────────────────────────────
-- Corpo de 20261024160300 copiado; as mudanças estão marcadas "-- FASE 4:".

create or replace function public.aplicar_os_material(p_needs jsonb, p_linhas jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  with
  -- Só o fato INFORMADO entra. A linha que a sincronização copiou (fonte nula, estoque ou oc) é espelho da
  -- conta bruta: aplicá-la não muda nada quando está em dia e esconde uma falta quando fica velha.
  linhas as (
    select x.l, x.ord
      from jsonb_array_elements(case when jsonb_typeof(p_linhas) = 'array' then p_linhas else '[]'::jsonb end)
           with ordinality as x(l, ord)
     where x.l ->> 'fonte' in ('dono', 'fornecedor', 'nfe', 'pix')
  ),
  -- FASE 4: o material que o dono citou (origem 'dono') e ainda falta, foi comprado ou está a caminho entra no fim da lista
  -- de compra, sem preço (unitCost 0, fora do custo estimado), com a régua do texto livre (spec §5.2, d9). Dispensado e na
  -- mão não entram. Qualquer fonte: a linha do dono só nasce do que ele disse.
  do_dono_base as (
    select x.ord, x.l,
           greatest(coalesce((x.l ->> 'quantidade_necessaria')::numeric, 0), 0) as r,
           least(greatest(coalesce((x.l ->> 'quantidade_na_mao')::numeric, 0), 0),
                 greatest(coalesce((x.l ->> 'quantidade_necessaria')::numeric, 0), 0)) as a
      from jsonb_array_elements(case when jsonb_typeof(p_linhas) = 'array' then p_linhas else '[]'::jsonb end)
           with ordinality as x(l, ord)
     where x.l ->> 'origem' = 'dono' and x.l ->> 'situacao' in ('falta', 'comprado', 'a_caminho')
       and coalesce((x.l ->> 'quantidade_necessaria')::numeric, 0) > 0
  ),
  do_dono as (
    select b.ord, f.s,
           jsonb_build_object(
             'sourceId', b.l -> 'id', 'origin', 'dono', 'productId', null,
             'description', coalesce(nullif(btrim(b.l ->> 'descricao'), ''), 'Material'), 'unit', null,
             'required', b.r, 'available', b.a, 'onOrder', f.o, 'shortage', f.s, 'status', f.st, 'unitCost', 0,
             'semPreco', true) as js,
           case f.st when 'uncatalogued' then 2 when 'on_order' then 3 else 4 end as rank
      from do_dono_base b
     cross join lateral (
       select p.o, p.s,
              case when p.s = 0 and b.r - b.a = 0 then 'ok' when p.s = 0 then 'on_order' else 'uncatalogued' end as st
         from (select q.o, greatest(b.r - b.a - q.o, 0) as s
                 from (select case when b.l ->> 'situacao' in ('comprado', 'a_caminho') then b.r - b.a else 0 end as o) q) p
     ) f
  ),
  -- FASE 4: fim
  itens as (
    select x.i, x.ord as idx
      from jsonb_array_elements(case when jsonb_typeof(p_needs -> 'items') = 'array' then p_needs -> 'items'
                                     else '[]'::jsonb end) with ordinality as x(i, ord)
  ),
  -- O vínculo decide: peça → linha da peça; texto livre → linha de serviço (só a de origem texto_livre: a do
  -- dono pode citar a mesma linha de serviço várias vezes e não entra na compra); item a caminho → item da OC.
  casados as (
    select it.i, it.idx, ln.l
      from itens it
      left join lateral (
        select y.l
          from linhas y
         where (it.i ->> 'origin' = 'part'           and y.l ->> 'origem' = 'peca'
                and y.l ->> 'service_order_part_id' = it.i ->> 'sourceId')
            or (it.i ->> 'origin' = 'free_text'      and y.l ->> 'origem' = 'texto_livre'
                and y.l ->> 'service_order_service_id' = it.i ->> 'sourceId')
            or (it.i ->> 'origin' = 'purchase_order' and y.l ->> 'origem' = 'oc'
                and y.l ->> 'purchase_order_item_id' = it.i ->> 'sourceId')
         order by y.ord
         limit 1
      ) ln on true
  ),
  base as (
    select c.i, c.idx, c.l,
           c.i ->> 'origin' as origem_item,
           c.l ->> 'situacao' as sit,
           coalesce((c.i ->> 'required')::numeric, 0)  as r,
           coalesce((c.i ->> 'available')::numeric, 0) as a0,
           coalesce((c.i ->> 'onOrder')::numeric, 0)   as o0,
           coalesce((c.i ->> 'shortage')::numeric, 0)  as s0,
           coalesce((c.i ->> 'unitCost')::numeric, 0)  as custo,
           greatest(coalesce((c.l ->> 'quantidade_necessaria')::numeric, 0), 0) as qn,
           greatest(coalesce((c.l ->> 'quantidade_na_mao')::numeric, 0), 0)     as qna
      from casados c
  ),
  -- A quantidade na mão soma ao disponível (na_mao tem a quantidade completa pelo CHECK; se a OS pedir mais
  -- do que o dito, sobra a diferença como falta).
  passo_disponivel as (
    select b.*, case when b.l is null then b.a0 else greatest(b.a0, least(b.r, b.qna)) end as a1
      from base b
  ),
  -- Comprado/a caminho conta como já pedido: o que o dono comprou (quantidade − na mão), até o que falta.
  passo_pedido as (
    select p.*, case
        when p.l is null then p.o0
        when p.sit in ('comprado', 'a_caminho')
          then greatest(least(p.o0, p.r - p.a1), least(p.r - p.a1, greatest(p.qn - p.qna, 0)))
        else least(p.o0, p.r - p.a1) end as o1
      from passo_disponivel p
  ),
  -- O item a caminho por OC de texto livre nunca pede compra (falta 0, como na conta bruta).
  passo_falta as (
    select p.*, case
        when p.l is null then p.s0
        when p.origem_item = 'purchase_order' then 0
        else greatest(p.r - p.a1 - p.o1, 0) end as s1
      from passo_pedido p
  ),
  -- A régua de compute_purchase_needs.
  passo_status as (
    select p.*, case
        when p.l is null then p.i ->> 'status'
        when p.origem_item = 'purchase_order' then case when p.r - p.a1 = 0 then 'ok' else 'on_order' end
        when p.s1 = 0 and p.r - p.a1 = 0 then 'ok'
        when p.s1 = 0 then 'on_order'
        when p.origem_item = 'free_text' then 'uncatalogued'
        when p.a1 > 0 then 'partial'
        else 'missing' end as st
      from passo_falta p
  ),
  marcados as (
    select p.*,
           (p.l is not null and p.sit = 'dispensado') as sai,
           (p.l is not null and p.sit is distinct from 'dispensado'
            and (p.a1 <> p.a0 or p.o1 <> p.o0 or p.s1 <> p.s0 or p.st is distinct from p.i ->> 'status')) as mudou
      from passo_status p
  ),
  final as (
    select m.idx, m.s1, m.custo,
           case when m.mudou
                then m.i || jsonb_build_object('available', m.a1, 'onOrder', m.o1, 'shortage', m.s1, 'status', m.st,
                                               'informado', case when m.sit = 'falta' then 'parcial' else m.sit end)
                else m.i end as js,
           case m.st when 'missing' then 0 when 'partial' then 1 when 'uncatalogued' then 2
                     when 'on_order' then 3 else 4 end as rank
      from marcados m
     where not m.sai
    -- FASE 4: + o material citado pelo dono, depois de todos os itens da conta.
    union all
    select (select count(*) from itens) + d.ord, d.s, 0::numeric, d.js, d.rank
      from do_dono d
    -- FASE 4: fim
  )
  select case
    when p_needs is null then null
    -- FASE 4: sem fato que mude algum item e sem material citado pelo dono: idêntico.
    when not exists (select 1 from marcados where sai or mudou) and not exists (select 1 from do_dono) then p_needs
    -- FASE 4: fim
    else p_needs || jsonb_build_object(
      'items',         coalesce((select jsonb_agg(f.js order by f.idx) from final f), '[]'::jsonb),
      'shortages',     coalesce((select jsonb_agg(f.js order by f.rank, f.s1 desc, f.idx) from final f where f.s1 > 0),
                                '[]'::jsonb),
      'shortageCount', (select count(*) from final f where f.s1 > 0),
      'estimatedCost', coalesce((select sum(f.s1 * f.custo) from final f where f.s1 > 0), 0),
      'needsPurchase', exists (select 1 from final f where f.s1 > 0))
      -- FASE 4: quantos itens a comprar não têm preço (o material citado pelo dono); só quando há linha do dono.
      || case when exists (select 1 from do_dono)
              then jsonb_build_object('semPreco', (select count(*) from do_dono d where d.s > 0))
              else '{}'::jsonb end
      -- FASE 4: fim
  end;
$function$;

comment on function public.aplicar_os_material(jsonb, jsonb) is
  'Agenda de Produção (Fase 1, P2; Fase 4, P2: a linha que o dono citou — origem dono — em falta, comprada ou a caminho entra no fim de items, origin dono, sem preço — unitCost 0, semPreco true —, comprado/a caminho = já pedido, falta = uncatalogued; entra em shortages e shortageCount, não no custo; semPreco no topo conta os itens a comprar sem preço; dispensado e na mão não entram): aplica a necessidade de compra (formato de get_os_purchase_needs) o que foi informado em os_material (fonte dono/fornecedor/nfe/pix; a linha copiada pela sincronização nao conta). Por vinculo: dispensado sai; quantidade na mao soma ao disponivel; na_mao completo = ok; comprado/a_caminho = ja pedido. Recalcula falta, status (regua de compute_purchase_needs), informado, shortages (rank, falta desc, posicao original), shortageCount, estimatedCost e needsPurchase. Sem fato que mude algum item, devolve p_needs identico. Pura. Espelho TS: aplicarSituacaoDoMaterial (src/lib/purchase-needs.ts).';


revoke all on function public.aplicar_os_material(jsonb, jsonb) from public, anon;
grant execute on function public.aplicar_os_material(jsonb, jsonb) to authenticated, service_role;

-- ── 3. get_os_purchase_needs: o id e a descrição de cada linha ──────────────────────────────────────────────
-- Corpo de 20261024160300 copiado; a mudança está marcada "-- FASE 4:".

create or replace function public.get_os_purchase_needs(p_so_id uuid)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  -- security invoker: quem não lê os_material (o técnico, pela RLS) recebe a conta bruta, sem erro.
  select public.aplicar_os_material(
    public.os_necessidade_bruta(p_so_id),
    coalesce((select jsonb_agg(jsonb_build_object(
        'service_order_part_id', m.service_order_part_id,
        'service_order_service_id', m.service_order_service_id,
        'purchase_order_item_id', m.purchase_order_item_id,
        'origem', m.origem, 'situacao', m.situacao, 'fonte', m.fonte,
        -- FASE 4: + o id e a descrição da linha: o material citado pelo dono entra na compra (aplicar_os_material, P2).
        'quantidade_necessaria', m.quantidade_necessaria, 'quantidade_na_mao', m.quantidade_na_mao,
        'id', m.id, 'descricao', m.descricao)
        -- FASE 4: fim
        order by m.id)
      from public.os_material m
     where m.service_order_id = p_so_id), '[]'::jsonb));
$function$;

comment on function public.get_os_purchase_needs(uuid) is
  'Necessidade LIQUIDA de compra de uma OS (falta = necessario - disponivel - ja pedido). Espelha src/lib/purchase-needs.ts + src/hooks/use-purchase-needs.ts; e a via do agente de IA e da R16 (count_purchase_shortages). Desde 24/10/2026 (Agenda, Fase 1, P2) = aplicar_os_material(os_necessidade_bruta(OS), os_material da OS): o que o dono informou (comprado/a caminho = ja pedido; na mao = disponivel; dispensado sai) entra na conta e o item ganha "informado". Sem os_material (ou para quem nao le os_material, como o tecnico), igual a os_necessidade_bruta. Fase 4 (P2): cada linha vai com o id e a descricao (o material citado pelo dono entra na compra, sem preco).';


revoke all on function public.get_os_purchase_needs(uuid) from public, anon;
grant execute on function public.get_os_purchase_needs(uuid) to authenticated, service_role;

-- ── 4. A sincronização: a OC ligada, o "comprado em" e a chegada pela nota ─────────────────────────────────
-- Corpo de 20261024160300 copiado; as mudanças estão marcadas "-- FASE 4:".

create or replace function public.os_material_sincronizar(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_bruto       jsonb;
  v_item        jsonb;
  v_origin      text;
  v_origem      text;
  v_src         uuid;
  v_req         numeric;
  v_status      text;
  v_desc        text;
  v_velha       public.os_material%rowtype;
  v_nova        public.os_material%rowtype;
  v_sistema     boolean;
  v_oc_prev     date;
  v_oc_forn     uuid;
  v_oc_numero   text;
  v_prod_forn   uuid;
  v_forn        uuid;
  v_ini_sit     text;
  v_nota        text;
  v_pendentes   uuid[] := '{}';
  v_criadas     int := 0;
  v_atualizadas int := 0;
  v_poi         record;
  -- FASE 4: o dia (Brasília) em que a OC que cobre o item foi criada (o "comprado em" da linha) e o "na mão" do texto
  -- livre pela OC ligada recebida (fonte oc, o dia do recebimento, a OC na nota) — o resto continua "o estoque cobre".
  v_oc_criada   date;
  v_ok_fonte    text;
  v_ok_chegou   date;
  v_ok_nota     text;
  v_rem         record;
  -- FASE 4: fim
begin
  if p_so_id is null then
    raise exception 'os_material_sincronizar: a OS veio vazia';
  end if;
  if not exists (select 1 from public.service_orders where id = p_so_id) then
    raise exception 'os_material_sincronizar: a OS % não existe', p_so_id using errcode = 'P0002';
  end if;
  -- Uma sincronização por OS de cada vez (o motor de 15 min e, no P5, as RPCs do rascunho).
  perform pg_advisory_xact_lock(hashtext('os_material:' || p_so_id::text));

  v_bruto := public.os_necessidade_bruta(p_so_id);

  for v_item in select e from jsonb_array_elements(coalesce(v_bruto -> 'items', '[]'::jsonb)) as t(e) loop
    v_origin := v_item ->> 'origin';
    v_origem := case v_origin when 'part' then 'peca' when 'free_text' then 'texto_livre'
                              when 'purchase_order' then 'oc' end;
    continue when v_origem is null;
    v_src := (v_item ->> 'sourceId')::uuid;
    if v_origin = 'purchase_order' then
      v_pendentes := v_pendentes || v_src;
    end if;
    v_req := (v_item ->> 'required')::numeric;
    continue when v_req is null or v_req <= 0;   -- linha com quantidade 0 não tem o que guardar
    v_status := v_item ->> 'status';
    v_desc := left(coalesce(nullif(btrim(v_item ->> 'description'), ''), 'Material'), 200);

    -- O que o sistema diz da linha hoje: a OC que a cobre (a da própria OS primeiro), o fornecedor e a
    -- situação inicial.
    v_oc_prev := null; v_oc_forn := null; v_oc_numero := null; v_prod_forn := null;
    -- FASE 4:
    v_oc_criada := null; v_ok_fonte := 'estoque'; v_ok_chegou := p_hoje; v_ok_nota := 'o estoque cobre';
    -- FASE 4: fim
    if v_status = 'on_order' then
      -- FASE 4: + o dia em que a OC foi criada (Brasília): o "comprado em" da linha.
      select v.expected_date, po.supplier_id, v.po_number, (v.po_criada_em at time zone 'America/Sao_Paulo')::date
        into v_oc_prev, v_oc_forn, v_oc_numero, v_oc_criada
      -- FASE 4: fim
        from public.v_oc_itens_a_caminho v
        join public.purchase_orders po on po.id = v.purchase_order_id
       where v.pendente > 0
         and case when v_origin = 'purchase_order' then v.purchase_order_item_id = v_src
                  -- FASE 4: o texto livre: a linha de OC desta OS ligada a ele (P2).
                  when v_origin = 'free_text' then v.service_order_service_id = v_src and v.service_order_id = p_so_id
                  -- FASE 4: fim
                  else v.product_id = (v_item ->> 'productId')::uuid and v.conta_como_ja_pedido end
       order by (v.service_order_id is distinct from p_so_id), v.po_criada_em, v.purchase_order_item_id
       limit 1;
    end if;
    if v_origin = 'part' then
      select p.supplier_id into v_prod_forn from public.products p where p.id = (v_item ->> 'productId')::uuid;
    elsif v_origin = 'purchase_order' and v_oc_forn is null then
      select po.supplier_id into v_oc_forn
        from public.purchase_order_items poi join public.purchase_orders po on po.id = poi.purchase_order_id
       where poi.id = v_src;
    end if;
    -- FASE 4: o texto livre só fica 'ok' na conta bruta pela OC ligada recebida: na mão com fonte oc, o dia do recebimento
    -- (nunca depois de hoje), a OC na nota e o dia da OC como "comprado em".
    if v_status = 'ok' and v_origin = 'free_text' then
      select least(coalesce(max(po.received_date), p_hoje), p_hoje),
             'recebido na ' || coalesce((array_agg(po.po_number order by po.received_date desc nulls last, po.created_at desc,
                                                                         poi.id))[1], 'OC'),
             min((po.created_at at time zone 'America/Sao_Paulo')::date),
             (array_agg(po.supplier_id order by po.created_at, poi.id))[1]
        into v_ok_chegou, v_ok_nota, v_oc_criada, v_oc_forn
        from public.purchase_order_items poi
        join public.purchase_orders po on po.id = poi.purchase_order_id
       where poi.service_order_service_id = v_src and po.service_order_id = p_so_id and po.status <> 'cancelled';
      v_ok_fonte := 'oc';
    end if;
    -- FASE 4: fim
    v_forn := coalesce(v_oc_forn, v_prod_forn);
    v_ini_sit := case v_status when 'ok' then 'na_mao' when 'on_order' then 'a_caminho' else 'falta' end;

    select m.* into v_velha
      from public.os_material m
     where m.origem = v_origem
       and case v_origem when 'peca' then m.service_order_part_id = v_src
                         when 'texto_livre' then m.service_order_service_id = v_src
                         else m.purchase_order_item_id = v_src end
     for update;

    if not found then
      insert into public.os_material (
        service_order_id, service_order_part_id, service_order_service_id, purchase_order_item_id, origem,
        descricao, quantidade_necessaria, quantidade_na_mao, situacao, fonte, fornecedor_id,
        -- FASE 4: + o "comprado em" da OC (o dia em Brasília) e a fonte dele (oc).
        previsao_ate, previsao_original, previsao_fonte, chegou_em, historico, comprado_em, comprado_fonte)
        -- FASE 4: fim
      values (
        p_so_id,
        case when v_origem = 'peca' then v_src end,
        case when v_origem = 'texto_livre' then v_src end,
        case when v_origem = 'oc' then v_src end,
        v_origem, v_desc, v_req,
        case when v_ini_sit = 'na_mao' then v_req else 0 end,
        v_ini_sit,
        -- FASE 4: na mão pela OC ligada recebida = fonte oc (senão estoque, como antes).
        case v_ini_sit when 'na_mao' then v_ok_fonte when 'a_caminho' then 'oc' end,
        -- FASE 4: fim
        v_forn,
        case when v_ini_sit = 'a_caminho' then v_oc_prev end,
        case when v_ini_sit = 'a_caminho' then v_oc_prev end,
        case when v_ini_sit = 'a_caminho' and v_oc_prev is not null then 'oc' end,
        -- FASE 4: o dia do recebimento da OC ligada (senão hoje, como antes).
        case when v_ini_sit = 'na_mao' then v_ok_chegou end,
        -- FASE 4: fim
        jsonb_build_array(jsonb_build_object('em', p_hoje, 'de', null, 'para', v_ini_sit, 'por', 'sistema',
          -- FASE 4: "recebido na OC-x" pela OC ligada (senão "o estoque cobre", como antes).
          'nota', case v_ini_sit when 'na_mao' then v_ok_nota
          -- FASE 4: fim
                                 when 'a_caminho' then 'pedido na ' || coalesce(v_oc_numero, 'OC')
          -- FASE 4: + o "comprado em" e a fonte dele: a linha que nasce a caminho, ou na mão pela OC ligada.
                                 else 'a comprar' end)),
        case when v_ini_sit <> 'falta' then v_oc_criada end,
        case when v_ini_sit <> 'falta' and v_oc_criada is not null then 'oc' end);
          -- FASE 4: fim
      v_criadas := v_criadas + 1;
      continue;
    end if;

    v_nova := v_velha;
    v_nota := null;
    v_nova.service_order_id := p_so_id;
    v_nova.descricao := v_desc;
    -- A linha que o próprio sistema escreveu é refeita pela conta bruta; o fato informado fica.
    v_sistema := v_velha.fonte is null or v_velha.fonte in ('estoque', 'oc');

    if v_req <> v_velha.quantidade_necessaria then
      v_nota := format('a quantidade %s de %s para %s',
                       case when v_req > v_velha.quantidade_necessaria then 'subiu' else 'caiu' end,
                       public._os_material_qtd(v_velha.quantidade_necessaria), public._os_material_qtd(v_req));
      v_nova.quantidade_necessaria := v_req;
      v_nova.quantidade_na_mao := least(v_nova.quantidade_na_mao, v_req);
    end if;

    if v_sistema then
      v_nova.situacao := v_ini_sit;
      -- FASE 4: na mão pela OC ligada recebida = fonte oc (senão estoque, como antes).
      v_nova.fonte := case v_ini_sit when 'na_mao' then v_ok_fonte when 'a_caminho' then 'oc' end;
      -- FASE 4: fim
      v_nova.fornecedor_id := v_forn;
      v_nova.compra_prevista_em := null;
      v_nova.quantidade_na_mao := case when v_ini_sit = 'na_mao' then v_req else 0 end;
      v_nova.chegou_em := case when v_ini_sit <> 'na_mao' then null
                               when v_velha.situacao = 'na_mao' then coalesce(v_velha.chegou_em, p_hoje)
                               -- FASE 4: o dia do recebimento da OC ligada (senão hoje, como antes).
                               else v_ok_chegou end;
                               -- FASE 4: fim
      v_nova.previsao_de := null;
      v_nova.previsao_ate := case when v_ini_sit = 'a_caminho' then v_oc_prev end;
      v_nova.previsao_fonte := case when v_ini_sit = 'a_caminho' and v_oc_prev is not null then 'oc' end;
      v_nova.previsao_original := coalesce(v_velha.previsao_original, v_nova.previsao_ate);
      if v_nova.situacao <> v_velha.situacao then
        v_nota := coalesce(v_nota || '; ', '') || case v_nova.situacao
          -- FASE 4: "recebido na OC-x" pela OC ligada (senão "o estoque cobre", como antes).
          when 'na_mao' then v_ok_nota
          -- FASE 4: fim
          when 'a_caminho' then 'pedido na ' || coalesce(v_oc_numero, 'OC')
          else case v_velha.situacao when 'na_mao' then 'o estoque deixou de cobrir'
                                     else 'a OC deixou de cobrir' end end;
      end if;
      -- FASE 4: o "comprado em" da OC: a linha a caminho (ou na mão pela OC) guarda o dia da OC se ainda não tinha; a que
      -- volta a faltar perde o que o sistema gravou (comprado_fonte oc).
      if v_oc_criada is not null and v_nova.situacao in ('a_caminho', 'na_mao') then
        if v_nova.comprado_em is null then
          v_nova.comprado_em := v_oc_criada;
          v_nova.comprado_fonte := 'oc';
        end if;
      elsif v_nova.situacao = 'falta' and v_nova.comprado_fonte = 'oc' then
        v_nova.comprado_em := null;
        v_nova.comprado_fonte := null;
      end if;
      -- FASE 4: fim
    else
      -- O que foi dito valia para a quantidade antiga: a que sobe derruba o fato.
      if v_req > v_velha.quantidade_necessaria and v_velha.situacao in ('na_mao', 'comprado', 'a_caminho') then
        v_nova.situacao := 'falta';
        v_nova.chegou_em := null;
        v_nova.previsao_de := null;
        v_nova.previsao_ate := null;
        v_nova.previsao_fonte := null;
      end if;
      -- A que cai pode completar o que está na mão.
      if v_nova.quantidade_na_mao >= v_nova.quantidade_necessaria
         and v_nova.situacao not in ('na_mao', 'dispensado') then
        v_nova.situacao := 'na_mao';
        v_nova.chegou_em := coalesce(v_nova.chegou_em, p_hoje);
        v_nova.compra_prevista_em := null;
      end if;
      if v_status = 'ok' and v_nova.situacao not in ('na_mao', 'dispensado') then
        -- Chegou e entrou no estoque.
        v_nova.situacao := 'na_mao';
        -- FASE 4: pela OC ligada recebida, fonte oc (senão o estoque, como antes).
        v_nova.fonte := v_ok_fonte;
        -- FASE 4: fim
        v_nova.quantidade_na_mao := v_req;
        -- FASE 4: o dia do recebimento da OC ligada (senão hoje).
        v_nova.chegou_em := v_ok_chegou;
        -- FASE 4: fim
        v_nova.compra_prevista_em := null;
        -- FASE 4: "recebido na OC-x" pela OC ligada (senão "o estoque cobre").
        v_nota := coalesce(v_nota || '; ', '') || v_ok_nota;
        -- FASE 4: fim
      elsif v_status = 'on_order' and v_nova.situacao = 'falta' then
        -- "Vou comprar" que virou OC: a OC é o fato mais novo.
        v_nova.situacao := 'a_caminho';
        v_nova.fonte := 'oc';
        v_nova.quantidade_na_mao := 0;
        v_nova.compra_prevista_em := null;
        v_nova.fornecedor_id := coalesce(v_oc_forn, v_nova.fornecedor_id);
        v_nova.previsao_de := null;
        v_nova.previsao_ate := v_oc_prev;
        v_nova.previsao_fonte := case when v_oc_prev is not null then 'oc' end;
        v_nova.previsao_original := coalesce(v_velha.previsao_original, v_oc_prev);
        v_nota := coalesce(v_nota || '; ', '') || 'pedido na ' || coalesce(v_oc_numero, 'OC');
        -- FASE 4: o "comprado em" da OC (Brasília), se o dono ainda não disse quando comprou.
        if v_nova.comprado_em is null and v_oc_criada is not null then
          v_nova.comprado_em := v_oc_criada;
          v_nova.comprado_fonte := 'oc';
        end if;
        -- FASE 4: fim
      end if;
    end if;

    if (v_nova.service_order_id, v_nova.descricao, v_nova.quantidade_necessaria, v_nova.quantidade_na_mao,
        v_nova.situacao, v_nova.fonte, v_nova.fornecedor_id, v_nova.compra_prevista_em, v_nova.previsao_de,
        -- FASE 4: + o "comprado em" e a fonte dele.
        v_nova.previsao_ate, v_nova.previsao_original, v_nova.previsao_fonte, v_nova.chegou_em,
        v_nova.comprado_em, v_nova.comprado_fonte)
        -- FASE 4: fim
       is distinct from
       (v_velha.service_order_id, v_velha.descricao, v_velha.quantidade_necessaria, v_velha.quantidade_na_mao,
        v_velha.situacao, v_velha.fonte, v_velha.fornecedor_id, v_velha.compra_prevista_em, v_velha.previsao_de,
        -- FASE 4: + o "comprado em" e a fonte dele.
        v_velha.previsao_ate, v_velha.previsao_original, v_velha.previsao_fonte, v_velha.chegou_em,
        v_velha.comprado_em, v_velha.comprado_fonte) then
        -- FASE 4: fim
      update public.os_material
         set service_order_id = v_nova.service_order_id, descricao = v_nova.descricao,
             quantidade_necessaria = v_nova.quantidade_necessaria, quantidade_na_mao = v_nova.quantidade_na_mao,
             situacao = v_nova.situacao, fonte = v_nova.fonte, fornecedor_id = v_nova.fornecedor_id,
             compra_prevista_em = v_nova.compra_prevista_em, previsao_de = v_nova.previsao_de,
             previsao_ate = v_nova.previsao_ate, previsao_original = v_nova.previsao_original,
             previsao_fonte = v_nova.previsao_fonte, chegou_em = v_nova.chegou_em,
             -- FASE 4:
             comprado_em = v_nova.comprado_em, comprado_fonte = v_nova.comprado_fonte,
             -- FASE 4: fim
             historico = public._os_material_historico(v_velha.historico, jsonb_build_object(
               'em', p_hoje, 'de', v_velha.situacao, 'para', v_nova.situacao, 'por', 'sistema',
               'nota', coalesce(v_nota, 'conferido com a OS'))),
             atualizado_em = now(), atualizado_por = null
       where id = v_velha.id;
      v_atualizadas := v_atualizadas + 1;
    end if;
  end loop;

  -- Item de OC da OS que não está mais pendente: recebido vira na mão; OC cancelada volta a faltar.
  for v_velha in
    select m.* from public.os_material m
     where m.service_order_id = p_so_id and m.origem = 'oc' and m.purchase_order_item_id is not null
       and not (m.purchase_order_item_id = any (v_pendentes))
     order by m.id
     for update
  loop
    select poi.quantity, poi.received_qty, po.status as po_status, po.received_date, po.po_number
      into v_poi
      from public.purchase_order_items poi join public.purchase_orders po on po.id = poi.purchase_order_id
     where poi.id = v_velha.purchase_order_item_id;
    continue when not found;
    v_nova := v_velha;
    v_nota := null;
    if v_poi.po_status = 'received' or coalesce(v_poi.received_qty, 0) >= v_poi.quantity then
      if v_velha.situacao not in ('na_mao', 'dispensado') then
        v_nova.situacao := 'na_mao';
        v_nova.fonte := 'oc';
        v_nova.quantidade_na_mao := v_nova.quantidade_necessaria;
        v_nova.chegou_em := least(coalesce(v_poi.received_date, p_hoje), p_hoje);
        v_nova.compra_prevista_em := null;
        v_nota := 'recebido na ' || v_poi.po_number;
      end if;
    elsif v_poi.po_status = 'cancelled'
          and (v_velha.fonte is null or v_velha.fonte = 'oc') and v_velha.situacao <> 'falta' then
      v_nova.situacao := 'falta';
      v_nova.fonte := null;
      v_nova.quantidade_na_mao := 0;
      v_nova.chegou_em := null;
      v_nova.previsao_de := null;
      v_nova.previsao_ate := null;
      v_nova.previsao_fonte := null;
      v_nota := 'a ' || v_poi.po_number || ' foi cancelada';
      -- FASE 4: a compra que o sistema registrou pela OC cancelada deixa de valer.
      if v_nova.comprado_fonte = 'oc' then
        v_nova.comprado_em := null;
        v_nova.comprado_fonte := null;
      end if;
      -- FASE 4: fim
    end if;
    if v_nota is not null then
      update public.os_material
         set situacao = v_nova.situacao, fonte = v_nova.fonte, quantidade_na_mao = v_nova.quantidade_na_mao,
             chegou_em = v_nova.chegou_em, compra_prevista_em = v_nova.compra_prevista_em,
             previsao_de = v_nova.previsao_de, previsao_ate = v_nova.previsao_ate,
             previsao_fonte = v_nova.previsao_fonte,
             -- FASE 4:
             comprado_em = v_nova.comprado_em, comprado_fonte = v_nova.comprado_fonte,
             -- FASE 4: fim
             historico = public._os_material_historico(v_velha.historico, jsonb_build_object(
               'em', p_hoje, 'de', v_velha.situacao, 'para', v_nova.situacao, 'por', 'sistema', 'nota', v_nota)),
             atualizado_em = now(), atualizado_por = null
       where id = v_velha.id;
      v_atualizadas := v_atualizadas + 1;
    end if;
  end loop;

  -- FASE 4: a chegada pela nota (P3): a linha ligada a uma nota (remessa_id) que chegou fica na mão — fonte nfe, o dia da
  -- chegada da nota (nunca depois de hoje), a quantidade toda. Só com modo_material ligado: em sombra a linha fica igual
  -- (spec §5.3). Quem registra a ação com desfaz é o caminho da nota (P3); aqui é a rede idempotente.
  if (select c.modo_material from public.agenda_config c where c.id) = 'ligado' then
    for v_velha in
      select m.* from public.os_material m
        join public.material_remessas r on r.id = m.remessa_id
       where m.service_order_id = p_so_id and r.estado = 'chegou'
         and m.situacao not in ('na_mao', 'dispensado')
       order by m.id
       for update of m
    loop
      select r.chegou_em, r.numero into v_rem from public.material_remessas r where r.id = v_velha.remessa_id;
      update public.os_material
         set situacao = 'na_mao', fonte = 'nfe', quantidade_na_mao = quantidade_necessaria,
             chegou_em = least(coalesce(v_rem.chegou_em, p_hoje), p_hoje), compra_prevista_em = null,
             historico = public._os_material_historico(v_velha.historico, jsonb_build_object(
               'em', p_hoje, 'de', v_velha.situacao, 'para', 'na_mao', 'por', 'sistema',
               'nota', 'chegou pela nota' || coalesce(' ' || v_rem.numero, ''))),
             atualizado_em = now(), atualizado_por = null
       where id = v_velha.id;
      v_atualizadas := v_atualizadas + 1;
    end loop;
  end if;
  -- FASE 4: fim
  return jsonb_build_object(
    'criadas', v_criadas,
    'atualizadas', v_atualizadas,
    'linhas', (select count(*) from public.os_material where service_order_id = p_so_id));
end;
$function$;

comment on function public.os_material_sincronizar(uuid, date) is
  'Agenda de Produção (Fase 1, P2; Fase 4, P2: o texto livre a caminho pela OC desta OS ligada a ele acha essa OC — previsão, fornecedor —, e recebido fica na mão com fonte oc e o dia do recebimento; a linha a caminho, ou na mão pela OC, ganha comprado_em = o dia da OC em Brasília e comprado_fonte oc, se não tinha, e a que volta a faltar perde o que o sistema gravou; a linha com remessa_id cuja nota chegou fica na mão, fonte nfe, só com modo_material ligado): materializa em os_material uma linha por item da conta bruta da OS (peça, texto livre, item de OC de texto livre) e mantém o que o sistema sabe: estoque cobrindo = na_mao (fonte estoque); OC cobrindo = a_caminho (fonte oc, previsão da OC); senão falta. A linha do sistema (fonte nula/estoque/oc) é refeita a cada passada; o fato informado fica, salvo quantidade que sobe (derruba para falta), estoque cobrindo (na_mao) e falta que ganhou OC (a_caminho). Item de OC recebido = na_mao; OC cancelada = falta. Histórico com os 20 mais novos; atualizado_em só muda com mudança real. Só service_role. Devolve {criadas, atualizadas, linhas}.';


revoke all on function public.os_material_sincronizar(uuid, date) from public, anon, authenticated;
grant execute on function public.os_material_sincronizar(uuid, date) to service_role;

-- ── 5. O recebimento do item de texto livre ──────────────────────────────────────────────────────────────
-- Corpo de 20261007160000 copiado; a mudança está marcada "-- FASE 4:". A conta a pagar ao completar NÃO muda
-- (NOVO-agenda-32: a OC já paga por Pix ganha conta a pagar ao ser recebida — decisão do dono).

create or replace function public.receive_po(p_po_id uuid, p_items jsonb, p_due_days integer default 30)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_item        jsonb;
  v_poi         record;
  v_new_rcv     numeric;
  v_qtd         numeric;
  v_po          record;
  v_all_done    boolean := true;
  v_any_done    boolean := false;
  v_new_status  text;
  v_payable_id  uuid;
  v_total       numeric;
BEGIN
  -- A OC primeiro, travada: só rascunho, enviada ou recebida em parte recebem.
  SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ordem de compra não encontrada.'; END IF;
  IF v_po.status = 'cancelled' THEN
    RAISE EXCEPTION 'A % está cancelada — não recebe. Volte-a para rascunho antes, se a compra continua.', v_po.po_number;
  END IF;
  IF v_po.status = 'received' THEN
    RAISE EXCEPTION 'A % já está toda recebida.', v_po.po_number;
  END IF;

  -- Process each item
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qtd := (v_item->>'received_qty')::numeric;
    IF v_qtd IS NULL OR v_qtd <= 0 THEN
      RAISE EXCEPTION 'Quantidade recebida tem de ser maior que zero.';
    END IF;

    -- Só item DESTA OC.
    SELECT * INTO v_poi
      FROM public.purchase_order_items
     WHERE id = (v_item->>'po_item_id')::uuid
       AND purchase_order_id = p_po_id
       FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'O item % não é da % — nada foi recebido.', v_item->>'po_item_id', v_po.po_number;
    END IF;

    v_new_rcv := COALESCE(v_poi.received_qty, 0) + v_qtd;
    v_new_rcv := LEAST(v_new_rcv, v_poi.quantity); -- cap at ordered qty

    -- Update received_qty on item
    UPDATE public.purchase_order_items
       SET received_qty = v_new_rcv
     WHERE id = v_poi.id;

    -- FASE 4: item de texto livre (sem produto) não tem estoque: recebe (received_qty acima) sem tocar products nem
    -- inventory_movements (product_id é NOT NULL lá; antes, um item assim derrubava o recebimento inteiro). P2.
    IF v_poi.product_id IS NOT NULL THEN
    -- FASE 4: fim
    -- O saldo sobe pelo movimento abaixo (fase E); aqui só a data da última entrada.
    UPDATE public.products
       SET last_stock_entry_at = NOW()
     WHERE id = v_poi.product_id;

    -- Inventory movement
    INSERT INTO public.inventory_movements
      (product_id, movement_type, quantity_delta, reference_type, reference_id, unit_cost_snapshot)
    VALUES
      (v_poi.product_id, 'purchase', v_qtd,
       'purchase_order', p_po_id, v_poi.unit_cost);
    -- FASE 4: o fim do "só com produto".
    END IF;
    -- FASE 4: fim

    v_any_done := true;
    IF v_new_rcv < v_poi.quantity THEN v_all_done := false; END IF;
  END LOOP;

  -- Check if ALL items across the entire PO are fully received
  SELECT bool_and(received_qty >= quantity)
    INTO v_all_done
    FROM public.purchase_order_items
   WHERE purchase_order_id = p_po_id;

  v_new_status := CASE
    WHEN v_all_done THEN 'received'
    WHEN v_any_done THEN 'partial'
    ELSE v_po.status
  END;

  -- Create payable when fully received and no payable yet
  IF v_new_status = 'received' AND v_po.payable_id IS NULL AND v_po.supplier_id IS NOT NULL THEN
    SELECT COALESCE(SUM(received_qty * unit_cost), 0)
      INTO v_total
      FROM public.purchase_order_items
     WHERE purchase_order_id = p_po_id;

    INSERT INTO public.payables
      (supplier_id, description, amount, balance_amount, paid_amount,
       issue_date, due_date, status, origin)
    VALUES
      (v_po.supplier_id,
       'Recebimento ' || v_po.po_number,
       v_total, v_total, 0,
       CURRENT_DATE, CURRENT_DATE + p_due_days,
       'pending', 'purchase_order')
    RETURNING id INTO v_payable_id;

    UPDATE public.purchase_orders
       SET status     = v_new_status,
           payable_id = v_payable_id,
           received_date = CURRENT_DATE
     WHERE id = p_po_id;
  ELSE
    UPDATE public.purchase_orders
       SET status = v_new_status,
           received_date = CASE WHEN v_new_status = 'received' THEN CURRENT_DATE ELSE received_date END
     WHERE id = p_po_id;
  END IF;

  RETURN json_build_object(
    'status',      v_new_status,
    'payable_id',  v_payable_id,
    'all_received', v_all_done
  );
END;
$function$;


comment on function public.receive_po(uuid, jsonb, integer) is
  'Recebe itens de uma OC (draft/sent/partial; confere que o item é desta OC e que a quantidade é maior que zero): received_qty sobe até o pedido; item com produto dá entrada no estoque pelo movimento (purchase) e marca a data da última entrada; item de texto livre (sem produto) só sobe o received_qty (Agenda de Produção, Fase 4, P2: antes derrubava o recebimento). A OC fica partial ou received; ao completar, com fornecedor e sem conta, cria a conta a pagar (recebido × custo de todos os itens; vencimento hoje + p_due_days) — NOVO-agenda-32: a OC já paga por Pix também ganha a conta; é decisão do dono, a Fase 4 não muda.';

-- create or replace mantém os privilégios; reafirmados para a migration valer sozinha.
revoke all on function public.receive_po(uuid, jsonb, integer) from public, anon;
grant execute on function public.receive_po(uuid, jsonb, integer) to authenticated, service_role;

-- ── 6. A prontidão: a OC recebida ligada não conta duas vezes ────────────────────────────────────────────
-- Corpo de 20261027100100 (P1) copiado; a mudança está marcada "-- FASE 4:" (só acréscimo).

create or replace function public.os_prontidao(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public'
as $function$
declare
  c            public.agenda_config := public._agenda_cfg();
  so           record;
  p            public.os_planejamento%rowtype;
  v_na_cart    boolean;
  v_aprov      date;
  v_pago       numeric := 0;
  v_pend       numeric := 0;
  v_ag_de      date;
  v_ag_ate     date;
  v_bem_nome   text;
  v_d_bem      date;
  v_bem_tudo   boolean := false;
  v_horizonte  date;
  v_base       date;
  v_est_sm     date;
  v_bruto      jsonb;
  v_itens      jsonb;
  v_crit       jsonb;
  v_embut      jsonb;
  v_n_itens    int;
  v_conferido  boolean;
  v_mat_estado text;
  v_dpm        date;
  v_gargalo    jsonb;
  v_confianca  text;
  v_inicio_mat date;
  v_est        date;
  v_sug        jsonb;
  v_dur        jsonb;
  v_equipe     jsonb;
  v_meios      numeric;
  v_diarias_eq numeric;
  v_dias_re    numeric;
  v_pres       jsonb;
  v_prazo      date;
  v_prazo_fnt  text;
  v_razao      numeric;
  v_r          jsonb := '[]'::jsonb;
  v_estado     text;
  v_estado_txt text;
  v_principal  jsonb;
  v_quase      boolean := false;
  v_parada     boolean := false;
  v_ult_diaria date;
  v_x          jsonb;
  v_compra     jsonb;
  v_n          int;
  v_n_falta    int := 0;
  v_n_sem      int;
  v_txt        text;
  v_cond       text;
  v_dono_padrao boolean;
  v_cc         record;
  -- FASE 2: o que o plano publicado diz da OS (spec-fase2 §6.1)
  v_plano      jsonb;
  v_ult_evid   date;
  v_tem_futuro boolean := false;
  -- FASE 2: fim
begin
  if p_hoje is null then
    raise exception 'os_prontidao: sem o dia de hoje' using errcode = '22004';
  end if;

  select o.*, cl.name as cliente_nome, vs.name as bem, vs.asset_type as bem_tipo,
         mg.service_order_number as juntado_em
    into so
    from public.service_orders o
    left join public.clients cl on cl.id = o.client_id
    left join public.vessels vs on vs.id = o.vessel_id
    left join public.service_orders mg on mg.id = o.merged_into_id
   where o.id = p_so_id;
  if not found then
    return jsonb_build_object('ok', false, 'texto', 'Não encontrei esse serviço.');
  end if;

  select * into p from public.os_planejamento where service_order_id = p_so_id;

  -- Carteira, aprovação, sinal e janela antiga: a MESMA conta de os_carteira (fora dela, a mesma fórmula).
  select true, k.aprovada_em, k.sinal_pago, k.sinal_pendente, k.agendada_de, k.agendada_ate
    into v_na_cart, v_aprov, v_pago, v_pend, v_ag_de, v_ag_ate
    from public.os_carteira(p_hoje) k where k.service_order_id = p_so_id;
  if not found then
    v_na_cart := false;
    v_aprov := (coalesce(so.converted_to_os_at, so.signed_at, so.created_at) at time zone 'America/Sao_Paulo')::date;
    select coalesce(sum(coalesce(r.paid_amount, 0)), 0),
           coalesce(sum(case when r.status in ('pending', 'partially_paid', 'overdue')
                             then greatest(r.amount - coalesce(r.paid_amount, 0), 0) else 0 end), 0)
      into v_pago, v_pend
      from public.receivables r
     where r.service_order_id = p_so_id and r.is_deposit and r.status <> 'cancelled';
    v_ag_de := (so.scheduled_start_at at time zone 'America/Sao_Paulo')::date;
    v_ag_ate := (coalesce(so.scheduled_end_at, so.scheduled_start_at) at time zone 'America/Sao_Paulo')::date;
  end if;

  -- O bem (barco, motorhome): 1º dia a partir de amanhã fora de bem_indisponivel; null = fora sem data de volta.
  v_bem_nome := case when public._agenda_normal(coalesce(so.bem_tipo, so.bem)) ~ 'motorhome|motor home|trailer'
                     then 'o motorhome' else 'o barco' end;
  v_horizonte := p_hoje + 7 * c.horizonte_semanas;
  v_d_bem := p_hoje + 1;
  if p.service_order_id is not null and not isempty(p.bem_indisponivel) and p.bem_indisponivel @> v_d_bem then
    select upper(r) into v_d_bem from unnest(p.bem_indisponivel) r where r @> (p_hoje + 1);
  end if;
  v_bem_tudo := v_d_bem is null or v_d_bem > v_horizonte;

  -- O início mais cedo sem olhar o material: o bem livre, o "não antes de" e o congelamento (hoje + o próximo
  -- dia útil ficam como estão).
  v_base := public.agenda_somar_du(p_hoje, c.congelamento_du + 1);
  v_est_sm := greatest(v_d_bem, p.nao_antes_de, v_base);

  -- ── Material efetivo: a conta bruta + o que foi informado em os_material ──
  v_bruto := public.os_necessidade_bruta(p_so_id);

  with
  bruto as (
    select x.ord, x.i ->> 'origin' as origin, (x.i ->> 'sourceId')::uuid as src,
           (x.i ->> 'required')::numeric as req, coalesce((x.i ->> 'available')::numeric, 0) as disp,
           x.i ->> 'status' as st, (x.i ->> 'productId')::uuid as prod, x.i ->> 'description' as descr
      from jsonb_array_elements(coalesce(v_bruto -> 'items', '[]'::jsonb)) with ordinality x(i, ord)
     where coalesce((x.i ->> 'required')::numeric, 0) > 0
       and x.i ->> 'origin' in ('part', 'free_text', 'purchase_order')
  ),
  cand as (
    -- (1) os itens da conta bruta, com a linha do mesmo vínculo
    select 1 as grupo, b.ord::bigint as ord,
           case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end as origem,
           b.src as vinculo, b.req, b.disp, b.st, b.descr, b.prod, null::uuid as po_forn, null::date as recebido_em,
           m as l
      from bruto b
      left join public.os_material m
        on m.service_order_id = p_so_id
       and m.origem = case b.origin when 'part' then 'peca' when 'free_text' then 'texto_livre' else 'oc' end
       and b.src = case m.origem when 'peca' then m.service_order_part_id
                                 when 'texto_livre' then m.service_order_service_id
                                 else m.purchase_order_item_id end
    union all
    -- (2) item de OC de texto livre da OS que já chegou (saiu da conta bruta) — continua, na mão
    select 2, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, poi.quantity,
           'recebido', poi.description, null, po.supplier_id, po.received_date, m
      from public.purchase_order_items poi
      join public.purchase_orders po on po.id = poi.purchase_order_id
      left join public.os_material m on m.origem = 'oc' and m.purchase_order_item_id = poi.id
     where po.service_order_id = p_so_id and poi.product_id is null and poi.quantity > 0
       and po.status <> 'cancelled'
       and (po.status = 'received' or coalesce(poi.received_qty, 0) >= poi.quantity)
       -- FASE 4: a linha ligada a um item de texto livre da conta já está nele, no grupo 1 (os_necessidade_bruta, P2).
       and not exists (select 1 from bruto b where b.origin = 'free_text' and b.src = poi.service_order_service_id)
       -- FASE 4: fim
    union all
    -- (3) item de OC cancelada que tinha linha: a sincronização o devolveu a "falta" (ou o dono informou)
    select 3, row_number() over (order by po.created_at, poi.id), 'oc', poi.id, poi.quantity, 0,
           'cancelado', poi.description, null, po.supplier_id, null, m
      from public.os_material m
      join public.purchase_order_items poi on poi.id = m.purchase_order_item_id
      join public.purchase_orders po on po.id = poi.purchase_order_id
     where m.service_order_id = p_so_id and m.origem = 'oc' and po.status = 'cancelled'
    union all
    -- (4) o que o dono citou e não está no orçamento (peça embutida, material novo)
    select 4, row_number() over (order by m.descricao, m.id), 'dono', m.service_order_service_id,
           m.quantidade_necessaria, 0, 'dono', m.descricao, null, null, null, m
      from public.os_material m
     where m.service_order_id = p_so_id and m.origem = 'dono'
  ),
  passo1 as (
    select k.*,
           coalesce((k.l).fonte in ('dono', 'fornecedor', 'nfe', 'pix'), false) as informado,
           coalesce((k.l).critico, true) as critico
      from cand k
     where (k.l).situacao is distinct from 'dispensado'
  ),
  passo2 as (
    select q.*,
           case when q.grupo = 1
                then greatest(q.disp, case when q.informado then least(q.req, (q.l).quantidade_na_mao) else 0 end)
                else 0 end as disp_ef
      from passo1 q
  ),
  passo3 as (
    -- A situação efetiva. Só o fato informado muda o item; "na mão" só com a quantidade completa contra a conta de
    -- hoje; o que o dono disse para menos do que a OS pede hoje volta a faltar.
    select q.*,
           case
             when q.grupo = 2 then case when q.informado and (q.l).situacao <> 'na_mao' then (q.l).situacao else 'na_mao' end
             when q.grupo = 4 then (q.l).situacao
             when q.grupo = 3 then case when q.informado then (q.l).situacao else 'falta' end
             when q.disp_ef >= q.req then 'na_mao'
             when q.informado and (q.l).situacao in ('na_mao', 'comprado', 'a_caminho')
                  and (q.l).quantidade_necessaria < q.req then 'falta'
             when q.informado and (q.l).situacao = 'na_mao' then 'falta'
             when q.informado then (q.l).situacao
             when q.st = 'on_order' then 'a_caminho'
             else 'falta' end as sit
      from passo2 q
  ),
  passo4 as (
    -- A OC que cobre o item que o sistema vê "a caminho" (a da própria OS primeiro): previsão, data e fornecedor.
    select q.*, oc.expected_date as oc_prev, oc.criada as oc_criada, oc.po_number as oc_numero, oc.forn as oc_forn,
           pr.supplier_id as prod_forn
      from passo3 q
      left join public.products pr on pr.id = q.prod
      left join lateral (
        select v.expected_date, (v.po_criada_em at time zone 'America/Sao_Paulo')::date as criada, v.po_number,
               po.supplier_id as forn
          from public.v_oc_itens_a_caminho v
          join public.purchase_orders po on po.id = v.purchase_order_id
         where q.grupo = 1 and q.sit = 'a_caminho' and not q.informado and v.pendente > 0
           and case when q.origem = 'oc' then v.purchase_order_item_id = q.vinculo
                    -- FASE 4: o item de texto livre é coberto pela linha da OC ligada a ele (service_order_service_id, P2).
                    when q.origem = 'texto_livre' then v.service_order_service_id = q.vinculo
                    -- FASE 4: fim
                    else v.product_id = q.prod and v.conta_como_ja_pedido end
         order by (v.service_order_id is distinct from p_so_id), v.po_criada_em, v.purchase_order_item_id
         limit 1) oc on true
  ),
  passo5 as (
    select q.*,
           case
             when q.sit = 'na_mao' and q.grupo = 1 and q.disp >= q.req and not q.informado then 'estoque'
             when q.informado then (q.l).fonte
             when q.grupo = 2 then 'oc'
             when q.sit = 'a_caminho' and q.grupo = 1 then 'oc'
             else (q.l).fonte end as fonte,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_ate when q.grupo = 1 then q.oc_prev end end as prev_ate,
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado then (q.l).previsao_fonte
                       when q.grupo = 1 and q.oc_prev is not null then 'oc' end end as prev_fonte,
           -- O informado sem data de compra conta do dia em que o dono contou (conferido_em): a estimativa não anda.
           case when q.sit in ('comprado', 'a_caminho') then
                  case when q.informado
                       then coalesce((q.l).comprado_em, ((q.l).conferido_em at time zone 'America/Sao_Paulo')::date)
                       when q.grupo = 1 then q.oc_criada end end as comprado_em,
           case when q.sit = 'falta' and q.informado then (q.l).compra_prevista_em end as compra_prevista_em,
           case when q.sit = 'na_mao' then
                  case when q.informado or q.grupo = 4 then (q.l).chegou_em
                       when q.grupo = 2 then coalesce((q.l).chegou_em, q.recebido_em)
                       when (q.l).situacao = 'na_mao' then (q.l).chegou_em end end as chegou_em,
           -- O fornecedor: o que o dono disse (cadastrado ou só o nome), senão o da OC, senão o do produto.
           case when q.informado and (q.l).fornecedor_id is null and (q.l).fornecedor_nome is not null then null
                else coalesce(case when q.informado then (q.l).fornecedor_id end, q.oc_forn, q.po_forn,
                              (q.l).fornecedor_id, q.prod_forn) end as forn_id,
           case when q.informado and (q.l).fornecedor_id is null then (q.l).fornecedor_nome end as forn_nome
      from passo4 q
  ),
  passo6 as (
    -- FASE 4: o prazo do fornecedor numa fonte só (_agenda_prazo_do_fornecedor: o que o dono disse, o cadastro repetido,
    -- o nome e a cidade/UF tolerante ao caractere quebrado); a classe, os dias úteis e os corridos saem dele no passo 7.
    select q.*, public._agenda_prazo_do_fornecedor(q.forn_id) as pf
    -- FASE 4: fim
      from passo5 q
  ),
  passo7 as (
    -- FASE 4: a classe e os dias úteis do fornecedor; o importado tem os dias corridos (e prazo nulo).
    select q.*, q.pf ->> 'classe' as classe, (q.pf ->> 'du')::int as prazo, (q.pf ->> 'corridos')::int as corridos
    -- FASE 4: fim
      from passo6 q
  ),
  passo8 as (
    select q.*,
           case
             when q.sit = 'na_mao' then 'A'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null and q.prev_fonte <> 'dono' then 'B'
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then 'C'
             when q.sit in ('comprado', 'a_caminho') then 'D'
             -- FASE 4: o importado tem prazo (em dias corridos).
             when q.prazo is not null or q.corridos is not null then 'D'
             -- FASE 4: fim
             else 'E' end as nivel,
           case
             when q.sit = 'na_mao' then q.chegou_em
             when q.sit in ('comprado', 'a_caminho') and q.prev_ate is not null then q.prev_ate
             -- FASE 4: a chegada pelo prazo do fornecedor (_agenda_chegada_pela_classe: dias úteis; o importado, os dias
             -- corridos levados ao dia útil).
             when q.sit in ('comprado', 'a_caminho') and (q.prazo is not null or q.corridos is not null) then
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos, coalesce(q.comprado_em, p_hoje))
             when q.sit = 'falta' and (q.prazo is not null or q.corridos is not null) then
               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.
               public._agenda_chegada_pela_classe(q.classe, q.prazo, q.corridos,
                                                  greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje))
             -- FASE 4: fim
           end as data,
           -- FASE 4: "compre até" pelo mesmo prazo; o importado: o início menos a folga, menos os dias corridos, no último dia
           -- útil até ali (agenda_somar_du(x + 1, -1) é o último dia útil até x).
           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo))
                when q.sit = 'falta' and q.corridos is not null and q.compra_prevista_em is null then
             public.agenda_somar_du(public.agenda_somar_du(v_est_sm, -c.folga_material_du) - q.corridos + 1, -1) end as compre_ate,
           -- FASE 4: fim
           (select f.name from public.suppliers f where f.id = q.forn_id) as forn_cadastro
      from passo7 q
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', (q.l).id, 'linha', q.vinculo, 'origem', q.origem,
           'descricao', coalesce((q.l).descricao, q.descr), 'curto', public._agenda_linha_curta(coalesce((q.l).descricao, q.descr)),
           'nivel', q.nivel, 'situacao', q.sit, 'data', q.data,
           -- Parcial (parte já na mão, informada ou do estoque): quantas estão na mão e quantas faltam, antes do resto.
           'data_texto', case when q.sit <> 'na_mao' and q.disp_ef > 0 and q.disp_ef < q.req
                              then format('%s de %s na mão, %s %s: ', replace(trim_scale(q.disp_ef)::text, '.', ','),
                                          replace(trim_scale(q.req)::text, '.', ','),
                                          case when q.req - q.disp_ef = 1 then 'falta' else 'faltam' end,
                                          replace(trim_scale(q.req - q.disp_ef)::text, '.', ','))
                              else '' end
           || case
              when q.nivel = 'A' then case when q.data is not null then 'na mão desde ' || public._dia_curto(q.data) else 'na mão' end
              when q.nivel = 'B' then 'chega ' || public._dia_curto(q.data) || case q.prev_fonte
                   when 'oc' then ' (pela OC)' when 'fornecedor' then ' (o fornecedor disse)'
                   when 'nfe' then ' (pela nota)' when 'pix' then ' (pelo Pix)' else '' end
              when q.nivel = 'C' then 'chega ' || public._dia_curto(q.data) || ' (você disse)'
              when q.sit in ('comprado', 'a_caminho') then
                   coalesce('pedido em ' || to_char(q.comprado_em, 'DD/MM'), 'comprado')
                   || case when q.data is not null then ', deve chegar por volta de ' || public._dia_curto(q.data)
                           else ', sem previsão' end
              when q.nivel = 'D' then
                   case when q.compra_prevista_em is not null and q.compra_prevista_em >= p_hoje
                        then format('comprando %s, chega por volta de %s', public._dia_curto(q.compra_prevista_em),
                                    public._dia_curto(q.data))
                        else 'se comprar hoje, chega por volta de ' || public._dia_curto(q.data) end
              when q.forn_nome is not null then format('a comprar de %s, sem prazo conhecido', q.forn_nome)
              when q.forn_id is not null then format('a comprar de %s, sem cidade/UF no cadastro', public._agenda_nome_curto(q.forn_cadastro))
              else 'a comprar, sem fornecedor' end,
           'fonte', q.fonte, 'previsao_fonte', q.prev_fonte, 'trecho', (q.l).trecho, 'critico', q.critico,
           'quantidade', trim_scale(q.req), 'na_mao', trim_scale(case when q.sit = 'na_mao' then q.req else q.disp_ef end),
           'fornecedor', coalesce(q.forn_nome, public._agenda_nome_curto(q.forn_cadastro)),
           'classe', q.classe, 'prazo_du', q.prazo,
           -- FASE 4: o texto do prazo do fornecedor ("entrega local, 1 dia útil (pela cidade, chute meu)"), a dúvida do
           -- cadastro (duplicado | sem_lugar) e os dias corridos do importado.
           'prazo_texto', q.pf ->> 'texto', 'duvida', q.pf ->> 'duvida', 'corridos', q.corridos,
           -- FASE 4: fim
           'comprado_em', q.comprado_em, 'compra_prevista_em', q.compra_prevista_em,
           'compre_ate', q.compre_ate,
           'atrasado', q.sit in ('comprado', 'a_caminho') and q.data is not null and q.data < p_hoje,
           'sem_data', q.nivel = 'E' or (q.nivel = 'D' and q.data is null))
           order by q.grupo, q.ord), '[]'::jsonb)
    into v_itens
    from passo8 q;

  v_crit := coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v_itens) with ordinality t(e, o)
                       where (e ->> 'critico')::boolean), '[]'::jsonb);
  v_n_itens := jsonb_array_length(v_itens);
  v_conferido := p.material_conferido_em is not null
              or exists (select 1 from public.os_material m
                          where m.service_order_id = p_so_id and m.fonte in ('dono', 'fornecedor', 'nfe', 'pix'));

  -- "Tem peça embutida?": linha de texto livre que NÃO entra na compra e (a) vale >= peca_embutida_acima, ou (b) o
  -- classificador lê como material (a unidade não é 'unit'), ou (c) cita peça/material. Some quando o dono responde
  -- por ela (linha do dono ligada à linha) ou quando ele diz "não tem peça a comprar" depois que a linha nasceu.
  select coalesce(jsonb_agg(jsonb_build_object('linha', s.id, 'nome', s.name_snapshot,
                                               'curto', public._agenda_linha_curta(s.name_snapshot),
                                               'valor', s.line_total)
                            order by s.line_total desc nulls last, s.created_at, s.id), '[]'::jsonb)
    into v_embut
    from public.service_order_services s
   where s.service_order_id = p_so_id and s.service_id is null
     and not (s.billing_unit_snapshot = 'unit' and coalesce(s.quantity, 0) > 0 and public.free_text_is_material(s.name_snapshot))
     and (coalesce(s.line_total, 0) >= c.peca_embutida_acima
          or public.free_text_is_material(s.name_snapshot)
          or public._agenda_normal(s.name_snapshot) ~ '\m(peca|pecas|material)\M')
     and not exists (select 1 from public.os_material m
                      where m.service_order_id = p_so_id and m.origem = 'dono' and m.service_order_service_id = s.id)
     and not (p.material_conferido_em is not null and p.material_conferido_em > s.created_at);

  -- O estado do material (do mais forte ao mais fraco).
  v_mat_estado := case
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'atrasado')::boolean) then 'atrasado'
    when exists (select 1 from jsonb_array_elements(v_crit) e where (e ->> 'sem_data')::boolean) then 'sem_previsao'
    when jsonb_array_length(v_embut) > 0 or (v_n_itens = 0 and not v_conferido) then 'nao_conferido'
    when exists (select 1 from jsonb_array_elements(v_crit) e where e ->> 'nivel' <> 'A') then 'previsto'
    else 'completo' end;

  -- DPM: a data mais tarde dos críticos fora de A; o início pelo material = chegada + folga_material_du, sem folga
  -- remota (revisão §7: o prazo "outro estado" já cobre o transporte).
  if v_mat_estado not in ('atrasado', 'sem_previsao') then
    select e into v_gargalo from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'nivel' <> 'A' order by (e ->> 'data')::date desc, o limit 1;
    v_dpm := (v_gargalo ->> 'data')::date;
    if v_dpm is not null then
      v_inicio_mat := public.agenda_somar_du(v_dpm, c.folga_material_du);
    end if;
    v_est := greatest(v_est_sm, v_inicio_mat);
  end if;
  v_confianca := (select e ->> 'nivel' from jsonb_array_elements(v_crit) e
                   order by case e ->> 'nivel' when 'E' then 0 when 'D' then 1 when 'C' then 2 when 'B' then 3 else 4 end
                   limit 1);

  -- ── Duração ──
  v_sug := public.os_duracao_sugerida(p_so_id);
  v_dono_padrao := exists (select 1 from public.agenda_disponibilidade d
                            where d.payee_id = public._agenda_dono(null) and d.substituida_em is null
                              and d.dias_semana is not null and d.situacao = 'disponivel');
  if p.dias is not null then
    select coalesce(jsonb_agg(jsonb_build_object('payee_id', e.payee_id, 'nome', public._agenda_nome_curto(py.name),
                                                 'eh_dono', py.kind = 'socio', 'turnos', e.turnos)
                              -- você primeiro; quem vai o dia todo antes de quem vai meio turno
                              order by py.kind = 'socio' desc, e.turnos = 'dia' desc, py.name, e.payee_id), '[]'::jsonb),
           -- Meios-dias por pessoa: o dia todo = 2 por dia; só de manhã ou só à tarde = 1 turno em cada dia que o
           -- serviço ocupa (meio dia com o João à tarde = 1 meio-dia; 1,5 dia à tarde = 2).
           coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0)
      into v_equipe, v_meios
      from public.os_planejamento_equipe e
      join public.payees py on py.id = e.payee_id
     where e.service_order_id = p_so_id;
    -- Sem equipe dita, a conta de diárias usa as pessoas da sugestão (é leitura, não vira número gravado). Na conta da
    -- equipe (a que a capacidade cobre), você só entra quando tem padrão.
    v_diarias_eq := case when jsonb_array_length(v_equipe) = 0
                         then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                         else (select coalesce(sum(case when e.turnos = 'dia' then p.dias * 2 else ceil(p.dias) end), 0) / 2
                                 from public.os_planejamento_equipe e join public.payees py on py.id = e.payee_id
                                where e.service_order_id = p_so_id
                                  and (py.kind <> 'socio' or v_dono_padrao)) end;
    v_dur := jsonb_build_object(
      'fonte', p.estimativa_fonte, 'dias', trim_scale(p.dias), 'equipe', v_equipe,
      'meios_dias', trim_scale(v_meios),
      'diarias', trim_scale(case when jsonb_array_length(v_equipe) = 0
                                 then p.dias * coalesce((v_sug ->> 'pessoas')::int, 1)
                                 else v_meios / 2 end),
      'diarias_equipe', trim_scale(v_diarias_eq),
      -- Diárias-pessoa da equipe para o backlog: o que o dono disse é um número só (otimista = realista).
      'dp_otimista', trim_scale(v_diarias_eq), 'dp_realista', trim_scale(v_diarias_eq),
      'equipe_dita', jsonb_array_length(v_equipe) > 0,
      'texto', public._agenda_dias(p.dias)
               || case when jsonb_array_length(v_equipe) > 0 then ': ' || public._agenda_lista(array(
                    select case when (x ->> 'eh_dono')::boolean then 'você' else x ->> 'nome' end
                           || case x ->> 'turnos' when 'dia' then ' (dia todo)' when 'manha' then ' (de manhã)'
                                                  else ' (à tarde)' end
                      from jsonb_array_elements(v_equipe) x), null) else '' end
               || case p.estimativa_fonte when 'aceita' then ' (você aceitou a minha estimativa)' else ' (você disse)' end,
      'sugestao', v_sug);
    v_dias_re := p.dias;
  else
    v_dur := jsonb_build_object(
      'fonte', 'sugerida',
      'dias', v_sug -> 'sugerida', 'dias_otimista', v_sug -> 'dias_otimista', 'dias_realista', v_sug -> 'dias_realista',
      'pessoas', v_sug -> 'pessoas', 'equipe', '[]'::jsonb, 'equipe_dita', false,
      'diarias_otimista', v_sug -> 'diarias_otimista', 'diarias_realista', v_sug -> 'diarias_realista',
      -- Diárias-pessoa da faixa (dias × pessoas) para o backlog: 74 = 3 a 6 (spec §6).
      'dp_otimista', v_sug -> 'diarias_otimista', 'dp_realista', v_sug -> 'diarias_realista',
      'sem_base', coalesce((v_sug ->> 'sem_base')::boolean, false),
      'texto', v_sug ->> 'texto', 'sugestao', v_sug);
    v_dias_re := (v_sug ->> 'dias_realista')::numeric;
  end if;

  v_pres := public.os_presenca_do_dono(p_so_id);

  -- ── Prazo e razão crítica ──
  v_prazo := coalesce(p.precisa_ate, public.agenda_somar_du(v_aprov, c.prazo_padrao_du));
  v_prazo_fnt := case when p.precisa_ate is not null then 'dono' else 'padrão' end;
  if v_dias_re is not null and v_dias_re > 0 then
    v_razao := round(greatest(public.agenda_du_entre(p_hoje, v_prazo), 0) / v_dias_re, 2);
  end if;

  -- ── Execução: parada = em andamento sem diária ligada nos últimos parada_du úteis e sem janela futura ──
  if so.status = 'in_progress' then
    select max(ws.data) into v_ult_diaria
      from public.work_shifts ws
     where ws.data <= p_hoje and ws.tipo in ('normal', 'diaria') and coalesce(ws.fracao, 1) > 0
       and (ws.service_order_id = p_so_id
            or exists (select 1 from public.work_shift_os x where x.shift_id = ws.id and x.service_order_id = p_so_id));
    v_parada := (v_ult_diaria is null or v_ult_diaria < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false;
  end if;
  -- FASE 2: (1) a evidência de que a OS andou é a maior entre a última diária ligada, o último meio-dia do plano
  -- cumprido ou parcial e o check-in; (2) com dia no plano de hoje em diante a OS em andamento nunca é parada.
  v_plano := public._agenda_plano_da_os(p_so_id, p_hoje);
  v_tem_futuro := coalesce((v_plano ->> 'proximo_dia')::date >= p_hoje, false);
  v_ult_evid := public._agenda_ultima_evidencia(p_so_id, p_hoje);
  if so.status = 'in_progress' then
    v_parada := (v_ult_evid is null or v_ult_evid < public.agenda_somar_du(p_hoje, -c.parada_du))
                and coalesce(v_ag_ate >= p_hoje, false) is false
                and not v_tem_futuro;
  end if;
  -- FASE 2: fim

  -- ── Restrições: {tipo, quem, texto, bloqueia, desde, compre_ate, pergunta} ──
  if so.status = 'draft' and so.quote_status = 'approved' and so.merged_into_id is null then
    v_r := v_r || jsonb_build_object('tipo', 'orcamento', 'quem', 'dono', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', 'converter em OS ou arquivar?',
      'texto', format('%s em %s e nunca virou OS: converter ou arquivar?',
                      case when so.signed_at is not null then 'assinado' else 'aprovado' end, to_char(v_aprov, 'DD/MM')));
  end if;
  if (so.quote_status = 'awaiting_deposit' and v_pago = 0) or v_pend > 0 then
    v_r := v_r || jsonb_build_object('tipo', 'sinal', 'quem', 'cliente', 'bloqueia', true, 'desde', v_aprov,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_pend > 0 then 'esperando o sinal de ' || public._brl(v_pend) else 'esperando o sinal' end);
  end if;
  if so.status = 'awaiting_client' then
    v_r := v_r || jsonb_build_object('tipo', 'cliente', 'quem', 'cliente', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', null, 'texto', 'esperando o cliente');
  end if;
  if p.escopo_em_aberto is not null then
    v_r := v_r || jsonb_build_object('tipo', 'escopo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', p.escopo_em_aberto, 'texto', p.escopo_em_aberto);
  end if;
  if p.dias is null then
    v_r := v_r || jsonb_build_object('tipo', 'duracao', 'quem', 'dono', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', 'quantos dias e com quem?',
      'texto', case when coalesce((v_sug ->> 'sem_base')::boolean, false)
                    then 'quantos dias e com quem? (o orçamento não dá base para estimar)'
                    else format('quantos dias e com quem? (chute: %s, %s)',
                                public._agenda_faixa_dias((v_sug ->> 'dias_otimista')::numeric, (v_sug ->> 'dias_realista')::numeric),
                                case when (v_sug ->> 'pessoas')::int = 1 then '1 pessoa'
                                     else (v_sug ->> 'pessoas') || ' pessoas' end) end);
  end if;
  -- Com peça embutida em aberto, a pergunta dela já é o "tem peça a comprar?" (mais precisa): não repete.
  if v_n_itens = 0 and not v_conferido and jsonb_array_length(v_embut) = 0 then
    v_r := v_r || jsonb_build_object('tipo', 'material_nao_conferido', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', 'tem peça a comprar?', 'texto', 'tem peça a comprar? (o orçamento não tem nenhuma)');
  end if;
  v_n := jsonb_array_length(v_embut);
  if v_n > 0 then
    v_txt := array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' ou ')
             || case when v_n > 2 then format(' (e mais %s)', v_n - 2) else '' end;
    v_r := v_r || jsonb_build_object('tipo', 'peca_embutida', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null, 'pergunta', format('tem peça embutida em %s?', v_txt),
      'texto', format('tem peça embutida em %s?', v_txt));
  end if;

  -- O que falta comprar: sem fornecedor/classe (E) pergunta "de quem e quando?"; com classe e sem compra combinada,
  -- "compre até" (programação para trás; se já passou, "comprando hoje, chega por volta de …"). A compra que o dono já
  -- combinou (dia que ainda não passou) sem prazo conhecido NÃO volta a perguntar "de quem e quando": vai à parte.
  select count(*) filter (where e ->> 'situacao' = 'falta'
                          and (((e ->> 'sem_data')::boolean and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
                               or e ->> 'compre_ate' is not null)),
         count(*) filter (where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean
                          and coalesce((e ->> 'compra_prevista_em')::date < p_hoje, true))
    into v_n_falta, v_n_sem
    from jsonb_array_elements(v_crit) e;
  if v_n_falta > 0 then
    select e into v_compra from jsonb_array_elements(v_crit) with ordinality t(e, o)
     where e ->> 'situacao' = 'falta' and e ->> 'compre_ate' is not null
     order by (e ->> 'compre_ate')::date, o limit 1;
    v_cond := case when v_compra is null then ''
                   when (v_compra ->> 'compre_ate')::date < p_hoje then
                     format('comprando hoje, "%s" chega por volta de %s', v_compra ->> 'curto',
                            -- FASE 4: a chegada "comprando hoje" pelo mesmo prazo do fornecedor (o importado em corridos).
                            public._dia_curto(public._agenda_chegada_pela_classe(v_compra ->> 'classe', (v_compra ->> 'prazo_du')::int,
                                                                                 (v_compra ->> 'corridos')::int, p_hoje)))
                            -- FASE 4: fim
                   else format('"%s": compre até %s', v_compra ->> 'curto',
                               public._dia_curto((v_compra ->> 'compre_ate')::date)) end;
    if v_n_sem > 0 then
      v_txt := case when so.status = 'awaiting_parts' then public._agenda_itens(v_n_falta) || ' sem compra registrada'
                    else public._agenda_itens(v_n_falta) || ' a comprar: de quem e quando?' end;
      v_r := v_r || jsonb_build_object('tipo', 'sem_previsao', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate',
        'pergunta', case when so.status = 'awaiting_parts' then 'o que já está na mão e o que falta? Quando chega?'
                         else format('o material (%s) — compra quando e onde?', public._agenda_itens(v_n_falta)) end,
        'texto', v_txt || case when v_cond <> '' then ' (' || v_cond || ')' else '' end);
    else
      v_r := v_r || jsonb_build_object('tipo', 'compre_ate', 'quem', 'dono', 'bloqueia', true, 'desde', null,
        'compre_ate', v_compra ->> 'compre_ate', 'pergunta', 'compra quando?',
        'texto', public._agenda_itens(v_n_falta) || ' a comprar: ' || v_cond);
    end if;
  end if;

  -- Compra combinada ("compro terça na Casa do Eletricista") sem prazo de entrega conhecido: o que o dono já disse fica
  -- dito; a pergunta é só o que falta — quando chega (com fornecedor) ou de quem (sem).
  select count(*) as n, min((e ->> 'compra_prevista_em')::date) as de, max((e ->> 'compra_prevista_em')::date) as ate,
         bool_and(e ->> 'fornecedor' is not null) as com_forn, count(distinct e ->> 'fornecedor') as n_forn,
         min(e ->> 'fornecedor') as forn, min(e ->> 'curto') as curto
    into v_cc
    from jsonb_array_elements(v_crit) e
   where e ->> 'situacao' = 'falta' and (e ->> 'sem_data')::boolean and (e ->> 'compra_prevista_em')::date >= p_hoje;
  if v_cc.n > 0 then
    v_txt := case when v_cc.de = v_cc.ate then public._dia_curto(v_cc.de)
                  else format('de %s a %s', public._dia_curto(v_cc.de), public._dia_curto(v_cc.ate)) end;
    v_r := v_r || jsonb_build_object('tipo', 'compra_sem_prazo', 'quem', 'dono', 'bloqueia', true, 'desde', null,
      'compre_ate', null,
      'pergunta', case when v_cc.com_forn then format('quando chega a compra de %s?', v_txt)
                       else format('de quem é a compra de %s?', v_txt) end,
      'texto', case when v_cc.n = 1 then format('"%s"', v_cc.curto) else public._agenda_itens(v_cc.n::int) end
               || ': você compra ' || v_txt
               || case when v_cc.com_forn and v_cc.n_forn = 1 then ', fornecedor ' || v_cc.forn else '' end
               || case when v_cc.com_forn then '; sem prazo de entrega conhecido: quando chega?'
                       else '; de quem? (sem o fornecedor não sei quando chega)' end);
  end if;

  -- Comprado sem previsão e sem classe: "chegou?"; previsão vencida: "venceu em dd/mm: chegou?".
  for v_x in select e from jsonb_array_elements(v_crit) with ordinality t(e, o)
              where e ->> 'situacao' in ('comprado', 'a_caminho')
                and ((e ->> 'sem_data')::boolean or (e ->> 'atrasado')::boolean)
              order by o
  loop
    if (v_x ->> 'atrasado')::boolean then
      v_r := v_r || jsonb_build_object('tipo', 'atrasado', 'quem', 'dono', 'bloqueia', true, 'desde', v_x ->> 'data',
        'compre_ate', null, 'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('a previsão de "%s" venceu em %s: chegou?', v_x ->> 'curto', to_char((v_x ->> 'data')::date, 'DD/MM')));
    else
      v_r := v_r || jsonb_build_object('tipo', 'comprado_sem_previsao', 'quem', 'dono', 'bloqueia', true,
        'desde', v_x ->> 'comprado_em', 'compre_ate', null,
        'pergunta', format('"%s" chegou?', v_x ->> 'curto'),
        'texto', format('"%s" (%s) chegou?', v_x ->> 'curto',
                        coalesce('pedido em ' || to_char((v_x ->> 'comprado_em')::date, 'DD/MM'), 'comprado, sem previsão')));
    end if;
  end loop;

  if v_d_bem is null or v_d_bem > p_hoje + 1 then
    v_r := v_r || jsonb_build_object('tipo', 'bem', 'quem', 'cliente', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                    else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end);
  end if;
  if p.nao_antes_de is not null and p.nao_antes_de > p_hoje then
    v_r := v_r || jsonb_build_object('tipo', 'nao_antes', 'quem', 'terceiro', 'bloqueia', false, 'desde', null,
      'compre_ate', null, 'pergunta', null,
      'texto', format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo));
  end if;
  if v_parada then
    v_r := v_r || jsonb_build_object('tipo', 'parada', 'quem', 'dono', 'bloqueia', true, 'desde', v_ult_diaria,
      'compre_ate', null, 'pergunta', 'parou?',
      'texto', case when v_ult_diaria is null then 'em andamento e sem diária lançada: parou?'
                    else format('em andamento sem diária desde %s: parou?', to_char(v_ult_diaria, 'DD/MM')) end);
  end if;

  -- Orçamento aprovado que nunca virou OS, ou sinal pendente: quem destrava é a conversão (o dono) ou o sinal (o
  -- cliente), não a compra — comprar peça de um orçamento que pode ser arquivado não é o próximo passo. As perguntas do
  -- material continuam na lista (a visão da OS e a rodada mostram), sem travar até a conversão e o sinal.
  if exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'sinal')) then
    select coalesce(jsonb_agg(case when e ->> 'tipo' in ('atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao',
                                                         'compre_ate', 'peca_embutida', 'material_nao_conferido')
                                   then jsonb_set(e, '{bloqueia}', 'false'::jsonb) else e end order by o), '[]'::jsonb)
      into v_r
      from jsonb_array_elements(v_r) with ordinality t(e, o);
  end if;

  -- A mais forte primeiro: o que trava antes do que só informa, e na ordem do bloco "travado" (spec §5.4).
  select coalesce(jsonb_agg(e order by (e ->> 'bloqueia')::boolean desc,
           array_position(array['parada', 'atrasado', 'sem_previsao', 'compra_sem_prazo', 'comprado_sem_previsao', 'compre_ate',
                                'peca_embutida', 'material_nao_conferido', 'orcamento', 'escopo', 'sinal', 'cliente',
                                'duracao', 'bem', 'nao_antes'], e ->> 'tipo'), o), '[]'::jsonb)
    into v_r
    from jsonb_array_elements(v_r) with ordinality t(e, o);

  -- ── Estado (o 1º que valer) ──
  v_estado := case
    when p.congelada_ate is not null and p.congelada_ate >= p_hoje then 'congelada'
    when so.status in ('completed', 'invoiced') then 'concluida'
    when so.status = 'cancelled' or so.merged_into_id is not null
         or (so.status = 'draft' and coalesce(so.quote_status, 'draft') not in ('approved', 'awaiting_deposit')) then 'fora_da_carteira'
    when so.status = 'in_progress' then case when v_parada then 'parada' else 'em_execucao' end
    when coalesce(v_ag_ate, v_ag_de) >= p_hoje then 'marcada'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
    when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
    when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
    when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
    else 'pronta' end;
  -- FASE 2: (3) os estados do plano: fixada e programada vêm depois de em execução/parada e antes de marcada; com a
  -- agenda automática ligada a janela antiga é o espelho do plano, e "marcada" não vale (o estado vem das alocações).
  if v_estado not in ('congelada', 'concluida', 'fora_da_carteira', 'em_execucao', 'parada') then
    if coalesce((v_plano ->> 'fixada')::boolean, false) then
      v_estado := 'fixada';
    elsif v_tem_futuro then
      v_estado := 'programada';
    elsif v_estado = 'marcada' and c.modo_proposta = 'ligado' then
      v_estado := case
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal') then 'sem_sinal'
        when so.status = 'awaiting_client' or v_bem_tudo or p.nao_antes_de > v_horizonte then 'aguardando_cliente'
        when exists (select 1 from jsonb_array_elements(v_r) e where e ->> 'tipo' in ('orcamento', 'escopo')) then 'esperando_voce'
        when v_mat_estado in ('nao_conferido', 'sem_previsao', 'atrasado') then 'aguardando_material'
        else 'pronta' end;
    end if;
  end if;
  -- FASE 2: fim

  if v_estado in ('concluida', 'fora_da_carteira') and (so.status in ('completed', 'invoiced', 'cancelled')
                                                         or so.merged_into_id is not null) then
    v_r := '[]'::jsonb;
  end if;

  -- A restrição do dono que mais pesa (a 1ª da lista que trava e é dele).
  select e into v_principal from jsonb_array_elements(v_r) with ordinality t(e, o)
   where (e ->> 'bloqueia')::boolean and e ->> 'quem' = 'dono' order by o limit 1;

  v_quase := v_estado = 'aguardando_material'
         and (select count(*) from jsonb_array_elements(v_r) e where (e ->> 'bloqueia')::boolean) = 1
         and v_principal ->> 'tipo' = 'material_nao_conferido';

  -- O texto do estado, para vir depois do nome do cliente ("Lenine: falta você dizer se tem peça a comprar").
  v_estado_txt := case v_estado
    -- "(rever …)" só quando o dia de rever não é o mesmo do fim da espera (é o padrão do rascunho).
    when 'congelada' then 'em espera até ' || public._dia_curto(p.congelada_ate)
                          || case when p.revisar_em is distinct from p.congelada_ate
                                  then coalesce(' (rever ' || public._dia_curto(p.revisar_em) || ')', '') else '' end
    when 'concluida' then case so.status when 'invoiced' then 'faturado' else 'concluído' end
    when 'fora_da_carteira' then public._agenda_rotulo_os(so.status, so.quote_status, so.signed_at is not null, so.juntado_em, false)
    when 'em_execucao' then 'em andamento'
    when 'parada' then case when v_ult_diaria is null then 'em andamento e sem diária lançada'
                            else 'em andamento sem diária desde ' || to_char(v_ult_diaria, 'DD/MM') end
    when 'marcada' then case when v_ag_de is null or v_ag_de = v_ag_ate then 'marcado para ' || public._dia_curto(coalesce(v_ag_ate, v_ag_de))
                             else format('marcado de %s a %s', public._dia_curto(v_ag_de), public._dia_curto(v_ag_ate)) end
    when 'sem_sinal' then (select e ->> 'texto' from jsonb_array_elements(v_r) e where e ->> 'tipo' = 'sinal' limit 1)
    when 'aguardando_cliente' then case
      when so.status = 'awaiting_client' then 'esperando o cliente'
      when v_bem_tudo then case when v_d_bem is null then v_bem_nome || ' está fora, sem data para voltar'
                                else v_bem_nome || ' só fica livre ' || public._dia_curto(v_d_bem) end
      else format('não antes de %s: %s', public._dia_curto(p.nao_antes_de), p.nao_antes_motivo) end
    -- O orçamento parado vem antes do escopo em aberto (a ordem do bloco "travado").
    when 'esperando_voce' then case
      when so.status = 'draft' and so.quote_status = 'approved'
        then format('%s em %s e nunca virou OS', case when so.signed_at is not null then 'assinado' else 'aprovado' end,
                    to_char(v_aprov, 'DD/MM'))
      else 'falta você decidir: ' || p.escopo_em_aberto end
    when 'aguardando_material' then case v_principal ->> 'tipo'
      when 'atrasado' then 'falta você dizer se ' || replace(v_principal ->> 'pergunta', ' chegou?', '') || ' chegou (a previsão venceu)'
      when 'sem_previsao' then case when so.status = 'awaiting_parts'
                                    then format('falta você dizer o que já está na mão e o que falta (%s sem compra registrada)',
                                                public._agenda_itens(v_n_falta))
                                    else 'falta você dizer de quem e quando comprar ' || public._agenda_itens(v_n_falta) end
      when 'comprado_sem_previsao' then 'falta você dizer se ' || replace(v_principal ->> 'texto', ' chegou?', '') || ' chegou'
      when 'compra_sem_prazo' then 'falta você dizer ' || rtrim(v_principal ->> 'pergunta', '?')
      when 'peca_embutida' then 'falta você dizer se tem peça embutida em '
                                || array_to_string(array(select format('"%s"', e ->> 'curto')
                                     from jsonb_array_elements(v_embut) with ordinality t(e, o) where o <= 2 order by o), ' e ')
                                || case when jsonb_array_length(v_embut) > 2
                                        then format(' (e mais %s)', jsonb_array_length(v_embut) - 2) else '' end
      else 'falta você dizer se tem peça a comprar' end
    else -- pronta
      case when v_est is not null and v_est > public.agenda_somar_du(p_hoje, 1) then
             'pronto a partir de ' || public._dia_curto(v_est)
             || case when v_inicio_mat is not null and v_inicio_mat >= v_est_sm then
                  (select case
                        when e ->> 'nivel' in ('B', 'C') then format(', se "%s" chegar %s', e ->> 'curto', public._dia_curto(v_dpm))
                        when e ->> 'situacao' = 'falta' and e ->> 'compra_prevista_em' is not null
                             and (e ->> 'compra_prevista_em')::date >= p_hoje
                          then ', se a compra sair ' || public._dia_curto((e ->> 'compra_prevista_em')::date)
                        when e ->> 'situacao' = 'falta' then ', se comprar hoje'
                        else format(', se "%s" chegar por volta de %s', e ->> 'curto', public._dia_curto(v_dpm)) end
                        from jsonb_array_elements(v_crit) with ordinality t(e, o)
                       where e ->> 'nivel' <> 'A' and (e ->> 'data')::date = v_dpm order by o limit 1)
                else '' end
           else 'pronto para começar' end
  end;
  -- FASE 2: o texto dos estados do plano ("marcado de ter 03/11 a qui 05/11", "(fixado)" quando é fixo).
  if v_estado in ('fixada', 'programada') then
    v_estado_txt := case when (v_plano ->> 'proximo_dia') = (v_plano ->> 'ultimo_dia')
                         then 'marcado para ' || public._dia_curto((v_plano ->> 'proximo_dia')::date)
                         else format('marcado de %s a %s', public._dia_curto((v_plano ->> 'proximo_dia')::date),
                                     public._dia_curto((v_plano ->> 'ultimo_dia')::date)) end
                    || case when v_estado = 'fixada' then ' (fixado)' else '' end;
  end if;
  -- FASE 2: fim

  -- FASE 2: (4) a saída ganha o plano (null sem alocação) e a última evidência; ultima_diaria continua.
  return jsonb_build_object('plano', v_plano, 'ultima_evidencia', v_ult_evid) || jsonb_build_object(
  -- FASE 2: fim
    'ok', true, 'os', so.id, 'numero', so.service_order_number, 'cliente', so.cliente_nome,
    'cliente_curto', public._agenda_nome_curto(so.cliente_nome), 'unidade', so.bem,
    'eh_orcamento', so.status = 'draft', 'status', so.status, 'quote_status', so.quote_status,
    'na_carteira', v_na_cart, 'aprovada_em', v_aprov,
    'estado', v_estado, 'estado_texto', v_estado_txt, 'quase_pronta', v_quase,
    'restricoes', v_r,
    'material', jsonb_build_object(
      'estado', v_mat_estado, 'itens', v_itens, 'dpm', v_dpm,
      'gargalo', (select e ->> 'descricao' from jsonb_array_elements(v_crit) with ordinality t(e, o)
                   where e ->> 'nivel' <> 'A' and v_dpm is not null and (e ->> 'data')::date = v_dpm order by o limit 1),
      'confianca', v_confianca, 'inicio_mat', v_inicio_mat, 'embutidas', v_embut,
      'conferido_em', p.material_conferido_em),
    'duracao', v_dur,
    'presenca_dono', v_pres,
    'est', v_est, 'est_texto', public._dia_curto(v_est), 'est_sem_material', v_est_sm,
    'prazo_efetivo', v_prazo, 'prazo_texto', public._dia_curto(v_prazo), 'prazo_fonte', v_prazo_fnt,
    'razao_critica', v_razao,
    'marcada', case when v_ag_de is not null or v_ag_ate is not null
                    then jsonb_build_object('de', v_ag_de, 'ate', v_ag_ate) end,
    'ultima_diaria', v_ult_diaria);
end;
$function$;

comment on function public.os_prontidao(uuid, date) is
  'Agenda de Produção (Fase 1, P3; Fase 2, P2; Fase 4, P2: a linha de OC recebida ligada a um item de texto livre da conta conta só nele, não de novo como item da OC que já chegou; Fase 4, P1: o prazo de cada item é o do fornecedor — _agenda_prazo_do_fornecedor, com o que o dono disse, o cadastro repetido, o nome e a cidade tolerante ao caractere quebrado; o importado conta em dias corridos; o item ganha prazo_texto, duvida e corridos; o texto livre é coberto pela linha da OC ligada a ele): a prontidão de uma OS em p_hoje. Estado (o 1º que valer): congelada → concluida → fora_da_carteira → em_execucao/parada → fixada/programada (Fase 2: tem meio-dia vigente de hoje em diante, fixado ou publicado) → marcada (a janela antiga; só fora de modo_proposta ligado) → sem_sinal → aguardando_cliente → esperando_voce → aguardando_material → pronta. Parada (Fase 2) = em andamento, sem evidência (diária ligada, meio-dia cumprido/parcial ou check-in) há parada_du dias úteis e sem dia no plano. Restrições {tipo, quem (dono|cliente|terceiro), texto, bloqueia, desde, compre_ate, pergunta}, a mais forte primeiro. Material efetivo = conta bruta + fato informado em os_material, níveis A (na mão, quantidade completa) / B (previsão do fornecedor, nota, OC, Pix) / C (previsão do dono) / D (sem previsão: comprado em + prazo da classe, ou "se comprar hoje") / E (sem fornecedor nem classe); "material não conferido" com zero itens ou peça embutida em aberto; dpm, início pelo material (chegada + folga_material_du, sem folga remota), est, compre até para trás, prazo efetivo (precisa_ate ou aprovação + prazo_padrao_du) e razão crítica. Saída também com plano (_agenda_plano_da_os; null sem alocação), ultima_evidencia e ultima_diaria. Também aceita OS fora da carteira.';


revoke all on function public.os_prontidao(uuid, date) from public, anon;
grant execute on function public.os_prontidao(uuid, date) to authenticated, service_role;


-- ── 7. A R7 não cobra o que a agenda já acompanha ──────────────────────────────────────────────────────────

create or replace function public.agenda_ocs_com_material_vivo(p_po_ids uuid[])
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  with
  ocs as (
    select distinct x.po_id from unnest(coalesce(p_po_ids, '{}'::uuid[])) as x(po_id) where x.po_id is not null
  ),
  -- As linhas de material de cada OC: a do item de texto livre da própria OC (origem oc) e a da linha da OS que o item
  -- compra (o vínculo de linha da Fase 4: texto livre ou peça).
  linhas as (
    select distinct o.po_id, m.id, m.situacao,
           exists (select 1 from public.agenda_perguntas p
                    where p.tipo = 'chegou' and p.estado = 'aberta' and p.modo = 'ligado' and p.os_material_id = m.id)
             as pergunta_viva
      from ocs o
      join public.purchase_order_items poi on poi.purchase_order_id = o.po_id
      join public.os_material m
        on (m.origem = 'oc' and m.purchase_order_item_id = poi.id)
        or (m.origem = 'texto_livre' and poi.service_order_service_id is not null
            and m.service_order_service_id = poi.service_order_service_id)
        or (m.origem = 'peca' and poi.service_order_part_id is not null
            and m.service_order_part_id = poi.service_order_part_id)
  ),
  motivos as (
    select l.po_id,
           case when bool_or(l.pergunta_viva) then 'a agenda já pergunta se chegou'
                when bool_and(l.situacao = 'na_mao') then 'a agenda registrou que chegou' end as motivo
      from linhas l
     group by l.po_id
  )
  select coalesce(jsonb_object_agg(m.po_id, m.motivo) filter (where m.motivo is not null), '{}'::jsonb)
    from motivos m;
$function$;

comment on function public.agenda_ocs_com_material_vivo(uuid[]) is
  'Agenda de Produção (Fase 4, P2): para a R7 (cobrar a entrega da OC), {<po_id>: motivo} das OCs cujo material a agenda já acompanha: alguma linha de material da OC com a pergunta "chegou?" aberta em ligado ("a agenda já pergunta se chegou") ou todas as linhas na mão ("a agenda registrou que chegou"). As linhas de uma OC: a do item de texto livre (os_material origem oc) e a da linha da OS que o item compra (purchase_order_items.service_order_service_id/service_order_part_id). OC sem linha de material não entra. Só service_role (o motor).';

revoke all on function public.agenda_ocs_com_material_vivo(uuid[]) from public, anon, authenticated;
grant execute on function public.agenda_ocs_com_material_vivo(uuid[]) to service_role;
