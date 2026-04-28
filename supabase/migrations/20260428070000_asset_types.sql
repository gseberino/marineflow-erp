-- Migration: Add asset_type to vessels
-- Name: 20260428070000_asset_types.sql

ALTER TABLE public.vessels ADD COLUMN IF NOT EXISTS asset_type TEXT DEFAULT 'Lancha';

-- Comment on column
COMMENT ON COLUMN public.vessels.asset_type IS 'Type of the asset (e.g., Lancha, Veleiro, Catamarã, Motorhome, Camper, Trailer). Default is Lancha for legacy data.';
