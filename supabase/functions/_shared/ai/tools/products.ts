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
    risk: "medium",
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
    risk: "medium",
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
    risk: "medium",
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
    risk: "medium",
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
