// Forma de pagamento — o que o banco aceita em payments.payment_method (05/10/2026).
//
// POR QUE EXISTE: register_payment, register_deposit_and_convert e approve_quote_full recebiam a
// forma como texto livre e mandavam direto para a RPC. "pix" passava (é igual nas duas línguas);
// "dinheiro" não: o sinal de R$ 800 da MP Motor Homes (ORÇ-00095) falhou DEPOIS do "sim <PIN>" do
// dono com "violates check constraint payments_payment_method_check". O CHECK do banco aceita só os
// seis códigos abaixo. Aqui o que o modelo disser vira o código — ou é recusado ANTES da pendência
// (preValidar), em vez de depois da confirmação.

/** Os códigos do CHECK payments_payment_method_check. */
export const FORMAS_DE_PAGAMENTO = ["pix", "cash", "credit_card", "debit_card", "bank_transfer", "check"] as const;
export type FormaDePagamento = typeof FORMAS_DE_PAGAMENTO[number];

const SINONIMOS: Record<string, FormaDePagamento> = {
  pix: "pix",
  dinheiro: "cash", especie: "cash", "em especie": "cash", "em dinheiro": "cash", cash: "cash",
  credito: "credit_card", "cartao de credito": "credit_card", "cartao credito": "credit_card", credit_card: "credit_card", credit: "credit_card",
  debito: "debit_card", "cartao de debito": "debit_card", "cartao debito": "debit_card", debit_card: "debit_card", debit: "debit_card",
  transferencia: "bank_transfer", "transferencia bancaria": "bank_transfer", ted: "bank_transfer", doc: "bank_transfer",
  deposito: "bank_transfer", "deposito bancario": "bank_transfer", boleto: "bank_transfer", bank_transfer: "bank_transfer",
  cheque: "check", check: "check",
};

function normalizar(v: unknown): string {
  return String(v ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[_-]+/g, (m) => (m === "_" ? "_" : " ")).replace(/\s+/g, " ").trim();
}

/** O código do banco para o que foi dito; null = não reconhecido (ou ambíguo, como "cartão"). */
export function formaDePagamento(v: unknown): FormaDePagamento | null {
  const n = normalizar(v);
  if (!n) return null;
  return SINONIMOS[n] ?? SINONIMOS[n.replace(/ /g, "_")] ?? null;
}

/** O esquema do argumento, igual nas três tools: o modelo já recebe a lista fechada. */
export const ESQUEMA_DA_FORMA = {
  type: "string",
  enum: [...FORMAS_DE_PAGAMENTO],
  description: "pix · cash (dinheiro/espécie) · credit_card (cartão de crédito) · debit_card (cartão de débito) · bank_transfer (transferência, TED, depósito, boleto) · check (cheque).",
} as const;

/** Para o preValidar: recusa antes de a pendência nascer, com as opções. null = ok. */
export function validarForma(args: Record<string, unknown> | null | undefined, campo = "payment_method"): { error: string } | null {
  if (formaDePagamento(args?.[campo])) return null;
  return {
    error: `Forma de pagamento "${String(args?.[campo] ?? "")}" não reconhecida. Use: pix, dinheiro (cash), cartão de crédito (credit_card), cartão de débito (debit_card), transferência (bank_transfer) ou cheque (check). Se o dono disse só "cartão", pergunte se foi crédito ou débito.`,
  };
}
