import type { ToolDef } from "./registry.ts";

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
];
