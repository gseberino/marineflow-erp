import type { ToolDef } from "./registry.ts";

export const purchasingTools: ToolDef[] = [
  {
    name: "create_purchase_order",
    description: "Cria uma nova ordem de compra para um fornecedor.",
    input_schema: {
      type: "object",
      properties: {
        supplier_id: { type: "string" },
        service_order_id: { type: "string" },
        expected_date: { type: "string", description: "Data esperada (ISO date)" },
        notes: { type: "string" },
        items: {
          type: "array",
          items: {
            type: "object",
            properties: {
              product_id: { type: "string" },
              description: { type: "string" },
              quantity: { type: "number" },
              unit_cost: { type: "number" },
            },
            required: ["description", "quantity", "unit_cost"],
          },
        },
      },
      required: ["supplier_id"],
    },
    risk: "medium",
    async execute(args, { sb, userId }) {
      const { supplier_id, service_order_id, items, ...rest } = args;
      const { data: po, error } = await sb
        .from("purchase_orders")
        .insert({ ...rest, supplier_id, service_order_id, status: rest.status || "draft", created_by: userId })
        .select()
        .single();
      if (error) throw error;
      if (Array.isArray(items) && items.length > 0) {
        await sb.from("purchase_order_items").insert(items.map((it: any) => ({ ...it, purchase_order_id: po.id })));
      }
      return { ok: true, purchase_order: po };
    },
  },
];
