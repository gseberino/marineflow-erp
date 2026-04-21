
-- Trigger: marca requires_resignature quando OS assinada é editada
CREATE OR REPLACE FUNCTION public.detect_so_change_after_signature()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.signed_at IS NOT NULL
     AND NEW.requires_resignature = false
     AND (
       NEW.problem_description IS DISTINCT FROM OLD.problem_description OR
       NEW.diagnosis IS DISTINCT FROM OLD.diagnosis OR
       NEW.solution_applied IS DISTINCT FROM OLD.solution_applied OR
       NEW.customer_visible_report IS DISTINCT FROM OLD.customer_visible_report OR
       NEW.payment_conditions IS DISTINCT FROM OLD.payment_conditions OR
       NEW.extra_notes IS DISTINCT FROM OLD.extra_notes OR
       NEW.grand_total IS DISTINCT FROM OLD.grand_total OR
       NEW.labor_cost_total IS DISTINCT FROM OLD.labor_cost_total OR
       NEW.parts_cost_total IS DISTINCT FROM OLD.parts_cost_total OR
       NEW.travel_cost_total IS DISTINCT FROM OLD.travel_cost_total OR
       NEW.discount_amount IS DISTINCT FROM OLD.discount_amount OR
       NEW.tax_amount IS DISTINCT FROM OLD.tax_amount OR
       NEW.operational_cost_total IS DISTINCT FROM OLD.operational_cost_total OR
       NEW.quote_validity_date IS DISTINCT FROM OLD.quote_validity_date
     )
  THEN
    NEW.requires_resignature := true;
    NEW.resignature_requested_at := now();

    -- supersede assinaturas anteriores
    UPDATE public.service_order_signatures
    SET superseded_at = now(),
        superseded_reason = 'OS alterada após assinatura'
    WHERE service_order_id = NEW.id
      AND superseded_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_detect_so_change_after_signature ON public.service_orders;
CREATE TRIGGER trg_detect_so_change_after_signature
BEFORE UPDATE ON public.service_orders
FOR EACH ROW
EXECUTE FUNCTION public.detect_so_change_after_signature();
