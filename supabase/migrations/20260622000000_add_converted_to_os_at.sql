-- Add converted_to_os_at to mark the moment a quote becomes a real service order.
-- NULL = still a quote (draft). NOT NULL = converted to OS.

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS converted_to_os_at timestamptz;

-- Backfill: existing non-draft records are treated as already-converted OS.
-- We use created_at as a reasonable approximation since we don't have the exact moment.
UPDATE public.service_orders
SET converted_to_os_at = created_at
WHERE status <> 'draft' AND converted_to_os_at IS NULL;
