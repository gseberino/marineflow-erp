// [MF-AUD-009] A cascata que faltava no caminho do agente.
//
// ═══ O QUE ESTAVA ACONTECENDO ═══
//
// Há dois caminhos para mudar o valor de uma OS, e eles faziam coisas diferentes:
//
//   Pela TELA    →  recalcTotals() → updateReceivableFromSO():
//                   bloqueia se o total cair abaixo do já pago, e redistribui os pendentes.
//   Pelo AGENTE  →  RPC recalc_so_totals():
//                   atualiza service_orders e PARA. Nenhuma cascata, nenhum piso.
//
// Nenhum trigger cobria a lacuna: o único que toca recebíveis dispara na CONCLUSÃO da OS
// (`trg_sync_balance_due_on_completion`), não em mudança de item. Então o agente
// acrescentava uma peça, o total da OS subia, e o título a receber ficava com o valor antigo
// — o financeiro divergindo da OS sem nenhum erro aparecer.
//
// Este módulo faz, do lado do agente, o que a tela já fazia. A aritmética não é dele: vem de
// `redistribution.ts`, o mesmo módulo puro que a tela usa.

import { redistribuirRecebiveis } from "./redistribution.ts";

/** Cliente Supabase — `any` de propósito: serve tanto ao `sb` (RLS) quanto ao `admin`. */
// deno-lint-ignore no-explicit-any
type DbClient = any;

export interface ResultadoDaCascata {
  /** Nada foi gravado: o novo total ficaria abaixo do já pago. */
  bloqueado: boolean;
  motivo?: string;
  /** Quantos recebíveis tiveram valor alterado. */
  atualizados: number;
  novoTotal?: number;
}

/**
 * Recalcula os totais da OS e propaga para os recebíveis, respeitando o piso do já pago.
 *
 * Substitui as chamadas soltas a `sb.rpc("recalc_so_totals", …)` nas tools. A ordem importa:
 * a RPC roda primeiro (é ela que sabe somar peças, serviços, taxa de cartão e deslocamento),
 * e só então se lê o `grand_total` resultante para redistribuir.
 *
 * ⚠ NÃO é atômico. A RPC e as atualizações dos recebíveis são chamadas separadas — se a
 * segunda falhar, a OS fica com o total novo e os recebíveis com o antigo, que é o estado de
 * hoje. Fossilizar isto numa função SQL resolveria de vez (proposta no PR); enquanto não for
 * decisão tomada, o `bloqueado` protege o caso caro (reduzir abaixo do pago) verificando
 * ANTES de gravar qualquer recebível.
 */
export async function recalcularOSComCascata(
  sb: DbClient,
  soId: string,
): Promise<ResultadoDaCascata> {
  await sb.rpc("recalc_so_totals", { so_id: soId });

  const { data: so } = await sb
    .from("service_orders")
    .select("grand_total")
    .eq("id", soId)
    .maybeSingle();

  const novoTotal = Number(so?.grand_total ?? 0);

  const { data: recebiveis } = await sb
    .from("receivables")
    .select("id, amount, paid_amount, status")
    .eq("service_order_id", soId)
    .neq("status", "cancelled");

  const plano = redistribuirRecebiveis(recebiveis ?? [], novoTotal);

  if (plano.bloqueado) {
    return { bloqueado: true, motivo: plano.motivo, atualizados: 0, novoTotal };
  }

  let atualizados = 0;
  for (const alt of plano.alteracoes) {
    // Só grava o que de fato mudou: um UPDATE por recebível a cada recálculo encheria a
    // trilha de auditoria de linhas idênticas e esconderia as alterações reais.
    if (
      alt.amount === alt.anterior.amount
      && alt.status === alt.anterior.status
    ) continue;

    const { error } = await sb
      .from("receivables")
      .update({
        amount: alt.amount,
        balance_amount: alt.balance_amount,
        status: alt.status,
      })
      .eq("id", alt.id);

    if (error) continue;
    atualizados++;

    // A tela grava trilha para cada redistribuição; o agente precisa gravar também, senão a
    // mesma alteração fica auditável quando vem de uma pessoa e invisível quando vem da IA.
    //
    // Engolir a falha da trilha é deliberado: o valor JÁ foi gravado, e derrubar a operação
    // aqui deixaria a alteração feita e o chamador achando que falhou — pior que uma linha de
    // auditoria faltando.
    try {
      await sb.from("audit_logs").insert({
        table_name: "receivables",
        record_id: alt.id,
        action: "cascade_update",
        previous_value: alt.anterior,
        new_value: {
          amount: alt.amount,
          balance_amount: alt.balance_amount,
          status: alt.status,
        },
        reason: "Atualização automática por alteração do total da OS pelo agente (redistribuição proporcional)",
        triggered_by_table: "service_orders",
        triggered_by_id: soId,
      });
    } catch (e) {
      console.error("[cascata] trilha de auditoria falhou para o recebível", alt.id, e);
    }
  }

  return { bloqueado: false, atualizados, novoTotal };
}
