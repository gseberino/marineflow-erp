// "Para onde foi o dinheiro": despesas por categoria, mês a mês.
//
// Mesma fonte do DRE e da tela Despesas: `payables` pela data do lançamento (issue_date), sem
// as canceladas. Por padrão fica de fora o grupo `nao_operacional` — fatura do cartão (cada
// compra já foi contada quando aconteceu), transferência, retirada, empréstimo e aplicação —,
// para o total bater com o DRE; a tela deixa incluir.

export interface DespesaDoMes {
  issue_date: string;
  amount: number | string;
  expense_category: string | null;
}

export interface CategoriaNoTempo {
  categoria: string;
  /** Linha do DRE da categoria; null = categoria sem grupo no plano de contas. */
  grupo: string | null;
  total: number;
  /** Um valor por mês, na ordem dos meses pedidos. */
  porMes: number[];
  quantidade: number;
}

export interface DespesasPorCategoria {
  meses: string[];
  categorias: CategoriaNoTempo[];
  totalPorMes: number[];
  total: number;
}

export const SEM_CATEGORIA = 'Sem categoria';

export function montarDespesasPorCategoria(
  linhas: DespesaDoMes[],
  grupoDe: Map<string, string>,
  meses: string[],
  incluirForaDoResultado = false,
): DespesasPorCategoria {
  const indice = new Map(meses.map((m, i) => [m, i]));
  const porCategoria = new Map<string, { grupo: string | null; centavos: number[]; quantidade: number }>();
  const totalPorMes = meses.map(() => 0);

  for (const l of linhas) {
    const i = indice.get(String(l.issue_date).slice(0, 7));
    if (i === undefined) continue;
    const categoria = l.expense_category?.trim() || SEM_CATEGORIA;
    const grupo = grupoDe.get(categoria) ?? null;
    if (!incluirForaDoResultado && grupo === 'nao_operacional') continue;
    const c = Math.round(Number(l.amount || 0) * 100);
    if (!Number.isFinite(c)) continue;
    let atual = porCategoria.get(categoria);
    if (!atual) {
      atual = { grupo, centavos: meses.map(() => 0), quantidade: 0 };
      porCategoria.set(categoria, atual);
    }
    atual.centavos[i] += c;
    atual.quantidade += 1;
    totalPorMes[i] += c;
  }

  const categorias = [...porCategoria.entries()]
    .map(([categoria, v]) => ({
      categoria,
      grupo: v.grupo,
      porMes: v.centavos.map((c) => c / 100),
      total: v.centavos.reduce((s, c) => s + c, 0) / 100,
      quantidade: v.quantidade,
    }))
    .sort((a, b) => b.total - a.total || a.categoria.localeCompare(b.categoria));

  return {
    meses,
    categorias,
    totalPorMes: totalPorMes.map((c) => c / 100),
    total: totalPorMes.reduce((s, c) => s + c, 0) / 100,
  };
}
