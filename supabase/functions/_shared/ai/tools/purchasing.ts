import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

// Mesmo esquema de numeração não-atômico usado em useCreatePOFromOS (frontend) —
// replicado aqui para gerar o mesmo formato "OC-00001".
async function generatePONumber(admin: any): Promise<string> {
  const { data } = await admin.from("purchase_orders").select("po_number").order("created_at", { ascending: false }).limit(1);
  let seq = 1;
  const last = data?.[0]?.po_number;
  if (last) {
    const match = String(last).match(/(\d+)$/);
    if (match) seq = parseInt(match[1], 10) + 1;
  }
  return `OC-${String(seq).padStart(5, "0")}`;
}

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
  {
    name: "list_pending_pos",
    description: "Lista ordens de compra ainda não totalmente recebidas (rascunho, enviada ou parcialmente recebida).",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    async execute(_args, { admin }) {
      const { data, error } = await admin
        .from("purchase_orders")
        .select("id, po_number, status, expected_date, total_amount, suppliers(name), service_orders(service_order_number)")
        .in("status", ["draft", "sent", "partial"])
        .order("expected_date", { ascending: true })
        .limit(50);
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "create_purchase_order_from_so",
    description: "Cria uma ordem de compra com um item, vinculada a uma OS específica (peça sob encomenda), e move a OS para 'Aguardando peças'.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        product_id: { type: "string" },
        product_name: { type: "string", description: "Descrição do item na OC" },
        quantity: { type: "number" },
        unit_cost: { type: "number" },
        supplier_id: { type: "string" },
        expected_date: { type: "string", description: "ISO date" },
        notes: { type: "string" },
      },
      required: ["service_order_id", "product_id", "product_name", "quantity", "unit_cost"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const poNumber = await generatePONumber(admin);
      const { data: po, error: poErr } = await admin
        .from("purchase_orders")
        .insert({
          po_number: poNumber,
          service_order_id: args.service_order_id,
          supplier_id: args.supplier_id ?? null,
          expected_date: args.expected_date ?? null,
          notes: args.notes ?? null,
          status: "draft",
        })
        .select()
        .single();
      if (poErr) throw poErr;

      const { error: itemErr } = await admin.from("purchase_order_items").insert({
        purchase_order_id: po.id,
        product_id: args.product_id,
        description: args.product_name,
        quantity: args.quantity,
        unit_cost: args.unit_cost,
      });
      if (itemErr) throw itemErr;

      await admin
        .from("service_orders")
        .update({ status: "awaiting_parts" })
        .eq("id", args.service_order_id)
        .in("status", ["open", "in_progress", "approved", "scheduled"]);

      return { ok: true, purchase_order: po };
    },
  },
  {
    name: "receive_purchase_order",
    description: "Registra o recebimento (total ou parcial) de itens de uma ordem de compra — RPC atômica que atualiza estoque e gera conta a pagar.",
    input_schema: {
      type: "object",
      properties: {
        po_id: { type: "string" },
        items: {
          type: "array",
          description: "Itens recebidos com a quantidade recebida",
          items: {
            type: "object",
            properties: { po_item_id: { type: "string" }, received_qty: { type: "number" } },
            required: ["po_item_id", "received_qty"],
          },
        },
        due_days: { type: "number", description: "Prazo em dias para a conta a pagar gerada. Padrão: 30." },
      },
      required: ["po_id", "items"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin.rpc("receive_po", {
        p_po_id: args.po_id,
        p_items: args.items,
        p_due_days: args.due_days || 30,
      });
      if (error) return { error: error.message };
      return { ok: true, result: data };
    },
  },
  {
    name: "create_supplier",
    description: "Cadastra um novo fornecedor.",
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
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin.from("suppliers").insert(args).select().single();
      if (error) throw error;
      return { ok: true, supplier: data };
    },
  },
];
