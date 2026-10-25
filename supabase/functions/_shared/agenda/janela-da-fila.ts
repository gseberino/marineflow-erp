// A janela da agenda NA HORA DE ENVIAR (Agenda de Produção, Fase 3, P7b — NOVO-agenda-26).
//
// O banco já não deixa a mensagem da agenda entrar na fila fora da janela (o gatilho trg_agenda_fila_da_equipe, com a
// última tentativa e o teto do dia) e a rotina de 15 min faz falhar o que ficou para trás. Sobrava o worker: ele manda toda
// linha pendente com scheduled_for vencido, sem olhar a hora. Se ele (ou a plataforma) parar às 19:25 e voltar às 22:00, a
// ficha das 19:30 sairia às 22:00 — a mensagem fora de hora que fez o dono desligar os alertas em setembro de 2026. Aqui,
// item por item e na hora do envio, a mensagem de uma origem da agenda que está fora da janela dela vira FALHA com o motivo
// e não sai.
//
// SÓ as origens listadas em ORIGENS_DA_AGENDA. Hoje é só 'agenda-equipe' (a rotina da equipe). As mensagens ao cliente da
// Fase 5 entram aqui, cada uma com a janela dela (seg–sex e sáb com fim próprio; as colunas nascem em agenda_config na Fase
// 5) e a tabela do registro dela. Toda outra origem (o lembrete, a cobrança, a resposta ao cliente, o comprovante…) o
// worker manda como sempre: nem a configuração da agenda é lida (provado em whatsapp-queue-worker/enviar_test.ts).
//
// Os horários vêm do banco (agenda_config.equipe_janela_inicio / equipe_janela_fim, o DEFAULT de 20261026100000 é o único
// lugar do número). Na janela: o mesmo dia de Brasília em que a mensagem estava marcada, de [início, fim), nunca no domingo,
// e com o modo da agenda ligado (a equipe fora de 'ligado' = nada à equipe, como o gatilho da nova tentativa e a rotina).
// Leitura que falha = a mensagem da agenda NÃO sai (o lado seguro), com o erro no motivo.

// deno-lint-ignore no-explicit-any
type Db = any;

/** Uma janela de envio: o modo e o horário de Brasília, como agenda_config os guarda ("HH:MM" ou "HH:MM:SS"). */
export interface JanelaDeEnvio {
  ligado: boolean;
  inicio: string;
  fim: string;
}

/** As janelas que as origens da agenda usam (a Fase 5 acrescenta a do cliente). */
export interface JanelasDaAgenda {
  equipe: JanelaDeEnvio;
}

interface OrigemDaAgenda {
  /** qual janela vale para a origem */
  janela: keyof JanelasDaAgenda;
  /** a tabela do registro da mensagem (a linha da fila aponta para ela em source_ref_id / fila_id) */
  registro: "agenda_equipe_mensagens";
}

/** As origens da fila que só saem dentro da janela da agenda. Origem fora daqui: o worker manda como sempre. */
const ORIGENS_DA_AGENDA: Readonly<Record<string, OrigemDaAgenda>> = Object.freeze({
  "agenda-equipe": { janela: "equipe", registro: "agenda_equipe_mensagens" },
});

/** A linha da fila tem a janela da agenda? (só as origens de ORIGENS_DA_AGENDA) */
export function origemComJanelaDaAgenda(source: unknown): boolean {
  return typeof source === "string" && Object.prototype.hasOwnProperty.call(ORIGENS_DA_AGENDA, source);
}

/** Um SELECT em agenda_config. Erro, sem a linha ou horário ilegível = lança (quem chama não deixa a mensagem sair). */
export async function lerJanelasDaAgenda(db: Db): Promise<JanelasDaAgenda> {
  const { data, error } = await db.from("agenda_config")
    .select("modo_equipe, equipe_janela_inicio, equipe_janela_fim")
    .maybeSingle();
  if (error) throw new Error(String(error.message ?? error.code ?? "erro na leitura de agenda_config"));
  if (!data) throw new Error("agenda_config sem a linha de parâmetros");
  const inicio = String(data.equipe_janela_inicio ?? "");
  const fim = String(data.equipe_janela_fim ?? "");
  if (segundosDoDia(inicio) === null || segundosDoDia(fim) === null) {
    throw new Error(`a janela da equipe está ilegível (${inicio || "—"} a ${fim || "—"})`);
  }
  const modo = typeof data.modo_equipe === "string" ? data.modo_equipe.trim().toLowerCase() : "";
  return { equipe: { ligado: modo === "ligado", inicio, fim } };
}

/** "07:30" / "07:30:00" → segundos desde a meia-noite; outra coisa → null. */
function segundosDoDia(hora: string): number | null {
  const m = /^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/.exec(hora.trim());
  if (!m) return null;
  const h = Number(m[1]), min = Number(m[2]), s = Number(m[3] ?? "0");
  if (h > 23 || min > 59 || s > 59) return null;
  return (h * 60 + min) * 60 + s;
}

/** "07:30:00" → "07:30" (o texto do motivo). */
function horaCurta(hora: string): string {
  return hora.trim().slice(0, 5);
}

/** O dia (AAAA-MM-DD), o dia da semana (domingo = 0) e os segundos do dia em Brasília, sem depender do fuso do servidor. */
export function instanteEmBrasilia(quando: Date): { dia: string; diaSemana: number; segundos: number } {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Sao_Paulo", weekday: "short", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
  });
  const p: Record<string, string> = {};
  for (const { type, value } of fmt.formatToParts(quando)) p[type] = value;
  const dias: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  const h = Number(p.hour) % 24;
  return {
    dia: `${p.year}-${p.month}-${p.day}`,
    diaSemana: dias[p.weekday] ?? 0,
    segundos: (h * 60 + Number(p.minute)) * 60 + Number(p.second),
  };
}

/** Por que a mensagem não sai: o motivo (a lista fechada de agenda_equipe_mensagens.recusa_motivo) e o texto da fila. */
export interface RecusaDaJanela {
  motivo: "janela" | "domingo" | "modo";
  texto: string;
}

/**
 * A mensagem de uma origem da agenda pode sair AGORA? null = pode (ou a origem não é da agenda). `janelas` null = a leitura
 * falhou (`erroDaLeitura` diz por quê): não sai.
 */
export function recusaNaHoraDeEnviar(
  item: { source?: unknown; scheduled_for?: unknown },
  agora: Date,
  janelas: JanelasDaAgenda | null,
  erroDaLeitura?: string,
): RecusaDaJanela | null {
  if (!origemComJanelaDaAgenda(item.source)) return null;
  const origem = String(item.source);
  if (!janelas) {
    return { motivo: "janela", texto: `${origem}: não consegui ler a janela da agenda (${erroDaLeitura ?? "sem resposta"}): não saiu` };
  }
  const j = janelas[ORIGENS_DA_AGENDA[origem].janela];
  if (!j.ligado) return { motivo: "modo", texto: `${origem}: modo_equipe saiu de ligado` };
  const ag = instanteEmBrasilia(agora);
  if (ag.diaSemana === 0) return { motivo: "domingo", texto: `${origem}: domingo, não sai (nunca no domingo)` };
  const marcada = new Date(String(item.scheduled_for ?? ""));
  if (isNaN(marcada.getTime())) return { motivo: "janela", texto: `${origem}: sem a hora marcada: não saiu` };
  const dia = instanteEmBrasilia(marcada).dia;
  if (dia !== ag.dia) {
    return { motivo: "janela", texto: `${origem}: era para ${dia.slice(8, 10)}/${dia.slice(5, 7)} e não saiu no dia dela` };
  }
  const ini = segundosDoDia(j.inicio)!, fim = segundosDoDia(j.fim)!;
  if (ag.segundos < ini || ag.segundos >= fim) {
    return { motivo: "janela", texto: `${origem}: fora da janela na hora de enviar (${horaCurta(j.inicio)}–${horaCurta(j.fim)}): não saiu` };
  }
  return null;
}

/**
 * Marca a linha da fila como falha (com o motivo; nada é enviado, as tentativas não contam) e o registro da mensagem como
 * recusado pelo mesmo motivo, se ele ainda estava "enfileirada". Devolve o erro da escrita (ou null) — quem chama registra
 * e segue: a mensagem não sai de qualquer jeito.
 */
export async function recusarNaFila(db: Db, item: { id: string; source?: unknown }, recusa: RecusaDaJanela): Promise<string | null> {
  const erros: string[] = [];
  const { error: e1 } = await db.from("whatsapp_send_queue")
    .update({ status: "failed", failed_reason: recusa.texto, processing_started_at: null })
    .eq("id", item.id);
  if (e1) erros.push(`fila: ${e1.message ?? e1.code ?? e1}`);
  const origem = typeof item.source === "string" ? ORIGENS_DA_AGENDA[item.source] : undefined;
  if (origem) {
    const { error: e2 } = await db.from(origem.registro)
      .update({ estado: "recusada", recusa_motivo: recusa.motivo })
      .eq("fila_id", item.id)
      .eq("estado", "enfileirada");
    if (e2) erros.push(`${origem.registro}: ${e2.message ?? e2.code ?? e2}`);
  }
  return erros.length ? erros.join("; ") : null;
}
