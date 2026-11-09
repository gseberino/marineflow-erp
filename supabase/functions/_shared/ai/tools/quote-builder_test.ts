// Retorno F3 (P7): o construtor do orçamento, com as guardas da sessão amarrada e o caminho da proposta (opcoes.origem).
// Banco falso, sem rede. Nomes, números e preços inventados.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  montarOrcamento,
  precificarAmarrado,
  quoteBuilderTools,
  resumirOrcamentoLivre,
  sessaoAmarradaDe,
} from "./quote-builder.ts";
import { casoAmarradoDaSessao } from "./registry.ts";

const tool = quoteBuilderTools.find((t) => t.name === "create_quote_from_items")!;

// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;

interface Opcoes {
  clientes?: Linha[];
  ativos?: Linha[];
  produtos?: Linha[];
  rascunhoRecente?: Linha;
  /** unit_sale_snapshot que `ultimoPreco` acha no histórico. */
  historico?: number;
  /** search_products_trgm */
  candidatos?: Linha[];
  /** retorno_previa_precos: o que devolve, ou "erro". */
  precos?: Linha[] | "erro";
  erroInsert?: Record<string, string>;
  erroRecalc?: string;
  erroRascunho?: string;
  grand?: number;
}

const CLIENTE = { id: "c-1", name: "João Silva", generico: false };
const ATIVO = { id: "v-1", name: "Lancha Mar Azul" };
const BATERIA = { id: "p-1", name: "Bateria LiFePO4 100Ah", sku: null, cost_price: 1500, sale_price: 2000 };

function bancoFalso(op: Opcoes = {}) {
  const insercoes: Record<string, Linha[]> = {};
  const exclusoes: Array<[string, string, unknown]> = [];
  const rpcs: Array<[string, Linha]> = [];
  const leituras: Array<[string, string]> = [];
  const clientes = op.clientes ?? [CLIENTE];
  const ativos = op.ativos ?? [ATIVO];
  const produtos = op.produtos ?? [BATERIA];

  function consulta(tabela: string) {
    const f: Record<string, unknown> = {};
    let textoIlike: string | null = null;
    let ids: string[] | null = null;
    let modo: "select" | "insert" | "update" | "delete" = "select";
    let campoDelete: [string, unknown] | null = null;

    const resolver = (): Promise<{ data: unknown; error: { message: string } | null }> => {
      if (modo === "delete") {
        exclusoes.push([tabela, campoDelete?.[0] ?? "", campoDelete?.[1]]);
        return Promise.resolve({ data: null, error: null });
      }
      if (modo === "update") return Promise.resolve({ data: null, error: null });
      if (modo === "insert") {
        const erro = op.erroInsert?.[tabela];
        if (erro) return Promise.resolve({ data: null, error: { message: erro } });
        if (tabela === "service_orders") return Promise.resolve({ data: { id: "orc-novo", service_order_number: "ORÇ-00151" }, error: null });
        if (tabela === "products") return Promise.resolve({ data: { id: "prod-novo" }, error: null });
        return Promise.resolve({ data: null, error: null });
      }
      switch (tabela) {
        case "clients": return Promise.resolve({ data: f.id ? clientes.filter((c) => c.id === f.id) : clientes, error: null });
        case "vessels": return Promise.resolve({ data: f.id ? ativos.filter((c) => c.id === f.id) : ativos, error: null });
        case "service_orders":
          if (f.status === "draft") {
            if (op.erroRascunho) return Promise.resolve({ data: null, error: { message: op.erroRascunho } });
            return Promise.resolve({ data: op.rascunhoRecente ? [op.rascunhoRecente] : [], error: null });
          }
          return Promise.resolve({ data: [{ grand_total: op.grand ?? 1000 }], error: null });
        case "products":
          if (ids) return Promise.resolve({ data: produtos.filter((p) => ids!.includes(p.id)), error: null });
          if (textoIlike) return Promise.resolve({ data: [], error: null });
          return Promise.resolve({ data: produtos.filter((p) => p.id === f.id), error: null });
        case "service_order_parts":
          return Promise.resolve({
            data: op.historico
              ? [{ unit_sale_snapshot: op.historico, created_at: "2026-08-12T10:00:00Z", service_orders: { service_order_number: "ORÇ-00088", created_at: "2026-08-12T10:00:00Z" } }]
              : [],
            error: null,
          });
        case "app_settings": return Promise.resolve({ data: [{ value: f.key === "stock_model_v2" ? "on" : "3" }], error: null });
        default: return Promise.resolve({ data: [], error: null });
      }
    };

    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: (colunas: string) => { if (modo === "select") leituras.push([tabela, colunas]); return q; },
      eq: (c: string, v: unknown) => { f[c] = v; if (modo === "delete") campoDelete = [c, v]; return q; },
      gte: () => q, gt: () => q, neq: () => q, order: () => q, limit: () => q, range: () => q,
      ilike: (_c: string, v: string) => { textoIlike = v; return q; },
      in: (_c: string, v: string[]) => { ids = v; return q; },
      insert: (linhas: Linha | Linha[]) => { modo = "insert"; (insercoes[tabela] ??= []).push(...(Array.isArray(linhas) ? linhas : [linhas])); return q; },
      update: () => { modo = "update"; return q; },
      delete: () => { modo = "delete"; return q; },
      maybeSingle: async () => {
        const r = await resolver();
        return { data: Array.isArray(r.data) ? (r.data[0] ?? null) : r.data, error: r.error };
      },
      single: async () => {
        const r = await resolver();
        return { data: Array.isArray(r.data) ? (r.data[0] ?? null) : r.data, error: r.error };
      },
      then: (ok: (v: unknown) => unknown, nao: (e: unknown) => unknown) => resolver().then(ok, nao),
    };
    return q;
  }

  const db = {
    from: consulta,
    rpc: (fn: string, args: Linha) => {
      rpcs.push([fn, args]);
      if (fn === "next_document_number") return Promise.resolve({ data: 151, error: null });
      if (fn === "search_products_trgm") return Promise.resolve({ data: op.candidatos ?? [BATERIA], error: null });
      if (fn === "recalc_so_totals") return Promise.resolve({ data: null, error: op.erroRecalc ? { message: op.erroRecalc } : null });
      if (fn === "retorno_previa_precos") {
        if (op.precos === "erro") return Promise.resolve({ data: null, error: { message: "falhou" } });
        const itens = args.p_itens as Linha[];
        const resposta = op.precos ?? [{ preco: 2300, fonte: "praticado_cliente", em: "2026-08-12", rotulo: "praticado em 12/08/26" }];
        return Promise.resolve({ data: itens.map((it, i) => ({ chave: it.chave, ...(resposta[i] ?? resposta[0]) })), error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  return {
    db, insercoes, exclusoes, rpcs, leituras,
    chamou: (fn: string) => rpcs.some(([n]) => n === fn),
    linhas: (tabela: string) => insercoes[tabela] ?? [],
  };
}

// deno-lint-ignore no-explicit-any
const ctxDe = (db: unknown, extra: Record<string, unknown> = {}): any =>
  ({ sb: db, admin: db, userId: "dono-1", userRole: "admin", jwt: "", appOrigin: "", settings: {}, ...extra });

const COM_ORIGEM = { origem: { valor: "retorno_previa" as const, chave8: "12345678" } };
const BASE = { client_id: "c-1", vessel_id: "v-1", title: "Troca de baterias" };

const FALA_PRECO = "Falta preço em";

// ─── Fluxo livre (o que já existia) ─────────────────────────────────────────────────────────

Deno.test("1. fluxo livre com nome continua: resolve cliente, ativo e item pelo nome", async () => {
  const b = bancoFalso({ historico: 1900 });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ client_name: "João", vessel_name: "Mar", title: "Baterias", items: [{ keyword: "Bateria LiFePO4 100Ah", quantity: 2 }] }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals(r.orcamento, "ORÇ-00151");
  assertEquals(r.cliente, "João Silva");
  assertEquals(b.linhas("service_order_parts")[0].product_id, "p-1");
  assertEquals(b.linhas("service_order_parts")[0].unit_sale_snapshot, 1900);
  assertEquals(b.chamou("search_products_trgm"), true);
});

Deno.test("2. amarrado + nome: preValidar e execute recusam com a frase que diz o que fazer", async () => {
  const b = bancoFalso();
  const args = { client_name: "João", vessel_id: "v-1", title: "x", items: [{ keyword: "Bateria" }] };
  const recusa = tool.preValidar!(args, ctxDe(b.db, { sessaoAmarrada: true }))!;
  assertStringIncludes(recusa.error, "nome não escolhe cadastro");
  assertStringIncludes(recusa.error, "search_clients");
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute(args, ctxDe(b.db, { sessaoAmarrada: true })) as any;
  assertStringIncludes(r.error, "nome não escolhe cadastro");
  assertEquals(b.linhas("service_orders"), []);
  // vessel_name recusa do mesmo jeito; sem amarra, passa
  assert(tool.preValidar!({ client_id: "c-1", vessel_name: "Mar" }, ctxDe(b.db, { sessaoAmarrada: true })));
  assertEquals(tool.preValidar!(args, ctxDe(b.db)), null);
  assertEquals(tool.preValidar!({ client_id: "c-1", vessel_id: "v-1" }, ctxDe(b.db, { sessaoAmarrada: true })), null);
});

Deno.test("4. amarrado sem client_id no contexto passa do mesmo jeito (a guarda não usa casoAmarrado)", async () => {
  const b = bancoFalso();
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ ...BASE, items: [{ keyword: "Bateria LiFePO4 100Ah" }] }, ctxDe(b.db, { sessaoAmarrada: true })) as any;
  assertEquals(r.ok, true);
  assertEquals(b.linhas("service_orders").length, 1);
});

// ─── Caminho da proposta (opcoes.origem) ────────────────────────────────────────────────────

Deno.test("5. com origem, product_id ignora o resolvedor e grava o preço do preparo", async () => {
  const b = bancoFalso();
  const args = { ...BASE, items: [{ product_id: "p-1", keyword: "Nome que o preparo mandou", quantity: 2, unit_price: 2200 }], labor: [] };
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento(args, ctxDe(b.db), COM_ORIGEM) as any;
  assertEquals(r.ok, true);
  assertEquals(b.chamou("search_products_trgm"), false);
  assertEquals(b.leituras.some(([t]) => t === "product_aliases"), false);
  const [peca] = b.linhas("service_order_parts");
  assertEquals(peca.product_id, "p-1");
  assertEquals(peca.unit_sale_snapshot, 2200);
  assertEquals(peca.unit_cost_snapshot, 1500);
  assertEquals(peca.line_total_sale, 4400);
  assertEquals(r.itens_no_catalogo[0].item, "Bateria LiFePO4 100Ah");
  assertEquals(r.itens_no_catalogo[0].origem, "proposta do retorno");
  assertEquals(b.leituras.filter(([t]) => t === "products").every(([, c]) => !c.includes("sale_price")), true);
});

Deno.test("6. com origem, product_id inexistente não cria nada", async () => {
  const b = bancoFalso();
  const r = await montarOrcamento({ ...BASE, items: [{ product_id: "sumiu", keyword: "x", quantity: 1, unit_price: 10 }] }, ctxDe(b.db), COM_ORIGEM);
  assertEquals(r, { error: "Produto da proposta não existe mais." });
  assertEquals(b.linhas("service_orders"), []);
  assertEquals(b.chamou("next_document_number"), false);
});

Deno.test("7. origem e chave8 vão no insert do orçamento", async () => {
  const b = bancoFalso();
  await montarOrcamento({ ...BASE, items: [{ product_id: "p-1", keyword: "x", quantity: 1, unit_price: 10 }] }, ctxDe(b.db), COM_ORIGEM);
  assertEquals(b.linhas("service_orders")[0].origem, "retorno_previa");
  assertEquals(b.linhas("service_orders")[0].origem_chave8, "12345678");
});

Deno.test("8. sem opcoes.origem, nenhum campo novo no insert", async () => {
  const b = bancoFalso();
  await montarOrcamento({ ...BASE, items: [{ keyword: "Bateria LiFePO4 100Ah" }] }, ctxDe(b.db));
  const [so] = b.linhas("service_orders");
  assertEquals("origem" in so, false);
  assertEquals("origem_chave8" in so, false);
});

Deno.test("9. rascunho recente devolve ja_existe, sem nenhum insert, mesmo com force_new vindo nos argumentos", async () => {
  const b = bancoFalso({ rascunhoRecente: { id: "orc-velho", service_order_number: "ORÇ-00140", created_at: "2026-12-08T10:00:00Z" } });
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento({ ...BASE, force_new: true, items: [{ product_id: "p-1", keyword: "x", quantity: 1, unit_price: 10 }] }, ctxDe(b.db), COM_ORIGEM) as any;
  assertEquals(r.ja_existe, "ORÇ-00140");
  assertEquals(b.insercoes, {});
});

Deno.test("9b. com origem, erro na leitura do rascunho recente recusa, em vez de virar 'não existe'", async () => {
  const b = bancoFalso({ erroRascunho: "falhou" });
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento({ ...BASE, items: [{ product_id: "p-1", keyword: "x", quantity: 1, unit_price: 10 }] }, ctxDe(b.db), COM_ORIGEM) as any;
  assert(r.error);
  assertEquals(b.linhas("service_orders"), []);
});

Deno.test("10. Cliente Final com origem recusa, antes de criar", async () => {
  const b = bancoFalso({ clientes: [{ ...CLIENTE, generico: true }] });
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento({ ...BASE, items: [{ product_id: "p-1", keyword: "x", quantity: 1, unit_price: 10 }] }, ctxDe(b.db), COM_ORIGEM) as any;
  assert(r.error);
  assertEquals(b.linhas("service_orders"), []);
  // sem origem nada muda: o genérico continua orçando pelo caminho livre
  const livre = bancoFalso({ clientes: [{ ...CLIENTE, generico: true }] });
  // deno-lint-ignore no-explicit-any
  const ok = await montarOrcamento({ ...BASE, items: [{ keyword: "Bateria LiFePO4 100Ah" }] }, ctxDe(livre.db)) as any;
  assertEquals(ok.ok, true);
});

Deno.test("11. só mão de obra cria o orçamento, sem peças e com o recálculo; os dois vazios recusam", async () => {
  const b = bancoFalso();
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento({ ...BASE, items: [], labor: [{ description: "Instalação", price: 800 }] }, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals(b.chamou("search_products_trgm"), false);
  assertEquals(b.linhas("service_order_parts"), []);
  assertEquals(b.linhas("service_order_services")[0].name_snapshot, "Instalação");
  assertEquals(b.chamou("recalc_so_totals"), true);

  const vazio = bancoFalso();
  // deno-lint-ignore no-explicit-any
  const recusa = await montarOrcamento({ ...BASE, items: [], labor: [] }, ctxDe(vazio.db)) as any;
  assert(recusa.error);
  assertEquals(vazio.linhas("service_orders"), []);
});

Deno.test("12. com origem, erro ao gravar serviço desfaz o orçamento; sem origem, o comportamento antigo", async () => {
  const b = bancoFalso({ erroInsert: { service_order_services: "falhou de propósito" } });
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento(
    { ...BASE, items: [{ product_id: "p-1", keyword: "x", quantity: 1, unit_price: 10 }], labor: [{ service_id: "s-1", description: "Instalação", price: 800, quantity: 1, billing_unit: "visit" }] },
    ctxDe(b.db), COM_ORIGEM,
  ) as any;
  assert(r.error);
  assertEquals(r.ok, undefined);
  assertEquals(b.exclusoes.map(([t]) => t), ["service_order_parts", "service_order_services", "service_orders"]);
  assertEquals(b.exclusoes[2], ["service_orders", "id", "orc-novo"]);

  const livre = bancoFalso({ erroInsert: { service_order_services: "falhou de propósito" } });
  // deno-lint-ignore no-explicit-any
  const ok = await montarOrcamento({ ...BASE, items: [{ keyword: "Bateria LiFePO4 100Ah" }], labor: [{ description: "Instalação", price: 800 }] }, ctxDe(livre.db)) as any;
  assertEquals(ok.ok, true);
  assertEquals(livre.exclusoes, []);
});

Deno.test("12b. com origem, erro na peça ou no recálculo também desfaz", async () => {
  const peca = bancoFalso({ erroInsert: { service_order_parts: "falhou" } });
  // deno-lint-ignore no-explicit-any
  const r1 = await montarOrcamento({ ...BASE, items: [{ product_id: "p-1", keyword: "x", quantity: 1, unit_price: 10 }] }, ctxDe(peca.db), COM_ORIGEM) as any;
  assert(r1.error);
  assertEquals(peca.exclusoes.at(-1)?.[0], "service_orders");

  const recalculo = bancoFalso({ erroRecalc: "falhou" });
  // deno-lint-ignore no-explicit-any
  const r2 = await montarOrcamento({ ...BASE, items: [{ product_id: "p-1", keyword: "x", quantity: 1, unit_price: 10 }] }, ctxDe(recalculo.db), COM_ORIGEM) as any;
  assert(r2.error);
  assertEquals(recalculo.exclusoes.at(-1)?.[0], "service_orders");
});

Deno.test("12c. com origem, labor grava service_id e billing_unit do preparo", async () => {
  const b = bancoFalso();
  await montarOrcamento({ ...BASE, items: [], labor: [{ service_id: "s-1", description: "Instalação", price: 800, quantity: 2, billing_unit: "visit" }] }, ctxDe(b.db), COM_ORIGEM);
  const [s] = b.linhas("service_order_services");
  assertEquals(s.service_id, "s-1");
  assertEquals(s.billing_unit_snapshot, "visit");
  assertEquals(s.line_total, 1600);
});

Deno.test("12d. com origem, linha com preço zero não vira orçamento", async () => {
  const b = bancoFalso();
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento({ ...BASE, items: [{ product_id: "p-1", keyword: "Bateria", quantity: 1, unit_price: 0 }] }, ctxDe(b.db), COM_ORIGEM) as any;
  assertStringIncludes(r.error, FALA_PRECO);
  assertEquals(b.linhas("service_orders"), []);
});

Deno.test("13. com origem, linha sem product_id não chama o resolvedor e grava o produto pendente com o nome e o preço", async () => {
  const b = bancoFalso();
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento({ ...BASE, items: [{ keyword: "Cabo especial 35 mm", quantity: 3, unit_price: 320 }] }, ctxDe(b.db), COM_ORIGEM) as any;
  assertEquals(r.ok, true);
  assertEquals(b.chamou("search_products_trgm"), false);
  const [produto] = b.linhas("products");
  assertEquals(produto.name, "Cabo especial 35 mm");
  assertEquals(produto.sale_price, 320);
  assertEquals(b.linhas("service_order_parts")[0].product_id, "prod-novo");
  assertEquals(b.linhas("service_order_parts")[0].unit_sale_snapshot, 320);
});

Deno.test("22. com origem, produtoProvisorio nulo desfaz o orçamento e não grava em service_order_services", async () => {
  const b = bancoFalso({ erroInsert: { products: "falhou" } });
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento({ ...BASE, items: [{ keyword: "Cabo especial", quantity: 1, unit_price: 320 }], labor: [{ description: "Instalação", price: 800 }] }, ctxDe(b.db), COM_ORIGEM) as any;
  assert(r.error);
  assertEquals(b.linhas("service_order_services"), []);
  assertEquals(b.exclusoes.at(-1)?.[0], "service_orders");

  // nome com menos de 2 letras conta como erro, sem ir parar em "valor provisório" no PDF
  const curto = bancoFalso();
  // deno-lint-ignore no-explicit-any
  const r2 = await montarOrcamento({ ...BASE, items: [{ keyword: "x", quantity: 1, unit_price: 10 }] }, ctxDe(curto.db), COM_ORIGEM) as any;
  assert(r2.error);
  assertEquals(curto.linhas("service_order_services"), []);
  assertEquals(curto.exclusoes.at(-1)?.[0], "service_orders");
});

// ─── Sessão amarrada ────────────────────────────────────────────────────────────────────────

const ARGS_LIVRES = { ...BASE, items: [{ keyword: "Bateria LiFePO4 100Ah", quantity: 2 }], labor: [{ description: "Instalação", price: 800 }] };

Deno.test("14. amarrado: resumo e gravação têm o preço de retorno_previa_precos, e não o de ultimoPreco", async () => {
  const b = bancoFalso({ historico: 9999 });
  const resumo = await resumirOrcamentoLivre(b.db, ARGS_LIVRES, {});
  assertEquals(
    resumo,
    "Orçamento para *João Silva* · Lancha Mar Azul\n" +
      "1. Bateria LiFePO4 100Ah · 2 × R$ 2.300 · praticado em 12/08/26\n" +
      "2. Instalação · 1 × R$ 800\n" +
      "Total: R$ 5.400 · *sim <PIN>* cria o rascunho, e nada vai ao cliente",
  );
  assertEquals(b.linhas("service_orders"), []);

  const c = bancoFalso({ historico: 9999 });
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento(ARGS_LIVRES, ctxDe(c.db, { sessaoAmarrada: true })) as any;
  assertEquals(r.ok, true);
  assertEquals(c.linhas("service_order_parts")[0].unit_sale_snapshot, 2300);
});

Deno.test("15. amarrado: orçado aparece como orçado (não aprovado), nunca como praticado", async () => {
  const b = bancoFalso({ precos: [{ preco: 2300, fonte: "orcado_cliente", em: "2026-08-12", rotulo: "orçado em 12/08/26 (não aprovado)" }] });
  const resumo = await resumirOrcamentoLivre(b.db, { ...BASE, items: [{ keyword: "Bateria LiFePO4 100Ah" }] }, {});
  assertStringIncludes(resumo, "orçado em 12/08/26 (não aprovado)");
  assertEquals(resumo.includes("praticado"), false);
});

const PRODUTO_SEM_PRECO = { ...BATERIA, id: "p-2", name: "Bateria Sem Preço", sale_price: 0 };
const SEM_PRECO = [{ preco: null, fonte: "sem_preco", em: null, rotulo: "sem preço" }];

Deno.test("16. amarrado: assumido com 0, provisório sem preço e labor com 0 dão Falta preço; preço dito passa", async () => {
  // assumido: o catálogo tem o produto, mas ninguém sabe o preço
  const assumido = bancoFalso({ candidatos: [PRODUTO_SEM_PRECO], produtos: [PRODUTO_SEM_PRECO], precos: SEM_PRECO });
  const r1 = await resumirOrcamentoLivre(assumido.db, { ...BASE, items: [{ keyword: "Bateria Sem Preço" }] }, {});
  assertEquals(r1, "⚠️ Falta preço em Bateria Sem Preço: diga o valor.");

  // provisório: o catálogo não achou
  const provisorio = bancoFalso({ candidatos: [] });
  const r2 = await resumirOrcamentoLivre(provisorio.db, { ...BASE, items: [{ keyword: "Peça inexistente" }] }, {});
  assertEquals(r2, "⚠️ Falta preço em Peça inexistente: diga o valor.");

  // labor com preço 0
  const labor = bancoFalso();
  const r3 = await resumirOrcamentoLivre(labor.db, { ...BASE, items: [], labor: [{ description: "Instalação", price: 0 }] }, {});
  assertEquals(r3, "⚠️ Falta preço em Instalação: diga o valor.");

  // execução: a mesma condição, com a frase de execução, e nada criado
  const exec = bancoFalso({ candidatos: [] });
  // deno-lint-ignore no-explicit-any
  const r4 = await montarOrcamento({ ...BASE, items: [{ keyword: "Peça inexistente" }] }, ctxDe(exec.db, { sessaoAmarrada: true })) as any;
  assertEquals(r4, { error: "Falta preço em Peça inexistente: nada foi criado." });
  assertEquals(exec.linhas("service_orders"), []);

  // preço dito passa, e o rótulo é "você disse", sem chamar a RPC para ele
  const dito = bancoFalso({ candidatos: [PRODUTO_SEM_PRECO], produtos: [PRODUTO_SEM_PRECO] });
  const r5 = await resumirOrcamentoLivre(dito.db, { ...BASE, items: [{ keyword: "Bateria Sem Preço", unit_price: 500 }] }, {});
  assertStringIncludes(r5, "1 × R$ 500 · você disse");
  assertEquals(dito.chamou("retorno_previa_precos"), false);
});

Deno.test("16b. amarrado: precificarAmarrado separa dito, RPC e sem preço", async () => {
  const b = bancoFalso({ precos: [{ preco: 2300, fonte: "catalogo", em: null, rotulo: "preço de catálogo, sem data" }] });
  const saida = await precificarAmarrado(b.db, "c-1", [
    { keyword: "a", quantidade: 1, status: "resolvido", product_id: "p-1", nome: "A", preco_venda: 9, custo: 1, origem: "x", preco_informado: 700 },
    { keyword: "b", quantidade: 1, status: "resolvido", product_id: "p-2", nome: "B", preco_venda: 9, custo: 1, origem: "x" },
    { keyword: "c", quantidade: 1, status: "provisorio", preco_venda: 0, custo: 0, origem: "x" },
  ]);
  assertEquals(saida.map((i) => [i.fonte, i.preco_venda, i.rotulo]), [
    ["dito", 700, "você disse"],
    ["catalogo", 2300, "preço de catálogo, sem data"],
    ["sem_preco", 0, "sem preço"],
  ]);
  assertEquals(saida[1].origem, "preço de catálogo, sem data");
  // só o item com produto e sem preço dito vai à RPC, e numa chamada só
  const chamadas = b.rpcs.filter(([n]) => n === "retorno_previa_precos");
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0][1].p_client, "c-1");
  assertEquals((chamadas[0][1].p_itens as Linha[]).map((i) => [i.tipo, i.product_id]), [["peca", "p-2"]]);
});

Deno.test("17. RPC com erro recusa, sem virar zero", async () => {
  const b = bancoFalso({ precos: "erro" });
  assertEquals(await resumirOrcamentoLivre(b.db, ARGS_LIVRES, {}), "⚠️ Não consegui conferir os preços agora. Nada foi registrado; tente de novo.");
  await assertRejects(() => precificarAmarrado(b.db, "c-1", [{ keyword: "b", quantidade: 1, status: "resolvido", product_id: "p-2", preco_venda: 0, custo: 0, origem: "x" }]));
  const exec = bancoFalso({ precos: "erro" });
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento(ARGS_LIVRES, ctxDe(exec.db, { sessaoAmarrada: true })) as any;
  assertEquals(r, { error: "Não consegui conferir os preços agora. Nada foi registrado; tente de novo." });
  assertEquals(exec.linhas("service_orders"), []);
});

Deno.test("18. não amarrado: retorno_previa_precos não é chamada", async () => {
  const b = bancoFalso({ historico: 1900 });
  await tool.execute(ARGS_LIVRES, ctxDe(b.db));
  assertEquals(b.chamou("retorno_previa_precos"), false);
  assertEquals(b.linhas("service_order_parts")[0].unit_sale_snapshot, 1900);
});

Deno.test("19. pendência com _retrato.amarrada = true no painel (sem sessaoAmarrada): preço da RPC e recusa do assumido com 0", async () => {
  const b = bancoFalso({ historico: 9999 });
  await tool.execute({ ...ARGS_LIVRES, _retrato: { amarrada: true } }, ctxDe(b.db, { canal: "panel" }));
  assertEquals(b.chamou("retorno_previa_precos"), true);
  assertEquals(b.linhas("service_order_parts")[0].unit_sale_snapshot, 2300);

  const zero = bancoFalso({ candidatos: [PRODUTO_SEM_PRECO], produtos: [PRODUTO_SEM_PRECO], precos: SEM_PRECO });
  // deno-lint-ignore no-explicit-any
  const r = await tool.execute({ ...BASE, items: [{ keyword: "Bateria Sem Preço" }], _retrato: { amarrada: true } }, ctxDe(zero.db, { canal: "panel" })) as any;
  assertStringIncludes(r.error, FALA_PRECO);
  assertEquals(zero.linhas("service_orders"), []);
});

Deno.test("20. pendência com _retrato.amarrada = false e contexto amarrado usa o ultimoPreco", async () => {
  const b = bancoFalso({ historico: 1900 });
  await tool.execute({ ...ARGS_LIVRES, _retrato: { amarrada: false } }, ctxDe(b.db, { sessaoAmarrada: true }));
  assertEquals(b.chamou("retorno_previa_precos"), false);
  assertEquals(b.linhas("service_order_parts")[0].unit_sale_snapshot, 1900);
});

Deno.test("21. retratoDaPendencia devolve a marca da sessão", async () => {
  const b = bancoFalso();
  assertEquals(await tool.retratoDaPendencia!({}, ctxDe(b.db, { sessaoAmarrada: true })), { amarrada: true });
  assertEquals(await tool.retratoDaPendencia!({}, ctxDe(b.db)), { amarrada: false });
});

Deno.test("sessaoAmarradaDe: o retrato vale sobre o contexto", () => {
  assertEquals(sessaoAmarradaDe({ _retrato: { amarrada: true } }, ctxDe(null)), true);
  assertEquals(sessaoAmarradaDe({ _retrato: { amarrada: false } }, ctxDe(null, { sessaoAmarrada: true })), false);
  assertEquals(sessaoAmarradaDe({}, ctxDe(null, { sessaoAmarrada: true })), true);
  assertEquals(sessaoAmarradaDe({}, ctxDe(null)), false);
});

Deno.test("23. sem origem, product_id, service_id e billing_unit recebidos são descartados", async () => {
  const args = {
    ...BASE,
    items: [{ keyword: "Bateria LiFePO4 100Ah", product_id: "id-do-modelo", quantity: 1 }],
    labor: [{ description: "Instalação", price: 800, service_id: "s-do-modelo", billing_unit: "hour" }],
  };
  const b = bancoFalso({ historico: 1900 });
  // deno-lint-ignore no-explicit-any
  const r = await montarOrcamento(args, ctxDe(b.db)) as any;
  assertEquals(r.ok, true);
  assertEquals(b.chamou("search_products_trgm"), true);
  assertEquals(b.linhas("service_order_parts")[0].product_id, "p-1");
  assertEquals(b.linhas("service_order_parts")[0].unit_sale_snapshot, 1900);
  assertEquals(b.linhas("service_order_services")[0].service_id, null);
  assertEquals(b.linhas("service_order_services")[0].billing_unit_snapshot, "unit");
  assertEquals(JSON.stringify(r).includes("proposta do retorno"), false);

  // amarrado: o preço vem da RPC, e o id do modelo também cai
  const a = bancoFalso({ historico: 9999 });
  await montarOrcamento(args, ctxDe(a.db, { sessaoAmarrada: true }));
  assertEquals(a.chamou("search_products_trgm"), true);
  assertEquals(a.linhas("service_order_parts")[0].product_id, "p-1");
  assertEquals(a.linhas("service_order_parts")[0].unit_sale_snapshot, 2300);
  assertEquals(a.linhas("service_order_services")[0].service_id, null);
});

Deno.test("o input_schema não muda: product_id, service_id e billing_unit não são oferecidos ao modelo", () => {
  // deno-lint-ignore no-explicit-any
  const p = tool.input_schema.properties as any;
  assertEquals("product_id" in p.items.items.properties, false);
  assertEquals("service_id" in p.labor.items.properties, false);
  assertEquals("billing_unit" in p.labor.items.properties, false);
  assertEquals(tool.input_schema.required, ["title", "items"]);
});

// ─── O resumo em código ─────────────────────────────────────────────────────────────────────

Deno.test("resumo: outro cliente que não o do caso ganha a nota; o mesmo, não", async () => {
  const b = bancoFalso();
  const outro = await resumirOrcamentoLivre(b.db, ARGS_LIVRES, { casoAmarrado: { client_id: "c-outro", vessel_id: null } });
  assertStringIncludes(outro.split("\n")[0], "(não é o cliente do caso do cartão)");
  const mesmo = await resumirOrcamentoLivre(b.db, ARGS_LIVRES, { casoAmarrado: { client_id: "c-1", vessel_id: "v-1" } });
  assertEquals(mesmo.includes("não é o cliente"), false);
});

Deno.test("resumo: cliente inválido devolve a frase do resolverCliente, com ⚠️ e numa linha", async () => {
  const b = bancoFalso({ clientes: [] });
  assertEquals(await resumirOrcamentoLivre(b.db, ARGS_LIVRES, {}), "⚠️ Cliente (client_id) não encontrado.");
  const c = bancoFalso({ ativos: [] });
  assertEquals(await resumirOrcamentoLivre(c.db, ARGS_LIVRES, {}), "⚠️ Ativo (vessel_id) não encontrado.");
});

Deno.test("resumo: sem nenhuma linha recusa, sem pedir PIN para 0 itens", async () => {
  const b = bancoFalso();
  assertEquals(await resumirOrcamentoLivre(b.db, { ...BASE, items: [], labor: [] }, {}), "⚠️ O orçamento ficaria sem nenhum item: diga o que entra.");
});

Deno.test("resumo: item assumido e item sem catálogo dizem o que aconteceu com o nome", async () => {
  const parcial = { ...BATERIA, id: "p-9", name: "Controlador MPPT 60A" };
  const b = bancoFalso({ candidatos: [parcial], produtos: [parcial] });
  const assumido = await resumirOrcamentoLivre(b.db, { ...BASE, items: [{ keyword: "controlador 60a marca nova", unit_price: 1320 }] }, {});
  assertStringIncludes(assumido, '1. Controlador MPPT 60A (você disse "controlador 60a marca nova", confira) · 1 × R$ 1.320 · você disse');

  const sem = bancoFalso({ candidatos: [] });
  const pendente = await resumirOrcamentoLivre(sem.db, { ...BASE, items: [{ keyword: "Cabo especial 35 mm", unit_price: 320 }] }, {});
  assertStringIncludes(pendente, "1. Cabo especial 35 mm (não está no catálogo: entra como produto pendente) · 1 × R$ 320 · você disse");
});

Deno.test("resumo: desconto e imposto entram na conta, e o total mostrado é o que o recálculo chega", async () => {
  const b = bancoFalso();
  const resumo = await resumirOrcamentoLivre(b.db, { ...ARGS_LIVRES, discount_amount: 400, tax_percent: 10 }, {});
  assertStringIncludes(resumo, "Desconto: R$ 400");
  assertStringIncludes(resumo, "Imposto: R$ 500");
  assertStringIncludes(resumo, "Total: R$ 5.500 ·");
});

Deno.test("resumo com centavos e quantidade fracionada segue _retorno_brl e _retorno_qtd", async () => {
  const b = bancoFalso({ precos: [{ preco: 12.5, fonte: "catalogo", em: null, rotulo: "preço de catálogo, sem data" }] });
  const resumo = await resumirOrcamentoLivre(b.db, { ...BASE, items: [{ keyword: "Bateria LiFePO4 100Ah", quantity: 2.5 }] }, {});
  assertStringIncludes(resumo, "2,5 × R$ 12,50");
  assertStringIncludes(resumo, "Total: R$ 31,25");
});

Deno.test("casoAmarradoDaSessao: só com retorno_amarrada = true", () => {
  assertEquals(casoAmarradoDaSessao({ metadata: { retorno_amarrada: true }, client_id: "c", vessel_id: null }), { client_id: "c", vessel_id: null });
  assertEquals(casoAmarradoDaSessao({ metadata: { retorno_amarrada: false }, client_id: "c", vessel_id: "v" }), undefined);
  assertEquals(casoAmarradoDaSessao({ metadata: null, client_id: "c", vessel_id: "v" }), undefined);
  assertEquals(casoAmarradoDaSessao(null), undefined);
});
