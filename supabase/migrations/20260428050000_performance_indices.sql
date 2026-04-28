-- Otimização de Performance - Índices
-- Nome: 20260428050000_performance_indices.sql

-- Índices para buscas rápidas em inventário (muito usado no dashboard e OS)
CREATE INDEX IF NOT EXISTS idx_products_sku ON public.products(sku) WHERE active = true;
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category) WHERE active = true;

-- Índices para movimentos de estoque (acelera relatórios históricos)
CREATE INDEX IF NOT EXISTS idx_inv_movements_product_date ON public.inventory_movements(product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inv_movements_fiscal_note ON public.inventory_movements(fiscal_note_id);

-- Índices para o financeiro
CREATE INDEX IF NOT EXISTS idx_payables_supplier_status ON public.payables(supplier_id, status);
CREATE INDEX IF NOT EXISTS idx_receivables_client_status ON public.receivables(client_id, status);
CREATE INDEX IF NOT EXISTS idx_payments_date ON public.payments(payment_date DESC);

-- Índices para Ordens de Serviço
CREATE INDEX IF NOT EXISTS idx_service_orders_client_status ON public.service_orders(client_id, status);
CREATE INDEX IF NOT EXISTS idx_service_orders_created_at ON public.service_orders(created_at DESC);

-- Analisar tabelas para atualizar estatísticas do query planner
ANALYZE public.products;
ANALYZE public.inventory_movements;
ANALYZE public.service_orders;
ANALYZE public.payables;
ANALYZE public.receivables;
