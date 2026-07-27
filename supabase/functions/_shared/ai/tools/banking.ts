// Ferramentas de conciliação bancária do agente.
//
// A conciliação é a terceira camada do motor: quando valor, data e documento não bastam,
// o agente tem o que nenhum motor de regra tem — as conversas, o histórico do cliente e
// os orçamentos em negociação. Ele consegue concluir que "o Pix do Marcelo é o sinal do
// orçamento que ele aprovou por mensagem na terça".
//
// Registrar dinheiro é irreversível na prática (mexe em saldo, aprova orçamento, dispara
// gatilho de conversão), então `conciliar_transacao` é risk alto: o loop do agente grava
// uma ação pendente e só executa depois da confirmação humana.

import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { suggestMatches } from "../../banking/matching.ts";
import type { BankTx } from "../../banking/types.ts";

/** Chama a banking-reconcile, que é quem sabe montar os candidatos a partir do banco. */
async function callReconcile(ctx: { jwt: string }, body: Record<string, unknown>) {
  const url = `${Deno.env.get("SUPABASE_URL")}/functions/v1/banking-reconcile`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${ctx.jwt}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`banking-reconcile respondeu ${res.status}`);
  return await res.json();
}

export const bankingTools: ToolDef[] = [
  {
    name: "listar_transacoes_pendentes",
    description:
      "Lista as transações do extrato bancário que ainda não foram conciliadas. Use para responder 'o que falta conciliar', 'quais entradas não identificamos' ou antes de sugerir conciliações.",
    input_schema: {
      type: "object",
      properties: {
        tipo: { type: "string", enum: ["credit", "debit"], description: "credit = entradas, debit = saídas" },
        limite: { type: "number", description: "Máximo de transações (padrão 30)" },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;

      let q = ctx.sb
        .from("bank_transactions")
        .select("id, transaction_date, description, amount, transaction_type, counterparty_name, counterparty_document, pix_end_to_end_id")
        .eq("reconciled", false)
        .order("transaction_date", { ascending: false })
        .limit(Math.min(Number(args.limite) || 30, 100));
      if (args.tipo) q = q.eq("transaction_type", args.tipo);

      const { data, error } = await q;
      if (error) throw error;
      return {
        total: (data || []).length,
        transacoes: data,
        dica: "Use sugerir_conciliacao com o id de uma transação para ver as correspondências pontuadas.",
      };
    },
  },

  {
    name: "sugerir_conciliacao",
    description:
      "Analisa uma transação do extrato (ou todas as pendentes) e devolve as correspondências possíveis com pontuação e justificativa — contas a receber/pagar, sinal de orçamento aguardando pagamento, saldo de OS e cobranças. NÃO registra nada.",
    input_schema: {
      type: "object",
      properties: {
        transaction_id: { type: "string", description: "UUID da transação. Omitir analisa todas as pendentes." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;

      const data = await callReconcile(ctx, {
        action: "suggest",
        ...(args.transaction_id ? { transaction_id: args.transaction_id } : {}),
      });

      // Resposta enxuta: o modelo não precisa do objeto inteiro, precisa do essencial
      // para explicar a escolha ao usuário.
      const itens = (data.transactions || []).map((t: any) => ({
        transacao: {
          id: t.transaction.id,
          data: t.transaction.transaction_date,
          descricao: t.transaction.description,
          valor: t.transaction.amount,
          tipo: t.transaction.transaction_type,
        },
        sugestoes: (t.suggestions || []).map((s: any) => ({
          tipo: s.candidate.kind,
          id: s.candidate.id,
          descricao: s.candidate.label,
          cliente: s.candidate.clientName,
          valor_esperado: s.candidate.amount,
          confianca: s.score,
          nivel: s.tier,
          diferenca: s.difference,
          motivos: s.reasons.map((r: any) => r.detail),
          aprova_orcamento: !!s.candidate.convertsQuote,
        })),
      }));

      return { resumo: data.summary, itens };
    },
  },

  {
    name: "conciliar_transacao",
    description:
      "Registra o pagamento de uma transação do extrato contra uma conta a receber/pagar ou o sinal de um orçamento. Conciliar o sinal APROVA o orçamento e o converte em OS. Use somente após confirmar a correspondência com sugerir_conciliacao.",
    input_schema: {
      type: "object",
      properties: {
        transaction_id: { type: "string", description: "UUID da transação do extrato" },
        tipo: {
          type: "string",
          enum: ["receivable", "payable", "quote_deposit"],
          description: "O que está sendo pago",
        },
        alvo_id: {
          type: "string",
          description: "UUID da conta a receber/pagar, ou da OS/orçamento no caso de quote_deposit",
        },
      },
      required: ["transaction_id", "tipo", "alvo_id"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const bloqueio = blockTechnician(ctx);
      if (bloqueio) return bloqueio;

      const { data: tx, error: txErr } = await ctx.sb
        .from("bank_transactions")
        .select("id, transaction_date, description, amount, reconciled")
        .eq("id", args.transaction_id)
        .single();
      if (txErr) throw txErr;
      if (!tx) return { error: "Transação não encontrada." };
      if (tx.reconciled) return { error: "Esta transação já foi conciliada." };

      const notas = `Conciliação pelo agente — ${tx.description}`.slice(0, 500);
      let paymentId: string | null = null;
      let serviceOrderId: string | null = null;

      if (args.tipo === "quote_deposit") {
        const { data, error } = await ctx.sb.rpc("register_deposit_and_convert", {
          p_service_order_id: args.alvo_id,
          p_amount: Number(tx.amount),
          p_payment_date: tx.transaction_date,
          p_payment_method: "bank_transfer",
          p_card_fee_percent: 0,
          p_notes: notas,
        });
        if (error) throw error;
        paymentId = (data as any)?.payment_id ?? null;
        serviceOrderId = args.alvo_id;
      } else {
        const { data, error } = await ctx.sb.rpc("register_payment_and_update_balance", {
          p_receivable_id: args.tipo === "receivable" ? args.alvo_id : null,
          p_payable_id: args.tipo === "payable" ? args.alvo_id : null,
          p_amount: Number(tx.amount),
          p_payment_date: tx.transaction_date,
          p_payment_method: "bank_transfer",
          p_installments: 1,
          p_card_fee_percent: 0,
          p_net_amount: Number(tx.amount),
          p_notes: notas,
        });
        if (error) throw error;
        paymentId = (data as any)?.payment_id ?? null;
      }

      const { error: updErr } = await ctx.sb
        .from("bank_transactions")
        .update({
          reconciled: true,
          reconciled_payment_id: paymentId,
          reconciled_service_order_id: serviceOrderId,
        })
        .eq("id", args.transaction_id);
      if (updErr) throw updErr;

      return {
        ok: true,
        payment_id: paymentId,
        mensagem: args.tipo === "quote_deposit"
          ? "Sinal registrado; o orçamento foi aprovado e convertido em OS."
          : "Pagamento registrado e saldo atualizado.",
      };
    },
  },
];

/** Reexporta o motor para quem quiser pontuar sem passar pela edge function. */
export { suggestMatches };
export type { BankTx };
