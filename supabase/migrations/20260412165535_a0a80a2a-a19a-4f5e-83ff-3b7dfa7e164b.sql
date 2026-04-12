
-- Add fiscal and pricing fields to products
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS ncm text,
  ADD COLUMN IF NOT EXISTS csosn text DEFAULT '400',
  ADD COLUMN IF NOT EXISTS fiscal_origin integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS icms_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ipi_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS pis_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cofins_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS profit_margin numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS use_global_fiscal boolean DEFAULT true;

-- Add fiscal default columns to app_settings
ALTER TABLE app_settings
  ADD COLUMN IF NOT EXISTS default_csosn text DEFAULT '400',
  ADD COLUMN IF NOT EXISTS default_fiscal_origin integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_icms_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_ipi_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_pis_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_cofins_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_commission_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_profit_margin numeric(6,4) DEFAULT 30,
  ADD COLUMN IF NOT EXISTS simples_aliquota numeric(6,4) DEFAULT 6;

-- Add commission fields to service_orders
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS commission_rate numeric(6,4) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_amount numeric(12,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commissioned_person text;
