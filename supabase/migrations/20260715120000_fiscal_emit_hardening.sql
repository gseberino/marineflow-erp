-- ─────────────────────────────────────────────────────────────────────────────
-- Endurecimento pós-revisão da Fase 2 (emissão de NF-e), antes do go-live:
--   1. RLS SELECT em company_fiscal_settings/issued_fiscal_documents estava
--      liberado para qualquer "authenticated" — restringe a admin. Achado
--      pelo get_advisors/revisão de segurança: expunha CPF/CNPJ e endereço de
--      clientes de toda nota emitida a qualquer funcionário logado.
--   2. company_fiscal_settings não tinha garantia de linha única (tela de
--      config singleton) — adiciona constraint.
--   3. fiscal-reconcile (rede de segurança contra webhook perdido) nunca
--      tinha sido de fato agendada via pg_cron — só existia o código.
-- 100% idempotente.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "cfs_select" ON company_fiscal_settings;
CREATE POLICY "cfs_select" ON company_fiscal_settings
  FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "ifd_select" ON issued_fiscal_documents;
CREATE POLICY "ifd_select" ON issued_fiscal_documents
  FOR SELECT TO authenticated USING (public.is_admin(auth.uid()));

ALTER TABLE company_fiscal_settings
  ADD COLUMN IF NOT EXISTS singleton_guard boolean NOT NULL DEFAULT true;
ALTER TABLE company_fiscal_settings
  DROP CONSTRAINT IF EXISTS uq_company_fiscal_settings_singleton;
ALTER TABLE company_fiscal_settings
  ADD CONSTRAINT uq_company_fiscal_settings_singleton UNIQUE (singleton_guard);

-- Agenda a rede de segurança fiscal-reconcile — mesmo padrão já usado por
-- whatsapp-status-worker, ai-business-monitor, expire-pending-actions etc.
-- (segredo lido de app_settings.cron_worker_secret, comparado no lado da
-- function contra Deno.env.get("CRON_SECRET")). cron.schedule com um nome já
-- existente atualiza o job em vez de duplicar — seguro rodar de novo.
SELECT cron.schedule(
  'fiscal-reconcile',
  '*/15 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/fiscal-reconcile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$
);
