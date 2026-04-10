
CREATE TABLE financial_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  type text NOT NULL CHECK (type IN ('payable', 'receivable')),
  color text DEFAULT '#6b7280',
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE financial_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_all_financial_categories ON financial_categories
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

CREATE TABLE saved_filters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  filter_type text NOT NULL CHECK (filter_type IN ('payable', 'receivable')),
  filter_config jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE saved_filters ENABLE ROW LEVEL SECURITY;

CREATE POLICY allow_all_saved_filters ON saved_filters
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

INSERT INTO financial_categories (name, type, color) VALUES
  ('Peças e Materiais', 'payable', '#3b82f6'),
  ('Veículo e Combustível', 'payable', '#f59e0b'),
  ('Ferramentas e Equipamentos', 'payable', '#8b5cf6'),
  ('Seguro', 'payable', '#06b6d4'),
  ('Aluguel', 'payable', '#84cc16'),
  ('Salários', 'payable', '#ec4899'),
  ('Impostos', 'payable', '#ef4444'),
  ('Marketing', 'payable', '#f97316'),
  ('Alimentação de Campo', 'payable', '#a16207'),
  ('Pedágio e Estacionamento', 'payable', '#78716c'),
  ('Outros', 'payable', '#6b7280');

INSERT INTO financial_categories (name, type, color) VALUES
  ('Serviços Técnicos', 'receivable', '#10b981'),
  ('Venda de Produtos', 'receivable', '#3b82f6'),
  ('Consultoria', 'receivable', '#8b5cf6'),
  ('Adiantamento', 'receivable', '#f59e0b'),
  ('Reembolso de Cliente', 'receivable', '#06b6d4'),
  ('Contrato Recorrente', 'receivable', '#84cc16'),
  ('Outros', 'receivable', '#6b7280');

ALTER TABLE receivables
  ADD COLUMN IF NOT EXISTS category text;
