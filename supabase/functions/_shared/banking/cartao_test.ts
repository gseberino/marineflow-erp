// O retrato do cartão (24/11/2026): lê o que o banco mandou sem inventar número, e guardar nunca derruba a busca.
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { CHAVE_DO_CARTAO, faturaDoBanco, faturasDoBanco, faturasVistas, guardarCartao, posicaoDoCartao } from "./cartao.ts";
import { fetchBills } from "./pluggy.ts";

// deno-lint-ignore no-explicit-any
type Qualquer = Record<string, any>;

const CONTA = {
  id: "conta-c6", type: "CREDIT", subtype: "CREDIT_CARD", name: "C6 Carbon", number: "5234 **** **** 7130", balance: 5300.874,
  creditData: {
    balanceDueDate: "2026-12-21T00:00:00.000Z", balanceCloseDate: null, minimumPayment: 795.13, creditLimit: 12000,
    availableCreditLimit: 6699.13, status: "ACTIVE", brand: "MASTERCARD",
  },
};

const FATURA = {
  id: "bill-1", dueDate: "2026-11-21T00:00:00", billClosingDate: "2026-11-14", totalAmount: 7399.74,
  totalAmountCurrencyCode: "BRL", minimumPaymentAmount: 1109.96,
  financeCharges: [{ id: "f1", type: "IOF", amount: 10.61 }, { id: "f2", type: "LATE_PAYMENT_INTEREST", amount: 236.61 }],
  payments: [{ id: "p1", amount: 1100, paymentDate: "2026-11-23" }, { id: "p2", amount: 300.5, paymentDate: "2026-11-10" }],
};

Deno.test("posicaoDoCartao: lê fatura aberta, vencimento, mínimo e limite; o dia é o que o banco escreveu", () => {
  assertEquals(posicaoDoCartao(CONTA), {
    provider_account_id: "conta-c6", nome: "C6 Carbon", final: "7130", saldo_informado: 5300.87,
    vencimento: "2026-12-21", fechamento: null, minimo: 795.13, limite: 12000, limite_disponivel: 6699.13,
    situacao: "ACTIVE", dados: CONTA.creditData,
  });
});

Deno.test("posicaoDoCartao: campo que o banco não mandou fica nulo, nunca zero; conta corrente não é cartão", () => {
  const p = posicaoDoCartao({ id: "x", type: "credit", name: "  ", balance: null, creditData: { minimumPayment: "", creditLimit: "abc" } })!;
  assertEquals([p.saldo_informado, p.minimo, p.limite, p.limite_disponivel, p.vencimento, p.nome, p.final, p.situacao],
    [null, null, null, null, null, null, null, null]);
  assertEquals(posicaoDoCartao({ id: "y", type: "CREDIT", balance: 0 })!.saldo_informado, 0); // zero de verdade continua zero
  assertEquals(posicaoDoCartao({ id: "y", type: "CREDIT", balance: "1234.56" })!.saldo_informado, 1234.56);
  // o que o JavaScript converteria em zero calado: espaço, lista vazia, falso
  for (const vazio of [" ", [], false, {}]) {
    assertEquals(posicaoDoCartao({ id: "y", type: "CREDIT", balance: vazio })!.saldo_informado, null);
  }
  assertEquals(posicaoDoCartao({ id: "y", type: "CREDIT", balance: 10 })!.dados, null);
  assertEquals(posicaoDoCartao({ id: "z", type: "BANK", balance: 10 }), null);
  assertEquals(posicaoDoCartao({ type: "CREDIT", balance: 10 }), null);
  assertEquals(posicaoDoCartao(null), null);
  // data impossível ou em outro formato não vira vencimento
  assertEquals(posicaoDoCartao({ id: "w", type: "CREDIT", creditData: { balanceDueDate: "2026-02-30" } })!.vencimento, null);
  assertEquals(posicaoDoCartao({ id: "w", type: "CREDIT", creditData: { balanceDueDate: "21/12/2026" } })!.vencimento, null);
});

Deno.test("faturaDoBanco: vencimento, total, mínimo, o que foi pago e os encargos; sem código fica de fora", () => {
  assertEquals(faturaDoBanco(FATURA, "conta-c6"), {
    bill_id: "bill-1", provider_account_id: "conta-c6", vencimento: "2026-11-21", fechamento: "2026-11-14",
    total: 7399.74, minimo: 1109.96, pago: 1400.5, encargos: 247.22, dados: FATURA,
  });
  // sem a lista de pagamentos não se sabe quanto foi pago (nulo); lista vazia é zero dito pelo banco
  const semLista = faturaDoBanco({ id: "b2", dueDate: "2026-10-21", totalAmount: 10 }, "c")!;
  assertEquals([semLista.pago, semLista.encargos, semLista.minimo, semLista.fechamento], [null, null, null, null]);
  assertEquals(faturaDoBanco({ id: "b3", payments: [], financeCharges: [] }, "c")!.pago, 0);
  // pagamento sem valor: a soma parcial não passa por total — fica "não sei"
  assertEquals(faturaDoBanco({ id: "b4", payments: [{ amount: null }] }, "c")!.pago, null);
  assertEquals(faturaDoBanco({ id: "b5", payments: [{ amount: 1100 }, { id: "sem valor" }] }, "c")!.pago, null);
  assertEquals(faturaDoBanco({ id: "b6", payments: [{ amount: 1100 }, "texto"], financeCharges: [{ amount: "10.5" }] }, "c"),
    { bill_id: "b6", provider_account_id: "c", vencimento: null, fechamento: null, total: null, minimo: null, pago: null,
      encargos: 10.5, dados: { id: "b6", payments: [{ amount: 1100 }, "texto"], financeCharges: [{ amount: "10.5" }] } });
  assertEquals(faturaDoBanco({ dueDate: "2026-10-21", totalAmount: 10 }, "c"), null);
  assertEquals(faturaDoBanco("texto", "c"), null);
});

Deno.test("faturasDoBanco: uma por código (a última vence) e ignora o que não é fatura", () => {
  const lista = [FATURA, null, { semId: true }, { ...FATURA, totalAmount: 8000 }, { id: "bill-2", totalAmount: 5 }];
  assertEquals(faturasDoBanco(lista, "conta-c6").map((f) => [f.bill_id, f.total]), [["bill-1", 8000], ["bill-2", 5]]);
  assertEquals(faturasDoBanco(undefined, "c"), []);
  assertEquals(faturasDoBanco({ results: [FATURA] }, "c"), []);
});

Deno.test("faturasVistas: o estado de cada fatura na leitura, só das que ainda podem mudar, em ordem de vencimento", () => {
  const faturas = faturasDoBanco([
    { id: "antiga", dueDate: "2026-08-21", totalAmount: 900, payments: [] },
    { id: "no-limite", dueDate: "2026-09-25", totalAmount: 100 },
    FATURA,
    { id: "futura", dueDate: "2026-12-21T00:00:00.000Z", totalAmount: 5300.87, payments: [], financeCharges: [] },
    { id: "sem-data", totalAmount: 12 },
  ], "conta-c6");
  assertEquals(faturasVistas(faturas, "2026-11-24"), [
    { bill_id: "no-limite", vencimento: "2026-09-25", total: 100, minimo: null, pago: null, encargos: null, pagamentos: null, ultimo_pagamento: null },
    { bill_id: "bill-1", vencimento: "2026-11-21", total: 7399.74, minimo: 1109.96, pago: 1400.5, encargos: 247.22, pagamentos: 2, ultimo_pagamento: "2026-11-23" },
    { bill_id: "futura", vencimento: "2026-12-21", total: 5300.87, minimo: null, pago: 0, encargos: 0, pagamentos: 0, ultimo_pagamento: null },
    { bill_id: "sem-data", vencimento: null, total: 12, minimo: null, pago: null, encargos: null, pagamentos: null, ultimo_pagamento: null },
  ]);
  assertEquals(faturasVistas([], "2026-11-24"), []);
});

/** Banco de mentira: guarda o que foi gravado e deixa escolher a chave e os erros. */
function banco(opcoes: { chave?: unknown; erroNasFaturas?: unknown; erroNoRetrato?: unknown; erroNaChave?: boolean } = {}) {
  const gravado: Array<{ tabela: string; como: string; linhas: Qualquer[]; opcoes?: Qualquer }> = [];
  const admin = {
    from: (tabela: string) => ({
      select: () => ({
        eq: (_coluna: string, chave: string) => ({
          maybeSingle: () => {
            if (opcoes.erroNaChave) return Promise.reject(new Error("sem rede"));
            return Promise.resolve({ data: chave === CHAVE_DO_CARTAO && opcoes.chave !== undefined ? { value: opcoes.chave } : null, error: null });
          },
        }),
      }),
      upsert: (linhas: Qualquer[], o: Qualquer) => {
        gravado.push({ tabela, como: "upsert", linhas, opcoes: o });
        return Promise.resolve({ error: opcoes.erroNasFaturas ?? null });
      },
      insert: (linha: Qualquer) => {
        gravado.push({ tabela, como: "insert", linhas: [linha] });
        return Promise.resolve({ error: opcoes.erroNoRetrato ?? null });
      },
    }),
  };
  return { admin, gravado };
}

Deno.test("guardarCartao: grava as faturas (por código, sem tocar no visto_em) e depois o retrato", async () => {
  const b = banco();
  const pedidas: string[] = [];
  await guardarCartao(b.admin, "conexao-1", CONTA, (id) => { pedidas.push(id); return Promise.resolve([FATURA, FATURA]); },
    "2026-11-24T09:01:22.000Z");
  assertEquals(pedidas, ["conta-c6"]);
  assertEquals(b.gravado.map((g) => [g.tabela, g.como, g.linhas.length]), [
    ["cartao_faturas_do_banco", "upsert", 1],
    ["cartao_posicoes", "insert", 1],
  ]);
  assertEquals(b.gravado[0].opcoes, { onConflict: "bill_id" });
  const fatura = b.gravado[0].linhas[0];
  assertEquals([fatura.bill_id, fatura.bank_connection_id, fatura.total, fatura.pago, "visto_em" in fatura], ["bill-1", "conexao-1", 7399.74, 1400.5, false]);
  const retrato = b.gravado[1].linhas[0];
  assertEquals([retrato.bank_connection_id, retrato.saldo_informado, retrato.vencimento, retrato.faturas_lidas, retrato.faturas_erro],
    ["conexao-1", 5300.87, "2026-12-21", 1, null]);
  assertEquals(retrato.lido_em, fatura.lido_em);
  // a série: o estado da fatura nesta leitura e de quando é o dado do provedor
  assertEquals(retrato.faturas_vistas.map((f: Qualquer) => [f.bill_id, f.total, f.pago, f.pagamentos]), [["bill-1", 7399.74, 1400.5, 2]]);
  assertEquals(retrato.provedor_atualizado_em, "2026-11-24T09:01:22.000Z");
});

Deno.test("guardarCartao: hora do provedor ausente ou inválida fica nula (nunca 'agora', nunca derruba a gravação)", async () => {
  for (const hora of [undefined, null, "", "ontem", "2026-11-24", 1732438882000, "2026-13-45T99:00:00Z"]) {
    const b = banco();
    await guardarCartao(b.admin, "c1", CONTA, () => Promise.resolve([]), hora);
    assertEquals([b.gravado.length, b.gravado[0].linhas[0].provedor_atualizado_em], [1, null]);
  }
});

Deno.test("guardarCartao: a lista de faturas falhou — o retrato é gravado mesmo assim, com o motivo", async () => {
  const semLista = banco();
  await guardarCartao(semLista.admin, "c1", CONTA, () => Promise.reject(new Error("Pluggy /bills respondeu 404: not available")));
  assertEquals(semLista.gravado.map((g) => g.tabela), ["cartao_posicoes"]);
  assertEquals([semLista.gravado[0].linhas[0].faturas_lidas, semLista.gravado[0].linhas[0].faturas_erro, semLista.gravado[0].linhas[0].faturas_vistas],
    [null, "Pluggy /bills respondeu 404: not available", null]);

  // a lista estourou o prazo (é assim que o fetch avisa): mesmo tratamento, e a sincronização segue
  const demorou = banco();
  await guardarCartao(demorou.admin, "c1", CONTA, () => Promise.reject(new DOMException("Signal timed out.", "TimeoutError")));
  assertEquals([demorou.gravado.length, demorou.gravado[0].linhas[0].faturas_erro, demorou.gravado[0].linhas[0].saldo_informado],
    [1, "Signal timed out.", 5300.87]);

  const naoGravou = banco({ erroNasFaturas: { message: "permission denied for table cartao_faturas_do_banco" } });
  await guardarCartao(naoGravou.admin, "c1", CONTA, () => Promise.resolve([FATURA]));
  const retrato = naoGravou.gravado.find((g) => g.tabela === "cartao_posicoes")!.linhas[0];
  assertEquals([retrato.faturas_lidas, retrato.faturas_erro], [null, "permission denied for table cartao_faturas_do_banco"]);
  // a gravação das faturas falhou, mas o que o banco disse nesta leitura fica na série
  assertEquals(retrato.faturas_vistas.map((f: Qualquer) => f.bill_id), ["bill-1"]);

  // banco sem fatura nenhuma: zero lidas, sem erro e sem gravação vazia
  const vazio = banco();
  await guardarCartao(vazio.admin, "c1", CONTA, () => Promise.resolve([]));
  assertEquals(vazio.gravado.map((g) => g.tabela), ["cartao_posicoes"]);
  assertEquals([vazio.gravado[0].linhas[0].faturas_lidas, vazio.gravado[0].linhas[0].faturas_erro, vazio.gravado[0].linhas[0].faturas_vistas], [0, null, []]);
});

Deno.test("guardarCartao: chave desligada, conta corrente ou erro — não grava e NUNCA lança", async () => {
  for (const chave of ["desligado", '"desligado"', " Desligado "]) {
    const b = banco({ chave });
    let chamou = false;
    await guardarCartao(b.admin, "c1", CONTA, () => { chamou = true; return Promise.resolve([FATURA]); });
    assertEquals([b.gravado.length, chamou], [0, false]);
  }
  const ligado = banco({ chave: "ligado" });
  await guardarCartao(ligado.admin, "c1", CONTA, () => Promise.resolve([]));
  assertEquals(ligado.gravado.length, 1);

  const corrente = banco();
  await guardarCartao(corrente.admin, "c1", { id: "cc", type: "BANK", balance: 1 }, () => Promise.resolve([FATURA]));
  assertEquals(corrente.gravado.length, 0);

  // falha ao ler a chave, e falha ao gravar o retrato: a sincronização segue
  await guardarCartao(banco({ erroNaChave: true }).admin, "c1", CONTA, () => Promise.resolve([FATURA]));
  await guardarCartao(banco({ erroNoRetrato: { message: "relation does not exist" } }).admin, "c1", CONTA, () => Promise.resolve([FATURA]));
});

Deno.test("fetchBills: pagina por número de página até o total, manda a chave no cabeçalho e para em resposta sem fim", async () => {
  const original = globalThis.fetch;
  const pedidos: Array<{ url: string; chave: string | null; prazo: AbortSignal | null }> = [];
  try {
    globalThis.fetch = ((url: string, init?: RequestInit) => {
      pedidos.push({ url: String(url), chave: new Headers(init?.headers).get("X-API-KEY"), prazo: init?.signal ?? null });
      const pagina = Number(new URL(String(url)).searchParams.get("page"));
      return Promise.resolve(new Response(JSON.stringify({ page: pagina, totalPages: 2, results: [{ id: `b${pagina}` }] }), { status: 200 }));
    }) as typeof fetch;
    assertEquals(await fetchBills("chave-de-teste", "conta 1"), [{ id: "b1" }, { id: "b2" }]);
    assertEquals(pedidos.map((p) => p.url), [
      "https://api.pluggy.ai/bills?accountId=conta+1&page=1",
      "https://api.pluggy.ai/bills?accountId=conta+1&page=2",
    ]);
    assertEquals(pedidos.every((p) => p.chave === "chave-de-teste"), true);
    // um prazo só para a leitura inteira: as duas páginas levam o MESMO sinal
    assertEquals([pedidos[0].prazo instanceof AbortSignal, pedidos[0].prazo === pedidos[1].prazo], [true, true]);

    // resposta que nunca diz que acabou: para no teto
    pedidos.length = 0;
    globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ totalPages: 99, results: [{ id: "x" }] }), { status: 200 }))) as typeof fetch;
    assertEquals((await fetchBills("k", "c", 3)).length, 3);
    // sem totalPages: uma página só; lista vazia é "o banco não tem fatura"
    globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ results: [{ id: "x" }] }), { status: 200 }))) as typeof fetch;
    assertEquals((await fetchBills("k", "c")).length, 1);
    globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ page: 1, total: 0, totalPages: 0, results: [] }), { status: 200 }))) as typeof fetch;
    assertEquals(await fetchBills("k", "c"), []);
    // resposta em outro formato NÃO é "nenhuma fatura": é erro, para aparecer em faturas_erro
    globalThis.fetch = (() => Promise.resolve(new Response(JSON.stringify({ message: "ok" }), { status: 200 }))) as typeof fetch;
    await assertRejects(() => fetchBills("k", "c"), Error, "sem a lista de faturas");
    globalThis.fetch = (() => Promise.resolve(new Response("nao disponivel", { status: 404 }))) as typeof fetch;
    await assertRejects(() => fetchBills("k", "c"), Error, "respondeu 404");

    // o banco não responde: o prazo corta a espera (aqui 50 ms; em produção 10 s para a leitura inteira)
    globalThis.fetch = ((_url: string, init?: RequestInit) =>
      new Promise((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => reject(init.signal!.reason));
      })) as typeof fetch;
    const inicio = performance.now();
    await assertRejects(() => fetchBills("k", "c", 5, 50));
    assertEquals(performance.now() - inicio < 2000, true);
  } finally {
    globalThis.fetch = original;
  }
});
