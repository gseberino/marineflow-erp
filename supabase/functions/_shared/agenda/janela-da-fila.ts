// A janela da agenda NA HORA DE ENVIAR (Agenda de Produção, Fase 3, P7b — NOVO-agenda-26).
//
// O banco já não deixa a mensagem da agenda entrar na fila fora da janela (o gatilho trg_agenda_fila_da_equipe, com a
// última tentativa e o teto do dia) e a rotina de 15 min faz falhar o que ficou para trás. Sobrava o worker: ele manda toda
// linha pendente com scheduled_for vencido, sem olhar a hora. Se ele (ou a plataforma) parar às 19:25 e voltar às 22:00, a
// ficha das 19:30 sairia às 22:00 — a mensagem fora de hora que fez o dono desligar os alertas em setembro de 2026. Aqui,
// item por item e na hora do envio, a mensagem de uma origem da agenda que está fora da janela dela vira FALHA com o motivo
// e não sai.
//
// SÓ as origens listadas em ORIGENS_DA_AGENDA: 'agenda-equipe' (a rotina da equipe), desde a Fase 4 (P5)
// 'agenda-fornecedor' (a pergunta ao fornecedor nos terços do prazo) e desde a Fase 5 (P2) 'agenda-cliente' (as
// mensagens-modelo ao cliente), cada uma com a janela dela e a tabela do registro dela. Toda outra origem (o lembrete, a cobrança, a resposta ao cliente, o comprovante…) o
// worker manda como sempre: nem a configuração da agenda é lida (provado em whatsapp-queue-worker/enviar_test.ts).
//
// Os horários vêm do banco (agenda_config.equipe_janela_inicio / equipe_janela_fim, o DEFAULT de 20261026100000 é o único
// lugar do número). Na janela: o mesmo dia de Brasília em que a mensagem estava marcada, de [início, fim), nunca no domingo,
// e com o modo da agenda ligado (a equipe fora de 'ligado' = nada à equipe, como o gatilho da nova tentativa e a rotina).
// Leitura que falha = a mensagem da agenda NÃO sai (o lado seguro), com o erro no motivo.
//
// Revisão da Fase 3 (C1 — NOVO-agenda-28 e R7): a resposta DIRETA a uma mensagem que o técnico acabou de mandar ("Tá bom,
// aviso o Gustavo." ao "não vou" das 07:10; a ficha ao "o que tem pra amanhã") tem uma janela própria, também aqui: de
// agenda_config.equipe_resposta_direta_inicio até antes de equipe_resposta_direta_fim, no dia dela, nunca no domingo, com a
// equipe ligada e só até equipe_resposta_direta_prazo depois da mensagem dele. A linha é reconhecida pela chave (a
// dedupe_key da mensagem, "agenda-equipe:resposta:…"; a trava da fila no banco recusa a linha com outra chave). Fora disso
// o banco põe a resposta no início da janela da equipe (_agenda_equipe_quando_responder): aí ela é uma linha como as
// outras. A regra é a mesma do banco (_agenda_equipe_fora_da_janela).
//
// Fase 4 (P5): a mensagem-modelo ao FORNECEDOR ("a entrega continua prevista para qua 04/11?", source 'agenda-fornecedor',
// registro agenda_fornecedor_mensagens) é a 2ª origem. A janela dela é outra: agenda_config.fornecedor_janela_inicio /
// fornecedor_janela_fim, segunda a sexta (o sábado só com fornecedor_sabado; nunca o domingo) e modo_fornecedor = 'ligado'
// — a mesma regra do banco (_agenda_fornecedor_fora_da_janela), nas três travas. A configuração de cada janela é lida num
// SELECT À PARTE, só quando o lote tem linha daquela origem: o worker publicado antes da migration da Fase 4 continua
// mandando a ficha da equipe (a leitura da equipe não pede coluna nova), e a linha do fornecedor, sem as colunas, não sai.
//
// Fase 5 (P2): a mensagem-modelo ao CLIENTE (source 'agenda-cliente', registro agenda_cliente_mensagens) é a 3ª origem. A
// janela dela: agenda_config.cliente_janela_inicio até cliente_janela_fim de segunda a sexta e até cliente_sabado_fim no
// sábado, nunca no domingo nem em feriado (feriadoDoDia, a lista de _shared/secretario/feriados.ts que o banco espelha em
// agenda_feriado) e modo_cliente = 'ligado' — a regra do banco (_agenda_cliente_fora_da_janela). A janela do cliente também
// é lida num SELECT à parte, só com linha de cliente no lote. O worker manda no máximo UMA linha de cliente por lote e,
// antes de mandar, pergunta ao banco se ela ainda vale (agenda_cliente_pode_sair: a revalidação na saída; recusaDoBanco
// lê a resposta) — ver whatsapp-queue-worker/enviar.ts.
//
// Correção de 29/10 (P4): o AVISO DO GESTOR ao dono (source 'agenda-dono', registro agenda_dono_avisos: o que a agenda mudou
// sozinha, o que ficou de fora e as perguntas que destravam) é a 4ª origem. A janela dela: agenda_config.gestor_aviso_inicio
// até gestor_aviso_fim, de segunda a sábado, nunca no domingo, no dia em que estava marcada, e só com o aviso ligado
// (modo_proposta e modo_vigia em 'ligado' e gestor_aviso_dia_max > 0) — a regra do banco (_agenda_aviso_fora_da_janela), nas
// três travas. Também lida num SELECT à parte, só com linha do aviso no lote. Fora da janela a linha vira falha e o aviso fica
// recusado; o agenda_aviso_conferir devolve as mudanças a "por contar" e elas saem no próximo aviso.

import { feriadoDoDia } from "../secretario/feriados.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** Uma janela de envio: o modo e o horário de Brasília, como agenda_config os guarda ("HH:MM" ou "HH:MM:SS"). */
export interface JanelaDeEnvio {
  ligado: boolean;
  inicio: string;
  fim: string;
}

/** (Fase 4, P5) A janela do fornecedor: a de envio + o sábado (agenda_config.fornecedor_sabado). */
export interface JanelaDoFornecedor extends JanelaDeEnvio {
  sabado: boolean;
}

/** (Fase 5, P2) A janela do cliente: a de envio (segunda a sexta) + o fim do sábado (agenda_config.cliente_sabado_fim). */
export interface JanelaDoCliente extends JanelaDeEnvio {
  sabadoFim: string;
}

/** (C1) A janela da resposta direta: o horário de Brasília e o prazo depois da mensagem do técnico. */
export interface JanelaDaRespostaDireta {
  inicio: string;
  fim: string;
  /** agenda_config.equipe_resposta_direta_prazo, em segundos */
  prazoSegundos: number;
}

/**
 * As janelas que as origens da agenda usam (a Fase 5 acrescenta a do cliente). Cada uma vem da sua leitura
 * (lerJanelasDaAgenda com o nome dela): a que não foi lida falta, e a linha que precisa dela não sai.
 */
export interface JanelasDaAgenda {
  equipe?: JanelaDeEnvio;
  /** (C1, NOVO-agenda-28) a resposta direta à equipe (lida junto com a da equipe) */
  respostaDireta?: JanelaDaRespostaDireta;
  /** (Fase 4, P5) a mensagem ao fornecedor */
  fornecedor?: JanelaDoFornecedor;
  /** (Fase 5, P2) a mensagem ao cliente */
  cliente?: JanelaDoCliente;
  /** (correção de 29/10, P4) o aviso do gestor ao dono */
  dono?: JanelaDeEnvio;
}

/** O nome de uma janela (a chave em JanelasDaAgenda e o que lerJanelasDaAgenda lê). */
export type NomeDaJanela = "equipe" | "fornecedor" | "cliente" | "dono";

interface OrigemDaAgenda {
  /** qual janela vale para a origem */
  janela: NomeDaJanela;
  /** a coluna do modo (o texto do motivo quando ele saiu de ligado) */
  modo: "modo_equipe" | "modo_fornecedor" | "modo_cliente" | "modo_vigia";
  /** (P4) o texto do motivo quando a origem depende de mais de uma chave (no lugar de "<modo> saiu de ligado") */
  textoDoModo?: string;
  /** a tabela do registro da mensagem (a linha da fila aponta para ela em source_ref_id / fila_id) */
  registro: "agenda_equipe_mensagens" | "agenda_fornecedor_mensagens" | "agenda_cliente_mensagens" | "agenda_dono_avisos";
  /** (C1) a resposta direta da origem: a linha cuja chave começa por este prefixo tem também a janela respostaDireta */
  respostaDireta?: { prefixoDaChave: string };
}

/** As origens da fila que só saem dentro da janela da agenda. Origem fora daqui: o worker manda como sempre. */
const ORIGENS_DA_AGENDA: Readonly<Record<string, OrigemDaAgenda>> = Object.freeze({
  "agenda-equipe": {
    janela: "equipe",
    modo: "modo_equipe",
    registro: "agenda_equipe_mensagens",
    respostaDireta: { prefixoDaChave: "agenda-equipe:resposta:" },
  },
  // Fase 4 (P5): a pergunta ao fornecedor nos terços de um prazo longo (agenda_material_vigiar). Sem resposta direta.
  "agenda-fornecedor": {
    janela: "fornecedor",
    modo: "modo_fornecedor",
    registro: "agenda_fornecedor_mensagens",
  },
  // Fase 5 (P2): a mensagem-modelo ao cliente (M1–M10). Sem resposta direta; no máximo 1 por lote e a revalidação pelo banco
  // antes de mandar (enviar.ts).
  "agenda-cliente": {
    janela: "cliente",
    modo: "modo_cliente",
    registro: "agenda_cliente_mensagens",
  },
  // Correção de 29/10 (P4): o aviso do gestor ao dono (o que a agenda mudou sozinha). Sem resposta direta.
  "agenda-dono": {
    janela: "dono",
    modo: "modo_vigia",
    textoDoModo: "o aviso do gestor saiu de ligado (modo_proposta, modo_vigia ou gestor_aviso_dia_max)",
    registro: "agenda_dono_avisos",
  },
});

/** (Fase 5, P2) A linha da fila é mensagem ao cliente? (a do máximo de 1 por lote e da revalidação pelo banco) */
export function ehMensagemAoCliente(source: unknown): boolean {
  return source === "agenda-cliente";
}

/** A linha da fila tem a janela da agenda? (só as origens de ORIGENS_DA_AGENDA) */
export function origemComJanelaDaAgenda(source: unknown): boolean {
  return typeof source === "string" && Object.prototype.hasOwnProperty.call(ORIGENS_DA_AGENDA, source);
}

/** (Fase 4, P5) Qual janela vale para a linha da fila (null = a origem não é da agenda: sai como sempre). */
export function janelaDaOrigem(source: unknown): NomeDaJanela | null {
  return origemComJanelaDaAgenda(source) ? ORIGENS_DA_AGENDA[String(source)].janela : null;
}

/**
 * Um SELECT em agenda_config, só das colunas da janela pedida (a da equipe, por padrão, como antes da Fase 4). Erro, sem a
 * linha ou horário ilegível = lança (quem chama não deixa a mensagem sair).
 */
export async function lerJanelasDaAgenda(db: Db, qual: NomeDaJanela = "equipe"): Promise<JanelasDaAgenda> {
  if (qual === "fornecedor") return { fornecedor: await lerJanelaDoFornecedor(db) };
  if (qual === "cliente") return { cliente: await lerJanelaDoCliente(db) };
  if (qual === "dono") return { dono: await lerJanelaDoDono(db) };
  const { data, error } = await db.from("agenda_config")
    .select(COLUNAS_DA_JANELA)
    .maybeSingle();
  if (error) throw new Error(String(error.message ?? error.code ?? "erro na leitura de agenda_config"));
  if (!data) throw new Error("agenda_config sem a linha de parâmetros");
  const inicio = String(data.equipe_janela_inicio ?? "");
  const fim = String(data.equipe_janela_fim ?? "");
  if (segundosDoDia(inicio) === null || segundosDoDia(fim) === null) {
    throw new Error(`a janela da equipe está ilegível (${inicio || "—"} a ${fim || "—"})`);
  }
  const rInicio = String(data.equipe_resposta_direta_inicio ?? "");
  const rFim = String(data.equipe_resposta_direta_fim ?? "");
  const prazo = intervaloEmSegundos(data.equipe_resposta_direta_prazo);
  if (segundosDoDia(rInicio) === null || segundosDoDia(rFim) === null || prazo === null) {
    throw new Error(`a janela da resposta direta está ilegível (${rInicio || "—"} a ${rFim || "—"}, prazo ${
      String(data.equipe_resposta_direta_prazo ?? "—")})`);
  }
  const modo = typeof data.modo_equipe === "string" ? data.modo_equipe.trim().toLowerCase() : "";
  return {
    equipe: { ligado: modo === "ligado", inicio, fim },
    respostaDireta: { inicio: rInicio, fim: rFim, prazoSegundos: prazo },
  };
}

/** As colunas que a janela da equipe lê (um SELECT por lote). */
export const COLUNAS_DA_JANELA =
  "modo_equipe, equipe_janela_inicio, equipe_janela_fim, equipe_resposta_direta_inicio, equipe_resposta_direta_fim, " +
  "equipe_resposta_direta_prazo";

/** (Fase 4, P5) As colunas que a janela do fornecedor lê (um SELECT à parte, só com linha do fornecedor no lote). */
export const COLUNAS_DA_JANELA_DO_FORNECEDOR =
  "modo_fornecedor, fornecedor_janela_inicio, fornecedor_janela_fim, fornecedor_sabado";

/** (Fase 4, P5) A janela do fornecedor. Erro, sem a linha, horário ilegível ou o sábado que não é sim/não = lança. */
async function lerJanelaDoFornecedor(db: Db): Promise<JanelaDoFornecedor> {
  const { data, error } = await db.from("agenda_config")
    .select(COLUNAS_DA_JANELA_DO_FORNECEDOR)
    .maybeSingle();
  if (error) throw new Error(String(error.message ?? error.code ?? "erro na leitura de agenda_config"));
  if (!data) throw new Error("agenda_config sem a linha de parâmetros");
  const inicio = String(data.fornecedor_janela_inicio ?? "");
  const fim = String(data.fornecedor_janela_fim ?? "");
  if (segundosDoDia(inicio) === null || segundosDoDia(fim) === null) {
    throw new Error(`a janela do fornecedor está ilegível (${inicio || "—"} a ${fim || "—"})`);
  }
  if (typeof data.fornecedor_sabado !== "boolean") {
    throw new Error(`o sábado do fornecedor está ilegível (${String(data.fornecedor_sabado ?? "—")})`);
  }
  const modo = typeof data.modo_fornecedor === "string" ? data.modo_fornecedor.trim().toLowerCase() : "";
  return { ligado: modo === "ligado", inicio, fim, sabado: data.fornecedor_sabado };
}

/** (Fase 5, P2) As colunas que a janela do cliente lê (um SELECT à parte, só com linha de cliente no lote). */
export const COLUNAS_DA_JANELA_DO_CLIENTE = "modo_cliente, cliente_janela_inicio, cliente_janela_fim, cliente_sabado_fim";

/** (Fase 5, P2) A janela do cliente. Erro, sem a linha ou horário ilegível = lança (a linha não sai). */
async function lerJanelaDoCliente(db: Db): Promise<JanelaDoCliente> {
  const { data, error } = await db.from("agenda_config")
    .select(COLUNAS_DA_JANELA_DO_CLIENTE)
    .maybeSingle();
  if (error) throw new Error(String(error.message ?? error.code ?? "erro na leitura de agenda_config"));
  if (!data) throw new Error("agenda_config sem a linha de parâmetros");
  const inicio = String(data.cliente_janela_inicio ?? "");
  const fim = String(data.cliente_janela_fim ?? "");
  const sabadoFim = String(data.cliente_sabado_fim ?? "");
  if (segundosDoDia(inicio) === null || segundosDoDia(fim) === null || segundosDoDia(sabadoFim) === null) {
    throw new Error(`a janela do cliente está ilegível (${inicio || "—"} a ${fim || "—"}, sábado até ${sabadoFim || "—"})`);
  }
  const modo = typeof data.modo_cliente === "string" ? data.modo_cliente.trim().toLowerCase() : "";
  return { ligado: modo === "ligado", inicio, fim, sabadoFim };
}

/** (correção de 29/10, P4) As colunas que a janela do aviso do gestor lê (um SELECT à parte, só com linha do aviso no lote). */
export const COLUNAS_DA_JANELA_DO_DONO = "modo_proposta, modo_vigia, gestor_aviso_dia_max, gestor_aviso_inicio, gestor_aviso_fim";

/**
 * (correção de 29/10, P4) A janela do aviso do gestor: ligado = a agenda automática e a vigia em 'ligado' e algum aviso por
 * dia (gestor_aviso_dia_max > 0), a regra de _agenda_aviso_ligado. Erro, sem a linha, horário ou teto ilegível = lança (a
 * linha não sai).
 */
async function lerJanelaDoDono(db: Db): Promise<JanelaDeEnvio> {
  const { data, error } = await db.from("agenda_config")
    .select(COLUNAS_DA_JANELA_DO_DONO)
    .maybeSingle();
  if (error) throw new Error(String(error.message ?? error.code ?? "erro na leitura de agenda_config"));
  if (!data) throw new Error("agenda_config sem a linha de parâmetros");
  const inicio = String(data.gestor_aviso_inicio ?? "");
  const fim = String(data.gestor_aviso_fim ?? "");
  if (segundosDoDia(inicio) === null || segundosDoDia(fim) === null) {
    throw new Error(`a janela do aviso do gestor está ilegível (${inicio || "—"} a ${fim || "—"})`);
  }
  const teto = data.gestor_aviso_dia_max;
  if (typeof teto !== "number" || !Number.isInteger(teto)) {
    throw new Error(`o teto do aviso do gestor está ilegível (${String(teto ?? "—")})`);
  }
  const modo = (v: unknown) => typeof v === "string" ? v.trim().toLowerCase() : "";
  return { ligado: modo(data.modo_proposta) === "ligado" && modo(data.modo_vigia) === "ligado" && teto > 0, inicio, fim };
}

/** O interval do Postgres como o PostgREST devolve ("00:10:00", "10 minutes", "PT10M") → segundos; outra coisa → null. */
export function intervaloEmSegundos(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v) && v >= 0) return v;
  if (typeof v !== "string") return null;
  const t = v.trim().toLowerCase();
  let m = /^(\d{1,3}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/.exec(t);
  if (m) {
    const h = Number(m[1]), min = Number(m[2]), s = Number(m[3] ?? "0");
    return min > 59 || s > 59 ? null : (h * 60 + min) * 60 + s;
  }
  m = /^(\d+) ?(?:min|mins|minute|minutes)$/.exec(t);
  if (m) return Number(m[1]) * 60;
  m = /^pt(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/.exec(t);
  if (m && (m[1] || m[2] || m[3])) return (Number(m[1] ?? 0) * 60 + Number(m[2] ?? 0)) * 60 + Number(m[3] ?? 0);
  return null;
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

/**
 * Por que a mensagem não sai: o motivo (as listas fechadas de agenda_equipe_mensagens.recusa_motivo,
 * agenda_fornecedor_mensagens.recusa_motivo e agenda_cliente_mensagens.recusa_motivo; fim_de_semana só no fornecedor;
 * feriado e os da revalidação só no cliente) e o texto da fila.
 */
export interface RecusaDaJanela {
  motivo: MotivoDaJanela | MotivoDoBanco;
  texto: string;
}

/** Os motivos que a janela decide aqui. */
export type MotivoDaJanela = "janela" | "domingo" | "modo" | "fim_de_semana" | "feriado";

/**
 * (Fase 5, P2) O motivo que agenda_cliente_pode_sair devolve (o tipo fora das ondas, a validade, os da revalidação): um
 * nome da lista fechada de agenda_cliente_mensagens.recusa_motivo. A lista mora no banco (o CHECK confere de novo quando
 * recusarNaFila grava o motivo); aqui só se exige que seja um nome (letras minúsculas, dígitos e "_").
 */
export type MotivoDoBanco = string;

const NOME_DE_MOTIVO = /^[a-z][a-z0-9_]{1,40}$/;

/**
 * (Fase 5, P2) A resposta de agenda_cliente_pode_sair → a recusa (null = pode sair). Erro na chamada, resposta que não é
 * {pode: true} ou motivo que não é um nome = não sai (esse vira janela, o lado seguro), com o porquê no texto.
 */
export function recusaDoBanco(
  resposta: { data?: unknown; error?: unknown },
  source = "agenda-cliente",
): RecusaDaJanela | null {
  if (resposta.error) {
    const e = resposta.error as { message?: unknown; code?: unknown };
    return {
      motivo: "janela",
      texto: `${source}: não consegui perguntar ao banco se ainda vale (${String(e?.message ?? e?.code ?? "erro")}): não saiu`,
    };
  }
  const d = (resposta.data ?? null) as { pode?: unknown; motivo?: unknown } | null;
  if (d && d.pode === true) return null;
  const dito = typeof d?.motivo === "string" ? d.motivo : null;
  const motivo = dito && NOME_DE_MOTIVO.test(dito) ? dito : "janela";
  return { motivo, texto: `${source}: o banco diz que não sai mais (${dito ?? "sem resposta"}): não saiu` };
}

/**
 * (C1) A linha é a resposta direta da origem? Pela chave da mensagem (a trava da fila no banco garante que a chave da linha
 * é a da mensagem registrada).
 */
export function ehRespostaDireta(item: { source?: unknown; dedupe_key?: unknown }): boolean {
  if (!origemComJanelaDaAgenda(item.source)) return false;
  const rd = ORIGENS_DA_AGENDA[String(item.source)].respostaDireta;
  return !!rd && typeof item.dedupe_key === "string" && item.dedupe_key.startsWith(rd.prefixoDaChave);
}

/**
 * A mensagem de uma origem da agenda pode sair AGORA? null = pode (ou a origem não é da agenda). `janelas` null = a leitura
 * falhou (`erroDaLeitura` diz por quê): não sai.
 */
export function recusaNaHoraDeEnviar(
  item: { source?: unknown; scheduled_for?: unknown; dedupe_key?: unknown; created_at?: unknown },
  agora: Date,
  janelas: JanelasDaAgenda | null,
  erroDaLeitura?: string,
): RecusaDaJanela | null {
  if (!origemComJanelaDaAgenda(item.source)) return null;
  const origem = String(item.source);
  const def = ORIGENS_DA_AGENDA[origem];
  const j = janelas?.[def.janela];
  if (!janelas || !j) {
    return {
      motivo: "janela",
      texto: `${origem}: não consegui ler a janela da agenda (${erroDaLeitura ?? `sem a janela ${def.janela}`}): não saiu`,
    };
  }
  if (!j.ligado) return { motivo: "modo", texto: `${origem}: ${def.textoDoModo ?? `${def.modo} saiu de ligado`}` };
  const ag = instanteEmBrasilia(agora);
  if (ag.diaSemana === 0) return { motivo: "domingo", texto: `${origem}: domingo, não sai (nunca no domingo)` };
  // (Fase 5, P2) o cliente: nunca em feriado (a lista de feriados.ts, a mesma do banco)
  if (def.janela === "cliente") {
    const feriado = feriadoDoDia(ag.dia);
    if (feriado) return { motivo: "feriado", texto: `${origem}: feriado (${feriado}), não sai` };
  }
  // (Fase 4, P5) o fornecedor: segunda a sexta; o sábado só com fornecedor_sabado
  if (def.janela === "fornecedor" && ag.diaSemana === 6 && !(j as JanelaDoFornecedor).sabado) {
    return { motivo: "fim_de_semana", texto: `${origem}: sábado, não sai (só de segunda a sexta)` };
  }
  const marcada = new Date(String(item.scheduled_for ?? ""));
  if (isNaN(marcada.getTime())) return { motivo: "janela", texto: `${origem}: sem a hora marcada: não saiu` };
  const dia = instanteEmBrasilia(marcada).dia;
  if (dia !== ag.dia) {
    return { motivo: "janela", texto: `${origem}: era para ${dia.slice(8, 10)}/${dia.slice(5, 7)} e não saiu no dia dela` };
  }
  const ini = segundosDoDia(j.inicio)!;
  // (Fase 5, P2) o cliente no sábado: até cliente_sabado_fim
  const fimDoDia = def.janela === "cliente" && ag.diaSemana === 6 ? (j as JanelaDoCliente).sabadoFim : j.fim;
  const fim = segundosDoDia(fimDoDia)!;
  if (ag.segundos >= ini && ag.segundos < fim) return null;
  // (C1, NOVO-agenda-28) a resposta direta a uma mensagem do técnico: a janela dela, e só até o prazo depois da mensagem
  // (a hora mais cedo entre a marcada e a de quando a linha entrou na fila)
  if (ehRespostaDireta(item) && janelas.respostaDireta) {
    const r = janelas.respostaDireta;
    const rIni = segundosDoDia(r.inicio)!, rFim = segundosDoDia(r.fim)!;
    const entrou = new Date(String(item.created_at ?? ""));
    const desde = Math.min(marcada.getTime(), isNaN(entrou.getTime()) ? marcada.getTime() : entrou.getTime());
    const limite = new Date(desde);
    limite.setSeconds(limite.getSeconds() + r.prazoSegundos);
    if (ag.segundos >= rIni && ag.segundos < rFim && agora.getTime() >= desde && agora.getTime() <= limite.getTime()) return null;
    return {
      motivo: "janela",
      texto: `${origem}: a resposta direta só sai até ${Math.round(r.prazoSegundos / 60)} min depois da mensagem dele, de ${
        horaCurta(r.inicio)} a ${horaCurta(r.fim)}: não saiu`,
    };
  }
  return { motivo: "janela", texto: `${origem}: fora da janela na hora de enviar (${horaCurta(j.inicio)}–${horaCurta(fimDoDia)}): não saiu` };
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
