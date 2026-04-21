-- 1) Templates de mensagem WhatsApp
CREATE TABLE IF NOT EXISTS public.whatsapp_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  category text NOT NULL DEFAULT 'general',
  body text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.whatsapp_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY whatsapp_templates_all_auth
  ON public.whatsapp_templates FOR ALL TO authenticated
  USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE TRIGGER trg_whatsapp_templates_updated
  BEFORE UPDATE ON public.whatsapp_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.whatsapp_templates (name, category, body, sort_order) VALUES
  ('Confirmação de OS', 'service_order', 'Olá {cliente}, sua Ordem de Serviço {os} foi aberta. Acompanhe pelo link: {link}', 10),
  ('Orçamento enviado', 'quote', 'Olá {cliente}, segue o orçamento {os} no valor de {valor}. Acesso: {link}', 20),
  ('Cobrança - lembrete', 'billing', 'Olá {cliente}, lembramos da cobrança "{descricao}" no valor de {valor} com vencimento em {vencimento}.', 30),
  ('Cobrança - vencida', 'billing', 'Olá {cliente}, a cobrança "{descricao}" no valor de {valor} venceu em {vencimento}. Por favor, regularize.', 40),
  ('OS concluída', 'service_order', 'Olá {cliente}, sua OS {os} foi concluída. Total: {valor}. Detalhes: {link}', 50);

-- 2) Realtime
ALTER TABLE public.whatsapp_messages REPLICA IDENTITY FULL;
ALTER TABLE public.whatsapp_leads REPLICA IDENTITY FULL;

DO $$ BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.whatsapp_messages;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.whatsapp_leads;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- 3) Estado de leitura por usuário
CREATE TABLE IF NOT EXISTS public.whatsapp_read_state (
  user_id uuid PRIMARY KEY,
  last_read_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.whatsapp_read_state ENABLE ROW LEVEL SECURITY;

CREATE POLICY whatsapp_read_state_self
  ON public.whatsapp_read_state FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TRIGGER trg_whatsapp_read_state_updated
  BEFORE UPDATE ON public.whatsapp_read_state
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();