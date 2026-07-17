-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: arquivamento do DANFE (PDF) — issued_fiscal_documents.pdf_storage_path
--   • Hoje só o XML autorizado é arquivado no bucket `fiscal-xml`
--     (xml_storage_path). Para enviar o DANFE ao cliente (WhatsApp) precisamos
--     de uma URL assinada do PDF, sem expor o token da Contora — então
--     passamos a arquivar também os bytes do PDF no mesmo bucket.
--   • apply-status.ts baixa o pdf_danfe autenticado (fetchArtifact) e grava o
--     caminho aqui; fiscal-reconcile re-tenta quando pdf_storage_path é nulo.
-- 100% idempotente. Sem segredos. Nenhuma escrita de dado fiscal.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE issued_fiscal_documents
  ADD COLUMN IF NOT EXISTS pdf_storage_path text;

COMMENT ON COLUMN issued_fiscal_documents.pdf_storage_path IS
  'Caminho do DANFE (PDF) arquivado no bucket fiscal-xml: {env}/{type}/{id}.pdf. Usado para gerar URL assinada e enviar ao cliente.';

-- Leitura do bucket fiscal-xml para ADMIN (gerar URL assinada do DANFE/XML e
-- enviar ao cliente por WhatsApp). Simétrico ao ifd_select (SELECT só admin):
-- os PDFs/XMLs contêm CPF/CNPJ, endereço e chave de acesso — só admin vê dados
-- fiscais no app. ESCRITA continua exclusiva do service_role (sem policy de
-- INSERT/UPDATE) — o front nunca grava no bucket, só o arquiva via edge.
DROP POLICY IF EXISTS "fiscal_xml_admin_read" ON storage.objects;
CREATE POLICY "fiscal_xml_admin_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'fiscal-xml' AND public.is_admin(auth.uid()));
