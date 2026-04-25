ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS travel_hours numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ferry_cost numeric DEFAULT 0,
  ADD COLUMN IF NOT EXISTS travel_type text DEFAULT 'comercial'
    CHECK (travel_type IN ('comercial', 'urgencia', 'fds_feriado'));