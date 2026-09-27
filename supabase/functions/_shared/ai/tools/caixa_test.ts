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

Deno.test("gastos_por_categoria: fatura, empréstimo e transferência ficam fora do total", async () => {
  // A compra no cartão já foi contada quando aconteceu; somar a fatura contava duas vezes.
  const linhas: Record<string, any[]> = {
    payables: [
      { amount: 100, expense_category: "Alimentação de campo", supplier_name: "Padaria" },
      { amount: 900, expense_category: "Pagamento de fatura de cartão", supplier_name: "C6" },
    ],
    financial_categories: [
      { name: "Alimentação de campo", dre_group: "custo_direto" },
      { name: "Pagamento de fatura de cartão", dre_group: "nao_operacional" },
    ],
  };
  const from = (t: string) => {
    const q: any = { select: () => q, neq: () => q, gte: () => q, lte: () => q, limit: () => q, eq: () => q,
      then: (res: any) => Promise.resolve({ data: linhas[t] ?? [], error: null }).then(res) };
    return q;
  };
  const c = { ...ctx(), sb: { from, rpc: () => Promise.resolve({ data: null, error: null }) } };
  const r = await caixaTools.find((t) => t.name === "gastos_por_categoria")!.execute({ mes: 9, ano: 2026 }, c as never) as any;
  assertEquals(r.total, 100);
  assertEquals(r.fora_do_resultado, [{ categoria: "Pagamento de fatura de cartão", valor: 900 }]);
  const soFatura = await caixaTools.find((t) => t.name === "gastos_por_categoria")!.execute({ mes: 9, ano: 2026, categoria: "fatura" }, c as never) as any;
  assertEquals(soFatura.total, 900);
});
