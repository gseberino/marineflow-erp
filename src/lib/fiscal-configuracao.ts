/**
 * Dados fiscais da empresa emitente: o formulário a partir do cadastro e a conversão de volta
 * para o banco. Extraído de FiscalEmission.tsx no D33 (01/10/2026), para ter teste.
 */

export interface FormularioFiscalDaEmpresa {
  legal_name: string;
  trade_name: string;
  cnpj: string;
  state_registration: string;
  municipal_registration: string;
  tax_regime: string;
  crt: number;
  state_code: string;
  street: string;
  number: string;
  district: string;
  city_name: string;
  postal_code: string;
  /**
   * Série da NF-e em produção (configurável): empresas que já emitiram em outro sistema usam
   * uma série nova para começar a numeração limpa (evita a Rejeição 539, "número já
   * utilizado"). Homologação fica sempre na série 2.
   */
  nfe_series_producao: number;
  // ── NFS-e (padrão nacional) ──
  ibge_city_code: string;
  nfse_standard: string;
  /**
   * pTotTribSN: carga TOTAL da faixa do Simples (não é a alíquota de ISS). Sem ele a NFS-e do
   * optante é rejeitada com E0712. Texto no formulário; vira número ou null ao salvar.
   */
  nfse_total_tax_rate_sn: string | number;
  nfse_municipal_registration_in_cnc: boolean;
  nfse_default_series: number;
}

/** O formulário com que o diálogo abre: o cadastro da empresa, ou os padrões se ainda não há. */
export function formularioDaEmpresa(company: Record<string, unknown> | null | undefined): FormularioFiscalDaEmpresa {
  const c = (company ?? {}) as Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any
  return {
    legal_name: c.legal_name || '',
    trade_name: c.trade_name || '',
    cnpj: c.cnpj || '',
    state_registration: c.state_registration || '',
    municipal_registration: c.municipal_registration || '',
    tax_regime: c.tax_regime || 'simples',
    crt: c.crt ?? 1,
    state_code: c.state_code || '',
    street: c.street || '',
    number: c.number || '',
    district: c.district || '',
    city_name: c.city_name || '',
    postal_code: c.postal_code || '',
    nfe_series_producao: c.nfe_series_producao ?? 1,
    ibge_city_code: c.ibge_city_code || '',
    nfse_standard: c.nfse_standard || 'nacional',
    nfse_total_tax_rate_sn: c.nfse_total_tax_rate_sn ?? '',
    nfse_municipal_registration_in_cnc: c.nfse_municipal_registration_in_cnc !== false,
    nfse_default_series: c.nfse_default_series ?? 1,
  };
}

/**
 * O que vai para company_fiscal_settings. Campos da NFS-e: vazio no formulário vira null no
 * banco (colunas numéricas/nullable); pTotTribSN zero é um valor (não vira null).
 */
export function payloadDasConfiguracoes(form: FormularioFiscalDaEmpresa, agora: Date = new Date()) {
  return {
    ...form,
    ibge_city_code: String(form.ibge_city_code).trim() || null,
    nfse_total_tax_rate_sn:
      form.nfse_total_tax_rate_sn === '' || form.nfse_total_tax_rate_sn == null
        ? null
        : Number(form.nfse_total_tax_rate_sn),
    nfse_default_series: Number(form.nfse_default_series) || 1,
    updated_at: agora.toISOString(),
  };
}
