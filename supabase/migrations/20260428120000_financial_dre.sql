-- financial_dre.sql — idempotente
CREATE TABLE IF NOT EXISTS cost_centers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name VARCHAR NOT NULL,
  type VARCHAR NOT NULL CHECK (type IN ('revenue', 'expense', 'both')),
  parent_id UUID REFERENCES cost_centers(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE cost_centers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Enable read/write for all authenticated users" ON cost_centers;
CREATE POLICY "Enable read/write for all authenticated users"
  ON cost_centers FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Insert default DRE structure (only if table is empty)
INSERT INTO cost_centers (name, type)
SELECT name, type FROM (VALUES
  ('Receitas Operacionais',             'revenue'),
  ('Deduções e Impostos',               'expense'),
  ('Custos Variáveis (CPV/CSV)',        'expense'),
  ('Despesas Operacionais Fixas',       'expense'),
  ('Despesas com Pessoal',              'expense'),
  ('Despesas Administrativas',          'expense'),
  ('Resultado Financeiro (Taxas/Juros)','expense')
) AS v(name, type)
WHERE NOT EXISTS (SELECT 1 FROM cost_centers LIMIT 1);

-- Add cost center columns (safe if already exist)
ALTER TABLE payables    ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);
ALTER TABLE payables    ADD COLUMN IF NOT EXISTS sub_category VARCHAR;
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS cost_center_id UUID REFERENCES cost_centers(id);
ALTER TABLE receivables ADD COLUMN IF NOT EXISTS sub_category VARCHAR;
