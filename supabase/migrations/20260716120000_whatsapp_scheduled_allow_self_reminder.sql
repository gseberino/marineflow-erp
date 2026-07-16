-- Permite auto-lembretes (self_reminder) na tabela whatsapp_scheduled_sends.
-- A tool schedule_self_reminder (supabase/functions/_shared/ai/tools/whatsapp.ts) insere
-- send_mode='text' e target_kind='self_reminder', mas as CHECK constraints (mais antigas que
-- o processador whatsapp-process-scheduled, que ja trata 'text') barravam o INSERT.
-- Tambem corrige o branch 'daily' de compute_next_run (avancava 1 minuto em vez de 1 dia).

-- 1. send_mode: permitir 'text' (o processador whatsapp-process-scheduled ja o trata)
ALTER TABLE public.whatsapp_scheduled_sends
  DROP CONSTRAINT IF EXISTS whatsapp_scheduled_sends_send_mode_check;
ALTER TABLE public.whatsapp_scheduled_sends
  ADD CONSTRAINT whatsapp_scheduled_sends_send_mode_check
  CHECK (send_mode = ANY (ARRAY['link'::text, 'document'::text, 'text'::text]));

-- 2. Remove a constraint estrita redundante de target_kind (barrava 'manual' e 'self_reminder').
--    A validacao passa a ser feita so por chk_target (reconciliada no passo 3).
ALTER TABLE public.whatsapp_scheduled_sends
  DROP CONSTRAINT IF EXISTS whatsapp_scheduled_sends_target_kind_check;

-- 3. chk_target: inclui 'self_reminder', mantendo regras de service_order/receivable e 'manual'.
ALTER TABLE public.whatsapp_scheduled_sends
  DROP CONSTRAINT IF EXISTS chk_target;
ALTER TABLE public.whatsapp_scheduled_sends
  ADD CONSTRAINT chk_target CHECK (
    (target_kind = 'service_order' AND service_order_id IS NOT NULL) OR
    (target_kind = 'receivable'    AND receivable_id    IS NOT NULL) OR
    (target_kind = 'manual') OR
    (target_kind = 'self_reminder')
  );

-- 4. Bug-fix de recorrencia: 'daily' deve avancar 1 dia (retornava base = +1 minuto -> spam).
--    Preserva o restante do corpo original da funcao.
CREATE OR REPLACE FUNCTION public.compute_next_run(
  _from timestamptz,
  _recurrence_type text,
  _days_of_week integer[],
  _day_of_month integer
) RETURNS timestamptz
  LANGUAGE plpgsql
  STABLE
  SET search_path TO 'public'
AS $function$
DECLARE
  base timestamptz := _from + interval '1 minute';
  candidate timestamptz;
  i int;
  dow int;
BEGIN
  IF _recurrence_type = 'once' THEN
    RETURN NULL;
  ELSIF _recurrence_type = 'daily' THEN
    RETURN _from + interval '1 day';
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
$function$;
