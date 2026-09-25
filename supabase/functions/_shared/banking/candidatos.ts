// O que uma ENTRADA de dinheiro pode estar pagando — num lugar só.
//
// Vivia dentro da edge `banking-reconcile`, que é usada pela Conciliação antiga, pelo
// briefing e pelo agente. A fila do Extrato (finance-review) não tinha acesso a ela, e a
// consequência foi medida em 25/09/2026: das 24 entradas esperando aprovação, três eram o
// sinal de um orçamento JÁ lançado à mão (ORÇ-00077, ORÇ-00084, ORÇ-00075). Aprovar criava
// uma receita nova ao lado da que já existia — o mesmo dinheiro contado duas vezes no DRE.
//
// Agora as duas edges leem daqui. A lógica é a mesma de antes; o que mudou é que os
// totais por OS e os sinais já pagos são lidos numa consulta cada, e não uma por orçamento
// ou por OS (eram até 400 idas ao banco numa varredura).
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { expectedDepositAmount } from "./quote-deposit.ts";
import type { Candidate } from "./types.ts";

type DbClient = SupabaseClient<any, "public", any>;

/** Status que significam "ainda não quitado". */
export const ABERTOS = ["pending", "partially_paid", "overdue", "scheduled"];
/** OS que ainda podem receber dinheiro. */
export const OS_ATIVAS = ["open", "scheduled", "in_progress", "awaiting_parts", "completed", "invoiced", "approved"];

/** Até 1000 ids por `in(...)`: acima disso a URL do PostgREST estoura. */
function fatias<T>(lista: T[], tamanho = 150): T[][] {
  const r: T[][] = [];
  for (let i = 0; i < lista.length; i += tamanho) r.push(lista.slice(i, i + tamanho));
  return r;
}

/**
 * Tudo que uma linha do extrato pode estar pagando, dos dois lados: recebíveis e contas a
 * pagar em aberto, cobranças, sinais de orçamento, pagamentos já lançados e saldo de OS.
 */
export async function carregarCandidatos(admin: DbClient): Promise<Candidate[]> {
  const candidates: Candidate[] = [];

  // 1. Contas a receber em aberto.
  const { data: receivables } = await admin
    .from("receivables")
    .select("id, description, balance_amount, due_date, client_id, service_order_id, clients(name, cpf_cnpj), service_orders(service_order_number)")
    .in("status", ABERTOS)
    .gt("balance_amount", 0)
    .limit(500);

  for (const r of (receivables ?? []) as any[]) {
    const cliente = r.clients;
    candidates.push({
      kind: "receivable",
      id: r.id,
      label: r.description || "Conta a receber",
      amount: Number(r.balance_amount),
      direction: "credit",
      dueDate: r.due_date,
      clientId: r.client_id ?? null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
      documentNumber: r.service_orders?.service_order_number ?? null,
      serviceOrderId: r.service_order_id ?? null,
    });
  }

  // 1b. Contas a pagar em aberto — a nota fiscal lançada e paga depois por Pix, por
  //     exemplo. Sem elas a saída do banco voltava como despesa nova.
  const { data: payables } = await admin
    .from("payables")
    .select("id, description, balance_amount, due_date, supplier_id, suppliers(name, cnpj_cpf)")
    .in("status", ABERTOS)
    .gt("balance_amount", 0)
    .limit(500);

  for (const p of (payables ?? []) as any[]) {
    candidates.push({
      kind: "payable",
      id: p.id,
      label: p.description || "Conta a pagar",
      amount: Number(p.balance_amount),
      direction: "debit",
      dueDate: p.due_date,
      clientName: p.suppliers?.name ?? null,
      clientDocument: p.suppliers?.cnpj_cpf ?? null,
    });
  }

  // 2. Cobranças avulsas (sem conta a receber por trás — as demais já entraram acima).
  const { data: collections } = await admin
    .from("collections")
    .select("id, description, amount, due_date, client_id, receivable_id, clients(name, cpf_cnpj)")
    .is("receivable_id", null)
    .not("status", "in", '("paid","cancelled")')
    .limit(200);

  for (const c of (collections ?? []) as any[]) {
    const cliente = c.clients;
    candidates.push({
      kind: "collection",
      id: c.id,
      label: c.description || "Cobrança",
      amount: Number(c.amount),
      direction: "credit",
      dueDate: c.due_date,
      clientId: c.client_id ?? null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
    });
  }

  // 3. Sinal de orçamento. Inclui os marcados como "aguardando sinal" e os enviados ao
  //    cliente (podem ter sido aprovados por WhatsApp sem ninguém mexer no status).
  const { data: settings } = await admin
    .from("app_settings").select("key, value").eq("key", "quote_deposit_percentage").maybeSingle();
  const globalPct = Number((settings as any)?.value ?? 30) || 30;

  const { data: quotes } = await admin
    .from("service_orders")
    .select(`id, service_order_number, quote_status, status, grand_total, created_at,
             labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total,
             subcontract_cost_total, is_travel_billable, discount_amount, tax_amount,
             custom_payment_installments, payment_condition_preset_id, payment_conditions,
             client_id, clients(name, cpf_cnpj),
             payment_condition_presets(label, installments)`)
    .in("quote_status", ["awaiting_deposit", "sent"])
    .not("status", "in", '("cancelled")')
    .limit(200);
  const listaDeOrcamentos = (quotes ?? []) as any[];

  // Sinal já pago: o orçamento não está mais esperando dinheiro. Uma consulta para todos.
  const comSinalPago = new Set<string>();
  for (const ids of fatias(listaDeOrcamentos.map((q) => q.id as string))) {
    const { data } = await admin.from("receivables")
      .select("service_order_id").in("service_order_id", ids).eq("is_deposit", true).eq("status", "paid");
    for (const r of (data ?? []) as any[]) comSinalPago.add(r.service_order_id);
  }

  // Condições pré-cadastradas: alguns orçamentos guardam só o rótulo em
  // `payment_conditions`, sem o id do preset — o mesmo fallback da tela de orçamento.
  const { data: presets } = await admin.from("payment_condition_presets").select("id, label, installments");
  const presetPorLabel = new Map<string, any>(((presets ?? []) as any[]).map((p) => [String(p.label), p]));

  for (const q of listaDeOrcamentos) {
    if (comSinalPago.has(q.id)) continue;
    // Precedência idêntica à do orçamento e do botão "Receber sinal": a condição
    // pré-cadastrada manda; sem ela, a condição avulsa; sem nenhuma, o percentual padrão.
    const preset = q.payment_condition_presets ?? presetPorLabel.get(String(q.payment_conditions ?? ""));
    const installments = Array.isArray(preset?.installments)
      ? preset.installments
      : (Array.isArray(q.custom_payment_installments) ? q.custom_payment_installments : null);

    const esperado = expectedDepositAmount(q as never, installments, globalPct);
    if (!esperado) continue;

    const cliente = q.clients;
    candidates.push({
      kind: "quote_deposit",
      id: q.id,
      label: `Sinal do ${q.service_order_number}`,
      amount: esperado.amount,
      amountSource: esperado.source,
      conditionLabel: esperado.source === "condicao"
        ? (preset?.label ?? "condição do orçamento")
        : esperado.source === "padrao" ? "100% materiais + 50% mão de obra" : null,
      direction: "credit",
      dueDate: null,
      referenceDate: String(q.created_at).slice(0, 10),
      clientId: q.client_id ?? null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
      documentNumber: q.service_order_number,
      serviceOrderId: q.id,
      convertsQuote: true,
    });
  }

  // 4. Pagamentos já registrados no ERP e ainda não ligados a nenhuma linha do extrato.
  //    Quem lança o recebimento na hora e importa o extrato depois não tem conta "em
  //    aberto" para casar — tem um pagamento para amarrar. Janela de 120 dias.
  const desde = new Date(Date.now() - 120 * 86_400_000).toISOString().slice(0, 10);
  const { data: pagamentos } = await admin
    .from("payments")
    .select(`id, amount, payment_date, receivable_id, payable_id, notes,
             receivables(description, client_id, service_order_id, bank_transaction_id, clients(name, cpf_cnpj), service_orders(service_order_number)),
             payables(description, bank_transaction_id, suppliers(name, cnpj_cpf))`)
    .eq("status", "confirmed")
    .gte("payment_date", desde)
    .limit(300);

  const { data: jaVinculados } = await admin
    .from("bank_transactions").select("reconciled_payment_id").not("reconciled_payment_id", "is", null);
  const vinculados = new Set(((jaVinculados ?? []) as any[]).map((r) => r.reconciled_payment_id));

  for (const p of (pagamentos ?? []) as any[]) {
    if (vinculados.has(p.id)) continue;
    const rec = p.receivables;
    const conta = p.payables;
    // Lançamento já casado com outra linha do extrato não é candidato: o dinheiro dele já
    // tem banco. Oferecer de novo convidaria a casar duas linhas com o mesmo lançamento.
    if (rec?.bank_transaction_id || conta?.bank_transaction_id) continue;
    const cliente = rec?.clients ?? (conta?.suppliers ? { name: conta.suppliers.name, cpf_cnpj: conta.suppliers.cnpj_cpf } : null);
    const descricao = rec?.description ?? conta?.description;
    candidates.push({
      kind: "existing_payment",
      id: p.id,
      label: descricao ? `Pagamento já lançado: ${descricao}` : "Pagamento já lançado",
      amount: Number(p.amount),
      // Pagamento de conta a receber é dinheiro entrando; de conta a pagar, saindo.
      direction: p.receivable_id ? "credit" : "debit",
      dueDate: p.payment_date,
      clientId: rec?.client_id ?? null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
      documentNumber: rec?.service_orders?.service_order_number ?? null,
      serviceOrderId: rec?.service_order_id ?? null,
      receivableId: p.receivable_id ?? null,
      payableId: p.payable_id ?? null,
    });
  }

  // 5. Saldo de OS ativa ainda não lançado como conta a receber.
  const { data: orders } = await admin
    .from("service_orders")
    .select("id, service_order_number, grand_total, created_at, client_id, clients(name, cpf_cnpj)")
    .in("status", OS_ATIVAS)
    .gt("grand_total", 0)
    .limit(200);
  const listaDeOS = (orders ?? []) as any[];

  const lancadoPorOS = new Map<string, number>();
  for (const ids of fatias(listaDeOS.map((o) => o.id as string))) {
    const { data } = await admin.from("receivables")
      .select("service_order_id, amount").in("service_order_id", ids).neq("status", "cancelled");
    for (const r of (data ?? []) as any[]) {
      lancadoPorOS.set(r.service_order_id, (lancadoPorOS.get(r.service_order_id) ?? 0) + Number(r.amount || 0));
    }
  }

  for (const o of listaDeOS) {
    const saldo = Number(o.grand_total) - (lancadoPorOS.get(o.id) ?? 0);
    if (saldo <= 0.01) continue; // já está todo lançado; os recebíveis acima cobrem
    const cliente = o.clients;
    candidates.push({
      kind: "service_order_balance",
      id: o.id,
      label: `Saldo da ${o.service_order_number}`,
      amount: Number(saldo.toFixed(2)),
      direction: "credit",
      dueDate: null,
      referenceDate: String(o.created_at).slice(0, 10),
      clientId: o.client_id ?? null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
      documentNumber: o.service_order_number,
      serviceOrderId: o.id,
    });
  }

  return candidates;
}
