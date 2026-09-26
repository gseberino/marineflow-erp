// Quais propostas o sistema lança sem clique — a regra num lugar só, com teste.
//
// Decisão do dono (25/09/2026), sobre a calibração medida nas aprovações reais: saídas com
// confiança 85+ abaixo de R$ 500 acertaram a categoria em 98,6% das 590 vezes.
//
// Travas de 26/09/2026 (achadas antes da primeira rodada):
// - Regra marcada "só sugerir" dá confiança 95 à linha; sem trava, passava pelo corte de 85
//   como se fosse "lançar sozinha". Só a regra com autonomia lança sem clique.
// - Nada que fica FORA do resultado (fatura, empréstimo, aplicação, retirada) vai sozinho por
//   confiança: o erro mais caro não é a categoria trocada, é a despesa que some do DRE.
// - Linha em que o banco não disse para quem foi (compra no débito sem loja) nunca vai
//   sozinha: a categoria depende de uma informação que só a pessoa tem.
//
// Decisões de 26/09/2026: só com confiança 90+ (app_settings); nada com nome cortado pelo banco;
// nada com OS, OC ou vínculo sugerido — "o sistema deve sempre questionar".
import { exigeDecisao, podeJaEstarLancado, type VinculoSugerido } from "../_shared/banking/vinculo.ts";

/** Decisão do dono (26/09/2026): "apenas com 90%+ de confiança". Configuração nenhuma desce disto. */
export const PISO_DA_CONFIANCA = 90;

export interface LinhaCandidata {
  kind: string;
  bank_transaction_id: string;
  confidence: number;
  suggested_amount: number;
  suggested_category: string | null;
  dre_group?: string | null;
  vinculo_sugerido?: VinculoSugerido | null;
  /** A proposta veio de uma regra marcada "Preencher e esperar meu OK". */
  regra_so_sugere?: boolean;
  /** O banco não informou para quem foi (débito sem loja, Pix sem nome, só a empresa de pagamento). */
  sem_identidade?: boolean;
  /** O fornecedor foi reconhecido pelo nome cortado pelo banco, não pelo nome inteiro. */
  nome_cortado?: boolean;
  /** O nome começa como o de um fornecedor com regra sua (outra grafia): o dono decide. */
  lembra_regra?: boolean;
  /** OS ou OC sugerida: é pergunta, e só a pessoa responde (decisão de 26/09/2026). */
  suggested_service_order_id?: string | null;
  suggested_purchase_order_id?: string | null;
}

export interface CriterioDoAutomatico {
  confiancaMinima: number;
  limiteLote: number;
  /** Transações com alerta do vigilante pendente. */
  comAlerta: Set<string>;
  /** Já lançadas pela regra com autonomia nesta mesma varredura. */
  jaPorRegra: Set<string>;
}

/** Por que uma linha NÃO vai sozinha (para teste e diagnóstico); null = vai. */
export function motivoParaNaoLancarSozinho(l: LinhaCandidata, c: CriterioDoAutomatico): string | null {
  if (l.kind !== "create_payable") return "só saída é lançada sozinha";
  if (c.jaPorRegra.has(l.bank_transaction_id)) return "já lançada pela regra";
  if (l.regra_so_sugere) return "a regra está marcada para só sugerir";
  if (l.sem_identidade) return "o banco não informou para quem foi (ou só a empresa de pagamento)";
  if (l.nome_cortado) return "o fornecedor foi reconhecido pelo nome cortado pelo banco — confira";
  if (l.lembra_regra) return "o nome começa como o de um fornecedor com regra sua — confira se é ele";
  if (l.suggested_service_order_id || l.suggested_purchase_order_id) return "há uma OS ou OC sugerida: a ligação com o serviço espera a sua resposta";
  if (Number(l.confidence) < Math.max(PISO_DA_CONFIANCA, c.confiancaMinima)) return "confiança abaixo do mínimo";
  if (!(Number(l.suggested_amount) < c.limiteLote)) return "acima do limite de lote";
  if (!l.suggested_category || l.suggested_category === "Outras despesas") return "sem categoria de verdade";
  if (l.dre_group === "nao_operacional") return "fica fora do resultado (fatura, empréstimo, aplicação ou retirada)";
  if (exigeDecisao(l.vinculo_sugerido)) {
    return podeJaEstarLancado(l.vinculo_sugerido) ? "pode já estar lançada" : "há um vínculo sugerido: espera a sua resposta";
  }
  if (c.comAlerta.has(l.bank_transaction_id)) return "tem alerta do vigilante";
  return null;
}

export function selecionarParaLancarSozinho<T extends LinhaCandidata>(linhas: T[], c: CriterioDoAutomatico): T[] {
  return linhas.filter((l) => motivoParaNaoLancarSozinho(l, c) === null);
}
