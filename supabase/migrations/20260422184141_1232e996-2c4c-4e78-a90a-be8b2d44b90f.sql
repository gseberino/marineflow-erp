-- 1) Deduplicação: garante que zapi_message_id seja único quando informado
-- Antes, limpa duplicatas mantendo a primeira ocorrência
DELETE FROM public.whatsapp_messages a
USING public.whatsapp_messages b
WHERE a.zapi_message_id IS NOT NULL
  AND a.zapi_message_id = b.zapi_message_id
  AND a.created_at > b.created_at;

CREATE UNIQUE INDEX IF NOT EXISTS whatsapp_messages_zapi_message_id_unique
  ON public.whatsapp_messages (zapi_message_id)
  WHERE zapi_message_id IS NOT NULL;

-- 2) Índices de rastreamento
CREATE INDEX IF NOT EXISTS whatsapp_messages_phone_created_idx
  ON public.whatsapp_messages (phone_normalized, created_at DESC);

CREATE INDEX IF NOT EXISTS whatsapp_messages_direction_created_idx
  ON public.whatsapp_messages (direction, created_at DESC);

CREATE INDEX IF NOT EXISTS whatsapp_messages_delivery_status_idx
  ON public.whatsapp_messages (delivery_status)
  WHERE delivery_status IN ('sent', 'queued', 'failed');

CREATE INDEX IF NOT EXISTS whatsapp_messages_lead_id_idx
  ON public.whatsapp_messages (lead_id) WHERE lead_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS whatsapp_messages_client_id_idx
  ON public.whatsapp_messages (client_id) WHERE client_id IS NOT NULL;

-- 3) Leads: índices para fila de pendentes
CREATE INDEX IF NOT EXISTS whatsapp_leads_status_last_inbound_idx
  ON public.whatsapp_leads (status, last_inbound_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS whatsapp_leads_unread_idx
  ON public.whatsapp_leads (unread_count DESC) WHERE unread_count > 0;