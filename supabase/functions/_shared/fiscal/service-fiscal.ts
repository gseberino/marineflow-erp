// [F-NFSE-03] Atributos fiscais EFETIVOS de um serviço — espelho em TypeScript do
// `public.resolve_service_fiscal` (migration 20260811003000).
//
// A hierarquia é de DOIS níveis, e mais rasa que a de produto de propósito:
//
//   valor próprio do serviço  →  default do VERBO fiscal  →  (nada)
//
// Produto tem um terceiro nível (o global de `app_settings`), e aqui ele não existe porque
// não faria sentido: NCM global até se defende como fallback de mercadoria genérica, mas um
// "código de tributação padrão da empresa" declararia à prefeitura a mesma atividade para
// serviços diferentes. Sem código, a emissão PARA — que é o comportamento correto.
//
// Puro (sem fetch/Deno), como o `product-fiscal.ts`: roda no Vitest e no edge `fiscal-emit`.
//
// ⚠ Ao mudar a ordem de precedência aqui, mude também na função SQL. Existe um teste de
// paridade (`src/test/fiscal-service-fiscal-paridade.test.ts`) que lê a migration e falha se
// as duas divergirem — espelho que diverge em silêncio já custou um bug real neste sistema.

export interface ServiceFiscalInput {
  national_tax_code?: string | null;
  service_code?: string | null;
  cnae?: string | null;
  iss_rate?: number | null;
  iss_withheld?: boolean | null;
}

export interface ServiceFiscalVerbDefaults {
  default_national_tax_code?: string | null;
  default_service_code?: string | null;
  default_cnae?: string | null;
  default_iss_rate?: number | null;
  default_iss_withheld?: boolean | null;
}

/** De onde veio o código de tributação que vai na nota. */
export type FiscalCodeSource = "proprio" | "verbo" | "nenhum";

export interface ResolvedServiceFiscal {
  nationalTaxCode: string | null;
  serviceCode: string | null;
  cnae: string | null;
  issRate: number | null;
  issWithheld: boolean;
  codeSource: FiscalCodeSource;
}

/**
 * COALESCE de verdade: só `null`/`undefined` cedem a vez.
 *
 * String vazia NÃO cede — e isso é deliberado. No Postgres `coalesce('', x)` devolve `''`, e o
 * espelho tem que empatar com o banco, não "melhorar" em cima dele. Um código vazio no serviço
 * vira erro de validação logo à frente, com mensagem clara; herdar em silêncio esconderia um
 * cadastro pela metade.
 */
function coalesce<T>(proprio: T | null | undefined, herdado: T | null | undefined): T | null {
  if (proprio !== null && proprio !== undefined) return proprio;
  if (herdado !== null && herdado !== undefined) return herdado;
  return null;
}

export function resolveServiceFiscal(
  service: ServiceFiscalInput | null | undefined,
  verb?: ServiceFiscalVerbDefaults | null,
): ResolvedServiceFiscal {
  const s = service ?? {};
  const f = verb ?? {};

  const nationalTaxCode = coalesce(s.national_tax_code, f.default_national_tax_code);

  // Espelha o CASE da função SQL: quem manda no rótulo é o código NACIONAL, não os demais
  // campos. É ele que decide se a nota sai, então é a procedência dele que a tela mostra.
  const codeSource: FiscalCodeSource = s.national_tax_code != null
    ? "proprio"
    : f.default_national_tax_code != null
      ? "verbo"
      : "nenhum";

  return {
    nationalTaxCode,
    serviceCode: coalesce(s.service_code, f.default_service_code),
    cnae: coalesce(s.cnae, f.default_cnae),
    issRate: coalesce(s.iss_rate, f.default_iss_rate),
    // Herda com TRÊS níveis (NOVO-014): serviço → verbo → false. O `false` final existe
    // porque retenção precisa de resposta booleana, mas só é alcançado quando nem o serviço
    // nem o verbo disseram nada — e o verbo é `not null` no banco, então na prática isso só
    // ocorre em serviço sem verbo fiscal.
    //
    // `=== true` NÃO serve aqui: ele achata `null` em `false` e mataria a herança
    // silenciosamente, que era exatamente o defeito que o NOVO-014 apontou.
    issWithheld: coalesce(s.iss_withheld, f.default_iss_withheld) ?? false,
    codeSource,
  };
}

/** Serviço sem código efetivo não emite nota — é o que o filtro da tela chama de pendente. */
export function semCodigoFiscal(resolved: ResolvedServiceFiscal): boolean {
  return resolved.nationalTaxCode == null || String(resolved.nationalTaxCode).trim() === "";
}
