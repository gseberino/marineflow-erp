// O banco reenviando a mesma transação com outro código (29/09/2026, "sim, pode fazer" do dono).
//
// A sincronização reconhecia o que já tinha pelo código do provedor (bank_ref_id). Em 29/09, às
// 10:59, o provedor devolveu 9 transações de julho e agosto idênticas às já gravadas — mesma
// conta, data, valor, descrição, parcela e fatura — só com código novo, e elas entraram em dobro.
//
// No extrato há 19 grupos de transações iguais de verdade (6 pedágios de R$ 5,70 no mesmo dia,
// por exemplo). Medido em 30/09 no extrato inteiro: todos chegaram JUNTOS, na mesma busca; só as
// 9 de 29/09 chegaram iguais a uma linha importada semanas antes. E a busca completa de 30/09
// mostrou que o banco passou a devolver as duas versões (a antiga e a de código novo) — contar
// quantas ele devolve não bastaria. Então:
//   · iguais chegando juntas, sem nenhuma igual guardada: entram (a repetição legítima);
//   · código novo para uma linha cujo código antigo o banco não devolve mais: é a mesma
//     transação — a guardada passa a usar o código novo (é por ele que virão pendente → lançada);
//   · cópia a mais de uma linha já importada antes: entra marcada como duplicata, fora da fila,
//     com o motivo escrito; se for compra de verdade, volta à fila com um clique. Nada se perde.

export interface LinhaDoExtrato {
  bank_ref_id: string;
  transaction_date: string;
  amount: number | string;
  transaction_type: string | null;
  description: string | null;
  installment_label?: string | null;
  card_last_digits?: string | null;
  provider_account_id?: string | null;
}

export interface LinhaGuardada extends LinhaDoExtrato {
  id: string;
}

export function chaveDoConteudo(l: LinhaDoExtrato): string {
  const descricao = String(l.description ?? "").trim().replace(/\s+/g, " ").toLowerCase();
  const centavos = Math.round(Math.abs(Number(l.amount) || 0) * 100);
  return [
    l.provider_account_id ?? "",
    String(l.transaction_date).slice(0, 10),
    centavos,
    l.transaction_type ?? "",
    descricao,
    l.installment_label ?? "",
    l.card_last_digits ?? "",
  ].join("|");
}

function agrupar<T extends LinhaDoExtrato>(linhas: T[]): Map<string, T[]> {
  const grupos = new Map<string, T[]>();
  for (const l of linhas) {
    const chave = chaveDoConteudo(l);
    const lista = grupos.get(chave);
    if (lista) lista.push(l);
    else grupos.set(chave, [l]);
  }
  return grupos;
}

/**
 * Separa as linhas de código novo em reais, reenvios e prováveis reenvios.
 *
 * - `doProvedor`: tudo o que o banco devolveu nesta busca (da conta).
 * - `novas`: as de código que o ERP ainda não guarda (subconjunto de `doProvedor`).
 * - `guardadas`: as linhas já gravadas com o mesmo conteúdo das novas (fora as já marcadas como
 *   duplicata), estejam ou não nesta busca. Todas vieram de buscas anteriores.
 *
 * Para cada conteúdo:
 * - nada igual guardado → todas são reais (inclusive várias iguais chegando juntas);
 * - a guardada cujo código o banco não devolve mais → a nova é o mesmo lançamento com código
 *   trocado (`reenvios`: a guardada passa a usar o código novo);
 * - o que sobra, com uma igual já importada antes → `provaveis`: entra marcada como duplicata,
 *   fora da fila e com o motivo escrito, e volta à fila com um clique se for compra de verdade.
 *   Foi o caso de 29/09: o banco passou a devolver as duas versões.
 */
export function separarReenvios<T extends LinhaDoExtrato, G extends LinhaGuardada>(
  doProvedor: T[],
  novas: T[],
  guardadas: G[],
): {
  reais: T[];
  reenvios: Array<{ linha: T; guardada: G }>;
  provaveis: Array<{ linha: T; igual: G }>;
} {
  const guardadasPorChave = agrupar(guardadas);
  const codigosDevolvidos = new Set(doProvedor.map((l) => l.bank_ref_id));

  const reais: T[] = [];
  const reenvios: Array<{ linha: T; guardada: G }> = [];
  const provaveis: Array<{ linha: T; igual: G }> = [];

  for (const [chave, lista] of agrupar(novas)) {
    const doConteudo = [...(guardadasPorChave.get(chave) ?? [])].sort((a, b) => a.id.localeCompare(b.id));
    if (doConteudo.length === 0) {
      reais.push(...lista);
      continue;
    }
    const substituidas = doConteudo.filter((g) => !codigosDevolvidos.has(g.bank_ref_id));
    for (const linha of lista) {
      const guardada = substituidas.shift();
      if (guardada) reenvios.push({ linha, guardada });
      else provaveis.push({ linha, igual: doConteudo[0] });
    }
  }

  return { reais, reenvios, provaveis };
}
