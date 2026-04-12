
CREATE TABLE product_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  description text,
  default_profit_margin numeric(6,4) DEFAULT 30,
  default_commission_rate numeric(6,4) DEFAULT 0,
  is_commissionable boolean DEFAULT true,
  default_csosn text DEFAULT '400',
  default_fiscal_origin integer DEFAULT 0,
  default_ncm text,
  default_icms_rate numeric(6,4) DEFAULT 0,
  default_ipi_rate numeric(6,4) DEFAULT 0,
  default_pis_rate numeric(6,4) DEFAULT 0,
  default_cofins_rate numeric(6,4) DEFAULT 0,
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE product_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_product_categories ON product_categories
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

CREATE TRIGGER set_updated_at_product_categories
  BEFORE UPDATE ON product_categories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS product_category_id uuid REFERENCES product_categories(id),
  ADD COLUMN IF NOT EXISTS is_commissionable boolean DEFAULT true;

INSERT INTO product_categories (name, default_profit_margin, default_commission_rate, is_commissionable, default_csosn) VALUES
  ('Eletrônicos e Navegação', 35, 5, true, '400'),
  ('Equipamentos Elétricos', 30, 5, true, '400'),
  ('Peças e Componentes', 40, 3, true, '400'),
  ('Acessórios Náuticos', 45, 5, true, '400'),
  ('Ferramentas', 30, 0, false, '400'),
  ('Consumíveis', 25, 0, false, '400'),
  ('Cabos e Conectores', 40, 3, true, '400'),
  ('Segurança e EPIs', 35, 0, false, '400'),
  ('Outros', 30, 0, false, '400');
