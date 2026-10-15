// "Mês até aqui" e "Faturamento do mês por cliente" — lógica pura, sem banco.
//
// ═══ POR QUE EXISTE ═══
//
// Dois números do conselheiro saíam errados (15/10/2026):
//   · "Mês até aqui" somava só as despesas JÁ lançadas. As do mês que ainda estão na fila de
//     propostas (27, R$ 11.143,82 nos grupos do resultado) ficavam de fora — o resultado saía
//     otimista, e a nota dizia o contrário ("o número está pessimista"), contando como "entrada
//     sem receita" dois Pix que já eram sinais lançados.
//   · "Faturamento por cliente" vinha da rpc bi_top_clients, que soma o total das OS CRIADAS no
//     mês: em outubro só a OS-00112 foi criada e saiu "Nelson 100% — concentrado". O faturado de
//     verdade (recebíveis do mês, a mesma base da "receita" acima) era Marcelo 44%, Nelson 27%,
//     Giancarlo 15%. A rpc fica como está (a tela de BI pode usá-la); o resumo não a usa mais.

/** Os grupos do DRE que entram no resultado do mês (o mesmo corte das despesas já lançadas). */
export const GRUPOS_DO_RESULTADO = ["custo_direto", "despesa_operacional", "financeiro"] as const;

/** Despesas do mês ainda na fila (create_payable pendente). O grupo vem da fila; se nulo, da categoria. */
export function despesasPendentesDoMes(
  fila: Array<{ suggested_amount: number | string | null; dre_group: string | null; suggested_category: string | null }>,
  grupoDaCategoria: Map<string, string>,
): { n: number; soma: number } {
  let n = 0;
  let soma = 0;
  for (const f of fila ?? []) {
    const grupo = f.dre_group ?? (f.suggested_category ? grupoDaCategoria.get(f.suggested_category) : undefined);
    if (!grupo || !(GRUPOS_DO_RESULTADO as readonly string[]).includes(grupo)) continue;
    n++;
    soma += Math.abs(Number(f.suggested_amount ?? 0));
  }
  return { n, soma: Math.round(soma * 100) / 100 };
}

/**
 * A nota depois do resultado do mês: diz o que ainda falta e para que lado o número vai.
 * "" quando nada está pendente.
 */
export function notaDoMes(
  p: { despesasPendentes: { n: number; soma: number }; entradasSemReceita: { n: number; soma: number } },
  fmt0: (v: number) => string,
): string {
  const d = p.despesasPendentes;
  const e = p.entradasSemReceita;
  const despesas = d.n > 0
    ? `${d.n === 1 ? "falta conferir 1 despesa" : `faltam conferir ${d.n} despesas`} do mês, ${fmt0(d.soma)} — o resultado real é menor`
    : "";
  const entradas = e.n > 0
    ? `${e.n} ${e.n === 1 ? "entrada" : "entradas"} do banco, ${fmt0(e.soma)}, ainda sem receita lançada`
    : "";
  if (despesas && entradas) return ` (${despesas}; ${entradas})`;
  if (despesas) return ` (${despesas})`;
  if (entradas) return ` (${entradas} — o resultado pode ser maior)`;
  return "";
}

/**
 * Faturamento do mês por cliente: soma dos recebíveis do mês não cancelados, por cliente.
 * null com menos de 2 clientes (um cliente só não é informação); top 3 com o primeiro nome e o %
 * arredondado; " — concentrado" só se o 1º tem 50% ou mais.
 */
export function faturamentoPorCliente(
  recs: Array<{ amount: number | string | null; status: string | null; client_id: string | null; nome: string | null }>,
): string | null {
  const porCliente = new Map<string, { nome: string; total: number }>();
  for (const r of recs ?? []) {
    if (r.status === "cancelled") continue;
    const valor = Number(r.amount || 0);
    if (!(valor > 0)) continue;
    const chave = r.client_id ?? "(sem cliente)";
    const atual = porCliente.get(chave) ?? { nome: r.nome || "sem cliente", total: 0 };
    atual.total += valor;
    porCliente.set(chave, atual);
  }
  const lista = [...porCliente.values()].sort((a, b) => b.total - a.total);
  if (lista.length < 2) return null;
  const total = lista.reduce((s, c) => s + c.total, 0);
  const tres = lista.slice(0, 3).map((c) => `${String(c.nome).trim().split(/\s+/)[0]} ${Math.round((100 * c.total) / total)}%`);
  const concentrado = lista[0].total / total >= 0.5;
  return `🏆 Faturamento do mês por cliente: ${tres.join(" · ")}${concentrado ? " — concentrado" : ""}`;
}
