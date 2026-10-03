import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { caixaTools, dataDita, escolherPorNome, formasDoDocumento, resolverPedidoDeCaixa, resumirPedido } from "./caixa.ts";

/* O assessor pelo WhatsApp: "gastei 50 em dinheiro com almoço", "paguei 100 pro Roberto".
   O que se fixa aqui é a parte que interpreta a fala — nome, data, sócio, categoria — e o
   que vai para a confirmação. O dinheiro em si é das funções do banco. */

Deno.test("escolherPorNome: igual, depois todas as palavras; dúvida vira pergunta", () => {
  const lista = [
    { id: "1", nome: "Roberto Carlos da Silva" },
    { id: "2", nome: "Mickael Souza" },
    { id: "3", nome: "Roberta Lima" },
    { id: "4", nome: "João Silva" }, { id: "5", nome: "João Pedro" },
  ];
  assertEquals(escolherPorNome("roberto", lista), { achado: lista[0] });
  assertEquals(escolherPorNome("Mickael Souza", lista), { achado: lista[1] });
  assertEquals("ambiguo" in escolherPorNome("joão", lista), true);
  assertEquals(escolherPorNome("Fulano", lista), { nenhum: true });
});

Deno.test("dataDita: hoje, ontem, dd/mm e ISO; o resto não passa", () => {
  const agora = new Date("2026-09-25T15:00:00Z");
  assertEquals(dataDita("hoje", agora), "2026-09-25");
  assertEquals(dataDita("ontem", agora), "2026-09-24");
  assertEquals(dataDita("20/09", agora), "2026-09-20");
  assertEquals(dataDita("2026-09-01", agora), "2026-09-01");
  assertEquals(dataDita("semana passada", agora), null);
  assertEquals(dataDita(undefined, agora), null);
});

/** Banco falso: só o que o resolvedor lê. */
function admin(mudar?: (t: Record<string, any[]>) => void) {
  const tabelas: Record<string, any[]> = {
    payees: [
      { id: "p-rob", name: "Roberto Carlos da Silva", default_category: "Serviços de terceiros", kind: "diarista", document: "12345678901" },
      { id: "p-gus", name: "Gustavo Seberino da Silva", default_category: null, kind: "socio" },
    ],
    // Como no banco: fornecedor com o CNPJ na máscara, favorecido só com os dígitos.
    suppliers: [{ id: "f-premel", name: "PREMEL MATERIAIS ELETRICOS", trade_name: "Premel", cnpj_cpf: "12.345.678/0001-90" }],
    clients: [{ id: "c-mp", name: "MP MOTOR HOMES", cpf_cnpj: "98.765.432/0001-10" }],
    financial_categories: [
      { name: "Alimentação de campo" }, { name: "Peças e materiais" }, { name: "Serviços de terceiros" }, { name: "Outras despesas" },
    ],
    service_orders: [{ id: "os60", service_order_number: "OS-00060" }],
  };
  mudar?.(tabelas);
  const consulta = (nome: string) => {
    const q: any = {
      _rows: tabelas[nome] ?? [],
      select() { return q; }, eq() { return q; }, limit() { return q; },
      in(coluna: string, valores: string[]) {
        q._rows = q._rows.filter((r: any) => valores.includes(r[coluna]));
        return q;
      },
      ilike(_c: string, padrao: string) {
        const alvo = padrao.replaceAll("%", "");
        q._rows = q._rows.filter((r: any) => String(r.service_order_number ?? "").includes(alvo));
        return q;
      },
      then(res: any) { return Promise.resolve({ data: q._rows, error: null }).then(res); },
    };
    return q;
  };
  return { from: consulta };
}
const ctx = (rpc?: (n: string, a: any) => any, mudar?: (t: Record<string, any[]>) => void) => ({
  sb: { rpc: rpc ?? (() => Promise.resolve({ data: { ok: true }, error: null })) },
  admin: admin(mudar), userId: "u-dono", userRole: "admin" as const, jwt: "", appOrigin: "", settings: {},
});

Deno.test("paguei 100 em dinheiro pro Roberto: favorecido e a categoria padrão dele", async () => {
  const p = await resolverPedidoDeCaixa(ctx() as never, { valor: 100, descricao: "diária", quem: "roberto" });
  if ("error" in p) throw new Error(p.error);
  assertEquals(p.pessoa?.id, "p-rob");
  assertEquals(p.categoria, "Serviços de terceiros");
  assertEquals(p.pagoPor, "caixa");
});

Deno.test("do meu bolso: o único sócio é achado sozinho e vira reembolso", async () => {
  let chamada: any = null;
  const c = ctx((n, a) => { chamada = { n, a }; return Promise.resolve({ data: { ok: true }, error: null }); });
  await caixaTools.find((t) => t.name === "lancar_no_caixa")!.execute(
    { valor: 80, descricao: "peça no balcão", categoria: "peças", pago_por: "bolso_do_socio", os: "60" }, c as never);
  assertEquals(chamada.n, "lancar_no_caixa");
  assertEquals(chamada.a.p_pago_por, "socio");
  assertEquals(chamada.a.p_socio_id, "p-gus");
  assertEquals(chamada.a.p_categoria, "Peças e materiais");
  assertEquals(chamada.a.p_os_id, "os60");
  assertEquals(chamada.a.p_autor, "u-dono");
});

Deno.test("recebimento sem cliente e categoria inexistente viram pergunta, sem gravar", async () => {
  let gravou = false;
  const c = ctx(() => { gravou = true; return Promise.resolve({ data: {}, error: null }); });
  const t = caixaTools.find((x) => x.name === "lancar_no_caixa")!;
  const r1 = await t.execute({ sentido: "recebimento", valor: 300, descricao: "serviço" }, c as never) as { error?: string };
  const r2 = await t.execute({ valor: 50, descricao: "almoço", categoria: "festa" }, c as never) as { error?: string };
  assertStringIncludes(String(r1.error), "de quem veio");
  assertStringIncludes(String(r2.error), "não existe");
  assertEquals(gravou, false);
});

Deno.test("a confirmação mostra o pedido resolvido", async () => {
  // Intl separa "R$" do número com espaço não separável; o que importa é o conteúdo.
  const txt = String(await resumirPedido(ctx() as never, "lancar_no_caixa", { valor: 100, descricao: "diária", quem: "roberto" })).replace(/\u00a0/g, " ");
  assertStringIncludes(String(txt), "R$ 100,00");
  assertStringIncludes(String(txt), "Serviços de terceiros");
  assertStringIncludes(String(txt), "Roberto Carlos da Silva");
  assertStringIncludes(String(txt), "Caixa (dinheiro)");
});

Deno.test("tudo que grava pede confirmação; consulta não", () => {
  for (const n of ["lancar_no_caixa", "ajustar_saldo_do_caixa", "anotar_transacao_do_banco"]) {
    assertEquals(caixaTools.find((t) => t.name === n)!.risk !== "low", true, n);
  }
  assertEquals(caixaTools.find((t) => t.name === "gastos_por_categoria")!.risk, "low");
});

Deno.test("gastei 50 em dinheiro com almoço: a categoria vem do texto, e a confirmação diz de onde", async () => {
  // Teste do dono em 25/09/2026: o almoço caía em "Outras despesas" e ele teve de corrigir.
  const p = await resolverPedidoDeCaixa(ctx() as never, { valor: 50, descricao: "almoço da equipe" });
  if ("error" in p) throw new Error(p.error);
  assertEquals(p.categoria, "Alimentação de campo");
  assertStringIncludes(String(p.origemDaCategoria), "pelo texto");
  const txt = String(await resumirPedido(ctx() as never, "lancar_no_caixa", { valor: 50, descricao: "almoço da equipe" }));
  assertStringIncludes(txt, "Alimentação de campo");
  assertStringIncludes(txt, "pelo texto");
});

Deno.test("a padrão de quem recebeu ainda vem antes do texto", async () => {
  const p = await resolverPedidoDeCaixa(ctx() as never, { valor: 100, descricao: "almoço", quem: "roberto" });
  if ("error" in p) throw new Error(p.error);
  assertEquals(p.categoria, "Serviços de terceiros");
});

Deno.test("sem pista no texto, a confirmação avisa que vai em Outras despesas", async () => {
  const txt = String(await resumirPedido(ctx() as never, "lancar_no_caixa", { valor: 30, descricao: "coisa diversa" }));
  assertStringIncludes(txt, "Outras despesas");
  assertStringIncludes(txt, "não reconheci");
});

Deno.test("formasDoDocumento: só dígitos e a máscara padrão; tamanho errado não passa", () => {
  assertEquals(formasDoDocumento("12.345.678/0001-90"), ["12345678000190", "12.345.678/0001-90"]);
  assertEquals(formasDoDocumento("123.456.789-01"), ["12345678901", "123.456.789-01"]);
  assertEquals(formasDoDocumento("1234"), null);
  assertEquals(formasDoDocumento(undefined), null);
});

Deno.test("Pix pro CNPJ, sem dizer o nome: o CNPJ acha o fornecedor (documento igual identifica)", async () => {
  let chamada: any = null;
  const c = ctx((n, a) => { chamada = { n, a }; return Promise.resolve({ data: { ok: true }, error: null }); });
  const args = { valor: 1500, data: "26/09", documento: "12345678000190", categoria: "peças", descricao: "Pix — cabos" };
  const txt = String(await resumirPedido(c as never, "anotar_transacao_do_banco", args));
  assertStringIncludes(txt, "PREMEL MATERIAIS ELETRICOS (fornecedor), pelo CPF/CNPJ");
  assertEquals(txt.includes("Sem dizer para quem foi"), false);
  await caixaTools.find((t) => t.name === "anotar_transacao_do_banco")!.execute(args, c as never);
  assertEquals(chamada.n, "anotar_transacao");
  assertEquals([chamada.a.p_fornecedor_id, chamada.a.p_nome, chamada.a.p_documento], ["f-premel", "PREMEL MATERIAIS ELETRICOS", "12345678000190"]);
  assertEquals(chamada.a.p_categoria, "Peças e materiais");
});

Deno.test("CPF de favorecido gravado só com dígitos também é achado, com a categoria padrão dele", async () => {
  let chamada: any = null;
  const c = ctx((n, a) => { chamada = { n, a }; return Promise.resolve({ data: { ok: true }, error: null }); });
  await caixaTools.find((t) => t.name === "anotar_transacao_do_banco")!.execute({ valor: 200, documento: "123.456.789-01" }, c as never);
  assertEquals([chamada.a.p_favorecido_id, chamada.a.p_categoria], ["p-rob", "Serviços de terceiros"]);
});

Deno.test("documento sem cadastro: a confirmação avisa que a transação com nome não entra classificada", async () => {
  const txt = String(await resumirPedido(ctx() as never, "anotar_transacao_do_banco",
    { valor: 90, documento: "11.111.111/0001-11", categoria: "peças" }));
  assertStringIncludes(txt, "Nenhum cadastro com esse CPF/CNPJ");
  let chamada: any = null;
  const c = ctx((n, a) => { chamada = { n, a }; return Promise.resolve({ data: { ok: true }, error: null }); });
  await caixaTools.find((t) => t.name === "anotar_transacao_do_banco")!.execute({ valor: 90, documento: "11111111000111", categoria: "peças" }, c as never);
  assertEquals([chamada.a.p_fornecedor_id, chamada.a.p_favorecido_id, chamada.a.p_documento], [null, null, "11111111000111"]);
});

Deno.test("dois cadastros com o mesmo documento: pergunta qual, sem gravar", async () => {
  let gravou = false;
  const doisIguais = (t: Record<string, any[]>) => { t.payees.push({ id: "p-premel", name: "Premel (favorecido)", document: "12345678000190" }); };
  const c = ctx(() => { gravou = true; return Promise.resolve({ data: {}, error: null }); }, doisIguais);
  const args = { valor: 1500, documento: "12345678000190", categoria: "peças" };
  assertStringIncludes(String(await resumirPedido(c as never, "anotar_transacao_do_banco", args)), "Mais de um cadastro");
  const r = await caixaTools.find((t) => t.name === "anotar_transacao_do_banco")!.execute(args, c as never) as { error?: string };
  assertStringIncludes(String(r.error), "Mais de um cadastro");
  assertEquals(gravou, false);
});

Deno.test("entrada com CNPJ procura só cliente", async () => {
  let chamada: any = null;
  const c = ctx((n, a) => { chamada = { n, a }; return Promise.resolve({ data: { ok: true }, error: null }); });
  await caixaTools.find((x) => x.name === "anotar_transacao_do_banco")!.execute({ sentido: "entrada", valor: 300, documento: "98765432000110", os: "60" }, c as never);
  assertEquals(chamada.a.p_cliente_id, "c-mp");
});

Deno.test("nome de um e documento de outro: pergunta qual vale, sem gravar (regra P1; revisão de 27/09)", async () => {
  // Antes passava: o documento dito toma o lugar do cadastro na identidade da anotação, e o Pix
  // da loja (CNPJ 12.345.678/0001-90) entraria como do Roberto (CPF 123.456.789-01).
  let gravou = false;
  const c = ctx(() => { gravou = true; return Promise.resolve({ data: {}, error: null }); });
  const args = { valor: 100, quem: "roberto", documento: "12345678000190", categoria: "peças" };
  const txt = String(await resumirPedido(c as never, "anotar_transacao_do_banco", args));
  assertStringIncludes(txt, "O documento 12.345.678/0001-90 não é o de Roberto Carlos da Silva (no cadastro: 123.456.789-01)");
  const r = await caixaTools.find((x) => x.name === "anotar_transacao_do_banco")!.execute(args, c as never) as { error?: string };
  // O caminho sugerido tem de levar a algum lugar: outra pessoa pagando em nome dele é caso de tela.
  assertStringIncludes(String(r.error), "classifique pela tela do Extrato quando a transação chegar");
  assertEquals(gravou, false);
});

Deno.test("nome e documento da mesma pessoa passam; cadastro sem documento avisa na confirmação", async () => {
  let chamada: any = null;
  const c = ctx((n, a) => { chamada = { n, a }; return Promise.resolve({ data: { ok: true }, error: null }); });
  const t = caixaTools.find((x) => x.name === "anotar_transacao_do_banco")!;
  await t.execute({ valor: 100, quem: "roberto", documento: "123.456.789-01" }, c as never);
  assertEquals([chamada.a.p_favorecido_id, chamada.a.p_documento], ["p-rob", "123.456.789-01"]);
  // O sócio não tem CPF no cadastro: não dá para conferir — a confirmação diz, e o "sim" decide.
  const txt = String(await resumirPedido(c as never, "anotar_transacao_do_banco", { valor: 100, quem: "gustavo", documento: "11122233344", categoria: "peças" }));
  assertStringIncludes(txt, "Gustavo Seberino da Silva não tem CPF/CNPJ no cadastro: não dá para conferir que 111.222.333-44 é dele");
});

Deno.test("documentoContradiz: CPF diferente ou CNPJ de outra raiz; filial é a mesma empresa; faltando um, não contradiz", async () => {
  const { documentoContradiz } = await import("./caixa.ts");
  assertEquals(documentoContradiz("12.345.678/0001-90", "12345678000271"), false); // filial
  assertEquals(documentoContradiz("12.345.678/0001-90", "98765432000110"), true);
  assertEquals(documentoContradiz("12345678901", "12345678000190"), true);         // CPF × CNPJ
  assertEquals(documentoContradiz("123.456.789-01", "12345678901"), false);
  assertEquals(documentoContradiz("1234567890", "01234567890"), false);           // zero comido
  assertEquals(documentoContradiz("12345678901", null), false);
});

// ── gastos_por_categoria ─────────────────────────────────────────────────────────────────
// 02/10/2026: o dono perguntou "quanto foi o gasto com combustível em setembro?" e ouviu R$ 0 —
// e depois "não há nenhuma despesa lançada em setembro". A consulta pedia `payees(name)` de
// payables (duas chaves para payees), o banco recusava e a ferramenta tratava o erro como
// "nada". O banco falso antigo daqui ignorava filtros e nunca falhava: por isso passava.
// Este filtra de verdade e sabe falhar.

/** Banco falso que aplica os filtros usados pela ferramenta e pode recusar uma tabela. */
function bancoDeGastos(tabelas: Record<string, any[]>, recusar: string[] = []) {
  const from = (nome: string) => {
    let linhas = [...(tabelas[nome] ?? [])];
    const q: any = {
      select: () => q, order: () => q, limit: () => q,
      eq: (c: string, v: unknown) => { linhas = linhas.filter((r) => r[c] === v); return q; },
      neq: (c: string, v: unknown) => { linhas = linhas.filter((r) => r[c] !== v); return q; },
      gte: (c: string, v: string) => { linhas = linhas.filter((r) => String(r[c]) >= v); return q; },
      lte: (c: string, v: string) => { linhas = linhas.filter((r) => String(r[c]) <= v); return q; },
      is: (c: string, v: unknown) => { linhas = linhas.filter((r) => (r[c] ?? null) === v); return q; },
      in: (c: string, vs: unknown[]) => { linhas = linhas.filter((r) => vs.includes(r[c])); return q; },
      range: (a: number, b: number) => { linhas = linhas.slice(a, b + 1); return q; },
      then: (res: any) => Promise.resolve(recusar.includes(nome)
        ? { data: null, error: { message: "Could not embed because more than one relationship was found for 'payables' and 'payees'", code: "PGRST201" } }
        : { data: linhas, error: null }).then(res),
    };
    return q;
  };
  return { from, rpc: () => Promise.resolve({ data: null, error: null }) };
}

const PLANO_DESPESA = [
  { name: "Combustível e deslocamento", type: "payable", dre_group: "custo_direto" },
  { name: "Veículo e Combustível", type: "payable", dre_group: null },
  { name: "Alimentação de campo", type: "payable", dre_group: "custo_direto" },
  { name: "Impostos e taxas", type: "payable", dre_group: "financeiro" },
  { name: "Pagamento de fatura de cartão", type: "payable", dre_group: "nao_operacional" },
];

/** Setembro/2026 como estava no banco no dia da pergunta (reduzido). */
function setembro() {
  return {
    financial_categories: PLANO_DESPESA,
    finance_rules: [],
    payables: [
      { id: "u", status: "paid", issue_date: "2026-09-01", amount: 16.9, expense_category: "Combustível e deslocamento", description: "Uber Uber *Trip", supplier_name: "Uber", bank_transactions: { payee_mcc: "4121", merchant_name: "Uber" } },
      { id: "c", status: "paid", issue_date: "2026-09-26", amount: 100, expense_category: "Combustível e deslocamento", description: "Combustível", supplier_name: "Combustível", bank_transactions: null },
      { id: "a", status: "paid", issue_date: "2026-09-07", amount: 31.99, expense_category: "Alimentação de campo", description: "POSTO PAULINHO", supplier_name: "POSTO PAULINHO", bank_transactions: { payee_mcc: "5541", merchant_name: "POSTO PAULINHO" } },
      { id: "f", status: "paid", issue_date: "2026-09-10", amount: 900, expense_category: "Pagamento de fatura de cartão", description: "Fatura C6", supplier_name: "C6", bank_transactions: null },
      { id: "x", status: "cancelled", issue_date: "2026-09-12", amount: 5000, expense_category: "Combustível e deslocamento", description: "cancelado", supplier_name: null, bank_transactions: null },
      { id: "ago", status: "paid", issue_date: "2026-08-20", amount: 80, expense_category: "Combustível e deslocamento", description: "Combustível", supplier_name: null, bank_transactions: null },
    ],
    bank_transactions: [
      // Compras no posto ainda pendentes no cartão: não viraram lançamento nem estão na fila.
      { id: "t1", transaction_type: "debit", dismissed_kind: null, reconciled: false, transaction_date: "2026-09-22", amount: 70.98, merchant_name: "POSTO PAULINHO", payee_mcc: "5541", tx_status: "PENDING" },
      { id: "t2", transaction_type: "debit", dismissed_kind: null, reconciled: false, transaction_date: "2026-09-28", amount: 40.34, merchant_name: "POSTO PAULINHO", payee_mcc: "5541", tx_status: "PENDING" },
      { id: "t3", transaction_type: "debit", dismissed_kind: null, reconciled: false, transaction_date: "2026-09-19", amount: 27.98, merchant_name: null, counterparty_name: "Posto Paulinho", payee_mcc: null, tx_status: "PENDING" },
      // Outras saídas sem lançamento: não são combustível.
      { id: "t4", transaction_type: "debit", dismissed_kind: null, reconciled: false, transaction_date: "2026-09-20", amount: 466.75, merchant_name: "ANTHROPIC* CLAUDE SUB", payee_mcc: "5734", tx_status: "PENDING" },
      { id: "t5", transaction_type: "debit", dismissed_kind: null, reconciled: false, transaction_date: "2026-09-30", amount: 100, description: "PGTO FAT CARTAO C6", payee_mcc: null, tx_status: "POSTED" },
      // Já lançada, descartada e de outro mês: fora.
      { id: "t6", transaction_type: "debit", dismissed_kind: null, reconciled: false, transaction_date: "2026-09-26", amount: 100, description: "Combustível", payee_mcc: "5541", tx_status: "POSTED" },
      { id: "t7", transaction_type: "debit", dismissed_kind: "duplicata", reconciled: false, transaction_date: "2026-09-23", amount: 19.99, merchant_name: "POSTO PAULINHO", payee_mcc: "5541", tx_status: "PENDING" },
      { id: "t8", transaction_type: "debit", dismissed_kind: null, reconciled: false, transaction_date: "2026-10-01", amount: 50, merchant_name: "POSTO PAULINHO", payee_mcc: "5541", tx_status: "PENDING" },
    ],
    // A linha t6 é a do lançamento "Combustível" de R$ 100.
    payables_ligadas: [{ bank_transaction_id: "t6", status: "paid" }],
    finance_review_queue: [{ bank_transaction_id: "t5", kind: "categorize", suggested_category: "Pagamento de fatura de cartão", status: "pending" }],
  };
}

/** O banco falso lê `payables` duas vezes: a lista do mês e a ligação com o extrato. */
function ctxDeSetembro(recusar: string[] = []) {
  const t = setembro();
  const base = bancoDeGastos({ ...t }, recusar);
  const ligadas = bancoDeGastos({ payables: t.payables_ligadas });
  const sb = {
    ...base,
    from: (nome: string) => {
      if (nome !== "payables") return base.from(nome);
      // A consulta de ligação filtra por bank_transaction_id com .in(): é a única que usa .in em payables.
      const lista = base.from(nome);
      const ligacao = ligadas.from(nome);
      const q: any = new Proxy({}, {
        get(_, prop) {
          if (prop === "in") return (c: string, vs: unknown[]) => ligacao.in(c, vs);
          return (...a: unknown[]) => { const r = (lista as any)[prop](...a); return r === lista ? q : r; };
        },
      });
      return q;
    },
  };
  return { ...ctx(), sb, admin: bancoDeGastos({ finance_rules: [] }) };
}

const gastos = () => caixaTools.find((t) => t.name === "gastos_por_categoria")!;

Deno.test("gastos_por_categoria: combustível em setembro — lançado, ainda não lançado e lançado em outra categoria", async () => {
  const r = await gastos().execute({ categoria: "combustível", mes: 9, ano: 2026 }, ctxDeSetembro() as never) as any;
  assertEquals(r.error, undefined);
  assertEquals(r.periodo, "09/2026");
  assertStringIncludes(r.como_entendi, "Combustível e deslocamento");
  assertEquals(r.lancado.total, 116.9);          // Uber 16,90 + combustível 100 (o cancelado não entra)
  assertEquals(r.lancado.quantidade, 2);
  assertEquals(r.nao_lancado.total, 139.3);       // 70,98 + 40,34 + 27,98: pendentes no posto
  assertEquals(r.nao_lancado.quantidade, 3);
  assertEquals(r.nao_lancado.pendentes_no_cartao, 3);
  assertEquals(r.total_com_nao_lancado, 256.2);
  assertEquals(r.em_outra_categoria.total, 31.99); // posto lançado como alimentação, fora do total
  assertEquals(r.mes_anterior_lancado, 80);
});

Deno.test("gastos_por_categoria: 'gasolina' e 'posto' dão o mesmo resultado que 'combustível'", async () => {
  for (const pedido of ["gasolina", "posto"]) {
    const r = await gastos().execute({ categoria: pedido, mes: 9, ano: 2026 }, ctxDeSetembro() as never) as any;
    assertEquals(r.lancado.total, 116.9, pedido);
    assertEquals(r.nao_lancado.total, 139.3, pedido);
  }
});

Deno.test("gastos_por_categoria: busca pelo estabelecimento ('Posto Paulinho')", async () => {
  const r = await gastos().execute({ busca: "posto paulinho", mes: 9, ano: 2026 }, ctxDeSetembro() as never) as any;
  assertEquals(r.lancado.total, 31.99);
  assertEquals(r.nao_lancado.total, 139.3);
});

Deno.test("gastos_por_categoria: o mês todo — fatura fica fora do total, e o não lançado aparece", async () => {
  const r = await gastos().execute({ mes: 9, ano: 2026 }, ctxDeSetembro() as never) as any;
  assertEquals(r.lancado.total, 148.89);          // 16,90 + 100 + 31,99; a fatura de 900 fica fora
  assertEquals(r.fora_do_resultado, 900);
  // Sem lançamento: posto (139,30) + assinatura (466,75); a fatura de 100 na fila fica fora.
  assertEquals(r.nao_lancado.total, 606.05);
});

Deno.test("gastos_por_categoria: consulta recusada vira erro dito — nunca R$ 0", async () => {
  const r = await gastos().execute({ categoria: "combustível", mes: 9, ano: 2026 }, ctxDeSetembro(["payables"]) as never) as any;
  assertStringIncludes(r.error, "Não consegui ler as contas a pagar");
  assertStringIncludes(r.error, "não que não houve gasto");
  assertEquals(r.lancado, undefined);
});

Deno.test("gastos_por_categoria: nome que não é categoria vira busca pelo nome", async () => {
  const r = await gastos().execute({ categoria: "Paulinho", mes: 9, ano: 2026 }, ctxDeSetembro() as never) as any;
  assertStringIncludes(r.como_entendi, "procurei pelo nome");
  assertEquals(r.nao_lancado.total, 139.3);
});
