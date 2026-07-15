-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: NF-e completa — CST de PIS/COFINS (defaults globais) + IE do destinatário
--   • app_settings: chaves default_pis_cst / default_cofins_cst → códigos CST
--     usados no bloco `taxes` de cada item (o produto guarda só a alíquota).
--     app_settings é key/value (colunas key, value) — inserimos como LINHAS,
--     no mesmo padrão de default_csosn/default_icms_rate já existentes.
--   • clients.state_registration (IE) + clients.ie_indicator (indicador de IE)
--     → para emitir a contribuintes do ICMS (indIEDest=1 exige IE) e reaproveitar
--     o dado em emissões futuras.
-- 100% idempotente. Sem segredos.
-- ─────────────────────────────────────────────────────────────────────────────

-- CST de PIS/COFINS. "49" (outras operações) é o default mais seguro para Simples
-- Nacional; a contadora pode ajustar em Configurações depois. Só a alíquota mora
-- no produto; o CST é global.
INSERT INTO app_settings (key, value)
VALUES ('default_pis_cst', '49'), ('default_cofins_cst', '49')
ON CONFLICT (key) DO NOTHING;

-- IE e indicador de IE do cliente (destinatário da NF-e).
--   ie_indicator: 1=contribuinte ICMS, 2=isento de IE, 9=não contribuinte (default).
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS state_registration text,
  ADD COLUMN IF NOT EXISTS ie_indicator       integer DEFAULT 9;

ALTER TABLE clients DROP CONSTRAINT IF EXISTS chk_clients_ie_indicator;
ALTER TABLE clients ADD CONSTRAINT chk_clients_ie_indicator
  CHECK (ie_indicator IS NULL OR ie_indicator IN (1, 2, 9));
