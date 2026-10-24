// Os modos da Agenda de Produção, lidos uma vez por rodada do motor de 15 min (Fase 2, P3 — 24/10/2026).
//
// O interruptor da regra antiga é o mesmo da substituta (spec-fase2 §3.3 d8, decisão d13 do dono): com
// agenda_config.modo_proposta = 'ligado' a agenda marca as OS e diz o que comprar — a R1 e a R16 param de criar tarefa e
// as vivas se resolvem sozinhas; com modo_vigia = 'ligado' a vigia pergunta quando a OS para — a R2 para. Assim é
// impossível ficar com as duas (o dono ouviria a mesma coisa duas vezes) ou com nenhuma.
//
// Leitura que falha aqui NÃO desliga nada: erro, linha ausente ou valor estranho = 'desligado', ou seja, as regras ficam
// como hoje (o lado seguro: no máximo o dono recebe a tarefa antiga). O erro volta em `erro` para entrar no resumo da
// rodada; quem registra em app_error_logs é a vigia, que lê a mesma tabela e falha junto.

// deno-lint-ignore no-explicit-any
type Db = any;

export type ModoDaAgenda = "desligado" | "sombra" | "ligado";

export interface ModosDaAgenda {
  /** agenda_config.modo_proposta: o que o motor FAZ (publicar, replanejar, status, datas). */
  proposta: ModoDaAgenda;
  /** agenda_config.modo_vigia: o que o sistema DIZ sozinho (perguntas, acorde). */
  vigia: ModoDaAgenda;
  /** A leitura falhou (as regras ficam como hoje). */
  erro?: string;
}

export const MODOS_DESLIGADOS: Readonly<ModosDaAgenda> = Object.freeze({ proposta: "desligado", vigia: "desligado" });

/** 'ligado', ' Sombra ', '"sombra"' → o modo; qualquer outra coisa → 'desligado'. */
export function lerModo(v: unknown): ModoDaAgenda {
  const s = typeof v === "string" ? v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase() : "";
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

/** Um SELECT em agenda_config. Nunca lança: erro = desligado (com o motivo em `erro`). */
export async function lerModosDaAgenda(db: Db): Promise<ModosDaAgenda> {
  try {
    const { data, error } = await db.from("agenda_config").select("modo_proposta, modo_vigia").maybeSingle();
    if (error) return { ...MODOS_DESLIGADOS, erro: String(error.message ?? error.code ?? "erro na leitura") };
    if (!data) return { ...MODOS_DESLIGADOS, erro: "agenda_config sem a linha de parâmetros" };
    return { proposta: lerModo(data.modo_proposta), vigia: lerModo(data.modo_vigia) };
  } catch (e) {
    return { ...MODOS_DESLIGADOS, erro: String((e as Error)?.message ?? e) };
  }
}

// ── Fase 3 (P4, 24/10/2026): os modos da equipe e da diária ─────────────────────────────────────────────
// Lidos num SELECT à parte: a coluna modo_diaria só existe com a migration 20261026100000, e um SELECT que falhasse por
// ela não pode derrubar os modos da Fase 2 (a R1, a R2 e a R16 voltariam com a agenda ligada). Ilegível = desligado: a
// R10 continua como hoje (o lado seguro: no máximo o técnico recebe o lembrete antigo) e a rotina não roda.

export interface ModosDaEquipe {
  /** agenda_config.modo_equipe: a ficha, a confirmação e o "como foi hoje?" (em ligado a R10 para). */
  equipe: ModoDaAgenda;
  /** agenda_config.modo_diaria: a diária automática. */
  diaria: ModoDaAgenda;
  /** A leitura falhou (a R10 fica como hoje). */
  erro?: string;
}

export const EQUIPE_DESLIGADA: Readonly<ModosDaEquipe> = Object.freeze({ equipe: "desligado", diaria: "desligado" });

/** Um SELECT em agenda_config (modo_equipe, modo_diaria). Nunca lança: erro = desligado (com o motivo em `erro`). */
export async function lerModosDaEquipe(db: Db): Promise<ModosDaEquipe> {
  try {
    const { data, error } = await db.from("agenda_config").select("modo_equipe, modo_diaria").maybeSingle();
    if (error) return { ...EQUIPE_DESLIGADA, erro: String(error.message ?? error.code ?? "erro na leitura") };
    if (!data) return { ...EQUIPE_DESLIGADA, erro: "agenda_config sem a linha de parâmetros" };
    return { equipe: lerModo(data.modo_equipe), diaria: lerModo(data.modo_diaria) };
  } catch (e) {
    return { ...EQUIPE_DESLIGADA, erro: String((e as Error)?.message ?? e) };
  }
}

/** O texto do resumo quando a R10 sai (spec-fase3 §7.6, d15): a ficha das 19:30 a substitui no instante em que liga. */
export const R10_DESLIGADA = "desligada: a ficha da agenda substitui";

/**
 * A R10 (o lembrete interno de OS agendada) sai no mesmo instante em que a ficha da agenda liga (modo_equipe = 'ligado';
 * decisão d13 do dono: a regra antiga sai no dia em que a substituta entra). Sombra e desligado = a R10 continua.
 */
export function r10DesligadaPelaAgenda(m: Pick<ModosDaEquipe, "equipe">): string | null {
  return m.equipe === "ligado" ? R10_DESLIGADA : null;
}
