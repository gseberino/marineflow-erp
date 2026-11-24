// A fatura do cartão no bloco da semana e na resposta do assistente (24/11/2026): seção à parte, data do banco, valor
// sempre "cerca de", sem mexer na fila das contas; sem cartão lido, o texto é o de antes, byte a byte.
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  blocoDaSemana, cartaoNaJanela, comCartoes, filaDePagamentos, lerPagamentosDaManha, linhaDasVencidas, linhaDoCartao,
  pagamentosDaManha, pagamentosDaResposta, type PagamentosDaSemana,
} from "./semana.ts";
import type { CartaoNaFila } from "./cartoes.ts";
import { financialTools } from "../ai/tools/financial.ts";
import type { ToolCtx } from "../ai/tools/registry.ts";
import { montarDosDados } from "../../ai-daily-briefing/secretario.ts";
import { AGORA_1510, coleta1510, deHoje1510 } from "../../ai-daily-briefing/secretario-fixture.ts";

// deno-lint-ignore no-explicit-any
type Qualquer = Record<string, any>;

const RESPOSTA = {
  hoje: "2026-11-23", ate: "2026-11-29", saldo_no_banco: 1476.13, saldo_em: "2026-11-23T09:01:00+00:00",
  contas: [
    { id: "u", nome: "Unifique", valor: 117.18, vencimento: "2026-11-20", vencida: true, grupo: 2, a_definir: false, categoria: null, boleto_linha: "x" },
    { id: "k", nome: "KAMELL COMERCIO GLOBAL LTDA", valor: 1433.6, vencimento: "2026-11-05", vencida: true, grupo: 3, a_definir: false, categoria: "Compras", boleto_linha: null },
  ],
  soma: 1550.78, vencido: { n: 2, total: 1550.78 }, reembolsos: { n: 0, total: 0 },
};
const fila = (extra: Partial<PagamentosDaSemana> = {}, resposta: Qualquer = RESPOSTA): PagamentosDaSemana => ({ ...pagamentosDaResposta(resposta), ...extra });

const base: CartaoNaFila = { cartao: "C6", valor: 500, total: 500, pago: 0, vencimento: "2026-11-25", fechamento: "2026-11-19", situacao: "fechada", vencida: false, origem: "extrato" };
const FECHADA = base;
const EM_PARTE: CartaoNaFila = { ...base, valor: 100, pago: 400 };
const COBERTA: CartaoNaFila = { ...base, valor: 0, total: 727.07, pago: 2450.61 };
const SEM_NADA: CartaoNaFila = { ...base, valor: 0, total: 0, pago: 1100 };
const ATRASADA: CartaoNaFila = { ...base, cartao: "Nubank", valor: 1384.95, total: 1684.95, pago: 300, vencimento: "2026-11-10", fechamento: "2026-11-03", vencida: true, origem: "banco" };
const ABERTA: CartaoNaFila = { cartao: "Nubank", valor: 1178.76, total: 1418.76, pago: 240, vencimento: "2026-12-10", fechamento: "2026-12-03", situacao: "aberta", vencida: false, origem: "extrato" };

Deno.test("linhaDoCartao: a data é a do banco; o valor estimado leva sempre 'cerca de' (só o total que o banco informou vai sem)", () => {
  assertEquals(linhaDoCartao(FECHADA), "Cartão C6 — fatura de cerca de R$ 500,00 (vencimento 25/11)");
  assertEquals(linhaDoCartao(EM_PARTE), "Cartão C6 — faltam cerca de R$ 100,00 da fatura de cerca de R$ 500,00 (vencimento 25/11)");
  assertEquals(linhaDoCartao(COBERTA), "Cartão C6 — fatura de cerca de R$ 727,07 (vencimento 25/11): coberta pelos R$ 2.450,61 pagos desde o fechamento");
  assertEquals(linhaDoCartao(SEM_NADA), "Cartão C6 — vencimento 25/11: pelo extrato não há nada em aberto");
  assertEquals(linhaDoCartao(ATRASADA), "Cartão Nubank — faltam cerca de R$ 1.384,95 da fatura de R$ 1.684,95 (vencimento 10/11; o extrato não mostra pagamento que cubra)");
  assertEquals(linhaDoCartao({ ...ATRASADA, pago: 0, valor: 1684.95 }), "Cartão Nubank — fatura de R$ 1.684,95 (vencimento 10/11; o extrato não mostra pagamento que cubra)");
  assertEquals(linhaDoCartao(ABERTA), "Cartão Nubank — cerca de R$ 1.178,76 até agora (fecha por volta de 03/12, vencimento 10/12)");
  // nenhum valor estimado sai sem "cerca de" (o que já foi pago é soma do extrato, não estimativa: fica depois de ": coberta")
  for (const f of [FECHADA, EM_PARTE, COBERTA, ABERTA]) {
    const estimados = linhaDoCartao(f).split(": coberta")[0].match(/(cerca de )?R\$ [\d.,]+/g) ?? [];
    assertEquals(estimados.every((v) => v.startsWith("cerca de ")), true, linhaDoCartao(f));
  }
});

Deno.test("blocoDaSemana: sem cartão lido (ausente, lista vazia ou erro) o texto é o de antes, byte a byte", () => {
  const antes = blocoDaSemana(fila())!;
  assertEquals(antes, [
    "*Pagamentos da semana* — no banco: R$ 1.476,13",
    "Na ordem em que eu pagaria:",
    "• Unifique — R$ 117,18 (venceu 20/11)",
    "• KAMELL COMERCIO GLOBAL LTDA — R$ 1.433,60 (venceu 05/11)",
    "Soma R$ 1.550,78: faltam R$ 74,65 no banco.",
    "Pagou alguma? Me diga qual (*paguei Unifique*). Para o código do boleto: *boleto Unifique*.",
  ].join("\n"));
  assertEquals(blocoDaSemana(fila({ cartoes: [], avisosDoCartao: [], cartaoEmTransito: 0 })), antes);
  assertEquals(blocoDaSemana(fila({ cartoes: [], cartaoEmTransito: 1100 })), antes);
  assertEquals(blocoDaSemana(fila({ cartoesErro: "timeout" })), antes);
});

Deno.test("blocoDaSemana: o cartão em seção própria depois das contas; fatura coberta e fatura de depois da semana não mexem na soma", () => {
  const p = fila({ cartoes: [COBERTA, ABERTA], cartaoEmTransito: 1100 });
  assertEquals(blocoDaSemana(p), [
    "*Pagamentos da semana* — no banco: R$ 1.476,13",
    "Na ordem em que eu pagaria:",
    "• Unifique — R$ 117,18 (venceu 20/11)",
    "• KAMELL COMERCIO GLOBAL LTDA — R$ 1.433,60 (venceu 05/11)",
    "Cartão (vencimento do banco; valor estimado pelo extrato):",
    "• C6 — fatura de cerca de R$ 727,07 (vencimento 25/11): coberta pelos R$ 2.450,61 pagos desde o fechamento",
    "• Nubank — cerca de R$ 1.178,76 até agora (fecha por volta de 03/12, vencimento 10/12)",
    "Contei como pagos R$ 1.100,00 que parecem ter saído da conta para o cartão; ele ainda não mostra.",
    "Soma R$ 1.550,78: faltam R$ 74,65 no banco.",
    "Pagou alguma? Me diga qual (*paguei Unifique*). Para o código do boleto: *boleto Unifique*.",
  ].join("\n"));
  assertEquals(cartaoNaJanela(p), 0);
});

Deno.test("blocoDaSemana: o que falta de fatura que vence na semana (ou já venceu) entra na soma — e a soma passa a ser 'cerca de'", () => {
  const p = fila({ cartoes: [ATRASADA, EM_PARTE, ABERTA] });
  assertEquals(cartaoNaJanela(p), 1484.95);
  const texto = blocoDaSemana(p)!;
  assertStringIncludes(texto, "• Nubank — faltam cerca de R$ 1.384,95 da fatura de R$ 1.684,95 (vencimento 10/11; o extrato não mostra pagamento que cubra)");
  assertStringIncludes(texto, "• C6 — faltam cerca de R$ 100,00 da fatura de cerca de R$ 500,00 (vencimento 25/11)");
  assertStringIncludes(texto, "Soma cerca de R$ 3.035,73 (com cerca de R$ 1.484,95 de cartão): faltam cerca de R$ 1.559,60 no banco.");
  assertStringIncludes(blocoDaSemana(fila({ cartoes: [FECHADA] }, { ...RESPOSTA, saldo_no_banco: 9000 }))!, "Soma cerca de R$ 2.050,78 (com cerca de R$ 500,00 de cartão): o saldo deve cobrir.");
  assertStringIncludes(blocoDaSemana(fila({ cartoes: [FECHADA] }, { ...RESPOSTA, saldo_no_banco: null }))!, "Soma cerca de R$ 2.050,78 (com cerca de R$ 500,00 de cartão).");
});

Deno.test("blocoDaSemana: só cartão, sem conta a pagar — sai o bloco, sem 'na ordem' nem 'pagou alguma'; avisos entram (até dois)", () => {
  const semContas = { ...RESPOSTA, contas: [], soma: 0, vencido: { n: 0, total: 0 } };
  assertEquals(blocoDaSemana(fila({ cartoes: [ABERTA] }, semContas)), [
    "*Pagamentos da semana* — no banco: R$ 1.476,13",
    "Cartão (vencimento do banco; valor estimado pelo extrato):",
    "• Nubank — cerca de R$ 1.178,76 até agora (fecha por volta de 03/12, vencimento 10/12)",
  ].join("\n"));
  assertEquals(blocoDaSemana(fila({ cartoes: [FECHADA] }, semContas))!.split("\n").slice(2), [
    "• C6 — fatura de cerca de R$ 500,00 (vencimento 25/11)",
    "Soma cerca de R$ 500,00 (com cerca de R$ 500,00 de cartão): o saldo deve cobrir.",
  ]);
  assertEquals(blocoDaSemana(fila({ cartoes: [] }, semContas)), null);
  const comAvisos = blocoDaSemana(fila({ cartoes: [], avisosDoCartao: ["Cartão C6: aviso um.", "Cartão Nubank: aviso dois.", "terceiro"] }, semContas))!;
  assertEquals(comAvisos.split("\n").slice(1), ["Cartão C6: aviso um.", "Cartão Nubank: aviso dois."]);
  // mais de quatro faturas: as primeiras por extenso e o resto somado
  const muitas = blocoDaSemana(fila({ cartoes: [ATRASADA, FECHADA, EM_PARTE, ABERTA, { ...ABERTA, cartao: "Inter", valor: 10 }, { ...ABERTA, cartao: "XP", valor: 5 }] }))!;
  assertStringIncludes(muitas, "• e mais 2 (cerca de R$ 15,00)");
});

Deno.test("a linha dos outros dias úteis não muda com o cartão (uma mudança por vez)", () => {
  const p = fila({ cartoes: [ATRASADA, ABERTA] });
  assertEquals(linhaDasVencidas(p), linhaDasVencidas(fila()));
  assertEquals(pagamentosDaManha(p, "2026-11-24"), linhaDasVencidas(fila())); // terça: só a linha
  assertStringIncludes(pagamentosDaManha(p, "2026-11-23")!, "Cartão (vencimento do banco"); // segunda: o bloco
});

Deno.test("a manhã inteira numa segunda: o bloco com o cartão entra no fim, antes da sugestão de imprimir", () => {
  const dados = (pagamentos: PagamentosDaSemana | null) => ({
    hoje: "2026-11-23", agora: AGORA_1510, coleta: coleta1510(), historico: [], naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(),
    escritorio: { propostas: null, alertas: null, regras: null, debitosSemLoja: null, entradas: null }, pagamentos, viasParaImprimir: 2,
  });
  const sem = montarDosDados(dados(null)).texto;
  const com = montarDosDados(dados(fila({ cartoes: [COBERTA, ABERTA] }))).texto;
  const bloco = blocoDaSemana(fila({ cartoes: [COBERTA, ABERTA] }))!;
  const imprimir = sem.slice(sem.lastIndexOf("\n🖨️"));
  assertEquals(imprimir.startsWith("\n🖨️"), true);
  assertEquals(com, `${sem.slice(0, sem.length - imprimir.length)}\n\n${bloco}${imprimir}`);
});

/** Banco de mentira: a função da fila + as leituras do cartão (ou erro nelas). Cartão que fecha dia 19 e vence dia 25. */
function banco(opcoes: { erroNoCartao?: boolean; chave?: string; hoje?: string; comprasDepois?: number } = {}) {
  const leituras: string[] = [];
  const linha = (data: string, valor: number, tipo = "debit", descricao = "COMPRA") => ({
    id: `${data}-${valor}`, bank_connection_id: "c6", transaction_date: data, amount: valor, transaction_type: tipo,
    description: descricao, bill_id: null, dismissed_kind: null, import_batch_id: null,
  });
  // a de outubro (R$ 1.000) quitada em 20/10; R$ 700 de compras até fechar em 19/11; depois, o que o teste pedir
  const extrato = [linha("2026-10-20", 1000, "credit", "Pagamento recebido"), linha("2026-11-10", 700), linha("2026-11-21", opcoes.comprasDepois ?? 0.5)];
  const doBanco = ["08", "09", "10"].map((m, i) => ({ bill_id: `b${m}`, bank_connection_id: "c6", fechamento: `2026-${m}-19`, vencimento: `2026-${m}-25`, total: 800 + i * 100 }));
  const admin = {
    rpc: (fn: string, args: Qualquer) => {
      leituras.push(`rpc:${fn}`);
      return Promise.resolve({ data: { ...RESPOSTA, hoje: args.p_hoje ?? opcoes.hoje ?? RESPOSTA.hoje, ate: args.p_ate ?? RESPOSTA.ate }, error: null });
    },
    from(tabela: string) {
      const filtros: Qualquer = {};
      const q: Qualquer = {
        select: () => q, not: () => q, lte: () => q, order: () => q, gte: () => q,
        eq: (c: string, v: unknown) => { filtros[c] = v; return q; },
        limit: () => Promise.resolve({ data: [], error: null }),
        maybeSingle: () => { leituras.push(`${tabela}:${filtros.key}`); return Promise.resolve({ data: opcoes.chave ? { value: opcoes.chave } : null, error: null }); },
        range: () => {
          const qual = tabela === "cartao_faturas_do_banco" ? "faturas" : String(filtros.source_type);
          leituras.push(`${tabela}:${qual}`);
          if (opcoes.erroNoCartao) return Promise.resolve({ data: null, error: { message: "canceling statement due to statement timeout" } });
          return Promise.resolve({ data: qual === "faturas" ? doBanco : qual === "credit_card" ? extrato : [], error: null });
        },
        then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: [{ id: "c6", label: "C6 - Conta PJ HBR" }], error: null }).then(ok),
      };
      return q;
    },
  };
  return { admin, leituras };
}

Deno.test("comCartoes: junta as faturas; erro de leitura NÃO lança — fica em cartoesErro e a fila das contas segue igual", async () => {
  const ok = await comCartoes(banco().admin, fila());
  assertEquals(ok.cartoes!.map((f) => [f.cartao, f.situacao, f.valor, f.vencimento, f.origem]), [["C6", "fechada", 700, "2026-11-25", "extrato"]]);
  assertEquals([ok.cartoesErro, ok.contas.length, ok.soma], [undefined, 2, 1550.78]);

  const falhou = await comCartoes(banco({ erroNoCartao: true }).admin, fila());
  assertEquals([falhou.cartoes, falhou.contas.length, falhou.soma], [undefined, 2, 1550.78]);
  assertStringIncludes(falhou.cartoesErro!, "statement timeout");
  assertEquals(blocoDaSemana(falhou), blocoDaSemana(fila())); // a manhã sai como antes

  const desligado = await comCartoes(banco({ chave: "desligado" }).admin, fila());
  assertEquals([desligado.cartoes, desligado.cartoesErro], [[], undefined]);
});

Deno.test("lerPagamentosDaManha: lê o cartão só no 1º dia útil da semana (nos outros dias a linha não o usa)", async () => {
  const segunda = banco();
  const p = await lerPagamentosDaManha(segunda.admin, "2026-11-23");
  assertEquals(p!.cartoes!.length, 1);
  assertEquals(segunda.leituras.includes("bank_transactions:credit_card"), true);

  const terca = banco();
  const q = await lerPagamentosDaManha(terca.admin, "2026-11-24");
  assertEquals(q!.cartoes, undefined);
  assertEquals(terca.leituras.some((l) => l.startsWith("bank_transactions") || l.startsWith("cartao_")), false);

  // cartão que falha na segunda não derruba a manhã
  const r = await lerPagamentosDaManha(banco({ erroNoCartao: true }).admin, "2026-11-23");
  assertEquals([r!.contas.length, r!.cartoes], [2, undefined]);
});

Deno.test("list_payables_due: as faturas de cartão à parte, com o jeito de ler e a soma com cartão; só admin e financeiro veem", async () => {
  const tool = financialTools.find((t) => t.name === "list_payables_due")!;
  const ctx = (admin: unknown, cargo = "admin") => ({ admin, sb: admin, userId: "dono", userRole: cargo }) as unknown as ToolCtx;

  // a fatura (R$ 700, vencimento 25/11) cai dentro da data-limite: entra na soma com cartão
  const r = await tool.execute({}, ctx(banco({ comprasDepois: 120 }).admin)) as Qualquer;
  assertEquals(r.cartoes, [
    { descricao: "Cartão C6 — fatura de cerca de R$ 700,00 (vencimento 25/11)", cartao: "C6", fatura: "fechada", falta_cerca_de: 700,
      soma_cerca_de: 700, pago: 0, fecha: "2026-11-19", vencimento: "2026-11-25" },
    { descricao: "Cartão C6 — cerca de R$ 120,00 até agora (fecha por volta de 19/12, vencimento 25/12)", cartao: "C6", fatura: "aberta", falta_cerca_de: 120,
      soma_cerca_de: 120, pago: 0, fecha: "2026-12-19", vencimento: "2026-12-25" },
  ]);
  assertStringIncludes(r.cartoes_como_ler, "não registre pagamento");
  assertStringIncludes(r.cartoes_como_ler, "cerca de");
  assertStringIncludes(r.cartoes_como_ler, "o cartão ainda não confirma");
  assertEquals([r.soma_da_fila, r.soma_com_cartao_cerca_de, r.falta_no_banco, r.falta_com_cartao_cerca_de, "cartoes_erro" in r],
    [1550.78, 2250.78, 74.65, 774.65, false]);

  // financeiro vê; vendedor não vê nada do cartão (o extrato do banco não é dele), mas a fila das contas continua
  assertEquals(((await tool.execute({}, ctx(banco().admin, "financial"))) as Qualquer).cartoes.length, 1);
  for (const cargo of ["seller", "external_seller"]) {
    const v = await tool.execute({}, ctx(banco().admin, cargo)) as Qualquer;
    assertEquals(Object.keys(v).filter((k) => k.includes("cart")), [], cargo);
    assertEquals(v.soma_da_fila, 1550.78);
  }

  const falhou = await tool.execute({}, ctx(banco({ erroNoCartao: true }).admin)) as Qualquer;
  assertEquals(["cartoes" in falhou, falhou.soma_da_fila], [false, 1550.78]);
  assertStringIncludes(falhou.cartoes_erro, "ficaram de fora");
  assertEquals("cartoes_erro" in ((await tool.execute({}, ctx(banco({ erroNoCartao: true }).admin, "seller"))) as Qualquer), false);

  // a fila do assistente e a da manhã saem da mesma leitura
  const direta = await filaDePagamentos(banco().admin, "2026-11-29");
  assertEquals(direta!.cartoes!.map((f) => f.valor), [700]);
});
