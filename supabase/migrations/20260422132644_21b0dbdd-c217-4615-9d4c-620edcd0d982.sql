-- 1. Collections table
CREATE TABLE IF NOT EXISTS public.collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  service_order_id UUID REFERENCES public.service_orders(id) ON DELETE SET NULL,
  receivable_id UUID REFERENCES public.receivables(id) ON DELETE SET NULL,
  description TEXT,
  standalone_amount NUMERIC(12,2),
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL,
  due_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','sent','viewed','paid','overdue','disputed','cancelled')),
  contact_name TEXT,
  contact_phone TEXT,
  contact_whatsapp TEXT,
  send_method TEXT DEFAULT 'text_link'
    CHECK (send_method IN ('pdf','text','text_link')),
  message_template TEXT,
  paid_at TIMESTAMPTZ,
  paid_amount NUMERIC(12,2),
  paid_method TEXT,
  payment_confirmed_by TEXT DEFAULT 'manual'
    CHECK (payment_confirmed_by IN ('manual','whatsapp','auto')),
  auto_rule_enabled BOOLEAN DEFAULT false,
  rule_days_before INTEGER DEFAULT 3,
  rule_days_after INTEGER DEFAULT 5,
  last_auto_sent_at TIMESTAMPTZ,
  created_by UUID REFERENCES public.app_users(id),
  notes TEXT
);

ALTER TABLE public.collections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_full_access" ON public.collections
  AS PERMISSIVE FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_collections_client ON public.collections(client_id);
CREATE INDEX IF NOT EXISTS idx_collections_status ON public.collections(status);
CREATE INDEX IF NOT EXISTS idx_collections_due_date ON public.collections(due_date);
CREATE INDEX IF NOT EXISTS idx_collections_so ON public.collections(service_order_id);

CREATE TRIGGER collections_updated_at
  BEFORE UPDATE ON public.collections
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 2. Collection contact history
CREATE TABLE IF NOT EXISTS public.collection_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  collection_id UUID NOT NULL REFERENCES public.collections(id) ON DELETE CASCADE,
  contact_type TEXT NOT NULL
    CHECK (contact_type IN (
      'whatsapp_sent','whatsapp_delivered','whatsapp_read',
      'call_made','call_answered','call_no_answer',
      'email_sent','manual_note','payment_promised','paid'
    )),
  notes TEXT,
  promised_date DATE,
  created_by UUID REFERENCES public.app_users(id)
);

ALTER TABLE public.collection_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_full_access" ON public.collection_contacts
  AS PERMISSIVE FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_collection_contacts_coll ON public.collection_contacts(collection_id, created_at DESC);

-- 3. Collection message templates
CREATE TABLE IF NOT EXISTS public.collection_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  name TEXT NOT NULL,
  body TEXT NOT NULL,
  is_default BOOLEAN DEFAULT false,
  send_method TEXT DEFAULT 'text_link'
    CHECK (send_method IN ('pdf','text','text_link'))
);

ALTER TABLE public.collection_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_full_access" ON public.collection_templates
  AS PERMISSIVE FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

INSERT INTO public.collection_templates (name, body, is_default, send_method) VALUES
('Cobrança Padrão',
 E'Olá, {{nome}}! 👋\n\nPassamos para informar que a fatura {{numero_os}} no valor de *R$ {{valor}}* vence em *{{vencimento}}*.\n\n💰 Para pagamento via PIX:\nChave: {{pix}}\n\nQualquer dúvida, estamos à disposição!\n\n*{{empresa}}* 🚢',
 true, 'text_link'),
('Lembrete de Vencimento',
 E'Olá, {{nome}}! ⏰\n\nLembramos que sua fatura {{numero_os}} de *R$ {{valor}}* vence *hoje*.\n\n💰 PIX: {{pix}}\n\nEvite juros e multas realizando o pagamento hoje. Obrigado!',
 false, 'text'),
('Cobrança em Atraso',
 E'Olá, {{nome}}. 📋\n\nIdentificamos que a fatura {{numero_os}} de *R$ {{valor}}* encontra-se em atraso desde {{vencimento}}.\n\nSolicito que entre em contato para regularizar a situação.\n\n💰 PIX: {{pix}}\n\nAtenciosamente,\n*{{empresa}}*',
 false, 'text_link');