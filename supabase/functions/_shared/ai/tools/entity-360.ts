import type { ToolCtx, ToolDef } from "./registry.ts";
import { chaveTelefone } from "../phone.ts";

// Ficha 360 — visão unificada por entidade (Fase 3 · Etapa 1).
// Ver plans/marineflow-contexto-unificado-escopo.md
//
// PRINCÍPIO: montagem em tempo de LEITURA. Nada aqui copia ou guarda dado — o banco continua
// dono da verdade. Cada seção tem teto próprio para não estourar o contexto do modelo.

const TETO = 5; // itens por seção — retrato, não extrato

function r2(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Técnico não vê dinheiro (mesma regra do resto do sistema). */
function podeVerFinanceiro(ctx: ToolCtx): boolean {
  return ctx.userRole !== "technician";
}

/** Prévia amigável de mídia já convertida (🎤/📄/📷) ou ainda crua. */
function previa(body: string | null | undefined): string {
  const b = String(body || "").trim();
  if (b === "[audio]") return "🎤 áudio (não lido)";
  if (b === "[image]") return "📷 imagem (não lida)";
  if (b === "[document]") return "📎 arquivo (não lido)";
  return b.slice(0, 90);
}

export const entity360Tools: ToolDef[] = [
  {
    name: "get_client_360",
    description:
      "RETRATO COMPLETO de um cliente numa única consulta: dados, ativos e seus equipamentos, orçamentos e OS (abertos e últimos), situação financeira, últimas mensagens de WhatsApp e notas fiscais. Use quando pedirem 'me resume o João', 'o que temos com esse cliente', 'como está a conta dele' — em vez de disparar várias buscas. Responda com a SÍNTESE antes do detalhe. Técnico não recebe as seções de dinheiro.",
    input_schema: {
      type: "object",
      properties: { client_id: { type: "string", description: "UUID do cliente (use search_clients para achar)." } },
      required: ["client_id"],
    },
    risk: "low",
    async execute(args, ctx) {
      const { sb } = ctx;
      const financeiroOk = podeVerFinanceiro(ctx);

      const { data: cli } = await sb
        .from("clients")
        .select("id, name, type, cpf_cnpj, phone, whatsapp, email, city, state, notes, active, created_at")
        .eq("id", args.client_id)
        .maybeSingle();
      if (!cli) return { error: "Cliente não encontrado." };

      // Ativos + equipamentos (o "o quê" para sugerir serviço).
      const { data: ativos } = await sb
        .from("vessels")
        .select("id, name, manufacturer, model, year, asset_type, engine_brand, engine_model, battery_bank_summary, inverter_charger_summary, navigation_electronics_summary")
        .eq("client_id", cli.id)
        .eq("active", true)
        .limit(TETO);

      // Orçamentos abertos e OS recentes — o que está em jogo agora.
      const { data: oss } = await sb
        .from("service_orders")
        .select("id, service_order_number, status, quote_status, grand_total, created_at, updated_at, scheduled_start_at")
        .eq("client_id", cli.id)
        .order("created_at", { ascending: false })
        .limit(20);
      const todas = (oss as any[]) || [];
      const orcamentosAbertos = todas
        .filter((o) => o.status === "draft" && ["sent", "awaiting_approval", "awaiting_deposit"].includes(o.quote_status || ""))
        .slice(0, TETO)
        .map((o) => ({ numero: o.service_order_number, etapa: o.quote_status, valor: r2(Number(o.grand_total) || 0), criado_em: o.created_at }));
      const osEmAndamento = todas
        .filter((o) => ["open", "in_progress", "scheduled", "approved", "awaiting_parts"].includes(o.status))
        .slice(0, TETO)
        .map((o) => ({ numero: o.service_order_number, status: o.status, valor: r2(Number(o.grand_total) || 0), agendado_para: o.scheduled_start_at }));
      const ultimasConcluidas = todas
        .filter((o) => ["completed", "invoiced"].includes(o.status))
        .slice(0, TETO)
        .map((o) => ({ numero: o.service_order_number, status: o.status, valor: r2(Number(o.grand_total) || 0), quando: o.updated_at }));

      // Financeiro (omitido para técnico).
      let financeiro: Record<string, unknown> | null = null;
      if (financeiroOk) {
        const hoje = new Date().toISOString().slice(0, 10);
        const { data: recs } = await sb
          .from("receivables")
          .select("amount, balance_amount, due_date, status")
          .eq("client_id", cli.id)
          .in("status", ["pending", "partially_paid"]);
        let aberto = 0, vencido = 0;
        for (const r of (recs as any[]) || []) {
          const v = Number(r.balance_amount ?? r.amount) || 0;
          aberto += v;
          if (r.due_date && r.due_date < hoje) vencido += v;
        }
        financeiro = { em_aberto: r2(aberto), vencido: r2(vencido), titulos_em_aberto: ((recs as any[]) || []).length };
      }

      // Conversa recente — o que ele falou por último.
      const chave = chaveTelefone(cli.whatsapp || cli.phone);
      let mensagens: unknown[] = [];
      if (chave) {
        const { data: msgs } = await sb
          .from("whatsapp_messages")
          .select("direction, body, created_at")
          .like("phone_normalized", `%${chave}`)
          .order("created_at", { ascending: false })
          .limit(TETO);
        mensagens = ((msgs as any[]) || []).map((m) => ({
          quem: m.direction === "inbound" ? "cliente" : "nós",
          quando: m.created_at,
          texto: previa(m.body),
        }));
      }

      // Notas fiscais (só leitura, e só para quem vê financeiro).
      let notas: unknown[] = [];
      if (financeiroOk) {
        const { data: nfs } = await sb
          .from("issued_fiscal_documents")
          .select("document_type, series, number, status, created_at")
          .eq("client_id", cli.id)
          .order("created_at", { ascending: false })
          .limit(3);
        notas = ((nfs as any[]) || []).map((n) => ({
          tipo: n.document_type, numero: n.number ? `${n.series ?? ""}/${n.number}` : null, status: n.status, quando: n.created_at,
        }));
      }

      // Memória da entidade (Etapa 3) — só notas verificadas.
      const { data: notasMem } = await sb
        .from("ai_operator_memory_notes")
        .select("title, body, topic")
        .eq("client_id", cli.id)
        .eq("verification_status", "verified")
        .limit(TETO);

      return {
        cliente: {
          id: cli.id, nome: cli.name, tipo: cli.type, documento: cli.cpf_cnpj,
          contato: cli.whatsapp || cli.phone || cli.email || null,
          cidade: [cli.city, cli.state].filter(Boolean).join("/") || null,
          ativo: cli.active, cliente_desde: cli.created_at, observacoes: cli.notes || null,
        },
        ativos: ((ativos as any[]) || []).map((v) => ({
          vessel_id: v.id, nome: v.name,
          modelo: [v.manufacturer, v.model, v.year].filter(Boolean).join(" ") || null,
          tipo: v.asset_type || null,
          equipamentos: [
            v.engine_brand || v.engine_model ? `Motor: ${[v.engine_brand, v.engine_model].filter(Boolean).join(" ")}` : null,
            v.battery_bank_summary ? `Baterias: ${String(v.battery_bank_summary).slice(0, 70)}` : null,
            v.inverter_charger_summary ? `Inversor: ${String(v.inverter_charger_summary).slice(0, 70)}` : null,
            v.navigation_electronics_summary ? `Eletrônica: ${String(v.navigation_electronics_summary).slice(0, 70)}` : null,
          ].filter(Boolean),
        })),
        orcamentos_abertos: orcamentosAbertos,
        os_em_andamento: osEmAndamento,
        ultimos_servicos: ultimasConcluidas,
        financeiro: financeiro ?? "(oculto para o seu cargo)",
        conversa_recente: mensagens,
        notas_fiscais: financeiroOk ? notas : "(oculto para o seu cargo)",
        memoria: ((notasMem as any[]) || []).map((n) => ({ titulo: n.title, nota: n.body, assunto: n.topic })),
      };
    },
  },
  {
    name: "get_supplier_360",
    description:
      "RETRATO COMPLETO de um fornecedor numa única consulta: dados, produtos que ele fornece, ordens de compra recentes, participação nas cotações (respondidas/escolhidas), contas a pagar e últimas mensagens. Use para 'o que temos com esse fornecedor', 'ele é bom de preço?', antes de decidir uma compra.",
    input_schema: {
      type: "object",
      properties: { supplier_id: { type: "string", description: "UUID do fornecedor (use suggest_suppliers ou busque pelo nome)." } },
      required: ["supplier_id"],
    },
    risk: "low",
    roles: ["admin", "financial", "seller", "external_seller"],
    async execute(args, ctx) {
      const { sb } = ctx;
      const { data: sup } = await sb
        .from("suppliers")
        .select("id, name, trade_name, cnpj_cpf, contact_name, phone, email, city, state, payment_terms, active, notes")
        .eq("id", args.supplier_id)
        .maybeSingle();
      if (!sup) return { error: "Fornecedor não encontrado." };

      // O que ele fornece (com preço da última compra).
      const { data: prods } = await sb
        .from("product_suppliers")
        .select("cost_price, last_purchase_price, last_purchase_date, lead_time_days, is_preferred, products(name)")
        .eq("supplier_id", sup.id)
        .limit(TETO);

      const { data: ocs } = await sb
        .from("purchase_orders")
        .select("po_number, status, total_amount, expected_date, created_at")
        .eq("supplier_id", sup.id)
        .order("created_at", { ascending: false })
        .limit(TETO);

      // Desempenho em cotação: respondeu quantas, ganhou quantas.
      const { data: resps } = await sb
        .from("quote_responses")
        .select("unit_price, lead_time_days, confirmed, created_at")
        .eq("supplier_id", sup.id)
        .limit(200);
      const totalResp = ((resps as any[]) || []).length;
      const ganhas = ((resps as any[]) || []).filter((r) => r.confirmed).length;

      const { data: contas } = await sb
        .from("payables")
        .select("description, amount, balance_amount, due_date, status")
        .eq("supplier_id", sup.id)
        .gt("balance_amount", 0)
        .order("due_date", { ascending: true })
        .limit(TETO);

      const chave = chaveTelefone(sup.phone);
      let mensagens: unknown[] = [];
      if (chave) {
        const { data: msgs } = await sb
          .from("whatsapp_messages")
          .select("direction, body, created_at")
          .like("phone_normalized", `%${chave}`)
          .order("created_at", { ascending: false })
          .limit(TETO);
        mensagens = ((msgs as any[]) || []).map((m) => ({
          quem: m.direction === "inbound" ? "fornecedor" : "nós",
          quando: m.created_at,
          texto: previa(m.body),
        }));
      }

      const { data: notasMem } = await sb
        .from("ai_operator_memory_notes")
        .select("title, body, topic")
        .eq("supplier_id", sup.id)
        .eq("verification_status", "verified")
        .limit(TETO);

      return {
        fornecedor: {
          id: sup.id, nome: sup.name, nome_fantasia: sup.trade_name, documento: sup.cnpj_cpf,
          contato: sup.contact_name || null, telefone: sup.phone || null, email: sup.email || null,
          cidade: [sup.city, sup.state].filter(Boolean).join("/") || null,
          condicao_pagamento: sup.payment_terms || null, ativo: sup.active, observacoes: sup.notes || null,
          tem_whatsapp: !!sup.phone,
        },
        fornece: ((prods as any[]) || []).map((p) => ({
          produto: p.products?.name || "—",
          preferencial: !!p.is_preferred,
          custo: p.cost_price != null ? r2(Number(p.cost_price)) : null,
          ultima_compra: p.last_purchase_date || null,
          ultimo_preco: p.last_purchase_price != null ? r2(Number(p.last_purchase_price)) : null,
          prazo_dias: p.lead_time_days ?? null,
        })),
        ordens_de_compra: ((ocs as any[]) || []).map((o) => ({
          numero: o.po_number, status: o.status, total: r2(Number(o.total_amount) || 0),
          previsao: o.expected_date, criada_em: o.created_at,
        })),
        desempenho_em_cotacao: {
          respostas_registradas: totalResp,
          vezes_escolhido: ganhas,
          aproveitamento_pct: totalResp > 0 ? Math.round((ganhas / totalResp) * 100) : null,
        },
        contas_a_pagar_em_aberto: ((contas as any[]) || []).map((c) => ({
          descricao: c.description, saldo: r2(Number(c.balance_amount ?? c.amount) || 0), vencimento: c.due_date, status: c.status,
        })),
        conversa_recente: mensagens,
        memoria: ((notasMem as any[]) || []).map((n) => ({ titulo: n.title, nota: n.body })),
      };
    },
  },
];
