// O extrato pelo assistente com CPF de terceiro (leva 8, revisão de 23/10/2026 — LGPD).
//
// O que se prova aqui:
//   - listar_transacoes_pendentes e sugerir_conciliacao: só administrador e financeiro, com o cargo conferido DENTRO do
//     execute (no WhatsApp e no Claude Max o banco é a chave de serviço, que passa por cima da RLS) — vendedor nem lê;
//   - o CPF sai mascarado (***.456.789-**) no campo, no nome e no histórico que o banco escreve com ele, e no motivo da
//     conciliação ("Quem enviou (CPF/CNPJ …)"); o CNPJ sai inteiro;
//   - regra por documento (criar_regra_financeira) com bank_transaction_id: o documento é o da LINHA do banco, lido pelo
//     id — nunca o texto mascarado que o modelo viu; mascarado sem a linha é recusado; a resposta volta mascarada;
//   - listar_regras_financeiras mascara o CPF da regra por documento; listar_propostas_de_lancamento, o CPF que o título
//     herda do nome do banco.
// Rodar com:
//   deno test --allow-all --no-lock supabase/functions/_shared/ai/tools/extrato-lgpd_test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bankingTools } from "./banking.ts";
import { financeRulesTools } from "./finance-rules.ts";
import { mascararCpfNoTexto } from "./financeiro-comum.ts";
import { lancamentoTools } from "./lancamentos.ts";
import { caixaTools } from "./caixa.ts";
import { relatorioTools } from "./relatorios.ts";
import { rotuloDoPagamento, type PagamentoLido } from "./estorno.ts";
import { fechamentoTools } from "./fechamento.ts";
import { financialTools } from "./financial.ts";
import { pixEsperandoNoExtrato } from "./pix-esperando.ts";

// deno-lint-ignore no-explicit-any
type Qualquer = any;

const listar = bankingTools.find((t) => t.name === "listar_transacoes_pendentes")!;
const sugerir = bankingTools.find((t) => t.name === "sugerir_conciliacao")!;
const criarRegra = financeRulesTools.find((t) => t.name === "criar_regra_financeira")!;
const listarRegras = financeRulesTools.find((t) => t.name === "listar_regras_financeiras")!;

const LINHA_CREDITO = "44444444-4444-4444-8444-444444444444";
const LINHA_DEBITO = "55555555-5555-4555-8555-555555555555";
const LINHA_SEM_DOC = "66666666-6666-4666-8666-666666666666";

const EXTRATO = [
  {
    id: LINHA_CREDITO, transaction_date: "2026-10-12", description: "12345678901-MARIA SOUZA PIX", amount: 1500, transaction_type: "credit",
    counterparty_name: "12345678901-MARIA SOUZA", counterparty_document: "123.456.789-01", pix_end_to_end_id: null, reconciled: false,
  },
  {
    id: LINHA_DEBITO, transaction_date: "2026-10-13", description: "PIX ENVIADO", amount: -350, transaction_type: "debit",
    counterparty_name: "JOAO PRESTADOR 98765432100", counterparty_document: "12345678000199", pix_end_to_end_id: null, reconciled: false,
  },
  {
    id: LINHA_SEM_DOC, transaction_date: "2026-10-14", description: "TARIFA", amount: -5, transaction_type: "debit",
    counterparty_name: null, counterparty_document: null, pix_end_to_end_id: null, reconciled: false,
  },
];

/**
 * Banco de mentira: filtra por eq/in, devolve maybeSingle/then (com count), guarda inserts e quantas vezes cada tabela
 * foi lida. `falham`: tabelas cuja leitura devolve erro. `linhas` por tabela.
 */
function bancoFalso(linhas: Record<string, Qualquer[]> = {}, opcoes: { falham?: string[] } = {}) {
  const lidas: string[] = [];
  const inseridas: Qualquer[] = [];
  return {
    lidas,
    inseridas,
    from(tabela: string) {
      lidas.push(tabela);
      let rows = [...(linhas[tabela] ?? [])];
      const erro = (opcoes.falham ?? []).includes(tabela) ? { message: `falha em ${tabela}` } : null;
      const q: Qualquer = {};
      for (const m of ["select", "order", "limit", "range", "neq", "is", "not", "gte", "lte", "gt", "lt", "or", "ilike"]) q[m] = () => q;
      q.eq = (c: string, v: unknown) => { rows = rows.filter((l) => l[c] === undefined || l[c] === v); return q; };
      q.in = (c: string, vs: unknown[]) => { rows = rows.filter((l) => l[c] === undefined || vs.includes(l[c])); return q; };
      q.maybeSingle = () => Promise.resolve(erro ? { data: null, error: erro } : { data: rows[0] ?? null, error: null });
      q.then = (ok: Qualquer, ko: Qualquer) =>
        Promise.resolve(erro ? { data: null, error: erro, count: null } : { data: rows, error: null, count: rows.length }).then(ok, ko);
      q.insert = (linha: Qualquer) => {
        inseridas.push({ tabela, linha });
        return { select: () => ({ single: () => Promise.resolve({ data: { id: "nova" }, error: null }) }) };
      };
      q.update = () => ({ eq: () => Promise.resolve({ error: null }), in: () => Promise.resolve({ error: null }) });
      return q;
    },
  };
}

const ctxDe = (sb: unknown, userRole = "admin") =>
  ({ sb, admin: sb, userId: "u-dono", userRole, jwt: "jwt", appOrigin: "", settings: {} }) as never;

/** fetch de mentira para a finance-review (reclassify). */
async function semFinanceReview<T>(f: () => Promise<T>): Promise<T> {
  Deno.env.set("SUPABASE_URL", "https://exemplo.supabase.co");
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ ok: true, atualizadas: 0 }), { status: 200 }))) as typeof fetch;
  try {
    return await f();
  } finally {
    globalThis.fetch = original;
  }
}

const temCpfInteiro = (r: unknown) => /12345678901|123\.456\.789-01|98765432100|987\.654\.321-00/.test(JSON.stringify(r));

// ─── a máscara ──────────────────────────────────────────────────────────────────────────────────────────
Deno.test("mascararCpfNoTexto: CPF solto ou formatado vira ***.456.789-**; CNPJ, valor, data e o resto ficam", () => {
  assertEquals(mascararCpfNoTexto("Quem enviou (CPF/CNPJ 123.456.789-01) não é ACRISIO — confira se foi um terceiro pagando"),
    "Quem enviou (CPF/CNPJ ***.456.789-**) não é ACRISIO — confira se foi um terceiro pagando");
  assertEquals(mascararCpfNoTexto("12345678901-MARIA SOUZA"), "***.456.789-**-MARIA SOUZA");
  assertEquals(mascararCpfNoTexto("JOAO PRESTADOR 98765432100"), "JOAO PRESTADOR ***.654.321-**");
  for (const fica of ["12.345.678/0001-99", "12345678000199", "R$ 1.500,00 em 12/10/2026", "PIX 2026-10-12", "MEI 12.345.678 JOAO"]) {
    assertEquals(mascararCpfNoTexto(fica), fica);
  }
  assertEquals(mascararCpfNoTexto(null), null);
  assertEquals(mascararCpfNoTexto(undefined), undefined);
});

// Revisão de 23/10/2026, item 3: a máscara mora em _shared/banking/contraparte.ts (nomeSemCpf), para a tela usar no
// recibo; o assistente continua chamando mascararCpfNoTexto — que é a MESMA função (paridade por identidade e por saída).
Deno.test("paridade: mascararCpfNoTexto é o nomeSemCpf do contraparte (uma fonte só, a tela e o assistente)", async () => {
  const contraparte = await import("../../banking/contraparte.ts");
  assertEquals(mascararCpfNoTexto, contraparte.nomeSemCpf);
  for (const t of [
    "12345678901-MARIA SOUZA", "JOAO 987.654.321-00", "12345678901 98765432100", "12.345.678/0001-99", "1234567890123", "", null, undefined,
  ]) {
    assertEquals(mascararCpfNoTexto(t), contraparte.nomeSemCpf(t), String(t));
  }
  // Sem lookbehind no módulo da tela: Safari antigo (iOS < 16.4) recusaria o arquivo inteiro.
  const fonte = await Deno.readTextFile(new URL("../../banking/contraparte.ts", import.meta.url));
  assertEquals(/\(\?<[!=]/.test(fonte), false, "contraparte.ts não pode ter lookbehind");
});

// ─── listar_transacoes_pendentes ────────────────────────────────────────────────────────────────────────
Deno.test("listar_transacoes_pendentes: CPF mascarado no campo, no nome e no histórico; CNPJ inteiro", async () => {
  const r = await listar.execute({}, ctxDe(bancoFalso({ bank_transactions: EXTRATO }))) as Qualquer;
  assertEquals(r.total, 3);
  const [credito, debito, tarifa] = r.transacoes;
  assertEquals(credito.counterparty_document, "***.456.789-**");
  assertEquals(credito.counterparty_name, "***.456.789-**-MARIA SOUZA");
  assertEquals(credito.description, "***.456.789-**-MARIA SOUZA PIX");
  assertEquals(credito.id, LINHA_CREDITO, "o id da linha continua: é por ele que a regra lê o documento");
  assertEquals(debito.counterparty_document, "12.345.678/0001-99");
  assertEquals(debito.counterparty_name, "JOAO PRESTADOR ***.654.321-**");
  assertEquals(tarifa.counterparty_document, null);
  assertEquals(temCpfInteiro(r), false);
  assert(r.dica.includes("bank_transaction_id"), r.dica);
});

Deno.test("listar_transacoes_pendentes e sugerir_conciliacao: só admin e financeiro — vendedor nem chega a ler o extrato", async () => {
  for (const t of [listar, sugerir]) {
    assertEquals(t.roles, ["admin", "financial"], t.name);
    for (const cargo of ["seller", "external_seller", "technician"]) {
      const banco = bancoFalso({ bank_transactions: EXTRATO });
      const r = await t.execute({}, ctxDe(banco, cargo)) as Qualquer;
      assertEquals(typeof r.error, "string", `${t.name} / ${cargo}`);
      assertEquals(banco.lidas, [], `${t.name} / ${cargo}: leu o banco`);
    }
  }
  const doFinanceiro = await listar.execute({}, ctxDe(bancoFalso({ bank_transactions: EXTRATO }), "financial")) as Qualquer;
  assertEquals(doFinanceiro.total, 3);
});

Deno.test("conciliar_transacao: só admin e financeiro (dono, 23/10/2026) — vendedor é recusado antes de ler o extrato", async () => {
  const conciliar = bankingTools.find((t) => t.name === "conciliar_transacao")!;
  assertEquals(conciliar.roles, ["admin", "financial"]);
  for (const cargo of ["seller", "external_seller", "technician"]) {
    const banco = bancoFalso({ bank_transactions: EXTRATO });
    const r = await conciliar.execute({ transaction_id: "x", tipo: "receivable", alvo_id: "y" }, ctxDe(banco, cargo)) as Qualquer;
    assertEquals(typeof r.error, "string", cargo);
    assertEquals(banco.lidas, [], `${cargo}: leu o banco`);
  }
});

// ─── sugerir_conciliacao: o motivo de terceiro ──────────────────────────────────────────────────────────
Deno.test("sugerir_conciliacao: o motivo 'Quem enviou (CPF/CNPJ …)' sai com o CPF mascarado", async () => {
  // Uma entrada sem nome, de um CPF que não é o do cliente da conta em aberto do mesmo valor.
  const tx = { ...EXTRATO[0], counterparty_name: null, description: "PIX RECEBIDO" };
  const banco = bancoFalso({
    bank_transactions: [tx],
    receivables: [{
      id: "r1", description: "OS-00012 parcela 1", balance_amount: 1500, due_date: "2026-10-12", client_id: "c1", service_order_id: null,
      clients: { name: "ACRISIO", cpf_cnpj: "98765432100" }, service_orders: null,
    }],
  });
  const r = await sugerir.execute({}, ctxDe(banco)) as Qualquer;
  const motivos: string[] = r.itens.flatMap((i: Qualquer) => i.sugestoes.flatMap((s: Qualquer) => s.motivos));
  assert(motivos.some((m) => m.includes("Quem enviou (CPF/CNPJ ***.456.789-**)")), JSON.stringify(motivos));
  assertEquals(temCpfInteiro(r), false, JSON.stringify(r));
});

// ─── criar_regra_financeira por documento: o documento vem da LINHA ─────────────────────────────────────
const CATEGORIAS = [
  { name: "Mão de obra terceirizada", dre_group: "custo", type: "payable", active: true },
  { name: "Aporte de sócio", dre_group: "nao_operacional", type: "receivable", active: true },
];

Deno.test("regra por documento com bank_transaction_id: grava o documento da linha do banco e responde mascarado", async () => {
  // Saída: o modelo só viu o CPF mascarado na lista — e a regra nasce com o documento inteiro, lido pelo id.
  const extratoCpf = [{ ...EXTRATO[1], counterparty_document: "123.456.789-01" }];
  const banco = bancoFalso({ bank_transactions: extratoCpf, financial_categories: CATEGORIAS, finance_rules: [] });
  const r = await semFinanceReview(() => criarRegra.execute({
    reconhecer_por: "documento", valor_de_busca: "***.456.789-**", bank_transaction_id: LINHA_DEBITO, categoria: "Mão de obra terceirizada",
  }, ctxDe(banco))) as Qualquer;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(banco.inseridas[0].linha.match_type, "document");
  assertEquals(banco.inseridas[0].linha.match_value, "12345678901");
  assertEquals(banco.inseridas[0].linha.direction, "debit");
  assertEquals(r.regras_criadas[0].alvo, "***.456.789-**");
  assertEquals(temCpfInteiro(r), false, JSON.stringify(r));

  // Entrada ("o Pix do CPF do sócio é aporte") pelo mesmo caminho.
  const entrada = bancoFalso({ bank_transactions: EXTRATO, financial_categories: CATEGORIAS, finance_rules: [] });
  const e = await semFinanceReview(() => criarRegra.execute({
    sentido: "entrada", reconhecer_por: "documento", valor_de_busca: "***.456.789-**", bank_transaction_id: LINHA_CREDITO,
    categoria: "Aporte de sócio",
  }, ctxDe(entrada))) as Qualquer;
  assertEquals(e.ok, true, JSON.stringify(e));
  assertEquals(entrada.inseridas[0].linha.match_value, "12345678901");
  assertEquals(entrada.inseridas[0].linha.direction, "credit");
  assertEquals(e.documento, "***.456.789-**");
  assertEquals(temCpfInteiro(e), false, JSON.stringify(e));
});

Deno.test("regra por documento: mascarado sem a linha, linha sem documento, sentido trocado, documento divergente e leitura que falha recusam", async () => {
  const base = { reconhecer_por: "documento", categoria: "Mão de obra terceirizada" };
  const casos: Array<[string, Record<string, unknown>, ReturnType<typeof bancoFalso>]> = [
    ["mascarado", { ...base, valor_de_busca: "***.456.789-**" }, bancoFalso({ financial_categories: CATEGORIAS })],
    ["não informou o CPF/CNPJ", { ...base, valor_de_busca: "x", bank_transaction_id: LINHA_SEM_DOC }, bancoFalso({ bank_transactions: EXTRATO })],
    ["é uma ENTRADA", { ...base, valor_de_busca: "x", bank_transaction_id: LINHA_CREDITO }, bancoFalso({ bank_transactions: EXTRATO })],
    ["não é o desta linha", { ...base, valor_de_busca: "111.222.333-44", bank_transaction_id: LINHA_DEBITO }, bancoFalso({ bank_transactions: EXTRATO })],
    ["Não consegui ler a linha do extrato", { ...base, valor_de_busca: "x", bank_transaction_id: LINHA_DEBITO },
      bancoFalso({ bank_transactions: EXTRATO }, { falham: ["bank_transactions"] })],
    ["não encontrada", { ...base, valor_de_busca: "x", bank_transaction_id: "77777777-7777-4777-8777-777777777777" }, bancoFalso({ bank_transactions: EXTRATO })],
    ["uuid", { ...base, valor_de_busca: "x", bank_transaction_id: "linha 3" }, bancoFalso({ bank_transactions: EXTRATO })],
  ];
  for (const [esperado, args, banco] of casos) {
    const r = await semFinanceReview(() => criarRegra.execute(args, ctxDe(banco))) as Qualquer;
    assert(typeof r.error === "string" && r.error.includes(esperado), `${esperado}: ${JSON.stringify(r)}`);
    assertEquals(banco.inseridas, [], esperado);
  }
  // O documento que o usuário DITA continua valendo, como sempre (sem linha).
  const dito = bancoFalso({ financial_categories: CATEGORIAS, finance_rules: [] });
  const r = await semFinanceReview(() => criarRegra.execute({ ...base, valor_de_busca: "12345678901" }, ctxDe(dito))) as Qualquer;
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(dito.inseridas[0].linha.match_value, "12345678901");
  assertEquals(r.regras_criadas[0].alvo, "***.456.789-**");
  assert("bank_transaction_id" in (criarRegra.input_schema as Qualquer).properties);
});

// ─── o título da proposta nasce do nome do banco ────────────────────────────────────────────────────────
Deno.test("listar_propostas_de_lancamento: título que traz o CPF do nome do banco sai mascarado", async () => {
  const banco = bancoFalso({
    finance_review_queue: [{
      id: "e1", kind: "create_receivable", title: "Receita: 12345678901-MARIA SOUZA", status: "pending", suggested_amount: 1500,
      suggested_category: "Serviços prestados", suggested_date: "2026-10-12", confidence: 60, bank_transaction_id: LINHA_CREDITO,
      suggested_client_id: null, vinculo_sugerido: null, suggested_service_order_id: null, suggested_purchase_order_id: null,
      evidencia: { deQuemE: { documento: "12345678901", nome: "12345678901-MARIA SOUZA", candidatos: [] } },
    }],
  });
  const t = financeRulesTools.find((x) => x.name === "listar_propostas_de_lancamento")!;
  const r = await t.execute({}, ctxDe(banco)) as Qualquer;
  assertEquals(r.propostas[0].titulo, "Receita: ***.456.789-**-MARIA SOUZA");
  assertEquals(r.propostas[0].de_quem_e.documento, "***.456.789-**");
  // o nome de quem pagou também (revisão de 23/10/2026, item 3)
  assertEquals(r.propostas[0].de_quem_e.nome, "***.456.789-**-MARIA SOUZA");
  assertEquals(temCpfInteiro(r), false, JSON.stringify(r));
});

Deno.test("listar_propostas_de_lancamento: na SAÍDA, o CPF do favorecido a cadastrar sai mascarado (dono, 23/10/2026)", async () => {
  const banco = bancoFalso({
    finance_review_queue: [{
      id: "s1", kind: "create_payable", title: "Despesa: JOAO PRESTADOR", status: "pending", suggested_amount: 350,
      suggested_category: "Outras despesas", suggested_date: "2026-10-13", confidence: 40, bank_transaction_id: LINHA_DEBITO,
      suggested_client_id: null, vinculo_sugerido: null, suggested_service_order_id: null, suggested_purchase_order_id: null,
      evidencia: { cadastrar: { tipo: "favorecido", documento: "98765432100", nome: "JOAO PRESTADOR" } },
    }],
  });
  const t = financeRulesTools.find((x) => x.name === "listar_propostas_de_lancamento")!;
  const r = await t.execute({}, ctxDe(banco)) as Qualquer;
  assertEquals(r.propostas[0].cadastrar, { tipo: "favorecido", documento: "***.654.321-**", nome: "JOAO PRESTADOR" });
  assertEquals(temCpfInteiro(r), false);
});

// ─── CPF mascarado nunca vira documento gravado (revisão da leva 8, 23/10/2026) ─────────────────────────
Deno.test("criar_regra_financeira: CPF mascarado sem a linha do extrato é recusado ANTES do cartão", () => {
  const pre = criarRegra.preValidar!;
  assertEquals(typeof pre({ reconhecer_por: "documento", valor_de_busca: "***.456.789-**", categoria: "Aporte de sócio" }, ctxDe({}))?.error, "string");
  assertEquals(typeof pre({ reconhecer_por: "documento", valor_de_busca: "123", categoria: "Aporte de sócio" }, ctxDe({}))?.error, "string");
  assertEquals(typeof pre({ reconhecer_por: "documento", valor_de_busca: "x", bank_transaction_id: "não-é-uuid" }, ctxDe({}))?.error, "string");
  assertEquals(pre({ reconhecer_por: "documento", valor_de_busca: "***.456.789-**", bank_transaction_id: LINHA_CREDITO }, ctxDe({})), null);
  assertEquals(pre({ reconhecer_por: "documento", valor_de_busca: "12345678901" }, ctxDe({})), null);
  assertEquals(pre({ reconhecer_por: "texto", valor_de_busca: "CONFEIT***" }, ctxDe({})), null, "texto não é documento");
});

Deno.test("cadastrar_favorecido: CPF mascarado recusado antes do cartão; pela linha do extrato o documento vem do banco", async () => {
  const fav = financeRulesTools.find((x) => x.name === "cadastrar_favorecido")!;
  const pre = fav.preValidar!;
  assertEquals(typeof pre({ nome: "João", tipo: "prestador", documento: "***.456.789-**" }, ctxDe({}))?.error, "string");
  assertEquals(typeof pre({ nome: "João", tipo: "prestador", documento: "456789" }, ctxDe({}))?.error, "string");
  assertEquals(pre({ nome: "João", tipo: "prestador" }, ctxDe({})), null);
  assertEquals(pre({ nome: "João", tipo: "prestador", documento: "***.456.789-**", bank_transaction_id: LINHA_DEBITO }, ctxDe({})), null);

  // Pela linha: grava o documento do banco, nunca o mascarado.
  const banco = bancoFalso({ bank_transactions: EXTRATO });
  const ok = await fav.execute({ nome: "João", tipo: "prestador", documento: "***.456.789-**", bank_transaction_id: LINHA_DEBITO }, ctxDe(banco)) as Qualquer;
  assertEquals(ok.ok, true, JSON.stringify(ok));
  assertEquals(banco.inseridas[0].linha.document, "12345678000199");

  // Documento dito que diverge da linha, linha sem documento e leitura que falha: nada é gravado.
  for (const [args, b] of [
    [{ nome: "João", tipo: "prestador", documento: "11122233344", bank_transaction_id: LINHA_DEBITO }, bancoFalso({ bank_transactions: EXTRATO })],
    [{ nome: "Tarifa", tipo: "prestador", bank_transaction_id: LINHA_SEM_DOC }, bancoFalso({ bank_transactions: EXTRATO })],
    [{ nome: "João", tipo: "prestador", bank_transaction_id: LINHA_DEBITO }, bancoFalso({ bank_transactions: EXTRATO }, { falham: ["bank_transactions"] })],
  ] as const) {
    const r = await fav.execute(args as Qualquer, ctxDe(b)) as Qualquer;
    assertEquals(typeof r.error, "string", JSON.stringify(args));
    assertEquals((b as Qualquer).inseridas, [], JSON.stringify(args));
  }

  // Sem linha e com o CPF dito inteiro: grava os dígitos (como antes).
  const dito = bancoFalso({});
  await fav.execute({ nome: "Maria", tipo: "prestador", documento: "123.456.789-01" }, ctxDe(dito));
  assertEquals(dito.inseridas[0].linha.document, "12345678901");
});

// ─── listar_regras_financeiras ──────────────────────────────────────────────────────────────────────────
Deno.test("listar_regras_financeiras: CPF da regra por documento e do porquê mascarado; CNPJ e texto ficam", async () => {
  const banco = bancoFalso({
    finance_rules: [
      { id: "r1", match_type: "document", match_value: "12345678901", direction: "credit", set_category: "Aporte de sócio", status: "active",
        reasoning: "Pix de quem tem o CNPJ/CPF 12345678901", set_client_id: null, clients: null },
      { id: "r2", match_type: "document", match_value: "12345678000199", direction: "debit", set_category: "Peças", status: "active",
        reasoning: null, set_client_id: null, clients: null },
      { id: "r3", match_type: "text", match_value: "POSTO", direction: "debit", set_category: "Combustível", status: "active",
        reasoning: "Criada pelo assistente", set_client_id: null, clients: null },
    ],
  });
  const r = await listarRegras.execute({}, ctxDe(banco)) as Qualquer;
  assertEquals(r.regras.map((x: Qualquer) => x.match_value), ["***.456.789-**", "12.345.678/0001-99", "POSTO"]);
  assertEquals(r.regras[0].reasoning, "Pix de quem tem o CNPJ/CPF ***.456.789-**");
  assertEquals(r.regras.map((x: Qualquer) => x.id), ["r1", "r2", "r3"], "mudar a regra continua pelo id");
  assertEquals(temCpfInteiro(r), false);
});

// ─── 4ª rodada (C4): o CPF embutido em textos do assistente FORA do motor ───────────────────────────────
// A despesa/receita que nasce da fila do Extrato herda o nome do banco ("12345678901-JOAO…") na descrição e no nome livre
// do fornecedor; o extrato em PDF e o "gastos por categoria" mostram o nome da linha. Tudo sai mascarado (***.456.789-**).
Deno.test("buscar_lancamentos: descrição e contraparte com o CPF do nome do banco saem mascaradas", async () => {
  const banco = bancoFalso({
    payables: [{
      id: "p1", description: "12345678901-JOAO PRESTADOR", amount: 350, paid_amount: 350, status: "paid", issue_date: "2026-10-13",
      due_date: "2026-10-13", expense_category: "Serviços de terceiros", supplier_name: "JOAO PRESTADOR 98765432100",
      bank_transaction_id: LINHA_DEBITO, origin: "bank_reconciliation", divisao_id: null, suppliers: null, payees: null, service_orders: null,
    }],
    receivables: [{
      id: "r1", description: "12345678901-MARIA SOUZA", amount: 1500, paid_amount: 1500, status: "paid", issue_date: "2026-10-12",
      due_date: "2026-10-12", category: "Serviços prestados", bank_transaction_id: LINHA_CREDITO,
      clients: { name: "MARIA SOUZA 987.654.321-00" }, service_orders: null,
    }],
  });
  const t = lancamentoTools.find((x) => x.name === "buscar_lancamentos")!;
  const r = await t.execute({ texto: "SOUZA" }, ctxDe(banco)) as Qualquer;
  const pagar = r.lancamentos.find((l: Qualquer) => l.tipo === "pagar");
  const receber = r.lancamentos.find((l: Qualquer) => l.tipo === "receber");
  assertEquals(pagar.descricao, "***.456.789-**-JOAO PRESTADOR");
  assertEquals(pagar.contraparte, "JOAO PRESTADOR ***.654.321-**");
  assertEquals(receber.descricao, "***.456.789-**-MARIA SOUZA");
  assertEquals(receber.contraparte, "MARIA SOUZA ***.654.321-**");
  assertEquals(pagar.payable_id, "p1", "o id continua: é por ele que se corrige/desfaz");
  assertEquals(temCpfInteiro(r), false, JSON.stringify(r));
});

Deno.test("gastos_por_categoria: 'quem' do lançado, do não lançado e de quem mais recebeu sai mascarado", async () => {
  const banco = bancoFalso({
    financial_categories: [{ name: "Serviços de terceiros", type: "payable", dre_group: "despesa_operacional", active: true }],
    finance_rules: [],
    payables: [{
      id: "p1", issue_date: "2026-10-13", amount: 350, expense_category: "Serviços de terceiros", description: "12345678901-JOAO PRESTADOR",
      supplier_name: "12345678901-JOAO PRESTADOR", suppliers: null, payees: null, bank_transactions: null, status: "paid",
      bank_transaction_id: "outra-linha",
    }],
    bank_transactions: [{
      id: "bt9", transaction_type: "debit", transaction_date: "2026-10-14", amount: -80, merchant_name: null,
      counterparty_name: "98765432100 MARIA LANCHES", description: "PIX ENVIADO", payee_mcc: null, tx_status: "POSTED", reconciled: false,
    }],
    finance_review_queue: [],
  });
  const t = caixaTools.find((x) => x.name === "gastos_por_categoria")!;
  const r = await t.execute({ mes: 10, ano: 2026 }, ctxDe(banco)) as Qualquer;
  assert(!r.error, JSON.stringify(r));
  assertEquals(r.lancado.itens[0].quem, "***.456.789-**-JOAO PRESTADOR");
  assertEquals(r.quem_mais_recebeu[0].nome, "***.456.789-**-JOAO PRESTADOR");
  assertEquals(r.nao_lancado.itens[0].quem, "***.654.321-** MARIA LANCHES");
  assertEquals(r.lancado.total, 350, "a soma não muda");
  assertEquals(temCpfInteiro(r), false, JSON.stringify(r));
});

Deno.test("enviar_relatorio_pdf 'extrato': a coluna Descrição do PDF sai com o CPF mascarado", async () => {
  const banco = {
    ...bancoFalso({
      bank_connections: [{ id: "c6", label: "C6" }],
      bank_transactions: EXTRATO.map((t) => ({ ...t, bank_connection_id: "c6", merchant_name: null, dismissed_kind: null, tx_status: "POSTED" })),
    }),
    rpc: () => Promise.resolve({ data: "token-de-teste", error: null }),
  };
  const ctx = {
    sb: banco, admin: banco, userId: "u-dono", userRole: "admin", jwt: "jwt", appOrigin: "", canal: "panel",
    settings: { app_public_url: "https://exemplo.app", company_name: "HBR" },
  } as never;
  const corpos: string[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = ((_u: unknown, init?: RequestInit) => {
    corpos.push(String(init?.body ?? ""));
    return Promise.resolve(new Response("indisponível no teste", { status: 503 }));
  }) as typeof fetch;
  try {
    const t = relatorioTools.find((x) => x.name === "enviar_relatorio_pdf")!;
    const r = await t.execute({ relatorio: "extrato", de: "2026-10-01", ate: "2026-10-31" }, ctx) as Qualquer;
    // o servidor de PDF de mentira recusa: só o HTML que foi para ele interessa
    assert(typeof r.error === "string", JSON.stringify(r));
  } finally {
    globalThis.fetch = original;
  }
  assertEquals(corpos.length, 1);
  const html = String(JSON.parse(corpos[0]).html);
  assert(html.includes("***.456.789-**-MARIA SOUZA"), html.slice(0, 400));
  assert(html.includes("JOAO PRESTADOR ***.654.321-**"));
  assertEquals(temCpfInteiro(html), false);
});

Deno.test("listar_propostas_de_lancamento: o rótulo do vínculo (o_que) sai mascarado; a escolha continua pelo id", async () => {
  const banco = bancoFalso({
    finance_review_queue: [{
      id: "e1", kind: "create_receivable", title: "Receita: PIX", status: "pending", suggested_amount: 1500, suggested_category: "Serviços prestados",
      suggested_date: "2026-10-12", confidence: 60, bank_transaction_id: LINHA_CREDITO, suggested_client_id: null,
      suggested_service_order_id: null, suggested_purchase_order_id: null, evidencia: null,
      vinculo_sugerido: {
        principal: { id: "o1", rotulo: "Pagamento já lançado: 12345678901-MARIA SOUZA", valor: 1500, confianca: 70, jaLancado: true },
        alternativas: [{ id: "o2", rotulo: "Conta a receber: JOAO 987.654.321-00", valor: 1500, confianca: 50 }],
      },
    }],
  });
  const t = financeRulesTools.find((x) => x.name === "listar_propostas_de_lancamento")!;
  const r = await t.execute({}, ctxDe(banco)) as Qualquer;
  assertEquals(r.propostas[0].vinculos.map((v: Qualquer) => v.o_que), [
    "Pagamento já lançado: ***.456.789-**-MARIA SOUZA", "Conta a receber: JOAO ***.654.321-**",
  ]);
  assertEquals(r.propostas[0].vinculos[0].opcao_id, "o1");
  assertEquals(temCpfInteiro(r), false, JSON.stringify(r));
});

Deno.test("estorno, lançados sozinhos, contas a pagar e Pix esperando: o CPF do nome do banco sai mascarado", async () => {
  // estornar/desfazer pagamento: o rótulo cita a conta e quem
  const pagamento = {
    id: "pg1", amount: 350, payment_date: "2026-10-13", payment_method: "pix", status: "confirmed", notes: null,
    bank_transaction_id: null, receivable_id: null, payable_id: "p1", receivables: null,
    payables: {
      description: "12345678901-JOAO PRESTADOR", amount: 350, paid_amount: 350, supplier_name: "JOAO 98765432100",
      payees: null, suppliers: null, service_orders: null,
    },
  } as unknown as PagamentoLido;
  const rotulo = rotuloDoPagamento(pagamento);
  assert(rotulo.includes("«***.456.789-**-JOAO PRESTADOR»") && rotulo.includes("JOAO ***.654.321-**"), rotulo);
  assertEquals(temCpfInteiro(rotulo), false);

  // listar_lancados_sozinhos: o título da proposta
  const fila = bancoFalso({
    finance_review_queue: [{
      title: "Despesa: 12345678901-JOAO PRESTADOR", suggested_amount: 350, suggested_category: "Serviços de terceiros",
      suggested_date: "2026-10-13", automatica: "regra", created_payable_id: "p1", status: "approved",
    }],
    app_settings: [],
  });
  const sozinhos = await fechamentoTools.find((x) => x.name === "listar_lancados_sozinhos")!.execute({}, ctxDe(fila)) as Qualquer;
  assertEquals(sozinhos.lancados[0].o_que, "Despesa: ***.456.789-**-JOAO PRESTADOR");

  // list_payables_due: a descrição e o nome livre do fornecedor
  const contas = bancoFalso({
    payables: [{
      id: "p2", description: "Serviço 12345678901-JOAO", amount: 200, balance_amount: 200, due_date: "2026-10-20", status: "pending",
      supplier_name: "JOAO PRESTADOR 98765432100", expense_category: "Serviços de terceiros",
    }],
  });
  const devidas = await financialTools.find((x) => x.name === "list_payables_due")!.execute({}, ctxDe(contas)) as Qualquer;
  assertEquals([devidas.results[0].description, devidas.results[0].supplier_name], ["Serviço ***.456.789-**-JOAO", "JOAO PRESTADOR ***.654.321-**"]);
  assertEquals(devidas.results[0].id, "p2");

  // Pix esperando no Extrato (plano de cobrança): o título da entrada
  const esperando = await pixEsperandoNoExtrato(ctxDe(bancoFalso({
    finance_review_queue: [{
      suggested_client_id: "c1", suggested_amount: 1500, suggested_date: "2026-10-12", title: "Receita: 12345678901-MARIA SOUZA",
      status: "pending", kind: "create_receivable",
    }],
  })), ["c1"]);
  assertEquals(esperando.get("c1")?.[0].titulo, "Receita: ***.456.789-**-MARIA SOUZA");
  assertEquals(temCpfInteiro([sozinhos, devidas, [...esperando.values()]]), false);
});

Deno.test("listar_propostas_de_lancamento: o NOME do favorecido a cadastrar com o CPF dentro sai mascarado; cadastrar pela fila recusa nome com ***", async () => {
  const banco = bancoFalso({
    finance_review_queue: [{
      id: "s2", kind: "create_payable", title: "Despesa: JOAO", status: "pending", suggested_amount: 120,
      suggested_category: "Outras despesas", suggested_date: "2026-10-13", confidence: 40, bank_transaction_id: LINHA_DEBITO,
      suggested_client_id: null, vinculo_sugerido: null, suggested_service_order_id: null, suggested_purchase_order_id: null,
      evidencia: { cadastrar: { tipo: "favorecido", documento: "98765432100", nome: "98765432100-JOAO SOUZA" } },
    }],
  });
  const t = financeRulesTools.find((x) => x.name === "listar_propostas_de_lancamento")!;
  const r = await t.execute({}, ctxDe(banco)) as Qualquer;
  assertEquals(r.propostas[0].cadastrar.nome, "***.654.321-**-JOAO SOUZA");
  assertEquals(temCpfInteiro(r), false);

  const cadastrar = financeRulesTools.find((x) => x.name === "cadastrar_contraparte_do_extrato")!;
  assertEquals(typeof cadastrar.preValidar!({ proposta_id: "s2", nome: "***.654.321-**-JOAO SOUZA" }, ctxDe({}))?.error, "string");
  assertEquals(cadastrar.preValidar!({ proposta_id: "s2" }, ctxDe({})), null);
  assertEquals(cadastrar.preValidar!({ proposta_id: "s2", nome: "João Souza" }, ctxDe({})), null);
});
