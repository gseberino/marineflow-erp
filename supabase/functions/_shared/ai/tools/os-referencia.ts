// Qual OS o dono quis dizer — pelo id OU pelo número falado (07/10/2026).
//
// "na OS-00112, diagnóstico: …" — o dono fala o NÚMERO, não o uuid. Antes, as tools de texto e
// de campo da OS exigiam o uuid, e o modelo tinha de fazer uma volta a mais (list_service_orders)
// só para traduzir o número. Aqui a tradução fica no sistema, pela mesma busca do PDF
// (localizarOrdem): ORÇ-00112, OS-00112, "112" (pergunta se existir como ORÇ e como OS) ou
// "ultimo". Nome de cliente NÃO identifica a OS aqui: "a OS do Nelson" é list_service_orders
// (pode haver várias), e a escolha é do dono.

import type { ToolCtx } from "./registry.ts";
import { localizarOrdem } from "./documentos-pdf.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface OsAchada {
  id: string;
  numero: string;
  status: string;
}

/**
 * Resolve `service_order_id` (uuid) ou `os` (número dito). Se o modelo puser o número no campo
 * do id ("OS-00112" em service_order_id), entende do mesmo jeito. Nunca chuta: número que existe
 * como ORÇ e como OS volta com as opções.
 */
export async function acharOS(
  ctx: Pick<ToolCtx, "admin">,
  args: { service_order_id?: unknown; os?: unknown },
): Promise<OsAchada | { error: string; opcoes?: string[] }> {
  const id = String(args.service_order_id ?? "").trim();
  const numero = String(args.os ?? "").trim();
  const referencia = UUID_RE.test(id) ? id : (numero || id);
  if (!referencia) return { error: "Diga qual OS: o número (ex.: OS-00112 ou ORÇ-00112) ou o id." };
  const achado = await localizarOrdem(ctx.admin, referencia);
  if ("opcoes" in achado) {
    return { error: `Existe mais de um documento com esse número: ${achado.opcoes.join(" e ")}. Qual deles?`, opcoes: achado.opcoes };
  }
  if ("erro" in achado) return { error: achado.erro };
  return { id: achado.ordem.id, numero: achado.ordem.service_order_number, status: achado.ordem.status };
}
