-- Blocklist de números (listas de transmissão, fornecedores spam)
CREATE TABLE IF NOT EXISTS public.whatsapp_blocked_numbers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_normalized text NOT NULL UNIQUE,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid
);
ALTER TABLE public.whatsapp_blocked_numbers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_blocked" ON public.whatsapp_blocked_numbers
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

-- Respostas rápidas / templates de saudação
CREATE TABLE IF NOT EXISTS public.whatsapp_quick_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shortcut text NOT NULL,
  body text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  sort_order int DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.whatsapp_quick_replies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_quick" ON public.whatsapp_quick_replies
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

-- Atribuição e flags em leads
ALTER TABLE public.whatsapp_leads
  ADD COLUMN IF NOT EXISTS assigned_to uuid,
  ADD COLUMN IF NOT EXISTS is_broadcast boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS unread_count int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_inbound_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_outbound_at timestamptz;

-- Flag broadcast em mensagens
ALTER TABLE public.whatsapp_messages
  ADD COLUMN IF NOT EXISTS is_broadcast boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS sent_by uuid;

-- Atribuição também para clients (conversas com clientes existentes)
CREATE TABLE IF NOT EXISTS public.whatsapp_conversation_assignments (
  phone_normalized text PRIMARY KEY,
  assigned_to uuid,
  notified_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.whatsapp_conversation_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_all_assign" ON public.whatsapp_conversation_assignments
  FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_wa_msgs_phone ON public.whatsapp_messages(phone_normalized, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_wa_leads_status ON public.whatsapp_leads(status, last_message_at DESC);