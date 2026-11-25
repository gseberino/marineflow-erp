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
  /**
   * (24/11/2026) O recebimento baixado pelo boleto é automatica = 'boleto' com kind = 'create_receivable': o título da
   * fila é só "Receita: CREDITO DE BOLETO" (sem cliente), então quem pagou vem da conta casada com a linha do banco.
   * Os três são opcionais: linha sem `kind` é tratada como sempre foi.
   */
  kind?: string | null;
  bank_transaction_id?: string | null;
  /** o cliente da conta baixada (já curto); ausente = a linha sai com "cliente" */
  quem?: string | null;
}

/** A conta a receber casada com a linha do banco e o cliente dela. */
export interface RecebimentoCasado {
  bank_transaction_id: string | null;
  quem: string | null;
}

/** A conta a receber que o sistema baixou sozinho pelo boleto (não é despesa nem entra na soma do que foi lançado). */
export function ehRecebimentoPeloBoleto(l: LancadoSozinho): boolean {
  return l.automatica === "boleto" && l.kind === "create_receivable";
}

/**
 * (24/11/2026) Põe o nome de quem pagou em cada recebimento baixado pelo boleto e tira o que foi desfeito: a proposta
 * fica approved/boleto para sempre, e a baixa desfeita se reconhece por não haver mais conta a receber casada com a
 * linha do banco. `casadas` null = a leitura das contas falhou: segue como veio, sem o nome (melhor dizer que houve a
 * baixa do que escondê-la). As outras linhas (despesa, conta a pagar baixada) não mudam.
 * (24/11/2026, revisão) `casadas` traz só a conta da baixa que continua de pé (contasDaBaixaDePe, secretario-boleto.ts):
 * a conta que o dono casou à mão com a mesma linha depois de desfazer não entra, e o recebimento sai da lista como a
 * baixa desfeita — antes saía "recebimento baixado" com o cliente da conta nova.
 */
export function comQuemPagouOBoleto(lancados: LancadoSozinho[], casadas: RecebimentoCasado[] | null): LancadoSozinho[] {
  if (!casadas) return lancados;
  const quemDaLinha = new Map<string, string | null>();
  for (const c of casadas) if (c.bank_transaction_id) quemDaLinha.set(String(c.bank_transaction_id), c.quem);
  const saida: LancadoSozinho[] = [];
  for (const l of lancados) {
    if (!ehRecebimentoPeloBoleto(l)) { saida.push(l); continue; }
    const linha = String(l.bank_transaction_id ?? "");
    if (!quemDaLinha.has(linha)) continue;
    saida.push({ ...l, quem: quemDaLinha.get(linha) ?? null });
  }
  return saida;
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
    // (24/11/2026) O recebimento baixado pelo boleto fica fora da soma: ela é do que o sistema lançou, e o dinheiro de um
    // cliente somado em valor absoluto com as despesas daria um total que não significa nada. Sem recebimento, o
    // cabeçalho é o de sempre, byte a byte.
    const recebidos = lancados.filter(ehRecebimentoPeloBoleto).length;
    const soma = lancados.reduce((s, l) => (ehRecebimentoPeloBoleto(l) ? s : s + Math.abs(Number(l.suggested_amount ?? 0))), 0);
    const total = recebidos === 0 ? moeda(soma)
      : recebidos === lancados.length ? (recebidos === 1 ? "recebimento baixado pelo boleto" : "recebimentos baixados pelo boleto")
      : `${moeda(soma)}, sem contar ${recebidos === 1 ? "o recebimento baixado" : `os ${recebidos} recebimentos baixados`}`;
    linhas.push(`🤖 Lançados sozinhos nas últimas 24h: *${lancados.length}* (${total})`);
    for (const l of lancados.slice(0, MOSTRAR)) {
      // Recebimento baixado pelo boleto (24/11/2026): a conta a receber já existia e o banco mostrou o crédito do boleto
      // no dia do vencimento. A palavra é outra ("recebimento baixado") para o dono não ler como conta a pagar.
      // (24/11/2026, revisão) A própria linha ensina como desfazer, com a frase da manhã nova: o item só tem o nome do
      // cliente, e "desfazer Apolo" (o rodapé "Responda *desfazer* e diga qual") é a palavra *desfaz <cliente>* da
      // agenda, lida antes do assistente — desfaria a mudança DELA numa OS do cliente e a baixa continuaria. "desfaz a
      // baixa de …" não é comando da agenda. Sem o nome não há o que digitar: o dono diz o valor.
      if (ehRecebimentoPeloBoleto(l)) {
        const nome = String(l.quem ?? "").replace(/\s+/g, " ").trim().slice(0, 40);
        const comoDesfazer = nome ? `Não era? Diga *desfaz a baixa de ${nome}*.` : "Não era? Diga *desfaz a baixa* e o valor.";
        linhas.push(`   • ${moeda(Math.abs(Number(l.suggested_amount ?? 0)))} — ${nome || "cliente"} → recebimento baixado (o cliente pagou o boleto). ${comoDesfazer}`);
        continue;
      }
      // Baixa pelo boleto (22/11/2026): não é despesa nova — a conta já existia e o banco mostrou o pagamento.
      if (l.automatica === "boleto") {
        linhas.push(`   • ${moeda(Math.abs(Number(l.suggested_amount ?? 0)))} — ${nomeCurto(l.title)} → conta baixada (boleto pago no banco)`);
        continue;
      }
      const por = l.automatica === "regra" ? "sua regra" : "confiança alta";
      linhas.push(`   • ${moeda(Math.abs(Number(l.suggested_amount ?? 0)))} — ${nomeCurto(l.title)} → ${l.suggested_category ?? "sem categoria"} (${por})`);
    }
    if (lancados.length > MOSTRAR) linhas.push(`   …e mais ${lancados.length - MOSTRAR} (Extrato → Lançados sozinhos)`);
    // (24/11/2026, revisão) O rodapé é do que foi LANÇADO (despesa, conta a pagar baixada): bloco só de recebimentos
    // não o leva — cada um já diz como desfazer, e "volta para a fila" não descreve o desfazer de uma conta a receber.
    // Sem recebimento a condição é sempre verdadeira: o bloco de sempre sai byte a byte.
    if (recebidos < lancados.length) linhas.push("   Algo errado? Responda *desfazer* e diga qual — volta para a fila.");
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
