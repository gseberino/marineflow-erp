import type { ToolDef } from "./registry.ts";
import { horariosDeBrasilia } from "../fuso.ts";
import { parseRRule } from "../../recurrence.ts";
import { ehTipoDeEntidadeValido, RELATED_ENTITY_TYPES } from "../../agenda-entity-types.ts";

// Agenda & Tarefas 2.0 — tool set completo (Fase 3 do plano
// plans/marineflow-agenda-tarefas.md §8). O agente é operador da agenda:
// consulta, cria com vínculo/lembrete, conclui, reagenda e enxerga conflitos.
// Fuso: America/Sao_Paulo (-03, sem DST desde 2019).

const BRT_OFFSET = "-03:00";

/** Janela [00:00, 24:00) de um dia local BRT em ISO UTC. */
export function dayRangeBRT(date?: string): { from: string; to: string; day: string } {
  const day = date && /^\d{4}-\d{2}-\d{2}$/.test(date)
    ? date
    : new Date(Date.now() - 3 * 3600000).toISOString().slice(0, 10);
  const from = new Date(`${day}T00:00:00${BRT_OFFSET}`).toISOString();
  const to = new Date(new Date(from).getTime() + 86400000).toISOString();
  return { from, to, day };
}

// ─── Valores aceitos (07/10/2026, frente operacional) ──────────────────────────────────────
// status e priority não têm CHECK no banco (só a tela limita as opções): um "concluida" ou
// "alta" vindo do modelo gravava texto que nenhuma tela nem filtro reconhece. A lista é a do
// AgendaTaskDialog; a palavra em português vira o valor.
const STATUS_DA_TAREFA: Record<string, string> = {
  pending: "pending", pendente: "pending", aberta: "pending", reaberta: "pending",
  in_progress: "in_progress", "em andamento": "in_progress", andamento: "in_progress",
  done: "done", concluida: "done", concluido: "done", feita: "done", feito: "done",
  cancelled: "cancelled", cancelada: "cancelled", cancelado: "cancelled",
};
const PRIORIDADE_DA_TAREFA: Record<string, string> = {
  low: "low", baixa: "low", normal: "normal", media: "normal",
  high: "high", alta: "high", urgent: "urgent", urgente: "urgent",
};

const semAcento = (s: unknown) =>
  String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/_/g, " ").replace(/\s+/g, " ").trim();

/** "concluída" → done; null = não veio; { error } = veio e não é status de tarefa. */
export function statusDaTarefa(v: unknown): string | null | { error: string } {
  if (v == null || v === "") return null;
  const s = STATUS_DA_TAREFA[semAcento(v)] ?? STATUS_DA_TAREFA[String(v)];
  return s ?? { error: `Status "${v}" não existe na agenda. Use: pendente, em andamento, concluída ou cancelada.` };
}

/** "alta" → high; null = não veio; { error } = veio e não é prioridade. */
export function prioridadeDaTarefa(v: unknown): string | null | { error: string } {
  if (v == null || v === "") return null;
  const p = PRIORIDADE_DA_TAREFA[semAcento(v)] ?? PRIORIDADE_DA_TAREFA[String(v)];
  return p ?? { error: `Prioridade "${v}" não existe. Use: baixa, normal, alta ou urgente.` };
}

// ─── Tarefa que se repete (07/10/2026, frente operacional) ─────────────────────────────────
// Caminho da tela: AgendaTaskDialog grava agenda_tasks.rrule ("FREQ=WEEKLY;UNTIL=20261231") na
// própria tarefa, que vira a "mãe" da série; o motor (task-automations, a cada 15 min,
// materializeRecurrences + _shared/recurrence.ts) cria as próximas ocorrências dos 30 dias
// seguintes com recurrence_parent_id = mãe. Editar a série apaga as ocorrências futuras ainda
// pendentes e o motor recria com os dados novos (useSaveAgendaTask). A tool faz o mesmo.
// O motor entende mais do que a tela oferece — INTERVAL ("a cada 15 dias") e BYDAY ("toda
// segunda e quinta") —, e é isso que as frases do dono pedem.
const DIAS_DA_SEMANA: Record<string, number> = {
  dom: 0, seg: 1, ter: 2, qua: 3, qui: 4, sex: 5, sab: 6,
  su: 0, mo: 1, tu: 2, we: 3, th: 4, fr: 5, sa: 6,
};
const CODIGO_DO_DIA = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
const NOME_DO_DIA = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"];
const BRT_MS = 3 * 3600_000;

export interface PedidoDeRepeticao {
  repetir?: unknown;
  repetir_a_cada?: unknown;
  dias_da_semana?: unknown;
  dia_do_mes?: unknown;
  repetir_ate?: unknown;
}

export function pediuRepeticao(a: PedidoDeRepeticao): boolean {
  return [a.repetir, a.repetir_a_cada, a.dias_da_semana, a.dia_do_mes, a.repetir_ate]
    .some((v) => v != null && v !== "" && !(Array.isArray(v) && v.length === 0));
}

/** Partes do instante na hora de Brasília (getUTC* sobre o instante deslocado). */
const local = (d: Date) => new Date(d.getTime() - BRT_MS);
const maisDias = (d: Date, n: number) => new Date(d.getTime() + n * 86_400_000);

/** Mesmo horário de Brasília, no dia `dia` do mês `mesesAFrente` depois do de `d`; null se o mês não tem o dia. */
function noDiaDoMes(d: Date, dia: number, mesesAFrente: number): Date | null {
  const l = local(d);
  const alvo = new Date(Date.UTC(l.getUTCFullYear(), l.getUTCMonth() + mesesAFrente, 1, l.getUTCHours(), l.getUTCMinutes(), l.getUTCSeconds()));
  alvo.setUTCDate(dia);
  if (alvo.getUTCDate() !== dia) return null;
  return new Date(alvo.getTime() + BRT_MS);
}

/** Texto curto da regra, para o dono conferir ("toda segunda", "a cada 15 dias até 31/12/2026"). */
export function descreverRepeticao(rrule: string | null | undefined, ancoraISO?: string | null): string | null {
  const r = rrule ? parseRRule(rrule) : null;
  if (!r) return null;
  let base: string;
  if (r.freq === "DAILY") base = r.interval > 1 ? `a cada ${r.interval} dias` : "todo dia";
  else if (r.freq === "WEEKLY") {
    // BYDAY vem no dia da semana de UTC (é o que o motor usa); o texto volta para Brasília.
    const desloc = ancoraISO ? (new Date(ancoraISO).getUTCDay() - local(new Date(ancoraISO)).getUTCDay() + 7) % 7 : 0;
    const dias = r.byday.length
      ? r.byday.map((d) => NOME_DO_DIA[(d - desloc + 7) % 7]).join(", ")
      : ancoraISO ? NOME_DO_DIA[local(new Date(ancoraISO)).getUTCDay()] : "semana";
    base = r.interval > 1 ? `a cada ${r.interval} semanas (${dias})` : `toda ${dias}`;
  } else {
    const dia = ancoraISO ? local(new Date(ancoraISO)).getUTCDate() : null;
    base = `${r.interval > 1 ? `a cada ${r.interval} meses` : "todo mês"}${dia ? `, dia ${dia}` : ""}`;
  }
  if (r.until) base += ` até ${r.until.toISOString().slice(0, 10).split("-").reverse().join("/")}`;
  return base;
}

/**
 * O pedido de repetição como se fala → a RRULE que o motor entende e a PRIMEIRA vez (âncora).
 * "IA pensa, sistema preenche": o modelo diz "semanal, segunda, 8h"; quem acha a próxima
 * segunda e escreve a regra é aqui.
 *  · âncora = o horário dado (due_at/scheduled_start_at) ou hoje 08:00 (o padrão da tela);
 *  · com dias da semana / dia do mês, a âncora anda para a frente até cair num dia da regra;
 *  · avancarSePassou (criar): a primeira vez nunca nasce no passado — seria uma tarefa já
 *    atrasada no minuto em que foi criada.
 * Dia da semana do BYDAY é o de UTC, porque é o que o motor compara (getUTCDay): às 21h de
 * Brasília já é o dia seguinte em UTC.
 */
export function montarRecorrencia(
  pedido: PedidoDeRepeticao,
  ancoraISO: string | null,
  agora = new Date(),
  opcoes: { avancarSePassou: boolean } = { avancarSePassou: true },
): { rrule: string; ancora: string; descricao: string } | { error: string } {
  const r = semAcento(pedido.repetir);
  let freq: "DAILY" | "WEEKLY" | "MONTHLY" | null = null;
  let intervaloPadrao = 1;
  if (/quinzen/.test(r)) { freq = "DAILY"; intervaloPadrao = 15; }
  else if (/^(diari|todo dia|todos os dias|dia|daily)/.test(r)) freq = "DAILY";
  else if (/^(seman|toda semana|weekly)/.test(r)) freq = "WEEKLY";
  else if (/^(mens|todo mes|mes|monthly)/.test(r)) freq = "MONTHLY";
  else if (/^(anual|todo ano|yearly)/.test(r)) return { error: "A agenda repete por dia, semana ou mês — não por ano. Para todo ano, use 'a cada 12 meses'." };
  else if (r) return { error: `Não entendi a repetição "${pedido.repetir}". Use diária, semanal, mensal ou quinzenal.` };

  // Dias da semana: ["seg","qui"], "segunda e quinta", "seg,qua,sex", "dias úteis".
  let dias: number[] = [];
  const diasBrutos = Array.isArray(pedido.dias_da_semana)
    ? pedido.dias_da_semana
    : pedido.dias_da_semana != null && pedido.dias_da_semana !== "" ? String(pedido.dias_da_semana).split(/,|\se\s|;/) : [];
  for (const bruto of diasBrutos) {
    const s = semAcento(bruto);
    if (!s) continue;
    if (/^dias? ute/.test(s)) { dias.push(1, 2, 3, 4, 5); continue; }
    const n = DIAS_DA_SEMANA[s.slice(0, 3)] ?? DIAS_DA_SEMANA[s.slice(0, 2)];
    if (n === undefined) return { error: `"${bruto}" não é dia da semana.` };
    dias.push(n);
  }
  dias = [...new Set(dias)].sort();
  if (dias.length && (!freq || freq === "DAILY") && intervaloPadrao === 1) freq = "WEEKLY";
  if (dias.length && freq !== "WEEKLY") return { error: "Dia da semana só vale para repetição semanal." };

  let diaDoMes: number | null = null;
  if (pedido.dia_do_mes != null && pedido.dia_do_mes !== "") {
    diaDoMes = Number(pedido.dia_do_mes);
    if (!Number.isInteger(diaDoMes) || diaDoMes < 1 || diaDoMes > 31) return { error: `Dia do mês "${pedido.dia_do_mes}" não existe (1 a 31).` };
    if (!freq) freq = "MONTHLY";
    if (freq !== "MONTHLY") return { error: "Dia do mês só vale para repetição mensal." };
  }
  if (!freq) return { error: "Diga como repete: todo dia, toda semana (e em que dias), todo mês (e em que dia) ou a cada N dias." };

  let intervalo = intervaloPadrao;
  if (pedido.repetir_a_cada != null && pedido.repetir_a_cada !== "") {
    intervalo = Number(pedido.repetir_a_cada);
    if (!Number.isInteger(intervalo) || intervalo < 1 || intervalo > 365) return { error: `"A cada ${pedido.repetir_a_cada}" não serve — use um número inteiro de 1 a 365.` };
  }

  let ate: string | null = null;
  if (pedido.repetir_ate != null && pedido.repetir_ate !== "") {
    ate = String(pedido.repetir_ate).slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(ate) || Number.isNaN(new Date(`${ate}T12:00:00Z`).getTime())) {
      return { error: `Data final "${pedido.repetir_ate}" inválida — use AAAA-MM-DD.` };
    }
  }

  // Âncora: o horário dado ou hoje 08:00 de Brasília (o padrão da tela para tarefa).
  const hojeBR = local(agora).toISOString().slice(0, 10);
  let ancora = new Date(ancoraISO || `${hojeBR}T08:00:00-03:00`);
  if (Number.isNaN(ancora.getTime())) return { error: `Horário "${ancoraISO}" inválido.` };

  const encaixa = (d: Date) =>
    (freq !== "WEEKLY" || !dias.length || dias.includes(local(d).getUTCDay())) &&
    (freq !== "MONTHLY" || diaDoMes == null || local(d).getUTCDate() === diaDoMes);
  const proxima = (d: Date): Date => {
    if (freq === "DAILY") return maisDias(d, intervalo);
    if (freq === "WEEKLY") return dias.length ? maisDias(d, 1) : maisDias(d, 7 * intervalo);
    const dia = diaDoMes ?? local(d).getUTCDate();
    for (let m = intervalo; m < 400; m += intervalo) {
      const c = noDiaDoMes(d, dia, m);
      if (c) return c;
    }
    return maisDias(d, 31);
  };
  // Alinha ao dia da regra (anda para a frente, nunca para trás).
  if (freq === "MONTHLY" && diaDoMes != null && !encaixa(ancora)) {
    let achou: Date | null = null;
    for (let m = 0; m < 24 && !achou; m++) {
      const c = noDiaDoMes(ancora, diaDoMes, m);
      if (c && c >= ancora) achou = c;
    }
    if (!achou) return { error: `Não achei um mês com dia ${diaDoMes}.` };
    ancora = achou;
  }
  for (let i = 0; i < 7 && !encaixa(ancora); i++) ancora = maisDias(ancora, 1);
  if (opcoes.avancarSePassou) {
    for (let i = 0; i < 1000 && (ancora.getTime() < agora.getTime() - 60_000 || !encaixa(ancora)); i++) ancora = proxima(ancora);
  }
  if (ate && ate < local(ancora).toISOString().slice(0, 10)) {
    return { error: `A data final (${ate}) é antes da primeira vez (${local(ancora).toISOString().slice(0, 10)}).` };
  }

  const desloc = (ancora.getUTCDay() - local(ancora).getUTCDay() + 7) % 7;
  const partes = [`FREQ=${freq}`];
  if (intervalo > 1) partes.push(`INTERVAL=${intervalo}`);
  if (dias.length) partes.push(`BYDAY=${[...new Set(dias.map((d) => CODIGO_DO_DIA[(d + desloc) % 7]))].join(",")}`);
  if (ate) partes.push(`UNTIL=${ate.replace(/-/g, "")}`);
  const rrule = partes.join(";");
  const iso = ancora.toISOString();
  return { rrule, ancora: iso, descricao: descreverRepeticao(rrule, iso) ?? rrule };
}

const PROPRIEDADES_DE_REPETICAO = {
  repetir: { type: "string", description: "Repetição: 'diaria', 'semanal', 'mensal' ou 'quinzenal'. Omitir = não repete." },
  repetir_a_cada: { type: "number", description: "Intervalo: 15 com 'diaria' = a cada 15 dias; 2 com 'semanal' = a cada 2 semanas." },
  dias_da_semana: { type: "array", items: { type: "string" }, description: "Para 'semanal': ['seg'], ['seg','qui'] ou ['dias úteis']." },
  dia_do_mes: { type: "number", description: "Para 'mensal': o dia do mês (ex.: 5 em 'todo dia 5')." },
  repetir_ate: { type: "string", description: "Última data da repetição (AAAA-MM-DD). Omitir = sem fim." },
} as const;

const TASK_COLS =
  "id, title, kind, status, priority, due_at, scheduled_start_at, scheduled_end_at, location, source, is_private, related_entity_type, related_entity_id, checklist, notes, assignee_user_id, rrule, recurrence_parent_id, app_users:assignee_user_id(full_name), clients:client_id(name)";

function mapTask(t: any) {
  return {
    id: t.id,
    titulo: t.title,
    tipo: t.kind === "appointment" ? "compromisso" : "tarefa",
    status: t.status,
    prioridade: t.priority,
    prazo: t.due_at,
    inicio: t.scheduled_start_at,
    fim: t.scheduled_end_at,
    responsavel: t.app_users?.full_name || null,
    cliente: t.clients?.name || null,
    local: t.location || null,
    origem: t.source,
    vinculo: t.related_entity_type
      ? { tipo: t.related_entity_type, id: t.related_entity_id }
      : null,
    checklist: Array.isArray(t.checklist) && t.checklist.length ? t.checklist : undefined,
    // 07/10/2026: sem isto o assistente não sabia que a tarefa se repete nem qual é a "mãe".
    repete: t.rrule
      ? descreverRepeticao(t.rrule, t.scheduled_start_at || t.due_at) ?? t.rrule
      : t.recurrence_parent_id ? "ocorrência de uma tarefa que se repete" : undefined,
  };
}

/** Esconde tarefas privadas de terceiros (o service role bypassa RLS). */
function visibleTo(t: any, userId: string, role: string) {
  if (!t.is_private) return true;
  return role === "admin" || t.assignee_user_id === userId;
}

async function getConflicts(sb: any, userId: string, startISO: string, endISO: string, opts?: { excludeTask?: string; excludeSo?: string }) {
  const { data } = await sb.rpc("get_agenda_conflicts", {
    p_user_id: userId,
    p_start: startISO,
    p_end: endISO,
    p_exclude_task: opts?.excludeTask ?? null,
    p_exclude_so: opts?.excludeSo ?? null,
  });
  return (data || []).map((c: any) => ({
    tipo: c.source === "service_order" ? "OS" : "compromisso",
    rotulo: c.label,
    inicio: c.starts_at,
    fim: c.ends_at,
  }));
}

export { getConflicts };

/** Sobrecarga do dia (não bloqueia — informa): horas ocupadas + novo item > 8h. */
export async function dayOverloadNotice(
  sb: any, userId: string, startISO: string, endISO: string,
  excl?: { excludeTask?: string; excludeSo?: string },
): Promise<string | null> {
  const day = new Date(startISO).toISOString().slice(0, 10);
  const from = `${day}T00:00:00Z`;
  const to = new Date(new Date(from).getTime() + 86400000).toISOString();
  const { data } = await sb.rpc("get_agenda_conflicts", {
    p_user_id: userId, p_start: from, p_end: to,
    p_exclude_task: excl?.excludeTask ?? null, p_exclude_so: excl?.excludeSo ?? null,
  });
  const busyMs = ((data as any[]) || []).reduce((s, c) => {
    return s + Math.max(0, new Date(c.ends_at).getTime() - new Date(c.starts_at).getTime());
  }, 0);
  const totalH = (busyMs + (new Date(endISO).getTime() - new Date(startISO).getTime())) / 3600000;
  return totalH > 8
    ? `Aviso: com este item o dia do responsável fica com ${totalH.toFixed(1)}h ocupadas — considere outro dia ou avise o usuário.`
    : null;
}

export const agendaTools: ToolDef[] = [
  {
    name: "list_tasks",
    description:
      "Lista TAREFAS/compromissos da agenda com filtros ricos. Sem filtros = tudo que está vivo (pendente/em andamento), incluindo atrasadas. Use date_from/date_to para um período (vale para prazo E horário marcado), assignee_user_id para uma pessoa, overdue_only para só atrasadas, related_entity_type+related_entity_id para as tarefas de uma OS/cliente/recebível etc.",
    input_schema: {
      type: "object",
      properties: {
        assignee_user_id: { type: "string" },
        status: { type: "string", description: "pending | in_progress | done | cancelled (default: vivas)" },
        date_from: { type: "string", description: "ISO — início do período" },
        date_to: { type: "string", description: "ISO — fim do período" },
        overdue_only: { type: "boolean" },
        priority: { type: "string" },
        related_entity_type: { type: "string" },
        related_entity_id: { type: "string" },
      },
    },
    risk: "low",
    async execute(args, { sb, userId, userRole }) {
      // 07/10/2026: "concluídas"/"alta" viravam filtro por um valor que não existe — lista vazia.
      const status = statusDaTarefa(args.status);
      if (status && typeof status === "object") return status;
      const prioridade = prioridadeDaTarefa(args.priority);
      if (prioridade && typeof prioridade === "object") return prioridade;
      let q = sb.from("agenda_tasks").select(TASK_COLS).limit(100);
      if (status) q = q.eq("status", status);
      else q = q.in("status", ["pending", "in_progress"]);
      if (args.assignee_user_id) q = q.eq("assignee_user_id", args.assignee_user_id);
      if (prioridade) q = q.eq("priority", prioridade);
      if (args.related_entity_type) q = q.eq("related_entity_type", args.related_entity_type);
      if (args.related_entity_id) q = q.eq("related_entity_id", args.related_entity_id);
      const { data, error } = await q.order("due_at", { ascending: true, nullsFirst: false });
      if (error) throw error;

      let rows = (data || []).filter((t: any) => visibleTo(t, userId, userRole));
      const anchor = (t: any) => t.due_at || t.scheduled_start_at;
      if (args.date_from) rows = rows.filter((t: any) => anchor(t) && anchor(t) >= args.date_from);
      if (args.date_to) rows = rows.filter((t: any) => anchor(t) && anchor(t) <= args.date_to);
      if (args.overdue_only) {
        const { from } = dayRangeBRT();
        rows = rows.filter((t: any) => anchor(t) && anchor(t) < from && t.status !== "done");
      }
      return { total: rows.length, tarefas: rows.map(mapTask) };
    },
  },
  {
    name: "my_agenda",
    description:
      "Agenda consolidada de UM DIA para uma pessoa (default: quem está falando, hoje): tarefas atrasadas, tarefas com prazo no dia, compromissos e OS agendadas. Para admin/financeiro inclui também os vencimentos financeiros do dia. É a tool certa para 'minha agenda', 'o que tenho hoje/amanhã?'.",
    input_schema: {
      type: "object",
      properties: {
        user_id: { type: "string", description: "Default: o próprio usuário." },
        date: { type: "string", description: "YYYY-MM-DD (dia local). Default: hoje." },
      },
    },
    risk: "low",
    async execute(args, { sb, userId, userRole }) {
      const targetId = args.user_id || userId;
      const { from, to, day } = dayRangeBRT(args.date);

      const { data: liveTasks } = await sb.from("agenda_tasks")
        .select(TASK_COLS)
        .eq("assignee_user_id", targetId)
        .in("status", ["pending", "in_progress"])
        .limit(200);
      const visible = (liveTasks || []).filter((t: any) => visibleTo(t, userId, userRole));
      const anchor = (t: any) => t.due_at || t.scheduled_start_at;
      const atrasadas = visible.filter((t: any) => anchor(t) && anchor(t) < from);
      const doDia = visible.filter((t: any) => anchor(t) && anchor(t) >= from && anchor(t) < to);
      const semData = visible.filter((t: any) => !anchor(t));

      const { data: soLinks } = await sb.from("service_order_technicians")
        .select("service_order_id").eq("user_id", targetId);
      const soIds = (soLinks || []).map((l: any) => l.service_order_id);
      let osDia: any[] = [];
      if (soIds.length > 0) {
        const { data: oss } = await sb.from("service_orders")
          .select("id, service_order_number, status, scheduled_start_at, scheduled_end_at, clients(name), vessels(name)")
          .in("id", soIds)
          .gte("scheduled_start_at", from).lt("scheduled_start_at", to)
          .neq("status", "cancelled")
          .order("scheduled_start_at");
        osDia = oss || [];
      }

      const result: any = {
        dia: day,
        atrasadas: atrasadas.map(mapTask),
        tarefas_do_dia: doDia.map(mapTask),
        sem_data: semData.slice(0, 10).map(mapTask),
        os_do_dia: osDia.map((o: any) => ({
          id: o.id, numero: o.service_order_number, status: o.status,
          inicio: o.scheduled_start_at, fim: o.scheduled_end_at,
          cliente: o.clients?.name || null, embarcacao: o.vessels?.name || null,
        })),
      };

      if (userRole === "admin" || userRole === "financial") {
        const { data: recv } = await sb.from("receivables")
          .select("id, amount, balance_amount, due_date, clients(name)")
          .in("status", ["pending", "partially_paid"]).eq("due_date", day).limit(20);
        const { data: pay } = await sb.from("payables")
          .select("id, amount, balance_amount, due_date, supplier_name")
          .in("status", ["pending", "partially_paid"]).eq("due_date", day).limit(20);
        result.vencimentos_do_dia = {
          a_receber: (recv || []).map((r: any) => ({ cliente: r.clients?.name, valor: r.balance_amount ?? r.amount })),
          a_pagar: (pay || []).map((p: any) => ({ fornecedor: p.supplier_name, valor: p.balance_amount ?? p.amount })),
        };
      }
      return result;
    },
  },
  {
    name: "list_technicians",
    description: "Lista os técnicos disponíveis no sistema.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    async execute(_args, { sb }) {
      const { data, error } = await sb
        .from("app_users")
        .select("id, full_name, role")
        .in("role", ["technician", "admin"])
        .eq("active", true)
        .order("full_name");
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "create_task",
    description:
      "Cria tarefa ou compromisso na agenda. TAREFA = coisa a fazer com prazo (due_at) e sem hora marcada. COMPROMISSO = hora marcada (scheduled_start_at/end) — checa conflito de agenda antes e, se houver, devolve os conflitos SEM criar (proponha outro horário ou pergunte). SEMPRE vincule à entidade do contexto (related_entity_type/id) quando a conversa for sobre uma OS/orçamento/cliente. Lembretes: reminder_offsets_minutes (ex.: [30] = 30min antes do início/prazo). " +
      "TAREFA QUE SE REPETE ('toda segunda às 8h', 'todo dia 5', 'a cada 15 dias'): passe repetir (+ dias_da_semana, dia_do_mes ou repetir_a_cada) e, se foi dita, a hora em due_at — a tool acha a primeira vez e monta a regra; as próximas o sistema cria sozinho.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string" },
        kind: { type: "string", description: "'task' (default) ou 'appointment'" },
        assignee_user_id: { type: "string", description: "Responsável (app_users.id). Omitir = sem responsável." },
        due_at: { type: "string", description: "Prazo ISO (para kind=task)" },
        scheduled_start_at: { type: "string", description: "Início ISO (para kind=appointment)" },
        scheduled_end_at: { type: "string", description: "Fim ISO" },
        priority: { type: "string", description: "low|normal|high|urgent" },
        client_id: { type: "string" },
        location: { type: "string" },
        notes: { type: "string" },
        related_entity_type: { type: "string", description: RELATED_ENTITY_TYPES.join("|") },
        related_entity_id: { type: "string" },
        checklist: { type: "array", items: { type: "string" }, description: "Itens do checklist" },
        reminder_offsets_minutes: { type: "array", items: { type: "number" }, description: "Minutos ANTES do início/prazo para lembrar no app" },
        is_private: { type: "boolean" },
        ...PROPRIEDADES_DE_REPETICAO,
      },
      required: ["title"],
    },
    risk: "low",
    async execute(argsCrus, { sb, userId }) {
      // Hora sem fuso vira hora de Brasília (fuso.ts): 09:00 não pode virar 06:00.
      const args = horariosDeBrasilia(argsCrus);
      const kind = args.kind === "appointment" || args.scheduled_start_at ? "appointment" : "task";
      if (kind === "appointment" && !args.scheduled_start_at) {
        return { error: "Compromisso precisa de scheduled_start_at." };
      }
      // 07/10/2026: prioridade e vínculo conferidos antes de gravar. O vínculo tem CHECK no banco
      // (o insert falharia com um erro técnico); a prioridade não tem — gravava qualquer texto.
      const prioridade = prioridadeDaTarefa(args.priority);
      if (prioridade && typeof prioridade === "object") return prioridade;
      if (!ehTipoDeEntidadeValido(args.related_entity_type || null)) {
        return { error: `Vínculo "${args.related_entity_type}" não existe. Use: ${RELATED_ENTITY_TYPES.join(", ")}.` };
      }

      // Repetição: a regra e a primeira vez saem daqui (montarRecorrencia), não do modelo.
      let rrule: string | null = null;
      let repete: string | null = null;
      if (pediuRepeticao(args)) {
        const r = montarRecorrencia(args, args.scheduled_start_at || args.due_at || null);
        if ("error" in r) return r;
        rrule = r.rrule;
        repete = r.descricao;
        if (kind === "appointment") {
          const delta = new Date(r.ancora).getTime() - new Date(args.scheduled_start_at).getTime();
          args.scheduled_start_at = r.ancora;
          if (args.scheduled_end_at) args.scheduled_end_at = new Date(new Date(args.scheduled_end_at).getTime() + delta).toISOString();
        } else {
          args.due_at = r.ancora;
        }
      }

      if (kind === "appointment" && args.assignee_user_id && args.scheduled_start_at && args.scheduled_end_at) {
        const conflitos = await getConflicts(sb, args.assignee_user_id, args.scheduled_start_at, args.scheduled_end_at);
        if (conflitos.length > 0) {
          return { conflito: true, mensagem: "Horário conflita com a agenda do responsável — nada foi criado.", conflitos };
        }
      }

      const { data, error } = await sb.from("agenda_tasks").insert({
        title: args.title,
        kind,
        status: "pending",
        priority: prioridade || "normal",
        assignee_user_id: args.assignee_user_id || null,
        due_at: kind === "task" ? (args.due_at || null) : null,
        scheduled_start_at: args.scheduled_start_at || null,
        scheduled_end_at: args.scheduled_end_at || null,
        client_id: args.client_id || null,
        location: args.location || null,
        notes: args.notes || null,
        related_entity_type: args.related_entity_type || null,
        related_entity_id: args.related_entity_id || null,
        checklist: Array.isArray(args.checklist)
          ? args.checklist.map((t: string) => ({ text: String(t), done: false }))
          : [],
        is_private: args.is_private === true,
        rrule,
        source: "ai",
        created_by: userId,
      }).select("id, title").single();
      if (error) throw error;

      let aviso_carga: string | null = null;
      if (kind === "appointment" && args.assignee_user_id && args.scheduled_start_at && args.scheduled_end_at) {
        aviso_carga = await dayOverloadNotice(sb, args.assignee_user_id, args.scheduled_start_at, args.scheduled_end_at, { excludeTask: data.id });
      }

      const anchorISO = args.scheduled_start_at || args.due_at;
      if (anchorISO && Array.isArray(args.reminder_offsets_minutes)) {
        const rows = args.reminder_offsets_minutes
          .map((m: number) => new Date(new Date(anchorISO).getTime() - m * 60000).toISOString())
          .filter((iso: string) => new Date(iso) > new Date())
          .map((iso: string) => ({ task_id: data.id, remind_at: iso, channel: "app" }));
        if (rows.length) await sb.from("task_reminders").insert(rows);
      }
      return {
        ok: true,
        task: { id: data.id, titulo: data.title },
        ...(rrule ? {
          repete,
          primeira_vez: anchorISO,
          // O motor copia a tarefa, não o lembrete (task-automations): só a 1ª vez tem aviso.
          obs_repeticao: "As próximas vezes aparecem sozinhas na agenda (o sistema cria as dos 30 dias seguintes). O lembrete marcado vale só para a primeira.",
        } : {}),
        ...(aviso_carga ? { aviso_carga } : {}),
      };
    },
  },
  {
    name: "update_task",
    description:
      "Atualiza uma tarefa/compromisso: reagendar (novas datas — checa conflito), reatribuir, prioridade, status, adiar (snoozed_until), notas, checklist (a lista nova substitui a antiga). Passe SÓ os campos a mudar. " +
      "Repetição: passe repetir (+ dias_da_semana, dia_do_mes, repetir_a_cada, repetir_ate) para passar a repetir ou mudar a regra; parar_de_repetir=true para parar ('para de repetir a tarefa de conferir o extrato'). Pode passar o id de qualquer vez da série — a regra muda na série inteira.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string" },
        title: { type: "string" },
        assignee_user_id: { type: "string" },
        due_at: { type: "string" },
        scheduled_start_at: { type: "string" },
        scheduled_end_at: { type: "string" },
        priority: { type: "string", description: "baixa | normal | alta | urgente" },
        status: { type: "string", description: "pendente | em andamento | concluída | cancelada" },
        snoozed_until: { type: "string", description: "ISO — esconder da visão Hoje até este momento" },
        location: { type: "string" },
        notes: { type: "string" },
        related_entity_type: { type: "string", description: RELATED_ENTITY_TYPES.join("|") },
        related_entity_id: { type: "string" },
        checklist: { type: "array", items: { type: "string" }, description: "A lista INTEIRA de itens (substitui a atual; item com o mesmo texto mantém o 'feito')." },
        ...PROPRIEDADES_DE_REPETICAO,
        parar_de_repetir: { type: "boolean", description: "true = a série para de se repetir (as próximas vezes ainda pendentes saem da agenda)." },
      },
      required: ["id"],
    },
    risk: "low",
    async execute(argsCrus, { sb, userId, userRole }) {
      // Hora sem fuso vira hora de Brasília (fuso.ts): 09:00 não pode virar 06:00.
      const args = horariosDeBrasilia(argsCrus);
      const id = String(args.id ?? "");
      // 07/10/2026 (frente operacional): antes, TODO argumento ia direto para o update — um campo
      // que o modelo inventasse (ou o checklist como lista de textos, que a tela não lê) ia para
      // o banco. Agora só os campos do formulário, conferidos; e a tarefa é lida antes, com erro
      // de leitura dito como erro e tarefa privada de outra pessoa tratada como inexistente.
      const COLS = "id, title, kind, status, assignee_user_id, is_private, due_at, scheduled_start_at, scheduled_end_at, rrule, recurrence_parent_id, checklist";
      const { data: atual, error: erroLeitura } = await sb.from("agenda_tasks").select(COLS).eq("id", id).maybeSingle();
      if (erroLeitura) return { error: `Não consegui ler a tarefa: ${erroLeitura.message}` };
      if (!atual || !visibleTo(atual, userId, userRole)) return { error: "Tarefa não encontrada." };

      const patch: Record<string, unknown> = {};
      if (typeof args.title === "string" && args.title.trim()) patch.title = args.title.trim();
      for (const c of ["assignee_user_id", "due_at", "scheduled_start_at", "scheduled_end_at", "snoozed_until", "location", "notes", "related_entity_id"]) {
        if (args[c] !== undefined) patch[c] = args[c] === "" ? null : args[c];
      }
      if (args.related_entity_type !== undefined) {
        const tipo = args.related_entity_type === "" ? null : args.related_entity_type;
        if (!ehTipoDeEntidadeValido(tipo)) return { error: `Vínculo "${tipo}" não existe. Use: ${RELATED_ENTITY_TYPES.join(", ")}.` };
        patch.related_entity_type = tipo;
        if (tipo === null) patch.related_entity_id = null;
      }
      const prioridade = prioridadeDaTarefa(args.priority);
      if (prioridade && typeof prioridade === "object") return prioridade;
      if (prioridade) patch.priority = prioridade;
      const status = statusDaTarefa(args.status);
      if (status && typeof status === "object") return status;
      if (status) {
        patch.status = status;
        // Como o "concluir" da tela (useCompleteTask): quem e quando; reabrir limpa os dois.
        if (status === "done" && atual.status !== "done") { patch.completed_at = new Date().toISOString(); patch.completed_by = userId; }
        if (status !== "done" && atual.status === "done") { patch.completed_at = null; patch.completed_by = null; }
      }
      if (Array.isArray(args.checklist)) {
        const feitos = new Map((Array.isArray(atual.checklist) ? atual.checklist : [])
          .map((c: any) => [semAcento(c?.text), !!c?.done] as [string, boolean]));
        patch.checklist = args.checklist
          .map((c: any) => (typeof c === "string" ? c : c?.text))
          .filter((t: unknown) => typeof t === "string" && t.trim())
          .map((t: string) => ({ text: t.trim(), done: feitos.get(semAcento(t)) ?? false }));
      }

      // Repetição: vale para a SÉRIE, que mora na tarefa-mãe (recurrence_parent_id nulo).
      const idDaMae = atual.recurrence_parent_id || atual.id;
      const patchDaMae: Record<string, unknown> = {};
      let repete: string | null | undefined;
      if (args.parar_de_repetir === true || pediuRepeticao(args)) {
        let mae = atual;
        if (idDaMae !== atual.id) {
          const { data, error } = await sb.from("agenda_tasks").select(COLS).eq("id", idDaMae).maybeSingle();
          if (error) return { error: `Não consegui ler a tarefa que se repete: ${error.message}` };
          if (!data) return { error: "A série desta tarefa não existe mais." };
          mae = data;
        }
        if (args.parar_de_repetir === true) {
          if (!mae.rrule) return { error: `"${mae.title}" não se repete.` };
          patchDaMae.rrule = null;
          repete = null;
        } else {
          // A âncora é a data nova (se veio e o pedido é sobre a própria mãe) ou a da mãe.
          const novaData = idDaMae === atual.id ? (patch.scheduled_start_at ?? patch.due_at) : undefined;
          const ancora = (novaData as string | undefined) || mae.scheduled_start_at || mae.due_at || null;
          const r = montarRecorrencia(args, ancora, new Date(), { avancarSePassou: !ancora });
          if ("error" in r) return r;
          patchDaMae.rrule = r.rrule;
          repete = r.descricao;
          if (r.ancora !== ancora) {
            if (mae.kind === "appointment") {
              const delta = new Date(r.ancora).getTime() - new Date(mae.scheduled_start_at).getTime();
              patchDaMae.scheduled_start_at = r.ancora;
              if (mae.scheduled_end_at) patchDaMae.scheduled_end_at = new Date(new Date(mae.scheduled_end_at).getTime() + delta).toISOString();
            } else {
              patchDaMae.due_at = r.ancora;
            }
          }
        }
      }
      if (Object.keys(patch).length === 0 && Object.keys(patchDaMae).length === 0) {
        return { error: "Nada para mudar: diga o que alterar na tarefa." };
      }

      const inicio = (patch.scheduled_start_at ?? (idDaMae === atual.id ? patchDaMae.scheduled_start_at : undefined)) as string | undefined;
      const fim = (patch.scheduled_end_at ?? (idDaMae === atual.id ? patchDaMae.scheduled_end_at : undefined) ?? atual.scheduled_end_at) as string | undefined;
      if (inicio && fim && atual.kind === "appointment") {
        const who = (patch.assignee_user_id as string | undefined) || atual.assignee_user_id;
        if (who) {
          const conflitos = await getConflicts(sb, who, inicio, fim, { excludeTask: id });
          if (conflitos.length > 0) {
            return { conflito: true, mensagem: "Novo horário conflita — nada foi alterado.", conflitos };
          }
        }
      }

      // Uma gravação por tarefa: a própria e, se a regra é da série, a mãe.
      const juntos = idDaMae === atual.id ? { ...patch, ...patchDaMae } : patch;
      let data: any = atual;
      if (Object.keys(juntos).length) {
        const r = await sb.from("agenda_tasks").update(juntos).eq("id", id).select("id, title, status, rrule, recurrence_parent_id").single();
        if (r.error) throw r.error;
        data = r.data;
      }
      if (idDaMae !== atual.id && Object.keys(patchDaMae).length) {
        const { error } = await sb.from("agenda_tasks").update(patchDaMae).eq("id", idDaMae);
        if (error) throw error;
      }
      // Série editada (como a tela, useSaveAgendaTask): as próximas vezes ainda pendentes saem;
      // o motor recria com os dados novos em até 15 min — ou não recria, se parou de repetir.
      let aviso: string | undefined;
      const mexeuNaSerie = (idDaMae === atual.id && (atual.rrule || data.rrule)) || Object.keys(patchDaMae).length > 0;
      if (mexeuNaSerie) {
        const nowISO = new Date().toISOString();
        const { error } = await sb.from("agenda_tasks").delete()
          .eq("recurrence_parent_id", idDaMae)
          .eq("status", "pending")
          .or(`scheduled_start_at.gte.${nowISO},due_at.gte.${nowISO}`);
        if (error) aviso = `A regra mudou, mas as próximas vezes já criadas não saíram da agenda (${error.message}).`;
      }
      return {
        ok: true,
        task: { id: data.id, title: data.title, status: data.status },
        ...(repete !== undefined ? { repete: repete ?? "não se repete mais", ...(idDaMae !== atual.id ? { obs: "A regra foi mudada na série inteira." } : {}) } : {}),
        ...(aviso ? { aviso } : {}),
      };
    },
  },
  {
    name: "complete_task",
    description: "Conclui uma tarefa (status=done), com nota opcional do que foi feito.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string" },
        note: { type: "string" },
      },
      required: ["id"],
    },
    risk: "low",
    async execute(args, { sb, userId }) {
      const { data: t } = await sb.from("agenda_tasks").select("notes").eq("id", args.id).maybeSingle();
      const { data, error } = await sb.from("agenda_tasks").update({
        status: "done",
        completed_at: new Date().toISOString(),
        completed_by: userId,
        notes: args.note ? [t?.notes, `Concluída: ${args.note}`].filter(Boolean).join("\n") : t?.notes ?? null,
      }).eq("id", args.id).select("id, title").single();
      if (error) throw error;
      return { ok: true, task: data };
    },
  },
  {
    name: "delete_task",
    description:
      "EXCLUI uma tarefa da agenda (não é concluir — é apagar). Tarefas criadas por automação não são apagadas: são canceladas (o motor as recriaria).",
    input_schema: {
      type: "object",
      properties: { id: { type: "string" } },
      required: ["id"],
    },
    risk: "medium",
    async execute(args, { sb }) {
      const { data: t, error: getErr } = await sb.from("agenda_tasks")
        .select("id, source, title").eq("id", args.id).maybeSingle();
      if (getErr) throw getErr;
      if (!t) return { error: "Tarefa não encontrada." };
      if (t.source === "automation") {
        const { error } = await sb.from("agenda_tasks").update({ status: "cancelled" }).eq("id", args.id);
        if (error) throw error;
        return { ok: true, cancelada: t.title, obs: "Tarefa de automação foi cancelada (não apagada)." };
      }
      const { error } = await sb.from("agenda_tasks").delete().eq("id", args.id);
      if (error) throw error;
      return { ok: true, excluida: t.title };
    },
  },
  {
    name: "list_team_agenda",
    description:
      "Visão da agenda da EQUIPE inteira num dia: por pessoa, os compromissos, tarefas com prazo e OS agendadas. Use para 'como está a agenda da equipe amanhã?'.",
    input_schema: {
      type: "object",
      properties: {
        date: { type: "string", description: "YYYY-MM-DD. Default: hoje." },
      },
    },
    risk: "low",
    async execute(args, { sb, userId, userRole }) {
      const { from, to, day } = dayRangeBRT(args.date);
      const { data: users } = await sb.from("app_users")
        .select("id, full_name, role").eq("active", true).order("full_name");

      const { data: tasks } = await sb.from("agenda_tasks")
        .select(TASK_COLS)
        .in("status", ["pending", "in_progress"])
        .limit(300);
      const dayTasks = (tasks || []).filter((t: any) => {
        const a = t.due_at || t.scheduled_start_at;
        return a && a >= from && a < to && visibleTo(t, userId, userRole);
      });

      const { data: orders } = await sb.from("service_orders")
        .select("id, service_order_number, scheduled_start_at, clients(name), service_order_technicians(user_id)")
        .gte("scheduled_start_at", from).lt("scheduled_start_at", to)
        .neq("status", "cancelled");

      const porPessoa = (users || []).map((u: any) => ({
        pessoa: u.full_name,
        user_id: u.id,
        cargo: u.role,
        tarefas: dayTasks.filter((t: any) => t.assignee_user_id === u.id).map(mapTask),
        os: (orders || [])
          .filter((o: any) => (o.service_order_technicians || []).some((l: any) => l.user_id === u.id))
          .map((o: any) => ({ numero: o.service_order_number, cliente: o.clients?.name, inicio: o.scheduled_start_at })),
      })).filter((p: any) => p.tarefas.length > 0 || p.os.length > 0);

      const semDono = dayTasks.filter((t: any) => !t.assignee_user_id).map(mapTask);
      return { dia: day, por_pessoa: porPessoa, sem_responsavel: semDono };
    },
  },
];
