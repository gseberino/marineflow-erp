import type { ToolDef } from "./registry.ts";

export const clientTools: ToolDef[] = [
  {
    name: "search_clients",
    description: "Busca clientes por nome, email, telefone ou CPF/CNPJ (tolerante a erros).",
    input_schema: {
      type: "object",
      properties: { query: { type: "string" }, limit: { type: "number" } },
      required: ["query"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("clients")
        .select("id, name, type, phone, whatsapp, email, cpf_cnpj")
        .or(`name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%,whatsapp.ilike.%${q}%,cpf_cnpj.ilike.%${q}%`)
        .eq("active", true)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "create_client",
    description: "Cadastra um novo cliente.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        type: { type: "string", enum: ["individual", "company"] },
        phone: { type: "string" },
        whatsapp: { type: "string" },
        email: { type: "string" },
        cpf_cnpj: { type: "string" },
      },
      required: ["name", "type"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("clients").insert(args).select().single();
      if (error) throw error;
      return { ok: true, client: data };
    },
  },
];
