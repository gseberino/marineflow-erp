import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { adicionarPecaNaOS } from "./service-orders.ts";
import { produtoFiscalPendencias } from "../product-fiscal.ts";

// Produto composto / kit (BOM). O custo do pai é mantido por trigger (Σ custo dos componentes).
export const bomTools: ToolDef[] = [
  {
    name: "create_composed_product",
    description:
      "Cria um PRODUTO COMPOSTO ou KIT a partir de OUTROS produtos do catálogo (BOM). O custo do pai é calculado como Σ (quantidade × custo de cada componente) — roll-up automático. Use product_type='composto' para algo que você PRODUZ a partir de peças; 'kit' para uma venda agrupada. Os componentes já precisam existir no catálogo — se não existirem, crie-os antes com create_product (podem ficar pendentes).",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string" },
        product_type: { type: "string", enum: ["composto", "kit"], description: "composto=produzido a partir de peças; kit=venda agrupada. Padrão: composto." },
        components: {
          type: "array",
          description: "Componentes do produto: cada um com product_id (do catálogo) e quantity.",
          items: {
            type: "object",
            properties: { product_id: { type: "string" }, quantity: { type: "number" } },
            required: ["product_id", "quantity"],
          },
        },
        sale_price: { type: "number", description: "Preço de venda do composto. Se omitir e passar profit_margin, calculo pelo custo roll-up." },
        profit_margin: { type: "number", description: "Margem em % sobre o custo (usada só se não informar sale_price)." },
        sku: { type: "string" },
        unit: { type: "string" },
        brand: { type: "string" },
        ncm: { type: "string", description: "NCM do composto (para NF-e)." },
      },
      required: ["name", "components"],
    },
    risk: "low",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb } = ctx;

      const comps: Array<{ product_id: string; quantity: number }> = (Array.isArray(args.components) ? args.components : [])
        .map((c: any) => ({ product_id: String(c?.product_id || ""), quantity: Number(c?.quantity) || 1 }))
        .filter((c: { product_id: string }) => c.product_id);
      if (comps.length === 0) return { error: "Informe ao menos um componente (product_id + quantity)." };
      const tipo = args.product_type === "kit" ? "kit" : "composto";

      // Valida que os componentes existem no catálogo.
      const ids = [...new Set(comps.map((c) => c.product_id))];
      const { data: existentes } = await sb.from("products").select("id, name, cost_price").in("id", ids);
      const mapa = new Map(((existentes as any[]) || []).map((p) => [p.id, p]));
      const faltam = ids.filter((id) => !mapa.has(id));
      if (faltam.length) {
        return { error: `Componente(s) não encontrado(s) no catálogo: ${faltam.join(", ")}. Cadastre com create_product primeiro (pode ser pendente).` };
      }

      // Cria o produto pai.
      const insertProd: Record<string, unknown> = { name: args.name, product_type: tipo };
      if (args.sku != null) insertProd.sku = args.sku;
      if (args.unit != null) insertProd.unit = args.unit;
      if (args.brand != null) insertProd.brand = args.brand;
      if (args.ncm != null) insertProd.ncm = args.ncm;
      const { data: parent, error: pErr } = await sb.from("products").insert(insertProd).select().single();
      if (pErr) throw pErr;

      // Insere os componentes — o trigger recalcula o custo do pai.
      const rows = comps.map((c) => ({ parent_product_id: parent.id, component_product_id: c.product_id, quantity: c.quantity }));
      const { error: cErr } = await sb.from("product_components").insert(rows);
      if (cErr) {
        await sb.from("products").delete().eq("id", parent.id); // desfaz o pai órfão
        throw cErr;
      }

      // Relê para pegar o custo roll-up já aplicado pelo trigger.
      const { data: atualizado } = await sb
        .from("products")
        .select("id, name, sku, cost_price, sale_price, product_type, ncm, cfop, csosn, fiscal_origin, use_global_fiscal, fiscal_complete")
        .eq("id", parent.id)
        .maybeSingle();
      const custo = Number(atualizado?.cost_price) || 0;

      // Preço de venda: explícito, ou por margem sobre o custo roll-up.
      let venda: number | null = args.sale_price != null ? Number(args.sale_price) : null;
      if (venda == null && args.profit_margin != null) venda = custo * (1 + Number(args.profit_margin) / 100);
      if (venda != null) await sb.from("products").update({ sale_price: venda }).eq("id", parent.id);

      const pend = produtoFiscalPendencias(atualizado || {});
      return {
        ok: true,
        product: { ...(atualizado || {}), sale_price: venda ?? (atualizado?.sale_price ?? null) },
        tipo,
        custo_rollup: custo,
        componentes: rows.map((r) => ({
          product_id: r.component_product_id,
          nome: mapa.get(r.component_product_id)?.name || null,
          quantidade: r.quantity,
          custo_unit: Number(mapa.get(r.component_product_id)?.cost_price) || 0,
        })),
        pendente_fiscal: !atualizado?.fiscal_complete,
        pendencias_fiscais: pend,
        aviso_nf: tipo === "kit"
          ? "Kit: no orçamento entra como 1 linha. Na NF-e, kits costumam EXPLODIR nos componentes (cada um com seu NCM) — a explosão automática ainda não está ativa; por ora, emita com o NCM do próprio kit ou lance os componentes manualmente."
          : "Composto: produzido a partir dos componentes; o custo acompanha o custo das peças.",
      };
    },
  },
  {
    name: "add_kit_to_order",
    description:
      "Adiciona um KIT ou produto COMPOSTO a uma OS/orçamento como UMA linha (usando o preço praticado a este cliente → global → catálogo, salvo se passar unit_price). O produto precisa existir (crie com create_composed_product).",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string" },
        product_id: { type: "string", description: "UUID do kit/composto." },
        quantity: { type: "number" },
        unit_price: { type: "number", description: "Opcional: sobrepõe o preço sugerido." },
      },
      required: ["service_order_id", "product_id", "quantity"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: prod } = await sb.from("products").select("product_type, name").eq("id", args.product_id).maybeSingle();
      if (!prod) return { error: "Produto não encontrado." };
      const r = await adicionarPecaNaOS(sb, {
        service_order_id: args.service_order_id,
        product_id: args.product_id,
        quantity: args.quantity,
        unit_price: args.unit_price,
      });
      if ("error" in r) return r;
      const ehComposto = prod.product_type === "kit" || prod.product_type === "composto";
      return {
        ...r,
        tipo: prod.product_type,
        aviso: ehComposto ? null : "Atenção: este produto NÃO é kit/composto — foi adicionado como peça normal.",
        aviso_nf: prod.product_type === "kit" ? "Na NF-e este kit deve explodir nos componentes (explosão automática ainda não ativa)." : null,
      };
    },
  },
  {
    name: "get_product_components",
    description: "Mostra a COMPOSIÇÃO (BOM) de um produto composto/kit: componentes, quantidades, custo de cada e o custo roll-up do pai.",
    input_schema: {
      type: "object",
      properties: { product_id: { type: "string" } },
      required: ["product_id"],
    },
    risk: "low",
    async execute(args, { sb }) {
      const { data: parent } = await sb.from("products").select("id, name, product_type, cost_price, sale_price").eq("id", args.product_id).maybeSingle();
      if (!parent) return { error: "Produto não encontrado." };
      const { data: comps } = await sb.from("product_components").select("quantity, component_product_id").eq("parent_product_id", args.product_id);
      const linhas = (comps as any[]) || [];
      const ids = linhas.map((c) => c.component_product_id);
      const { data: prods } = ids.length ? await sb.from("products").select("id, name, cost_price").in("id", ids) : { data: [] };
      const mapa = new Map(((prods as any[]) || []).map((p) => [p.id, p]));
      const lista = linhas.map((c) => {
        const p = mapa.get(c.component_product_id);
        const q = Number(c.quantity) || 0;
        const custoUnit = Number(p?.cost_price) || 0;
        return { product_id: c.component_product_id, nome: p?.name || null, quantidade: q, custo_unit: custoUnit, subtotal_custo: q * custoUnit };
      });
      return {
        produto: { id: parent.id, nome: parent.name, tipo: parent.product_type, custo_rollup: Number(parent.cost_price) || 0, preco_venda: Number(parent.sale_price) || 0 },
        componentes: lista,
        total_componentes: lista.length,
      };
    },
  },
];
