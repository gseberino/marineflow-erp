import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";

export const financialTools: ToolDef[] = [
  {
    name: "list_pending_collections",
    description: "Lista cobranças pendentes ou atrasadas. Pode filtrar por client_id.",
    input_schema: {
      type: "object",
      properties: { client_id: { type: "string" } },
    },
    risk: "low",
    async execute(args, { sb }) {
      let query = sb
        .from("collections")
        .select("id, client_id, due_date, amount, status, contact_name, contact_whatsapp, description")
        .in("status", ["pending", "overdue", "scheduled"])
        .order("due_date", { ascending: true })
        .limit(50);
      if (args.client_id) query = query.eq("client_id", args.client_id);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "get_os_receivables",
    description: "Lista os recebíveis e pagamentos de uma OS. Use para responder perguntas sobre o status financeiro de uma OS: quanto foi cobrado, quanto foi pago, saldo em aberto.",
    input_schema: {
      type: "object",
      properties: { service_order_id: { type: "string", description: "UUID da OS" } },
      required: ["service_order_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const soId = args.service_order_id;
      const { data: recs, error: recErr } = await sb
        .from("receivables")
        .select("id, description, amount, due_date, status, payment_method, is_deposit")
        .eq("service_order_id", soId)
        .neq("status", "cancelled")
        .order("due_date", { ascending: true });
      if (recErr) throw recErr;

      const recIds = (recs || []).map((r: any) => r.id);
      let payments: any[] = [];
      if (recIds.length > 0) {
        const { data: pays } = await sb
          .from("payments")
          .select("id, receivable_id, amount, payment_date, payment_method, notes")
          .in("receivable_id", recIds)
          .eq("status", "confirmed")
          .order("payment_date", { ascending: false });
        payments = pays || [];
      }

      const totalCharged = (recs || []).reduce((s: number, r: any) => s + Number(r.amount), 0);
      const totalPaid = payments.reduce((s: number, p: any) => s + Number(p.amount), 0);

      const statusMap: Record<string, string> = {
        pending: "Pendente", partial: "Parcialmente pago", paid: "Pago", overdue: "Vencido", cancelled: "Cancelado",
      };

      return {
        total_cobrado: totalCharged,
        total_pago: totalPaid,
        saldo_aberto: totalCharged - totalPaid,
        "recebíveis": (recs || []).map((r: any) => ({
          id: r.id,
          descricao: r.description,
          valor: r.amount,
          vencimento: r.due_date,
          status: statusMap[r.status] || r.status,
          is_sinal: r.is_deposit,
        })),
        pagamentos: payments.map((p: any) => ({
          valor: p.amount,
          data: p.payment_date,
          forma: p.payment_method,
          obs: p.notes,
        })),
      };
    },
  },
  {
    name: "get_technician_commissions",
    description: "Calcula ou lista as comissões de um técnico.",
    input_schema: {
      type: "object",
      properties: {
        technician_id: { type: "string" },
        status: { type: "string", enum: ["pending", "paid"] },
      },
    },
    risk: "low",
    async execute(args, { admin }) {
      let query = admin.from("commissions").select("*, service_orders(service_order_number)");
      if (args.technician_id) query = query.eq("user_id", args.technician_id);
      if (args.status) query = query.eq("status", args.status);
      const { data, error } = await query;
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "list_overdue_receivables",
    description: "Lista recebíveis vencidos ou próximos do vencimento (pendentes/parcialmente pagos/vencidos).",
    input_schema: {
      type: "object",
      properties: { days_ahead: { type: "number", description: "Inclui recebíveis que vencem até N dias à frente, além dos já vencidos. Padrão: 3." } },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const daysAhead = Number(args.days_ahead) || 3;
      const limitDate = new Date(Date.now() + daysAhead * 86400000).toISOString().slice(0, 10);
      const { data, error } = await admin
        .from("receivables")
        .select("id, description, amount, balance_amount, due_date, status, client_id, clients!receivables_client_id_fkey(name), service_orders!receivables_service_order_id_fkey(service_order_number)")
        .in("status", ["pending", "partially_paid", "overdue"])
        .lte("due_date", limitDate)
        .order("due_date", { ascending: true })
        .limit(50);
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "list_payables_due",
    description: "Lista contas a pagar vencidas ou próximas do vencimento.",
    input_schema: {
      type: "object",
      properties: { days_ahead: { type: "number", description: "Inclui contas que vencem até N dias à frente, além das já vencidas. Padrão: 7." } },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const daysAhead = Number(args.days_ahead) || 7;
      const limitDate = new Date(Date.now() + daysAhead * 86400000).toISOString().slice(0, 10);
      const { data, error } = await admin
        .from("payables")
        .select("id, description, amount, balance_amount, due_date, status, supplier_name, expense_category")
        .not("status", "in", "(paid,cancelled)")
        .lte("due_date", limitDate)
        .order("due_date", { ascending: true })
        .limit(50);
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "get_commissions_summary",
    description: "Resumo de comissões por período: total pendente e aprovado, e quantidade de lançamentos. Pode filtrar por técnico.",
    input_schema: {
      type: "object",
      properties: {
        period: { type: "string", description: "Mês no formato YYYY-MM. Se omitido, considera todos os lançamentos." },
        user_id: { type: "string", description: "UUID do técnico/vendedor. Se omitido, soma todos." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      let query = admin.from("commissions").select("amount, status, created_at, user_id");
      if (args.user_id) query = query.eq("user_id", args.user_id);
      if (args.period) {
        const [y, m] = String(args.period).split("-").map(Number);
        const start = new Date(y, m - 1, 1).toISOString();
        const end = new Date(y, m, 0, 23, 59, 59).toISOString();
        query = query.gte("created_at", start).lte("created_at", end);
      }
      const { data, error } = await query;
      if (error) throw error;
      const rows = data || [];
      const sum = (status: string) => rows.filter((r: any) => r.status === status).reduce((s: number, r: any) => s + Number(r.amount), 0);
      return {
        periodo: args.period || "todos",
        total_pendente: sum("pending"),
        total_aprovado: sum("approved"),
        total_pago: sum("paid"),
        quantidade_lancamentos: rows.length,
      };
    },
  },
  {
    name: "create_receivable",
    description: "Cria uma conta a receber (cobrança) avulsa ou vinculada a uma OS.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string" },
        description: { type: "string" },
        issue_date: { type: "string", description: "Data de emissão (ISO date)" },
        due_date: { type: "string", description: "Data de vencimento (ISO date)" },
        amount: { type: "number" },
        service_order_id: { type: "string" },
        notes: { type: "string" },
      },
      required: ["client_id", "description", "issue_date", "due_date", "amount"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin
        .from("receivables")
        .insert({ ...args, balance_amount: args.amount, paid_amount: 0, status: "pending" })
        .select()
        .single();
      if (error) throw error;
      return { ok: true, receivable: data };
    },
  },
  {
    name: "create_payable",
    description: "Cria uma conta a pagar (despesa).",
    input_schema: {
      type: "object",
      properties: {
        description: { type: "string" },
        issue_date: { type: "string", description: "Data de emissão (ISO date)" },
        due_date: { type: "string", description: "Data de vencimento (ISO date)" },
        amount: { type: "number" },
        expense_category: { type: "string" },
        supplier_id: { type: "string" },
        linked_service_order_id: { type: "string" },
        notes: { type: "string" },
      },
      required: ["description", "issue_date", "due_date", "amount"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin
        .from("payables")
        .insert({ ...args, balance_amount: args.amount, paid_amount: 0, status: "pending" })
        .select()
        .single();
      if (error) throw error;
      return { ok: true, payable: data };
    },
  },
  {
    name: "register_payment",
    description: "Registra o pagamento de um recebível ou de uma conta a pagar (RPC atômica, atualiza saldo).",
    input_schema: {
      type: "object",
      properties: {
        receivable_id: { type: "string", description: "Informe este OU payable_id" },
        payable_id: { type: "string" },
        amount: { type: "number" },
        payment_date: { type: "string", description: "ISO date" },
        payment_method: { type: "string" },
        installments: { type: "number" },
        card_fee_percent: { type: "number" },
        notes: { type: "string" },
      },
      required: ["amount", "payment_date", "payment_method"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin.rpc("register_payment_and_update_balance", {
        p_receivable_id: args.receivable_id || null,
        p_payable_id: args.payable_id || null,
        p_amount: args.amount,
        p_payment_date: String(args.payment_date).split("T")[0],
        p_payment_method: args.payment_method,
        p_installments: args.installments || 1,
        p_card_fee_percent: args.card_fee_percent || 0,
        p_net_amount: args.amount,
        p_notes: args.notes || null,
      });
      if (error) return { error: error.message };
      return { ok: true, payment_id: (data as any)?.payment_id };
    },
  },
  {
    name: "register_deposit_and_convert",
    description: "Registra o pagamento do sinal de um orçamento e converte automaticamente em Ordem de Serviço (RPC atômica).",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID do orçamento (draft)" },
        amount: { type: "number" },
        payment_date: { type: "string", description: "ISO date" },
        payment_method: { type: "string" },
        card_fee_percent: { type: "number" },
        notes: { type: "string" },
      },
      required: ["service_order_id", "amount", "payment_date", "payment_method"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin.rpc("register_deposit_and_convert", {
        p_service_order_id: args.service_order_id,
        p_amount: args.amount,
        p_payment_date: String(args.payment_date).split("T")[0],
        p_payment_method: args.payment_method,
        p_card_fee_percent: args.card_fee_percent || 0,
        p_notes: args.notes || null,
      });
      if (error) return { error: error.message };
      return { ok: true, result: data };
    },
  },
];
