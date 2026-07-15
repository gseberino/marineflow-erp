-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: fundação da EMISSÃO fiscal (NF-e/NFS-e) — saída
--   • company_fiscal_settings  (dados do emitente + ids da Contora)
--   • issued_fiscal_documents  (documentos EMITIDOS; distinto de fiscal_notes/entrada)
--   • fiscal_document_sequences + RPC next_fiscal_number (numeração atômica)
--   • bucket de Storage fiscal-xml (guarda legal do XML autorizado, ≥5 anos)
-- 100% idempotente. NÃO contém segredos: token/certificado ficam em Function Secrets
-- e no provedor (Contora), respectivamente.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Emitente (config da própria empresa). Sem CNPJ do certificado aqui.
CREATE TABLE IF NOT EXISTS company_fiscal_settings (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name              text,
  trade_name              text,
  cnpj                    text UNIQUE,
  state_registration      text,          -- IE
  municipal_registration  text,          -- IM (NFS-e)
  tax_regime              text NOT NULL DEFAULT 'simples',  -- mei|simples|presumido|real
  crt                     int  NOT NULL DEFAULT 1,          -- Código de Regime Tributário (1=Simples)
  street                  text,
  number                  text,
  complement              text,
  district                text,
  city_name               text,
  ibge_city_code          text,          -- código IBGE do município
  state_code              text,          -- UF
  postal_code             text,
  provider                text NOT NULL DEFAULT 'contora',
  contora_template_id     text,          -- template "Venda Padrão Simples Nacional" (POST /templates)
  active_environment      text NOT NULL DEFAULT 'homologacao', -- homologacao|producao
  created_at              timestamptz DEFAULT now(),
  updated_at              timestamptz DEFAULT now()
);

ALTER TABLE company_fiscal_settings
  DROP CONSTRAINT IF EXISTS chk_cfs_tax_regime;
ALTER TABLE company_fiscal_settings
  ADD CONSTRAINT chk_cfs_tax_regime CHECK (tax_regime IN ('mei','simples','presumido','real'));
ALTER TABLE company_fiscal_settings
  DROP CONSTRAINT IF EXISTS chk_cfs_environment;
ALTER TABLE company_fiscal_settings
  ADD CONSTRAINT chk_cfs_environment CHECK (active_environment IN ('homologacao','producao'));

-- 2. Documentos fiscais EMITIDOS (saída).
CREATE TABLE IF NOT EXISTS issued_fiscal_documents (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_type         text NOT NULL,                 -- nfe|nfce|nfse
  origin_type           text NOT NULL DEFAULT 'manual', -- invoice|service_order|manual
  origin_id             uuid,
  client_id             uuid,
  provider              text NOT NULL DEFAULT 'contora',
  provider_document_id  text,                          -- id do documento no provedor
  environment           text NOT NULL DEFAULT 'homologacao',
  series                int,
  number                int,
  access_key            text,                          -- chave de acesso (NF-e)
  protocol              text,
  status                text NOT NULL DEFAULT 'draft',
  status_code           text,                          -- ex.: SEFAZ "100"
  status_message        text,
  xml_url               text,                          -- URL do provedor (pode expirar)
  xml_storage_path      text,                          -- caminho no bucket fiscal-xml (retenção)
  pdf_url               text,                          -- DANFE/DANFSe
  idempotency_key       text,
  request_payload       jsonb,
  provider_status       jsonb,
  authorized_at         timestamptz,
  cancelled_at          timestamptz,
  created_at            timestamptz DEFAULT now(),
  updated_at            timestamptz DEFAULT now()
);

ALTER TABLE issued_fiscal_documents DROP CONSTRAINT IF EXISTS chk_ifd_document_type;
ALTER TABLE issued_fiscal_documents ADD CONSTRAINT chk_ifd_document_type
  CHECK (document_type IN ('nfe','nfce','nfse'));
ALTER TABLE issued_fiscal_documents DROP CONSTRAINT IF EXISTS chk_ifd_origin_type;
ALTER TABLE issued_fiscal_documents ADD CONSTRAINT chk_ifd_origin_type
  CHECK (origin_type IN ('invoice','service_order','manual'));
ALTER TABLE issued_fiscal_documents DROP CONSTRAINT IF EXISTS chk_ifd_environment;
ALTER TABLE issued_fiscal_documents ADD CONSTRAINT chk_ifd_environment
  CHECK (environment IN ('homologacao','producao'));
ALTER TABLE issued_fiscal_documents DROP CONSTRAINT IF EXISTS chk_ifd_status;
ALTER TABLE issued_fiscal_documents ADD CONSTRAINT chk_ifd_status
  CHECK (status IN ('draft','queued','processing','authorized','rejected','failed','cancelled'));

CREATE INDEX IF NOT EXISTS idx_ifd_status        ON issued_fiscal_documents (status);
CREATE INDEX IF NOT EXISTS idx_ifd_origin        ON issued_fiscal_documents (origin_type, origin_id);
CREATE INDEX IF NOT EXISTS idx_ifd_provider_doc  ON issued_fiscal_documents (provider_document_id);
CREATE INDEX IF NOT EXISTS idx_ifd_created_at    ON issued_fiscal_documents (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ifd_access_key    ON issued_fiscal_documents (access_key);

-- Idempotência: uma emissão ativa/autorizada por origem (permite reemitir após rejeição/falha/cancelamento).
CREATE UNIQUE INDEX IF NOT EXISTS uq_ifd_active_per_origin
  ON issued_fiscal_documents (origin_type, origin_id, document_type)
  WHERE origin_id IS NOT NULL AND status IN ('draft','queued','processing','authorized');
CREATE UNIQUE INDEX IF NOT EXISTS uq_ifd_idempotency_key
  ON issued_fiscal_documents (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- 3. Numeração atômica por (document_type, série, ambiente) — evita rejeições 204/539.
CREATE TABLE IF NOT EXISTS fiscal_document_sequences (
  document_type  text NOT NULL,
  series         int  NOT NULL DEFAULT 1,
  environment    text NOT NULL DEFAULT 'homologacao',
  last_number    int  NOT NULL DEFAULT 0,
  updated_at     timestamptz DEFAULT now(),
  PRIMARY KEY (document_type, series, environment)
);

CREATE OR REPLACE FUNCTION next_fiscal_number(
  p_document_type text,
  p_series        int DEFAULT 1,
  p_environment   text DEFAULT 'homologacao'
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next int;
BEGIN
  INSERT INTO fiscal_document_sequences (document_type, series, environment, last_number, updated_at)
  VALUES (p_document_type, p_series, p_environment, 1, now())
  ON CONFLICT (document_type, series, environment)
  DO UPDATE SET last_number = fiscal_document_sequences.last_number + 1,
                updated_at  = now()
  RETURNING last_number INTO v_next;
  RETURN v_next;
END;
$$;

-- Reserva de número é operação de servidor (edge function com service_role). Não expor ao front.
-- NOTA: "REVOKE ... FROM PUBLIC" sozinho NÃO bloqueia anon/authenticated — o
-- Supabase concede EXECUTE a esses papéis diretamente (não via PUBLIC) por
-- padrão em funções novas no schema public (confirmado via get_advisors após
-- o primeiro deploy). Por isso os REVOKEs explícitos abaixo são obrigatórios.
REVOKE ALL ON FUNCTION next_fiscal_number(text, int, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION next_fiscal_number(text, int, text) FROM anon;
REVOKE EXECUTE ON FUNCTION next_fiscal_number(text, int, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION next_fiscal_number(text, int, text) TO service_role;

-- 4. Bucket privado para guarda do XML autorizado (retenção legal ≥ 5 anos).
INSERT INTO storage.buckets (id, name, public)
VALUES ('fiscal-xml', 'fiscal-xml', false)
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RLS
--   • Leitura (histórico) liberada a usuários autenticados; o app já restringe as
--     rotas fiscais a admin no ProtectedRoute.
--   • ESCRITA de issued_fiscal_documents e sequences NÃO tem policy para
--     authenticated ⇒ só o service_role (edge functions) grava. Emissão nunca é
--     forjada pelo front.
--   • company_fiscal_settings é gerenciada na tela de configurações (admin).
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE company_fiscal_settings     ENABLE ROW LEVEL SECURITY;
ALTER TABLE issued_fiscal_documents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE fiscal_document_sequences    ENABLE ROW LEVEL SECURITY;

-- Leitura E escrita restritas a admin via public.is_admin() — CNPJ/IE/IM/regime
-- da empresa e o conteúdo de toda nota emitida (CPF/CNPJ e endereço de
-- clientes, chave de acesso, payloads) são dados sensíveis; "authenticated"
-- sozinho exporia isso a qualquer perfil (técnico/vendedor), não só admin.
DROP POLICY IF EXISTS "cfs_select"  ON company_fiscal_settings;
DROP POLICY IF EXISTS "cfs_insert"  ON company_fiscal_settings;
DROP POLICY IF EXISTS "cfs_update"  ON company_fiscal_settings;
CREATE POLICY "cfs_select" ON company_fiscal_settings FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
CREATE POLICY "cfs_insert" ON company_fiscal_settings FOR INSERT TO authenticated WITH CHECK (public.is_admin(auth.uid()));
CREATE POLICY "cfs_update" ON company_fiscal_settings FOR UPDATE TO authenticated USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "ifd_select" ON issued_fiscal_documents;
CREATE POLICY "ifd_select" ON issued_fiscal_documents FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));
-- (sem policies de INSERT/UPDATE para authenticated: escrita apenas via service_role)

-- Garante no máximo uma linha em company_fiscal_settings (é uma tela de
-- configuração singleton) — sem isso, dois admins salvando ao mesmo tempo na
-- primeira configuração criam duas linhas, e qual delas um SELECT ... LIMIT 1
-- sem ORDER BY retorna passa a ser não-determinístico.
ALTER TABLE company_fiscal_settings
  ADD COLUMN IF NOT EXISTS singleton_guard boolean NOT NULL DEFAULT true;
ALTER TABLE company_fiscal_settings
  DROP CONSTRAINT IF EXISTS uq_company_fiscal_settings_singleton;
ALTER TABLE company_fiscal_settings
  ADD CONSTRAINT uq_company_fiscal_settings_singleton UNIQUE (singleton_guard);
