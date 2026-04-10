
-- 1. Audit log table
CREATE TABLE audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text NOT NULL,
  record_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN (
    'update', 'cancel', 'reopen', 'reversal', 'cascade_update'
  )),
  changed_by text NOT NULL DEFAULT 'sistema',
  changed_at timestamptz DEFAULT now(),
  previous_value jsonb,
  new_value jsonb,
  reason text,
  triggered_by_table text,
  triggered_by_id uuid
);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY allow_all_audit_log ON audit_log
  AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

-- 2. Add cancellation/reopen columns to service_orders
ALTER TABLE service_orders
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_reason text,
  ADD COLUMN IF NOT EXISTS reopened_at timestamptz,
  ADD COLUMN IF NOT EXISTS reopen_reason text;

-- 3. Add cancellation tracking to payments
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_reason text,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'confirmed'
    CHECK (status IN ('confirmed', 'cancelled'));
