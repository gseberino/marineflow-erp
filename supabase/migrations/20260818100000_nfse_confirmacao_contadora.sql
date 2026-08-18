-- [F-NFSE] Confirmações da CONTABILIDADE (repassadas pelo dono em 18/08/2026)
--
-- Respostas oficiais:
--   1. HBR é OPTANTE do Simples Nacional desde JANEIRO/2026 (a NFS-e de dez/2025 saiu
--      como não optante porque a opção ainda não valia — mistério resolvido).
--   2. pTotTribSN = 6% CONFIRMADO (deixa de ser provisório).
--   3. Laudos/projetos: "manter tudo no 14.01" → verbo projeto recebe 140101.
--   4. Sem obrigação de reter ISS (nós recolhemos) → iss_withheld false permanece.
--   5. CNC: "Itajaí não utiliza o CNC [em produção]; usa os dados do cartão CNPJ da RFB"
--      → a flag nfse_municipal_registration_in_cnc_producao=false da Contora é o estado
--      PERMANENTE correto (produção omite a IM; homologação, que tem registro no CNC,
--      continua enviando).
--
-- a) Verbos restantes recebem o 14.01 ("manter tudo no 14.01"):
--    - projeto: resposta explícita da contadora.
--    - logistica: coberto pelo "tudo"; o conteúdo real do verbo hoje é deslocamento
--      cobrado junto do serviço (acessório do 14.01). Se um dia existir TRANSPORTE como
--      atividade autônoma, é item 16 da LC 116 — reavaliar (anotado nas notes).
update public.service_fiscal_verbs
   set default_national_tax_code = '140101',
       default_cnae              = '3317102',
       default_iss_rate          = 3,
       default_service_code      = '14.01',
       notes = 'CONFIRMADO pela contadora em 18/08/2026 ("manter tudo no 14.01"). '
             || case when verb_slug = 'logistica'
                     then 'Atenção: vale para deslocamento acessório ao serviço; '
                       || 'transporte como atividade autônoma seria item 16 da LC 116 — reavaliar se surgir. '
                     else '' end
             || 'ISS 3% Itajaí, sem retenção.',
       updated_at = now()
 where verb_slug in ('projeto', 'logistica')
   and default_national_tax_code is null;

-- b) Os 8 verbos semeados da nota real saem de "A VALIDAR" para CONFIRMADO.
update public.service_fiscal_verbs
   set notes = 'Semeado da NFS-e real nº 11 (17/12/2025) e CONFIRMADO pela contadora em '
             || '18/08/2026: 140101 (14.01), CNAE 3317102, ISS 3% Itajaí, sem retenção.',
       updated_at = now()
 where verb_slug in (
         'adequacao', 'configuracao', 'diagnostico', 'instalacao',
         'manutencao', 'remocao', 'reparo', 'substituicao'
       )
   and default_national_tax_code = '140101';

-- c) O serviço "MÃO DE OBRA" (R$ 12k, NOVO-012) ficou fora do backfill de fiscal_verb de
--    propósito ("atividade não confirmada"). A contadora confirmou: mão de obra é 14.01.
--    Recebe cadastro fiscal PRÓPRIO (não herda — a classificação operacional 'logistica'
--    segue suspeita e é outra discussão; o fiscal agora está explícito e correto).
update public.services
   set national_tax_code = '140101',
       cnae              = '3317102',
       iss_rate          = 3,
       service_code      = '14.01',
       updated_at        = now()
 where upper(btrim(translate(name, 'ÃÁÂÀÇÉÊÍÓÔÕÚ', 'AAAACEEIOOOU'))) = 'MAO DE OBRA'
   and national_tax_code is null;
