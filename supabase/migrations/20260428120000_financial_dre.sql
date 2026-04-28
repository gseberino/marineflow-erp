CREATE TABLE cost_centers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name VARCHAR NOT NULL,
  type VARCHAR NOT NULL CHECK (type IN ('revenue', 'expense', 'both')),
  parent_id UUID REFERENCES cost_centers(id),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE cost_centers ENABLE ROW LEVEL SECURITY;

-- Create policy for cost_centers
CREATE POLICY "Enable read/write for all authenticated users"
  ON cost_centers
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Insert default DRE structure
INSERT INTO cost_centers (name, type) VALUES
('Receitas Operacionais', 'revenue'),
('Deduções e Impostos', 'expense'),
('Custos Variáveis (CPV/CSV)', 'expense'),
('Despesas Operacionais Fixas', 'expense'),
('Despesas com Pessoal', 'expense'),
('Despesas Administrativas', 'expense'),
('Resultado Financeiro (Taxas/Juros)', 'expense');

-- Add cost center to payables and receivables
ALTER TABLE payables ADD COLUMN cost_center_id UUID REFERENCES cost_centers(id);
ALTER TABLE payables ADD COLUMN sub_category VARCHAR;

ALTER TABLE receivables ADD COLUMN cost_center_id UUID REFERENCES cost_centers(id);
ALTER TABLE receivables ADD COLUMN sub_category VARCHAR;

-- Update the existing view profitability_view if necessary
-- profitability_view already exists, we leave it as is unless it needs cost centers.

-- Create DRE materialized view or function for ease (optional, but we can just calculate in frontend)
