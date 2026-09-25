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

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  suggestMatches, pickAutoApply, suggestCombinations, statementSignature,
  looksLikeInternalTransfer, findInternalTransfers,
} from "../_shared/banking/matching.ts";
import { carregarCandidatos } from "../_shared/banking/candidatos.ts";
import type { BankTx, Candidate, Suggestion } from "../_shared/banking/types.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

/**
 * Cliente do banco.
 *
 * Alias explícito em vez de `ReturnType<typeof createClient>`, que resolve para um
 * genérico incompatível com o que `createClient(url, key)` realmente devolve. O ruído
 * desses erros falsos escondia erro de verdade no `deno check` — foi assim que uma
 * chamada com argumentos deslocados passou despercebida e derrubou a conciliação em
 * produção. Rodar `deno check` nesta função antes de deployar agora vale a pena.
 */
type DbClient = SupabaseClient<any, "public", any>;

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}


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

servirComCors(async (req) => {
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

  /**
   * Cliente que carrega o JWT de quem clicou.
   *
   * As rotinas de baixa checam o cargo com `is_admin_or_financial(auth.uid())`, e
   * `auth.uid()` é NULO em chamada com service-role — usar o cliente admin aqui derruba
   * toda baixa com "Acesso negado". Além disso, registrar dinheiro deve ficar atribuído
   * ao usuário real, não a um processo anônimo.
   */
  let userClient: DbClient | null = null;
  if (!isCron) {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) return jr({ error: "unauthorized" }, 401);
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData?.user) return jr({ error: "unauthorized" }, 401);
    userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
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
      const resultado = await applySuggestion(admin, userClient, txRow as BankTx, {
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
        const r = await applySuggestion(admin, userClient, parcela, {
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
      .select("id, transaction_date, description, amount, transaction_type, pix_end_to_end_id, counterparty_document, counterparty_name, bank_connection_id")
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

    // Nome da empresa para reconhecer dinheiro circulando entre contas próprias.
    const { data: cfgEmpresa } = await admin
      .from("app_settings")
      .select("value")
      .eq("key", "company_name")
      .maybeSingle();
    const companyName = (cfgEmpresa as any)?.value ?? null;

    // ── Transferências entre contas da própria empresa ───────────────────────
    // Com mais de uma conta conectada, o mesmo dinheiro aparece duas vezes: sai de uma e
    // entra na outra. Sem parear, vira despesa e receita fantasmas — infla faturamento e
    // custo ao mesmo tempo. Marcamos as duas pernas para saírem da caça a candidatos.
    //
    // O pareamento roda sobre TODAS as pendentes, não sobre o lote exibido: as duas pernas
    // podem cair em páginas diferentes, e aí metade dos pares desaparece — foi o que
    // aconteceu quando isto usava só o lote (15 pares vistos de 29 existentes).
    const { data: universoParaPares } = await admin
      .from("bank_transactions")
      .select("id, transaction_date, description, amount, transaction_type, bank_connection_id")
      .eq("reconciled", false)
      .not("bank_connection_id", "is", null)
      .limit(5000);
    const paresInternos = findInternalTransfers((universoParaPares ?? transactions) as never[]);
    const pernaDeTransferencia = new Map<string, string>();
    for (const par of paresInternos) {
      pernaDeTransferencia.set(par.saida.id, par.detail);
      pernaDeTransferencia.set(par.entrada.id, par.detail);
    }

    // ── Pontuação ────────────────────────────────────────────────────────────
    const perTransaction = transactions.map((tx) => {
      // Duas formas de reconhecer o mesmo fenômeno: pelo nome da empresa no histórico, ou
      // pelo par saída↔entrada entre contas conectadas. A segunda é mais forte, porque
      // enxerga as duas pernas do movimento em vez de depender do texto.
      const parInterno = pernaDeTransferencia.get(tx.id) ?? null;
      const internalTransfer = !!parInterno ||
        looksLikeInternalTransfer(tx.description, tx.counterparty_name, companyName);

      // Transferência entre contas próprias não tem candidato a procurar: não é receita
      // nem despesa, é o mesmo dinheiro mudando de lugar.
      if (internalTransfer) {
        return {
          transaction: tx,
          suggestions: [],
          groups: [],
          internalTransfer: true,
          internalTransferDetail: parInterno,
        };
      }
      const suggestions = suggestMatches(tx, candidates, {}, 5, memoriaPorTx.get(tx.id));
      // Pagamento agrupado só interessa quando nenhuma conta sozinha explica o valor.
      const grupos = suggestions.some((s) => Math.abs(s.difference) < 0.01)
        ? []
        : suggestCombinations(tx, candidates);
      return { transaction: tx, suggestions, groups: grupos, internalTransfer: false, internalTransferDetail: null };
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
        const result = await applySuggestion(admin, userClient, item.transaction, auto);
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
        internalTransfer: p.internalTransfer,
        internalTransferDetail: p.internalTransferDetail,
      })),
      applied,
      summary: {
        pendentes: transactions.length,
        conciliadas: applied.length,
        sugeridas: restantes.filter((p) => p.suggestions.length > 0).length,
        sem_candidato: restantes.filter((p) => p.suggestions.length === 0).length,
        candidatos_avaliados: candidates.length,
        transferencias_internas: paresInternos.length,
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
async function buildCandidates(admin: DbClient): Promise<Candidate[]> {
  // Recebíveis, contas a pagar, cobranças, sinais de orçamento, pagamentos já lançados e
  // saldo de OS vêm do módulo compartilhado — o mesmo que a fila do Extrato usa para não
  // criar lançamento em dobro.
  return await carregarCandidatos(admin);
}

/**
 * Aplica uma sugestão da camada de certeza.
 * Reaproveita as rotinas atômicas que o painel já usa, para que baixa de saldo,
 * trilha de auditoria e os gatilhos de conversão de orçamento aconteçam igual.
 */
async function applySuggestion(
  admin: DbClient,
  /** Cliente com o JWT de quem clicou — as rotinas de baixa exigem auth.uid(). */
  userClient: DbClient | null,
  tx: BankTx,
  suggestion: Suggestion,
): Promise<{ ok: boolean; message: string }> {
  const { candidate } = suggestion;
  const hoje = tx.transaction_date;

  try {
    // Pagamento já existente: apenas amarra a transação a ele. Criar lançamento aqui
    // dobraria a receita, porque o dinheiro já está registrado no financeiro.
    if (candidate.kind === "existing_payment") {
      await marcarConciliada(admin, tx.id, candidate.id, candidate.serviceOrderId ?? null);
      await aprender(admin, tx, candidate);
      return { ok: true, message: `Vinculado ao pagamento já registrado (${candidate.label})` };
    }

    // As rotinas abaixo checam o cargo por auth.uid(); sem o cliente do usuário elas
    // recusam com "Acesso negado". A varredura automática por cron não registra dinheiro.
    if (!userClient) {
      return { ok: false, message: "Registrar pagamento exige um usuário autenticado." };
    }

    if (candidate.kind === "receivable" || candidate.kind === "payable") {
      const { data, error } = await userClient.rpc("register_payment_and_update_balance", {
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
      const { data, error } = await userClient.rpc("register_deposit_and_convert", {
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
  admin: DbClient,
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
  admin: DbClient,
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
