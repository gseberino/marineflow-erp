// Edge Function: finance-review
//
// Gera as propostas de lançamento a partir do extrato e aplica as que o gestor aprova.
// É o módulo que ataca o problema central do financeiro: quase todo o dinheiro que passou
// pela conta nunca virou despesa ou receita registrada, porque lançar isso à mão é inviável.
//
// GOVERNANÇA (decisões do usuário em 29/07/2026):
//   · Limite de R$ 500 — abaixo, aprovação em lote; acima, item a item.
//   · Últimos 90 dias na fila; o histórico anterior fica para um mutirão à parte.
//   · Aprovar cria REGISTRO de despesa/receita. Nada aqui movimenta dinheiro.
//
// O limite vive aqui e na tabela, não no texto de um prompt: instrução em linguagem
// natural não é controle de acesso.
//
// POR QUE SÓ SAÍDAS, POR ENQUANTO
// Saída de dinheiro quase nunca está registrada (R$ 926 mil em saídas para 5 contas a
// pagar): a despesa só existe no extrato, e propô-la não corre risco de duplicar nada.
// Entrada é o oposto — quase sempre corresponde a um orçamento ou OS que JÁ existe no
// sistema, e é o módulo de conciliação que sabe ligar as duas pontas. Criar uma receita
// avulsa para cada entrada contaria o mesmo faturamento duas vezes assim que a OS fosse
// faturada, e ninguém perceberia. Entrada, portanto, entra na fila apenas quando é a
// perna de uma transferência entre contas próprias (que não é receita de ninguém).

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  montarProposta, sugerirRegras,
  type FornecedorConhecido, type HistoricoFornecedor, type RegraFinanceira, type TransacaoOrfa,
} from "../_shared/banking/proposals.ts";
import { findInternalTransfers } from "../_shared/banking/matching.ts";

type DbClient = SupabaseClient<any, "public", any>;

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

/** Acima disto, a proposta exige olhar individual — decisão do usuário. */
const LIMITE_LOTE = 500;
/** Janela da fila: o que é mais antigo vira mutirão separado, para não sepultar o dia. */
const JANELA_DIAS = 90;

interface Body {
  action?: "generate" | "approve" | "reject" | "suggest_rules";
  /** generate: inclui o histórico inteiro, não só a janela. */
  incluir_historico?: boolean;
  ids?: string[];
  note?: string;
  /** Correções do gestor antes de aprovar. */
  overrides?: Record<string, Correcao>;
}

interface Correcao {
  category?: string;
  description?: string;
  amount?: number;
  date?: string;
  /** A quem a despesa pertence quando não é a um fornecedor. */
  payeeId?: string | null;
  /** OS a que a compra pertence — é o que dá custo e margem reais por serviço. */
  serviceOrderId?: string | null;
  /** OC que este pagamento quita. */
  purchaseOrderId?: string | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin: DbClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const cronSecret = req.headers.get("x-cron-secret");
  const isCron = !!cronSecret && cronSecret === Deno.env.get("CRON_SECRET");
  let userId: string | null = null;

  if (!isCron) {
    const token = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    if (!token) return jr({ error: "unauthorized" }, 401);
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data?.user) return jr({ error: "unauthorized" }, 401);
    userId = data.user.id;
  }

  const body: Body = await req.json().catch(() => ({}));
  const action = body.action ?? "generate";

  try {
    if (action === "generate") return await gerar(admin, !!body.incluir_historico);
    if (action === "approve") return await aprovar(admin, body.ids ?? [], userId, body.overrides ?? {});
    if (action === "reject") return await recusar(admin, body.ids ?? [], userId, body.note ?? null);
    if (action === "suggest_rules") return await proporRegras(admin);
    return jr({ error: "acao_desconhecida" }, 400);
  } catch (e) {
    console.error("[finance-review] erro:", e);
    return jr({ error: "unexpected_error", detail: String((e as Error)?.message ?? e) }, 500);
  }
});

async function gerar(admin: DbClient, incluirHistorico: boolean) {
  const desde = new Date(Date.now() - JANELA_DIAS * 86_400_000).toISOString().slice(0, 10);

  let q = admin
    .from("bank_transactions")
    .select("id, transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document, source_type, bank_connection_id")
    .eq("reconciled", false)
    .order("transaction_date", { ascending: false })
    .limit(3000);
  if (!incluirHistorico) q = q.gte("transaction_date", desde);

  const { data: pendentes, error } = await q;
  if (error) throw error;
  const transacoes = (pendentes ?? []) as TransacaoOrfa[];
  if (transacoes.length === 0) {
    return jr({ ok: true, message: "Nenhuma transação pendente na janela.", criadas: 0 });
  }

  // Transferência entre contas próprias não é despesa nem receita: entra na fila como o
  // que é, para o gestor confirmar e as duas pernas saírem do resultado de uma vez.
  // Uma proposta por PAR, não por perna — duas linhas para o mesmo dinheiro fariam o
  // gestor decidir a mesma coisa duas vezes.
  const pares = findInternalTransfers(transacoes as never[]);
  const parPor = new Map<string, { detail: string; outra: string }>();
  const jaCoberta = new Set<string>();
  for (const p of pares) {
    parPor.set(p.saida.id, { detail: p.detail, outra: p.entrada.id });
    jaCoberta.add(p.entrada.id);
  }

  // Não propor de novo o que já está na fila ou já virou lançamento.
  const { data: jaNaFila } = await admin
    .from("finance_review_queue")
    .select("bank_transaction_id")
    .eq("status", "pending");
  const naFila = new Set((jaNaFila ?? []).map((r: any) => r.bank_transaction_id));

  const { data: jaLancadas } = await admin
    .from("payables").select("bank_transaction_id").not("bank_transaction_id", "is", null);
  const { data: jaLancadasRec } = await admin
    .from("receivables").select("bank_transaction_id").not("bank_transaction_id", "is", null);
  const lancadas = new Set([
    ...(jaLancadas ?? []).map((r: any) => r.bank_transaction_id),
    ...(jaLancadasRec ?? []).map((r: any) => r.bank_transaction_id),
  ]);

  const { data: fornecedoresRows } = await admin
    .from("suppliers").select("id, name, cnpj_cpf, trade_name").limit(2000);
  const fornecedores = (fornecedoresRows ?? []) as FornecedorConhecido[];

  const historico = await montarHistoricoPorFornecedor(admin);

  const { data: regrasRows } = await admin
    .from("finance_rules").select("*").eq("status", "active").limit(500);
  const regras = (regrasRows ?? []) as unknown as RegraFinanceira[];

  // Ordens de compra ainda sem pagamento: é com elas que uma saída pode casar.
  const { data: ocsAbertas } = await admin
    .from("purchase_orders")
    .select("id, po_number, total_amount, supplier_id, service_order_id, expected_date")
    .is("payable_id", null)
    .not("status", "in", '("cancelled")')
    .limit(500);
  const ocs = (ocsAbertas ?? []) as any[];

  // Favorecidos conhecidos, para reconhecer sócio/diarista pelo CPF do extrato.
  const { data: favorecidosRows } = await admin
    .from("payees").select("id, name, document, default_category").eq("active", true).limit(500);
  const favorecidos = (favorecidosRows ?? []) as any[];

  const linhas: Record<string, unknown>[] = [];
  const autoAplicar: Record<string, unknown>[] = [];
  for (const tx of transacoes) {
    if (naFila.has(tx.id) || lancadas.has(tx.id)) continue;
    if (jaCoberta.has(tx.id)) continue;   // é a entrada de um par já proposto pela saída

    const par = parPor.get(tx.id);
    if (par) {
      linhas.push({
        kind: "internal_transfer",
        bank_transaction_id: tx.id,
        related_transaction_id: par.outra,
        title: `Transferência entre contas: ${tx.description}`.slice(0, 160),
        reasoning: par.detail,
        confidence: 92,
        suggested_amount: tx.amount,
        suggested_date: tx.transaction_date,
        suggested_category: "Transferência entre contas",
        suggested_description: tx.description.slice(0, 200),
        dre_group: "nao_operacional",
      });
      continue;
    }

    // Entrada que não é transferência interna fica para a conciliação (ver cabeçalho).
    if (tx.transaction_type !== "debit") continue;

    const p = montarProposta(tx, fornecedores, historico, regras);

    // Favorecido pelo documento: CPF é identidade, e reconhecê-lo poupa o gestor de
    // escolher a mesma pessoa toda vez que ela recebe.
    const docTx = (tx.counterparty_document || "").replace(/\D/g, "");
    const favorecido = docTx.length >= 11
      ? favorecidos.find((f) => String(f.document || "").replace(/\D/g, "") === docTx)
      : undefined;

    // OC do MESMO fornecedor com valor idêntico — o par é forte o bastante para sugerir,
    // fraco o bastante para exigir confirmação: duas OCs de igual valor existem.
    const oc = p.suggestedSupplierId
      ? ocs.find((o) => o.supplier_id === p.suggestedSupplierId
          && Math.abs(Number(o.total_amount) - tx.amount) < 0.01)
      : undefined;

    const linha = {
      kind: p.kind,
      bank_transaction_id: p.bankTransactionId,
      title: p.title,
      confidence: p.confidence,
      suggested_amount: p.suggestedAmount,
      suggested_date: p.suggestedDate,
      suggested_category: p.suggestedCategory,
      suggested_description: p.suggestedDescription,
      suggested_supplier_id: p.suggestedSupplierId,
      suggested_payee_id: favorecido?.id ?? null,
      // A OC costuma saber para qual serviço a compra foi — herdar isso evita perguntar
      // duas vezes a mesma coisa.
      suggested_purchase_order_id: oc?.id ?? null,
      suggested_service_order_id: oc?.service_order_id ?? null,
      dre_group: p.dreGroup,
      applied_rule_id: p.appliedRuleId,
      reasoning: [
        p.reasoning,
        favorecido && `Favorecido reconhecido pelo CPF/CNPJ: ${favorecido.name}`,
        oc && `Mesmo valor da ordem de compra ${oc.po_number}, do mesmo fornecedor`,
      ].filter(Boolean).join(" · "),
    };
    linhas.push(linha);
    // Regra com autonomia foi conferida pelo gestor no momento em que ele a criou; segurar
    // a proposta para ele confirmar de novo seria pedir a mesma decisão duas vezes.
    if (p.autoAplicavel) autoAplicar.push(linha);
  }

  let criadas = 0;
  const idsPorTransacao = new Map<string, string>();
  for (let i = 0; i < linhas.length; i += 200) {
    const lote = linhas.slice(i, i + 200);
    const { data: inseridas, error: insErr } = await admin
      .from("finance_review_queue").insert(lote).select("id, bank_transaction_id");
    if (insErr) throw insErr;
    for (const r of (inseridas ?? []) as any[]) idsPorTransacao.set(r.bank_transaction_id, r.id);
    criadas += lote.length;
  }

  // Aplica de imediato o que as regras autônomas resolveram. Cada lançamento fica ligado à
  // regra que o criou, então desligar a regra e desfazer o que ela fez são a mesma consulta.
  let lancadasSozinhas = 0;
  const idsAuto = autoAplicar
    .map((l) => idsPorTransacao.get(String(l.bank_transaction_id)))
    .filter((v): v is string => !!v);
  if (idsAuto.length > 0) {
    const resposta = await aprovar(admin, idsAuto, null, {});
    const corpo = await resposta.json();
    lancadasSozinhas = Number(corpo?.aprovadas ?? 0);
  }

  const partes = [
    criadas > 0 ? `${criadas - lancadasSozinhas} proposta(s) para revisar` : "Nada novo para propor",
    lancadasSozinhas > 0 ? `${lancadasSozinhas} lançada(s) pelas suas regras` : "",
    pares.length ? `${pares.length} transferência(s) entre contas` : "",
  ].filter(Boolean);

  return jr({
    ok: true,
    criadas,
    lancadas_por_regra: lancadasSozinhas,
    transferencias_internas: pares.length,
    elegiveis_lote: linhas.filter((l) => Number(l.suggested_amount) < LIMITE_LOTE).length,
    message: partes.join(" · "),
  });
}

/**
 * Procura repetições nas decisões já tomadas e as grava como regras PROPOSTAS.
 *
 * Nasce inerte: `status: 'proposed'` não classifica nada até alguém aceitar. O sistema
 * observou um padrão, não recebeu uma ordem — e um padrão pode ser três erros iguais.
 */
async function proporRegras(admin: DbClient) {
  const { data: lancamentos } = await admin
    .from("payables")
    .select("supplier_id, supplier_name, expense_category")
    .not("expense_category", "is", null)
    .order("created_at", { ascending: false })
    .limit(3000);

  const { data: cats } = await admin
    .from("financial_categories").select("name, dre_group").eq("active", true);
  const grupoDa = new Map<string, string>();
  for (const c of (cats ?? []) as any[]) if (c.dre_group) grupoDa.set(String(c.name), String(c.dre_group));

  const { data: fornecedores } = await admin.from("suppliers").select("id, name").limit(2000);
  const nomeDo = new Map<string, string>();
  for (const f of (fornecedores ?? []) as any[]) nomeDo.set(f.id, f.name);

  const decisoes = ((lancamentos ?? []) as any[]).map((p) => ({
    supplierId: p.supplier_id ?? null,
    supplierName: p.supplier_id ? nomeDo.get(p.supplier_id) : p.supplier_name,
    counterpartyName: p.supplier_name ?? null,
    categoria: String(p.expense_category),
    dreGroup: grupoDa.get(String(p.expense_category)) ?? "despesa_operacional",
  }));

  const { data: existentes } = await admin.from("finance_rules").select("*").limit(1000);
  const padroes = sugerirRegras(decisoes, (existentes ?? []) as unknown as RegraFinanceira[]);

  if (padroes.length === 0) {
    return jr({ ok: true, propostas: 0, message: "Nenhum padrão novo o bastante para virar regra" });
  }

  const { error } = await admin.from("finance_rules").insert(
    padroes.map((p) => ({
      match_type: p.matchType,
      match_value: p.matchValue,
      direction: p.direction,
      set_category: p.setCategory,
      set_dre_group: p.setDreGroup,
      set_supplier_id: p.setSupplierId,
      autonomy: "suggest",
      origin: "ai",
      status: "proposed",
      reasoning: p.reasoning,
    })),
  );
  if (error) throw error;

  return jr({
    ok: true,
    propostas: padroes.length,
    message: `${padroes.length} regra(s) sugerida(s) a partir do que você já decidiu`,
  });
}

/**
 * Lê as despesas já lançadas e monta, por fornecedor, a categoria que ele mais recebeu.
 *
 * É a memória que faz a ferramenta melhorar sozinha: cada aprovação do gestor vira
 * evidência para a próxima proposta do mesmo fornecedor. Só conta o que tem categoria de
 * verdade — "Outras despesas" é ausência de classificação, e aprender a não classificar
 * seria transformar a lacuna em regra.
 */
async function montarHistoricoPorFornecedor(admin: DbClient): Promise<Map<string, HistoricoFornecedor>> {
  const { data } = await admin
    .from("payables")
    .select("supplier_id, expense_category")
    .not("supplier_id", "is", null)
    .not("expense_category", "is", null)
    .limit(5000);

  const contagem = new Map<string, Map<string, number>>();
  for (const row of (data ?? []) as any[]) {
    const cat = String(row.expense_category || "").trim();
    if (!cat || cat === "Outras despesas") continue;
    const porCat = contagem.get(row.supplier_id) ?? new Map<string, number>();
    porCat.set(cat, (porCat.get(cat) ?? 0) + 1);
    contagem.set(row.supplier_id, porCat);
  }

  const grupoDaCategoria = new Map<string, string>();
  const { data: cats } = await admin
    .from("financial_categories").select("name, dre_group").eq("active", true);
  for (const c of (cats ?? []) as any[]) {
    if (c.dre_group) grupoDaCategoria.set(String(c.name), String(c.dre_group));
  }

  const historico = new Map<string, HistoricoFornecedor>();
  for (const [supplierId, porCat] of contagem) {
    let melhor = ""; let vezes = 0;
    for (const [cat, n] of porCat) if (n > vezes) { melhor = cat; vezes = n; }
    if (melhor) {
      historico.set(supplierId, {
        categoria: melhor,
        dreGroup: grupoDaCategoria.get(melhor) ?? "despesa_operacional",
        vezes,
      });
    }
  }
  return historico;
}

/**
 * Aprova propostas, criando os lançamentos.
 *
 * Transferência entre contas NÃO gera lançamento: ela apenas marca as duas pernas como
 * resolvidas. Criar despesa e receita para o mesmo dinheiro é exatamente o erro que a
 * detecção existe para evitar.
 */
async function aprovar(
  admin: DbClient,
  ids: string[],
  userId: string | null,
  overrides: Record<string, Correcao>,
) {
  if (ids.length === 0) return jr({ error: "nenhuma proposta informada" }, 400);

  const { data: propostas, error } = await admin
    .from("finance_review_queue").select("*").in("id", ids).eq("status", "pending");
  if (error) throw error;

  const feitos: string[] = [];
  const falhas: string[] = [];

  for (const p of (propostas ?? []) as any[]) {
    try {
      const ov = overrides[p.id] ?? {};
      const valor = Number(ov.amount ?? p.suggested_amount);
      const data = String(ov.date ?? p.suggested_date);
      const descricao = String(ov.description ?? p.suggested_description ?? p.title);
      const categoria = String(ov.category ?? p.suggested_category ?? "Outras despesas");

      if (p.kind === "internal_transfer") {
        // Só marca as duas pernas: nenhum lançamento é criado.
        await admin.from("bank_transactions")
          .update({ reconciled: true, dismissed_reason: "Transferência entre contas próprias" })
          .in("id", [p.bank_transaction_id, p.related_transaction_id].filter(Boolean));
      } else if (p.kind === "create_payable") {
        const { data: criado, error: e1 } = await admin.from("payables").insert({
          description: descricao,
          issue_date: data,
          due_date: data,
          amount: valor,
          paid_amount: valor,
          balance_amount: 0,
          status: "paid",           // saiu do banco: já está pago por definição
          expense_category: categoria,
          supplier_id: p.suggested_supplier_id,
          // Sem fornecedor cadastrado, o nome do extrato é a única identificação que
          // existe — melhor guardá-lo do que deixar a despesa anônima.
          supplier_name: p.suggested_supplier_id ? null : descricao,
          // Favorecido pessoa e OS a que a compra pertence: é o que transforma "saiu
          // dinheiro" em "este serviço custou isto" e "este sócio retirou aquilo".
          payee_id: ov.payeeId ?? p.suggested_payee_id ?? null,
          linked_service_order_id: ov.serviceOrderId ?? p.suggested_service_order_id ?? null,
          origin: "bank_reconciliation",
          bank_transaction_id: p.bank_transaction_id,
        }).select("id").single();
        if (e1) throw e1;
        const payableId = (criado as any).id as string;
        await admin.from("finance_review_queue").update({ created_payable_id: payableId }).eq("id", p.id);
        await admin.from("bank_transactions").update({ reconciled: true }).eq("id", p.bank_transaction_id);

        // Quitar a ordem de compra fecha o ciclo do suprimento: sem isto, a OC fica
        // "enviada" para sempre e ninguém sabe o que já foi pago.
        const ocId = ov.purchaseOrderId ?? p.suggested_purchase_order_id ?? null;
        if (ocId) {
          await admin.from("purchase_orders")
            .update({ payable_id: payableId, status: "received" })
            .eq("id", ocId);
        }
      } else if (p.kind === "create_receivable") {
        // Receita exige cliente (receivables.client_id é NOT NULL) e, sem ele, o
        // lançamento não teria a quem pertencer. Falhar aqui com motivo legível é melhor
        // que devolver um erro cru de banco para o gestor.
        if (!p.suggested_client_id) {
          throw new Error("Escolha o cliente antes de aprovar esta receita");
        }
        const { data: criado, error: e2 } = await admin.from("receivables").insert({
          description: descricao,
          issue_date: data,
          due_date: data,
          amount: valor,
          paid_amount: valor,
          balance_amount: 0,
          status: "paid",           // entrou no banco: já está recebido
          category: categoria,
          client_id: p.suggested_client_id,
          bank_transaction_id: p.bank_transaction_id,
        }).select("id").single();
        if (e2) throw e2;
        await admin.from("finance_review_queue").update({ created_receivable_id: (criado as any).id }).eq("id", p.id);
        await admin.from("bank_transactions").update({ reconciled: true }).eq("id", p.bank_transaction_id);
      }

      await admin.from("finance_review_queue").update({
        status: "approved", decided_by: userId, decided_at: new Date().toISOString(),
      }).eq("id", p.id);

      // Quanto cada regra trabalhou é o que separa regra útil de regra esquecida — e é o
      // número que permite auditar uma regra pelo resultado, não pela intenção.
      if (p.applied_rule_id) {
        await admin.rpc("increment_finance_rule_usage", { rule_id: p.applied_rule_id })
          .then(undefined, () => { /* contador é telemetria: nunca derruba a aprovação */ });
      }
      feitos.push(p.id);
    } catch (e) {
      console.error("[finance-review] falha ao aprovar", p.id, e);
      falhas.push(`${p.title}: ${String((e as Error)?.message ?? e).slice(0, 120)}`);
    }
  }

  return jr({
    ok: falhas.length === 0,
    aprovadas: feitos.length,
    falhas,
    message: `${feitos.length} lançamento(s) criado(s)` + (falhas.length ? ` · ${falhas.length} falharam` : ""),
  });
}

async function recusar(admin: DbClient, ids: string[], userId: string | null, note: string | null) {
  if (ids.length === 0) return jr({ error: "nenhuma proposta informada" }, 400);
  const { error } = await admin.from("finance_review_queue").update({
    status: "rejected", decided_by: userId, decided_at: new Date().toISOString(), decision_note: note,
  }).in("id", ids).eq("status", "pending");
  if (error) throw error;
  return jr({ ok: true, recusadas: ids.length, message: `${ids.length} proposta(s) recusada(s)` });
}
