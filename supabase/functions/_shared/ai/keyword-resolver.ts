// Resolvedor por PALAVRA-CHAVE — o "a IA só comanda, o código executa".
//
// O LLM passa termos ("MultiPlus-II 12/3000", "Orion 12/12"); este código casa cada termo
// contra o catálogo de forma DETERMINÍSTICA e traz o preço já praticado (com origem e data).
// Nunca interrompe por item: resolve tudo e REPORTA o que assumiu / o que ficou provisório,
// para o dono corrigir depois. É a base das macro-tools (uma ida ao LLM em vez de dezenas).

export type ItemResolvido = {
  keyword: string;
  quantidade: number;
  status: "resolvido" | "assumido" | "provisorio";
  product_id?: string;
  nome?: string;
  preco_venda: number;
  custo: number;
  origem: string;
  candidatos?: number;
  /** preço informado pelo LLM (override/estimativa), quando houver. */
  preco_informado?: number;
};

/** Quebra em tokens alfanuméricos (ignora hífen, barra, pontuação). "MultiPlus-II 12/3000" -> [multiplus, ii, 12, 3000]. */
function tokenizar(s: string): string[] {
  return s.toLowerCase().split(/[^a-z0-9]+/i).filter((t) => t.length >= 2);
}

/**
 * Token ÂNCORA = a palavra distintiva para a BUSCA (marca/modelo). Buscar pela frase inteira
 * falha quando a formatação do cadastro difere ("MultiPlus-II 12/3000" vs "MultiPlus 12/3000/120").
 * Então buscamos pela âncora (o maior token alfabético) e depois pontuamos os candidatos pela
 * sobreposição COMPLETA de tokens — incluindo números de spec (3000, 100, 50).
 */
function tokenAncora(termo: string): string | null {
  const tokens = tokenizar(termo);
  const alfabeticos = tokens.filter((t) => /[a-z]/.test(t) && t.length >= 3);
  if (alfabeticos.length) return alfabeticos.sort((a, b) => b.length - a.length)[0];
  return tokens.sort((a, b) => b.length - a.length)[0] ?? null;
}

/** Pontua o candidato: nº de tokens do termo presentes no nome/sku; desempate por nome mais curto. */
function pontua(termo: string, nome: string, sku: string | null): number {
  const tokens = tokenizar(termo);
  const alvo = `${nome} ${sku || ""}`.toLowerCase();
  let achou = 0;
  for (const t of tokens) if (alvo.includes(t)) achou++;
  return achou * 1000 - nome.length;
}

function origemDoHistorico(row: any): string {
  const so = Array.isArray(row?.service_orders) ? row.service_orders[0] : row?.service_orders;
  const quando = so?.created_at || row?.created_at;
  const data = quando ? new Date(quando).toLocaleDateString("pt-BR") : null;
  if (so?.service_order_number && data) return `praticado na ${so.service_order_number} em ${data}`;
  if (data) return `praticado em ${data}`;
  return "praticado antes";
}

/**
 * Resolve uma lista de itens (palavra-chave + quantidade + preço opcional).
 * Roda tudo em paralelo — 20 itens = 20 buscas curtas simultâneas, uma única execução.
 */
export async function resolverItens(
  sb: any,
  itens: Array<{ keyword: string; quantity?: number; unit_price?: number }>,
): Promise<ItemResolvido[]> {
  return await Promise.all(
    itens.map(async (it): Promise<ItemResolvido> => {
      const termo = String(it.keyword || "").trim();
      const qtd = Number(it.quantity) || 1;
      const precoInformado = it.unit_price != null ? Number(it.unit_price) : undefined;

      if (termo.length < 2) {
        return { keyword: termo, quantidade: qtd, status: "provisorio", preco_venda: precoInformado ?? 0, custo: 0, origem: "termo vazio", preco_informado: precoInformado };
      }

      // Busca pela ÂNCORA (palavra distintiva), não pela frase — senão spec/formatação derruba o match.
      const ancora = tokenAncora(termo);
      if (!ancora) {
        return { keyword: termo, quantidade: qtd, status: "provisorio", preco_venda: precoInformado ?? 0, custo: 0, origem: "termo sem palavra utilizável", preco_informado: precoInformado };
      }
      const { data: cands } = await sb
        .from("products")
        .select("id, name, sku, brand, sale_price, cost_price")
        .eq("active", true)
        .or(`name.ilike.%${ancora}%,sku.ilike.%${ancora}%,brand.ilike.%${ancora}%`)
        .limit(20);

      const lista = (cands as any[]) || [];
      if (lista.length === 0) {
        // Sem cadastro → provisório. Usa o preço informado pelo LLM, se houver.
        return { keyword: termo, quantidade: qtd, status: "provisorio", preco_venda: precoInformado ?? 0, custo: 0, origem: "não encontrado no catálogo — aguardando cotação", preco_informado: precoInformado };
      }

      // Melhor candidato pela sobreposição COMPLETA de tokens (spec incluída).
      lista.sort((a, b) => pontua(termo, b.name, b.sku) - pontua(termo, a.name, a.sku));
      const p = lista[0];

      // Último preço PRATICADO deste produto (fonte da verdade de "valor já usado").
      const { data: hist } = await sb
        .from("service_order_parts")
        .select("unit_sale_snapshot, created_at, service_orders(service_order_number, created_at)")
        .eq("product_id", p.id)
        .not("unit_sale_snapshot", "is", null)
        .order("created_at", { ascending: false })
        .limit(1);
      const h = ((hist as any[]) || [])[0];

      const precoPraticado = h?.unit_sale_snapshot != null ? Number(h.unit_sale_snapshot) : null;
      const precoVenda = precoInformado ?? precoPraticado ?? (p.sale_price != null ? Number(p.sale_price) : 0);
      const origem = precoInformado != null
        ? "preço informado no pedido"
        : precoPraticado != null
        ? origemDoHistorico(h)
        : "cadastro atual do catálogo";

      // Confiança pela cobertura de tokens: casou TODOS os tokens do termo = resolvido; parcial = assumido.
      const toks = tokenizar(termo);
      const alvo = `${p.name} ${p.sku || ""}`.toLowerCase();
      const casados = toks.filter((t) => alvo.includes(t)).length;
      const status: ItemResolvido["status"] = casados === toks.length ? "resolvido" : "assumido";

      return {
        keyword: termo,
        quantidade: qtd,
        status,
        product_id: p.id,
        nome: p.name,
        preco_venda: precoVenda,
        custo: p.cost_price != null ? Number(p.cost_price) : 0,
        origem,
        candidatos: lista.length,
        preco_informado: precoInformado,
      };
    }),
  );
}
