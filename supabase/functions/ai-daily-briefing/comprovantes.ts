// O resumo das 07:30 e os comprovantes (CMP) — F3, 11/10/2026 (spec-f3.md, 5.3). SÓ REMOÇÃO
// (decisão do dono): nada novo entra no resumo.
//
//   - A compra no débito sem loja que um CMP já ligou (ou que é candidata da pergunta do extrato
//     que espera o dono) não é perguntada aqui: o WhatsApp dos comprovantes já cuida dela.
//   - A anotação de um CMP vivo não entra em "não aplicadas": quem cuida dela é o CMP (a pergunta do
//     extrato, o abandono com a pendência "classificar no Extrato").
//
// Chama comprovantes_linhas_da_conciliacao (R2) direto — sem importar do finance-review: uma função
// não depende do código da outra. Erro na R2 = o bloco como antes da F3.

// deno-lint-ignore no-explicit-any
type Admin = any;

export type DoComprovante = { linhas: Set<string>; anotacoes: Set<string> };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * As linhas do banco ligadas a um CMP (ou candidatas de pergunta aberta) e as anotações dos CMPs
 * vivos. Sem filtro de linhas (p_transacoes = null): a anotação cancelada não tem linha, e é ela que
 * sai de "não aplicadas". Nunca lança: erro → vazio (o log leva só o código).
 */
export async function linhasDosComprovantes(admin: Admin): Promise<DoComprovante> {
  const vazio: DoComprovante = { linhas: new Set(), anotacoes: new Set() };
  try {
    const { data, error } = await admin.rpc("comprovantes_linhas_da_conciliacao", { p_transacoes: null });
    if (error) {
      console.warn(`[ai-daily-briefing] comprovantes indisponível: ${String(error.code ?? "erro")}`);
      return vazio;
    }
    const d = (data ?? {}) as { linhas?: unknown; anotacoes?: unknown };
    const linhas = new Set<string>();
    for (const l of (Array.isArray(d.linhas) ? d.linhas : []) as Array<Record<string, unknown>>) {
      if (typeof l?.bank_transaction_id === "string" && UUID.test(l.bank_transaction_id)) linhas.add(l.bank_transaction_id);
    }
    const anotacoes = new Set((Array.isArray(d.anotacoes) ? d.anotacoes : []).filter((x): x is string => typeof x === "string" && UUID.test(x)));
    return { linhas, anotacoes };
  } catch (e) {
    console.warn(`[ai-daily-briefing] comprovantes falhou: ${(e as Error)?.name ?? "erro"}`);
    return vazio;
  }
}

/**
 * Do bloco "compra no débito sem loja": as que ainda são pergunta (sem anotação e sem CMP) e quantas
 * já estão anotadas esperando aprovar (o número de antes da F3, só as com anotação).
 */
export function debitosSemComprovante<T extends { bank_transaction_id?: unknown; evidencia?: { anotacao?: unknown } | null }>(
  semLoja: T[],
  doCmp: DoComprovante,
): { debitos: T[]; anotadosEsperando: number } {
  const debitos = semLoja.filter((l) => !l.evidencia?.anotacao && !doCmp.linhas.has(String(l.bank_transaction_id ?? "")));
  const anotadosEsperando = semLoja.filter((l) => Boolean(l.evidencia?.anotacao)).length;
  return { debitos, anotadosEsperando };
}

/** As anotações canceladas pela varredura que NÃO são de um CMP vivo. */
export function canceladasSemComprovante<T extends { id?: unknown }>(canceladas: T[], doCmp: DoComprovante): T[] {
  return canceladas.filter((a) => !doCmp.anotacoes.has(String(a.id ?? "")));
}
