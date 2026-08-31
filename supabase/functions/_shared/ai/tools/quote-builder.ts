import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolCtx, type ToolDef } from "./registry.ts";
import { applyStockDelta } from "./service-orders.ts";
import { resolverItens } from "../keyword-resolver.ts";
import { recalcularOSComCascata } from "../../receivables/cascata.ts";

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

/**
 * Produto para um item que o catálogo não tinha. Reaproveita se já existir com o mesmo nome —
 * orçar duas vezes a mesma peça não pode encher o catálogo de duplicatas.
 *
 * Nasce PENDENTE de propósito: sem NCM ele não entra em NF-e, e é isso que o `fiscal_complete`
 * marca. O prompt já trata produto pendente como suficiente para orçamento — o que faltava era o
 * cadastro existir, para a linha poder morar em Peças.
 */
async function produtoProvisorio(sb: any, nome: string, precoVenda: number): Promise<{ id: string } | null> {
  // `%` e `_` são curinga no ILIKE: um item chamado "Cabo 2,5% cobre" casaria com qualquer produto
  // do catálogo e o orçamento receberia o item errado. Escapar antes de comparar.
  const nomeEscapado = nome.replace(/([\\%_])/g, "\\$1");
  const { data: existente } = await sb
    .from("products").select("id").ilike("name", nomeEscapado).limit(1).maybeSingle();
  if (existente?.id) return { id: existente.id };

  const { data, error } = await sb
    .from("products")
    .insert({
      name: nome,
      sale_price: precoVenda > 0 ? r2(precoVenda) : 0,
      unit: "UN",
      notes: "Criado automaticamente ao montar um orçamento. Confirmar preço, unidade e NCM.",
    })
    .select("id")
    .single();
  if (error || !data) return null;
  return { id: data.id };
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
        force_new: {
          type: "boolean",
          description: "Só use se o usuário confirmar que quer OUTRO orçamento para o mesmo cliente/ativo hoje. Sem isto, a tool recusa quando já existe um rascunho aberto e diz qual é.",
        },
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

      // 2. TRAVA DE DUPLICATA (NOVO-agente-04/B). Sem isto, nada impedia seis orçamentos idênticos
      // numa tarde — foi exatamente o que aconteceu em 31/08 (ORÇ-00086 a 00091), porque o agente
      // não enxergava o orçamento que ele mesmo tinha acabado de criar e reexecutava o pedido.
      // A janela de histórico já foi corrigida; esta trava é a segunda linha de defesa, e vale
      // mesmo quando o pedido vem de outra sessão ou de outra pessoa.
      if (!args.force_new) {
        // JANELA RELATIVA, não "hoje". A Edge Function roda em UTC: `setHours(0,0,0,0)` daria
        // meia-noite de Londres, e entre 21h e 00h no Brasil a trava deixaria de enxergar o
        // orçamento criado mais cedo no mesmo dia de trabalho. Doze horas cobrem uma jornada
        // inteira e ainda pegam quem vira a noite montando orçamento — que foi o caso real.
        const desde = new Date(Date.now() - 12 * 60 * 60 * 1000);
        const { data: jaExiste } = await sb
          .from("service_orders")
          .select("id, service_order_number, created_at")
          .eq("client_id", cli.id)
          .eq("vessel_id", ativo.id)
          .eq("status", "draft")
          .gte("created_at", desde.toISOString())
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (jaExiste?.id) {
          return {
            ja_existe: jaExiste.service_order_number,
            service_order_id: jaExiste.id,
            error: `Já existe um orçamento em rascunho recente para ${cli.nome} / ${ativo.nome}: ${jaExiste.service_order_number}.`,
            instruction:
              "NÃO crie outro. Para ajustar o que já existe use as ferramentas de item " +
              "(add_service_order_item / edit_service_order_item / remove_service_order_item) sobre este service_order_id. " +
              "Só chame de novo com force_new=true se o usuário confirmar que quer um orçamento SEPARADO.",
          };
        }
      }

      // 3. Resolve os itens contra o catálogo (paralelo).
      const itens = Array.isArray(args.items) ? args.items : [];
      if (itens.length === 0) return { error: "Informe ao menos um item em items." };
      const resolvidos = await resolverItens(sb, itens, cli.id);

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

      // 5. Provisórios (sem cadastro) → PRODUTO PENDENTE + service_order_parts.
      //
      // Antes iam para `service_order_services`, junto da mão de obra, porque
      // `service_order_parts.product_id` é NOT NULL e uma linha sem produto não tinha onde caber.
      // O resultado (NOVO-agente-05) era cabo, terminal e disjuntor aparecendo na lista de
      // Serviços do orçamento: no ORÇ-00086, 13 das 18 linhas de "serviço" eram material físico,
      // e em agosto isso já era 80% das linhas de serviço criadas.
      //
      // Tudo que entra por `items` é peça POR DEFINIÇÃO do schema ("Peças/equipamentos como
      // palavras-chave") — mão de obra vem por `labor`. Então o item sem cadastro não precisa de
      // um lugar improvisado: precisa de cadastro. Ele vira produto PENDENTE (sem NCM, o que o
      // prompt já declara suficiente para orçar) e a linha vai para Peças, onde ela pertence.
      const provisorios = resolvidos.filter((i) => !i.product_id);
      const criados: Array<{ item: string; product_id: string; preco: number; quantidade: number }> = [];
      // Guarda o item inteiro, não só o nome: dois itens do mesmo pedido podem ter o mesmo nome, e
      // procurar de volta por nome devolveria a quantidade do outro.
      const naoCadastrados: Array<{ nome: string; quantidade: number; preco: number }> = [];
      for (const p of provisorios) {
        const nome = String(p.keyword || "").trim();
        const naoDeu = { nome: nome || "(sem nome)", quantidade: p.quantidade, preco: p.preco_venda };
        if (nome.length < 2) { naoCadastrados.push(naoDeu); continue; }
        const criado = await produtoProvisorio(sb, nome, p.preco_venda);
        if (!criado) { naoCadastrados.push(naoDeu); continue; }
        criados.push({ item: nome, product_id: criado.id, preco: p.preco_venda, quantidade: p.quantidade });
        // SEM baixa de estoque, ao contrário das peças resolvidas: este produto acabou de nascer
        // com estoque zero e não foi comprado. Dar baixa aqui criaria saldo negativo — a mesma
        // classe do estoque fantasma que já custou uma investigação neste sistema.
        await sb.from("service_order_parts").insert({
          service_order_id: so.id,
          product_id: criado.id,
          quantity: p.quantidade,
          unit_cost_snapshot: 0,
          unit_sale_snapshot: p.preco_venda,
          currency_snapshot: "BRL",
          line_total_cost: 0,
          line_total_sale: r2(p.preco_venda * p.quantidade),
          notes: "Cadastrado pelo orçamento — confirmar preço e completar cadastro fiscal.",
        });
      }

      const labor = Array.isArray(args.labor) ? args.labor : [];
      const svcRows: any[] = [];
      // Sobra para Serviços só o que não deu para cadastrar (nome vazio/inutilizável) — e mesmo
      // assim marcado, para não sumir do orçamento.
      for (const n of naoCadastrados) {
        svcRows.push({
          service_order_id: so.id, service_id: null,
          name_snapshot: `${n.nome} — Valor provisório (aguardando cotação)`,
          billing_unit_snapshot: "unit", quantity: n.quantidade,
          unit_price_snapshot: n.preco, line_total: r2(n.preco * n.quantidade),
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
      // Os provisórios agora entram como PEÇA, então precisam somar aqui — sem isto o imposto e a
      // comissão sairiam sobre uma base menor que o orçamento.
      const subtotalPecas = comProduto.reduce((a, i) => a + i.preco_venda * i.quantidade, 0)
        + criados.reduce((a, c) => a + c.preco * c.quantidade, 0);
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
      try { await recalcularOSComCascata(sb, so.id); } catch { /* best-effort */ }
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
        // `pedido` ao lado de `item` é o que permite ver a TROCA (NOVO-agente-07): o retorno só
        // trazia o nome do catálogo, então "pedi cabo, veio suporte" era invisível para o modelo
        // e para quem lia a narração.
        itens_no_catalogo: comProduto.map((i) => ({
          pedido: i.keyword, item: i.nome, qtd: i.quantidade, preco: i.preco_venda, origem: i.origem,
          confirmar: i.status === "assumido" ? `casamento PARCIAL — confira se "${i.nome}" é mesmo "${i.keyword}"` : null,
        })),
        cadastrados_agora: criados.map((c) => ({ item: c.item, qtd: c.quantidade, preco: c.preco || null })),
        provisorios: naoCadastrados.map((n) => ({ item: n.nome, qtd: n.quantidade, lista: "SERVIÇOS (não deu para cadastrar)" })),
        mao_de_obra: labor.length,
        avisos: [
          criados.length
            ? `${criados.length} item(ns) não existiam no catálogo: foram CADASTRADOS como produto pendente e entraram na lista de PEÇAS. Confirme preço e complete o NCM depois.`
            : null,
          criados.some((c) => !c.preco)
            ? "Alguns dos itens cadastrados ficaram SEM PREÇO (R$ 0,00) — informe o valor antes de enviar ao cliente."
            : null,
          naoCadastrados.length
            ? `${naoCadastrados.length} item(ns) não puderam ser cadastrados e ficaram como texto na lista de SERVIÇOS: ${naoCadastrados.map((n) => n.nome).join(", ")}.`
            : null,
          comProduto.some((i) => i.status === "assumido") ? "Alguns itens foram ASSUMIDOS entre parecidos — confira os marcados." : null,
        ].filter(Boolean),
      };
    },
  },
];
