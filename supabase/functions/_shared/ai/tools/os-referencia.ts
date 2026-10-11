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

// ── O número no lugar do uuid, para TODAS as tools (11/10/2026) ──────────────────────────────
// Só ~5 tools usavam acharOS; ~46 recebiam a OS e só aceitavam o uuid ("invalid input syntax for
// type uuid" com ORÇ-00112 no get_service_order). A troca roda em executarChamadaDeTool, antes do
// risco, da pendência e da execução: a pendência grava o uuid e o OpenRouter e o Max ganham juntos.

/** Chaves que, em qualquer tool, são a OS/orçamento. */
const CHAVES_DA_OS = ["service_order_id", "linked_service_order_id", "os_id"];
/** Tools em que o próprio `id` é a OS/orçamento (nas demais, `id` é tarefa, e-mail, nota…). */
const TOOLS_COM_ID_DA_OS = new Set(["get_service_order", "update_service_order_status", "apply_service_order_discount", "update_quote_status"]);

/** "OS-00112", "ORÇ-00112", "orc 112", "112" — número de documento e nada mais ("ultimo" e frases ficam). */
function pareceNumeroDeOS(v: string): boolean {
  const t = v.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return /^(ORCAMENTO|ORC|OS|ORDEM)?\d{1,8}$/.test(t);
}

/**
 * Troca o número dito pelo uuid nas chaves da OS. Usa o cliente de quem pede (sb), não o admin.
 * Número ambíguo (ORÇ e OS) ou não achado volta `{ error, opcoes }` e nada deve rodar. uuid,
 * "ultimo" e texto sem cara de número seguem como vieram — a tool decide, como antes.
 */
export async function trocarNumeroDaOsPeloId(
  nomeDaTool: string,
  input: unknown,
  sb: ToolCtx["sb"],
): Promise<{ input: unknown } | { error: string; opcoes?: string[] }> {
  if (!input || typeof input !== "object" || Array.isArray(input)) return { input };
  const chaves = TOOLS_COM_ID_DA_OS.has(nomeDaTool) ? [...CHAVES_DA_OS, "id"] : CHAVES_DA_OS;
  let trocado: Record<string, unknown> | null = null;
  for (const chave of chaves) {
    const v = (input as Record<string, unknown>)[chave];
    if (typeof v !== "string" || UUID_RE.test(v.trim()) || !pareceNumeroDeOS(v)) continue;
    const achada = await acharOS({ admin: sb }, { os: v });
    if ("error" in achada) return achada;
    trocado = { ...(trocado ?? (input as Record<string, unknown>)), [chave]: achada.id };
  }
  return { input: trocado ?? input };
}
