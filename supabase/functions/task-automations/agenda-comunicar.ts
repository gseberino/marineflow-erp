// Passo do motor de 15 min: a rodada do que se fala ao dono, à equipe e ao cliente (Agenda de Produção, Fase 7f, P4 — 08/11/2026).
//
// Roda DEPOIS da rodada do cliente (0d) e antes das regras, com o MESMO instante da vigia e do aviso do gestor (0c, 0c2): a rodada mede o aviso desta rodada
// (contagens.lote_guardaria, no banco). Chama agenda_comunicar_rodar (migration 20261109100100, com o passo da quinta e o pré-passo do lote de 20261109100300),
// que faz tudo no banco e decide sozinha o que roda: o destrava uma vez por dia, o teto, a mensagem da quinta no dia do plano. Domingo, os 6 modos desligados e outra
// rodada ao mesmo tempo voltam { rodou: false }: é o normal. Por isso o passo chama o banco a CADA tique, sem ler o modo nem a hora.
//
// O que sai daqui: só a mensagem da semana ao dono, quando o banco a devolve em `avisos` (com o lote ligado de verdade, na quinta, uma vez). Ela vai pelo MESMO caminho
// do aviso do gestor (agenda-aviso.ts): o montador _shared/agenda/aviso-do-gestor.ts junta as peças do banco, agenda_aviso_enfileirar (com p_semana) é a 1ª trava e põe
// na fila com a origem agenda-dono, e o texto entra no histórico do assistente. O enfileirar usa um instante próprio (o da hora de mandar): a rodada é única por
// instante, e o aviso desta rodada já pode ter usado o da vigia. Em sombra o banco só diz (contagens.quinta.quinta_diria) e devolve `avisos` vazio: nada sai.
//
// Nunca lança: erro vira `{ erro }` no resumo da rodada e uma linha em app_error_logs (task-automations, agenda:comunicar). O passo que falha NO BANCO já vai a
// app_error_logs lá (context agenda, action comunicar:<passo>) e os outros passos rodam. O código publicado antes da migration (a função ainda não existe:
// PGRST202/42883) é pulado calado — sem 96 linhas de erro por dia.
import { diaBR } from "../_shared/agenda-dia.ts";
import { lerPecasDoAviso, montarAvisoDoGestor } from "../_shared/agenda/aviso-do-gestor.ts";
import { logEdgeError } from "../_shared/log-error.ts";
import { historicoDoAviso } from "./agenda-aviso.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O resumo quando a função da rodada ainda não está no banco (a migration 20261109100100 não foi aplicada). */
export const RODADA_COMUNICAR_AUSENTE = "a migration 20261109100100 ainda não está no banco";

/** A função ainda não existe no banco (o PostgREST não acha, ou o Postgres não acha). */
function funcaoAusente(e: { code?: unknown } | null | undefined): boolean {
  const code = String(e?.code ?? "");
  return code === "PGRST202" || code === "42883";
}

/** O que aconteceu com cada mensagem que o banco devolveu para mandar. */
export interface AvisoDaComunicacao {
  enfileirou: boolean;
  /** por que não foi (o do banco: fechamento, teto, fora_da_janela, ja_existe, modo…; ou formato, nada_a_contar) */
  motivo?: string;
  id?: string | null;
  fila_id?: string | null;
  mudancas?: number;
  perguntas?: number;
  caracteres?: number;
  cortes?: string[];
  historico?: boolean;
}

export interface ResultadoDaComunicacao {
  /** Por que não rodou: a função agenda_comunicar_rodar ainda não existe no banco (o código publicado antes da migration). */
  pulado?: string;
  rodou?: boolean;
  /** domingo, ou o que o banco disser */
  motivo?: string;
  /** outra rodada ao mesmo tempo */
  ocupado?: boolean;
  modos?: Record<string, unknown>;
  contagens?: Record<string, unknown>;
  /** Quantos passos falharam no banco (o detalhe já está em app_error_logs, action comunicar:<passo>). */
  erros?: number;
  falhas?: unknown[];
  parou_no?: string | null;
  /** só quando o banco devolveu mensagem para mandar (a da quinta) */
  avisos?: AvisoDaComunicacao[];
  /** A rodada inteira falhou. */
  erro?: string;
}

/** O que o passo faz fora do banco (injetável no teste). */
export interface DepsDaComunicacao {
  historico: (db: Db, texto: string, agora: Date) => Promise<boolean>;
  /** o instante de mandar (o enfileirar tem rodada própria) */
  agora: () => Date;
}

const DEPS: DepsDaComunicacao = { historico: historicoDoAviso, agora: () => new Date() };

function numero(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Uma mensagem que o banco devolveu: monta e enfileira pelo caminho do aviso do gestor. Erro do enfileirar sobe (quem chama registra). */
async function mandar(db: Db, peca: unknown, p_hoje: string, deps: DepsDaComunicacao): Promise<AvisoDaComunicacao> {
  const lidas = lerPecasDoAviso(peca);
  if (!lidas || !lidas.avisar || lidas.pecas.semana !== true) {
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:comunicar",
      message: "rodada comunicar: o banco devolveu uma mensagem num formato que o montador não conhece; nada foi mandado",
    });
    return { enfileirou: false, motivo: "formato" };
  }
  const m = montarAvisoDoGestor(lidas.pecas);
  if (!m) {
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:comunicar",
      level: "warn",
      message: "rodada comunicar: a mensagem da semana não coube no teto nem só com as perguntas; nada foi mandado",
    });
    return { enfileirou: false, motivo: "nada_a_contar" };
  }
  const quando = deps.agora();
  const e = await db.rpc("agenda_aviso_enfileirar", {
    p_texto: m.texto, p_acao_ids: m.acaoIds, p_pergunta_ids: m.perguntaIds, p_com_perguntas: m.comPerguntas, p_hoje, p_agora: quando.toISOString(), p_semana: true,
  });
  if (e.error) throw e.error;
  const d = (e.data ?? {}) as Record<string, unknown>;
  if (d.enfileirou !== true) return { enfileirou: false, motivo: typeof d.motivo === "string" ? d.motivo : "recusado" };
  return {
    enfileirou: true,
    id: typeof d.id === "string" ? d.id : null,
    fila_id: typeof d.fila_id === "string" ? d.fila_id : null,
    mudancas: m.acaoIds.length,
    perguntas: m.perguntaIds.length,
    caracteres: m.texto.length,
    cortes: m.cortes,
    historico: await deps.historico(db, m.texto, quando),
  };
}

/** O passo da rodada comunicar no motor. Nunca lança. */
export async function comunicarDaAgenda(db: Db, agora: Date = new Date(), deps: DepsDaComunicacao = DEPS): Promise<ResultadoDaComunicacao> {
  try {
    const p_hoje = diaBR(agora.getTime());
    const { data, error } = await db.rpc("agenda_comunicar_rodar", { p_hoje, p_agora: agora.toISOString() });
    if (error) {
      // o código publicado antes da migration: a função ainda não existe — cala (sem uma linha em app_error_logs a cada 15 min)
      if (funcaoAusente(error)) return { pulado: RODADA_COMUNICAR_AUSENTE };
      throw error;
    }
    const v = (data ?? {}) as Record<string, unknown>;
    const modos = v.modos && typeof v.modos === "object" ? (v.modos as Record<string, unknown>) : undefined;
    // domingo, os 6 desligados e outra rodada ao mesmo tempo: o normal (o banco não fez nada)
    if (v.rodou !== true) {
      return {
        rodou: false,
        ...(typeof v.motivo === "string" ? { motivo: v.motivo } : {}),
        ...(v.ocupado === true ? { ocupado: true } : {}),
        ...(modos ? { modos } : {}),
      };
    }
    const r: ResultadoDaComunicacao = {
      rodou: true,
      contagens: (v.contagens ?? undefined) as Record<string, unknown> | undefined,
      erros: numero(v.erros),
      falhas: Array.isArray(v.falhas) ? v.falhas : [],
      parou_no: typeof v.parou_no === "string" ? v.parou_no : null,
    };
    const avisos = Array.isArray(v.avisos) ? v.avisos : [];
    if (avisos.length) {
      r.avisos = [];
      for (const a of avisos) r.avisos.push(await mandar(db, a, p_hoje, deps));
    }
    return r;
  } catch (e) {
    const msg = String((e as { message?: unknown })?.message ?? e);
    console.error("agenda:comunicar failed:", e);
    await logEdgeError(db, {
      context: "task-automations",
      action: "agenda:comunicar",
      message: `rodada comunicar da agenda: ${msg}`,
      details: { code: (e as { code?: unknown })?.code ?? null },
      error: e,
    });
    return { erro: msg };
  }
}
