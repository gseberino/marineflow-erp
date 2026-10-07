import { blockTechnician, NON_TECHNICIAN_ROLES, type Role, type ToolDef } from "./registry.ts";
import { buscarCadastro } from "../busca-cadastro.ts";
import { CARGOS_DE_COMPRAS, criarOC, itensDitos } from "./compras-base.ts";
import { resolverRecebimento } from "./compras-ciclo.ts";

// O número da OC (mesmo esquema não-atômico de useCreatePOFromOS, "OC-00001") mora em
// compras-base.ts desde 07/10/2026, junto de criarOC, que as três tools de criar OC usam.
// Continua saindo daqui para quem já importava.
export { generatePONumber } from "./compras-base.ts";

/** Compras é do admin e do financeiro (policies de purchase_orders); revalida no execute. */
function cargoDeCompras(ctx: { userRole: string }) {
  return CARGOS_DE_COMPRAS.includes(ctx.userRole as Role) ? null : { error: "Ordem de compra é do administrador e do financeiro." };
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
    risk: "low",
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx) ?? cargoDeCompras(ctx);
      if (blocked) return blocked;
      const { sb, admin, userId } = ctx;
      // Até 07/10/2026 esta tool inseria SEM po_number (NOT NULL, sem default: falhava sempre) e
      // ignorava o erro dos itens (OC vazia dita "criada"). Agora é o caminho da tela: número
      // gerado, itens conferidos, e OC desfeita se os itens não entram (criarOC).
      const lidos = itensDitos(args.items);
      if ("erro" in lidos) return { error: lidos.erro };
      const criada = await criarOC(sb, admin, {
        supplier_id: args.supplier_id,
        service_order_id: args.service_order_id ?? null,
        expected_date: args.expected_date ?? null,
        notes: args.notes ?? null,
        status: "draft",
        created_by: userId,
      }, lidos.itens);
      if ("erro" in criada) return { error: criada.erro };
      return { ok: true, purchase_order: criada.po, ordem_de_compra: criada.po.po_number };
    },
  },
  {
    name: "get_purchase_needs",
    description:
      "O que FALTA COMPRAR para executar uma ordem de serviço. Devolve a necessidade LÍQUIDA por item: " +
      "falta = necessário − disponível (físico menos reservado) − o que já está em ordem de compra aberta. " +
      "Use ANTES de criar cotação ou ordem de compra para uma OS — é isto que diz o que cotar, em vez de " +
      "supor pela lista de peças. Cada item vem com status: 'missing' (nada disponível), 'partial' (parte " +
      "em estoque), 'on_order' (já pedido, só esperar), 'uncatalogued' (material sem cadastro) e 'ok' " +
      "(estoque cobre). Mão de obra digitada à mão NÃO entra: não se compra instalação de fornecedor de peça.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID da OS." },
      },
      required: ["service_order_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, { sb }) {
      // Delega ao banco de propósito: a mesma conta existe na tela (TypeScript) e
      // aqui. Reimplementá-la em Deno criaria uma terceira versão para divergir —
      // a RPC é a fonte única, com paridade provada contra os testes da lib.
      const { data, error } = await sb.rpc("get_os_purchase_needs", {
        p_so_id: args.service_order_id,
      });
      if (error) throw error;

      const r = (data ?? {}) as any;
      const faltando = (r.shortages ?? []) as any[];
      return {
        precisa_comprar: !!r.needsPurchase,
        itens_em_falta: faltando.length,
        custo_estimado: r.estimatedCost ?? 0,
        // Só o que falta, que é o que interessa para cotar. A lista completa fica
        // em `todos_os_itens` para quando a pergunta for sobre o que já tem.
        faltando: faltando.map((i) => ({
          descricao: i.description,
          quantidade_faltando: i.shortage,
          necessario: i.required,
          disponivel: i.available,
          ja_pedido: i.onOrder,
          situacao: i.status,
          product_id: i.productId,
          custo_unitario_conhecido: i.unitCost,
        })),
        todos_os_itens: (r.items ?? []).length,
      };
    },
  },
  {
    name: "list_pending_pos",
    description: "Lista ordens de compra ainda não totalmente recebidas (rascunho, enviada ou parcialmente recebida).",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    // Compras traz custo e fornecedor — mesma regra das demais tools deste arquivo.
    roles: NON_TECHNICIAN_ROLES,
    async execute(_args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
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
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const cargo = cargoDeCompras(ctx);
      if (cargo) return cargo;
      const { admin } = ctx;
      // Mesmo caminho de useCreatePOFromOS; desde 07/10/2026 por criarOC: item que não entra
      // desfaz a OC (antes ficava uma OC vazia de pé e a OS ia para "Aguardando peças" à toa).
      const lidos = itensDitos([{ product_id: args.product_id, descricao: args.product_name, quantidade: args.quantity, custo_unitario: args.unit_cost }]);
      if ("erro" in lidos) return { error: lidos.erro };
      const criada = await criarOC(admin, admin, {
        service_order_id: args.service_order_id,
        supplier_id: args.supplier_id ?? null,
        expected_date: args.expected_date ?? null,
        notes: args.notes ?? null,
        status: "draft",
      }, lidos.itens);
      if ("erro" in criada) return { error: criada.erro };
      const po = criada.po;

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
    description:
      "Registra o que CHEGOU de uma ordem de compra (tudo ou só parte) — a mesma rotina do 'Receber itens' da tela: dá entrada no estoque e, quando a OC fica completa, gera a conta a pagar. Ache a OC pelo número (ordem_de_compra: OC-00012 ou 12), pelo fornecedor ou pela OS. Diga os itens que chegaram em itens [{n (o número do item em get_purchase_order) ou descricao, quantidade}] — ex.: 'chegou incompleta, recebe só 2 das 4 baterias' = itens [{descricao:'bateria', quantidade:2}]; ou receber_tudo=true para tudo o que falta. Não recebe mais do que falta, nem OC cancelada.",
    input_schema: {
      type: "object",
      properties: {
        ordem_de_compra: { type: "string", description: "Número da OC (OC-00012, 12) ou o id." },
        fornecedor: { type: "string", description: "Nome do fornecedor, para achar a OC em aberto dele ('a OC da Victron')." },
        os: { type: "string", description: "OS/orçamento de origem, para achar a OC dela." },
        itens: {
          type: "array",
          description: "O que chegou: cada item pelo número na lista (n) ou pela descrição, com a quantidade que chegou AGORA.",
          items: {
            type: "object",
            properties: {
              n: { type: "number", description: "Número do item na OC (1, 2, 3…), como get_purchase_order mostra." },
              descricao: { type: "string", description: "Descrição do item, se não souber o número." },
              quantidade: { type: "number", description: "Quantidade que chegou agora." },
            },
            required: ["quantidade"],
          },
        },
        receber_tudo: { type: "boolean", description: "true = chegou tudo o que faltava." },
        po_id: { type: "string", description: "(antigo) id da OC — prefira ordem_de_compra." },
        items: {
          type: "array",
          description: "(antigo) [{po_item_id, received_qty}] — prefira itens.",
          items: {
            type: "object",
            properties: { po_item_id: { type: "string" }, received_qty: { type: "number" } },
            required: ["po_item_id", "received_qty"],
          },
        },
        due_days: { type: "number", description: "Prazo em dias para a conta a pagar gerada. Padrão: 30." },
      },
    },
    risk: "high",
    // Admin e financeiro, como as policies de purchase_orders (07/10/2026: pelo WhatsApp o
    // assistente grava sem RLS, e o vendedor recebia OC por aqui).
    roles: CARGOS_DE_COMPRAS,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx) ?? cargoDeCompras(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      // Tudo conferido ANTES da rotina do banco (07/10/2026): receive_po não confere se o item é
      // da OC, nem a situação dela, e grava o movimento de estoque com a quantidade PEDIDA mesmo
      // quando corta o recebido no que faltava — receber 5 de um item que só faltavam 2 punha 5
      // no estoque. Item de texto livre (sem produto) derruba a rotina inteira (o movimento de
      // estoque exige produto): sai recusado aqui, com o motivo.
      const pedido = await resolverRecebimento(admin, args);
      if ("erro" in pedido) return { error: pedido.erro, ...(pedido.opcoes ? { opcoes: pedido.opcoes } : {}) };
      const { oc, linhas } = pedido;
      const { data, error } = await admin.rpc("receive_po", {
        p_po_id: oc.id,
        p_items: linhas.map((l) => ({ po_item_id: l.item.id, received_qty: l.quantidade })),
        p_due_days: Number(args.due_days) > 0 ? Number(args.due_days) : 30,
      });
      if (error) return { error: `O recebimento não foi registrado: ${error.message}` };
      const r = (data ?? {}) as { status?: string; payable_id?: string | null; all_received?: boolean };
      return {
        ok: true,
        ordem_de_compra: oc.po_number,
        recebido: linhas.map((l) => ({ item: `${l.n}. ${l.item.description}`, chegou: l.quantidade, faltava: l.faltava, falta_agora: l.faltava - l.quantidade })),
        situacao: r.all_received ? "recebida (completa)" : "recebida em parte",
        conta_a_pagar: r.payable_id
          ? "gerada (veja em Contas a pagar)"
          : r.all_received
          ? (oc.supplier_id ? "já existia" : "não gerada: a OC não tem fornecedor")
          : "ainda não: a conta a pagar nasce quando a OC fica completa (é a mesma regra da tela)",
        estoque: "entrada registrada pelo movimento de compra",
      };
    },
  },
  {
    name: "search_suppliers",
    description:
      "Busca FORNECEDORES por nome, nome fantasia, contato ou cidade (sem precisar de acento), CNPJ/CPF ou telefone (com ou sem pontos/traço/DDD). Use para achar o supplier_id quando o produto NÃO está no catálogo (aí suggest_suppliers não serve), para pesquisar se um fornecedor já é cadastrado, ou antes de disparar cotação. NÃO busca por marca de produto (fornecedor não tem marca no cadastro). Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Nome, nome fantasia, contato, CNPJ/CPF, telefone ou cidade." },
        limit: { type: "number", description: "Máximo de resultados (padrão 10, teto 25)." },
      },
      required: ["query"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const q = String(args.query || "").trim();
      if (q.length < 2) return { error: "Termo de busca muito curto. Diga o nome (ou parte) do fornecedor." };
      const limit = Math.min(Number(args.limit) || 10, 25);

      // Sem acento e por dígitos (busca-cadastro.ts, 07/10/2026): o ILIKE não achava o CNPJ gravado
      // "12.063.636/0001-61" por "12063636000161", e a descrição prometia "marca", que fornecedor
      // não tem. Leitura que falha lança — não vira "nenhum fornecedor, cadastre".
      const data = await buscarCadastro(
        sb,
        "suppliers",
        "id, name, trade_name, display_name, cnpj_cpf, contact_name, phone, email, city, state, payment_terms, active",
        q,
        { texto: ["name", "trade_name", "display_name", "contact_name", "city"], documento: ["cnpj_cpf"], telefone: ["phone"] },
        { limite: limit },
      );

      const results = ((data as any[]) || []).map((s) => ({
        supplier_id: s.id,
        nome: s.name,
        nome_fantasia: s.trade_name || null,
        documento: s.cnpj_cpf || null,
        contato: s.contact_name || null,
        telefone: s.phone || null,
        tem_whatsapp: !!s.phone,
        cidade: [s.city, s.state].filter(Boolean).join("/") || null,
        condicao_pagamento: s.payment_terms || null,
        ativo: s.active !== false,
      }));
      return {
        count: results.length,
        results,
        nota: results.length === 0 ? `Nenhum fornecedor encontrado para "${q}". Se for um fornecedor novo, use create_supplier.` : null,
      };
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
    risk: "low",
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
  {
    name: "suggest_suppliers",
    description:
      "Sugere fornecedores para um produto do catálogo, rankeados por preferência e histórico (tabela product_suppliers). SÓ LEITURA — não abre OC nem envia nada. Use para 'quem vende o inversor Victron?', 'de quem eu compro essa bateria?'.",
    input_schema: {
      type: "object",
      properties: {
        product_id: { type: "string", description: "UUID do produto (use search_products para achar)." },
      },
      required: ["product_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const { data: prod } = await sb.from("products").select("name").eq("id", args.product_id).maybeSingle();
      if (!prod) return { error: "Produto não encontrado. Use search_products primeiro." };
      const { data: rels, error } = await sb
        .from("product_suppliers")
        .select("supplier_id, cost_price, currency, lead_time_days, is_preferred, last_purchase_date, last_purchase_price, minimum_order_qty, suppliers(name, contact_name, phone, active)")
        .eq("product_id", args.product_id);
      if (error) throw error;
      const ativos = (rels || []).filter((r: any) => r.suppliers && r.suppliers.active !== false);
      if (ativos.length === 0) {
        return {
          produto: prod.name,
          count: 0,
          message: "Nenhum fornecedor vinculado a este produto. Cadastre e vincule (create_supplier), ou escolha manualmente ao abrir a OC.",
          results: [],
        };
      }
      ativos.sort((a: any, b: any) => {
        if (!!b.is_preferred !== !!a.is_preferred) return Number(!!b.is_preferred) - Number(!!a.is_preferred);
        const da = a.last_purchase_date ? new Date(a.last_purchase_date).getTime() : 0;
        const db = b.last_purchase_date ? new Date(b.last_purchase_date).getTime() : 0;
        return db - da;
      });
      const results = ativos.map((r: any) => ({
        supplier_id: r.supplier_id,
        fornecedor: r.suppliers?.name || "—",
        contato: r.suppliers?.phone || r.suppliers?.contact_name || null,
        preferencial: !!r.is_preferred,
        custo: r.cost_price != null ? Number(r.cost_price) : (r.last_purchase_price != null ? Number(r.last_purchase_price) : null),
        moeda: r.currency || "BRL",
        prazo_dias: r.lead_time_days ?? null,
        qtd_minima: r.minimum_order_qty ?? null,
        ultima_compra: r.last_purchase_date || null,
        motivo: r.is_preferred ? "preferencial" : (r.last_purchase_date ? "comprado antes" : "vinculado"),
      }));
      return { produto: prod.name, count: results.length, results };
    },
  },
];
