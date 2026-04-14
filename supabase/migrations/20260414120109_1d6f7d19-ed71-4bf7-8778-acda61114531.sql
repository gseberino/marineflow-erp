ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS commissioned_user_id uuid REFERENCES app_users(id),
  ADD COLUMN IF NOT EXISTS quote_validity_days integer DEFAULT 15,
  ADD COLUMN IF NOT EXISTS quote_validity_date date;