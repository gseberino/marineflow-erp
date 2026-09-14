-- Recuperada do transcript da sessão (C--Users-PC/2d4124b3-a014-48da-8feb-73901aafa6ff.jsonl, 2026-07-27T19:38:59.036Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260727193904 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Correção da view de fatos: valor em pt-BR e exclusão de títulos com saldo zerado.
-- (mesmo conteúdo final do arquivo 20260727180000_entity_open_loops.sql)
CREATE OR REPLACE VIEW public.erp_open_loop_facts AS
SELECT
  'client'::text AS entity_type,
  so.client_id   AS entity_id,
  'so:' || so.id::text AS loop_key,
  'service_order'::text AS kind,
  ('OS ' || so.service_order_number || ' — ' || CASE so.status
      WHEN 'open'           THEN 'aberta'
      WHEN 'approved'       THEN 'aprovada, a agendar'
      WHEN 'scheduled'      THEN 'agendada'
      WHEN 'in_progress'    THEN 'em execução'
      WHEN 'awaiting_parts' THEN 'aguardando peças'
      ELSE so.status END)::text AS title,
  left(coalesce(so.problem_description, ''), 180)::text AS detail,
  'service_orders'::text AS ref_table,
  so.id AS ref_id,
  so.id AS service_order_id,
  so.scheduled_start_at AS due_at,
  (CASE WHEN so.status = 'awaiting_parts' THEN 'high' ELSE 'normal' END)::text AS priority
FROM public.service_orders so
WHERE so.client_id IS NOT NULL
  AND so.status IN ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts')

UNION ALL

SELECT
  'client'::text,
  so.client_id,
  'so-parts:' || so.id::text,
  'delivery'::text,
  ('Materiais da OS ' || so.service_order_number || ' a receber')::text,
  (count(DISTINCT poi.id)::text || ' item(ns) pendente(s): ' ||
   left(string_agg(DISTINCT coalesce(poi.description, 'item'), ', '), 150))::text,
  'purchase_orders'::text,
  (array_agg(po.id ORDER BY po.expected_date NULLS LAST, po.id))[1],
  so.id,
  min((po.expected_date::timestamp AT TIME ZONE 'America/Sao_Paulo')),
  (CASE WHEN min(po.expected_date) < current_date THEN 'high' ELSE 'normal' END)::text
FROM public.purchase_orders po
JOIN public.service_orders so ON so.id = po.service_order_id
JOIN public.purchase_order_items poi ON poi.purchase_order_id = po.id
WHERE so.client_id IS NOT NULL
  AND po.received_date IS NULL
  AND coalesce(po.status, '') NOT IN ('cancelled', 'canceled', 'received')
  AND coalesce(poi.received_qty, 0) < poi.quantity
GROUP BY so.id, so.client_id, so.service_order_number

UNION ALL

SELECT
  'client'::text,
  q.client_id,
  'quote:' || q.id::text,
  'quote'::text,
  ('Orçamento ' || coalesce(q.quote_number, '') || ' aguardando resposta do cliente')::text,
  left(coalesce(q.problem_description, ''), 180)::text,
  'external_quotes'::text,
  q.id,
  NULL::uuid,
  (q.quote_validity_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  'normal'::text
FROM public.external_quotes q
WHERE q.client_id IS NOT NULL
  AND q.status IN ('pending_approval', 'pending_product')

UNION ALL

SELECT
  'client'::text,
  r.client_id,
  'ar:' || r.id::text,
  'receivable'::text,
  ((CASE WHEN r.due_date < current_date THEN 'Título VENCIDO ' ELSE 'Título a vencer ' END)
   || 'R$ ' || translate(to_char(coalesce(r.balance_amount, r.amount), 'FM999G999G990D00'), ',.', '.,'))::text,
  left(coalesce(r.description, ''), 180)::text,
  'receivables'::text,
  r.id,
  r.service_order_id,
  (r.due_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN r.due_date < current_date THEN 'urgent' ELSE 'high' END)::text
FROM public.receivables r
WHERE r.client_id IS NOT NULL
  AND r.status = 'pending'
  AND r.due_date <= current_date + 15
  AND coalesce(r.balance_amount, r.amount) > 0

UNION ALL

SELECT
  'supplier'::text,
  po.supplier_id,
  'po:' || po.id::text,
  'purchase_order'::text,
  ('Compra ' || coalesce(po.po_number, '') || ' aguardando entrega')::text,
  left(coalesce(po.notes, ''), 180)::text,
  'purchase_orders'::text,
  po.id,
  po.service_order_id,
  (po.expected_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN po.expected_date < current_date THEN 'high' ELSE 'normal' END)::text
FROM public.purchase_orders po
WHERE po.supplier_id IS NOT NULL
  AND po.received_date IS NULL
  AND coalesce(po.status, '') NOT IN ('cancelled', 'canceled', 'received')

UNION ALL

SELECT
  'supplier'::text,
  p.supplier_id,
  'ap:' || p.id::text,
  'payable'::text,
  ((CASE WHEN p.due_date < current_date THEN 'Pagamento VENCIDO ' ELSE 'Pagamento a vencer ' END)
   || 'R$ ' || translate(to_char(coalesce(p.balance_amount, p.amount), 'FM999G999G990D00'), ',.', '.,'))::text,
  left(coalesce(p.description, ''), 180)::text,
  'payables'::text,
  p.id,
  p.linked_service_order_id,
  (p.due_date::timestamp AT TIME ZONE 'America/Sao_Paulo'),
  (CASE WHEN p.due_date < current_date THEN 'urgent' ELSE 'high' END)::text
FROM public.payables p
WHERE p.supplier_id IS NOT NULL
  AND p.status = 'pending'
  AND p.due_date <= current_date + 15
  AND coalesce(p.balance_amount, p.amount) > 0;
