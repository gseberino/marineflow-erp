// A agenda automática está ligada? (Agenda de Produção, Fase 2, P4 — 24/10/2026.)
//
// Os caminhos que agendam e mudam status (a tela "Agendar OS", o botão da R1, a aprovação com PIN, o
// schedule_service_order) perguntam aqui, a cada chamada, o agenda_config.modo_proposta:
//   · fora de 'ligado' (desligado, sombra): a data da OS é gravada como antes e o status vai pela porta única
//     (os_transicionar_status);
//   · em 'ligado': a data é da agenda — a tela e a aprovação chamam agenda_marcar_os, e o assistente deixa o rascunho
//     (agenda_rascunho_marcar) para o *grava* do dono. Gravar scheduled_* direto daria o erro do gatilho do banco.
//
// Leitura que falha aqui NÃO liga nada: erro, tabela ausente (migrations da Fase 1 ainda não aplicadas), linha ausente
// ou valor estranho = 'desligado', ou seja, o caminho de hoje. Se a agenda estiver ligada de verdade, o gatilho das datas
// recusa a escrita direta com a frase que diz o que fazer: o erro aparece, nunca uma data errada calada.
//
// Este arquivo não importa nada de propósito: a tela (Vite) o carrega por caminho relativo, como service-order-status.ts e
// agenda-dia.ts, e as Edge Functions (Deno) importam direto.

// deno-lint-ignore no-explicit-any
type Cliente = any;

export type ModoDaProposta = "desligado" | "sombra" | "ligado";

/** 'ligado', ' Sombra ', '"sombra"' → o modo; qualquer outra coisa → 'desligado'. */
export function lerModoDaProposta(v: unknown): ModoDaProposta {
  const s = typeof v === "string" ? v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase() : "";
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

/** agenda_config.modo_proposta (uma linha). Nunca lança: erro de leitura = 'desligado' (o caminho de hoje). */
export async function modoDaPropostaNoBanco(db: Cliente): Promise<ModoDaProposta> {
  try {
    const { data, error } = await db.from("agenda_config").select("modo_proposta").maybeSingle();
    if (error) return "desligado";
    return lerModoDaProposta(data?.modo_proposta);
  } catch {
    return "desligado";
  }
}

/**
 * O favorecido (payees) ligado ao login do técnico: é a "pessoa" da agenda (a alocação é por favorecido, com ou sem
 * login). null = o login não tem favorecido ativo (a agenda escolhe a equipe). Erro de leitura lança: escolher "ninguém"
 * por engano mudaria quem vai.
 */
export async function favorecidoDoLogin(db: Cliente, userId: string | null | undefined): Promise<string | null> {
  if (!userId) return null;
  const { data, error } = await db.from("payees").select("id").eq("app_user_id", userId).eq("active", true).limit(1);
  if (error) throw error;
  return Array.isArray(data) && data[0]?.id ? String(data[0].id) : null;
}

/**
 * agenda_config.jornada_horas (Agenda de Produção, Fase 3, P7a): a jornada do dia de trabalho, que o aviso de sobrecarga
 * usa. Nunca lança. Tabela ausente (as migrations da Fase 1 ainda não aplicadas: PGRST205/42P01), sem linha ou valor
 * estranho = jornada null e erro null (quem chama usa JORNADA_PADRAO_HORAS, de _shared/agenda-dia.ts); outro erro vem em
 * `erro` para quem chama registrar.
 */
export async function jornadaHorasNoBanco(db: Cliente): Promise<{ jornada: number | null; erro: unknown }> {
  try {
    const { data, error } = await db.from("agenda_config").select("jornada_horas").limit(1);
    if (error) {
      const code = (error as { code?: unknown }).code;
      return { jornada: null, erro: code === "PGRST205" || code === "42P01" ? null : error };
    }
    const linha = Array.isArray(data) ? data[0] : data;
    const n = Number(linha?.jornada_horas);
    return { jornada: Number.isFinite(n) && n > 0 ? n : null, erro: null };
  } catch (e) {
    return { jornada: null, erro: e };
  }
}

/** A frase do diálogo de agendar com a agenda automática ligada. */
export const TEXTO_AGENDA_AUTOMATICA_LIGADA =
  "Com a agenda automática ligada, a agenda escolhe os turnos e a equipe dentro destes dias.";

/** O status em que a OC criada a partir da OS passa a OS para "aguardando peças" (pela porta, via 'oc'). Aguardando o
 *  cliente fica como está (era assim antes da porta); em andamento a porta mantém (NOVO-agenda-10). */
export const STATUS_QUE_A_OC_MOVE: readonly string[] = ["open", "approved", "scheduled", "in_progress"];
