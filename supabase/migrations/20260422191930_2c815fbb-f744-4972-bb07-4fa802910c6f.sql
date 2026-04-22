CREATE TABLE IF NOT EXISTS public.whatsapp_send_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_normalized text NOT NULL,
  message text NOT NULL,
  source text NOT NULL DEFAULT 'manual',
  source_ref_id uuid,
  priority integer NOT NULL DEFAULT 5,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 3,
  scheduled_for timestamptz NOT NULL DEFAULT now(),
  processing_started_at timestamptz,
  sent_at timestamptz,
  failed_reason text,
  zapi_message_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wa_queue_pending ON public.whatsapp_send_queue (status, scheduled_for, priority) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_wa_queue_phone ON public.whatsapp_send_queue (phone_normalized, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wa_queue_source ON public.whatsapp_send_queue (source, created_at DESC);

ALTER TABLE public.whatsapp_send_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_all_wa_queue"
ON public.whatsapp_send_queue FOR ALL
TO authenticated
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

CREATE TRIGGER trg_wa_queue_updated_at
BEFORE UPDATE ON public.whatsapp_send_queue
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.app_settings (key, value, description) VALUES
  ('whatsapp_queue_enabled', 'true', 'Liga/desliga o worker da fila de envio WhatsApp.'),
  ('whatsapp_queue_max_per_run', '5', 'Quantas mensagens o worker envia por execução (cada cron tick).'),
  ('whatsapp_queue_delay_ms', '1500', 'Delay entre envios consecutivos do worker (ms).'),
  ('whatsapp_queue_max_per_hour', '60', 'Limite global de envios por hora (rate limit).')
ON CONFLICT (key) DO NOTHING;