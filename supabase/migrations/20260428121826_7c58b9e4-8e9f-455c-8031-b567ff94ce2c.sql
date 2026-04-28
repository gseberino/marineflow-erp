-- Sincroniza estruturas das Fases 1-4 que ainda não foram aplicadas

-- 1. Ativos genéricos (Barcos / Motorhomes / etc)
ALTER TABLE public.vessels ADD COLUMN IF NOT EXISTS asset_type TEXT DEFAULT 'Lancha';
COMMENT ON COLUMN public.vessels.asset_type IS 'Tipo do ativo (Lancha, Veleiro, Catamarã, Motorhome, Camper, Trailer)';

-- 2. Fotos de Ordem de Serviço
ALTER TABLE public.service_orders ADD COLUMN IF NOT EXISTS photos JSONB DEFAULT '[]'::jsonb;

-- 3. Centros de Custo (DRE)
CREATE TABLE IF NOT EXISTS public.cost_centers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR NOT NULL,
  type VARCHAR NOT NULL CHECK (type IN ('revenue','expense','both')),
  parent_id UUID REFERENCES public.cost_centers(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.cost_centers ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='cost_centers' AND policyname='cost_centers_all_authenticated') THEN
    CREATE POLICY "cost_centers_all_authenticated" ON public.cost_centers
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

INSERT INTO public.cost_centers (name, type)
SELECT v.name, v.type FROM (VALUES
  ('Receitas Operacionais','revenue'),
  ('Deduções e Impostos','expense'),
  ('Custos Variáveis (CPV/CSV)','expense'),
  ('Despesas Operacionais Fixas','expense'),
  ('Despesas com Pessoal','expense'),
  ('Despesas Administrativas','expense'),
  ('Resultado Financeiro (Taxas/Juros)','expense')
) AS v(name,type)
WHERE NOT EXISTS (SELECT 1 FROM public.cost_centers cc WHERE cc.name = v.name);

ALTER TABLE public.payables ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES public.cost_centers(id);
ALTER TABLE public.payables ADD COLUMN IF NOT EXISTS sub_category VARCHAR;
ALTER TABLE public.receivables ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES public.cost_centers(id);
ALTER TABLE public.receivables ADD COLUMN IF NOT EXISTS sub_category VARCHAR;

-- 4. Comissões
CREATE TABLE IF NOT EXISTS public.commissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id UUID REFERENCES public.service_orders(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.app_users(id),
  amount NUMERIC(12,2) NOT NULL,
  base_value NUMERIC(12,2),
  percentage NUMERIC(5,2),
  status TEXT DEFAULT 'pending',
  paid_at TIMESTAMPTZ,
  payable_id UUID REFERENCES public.payables(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.commissions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='commissions' AND policyname='commissions_admin_all') THEN
    CREATE POLICY "commissions_admin_all" ON public.commissions
      FOR ALL TO authenticated USING (public.is_admin(auth.uid())) WITH CHECK (public.is_admin(auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='commissions' AND policyname='commissions_self_select') THEN
    CREATE POLICY "commissions_self_select" ON public.commissions
      FOR SELECT TO authenticated USING (auth.uid() = user_id);
  END IF;
END $$;

-- 5. Mapeamento SKU fornecedor -> produto interno
CREATE TABLE IF NOT EXISTS public.supplier_product_mappings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID REFERENCES public.suppliers(id) ON DELETE CASCADE,
  supplier_sku TEXT NOT NULL,
  supplier_description TEXT,
  internal_product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(supplier_id, supplier_sku)
);
ALTER TABLE public.supplier_product_mappings ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='supplier_product_mappings' AND policyname='spm_all_authenticated') THEN
    CREATE POLICY "spm_all_authenticated" ON public.supplier_product_mappings
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 6. Inteligência de preços
CREATE TABLE IF NOT EXISTS public.product_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
  old_cost NUMERIC,
  new_cost NUMERIC,
  fiscal_note_id UUID REFERENCES public.fiscal_notes(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.product_price_history ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='product_price_history' AND policyname='pph_all_authenticated') THEN
    CREATE POLICY "pph_all_authenticated" ON public.product_price_history
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.price_update_suggestions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
  fiscal_note_id UUID REFERENCES public.fiscal_notes(id) ON DELETE CASCADE,
  current_sale_price NUMERIC,
  suggested_sale_price NUMERIC,
  margin_percent NUMERIC,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.price_update_suggestions ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='price_update_suggestions' AND policyname='pus_all_authenticated') THEN
    CREATE POLICY "pus_all_authenticated" ON public.price_update_suggestions
      FOR ALL TO authenticated USING (true) WITH CHECK (true);
  END IF;
END $$;

-- 7. Produtos: última entrada de estoque
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS last_stock_entry_at TIMESTAMPTZ;