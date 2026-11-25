// Leitura que falha não pode virar "não há nada" (auditoria de 02-03/10/2026, depois do combustível
// R$ 0). Cada ferramenta abaixo engolia o `error` de uma leitura secundária e respondia vazio como
// fato: OS sem peças, fornecedor "sem resposta", cliente "nunca cobrado" (cobrar duas vezes), item
// "sem resultado" (valor provisório para produto que existe). E list_low_stock falhava SEMPRE.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { orContem } from "../filtro-or.ts";
import { productTools } from "./products.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { financialTools } from "./financial.ts";
import { quoteTools } from "./quotes.ts";
import { fechamentoTools } from "./fechamento.ts";
import { whatsappTools } from "./whatsapp.ts";

/** Banco de mentira: devolve as linhas da tabela; as tabelas em `falham` respondem com erro. */
function bancoFalso(tabelas: Record<string, unknown[]>, falham: string[] = []) {
  const pedidos: Array<{ tabela: string; chamadas: unknown[][] }> = [];
  const db = {
    pedidos,
    from(tabela: string) {
      const pedido = { tabela, chamadas: [] as unknown[][] };
      pedidos.push(pedido);
      const resultado = () => falham.includes(tabela)
        ? { data: null, error: { message: `falha em ${tabela}` } }
        : { data: tabelas[tabela] ?? [], error: null };
      // deno-lint-ignore no-explicit-any
      const q: any = {};
      for (const m of ["select", "in", "gte", "lte", "lt", "gt", "eq", "not", "or", "order", "range", "limit", "filter", "ilike"]) {
        q[m] = (...a: unknown[]) => { pedido.chamadas.push([m, ...a]); return q; };
      }
      q.maybeSingle = () => {
        const r = resultado();
        return Promise.resolve(r.error ? r : { data: (r.data as unknown[])[0] ?? null, error: null });
      };
      // deno-lint-ignore no-explicit-any
      q.then = (ok: any, erro: any) => Promise.resolve(resultado()).then(ok, erro);
      return q;
    },
  };
  return db;
}

function contexto(db: ReturnType<typeof bancoFalso>) {
  return { sb: db, admin: db, userId: "u", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {} } as never;
}

const ferramenta = (lista: Array<{ name: string }>, nome: string) =>
  // deno-lint-ignore no-explicit-any
  lista.find((t) => t.name === nome) as any;

Deno.test("orContem: vírgula e parênteses viram texto (\"cabo 2,5mm\" quebrava a busca)", () => {
  assertEquals(orContem(["name", "sku"], "cabo 2,5mm"), 'name.ilike."%cabo 2,5mm%",sku.ilike."%cabo 2,5mm%"');
  assertEquals(orContem(["name"], "Bomba (12V)"), 'name.ilike."%Bomba (12V)%"');
  // Aspas e barra invertida fechariam o valor antes da hora: saem.
  assertEquals(orContem(["name"], 'cabo 10" \\x'), 'name.ilike."%cabo 10   x%"');
});

Deno.test("list_low_stock: compara estoque com o mínimo de cada produto (antes falhava sempre)", async () => {
  const db = bancoFalso({
    products: [
      { id: "a", name: "Anodo", stock_quantity: 1, minimum_stock: 2, unit: "un" },
      { id: "b", name: "Bomba", stock_quantity: 5, minimum_stock: 2, unit: "un" },
      { id: "c", name: "Cabo", stock_quantity: null, minimum_stock: 3, unit: "m" },
    ],
  });
  const r = await ferramenta(productTools, "list_low_stock").execute({}, contexto(db));
  assertEquals(r.results.map((p: { id: string }) => p.id), ["a", "c"]);
  assertEquals(r.produtos_com_minimo_cadastrado, 3);
  // Nada de filtro coluna-com-coluna (o PostgREST comparava com o texto "minimum_stock").
  assertEquals(db.pedidos[0].chamadas.some((c) => c[0] === "filter"), false);
});

Deno.test("search_products_batch: busca que falhou NÃO vira 'sem resultado'", async () => {
  const db = bancoFalso({}, ["products"]);
  await assertRejects(
    () => ferramenta(productTools, "search_products_batch").execute({ queries: ["cabo 2,5mm"] }, contexto(db)),
    Error,
    'Não consegui buscar "cabo 2,5mm"',
  );
});

Deno.test("search_products_batch: o termo vai entre aspas no filtro", async () => {
  const db = bancoFalso({ products: [] });
  const r = await ferramenta(productTools, "search_products_batch").execute({ queries: ["cabo 2,5mm"] }, contexto(db));
  assertEquals(r.sem_resultado, ["cabo 2,5mm"]);
  const or = db.pedidos[0].chamadas.find((c) => c[0] === "or");
  assertEquals(or, ["or", 'name.ilike."%cabo 2,5mm%",sku.ilike."%cabo 2,5mm%",brand.ilike."%cabo 2,5mm%"']);
});

Deno.test("get_product_price_history: histórico ilegível não vira 'use o catálogo'", async () => {
  const db = bancoFalso({ products: [{ id: "p", name: "Anodo", sale_price: 10 }] }, ["service_order_parts"]);
  await assertRejects(
    () => ferramenta(productTools, "get_product_price_history").execute({ product_id: "p" }, contexto(db)),
    Error,
    "histórico de uso",
  );
});

Deno.test("get_service_order: peças ilegíveis não viram 'OS sem peças'", async () => {
  const db = bancoFalso({ service_orders: [{ id: "os", clients: { name: "X" } }] }, ["service_order_parts"]);
  await assertRejects(
    () => ferramenta(serviceOrderTools, "get_service_order").execute({ id: "os" }, contexto(db)),
    Error,
    "peças da OS",
  );
});

Deno.test("get_delinquency_plan: sem ler as cobranças, não diz 'nunca cobrado'", async () => {
  const vencido = { id: "r", amount: 500, balance_amount: 500, due_date: "2026-01-10", client_id: "c", clients: { name: "Cliente" } };
  const db = bancoFalso({ receivables: [vencido] }, ["collections"]);
  await assertRejects(
    () => ferramenta(financialTools, "get_delinquency_plan").execute({}, contexto(db)),
    Error,
    "cobranças já enviadas",
  );
  // E o status 'overdue' também entra.
  const ok = bancoFalso({ receivables: [vencido], collections: [], app_settings: [] });
  await ferramenta(financialTools, "get_delinquency_plan").execute({}, contexto(ok));
  const inStatus = ok.pedidos[0].chamadas.find((c) => c[0] === "in");
  assertEquals(inStatus, ["in", "status", ["pending", "partially_paid", "overdue"]]);
});

Deno.test("get_quote_comparison: respostas ilegíveis não viram 'fornecedor sem resposta'", async () => {
  const db = bancoFalso(
    { quote_requests: [{ id: "q", code: "COT-00001", sent_supplier_ids: ["s1"] }], quote_request_items: [] },
    ["quote_responses"],
  );
  await assertRejects(
    () => ferramenta(quoteTools, "get_quote_comparison").execute({ code: "COT-00001" }, contexto(db)),
    Error,
    "respostas dos fornecedores",
  );
});

Deno.test("listar_lancados_sozinhos: fila ilegível não vira 'nada lançado'", async () => {
  const db = bancoFalso({ app_settings: [{ value: "on" }] }, ["finance_review_queue"]);
  await assertRejects(
    () => ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db)),
    Error,
    "lançado sozinho",
  );
});

Deno.test("listar_lancados_sozinhos: baixa pelo boleto (22/11/2026) vem com a conta casada para desfazer; a desfeita some", async () => {
  const fila = [
    { title: "Despesa: TSD", suggested_amount: 785.07, suggested_category: "Mercadorias", suggested_date: "2026-10-20", automatica: "boleto", created_payable_id: null, bank_transaction_id: "t1" },
    { title: "Despesa: OUTRA", suggested_amount: 10, suggested_category: "Mercadorias", suggested_date: "2026-10-21", automatica: "boleto", created_payable_id: null, bank_transaction_id: "t-desfeita" },
    { title: "Despesa: POSTO", suggested_amount: 50, suggested_category: "Combustível", suggested_date: "2026-10-22", automatica: "confianca", created_payable_id: "p9", bank_transaction_id: "t3" },
  ];
  const db = bancoFalso({ finance_review_queue: fila, app_settings: [{ value: "on" }], payables: [{ id: "conta-1", bank_transaction_id: "t1" }] });
  const r = await ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db));
  assertEquals(r.lancados.map((l: { por: string; payable_id: string }) => [l.por, l.payable_id]), [["baixa pelo boleto", "conta-1"], ["confiança alta", "p9"]]);
  assertEquals(r.total, 2);
  // a leitura das contas casadas pede só as linhas das baixas
  const pedido = db.pedidos.find((p) => p.tabela === "payables")!;
  assertEquals(pedido.chamadas.find((c) => c[0] === "in"), ["in", "bank_transaction_id", ["t1", "t-desfeita"]]);
});

Deno.test("listar_lancados_sozinhos: contas da baixa ilegíveis não viram 'nada baixado'", async () => {
  const db = bancoFalso({
    finance_review_queue: [{ title: "Despesa: TSD", suggested_amount: 1, automatica: "boleto", created_payable_id: null, bank_transaction_id: "t1" }],
    app_settings: [],
  }, ["payables"]);
  await assertRejects(
    () => ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db)),
    Error,
    "baixadas pelo boleto",
  );
});

// Recebimento baixado pelo boleto (24/11/2026): a conta casada com a linha do banco está em receivables. Procurada só em
// payables, a baixa pareceria desfeita e sumiria da resposta — o dono não teria como pedir "desfaz a baixa da Apolo".
Deno.test("listar_lancados_sozinhos: recebimento baixado pelo boleto (24/11/2026) vem com receivable_id, o cliente e a soma à parte; o desfeito some", async () => {
  const fila = [
    { title: "Receita: CREDITO DE BOLETO", suggested_amount: 5237.99, suggested_category: "Outras receitas", suggested_date: "2026-10-16", automatica: "boleto", kind: "create_receivable", created_payable_id: null, bank_transaction_id: "t-apolo" },
    { title: "Receita: CREDITO DE BOLETO", suggested_amount: 99, suggested_category: "Outras receitas", suggested_date: "2026-10-17", automatica: "boleto", kind: "create_receivable", created_payable_id: null, bank_transaction_id: "t-recebido-desfeito" },
    { title: "Despesa: TSD", suggested_amount: 785.07, suggested_category: "Mercadorias", suggested_date: "2026-10-20", automatica: "boleto", kind: "create_payable", created_payable_id: null, bank_transaction_id: "t1" },
    // dado antigo, sem kind: continua sendo conta a pagar
    { title: "Despesa: ANTIGA", suggested_amount: 10, suggested_category: "Mercadorias", suggested_date: "2026-10-21", automatica: "boleto", created_payable_id: null, bank_transaction_id: "t-antiga" },
    { title: "Despesa: POSTO", suggested_amount: 50, suggested_category: "Combustível", suggested_date: "2026-10-22", automatica: "confianca", kind: "create_payable", created_payable_id: "p9", bank_transaction_id: "t3" },
  ];
  const db = bancoFalso({
    finance_review_queue: fila, app_settings: [{ value: "on" }],
    payables: [{ id: "conta-1", bank_transaction_id: "t1" }, { id: "conta-antiga", bank_transaction_id: "t-antiga" }],
    // a conta como está em produção: a de NF-e não tem categoria (a da proposta, "Outras receitas", não foi gravada em lugar nenhum)
    receivables: [{ id: "rec-apolo", bank_transaction_id: "t-apolo", description: "NF-e 2/25 (parcela 2/3)", category: null, clients: { name: "APOLO INDUSTRIA E COMERCIO" } }],
    // o registro que a baixa deixa na linha do banco: um só, o da conciliação, com a marca na frente
    reconciliation_log: [{ bank_transaction_id: "t-apolo", receivable_id: "rec-apolo", acao: "conciliou", detalhe: "Baixa automática pelo boleto · Conciliado com o extrato de 16/10/2026" }],
  });
  const r = await ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db));
  // a categoria é a da CONTA (24/11/2026): dizer "Outras receitas" seria narrar um lançamento que não existe
  assertEquals(r.lancados[0], {
    o_que: "Recebimento: APOLO INDUSTRIA E COMERCIO — NF-e 2/25 (parcela 2/3)", valor: 5237.99, categoria: null, data: "2026-10-16",
    por: "recebimento pelo boleto", payable_id: null, receivable_id: "rec-apolo",
  });
  assertEquals(
    r.lancados.slice(1).map((l: { por: string; payable_id: string }) => [l.por, l.payable_id]),
    [["baixa pelo boleto", "conta-1"], ["baixa pelo boleto", "conta-antiga"], ["confiança alta", "p9"]],
  );
  // a conta a pagar não ganha campo novo
  assertEquals(r.lancados.slice(1).some((l: Record<string, unknown>) => "receivable_id" in l), false);
  // o total das saídas não soma a entrada do cliente; o recebimento tem a soma dele
  assertEquals(r.total, 4);
  assertEquals(r.valor_total, 785.07 + 10 + 50);
  assertEquals([r.recebimentos_pelo_boleto, r.valor_recebido_pelo_boleto], [1, 5237.99]);
  // cada leitura pede só as linhas do seu lado
  const pedidoDe = (tabela: string) => db.pedidos.find((p) => p.tabela === tabela)!;
  assertEquals(pedidoDe("receivables").chamadas.find((c) => c[0] === "in"), ["in", "bank_transaction_id", ["t-apolo", "t-recebido-desfeito"]]);
  assertEquals(pedidoDe("payables").chamadas.find((c) => c[0] === "in"), ["in", "bank_transaction_id", ["t1", "t-antiga"]]);
  // o registro é conferido só para as linhas de RECEBER que ainda têm conta casada (a desfeita e as de pagar ficam de fora)
  assertEquals(pedidoDe("reconciliation_log").chamadas.find((c) => c[0] === "in"), ["in", "bank_transaction_id", ["t-apolo"]]);
  // a fila é lida com o kind — sem ele não dá para saber de que lado está a conta
  const colunas = String(pedidoDe("finance_review_queue").chamadas.find((c) => c[0] === "select")![1]);
  assertEquals(colunas.split(", ").includes("kind"), true);
  // … e a conta, com a categoria dela
  assertEquals(String(pedidoDe("receivables").chamadas.find((c) => c[0] === "select")![1]).split(", ").includes("category"), true);
});

// A marca que revive (24/11/2026). O desfazer não toca na fila: a proposta fica approved + 'boleto' para sempre. Se o
// dono desfaz a baixa e depois casa À MÃO a mesma linha do banco, "existe conta casada com a linha" volta a ser
// verdade e a ferramenta dizia "recebimento pelo boleto" (baixado sozinho) para uma decisão dele — com o cliente da
// conta nova e o valor somado em valor_recebido_pelo_boleto. O critério (o mesmo da tela e do resumo do dia): o
// registro da linha tem EXATAMENTE UMA entrada, e ela é a da baixa — acao 'conciliou', detalhe começando por "Baixa
// automática pelo boleto", a mesma conta. A função do banco nunca baixa linha que já tenha registro, então qualquer
// outra entrada veio depois e é mão do dono.
Deno.test("listar_lancados_sozinhos: baixa desfeita e a mesma linha casada à mão não volta como 'recebimento pelo boleto' (a marca que revive, 24/11/2026)", async () => {
  const proposta = (linha: string, valor: number) => ({
    title: "Receita: CREDITO DE BOLETO", suggested_amount: valor, suggested_category: "Outras receitas", suggested_date: "2026-11-13",
    automatica: "boleto", kind: "create_receivable", created_payable_id: null, bank_transaction_id: linha,
  });
  const conta = (id: string, linha: string, cliente: string) => ({ id, bank_transaction_id: linha, description: `Saldo ${id}`, category: "Serviços prestados", clients: { name: cliente } });
  const baixa = (linha: string, contaId: string) => ({ bank_transaction_id: linha, receivable_id: contaId, acao: "conciliou", detalhe: "Baixa automática pelo boleto · Conciliado com o extrato de 13/11/2026" });
  const fila = [
    proposta("t-viva", 100), proposta("t-outra-conta", 200), proposta("t-mesma-conta", 300), proposta("t-cancelada", 400),
    proposta("t-sem-registro", 500), proposta("t-a-mao-desde-o-inicio", 600), proposta("t-corrigida", 700),
  ];
  const db = bancoFalso({
    finance_review_queue: fila, app_settings: [{ value: "on" }],
    receivables: [
      conta("rec-viva", "t-viva", "APOLO"),
      conta("rec-do-outro-cliente", "t-outra-conta", "BETA NAUTICA"),
      conta("rec-mesma", "t-mesma-conta", "APOLO"),
      conta("rec-nova", "t-cancelada", "GAMA"),
      conta("rec-sem-registro", "t-sem-registro", "DELTA"),
      conta("rec-a-mao", "t-a-mao-desde-o-inicio", "EPSILON"),
      conta("rec-corrigida", "t-corrigida", "ZETA"),
    ],
    reconciliation_log: [
      // a baixa que continua valendo: um registro só, o dela — a faxina da própria varredura (proposta repetida
      // fechada por outra rodada) não é mão de ninguém e não conta
      baixa("t-viva", "rec-viva"),
      { bank_transaction_id: "t-viva", receivable_id: null, acao: "tirou_da_fila_ja_lancada", detalhe: "Proposta repetida fechada" },
      // desfeita, e a linha casada à mão com a conta de OUTRO cliente
      baixa("t-outra-conta", "rec-apolo-original"),
      { bank_transaction_id: "t-outra-conta", receivable_id: "rec-apolo-original", acao: "desconciliou", detalhe: "Vínculo desfeito: não era da Apolo" },
      { bank_transaction_id: "t-outra-conta", receivable_id: "rec-do-outro-cliente", acao: "conciliou", detalhe: "Conciliado com o extrato de 13/11/2026" },
      // desfeita, e casada à mão de novo com a MESMA conta: agora é decisão do dono
      baixa("t-mesma-conta", "rec-mesma"),
      { bank_transaction_id: "t-mesma-conta", receivable_id: "rec-mesma", acao: "desfez_aplicacao", detalhe: "Aplicação desfeita" },
      { bank_transaction_id: "t-mesma-conta", receivable_id: "rec-mesma", acao: "conciliou", detalhe: "Conciliado com o extrato de 13/11/2026" },
      // a conta baixada foi cancelada (a linha voltou para a fila) e o dono casou a linha com outra
      baixa("t-cancelada", "rec-antiga"),
      { bank_transaction_id: "t-cancelada", receivable_id: "rec-antiga", acao: "cancelou_lancamento", detalhe: "Cancelado: nota errada" },
      { bank_transaction_id: "t-cancelada", receivable_id: "rec-nova", acao: "conciliou", detalhe: "Conciliado com o extrato de 13/11/2026" },
      // (t-sem-registro: nenhuma entrada — não há prova de que a baixa é do sistema)
      // um registro só, mas de conciliação feita à mão (sem a marca na frente) …
      { bank_transaction_id: "t-a-mao-desde-o-inicio", receivable_id: "rec-a-mao", acao: "conciliou", detalhe: "Conciliado com o extrato de 13/11/2026" },
      // … e a baixa em que o dono mexeu depois (corrigiu): já passou pela mão dele, não é mais "sozinho"
      baixa("t-corrigida", "rec-corrigida"),
      { bank_transaction_id: "t-corrigida", receivable_id: "rec-corrigida", acao: "corrigiu_lancamento", detalhe: "Categoria corrigida" },
    ],
  });
  const r = await ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db));
  assertEquals(r.lancados, [{
    o_que: "Recebimento: APOLO — Saldo rec-viva", valor: 100, categoria: "Serviços prestados", data: "2026-11-13",
    por: "recebimento pelo boleto", payable_id: null, receivable_id: "rec-viva",
  }]);
  assertEquals([r.total, r.valor_total, r.recebimentos_pelo_boleto, r.valor_recebido_pelo_boleto], [1, 0, 1, 100]);
  // nenhum cliente das contas casadas à mão vai para o modelo como "baixado sozinho"
  assertEquals(/BETA|GAMA|DELTA|EPSILON|ZETA/.test(JSON.stringify(r)), false, JSON.stringify(r));
});

Deno.test("listar_lancados_sozinhos: a baixa cujo registro aponta OUTRA conta não vale (a conta casada tem de ser a da baixa)", async () => {
  const db = bancoFalso({
    finance_review_queue: [{ title: "Receita: CREDITO DE BOLETO", suggested_amount: 100, suggested_category: "Outras receitas", suggested_date: "2026-11-13", automatica: "boleto", kind: "create_receivable", created_payable_id: null, bank_transaction_id: "t1" }],
    app_settings: [{ value: "on" }],
    receivables: [{ id: "rec-de-agora", bank_transaction_id: "t1", description: "Saldo", category: null, clients: { name: "BETA" } }],
    reconciliation_log: [{ bank_transaction_id: "t1", receivable_id: "rec-da-baixa", acao: "conciliou", detalhe: "Baixa automática pelo boleto · Conciliado com o extrato de 13/11/2026" }],
  });
  const r = await ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db));
  assertEquals(r, { ligado: true, total: 0, valor_total: 0, lancados: [] });
});

Deno.test("listar_lancados_sozinhos: registro da linha ilegível não vira 'nada baixado' nem 'continua valendo'", async () => {
  const db = bancoFalso({
    finance_review_queue: [{ title: "Receita: CREDITO DE BOLETO", suggested_amount: 1, automatica: "boleto", kind: "create_receivable", created_payable_id: null, bank_transaction_id: "t1" }],
    app_settings: [],
    receivables: [{ id: "rec-1", bank_transaction_id: "t1", description: "NF-e 1/1", category: null, clients: { name: "APOLO" } }],
  }, ["reconciliation_log"]);
  await assertRejects(
    () => ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db)),
    Error,
    "Não consegui conferir se os recebimentos baixados pelo boleto continuam valendo",
  );
});

// O critério novo é só do lado de RECEBER. Na conta a pagar a trava do banco é outra (só barra 'desconciliou'): a linha
// de saída pode ter um 'cancelou_lancamento' ou 'desfez_aprovacao' ANTIGO e receber depois uma baixa pelo boleto
// legítima — filtrada pelo registro, essa baixa viva sumiria. O conserto de lá é outro item (comparar datas).
Deno.test("listar_lancados_sozinhos: a conta a PAGAR baixada pelo boleto não passa pelo registro — linha com registro antigo continua na lista", async () => {
  const fila = [
    { title: "Despesa: TSD", suggested_amount: 785.07, suggested_category: "Mercadorias", suggested_date: "2026-10-20", automatica: "boleto", kind: "create_payable", created_payable_id: null, bank_transaction_id: "t1" },
  ];
  const db = bancoFalso({
    finance_review_queue: fila, app_settings: [{ value: "on" }], payables: [{ id: "conta-1", bank_transaction_id: "t1" }],
    reconciliation_log: [
      { bank_transaction_id: "t1", payable_id: "conta-velha", acao: "cancelou_lancamento", detalhe: "Cancelado em setembro" },
      { bank_transaction_id: "t1", payable_id: "conta-1", acao: "conciliou", detalhe: "Baixa automática pelo boleto" },
    ],
  });
  const r = await ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db));
  assertEquals(r, {
    ligado: true, total: 1, valor_total: 785.07,
    lancados: [{ o_que: "Despesa: TSD", valor: 785.07, categoria: "Mercadorias", data: "2026-10-20", por: "baixa pelo boleto", payable_id: "conta-1" }],
  });
  assertEquals(db.pedidos.some((p) => p.tabela === "reconciliation_log" || p.tabela === "receivables"), false);
});

Deno.test("listar_lancados_sozinhos: sem recebimento na lista, a resposta é a de antes (nem campo novo, nem leitura de receivables)", async () => {
  const fila = [
    { title: "Despesa: TSD", suggested_amount: 785.07, suggested_category: "Mercadorias", suggested_date: "2026-10-20", automatica: "boleto", created_payable_id: null, bank_transaction_id: "t1" },
    { title: "Despesa: POSTO", suggested_amount: 50, suggested_category: "Combustível", suggested_date: "2026-10-22", automatica: "regra", created_payable_id: "p9", bank_transaction_id: "t3" },
  ];
  const db = bancoFalso({ finance_review_queue: fila, app_settings: [{ value: "on" }], payables: [{ id: "conta-1", bank_transaction_id: "t1" }] });
  const r = await ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db));
  assertEquals(r, {
    ligado: true, total: 2, valor_total: 785.07 + 50,
    lancados: [
      { o_que: "Despesa: TSD", valor: 785.07, categoria: "Mercadorias", data: "2026-10-20", por: "baixa pelo boleto", payable_id: "conta-1" },
      { o_que: "Despesa: POSTO", valor: 50, categoria: "Combustível", data: "2026-10-22", por: "regra sua", payable_id: "p9" },
    ],
  });
  assertEquals(db.pedidos.some((p) => p.tabela === "receivables" || p.tabela === "reconciliation_log"), false);
});

Deno.test("listar_lancados_sozinhos: recebimentos da baixa ilegíveis não viram 'nada baixado'", async () => {
  const db = bancoFalso({
    finance_review_queue: [{ title: "Receita: CREDITO DE BOLETO", suggested_amount: 1, automatica: "boleto", kind: "create_receivable", created_payable_id: null, bank_transaction_id: "t1" }],
    app_settings: [],
  }, ["receivables"]);
  await assertRejects(
    () => ferramenta(fechamentoTools, "listar_lancados_sozinhos").execute({}, contexto(db)),
    Error,
    "Não consegui ler os recebimentos baixados pelo boleto",
  );
});

Deno.test("listar_lancados_sozinhos: a descrição ensina a desfazer o recebimento pelo receivable_id", () => {
  const descricao = String(ferramenta(fechamentoTools, "listar_lancados_sozinhos").description);
  for (const trecho of ["recebimento pelo boleto", "receivable_id", "desfazer_aprovacao_de_lancamento", "valor_recebido_pelo_boleto", "baixa pelo boleto"]) {
    assertEquals(descricao.includes(trecho), true, trecho);
  }
});

Deno.test("get_delinquency_plan: cliente com entrada esperando no Extrato sai da cobrança, com o porquê", async () => {
  const vencido = { id: "r", amount: 500, balance_amount: 500, due_date: "2026-01-10", client_id: "c", clients: { name: "Cliente" } };
  const db = bancoFalso({
    receivables: [vencido], collections: [], app_settings: [],
    finance_review_queue: [{ suggested_client_id: "c", suggested_amount: 500, suggested_date: "2026-10-02", title: "Receita: CLIENTE" }],
  });
  const r = await ferramenta(financialTools, "get_delinquency_plan").execute({}, contexto(db));
  assertEquals(r.casos, []);
  assertEquals(r.talvez_ja_pago.map((c: { cliente: string; pix_esperando_no_extrato: unknown[] }) => [c.cliente, c.pix_esperando_no_extrato.length]), [["Cliente", 1]]);
  // E a leitura da fila que falha não vira "nenhum Pix esperando".
  const falha = bancoFalso({ receivables: [vencido], collections: [], app_settings: [] }, ["finance_review_queue"]);
  await assertRejects(() => ferramenta(financialTools, "get_delinquency_plan").execute({}, contexto(falha)), Error, "Pix que esperam no Extrato");
});

// 25/11/2026: o lembrete só roda pelo "sim" de uma pendência, que leva o retrato do que o cartão mostrou (_retrato); sem
// ele o execute recusa antes de ler. Estes três testes passam o retrato para chegar na trava que cada um prova — a
// entrada que chegou no Extrato DEPOIS do pedido ainda segura o envio. O id da cobrança é uuid, como no banco.
const COBRANCA = "33333333-3333-4333-8333-333333333001";

Deno.test("send_collection_reminder: com Pix do cliente esperando no Extrato, não cobra", async () => {
  const db = bancoFalso({
    collections: [{ id: COBRANCA, amount: 500, due_date: "2026-09-10", contact_whatsapp: "5547999990000", client_id: "c" }],
    app_settings: [],
    finance_review_queue: [{ suggested_client_id: "c", suggested_amount: 500, suggested_date: "2026-10-02", title: "Receita: CLIENTE" }],
  });
  const original = globalThis.fetch;
  let enviou = false;
  globalThis.fetch = (() => { enviou = true; return Promise.resolve(new Response("{}")); }) as typeof fetch;
  try {
    const tool = ferramenta(whatsappTools, "send_collection_reminder");
    // Pedido novo com a entrada já esperando: nem retrato há (o cartão vira a recusa, sem pendência).
    assertEquals(await tool.retratoDaPendencia({ collection_id: COBRANCA }, contexto(db)), null);
    const r = await tool.execute({ collection_id: COBRANCA, _retrato: { cobranca: COBRANCA } }, contexto(db));
    assertEquals(/entrada esperando no Extrato/.test(r.error), true);
    assertEquals(r.nada_enviado, true);
    assertEquals(enviou, false);
    // E sem retrato nenhum (chamada direta, pendência antiga) também não sai nada.
    const semRetrato = await tool.execute({ collection_id: COBRANCA }, contexto(db));
    assertEquals(/não consegui conferir a cobrança quando o pedido foi feito/.test(semRetrato.error), true);
    assertEquals(enviou, false);
  } finally {
    globalThis.fetch = original;
  }
});

// Retorno F0a-2 (05/11/2026): o telefone do cadastro genérico é de um terceiro. Cobrar lá expõe a dívida a quem não deve.
Deno.test("send_collection_reminder: 'Cliente Final' sem contato próprio não recebe a cobrança", async () => {
  const db = bancoFalso({
    collections: [{ id: COBRANCA, amount: 500, due_date: "2026-09-10", client_id: "c" }],
    clients: [{ id: "c", name: "Cliente Final", whatsapp: "5547999990000", phone: null, opt_out_whatsapp: false, generico: true }],
    app_settings: [], finance_review_queue: [],
  });
  const original = globalThis.fetch;
  let enviou = false;
  globalThis.fetch = (() => { enviou = true; return Promise.resolve(new Response("{}")); }) as typeof fetch;
  try {
    const r = await ferramenta(whatsappTools, "send_collection_reminder").execute({ collection_id: COBRANCA, _retrato: { cobranca: COBRANCA } }, contexto(db));
    assertEquals(/Cliente Final/.test(r.error), true);
    assertEquals(r.nada_enviado, true);
    assertEquals(enviou, false);
  } finally {
    globalThis.fetch = original;
  }
});

Deno.test("send_collection_reminder: a cobrança com contato próprio não é barrada pelo cadastro genérico", async () => {
  const db = bancoFalso({
    collections: [{ id: COBRANCA, amount: 500, due_date: "2026-09-10", contact_whatsapp: "5547988887777", client_id: "c" }],
    clients: [{ id: "c", name: "Cliente Final", whatsapp: "5547999990000", phone: null, opt_out_whatsapp: false, generico: true }],
    app_settings: [], finance_review_queue: [],
  });
  const original = globalThis.fetch;
  let destino = "";
  globalThis.fetch = ((_url: string, init?: RequestInit) => {
    destino = String(JSON.parse(String(init?.body ?? "{}")).phone ?? "");
    return Promise.resolve(new Response("{}"));
  }) as typeof fetch;
  // 11h em Brasília: fora da janela a guarda barra o envio, e o teste só passaria em horário comercial.
  const relogio = new FakeTime(new Date("2026-11-05T14:00:00.000Z"));
  try {
    const tool = ferramenta(whatsappTools, "send_collection_reminder");
    // O retrato como a pendência grava: tirado do banco quando o pedido nasce (o destino já é o contato da cobrança).
    const retrato = await tool.retratoDaPendencia({ collection_id: COBRANCA }, contexto(db));
    assertEquals([retrato?.cobranca, retrato?.telefone, retrato?.valor, retrato?.vencimento], [COBRANCA, "5547988887777", 500, "2026-09-10"]);
    // O banco falso não grava o histórico da cobrança, que vem depois do envio: aqui importa só para onde saiu.
    await tool.execute({ collection_id: COBRANCA, _retrato: retrato }, contexto(db)).catch(() => null);
    assertEquals(destino, "5547988887777");
  } finally {
    relogio.restore();
    globalThis.fetch = original;
  }
});
