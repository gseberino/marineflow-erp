import type { ToolDef } from "./registry.ts";

// Campos de endereço/fiscais aceitos no cadastro e na atualização do cliente.
// NÃO são cosméticos: sem documento e endereço completo a SEFAZ rejeita a NF-e — um cliente
// criado sem eles nasce impossível de faturar (era o que acontecia antes destes campos).
const CAMPOS_ENDERECO_FISCAL = {
  cpf_cnpj: { type: "string", description: "CPF ou CNPJ — OBRIGATÓRIO para emitir nota fiscal." },
  address_line_1: { type: "string", description: "Rua/logradouro — obrigatório para nota fiscal." },
  address_number: { type: "string", description: "Número." },
  address_complement: { type: "string", description: "Complemento (apto, bloco...)." },
  neighborhood: { type: "string", description: "Bairro." },
  city: { type: "string", description: "Cidade — obrigatório para nota fiscal." },
  state: { type: "string", description: "UF com 2 letras (ex.: SC) — obrigatório para nota fiscal." },
  postal_code: { type: "string", description: "CEP — obrigatório para nota fiscal." },
  state_registration: { type: "string", description: "Inscrição estadual (empresa)." },
  ie_indicator: { type: "string", description: "Indicador de IE (1=contribuinte, 2=isento, 9=não contribuinte)." },
  notes: { type: "string", description: "Observações livres (ex.: data de nascimento, referências)." },
} as const;

/** Diz o que ainda falta para o cliente poder receber nota fiscal. */
function pendenciasFiscais(c: Record<string, unknown>): string[] {
  const faltando: string[] = [];
  if (!c.cpf_cnpj) faltando.push("CPF/CNPJ");
  if (!c.address_line_1) faltando.push("rua");
  if (!c.city) faltando.push("cidade");
  if (!c.state) faltando.push("UF");
  if (!c.postal_code) faltando.push("CEP");
  return faltando;
}

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
      // Busca com termo vazio/genérico devolveria "qualquer cliente" e induz escolha errada.
      if (q.length < 2) return { error: "Termo de busca muito curto. Diga o nome (ou parte dele) do cliente." };
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
    description:
      "Cadastra um novo cliente. Se o usuário forneceu endereço, CPF/CNPJ ou CEP, GRAVE TUDO — esses campos são o que permite emitir nota fiscal depois. A resposta avisa se ficou faltando algo para faturamento.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        type: { type: "string", enum: ["individual", "company"] },
        phone: { type: "string" },
        whatsapp: { type: "string" },
        email: { type: "string" },
        ...CAMPOS_ENDERECO_FISCAL,
      },
      required: ["name", "type"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("clients").insert(args).select().single();
      if (error) throw error;
      const faltando = pendenciasFiscais(data);
      return {
        ok: true,
        client: data,
        pronto_para_nota_fiscal: faltando.length === 0,
        falta_para_faturar: faltando.length ? faltando : null,
        aviso: faltando.length
          ? `Cadastrado, mas ainda falta ${faltando.join(", ")} para conseguir emitir nota fiscal para ele.`
          : null,
      };
    },
  },
  {
    name: "update_client",
    description:
      "Atualiza dados de um cliente já cadastrado — especialmente para COMPLETAR o que falta para emitir nota fiscal (CPF/CNPJ, rua, cidade, UF, CEP). Use quando o usuário informar dados novos ou quando uma emissão falhar por dado faltante. Só envie os campos que quer mudar.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string", description: "UUID do cliente." },
        name: { type: "string" },
        phone: { type: "string" },
        whatsapp: { type: "string" },
        email: { type: "string" },
        display_name: { type: "string", description: "Nome usado na comunicação (fantasia/primeiro nome) — preferido na saudação." },
        communication_tone: { type: "string", description: "Tom preferido na comunicação (ex.: formal, informal)." },
        opt_out_whatsapp: { type: "boolean", description: "true = o cliente NÃO quer mais receber mensagens no WhatsApp (bloqueia envios)." },
        ...CAMPOS_ENDERECO_FISCAL,
      },
      required: ["client_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { client_id, ...campos } = args as Record<string, unknown>;
      const patch = Object.fromEntries(Object.entries(campos).filter(([, v]) => v !== undefined && v !== null && v !== ""));
      if (Object.keys(patch).length === 0) return { error: "Nada para atualizar — informe ao menos um campo." };

      const { data, error } = await sb.from("clients").update(patch).eq("id", client_id).select().single();
      if (error) throw error;
      const faltando = pendenciasFiscais(data);
      return {
        ok: true,
        cliente: data.name,
        atualizado: Object.keys(patch),
        pronto_para_nota_fiscal: faltando.length === 0,
        falta_para_faturar: faltando.length ? faltando : null,
      };
    },
  },
];
