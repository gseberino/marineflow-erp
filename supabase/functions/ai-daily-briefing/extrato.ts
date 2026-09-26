// O que o Extrato tem para dizer no resumo das 07:30 (decisões do dono de 26/09/2026).
//
// - Resposta 17: "resumo matinal do que foi lançado sozinho, com desfazer". O lançar sozinho
//   só é aceitável porque é visível e desfazível; sem o resumo, o que o sistema lançou de
//   madrugada só aparecia para quem abrisse a tela.
// - Resposta 15: "pergunta diária sobre compra no débito sem loja". O banco não diz onde foi
//   a compra no débito (a regra do Open Finance dispensa), e só o dono sabe. Perguntar uma vez
//   por dia, com data e valor, é o que transforma "DEBITO DE CARTAO" em despesa classificada.
//
// Puro de propósito: o index.ts lê o banco, isto só escreve — e é testado sem rede.

export interface LancadoSozinho {
  title: string | null;
  suggested_amount: number | string | null;
  suggested_category: string | null;
  automatica: string | null;
}

/** Anotação do dono que a varredura não pôde aplicar (ambígua, disputada…): ele precisa saber. */
export interface AnotacaoNaoAplicada {
  valor: number | string;
  quem: string | null;
  motivo: string;
}

export interface DebitoSemLoja {
  suggested_amount: number | string | null;
  suggested_date: string | null;
}

const MOSTRAR = 3;

/**
 * "24/09" no ano corrente, "30/08/2025" em outro ano: é assim que a pessoa responde, e o
 * assistente põe o ano corrente em "dd/mm" — um débito de 2025 respondido como "30/08" nunca
 * casaria (revisão de 26/09/2026).
 */
function dataCurta(iso: string | null, anoAtual: number): string {
  if (!iso) return "";
  const [a, m, d] = iso.slice(0, 10).split("-");
  if (!d || !m) return "";
  return Number(a) === anoAtual ? `${d}/${m}` : `${d}/${m}/${a}`;
}

function nomeCurto(titulo: string | null): string {
  return String(titulo ?? "").replace(/^(Despesa|Receita):\s*/i, "").slice(0, 40);
}

export function linhasDoExtratoNoResumo(
  lancados: LancadoSozinho[],
  debitos: DebitoSemLoja[],
  moeda: (v: number) => string,
  opcoes: { anoAtual?: number; anotadosEsperando?: number; naoAplicadas?: AnotacaoNaoAplicada[] } = {},
): { linhas: string[]; acoes: string[] } {
  const anoAtual = opcoes.anoAtual ?? new Date().getUTCFullYear();
  const ddmm = (iso: string | null) => dataCurta(iso, anoAtual);
  const linhas: string[] = [];
  const acoes: string[] = [];

  if (lancados.length > 0) {
    const soma = lancados.reduce((s, l) => s + Math.abs(Number(l.suggested_amount ?? 0)), 0);
    linhas.push(`🤖 Lançados sozinhos nas últimas 24h: *${lancados.length}* (${moeda(soma)})`);
    for (const l of lancados.slice(0, MOSTRAR)) {
      const por = l.automatica === "regra" ? "sua regra" : "confiança alta";
      linhas.push(`   • ${moeda(Math.abs(Number(l.suggested_amount ?? 0)))} — ${nomeCurto(l.title)} → ${l.suggested_category ?? "sem categoria"} (${por})`);
    }
    if (lancados.length > MOSTRAR) linhas.push(`   …e mais ${lancados.length - MOSTRAR} (Extrato → Lançados sozinhos)`);
    linhas.push("   Algo errado? Responda *desfazer* e diga qual — volta para a fila.");
    acoes.push("   • *O que foi lançado sozinho?*");
  }

  if (debitos.length > 0) {
    const ordem = [...debitos].sort((a, b) => String(b.suggested_date ?? "").localeCompare(String(a.suggested_date ?? "")));
    linhas.push(`❓ Compras no débito que o banco não diz onde foram: *${debitos.length}*. Onde foram?`);
    for (const d of ordem.slice(0, MOSTRAR)) {
      linhas.push(`   • ${ddmm(d.suggested_date)} · ${moeda(Math.abs(Number(d.suggested_amount ?? 0)))}`);
    }
    if (debitos.length > MOSTRAR) linhas.push(`   …e mais ${debitos.length - MOSTRAR} no Extrato`);
    // O exemplo leva o valor com centavos e a data inteira: a anotação casa ao centavo e no dia
    // (±1). "o débito de 9 do dia 24" nunca casaria com R$ 8,90 (revisão de 26/09/2026).
    const exemplo = ordem[0];
    linhas.push(`   Responda, por exemplo: *o débito de ${moeda(Math.abs(Number(exemplo.suggested_amount ?? 0)))} de ${ddmm(exemplo.suggested_date)} foi almoço da equipe*`);
  }
  if ((opcoes.anotadosEsperando ?? 0) > 0) {
    // Sem débito novo para perguntar, a linha fica sozinha (sem o recuo da lista).
    linhas.push(debitos.length > 0
      ? `   ✍️ ${opcoes.anotadosEsperando} que você já respondeu esperam só a aprovação no Extrato.`
      : `✍️ ${opcoes.anotadosEsperando} débito(s) que você já respondeu esperam só a aprovação no Extrato.`);
  }

  // Anotação que a varredura cancelou: o dono ouviu "entra classificada" — se ela não entrou,
  // ele precisa saber por quê, em vez de a anotação simplesmente sumir (revisão de 26/09/2026).
  const naoAplicadas = opcoes.naoAplicadas ?? [];
  if (naoAplicadas.length > 0) {
    linhas.push(`⚠️ Anotações suas que não pude aplicar: *${naoAplicadas.length}*`);
    for (const a of naoAplicadas.slice(0, MOSTRAR)) {
      linhas.push(`   • ${moeda(Math.abs(Number(a.valor ?? 0)))}${a.quem ? ` · ${a.quem}` : ""} — ${a.motivo}`);
    }
    if (naoAplicadas.length > MOSTRAR) linhas.push(`   …e mais ${naoAplicadas.length - MOSTRAR}`);
  }

  return { linhas, acoes };
}
