// Histórico de documentos pelo assistente (16/11/2026): "o que mudou no ORÇ-00112?", "como estava quando foi enviado?",
// "quem mexeu no desconto?" e "desfaz isso / volta para a versão 3". Paridade com a linha do tempo da tela.
//
// O banco faz tudo (migrations 20270121100000/100100/100200): o gatilho grava cada alteração no audit_log com quem e por
// onde; documento_historico devolve o histórico já em português (R$, datas de Brasília, nomes no lugar de uuid);
// documento_restaurar simula e restaura numa transação. Aqui só se chama, se resume para o modelo e se pede o "sim".
//
// Regra da casa: leitura que falha NUNCA vira "sem alterações" — o erro vai inteiro para o modelo, que diz ao dono que
// não conseguiu ler.
import { cargosQueContam, lerRetrato, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import { recalcularOSComCascata } from "../../receivables/cascata.ts";

/** Só administrador e financeiro (as duas funções do banco conferem de novo: 42501 para os outros). */
export const CARGOS_DO_HISTORICO: Role[] = ["admin", "financial"];
const SEM_CARGO = "O histórico de documentos é só para administrador e financeiro.";

export const TIPOS_DE_DOCUMENTO = [
  "os", "compra", "cotacao", "orcamento_externo", "cliente", "embarcacao", "produto", "servico", "configuracao",
] as const;
export const MODOS_DO_HISTORICO = ["alteracoes", "versoes", "ver_versao", "comparar", "revisoes", "conferir_codigo"] as const;

/**
 * Revisão do documento (17/11/2026): a Rev. N impressa no PDF. `revisoes` lista as de um orçamento/OS (emitida, enviada
 * ao cliente, aprovada/assinada) e diz se a tela já mudou desde a última; `conferir_codigo` diz de que documento e
 * revisão é o código do rodapé ("7F3A-21C9") e se ainda é a revisão em vigor.
 */
const INSTRUCAO_DAS_REVISOES =
  "A revisão (Rev. N) só sobe quando muda o que o cliente lê, na hora de gerar o PDF. 'enviada_ao_cliente_em' diz qual " +
  "revisão o cliente recebeu; se ela for menor que a última, o cliente tem uma versão antiga — diga isso. " +
  "mudou_desde_a_ultima = o documento já mudou e o próximo PDF sai com a revisão seguinte. Para 'o que mudou da Rev. 2 " +
  "para a 3': modo comparar com versao = versao_do_historico da Rev. 2 e versao_b = a da Rev. 3.";

async function consultarRevisoes(ctx: ToolCtx, modo: "revisoes" | "conferir_codigo", documento: string) {
  const { data, error } = modo === "revisoes"
    ? await ctx.sb.rpc("documento_revisoes", { p_ref: documento })
    : await ctx.sb.rpc("documento_revisao_conferir", { p_codigo: documento });
  if (error || !data || typeof data !== "object") {
    return {
      error: `Não consegui ler as revisões de ${documento}: ${error ? umaLinha(mensagemDoBanco(error)) : "o banco não devolveu nada"}`,
      instrucao: "A leitura FALHOU: diga ao dono que não conseguiu ler. Nunca diga que não há revisão.",
    };
  }
  return { modo, ...(data as Record<string, unknown>), instrucao: INSTRUCAO_DAS_REVISOES };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Uma restauração desfaz no máximo isto de alterações de uma vez (um evento grande tem dezenas de linhas). */
const MAX_EVENTOS = 200;

const texto = (v: unknown) => (typeof v === "string" ? v.replace(/\s+/g, " ").trim() : "");
const umaLinha = (v: unknown) => String(v ?? "").replace(/\s+/g, " ").trim();
const valor = (v: unknown) => (v === null || v === undefined || v === "" ? "vazio" : String(v));

function inteiroPositivo(v: unknown): number | null | "invalido" {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isInteger(n) && n > 0 ? n : "invalido";
}

const SO_DATA_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * desde/ate em ISO. Só a data (AAAA-MM-DD) é o dia INTEIRO de Brasília: "desde 2026-11-16" começa 00:00 de Brasília e
 * "ate 2026-11-16" termina 23:59:59.999 de Brasília (sem isto o Postgres lê meia-noite UTC e o "até hoje" perde o dia).
 */
export function dataDoFiltro(v: unknown, ponta: "inicio" | "fim"): string | null | "invalido" {
  const t = texto(v);
  if (!t) return null;
  const iso = SO_DATA_RE.test(t) ? `${t}${ponta === "inicio" ? "T00:00:00-03:00" : "T23:59:59.999-03:00"}` : t;
  return Number.isNaN(new Date(iso).getTime()) ? "invalido" : iso;
}

// ─── consultar: o texto curto de cada evento ────────────────────────────────────────────────────

interface Mudanca { campo?: string; antes?: string | null; depois?: string | null; calculado?: boolean }
interface ItemDoEvento {
  item?: string; acao?: string; mudancas?: Mudanca[]; motivo?: string | null; registro_id?: string; desfazivel?: boolean;
}
interface Evento { quando?: string; quem?: string; por_onde?: string; itens?: ItemDoEvento[]; desfazivel?: boolean }

function textoDaMudanca(m: Mudanca): string {
  const campo = m.campo || "Campo";
  const temAntes = m.antes !== null && m.antes !== undefined;
  const temDepois = m.depois !== null && m.depois !== undefined;
  if (temAntes && temDepois) return `${campo} ${valor(m.antes)} → ${valor(m.depois)}`;
  if (temDepois) return `${campo} ${valor(m.depois)}`;
  if (temAntes) return `${campo} era ${valor(m.antes)}`;
  return `${campo} ${valor(null)}`;
}

/**
 * Uma linha por evento, para o modelo gastar poucos tokens:
 * "16/11/2026 14:22 · Gustavo (tela): Peça: Bomba — Quantidade 2 → 3 · Total recalculado R$ 1.200,00 → R$ 1.150,00".
 * O que o sistema recalculou (calculado) vai no fim, separado do que alguém digitou.
 */
export function linhaDoEvento(e: Evento): string {
  const partes: string[] = [];
  const recalculados: string[] = [];
  for (const it of Array.isArray(e.itens) ? e.itens : []) {
    const mudancas = Array.isArray(it.mudancas) ? it.mudancas : [];
    for (const m of mudancas.filter((m) => m.calculado)) {
      recalculados.push(`${m.campo || "Campo"} recalculado ${valor(m.antes)} → ${valor(m.depois)}`);
    }
    const digitadas = mudancas.filter((m) => !m.calculado).map(textoDaMudanca);
    const nome = it.item || "Documento";
    const motivo = texto(it.motivo) ? ` (motivo: ${texto(it.motivo)})` : "";
    if (it.acao === "alterado") {
      // Só o sistema mexeu (ex.: o total da OS depois de mudar uma peça): fica só no "recalculado".
      if (digitadas.length) partes.push(`${nome} — ${digitadas.join(", ")}${motivo}`);
      else if (motivo) partes.push(`${nome}${motivo}`);
    } else {
      partes.push(`${nome} ${it.acao || "alterado"}${digitadas.length ? ` (${digitadas.join(", ")})` : ""}${motivo}`);
    }
  }
  const cabeca = `${e.quando || "?"} · ${e.quem || "sistema"}${e.por_onde ? ` (${e.por_onde})` : ""}`;
  const corpo = partes.length ? partes.join("; ") : "só recálculo do sistema";
  return `${cabeca}: ${corpo}${recalculados.length ? ` · ${recalculados.join(", ")}` : ""}`;
}

/**
 * O modo alteracoes enxuto: as linhas e, para orçamento/OS, os registro_id DESFAZÍVEIS de cada evento (para desfazer).
 * Item sem desfazivel === true (situação, total recalculado, envio, versão, registro antigo) não vai: mandá-lo ao
 * restaurar_documento só viraria "não será desfeito".
 */
// deno-lint-ignore no-explicit-any
export function alteracoesParaOModelo(data: any, tipo: string): Record<string, unknown> {
  const eventos: Evento[] = Array.isArray(data?.eventos) ? data.eventos : [];
  const linhas = eventos.map(linhaDoEvento);
  const r: Record<string, unknown> = {
    documento: data?.documento ?? null,
    modo: "alteracoes",
    total_de_eventos: data?.total_de_eventos ?? eventos.length,
    aviso: data?.aviso ?? null,
    linhas,
  };
  if (tipo === "os") {
    r.registro_ids = eventos.map((e) =>
      (Array.isArray(e.itens) ? e.itens : []).filter((i) => i.desfazivel === true).map((i) => i.registro_id).filter(Boolean)
    );
  }
  r.instrucao = linhas.length
    ? "Responda pelas linhas (a mais recente primeiro). 'recalculado' é o sistema refazendo a conta, não alguém digitando." +
      (tipo === "os"
        ? " Para desfazer um evento: restaurar_documento com eventos = os registro_ids da MESMA posição da linha. Evento com " +
          "registro_ids vazio NÃO se desfaz (só mudou situação, total recalculado, envio ou versão, ou é registro antigo sem o " +
          "valor de antes): diga isso ao dono e, se ele quiser voltar o conteúdo, ofereça voltar para uma versão (modo versoes)."
        : "")
    : "A leitura deu certo e não há alteração registrada para este documento no período pedido.";
  return r;
}

// ─── restaurar: pedido, simulação e resumo ──────────────────────────────────────────────────────

export interface PedidoDeRestaurar {
  documento: string;
  versao: number | null;
  eventos: string[] | null;
  motivo: string | null;
}

/** Os argumentos conferidos sem banco (o preValidar, o resumo e o execute leem igual). */
export function pedidoDeRestaurar(args: Record<string, unknown> | null | undefined): PedidoDeRestaurar | { error: string } {
  const documento = texto(args?.documento);
  if (!documento) return { error: "Diga qual orçamento/OS restaurar (o número, como ORÇ-00112 ou OS-00045)." };
  const versao = inteiroPositivo(args?.versao);
  if (versao === "invalido") return { error: "A versão é um número inteiro (1, 2, 3…), como veio de consultar_historico_documento." };
  const brutos = args?.eventos;
  const eventos = Array.isArray(brutos)
    ? brutos.map((e) => texto(e)).filter(Boolean)
    : typeof brutos === "string" && brutos.trim() ? brutos.split(/[,\s]+/).filter(Boolean) : [];
  if ((versao === null) === (eventos.length === 0)) {
    return { error: "Diga UMA coisa: a versão para voltar (versao) OU as alterações a desfazer (eventos, os registro_ids da consulta)." };
  }
  const torto = eventos.find((e) => !UUID_RE.test(e));
  if (torto) return { error: `"${torto}" não é um registro_id. Use os registro_ids que consultar_historico_documento devolveu.` };
  if (eventos.length > MAX_EVENTOS) return { error: `São ${eventos.length} alterações: desfaça no máximo ${MAX_EVENTOS} de cada vez.` };
  return { documento, versao, eventos: eventos.length ? [...new Set(eventos.map((e) => e.toLowerCase()))] : null, motivo: texto(args?.motivo) || null };
}

function argumentosDaFuncao(p: PedidoDeRestaurar, simular: boolean, autor: string | null, hash: string | null = null) {
  return {
    p_ref: p.documento,
    p_versao: p.versao,
    p_eventos: p.eventos,
    p_motivo: p.motivo,
    p_simular: simular,
    p_conferir_hash: hash,
    p_autor: autor,
  };
}

// deno-lint-ignore no-explicit-any
type Simulacao = Record<string, any>;

/**
 * A simulação (p_simular = true: o banco faz tudo e desfaz). O retrato da pendência e o resumo do cartão nascem no mesmo
 * turno, com o mesmo client: lembrar a simulação por 60 s evita rodar a transação duas vezes e garante que o hash guardado
 * é o da simulação que o dono leu. Chave: client (WeakMap) + pedido + autor.
 */
const SIMULACOES = new WeakMap<object, Map<string, { em: number; resultado: Promise<Simulacao | { error: string }> }>>();

// deno-lint-ignore no-explicit-any
export function simularRestauracao(db: any, p: PedidoDeRestaurar, autor: string | null): Promise<Simulacao | { error: string }> {
  const chave = JSON.stringify([p.documento, p.versao, p.eventos, p.motivo, autor]);
  let doClient = SIMULACOES.get(db);
  if (!doClient) {
    doClient = new Map();
    SIMULACOES.set(db, doClient);
  }
  const guardada = doClient.get(chave);
  if (guardada && Date.now() - guardada.em < 60_000) return guardada.resultado;
  const resultado = (async (): Promise<Simulacao | { error: string }> => {
    const { data, error } = await db.rpc("documento_restaurar", argumentosDaFuncao(p, true, autor));
    if (error) return { error: umaLinha(mensagemDoBanco(error)) };
    if (!data || typeof data !== "object") return { error: "o banco não devolveu a simulação" };
    if (!texto((data as Simulacao).hash_do_documento)) return { error: "a simulação veio sem a marca do documento" };
    return data as Simulacao;
  })();
  doClient.set(chave, { em: Date.now(), resultado });
  // Falha não fica lembrada: a próxima tentativa simula de novo.
  resultado.then((r) => { if ("error" in r) doClient!.delete(chave); }, () => doClient!.delete(chave));
  return resultado;
}

// deno-lint-ignore no-explicit-any
function linhasDoQueMuda(d: any): string[] {
  const linhas: string[] = [];
  for (const c of Array.isArray(d?.cabecalho) ? d.cabecalho : []) {
    linhas.push(`- ${textoDaMudanca(c)}${c?.calculado ? " (recalculado)" : ""}`);
  }
  for (const i of Array.isArray(d?.itens_incluidos) ? d.itens_incluidos : []) {
    linhas.push(`- Volta: ${i?.item ?? "item"} (${valor(i?.quantidade)} un., ${valor(i?.total)})`);
  }
  for (const i of Array.isArray(d?.itens_removidos) ? d.itens_removidos : []) {
    linhas.push(`- Sai: ${i?.item ?? "item"} (${valor(i?.quantidade)} un., ${valor(i?.total)})`);
  }
  for (const i of Array.isArray(d?.itens_alterados) ? d.itens_alterados : []) {
    const m = (Array.isArray(i?.mudancas) ? i.mudancas : []) as Mudanca[];
    linhas.push(`- ${i?.item ?? "item"}: ${m.map((x) => `${textoDaMudanca(x)}${x.calculado ? " (recalculado)" : ""}`).join(", ")}`);
  }
  return linhas;
}

/** Os avisos da função ("sai do documento e leva junto: ..."): o que a restauração arrasta e não volta depois. */
// deno-lint-ignore no-explicit-any
export function avisosDaRestauracao(d: any): Array<{ item: string; aviso: string }> {
  // deno-lint-ignore no-explicit-any
  return (Array.isArray(d?.avisos) ? d.avisos : []).map((a: any) => ({ item: texto(a?.item) || "item", aviso: texto(a?.aviso) }))
    .filter((a: { aviso: string }) => a.aviso);
}

/**
 * O resumo do cartão do "sim" (buildPendingSummary, agent.ts): o que muda (cabeçalho, itens que voltam, saem e mudam), o
 * total antes → depois, se o cliente terá de assinar de novo e o que não pôde ser desfeito. Recusa (erro da simulação,
 * nada a mudar) é UMA linha "⚠️": o runAgentLoop não grava pendência (RESUMO_QUE_RESOLVE).
 */
// deno-lint-ignore no-explicit-any
export async function resumirRestauracao(admin: any, args: Record<string, unknown>, autor: string | null): Promise<string> {
  const p = pedidoDeRestaurar(args);
  if ("error" in p) return `⚠️ ${umaLinha(p.error)}`;
  const s = await simularRestauracao(admin, p, autor);
  if ("error" in s) return `⚠️ Não dá para restaurar ${p.documento}: ${umaLinha(s.error).replace(/\.$/, "")}. Nada foi alterado.`;
  const doc = texto(s.documento) || p.documento;
  if (s.o_que_muda?.sem_diferenca === true) {
    return `⚠️ Nada mudaria em ${doc}: ${texto(s.mensagem) ? umaLinha(s.mensagem).replace(/^Nada a mudar:\s*/i, "").replace(/\.$/, "") : "ele já está assim"}. Nada foi registrado.`;
  }
  const oQue = p.versao !== null
    ? `voltar para a versão ${p.versao}`
    : `desfazer ${p.eventos!.length === 1 ? "1 alteração" : `${p.eventos!.length} alterações`}`;
  const linhas = [`Restaurar *${doc}*: ${oQue}.`];
  if (p.motivo) linhas.push(`Motivo: ${p.motivo}`);
  linhas.push("O que muda:", ...linhasDoQueMuda(s.o_que_muda));
  linhas.push(`Total: *${valor(s.total_antes)}* → *${valor(s.total_depois)}*`);
  if (s.pede_nova_assinatura === true) linhas.push("O cliente terá de assinar de novo (o documento assinado muda).");
  const avisos = avisosDaRestauracao(s);
  if (avisos.length) {
    linhas.push("⚠️ *Atenção:*");
    for (const a of avisos) linhas.push(`- ${a.item}: ${a.aviso}`);
  }
  const nao = Array.isArray(s.nao_desfeito) ? s.nao_desfeito : [];
  if (nao.length) {
    linhas.push("Não será desfeito:");
    // deno-lint-ignore no-explicit-any
    for (const n of nao as any[]) linhas.push(`- ${n?.item ?? "item"}${n?.campo ? ` (${n.campo})` : ""}: ${n?.motivo ?? "mudou depois"}`);
  }
  linhas.push("As parcelas a receber são reajustadas ao novo total.");
  return linhas.join("\n");
}

function podeRestaurar(args: unknown, ctx: Pick<ToolCtx, "userRole">): { error: string } | null {
  return cargosQueContam(args, ctx).every((c) => CARGOS_DO_HISTORICO.includes(c as Role)) ? null : { error: SEM_CARGO };
}

// ─── as ferramentas ─────────────────────────────────────────────────────────────────────────────

export const historicoDocumentoTools: ToolDef[] = [
  {
    name: "consultar_historico_documento",
    description:
      "Histórico de um documento: o que mudou, quem mudou, quando e por onde (tela, assistente, cliente pelo link), com o antes → " +
      "depois de cada campo, as versões guardadas (criação, envio ao cliente, aprovação, assinatura), o conteúdo de uma versão e a " +
      "comparação entre versões. Use para 'o que mudou no ORÇ-00112', 'como estava quando foi enviado', 'quem mexeu no desconto', " +
      "'o que foi mandado ao cliente'. Valores já vêm formatados. modo alteracoes devolve uma linha por evento e, para orçamento/OS, " +
      "os registro_ids desfazíveis de cada evento (para restaurar_documento; vazio = aquele evento não se desfaz). Versões só existem para orçamento/OS. " +
      "modo revisoes: as revisões impressas no PDF (Rev. 1, 2, 3…) — qual o cliente recebeu, qual aprovou e se o documento mudou " +
      "depois da última ('o cliente tem a revisão certa do ORÇ-00136?'). modo conferir_codigo: documento = o código do rodapé do " +
      "PDF (7F3A-21C9); diz de que documento e revisão ele é e se ainda vale. Só leitura; administrador e financeiro.",
    input_schema: {
      type: "object",
      properties: {
        tipo: {
          type: "string",
          enum: [...TIPOS_DE_DOCUMENTO],
          description: "os (orçamento/OS, padrão), compra, cotacao, orcamento_externo, cliente, embarcacao, produto, servico ou configuracao.",
        },
        documento: { type: "string", description: "Como o dono disse: número (ORÇ-00112, OS-00045), código, nome ou id." },
        modo: {
          type: "string",
          enum: [...MODOS_DO_HISTORICO],
          description: "alteracoes (padrão: quem mudou o quê), versoes (lista das versões), ver_versao (o conteúdo de uma versão; sem " +
            "versao = a última), comparar (versao × versao_b; sem versao_b = o estado atual), revisoes (as Rev. N impressas no PDF: " +
            "emitida, enviada ao cliente, aprovada) ou conferir_codigo (documento = o código do rodapé do PDF).",
        },
        versao: { type: "integer", description: "Número da versão (ver_versao e comparar)." },
        versao_b: { type: "integer", description: "Segunda versão de comparar. Vazio = o estado atual." },
        desde: {
          type: "string",
          description: "Só alterações a partir daqui. AAAA-MM-DD = desde o começo desse dia (Brasília); ou data e hora ISO com fuso (2026-11-16T14:00:00-03:00).",
        },
        ate: {
          type: "string",
          description: "Só alterações até aqui. AAAA-MM-DD = até o fim desse dia (Brasília), inclusive; ou data e hora ISO com fuso.",
        },
        limite: { type: "integer", description: "Quantos eventos (mais recentes primeiro). Padrão 20, máximo 100." },
      },
      required: ["documento"],
    },
    risk: "low",
    roles: CARGOS_DO_HISTORICO,
    async execute(args, ctx) {
      if (!CARGOS_DO_HISTORICO.includes(ctx.userRole as Role)) return { error: SEM_CARGO };
      const tipo = texto(args?.tipo) || "os";
      if (!(TIPOS_DE_DOCUMENTO as readonly string[]).includes(tipo)) {
        return { error: `Tipo "${tipo}" não existe. Use: ${TIPOS_DE_DOCUMENTO.join(", ")}.` };
      }
      const documento = texto(args?.documento);
      if (!documento) return { error: "Diga qual documento (número, código ou nome)." };
      const modo = texto(args?.modo) || "alteracoes";
      if (!(MODOS_DO_HISTORICO as readonly string[]).includes(modo)) {
        return { error: `Modo "${modo}" não existe. Use: ${MODOS_DO_HISTORICO.join(", ")}.` };
      }
      if (modo === "revisoes" || modo === "conferir_codigo") {
        if (modo === "revisoes" && tipo !== "os") return { error: "Revisão só existe para orçamento/OS." };
        return await consultarRevisoes(ctx, modo, documento);
      }
      const versao = inteiroPositivo(args?.versao);
      const versaoB = inteiroPositivo(args?.versao_b);
      if (versao === "invalido" || versaoB === "invalido") return { error: "A versão é um número inteiro (1, 2, 3…)." };
      if (modo === "comparar" && versao === null) {
        return { error: "Para comparar, diga a versão (versao) e, se quiser, a segunda (versao_b); sem ela compara com o estado atual." };
      }
      const desde = dataDoFiltro(args?.desde, "inicio");
      const ate = dataDoFiltro(args?.ate, "fim");
      if (desde === "invalido" || ate === "invalido") {
        return {
          error: "desde e ate são datas ISO: só a data (2026-11-16 = o dia inteiro de Brasília) ou data e hora " +
            "(2026-11-16T14:00:00-03:00).",
        };
      }
      const limite = inteiroPositivo(args?.limite);
      const { data, error } = await ctx.sb.rpc("documento_historico", {
        p_tipo: tipo,
        p_ref: documento,
        p_modo: modo,
        p_versao: versao,
        p_versao_b: versaoB,
        p_desde: desde,
        p_ate: ate,
        p_limite: limite === "invalido" || limite === null ? 20 : Math.min(limite, 100),
      });
      // Leitura que falha nunca vira "sem alterações": o modelo recebe o erro e diz que não conseguiu ler.
      if (error) {
        return {
          error: `Não consegui ler o histórico de ${documento}: ${umaLinha(mensagemDoBanco(error))}`,
          instrucao: "A leitura FALHOU: diga ao dono que não conseguiu ler o histórico. Nunca diga que não houve alterações.",
        };
      }
      if (!data || typeof data !== "object") {
        return {
          error: `Não consegui ler o histórico de ${documento}: o banco não devolveu nada.`,
          instrucao: "A leitura FALHOU: diga ao dono que não conseguiu ler o histórico. Nunca diga que não houve alterações.",
        };
      }
      return modo === "alteracoes" ? alteracoesParaOModelo(data, tipo) : data;
    },
  },
  {
    name: "restaurar_documento",
    description:
      "Desfaz alterações de um orçamento/OS EM ABERTO ou volta para uma versão guardada. Antes, consulte com " +
      "consultar_historico_documento. Passe a versao OU os eventos (os registro_ids de um evento da consulta), nunca os dois, e o " +
      "motivo dito. O total é recalculado e as parcelas a receber reajustadas. Sempre pede o 'sim': a confirmação mostra o que muda, " +
      "o total antes e depois, o que não pôde ser desfeito e se o cliente terá de assinar de novo — não pergunte antes. Concluída, " +
      "faturada, cancelada ou agrupada não se restaura. Administrador e financeiro.",
    input_schema: {
      type: "object",
      properties: {
        documento: { type: "string", description: "Número (ORÇ-00112, OS-00045) ou id do orçamento/OS." },
        versao: { type: "integer", description: "A versão para a qual voltar (de consultar_historico_documento, modo versoes)." },
        eventos: {
          type: "array",
          items: { type: "string" },
          description: "Os registro_ids das alterações a desfazer (de consultar_historico_documento, modo alteracoes).",
        },
        motivo: { type: "string", description: "Por que restaurar, como o dono disse." },
      },
      required: ["documento"],
    },
    risk: "high",
    roles: CARGOS_DO_HISTORICO,
    gravarSolicitante: true,
    // Sem banco (o contrato do preValidar): cargo e argumentos. A simulação — que recusa documento fechado, versão que não
    // existe, total abaixo do pago e "nada mudaria" — roda no resumo do cartão, e a recusa dela vira uma linha "⚠️" sem
    // pendência (RESUMO_QUE_RESOLVE, agent.ts).
    preValidar(args, ctx) {
      const semCargo = podeRestaurar(args, ctx);
      if (semCargo) return semCargo;
      const p = pedidoDeRestaurar(args);
      return "error" in p ? p : null;
    },
    // O hash do documento na simulação que o dono leu: o "sim" é recusado pelo banco se o documento mudou no meio.
    async retratoDaPendencia(args, ctx) {
      const p = pedidoDeRestaurar(args);
      if ("error" in p) return null;
      const s = await simularRestauracao(ctx.admin, p, ctx.userId || null);
      if ("error" in s) return null;
      return {
        hash_do_documento: s.hash_do_documento,
        documento: s.documento ?? p.documento,
        total_antes: s.total_antes ?? null,
        total_depois: s.total_depois ?? null,
      };
    },
    async execute(args, ctx) {
      const semCargo = podeRestaurar(args, ctx);
      if (semCargo) return semCargo;
      const p = pedidoDeRestaurar(args);
      if ("error" in p) return p;
      // O "sim" foi sobre a simulação guardada: sem o hash dela, não restaura às cegas.
      const hash = texto(lerRetrato(args)?.hash_do_documento);
      if (!hash) return { error: "Nada foi restaurado: o pedido não guardou o retrato do documento. Peça de novo que eu simulo e mostro o que muda." };

      const { data, error } = await ctx.sb.rpc("documento_restaurar", argumentosDaFuncao(p, false, ctx.userId || null, hash));
      if (error) return { error: `Nada foi restaurado: ${umaLinha(mensagemDoBanco(error))}` };
      // deno-lint-ignore no-explicit-any
      const r = (data ?? {}) as any;
      const doc = texto(r.documento) || p.documento;
      if (r.restaurado !== true) {
        return { ok: true, restaurado: false, documento: doc, aviso: texto(r.mensagem) || `Nada mudou em ${doc}.` };
      }

      // A função já recalculou o total; as parcelas a receber são redistribuídas aqui, como depois de editar um item.
      // O id vem da própria função (documento_id): nada de procurar pelo número de novo.
      let parcelas = "As parcelas a receber foram reajustadas ao novo total.";
      try {
        const soId = UUID_RE.test(texto(r.documento_id)) ? texto(r.documento_id) : UUID_RE.test(p.documento) ? p.documento : null;
        if (!soId) throw new Error(`o banco não devolveu o id de ${doc}`);
        const c = await recalcularOSComCascata(ctx.sb, soId);
        if (c.bloqueado) {
          parcelas = `As parcelas NÃO foram reajustadas (${c.motivo ?? "total abaixo do já pago"}): confira o financeiro de ${doc}.`;
        } else if ((c.falhas ?? 0) > 0) {
          const n = c.falhas === 1 ? "1 parcela a receber NÃO foi reajustada" : `${c.falhas} parcelas a receber NÃO foram reajustadas`;
          parcelas = `${c.atualizados ? `${c.atualizados} reajustada(s), mas ` : ""}${n} (a gravação falhou): confira o financeiro de ${doc}.`;
        } else if (c.atualizados === 0) parcelas = "Nenhuma parcela a receber precisou mudar.";
      } catch (e) {
        parcelas = `O documento foi restaurado, mas as parcelas a receber NÃO foram reajustadas (${umaLinha((e as Error)?.message ?? e)}): confira o financeiro de ${doc}.`;
      }

      const versaoNova = r.versao_nova ?? null;
      const assinatura = r.pede_nova_assinatura === true ? " O cliente terá de assinar de novo." : "";
      const avisos = avisosDaRestauracao(r);
      const textoAvisos = avisos.length ? ` Atenção: ${avisos.map((a) => `${a.item} ${a.aviso}`).join("; ")}.` : "";
      const resumo = `${doc} restaurado: total ${valor(r.total_antes)} → ${valor(r.total_depois)}.` +
        `${versaoNova ? ` Guardado como versão ${versaoNova}.` : ""}${assinatura}${textoAvisos} ${parcelas}`;
      return {
        ok: true,
        restaurado: true,
        documento: doc,
        versao_nova: versaoNova,
        total_antes: r.total_antes ?? null,
        total_depois: r.total_depois ?? null,
        pede_nova_assinatura: r.pede_nova_assinatura === true,
        nao_desfeito: Array.isArray(r.nao_desfeito) ? r.nao_desfeito : [],
        avisos,
        parcelas,
        aviso: resumo,
        message: resumo,
      };
    },
  },
];
