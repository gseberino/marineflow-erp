-- Tabela de agendamentos de envio Z-API
CREATE TABLE public.whatsapp_scheduled_sends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Alvo do envio
  target_kind text NOT NULL CHECK (target_kind IN ('service_order', 'receivable')),
  service_order_id uuid REFERENCES public.service_orders(id) ON DELETE CASCADE,
  receivable_id uuid REFERENCES public.receivables(id) ON DELETE CASCADE,
  client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  -- Conteúdo
  phone text NOT NULL,
  message text NOT NULL,
  send_mode text NOT NULL DEFAULT 'link' CHECK (send_mode IN ('link', 'document')),
  context text,
  document_type text,
  link_title text,
  link_description text,
  pdf_filename text,
  caption text,
  include_link_in_caption boolean NOT NULL DEFAULT true,
  -- Agendamento
  scheduled_at timestamptz NOT NULL,
  recurrence_type text NOT NULL DEFAULT 'once' CHECK (recurrence_type IN ('once', 'daily', 'weekly', 'monthly')),
  recurrence_days_of_week int[] DEFAULT NULL, -- 0=domingo .. 6=sábado, para weekly
  recurrence_day_of_month int DEFAULT NULL,    -- 1..31 para monthly
  recurrence_end_date timestamptz DEFAULT NULL,
  next_run_at timestamptz NOT NULL,
  last_run_at timestamptz DEFAULT NULL,
  -- Retry
  auto_retry boolean NOT NULL DEFAULT true,
  max_attempts int NOT NULL DEFAULT 3,
  attempt_count int NOT NULL DEFAULT 0,
  -- Estado
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  last_error text,
  last_response jsonb,
  -- Auditoria
  created_by uuid REFERENCES public.app_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_target CHECK (
    (target_kind = 'service_order' AND service_order_id IS NOT NULL) OR
    (target_kind = 'receivable' AND receivable_id IS NOT NULL)
  )
);

CREATE INDEX idx_wss_next_run ON public.whatsapp_scheduled_sends(next_run_at) WHERE status = 'pending';
CREATE INDEX idx_wss_status ON public.whatsapp_scheduled_sends(status);
CREATE INDEX idx_wss_so ON public.whatsapp_scheduled_sends(service_order_id);
CREATE INDEX idx_wss_rec ON public.whatsapp_scheduled_sends(receivable_id);

ALTER TABLE public.whatsapp_scheduled_sends ENABLE ROW LEVEL SECURITY;

CREATE POLICY whatsapp_scheduled_sends_all_auth ON public.whatsapp_scheduled_sends
  FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);

CREATE TRIGGER trg_wss_updated_at
  BEFORE UPDATE ON public.whatsapp_scheduled_sends
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Função para calcular próxima execução de agendamentos recorrentes
CREATE OR REPLACE FUNCTION public.compute_next_run(
  _from timestamptz,
  _recurrence_type text,
  _days_of_week int[],
  _day_of_month int
) RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  base timestamptz := _from + interval '1 minute';
  candidate timestamptz;
  i int;
  dow int;
BEGIN
  IF _recurrence_type = 'once' THEN
    RETURN NULL;
  ELSIF _recurrence_type = 'daily' THEN
    RETURN base;
  ELSIF _recurrence_type = 'weekly' THEN
    IF _days_of_week IS NULL OR array_length(_days_of_week, 1) = 0 THEN
      RETURN base + interval '7 days';
    END IF;
    FOR i IN 0..7 LOOP
      candidate := base + (i || ' days')::interval;
      dow := EXTRACT(DOW FROM candidate)::int;
      IF dow = ANY(_days_of_week) THEN
        RETURN candidate;
      END IF;
    END LOOP;
    RETURN base + interval '7 days';
  ELSIF _recurrence_type = 'monthly' THEN
    candidate := base + interval '1 month';
    IF _day_of_month IS NOT NULL THEN
      candidate := date_trunc('month', candidate) + ((_day_of_month - 1) || ' days')::interval
                   + (EXTRACT(HOUR FROM _from) || ' hours')::interval
                   + (EXTRACT(MINUTE FROM _from) || ' minutes')::interval;
    END IF;
    RETURN candidate;
  END IF;
  RETURN NULL;
END;
$$;