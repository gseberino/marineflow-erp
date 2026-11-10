// O cartão do parceiro (retorno rápido, F4, P12.1). A ferramenta NÃO é oferecida ao modelo: fica fora de allTools e só entra
// no mapa de execução das pendências, depois do *sim <PIN>* do dono (risco alto, nunca autônoma).
//
// O que ela faz: parceiro_cartao_executar decide cada item no banco (vínculo, aviso, painel, pátio, repassar…) e já agenda as
// saídas em retorno_saidas, que a rodada do retorno-recibos leva. Aqui só sai o que é da edge: os orçamentos do pedido da MP
// (C13), por orcarEEnviar com os cinco nomes do parceiro, e os PDFs (hoje sempre vazio no SQL), pelo send_service_order_link.
//
// O texto do cartão não vai ao assistente: nenhuma ferramenta do modelo lê o cartão do parceiro (retorno_ler_caso só lê os
// itens do cartão da F2). O telefone nunca vem de argumento: o destino do PDF ao parceiro é parceiro_destino_do_pdf, e o do
// cliente, o cadastro.
//
// Reverter: tirar parceiroSoPelaPendencia de toolsSoPelaPendencia (tools/index.ts).

import { logEdgeError } from "../../log-error.ts";
import { dependenciasReais, type DepsDoCartao, type OpcoesDoOrcamento, type OrcamentoDoCartao, orcarEEnviarSemLancar } from "./retorno.ts";
import type { ToolCtx, ToolDef } from "./registry.ts";
import { retratoDoEnvio } from "./whatsapp.ts";

export const NOME_DA_TOOL_DO_CARTAO_PARCEIRO = "parceiro_executar_cartao";

const FALHOU = "Não consegui executar o cartão do parceiro agora.";

/** Os cinco nomes do caminho do parceiro (P10.1): o par de cada um da F3, sobre parceiro_cartao_itens. */
export const RPCS_DO_PARCEIRO = {
  preparar: "parceiro_previa_preparar",
  soltar: "parceiro_previa_soltar",
  enviado: "parceiro_item_enviado",
  caiu: "parceiro_previa_caiu",
  pdf: "parceiro_previa_pdf",
} as const;

/** O orçamento do item `pedido` (C-EXEC-P), além do formato da F3. */
export interface OrcamentoDoParceiro extends OrcamentoDoCartao {
  pedido_id?: string | null;
  destino?: "cliente" | "parceiro";
  parceiro_id?: string | null;
}

/** O PDF de um item (C-EXEC-P). Hoje parceiro_cartao_executar devolve sempre a lista vazia. */
interface PdfDoCartao {
  item_id?: string | null;
  service_order_id?: string | null;
  destino?: "cliente" | "parceiro";
  parceiro_id?: string | null;
}

/** As opções de orcarEEnviar para um item do parceiro: o sem_enviar encerra o item sem soltar (P10.1). */
export function opcoesDoParceiro(o: OrcamentoDoParceiro): OpcoesDoOrcamento {
  return {
    rpcs: { ...RPCS_DO_PARCEIRO },
    destino: o.destino === "parceiro" ? "parceiro" : "cliente",
    ...(o.parceiro_id ? { parceiro_id: o.parceiro_id } : {}),
    ...(o.pedido_id ? { pedido_id: o.pedido_id } : {}),
    soltar_sem_enviar: false,
    frase_sem_enviar: `o ${o.n ?? "pedido"}: ficou em rascunho; o PDF ao parceiro só sai depois do aviso e de 24 h; peça de novo depois disso`,
  };
}

async function enviarPdfDoItem(p: PdfDoCartao, ctx: ToolCtx, deps: DepsDoCartao): Promise<string | null> {
  const aoParceiro = p.destino === "parceiro";
  const pedido: Record<string, unknown> = {
    service_order_id: p.service_order_id,
    formato: "pdf",
    ...(aoParceiro ? { destino: "parceiro", ...(p.parceiro_id ? { parceiro_id: p.parceiro_id } : {}) } : {}),
  };
  let ok = false;
  try {
    const envio = await deps.enviarPdf({ ...pedido, _retrato: await retratoDoEnvio(ctx.admin, pedido, ctx.userId) }, ctx) as Record<string, unknown>;
    ok = !envio.error;
  } catch {
    ok = false;
  }
  if (p.item_id) {
    try {
      await ctx.admin.rpc("parceiro_item_enviado", { p_item: p.item_id, p_ok: ok, p_wa_id: null });
    } catch {
      // o item fica no cartão; o próximo *parceiro* mostra de novo
    }
  }
  return ok ? null : "o PDF não saiu: mande pelo celular";
}

export async function executarCartaoDoParceiro(
  args: Record<string, unknown>,
  ctx: ToolCtx,
  deps: DepsDoCartao = dependenciasReais(),
): Promise<Record<string, unknown>> {
  const cartao = typeof args.cartao_id === "string" ? args.cartao_id : "";
  if (!cartao) return { error: FALHOU };
  const t0 = Date.now();

  let data: { ok?: boolean; aviso?: string; pdfs?: PdfDoCartao[]; orcamentos?: OrcamentoDoParceiro[] } | null;
  try {
    const r = await ctx.admin.rpc("parceiro_cartao_executar", { p_cartao: cartao, p_autor: ctx.userId });
    if (r.error) return { error: FALHOU };
    data = r.data;
  } catch {
    return { error: FALHOU };
  }
  if (!data?.ok) return { error: data?.aviso || FALHOU };

  const avisos: string[] = data.aviso ? [data.aviso] : [];

  for (const p of Array.isArray(data.pdfs) ? data.pdfs : []) {
    try {
      const falha = await enviarPdfDoItem(p, ctx, deps);
      if (falha) avisos.push(falha);
    } catch (e) {
      await logEdgeError(ctx.admin, { context: "ai-agent", action: "parceiro_pdf_do_cartao", message: `PDF do cartão do parceiro não terminou: ${(e as Error)?.message ?? String(e)}`, error: e });
      avisos.push("o PDF não saiu: mande pelo celular");
    }
  }

  // Orçamento de tempo: o teto da edge é ~150 s, e um PDF pode levar até 25 s.
  for (const o of Array.isArray(data.orcamentos) ? data.orcamentos : []) {
    if (Date.now() - t0 > 90_000) {
      avisos.push(`o ${o.n} ficou para depois: *parceiro*`);
      if (o.item_id) {
        try {
          await ctx.admin.rpc(RPCS_DO_PARCEIRO.soltar, { p_item: o.item_id });
        } catch {
          // o item volta pelo vigia do cartão; nada saiu
        }
      }
      continue;
    }
    avisos.push(...await orcarEEnviarSemLancar(o, ctx, deps, opcoesDoParceiro(o)));
  }
  return { ok: true, aviso: avisos.join(" "), so_texto: true };
}

/** Só no mapa de execução (toolsByName), nunca na lista do modelo. */
export const parceiroSoPelaPendencia: ToolDef[] = [{
  name: NOME_DA_TOOL_DO_CARTAO_PARCEIRO,
  description: "Executa o cartão do parceiro que o dono aprovou com \"sim <PIN>\". Só roda pela confirmação do cartão; nunca é oferecida ao modelo.",
  input_schema: { type: "object", properties: { cartao_id: { type: "string" } }, required: ["cartao_id"] },
  risk: "high",
  roles: ["admin"],
  execute: (args, ctx) => executarCartaoDoParceiro((args ?? {}) as Record<string, unknown>, ctx),
}];
