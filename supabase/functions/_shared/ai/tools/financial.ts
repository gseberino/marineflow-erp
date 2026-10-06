import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolCtx, type ToolDef } from "./registry.ts";
import { ESQUEMA_DA_FORMA, formaDePagamento, validarForma } from "./forma-de-pagamento.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import { pixEsperandoNoExtrato } from "./pix-esperando.ts";
import { descreverSaldo, parcelasDoSaldo } from "./saldo-do-sinal.ts";
import {
  COLUNAS_DO_FLUXO, FUNCAO_DA_RAIZ_DA_EMPRESA, ROTULO_DO_DESTINO, hojeEmBrasilia, mesesInteirosDoPeriodo, somarDias,
  somarFluxoDoPeriodo, type DestinoDeFora, type LinhaDoFluxo, type OpcoesDoFluxo,
} from "../../banking/fluxo-de-caixa.ts";

/** O recorte de dias do fechamento, em datas de Brasília ('AAAA-MM-DD'). */
export function periodoDoFechamento(periodo: string, hoje: string): { de: string; ate: string } {
  if (periodo === "ontem") {
    const ontem = somarDias(hoje, -1);
    return { de: ontem, ate: ontem };
  }
  if (periodo === "semana") return { de: somarDias(hoje, -6), ate: hoje };
  if (periodo === "mes") return { de: `${hoje.slice(0, 7)}-01`, ate: hoje };
  return { de: hoje, ate: hoje };
}

/**
 * As linhas do extrato (conta corrente e Caixa) dos meses INTEIROS que o recorte toca — o
 * pareamento de cada mês usa o mês todo, como nas telas — e a raiz do CNPJ da empresa. Em
 * páginas: o servidor corta em 1.000 linhas sem avisar.
 */
async function lerExtratoDoFluxo(sb: ToolCtx["sb"], de: string, ate: string): Promise<{ linhas: LinhaDoFluxo[]; opcoes: OpcoesDoFluxo }> {
  const meses = mesesInteirosDoPeriodo(de, ate);
  const tudo: LinhaDoFluxo[] = [];
  for (let i = 0; i < 50_000; i += 1000) {
    const { data, error } = await sb.from("bank_transactions")
      .select(COLUNAS_DO_FLUXO)
      .in("source_type", ["bank", "cash"])
      .gte("transaction_date", meses.de)
      .lte("transaction_date", meses.ate)
      .order("transaction_date")
      .order("id")
      .range(i, i + 999);
    if (error) throw error;
    const lote = (data ?? []) as LinhaDoFluxo[];
    tudo.push(...lote);
    if (lote.length < 1000) break;
  }
  // Sem conseguir ler a raiz, o fechamento falha como a tela: seguir sem ela mudaria os números
  // em silêncio. Raiz vazia (empresa sem CNPJ cadastrado) é outra coisa: a regra segue sem ela.
  const { data: raiz, error: erroDaRaiz } = await sb.rpc(FUNCAO_DA_RAIZ_DA_EMPRESA);
  if (erroDaRaiz) throw erroDaRaiz;
  return { linhas: tudo, opcoes: { raizDaEmpresa: typeof raiz === "string" && raiz.length === 8 ? raiz : null } };
}

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
        // Sem checar o erro, uma falha virava "total pago 0" — "o cliente não pagou nada" (02/10/2026).
        const { data: pays, error: payErr } = await sb
          .from("payments")
          .select("id, receivable_id, amount, payment_date, payment_method, notes")
          .in("receivable_id", recIds)
          .eq("status", "confirmed")
          .order("payment_date", { ascending: false });
        if (payErr) throw payErr;
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
        payment_method: ESQUEMA_DA_FORMA,
        installments: { type: "number" },
        card_fee_percent: { type: "number" },
        notes: { type: "string" },
      },
      required: ["amount", "payment_date", "payment_method"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    // Forma que o banco não aceita é recusada ANTES da pendência, não depois do PIN (05/10/2026).
    preValidar: (args) => validarForma(args),
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const forma = validarForma(args);
      if (forma) return forma;
      const { admin } = ctx;
      const { data, error } = await admin.rpc("register_payment_and_update_balance", {
        p_receivable_id: args.receivable_id || null,
        p_payable_id: args.payable_id || null,
        p_amount: args.amount,
        p_payment_date: String(args.payment_date).split("T")[0],
        p_payment_method: formaDePagamento(args.payment_method),
        p_installments: args.installments || 1,
        p_card_fee_percent: args.card_fee_percent || 0,
        p_net_amount: args.amount,
        p_notes: args.notes || null,
        // O assistente roda sem sessão (service role): quem pediu vai junto e o banco confere o
        // cargo. Sem isto, toda baixa voltava "acesso negado" (06/10/2026).
        p_autor: ctx.userId || null,
      });
      if (error) return { error: error.message };
      return { ok: true, payment_id: (data as any)?.payment_id };
    },
  },
  {
    name: "register_deposit_and_convert",
    description: "Registra o pagamento do sinal de um orçamento e converte automaticamente em Ordem de Serviço (RPC atômica). O SALDO vira conta a receber junto (pela condição de pagamento; sem ela, o restante na entrega).",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID do orçamento (draft)" },
        amount: { type: "number" },
        payment_date: { type: "string", description: "ISO date" },
        payment_method: ESQUEMA_DA_FORMA,
        card_fee_percent: { type: "number" },
        notes: { type: "string" },
      },
      required: ["service_order_id", "amount", "payment_date", "payment_method"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    preValidar: (args) => validarForma(args),
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const forma = validarForma(args);
      if (forma) return forma;
      const { admin } = ctx;
      const dataDoSinal = String(args.payment_date).split("T")[0];
      // O saldo vira conta a receber junto, como no "Receber sinal" da tela (06/10/2026).
      const saldo = await parcelasDoSaldo(ctx, String(args.service_order_id), Number(args.amount), dataDoSinal);
      if ("error" in saldo) return { error: saldo.error };
      const { data, error } = await admin.rpc("register_deposit_and_convert", {
        p_service_order_id: args.service_order_id,
        p_amount: args.amount,
        p_payment_date: dataDoSinal,
        p_payment_method: formaDePagamento(args.payment_method),
        p_card_fee_percent: args.card_fee_percent || 0,
        p_notes: args.notes || null,
        p_balance_installments: saldo.parcelas.length ? saldo.parcelas : null,
        p_create_collections: true,
      });
      if (error) return { error: error.message };
      return { ok: true, result: data, saldo: descreverSaldo(saldo.parcelas) };
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
      "FECHAMENTO do período pelo EXTRATO: quanto ENTROU e quanto SAIU das contas e do Caixa (a mesma conta da Central de relatórios e do painel inicial), o saldo do período (entrou − saiu; NÃO é o saldo das contas) e as pendências que pedem ação (a receber vencido, contas a pagar vencendo, OS concluídas). Transferência entre contas próprias e crédito do cartão na conta vêm à parte, sem somar. Use para 'como foi hoje?', 'fechamento da semana', 'resumo do mês', 'quanto entrou esse mês' e, com mes/ano, um mês passado inteiro ('quanto entrou em setembro'). Só leitura — não registra nada.",
    input_schema: {
      type: "object",
      properties: {
        period: { type: "string", enum: ["hoje", "ontem", "semana", "mes"], description: "Período do fechamento (padrão: hoje). 'semana' = últimos 7 dias; 'mes' = mês corrente." },
        mes: { type: "number", description: "Um mês inteiro (1 a 12), no lugar de period — ex.: setembro = 9." },
        ano: { type: "number", description: "Ano do mês (padrão: o atual)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;

      // Datas de Brasília: o servidor roda em UTC, e depois das 21h "hoje" já era amanhã.
      const hoje = hojeEmBrasilia();
      let periodo = String(args.period || "hoje");
      let { de, ate } = periodoDoFechamento(periodo, hoje);
      // Um mês inteiro, inclusive passado (02/10/2026: "gasto total de setembro" caía no mês
      // corrente, porque 'mes' só sabia o mês de hoje).
      if (args.mes != null) {
        const mes = Number(args.mes);
        const ano = Number(args.ano ?? hoje.slice(0, 4));
        if (!(mes >= 1 && mes <= 12) || !(ano > 2000)) return { error: "Mês precisa estar entre 1 e 12 (e o ano, completo)." };
        const mm = String(mes).padStart(2, "0");
        de = `${ano}-${mm}-01`;
        ate = `${ano}-${mm}-${new Date(Date.UTC(ano, mes, 0)).getUTCDate()}`;
        if (ate > hoje) ate = hoje;
        if (de > hoje) return { error: "Esse mês ainda não começou." };
        periodo = `${mm}/${ano}`;
      }

      // ENTROU e SAIU: pelo extrato, com a regra da Central de relatórios e do painel inicial
      // (_shared/banking/fluxo-de-caixa.ts). Até 27/09/2026 a entrada vinha das baixas em
      // `payments` e a saída das contas marcadas pagas por updated_at: o assistente dava um
      // terceiro número para "quanto entrou no mês", diferente da tela e do painel.
      let extrato: { linhas: LinhaDoFluxo[]; opcoes: OpcoesDoFluxo };
      try {
        extrato = await lerExtratoDoFluxo(sb, de, ate);
      } catch (e) {
        return { error: `Não consegui ler o extrato: ${mensagemDoBanco(e)}` };
      }
      const fluxo = somarFluxoDoPeriodo(extrato.linhas, de, ate, hoje, extrato.opcoes);

      // Pendências que pedem ação. Leitura que falha vira { erro } no bloco — nunca 0 dito como
      // fato (02/10/2026). Vencido inclui o status 'overdue' (antes só pending/partially_paid).
      const { data: venc, error: vencErr } = await sb
        .from("receivables")
        .select("balance_amount, amount")
        .in("status", ["pending", "overdue", "partially_paid"])
        .eq("is_deposit", false)
        .lt("due_date", hoje);
      const vencidoTotal = ((venc as any[]) || []).reduce((a, r) => a + (Number(r.balance_amount ?? r.amount) || 0), 0);

      // Conta cancelada guarda o saldo antigo: sem tirar paga e cancelada, ela contava como "a pagar".
      const em7 = somarDias(hoje, 7);
      const { data: pag, error: pagErr } = await sb
        .from("payables")
        .select("amount, balance_amount, due_date")
        .lte("due_date", em7)
        .gt("balance_amount", 0)
        .not("status", "in", "(paid,cancelled)");
      const aPagar = ((pag as any[]) || []).reduce((a, p) => a + (Number(p.balance_amount ?? p.amount) || 0), 0);

      const { count: osConcluidas, error: osErr } = await sb
        .from("service_orders")
        .select("id", { count: "exact", head: true })
        .in("status", ["completed", "invoiced"])
        .gte("updated_at", `${de}T00:00:00-03:00`);
      const naoLi = (o: string, e: { message?: string }) => ({ erro: `não consegui ler ${o}: ${mensagemDoBanco(e)}` });

      const r2 = (n: number) => Math.round(n * 100) / 100;
      return {
        periodo,
        de,
        ate,
        fonte: "extrato das contas e do Caixa — o mesmo número da Central de relatórios e do painel inicial",
        entrou: fluxo.entrou,
        saiu: fluxo.saiu,
        saldo: fluxo.liquido,
        qtd_movimentos: fluxo.quantidade,
        a_parte_sem_somar: {
          transferencias_entre_contas_proprias: fluxo.transferencias,
          credito_do_cartao_na_conta: fluxo.creditoDoCartao,
        },
        fora_da_conta: Object.fromEntries(
          (Object.entries(fluxo.deFora) as Array<[DestinoDeFora, { quantidade: number; valor: number }]>)
            .map(([motivo, v]) => [ROTULO_DO_DESTINO[motivo], v]),
        ),
        pendencias: {
          a_receber_vencido: vencErr ? naoLi("o a receber", vencErr) : r2(vencidoTotal),
          a_pagar_proximos_7_dias: pagErr ? naoLi("o a pagar", pagErr) : r2(aPagar),
        },
        os_concluidas_no_periodo: osErr ? naoLi("as OS", osErr) : osConcluidas ?? 0,
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
        .in("status", ["pending", "partially_paid", "overdue"])
        .eq("is_deposit", false)
        .lt("due_date", hojeIso)
        .order("due_date", { ascending: true })
        .limit(200);
      if (error) throw error;

      // Última cobrança enviada por cliente — evita cobrar de novo no mesmo dia. Leitura que
      // falha LANÇA: "nunca cobrado" com erro engolido levaria a cobrar a mesma pessoa duas vezes.
      const clientIds = [...new Set(((recs as any[]) || []).map((r) => r.client_id).filter(Boolean))];
      const ultimaCobranca: Record<string, string> = {};
      if (clientIds.length) {
        const { data: cols, error: erroCobrancas } = await sb
          .from("collections")
          .select("client_id, last_auto_sent_at")
          .in("client_id", clientIds)
          .not("last_auto_sent_at", "is", null);
        if (erroCobrancas) throw new Error(`Não consegui ler as cobranças já enviadas: ${erroCobrancas.message}`);
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
      const { data: cfgPiso, error: erroPiso } = await ctx.admin.from("app_settings").select("value").eq("key", "collection_min_amount").maybeSingle();
      if (erroPiso) throw new Error(`Não consegui ler o piso de cobrança: ${erroPiso.message}`);
      const piso = Number((cfgPiso as { value?: string } | null)?.value) || 0;
      // Cliente com Pix esperando no Extrato pode já ter pago: confere antes de cobrar (o Pix só
      // abate a conta quando alguém o aplica). Sai da lista de cobrança, com o porquê.
      const esperando = await pixEsperandoNoExtrato(ctx, [...new Set(casos.map((c) => c.client_id).filter(Boolean))] as string[]);
      const talvezPago = casos.filter((c) => c.client_id && esperando.has(String(c.client_id)));
      const semPix = casos.filter((c) => !(c.client_id && esperando.has(String(c.client_id))));
      const cobraveis = semPix.filter((c) => c.saldo >= piso).slice(0, limite);
      const abaixoDoPiso = semPix.filter((c) => c.saldo < piso);

      const total = cobraveis.reduce((a, c) => a + c.saldo, 0);
      return {
        count: cobraveis.length,
        total_em_atraso: Math.round(total * 100) / 100,
        ordem_sugerida: "maior valor primeiro (impacto de caixa)",
        casos: cobraveis,
        piso_de_cobranca: piso,
        abaixo_do_piso: abaixoDoPiso.map((c) => ({ cliente: c.cliente, saldo: c.saldo, dias_atraso: c.dias_atraso })),
        talvez_ja_pago: talvezPago.map((c) => ({
          cliente: c.cliente, saldo: c.saldo, dias_atraso: c.dias_atraso,
          pix_esperando_no_extrato: esperando.get(String(c.client_id)) ?? [],
        })),
        nota: `Não cobre quem já foi cobrado hoje nem valores abaixo de R$ ${piso} (só listados). `
          + "Quem está em talvez_ja_pago tem Pix esperando no Extrato: confira se é o pagamento (Extrato › Este Pix paga…) antes de cobrar. "
          + "Enviar cobrança é ação sensível — o sistema pede sua confirmação.",
      };
    },
  },
];
