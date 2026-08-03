// Motor de casamento entre extrato bancário e o que a empresa tem em aberto.
//
// Desenho em camadas, que é o padrão consolidado no mercado de conciliação: chaves
// exatas resolvem o grosso de forma explicável e barata, pontuação heurística trata o
// meio, e só o resíduo ambíguo sobra para a IA (que roda fora daqui, na banking-reconcile).
//
// Duas escolhas merecem explicação:
//
// 1. TOLERÂNCIA DUPLA. Percentual sozinho falha nos extremos: 5% de um orçamento de
//    R$ 50.000 são R$ 2.500 de folga, o que casa transações que nada têm a ver.
//    Aqui vale sempre a mais conservadora entre o percentual e o teto absoluto.
//
// 2. PONTUAÇÃO, NÃO FILTRO. A tela antiga descartava candidatos fora da faixa; um
//    candidato com valor levemente diferente mas CNPJ igual simplesmente sumia. Agora
//    todo candidato plausível é pontuado e ordenado, com o motivo visível.

import {
  type BankTx,
  type Candidate,
  type GroupSuggestion,
  type MatchOptions,
  type MatchReason,
  type MatchTier,
  type Suggestion,
  DEFAULT_MATCH_OPTIONS,
} from "./types.ts";

// Pesos por sinal. Somam 100 no caso perfeito sem os bônus.
const W_AMOUNT = 45;   // o valor é o sinal mais forte de todos
const W_DOCUMENT = 25; // CNPJ/CPF do pagador batendo com o cadastro
const W_NAME = 15;     // nome do cliente aparecendo no histórico
const W_DATE = 15;     // proximidade do vencimento
const BONUS_DOCNUM = 12; // número do orçamento/OS citado no histórico do extrato
const BONUS_MEMORIA = 18; // teto do reforço por conciliações anteriores com o mesmo cliente

/**
 * Desconto quando os dois lados têm documento e eles DISCORDAM.
 *
 * Pesa mais que o acerto de nome inteiro (15) de propósito: documento é identidade, nome é
 * aproximação. Uma entrada de R$ 18.001,04 do CPF de Lucenira casava com a OS de Charline
 * porque o valor batia com o sinal — e nada no cálculo notava que eram duas pessoas
 * diferentes. Não elimina o candidato, porque terceiro pagando por outro é comum; rebaixa
 * e escreve o motivo.
 *
 * Calibrado em 20 de propósito: com valor exato (45) e data no vencimento (15), o total
 * cai para 40 — acima do corte de 35, logo o candidato ainda APARECE, mas como sugestão
 * fraca e com o aviso à vista. Uma penalidade de 30 zeraria a sugestão, e aí o gestor não
 * veria nem o alerta: some da tela o caso que ele mais precisa julgar.
 */
const PENALIDADE_DOCUMENTO_DIVERGENTE = 20;

/** Sufixos societários e ruído que atrapalham a comparação de nomes. */
const NAME_NOISE = new Set([
  "LTDA", "ME", "EPP", "EIRELI", "SA", "S", "A", "CIA", "COMERCIO", "COMERCIAL",
  "INDUSTRIA", "SERVICOS", "SERVICO", "DE", "DA", "DO", "DAS", "DOS", "E",
]);

/** Ruído típico de histórico bancário, que não identifica ninguém. */
const STATEMENT_NOISE = new Set([
  "PIX", "TED", "DOC", "TRANSFERENCIA", "RECEBIDO", "RECEBIDA", "ENVIADO", "PAGAMENTO",
  "CREDITO", "DEBITO", "DEPOSITO", "LIQUIDACAO", "BOLETO", "COBRANCA", "REF", "CP", "CC",
]);

export function normalizeText(value: string): string {
  return (value || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // tira acentos (marcas de combinacao do NFD)
    .toUpperCase()
    .replace(/[^A-Z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function significantTokens(value: string, noise: Set<string>): string[] {
  return normalizeText(value)
    .split(" ")
    .filter((t) => t.length >= 3 && !noise.has(t));
}

function onlyDigits(value: string | null | undefined): string {
  return (value || "").replace(/\D/g, "");
}

function daysBetween(a: string, b: string): number {
  const da = new Date(`${a}T12:00:00Z`).getTime();
  const db = new Date(`${b}T12:00:00Z`).getTime();
  return Math.round((da - db) / 86_400_000);
}

/**
 * Quanto do nome do cliente aparece no histórico do extrato.
 * Retorna 0..1. Comparação por tokens (e não distância de edição) porque o nome vem
 * cercado de ruído — "PIX RECEBIDO MARINA DO SOL LTDA 12345" — e o que importa é
 * quantas palavras identificadoras do cliente estão presentes.
 */
export function nameOverlap(clientName: string | null | undefined, statementText: string): number {
  const nameTokens = significantTokens(clientName || "", NAME_NOISE);
  if (nameTokens.length === 0) return 0;
  const haystack = ` ${normalizeText(statementText)} `;
  const hits = nameTokens.filter((t) => haystack.includes(` ${t} `) || haystack.includes(t));
  return hits.length / nameTokens.length;
}

/**
 * Assinatura do histórico bancário: tokens identificadores, sem ruído, em ordem
 * alfabética. É a chave da memória de conciliação — "PIX RECEBIDO MARINA SOL" e
 * "TED MARINA SOL LTDA" produzem a mesma assinatura, então o que foi aprendido numa
 * transferência serve para a próxima, mesmo que o banco escreva diferente.
 * Devolve string vazia quando o histórico não tem nada identificável (só "PIX RECEBIDO"),
 * caso em que não há o que aprender.
 */
export function statementSignature(description: string, counterpartyName?: string | null): string {
  const tokens = significantTokens(`${description} ${counterpartyName || ""}`, STATEMENT_NOISE)
    .filter((t) => !/^\d+$/.test(t)); // números soltos (valor, documento) não identificam
  if (tokens.length === 0) return "";
  return Array.from(new Set(tokens)).sort().join(" ").slice(0, 200);
}

/**
 * A transação parece ser dinheiro seu circulando entre contas próprias.
 *
 * No extrato real aparece como "Pix recebido de Hbr Boats": não é receita de cliente, é
 * transferência interna. Sem reconhecer isso, essas linhas ficam para sempre na fila de
 * conciliação pedindo um candidato que não existe — e ainda inflam o total "a identificar".
 */
export function looksLikeInternalTransfer(
  description: string,
  counterpartyName: string | null | undefined,
  companyName: string | null | undefined,
): boolean {
  const empresa = significantTokens(companyName || "", NAME_NOISE);
  if (empresa.length === 0) return false;
  const texto = ` ${normalizeText(`${description} ${counterpartyName || ""}`)} `;
  // Exige TODOS os tokens do nome da empresa: "Boats" sozinho casaria com outra empresa.
  return empresa.every((t) => texto.includes(` ${t} `) || texto.includes(t));
}

/** Uma saída de uma conta que corresponde à entrada em outra conta da empresa. */
export interface InternalTransferPair {
  saida: { id: string; date: string; description: string; amount: number; connectionId: string | null };
  entrada: { id: string; date: string; description: string; amount: number; connectionId: string | null };
  /** Dias entre as duas pernas — normalmente 0 ou 1. */
  defasagem: number;
  detail: string;
}

interface TxParaPareamento {
  id: string;
  transaction_date: string;
  description: string;
  amount: number;
  transaction_type: "credit" | "debit";
  bank_connection_id?: string | null;
}

/**
 * Encontra transferências entre contas da própria empresa pareando as duas pernas.
 *
 * Com mais de uma conta conectada, o mesmo dinheiro aparece duas vezes: sai de uma e entra
 * na outra. Sem parear, ele vira uma despesa e uma receita fantasmas — infla faturamento e
 * custo ao mesmo tempo, e o resultado até fecha, mas todos os números do meio ficam errados.
 *
 * O pareamento é por valor idêntico, contas diferentes e poucos dias de defasagem (Pix cai
 * na hora, TED entre bancos pode virar o dia). Cada perna é usada uma única vez: sem isso,
 * três transferências de mesmo valor no mesmo dia gerariam pares cruzados absurdos.
 */
export function findInternalTransfers(
  transacoes: TxParaPareamento[],
  toleranciaDias = 2,
): InternalTransferPair[] {
  const saidas = transacoes.filter((t) => t.transaction_type === "debit");
  const entradas = transacoes.filter((t) => t.transaction_type === "credit");
  const usadas = new Set<string>();
  const pares: InternalTransferPair[] = [];

  // Maiores primeiro: se houver ambiguidade, é melhor resolvê-la nos valores que mais
  // pesam no resultado.
  for (const saida of saidas.slice().sort((a, b) => b.amount - a.amount)) {
    if (usadas.has(saida.id)) continue;

    const candidata = entradas.find((e) => {
      if (usadas.has(e.id)) return false;
      // Contas diferentes: dinheiro que sai e entra na MESMA conta não é transferência.
      if (!e.bank_connection_id || !saida.bank_connection_id) return false;
      if (e.bank_connection_id === saida.bank_connection_id) return false;
      if (Math.abs(e.amount - saida.amount) >= 0.01) return false;
      return Math.abs(daysBetween(e.transaction_date, saida.transaction_date)) <= toleranciaDias;
    });

    if (!candidata) continue;
    usadas.add(saida.id);
    usadas.add(candidata.id);

    const defasagem = Math.abs(daysBetween(candidata.transaction_date, saida.transaction_date));
    pares.push({
      saida: {
        id: saida.id, date: saida.transaction_date, description: saida.description,
        amount: saida.amount, connectionId: saida.bank_connection_id ?? null,
      },
      entrada: {
        id: candidata.id, date: candidata.transaction_date, description: candidata.description,
        amount: candidata.amount, connectionId: candidata.bank_connection_id ?? null,
      },
      defasagem,
      detail: defasagem === 0
        ? "Saiu de uma conta e entrou em outra no mesmo dia, pelo mesmo valor"
        : `Saiu de uma conta e entrou em outra ${defasagem} dia(s) depois, pelo mesmo valor`,
    });
  }

  return pares;
}

/** Tolerância efetiva: a menor entre o percentual e o teto absoluto. */
export function effectiveTolerance(expected: number, opts: MatchOptions): number {
  const pct = Math.abs(expected) * (opts.amountTolerancePct / 100);
  return Math.min(pct, opts.amountToleranceMax);
}

/** O número do documento (ORÇ-00042 / OS-13) aparece no histórico? */
function documentCited(documentNumber: string | null | undefined, statementText: string): boolean {
  const doc = normalizeText(documentNumber || "");
  if (!doc) return false;
  const haystack = normalizeText(statementText);
  if (haystack.includes(doc)) return true;
  // Também aceita só a parte numérica, sem zeros à esquerda: "ORÇ-00042" casa com "42".
  const num = doc.replace(/\D/g, "").replace(/^0+/, "");
  if (num.length >= 2) {
    const tokens = significantTokens(statementText, STATEMENT_NOISE);
    return tokens.some((t) => t.replace(/^0+/, "") === num);
  }
  return false;
}

/**
 * Pontua um candidato contra uma transação. Devolve null quando nem faz sentido
 * comparar (sentido do dinheiro trocado, ou valor absurdamente distante).
 */
export function scoreCandidate(
  tx: BankTx,
  candidate: Candidate,
  options: Partial<MatchOptions> = {},
  /** Clientes que este histórico já apontou antes, e quantas vezes. Ver reconciliation_memory. */
  memory?: Map<string, number>,
): Suggestion | null {
  const opts = { ...DEFAULT_MATCH_OPTIONS, ...options };

  // Dinheiro entrando não paga conta a pagar, e vice-versa.
  if (candidate.direction !== tx.transaction_type) return null;

  const expected = Number(candidate.amount) || 0;
  const received = Number(tx.amount) || 0;
  if (expected <= 0) return null;

  const difference = Number((received - expected).toFixed(2));
  const absDiff = Math.abs(difference);
  const tolerance = effectiveTolerance(expected, opts);
  const reasons: MatchReason[] = [];

  // ── Camada de certeza ──────────────────────────────────────────────────────
  // O EndToEndId do Pix é único no SPI: se bate, é a mesma transação. Não há o que discutir.
  const e2eMatch = !!tx.pix_end_to_end_id &&
    !!candidate.pixEndToEndId &&
    tx.pix_end_to_end_id === candidate.pixEndToEndId;

  const docDigits = onlyDigits(tx.counterparty_document);
  const candDocDigits = onlyDigits(candidate.clientDocument);
  const documentMatch = docDigits.length >= 11 && docDigits === candDocDigits;
  const exactAmount = absDiff < 0.01;

  if (e2eMatch) {
    reasons.push({
      signal: "pix",
      detail: "Identificador do Pix idêntico ao da cobrança emitida",
      points: 100,
    });
    return {
      candidate,
      score: 100,
      tier: "certain",
      reasons,
      difference,
      autoApply: true,
    };
  }

  if (documentMatch && exactAmount) {
    reasons.push({
      signal: "documento",
      detail: `CNPJ/CPF do pagador confere com ${candidate.clientName || "o cliente"}`,
      points: W_DOCUMENT,
    });
    reasons.push({ signal: "valor", detail: "Valor exato", points: W_AMOUNT });
    return {
      candidate,
      score: 100,
      tier: "certain",
      reasons,
      difference,
      autoApply: true,
    };
  }

  // ── Camada de probabilidade ────────────────────────────────────────────────
  let score = 0;

  const searchText = `${tx.description} ${tx.counterparty_name || ""}`;
  const overlap = nameOverlap(candidate.clientName, searchText);

  /**
   * O remetente CONTRADIZ o candidato: os dois lados têm documento e eles diferem.
   *
   * Não elimina — terceiro pagando por outro é comum (cônjuge, empresa do titular). Mas
   * não pode ser tratado como ausência de informação: quando os dois documentos são
   * conhecidos e discordam, isso é evidência CONTRA, e o gestor precisa ler isso escrito
   * antes de confirmar.
   */
  const documentoContradiz = docDigits.length >= 11 && candDocDigits.length >= 11
    && docDigits !== candDocDigits;

  /**
   * Há algo ligando este remetente a este candidato?
   *
   * É o que separa "pagamento identificado" de "valor que por acaso é parecido". Sem
   * nenhum vínculo, um valor aproximado é só coincidência aritmética — e coincidência
   * aritmética não deve virar sugestão de baixa.
   */
  const identificado = documentMatch
    || overlap > 0
    || (!!candidate.clientId && (memory?.get(candidate.clientId) ?? 0) > 0)
    || documentCited(candidate.documentNumber, searchText);

  // Valor: pontuação cheia dentro da tolerância, decaindo até 25% de diferença.
  if (absDiff < 0.01) {
    score += W_AMOUNT;
    reasons.push({ signal: "valor", detail: "Valor exato", points: W_AMOUNT });
  } else if (!identificado) {
    // A tolerância é um privilégio de quem já foi reconhecido. Aqui não foi: nem o
    // documento bate, nem o nome aparece, nem existe histórico. Aceitar valor aproximado
    // neste estado é o que fazia uma entrada de um remetente casar com a OS de outro
    // cliente só porque os números ficaram perto.
    return null;
  } else if (absDiff <= tolerance) {
    const pts = Math.round(W_AMOUNT * 0.9);
    score += pts;
    reasons.push({
      signal: "valor",
      detail: `Diferença de ${formatBRL(absDiff)}, dentro da tolerância`,
      points: pts,
    });
  } else {
    const relative = absDiff / expected;
    if (relative > 0.25) return null; // longe demais para ser o mesmo pagamento
    const pts = Math.round(W_AMOUNT * (1 - relative / 0.25) * 0.6);
    if (pts <= 0) return null;
    score += pts;
    reasons.push({
      signal: "valor",
      detail: difference > 0
        ? `Recebido ${formatBRL(absDiff)} a mais que o esperado`
        : `Recebido ${formatBRL(absDiff)} a menos que o esperado`,
      points: pts,
    });
  }

  if (documentoContradiz) {
    score -= PENALIDADE_DOCUMENTO_DIVERGENTE;
    reasons.push({
      signal: "documento",
      detail: `Quem enviou (${tx.counterparty_name || "CPF/CNPJ " + formatDoc(docDigits)}) não é ${candidate.clientName || "o cliente"} — confira se foi um terceiro pagando`,
      points: -PENALIDADE_DOCUMENTO_DIVERGENTE,
    });
  }

  if (documentMatch) {
    score += W_DOCUMENT;
    reasons.push({
      signal: "documento",
      detail: `CNPJ/CPF do pagador confere com ${candidate.clientName || "o cliente"}`,
      points: W_DOCUMENT,
    });
  }

  if (overlap > 0) {
    const pts = Math.round(W_NAME * overlap);
    if (pts > 0) {
      score += pts;
      reasons.push({
        signal: "nome",
        detail: overlap >= 0.99
          ? `Nome de ${candidate.clientName} aparece no histórico`
          : `Parte do nome de ${candidate.clientName} aparece no histórico`,
        points: pts,
      });
    }
  }

  // Data: perto do vencimento pontua cheio; sinal de orçamento usa janela ampla,
  // porque o cliente pode aprovar semanas depois de receber a proposta.
  const dateScore = scoreDate(tx.transaction_date, candidate, opts);
  if (!dateScore.ok) return null;
  if (dateScore.reason) {
    score += dateScore.reason.points;
    reasons.push(dateScore.reason);
  }

  if (documentCited(candidate.documentNumber, searchText)) {
    score += BONUS_DOCNUM;
    reasons.push({
      signal: "referencia",
      detail: `${candidate.documentNumber} citado no histórico`,
      points: BONUS_DOCNUM,
    });
  }

  // Aprendizado: este histórico já foi conciliado com este cliente antes. Cresce com as
  // confirmações, mas com teto — memória reforça um candidato, não decide sozinha.
  if (memory && candidate.clientId) {
    const hits = memory.get(candidate.clientId) ?? 0;
    if (hits > 0) {
      const pts = Math.min(BONUS_MEMORIA, 6 + hits * 3);
      score += pts;
      reasons.push({
        signal: "memoria",
        detail: hits === 1
          ? "Histórico parecido já foi conciliado com este cliente"
          : `Histórico parecido já foi conciliado com este cliente ${hits} vezes`,
        points: pts,
      });
    }
  }

  score = Math.min(100, score);
  if (score < opts.minScore) return null;

  const tier: MatchTier = score >= 70 ? "probable" : "weak";
  return { candidate, score, tier, reasons, difference, autoApply: false };
}

/**
 * Avalia a data. `ok: false` REPROVA o candidato — diferente de simplesmente não pontuar.
 *
 * A distinção importa: uma conta vencida há muito tempo ainda pode ser paga (atraso é
 * normal), então ela apenas perde pontos. Já um sinal de orçamento pago ANTES da proposta
 * existir, ou meses depois dela, é impossível — e sem essa reprovação qualquer orçamento
 * antigo de valor parecido viraria sugestão só pelo valor bater.
 */
function scoreDate(
  txDate: string,
  candidate: Candidate,
  opts: MatchOptions,
): { ok: boolean; reason?: MatchReason } {
  if (candidate.dueDate) {
    const delta = daysBetween(txDate, candidate.dueDate); // >0 = pagou depois do vencimento
    if (delta >= -opts.daysBefore && delta <= opts.daysAfter) {
      return {
        ok: true,
        reason: {
          signal: "data",
          detail: delta === 0
            ? "Pago no dia do vencimento"
            : delta > 0
              ? `Pago ${delta} dia(s) após o vencimento`
              : `Pago ${Math.abs(delta)} dia(s) antes do vencimento`,
          points: W_DATE,
        },
      };
    }
    // Fora da janela ainda pontua um pouco, decaindo até 45 dias. Atraso é comum.
    const distance = delta > 0 ? delta - opts.daysAfter : Math.abs(delta) - opts.daysBefore;
    if (distance <= 45) {
      const pts = Math.round(W_DATE * (1 - distance / 45) * 0.5);
      if (pts > 0) {
        return {
          ok: true,
          reason: {
            signal: "data",
            detail: delta > 0
              ? `Pago ${delta} dias após o vencimento`
              : `Pago ${Math.abs(delta)} dias antes do vencimento`,
            points: pts,
          },
        };
      }
    }
    return { ok: true }; // sem pontos de data, mas ainda plausível pelos demais sinais
  }

  // Sem vencimento (sinal de orçamento): a data da proposta é a única âncora temporal,
  // então a janela é eliminatória.
  if (candidate.referenceDate) {
    const age = daysBetween(txDate, candidate.referenceDate);
    if (age < -opts.daysBefore) return { ok: false };      // pagou antes de a proposta existir
    if (age > opts.quoteWindowDays) return { ok: false };  // proposta velha demais
    const pts = Math.round(W_DATE * (1 - Math.max(0, age) / opts.quoteWindowDays) * 0.8);
    return {
      ok: true,
      reason: pts > 0
        ? {
            signal: "data",
            detail: age <= 1 ? "Proposta enviada há poucos dias" : `Proposta de ${age} dias atrás`,
            points: pts,
          }
        : undefined,
    };
  }

  return { ok: true };
}

/** CPF/CNPJ com máscara: dígitos crus não se conferem de olho. */
function formatDoc(doc: string): string {
  if (doc.length === 14) return doc.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})/, "$1.$2.$3/$4-$5");
  if (doc.length === 11) return doc.replace(/(\d{3})(\d{3})(\d{3})(\d{2})/, "$1.$2.$3-$4");
  return doc;
}

function formatBRL(value: number): string {
  return `R$ ${value.toFixed(2).replace(".", ",")}`;
}

/**
 * Pontua todos os candidatos e devolve as melhores sugestões, da mais forte para a mais fraca.
 * `limit` existe porque a tela mostra poucas opções — mas a ordenação considera todas.
 */
export function suggestMatches(
  tx: BankTx,
  candidates: Candidate[],
  options: Partial<MatchOptions> = {},
  limit = 5,
  memory?: Map<string, number>,
): Suggestion[] {
  const scored: Suggestion[] = [];
  for (const candidate of candidates) {
    const suggestion = scoreCandidate(tx, candidate, options, memory);
    if (suggestion) scored.push(suggestion);
  }
  scored.sort((a, b) => b.score - a.score || Math.abs(a.difference) - Math.abs(b.difference));
  return scored.slice(0, limit);
}

/**
 * Um depósito pagando várias contas do mesmo cliente.
 *
 * É o problema da soma de subconjuntos, que é exponencial no caso geral — mas o caso real
 * é pequeno e bem-comportado: contas de um mesmo cliente, poucas em aberto, e só interessa
 * combinação de 2 ou 3 (acima disso a chance de coincidência acidental cresce mais rápido
 * que a utilidade). Por isso a busca é limitada por cliente e por tamanho, em vez de um
 * algoritmo genérico.
 */
export function suggestCombinations(
  tx: BankTx,
  candidates: Candidate[],
  options: Partial<MatchOptions> = {},
  maxPorCliente = 8,
): GroupSuggestion[] {
  const opts = { ...DEFAULT_MATCH_OPTIONS, ...options };
  const tolerance = effectiveTolerance(tx.amount, opts);

  // Agrupa por cliente: só faz sentido somar contas do mesmo pagador.
  const porCliente = new Map<string, Candidate[]>();
  for (const c of candidates) {
    if (c.direction !== tx.transaction_type || !c.clientId) continue;
    if (c.amount <= 0 || c.amount >= tx.amount) continue; // parcela maior que o todo não compõe
    const lista = porCliente.get(c.clientId) ?? [];
    lista.push(c);
    porCliente.set(c.clientId, lista);
  }

  const grupos: GroupSuggestion[] = [];

  for (const [, lista] of porCliente) {
    // As maiores primeiro: combinações relevantes aparecem cedo e o corte não as perde.
    const itens = lista.slice().sort((a, b) => b.amount - a.amount).slice(0, maxPorCliente);

    for (let i = 0; i < itens.length; i++) {
      for (let j = i + 1; j < itens.length; j++) {
        const soma2 = itens[i].amount + itens[j].amount;
        if (Math.abs(soma2 - tx.amount) <= tolerance) {
          grupos.push(montarGrupo(tx, [itens[i], itens[j]], soma2));
          continue;
        }
        // Só tenta trio se a dupla ainda está abaixo do valor recebido.
        if (soma2 >= tx.amount) continue;
        for (let k = j + 1; k < itens.length; k++) {
          const soma3 = soma2 + itens[k].amount;
          if (Math.abs(soma3 - tx.amount) <= tolerance) {
            grupos.push(montarGrupo(tx, [itens[i], itens[j], itens[k]], soma3));
          }
        }
      }
    }
  }

  grupos.sort((a, b) => Math.abs(a.difference) - Math.abs(b.difference) || a.candidates.length - b.candidates.length);
  return grupos.slice(0, 3);
}

function montarGrupo(tx: BankTx, itens: Candidate[], soma: number): GroupSuggestion {
  const nomes = itens.map((c) => c.label).join(" + ");
  return {
    candidates: itens,
    total: Number(soma.toFixed(2)),
    difference: Number((tx.amount - soma).toFixed(2)),
    clientName: itens[0].clientName ?? null,
    detail: `${itens.length} contas de ${itens[0].clientName || "um mesmo cliente"} somam este valor: ${nomes}`,
  };
}

/**
 * Uma sugestão só pode ser aplicada sozinha se for da camada de certeza E não houver
 * empate: dois candidatos igualmente certos (mesmo cliente, mesmo valor, contas
 * diferentes) precisam de olho humano para decidir qual conta está sendo paga.
 */
export function pickAutoApply(suggestions: Suggestion[]): Suggestion | null {
  const certain = suggestions.filter((s) => s.autoApply);
  if (certain.length !== 1) return null;
  return certain[0];
}
