-- Migration: cria tabela de referência de APIs e popula com Z-API
-- Objetivo: Reduzir carga de trabalho futura ao ter mapeamento completo da API disponível para a IA e sistema.

CREATE TABLE IF NOT EXISTS public.api_references (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL, -- ex: 'z-api'
  category text NOT NULL, -- ex: 'messages', 'status', 'instance', 'webhooks'
  endpoint_name text NOT NULL,
  http_method text NOT NULL DEFAULT 'POST',
  path text NOT NULL,
  description text,
  payload_example jsonb,
  is_implemented boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(provider, path)
);

-- Habilita RLS
ALTER TABLE public.api_references ENABLE ROW LEVEL SECURITY;
CREATE POLICY "api_references_read_auth" ON public.api_references FOR SELECT TO authenticated USING (true);

-- Popula com as principais funcionalidades da Z-API
INSERT INTO public.api_references (provider, category, endpoint_name, path, description, is_implemented)
VALUES 
  ('z-api', 'messages', 'Send Text', '/send-text', 'Envia mensagem de texto simples.', true),
  ('z-api', 'messages', 'Send Image', '/send-image', 'Envia imagem com legenda opcional.', true),
  ('z-api', 'messages', 'Send Video', '/send-video', 'Envia vídeo com legenda opcional.', false),
  ('z-api', 'messages', 'Send Audio', '/send-audio', 'Envia áudio (PTT ou arquivo).', false),
  ('z-api', 'messages', 'Send Document', '/send-document/pdf', 'Envia documento PDF.', true),
  ('z-api', 'messages', 'Send Link', '/send-link', 'Envia link com preview customizado.', true),
  ('z-api', 'messages', 'Send Contact', '/send-contact', 'Envia contato (VCard).', false),
  ('z-api', 'messages', 'Send Location', '/send-location', 'Envia localização geográfica.', false),
  ('z-api', 'status', 'Send Text Status', '/send-text-status', 'Posta texto no Status (Stories).', false),
  ('z-api', 'status', 'Send Image Status', '/send-image-status', 'Posta imagem no Status (Stories).', false),
  ('z-api', 'status', 'Send Video Status', '/send-video-status', 'Posta vídeo no Status (Stories).', false),
  ('z-api', 'instance', 'Get QR Code', '/qr-code', 'Obtém o QR Code para conexão.', false),
  ('z-api', 'instance', 'Get Status', '/status', 'Verifica se a instância está conectada.', false),
  ('z-api', 'instance', 'Restart', '/restart', 'Reinicia a instância do WhatsApp.', false),
  ('z-api', 'webhooks', 'Set Webhook', '/set-webhook', 'Configura URL de callback.', false),
  ('z-api', 'webhooks', 'Get Webhooks', '/webhooks', 'Lista webhooks configurados.', false);
