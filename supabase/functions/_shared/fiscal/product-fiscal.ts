// Resolve os atributos fiscais EFETIVOS de um item a partir de um produto,
// replicando exatamente a hierarquia de 3 níveis que a UI de produtos já usa
// (ver ProductFormDialog.tsx ~L250-253):
//
//   use_global_fiscal = false  → valores próprios do produto
//   use_global_fiscal = true   → default da categoria → default global (app_settings)
//
// Puro (sem fetch/Deno) — roda no Vitest e no edge fiscal-emit. É a fonte da
// verdade dos impostos por item; o diálogo de emissão usa o mesmo cálculo só
// para pré-preencher os campos (que o usuário ainda pode editar).

export interface ProductFiscalInput {
  ncm?: string | null;
  cfop?: string | null;
  unit?: string | null;
  csosn?: string | null;
  fiscal_origin?: number | null;
  icms_rate?: number | null;
  ipi_rate?: number | null;
  pis_rate?: number | null;
  cofins_rate?: number | null;
  use_global_fiscal?: boolean | null;
}

export interface CategoryFiscalDefaults {
  default_ncm?: string | null;
  default_csosn?: string | null;
  default_fiscal_origin?: number | null;
  default_icms_rate?: number | null;
  default_ipi_rate?: number | null;
  default_pis_rate?: number | null;
  default_cofins_rate?: number | null;
}

export interface GlobalFiscalDefaults {
  default_csosn?: string | null;
  default_fiscal_origin?: number | null;
  default_icms_rate?: number | null;
  default_ipi_rate?: number | null;
  default_pis_rate?: number | null;
  default_cofins_rate?: number | null;
  // CST de PIS/COFINS não existe no produto (só a alíquota); vive no global.
  // "49" = outras operações — default seguro p/ Simples, confirmar com a contadora.
  default_pis_cst?: string | null;
  default_cofins_cst?: string | null;
}

export interface ResolvedProductFiscal {
  ncm: string;
  csosn: string;
  origin: number;
  icmsRate: number;
  ipiRate: number;
  pisRate: number;
  cofinsRate: number;
  pisCst: string;
  cofinsCst: string;
}

// Fallbacks quando nada foi configurado (mesmos defaults do schema/DB).
// CSOSN 102 = Tributada pelo Simples SEM permissão de crédito (correto p/ revenda);
// 400 (não tributada) só serve p/ operações especiais (remessa/conserto/bonificação).
const FALLBACK_CSOSN = "102";
const FALLBACK_ORIGIN = 0;
const FALLBACK_PIS_CST = "49";
const FALLBACK_COFINS_CST = "49";

function firstStr(...vals: Array<string | null | undefined>): string | undefined {
  for (const v of vals) if (v != null && String(v).trim() !== "") return String(v);
  return undefined;
}

function firstNum(...vals: Array<number | null | undefined>): number | undefined {
  for (const v of vals) if (v != null && !Number.isNaN(Number(v))) return Number(v);
  return undefined;
}

/**
 * Os padrões fiscais globais (fim da hierarquia produto → categoria → global) a partir de
 * app_settings, um mapa chave → valor. Um lugar só para a tela de emissão (que pré-preenche os
 * impostos do item) e o fiscal-emit (que calcula os da nota): antes cada um tinha a sua cópia
 * desta conta (D33, 01/10/2026). Valor vazio ou que não é número fica de fora, e o resolver usa
 * o fallback.
 */
export function globalFiscalDefaultsFromSettings(
  settings: Record<string, unknown> | null | undefined,
): GlobalFiscalDefaults {
  const texto = (k: string) => (settings?.[k] == null ? "" : String(settings[k]));
  const numero = (k: string) => {
    const v = texto(k);
    return v !== "" && !Number.isNaN(Number(v)) ? Number(v) : undefined;
  };
  return {
    default_csosn: texto("default_csosn") || undefined,
    default_fiscal_origin: numero("default_fiscal_origin"),
    default_icms_rate: numero("default_icms_rate"),
    default_ipi_rate: numero("default_ipi_rate"),
    default_pis_rate: numero("default_pis_rate"),
    default_cofins_rate: numero("default_cofins_rate"),
    default_pis_cst: texto("default_pis_cst") || undefined,
    default_cofins_cst: texto("default_cofins_cst") || undefined,
  };
}

export function resolveProductFiscal(
  product: ProductFiscalInput | null | undefined,
  category?: CategoryFiscalDefaults | null,
  global?: GlobalFiscalDefaults | null,
): ResolvedProductFiscal {
  const p = product ?? {};
  const c = category ?? {};
  const g = global ?? {};
  const useGlobal = p.use_global_fiscal !== false;

  // NCM é intrínseco ao produto (classificação fiscal da mercadoria); para a
  // emissão o NCM real do produto tem precedência, com o default da categoria
  // como último recurso. Difere de propósito da UI, que só mostra o da categoria
  // no modo global — aqui o que vale é o que vai no XML.
  const ncm = firstStr(p.ncm, c.default_ncm) ?? "";

  const csosn = useGlobal
    ? (firstStr(c.default_csosn, g.default_csosn) ?? FALLBACK_CSOSN)
    : (firstStr(p.csosn) ?? FALLBACK_CSOSN);

  const origin = useGlobal
    ? (firstNum(c.default_fiscal_origin, g.default_fiscal_origin) ?? FALLBACK_ORIGIN)
    : (firstNum(p.fiscal_origin) ?? FALLBACK_ORIGIN);

  const icmsRate = useGlobal
    ? (firstNum(c.default_icms_rate, g.default_icms_rate) ?? 0)
    : (firstNum(p.icms_rate) ?? 0);

  const ipiRate = useGlobal
    ? (firstNum(c.default_ipi_rate, g.default_ipi_rate) ?? 0)
    : (firstNum(p.ipi_rate) ?? 0);

  const pisRate = useGlobal
    ? (firstNum(c.default_pis_rate, g.default_pis_rate) ?? 0)
    : (firstNum(p.pis_rate) ?? 0);

  const cofinsRate = useGlobal
    ? (firstNum(c.default_cofins_rate, g.default_cofins_rate) ?? 0)
    : (firstNum(p.cofins_rate) ?? 0);

  const pisCst = firstStr(g.default_pis_cst) ?? FALLBACK_PIS_CST;
  const cofinsCst = firstStr(g.default_cofins_cst) ?? FALLBACK_COFINS_CST;

  return { ncm, csosn, origin, icmsRate, ipiRate, pisRate, cofinsRate, pisCst, cofinsCst };
}
