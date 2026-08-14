-- [F-NFSE] pTotTribSN provisório + código IBGE do emitente
--
-- Decisão do dono (13/08/2026, sessão nfse-um-clique): usar 6,00% (1ª faixa do Anexo III)
-- como percentual total de tributos do Simples (pTotTribSN) PROVISÓRIO, só para destravar a
-- homologação — a ausência do campo rejeita a NFS-e do optante com E0712. O valor definitivo
-- é da contabilidade (é a carga total da faixa do Simples na competência, NÃO a alíquota de
-- ISS), e a UI de Dados da Empresa exibe o aviso "a validar com a contadora".
--
-- Não sobrescreve valor já preenchido: se a contabilidade (ou alguém) já gravou o percentual,
-- esta migration não toca nele.
update public.company_fiscal_settings
   set nfse_total_tax_rate_sn = 6.00,
       updated_at = now()
 where nfse_total_tax_rate_sn is null;

-- Código IBGE de Itajaí/SC (4208203) — a coluna estava NULA desde a criação da tabela.
-- O cadastro da empresa na Contora já tem o município, mas o nosso lado usa ibge_city_code
-- em diagnósticos e na montagem local de payloads. Guarda por city_name para nunca gravar
-- o código de Itajaí numa empresa que não seja de lá.
update public.company_fiscal_settings
   set ibge_city_code = '4208203',
       updated_at = now()
 where (ibge_city_code is null or btrim(ibge_city_code) = '')
   and city_name ilike 'itaja%';
