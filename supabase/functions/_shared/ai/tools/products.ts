import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

export const productTools: ToolDef[] = [
  {
    name: "search_products",
    description: "Busca produtos/equipamentos no catálogo.",
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
        .from("products")
        .select("id, name, sku, brand, sale_price, stock_quantity, unit")
        .eq("active", true)
        .or(`name.ilike.%${q}%,sku.ilike.%${q}%,brand.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "search_products_batch",
    description:
      "Busca VÁRIOS produtos de uma vez e devolve as melhores opções de cada um. Use SEMPRE que precisar levantar preços de uma lista de itens (montar orçamento, cotação, comparar): uma chamada resolve a lista inteira, em vez de dezenas de buscas. Devolve, por termo, até 3 candidatos com id, nome e preço — e marca os termos SEM resultado, que você deve tratar como 'valor provisório' em vez de travar o trabalho.",
    input_schema: {
      type: "object",
      properties: {
        queries: {
          type: "array",
          items: { type: "string" },
          description: "Termos a buscar (ex.: ['MultiPlus-II 12/3000','Orion 12/12','MPPT 100/50','SmartShunt']). Máximo 25.",
        },
        per_query: { type: "number", description: "Candidatos por termo (padrão 3, teto 5)." },
      },
      required: ["queries"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const termos = (Array.isArray(args.queries) ? args.queries : [])
        .map((q: unknown) => String(q || "").trim())
        .filter(Boolean)
        .slice(0, 25);
      if (termos.length === 0) return { error: "Informe ao menos um termo em queries." };
      const porTermo = Math.min(Number(args.per_query) || 3, 5);

      const achados: Array<Record<string, unknown>> = [];
      const semResultado: string[] = [];
      // Em paralelo: 25 buscas curtas custam menos que 25 turnos de conversa.
      await Promise.all(
        termos.map(async (q: string) => {
          const { data } = await sb
            .from("products")
            .select("id, name, sku, brand, sale_price, cost_price, unit")
            .eq("active", true)
            .or(`name.ilike.%${q}%,sku.ilike.%${q}%,brand.ilike.%${q}%`)
            .limit(porTermo);
          const opcoes = ((data as any[]) || []).map((p) => ({
            product_id: p.id,
            nome: p.name,
            sku: p.sku || null,
            marca: p.brand || null,
            preco_venda: p.sale_price != null ? Number(p.sale_price) : null,
            custo: p.cost_price != null ? Number(p.cost_price) : null,
            unidade: p.unit || null,
          }));
          if (opcoes.length === 0) semResultado.push(q);
          else achados.push({ termo: q, encontrados: opcoes.length, opcoes });
        }),
      );

      return {
        resultados: achados,
        sem_resultado: semResultado,
        instrucao:
          "Escolha o candidato mais adequado por termo e DIGA qual escolheu (nome e preço). Para os termos em 'sem_resultado', não trave: marque como 'Valor provisório — aguardando cotação do fornecedor' e siga.",
      };
    },
  },
  {
    name: "search_services",
    description: "Busca serviços de mão de obra no catálogo por nome ou descrição.",
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
        .from("services")
        .select("id, name, description, billing_unit, default_price")
        .eq("active", true)
        .or(`name.ilike.%${q}%,description.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "adjust_inventory",
    description: "Realiza um ajuste manual no estoque de um produto.",
    input_schema: {
      type: "object",
      properties: {
        product_id: { type: "string" },
        new_quantity: { type: "number" },
        reason: { type: "string" },
      },
      required: ["product_id", "new_quantity", "reason"],
    },
    risk: "low",
    async execute(args, { admin }) {
      const { product_id, new_quantity, reason } = args;
      const { data: prod } = await admin.from("products").select("stock_quantity").eq("id", product_id).single();
      const delta = new_quantity - (prod?.stock_quantity || 0);

      const { error: updateErr } = await admin.from("products").update({ stock_quantity: new_quantity }).eq("id", product_id);
      if (updateErr) throw updateErr;

      await admin.from("inventory_movements").insert({
        product_id,
        quantity_delta: delta,
        movement_type: "manual_adjustment",
        notes: reason,
      });

      return { ok: true, new_quantity };
    },
  },
  {
    name: "create_product",
    description: "Cadastra um novo produto/equipamento.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        sku: { type: "string" },
        sale_price: { type: "number" },
        cost_price: { type: "number" },
        unit: { type: "string" },
      },
      required: ["name"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("products").insert(args).select().single();
      if (error) throw error;
      return { ok: true, product: data };
    },
  },
  {
    name: "list_low_stock",
    description: "Lista produtos com estoque abaixo do mínimo cadastrado.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    async execute(_args, { admin }) {
      const { data, error } = await admin
        .from("products")
        .select("id, name, stock_quantity, minimum_stock, unit")
        .gt("minimum_stock", 0)
        .filter("stock_quantity", "lte", "minimum_stock")
        .order("name");
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "register_stock_entry",
    description: "Registra entrada de estoque (compra/reposição) de um produto, somando à quantidade atual.",
    input_schema: {
      type: "object",
      properties: {
        product_id: { type: "string" },
        quantity: { type: "number" },
        unit_cost: { type: "number" },
        notes: { type: "string" },
      },
      required: ["product_id", "quantity"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data: product, error: pErr } = await admin.from("products").select("stock_quantity").eq("id", args.product_id).single();
      if (pErr) return { error: `Produto não encontrado: ${pErr.message}` };
      const newQty = (product?.stock_quantity ?? 0) + args.quantity;
      const { error: uErr } = await admin.from("products").update({ stock_quantity: newQty }).eq("id", args.product_id);
      if (uErr) return { error: `Erro ao atualizar estoque: ${uErr.message}` };
      const { error: mErr } = await admin.from("inventory_movements").insert({
        product_id: args.product_id,
        movement_type: "purchase",
        quantity_delta: args.quantity,
        unit_cost_snapshot: args.unit_cost ?? null,
        reference_type: "manual_entry",
        notes: args.notes || null,
      });
      if (mErr) return { error: `Erro ao registrar movimento: ${mErr.message}` };
      return { ok: true, new_quantity: newQty };
    },
  },
  {
    name: "create_service",
    description: "Cadastra um novo serviço de mão de obra no catálogo.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        description: { type: "string" },
        billing_unit: { type: "string", enum: ["hour", "visit", "day", "unit"] },
        default_price: { type: "number" },
      },
      required: ["name", "billing_unit"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin.from("services").insert(args).select().single();
      if (error) throw error;
      return { ok: true, service: data };
    },
  },
];
