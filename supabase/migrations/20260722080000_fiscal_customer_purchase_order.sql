-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: pedido de compra do CLIENTE (ordem de compra + comprador)
--
-- Antes, a referência do pedido do cliente só existia como texto solto digitado
-- no campo de informações complementares da NF-e: saía misturada no meio das
-- declarações do contribuinte, se perdia ao faturar uma OS/orçamento e não era
-- pesquisável. Estas colunas guardam o dado de forma estruturada:
--
--   service_orders            → capturado na OS/orçamento e levado à emissão
--   issued_fiscal_documents   → gravado na nota (restaura ao duplicar/reemitir
--                               sem depender de parsing do texto, e permite
--                               responder "qual nota é do pedido 05447?")
--
-- Mesmo padrão de metadado do app fora do request_payload já usado por
-- source_items e payment_terms. Aditiva e reversível (nenhum dado é alterado).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.issued_fiscal_documents
  ADD COLUMN IF NOT EXISTS customer_po_number  text,
  ADD COLUMN IF NOT EXISTS customer_buyer_name text;

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS customer_po_number  text,
  ADD COLUMN IF NOT EXISTS customer_buyer_name text;

COMMENT ON COLUMN public.issued_fiscal_documents.customer_po_number IS
  'Ordem de compra do cliente (NF-e: xPed, 15 caract.). Sai no início do infCpl.';
COMMENT ON COLUMN public.issued_fiscal_documents.customer_buyer_name IS
  'Nome do comprador do cliente. Sai no início do infCpl, junto do pedido.';
COMMENT ON COLUMN public.service_orders.customer_po_number IS
  'Ordem de compra do cliente, capturada na OS/orçamento e levada à emissão da NF-e.';
COMMENT ON COLUMN public.service_orders.customer_buyer_name IS
  'Comprador informado pelo cliente; default do campo Comprador na emissão da NF-e.';
