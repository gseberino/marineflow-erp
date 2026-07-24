import type { ToolDef } from "./registry.ts";

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

const TASK_COLS =
  "id, title, kind, status, priority, due_at, scheduled_start_at, scheduled_end_at, location, source, is_private, related_entity_type, related_entity_id, checklist, notes, assignee_user_id, app_users:assignee_user_id(full_name), clients:client_id(name)";

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
      let q = sb.from("agenda_tasks").select(TASK_COLS).limit(100);
      if (args.status) q = q.eq("status", args.status);
      else q = q.in("status", ["pending", "in_progress"]);
      if (args.assignee_user_id) q = q.eq("assignee_user_id", args.assignee_user_id);
      if (args.priority) q = q.eq("priority", args.priority);
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
      "Cria tarefa ou compromisso na agenda. TAREFA = coisa a fazer com prazo (due_at) e sem hora marcada. COMPROMISSO = hora marcada (scheduled_start_at/end) — checa conflito de agenda antes e, se houver, devolve os conflitos SEM criar (proponha outro horário ou pergunte). SEMPRE vincule à entidade do contexto (related_entity_type/id) quando a conversa for sobre uma OS/orçamento/cliente. Lembretes: reminder_offsets_minutes (ex.: [30] = 30min antes do início/prazo).",
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
        related_entity_type: { type: "string", description: "service_order|external_quote|client|vessel|receivable|payable|purchase_order|stock_item" },
        related_entity_id: { type: "string" },
        checklist: { type: "array", items: { type: "string" }, description: "Itens do checklist" },
        reminder_offsets_minutes: { type: "array", items: { type: "number" }, description: "Minutos ANTES do início/prazo para lembrar no app" },
        is_private: { type: "boolean" },
      },
      required: ["title"],
    },
    risk: "low",
    async execute(args, { sb, userId }) {
      const kind = args.kind === "appointment" || args.scheduled_start_at ? "appointment" : "task";
      if (kind === "appointment" && !args.scheduled_start_at) {
        return { error: "Compromisso precisa de scheduled_start_at." };
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
        priority: args.priority || "normal",
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
        source: "ai",
        created_by: userId,
      }).select("id, title").single();
      if (error) throw error;

      const anchorISO = args.scheduled_start_at || args.due_at;
      if (anchorISO && Array.isArray(args.reminder_offsets_minutes)) {
        const rows = args.reminder_offsets_minutes
          .map((m: number) => new Date(new Date(anchorISO).getTime() - m * 60000).toISOString())
          .filter((iso: string) => new Date(iso) > new Date())
          .map((iso: string) => ({ task_id: data.id, remind_at: iso, channel: "app" }));
        if (rows.length) await sb.from("task_reminders").insert(rows);
      }
      return { ok: true, task: { id: data.id, titulo: data.title } };
    },
  },
  {
    name: "update_task",
    description:
      "Atualiza uma tarefa/compromisso: reagendar (novas datas — checa conflito), reatribuir, prioridade, status, adiar (snoozed_until), notas, checklist. Passe SÓ os campos a mudar.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string" },
        title: { type: "string" },
        assignee_user_id: { type: "string" },
        due_at: { type: "string" },
        scheduled_start_at: { type: "string" },
        scheduled_end_at: { type: "string" },
        priority: { type: "string" },
        status: { type: "string" },
        snoozed_until: { type: "string", description: "ISO — esconder da visão Hoje até este momento" },
        location: { type: "string" },
        notes: { type: "string" },
      },
      required: ["id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { id, ...rest } = args;
      if (rest.scheduled_start_at && rest.scheduled_end_at) {
        const { data: current } = await sb.from("agenda_tasks")
          .select("assignee_user_id, kind").eq("id", id).maybeSingle();
        const who = rest.assignee_user_id || current?.assignee_user_id;
        if (who && current?.kind === "appointment") {
          const conflitos = await getConflicts(sb, who, rest.scheduled_start_at, rest.scheduled_end_at, { excludeTask: id });
          if (conflitos.length > 0) {
            return { conflito: true, mensagem: "Novo horário conflita — nada foi alterado.", conflitos };
          }
        }
      }
      const { data, error } = await sb.from("agenda_tasks").update(rest).eq("id", id)
        .select("id, title, status").single();
      if (error) throw error;
      return { ok: true, task: data };
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
