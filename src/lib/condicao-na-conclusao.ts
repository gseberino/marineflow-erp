// Condição "100% na conclusão" — usada quando um orçamento vira OS SEM sinal (27/10/2026).
//
// Caso real: orçamento adicional de um cliente que já tem serviço em andamento; fica tudo para
// acertar no final. A conversão troca a condição do orçamento por esta, para o PDF, o resumo e as
// contas a receber dizerem o combinado. Na conclusão, `ensureCompletionReceivables` lança um título
// único vencendo na data da conclusão (parcela tipo 'entrega').

import type { DepositInstallment } from './quote-deposit';

export const ROTULO_TUDO_NA_CONCLUSAO = '100% na entrega';

export const PARCELA_TUDO_NA_CONCLUSAO: DepositInstallment = {
  label: 'Total na conclusão',
  services_pct: 100,
  parts_pct: 100,
  expenses_pct: 100,
  days_after_approval: 0,
  tipo: 'entrega',
};

export interface CondicaoGravada {
  payment_condition_preset_id: string | null;
  payment_conditions: string;
  custom_payment_installments: DepositInstallment[] | null;
}

interface PresetLike {
  id: string;
  label: string;
  installments?: unknown;
}

/** Preset que cobra serviços, peças E despesas inteiros numa parcela só, na entrega. */
function cobraTudoNaEntrega(p: PresetLike): boolean {
  const rows = Array.isArray(p.installments) ? (p.installments as DepositInstallment[]) : [];
  if (rows.length !== 1) return false;
  const r = rows[0];
  return r.tipo === 'entrega'
    && Number(r.services_pct ?? r.percent ?? 0) === 100
    && Number(r.parts_pct ?? r.percent ?? 0) === 100
    && Number(r.expenses_pct ?? 0) === 100;
}

/**
 * Usa o preset cadastrado quando ele cobra tudo na entrega (inclusive despesas). Sem ele, grava a
 * parcela como condição personalizada — nunca um preset que deixe deslocamento/operacional de fora.
 */
export function condicaoTudoNaConclusao(presets: PresetLike[] | null | undefined): CondicaoGravada {
  const preset = (presets || []).find(cobraTudoNaEntrega);
  if (preset) {
    return {
      payment_condition_preset_id: preset.id,
      payment_conditions: preset.label,
      custom_payment_installments: null,
    };
  }
  return {
    payment_condition_preset_id: null,
    payment_conditions: ROTULO_TUDO_NA_CONCLUSAO,
    custom_payment_installments: [PARCELA_TUDO_NA_CONCLUSAO],
  };
}
