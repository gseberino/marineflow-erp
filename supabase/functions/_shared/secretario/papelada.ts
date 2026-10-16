// O comando *lote* (secretário, Passo 5, 16/10/2026): mostra o lote semanal da papelada e, com a chave ligada, devolve
// a confirmação que o ai-agent abre como pendência do assistente ("sim <PIN>").
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-papelada.md §3.5–3.7.
//
// Só LÊ: o lote (papelada_lote), a chave e a conferência sem aplicar (papelada_lote_conferir, aplicar=false). A
// única escrita possível aqui é fechar um lote que ficou "aplicando" há mais de 10 minutos (papelada_lote_resultado,
// que só lê a fila e grava o resultado). Nunca lança.

import { ddmm, nomeDoDia } from "./base.ts";
import type { ComandoDoSecretario } from "./comandos.ts";
import type { GrupoDoLote, ItemDeFora, ItemDoLote } from "../papelada/lote.ts";
import {
  CHAVE_DA_PAPELADA, lerFormatoDaPapelada, NOME_DA_TOOL_DO_LOTE, type ResultadoDoLote, textoDoErroDoLote, textoDoLote,
  textoDoResultado, tituloDaConfirmacao,
} from "../papelada/texto.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

/** A pendência que o ai-agent abre (ai_operator_pending_actions) quando o comando pede confirmação. */
export interface PendenciaDoSecretario {
  action_name: string;
  risk_level: "high";
  risk_reason: string;
  title: string;
  summary: string;
  payload: Record<string, unknown>;
  /** quanto tempo a confirmação vale */
  minutos: number;
}

export type ResultadoDaPapelada =
  | { tipo: "resposta"; texto: string }
  | { tipo: "seguir" }
  | { tipo: "confirmar"; texto: string; pendencia: PendenciaDoSecretario };

/** A confirmação vale 12 h (o lote vale 7 dias: depois disso, *lote* de novo). */
export const VALIDADE_DA_CONFIRMACAO_MIN = 12 * 60;
/** O lote "aplicando" há mais disto é fechado pelo banco no próximo *lote* (a tool caiu no meio). */
const APLICANDO_ESQUECIDO_MS = 10 * 60_000;

const NOME_DO_GRUPO: Record<GrupoDoLote, string> = { despesa: "despesas", transferencia: "transferências", aviso: "avisos" };

function juntarNomes(xs: string[]): string {
  return xs.length <= 1 ? xs.join("") : `${xs.slice(0, -1).join(", ")} e ${xs[xs.length - 1]}`;
}

/** O recorte pedido ("lote sem 3, 7", "lote só despesas") sobre os itens do lote. */
export function selecionarDoLote(
  itens: ItemDoLote[],
  cmd: Extract<ComandoDoSecretario, { comando: "papelada" }>,
): { escolhidos: ItemDoLote[]; recorte: string | null; erro: string | null } {
  const maior = itens.reduce((m, i) => Math.max(m, i.n), 0);
  const fora = cmd.sem.filter((n) => !itens.some((i) => i.n === n));
  if (fora.length) {
    return {
      escolhidos: [], recorte: null,
      erro: `Não há ${fora.length === 1 ? `item ${fora[0]}` : `itens ${juntarNomes(fora.map(String))}`} no lote (vai de 1 a ${maior}). Escreva *lote* para ver a lista.`,
    };
  }
  let escolhidos = itens;
  const partes: string[] = [];
  if (cmd.soGrupos?.length) {
    escolhidos = escolhidos.filter((i) => cmd.soGrupos!.includes(i.grupo));
    partes.push(`só ${juntarNomes(cmd.soGrupos.map((g) => NOME_DO_GRUPO[g]))}`);
  }
  if (cmd.semGrupos.length) {
    escolhidos = escolhidos.filter((i) => !cmd.semGrupos.includes(i.grupo));
    partes.push(`sem ${juntarNomes(cmd.semGrupos.map((g) => NOME_DO_GRUPO[g]))}`);
  }
  if (cmd.sem.length) {
    escolhidos = escolhidos.filter((i) => !cmd.sem.includes(i.n));
    const ns = [...cmd.sem].sort((a, b) => a - b).map(String);
    partes.push(`sem ${ns.length === 1 ? `o item ${ns[0]}` : `os itens ${juntarNomes(ns)}`}`);
  }
  return { escolhidos, recorte: partes.length ? partes.join(", ") : null, erro: null };
}

async function lerChave(admin: Admin): Promise<string> {
  const { data, error } = await admin.from("app_settings").select("value").eq("key", CHAVE_DA_PAPELADA).maybeSingle();
  if (error) throw new Error(String(error.code ?? "chave"));
  return lerFormatoDaPapelada(data?.value);
}

interface LoteGravado {
  id: string;
  dia: string;
  formato: "sombra" | "ligado";
  status: string;
  itens: ItemDoLote[];
  excecoes: ItemDeFora[];
  total: number;
  contagens: Record<string, unknown> | null;
  valido_ate: string;
  aplicacao_inicio: string | null;
}

/** O lote vivo do telefone: o mais novo que está pronto ou aplicando. */
async function loteVivo(admin: Admin, phone: string): Promise<LoteGravado | null> {
  const { data, error } = await admin.from("papelada_lote")
    .select("id, dia, formato, status, itens, excecoes, total, contagens, valido_ate, aplicacao_inicio")
    .eq("phone_normalized", phone).in("status", ["pronto", "aplicando"])
    .order("dia", { ascending: false }).limit(1).maybeSingle();
  if (error) throw new Error(String(error.code ?? "lote"));
  return (data ?? null) as LoteGravado | null;
}

// deno-lint-ignore no-explicit-any
async function rpc(admin: Admin, nome: string, p: Record<string, unknown>): Promise<Record<string, any> | null> {
  try {
    const { data, error } = await admin.rpc(nome, { p });
    if (error) {
      console.warn(JSON.stringify({ fn: "secretario", evento: `${nome}_falhou`, codigo: String(error.code ?? "erro") }));
      return null;
    }
    // deno-lint-ignore no-explicit-any
    return (data ?? null) as Record<string, any> | null;
  } catch (e) {
    console.warn(JSON.stringify({ fn: "secretario", evento: `${nome}_falhou`, codigo: (e as Error)?.name ?? "erro" }));
    return null;
  }
}

function minutosDoLoteGravado(l: LoteGravado): number {
  const m = Number((l.contagens as { minutos?: unknown } | null)?.minutos);
  return Number.isFinite(m) ? m : 0;
}

/** Executa *lote* / *lote sem …* / *lote só …*. Quem chama já conferiu: resumo_formato = 'novo' e é o dono. */
export async function executarPapelada(
  admin: Admin,
  cmd: Extract<ComandoDoSecretario, { comando: "papelada" }>,
  ctx: { phone: string; agora?: Date },
): Promise<ResultadoDaPapelada> {
  const resposta = (texto: string): ResultadoDaPapelada => ({ tipo: "resposta", texto });
  const agora = ctx.agora ?? new Date();
  let chave: string;
  try {
    chave = await lerChave(admin);
  } catch {
    return { tipo: "seguir" };
  }
  // chave desligada: "lote" não é comando (segue ao assistente como sempre foi)
  if (chave === "desligado") return { tipo: "seguir" };

  let lote: LoteGravado | null;
  try {
    lote = await loteVivo(admin, ctx.phone);
  } catch {
    return resposta("Não consegui ler o lote agora. Tente *lote* de novo em instantes.");
  }
  if (!lote) return resposta(textoDoErroDoLote("sem_lote"));
  const titulos = new Map(lote.itens.map((i) => [i.n, i.titulo]));

  if (lote.status === "aplicando") {
    const desde = Date.parse(String(lote.aplicacao_inicio ?? ""));
    if (Number.isFinite(desde) && agora.getTime() - desde > APLICANDO_ESQUECIDO_MS) {
      const r = await rpc(admin, "papelada_lote_resultado", { lote_id: lote.id });
      if (r?.ok) return resposta(textoDoResultado(r as unknown as ResultadoDoLote, titulos));
    }
    return resposta(textoDoErroDoLote("lote_aplicando"));
  }

  const sel = selecionarDoLote(lote.itens, cmd);
  if (sel.erro) return resposta(sel.erro);
  if (!sel.escolhidos.length) return resposta(textoDoErroDoLote("nada_escolhido"));

  // conferência SÓ DE LEITURA: o que mudou desde a montagem sai já do detalhe (o "sim" confere de novo)
  const conf = await rpc(admin, "papelada_lote_conferir", { lote_id: lote.id, ids: sel.escolhidos.map((i) => i.id) });
  if (!conf?.ok) return resposta(textoDoErroDoLote(conf?.erro ?? null));
  const saiuAgora = ((Array.isArray(conf.fora) ? conf.fora : []) as Array<{ n: number; codigo: string }>)
    .map((f) => ({ n: Number(f.n), codigo: String(f.codigo) }));
  const sairam = new Set(saiuAgora.map((s) => s.n));
  const validos = sel.escolhidos.filter((i) => !sairam.has(i.n));

  const pode = chave === "ligado" && lote.formato === "ligado" && validos.length > 0;
  const texto = textoDoLote(
    { dia: lote.dia, itens: lote.itens, fora: lote.excecoes ?? [], total: Number(lote.total) || 0, minutos: minutosDoLoteGravado(lote) },
    {
      quando: `${nomeDoDia(lote.dia).toLowerCase()}, ${ddmm(lote.dia)}`,
      escolhidos: sel.escolhidos,
      recorte: sel.recorte,
      saiuAgora,
      formato: pode ? "ligado" : "sombra",
      regrasGuardadas: Number((lote.contagens as { regras_guardadas?: unknown } | null)?.regras_guardadas) || null,
    },
  );
  if (!pode) return resposta(texto);

  const titulo = tituloDaConfirmacao(validos);
  return {
    tipo: "confirmar",
    texto,
    pendencia: {
      action_name: NOME_DA_TOOL_DO_LOTE,
      risk_level: "high",
      risk_reason: "Cria despesas e tira avisos da fila do Extrato em lote (o mesmo caminho da tela).",
      title: titulo,
      summary: `${titulo}. Itens: ${validos.map((i) => i.n).join(", ")}.`,
      payload: { lote_id: lote.id, ids: validos.map((i) => i.id), numeros: validos.map((i) => i.n) },
      minutos: VALIDADE_DA_CONFIRMACAO_MIN,
    },
  };
}
