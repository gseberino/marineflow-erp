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
import {
  suggestMatches, pickAutoApply, suggestCombinations, statementSignature,
} from "../_shared/banking/matching.ts";
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
  action?: "suggest" | "auto" | "apply" | "apply_group";
  transaction_id?: string;
  /** Só simula: devolve o que faria, sem gravar. */
  dry_run?: boolean;
  limit?: number;
  /** Para `apply`: o candidato escolhido na tela, do jeito que esta função o devolveu. */
  candidate?: Candidate;
  /** Para `apply_group`: as contas que juntas somam o depósito. */
  candidates?: Candidate[];
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
    // ── Aplicar uma escolha da tela ──────────────────────────────────────────
    // Passa por aqui (e não direto do frontend) para que exista um único caminho de
    // escrita no financeiro, e para que toda confirmação vire aprendizado.
    if (action === "apply") {
      if (!body.transaction_id || !body.candidate) {
        return jr({ error: "transaction_id e candidate são obrigatórios" }, 400);
      }
      const { data: txRow, error: txOneErr } = await admin
        .from("bank_transactions")
        .select("id, transaction_date, description, amount, transaction_type, counterparty_name, reconciled")
        .eq("id", body.transaction_id)
        .single();
      if (txOneErr) throw txOneErr;
      if (!txRow) return jr({ error: "transação não encontrada" }, 404);
      if ((txRow as any).reconciled) return jr({ error: "esta transação já foi conciliada" }, 409);

      const alvo = body.candidate;
      const resultado = await applySuggestion(admin, txRow as BankTx, {
        candidate: alvo,
        score: 0, tier: "probable", reasons: [], difference: 0, autoApply: false,
      });
      if (!resultado.ok) return jr({ error: resultado.message }, 400);
      return jr({ ok: true, message: resultado.message });
    }

    // ── Aplicar um pagamento agrupado ────────────────────────────────────────
    // Cada conta recebe o próprio valor (não o do depósito), senão a primeira baixa
    // consumiria o total e as demais ficariam com valor errado.
    if (action === "apply_group") {
      if (!body.transaction_id || !body.candidates?.length) {
        return jr({ error: "transaction_id e candidates são obrigatórios" }, 400);
      }
      const { data: txRow, error: txOneErr } = await admin
        .from("bank_transactions")
        .select("id, transaction_date, description, amount, transaction_type, counterparty_name, reconciled")
        .eq("id", body.transaction_id)
        .single();
      if (txOneErr) throw txOneErr;
      if ((txRow as any)?.reconciled) return jr({ error: "esta transação já foi conciliada" }, 409);

      const tx = txRow as BankTx;
      const feitos: string[] = [];
      const falhas: string[] = [];
      for (const alvo of body.candidates) {
        const parcela = { ...tx, amount: Number(alvo.amount) };
        const r = await applySuggestion(admin, parcela, {
          candidate: alvo, score: 0, tier: "probable", reasons: [], difference: 0, autoApply: false,
        });
        if (r.ok) feitos.push(alvo.label);
        else falhas.push(`${alvo.label}: ${r.message}`);
      }

      // A transação é uma só e tem um único campo de pagamento, então ela guarda o
      // vínculo da última baixa; o rastro completo do grupo fica nas contas quitadas.
      if (feitos.length > 0) {
        await admin.from("bank_transactions").update({ reconciled: true }).eq("id", tx.id);
      }
      return jr({
        ok: falhas.length === 0,
        message: `${feitos.length} conta(s) baixada(s)${falhas.length ? ` · ${falhas.length} falharam` : ""}`,
        feitos,
        falhas,
      });
    }

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

    // ── Memória: o que histórico parecido já ensinou sobre quem paga ─────────
    const assinaturas = new Map<string, string>();
    for (const tx of transactions) {
      const sig = statementSignature(tx.description, tx.counterparty_name);
      if (sig) assinaturas.set(tx.id, sig);
    }
    const memoriaPorTx = new Map<string, Map<string, number>>();
    if (assinaturas.size > 0) {
      const { data: memoria } = await admin
        .from("reconciliation_memory")
        .select("statement_key, client_id, hits")
        .in("statement_key", Array.from(new Set(assinaturas.values())));
      const porChave = new Map<string, Map<string, number>>();
      for (const m of (memoria || []) as any[]) {
        const mapa = porChave.get(m.statement_key) ?? new Map<string, number>();
        mapa.set(m.client_id, Number(m.hits) || 1);
        porChave.set(m.statement_key, mapa);
      }
      for (const [txId, sig] of assinaturas) {
        const mapa = porChave.get(sig);
        if (mapa) memoriaPorTx.set(txId, mapa);
      }
    }

    // ── Pontuação ────────────────────────────────────────────────────────────
    const perTransaction = transactions.map((tx) => {
      const suggestions = suggestMatches(tx, candidates, {}, 5, memoriaPorTx.get(tx.id));
      // Pagamento agrupado só interessa quando nenhuma conta sozinha explica o valor.
      const grupos = suggestions.some((s) => Math.abs(s.difference) < 0.01)
        ? []
        : suggestCombinations(tx, candidates);
      return { transaction: tx, suggestions, groups: grupos };
    });

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
        groups: p.groups,
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
             custom_payment_installments, payment_condition_preset_id, payment_conditions,
             client_id, clients(name, cpf_cnpj),
             payment_condition_presets(label, installments)`)
    .in("quote_status", ["awaiting_deposit", "sent"])
    .not("status", "in", '("cancelled")')
    .limit(200);

  // Condições pré-cadastradas: alguns orçamentos guardam só o rótulo em
  // `payment_conditions`, sem o id do preset — o mesmo fallback que a tela de orçamento faz.
  const { data: presets } = await admin
    .from("payment_condition_presets")
    .select("id, label, installments");
  const presetPorLabel = new Map<string, any>(
    (presets || []).map((p: any) => [String(p.label), p]),
  );

  for (const q of quotes || []) {
    // Se o sinal já foi pago, o orçamento não está mais esperando dinheiro.
    const { count } = await admin
      .from("receivables")
      .select("id", { count: "exact", head: true })
      .eq("service_order_id", q.id as string)
      .eq("is_deposit", true)
      .eq("status", "paid");
    if ((count ?? 0) > 0) continue;

    // Precedência idêntica à do orçamento e do botão "Receber sinal": a condição
    // pré-cadastrada manda; sem ela, a condição avulsa do orçamento; sem nenhuma, o
    // percentual padrão — que é estimativa, não combinado, e a UI diz isso.
    const preset = (q as any).payment_condition_presets
      ?? presetPorLabel.get(String((q as any).payment_conditions ?? ""));
    const installments = Array.isArray(preset?.installments)
      ? preset.installments
      : (Array.isArray((q as any).custom_payment_installments) ? (q as any).custom_payment_installments : null);

    const esperado = expectedDepositAmount(q as never, installments, globalPct);
    if (!esperado) continue;

    const cliente = (q as any).clients;
    const rotuloCondicao = esperado.source === "condicao"
      ? (preset?.label ?? "condição do orçamento")
      : esperado.source === "padrao"
        ? "100% materiais + 50% mão de obra"
        : null;
    candidates.push({
      kind: "quote_deposit",
      id: q.id as string,
      label: `Sinal do ${q.service_order_number}`,
      amount: esperado.amount,
      amountSource: esperado.source,
      conditionLabel: rotuloCondicao,
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
      await aprender(admin, tx, candidate);
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
      await aprender(admin, tx, candidate);
      return { ok: true, message: `Sinal registrado e ${candidate.documentNumber} aprovado` };
    }

    // Saldo de OS ainda não lançado: cria a conta a receber já quitada, para que o
    // recebimento apareça no financeiro ligado à ordem certa. Só acontece por escolha
    // explícita na tela — nunca na camada automática, que não trata este tipo.
    if (candidate.kind === "service_order_balance" && candidate.serviceOrderId) {
      const { data: rec, error: recErr } = await admin
        .from("receivables")
        .insert({
          service_order_id: candidate.serviceOrderId,
          client_id: candidate.clientId,
          description: `Recebimento conciliado — ${candidate.documentNumber ?? "OS"}`,
          issue_date: hoje,
          due_date: hoje,
          amount: tx.amount,
          paid_amount: tx.amount,
          balance_amount: 0,
          status: "paid",
        })
        .select("id")
        .single();
      if (recErr) throw recErr;

      const { data: pay, error: payErr } = await admin
        .from("payments")
        .insert({
          receivable_id: (rec as any).id,
          payment_date: hoje,
          amount: tx.amount,
          payment_method: "bank_transfer",
          notes: `Conciliação — ${tx.description}`.slice(0, 500),
        })
        .select("id")
        .single();
      if (payErr) throw payErr;

      await marcarConciliada(admin, tx.id, (pay as any).id, candidate.serviceOrderId);
      await aprender(admin, tx, candidate);
      return { ok: true, message: `Recebimento lançado em ${candidate.label}` };
    }

    // Cobrança avulsa: não tem conta a receber por trás, então cria a conta já quitada e
    // deixa o gatilho de sincronização fechar a cobrança sozinho.
    if (candidate.kind === "collection") {
      const { data: cob, error: cobErr } = await admin
        .from("collections")
        .select("id, client_id, description, service_order_id, amount")
        .eq("id", candidate.id)
        .single();
      if (cobErr) throw cobErr;

      const { data: rec, error: recErr } = await admin
        .from("receivables")
        .insert({
          client_id: (cob as any).client_id,
          service_order_id: (cob as any).service_order_id ?? null,
          description: (cob as any).description || candidate.label,
          issue_date: hoje,
          due_date: hoje,
          amount: tx.amount,
          paid_amount: tx.amount,
          balance_amount: 0,
          status: "paid",
        })
        .select("id")
        .single();
      if (recErr) throw recErr;

      const { data: pay, error: payErr } = await admin
        .from("payments")
        .insert({
          receivable_id: (rec as any).id,
          payment_date: hoje,
          amount: tx.amount,
          payment_method: "bank_transfer",
          notes: `Conciliação — ${tx.description}`.slice(0, 500),
        })
        .select("id")
        .single();
      if (payErr) throw payErr;

      // Liga a cobrança à conta criada e a marca como paga (o gatilho cuida do resto
      // quando o receivable já nasce quitado, mas aqui o vínculo ainda não existia).
      await admin
        .from("collections")
        .update({
          receivable_id: (rec as any).id,
          status: "paid",
          paid_at: new Date().toISOString(),
          paid_amount: tx.amount,
          paid_method: "bank_transfer",
          payment_confirmed_by: "conciliacao",
        })
        .eq("id", candidate.id);

      await marcarConciliada(admin, tx.id, (pay as any).id, (cob as any).service_order_id ?? null);
      await aprender(admin, tx, candidate);
      return { ok: true, message: `Cobrança quitada: ${candidate.label}` };
    }

    return { ok: false, message: "Este tipo precisa ser conciliado pelas opções abaixo." };
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

/**
 * Guarda o que esta conciliação ensinou: este histórico bancário pertence a este cliente.
 * Falha aqui não pode derrubar a conciliação — o dinheiro já foi registrado, e não
 * aprender é bem menos grave do que quebrar a operação.
 */
async function aprender(
  admin: ReturnType<typeof createClient>,
  tx: BankTx,
  candidate: Candidate,
) {
  try {
    if (!candidate.clientId) return;
    const chave = statementSignature(tx.description, tx.counterparty_name);
    if (!chave) return;
    await admin.rpc("remember_reconciliation", {
      p_statement_key: chave,
      p_client_id: candidate.clientId,
      p_candidate_kind: candidate.kind,
    });
  } catch (e) {
    console.warn("[banking-reconcile] não consegui registrar o aprendizado:", e);
  }
}
