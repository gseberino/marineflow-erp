ALTER TABLE public.service_order_services
  ADD COLUMN IF NOT EXISTS warranty_months integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS warranty_expires_at date;

ALTER TABLE public.service_order_parts
  ADD COLUMN IF NOT EXISTS warranty_months integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS warranty_expires_at date,
  ADD COLUMN IF NOT EXISTS serial_number text;

CREATE OR REPLACE FUNCTION public.calc_warranty_expiry()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.warranty_months > 0 THEN
    NEW.warranty_expires_at := CURRENT_DATE + (NEW.warranty_months || ' months')::interval;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_warranty_services ON public.service_order_services;
CREATE TRIGGER trg_warranty_services
  BEFORE INSERT OR UPDATE ON public.service_order_services
  FOR EACH ROW EXECUTE FUNCTION public.calc_warranty_expiry();

DROP TRIGGER IF EXISTS trg_warranty_parts ON public.service_order_parts;
CREATE TRIGGER trg_warranty_parts
  BEFORE INSERT OR UPDATE ON public.service_order_parts
  FOR EACH ROW EXECUTE FUNCTION public.calc_warranty_expiry();