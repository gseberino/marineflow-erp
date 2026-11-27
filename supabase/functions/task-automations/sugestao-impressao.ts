// A sugestão de imprimir as vias de amanhã, na hora da ficha da véspera (20/11/2026, decisão do dono: "Junto da ficha das
// 19:30 (véspera)"). O assistente SÓ SUGERE; nada é impresso sozinho (a impressão continua sob pedido: "imprime as vias de
// amanhã" é lido sem modelo por _shared/ai/atalho-pdf.ts e impresso por _shared/ai/tools/impressao.ts).
//
// (27/11/2026) A hora deixou de ser fixa: é a da ficha, agenda_config.equipe_hora_ficha (o dono mudou a ficha de 19:30 para
// 17:45 e a sugestão ficaria chegando uma hora e meia depois dela). Se a hora não puder ser lida, vale a de sempre, 19:30.
//
// A ficha vai só à EQUIPE (agenda_rotina_rodar → agenda_equipe_mensagens tipo 'ficha'); o dono não recebe ficha.
// Por isso a linha vai ao dono numa mensagem curta própria, no mesmo tique da ficha (o 1º a partir da hora dela, em
// Brasília) ou no seguinte, e só quando:
//   · há OS na agenda de amanhã (a mesma regra de "as vias de amanhã" e da manhã: alocação publicada ou fixada, reserva não
//     conta) — o N da mensagem é o que o pedido imprime;
//   · a impressora do escritório está no ar (o mesmo teste da manhã);
//   · app_settings.impressao_sugestao_vespera não é 'off' (o interruptor; o da manhã é impressao_sugestao_manha).
// Uma por véspera: a chave da fila impressao_sugestao:<amanhã> (a fila recusa a 2ª). Tentativas só até as 20h (nada à noite).
// A origem 'impressao_sugestao' não começa por "agenda-": a linha entra na conversa do dono, e o "imprime as vias de amanhã"
// que ele responder tem o contexto.
//
// Nunca lança: erro vira `{ erro }` no resumo do tique e uma linha em app_error_logs (task-automations, impressao:vespera).
import { logEdgeError } from "../_shared/log-error.ts";
import { impressoraNoAr } from "../_shared/impressao/fila.ts";
import { diaSeguinte, osDaAgendaDoDia } from "../_shared/impressao/agenda.ts";
import { emBrasilia, tentativasAteAs20h } from "../_shared/uma-voz/janela.ts";
import { lerDonoDaVoz } from "../_shared/uma-voz/registrar.ts";
import type { Dono } from "../_shared/whatsapp/dono.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** A hora da ficha (minutos em Brasília) quando a configuração não pôde ser lida: 19:30, o DEFAULT da coluna. */
export const SUGESTAO_DE_MIN = 19 * 60 + 30;
/** Nada à noite: a janela nunca passa das 20h de Brasília (exclusive). */
export const SUGESTAO_ATE_MIN = 20 * 60;
/** A janela dura dois tiques do motor de 15 minutos: o da ficha e o seguinte. */
export const SUGESTAO_JANELA_MIN = 30;
/** A ficha nunca é antes das 06:00 (CHECK de agenda_config.equipe_janela_inicio): antes disso nem a hora é lida. */
export const SUGESTAO_MAIS_CEDO_MIN = 6 * 60;
export const ORIGEM_DA_SUGESTAO = "impressao_sugestao";
export const CHAVE_DO_INTERRUPTOR = "impressao_sugestao_vespera";

export interface ResultadoDaSugestao {
  /** por que não mandou (fora_da_hora, desligada, sem_vias, impressora, sem_dono, ja_foi) */
  pulou?: string;
  /** mandou para a fila (N = quantas vias) */
  enviada?: number;
  erro?: string;
}

/** "17:45:00" → 1065 (minutos do dia). Null quando não é hora. */
export function minutosDaHora(hora: unknown): number | null {
  const m = /^(\d{1,2}):(\d{2})/.exec(String(hora ?? "").trim());
  if (!m) return null;
  const h = Number(m[1]), mi = Number(m[2]);
  return h < 24 && mi < 60 ? h * 60 + mi : null;
}

/**
 * A janela da sugestão no dia (minutos em Brasília; `ate` exclusive): do tique da ficha ao seguinte, nunca depois das 20h.
 * Sem hora lida, a das 19:30. Ficha às 20:00 ou depois: janela vazia (nada à noite).
 */
export function janelaDaSugestao(horaDaFichaMin: number | null): { de: number; ate: number } {
  const de = horaDaFichaMin ?? SUGESTAO_DE_MIN;
  return { de, ate: Math.min(de + SUGESTAO_JANELA_MIN, SUGESTAO_ATE_MIN) };
}

/** A linha ao dono. Null sem vias. */
export function textoDaSugestaoDaVespera(vias: number): string | null {
  if (!(vias > 0)) return null;
  const quantas = vias === 1 ? "a via de amanhã" : `as ${vias} vias de amanhã`;
  return `🖨️ Quer imprimir ${quantas}? Responda: *imprime as vias de amanhã*`;
}

/** A linha da fila: uma por véspera (chave impressao_sugestao:<amanhã>), tentativas só até as 20h. */
export function linhaDaSugestao(p: { phone: string; texto: string; amanha: string; agora: Date }): Record<string, unknown> {
  return {
    phone_normalized: p.phone,
    message: p.texto,
    source: ORIGEM_DA_SUGESTAO,
    priority: 4,
    max_attempts: tentativasAteAs20h(p.agora),
    dedupe_key: `${ORIGEM_DA_SUGESTAO}:${p.amanha}`,
  };
}

/** O que a sugestão lê de fora (injetável no teste). */
export interface PecasDaSugestao {
  /** A hora da ficha em minutos do dia (agenda_config.equipe_hora_ficha). Null = não deu para ler: vale 19:30. */
  horaDaFicha: (db: Db) => Promise<number | null>;
  desligada: (db: Db) => Promise<boolean>;
  impressoraNoAr: (db: Db, agora: Date) => Promise<boolean>;
  osDoDia: (db: Db, dia: string) => Promise<string[]>;
  dono: (db: Db) => Promise<Dono | null>;
  /** "ok" = entrou na fila; "ja_foi" = a chave desta véspera já estava lá (23505). Outro erro lança. */
  enfileirar: (db: Db, linha: Record<string, unknown>) => Promise<"ok" | "ja_foi">;
}

const PECAS: PecasDaSugestao = {
  horaDaFicha: async (db) => {
    const { data, error } = await db.from("agenda_config").select("equipe_hora_ficha").maybeSingle();
    if (error) {
      // sem a hora, a sugestão não some: sai na hora de sempre
      console.error("impressao:vespera: não consegui ler a hora da ficha, vale 19:30:", error.message ?? error);
      return null;
    }
    return minutosDaHora(data?.equipe_hora_ficha);
  },
  desligada: async (db) => {
    const { data, error } = await db.from("app_settings").select("value").eq("key", CHAVE_DO_INTERRUPTOR).maybeSingle();
    if (error) throw new Error(`não consegui ler ${CHAVE_DO_INTERRUPTOR} (${error.message})`);
    return String(data?.value ?? "").trim().toLowerCase() === "off";
  },
  impressoraNoAr: async (db, agora) => (await impressoraNoAr(db, agora)).ok,
  osDoDia: (db, dia) => osDaAgendaDoDia(db, dia),
  dono: (db) => lerDonoDaVoz(db),
  enfileirar: async (db, linha) => {
    const { error } = await db.from("whatsapp_send_queue").insert(linha);
    if (!error) return "ok";
    if ((error as { code?: string }).code === "23505") return "ja_foi";
    throw new Error(`a fila recusou a sugestão (${error.message ?? error})`);
  },
};

/** O passo do motor. Nunca lança. `pecas` só no teste. */
export async function sugerirImpressaoDaVespera(
  db: Db, agora: Date = new Date(), pecas: PecasDaSugestao = PECAS,
): Promise<ResultadoDaSugestao> {
  const { dia, min } = emBrasilia(agora);
  // de madrugada e à noite nada é lido: a ficha só existe entre as 06:00 e as 20:00
  if (min < SUGESTAO_MAIS_CEDO_MIN || min >= SUGESTAO_ATE_MIN) return { pulou: "fora_da_hora" };
  try {
    const { de, ate } = janelaDaSugestao(await pecas.horaDaFicha(db));
    if (min < de || min >= ate) return { pulou: "fora_da_hora" };
    if (await pecas.desligada(db)) return { pulou: "desligada" };
    const amanha = diaSeguinte(dia);
    const vias = (await pecas.osDoDia(db, amanha)).length;
    const texto = textoDaSugestaoDaVespera(vias);
    if (!texto) return { pulou: "sem_vias" };
    if (!(await pecas.impressoraNoAr(db, agora))) return { pulou: "impressora" };
    const dono = await pecas.dono(db);
    if (!dono?.phone) return { pulou: "sem_dono" };
    const r = await pecas.enfileirar(db, linhaDaSugestao({ phone: dono.phone, texto, amanha, agora }));
    return r === "ja_foi" ? { pulou: "ja_foi" } : { enviada: vias };
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("impressao:vespera failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "impressao:vespera",
      message: `sugestão de imprimir as vias de amanhã: ${msg}`,
      details: {},
      error: e,
    });
    return { erro: msg };
  }
}
