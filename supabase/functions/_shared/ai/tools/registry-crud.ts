import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolCtx, type ToolDef } from "./registry.ts";

// ATUALIZAÇÃO de cadastros (produto, ativo, fornecedor, serviço, marina).
//
// POR QUE ISTO EXISTE: uma auditoria mostrou que o agente sabia CRIAR quase tudo e ATUALIZAR
// quase nada — 8 de 10 entidades não tinham ferramenta de edição. Na prática, pedidos triviais
// ("corrige o preço desse produto", "esse fornecedor mudou de telefone", "o ano do barco está
// errado") não tinham como ser atendidos, e o agente respondia que não conseguia.
//
// Também mediu-se que os cadastros usavam poucos campos da tabela (create_product usava 5 de
// 33). Produto sem NCM não entra em NF-e — o mesmo efeito em cadeia que travava o cliente sem
// endereço. Por isso as edições abaixo expõem os campos que importam, inclusive os fiscais.

/** Monta um patch só com o que veio preenchido (evita apagar campo por omissão). */
function patchDe(args: Record<string, unknown>, exceto: string[]): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(args).filter(([k, v]) => !exceto.includes(k) && v !== undefined && v !== null && v !== ""),
  );
}

/** Atualização genérica com as guardas comuns. */
async function atualizar(
  ctx: ToolCtx,
  tabela: string,
  idCampo: string,
  args: Record<string, unknown>,
  rotulo: string,
) {
  const bloqueio = blockTechnician(ctx);
  if (bloqueio) return bloqueio;
  const id = args[idCampo];
  if (!id) return { error: `Informe ${idCampo}.` };
  const patch = patchDe(args, [idCampo]);
  if (Object.keys(patch).length === 0) return { error: "Nada para atualizar — informe ao menos um campo." };

  const { data: antes } = await ctx.sb.from(tabela).select("*").eq("id", id).maybeSingle();
  if (!antes) return { error: `${rotulo} não encontrado.` };

  const { data, error } = await ctx.sb.from(tabela).update(patch).eq("id", id).select().single();
  if (error) throw error;

  // Devolve o antes/depois só dos campos tocados — resposta enxuta e auditável.
  const mudou: Record<string, unknown> = {};
  for (const k of Object.keys(patch)) mudou[k] = { de: (antes as any)[k] ?? null, para: (data as any)[k] ?? null };
  return { ok: true, [rotulo.toLowerCase()]: (data as any).name ?? id, alterado: mudou };
}

export const registryCrudTools: ToolDef[] = [
  {
    name: "update_product",
    description:
      "Atualiza um produto do catálogo: preço, custo, estoque mínimo, marca, unidade, código de barras, observações e os campos FISCAIS (NCM, CFOP, CSOSN, origem, alíquotas). Use para 'corrige o preço', 'esse produto é NCM tal', 'marca errada'. Sem NCM o produto não pode entrar em nota fiscal — se o usuário informar, grave.",
    input_schema: {
      type: "object",
      properties: {
        product_id: { type: "string", description: "UUID do produto." },
        name: { type: "string" },
        sku: { type: "string" },
        brand: { type: "string", description: "Marca/fabricante." },
        category: { type: "string" },
        unit: { type: "string", description: "Unidade (UN, PC, M...)." },
        cost_price: { type: "number", description: "Custo de compra." },
        sale_price: { type: "number", description: "Preço de venda." },
        minimum_stock: { type: "number" },
        barcode: { type: "string" },
        notes: { type: "string" },
        active: { type: "boolean" },
        ncm: { type: "string", description: "NCM — necessário para emitir NF-e." },
        cfop: { type: "string" },
        csosn: { type: "string" },
        fiscal_origin: { type: "number", description: "Origem fiscal (0=nacional...)." },
        profit_margin: { type: "number", description: "Margem em %." },
      },
      required: ["product_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      return await atualizar(ctx, "products", "product_id", args, "Produto");
    },
  },
  {
    name: "update_vessel",
    description:
      "Atualiza um ativo (embarcação/motorhome): nome, fabricante, modelo, ano, marina, e principalmente os EQUIPAMENTOS (motor, banco de baterias, inversor/carregador, eletrônica) — que é o que permite sugerir manutenção concreta depois. Use para corrigir dados ou registrar o que foi identificado no ativo.",
    input_schema: {
      type: "object",
      properties: {
        vessel_id: { type: "string", description: "UUID do ativo." },
        name: { type: "string" },
        manufacturer: { type: "string" },
        model: { type: "string" },
        year: { type: "number" },
        asset_type: { type: "string", description: "Tipo (embarcação, motorhome...)." },
        marina_id: { type: "string" },
        hull_id_or_registration: { type: "string", description: "Chassi/registro/placa." },
        engine_brand: { type: "string" },
        engine_model: { type: "string" },
        engine_type: { type: "string" },
        battery_bank_summary: { type: "string", description: "Resumo do banco de baterias." },
        inverter_charger_summary: { type: "string", description: "Inversor/carregador instalado." },
        navigation_electronics_summary: { type: "string", description: "Eletrônica de navegação." },
        electrical_system_notes: { type: "string", description: "Observações do sistema elétrico." },
        current_dock_position: { type: "string" },
        active: { type: "boolean" },
      },
      required: ["vessel_id"],
    },
    risk: "low",
    async execute(args, ctx) {
      return await atualizar(ctx, "vessels", "vessel_id", args, "Ativo");
    },
  },
  {
    name: "update_supplier",
    description:
      "Atualiza um fornecedor: contato, telefone (o que permite mandar cotação por WhatsApp), e-mail, endereço, condição de pagamento e observações. Use para 'esse fornecedor mudou de telefone', 'o contato agora é fulano'.",
    input_schema: {
      type: "object",
      properties: {
        supplier_id: { type: "string", description: "UUID do fornecedor." },
        name: { type: "string" },
        trade_name: { type: "string", description: "Nome fantasia." },
        cnpj_cpf: { type: "string" },
        contact_name: { type: "string" },
        phone: { type: "string", description: "Telefone/WhatsApp — sem ele não dá para enviar cotação." },
        email: { type: "string" },
        city: { type: "string" },
        state: { type: "string" },
        postal_code: { type: "string" },
        address_line_1: { type: "string" },
        payment_terms: { type: "string", description: "Condição de pagamento." },
        notes: { type: "string" },
        communication_tone: { type: "string", description: "Tom preferido na comunicação." },
        opt_out_whatsapp: { type: "boolean", description: "true = fornecedor NÃO quer receber WhatsApp (bloqueia envios de cotação)." },
        active: { type: "boolean" },
      },
      required: ["supplier_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      return await atualizar(ctx, "suppliers", "supplier_id", args, "Fornecedor");
    },
  },
  {
    name: "update_service",
    description:
      "Atualiza um serviço de mão de obra do catálogo: nome, descrição, preço padrão, unidade de cobrança (hora/visita/dia) e garantia. Use para 'reajusta o valor desse serviço'.",
    input_schema: {
      type: "object",
      properties: {
        service_id: { type: "string", description: "UUID do serviço." },
        name: { type: "string" },
        description: { type: "string" },
        category: { type: "string" },
        default_price: { type: "number" },
        billing_unit: { type: "string", enum: ["hour", "visit", "day", "unit"] },
        default_warranty_days: { type: "number" },
        active: { type: "boolean" },
      },
      required: ["service_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      return await atualizar(ctx, "services", "service_id", args, "Serviço");
    },
  },
];
