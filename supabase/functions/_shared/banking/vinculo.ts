// O que uma linha do extrato provavelmente PAGA — e quando isso pode ser usado sem perguntar.
//
// Em 25/09/2026 três entradas da fila eram sinais de orçamento já lançados à mão. A fila
// não sabia disso, e "aprovar" criava uma receita nova ao lado da existente. O mesmo vale
// para as saídas: conta a pagar lançada pela nota fiscal, paga por Pix, voltava do banco
// como despesa nova.
//
// Aqui a linha ganha o vínculo mais provável (com alternativas) usando o mesmo motor de
// pontuação da Conciliação, e uma POLÍTICA escrita de quando esse vínculo vale sozinho.
import { suggestMatches } from "./matching.ts";
import type { BankTx, Candidate, MatchTier } from "./types.ts";

export type TipoDeVinculo = "receivable" | "payable" | "existing_payment" | "quote_deposit" | "service_order_balance";

export interface OpcaoDeVinculo {
  tipo: TipoDeVinculo;
  /** Id do candidato (recebível, conta, pagamento, orçamento ou OS). */
  id: string;
  rotulo: string;
  valor: number;
  confianca: number;
  nivel: MatchTier;
  motivos: string[];
  /** Recebido menos esperado. */
  diferenca: number;
  /** Lançamento a CASAR com a linha (recebível ou conta a pagar), quando o vínculo é esse. */
  lancamentoId: string | null;
  lado: "payable" | "receivable" | null;
  ordemDeServicoId: string | null;
  clienteId: string | null;
  clienteNome: string | null;
  /** Aprovar converte o orçamento em OS — decisão de negócio, nunca automática. */
  converteOrcamento: boolean;
  /** Já existe lançamento para este dinheiro: aprovar sem casar contaria duas vezes. */
  jaLancado: boolean;
}

export interface VinculoSugerido {
  principal: OpcaoDeVinculo;
  alternativas: OpcaoDeVinculo[];
}

const TIPOS_ACIONAVEIS = new Set<string>(["receivable", "payable", "existing_payment", "quote_deposit", "service_order_balance"]);

function opcao(s: ReturnType<typeof suggestMatches>[number]): OpcaoDeVinculo {
  const c = s.candidate as Candidate & { payableId?: string | null };
  const tipo = c.kind as TipoDeVinculo;
  let lancamentoId: string | null = null;
  let lado: OpcaoDeVinculo["lado"] = null;
  if (tipo === "receivable") { lancamentoId = c.id; lado = "receivable"; }
  else if (tipo === "payable") { lancamentoId = c.id; lado = "payable"; }
  else if (tipo === "existing_payment") {
    lancamentoId = c.receivableId ?? c.payableId ?? null;
    lado = c.receivableId ? "receivable" : c.payableId ? "payable" : null;
  }
  return {
    tipo,
    id: c.id,
    rotulo: c.label,
    valor: Number(c.amount),
    confianca: s.score,
    nivel: s.tier,
    motivos: s.reasons.map((r) => r.detail),
    diferenca: s.difference,
    lancamentoId,
    lado,
    ordemDeServicoId: c.serviceOrderId ?? null,
    clienteId: c.clientId ?? null,
    clienteNome: c.clientName ?? null,
    converteOrcamento: !!c.convertsQuote,
    jaLancado: tipo === "existing_payment",
  };
}

/**
 * O vínculo mais provável e até duas alternativas. `clienteReconhecido` é quem o
 * identificador de contraparte apontou (por documento ou histórico): candidatos dele sobem,
 * porque "este dinheiro é do Acrisio" já foi estabelecido antes do valor ser comparado.
 */
/** Dias entre duas datas ISO. */
function dias(a: string, b: string): number {
  return Math.round((Date.parse(a.slice(0, 10)) - Date.parse(b.slice(0, 10))) / 86_400_000);
}

/**
 * Pagamento já lançado só é o mesmo dinheiro se estiver perto no tempo. Sem esta janela, a
 * STONE (R$ 5.000 em ago/2025) aparecia como o sinal do ORÇ-00061 (R$ 5.000 em 2026) só
 * porque o valor era igual.
 */
const JANELA_DO_JA_LANCADO = 45;

export function sugerirVinculo(
  tx: BankTx,
  candidatos: Candidate[],
  clienteReconhecido?: { id: string; nome: string } | null,
): VinculoSugerido | null {
  const uteis = candidatos.filter((c) =>
    TIPOS_ACIONAVEIS.has(c.kind) && c.direction === tx.transaction_type
    && !(c.kind === "existing_payment" && c.dueDate && Math.abs(dias(tx.transaction_date, c.dueDate)) > JANELA_DO_JA_LANCADO)
    // O motor recusa diferença de valor acima de 25% em qualquer caso; filtrar antes de pontuar dá
    // o mesmo resultado sem pontuar centenas de candidatos por linha — foi pontuação demais que
    // derrubou a varredura pelo limite de CPU (erro 546) em agosto.
    && Math.abs(Number(c.amount) - Number(tx.amount)) <= Math.max(1, Math.abs(Number(c.amount)) * 0.25));
  const sugestoes = suggestMatches(tx, uteis, {}, 6).map(opcao);

  /**
   * Possível duplicata que o motor não "reconhece": o sinal do ORÇ-00077 foi lançado à mão
   * como R$ 2.520 e chegou no banco como R$ 2.498 (tarifa), 5 dias antes — e o cliente do
   * orçamento é "Cliente Final", sem nome nem documento para bater. Valor até 3% e data até
   * 7 dias de um pagamento já lançado não PROVA nada, mas proíbe aprovar no escuro.
   */
  for (const c of uteis) {
    if (c.kind !== "existing_payment" || !c.dueDate) continue;
    if (sugestoes.some((o) => o.id === c.id)) continue;
    const diferenca = Number((tx.amount - Number(c.amount)).toFixed(2));
    if (Math.abs(diferenca) > Math.max(1, Number(c.amount) * 0.03)) continue;
    if (Math.abs(dias(tx.transaction_date, c.dueDate)) > 7) continue;
    const o = opcao({
      candidate: c, score: 50, tier: "weak", difference: diferenca, autoApply: false,
      reasons: [{ signal: "duplicata", points: 50,
        detail: `Valor e data muito próximos de um pagamento já lançado (${Math.abs(dias(tx.transaction_date, c.dueDate))} dia(s), diferença de R$ ${Math.abs(diferenca).toFixed(2).replace(".", ",")}) — possível duplicata` }],
    });
    sugestoes.push(o);
  }
  if (clienteReconhecido) {
    for (const o of sugestoes) {
      if (o.clienteId && o.clienteId === clienteReconhecido.id) {
        o.confianca = Math.min(100, o.confianca + 10);
        o.motivos.push(`É do cliente reconhecido (${clienteReconhecido.nome})`);
        if (o.nivel === "weak" && o.confianca >= 70) o.nivel = "probable";
      }
    }
    sugestoes.sort((a, b) => b.confianca - a.confianca || Math.abs(a.diferenca) - Math.abs(b.diferenca));
  }
  if (sugestoes.length === 0) return null;
  sugestoes.sort((a, b) => b.confianca - a.confianca || Math.abs(a.diferenca) - Math.abs(b.diferenca));
  const [principal, ...resto] = sugestoes;
  return { principal, alternativas: resto.slice(0, 2) };
}

/**
 * O vínculo que a aprovação usa SEM a pessoa escolher: NENHUM.
 *
 * Decisão do dono (26/09/2026): ligar o dinheiro a uma OS, conta ou pagamento se faz pelo
 * casamento de informações lançadas (a sugestão) OU à mão, "mas o sistema deve sempre
 * questionar". Antes, vínculo "certo" ou com 70+ pontos era usado sozinho na aprovação; agora
 * toda sugestão vira pergunta. A função continua existindo para a tela e o servidor lerem a
 * mesma política.
 */
export function vinculoAutomatico(_v: VinculoSugerido | null | undefined): OpcaoDeVinculo | null {
  return null;
}

/**
 * Há vínculo sugerido e ninguém escolheu: a linha não é aprovada no escuro. Em lote, pelo
 * assistente ou pelo "lançar sozinho", ela fica para alguém responder "é este" ou "é outro".
 */
export function exigeDecisao(v: VinculoSugerido | null | undefined): boolean {
  return !!v?.principal;
}

/** A sugestão é de algo que JÁ está lançado (aprovar como novo contaria duas vezes). */
export function podeJaEstarLancado(v: VinculoSugerido | null | undefined): boolean {
  if (!v) return false;
  return [v.principal, ...v.alternativas].some((o) => o.jaLancado && (o.confianca >= 50 || Math.abs(o.diferenca) < 0.01));
}

/** O que as perguntas da OS e da OC precisam saber de uma linha da fila. */
export interface LinhaComPerguntas {
  suggested_service_order_id?: string | null;
  suggested_purchase_order_id?: string | null;
  vinculo_sugerido?: VinculoSugerido | null;
  evidencia?: { anotacao?: { id?: string; os_id?: string | null } | null } | null;
}

/** A OS sugerida é a de uma das opções do vínculo: a escolha do vínculo já responde. */
export function osVemDoVinculo(p: LinhaComPerguntas): boolean {
  const os = p.suggested_service_order_id;
  const v = p.vinculo_sugerido;
  return !!os && !!v && [v.principal, ...(v.alternativas ?? [])].some((o) => o?.ordemDeServicoId === os);
}

/** A OS que o dono DISSE numa anotação ("o Pix de 800 é da OS-60") — já é a resposta. */
export function osAnotada(p: LinhaComPerguntas): string | null {
  const os = p.evidencia?.anotacao?.os_id ?? null;
  return os && os === p.suggested_service_order_id ? os : null;
}

/** "Paga esta OC?" aparece nesta linha. */
export function temPerguntaDaOC(p: LinhaComPerguntas): boolean {
  return !!p.suggested_purchase_order_id;
}

/**
 * "É desta OS?" aparece nesta linha: OS sugerida que não é a do vínculo (o vínculo já
 * pergunta) — ou que o dono anotou, para ele ver e poder desdizer.
 */
export function temPerguntaDaOS(p: LinhaComPerguntas): boolean {
  return !!p.suggested_service_order_id && (!osVemDoVinculo(p) || !!osAnotada(p));
}

/**
 * Alguma pergunta de OS ou OC está sem resposta. Decisão do dono (26/09/2026): a ligação
 * com o serviço "deve sempre questionar" — linha assim não entra no lote, no grupo nem na
 * aprovação em bloco, para a pergunta não sumir num clique dado para outra coisa.
 */
export function perguntaDaOSAberta(
  p: LinhaComPerguntas,
  resposta?: { serviceOrderId?: string | null; purchaseOrderId?: string | null },
): boolean {
  if (temPerguntaDaOC(p) && resposta?.purchaseOrderId === undefined) return true;
  if (temPerguntaDaOS(p) && !osVemDoVinculo(p) && resposta?.serviceOrderId === undefined && !osAnotada(p)) {
    // A OS da OC confirmada ("Sim, é dela") já respondeu a OS.
    return !(resposta?.purchaseOrderId && resposta?.serviceOrderId !== undefined);
  }
  return false;
}
