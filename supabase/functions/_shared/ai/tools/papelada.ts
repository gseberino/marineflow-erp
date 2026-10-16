// O "sim" do lote semanal da papelada (secretário, Passo 5, 16/10/2026).
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-papelada.md §3.8.
//
// Esta tool NÃO é oferecida ao modelo (fica fora de allTools; só está no mapa de execução, toolsByName): ela só roda
// pela pendência que o comando *lote* abre, depois do "sim <PIN>" do dono (risco alto, a mesma regra da aprovação
// pelo painel). E não escreve lançamento nenhum por conta própria:
//   1. papelada_lote_conferir (aplicar=true): confere cada item contra a fila AGORA e trava o lote (tudo ou nada);
//   2. aprovar_propostas_de_lancamento.execute({ids}) — A MESMA tool do painel, que chama o finance-review approve
//      (o caminho da tela), com os cortes de lote do servidor;
//   3. papelada_lote_resultado: o banco diz o que entrou e o que não entrou, item por item.

import { financeRulesTools } from "./finance-rules.ts";
import type { ToolCtx, ToolDef } from "./registry.ts";
import {
  CHAVE_DA_PAPELADA, lerFormatoDaPapelada, NOME_DA_TOOL_DO_LOTE, type ResultadoDoLote, textoDoErroDoLote, textoDoResultado,
} from "../../papelada/texto.ts";

export { NOME_DA_TOOL_DO_LOTE };

/** A aprovação item a item de hoje (painel/tela): a única porta de escrita que o lote usa. */
export function aprovacaoDeSempre(): ToolDef {
  const t = financeRulesTools.find((x) => x.name === "aprovar_propostas_de_lancamento");
  if (!t) throw new Error("aprovar_propostas_de_lancamento não existe");
  return t;
}

// deno-lint-ignore no-explicit-any
async function rpc(admin: any, nome: string, p: Record<string, unknown>): Promise<Record<string, any> | null> {
  try {
    const { data, error } = await admin.rpc(nome, { p });
    if (error) {
      console.warn(JSON.stringify({ fn: "papelada", evento: `${nome}_falhou`, codigo: String(error.code ?? "erro") }));
      return null;
    }
    // deno-lint-ignore no-explicit-any
    return (data ?? null) as Record<string, any> | null;
  } catch (e) {
    console.warn(JSON.stringify({ fn: "papelada", evento: `${nome}_falhou`, codigo: (e as Error)?.name ?? "erro" }));
    return null;
  }
}

/** A chave lida do banco agora (a da sessão pode ter horas). Erro = desligado. */
// deno-lint-ignore no-explicit-any
async function chaveAgora(admin: any): Promise<string> {
  try {
    const { data, error } = await admin.from("app_settings").select("value").eq("key", CHAVE_DA_PAPELADA).maybeSingle();
    if (error) return "desligado";
    return lerFormatoDaPapelada(data?.value);
  } catch {
    return "desligado";
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function aprovarLoteDaPapelada(
  args: { lote_id?: unknown; ids?: unknown },
  ctx: ToolCtx,
  aprovar: ToolDef = aprovacaoDeSempre(),
): Promise<Record<string, unknown>> {
  if (ctx.userRole !== "admin") return { error: "Só o dono aprova o lote da papelada." };
  const loteId = String(args.lote_id ?? "");
  const ids = (Array.isArray(args.ids) ? args.ids : []).map(String).filter((x) => UUID.test(x));
  if (!UUID.test(loteId) || !ids.length) return { error: "Pedido do lote incompleto. Escreva *lote* de novo." };
  if ((await chaveAgora(ctx.admin)) !== "ligado") return { error: textoDoErroDoLote("sombra") };

  // 1. confere e trava (pronto → aplicando): o que mudou desde a sexta fica de fora, com o motivo
  const conf = await rpc(ctx.admin, "papelada_lote_conferir", { lote_id: loteId, ids, aplicar: true, app_user_id: ctx.userId });
  if (!conf?.ok) return { error: textoDoErroDoLote(conf?.erro ?? null) };
  const validos = (Array.isArray(conf.validos) ? conf.validos : []).map(String);

  // 2. a aprovação de sempre, com os mesmos cortes de lote do servidor (limite, OS/OC, terceiro, entrada sem receita)
  let resposta: unknown;
  try {
    resposta = await aprovar.execute({ ids: validos }, ctx);
  } catch (e) {
    resposta = { error: (e as Error)?.message ?? "falha na aprovação" };
  }

  // 3. o banco diz o que entrou (não a resposta): fecha o lote
  const r = await rpc(ctx.admin, "papelada_lote_resultado", {
    lote_id: loteId,
    resposta: resposta && typeof resposta === "object" ? resposta : {},
  });
  if (!r?.ok) {
    return { error: "Aprovei pelo caminho de sempre, mas não consegui conferir o resultado agora. Escreva *lote* daqui a 10 minutos." };
  }
  const titulos = new Map<number, string>();
  try {
    const { data } = await ctx.admin.from("papelada_lote").select("itens").eq("id", loteId).maybeSingle();
    for (const i of (Array.isArray(data?.itens) ? data.itens : []) as Array<{ n: number; titulo: string }>) titulos.set(Number(i.n), String(i.titulo));
  } catch {
    /* sem os títulos, o relatório usa só os números */
  }
  return {
    ok: true,
    entrou: Number(r.entrou ?? 0),
    falhou: Number(r.falhou ?? 0),
    fora: Number(r.fora ?? 0),
    aviso: textoDoResultado(r as unknown as ResultadoDoLote, titulos),
  };
}

/** Só no mapa de execução (toolsByName), nunca na lista do modelo. */
export const papeladaTools: ToolDef[] = [
  {
    name: NOME_DA_TOOL_DO_LOTE,
    description:
      "Aprova o lote semanal da papelada que o dono confirmou com \"sim <PIN>\". Só roda pela confirmação que o comando " +
      "*lote* abre; nunca é oferecida ao modelo.",
    input_schema: {
      type: "object",
      properties: {
        lote_id: { type: "string", description: "O id do lote (papelada_lote)." },
        ids: { type: "array", items: { type: "string" }, description: "Os ids das propostas escolhidas do lote." },
      },
      required: ["lote_id", "ids"],
    },
    // ALTA, como aprovar_propostas_de_lancamento: cria despesas registradas
    risk: "high",
    roles: ["admin"],
    execute: (args, ctx) => aprovarLoteDaPapelada(args ?? {}, ctx),
  },
];
