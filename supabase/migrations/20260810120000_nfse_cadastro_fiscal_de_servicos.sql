-- [B1 / F-NFSE-01] Cadastro fiscal de serviços e settings de NFS-e.
--
-- A NF-e é documento de PRODUTO; a mão de obra sempre ficou de fora e o `fiscal-emit` já a
-- devolve pronta no seam `servicos_para_nfse`. O que faltava para emitir era o cadastro
-- fiscal do serviço — sem ele não há código de tributação, CNAE nem alíquota para montar
-- o payload.
--
-- CADA CAMPO AQUI EXISTE PARA EVITAR UMA REJEIÇÃO ESPECÍFICA DA CONTORA/SISTEMA NACIONAL:
--
--   national_tax_code                  → E0310 quando o código de 6 dígitos não existe na
--                                        lista nacional. Atenção: o nacional NÃO é o
--                                        municipal sem os pontos — "14.01" vira "140101",
--                                        não "140100".
--   nfse_total_tax_rate_sn             → E0712. O padrão nacional recusa o INDICADOR de
--                                        valor total de tributos para ME/EPP e exige o
--                                        percentual da faixa do Simples. A HBR é Simples,
--                                        então isto é obrigatório, não opcional.
--   nfse_simples_nacional_option       → E0160 quando o regime declarado diverge do cadastro
--                                        do Simples na competência (o cadastro é que vale).
--   nfse_municipal_registration_in_cnc → E0120 quando a inscrição municipal é enviada mas o
--                                        município não tem dados no CNC NFS-e.
--   nfse_standard                      → quem decide o caminho não é o regime da empresa: é o
--                                        MUNICÍPIO. Onde aderiu ao Sistema Nacional, vale o
--                                        padrão nacional; onde mantém layout próprio, o
--                                        provedor municipal. Itajaí/SC será confirmado pelo
--                                        pre-flight (GET /companies/{id}/nfse/health) antes
--                                        da primeira emissão.
--
-- Os CHECKs guardam o formato no BANCO em vez de só na aplicação: um CNAE com 6 dígitos só
-- apareceria como rejeição da prefeitura, minutos depois e longe da causa.

-- ── a. Cadastro fiscal do serviço ────────────────────────────────────────────
alter table public.services
  add column if not exists national_tax_code text,
  add column if not exists service_code      text,
  add column if not exists cnae              text,
  add column if not exists iss_rate          numeric,
  add column if not exists iss_withheld      boolean not null default false;

comment on column public.services.national_tax_code is
  'Codigo de tributacao NACIONAL, 6 digitos sem pontuacao (ex.: 140101). Obrigatorio no padrao nacional. Nao e o municipal sem os pontos.';
comment on column public.services.service_code is
  'Codigo MUNICIPAL do servico, informativo no padrao nacional. Pode ser pontuado (ex.: 01.05.01).';
comment on column public.services.cnae is
  'CNAE com 7 digitos, sem pontuacao (ex.: 3313901 = manutencao e reparacao de motores eletricos).';
comment on column public.services.iss_rate is
  'Aliquota de ISS em PERCENTUAL (5 = 5%), nao fracao. Para MEI, 0 e aceito quando for o enquadramento.';
comment on column public.services.iss_withheld is
  'ISS retido na fonte pelo tomador.';

-- Formato validado no banco. `is null or` mantém o cadastro incompleto possível: o serviço
-- existe no ERP muito antes de alguém saber seu código fiscal, e travar o INSERT aqui
-- impediria de cadastrar serviço nenhum. Quem exige preenchimento é o builder da NFS-e,
-- no momento em que a nota vai sair.
alter table public.services
  drop constraint if exists services_national_tax_code_formato;
alter table public.services
  add constraint services_national_tax_code_formato
  check (national_tax_code is null or national_tax_code ~ '^[0-9]{6}$');

alter table public.services
  drop constraint if exists services_cnae_formato;
alter table public.services
  add constraint services_cnae_formato
  check (cnae is null or cnae ~ '^[0-9]{7}$');

alter table public.services
  drop constraint if exists services_iss_rate_faixa;
alter table public.services
  add constraint services_iss_rate_faixa
  check (iss_rate is null or (iss_rate >= 0 and iss_rate <= 100));

-- ── b. Settings de NFS-e da empresa ──────────────────────────────────────────
alter table public.company_fiscal_settings
  add column if not exists nfse_standard                      text    not null default 'nacional',
  add column if not exists nfse_total_tax_rate_sn             numeric,
  add column if not exists nfse_simples_nacional_option       smallint,
  add column if not exists nfse_municipal_registration_in_cnc boolean not null default true,
  add column if not exists nfse_default_series                integer not null default 1;

comment on column public.company_fiscal_settings.nfse_standard is
  'nacional | municipal. Quem decide e o MUNICIPIO, nao o regime da empresa. Confirmar em GET /companies/{id}/nfse/health antes da primeira emissao.';
comment on column public.company_fiscal_settings.nfse_total_tax_rate_sn is
  'Percentual TOTAL de tributos da faixa do Simples na competencia — so a contabilidade sabe. Obrigatorio para ME/EPP no padrao nacional (E0712). Nao e a aliquota de ISS.';
comment on column public.company_fiscal_settings.nfse_simples_nacional_option is
  '1 nao optante | 2 optante MEI | 3 optante ME/EPP. Preencher so quando o regime cadastrado divergir do cadastro do Simples (E0160).';
comment on column public.company_fiscal_settings.nfse_municipal_registration_in_cnc is
  'A inscricao municipal so entra no documento quando o municipio tem dados no CNC NFS-e. Onde nao tem, o envio e recusado com E0120 — ai marque false.';
comment on column public.company_fiscal_settings.nfse_default_series is
  'Serie padrao da NFS-e. Separada de nfe_series_producao: sao numeracoes independentes.';

alter table public.company_fiscal_settings
  drop constraint if exists cfs_nfse_standard_valido;
alter table public.company_fiscal_settings
  add constraint cfs_nfse_standard_valido
  check (nfse_standard in ('nacional', 'municipal'));

alter table public.company_fiscal_settings
  drop constraint if exists cfs_nfse_simples_option_valido;
alter table public.company_fiscal_settings
  add constraint cfs_nfse_simples_option_valido
  check (nfse_simples_nacional_option is null
         or nfse_simples_nacional_option in (1, 2, 3));

alter table public.company_fiscal_settings
  drop constraint if exists cfs_nfse_total_tax_rate_sn_faixa;
alter table public.company_fiscal_settings
  add constraint cfs_nfse_total_tax_rate_sn_faixa
  check (nfse_total_tax_rate_sn is null
         or (nfse_total_tax_rate_sn >= 0 and nfse_total_tax_rate_sn <= 100));

-- ── RLS ──────────────────────────────────────────────────────────────────────
-- Nenhuma policy nova: `services` já tem `authenticated_all_services` (ALL, TO authenticated)
-- e `company_fiscal_settings` já restringe leitura E escrita a admin via public.is_admin().
-- Coluna nova herda a policy da tabela — o que NÃO se herda é o GRANT, que vem aberto por
-- padrão no Supabase. Revogar de `anon` é o passo que costuma ser esquecido, e aqui o dado é
-- CNPJ, inscrição municipal e carga tributária da empresa.
revoke all on public.services                from anon;
revoke all on public.company_fiscal_settings from anon;
