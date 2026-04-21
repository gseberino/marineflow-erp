-- whatsapp_leads: fila de novos contatos
CREATE TABLE public.whatsapp_leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_normalized text NOT NULL,
  display_name text,
  first_message text,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  message_count integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','linked','converted','discarded')),
  linked_client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (phone_normalized)
);

CREATE INDEX idx_whatsapp_leads_status ON public.whatsapp_leads(status);
CREATE INDEX idx_whatsapp_leads_phone ON public.whatsapp_leads(phone_normalized);

ALTER TABLE public.whatsapp_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view leads"
  ON public.whatsapp_leads FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert leads"
  ON public.whatsapp_leads FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update leads"
  ON public.whatsapp_leads FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated users can delete leads"
  ON public.whatsapp_leads FOR DELETE TO authenticated USING (true);

CREATE TRIGGER trg_whatsapp_leads_updated_at
  BEFORE UPDATE ON public.whatsapp_leads
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- whatsapp_messages: histórico de mensagens
CREATE TABLE public.whatsapp_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  direction text NOT NULL CHECK (direction IN ('inbound','outbound')),
  phone_normalized text NOT NULL,
  message_type text NOT NULL DEFAULT 'text'
    CHECK (message_type IN ('text','image','audio','video','document','location','contact','sticker','other')),
  body text,
  media_url text,
  client_id uuid REFERENCES public.clients(id) ON DELETE SET NULL,
  lead_id uuid REFERENCES public.whatsapp_leads(id) ON DELETE SET NULL,
  service_order_id uuid REFERENCES public.service_orders(id) ON DELETE SET NULL,
  zapi_message_id text,
  delivery_status text DEFAULT 'received'
    CHECK (delivery_status IN ('received','sent','delivered','read','failed')),
  raw_payload jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_whatsapp_messages_phone ON public.whatsapp_messages(phone_normalized);
CREATE INDEX idx_whatsapp_messages_client ON public.whatsapp_messages(client_id);
CREATE INDEX idx_whatsapp_messages_lead ON public.whatsapp_messages(lead_id);
CREATE INDEX idx_whatsapp_messages_occurred ON public.whatsapp_messages(occurred_at DESC);

ALTER TABLE public.whatsapp_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view messages"
  ON public.whatsapp_messages FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated users can insert messages"
  ON public.whatsapp_messages FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Authenticated users can update messages"
  ON public.whatsapp_messages FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Authenticated users can delete messages"
  ON public.whatsapp_messages FOR DELETE TO authenticated USING (true);