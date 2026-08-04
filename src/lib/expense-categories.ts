/**
 * APOSENTADA em 03/08/2026 — não use em tela nova.
 *
 * Esta lista fixa de dez itens (alimentação, pedágio, hospedagem, ferry…) era usada como se
 * fosse plano de contas em três lugares: Conciliação Bancária, despesas de campo da OS e o
 * formulário da OS. Nenhum dos nomes correspondia a uma categoria real de
 * `financial_categories`, então toda despesa classificada por aqui nascia sem grupo no DRE
 * — e valor sem grupo não entra em nenhuma linha do resultado: some, sem erro e sem aviso.
 *
 * A auditoria do Financeiro achou R$ 64.252 perdidos assim por outro caminho, incluindo um
 * lançamento em "Outros" feito no mesmo dia da correção.
 *
 * Substituída por `CategoriaDespesaSelect`, que lê o plano de contas e permite criar a
 * categoria que falta sem sair da tela. O tipo continua exportado apenas para não quebrar
 * alguma assinatura remanescente.
 */
export const OPERATIONAL_EXPENSE_CATEGORIES = [] as const;

export type ExpenseCategory = string;
