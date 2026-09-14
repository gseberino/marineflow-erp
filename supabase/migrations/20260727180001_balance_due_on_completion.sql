-- ═══════════════════════════════════════════════════════════════
-- Vencimento do saldo "na entrega" ajusta para a conclusão REAL da OS
--
-- Regra do usuário: a parcela de saldo do tipo "na entrega" vence na entrega prevista
-- (scheduled_end_at). Mas se o serviço for concluído em data diferente, o vencimento deve
-- passar automaticamente para o momento exato da conclusão da OS.
--
-- receivables.due_on_completion marca os títulos de saldo "na entrega" (a RPC
-- register_deposit_and_convert seta true para parcelas dueBasis='delivery'). Um trigger em
-- service_orders, ao mudar o status para 'completed', reescreve o vencimento desses títulos
-- (e das cobranças vinculadas) para check_out_at (data real de conclusão) — ou a data atual
-- se check_out_at ainda não estiver preenchido. Cobre TODOS os caminhos de conclusão.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.receivables
  ADD COLUMN IF NOT EXISTS due_on_completion boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.sync_balance_due_on_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_due date := COALESCE(NEW.check_out_at::date, CURRENT_DATE);
BEGIN
  UPDATE public.receivables
  SET due_date = v_due
  WHERE service_order_id = NEW.id
    AND due_on_completion = true
    AND status NOT IN ('paid', 'cancelled');

  UPDATE public.collections c
  SET due_date = v_due
  FROM public.receivables r
  WHERE c.receivable_id = r.id
    AND r.service_order_id = NEW.id
    AND r.due_on_completion = true
    AND c.status = 'pending';

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_balance_due_on_completion ON public.service_orders;
CREATE TRIGGER trg_sync_balance_due_on_completion
AFTER UPDATE ON public.service_orders
FOR EACH ROW
WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
EXECUTE FUNCTION public.sync_balance_due_on_completion();
