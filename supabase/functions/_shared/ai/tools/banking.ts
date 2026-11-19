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

import { type ToolDef } from "./registry.ts";
import { suggestMatches } from "../../banking/matching.ts";
import type { BankTx } from "../../banking/types.ts";
import { montarSugestoes } from "../../banking/sugestoes.ts";
import { documentoMascarado } from "../../banking/contraparte.ts";
import { CARGOS_DO_FINANCEIRO, mascararCpfNoTexto, semAcessoDoFinanceiro } from "./financeiro-comum.ts";
import { mensagemDoBanco } from "./lancamentos.ts";

// Ler o extrato pelo assistente (leva 8, 23/10/2026 — LGPD): CPF de terceiro só para administrador e financeiro, e
// mascarado (***.456.789-**; CNPJ inteiro). O cargo é conferido DENTRO do execute: no WhatsApp e no Claude Max o
// cliente do banco é a chave de serviço, que passa por cima da RLS de bank_transactions (só admin/financeiro na tela).
// Quem precisa do documento inteiro (regra por CPF/CNPJ) passa o id da linha e a tool lê do banco
// (criar_regra_financeira com bank_transaction_id) — nunca do texto que o modelo viu.

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
    roles: CARGOS_DO_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = semAcessoDoFinanceiro(ctx);
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
      // CPF de terceiro mascarado — no campo e no texto que o banco escreve com ele (nome e histórico).
      // deno-lint-ignore no-explicit-any
      const transacoes = ((data || []) as any[]).map((t) => ({
        ...t,
        description: mascararCpfNoTexto(t.description),
        counterparty_name: mascararCpfNoTexto(t.counterparty_name),
        counterparty_document: documentoMascarado(t.counterparty_document),
      }));
      return {
        total: transacoes.length,
        transacoes,
        dica: "Use sugerir_conciliacao com o id de uma transação para ver as correspondências pontuadas. "
          + "O CPF aparece mascarado: regra por documento é criar_regra_financeira com o id da linha em bank_transaction_id.",
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
    roles: CARGOS_DO_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = semAcessoDoFinanceiro(ctx);
      if (bloqueio) return bloqueio;

      // O mesmo cálculo da tela de Conciliação, direto (03/10/2026). Antes ia por HTTP à
      // banking-reconcile com o JWT do usuário — e no WhatsApp e no Claude Max não há sessão do
      // navegador, então a sugestão nunca rodava fora do painel. Sugerir só lê, com a chave de
      // serviço, como a edge já fazia; gravar continua só pela confirmação humana.
      const r = await montarSugestoes(ctx.admin, {
        ...(args.transaction_id ? { transactionId: String(args.transaction_id) } : {}),
      });
      const resumo = {
        pendentes: r.porTransacao.length,
        sugeridas: r.porTransacao.filter((p) => p.suggestions.length > 0).length,
        sem_candidato: r.porTransacao.filter((p) => p.suggestions.length === 0).length,
        candidatos_avaliados: r.candidatosAvaliados,
        transferencias_internas: r.transferenciasInternas,
      };

      // Resposta enxuta: o modelo não precisa do objeto inteiro, precisa do essencial
      // para explicar a escolha ao usuário.
      const itens = r.porTransacao.map((t: any) => ({
        transacao: {
          id: t.transaction.id,
          data: t.transaction.transaction_date,
          descricao: mascararCpfNoTexto(t.transaction.description),
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
          // O motivo de terceiro sem nome traz o CPF de quem enviou (matching.ts): mascarado aqui, sem mexer no motor.
          motivos: s.reasons.map((r: any) => mascararCpfNoTexto(r.detail)),
          aprova_orcamento: !!s.candidate.convertsQuote,
        })),
      }));

      return { resumo, itens };
    },
  },

  {
    name: "conciliar_transacao",
    description:
      "Registra o pagamento de uma transação do extrato contra uma conta a receber/pagar ou o sinal de um orçamento. Conciliar o sinal APROVA o orçamento e o converte em OS. Use somente após confirmar a correspondência com sugerir_conciliacao. " +
      "Conta já paga: a linha casa com o pagamento que já existe (nenhuma receita nova). Linha maior que o saldo: só o saldo vira pagamento. Entrada só casa com conta a receber; saída, com conta a pagar.",
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
    // Só administrador e financeiro (decisão do dono, 23/10/2026): pelo WhatsApp/Max a chave de serviço ignora a RLS de
    // bank_transactions, e a tela de Conciliação já nega o vendedor.
    roles: CARGOS_DO_FINANCEIRO,
    async execute(args, ctx) {
      const bloqueio = semAcessoDoFinanceiro(ctx);
      if (bloqueio) return bloqueio;

      const { data: tx, error: txErr } = await ctx.sb
        .from("bank_transactions")
        .select("id, transaction_date, description, amount, reconciled, transaction_type")
        .eq("id", args.transaction_id)
        .maybeSingle();
      if (txErr) throw txErr;
      if (!tx) return { error: "Transação não encontrada." };
      if (tx.reconciled) return { error: "Esta transação já foi conciliada." };

      // Conta a receber/pagar: pela MESMA função do banco que a tela de Conciliação e casar_lancamento_com_extrato
      // usam (19/11/2026). Antes a tool registrava o valor INTEIRO da linha com register_payment_and_update_balance e
      // marcava a linha à parte: conta já paga ganhava um segundo pagamento (receita em dobro), o valor acima do saldo
      // virava pagamento a mais, a conta não guardava bank_transaction_id e entrada casava com conta a pagar.
      // conciliar_lancamento confere tudo isso numa transação só (já paga = casa com o pagamento que existe; paga só
      // até o saldo; crédito ↔ receber, débito ↔ pagar; linha já vinculada recusa) e aceita p_autor sem sessão
      // (pelo WhatsApp/Max): _autor_do_financeiro usa auth.uid() quando há sessão e, sem ela, confere o cargo do p_autor.
      if (args.tipo === "receivable" || args.tipo === "payable") {
        const { data, error } = await ctx.sb.rpc("conciliar_lancamento", {
          p_tipo: args.tipo, p_id: args.alvo_id, p_transacao: args.transaction_id, p_autor: ctx.userId || null,
        });
        if (error) return { error: `Não conciliei: ${mensagemDoBanco(error)}` };
        const r = (data ?? {}) as { ok?: boolean; pagamento_registrado?: boolean; valor_pago?: number; message?: string };
        if (r.ok !== true) return { error: r.message || "Não conciliei: o banco não confirmou." };
        const valorPago = Number(r.valor_pago) || 0;
        const sobra = Math.round((Number(tx.amount) - valorPago) * 100) / 100;
        return {
          ok: true,
          pagamento_registrado: r.pagamento_registrado === true,
          valor_pago: valorPago,
          mensagem: r.message || "Conciliado.",
          ...(r.pagamento_registrado && sobra > 0.009
            ? { aviso: `A linha do extrato tem R$ ${sobra.toFixed(2)} a mais que o saldo da conta: só o saldo foi registrado como pagamento.` }
            : {}),
        };
      }
      if (args.tipo !== "quote_deposit") return { error: "tipo deve ser receivable, payable ou quote_deposit." };
      if (tx.transaction_type && tx.transaction_type !== "credit") {
        return { error: "Sinal de orçamento só casa com ENTRADA no banco; esta linha é uma saída." };
      }

      const notas = `Conciliação pelo agente — ${tx.description}`.slice(0, 500);
      let paymentId: string | null = null;
      let serviceOrderId: string | null = null;

      {
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
      }

      // A linha do extrato marca o pagamento (o gatilho _pagamento_segue_a_linha grava payments.bank_transaction_id).
      const { data: marcou, error: updErr } = await ctx.sb
        .from("bank_transactions")
        .update({
          reconciled: true,
          reconciled_payment_id: paymentId,
          reconciled_service_order_id: serviceOrderId,
        })
        .eq("id", args.transaction_id)
        .select("id");
      if (updErr || !Array.isArray(marcou) || marcou.length === 0) {
        return {
          ok: false,
          payment_id: paymentId,
          error: "O sinal foi registrado e o orçamento convertido, mas a linha do extrato NÃO ficou marcada como conciliada" +
            `${updErr ? ` (${mensagemDoBanco(updErr)})` : ""}. Marque-a na tela de Conciliação para não registrar o mesmo dinheiro duas vezes.`,
        };
      }

      return {
        ok: true,
        payment_id: paymentId,
        mensagem: "Sinal registrado; o orçamento foi aprovado e convertido em OS.",
      };
    },
  },
];

/** Reexporta o motor para quem quiser pontuar sem passar pela edge function. */
export { suggestMatches };
export type { BankTx };
