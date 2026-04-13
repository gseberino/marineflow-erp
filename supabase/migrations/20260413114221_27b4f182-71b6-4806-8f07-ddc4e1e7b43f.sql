ALTER TABLE inventory_movements
  ADD COLUMN IF NOT EXISTS adjusted_by text DEFAULT 'sistema';