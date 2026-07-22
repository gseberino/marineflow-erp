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
  {
    name: "update_receivable",
    description:
      "Corrige um RECEBÍVEL já lançado: vencimento, valor, descrição, categoria, centro de custo ou observação. Use para 'muda o vencimento dessa parcela', 'o valor está errado'. Ação sensível (mexe no que o cliente deve) — pede confirmação. NÃO registra pagamento: para isso use register_payment.",
    input_schema: {
      type: "object",
      properties: {
        receivable_id: { type: "string", description: "UUID do recebível (de list_overdue_receivables/get_os_receivables)." },
        due_date: { type: "string", description: "Novo vencimento (ISO date)." },
        amount: { type: "number", description: "Novo valor total." },
        description: { type: "string" },
        category: { type: "string", description: "Categoria financeira (veja list_reference_data)." },
        cost_center_id: { type: "string" },
        notes: { type: "string" },
      },
      required: ["receivable_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const { receivable_id, ...campos } = args as Record<string, unknown>;
      const patch = Object.fromEntries(Object.entries(campos).filter(([, v]) => v !== undefined && v !== null && v !== ""));
      if (Object.keys(patch).length === 0) return { error: "Informe ao menos um campo para alterar." };

      const { data: antes } = await sb.from("receivables").select("description, amount, balance_amount, due_date, status, paid_amount").eq("id", receivable_id).maybeSingle();
      if (!antes) return { error: "Recebível não encontrado." };
      if (antes.status === "cancelled") return { error: "Recebível cancelado não pode ser alterado." };
      // Reduzir o valor abaixo do que já foi pago deixaria o título inconsistente.
      if (patch.amount != null && Number(patch.amount) < (Number(antes.paid_amount) || 0)) {
        return { error: `O novo valor (R$ ${Number(patch.amount).toFixed(2)}) é menor que o já pago (R$ ${(Number(antes.paid_amount) || 0).toFixed(2)}).` };
      }
      // Mexer no valor exige recalcular o saldo em aberto.
      if (patch.amount != null) patch.balance_amount = Number(patch.amount) - (Number(antes.paid_amount) || 0);

      const { data, error } = await sb.from("receivables").update(patch).eq("id", receivable_id).select().single();
      if (error) throw error;
      return {
        ok: true,
        antes: { valor: Number(antes.amount) || 0, vencimento: antes.due_date, saldo: Number(antes.balance_amount) || 0 },
        depois: { valor: Number(data.amount) || 0, vencimento: data.due_date, saldo: Number(data.balance_amount) || 0 },
      };
    },
  },
  {
    name: "update_payable",
    description:
      "Corrige uma CONTA A PAGAR já lançada: vencimento, valor, descrição, fornecedor, categoria de despesa, centro de custo ou observação. Use para 'adia o vencimento dessa conta', 'o valor veio diferente na nota'. Ação sensível — pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        payable_id: { type: "string", description: "UUID da conta a pagar (de list_payables_due)." },
        due_date: { type: "string", description: "Novo vencimento (ISO date)." },
        amount: { type: "number", description: "Novo valor total." },
        description: { type: "string" },
        supplier_id: { type: "string" },
        expense_category: { type: "string" },
        cost_center_id: { type: "string" },
        notes: { type: "string" },
      },
      required: ["payable_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const { payable_id, ...campos } = args as Record<string, unknown>;
      const patch = Object.fromEntries(Object.entries(campos).filter(([, v]) => v !== undefined && v !== null && v !== ""));
      if (Object.keys(patch).length === 0) return { error: "Informe ao menos um campo para alterar." };

      const { data: antes } = await sb.from("payables").select("description, amount, balance_amount, due_date, status, paid_amount").eq("id", payable_id).maybeSingle();
      if (!antes) return { error: "Conta a pagar não encontrada." };
      if (antes.status === "paid") return { error: "Conta já paga não pode ser alterada." };
      if (patch.amount != null && Number(patch.amount) < (Number(antes.paid_amount) || 0)) {
        return { error: "O novo valor é menor que o já pago nessa conta." };
      }
      if (patch.amount != null) patch.balance_amount = Number(patch.amount) - (Number(antes.paid_amount) || 0);

      const { data, error } = await sb.from("payables").update(patch).eq("id", payable_id).select().single();
      if (error) throw error;
      return {
        ok: true,
        antes: { valor: Number(antes.amount) || 0, vencimento: antes.due_date },
        depois: { valor: Number(data.amount) || 0, vencimento: data.due_date },
      };
    },
  },
  {
    name: "get_period_summary",
    description:
      "FECHAMENTO do período: quanto ENTROU, quanto SAIU, o saldo, e as pendências que pedem ação (a receber vencido, contas a pagar vencendo, OS concluídas). Use para 'como foi hoje?', 'fechamento da semana', 'resumo do mês'. Só leitura — não registra nada.",
    input_schema: {
      type: "object",
      properties: {
        period: { type: "string", enum: ["hoje", "ontem", "semana", "mes"], description: "Período do fechamento (padrão: hoje). 'semana' = últimos 7 dias; 'mes' = mês corrente." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;

      const hoje = new Date();
      const iso = (d: Date) => d.toISOString().slice(0, 10);
      const periodo = String(args.period || "hoje");
      let de = iso(hoje);
      let ate = iso(hoje);
      if (periodo === "ontem") {
        const o = new Date(hoje.getTime() - 86400000);
        de = iso(o); ate = iso(o);
      } else if (periodo === "semana") {
        de = iso(new Date(hoje.getTime() - 6 * 86400000));
      } else if (periodo === "mes") {
        de = iso(new Date(hoje.getFullYear(), hoje.getMonth(), 1));
      }

      // ENTRADAS: vêm da tabela payments (payment_date é a data do recebimento).
      const { data: pays } = await sb
        .from("payments")
        .select("amount, net_amount, receivable_id, payment_method, payment_date, status")
        .gte("payment_date", de)
        .lte("payment_date", ate)
        .eq("status", "confirmed");

      let entrou = 0, nEntradas = 0;
      const porMetodo: Record<string, number> = {};
      for (const p of (pays as any[]) || []) {
        if (!p.receivable_id) continue;
        const v = Number(p.net_amount ?? p.amount) || 0;
        entrou += v; nEntradas++;
        const m = p.payment_method || "não informado";
        porMetodo[m] = (porMetodo[m] || 0) + v;
      }

      // SAÍDAS: conferido no banco — pagamento de conta a pagar NÃO passa por `payments`
      // (é marcado direto em payables). Então a fonte da verdade aqui é payables.
      // Não existe paid_at no schema: usamos updated_at (quando a conta foi marcada paga).
      const { data: pagos } = await sb
        .from("payables")
        .select("paid_amount, amount, status, updated_at")
        .eq("status", "paid")
        .gte("updated_at", `${de}T00:00:00`)
        .lte("updated_at", `${ate}T23:59:59`);
      let saiu = 0, nSaidas = 0;
      for (const p of (pagos as any[]) || []) {
        saiu += Number(p.paid_amount ?? p.amount) || 0;
        nSaidas++;
      }

      // Pendências que pedem ação.
      const { data: venc } = await sb
        .from("receivables")
        .select("balance_amount, amount")
        .in("status", ["pending", "partially_paid"])
        .eq("is_deposit", false)
        .lt("due_date", iso(hoje));
      const vencidoTotal = ((venc as any[]) || []).reduce((a, r) => a + (Number(r.balance_amount ?? r.amount) || 0), 0);

      const em7 = iso(new Date(hoje.getTime() + 7 * 86400000));
      const { data: pag } = await sb
        .from("payables")
        .select("amount, balance_amount, due_date")
        .lte("due_date", em7)
        .gt("balance_amount", 0);
      const aPagar = ((pag as any[]) || []).reduce((a, p) => a + (Number(p.balance_amount ?? p.amount) || 0), 0);

      const { count: osConcluidas } = await sb
        .from("service_orders")
        .select("id", { count: "exact", head: true })
        .in("status", ["completed", "invoiced"])
        .gte("updated_at", `${de}T00:00:00`);

      const r2 = (n: number) => Math.round(n * 100) / 100;
      return {
        periodo,
        de,
        ate,
        entrou: r2(entrou),
        saiu: r2(saiu),
        saldo: r2(entrou - saiu),
        qtd_entradas: nEntradas,
        qtd_saidas: nSaidas,
        entradas_por_metodo: Object.fromEntries(Object.entries(porMetodo).map(([k, v]) => [k, r2(v)])),
        pendencias: {
          a_receber_vencido: r2(vencidoTotal),
          a_pagar_proximos_7_dias: r2(aPagar),
        },
        os_concluidas_no_periodo: osConcluidas ?? 0,
      };
    },
  },
  {
    name: "get_delinquency_plan",
    description:
      "Plano de ação da INADIMPLÊNCIA: recebíveis vencidos priorizados por impacto (maior valor primeiro), com dias de atraso e QUANDO o cliente foi cobrado pela última vez — para não cobrar a mesma pessoa duas vezes. Só leitura: não envia cobrança (isso é send_collection_reminder, que pede confirmação).",
    input_schema: {
      type: "object",
      properties: {
        limit: { type: "number", description: "Máximo de casos (padrão 10, teto 30)." },
        min_days_overdue: { type: "number", description: "Só vencidos há pelo menos N dias (padrão 1)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const limite = Math.min(Number(args.limit) || 10, 30);
      const minDias = Number(args.min_days_overdue) > 0 ? Number(args.min_days_overdue) : 1;
      const hoje = new Date();
      const hojeIso = hoje.toISOString().slice(0, 10);

      const { data: recs, error } = await sb
        .from("receivables")
        .select("id, description, amount, balance_amount, due_date, client_id, service_order_id, clients(name)")
        .in("status", ["pending", "partially_paid"])
        .eq("is_deposit", false)
        .lt("due_date", hojeIso)
        .limit(200);
      if (error) throw error;

      // Última cobrança enviada por cliente — evita cobrar de novo no mesmo dia.
      const clientIds = [...new Set(((recs as any[]) || []).map((r) => r.client_id).filter(Boolean))];
      const ultimaCobranca: Record<string, string> = {};
      if (clientIds.length) {
        const { data: cols } = await sb
          .from("collections")
          .select("client_id, last_auto_sent_at")
          .in("client_id", clientIds)
          .not("last_auto_sent_at", "is", null);
        for (const c of (cols as any[]) || []) {
          const k = String(c.client_id);
          if (!ultimaCobranca[k] || new Date(c.last_auto_sent_at) > new Date(ultimaCobranca[k])) {
            ultimaCobranca[k] = c.last_auto_sent_at;
          }
        }
      }

      const casos = ((recs as any[]) || [])
        .map((r: any) => {
          const saldo = Number(r.balance_amount ?? r.amount) || 0;
          const dias = Math.floor((hoje.getTime() - new Date(`${r.due_date}T00:00:00`).getTime()) / 86400000);
          const ult = r.client_id ? ultimaCobranca[String(r.client_id)] || null : null;
          const diasDesdeCobranca = ult ? Math.floor((hoje.getTime() - new Date(ult).getTime()) / 86400000) : null;
          return {
            receivable_id: r.id,
            cliente: r.clients?.name || "(sem cliente)",
            client_id: r.client_id,
            descricao: r.description || null,
            saldo: Math.round(saldo * 100) / 100,
            dias_atraso: dias,
            ultima_cobranca: ult,
            dias_desde_ultima_cobranca: diasDesdeCobranca,
            ja_cobrado_hoje: diasDesdeCobranca === 0,
          };
        })
        .filter((c) => c.dias_atraso >= minDias && c.saldo > 0)
        .sort((a, b) => b.saldo - a.saldo)
        .slice(0, limite);

      const total = casos.reduce((a, c) => a + c.saldo, 0);
      return {
        count: casos.length,
        total_em_atraso: Math.round(total * 100) / 100,
        ordem_sugerida: "maior valor primeiro (impacto de caixa)",
        casos,
        nota: "Não cobre quem já foi cobrado hoje. Enviar cobrança é ação sensível — o sistema pede sua confirmação.",
      };
    },
  },
];
