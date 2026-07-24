import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { normalizarTermo } from "../keyword-resolver.ts";
import { produtoFiscalPendencias } from "../product-fiscal.ts";

export const productTools: ToolDef[] = [
  {
    name: "search_products",
    description: "Busca produtos/equipamentos no catálogo.",
    input_schema: {
      type: "object",
      properties: { query: { type: "string" }, limit: { type: "number" } },
      required: ["query"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("products")
        .select("id, name, sku, brand, sale_price, stock_quantity, unit")
        .eq("active", true)
        .or(`name.ilike.%${q}%,sku.ilike.%${q}%,brand.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "search_products_batch",
    description:
      "Busca VÁRIOS produtos de uma vez e devolve as melhores opções de cada um. Use SEMPRE que precisar levantar preços de uma lista de itens (montar orçamento, cotação, comparar): uma chamada resolve a lista inteira, em vez de dezenas de buscas. Devolve, por termo, até 3 candidatos com id, nome e preço — e marca os termos SEM resultado, que você deve tratar como 'valor provisório' em vez de travar o trabalho.",
    input_schema: {
      type: "object",
      properties: {
        queries: {
          type: "array",
          items: { type: "string" },
          description: "Termos a buscar (ex.: ['MultiPlus-II 12/3000','Orion 12/12','MPPT 100/50','SmartShunt']). Máximo 25.",
        },
        per_query: { type: "number", description: "Candidatos por termo (padrão 3, teto 5)." },
      },
      required: ["queries"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const termos = (Array.isArray(args.queries) ? args.queries : [])
        .map((q: unknown) => String(q || "").trim())
        .filter(Boolean)
        .slice(0, 25);
      if (termos.length === 0) return { error: "Informe ao menos um termo em queries." };
      const porTermo = Math.min(Number(args.per_query) || 3, 5);

      const achados: Array<Record<string, unknown>> = [];
      const semResultado: string[] = [];
      // Em paralelo: 25 buscas curtas custam menos que 25 turnos de conversa.
      await Promise.all(
        termos.map(async (q: string) => {
          const { data } = await sb
            .from("products")
            .select("id, name, sku, brand, sale_price, cost_price, unit")
            .eq("active", true)
            .or(`name.ilike.%${q}%,sku.ilike.%${q}%,brand.ilike.%${q}%`)
            .limit(porTermo);
          const opcoes = ((data as any[]) || []).map((p) => ({
            product_id: p.id,
            nome: p.name,
            sku: p.sku || null,
            marca: p.brand || null,
            preco_venda: p.sale_price != null ? Number(p.sale_price) : null,
            custo: p.cost_price != null ? Number(p.cost_price) : null,
            unidade: p.unit || null,
          }));
          if (opcoes.length === 0) semResultado.push(q);
          else achados.push({ termo: q, encontrados: opcoes.length, opcoes });
        }),
      );

      return {
        resultados: achados,
        sem_resultado: semResultado,
        instrucao:
          "Escolha o candidato mais adequado por termo e DIGA qual escolheu (nome e preço). Para os termos em 'sem_resultado', não trave: marque como 'Valor provisório — aguardando cotação do fornecedor' e siga.",
      };
    },
  },
  {
    name: "learn_product_alias",
    description:
      "Ensina que uma PALAVRA-CHAVE se refere a um produto específico do catálogo. Use quando o usuário CORRIGE um match ('não, MultiPlus-II é o 12/3000/120') ou confirma um item que você tinha ASSUMIDO. Na próxima vez que esse termo aparecer (em orçamento/cotação), o sistema acerta de primeira — o agente fica mais certeiro a cada correção, sem retreinar nada.",
    input_schema: {
      type: "object",
      properties: {
        alias: { type: "string", description: "O termo/apelido como o usuário costuma dizer (ex.: 'MultiPlus-II 12/3000')." },
        product_id: { type: "string", description: "UUID do produto correto (de search_products)." },
      },
      required: ["alias", "product_id"],
    },
    risk: "low",
    async execute(args, { sb, userId }) {
      const alias = String(args.alias || "").trim();
      if (alias.length < 2) return { error: "Apelido curto demais." };
      const { data: prod } = await sb.from("products").select("id, name").eq("id", args.product_id).maybeSingle();
      if (!prod) return { error: "Produto não encontrado." };

      const norm = normalizarTermo(alias);
      // upsert por alias_normalized (um apelido -> um produto; corrigir reaponta).
      const { error } = await sb
        .from("product_aliases")
        .upsert({ alias_normalized: norm, alias_original: alias, product_id: prod.id, created_by: userId ?? null }, { onConflict: "alias_normalized" });
      if (error) throw error;
      return { ok: true, aprendido: `"${alias}" → ${prod.name}`, efeito: "Da próxima vez que esse termo aparecer, eu já uso esse produto direto." };
    },
  },
  {
    name: "get_product_price_history",
    description:
      "HISTÓRICO DE PREÇO de um produto: quanto já foi COBRADO dele em orçamentos/OS anteriores (com data, número da OS e cliente), qual o custo praticado, a última compra por fornecedor e o preço atual do catálogo. Use SEMPRE que precisar dizer a ORIGEM e a DATA de um valor — por exemplo, ao montar orçamento com base no que já foi praticado. Se não houver histórico, diga que o preço vem do catálogo atual.",
    input_schema: {
      type: "object",
      properties: {
        product_id: { type: "string", description: "UUID do produto." },
        limit: { type: "number", description: "Quantos usos anteriores trazer (padrão 5, teto 15)." },
      },
      required: ["product_id"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const limite = Math.min(Number(args.limit) || 5, 15);

      const { data: prod } = await sb
        .from("products")
        .select("id, name, sku, sale_price, cost_price, product_category_id")
        .eq("id", args.product_id)
        .maybeSingle();
      if (!prod) return { error: "Produto não encontrado." };

      // Preço REALMENTE praticado: cada linha de peça guarda o snapshot do momento.
      const { data: usos } = await sb
        .from("service_order_parts")
        .select("quantity, unit_cost_snapshot, unit_sale_snapshot, created_at, service_orders(service_order_number, status, created_at, clients(name))")
        .eq("product_id", prod.id)
        .order("created_at", { ascending: false })
        .limit(limite);

      const historico = ((usos as any[]) || []).map((u) => {
        const so = Array.isArray(u.service_orders) ? u.service_orders[0] : u.service_orders;
        const cli = so?.clients ? (Array.isArray(so.clients) ? so.clients[0] : so.clients) : null;
        return {
          origem: so?.service_order_number ? `OS/Orçamento ${so.service_order_number}` : "registro anterior",
          data: so?.created_at || u.created_at,
          cliente: cli?.name || null,
          quantidade: Number(u.quantity) || 0,
          custo_unitario: u.unit_cost_snapshot != null ? Number(u.unit_cost_snapshot) : null,
          preco_vendido: u.unit_sale_snapshot != null ? Number(u.unit_sale_snapshot) : null,
        };
      });

      // Última compra por fornecedor (custo de entrada).
      const { data: forn } = await sb
        .from("product_suppliers")
        .select("last_purchase_price, last_purchase_date, cost_price, is_preferred, suppliers(name)")
        .eq("product_id", prod.id)
        .order("last_purchase_date", { ascending: false })
        .limit(3);

      // Margem padrão da CATEGORIA (varia por categoria — não presuma um valor fixo).
      let margemCategoria: number | null = null;
      if (prod.product_category_id) {
        const { data: cat } = await sb
          .from("product_categories")
          .select("name, default_profit_margin")
          .eq("id", prod.product_category_id)
          .maybeSingle();
        margemCategoria = cat?.default_profit_margin != null ? Number(cat.default_profit_margin) : null;
      }

      return {
        produto: { id: prod.id, nome: prod.name, sku: prod.sku || null },
        catalogo_atual: {
          preco_venda: prod.sale_price != null ? Number(prod.sale_price) : null,
          custo: prod.cost_price != null ? Number(prod.cost_price) : null,
        },
        margem_padrao_da_categoria_pct: margemCategoria,
        ja_praticado: historico,
        compras_de_fornecedor: ((forn as any[]) || []).map((f) => ({
          fornecedor: f.suppliers?.name || null,
          preferencial: !!f.is_preferred,
          ultimo_preco_compra: f.last_purchase_price != null ? Number(f.last_purchase_price) : null,
          data_ultima_compra: f.last_purchase_date || null,
        })),
        instrucao: historico.length > 0
          ? "Ao citar o valor, informe a ORIGEM e a DATA (ex.: 'R$ X — praticado na OS-00042 em 12/05/2026')."
          : "Sem histórico de uso: informe que o valor vem do CADASTRO ATUAL do catálogo.",
      };
    },
  },
  {
    name: "search_services",
    description: "Busca serviços de mão de obra no catálogo por nome ou descrição.",
    input_schema: {
      type: "object",
      properties: { query: { type: "string" }, limit: { type: "number" } },
      required: ["query"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const q = String(args.query || "").trim();
      const limit = Math.min(Number(args.limit) || 10, 25);
      const { data, error } = await sb
        .from("services")
        .select("id, name, description, billing_unit, default_price")
        .eq("active", true)
        .or(`name.ilike.%${q}%,description.ilike.%${q}%`)
        .limit(limit);
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "adjust_inventory",
    description: "Realiza um ajuste manual no estoque de um produto.",
    input_schema: {
      type: "object",
      properties: {
        product_id: { type: "string" },
        new_quantity: { type: "number" },
        reason: { type: "string" },
      },
      required: ["product_id", "new_quantity", "reason"],
    },
    risk: "low",
    async execute(args, { admin }) {
      const { product_id, new_quantity, reason } = args;
      const { data: prod } = await admin.from("products").select("stock_quantity").eq("id", product_id).single();
      const delta = new_quantity - (prod?.stock_quantity || 0);

      const { error: updateErr } = await admin.from("products").update({ stock_quantity: new_quantity }).eq("id", product_id);
      if (updateErr) throw updateErr;

      await admin.from("inventory_movements").insert({
        product_id,
        quantity_delta: delta,
        movement_type: "manual_adjustment",
        notes: reason,
      });

      return { ok: true, new_quantity };
    },
  },
  {
    name: "create_product",
    description:
      "Cadastra um novo produto/equipamento. Grave TUDO que o usuário informar — principalmente marca, unidade e NCM: sem NCM o produto não pode entrar em nota fiscal depois. A resposta avisa se ficou faltando algo para faturamento.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        sku: { type: "string" },
        brand: { type: "string", description: "Marca/fabricante (ex.: Victron, Usina)." },
        category: { type: "string" },
        unit: { type: "string", description: "Unidade (UN, PC, M...)." },
        sale_price: { type: "number", description: "Preço de venda." },
        cost_price: { type: "number", description: "Custo de compra." },
        minimum_stock: { type: "number" },
        barcode: { type: "string" },
        notes: { type: "string" },
        ncm: { type: "string", description: "NCM — necessário para emitir NF-e com este produto." },
        cfop: { type: "string" },
        csosn: { type: "string" },
        fiscal_origin: { type: "number", description: "Origem fiscal (0=nacional...)." },
        profit_margin: { type: "number", description: "Margem em %." },
        supplier_id: { type: "string", description: "Fornecedor principal, se conhecido." },
      },
      required: ["name"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data, error } = await sb.from("products").insert(args).select().single();
      if (error) throw error;
      // fiscal_complete é calculado por trigger no banco — reflete a realidade fiscal do registro.
      // As pendências abaixo dizem exatamente o que falta para o produto poder entrar numa NF-e.
      const pendenciasFiscais = produtoFiscalPendencias(data);
      const faltando = [...pendenciasFiscais];
      if (data.sale_price == null || Number(data.sale_price) === 0) faltando.push("preço de venda");
      return {
        ok: true,
        product: data,
        pendente: !data.fiscal_complete,
        pronto_para_nota_fiscal: !!data.fiscal_complete,
        pendencias_fiscais: pendenciasFiscais,
        aviso: pendenciasFiscais.length
          ? `Produto cadastrado como PENDENTE — já pode ir ao orçamento, mas falta para NF-e: ${pendenciasFiscais.join(", ")}. Sugira/pergunte o NCM e complete depois.`
          : (faltando.length ? `Cadastrado. Falta ${faltando.join(" e ")}.` : null),
      };
    },
  },
  {
    name: "list_pending_fiscal_products",
    description:
      "Lista os produtos com CADASTRO FISCAL PENDENTE (não podem entrar em NF-e ainda: falta NCM, CFOP, etc.). Use ANTES de tentar emitir nota — para completar tudo de uma vez — ou quando o usuário perguntar o que falta para faturar. Passe service_order_id para checar só os itens daquele orçamento/OS; sem ele, lista o catálogo. Devolve, por produto, exatamente o que falta.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "Opcional: UUID do orçamento/OS — lista só os produtos usados nele que estão pendentes." },
        limit: { type: "number", description: "Máximo de produtos (padrão 30, teto 100)." },
      },
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;
      const limite = Math.min(Number(args.limit) || 30, 100);
      const campos = "id, name, sku, ncm, cfop, csosn, fiscal_origin, use_global_fiscal, fiscal_complete";

      let produtos: any[] = [];
      if (args.service_order_id) {
        // Só os produtos que aparecem como PEÇA neste orçamento/OS.
        const { data: parts, error } = await sb
          .from("service_order_parts")
          .select(`product_id, products(${campos})`)
          .eq("service_order_id", args.service_order_id);
        if (error) throw error;
        const vistos = new Set<string>();
        for (const p of (parts as any[]) || []) {
          const prod = Array.isArray(p.products) ? p.products[0] : p.products;
          if (prod && !vistos.has(prod.id)) { vistos.add(prod.id); produtos.push(prod); }
        }
        produtos = produtos.filter((p) => !p.fiscal_complete);
      } else {
        const { data, error } = await sb
          .from("products")
          .select(campos)
          .eq("active", true)
          .eq("fiscal_complete", false)
          .order("name")
          .limit(limite);
        if (error) throw error;
        produtos = (data as any[]) || [];
      }

      const lista = produtos.slice(0, limite).map((p) => ({
        product_id: p.id,
        nome: p.name,
        sku: p.sku || null,
        falta: produtoFiscalPendencias(p),
      }));
      return {
        total_pendentes: lista.length,
        escopo: args.service_order_id ? "orçamento/OS" : "catálogo",
        produtos: lista,
        instrucao: lista.length
          ? "Para cada produto, complete o que está em 'falta' (use update_product; sugira um NCM plausível pelo tipo do produto e CONFIRME com o usuário antes de gravar)."
          : "Nenhum produto pendente neste escopo — pode seguir para a emissão.",
      };
    },
  },
  {
    name: "list_low_stock",
    description: "Lista produtos com estoque abaixo do mínimo cadastrado.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    async execute(_args, { admin }) {
      const { data, error } = await admin
        .from("products")
        .select("id, name, stock_quantity, minimum_stock, unit")
        .gt("minimum_stock", 0)
        .filter("stock_quantity", "lte", "minimum_stock")
        .order("name");
      if (error) throw error;
      return { results: data };
    },
  },
  {
    name: "register_stock_entry",
    description: "Registra entrada de estoque (compra/reposição) de um produto, somando à quantidade atual.",
    input_schema: {
      type: "object",
      properties: {
        product_id: { type: "string" },
        quantity: { type: "number" },
        unit_cost: { type: "number" },
        notes: { type: "string" },
      },
      required: ["product_id", "quantity"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data: product, error: pErr } = await admin.from("products").select("stock_quantity").eq("id", args.product_id).single();
      if (pErr) return { error: `Produto não encontrado: ${pErr.message}` };
      const newQty = (product?.stock_quantity ?? 0) + args.quantity;
      const { error: uErr } = await admin.from("products").update({ stock_quantity: newQty }).eq("id", args.product_id);
      if (uErr) return { error: `Erro ao atualizar estoque: ${uErr.message}` };
      const { error: mErr } = await admin.from("inventory_movements").insert({
        product_id: args.product_id,
        movement_type: "purchase",
        quantity_delta: args.quantity,
        unit_cost_snapshot: args.unit_cost ?? null,
        reference_type: "manual_entry",
        notes: args.notes || null,
      });
      if (mErr) return { error: `Erro ao registrar movimento: ${mErr.message}` };
      return { ok: true, new_quantity: newQty };
    },
  },
  {
    name: "create_service",
    description: "Cadastra um novo serviço de mão de obra no catálogo.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        description: { type: "string" },
        billing_unit: { type: "string", enum: ["hour", "visit", "day", "unit"] },
        default_price: { type: "number" },
      },
      required: ["name", "billing_unit"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { admin } = ctx;
      const { data, error } = await admin.from("services").insert(args).select().single();
      if (error) throw error;
      return { ok: true, service: data };
    },
  },
];
