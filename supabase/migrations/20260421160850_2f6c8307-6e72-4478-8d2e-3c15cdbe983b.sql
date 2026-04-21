
-- ============================================================
-- Assinatura digital pelo link público da OS
-- ============================================================

-- 1) Tabela de assinaturas (histórico completo)
CREATE TABLE public.service_order_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_order_id uuid NOT NULL REFERENCES public.service_orders(id) ON DELETE CASCADE,
  share_token uuid NOT NULL,
  signature_image_url text,                      -- PNG do desenho (storage)
  accepted_name text NOT NULL,                   -- nome digitado pelo cliente
  accepted_terms_snapshot text,                  -- termos vigentes no momento do aceite
  document_hash text NOT NULL,                   -- hash do conteúdo da OS no momento
  ip_address text,
  user_agent text,
  signed_at timestamptz NOT NULL DEFAULT now(),
  superseded_at timestamptz,                     -- preenchido quando OS é alterada
  superseded_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_so_signatures_service_order ON public.service_order_signatures(service_order_id);
CREATE INDEX idx_so_signatures_signed_at ON public.service_order_signatures(signed_at DESC);

-- 2) Colunas na service_orders para refletir status de assinatura
ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS signed_at timestamptz,
  ADD COLUMN IF NOT EXISTS signed_document_hash text,
  ADD COLUMN IF NOT EXISTS signed_by_name text,
  ADD COLUMN IF NOT EXISTS requires_resignature boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS resignature_requested_at timestamptz;

-- 3) RLS na tabela de assinaturas
ALTER TABLE public.service_order_signatures ENABLE ROW LEVEL SECURITY;

-- Authenticated lê tudo (equipe interna)
CREATE POLICY "auth_read_signatures"
ON public.service_order_signatures
FOR SELECT
TO authenticated
USING (auth.uid() IS NOT NULL);

-- Authenticated pode atualizar (para marcar superseded)
CREATE POLICY "auth_update_signatures"
ON public.service_order_signatures
FOR UPDATE
TO authenticated
USING (auth.uid() IS NOT NULL)
WITH CHECK (auth.uid() IS NOT NULL);

-- Anon pode ler assinaturas vinculadas a uma OS com share_token válido
-- (necessário para a página pública mostrar "Assinado em")
CREATE POLICY "anon_read_signatures_by_token"
ON public.service_order_signatures
FOR SELECT
TO anon
USING (
  EXISTS (
    SELECT 1 FROM public.service_orders so
    WHERE so.id = service_order_signatures.service_order_id
      AND so.share_token IS NOT NULL
      AND so.share_token = service_order_signatures.share_token
  )
);

-- INSERT por anon será feito EXCLUSIVAMENTE via edge function com service_role,
-- então NÃO criamos política de INSERT para anon (mais seguro).

-- 4) Storage bucket para imagens de assinatura
INSERT INTO storage.buckets (id, name, public)
VALUES ('signatures', 'signatures', true)
ON CONFLICT (id) DO NOTHING;

-- Policies do bucket: leitura pública, escrita só via service_role
CREATE POLICY "signatures_public_read"
ON storage.objects FOR SELECT
USING (bucket_id = 'signatures');

-- 5) Settings keys para controlar quais blocos aparecem no link público
INSERT INTO public.app_settings (key, value, description) VALUES
  ('public_view_show_service_prices', 'true', 'Mostrar preços de serviços no link público'),
  ('public_view_show_parts_prices', 'true', 'Mostrar preços de peças no link público'),
  ('public_view_show_travel_cost', 'true', 'Mostrar custo de deslocamento no link público'),
  ('public_view_show_discount', 'true', 'Mostrar desconto no link público'),
  ('public_view_show_tax', 'true', 'Mostrar impostos no link público'),
  ('public_view_show_terms', 'true', 'Mostrar termos e condições no link público'),
  ('public_view_show_bank_details', 'true', 'Mostrar dados bancários no link público'),
  ('public_view_show_payment_instructions', 'true', 'Mostrar instruções de pagamento no link público'),
  ('public_view_show_extra_notes', 'true', 'Mostrar notas extras no link público'),
  ('public_view_show_validity', 'true', 'Mostrar validade do orçamento no link público'),
  ('public_view_allow_signature', 'true', 'Permitir assinatura digital pelo link público'),
  ('signature_status_after', 'approved', 'Status para o qual a OS muda após assinatura do cliente')
ON CONFLICT (key) DO NOTHING;
