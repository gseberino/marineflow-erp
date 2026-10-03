// Pix de cliente que chegou no banco e ainda espera decisão no Extrato (auditoria de 02-03/10/2026).
//
// Uma conta a receber continua "em aberto" até alguém aplicar o Pix nela; enquanto a entrada espera
// na fila do Extrato, o plano de inadimplência mandava cobrar — e o lembrete saía — de quem já tinha
// pago. Só olha entradas com cliente identificado pela fila (documento, histórico, nome idêntico ou
// regra do dono): nunca casa pelo valor.
import type { ToolCtx } from "./registry.ts";

export interface PixEsperando {
  valor: number;
  data: string | null;
  titulo: string;
}

export async function pixEsperandoNoExtrato(ctx: ToolCtx, clientIds: string[]): Promise<Map<string, PixEsperando[]>> {
  const mapa = new Map<string, PixEsperando[]>();
  if (clientIds.length === 0) return mapa;
  const { data, error } = await ctx.admin
    .from("finance_review_queue")
    .select("suggested_client_id, suggested_amount, suggested_date, title")
    .eq("status", "pending")
    .eq("kind", "create_receivable")
    .in("suggested_client_id", clientIds)
    .range(0, 999);
  // Leitura que falha lança: "nenhum Pix esperando" por erro mandaria cobrar quem já pagou.
  if (error) throw new Error(`Não consegui ler os Pix que esperam no Extrato: ${error.message}`);
  for (const l of (data ?? []) as Array<{ suggested_client_id: string; suggested_amount: number | null; suggested_date: string | null; title: string }>) {
    const lista = mapa.get(l.suggested_client_id) ?? [];
    lista.push({ valor: Math.abs(Number(l.suggested_amount ?? 0)), data: l.suggested_date, titulo: l.title });
    mapa.set(l.suggested_client_id, lista);
  }
  return mapa;
}
