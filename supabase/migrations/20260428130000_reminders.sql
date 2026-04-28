ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS reminder_sent_at TIMESTAMPTZ;
