import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolCtx, type ToolDef } from "./registry.ts";
import { mensagemDoBanco } from "./lancamentos.ts";

/** Campos que o modelo pode pedir para LIMPAR (deixar vazio) numa correção. */
const LIMPAVEIS: Record<string, { payable?: string; receivable?: string }> = {
  observacao: { payable: "notes", receivable: "notes" },
  categoria: { payable: "expense_category", receivable: "category" },
  fornecedor: { payable: "supplier_id" },
  favorecido: { payable: "payee_id" },
  os: { payable: "linked_service_order_id", receivable: "service_order_id" },
  centro_de_custo: { payable: "cost_center_id", receivable: "cost_center_id" },
};

/**
 * Monta o que vai para corrigir_lancamento a partir dos argumentos da tool.
 *
 * Só entra o que veio preenchido; o que a pessoa pediu para tirar ("tira a OS dessa
 * despesa") vem em `limpar` e vira null. Exportada para o teste: é aqui que "vazio"
 * poderia virar "apagar sem querer".
 */
export function camposDaCorrecao(
  tipo: "payable" | "receivable",
  args: Record<string, unknown>,
  permitidos: string[],
): { campos: Record<string, unknown> } | { error: string } {
  const campos: Record<string, unknown> = {};
  for (const chave of permitidos) {
    const v = args[chave];
    if (v === undefined || v === null || v === "") continue;
    campos[chave] = v;
  }
  const limpar = Array.isArray(args.limpar) ? args.limpar.map(String) : [];
  for (const nome of limpar) {
    const coluna = LIMPAVEIS[nome]?.[tipo];
    if (!coluna) return { error: `Não dá para limpar "${nome}" ${tipo === "payable" ? "numa conta a pagar" : "numa conta a receber"}.` };
    if (coluna in campos) return { error: `"${nome}" veio para mudar e para limpar ao mesmo tempo.` };
    campos[coluna] = null;
  }
  if (Object.keys(campos).length === 0) return { error: "Informe ao menos um campo para alterar." };
  return { campos };
}

async function corrigirPeloBanco(
  ctx: ToolCtx, tipo: "payable" | "receivable", id: string, campos: Record<string, unknown>, motivo: unknown,
) {
  const { data, error } = await ctx.sb.rpc("corrigir_lancamento", {
    p_tipo: tipo, p_id: id, p_campos: campos,
    p_motivo: typeof motivo === "string" && motivo.trim() ? motivo.trim() : null,
    p_autor: ctx.userId || null,
  });
  if (error) return { error: mensagemDoBanco(error) };
  return data;
}


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
    // Decisão do dono (09/08/2026): o cargo técnico não enxerga nada financeiro.
    // Vale nos dois planos — RLS no banco e tool do agente.
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
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
    // Roda com service role e devolve as comissões de QUALQUER técnico — é ferramenta de
    // gestão, não consulta pessoal. Se um dia o técnico precisar ver as próprias, a tool
    // certa é outra, filtrando por ctx.userId (a RLS de `commissions` já permite isso).
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
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
      "Corrige uma CONTA A RECEBER já lançada — inclusive já recebida: cliente, OS, categoria, descrição, data, vencimento, valor, centro de custo ou observação. Use para 'muda o vencimento dessa parcela', 'esse recebimento é da OS-60', 'o cliente está errado'. Para tirar a OS ou a categoria, use limpar. Mês fechado recusa (só observação passa); valor que veio do banco não muda. Vai para a trilha. Pede confirmação. NÃO registra pagamento: para isso use register_payment.",
    input_schema: {
      type: "object",
      properties: {
        receivable_id: { type: "string", description: "UUID do recebível (de buscar_lancamentos, list_overdue_receivables ou get_os_receivables)." },
        client_id: { type: "string" },
        service_order_id: { type: "string", description: "OS a que o recebimento pertence." },
        category: { type: "string", description: "Categoria financeira (veja listar_categorias_financeiras)." },
        description: { type: "string" },
        issue_date: { type: "string", description: "Data do lançamento (ISO date)." },
        due_date: { type: "string", description: "Novo vencimento (ISO date)." },
        amount: { type: "number", description: "Novo valor total." },
        cost_center_id: { type: "string" },
        notes: { type: "string" },
        limpar: { type: "array", items: { type: "string", enum: ["observacao", "categoria", "os", "centro_de_custo"] }, description: "Campos a deixar vazios." },
        motivo: { type: "string", description: "Por que corrigir — vai para a trilha." },
      },
      required: ["receivable_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const r = camposDaCorrecao("receivable", args, [
        "client_id", "service_order_id", "category", "description", "issue_date", "due_date", "amount", "cost_center_id", "notes",
      ]);
      if ("error" in r) return r;
      return await corrigirPeloBanco(ctx, "receivable", String(args.receivable_id), r.campos, args.motivo);
    },
  },
  {
    name: "update_payable",
    description:
      "Corrige uma CONTA A PAGAR ou DESPESA já lançada — inclusive já paga e as que vieram do extrato: fornecedor, favorecido (pessoa), OS, categoria de despesa, descrição, data, vencimento, valor, centro de custo ou observação. Use para 'essa despesa é da OS-60', 'muda a categoria do almoço para alimentação', 'o fornecedor é a Coremma', 'adia o vencimento'. Para tirar OS/favorecido/fornecedor, use limpar. Mês fechado recusa (só observação passa); valor que veio do banco não muda (para isso, desfazer_aprovacao_de_lancamento). Vai para a trilha. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        payable_id: { type: "string", description: "UUID da conta a pagar (de buscar_lancamentos ou list_payables_due)." },
        supplier_id: { type: "string" },
        payee_id: { type: "string", description: "Favorecido pessoa (sócio, funcionário, diarista) — veja listar_favorecidos." },
        linked_service_order_id: { type: "string", description: "OS a que o custo pertence." },
        expense_category: { type: "string", description: "Categoria de despesa (veja listar_categorias_financeiras)." },
        description: { type: "string" },
        issue_date: { type: "string", description: "Data do lançamento (ISO date)." },
        due_date: { type: "string", description: "Novo vencimento (ISO date)." },
        amount: { type: "number", description: "Novo valor total." },
        cost_center_id: { type: "string" },
        notes: { type: "string" },
        limpar: { type: "array", items: { type: "string", enum: ["observacao", "categoria", "fornecedor", "favorecido", "os", "centro_de_custo"] }, description: "Campos a deixar vazios." },
        motivo: { type: "string", description: "Por que corrigir — vai para a trilha." },
      },
      required: ["payable_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const r = camposDaCorrecao("payable", args, [
        "supplier_id", "payee_id", "linked_service_order_id", "expense_category", "description",
        "issue_date", "due_date", "amount", "cost_center_id", "notes",
      ]);
      if ("error" in r) return r;
      return await corrigirPeloBanco(ctx, "payable", String(args.payable_id), r.campos, args.motivo);
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
        .sort((a, b) => b.saldo - a.saldo);

      // D21 (dono, 17/09/2026): abaixo do piso de materialidade a IA LISTA, mas não cobra.
      // Mandar mensagem por R$ 80 custa mais relação do que vale o dinheiro.
      const { data: cfgPiso } = await ctx.admin.from("app_settings").select("value").eq("key", "collection_min_amount").maybeSingle();
      const piso = Number((cfgPiso as { value?: string } | null)?.value) || 0;
      const cobraveis = casos.filter((c) => c.saldo >= piso).slice(0, limite);
      const abaixoDoPiso = casos.filter((c) => c.saldo < piso);

      const total = cobraveis.reduce((a, c) => a + c.saldo, 0);
      return {
        count: cobraveis.length,
        total_em_atraso: Math.round(total * 100) / 100,
        ordem_sugerida: "maior valor primeiro (impacto de caixa)",
        casos: cobraveis,
        piso_de_cobranca: piso,
        abaixo_do_piso: abaixoDoPiso.map((c) => ({ cliente: c.cliente, saldo: c.saldo, dias_atraso: c.dias_atraso })),
        nota: `Não cobre quem já foi cobrado hoje nem valores abaixo de R$ ${piso} (só listados). Enviar cobrança é ação sensível — o sistema pede sua confirmação.`,
      };
    },
  },
];
