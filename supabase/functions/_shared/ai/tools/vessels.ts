import type { ToolDef } from "./registry.ts";

export const vesselTools: ToolDef[] = [
  {
    name: "search_vessels",
    description: "Busca embarcações por nome/modelo. Pode filtrar por client_id.",
    input_schema: {
      type: "object",
      properties: { query: { type: "string" }, client_id: { type: "string" } },
      required: ["query"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const q = String(args.query || "").trim();
      let query = sb
        .from("vessels")
        .select("id, name, manufacturer, model, year, client_id, marina_id")
        .eq("active", true)
        .or(`name.ilike.%${q}%,model.ilike.%${q}%,manufacturer.ilike.%${q}%`)
        .limit(15);
      if (args.client_id) query = query.eq("client_id", args.client_id);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "get_vessel_history",
    description: "Retorna o histórico completo de serviços realizados em uma embarcação.",
    input_schema: {
      type: "object",
      properties: { vessel_id: { type: "string" } },
      required: ["vessel_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, scheduled_start_at, grand_total, created_at, problem_description, clients(name)")
        .eq("vessel_id", args.vessel_id)
        .order("created_at", { ascending: false })
        .limit(30);
      if (error) throw error;
      const mapped = (data || []).map((so: any) => ({
        numero: so.service_order_number,
        status: so.status,
        cliente: so.clients?.name || "—",
        problema: so.problem_description || "—",
        valor_total: so.grand_total || 0,
        agendado_para: so.scheduled_start_at || null,
        criado_em: so.created_at,
      }));
      return { history: mapped };
    },
  },
  {
    name: "list_marinas",
    description: "Lista marinas cadastradas.",
    input_schema: { type: "object", properties: { query: { type: "string" } } },
    risk: "low",
    async execute(args, { sb }) {
      const q = String(args.query || "").trim();
      let query = sb.from("marinas").select("id, name, city, state").eq("active", true).order("name").limit(20);
      if (q) query = query.ilike("name", `%${q}%`);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "create_vessel",
    description: "Cadastra uma nova unidade/ativo (embarcação ou motorhome) para um cliente.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string" },
        name: { type: "string", description: "Nome da embarcação ou identificação do motorhome" },
        manufacturer: { type: "string" },
        model: { type: "string" },
        year: { type: "number" },
        asset_type: { type: "string", description: "Exemplo: Lancha, Veleiro, Motorhome, Camper, Jet Ski" },
        marina_id: { type: "string" },
      },
      required: ["client_id", "name", "asset_type"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("vessels").insert(args).select().single();
      if (error) throw error;
      return { ok: true, vessel: data };
    },
  },
  {
    name: "create_marina",
    description: "Cadastra uma nova marina.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        contact_name: { type: "string" },
        phone: { type: "string" },
        email: { type: "string" },
        city: { type: "string" },
        state: { type: "string" },
      },
      required: ["name"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("marinas").insert(args).select().single();
      if (error) throw error;
      return { ok: true, marina: data };
    },
  },
];
