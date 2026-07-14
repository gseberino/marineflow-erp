import type { ToolDef } from "./registry.ts";

export const agendaTools: ToolDef[] = [
  {
    name: "list_agenda",
    description: "Lista compromissos da agenda em um intervalo de datas (ISO).",
    input_schema: {
      type: "object",
      properties: {
        date_from: { type: "string", description: "ISO datetime" },
        date_to: { type: "string", description: "ISO datetime" },
        technician_id: { type: "string" },
      },
      required: ["date_from", "date_to"],
    },
    risk: "low",
    async execute(args, { sb }) {
      let query = sb
        .from("agenda_tasks")
        .select("id, title, scheduled_start_at, scheduled_end_at, status, priority, location, clients(name), app_users(full_name)")
        .gte("scheduled_start_at", args.date_from)
        .lte("scheduled_start_at", args.date_to)
        .order("scheduled_start_at", { ascending: true });
      if (args.technician_id) query = query.eq("technician_user_id", args.technician_id);
      const { data, error } = await query;
      if (error) throw error;
      const mapped = (data || []).map((t: any) => ({
        id: t.id,
        titulo: t.title,
        cliente: t.clients?.name || "—",
        tecnico: t.app_users?.full_name || "—",
        inicio: t.scheduled_start_at,
        fim: t.scheduled_end_at,
        status: t.status,
        prioridade: t.priority,
        local: t.location || "—",
      }));
      return { results: mapped };
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
    name: "create_agenda_task",
    description: "Cria um compromisso na agenda.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string" },
        scheduled_start_at: { type: "string" },
        scheduled_end_at: { type: "string" },
        technician_user_id: { type: "string" },
        client_id: { type: "string" },
        location: { type: "string" },
        notes: { type: "string" },
        priority: { type: "string" },
      },
      required: ["title", "scheduled_start_at", "technician_user_id"],
    },
    risk: "low",
    async execute(args, { sb, userId }) {
      const { data, error } = await sb.from("agenda_tasks").insert({ ...args, created_by: userId }).select().single();
      if (error) throw error;
      return { ok: true, task: data };
    },
  },
  {
    name: "update_agenda_task",
    description: "Atualiza campos de um compromisso.",
    input_schema: {
      type: "object",
      properties: {
        id: { type: "string" },
        title: { type: "string" },
        scheduled_start_at: { type: "string" },
        scheduled_end_at: { type: "string" },
        status: { type: "string" },
        notes: { type: "string" },
      },
      required: ["id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { id, ...rest } = args;
      const { data, error } = await sb.from("agenda_tasks").update(rest).eq("id", id).select().single();
      if (error) throw error;
      return { ok: true, task: data };
    },
  },
];
