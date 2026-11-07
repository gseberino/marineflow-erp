// O retorno rápido no Secretário (F1, P14, 01/11/2026): "Clientes esperando" e "Para conferir" na manhã; "Ainda
// esperando hoje" e o resumo do retorno ("Retorno hoje: …" ligado, "Em teste (retorno): eu teria mandado …" na sombra) na
// tarde. Spec: retorno-rapido/f1/spec.md, P14 e P9.1 (contrato C-RESUMO).
//
// Por que existe: o recibo promete ao cliente uma hora ("hoje até as 10h", "hoje até as 19h", "abre a lista dele … cedo").
// Quem cumpre é o dono, e ele só cumpre o que vê. A linha de quem espera COM PRAZO HOJE é o que sustenta essas promessas:
// ela nunca é cortada (nem pelo encurtar da manhã, nem pelo corte da tarde, nem pelas vagas garantidas da agenda). As
// outras linhas do retorno são as primeiras a sair. A linha que NÃO sustenta promessa (sombra, ou ninguém nela ouviu) é
// extra no fechamento: `fixa = false` (secretario-tarde-texto.ts).
//
// Tudo o que é dado vem do banco (retorno_resumo_do_dia: hora, prazo, rótulo; "IA pensa, sistema preenche"); aqui só se
// escreve. A função nunca devolve texto do cliente (o resumo vai ao WhatsApp do dono e entra no histórico do assistente).
// Lógica nova fica TODA aqui; as edições em secretario-texto.ts, secretario.ts, secretario-tarde-texto.ts e
// secretario-tarde.ts são de poucas linhas e com parâmetro opcional: sem o retorno, o texto é o de antes, byte a byte.
//
// (01/11/2026, correções da revisão) O que este arquivo espera do item de "esperando", além dos campos de P9.1. Os três são
// OPCIONAIS aqui e precisam entrar na P9 (pedido à sessão coordenadora, contrato C-RESUMO):
//   · `ouviu`: o cliente ouviu a promessa (o recibo ou a saudação do caso saiu 'enviada' ou 'incerta'). Com o retorno
//     ligado, só o recibo de dia útil das 07:00 às 15:29 sai ligado (seção 8); os outros casos seguem em sombra e mesmo
//     assim têm prometido_ate (a sombra simula o relógio). Ausente = não ouviu: "prometi" nunca sai sem esse dado;
//   · o prazo VIGENTE: o adiamento grava segundo_prazo (X2) e mantém prometido_ate. A P9 manda prometido_ate =
//     coalesce(segundo_prazo, prometido_ate) ou o campo `segundo_prazo`, que aqui tem preferência;
//   · `papel` (retorno_aberturas.papel): 'numero_novo' põe "número novo" ao lado do nome que a coleta 2 obteve.
// E as listas: jsonb_agg de zero linhas é NULL. Aqui null ou ausente vale lista vazia (uma lista vazia nunca apaga a
// outra); outro tipo é forma inesperada. Pedido à P9: coalesce(jsonb_agg(...), '[]').
//
// (correção) Desvio de P14.2, a levar à sessão coordenadora: a tarde lê o retorno nos TRÊS turnos, não só no fechamento.
// No 1º dia útil da semana e do mês, as 17:30 são a revisão (_shared/secretario/turno.ts), e é ela que cumpre o "hoje até
// as 19h" (a regra de P14: a linha nunca é cortada). O resumo continua só no fechamento.
//
// (correção) Teto: a linha não tem limite de itens, mas o texto gravado tem (CHECK char_length <= 4000 em
// resumo_manha.texto_novo e resumo_tarde.texto; resumo_registrar e resumo_tarde_registrar não truncam). Acima de
// TETO_DA_LINHA, os itens vão na forma curta (só o nome) e, se ainda não couber, os nomes até caber e o resto contado:
// ninguém some, e o texto inteiro fica abaixo do CHECK (o resto da mensagem, no mais curto, fica bem abaixo de 2.000).
//
// Falha fecha: erro, função ausente (antes do deploy de 16/11) ou forma inesperada = null, e a mensagem sai como antes. O
// erro e a forma inesperada vão para app_error_logs (ai-daily-briefing, retorno:<turno>), como a agenda do fechamento
// depois de 28/10 (falhouNaAgenda); a função ausente (PGRST202/42883) não, para não gravar ruído todo dia. Nunca lança.
// Não importa nada de _shared/ai/ nem de _shared/agenda/.
//
// Reverter: tirar as chamadas a lerRetorno de secretario.ts e secretario-tarde.ts (o parâmetro opcional some sozinho).
// Sem deploy, `retorno_config.modo = 'desligado'` tira "Para conferir" e o resumo, e deixa na linha só quem já ouviu a
// promessa: ele continua esperando, e nada mais o avisa (o vigia para).

import { ddmm, diaDaSemana, diasEntre, quandoEmPalavras, umaLinha } from "../_shared/secretario/base.ts";
import { diaBR, horaBR } from "../_shared/pdf/datas.ts";
import { logEdgeError } from "../_shared/log-error.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export interface EsperandoDoRetorno {
  phone: string;
  rotulo: string;
  desde: string;
  prometido_ate: string | null;
  venceu: boolean;
  com_prazo_hoje: boolean;
  /** (correção) o X2 do adiamento; quando vem, é ele a promessa de pé. Ausente = prometido_ate já é o prazo vigente */
  segundo_prazo?: string | null;
  /** (correção) o cliente ouviu a promessa (recibo ou saudação do caso 'enviada' ou 'incerta'). Ausente = não ouviu */
  ouviu?: boolean;
  /** (correção) retorno_aberturas.papel; 'numero_novo' põe "número novo" ao lado do nome dito */
  papel?: string | null;
}
export interface ConferirDoRetorno {
  phone: string;
  rotulo: string;
  motivo: "parar_largo" | "opt_out" | "atraso_longo";
  desde: string;
}
export interface RetornoDaManha {
  modo: "sombra" | "ligado" | "desligado";
  esperando: EsperandoDoRetorno[];
  esperando_mais: number;
  conferir: ConferirDoRetorno[];
  conferir_mais: number;
}
export interface RetornoDoFechamento {
  modo: "sombra" | "ligado" | "desligado";
  esperando: EsperandoDoRetorno[];
  recebidos: number;
  no_prazo: number;
  adiados: number;
  sem_palavra: number;
  na_queda: number;
  sombra: { teria_mandado: number; por_papel: Record<string, number>; respondeu_antes: number };
  alongadas: Array<{ faixa: string; de: { dias: number; hora: string }; para: { dias: number; hora: string }; casos: number; pct: number }>;
}

/** Quantos sem prazo hoje a manhã nomeia (o resto vira "e mais N"). Os com prazo hoje vão todos, sem limite. */
export const SEM_PRAZO_NA_MANHA = 3;
/** Quantos "Para conferir" a manhã nomeia. */
export const CONFERIR_NA_MANHA = 3;
/**
 * (correção) Até quantos caracteres a linha de quem espera vai inteira. Só a última defesa: o caso comum (até ~20 casos)
 * nunca chega perto. Acima, a forma curta; com o resto da mensagem, o texto fica abaixo dos 4.000 do CHECK do banco.
 */
export const TETO_DA_LINHA = 2000;

const MODOS = new Set(["sombra", "ligado", "desligado"]);
const MOTIVOS_DE_CONFERIR = new Set(["parar_largo", "opt_out", "atraso_longo"]);
/** "A função ainda não existe" (antes do deploy de 16/11): não vai a app_error_logs. */
const FUNCAO_AUSENTE = new Set(["PGRST202", "42883"]);

// ─── Leitura (C-RESUMO) ─────────────────────────────────────────────────────────────────────────

function objeto(x: unknown): Record<string, unknown> | null {
  return x && typeof x === "object" && !Array.isArray(x) ? x as Record<string, unknown> : null;
}

/** Contagem do banco: inteiro ≥ 0; qualquer outra coisa = 0. */
function contagem(x: unknown): number {
  const v = typeof x === "number" ? x : typeof x === "string" && x.trim() !== "" ? Number(x) : NaN;
  return Number.isFinite(v) ? Math.max(0, Math.trunc(v)) : 0;
}

function textoOu(x: unknown, padrao: string): string {
  return typeof x === "string" ? x : padrao;
}

/**
 * (correção) Uma lista do banco: null ou ausente = vazia (jsonb_agg de zero linhas é NULL, e a lista de conferir fica vazia
 * na maioria dos dias); outro tipo (objeto, texto) = null, forma inesperada.
 */
function listaOuVazia(x: unknown): unknown[] | null {
  return x == null ? [] : Array.isArray(x) ? x : null;
}

/**
 * O rótulo numa linha só, sem negrito/itálico do WhatsApp nem emoji (o nome que o número novo disse é texto dele, mesmo
 * filtrado pelo banco), até 40 caracteres. "(número de 2 clientes)" perde os parênteses: a linha já põe os dela.
 */
function limparRotulo(x: unknown): string {
  const s = umaLinha(
    textoOu(x, "").replace(/[\p{Extended_Pictographic}\u{FE0F}\u{200D}]/gu, "").replace(/[*_~`]/g, ""),
    40,
  );
  const semParenteses = /^\((.+)\)$/.exec(s)?.[1]?.trim() ?? s;
  return semParenteses || "sem nome";
}

/** Um item de "esperando". Só o que não é objeto fica de fora; o resto é aproveitado (uma promessa não some por um campo). */
function itemEsperando(x: unknown): EsperandoDoRetorno | null {
  const o = objeto(x);
  if (!o) return null;
  const venceu = o.venceu === true;
  return {
    phone: textoOu(o.phone, ""),
    rotulo: limparRotulo(o.rotulo),
    desde: textoOu(o.desde, ""),
    prometido_ate: typeof o.prometido_ate === "string" && o.prometido_ate ? o.prometido_ate : null,
    venceu,
    // venceu já é "com prazo hoje" pela definição do banco (P9.1): na dúvida, o item fica entre os que nunca saem
    com_prazo_hoje: o.com_prazo_hoje === true || venceu,
    // (correção) os campos que a P9 acrescenta ao C-RESUMO; ausentes, o item é o de antes (e "não ouviu")
    ...(typeof o.segundo_prazo === "string" && o.segundo_prazo ? { segundo_prazo: o.segundo_prazo } : {}),
    ...(o.ouviu === true ? { ouviu: true } : {}),
    ...(typeof o.papel === "string" && o.papel ? { papel: o.papel } : {}),
  };
}

function itemConferir(x: unknown): ConferirDoRetorno | null {
  const o = objeto(x);
  if (!o || typeof o.motivo !== "string" || !MOTIVOS_DE_CONFERIR.has(o.motivo)) return null;
  return {
    phone: textoOu(o.phone, ""),
    rotulo: limparRotulo(o.rotulo),
    motivo: o.motivo as ConferirDoRetorno["motivo"],
    desde: textoOu(o.desde, ""),
  };
}

function listaDeEsperando(x: unknown[]): EsperandoDoRetorno[] {
  return x.map(itemEsperando).filter((e): e is EsperandoDoRetorno => !!e);
}

/** A manhã lida, conferida. Forma inesperada = null (a manhã sai como antes). */
export function retornoDaManha(data: unknown): RetornoDaManha | null {
  const d = objeto(data);
  if (!d || "erro" in d || typeof d.modo !== "string" || !MODOS.has(d.modo)) return null;
  const esperando = listaOuVazia(d.esperando);
  const conferirCru = listaOuVazia(d.conferir);
  if (!esperando || !conferirCru) return null;
  const conferir = conferirCru.map(itemConferir);
  return {
    modo: d.modo as RetornoDaManha["modo"],
    esperando: listaDeEsperando(esperando),
    esperando_mais: contagem(d.esperando_mais),
    conferir: conferir.filter((c): c is ConferirDoRetorno => !!c),
    // um item de motivo desconhecido não some calado: entra no "e mais N"
    conferir_mais: contagem(d.conferir_mais) + conferir.filter((c) => !c).length,
  };
}

function prazoDoAlongamento(x: unknown): { dias: number; hora: string } | null {
  const o = objeto(x);
  if (!o || typeof o.dias !== "number" || !Number.isInteger(o.dias) || o.dias < 0) return null;
  if (typeof o.hora !== "string" || !/^\d{1,2}:\d{2}(:\d{2})?$/.test(o.hora)) return null;
  return { dias: o.dias, hora: o.hora };
}

/** O fechamento lido, conferido. Forma inesperada = null (a tarde sai como antes). */
export function retornoDoFechamento(data: unknown): RetornoDoFechamento | null {
  const d = objeto(data);
  if (!d || "erro" in d || typeof d.modo !== "string" || !MODOS.has(d.modo)) return null;
  const esperando = listaOuVazia(d.esperando);
  if (!esperando) return null;
  const s = objeto(d.sombra) ?? {};
  const porPapel: Record<string, number> = {};
  for (const [papel, n] of Object.entries(objeto(s.por_papel) ?? {})) {
    const v = contagem(n);
    if (v > 0) porPapel[papel] = v;
  }
  const alongadas: RetornoDoFechamento["alongadas"] = [];
  for (const x of Array.isArray(d.alongadas) ? d.alongadas : []) {
    const a = objeto(x);
    const de = prazoDoAlongamento(a?.de);
    const para = prazoDoAlongamento(a?.para);
    const pct = typeof a?.pct === "number" ? a.pct : typeof a?.pct === "string" ? Number(a.pct) : NaN;
    if (!a || typeof a.faixa !== "string" || !a.faixa || !de || !para || !Number.isFinite(pct)) continue;
    alongadas.push({ faixa: a.faixa, de, para, casos: contagem(a.casos), pct });
  }
  return {
    modo: d.modo as RetornoDoFechamento["modo"],
    esperando: listaDeEsperando(esperando),
    recebidos: contagem(d.recebidos),
    no_prazo: contagem(d.no_prazo),
    adiados: contagem(d.adiados),
    sem_palavra: contagem(d.sem_palavra),
    na_queda: contagem(d.na_queda),
    sombra: { teria_mandado: contagem(s.teria_mandado), por_papel: porPapel, respondeu_antes: contagem(s.respondeu_antes) },
    alongadas,
  };
}

/**
 * retorno_resumo_do_dia(p_turno, p_agora) — contrato C-RESUMO (P9.1). Erro, função ausente (antes do deploy) ou forma
 * inesperada = null; o console leva só o código, nunca o conteúdo. (correção) O erro (fora a função ausente) e a forma
 * inesperada vão também para app_error_logs (ai-daily-briefing, retorno:<turno>): sem isso, a linha que sustenta a promessa
 * sumiria calada, como a agenda do fechamento em 28/10. Nunca lança.
 */
export async function lerRetorno(admin: Admin, turno: "manha", agora: Date): Promise<RetornoDaManha | null>;
export async function lerRetorno(admin: Admin, turno: "fechamento", agora: Date): Promise<RetornoDoFechamento | null>;
export async function lerRetorno(
  admin: Admin, turno: "manha" | "fechamento", agora: Date,
): Promise<RetornoDaManha | RetornoDoFechamento | null>;
export async function lerRetorno(
  admin: Admin, turno: "manha" | "fechamento", agora: Date,
): Promise<RetornoDaManha | RetornoDoFechamento | null> {
  try {
    const { data, error } = await admin.rpc("retorno_resumo_do_dia", { p_turno: turno, p_agora: agora.toISOString() });
    if (error) throw error;
    const r = turno === "manha" ? retornoDaManha(data) : retornoDoFechamento(data);
    if (!r && data != null) {
      console.warn(JSON.stringify({ fn: "ai-daily-briefing", retorno: "forma_inesperada", turno }));
      await logEdgeError(admin, {
        context: "ai-daily-briefing",
        action: `retorno:${turno}`,
        message: `retorno: retorno_resumo_do_dia (${turno}) devolveu uma forma inesperada; a linha de quem espera ficou de fora`,
        details: { codigo: "forma_inesperada" },
      });
    } else if (r) {
      // (correção) a lista nula vale vazia; o aviso diz à P9 que falta o coalesce
      const nulas = (turno === "manha" ? ["esperando", "conferir"] : ["esperando"])
        .filter((k) => (data as Record<string, unknown>)[k] == null);
      if (nulas.length) console.warn(JSON.stringify({ fn: "ai-daily-briefing", retorno: "lista_nula", turno, campos: nulas }));
    }
    return r;
  } catch (e) {
    const codigo = String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro");
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", retorno: "leitura_falhou", turno, codigo }));
    if (!FUNCAO_AUSENTE.has(codigo)) {
      await logEdgeError(admin, {
        context: "ai-daily-briefing",
        action: `retorno:${turno}`,
        message: `retorno: a leitura de retorno_resumo_do_dia (${turno}) falhou${codigo === "57014" ? " por tempo esgotado" : ""}: ${
          String((e as { message?: unknown })?.message ?? codigo).slice(0, 300)}`,
        details: { codigo },
        error: e,
      });
    }
    return null;
  }
}

// ─── Pedaços de texto ───────────────────────────────────────────────────────────────────────────

function instante(s: string | null): Date | null {
  if (!s) return null;
  const t = Date.parse(s);
  return Number.isFinite(t) ? new Date(t) : null;
}

/** "19h" na hora cheia, "19:30" fora dela (a mesma forma do {hora} dos textos ao cliente, P3). */
export function horaDaPromessa(d: Date): string {
  const [h, m] = horaBR(d).split(":");
  return m === "00" ? `${Number(h)}h` : `${h}:${m}`;
}

/** `desde`: "21:40" se for hoje, "ontem 16:02" se for ontem, senão "13/10 09:14". Data inválida = null. */
export function desdeEmPalavras(desde: string, agora: Date): string | null {
  const d = instante(desde);
  if (!d) return null;
  const dia = diaBR(d);
  const n = diasEntre(dia, diaBR(agora));
  if (n === 0) return horaBR(d);
  if (n === 1) return `ontem ${horaBR(d)}`;
  return `${ddmm(dia)} ${horaBR(d)}`;
}

function plural(n: number, um: string, varios: string): string {
  return `${n} ${n === 1 ? um : varios}`;
}

/** "venceu ontem" (o prazo era de ontem), "venceu hoje", "venceu 13/10"; sem prazo lido, só "venceu". */
function venceuQuando(prometido: Date | null, hoje: string): { texto: string; hoje: boolean } {
  if (!prometido) return { texto: "venceu", hoje: false };
  const dia = diaBR(prometido);
  const n = diasEntre(dia, hoje);
  if (n === 0) return { texto: "venceu hoje", hoje: true };
  if (n === 1) return { texto: "venceu ontem", hoje: false };
  return { texto: `venceu ${ddmm(dia)}`, hoje: false };
}

/** "hoje", "amanhã", "segunda (09/11)", "ontem" ou "09/11": o dia do prazo visto de hoje. */
function diaDoPrazo(prometido: Date, hoje: string): string {
  const dia = diaBR(prometido);
  const n = diasEntre(hoje, dia);
  return n === -1 ? "ontem" : n < 0 ? ddmm(dia) : quandoEmPalavras(dia, hoje);
}

function comParenteses(rotulo: string, partes: Array<string | null>): string {
  const p = partes.filter((x): x is string => !!x);
  return p.length ? `${rotulo} (${p.join(", ")})` : rotulo;
}

/** (correção) A promessa de pé: a do adiamento (X2), se houve; senão a do recibo. */
function prazoVigente(e: EsperandoDoRetorno): Date | null {
  return instante(e.segundo_prazo ?? null) ?? instante(e.prometido_ate);
}

/** (correção) "número novo" ao lado do nome que a coleta 2 obteve: sem ele, "Ana" se leria como a cliente cadastrada. */
function qualificador(e: EsperandoDoRetorno): string | null {
  return e.papel === "numero_novo" && e.rotulo !== "número novo" ? "número novo" : null;
}

/** Na sombra nada foi prometido: só "desde" (e, fora da sombra, a `marca` de quem não ouviu). */
function itemNaSombra(e: EsperandoDoRetorno, agora: Date, marca: string | null = null): string {
  const desde = desdeEmPalavras(e.desde, agora);
  return comParenteses(e.rotulo, [qualificador(e), desde ? `desde ${desde}` : null, marca]);
}

/**
 * (correção) Com o retorno ligado ou desligado, quem NÃO ouviu promessa: o caso ficou em sombra (o tipo dele ainda não liga,
 * seção 8), e o prazo que o banco tem é o simulado. Sai como na sombra, com "nada prometido" onde a forma ligada diria
 * "prometi" ou "venceu".
 */
function itemQueNaoOuviu(e: EsperandoDoRetorno, agora: Date): string {
  return itemNaSombra(e, agora, prazoVigente(e) || e.venceu ? "nada prometido" : null);
}

/** Manhã, ligado: "Paulo (venceu ontem, prometi até 19h)" · "Ana (número novo, desde ontem 21:40, prometi hoje até 10h)". */
function itemDaManhaLigado(e: EsperandoDoRetorno, agora: Date): string {
  const hoje = diaBR(agora);
  const prazo = prazoVigente(e);
  if (e.venceu) {
    return comParenteses(e.rotulo, [qualificador(e), venceuQuando(prazo, hoje).texto, prazo ? `prometi até ${horaDaPromessa(prazo)}` : null]);
  }
  const desde = desdeEmPalavras(e.desde, agora);
  return comParenteses(e.rotulo, [
    qualificador(e),
    desde ? `desde ${desde}` : null,
    prazo ? `prometi ${diaDoPrazo(prazo, hoje)} até ${horaDaPromessa(prazo)}` : null,
  ]);
}

/** Fechamento, ligado: "Paulo (prometi até 19h)" · "Ana (venceu ontem)" · "Rui (venceu hoje às 10h)". */
function itemDoFechamentoLigado(e: EsperandoDoRetorno, agora: Date): string {
  const hoje = diaBR(agora);
  const prazo = prazoVigente(e);
  if (e.venceu) {
    const v = venceuQuando(prazo, hoje);
    return comParenteses(e.rotulo, [qualificador(e), v.hoje && prazo ? `${v.texto} às ${horaDaPromessa(prazo)}` : v.texto]);
  }
  if (prazo) {
    const dia = diaDoPrazo(prazo, hoje);
    return comParenteses(e.rotulo, [qualificador(e), `prometi ${dia === "hoje" ? "" : `${dia} `}até ${horaDaPromessa(prazo)}`]);
  }
  const desde = desdeEmPalavras(e.desde, agora);
  return comParenteses(e.rotulo, [qualificador(e), desde ? `desde ${desde}` : null]);
}

function digitos(s: string): string {
  return s.replace(/\D/g, "");
}

/**
 * (correção) A linha com teto: até TETO_DA_LINHA, inteira; acima, os itens na forma curta (só o rótulo); ainda acima, os
 * nomes até caber (os primeiros: a ordem do banco põe os vencidos e os com prazo antes) e o resto contado pela `cauda`.
 * Ninguém some: quem não é nomeado é contado.
 */
function linhaComTeto(
  cabeca: string,
  itens: Array<{ longo: string; curto: string }>,
  cauda: (fora: number, nomeados: number) => string[],
): string | null {
  const montar = (partes: string[]) => (partes.length ? `${cabeca} ${partes.join(" · ")}.` : null);
  const inteira = montar([...itens.map((i) => i.longo), ...cauda(0, itens.length)]);
  if (!inteira || inteira.length <= TETO_DA_LINHA) return inteira;
  const curta = montar([...itens.map((i) => i.curto), ...cauda(0, itens.length)]);
  if (curta && curta.length <= TETO_DA_LINHA) return curta;
  for (let n = itens.length - 1; n > 0; n--) {
    const l = montar([...itens.slice(0, n).map((i) => i.curto), ...cauda(itens.length - n, n)]);
    if (l && l.length <= TETO_DA_LINHA) return l;
  }
  return montar(cauda(itens.length, 0));
}

// ─── Manhã ──────────────────────────────────────────────────────────────────────────────────────

/**
 * As duas linhas do retorno na manhã. `jaNaLista` = fonesDaManha(sel): quem já tem letra na manhã.
 *   · esperando: TODOS os com prazo hoje (sem limite e sem exclusão: repetir quem já tem letra é melhor que sumir com
 *     uma promessa), depois até 3 sem prazo fora de `jaNaLista`, e "e mais N" (os sem prazo que não couberam +
 *     esperando_mais). (correção) "prometi" só para quem ouviu; acima do teto, a forma curta;
 *   · conferir: até 3, e "e mais N".
 * (correção) Desligado: só quem já ouviu a promessa (ninguém mais o avisa), e sem "Para conferir". Nulo ou nada a dizer = null.
 */
export function linhasDaManha(
  r: RetornoDaManha | null, jaNaLista: Set<string>, agora: Date, extra: ExtraDaManha | null = null,
): { esperando: string | null; conferir: string | null } {
  if (!r) return { esperando: null, conferir: linhaDeContatos(extra) };
  const sombra = r.modo === "sombra";
  const desligado = r.modo === "desligado";
  const todos = desligado ? r.esperando.filter((e) => e.ouviu === true) : r.esperando;
  const fones = new Set([...jaNaLista].map(digitos));
  const comPrazo = todos.filter((e) => e.com_prazo_hoje);
  const semPrazo = todos.filter((e) => !e.com_prazo_hoje && !(digitos(e.phone) && fones.has(digitos(e.phone))));
  const semPrazoNomeados = semPrazo.slice(0, SEM_PRAZO_NA_MANHA);
  // no desligado, esperando_mais não entra: o banco conta ali também quem não ouviu
  const mais = semPrazo.length - semPrazoNomeados.length + (desligado ? 0 : r.esperando_mais);
  const forma = (e: EsperandoDoRetorno) =>
    sombra ? itemNaSombra(e, agora) : e.ouviu ? itemDaManhaLigado(e, agora) : itemQueNaoOuviu(e, agora);
  // `fora` sai do fim da lista: primeiro os sem prazo nomeados, depois os com prazo
  const cauda = (fora: number, nomeados: number): string[] => {
    const foraSem = Math.min(fora, semPrazoNomeados.length);
    const foraCom = fora - foraSem;
    const sem = mais + foraSem;
    if (sombra) {
      const n = foraCom + sem;
      return n > 0 ? [nomeados ? `e mais ${n}` : plural(n, "contato", "contatos")] : [];
    }
    const partes: string[] = [];
    if (foraCom > 0) partes.push(nomeados ? `e mais ${foraCom} com prazo hoje` : `${foraCom} com prazo hoje`);
    // sem nenhum nomeado (todos os sem prazo já têm letra), a contagem fica sozinha
    if (sem > 0) partes.push(nomeados || foraCom ? `e mais ${sem} sem prazo` : `${plural(sem, "contato", "contatos")} sem prazo`);
    return partes;
  };
  const cabeca = sombra
    ? "Clientes esperando (em teste, nada foi prometido):"
    : desligado ? "Clientes esperando (retorno desligado):" : "Clientes esperando:";
  const esperando = linhaComTeto(cabeca, [...comPrazo, ...semPrazoNomeados].map((e) => ({ longo: forma(e), curto: e.rotulo })), cauda);
  // (F2, P12) a palavra no fim de "Clientes esperando"; os contatos junto de "Para conferir", os primeiros a sair
  const conferir = [desligado ? null : linhaDeConferir(r, agora), linhaDeContatos(extra)].filter((l): l is string => !!l);
  return { esperando: esperando && extra?.palavra ? `${esperando} · *retorno*` : esperando, conferir: conferir.length ? conferir.join("\n") : null };
}

function porQueConferir(c: ConferirDoRetorno, agora: Date): string {
  if (c.motivo === "parar_largo") return "pediu para parar?";
  if (c.motivo === "opt_out") return "pediu PARAR e voltou a escrever";
  const d = instante(c.desde);
  const n = d ? diasEntre(diaBR(d), diaBR(agora)) : 0;
  return n <= 0 ? "escreveu na queda" : n === 1 ? "escreveu na queda, ontem" : `escreveu na queda, há ${n} dias`;
}

/** "Para conferir: Paulo (pediu para parar?) · número novo (pediu PARAR e voltou a escrever) · e mais 1." */
function linhaDeConferir(r: RetornoDaManha, agora: Date): string | null {
  const nomeados = r.conferir.slice(0, CONFERIR_NA_MANHA);
  const mais = r.conferir.length - nomeados.length + r.conferir_mais;
  const partes = nomeados.map((c) => `${c.rotulo} (${porQueConferir(c, agora)})`);
  if (mais > 0) partes.push(partes.length ? `e mais ${mais}` : plural(mais, "contato", "contatos"));
  return partes.length ? `Para conferir: ${partes.join(" · ")}.` : null;
}

// ─── Fechamento (e as revisões da tarde) ────────────────────────────────────────────────────────

/**
 * As linhas do retorno na tarde (fechamento e, desde a correção, as revisões).
 *   · esperando ("Ainda esperando hoje"): TODOS os itens (o banco já manda só os com prazo hoje); acima do teto, a forma curta.
 *     (correção) "prometi" só para quem ouviu;
 *   · resumo: o extra (o primeiro a sair). Sem palavra de ação (*ver retorno* é da F2);
 *   · fixa (correção): a linha sustenta promessa (alguém nela ouviu, fora da sombra). Nunca sai. Com fixa = false (sombra,
 *     ou ninguém que ouviu) ela é extra: a segunda a sair, depois do resumo (secretario-tarde-texto.ts, textoDaTarde).
 * (correção) Desligado: só quem já ouviu a promessa, e sem resumo. Nulo ou nada a dizer = null.
 */
export function linhasDoFechamento(
  r: RetornoDoFechamento | null, agora: Date, extra: ExtraDoFechamento | null = null,
): { esperando: string | null; resumo: string | null; fixa: boolean; mandei?: string | null; extras?: string[] } {
  if (!r) return { esperando: null, resumo: null, fixa: false };
  const sombra = r.modo === "sombra";
  const desligado = r.modo === "desligado";
  const itens = desligado ? r.esperando.filter((e) => e.ouviu === true) : r.esperando;
  const forma = (e: EsperandoDoRetorno) =>
    sombra ? itemNaSombra(e, agora) : e.ouviu ? itemDoFechamentoLigado(e, agora) : itemQueNaoOuviu(e, agora);
  const cabeca = sombra
    ? "Ainda esperando hoje (em teste):"
    : desligado ? "Ainda esperando hoje (retorno desligado):" : "Ainda esperando hoje:";
  const esperando = linhaComTeto(cabeca, itens.map((e) => ({ longo: forma(e), curto: e.rotulo })),
    (fora, nomeados) => (fora > 0 ? [nomeados ? `e mais ${fora}` : plural(fora, "contato", "contatos")] : []));
  const fixa = !!esperando && !sombra && itens.some((e) => e.ouviu === true);
  const resumo = desligado ? null : linhaDoResumo(r, agora);
  const base = { esperando, resumo: resumo && sombra && extra?.palavra ? `${resumo} · *ver retorno*` : resumo, fixa };
  if (!extra) return base;
  return { ...base, mandei: linhaDoMandei(extra), extras: linhasDoExtra(extra) };
}

/**
 * Os papéis do "eu teria mandado", na ordem fixa: clientes, números de mais de um cliente, números novos; depois os que
 * nunca deveriam receber (público errado: o dono precisa ver pelo nome), e o que sobrar como "outros".
 */
const PAPEIS: Array<[string, string, string]> = [
  ["cliente", "a cliente", "a clientes"],
  ["cliente_ambiguo", "a número de mais de um cliente", "a números de mais de um cliente"],
  ["numero_novo", "a número novo", "a números novos"],
  ["cliente_parceiro", "a cliente de parceiro", "a clientes de parceiro"],
  ["contato_conhecido", "a contato conhecido", "a contatos conhecidos"],
  ["fornecedor", "a fornecedor", "a fornecedores"],
];

function porPapel(s: RetornoDoFechamento["sombra"]): string[] {
  // sem nenhum papel contado pelo banco, a frase fica sem a divisão (não se inventa "a outros")
  if (!Object.keys(s.por_papel).length) return [];
  const partes: string[] = [];
  let somados = 0;
  for (const [papel, um, varios] of PAPEIS) {
    const n = s.por_papel[papel] ?? 0;
    if (n > 0) partes.push(plural(n, um, varios));
    somados += n;
  }
  const conhecidos = new Set(PAPEIS.map(([p]) => p));
  let outros = 0;
  for (const [papel, n] of Object.entries(s.por_papel)) if (!conhecidos.has(papel)) outros += n;
  // o que o banco contou e não pôs em papel nenhum também aparece (a soma fecha com o total)
  outros += Math.max(0, s.teria_mandado - somados - outros);
  if (outros > 0) partes.push(plural(outros, "a outro", "a outros"));
  return partes;
}

/** "quem escreve de manhã" etc. (as faixas de B.4.1; fora_ate e promessa_dono não são calibradas). */
const FAIXAS: Record<string, string> = {
  manha_cedo: "quem escreve de manhã",
  meio: "quem escreve no meio do dia",
  tarde: "quem escreve à tarde",
  noite: "quem escreve à noite",
  folga: "quem escreve em dia sem expediente",
  pressa: "quem escreve com pressa",
};

/**
 * O que o cliente da faixa passa a ouvir. `dias` conta a partir do dia que a tabela do P3 daria: o mesmo dia (manhã, meio,
 * pressa; a noite ouve na manhã seguinte, "hoje"), o próximo dia útil (tarde: "amanhã") ou o 1º dia útil (folga).
 */
function oQueOuve(faixa: string, para: { dias: number; hora: string }): string {
  const [h, m] = para.hora.split(":");
  const hora = m === "00" ? `${Number(h)}h` : `${h.padStart(2, "0")}:${m}`;
  const base = faixa === "tarde" ? 1 : faixa === "folga" ? -1 : 0;
  if (base === -1) {
    return para.dias === 0 ? `no próximo dia útil até as ${hora}` : `em ${para.dias + 1} dias úteis até as ${hora}`;
  }
  const dias = base + para.dias;
  return dias === 0 ? `hoje até as ${hora}` : dias === 1 ? `amanhã até as ${hora}` : `em ${dias} dias úteis até as ${hora}`;
}

/** `Prazo alongado: quem escreve de manhã passa a ouvir "amanhã até as 10h" (você cumpriu 72% de 25).` */
function linhaDoAlongamento(a: RetornoDoFechamento["alongadas"][number]): string {
  const quem = FAIXAS[a.faixa] ?? `quem escreve (${umaLinha(a.faixa, 20)})`;
  const pct = Math.round(a.pct <= 1 ? a.pct * 100 : a.pct);
  return `Prazo alongado: ${quem} passa a ouvir "${oQueOuve(a.faixa, a.para)}" (você cumpriu ${pct}% de ${a.casos}).`;
}

function linhaDoResumo(r: RetornoDoFechamento, agora: Date): string | null {
  const frases: string[] = [];
  if (r.modo === "ligado" && r.recebidos > 0) {
    const queda = r.na_queda > 0 ? ` (${r.na_queda} ${r.na_queda === 1 ? "venceu" : "venceram"} com o WhatsApp fora.)` : "";
    frases.push(
      `Retorno hoje: ${plural(r.recebidos, "recebido", "recebidos")}, ${r.no_prazo} no prazo, ` +
        `${plural(r.adiados, "adiado", "adiados")}, ${r.sem_palavra} sem palavra.${queda}`,
    );
  }
  const s = r.sombra;
  if (r.modo === "sombra" && (s.teria_mandado > 0 || s.respondeu_antes > 0)) {
    const papeis = porPapel(s);
    const teria = s.teria_mandado > 0
      ? `eu teria mandado ${plural(s.teria_mandado, "recibo", "recibos")} hoje${papeis.length ? ` (${papeis.join(", ")})` : ""}`
      : "eu não teria mandado nenhum recibo hoje";
    const antes = s.respondeu_antes > 0 ? `; você respondeu ${s.respondeu_antes} antes` : "";
    frases.push(`Em teste (retorno): ${teria}${antes}.`);
  }
  // o banco só manda as alongadas na sexta; aqui também se confere (a frase é da semana)
  if (r.alongadas.length && diaDaSemana(diaBR(agora)) === 5) frases.push(...r.alongadas.map(linhaDoAlongamento));
  return frases.length ? frases.join(" ") : null;
}

// ─── O que a F2 acrescenta (P12): retorno_resumo_extra ───────────────────────────────────────────────────────────────

export interface ExtraDaManha {
  palavra: boolean;
  contatos: { vendedores: number; conhecidos: number };
}
export interface MandeiSozinho {
  letra: string;
  rotulo: string;
  tipo_curto: string;
  saida_id: string;
}
export interface SemanaDoRetorno {
  recibos: number;
  recibo_12min: number;
  hora_cumprida: number;
  hora_casos: number;
  vencida_sem_aviso: number;
  insistencia: number;
  toques: number;
  dias_uteis: number;
}
export interface ExtraDoFechamento {
  palavra: boolean;
  mandei: MandeiSozinho[];
  mandei_mais: number;
  promovidos: string[];
  rebaixados: Array<{ tipo_curto: string; motivo: string }>;
  suspensos: string[];
  semana: SemanaDoRetorno | null;
}

/** Abaixo disto, os números sem percentual. */
const MINIMO_PARA_PERCENTUAL = 20;

const POR_QUE_REBAIXOU: Record<string, string> = {
  errado: "você marcou errado",
  queixa: "houve queixa",
  opt_out: "pediu para parar",
  validador: "o validador barrou 3 vezes",
};

export async function lerExtra(admin: Admin, turno: "manha", agora: Date): Promise<ExtraDaManha | null>;
export async function lerExtra(admin: Admin, turno: "fechamento", agora: Date): Promise<ExtraDoFechamento | null>;
export async function lerExtra(admin: Admin, turno: "manha" | "fechamento", agora: Date): Promise<ExtraDaManha | ExtraDoFechamento | null> {
  try {
    const { data, error } = await admin.rpc("retorno_resumo_extra", { p_turno: turno, p_agora: agora.toISOString() });
    if (error) throw error;
    const o = objeto(data);
    if (!o) return null;
    if (turno === "manha") {
      const c = objeto(o.contatos);
      return { palavra: o.palavra === true, contatos: { vendedores: contagem(c?.vendedores), conhecidos: contagem(c?.conhecidos) } };
    }
    return {
      palavra: o.palavra === true,
      mandei: (listaOuVazia(o.mandei) ?? []).flatMap((x) => {
        const m = objeto(x);
        return m && typeof m.letra === "string"
          ? [{ letra: m.letra, rotulo: limparRotulo(m.rotulo), tipo_curto: textoOu(m.tipo_curto, ""), saida_id: textoOu(m.saida_id, "") }]
          : [];
      }),
      mandei_mais: contagem(o.mandei_mais),
      promovidos: (listaOuVazia(o.promovidos) ?? []).filter((x): x is string => typeof x === "string"),
      rebaixados: (listaOuVazia(o.rebaixados) ?? []).flatMap((x) => {
        const m = objeto(x);
        return m ? [{ tipo_curto: textoOu(m.tipo_curto, ""), motivo: textoOu(m.motivo, "") }] : [];
      }),
      suspensos: (listaOuVazia(o.suspensos) ?? []).filter((x): x is string => typeof x === "string"),
      semana: objeto(o.semana) as unknown as SemanaDoRetorno | null,
    };
  } catch (e) {
    const codigo = String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro");
    console.warn(JSON.stringify({ fn: "ai-daily-briefing", retorno: "extra_falhou", turno, codigo }));
    return null;
  }
}

/** "Sem recibo ontem: 3 vendedores · 2 contatos conhecidos." Nada a contar = null. */
export function linhaDeContatos(e: ExtraDaManha | null): string | null {
  if (!e) return null;
  const { vendedores, conhecidos } = e.contatos;
  const partes = [
    vendedores > 0 ? plural(vendedores, "vendedor", "vendedores") : null,
    conhecidos > 0 ? plural(conhecidos, "contato conhecido", "contatos conhecidos") : null,
  ].filter((p): p is string => !!p);
  return partes.length ? `Sem recibo ontem: ${partes.join(" · ")}.` : null;
}

/** A prestação de contas: nunca sai. A letra do fim é a da última nomeada. */
export function linhaDoMandei(e: ExtraDoFechamento | null): string | null {
  if (!e || e.mandei.length === 0) return null;
  const itens = e.mandei.map((m) => `${m.letra}) '${m.tipo_curto}' ao ${m.rotulo}`);
  if (e.mandei_mais > 0) itens.push(`e mais ${e.mandei_mais}`);
  return `Mandei sozinho hoje: ${itens.join(" · ")} · *errado ${e.mandei[e.mandei.length - 1].letra}*`;
}

function linhaDaSemana(s: SemanaDoRetorno): string {
  const fracao = (a: number, b: number) => b >= MINIMO_PARA_PERCENTUAL ? `${Math.round((100 * a) / b)}%` : `${a} de ${b}`;
  const recibo = s.recibos >= MINIMO_PARA_PERCENTUAL
    ? `recibo em até 12 min ${fracao(s.recibo_12min, s.recibos)} (de ${s.recibos})`
    : `recibo em até 12 min ${s.recibo_12min} de ${s.recibos}`;
  const media = s.dias_uteis > 0 ? (s.toques / s.dias_uteis).toFixed(1).replace(".", ",") : "0";
  return `Retorno da semana: ${recibo} · hora cumprida ${fracao(s.hora_cumprida, s.hora_casos)} · ` +
    `${s.vencida_sem_aviso} vencida sem aviso · insistência ${fracao(s.insistencia, s.recibos)} · ` +
    `você deu ${s.toques} toques novos (${media} por dia)`;
}

/** No máximo uma: semana > rebaixado > promovido > fadiga. */
export function linhasDoExtra(e: ExtraDoFechamento | null): string[] {
  if (!e) return [];
  if (e.semana) return [linhaDaSemana(e.semana)];
  const r = e.rebaixados[0];
  if (r) return [`'${r.tipo_curto}' voltou ao cartão: ${POR_QUE_REBAIXOU[r.motivo] ?? "foi rebaixado"}.`];
  const p = e.promovidos[0];
  if (p) return [`A partir de amanhã, '${p}' sai sozinho. *errado <letra>* volta ao cartão.`];
  const f = e.suspensos[0];
  if (f) return [`Aprovações rápidas demais: '${f}' não promove por 7 dias.`];
  return [];
}
