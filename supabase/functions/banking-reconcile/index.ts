// Edge Function: banking-reconcile
//
// Monta o que a empresa tem em aberto, pontua contra as transações do extrato e devolve
// sugestões ordenadas. Só a camada de certeza (identificador do Pix, ou documento do
// pagador com valor exato) pode ser aplicada sozinha — decisão do usuário em 27/07/2026.
//
// O que mudou em relação à tela antiga: ela só comparava contas a receber e a pagar já
// lançadas, e para dinheiro entrando só enxergava OS concluída ou faturada. Sinal de
// orçamento — o caso mais comum de entrada avulsa — nunca virava candidato, porque só
// existe como conta a receber DEPOIS que alguém registra o pagamento na mão.
//
// verify_jwt=false no config.toml porque há dois chamadores: o painel (manda o JWT do
// usuário, validado aqui) e o cron da varredura diária (manda só x-cron-secret).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { suggestMatches, pickAutoApply } from "../_shared/banking/matching.ts";
import { expectedDepositAmount } from "../_shared/banking/quote-deposit.ts";
import type { BankTx, Candidate, Suggestion } from "../_shared/banking/types.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Status que significam "ainda não quitado". */
const ABERTOS = ["pending", "partially_paid", "overdue", "scheduled"];
/** OS que ainda podem receber dinheiro. */
const OS_ATIVAS = ["open", "scheduled", "in_progress", "awaiting_parts", "completed", "invoiced", "approved"];

interface ReconcileBody {
  action?: "suggest" | "auto";
  transaction_id?: string;
  /** Só simula: devolve o que faria, sem gravar. */
  dry_run?: boolean;
  limit?: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // ── Autenticação: painel (JWT) ou cron (segredo) ───────────────────────────
  const cronSecret = req.headers.get("x-cron-secret");
  const isCron = !!cronSecret && cronSecret === Deno.env.get("CRON_SECRET");
  if (!isCron) {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) return jr({ error: "unauthorized" }, 401);
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData?.user) return jr({ error: "unauthorized" }, 401);
  }

  const body: ReconcileBody = await req.json().catch(() => ({}));
  const action = body.action ?? "suggest";

  try {
    // ── Transações pendentes ─────────────────────────────────────────────────
    let txQuery = admin
      .from("bank_transactions")
      .select("id, transaction_date, description, amount, transaction_type, pix_end_to_end_id, counterparty_document, counterparty_name")
      .eq("reconciled", false)
      .order("transaction_date", { ascending: false })
      .limit(body.limit ?? 200);
    if (body.transaction_id) txQuery = txQuery.eq("id", body.transaction_id);

    const { data: txRows, error: txErr } = await txQuery;
    if (txErr) throw txErr;
    const transactions = (txRows || []) as BankTx[];
    if (transactions.length === 0) {
      return jr({ transactions: [], applied: [], summary: { pendentes: 0, conciliadas: 0, sugeridas: 0, sem_candidato: 0 } });
    }

    const candidates = await buildCandidates(admin);

    // ── Pontuação ────────────────────────────────────────────────────────────
    const perTransaction: Array<{ transaction: BankTx; suggestions: Suggestion[] }> = transactions.map((tx) => ({
      transaction: tx,
      suggestions: suggestMatches(tx, candidates),
    }));

    // ── Camada de certeza: aplica sozinha ────────────────────────────────────
    const applied: Array<{ transaction_id: string; candidate: Candidate; message: string }> = [];
    if (action === "auto") {
      for (const item of perTransaction) {
        const auto = pickAutoApply(item.suggestions);
        if (!auto) continue;
        if (body.dry_run) {
          applied.push({ transaction_id: item.transaction.id, candidate: auto.candidate, message: "simulação" });
          continue;
        }
        const result = await applySuggestion(admin, item.transaction, auto);
        if (result.ok) {
          applied.push({ transaction_id: item.transaction.id, candidate: auto.candidate, message: result.message });
          item.suggestions = []; // já resolvida
        }
      }
    }

    const appliedIds = new Set(applied.map((a) => a.transaction_id));
    const restantes = perTransaction.filter((p) => !appliedIds.has(p.transaction.id));

    return jr({
      transactions: restantes.map((p) => ({
        transaction: p.transaction,
        suggestions: p.suggestions,
      })),
      applied,
      summary: {
        pendentes: transactions.length,
        conciliadas: applied.length,
        sugeridas: restantes.filter((p) => p.suggestions.length > 0).length,
        sem_candidato: restantes.filter((p) => p.suggestions.length === 0).length,
        candidatos_avaliados: candidates.length,
      },
    });
  } catch (e) {
    console.error("[banking-reconcile] erro:", e);
    return jr({ error: "unexpected_error", detail: String((e as Error)?.message ?? e) }, 500);
  }
});

/**
 * Tudo que uma transação do extrato poderia estar pagando.
 * A ordem importa pouco (o motor pontua), mas a abrangência importa muito: candidato
 * que não entra aqui simplesmente nunca é sugerido.
 */
async function buildCandidates(admin: ReturnType<typeof createClient>): Promise<Candidate[]> {
  const candidates: Candidate[] = [];

  // 1. Contas a receber em aberto.
  const { data: receivables } = await admin
    .from("receivables")
    .select("id, description, balance_amount, due_date, client_id, service_order_id, clients(name, cpf_cnpj), service_orders(service_order_number)")
    .in("status", ABERTOS)
    .gt("balance_amount", 0)
    .limit(500);

  for (const r of receivables || []) {
    const cliente = (r as any).clients;
    candidates.push({
      kind: "receivable",
      id: r.id as string,
      label: (r.description as string) || "Conta a receber",
      amount: Number(r.balance_amount),
      direction: "credit",
      dueDate: r.due_date as string,
      clientId: r.client_id as string | null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
      documentNumber: (r as any).service_orders?.service_order_number ?? null,
      serviceOrderId: r.service_order_id as string | null,
    });
  }

  // 2. Contas a pagar em aberto.
  const { data: payables } = await admin
    .from("payables")
    .select("id, description, balance_amount, due_date, supplier_id, suppliers(name)")
    .in("status", ABERTOS)
    .gt("balance_amount", 0)
    .limit(500);

  for (const p of payables || []) {
    candidates.push({
      kind: "payable",
      id: p.id as string,
      label: (p.description as string) || "Conta a pagar",
      amount: Number(p.balance_amount),
      direction: "debit",
      dueDate: p.due_date as string,
      clientName: (p as any).suppliers?.name ?? null,
    });
  }

  // 3. Cobranças avulsas (sem conta a receber por trás — as demais já entraram acima).
  const { data: collections } = await admin
    .from("collections")
    .select("id, description, amount, due_date, client_id, receivable_id, clients(name, cpf_cnpj)")
    .is("receivable_id", null)
    .not("status", "in", '("paid","cancelled")')
    .limit(200);

  for (const c of collections || []) {
    const cliente = (c as any).clients;
    candidates.push({
      kind: "collection",
      id: c.id as string,
      label: (c.description as string) || "Cobrança",
      amount: Number(c.amount),
      direction: "credit",
      dueDate: c.due_date as string,
      clientId: c.client_id as string | null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
    });
  }

  // 4. Sinal de orçamento — o candidato que faltava.
  //    Inclui os marcados como "aguardando sinal" e os que foram enviados ao cliente
  //    (podem ter sido aprovados por WhatsApp sem ninguém mexer no status).
  const { data: settings } = await admin
    .from("app_settings")
    .select("key, value")
    .eq("key", "quote_deposit_percentage")
    .maybeSingle();
  const globalPct = Number((settings as any)?.value ?? 30) || 30;

  const { data: quotes } = await admin
    .from("service_orders")
    .select(`id, service_order_number, quote_status, status, grand_total, created_at,
             labor_cost_total, parts_cost_total, operational_cost_total, travel_cost_total,
             subcontract_cost_total, is_travel_billable, discount_amount, tax_amount,
             custom_payment_installments, client_id, clients(name, cpf_cnpj)`)
    .in("quote_status", ["awaiting_deposit", "sent"])
    .not("status", "in", '("cancelled")')
    .limit(200);

  for (const q of quotes || []) {
    // Se o sinal já foi pago, o orçamento não está mais esperando dinheiro.
    const { count } = await admin
      .from("receivables")
      .select("id", { count: "exact", head: true })
      .eq("service_order_id", q.id as string)
      .eq("is_deposit", true)
      .eq("status", "paid");
    if ((count ?? 0) > 0) continue;

    const esperado = expectedDepositAmount(
      q as never,
      (q as any).custom_payment_installments,
      globalPct,
    );
    if (!esperado) continue;

    const cliente = (q as any).clients;
    candidates.push({
      kind: "quote_deposit",
      id: q.id as string,
      label: `Sinal do ${q.service_order_number}`,
      amount: esperado.amount,
      direction: "credit",
      dueDate: null,
      referenceDate: String(q.created_at).slice(0, 10),
      clientId: q.client_id as string | null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
      documentNumber: q.service_order_number as string,
      serviceOrderId: q.id as string,
      convertsQuote: true,
    });
  }

  // 5. Saldo de OS ativa ainda não lançado como conta a receber.
  const { data: orders } = await admin
    .from("service_orders")
    .select("id, service_order_number, grand_total, created_at, client_id, clients(name, cpf_cnpj)")
    .in("status", OS_ATIVAS)
    .gt("grand_total", 0)
    .limit(200);

  for (const o of orders || []) {
    const { data: recs } = await admin
      .from("receivables")
      .select("amount")
      .eq("service_order_id", o.id as string)
      .neq("status", "cancelled");
    const lancado = (recs || []).reduce((s, r) => s + Number((r as any).amount || 0), 0);
    const saldo = Number(o.grand_total) - lancado;
    if (saldo <= 0.01) continue; // já está todo lançado; os receivables acima cobrem

    const cliente = (o as any).clients;
    candidates.push({
      kind: "service_order_balance",
      id: o.id as string,
      label: `Saldo da ${o.service_order_number}`,
      amount: Number(saldo.toFixed(2)),
      direction: "credit",
      dueDate: null,
      referenceDate: String(o.created_at).slice(0, 10),
      clientId: o.client_id as string | null,
      clientName: cliente?.name ?? null,
      clientDocument: cliente?.cpf_cnpj ?? null,
      documentNumber: o.service_order_number as string,
      serviceOrderId: o.id as string,
    });
  }

  return candidates;
}

/**
 * Aplica uma sugestão da camada de certeza.
 * Reaproveita as rotinas atômicas que o painel já usa, para que baixa de saldo,
 * trilha de auditoria e os gatilhos de conversão de orçamento aconteçam igual.
 */
async function applySuggestion(
  admin: ReturnType<typeof createClient>,
  tx: BankTx,
  suggestion: Suggestion,
): Promise<{ ok: boolean; message: string }> {
  const { candidate } = suggestion;
  const hoje = tx.transaction_date;

  try {
    if (candidate.kind === "receivable" || candidate.kind === "payable") {
      const { data, error } = await admin.rpc("register_payment_and_update_balance", {
        p_receivable_id: candidate.kind === "receivable" ? candidate.id : null,
        p_payable_id: candidate.kind === "payable" ? candidate.id : null,
        p_amount: tx.amount,
        p_payment_date: hoje,
        p_payment_method: "bank_transfer",
        p_installments: 1,
        p_card_fee_percent: 0,
        p_net_amount: tx.amount,
        p_notes: `Conciliação automática — ${tx.description}`.slice(0, 500),
      });
      if (error) throw error;
      const paymentId = (data as any)?.payment_id ?? null;
      await marcarConciliada(admin, tx.id, paymentId, candidate.serviceOrderId ?? null);
      return { ok: true, message: `Baixa registrada em ${candidate.label}` };
    }

    if (candidate.kind === "quote_deposit") {
      // Cria o recebível de sinal já quitado e converte o orçamento — o mesmo caminho
      // do botão "Receber sinal", inclusive disparando o gatilho de conversão.
      const { data, error } = await admin.rpc("register_deposit_and_convert", {
        p_service_order_id: candidate.serviceOrderId,
        p_amount: tx.amount,
        p_payment_date: hoje,
        p_payment_method: "bank_transfer",
        p_card_fee_percent: 0,
        p_notes: `Conciliação automática — ${tx.description}`.slice(0, 500),
      });
      if (error) throw error;
      const paymentId = (data as any)?.payment_id ?? null;
      await marcarConciliada(admin, tx.id, paymentId, candidate.serviceOrderId ?? null);
      return { ok: true, message: `Sinal registrado e ${candidate.documentNumber} aprovado` };
    }

    // collection avulsa e saldo de OS exigem decisão de classificação — ficam como sugestão.
    return { ok: false, message: "tipo requer confirmação humana" };
  } catch (e) {
    console.error("[banking-reconcile] falha ao aplicar:", candidate.kind, candidate.id, e);
    return { ok: false, message: String((e as Error)?.message ?? e) };
  }
}

async function marcarConciliada(
  admin: ReturnType<typeof createClient>,
  txId: string,
  paymentId: string | null,
  serviceOrderId: string | null,
) {
  await admin
    .from("bank_transactions")
    .update({
      reconciled: true,
      reconciled_payment_id: paymentId,
      reconciled_service_order_id: serviceOrderId,
    })
    .eq("id", txId);
}
