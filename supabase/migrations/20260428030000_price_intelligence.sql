-- Migração para sugestões de preços e histórico de custos
-- Nome: 20260428030000_price_intelligence.sql

CREATE TABLE IF NOT EXISTS public.product_price_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
    old_cost DECIMAL,
    new_cost DECIMAL,
    fiscal_note_id UUID REFERENCES public.fiscal_notes(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.price_update_suggestions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
    fiscal_note_id UUID REFERENCES public.fiscal_notes(id) ON DELETE CASCADE,
    current_sale_price DECIMAL,
    suggested_sale_price DECIMAL,
    margin_percent DECIMAL,
    status TEXT DEFAULT 'pending', -- 'pending', 'applied', 'ignored'
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Habilitar RLS
ALTER TABLE public.product_price_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.price_update_suggestions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Enable all for authenticated users" ON public.product_price_history FOR ALL TO authenticated USING (true);
CREATE POLICY "Enable all for authenticated users" ON public.price_update_suggestions FOR ALL TO authenticated USING (true);

-- Trigger para registrar histórico de custo automaticamente
CREATE OR REPLACE FUNCTION log_product_cost_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.cost_price IS DISTINCT FROM NEW.cost_price) THEN
        INSERT INTO product_price_history (product_id, old_cost, new_cost)
        VALUES (NEW.id, OLD.cost_price, NEW.cost_price);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_log_product_cost_change
    AFTER UPDATE OF cost_price ON public.products
    FOR EACH ROW EXECUTE FUNCTION log_product_cost_change();

-- Atualizar confirm_nfe_import para gerar sugestões de preço
-- Vou adicionar esta lógica diretamente na RPC existente via replace
