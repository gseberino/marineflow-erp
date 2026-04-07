
-- 1. Services catalog table
CREATE TABLE services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_name text NOT NULL,
  description text,
  category text,
  billing_unit text NOT NULL DEFAULT 'hour' 
    CHECK (billing_unit IN ('hour', 'visit', 'day', 'unit')),
  default_price numeric(12,2) DEFAULT 0,
  currency text DEFAULT 'BRL',
  active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE services ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_services ON services 
  AS PERMISSIVE FOR ALL TO anon, authenticated 
  USING (true) WITH CHECK (true);

CREATE TRIGGER set_updated_at_services
  BEFORE UPDATE ON services
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. Service order labor lines
CREATE TABLE service_order_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
  service_id uuid REFERENCES services(id),
  service_name_snapshot text NOT NULL,
  description_snapshot text,
  billing_unit_snapshot text NOT NULL DEFAULT 'hour',
  quantity numeric(10,3) NOT NULL DEFAULT 1,
  unit_price_snapshot numeric(12,2) NOT NULL DEFAULT 0,
  line_total numeric(12,2) NOT NULL DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE service_order_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_service_order_services ON service_order_services
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

CREATE TRIGGER set_updated_at_service_order_services
  BEFORE UPDATE ON service_order_services
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 3. Card installment fee table
CREATE TABLE card_installment_fees (
  installments integer PRIMARY KEY CHECK (installments BETWEEN 1 AND 6),
  fee_percent numeric(6,4) NOT NULL DEFAULT 0,
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE card_installment_fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_card_fees ON card_installment_fees
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

-- Seed default installment fees
INSERT INTO card_installment_fees (installments, fee_percent) VALUES
  (1, 2.49),
  (2, 3.49),
  (3, 4.49),
  (4, 5.49),
  (5, 6.49),
  (6, 7.49)
ON CONFLICT (installments) DO NOTHING;

-- 4. Seed standard terms into app_settings
INSERT INTO app_settings (key, value, description) VALUES
  ('terms_warranty', 
   'Os serviços executados possuem garantia de 90 dias para mão de obra a contar da data de conclusão. Peças e equipamentos seguem a garantia do fabricante.',
   'Termos de garantia padrão'),
  ('terms_cancellation',
   'O cancelamento do serviço deve ser comunicado com no mínimo 24 horas de antecedência. Serviços já iniciados serão cobrados proporcionalmente às horas trabalhadas e materiais utilizados.',
   'Termos de cancelamento'),
  ('terms_delivery',
   'O prazo de entrega de produtos e equipamentos importados pode variar de 15 a 45 dias úteis, sujeito à disponibilidade do fabricante e liberação alfandegária.',
   'Observações sobre prazo de entrega'),
  ('terms_responsibilities',
   'O cliente é responsável por garantir acesso à embarcação no horário agendado. A empresa não se responsabiliza por danos pré-existentes não documentados antes do início do serviço.',
   'Responsabilidades e obrigações'),
  ('terms_general',
   'Todos os serviços são executados por profissionais qualificados. Os valores apresentados neste documento são válidos por 15 dias a partir da data de emissão.',
   'Observações gerais')
ON CONFLICT (key) DO NOTHING;
