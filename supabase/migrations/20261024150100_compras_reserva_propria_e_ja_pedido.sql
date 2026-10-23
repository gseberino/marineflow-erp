-- Compras: reserva própria, "já pedido" honesto e o que vem a caminho por OC de texto livre (C1, C2 e item 16).
-- Agenda de Produção, Fase 0, pacote P5 (passo 2). Spec: scratchpad agenda-pesquisa/spec-fase0.md (§2.5-§2.7).
-- Depende de 20261024150000 (count_purchase_shortages versionada, que chama esta função).
--
-- ═══ DDL — OK NOMEADO ═══ (uma view nova e CREATE OR REPLACE de get_os_purchase_needs, mesma assinatura;
-- não grava dado)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- O QUE MUDA:
--   1. View v_oc_itens_a_caminho: o que ainda vai entregar, em UM lugar só. Traz toda linha de OC em
--      draft/sent/partial, e a coluna conta_como_ja_pedido diz se ela abate a falta de catálogo: OC criada
--      há menos de 60 dias corridos, sem OS ou com a OS ainda viva (fora de completed/invoiced/cancelled).
--      Antes, toda OC aberta contava, de qualquer idade e de OS faturada: a OC-00001 (84 dias, OS-00073
--      faturada) abateria a falta de outra OS se tivesse produto. O 60 é o dobro da maior espera aberta
--      medida (19 d), dentro dos prazos ditos de 2 a 60 d; a Fase 1 pode levá-lo para agenda_config.
--      A tela (src/hooks/use-purchase-needs.ts) lê a MESMA view: o número existe uma vez.
--      POR QUE A IDADE É COLUNA E NÃO FILTRO (revisão de 23/10): o corte só é seguro no "já pedido" de
--      catálogo, onde tirar a OC velha faz a falta voltar a aparecer. Na linha de texto livre da própria
--      OS (item 3) ele faria o contrário: a linha tem falta 0 e não abate nada, então o corte só a
--      esconderia. A OC-00004 (rascunho de 13/10) sairia da view em 12/12, a OS-00104 ficaria sem linha
--      nenhuma e pareceria pronta com o compressor ainda no fornecedor. O "a caminho" da própria OS não
--      tem idade.
--   2. get_os_purchase_needs desconta a reserva DA PRÓPRIA OS do reservado (C1). O estoque v2 reserva a
--      peça quando a OS é comprometida, e a conta tirava essa reserva do disponível da própria OS: com
--      1 no físico reservado para ela mesma, a OS dizia que faltava. Agora o reservado é
--      greatest(reservado − reserva desta OS, 0), e a reserva desta OS só conta se o status dela estiver
--      na MESMA lista de recompute_product_reservations (20260724220000_stock_v2_status_sets_fix.sql).
--      'open' não reserva (NOVO-agenda-01, registrado e não corrigido aqui). A lista é cobrada contra a
--      do TS por src/test/status-que-reservam.test.ts.
--   3. get_os_purchase_needs anexa a "items" as linhas de TEXTO LIVRE ainda não recebidas de OC da própria
--      OS, como origin 'purchase_order', status 'on_order', shortage 0 e purchaseOrderNumber. Caso real:
--      a OS-00104 só tem o compressor na OC-00004 (rascunho, "Compressor 12V de geladeira SS65", 0 de 1
--      recebido). Com a "conversão" virando serviço (150200), a OS ficaria sem nenhuma linha de material e
--      pareceria pronta. Assim a falta cai para 0 (o R16 fecha) e o compressor continua visível como
--      "pedido na OC-00004 — chegou?". shortages, shortageCount, estimatedCost e needsPurchase NÃO mudam.
--
-- O QUE NÃO MUDA: compute_purchase_needs (a fórmula pura; trocar a assinatura criaria sobrecarga ambígua),
-- as linhas de peça e de texto livre que entram nela, a ordem por (created_at, id) e a assinatura e a ACL
-- de get_os_purchase_needs.
--
-- EFEITO MEDIDO NA CARTEIRA (simulação só de leitura, f16_simula_p5, 23/10/2026, junto com 150200):
--   OS-00104 faltas 1 → 0 e 1 item a caminho; nenhuma outra OS muda (OS-00069 4, OS-00076 1, OS-00112 4,
--   ORÇ-00083 2; as demais 0).
--
-- ORDEM DE LIGAR: aplicar ANTES de o front ir para a main e ser publicado. O hook lê a view;
-- sem ela o PostgREST responde 404 (PGRST205) e o hook lança. Até a revisão de 23/10 esse erro era engolido
-- pela tela: o diálogo dizia "Tudo disponível para executar" e a faixa da OS sumia. Agora o diálogo diz
-- "Não consegui conferir o estoque" e a faixa mostra uma linha de erro; o NewQuoteRequestDialog continua
-- abrindo com a linha em branco, sem o preenchimento automático. O agente funciona com ou sem.
--
-- PROVA (depois de aplicar): supabase/tests/purchase_needs_reserva_e_a_caminho.sql (begin/rollback) e
-- supabase/tests/purchase_needs_parity.sql (regressão da fórmula pura).
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 150000 e antes de 150200):
--   npx supabase db query --linked -f supabase/migrations/20261024150100_compras_reserva_propria_e_ja_pedido.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024150100', 'compras_reserva_propria_e_ja_pedido');"

-- ── 1. O "já pedido" em um lugar só ─────────────────────────────────────────────────────────────────────

create or replace view public.v_oc_itens_a_caminho with (security_invoker = on) as
select poi.id as purchase_order_item_id,
       poi.purchase_order_id,
       po.po_number,
       po.status as po_status,
       po.service_order_id,
       po.created_at as po_criada_em,
       po.expected_date,
       poi.product_id,
       poi.description,
       poi.quantity,
       poi.received_qty,
       poi.unit_cost,
       greatest(poi.quantity - coalesce(poi.received_qty, 0), 0) as pendente,
       -- Abate a falta de catálogo (o "já pedido")? Só OC viva: recente e sem OS encerrada. NÃO filtra a
       -- view: o "a caminho" de texto livre da própria OS vale com qualquer idade (item 1 do cabeçalho).
       (po.created_at >= now() - interval '60 days'          -- o único "60" do sistema (spec §2.6)
        and (po.service_order_id is null
             or coalesce(so.status not in ('completed', 'invoiced', 'cancelled'), false))) as conta_como_ja_pedido
  from public.purchase_order_items poi
  join public.purchase_orders po on po.id = poi.purchase_order_id
  left join public.service_orders so on so.id = po.service_order_id
 where po.status in ('draft', 'sent', 'partial');

comment on view public.v_oc_itens_a_caminho is
  'Itens de OC que ainda vao entregar: OC draft/sent/partial, de qualquer idade. conta_como_ja_pedido = OC criada ha menos de 60 dias, sem OS ou com a OS viva (fora de completed/invoiced/cancelled): so essas abatem a falta de catalogo (o "ja pedido"). O "a caminho" de texto livre da propria OS nao corta idade. Fonte unica de get_os_purchase_needs e de src/hooks/use-purchase-needs.ts. pendente = quantidade - recebido. security_invoker: a RLS de compras (admin/financeiro) vale para quem le.';

-- authenticated sai junto e volta só com select: o privilégio padrão do Supabase daria ALL a ele.
revoke all on public.v_oc_itens_a_caminho from public, anon, authenticated;
grant select on public.v_oc_itens_a_caminho to authenticated, service_role;

-- ── 2 e 3. get_os_purchase_needs: reserva própria, "já pedido" pela view e itens a caminho ──────────────

create or replace function public.get_os_purchase_needs(p_so_id uuid)
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
  )
  select jsonb_set(n.r, '{items}', coalesce(n.r -> 'items', '[]'::jsonb) || a.itens)
    from necessidade n, a_caminho a;
$function$;

comment on function public.get_os_purchase_needs(uuid) is
  'Necessidade LIQUIDA de compra de uma OS (falta = necessario - disponivel - ja pedido). Espelha src/lib/purchase-needs.ts + src/hooks/use-purchase-needs.ts; e a via do agente de IA. Ordem deterministica por (created_at, id). Desde 24/10/2026: (1) o reservado e o de OUTRAS OS (a reserva desta sai, se o status dela reserva); (2) o ja pedido vem de v_oc_itens_a_caminho com conta_como_ja_pedido (OC viva, < 60 dias); (3) as linhas de texto livre de OC desta OS ainda nao recebidas, de qualquer idade, entram em items como on_order (origin purchase_order, shortage 0), sem mudar shortages, shortageCount, estimatedCost nem needsPurchase.';

revoke all on function public.get_os_purchase_needs(uuid) from public, anon;
grant execute on function public.get_os_purchase_needs(uuid) to authenticated, service_role;
