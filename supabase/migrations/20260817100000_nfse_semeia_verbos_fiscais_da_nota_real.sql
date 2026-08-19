-- [F-NFSE] Semente dos verbos fiscais a partir de NOTA REAL da HBR
--
-- Fonte: NFS-e nacional nº 11 de 17/12/2025 (Emissor Nacional web, XML fornecido pelo
-- dono em 17/08/2026) — nota emitida pela contabilidade da HBR:
--   cTribNac = 140101 (14.01 — manutenção/conserto; peças ficam no ICMS)
--   pAliqAplic = 3,00% (alíquota de ISS de Itajaí para o 14.01)
--   tpRetISSQN = 1 (sem retenção, tomador PJ)
--   Serviço faturado: "Instalação e configuração de flaps hidráulicos" → a própria
--   contabilidade classifica INSTALAÇÃO como 14.01 (não 14.06).
-- CNAE 3317102 vem do cadastro da empresa no console da Contora (parametrizado lá).
--
-- Semeados 8 dos 10 verbos. Ficam SEM código, de propósito:
--   - projeto: laudo/projeto técnico tende a 31.01 (310102, ISS 5% em Itajaí) — sem
--     evidência em nota real; decisão da contadora.
--   - logistica: o serviço "MÃO DE OBRA" (R$ 12k) está classificado nesse verbo com
--     suspeita registrada (NOVO-012); dar código a ele antes de reclassificar seria
--     declarar atividade que ninguém confirmou.
--
-- Marcados "A VALIDAR" nas notes: a fonte é a prática real da contadora, não uma
-- confirmação formal dela. Reversível: basta limpar as colunas default_*.
-- Só preenche verbo ainda VAZIO — nunca sobrescreve valor que alguém já tenha gravado.
update public.service_fiscal_verbs
   set default_national_tax_code = '140101',
       default_cnae              = '3317102',
       default_iss_rate          = 3,
       default_service_code      = '14.01',
       notes = 'Semeado em 17/08/2026 a partir da NFS-e real nº 11 de 17/12/2025 '
             || '(cTribNac 140101, ISS 3%, sem retenção) + CNAE do cadastro Contora. '
             || 'A VALIDAR com a contadora.',
       updated_at = now()
 where verb_slug in (
         'adequacao', 'configuracao', 'diagnostico', 'instalacao',
         'manutencao', 'remocao', 'reparo', 'substituicao'
       )
   and default_national_tax_code is null;
