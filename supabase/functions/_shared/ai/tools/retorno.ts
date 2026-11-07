// O cartão do retorno rápido (F2, P8). A ferramenta NÃO é oferecida ao modelo: fica fora de allTools e só entra no mapa de
// execução das pendências, depois do "sim <PIN>" do dono (risco alto).
//
// O que ela faz: retorno_cartao_executar cria no banco as saídas dos modelos e devolve os ditados; cada ditado sai aqui, pelo
// whatsapp-send, como humano, e retorno_item_enviado fecha o caso.
//
// O telefone sai do banco, do caso, nunca de argumento.
//
// Reverter: tirar retornoSoPelaPendencia de toolsSoPelaPendencia.

import type { ToolCtx, ToolDef } from "./registry.ts";
import { sendWhatsapp } from "./whatsapp.ts";

export const NOME_DA_TOOL_DO_CARTAO = "retorno_executar_cartao";

const FALHOU = "Não consegui executar o cartão agora.";
const DITADO_NAO_SAIU = "Um ditado não saiu: responda pelo celular.";

export type EnviarDitado = (
  phone: string,
  texto: string,
  jwt: string,
  dedupeKey: string,
  sentBy: string,
) => Promise<{ ok?: boolean; error?: string; messageId?: string | null }>;

interface Ditado {
  item_id: string;
  phone: string;
  texto: string;
  dedupe_key: string;
}

export async function executarCartao(
  args: Record<string, unknown>,
  ctx: ToolCtx,
  enviar: EnviarDitado = sendWhatsapp,
): Promise<Record<string, unknown>> {
  const cartao = typeof args.cartao_id === "string" ? args.cartao_id : "";
  if (!cartao) return { error: FALHOU };

  let data: { ok?: boolean; aviso?: string; ditados?: Ditado[] } | null;
  try {
    const r = await ctx.admin.rpc("retorno_cartao_executar", { p_cartao: cartao, p_autor: ctx.userId });
    if (r.error) return { error: FALHOU };
    data = r.data;
  } catch {
    return { error: FALHOU };
  }
  if (!data?.ok) return { error: data?.aviso || FALHOU };

  const avisos: string[] = data.aviso ? [data.aviso] : [];
  for (const d of data.ditados ?? []) {
    let enviado = false;
    let waId: string | null = null;
    try {
      const r = await enviar(d.phone, d.texto, ctx.jwt, d.dedupe_key, ctx.userId);
      enviado = !r.error;
      waId = r.messageId ?? null;
    } catch {
      enviado = false;
    }
    if (!enviado && !avisos.includes(DITADO_NAO_SAIU)) avisos.push(DITADO_NAO_SAIU);
    try {
      await ctx.admin.rpc("retorno_item_enviado", { p_item: d.item_id, p_ok: enviado, p_wa_id: waId });
    } catch {
      // A saída humana aparece para a régua da F1 de qualquer jeito; sem esta linha, o caso só demora a fechar.
    }
  }
  return { ok: true, aviso: avisos.join(" "), so_texto: true };
}

/** Só no mapa de execução (toolsByName), nunca na lista do modelo. */
export const retornoSoPelaPendencia: ToolDef[] = [{
  name: NOME_DA_TOOL_DO_CARTAO,
  description: "Executa o cartão do retorno que o dono aprovou com \"sim <PIN>\". Só roda pela confirmação do cartão; nunca é oferecida ao modelo.",
  input_schema: { type: "object", properties: { cartao_id: { type: "string" } }, required: ["cartao_id"] },
  risk: "high",
  roles: ["admin"],
  execute: (args, ctx) => executarCartao((args ?? {}) as Record<string, unknown>, ctx),
}];
