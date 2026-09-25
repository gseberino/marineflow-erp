// Quais propostas o sistema lança sem clique — a regra num lugar só, com teste.
//
// Decisão do dono (25/09/2026), sobre a calibração medida nas aprovações reais: saídas com
// confiança 85+ abaixo de R$ 500 acertaram a categoria em 98,6% das 590 vezes.
import { exigeDecisao, type VinculoSugerido } from "../_shared/banking/vinculo.ts";

export interface LinhaCandidata {
  kind: string;
  bank_transaction_id: string;
  confidence: number;
  suggested_amount: number;
  suggested_category: string | null;
  vinculo_sugerido?: VinculoSugerido | null;
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
  if (Number(l.confidence) < Math.max(85, c.confiancaMinima)) return "confiança abaixo do mínimo";
  if (!(Number(l.suggested_amount) < c.limiteLote)) return "acima do limite de lote";
  if (!l.suggested_category || l.suggested_category === "Outras despesas") return "sem categoria de verdade";
  if (exigeDecisao(l.vinculo_sugerido)) return "pode já estar lançada";
  if (c.comAlerta.has(l.bank_transaction_id)) return "tem alerta do vigilante";
  return null;
}

export function selecionarParaLancarSozinho<T extends LinhaCandidata>(linhas: T[], c: CriterioDoAutomatico): T[] {
  return linhas.filter((l) => motivoParaNaoLancarSozinho(l, c) === null);
}
