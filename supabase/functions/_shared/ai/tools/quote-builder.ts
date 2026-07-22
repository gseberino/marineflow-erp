import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolCtx, type ToolDef } from "./registry.ts";
import { applyStockDelta } from "./service-orders.ts";
import { resolverItens } from "../keyword-resolver.ts";

// MACRO — cria um orçamento INTEIRO numa única chamada (LLM orquestra, código executa).
// Ver plans/marineflow-llm-orquestra-codigo-executa.md
//
// Em vez de o LLM fazer ~30 idas (buscar produto, criar OS, add item, buscar o próximo...),
// ele manda UMA intenção compacta com palavras-chave e o servidor faz tudo: resolve os itens
// contra o catálogo (com preço praticado), cria a OS, adiciona peças/serviços, aplica
// imposto/comissão, recalcula e devolve um resumo curto. Corta custo, latência e o timeout.

const r2 = (n: number) => Math.round(n * 100) / 100;

/** Resolve o cliente por id ou nome. Cliente é crítico — se ambíguo, devolve opções e para. */
async function resolverCliente(sb: any, clientId?: string, clientName?: string) {
  if (clientId) {
    const { data } = await sb.from("clients").select("id, name").eq("id", clientId).maybeSingle();
    return data ? { ok: true as const, id: data.id, nome: data.name } : { ok: false as const, erro: "Cliente (client_id) não encontrado." };
  }
  const q = String(clientName || "").trim();
  if (q.length < 2) return { ok: false as const, erro: "Informe client_id ou client_name." };
  const { data } = await sb.from("clients").select("id, name, whatsapp, phone").ilike("name", `%${q}%`).eq("active", true).limit(6);
  const lista = (data as any[]) || [];
  if (lista.length === 0) return { ok: false as const, erro: `Nenhum cliente "${q}". Cadastre com create_client (com endereço, para poder faturar depois).` };
  if (lista.length > 1) {
    return { ok: false as const, ambiguo: true, opcoes: lista.map((c) => ({ client_id: c.id, nome: c.name, contato: c.whatsapp || c.phone || null })), erro: `Há ${lista.length} clientes com "${q}" — confirme qual (passe client_id).` };
  }
  return { ok: true as const, id: lista[0].id, nome: lista[0].name };
}

/** Resolve o ativo por id ou nome (dentro do cliente). */
async function resolverAtivo(sb: any, clientId: string, vesselId?: string, vesselName?: string) {
  if (vesselId) {
    const { data } = await sb.from("vessels").select("id, name").eq("id", vesselId).maybeSingle();
    return data ? { ok: true as const, id: data.id, nome: data.name } : { ok: false as const, erro: "Ativo (vessel_id) não encontrado." };
  }
  const q = String(vesselName || "").trim();
  if (q.length < 2) return { ok: false as const, erro: "Informe vessel_id ou vessel_name (crie com create_vessel se for novo)." };
  const { data } = await sb.from("vessels").select("id, name").eq("client_id", clientId).ilike("name", `%${q}%`).eq("active", true).limit(6);
  const lista = (data as any[]) || [];
  if (lista.length === 0) return { ok: false as const, erro: `Nenhum ativo "${q}" para esse cliente. Crie com create_vessel e chame de novo.` };
  if (lista.length > 1) return { ok: false as const, ambiguo: true, opcoes: lista.map((v) => ({ vessel_id: v.id, nome: v.name })), erro: `Há ${lista.length} ativos com "${q}" — confirme qual.` };
  return { ok: true as const, id: lista[0].id, nome: lista[0].name };
}

export const quoteBuilderTools: ToolDef[] = [
  {
    name: "create_quote_from_items",
    description:
      "MONTA UM ORÇAMENTO COMPLETO numa única chamada — use SEMPRE que o pedido tiver uma lista de itens (é MUITO mais rápido e barato que criar item por item). Você passa cliente, ativo, título, os itens como PALAVRAS-CHAVE (o sistema acha no catálogo e usa o preço já praticado), a mão de obra, e imposto/comissão. O servidor resolve tudo, cria a OS, aplica os valores e devolve um resumo com o que casou (origem e data), o que ASSUMIU (confirmar) e o que ficou PROVISÓRIO. Para vários orçamentos separados, chame uma vez por orçamento.",
    input_schema: {
      type: "object",
      properties: {
        client_id: { type: "string", description: "UUID do cliente (ou use client_name)." },
        client_name: { type: "string", description: "Nome do cliente, se não tiver o id." },
        vessel_id: { type: "string", description: "UUID do ativo (ou use vessel_name)." },
        vessel_name: { type: "string", description: "Nome do ativo. Se for novo, crie antes com create_vessel." },
        title: { type: "string", description: "Título/escopo do orçamento (ex.: 'Sistema elétrico Victron - LiFePO4')." },
        items: {
          type: "array",
          description: "Peças/equipamentos como palavras-chave. O sistema casa no catálogo.",
          items: {
            type: "object",
            properties: {
              keyword: { type: "string", description: "Termo do item (ex.: 'MultiPlus-II 12/3000', 'MPPT 100/50')." },
              quantity: { type: "number", description: "Quantidade (padrão 1)." },
              unit_price: { type: "number", description: "Preço unitário, se você quiser fixar (senão usa o praticado/catálogo, ou fica provisório)." },
            },
            required: ["keyword"],
          },
        },
        labor: {
          type: "array",
          description: "Mão de obra / serviços (texto livre).",
          items: {
            type: "object",
            properties: {
              description: { type: "string" },
              price: { type: "number", description: "Valor (total da linha, ou unitário se informar quantity)." },
              quantity: { type: "number" },
            },
            required: ["description", "price"],
          },
        },
        tax_percent: { type: "number", description: "Imposto em % sobre o subtotal (ex.: 6)." },
        commission_rate: { type: "number", description: "Comissão em % (ex.: 3)." },
        discount_amount: { type: "number", description: "Desconto em R$." },
        payment_conditions: { type: "string" },
        quote_validity_days: { type: "number" },
      },
      required: ["title", "items"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx: ToolCtx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, userId } = ctx;

      // 1. Cliente e ativo (param crítico — para se ambíguo).
      const cli = await resolverCliente(sb, args.client_id, args.client_name);
      if (!cli.ok) return cli.ambiguo ? { needs_choice: true, o_que: "cliente", opcoes: cli.opcoes, message: cli.erro } : { error: cli.erro };
      const ativo = await resolverAtivo(sb, cli.id, args.vessel_id, args.vessel_name);
      if (!ativo.ok) return ativo.ambiguo ? { needs_choice: true, o_que: "ativo", opcoes: ativo.opcoes, message: ativo.erro } : { error: ativo.erro };

      // 2. Resolve os itens contra o catálogo (paralelo).
      const itens = Array.isArray(args.items) ? args.items : [];
      if (itens.length === 0) return { error: "Informe ao menos um item em items." };
      const resolvidos = await resolverItens(sb, itens);

      // 3. Cria a OS (orçamento).
      let num: string;
      try {
        const { data: seqVal, error } = await admin.rpc("next_document_number");
        if (error || seqVal == null) throw new Error();
        num = `ORÇ-${String(seqVal as number).padStart(5, "0")}`;
      } catch {
        num = `ORÇ-${Date.now().toString().slice(-5)}`;
      }
      const { data: so, error: soErr } = await sb
        .from("service_orders")
        .insert({
          client_id: cli.id,
          vessel_id: ativo.id,
          status: "draft",
          problem_description: String(args.title || "Orçamento"),
          payment_conditions: args.payment_conditions ?? null,
          quote_validity_days: args.quote_validity_days ?? 30,
          discount_amount: args.discount_amount != null ? r2(Number(args.discount_amount)) : 0,
          service_order_number: num,
          created_by: userId ?? null,
        })
        .select("id, service_order_number")
        .single();
      if (soErr) throw soErr;

      // 4. Peças resolvidas → service_order_parts (+ baixa de estoque, como o resto do sistema).
      const comProduto = resolvidos.filter((i) => i.product_id);
      if (comProduto.length) {
        const partsRows = comProduto.map((i) => ({
          service_order_id: so.id,
          product_id: i.product_id!,
          quantity: i.quantidade,
          unit_cost_snapshot: i.custo,
          unit_sale_snapshot: i.preco_venda,
          currency_snapshot: "BRL",
          line_total_cost: r2(i.custo * i.quantidade),
          line_total_sale: r2(i.preco_venda * i.quantidade),
        }));
        await sb.from("service_order_parts").insert(partsRows);
        for (const row of partsRows) await applyStockDelta(sb, row.product_id, -Number(row.quantity), so.id, row.unit_cost_snapshot);
      }

      // 5. Provisórios (sem cadastro) + mão de obra → service_order_services (linhas de texto).
      const provisorios = resolvidos.filter((i) => !i.product_id);
      const labor = Array.isArray(args.labor) ? args.labor : [];
      const svcRows: any[] = [];
      for (const p of provisorios) {
        svcRows.push({
          service_order_id: so.id, service_id: null,
          name_snapshot: `${p.keyword} — Valor provisório (aguardando cotação)`,
          billing_unit_snapshot: "unit", quantity: p.quantidade,
          unit_price_snapshot: p.preco_venda, line_total: r2(p.preco_venda * p.quantidade),
        });
      }
      for (const l of labor) {
        const q = Number(l.quantity) || 1;
        const preco = Number(l.price) || 0;
        svcRows.push({
          service_order_id: so.id, service_id: null,
          name_snapshot: String(l.description || "Mão de obra"),
          billing_unit_snapshot: "unit", quantity: q,
          unit_price_snapshot: preco, line_total: r2(preco * q),
        });
      }
      if (svcRows.length) await sb.from("service_order_services").insert(svcRows);

      // 6. Imposto e comissão (subtotal = peças + serviços já inseridos).
      const subtotalPecas = comProduto.reduce((a, i) => a + i.preco_venda * i.quantidade, 0);
      const subtotalSvc = svcRows.reduce((a, s) => a + Number(s.line_total), 0);
      const subtotal = subtotalPecas + subtotalSvc;
      const desconto = args.discount_amount != null ? Number(args.discount_amount) : 0;
      const base = subtotal - desconto;
      const encargos: Record<string, unknown> = {};
      const patch: Record<string, unknown> = {};
      if (args.tax_percent != null) { patch.tax_amount = r2(base * (Number(args.tax_percent) / 100)); encargos.imposto = patch.tax_amount; }
      if (args.commission_rate != null) {
        patch.commission_rate = Number(args.commission_rate);
        patch.commission_amount = r2(base * (Number(args.commission_rate) / 100));
        encargos.comissao_pct = Number(args.commission_rate);
        encargos.comissao_valor = patch.commission_amount;
      }
      if (Object.keys(patch).length) await sb.from("service_orders").update(patch).eq("id", so.id);

      // 7. Recalcula o total oficial e lê a margem.
      try { await sb.rpc("recalc_so_totals", { so_id: so.id }); } catch { /* best-effort */ }
      const { data: soFinal } = await sb.from("service_orders").select("grand_total").eq("id", so.id).maybeSingle();
      const custoPecas = comProduto.reduce((a, i) => a + i.custo * i.quantidade, 0);
      const grand = Number(soFinal?.grand_total) || 0;
      const margem = grand > 0 ? r2(((grand - custoPecas) / grand) * 100) : null;

      // 8. Resumo COMPACTO (o LLM narra isso, não repete tabela).
      return {
        ok: true,
        orcamento: so.service_order_number,
        service_order_id: so.id,
        cliente: cli.nome,
        ativo: ativo.nome,
        total: grand,
        margem_bruta_pct: margem,
        encargos: Object.keys(encargos).length ? encargos : null,
        itens_no_catalogo: comProduto.map((i) => ({
          item: i.nome, qtd: i.quantidade, preco: i.preco_venda, origem: i.origem,
          confirmar: i.status === "assumido" ? `assumi entre ${i.candidatos} parecidos` : null,
        })),
        provisorios: provisorios.map((i) => ({ item: i.keyword, qtd: i.quantidade, preco: i.preco_venda || null })),
        mao_de_obra: labor.length,
        avisos: [
          provisorios.length ? `${provisorios.length} item(ns) sem cadastro entraram como PROVISÓRIO — cote e ajuste.` : null,
          comProduto.some((i) => i.status === "assumido") ? "Alguns itens foram ASSUMIDOS entre parecidos — confira os marcados." : null,
        ].filter(Boolean),
      };
    },
  },
];
