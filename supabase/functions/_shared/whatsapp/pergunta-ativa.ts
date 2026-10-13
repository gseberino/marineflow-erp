// O registro único de pergunta ativa por telefone (comprovantes F2, 11/10/2026 — spec-f2.md, 3.2 e 5.1).
//
// O dono recebe, no mesmo WhatsApp, perguntas de vários fluxos que esperam "sim" ou um número: o
// menu dos comprovantes, a pendência do assistente, o "posso mandar?" dos lembretes de revisão e da
// campanha de temporada. Um "1" ou um "sim" solto só pode ir para UM deles. O banco guarda uma
// pergunta aberta por telefone (whatsapp_perguntas, índice único parcial) e esta peça decide, de
// forma determinística e sem rede, quem responde a cada mensagem:
//   1º a mensagem citada (quotedId), 2º a pergunta aberta mais nova, 3º a pendência viva da sessão;
//   empate em menos de 2 min → pede para citar.
// Revisão de 11/10/2026: o "sim"/número depois de o dono conversar com o assistente (a pergunta do
// CMP ficou "interrompida") ou logo depois de a pendência do assistente substituir a pergunta do CMP
// também é empate — nunca aprova/grava o que o dono não estava respondendo.
//
// Usado pelos três lotes da F2 (webhook e edge dos comprovantes, ai-agent, lembretes e
// acompanhar-conversas). As chamadas ao banco nunca lançam: erro vira o caminho de hoje (ou "ocupado",
// para quem só adia). Logs: só o código do erro, nunca texto do dono.
// F3 (11/10/2026): a pergunta do extrato ("apareceu no extrato, ligo?") usa o mesmo registro, com
// origem "comprovante" e passo "banco" — as mesmas regras de quem responde.

export type OrigemDaPergunta = "comprovante" | "assistente" | "lembrete_revisao" | "campanha_temporada" | "acompanhar_conversa";
export type Opcao = { n: number; rotulo: string; valor: string };
export type PerguntaAtiva = {
  id: string;
  origem: OrigemDaPergunta;
  tipo: "pergunta" | "confirmacao" | "opcoes";
  referencia_id: string;
  referencia_codigo: string | null;
  passo: string | null;
  opcoes: Opcao[];
  wa_message_id: string | null;
  aberta_em: string;
  /** Quando o whatsapp-send confirmou o envio (null = ainda não saiu). */
  enviada_em?: string | null;
  /** O dono conversou com o assistente depois desta pergunta (o próximo "sim" pode ser para ele). */
  interrompida_em?: string | null;
};
export type PerguntaCitada = {
  id: string;
  origem: OrigemDaPergunta;
  tipo: string;
  referencia_id: string;
  status: string;
  passo: string | null;
  referencia_codigo?: string | null;
};
export type PendenciaViva = { tipo: "confirmacao" | "opcoes"; id: string | null; titulo: string; desde: string };
/** Uma pergunta de CMP já fechada que ainda vale (a substituída há pouco; a última, para a resposta atrasada). */
export type PerguntaDoCmp = {
  id: string;
  referencia_id: string;
  referencia_codigo: string | null;
  passo: string | null;
  opcoes: Opcao[];
  aberta_em?: string | null;
};
export type CmpCurto = { id: string; codigo: string; situacao: string; gravado: boolean };
export type EstadoDoTelefone = {
  conversa: boolean;
  dono: boolean;
  ativa: PerguntaAtiva | null;
  citada: PerguntaCitada | null;
  pendencia: PendenciaViva | null;
  cmp_em_contexto: CmpCurto | null;
  /** A mensagem citada é a FOTO/arquivo de um CMP (não uma pergunta). */
  citado_cmp?: CmpCurto | null;
  /** A pergunta do CMP que a ativa (do assistente/lembrete) acabou de substituir (< 2 min entre elas). */
  cmp_substituido?: PerguntaDoCmp | null;
  /** Sem pergunta aberta: a última de CMP fechada há < 24 h sem resposta (expirou, substituída, não saiu). */
  ultima_do_cmp?: PerguntaDoCmp | null;
  /** O CMP que o dono acabou de mandar (até 2 min) e que ainda não foi perguntado. */
  cmp_chegando?: { id: string; codigo: string | null } | null;
};
export type Destino =
  | "assistente" | "comprovante" | "comprovante_reabrir" | "comando" | "pendentes" | "ambiguo"
  /** O texto solto logo depois da foto vira dica do CMP que está chegando. */
  | "dica"
  /** Citou a foto de um CMP: o texto vale para ele. */
  | "foto_do_cmp"
  /** Mensagem curta que não é resposta nem conversa, com a pergunta do CMP aberta. */
  | "nao_entendi";

// deno-lint-ignore no-explicit-any
type Admin = any;

/** Janela do empate entre a pergunta do comprovante e a pendência do assistente. */
export const JANELA_DO_EMPATE_MS = 2 * 60_000;

const ORIGENS: ReadonlySet<string> = new Set(["comprovante", "assistente", "lembrete_revisao", "campanha_temporada", "acompanhar_conversa"]);

function logDaPergunta(evento: string, codigo: string): void {
  console.warn(JSON.stringify({ fn: "pergunta-ativa", evento, codigo }));
}

// ---------------------------------------------------------------------------------------------
// Normalização e leituras básicas (sem LLM; o áudio chega pela transcrição que já existe)
// ---------------------------------------------------------------------------------------------

/**
 * trim; tira 🎤 e aspas das pontas; minúsculas; sem acento (NFD); espaços colapsados; tira a
 * pontuação final ("Um." → "um", "Opção dois!" → "opcao dois").
 */
export function normalizarResposta(texto: string): string {
  let s = String(texto ?? "").trim();
  s = s.replace(/^[\s🎤"'“”‘’«»]+/u, "");
  s = s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  s = s.replace(/\s+/g, " ").trim();
  s = s.replace(/[\s.!?,;:"'“”‘’«»]+$/u, "").trim();
  return s;
}

const NUMERO_POR_EXTENSO: Record<string, number> = {
  um: 1, uma: 1, dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5, seis: 6, sete: 7, oito: 8, nove: 9, dez: 10,
  primeiro: 1, primeira: 1, segundo: 2, segunda: 2, terceiro: 3, terceira: 3, quarto: 4, quarta: 4,
  quinto: 5, quinta: 5, sexto: 6, sexta: 6, setimo: 7, setima: 7, oitavo: 8, oitava: 8, nono: 9, nona: 9,
  decimo: 10, decima: 10,
};

/** Palavras que podem vir antes do número ("opção 2", "é a 2", "número três", "o terceiro"). */
const ANTES_DO_NUMERO = new Set(["e", "eh", "a", "o", "opcao", "numero", "n", "no", "item", "alternativa"]);
/** Palavras que podem vir depois ("dois mesmo", "a 3 por favor", "segunda opção"). */
const DEPOIS_DO_NUMERO = new Set(["mesmo", "mesma", "ai", "por favor", "pf", "pfv", "opcao", "alternativa"]);

function numeroDoToken(token: string): number | null {
  const m = /^0*(\d{1,2})[ºª°o]?[.)]?$/.exec(token);
  if (m) return Number(m[1]);
  return NUMERO_POR_EXTENSO[token] ?? null;
}

/**
 * Um número de menu de 1 a `max`: "1", "01", "1.", "um", "primeira", "opcao 2", "opcao dois",
 * "numero 3", "a 2", "o terceiro", "dois mesmo", "segunda opcao", "dez", "decimo". Fora da faixa (ou
 * max < 1) → null. Recebe o texto JÁ normalizado.
 */
export function lerNumero(textoNormalizado: string, max: number): number | null {
  const t = String(textoNormalizado ?? "").trim();
  if (!t || max < 1) return null;
  let tokens = t.split(" ");
  if (tokens.length > 5) return null;
  // sufixos ("por favor" são duas palavras)
  const fim = tokens.slice(-2).join(" ");
  if (tokens.length > 2 && DEPOIS_DO_NUMERO.has(fim)) tokens = tokens.slice(0, -2);
  else if (tokens.length > 1 && DEPOIS_DO_NUMERO.has(tokens[tokens.length - 1])) tokens = tokens.slice(0, -1);
  // prefixos (no máximo três: "e a opcao 2")
  let prefixos = 0;
  while (tokens.length > 1 && prefixos < 3 && ANTES_DO_NUMERO.has(tokens[0])) {
    tokens = tokens.slice(1);
    prefixos++;
  }
  if (tokens.length !== 1) return null;
  const n = numeroDoToken(tokens[0]);
  if (n === null || n < 1 || n > max) return null;
  return n;
}

const SIM = new Set([
  "sim", "s", "ss", "simm", "siim", "isso", "isso mesmo", "isso ai", "confirmo", "confirma", "confirmado", "confirmar", "grava",
  "grave", "grava ai", "pode gravar", "pode gravar ai", "pode", "pode sim", "sim pode", "sim grava", "sim grava ai",
  "sim pode gravar", "sim sim", "sim confirmo", "sim isso", "sim isso mesmo", "isso sim", "pode gravar sim", "isso pode gravar",
  "isso mesmo pode gravar", "correto", "ta correto", "esta correto", "sim correto", "sim esta certo", "sim ta certo",
]);
const NAO = new Set([
  "nao", "n", "nao grava", "nao grave", "errado", "esta errado", "ta errado", "nao nao", "nao pode gravar", "nao confirmo",
  "nao confirma", "negativo", "nao esta certo", "nao ta certo", "nao e isso", "nao eh isso", "nao ta errado", "nao esta errado",
  "nao errado",
]);
/** Concordância que NUNCA aprova (o "ok" do dono pode ser para qualquer coisa). */
const OK = new Set([
  "ok", "okay", "okey", "okk", "oky", "blz", "beleza", "certo", "ta", "ta bom", "ta certo", "show", "valeu", "vlw",
  "obrigado", "obrigada", "brigado", "pode ser", "joia", "top", "perfeito", "certinho", "ok obrigado", "ok valeu",
  "beleza obrigado", "entendi", "ok entendi", "otimo", "massa", "combinado", "fechado",
]);
const SO_EMOJI = /^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|‍|️|\s)+$/u;

/**
 * "sim" (só a confirmação, sem texto a mais: "sim, mas é da OS 12" NÃO é sim), "nao", "ok" (o grupo
 * que nunca aprova: ok, beleza, valeu, 👍 e só emoji) ou null. Recebe o texto JÁ normalizado.
 */
export function lerSimNao(textoNormalizado: string): "sim" | "nao" | "ok" | null {
  const t = String(textoNormalizado ?? "").replace(/,/g, " ").replace(/\s+/g, " ").trim();
  if (!t) return null;
  if (SIM.has(t)) return "sim";
  if (NAO.has(t)) return "nao";
  if (OK.has(t) || SO_EMOJI.test(t)) return "ok";
  return null;
}

// ---------------------------------------------------------------------------------------------
// Quem responde (seção 3.2 da spec)
// ---------------------------------------------------------------------------------------------

function ms(iso: string | null | undefined): number {
  const t = iso ? Date.parse(iso) : NaN;
  return Number.isNaN(t) ? NaN : t;
}

/** Parece resposta a um menu/confirmação: sim/não/ok ou só um número (o que aprovaria uma pendência). */
export function pareceRespostaCurta(texto: string): boolean {
  const n = normalizarResposta(texto);
  if (!n) return false;
  return lerSimNao(n) !== null || lerNumero(n, 99) !== null || /^\d+$/.test(n);
}

/**
 * Para onde vai a mensagem do dono. `ehRespostaValida` = o texto é resposta ao passo da pergunta
 * ativa (interpretarResposta ≠ null, inclui sim/não/ok); `ehComando` = a classe do comando lido
 * ("pendentes"; "comprovante" = cmp N, cancelar cmp N, feito cmp N, lote antigo; "contexto" =
 * corrigir…, pular, sair, cancelar esse). Opcionais (revisão de 11/10/2026): `ehRespostaAUltima` = o
 * texto é resposta de dado à última pergunta de CMP fechada (ultima_do_cmp); `ehDica` = frase solta
 * que serve de dica a um CMP; `ehNaoEntendida` = mensagem curta que não é resposta nem conversa.
 * As regras, NESTA ordem:
 *   1. conversa desligada ou não é o dono → assistente (o despacho de hoje);
 *   2. comando explícito → comando (pendentes → pendentes: a lista e depois o assistente);
 *   3. citação de pergunta de comprovante → comprovante (aberta) / comprovante_reabrir (fechada);
 *      citação da FOTO de um CMP → foto_do_cmp; de outra origem, ou fora do registro → assistente;
 *   4. corrigir/pular/sair → comprovante com pergunta de CMP aberta (corrigir, cancelar esse e
 *      "obs: …": também com CMP em contexto); senão assistente;
 *   5. pergunta de CMP aberta e resposta válida: interrompida (o dono falou com o assistente depois
 *      dela) → ambiguo; pendência a menos de 2 min → ambiguo; pendência mais nova → assistente;
 *      senão comprovante;
 *   6. a ativa é de outra origem e acabou de substituir a pergunta de um CMP (< 2 min) e o texto
 *      parece resposta curta → ambiguo (o "1" podia ser do menu do CMP);
 *   7. sem pergunta aberta, a última de CMP fechada sem resposta (< 24 h) e o texto responde ao
 *      passo dela → comprovante_reabrir;
 *   8. o CMP acabou de chegar e o texto é dica → dica;
 *   9. pergunta de CMP aberta e mensagem curta não entendida → nao_entendi (a pergunta de novo);
 *  10. pergunta de CMP aberta e texto livre → assistente (a pergunta segue aberta, interrompida);
 *  11. o resto → assistente.
 */
export function quemResponde(p: {
  texto: string;
  citado: string | null;
  estado: EstadoDoTelefone;
  ehRespostaValida: boolean;
  ehComando: "pendentes" | "comprovante" | "contexto" | null;
  agora: Date;
  ehRespostaAUltima?: boolean;
  ehDica?: boolean;
  ehNaoEntendida?: boolean;
}): { destino: Destino; motivo: string } {
  const e = p.estado;
  if (!e?.conversa || !e.dono) return { destino: "assistente", motivo: "desligada" };

  if (p.ehComando === "pendentes") return { destino: "pendentes", motivo: "comando_pendentes" };
  if (p.ehComando === "comprovante") return { destino: "comando", motivo: "comando" };

  if (p.citado) {
    if (e.citada?.origem === "comprovante") {
      return e.citada.status === "aberta"
        ? { destino: "comprovante", motivo: "citou_pergunta_aberta" }
        : { destino: "comprovante_reabrir", motivo: "citou_pergunta_fechada" };
    }
    if (!e.citada && e.citado_cmp) return { destino: "foto_do_cmp", motivo: "citou_a_foto" };
    return { destino: "assistente", motivo: e.citada ? "citou_outra_origem" : "citou_fora_do_registro" };
  }

  const ativaDoCmp = e.ativa?.origem === "comprovante" ? e.ativa : null;

  if (p.ehComando === "contexto") {
    if (ativaDoCmp) return { destino: "comprovante", motivo: "contexto_com_pergunta" };
    const t = normalizarResposta(p.texto);
    // A (12/10/2026): "obs: …"/"observação: …" anota no CMP em contexto, como o corrigir
    const doContexto = t.startsWith("corrig") || t.startsWith("cancela") || t.startsWith("obs");
    if (doContexto && e.cmp_em_contexto && !e.cmp_em_contexto.gravado) return { destino: "comprovante", motivo: "corrigir_cmp_em_contexto" };
    if (doContexto && e.cmp_em_contexto) return { destino: "comprovante", motivo: "corrigir_cmp_gravado" };
    return { destino: "assistente", motivo: "contexto_sem_cmp" };
  }

  if (ativaDoCmp && p.ehRespostaValida) {
    if (ativaDoCmp.interrompida_em) return { destino: "ambiguo", motivo: "interrompida" };
    const pend = e.pendencia;
    if (pend) {
      const diff = ms(pend.desde) - ms(ativaDoCmp.aberta_em);
      if (Number.isNaN(diff) || Math.abs(diff) < JANELA_DO_EMPATE_MS) return { destino: "ambiguo", motivo: "empate" };
      if (diff > 0) return { destino: "assistente", motivo: "pendencia_mais_nova" };
    }
    return { destino: "comprovante", motivo: "resposta" };
  }
  if (!ativaDoCmp && e.ativa && e.cmp_substituido && pareceRespostaCurta(p.texto)) {
    const diff = ms(e.ativa.aberta_em) - ms(e.cmp_substituido.aberta_em);
    if (Number.isNaN(diff) || Math.abs(diff) < JANELA_DO_EMPATE_MS) return { destino: "ambiguo", motivo: "substituido" };
  }
  if (!e.ativa && e.ultima_do_cmp && p.ehRespostaAUltima) return { destino: "comprovante_reabrir", motivo: "resposta_atrasada" };
  if (e.cmp_chegando && p.ehDica && !(ativaDoCmp && p.ehRespostaValida)) return { destino: "dica", motivo: "dica_depois_da_foto" };
  if (ativaDoCmp && p.ehNaoEntendida) return { destino: "nao_entendi", motivo: "nao_entendi" };
  if (ativaDoCmp) return { destino: "assistente", motivo: "texto_livre" };
  return { destino: "assistente", motivo: "sem_pergunta_de_cmp" };
}

// ---------------------------------------------------------------------------------------------
// O banco (RPCs do registro, migration 20261011201000)
// ---------------------------------------------------------------------------------------------

const DESLIGADO: EstadoDoTelefone = {
  conversa: false, dono: false, ativa: null, citada: null, pendencia: null, cmp_em_contexto: null,
};

function texto(v: unknown): string | null {
  return typeof v === "string" && v ? v : null;
}

function opcoesValidas(v: unknown): Opcao[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter((o) => o && typeof o === "object" && Number.isInteger((o as Opcao).n) && typeof (o as Opcao).rotulo === "string")
    .map((o) => ({ n: (o as Opcao).n, rotulo: String((o as Opcao).rotulo), valor: String((o as Opcao).valor ?? "") }));
}

function ativaValida(v: unknown): PerguntaAtiva | null {
  const a = v as Record<string, unknown> | null;
  if (!a || typeof a !== "object" || !texto(a.id) || !ORIGENS.has(String(a.origem))) return null;
  const tipo = a.tipo === "confirmacao" || a.tipo === "opcoes" ? a.tipo : "pergunta";
  return {
    id: String(a.id),
    origem: a.origem as OrigemDaPergunta,
    tipo,
    referencia_id: String(a.referencia_id ?? ""),
    referencia_codigo: texto(a.referencia_codigo),
    passo: texto(a.passo),
    opcoes: opcoesValidas(a.opcoes),
    wa_message_id: texto(a.wa_message_id),
    aberta_em: String(a.aberta_em ?? ""),
    enviada_em: texto(a.enviada_em),
    interrompida_em: texto(a.interrompida_em),
  };
}

function citadaValida(v: unknown): PerguntaCitada | null {
  const c = v as Record<string, unknown> | null;
  if (!c || typeof c !== "object" || !texto(c.id) || !ORIGENS.has(String(c.origem))) return null;
  return {
    id: String(c.id),
    origem: c.origem as OrigemDaPergunta,
    tipo: String(c.tipo ?? ""),
    referencia_id: String(c.referencia_id ?? ""),
    status: String(c.status ?? ""),
    passo: texto(c.passo),
    referencia_codigo: texto(c.referencia_codigo),
  };
}

function pendenciaValida(v: unknown): PendenciaViva | null {
  const p = v as Record<string, unknown> | null;
  if (!p || typeof p !== "object" || (p.tipo !== "confirmacao" && p.tipo !== "opcoes")) return null;
  return { tipo: p.tipo, id: texto(p.id), titulo: String(p.titulo ?? "pedido do assistente"), desde: String(p.desde ?? "") };
}

function cmpCurto(v: unknown): CmpCurto | null {
  const c = v as Record<string, unknown> | null;
  return c && typeof c === "object" && texto(c.id) && texto(c.codigo)
    ? { id: String(c.id), codigo: String(c.codigo), situacao: String(c.situacao ?? ""), gravado: c.gravado === true }
    : null;
}

function perguntaDoCmp(v: unknown): PerguntaDoCmp | null {
  const c = v as Record<string, unknown> | null;
  if (!c || typeof c !== "object" || !texto(c.id) || !texto(c.referencia_id)) return null;
  return {
    id: String(c.id),
    referencia_id: String(c.referencia_id),
    referencia_codigo: texto(c.referencia_codigo),
    passo: texto(c.passo),
    opcoes: opcoesValidas(c.opcoes),
    aberta_em: texto(c.aberta_em),
  };
}

/** pergunta_rotear. Erro → { conversa: false, dono: false, ... } (cai no despacho de hoje). */
export async function lerEstadoDoTelefone(admin: Admin, phone: string, citado: string | null): Promise<EstadoDoTelefone> {
  try {
    const { data, error } = await admin.rpc("pergunta_rotear", { p_phone: phone, p_citado: citado ?? null });
    if (error) {
      logDaPergunta("rotear_falhou", String(error.code ?? "erro"));
      return { ...DESLIGADO };
    }
    const d = (data ?? {}) as Record<string, unknown>;
    if (d.conversa !== true) return { ...DESLIGADO, dono: d.dono === true };
    const chegando = d.cmp_chegando as Record<string, unknown> | null;
    return {
      conversa: true,
      dono: d.dono === true,
      ativa: ativaValida(d.ativa),
      citada: citadaValida(d.citada),
      pendencia: pendenciaValida(d.pendencia),
      cmp_em_contexto: cmpCurto(d.cmp_em_contexto),
      citado_cmp: cmpCurto(d.citado_cmp),
      cmp_substituido: perguntaDoCmp(d.cmp_substituido),
      ultima_do_cmp: perguntaDoCmp(d.ultima_do_cmp),
      cmp_chegando: chegando && typeof chegando === "object" && texto(chegando.id)
        ? { id: String(chegando.id), codigo: texto(chegando.codigo) }
        : null,
    };
  } catch (e) {
    logDaPergunta("rotear_falhou", (e as Error)?.name ?? "erro");
    return { ...DESLIGADO };
  }
}

/** pergunta_ocupado. Erro → { ocupado: true, por: { origem: "erro", ... } } (quem chama adia). */
export async function telefoneOcupado(
  admin: Admin,
  phone: string,
): Promise<{ ocupado: boolean; por: { origem: string; titulo: string | null; desde: string } | null }> {
  const erro = () => ({ ocupado: true, por: { origem: "erro", titulo: null, desde: new Date().toISOString() } });
  try {
    const { data, error } = await admin.rpc("pergunta_ocupado", { p_phone: phone });
    if (error) {
      logDaPergunta("ocupado_falhou", String(error.code ?? "erro"));
      return erro();
    }
    const d = (data ?? {}) as { ocupado?: unknown; por?: Record<string, unknown> | null };
    if (typeof d.ocupado !== "boolean") return erro();
    if (!d.ocupado) return { ocupado: false, por: null };
    const por = d.por ?? {};
    return { ocupado: true, por: { origem: String(por.origem ?? "desconhecida"), titulo: texto(por.titulo), desde: String(por.desde ?? "") } };
  } catch (e) {
    logDaPergunta("ocupado_falhou", (e as Error)?.name ?? "erro");
    return erro();
  }
}

type ParametrosDaExterna = {
  phone: string;
  origem: Exclude<OrigemDaPergunta, "comprovante">;
  tipo: "confirmacao" | "opcoes";
  referencia_id: string;
  titulo: string;
};

/**
 * pergunta_registrar_externa com o que ela substituiu (a pergunta de um CMP que volta para a fila:
 * quem envia avisa o dono). Nunca lança: erro → { id: null, substituiu: null } (só o código no log).
 */
export async function registrarPerguntaExternaDetalhada(admin: Admin, p: ParametrosDaExterna): Promise<{
  id: string | null;
  substituiu: { origem: string; referencia_codigo: string | null } | null;
}> {
  try {
    const { data, error } = await admin.rpc("pergunta_registrar_externa", {
      p: { phone: p.phone, origem: p.origem, tipo: p.tipo, referencia_id: p.referencia_id, titulo: String(p.titulo ?? "").slice(0, 80) },
    });
    if (error) {
      logDaPergunta("registrar_falhou", String(error.code ?? "erro"));
      return { id: null, substituiu: null };
    }
    const d = (data ?? {}) as { id?: unknown; substituiu?: Record<string, unknown> | null };
    const sub = d.substituiu && typeof d.substituiu === "object"
      ? { origem: String(d.substituiu.origem ?? ""), referencia_codigo: texto(d.substituiu.referencia_codigo) }
      : null;
    return { id: typeof d.id === "string" && d.id ? d.id : null, substituiu: sub };
  } catch (e) {
    logDaPergunta("registrar_falhou", (e as Error)?.name ?? "erro");
    return { id: null, substituiu: null };
  }
}

/** pergunta_registrar_externa. Nunca lança: erro → null (só o código no log). */
export async function registrarPerguntaExterna(admin: Admin, p: ParametrosDaExterna): Promise<string | null> {
  return (await registrarPerguntaExternaDetalhada(admin, p)).id;
}

/**
 * pergunta_marcar_enviada: o envio da pergunta foi confirmado (e o id do WhatsApp dele, para a
 * citação achar). Sem o id do WhatsApp, ainda marca o envio. Nunca lança.
 */
export async function marcarPerguntaEnviada(admin: Admin, id: string | null, waMessageId: string | null): Promise<void> {
  if (!id) return;
  try {
    const { error } = await admin.rpc("pergunta_marcar_enviada", {
      p_id: id, p_wa_message_id: waMessageId ? String(waMessageId).slice(0, 128) : null,
    });
    if (error) logDaPergunta("marcar_falhou", String(error.code ?? "erro"));
  } catch (e) {
    logDaPergunta("marcar_falhou", (e as Error)?.name ?? "erro");
  }
}

/** pergunta_encerrar_externa: fecha as abertas que não são de comprovante; quantas fechou. Nunca lança. */
export async function encerrarPerguntasExternas(admin: Admin, phone: string, status: "respondida" | "cancelada"): Promise<number> {
  try {
    const { data, error } = await admin.rpc("pergunta_encerrar_externa", { p_phone: phone, p_status: status });
    if (error) {
      logDaPergunta("encerrar_falhou", String(error.code ?? "erro"));
      return 0;
    }
    return typeof data === "number" ? data : 0;
  } catch (e) {
    logDaPergunta("encerrar_falhou", (e as Error)?.name ?? "erro");
    return 0;
  }
}

/**
 * pergunta_interromper: o texto livre do dono vai ao ASSISTENTE com a pergunta de um CMP aberta — o
 * próximo "sim"/número sem citar não vale para o CMP sem a pergunta ser reapresentada. Nunca lança.
 */
export async function interromperPergunta(admin: Admin, phone: string): Promise<void> {
  try {
    const { error } = await admin.rpc("pergunta_interromper", { p_phone: phone });
    if (error) logDaPergunta("interromper_falhou", String(error.code ?? "erro"));
  } catch (e) {
    logDaPergunta("interromper_falhou", (e as Error)?.name ?? "erro");
  }
}

// ---------------------------------------------------------------------------------------------
// A trava do ai-agent e o texto do desempate
// ---------------------------------------------------------------------------------------------

/** As mesmas palavras de parseConfirmationReply (whatsapp-channel.ts): o que aprovaria ou recusaria. */
const PRIMEIRA_PALAVRA_DE_CONFIRMACAO = new Set(["sim", "s", "ok", "confirmar", "1", "não", "nao", "n", "cancelar", "2"]);

function pareceConfirmacao(t: string): boolean {
  const cru = String(t ?? "").trim().toLowerCase();
  if (!cru) return false;
  if (PRIMEIRA_PALAVRA_DE_CONFIRMACAO.has(cru.split(/\s+/)[0])) return true;
  if (/^\d+$/.test(cru)) return true;
  const n = normalizarResposta(cru);
  return lerSimNao(n) !== null || lerNumero(n, 99) !== null;
}

const PASSO_LEGIVEL: Record<string, string> = {
  valor: "o valor",
  para_que: "para quê",
  qual_os: "qual OS",
  mesma_compra: "se é a mesma compra",
  como_pagou: "como foi pago",
  quem_pagou: "quem pagou",
  qual_tecnico: "qual técnico",
  // ajustes do dono (11/10/2026): no lugar do "cobrar do cliente?", peça ou despesa da OS
  tipo_na_os: "se é peça ou despesa da OS",
  categoria: "a categoria",
  data: "a data",
  confirmar: "gravar ou não",
  corrigir: "o que corrigir",
  // F3 (spec-f3.md, 4.2): a pergunta "apareceu no extrato, ligo?" de um CMP já gravado
  banco: "a linha do extrato",
  // regra E (ajustes do dono, 11/10/2026): 5 dias sem aparecer em conta da empresa
  banco_quem: "quem pagou a compra que não apareceu no extrato",
};

export function passoLegivel(passo: string | null | undefined): string {
  return PASSO_LEGIVEL[String(passo ?? "")] ?? "a pergunta";
}

/**
 * A trava do ai-agent: true quando "sim"/"1" chegaria a uma pendência do assistente mas a pergunta de
 * comprovante aberta é mais nova (ou empata em < 2 min) — ou quando a pendência acabou de substituir a
 * pergunta de um CMP (< 2 min entre as duas): o "1" podia ser do menu do CMP. Devolve o texto do
 * desempate. Não trava: conversa desligada, sem pendência na sessão, sem pergunta de CMP envolvida,
 * citação de uma pergunta de outra origem (o dono apontou o pedido do assistente) ou pendência mais
 * nova por 2 min+. Recusa ("não", "2") também trava: era a resposta ao menu do CMP, e recusar o pedido
 * do assistente por engano o perderia.
 */
export function travaDaConfirmacao(
  estado: EstadoDoTelefone | null,
  texto: string,
  metadata: { pending_confirm_action_id?: unknown; pending_options?: unknown },
): { travar: boolean; texto: string | null } {
  const nao = { travar: false, texto: null };
  const temPendencia = (typeof metadata?.pending_confirm_action_id === "string" && metadata.pending_confirm_action_id !== "") ||
    (Array.isArray(metadata?.pending_options) && metadata.pending_options.length > 0);
  if (!temPendencia || !estado?.conversa || !estado.dono) return nao;
  if (estado.citada && estado.citada.origem !== "comprovante") return nao;
  if (!pareceConfirmacao(texto)) return nao;
  const ativa = estado.ativa;
  if (ativa && ativa.origem !== "comprovante") {
    // a pendência do assistente/lembrete substituiu há pouco a pergunta de um CMP: empate
    const sub = estado.cmp_substituido;
    if (!sub) return nao;
    const diff = ms(ativa.aberta_em) - ms(sub.aberta_em);
    if (!Number.isNaN(diff) && Math.abs(diff) >= JANELA_DO_EMPATE_MS) return nao;
    return { travar: true, texto: textoDoDesempate(estado) };
  }
  if (!ativa) return nao;
  const desde = ms(estado.pendencia?.desde);
  const aberta = ms(ativa.aberta_em);
  if (!Number.isNaN(desde) && !Number.isNaN(aberta) && desde - aberta >= JANELA_DO_EMPATE_MS && !ativa.interrompida_em) return nao;
  return { travar: true, texto: textoDoDesempate(estado) };
}

function tituloLimpo(t: string | null | undefined, padrao: string): string {
  return String(t ?? padrao).replace(/["\n\r]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 80) || padrao;
}

function numeroDoCodigo(codigo: string | null | undefined): string | null {
  const m = /(\d+)\s*$/.exec(String(codigo ?? ""));
  return m ? String(Number(m[1])) : null;
}

/**
 * "Fiquei na dúvida: essa resposta é para o CMP-00124 (para quê) ou para o pedido "<título>"? …" —
 * com a saída sem citar: *cmp N* repete a pergunta do comprovante. Sem pendência (o dono falou com o
 * assistente depois da pergunta do CMP): "… ou para a conversa com o assistente?".
 */
export function textoDoDesempate(estado: EstadoDoTelefone): string {
  const ativaDoCmp = estado.ativa?.origem === "comprovante" ? estado.ativa : null;
  const sub = !ativaDoCmp ? estado.cmp_substituido ?? null : null;
  const codigo = ativaDoCmp?.referencia_codigo ?? sub?.referencia_codigo ?? "comprovante";
  const passo = ativaDoCmp?.passo ?? sub?.passo ?? null;
  const pedido = estado.pendencia?.titulo ?? (!ativaDoCmp ? estado.ativa?.referencia_codigo : null) ?? null;
  const outro = pedido ? `o pedido "${tituloLimpo(pedido, "do assistente")}"` : "a conversa com o assistente";
  const n = numeroDoCodigo(codigo);
  const saida = n ? ` Ou mande *cmp ${n}* que eu repito a pergunta do comprovante.` : "";
  return `Fiquei na dúvida: essa resposta é para o ${codigo} (${passoLegivel(passo)}) ou para ${outro}? ` +
    `Responda de novo citando a mensagem certa (segure a mensagem e toque em Responder).${saida}`;
}
