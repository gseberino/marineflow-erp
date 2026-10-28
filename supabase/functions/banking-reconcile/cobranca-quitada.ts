// Fechamento da cobrança avulsa conciliada pelo extrato.
//
// [FECHAR-JUNTAS 0b, item 2] A conciliação gravava `payment_confirmed_by: "conciliacao"`,
// valor que o CHECK `collections_payment_confirmed_by_check` recusa (só aceita manual,
// whatsapp e auto — supabase/schemas/producao/02-tabelas.sql:1099, conferido em produção em
// 28/10/2026). O erro do update não era conferido: o dinheiro entrava no financeiro, a
// transação saía como conciliada e a cobrança continuava `pending`, candidata a conciliar de
// novo e lembrada ao cliente depois de paga.
//
// "auto" é o mesmo valor que o gatilho `sync_collection_from_receivable` grava quando a conta
// ligada à cobrança é quitada — a confirmação veio do sistema, não de uma pessoa.

/** Quem confirmou o pagamento, do jeito que o CHECK da tabela aceita. */
export const CONFIRMADO_PELA_CONCILIACAO = "auto" as const;

/** Campos que fecham a cobrança e a ligam à conta a receber criada na conciliação. */
export function dadosDaCobrancaQuitada(
  receivableId: string,
  valor: number,
  agora: Date = new Date(),
): Record<string, unknown> {
  return {
    receivable_id: receivableId,
    status: "paid",
    paid_at: agora.toISOString(),
    paid_amount: valor,
    paid_method: "bank_transfer",
    payment_confirmed_by: CONFIRMADO_PELA_CONCILIACAO,
  };
}

// Só o pedaço do cliente do Supabase que esta função usa — permite testar com um falso.
// deno-lint-ignore no-explicit-any
type BancoMinimo = { from: (tabela: string) => any };

/**
 * Grava o fechamento da cobrança e CONFERE o resultado: erro do banco ou nenhuma linha
 * alterada viram `ok: false` com a mensagem pronta para a tela.
 */
export async function quitarCobrancaConciliada(
  admin: BancoMinimo,
  cobrancaId: string,
  receivableId: string,
  valor: number,
  agora: Date = new Date(),
): Promise<{ ok: true } | { ok: false; message: string }> {
  const { data, error } = await admin
    .from("collections")
    .update(dadosDaCobrancaQuitada(receivableId, valor, agora))
    .eq("id", cobrancaId)
    .select("id");
  if (error) {
    return { ok: false, message: String(error.message ?? error) };
  }
  if (!Array.isArray(data) || data.length === 0) {
    return { ok: false, message: "a cobrança não foi encontrada para fechar" };
  }
  return { ok: true };
}

/**
 * Mensagem quando o dinheiro já entrou (conta e pagamento criados) mas a cobrança não fechou.
 * Diz o que aconteceu e o que fazer — refazer a conciliação lançaria o recebimento duas vezes.
 */
export function mensagemCobrancaNaoFechou(rotulo: string, motivo: string): string {
  return `Recebimento lançado, mas a cobrança "${rotulo}" não foi fechada (${motivo}). `
    + "Não concilie de novo: marque a cobrança como paga à mão em Cobranças.";
}
