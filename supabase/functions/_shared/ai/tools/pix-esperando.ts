// Pix de cliente que chegou no banco e ainda espera decisão no Extrato (auditoria de 02-03/10/2026).
//
// Uma conta a receber continua "em aberto" até alguém aplicar o Pix nela; enquanto a entrada espera
// na fila do Extrato, o plano de inadimplência mandava cobrar — e o lembrete saía — de quem já tinha
// pago.
//
// (24/11/2026) Quais entradas contam para um cliente mora em _shared/receivables/dinheiro-esperando.ts: as que a fila
// identificou (documento, histórico, nome idêntico ou regra do dono) E as que o vínculo sugerido aponta para uma conta
// ABERTA dele. Antes só valiam as primeiras, e os dois boletos da Apolo e o Pix do Nelson (R$ 12.586,07, na fila sem
// cliente, só com o vínculo apontando a conta) passavam: o plano mandava cobrar quem tinha dinheiro no banco. Isto só
// SEGURA cobrança; nunca aplica dinheiro nem dá baixa.
import type { ToolCtx } from "./registry.ts";
// LGPD (leva 8): o título da entrada nasce do nome do banco ("Receita: 12345678901-MARIA…") — CPF mascarado ao modelo.
import { nomeSemCpf as mascararCpfNoTexto } from "../../banking/contraparte.ts";
import { lerDinheiroEsperando } from "../../receivables/dinheiro-esperando.ts";

export interface PixEsperando {
  valor: number;
  data: string | null;
  titulo: string;
}

export async function pixEsperandoNoExtrato(ctx: ToolCtx, clientIds: string[]): Promise<Map<string, PixEsperando[]>> {
  const mapa = new Map<string, PixEsperando[]>();
  if (clientIds.length === 0) return mapa;
  const pedidos = new Set(clientIds.map(String));
  // Leitura que falha lança (lerDinheiroEsperando): "nenhum Pix esperando" por erro mandaria cobrar quem já pagou.
  for (const e of await lerDinheiroEsperando(ctx.admin)) {
    if (!pedidos.has(e.clienteId)) continue;
    const lista = mapa.get(e.clienteId) ?? [];
    lista.push({ valor: e.valor, data: e.data, titulo: mascararCpfNoTexto(e.titulo) });
    mapa.set(e.clienteId, lista);
  }
  return mapa;
}
