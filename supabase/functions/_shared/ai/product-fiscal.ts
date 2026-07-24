// Completude fiscal do produto (portão da NF-e). "Item físico é Produto" — mas só entra numa
// nota quando o cadastro fiscal está fechado. Espelha o que o emissor exige por item
// (payload-builder: NCM 8 díg. + CFOP 4 díg.); CSOSN/origem só são obrigatórios quando o
// produto NÃO usa o fiscal global da empresa. Função PURA e testável.

export interface ProdutoFiscal {
  ncm?: string | null;
  cfop?: string | null;
  csosn?: string | null;
  fiscal_origin?: number | string | null;
  use_global_fiscal?: boolean | null;
}

function digitos(s: unknown): string {
  return String(s ?? "").replace(/\D/g, "");
}

/** Lista de pendências fiscais (vazio = completo para emitir). */
export function produtoFiscalPendencias(p: ProdutoFiscal): string[] {
  const pend: string[] = [];
  const ncm = digitos(p.ncm);
  if (ncm.length !== 8) pend.push("NCM (8 dígitos)");
  const cfop = digitos(p.cfop);
  if (cfop.length !== 4) pend.push("CFOP (4 dígitos)");
  // Quando não herda o fiscal global da empresa, precisa de CSOSN e origem próprios.
  if (p.use_global_fiscal === false) {
    if (!p.csosn) pend.push("CSOSN");
    if (p.fiscal_origin === null || p.fiscal_origin === undefined || p.fiscal_origin === "") pend.push("origem");
  }
  return pend;
}

/** true = produto pode entrar numa NF-e. */
export function produtoFiscalCompleto(p: ProdutoFiscal): boolean {
  return produtoFiscalPendencias(p).length === 0;
}
