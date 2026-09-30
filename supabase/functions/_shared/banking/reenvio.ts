// O banco reenviando a mesma transação com outro código (29/09/2026, "sim, pode fazer" do dono).
//
// A sincronização reconhecia o que já tinha pelo código do provedor (bank_ref_id). Em 29/09, às
// 10:59, o provedor devolveu 9 transações de julho e agosto idênticas às já gravadas — mesma
// conta, data, valor, descrição, parcela e fatura — só com código novo, e elas entraram em dobro.
//
// Reconhecer só pelo conteúdo quebraria o legítimo: no extrato há 19 grupos de transações iguais
// de verdade (6 pedágios de R$ 5,70 no mesmo dia, por exemplo). Então a regra CONTA: se o banco
// devolve N transações com o mesmo conteúdo e o ERP já guarda N, a de código novo é reenvio; se
// ele devolve N+1, uma é nova. Medido em 30/09 no extrato inteiro: os 19 grupos iguais chegaram
// todos na mesma busca (a regra não mexe neles) e só as 9 de 29/09 chegaram em dias diferentes.
//
// O reenvio não vira linha nova: a linha guardada passa a usar o código novo (é por ele que o
// banco vai mandar as próximas mudanças, como pendente → lançada).

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
 * Separa as linhas de código novo em reais e reenvios.
 *
 * - `doProvedor`: tudo o que o banco devolveu nesta busca (da conta).
 * - `novas`: as de código que o ERP ainda não guarda (subconjunto de `doProvedor`).
 * - `guardadas`: as linhas já gravadas com o mesmo conteúdo das novas (fora as já marcadas como
 *   duplicata), estejam ou não nesta busca.
 *
 * Para cada conteúdo: novas reais = devolvidas − guardadas (nunca menos que zero). As demais
 * são reenvios e cada uma fica com uma guardada cujo código o banco NÃO devolveu mais — pela
 * conta, sempre existe uma.
 */
export function separarReenvios<T extends LinhaDoExtrato, G extends LinhaGuardada>(
  doProvedor: T[],
  novas: T[],
  guardadas: G[],
): { reais: T[]; reenvios: Array<{ linha: T; guardada: G }> } {
  const devolvidas = agrupar(doProvedor);
  const guardadasPorChave = agrupar(guardadas);
  const codigosDevolvidos = new Set(doProvedor.map((l) => l.bank_ref_id));

  const reais: T[] = [];
  const reenvios: Array<{ linha: T; guardada: G }> = [];

  for (const [chave, lista] of agrupar(novas)) {
    const f = devolvidas.get(chave)?.length ?? lista.length;
    const doConteudo = guardadasPorChave.get(chave) ?? [];
    const substituidas = doConteudo
      .filter((g) => !codigosDevolvidos.has(g.bank_ref_id))
      .sort((a, b) => a.id.localeCompare(b.id));
    let vagas = Math.max(0, f - doConteudo.length);

    for (const linha of lista) {
      if (vagas > 0) {
        reais.push(linha);
        vagas--;
        continue;
      }
      const guardada = substituidas.shift();
      if (guardada) reenvios.push({ linha, guardada });
      else reais.push(linha); // não acontece pela conta; na dúvida, grava (perder é pior)
    }
  }

  return { reais, reenvios };
}
