-- Migration: cria tabela de agendamento de Status (Stories) do WhatsApp via Z-API
-- Objetivo: Permitir que o usuário agende postagens no Status com imagem, vídeo ou texto.

CREATE TABLE IF NOT EXISTS public.whatsapp_status_scheduled (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type text NOT NULL CHECK (content_type IN ('text', 'image', 'video')),
  media_url text, -- URL da mídia hospedada no Supabase Storage
  text_content text, -- Texto do status ou legenda da mídia
  background_color text DEFAULT '#000000', -- Para status de texto
  font_type integer DEFAULT 0, -- Índice da fonte na Z-API (0 a 5)
  
  scheduled_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  error_message text,
  zapi_message_id text,
  
  created_by uuid REFERENCES public.app_users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Índices para performance
CREATE INDEX idx_wss_status_pending ON public.whatsapp_status_scheduled(scheduled_at) WHERE status = 'pending';
CREATE INDEX idx_wss_status_lookup ON public.whatsapp_status_scheduled(status);

-- RLS
ALTER TABLE public.whatsapp_status_scheduled ENABLE ROW LEVEL SECURITY;
CREATE POLICY "whatsapp_status_scheduled_all_auth" ON public.whatsapp_status_scheduled
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Trigger updated_at
CREATE TRIGGER trg_whatsapp_status_scheduled_updated_at
  BEFORE UPDATE ON public.whatsapp_status_scheduled
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
