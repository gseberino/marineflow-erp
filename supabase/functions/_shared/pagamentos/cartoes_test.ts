// A fatura do cartão na fila (24/11/2026): data do calendário do banco, valor estimado pelo saldo (última fatura do
// banco + cobrado − pago), o pagamento da véspera lido da conta, e a leitura que nunca devolve "sem fatura" quando na
// verdade não conseguiu ler.
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  cartaoDoPagamento, comPagamentosEmTransito, faturasDoCartao, faturasPeloBanco, PAGAMENTO_EM_TRANSITO, semParcelaRepetida,
  somaEmTransito, type FaturaInformada, type LinhaDoCartao,
} from "../banking/fatura-do-cartao.ts";
import {
  cartoesDoExtrato, CHAVE_DOS_CARTOES, lerCartoes, nomeDoCartao, type DebitoLido, type FaturaLida, type LinhaLida,
} from "./cartoes.ts";

// deno-lint-ignore no-explicit-any
type Qualquer = Record<string, any>;

const HOJE = "2026-11-24";
const C6 = "conexao-c6", NU = "conexao-nu";
const ROTULOS = new Map([[C6, "C6 - Conta PJ HBR"], [NU, "Nubank PJ HBR"], ["conexao-ip", "Infinitepay PJ - HBR"]]);

const compra = (data: string, valor: number, fatura: string | null = null, conexao = C6): LinhaLida => ({
  bank_connection_id: conexao, transaction_date: data, amount: valor, transaction_type: "debit", description: "COMPRA",
  bill_id: fatura, dismissed_kind: null, import_batch_id: null,
});
const pagamento = (data: string, valor: number, conexao = C6, descricao = "Pagamento recebido"): LinhaLida => ({
  bank_connection_id: conexao, transaction_date: data, amount: valor, transaction_type: "credit", description: descricao,
  bill_id: null, dismissed_kind: null, import_batch_id: null,
});
const debito = (data: string, valor: number, extra: Partial<DebitoLido> = {}): DebitoLido => ({
  bank_connection_id: C6, transaction_date: data, amount: valor, description: "PGTO FAT CARTAO C6", counterparty_name: null, ...extra,
});

// ── A regra antiga (a da tela), agora no servidor: continua dando o mesmo ───────────────────────────────────────────
const EXTRATO_ANTIGO: LinhaLida[] = [
  compra("2026-08-23", 300, "f-set"), compra("2026-08-25", 300, "f-set"), compra("2026-09-10", 200, "f-set"),
  compra("2026-09-23", 400, "f-out"), compra("2026-09-30", 400, "f-out"), compra("2026-10-15", 200, "f-out"),
  compra("2026-10-25", 300), compra("2026-11-10", 200),
  pagamento("2026-09-21", 900), pagamento("2026-10-21", 800),
  pagamento("2026-11-20", 600, C6, "Inclusao de Pagamento Ciclo Corrente"), pagamento("2026-11-20", 600),
];

Deno.test("a regra da tela (ciclo deduzido), movida sem mudar: o que falta da que venceu e a que fechou", () => {
  const r = faturasDoCartao("C6", EXTRATO_ANTIGO, HOJE);
  assertEquals(r.ciclo, { diaDeFechamento: 22, diaDePagamento: 21 });
  assertEquals(r.faturas.map((f) => [f.valor, f.vencimento, f.situacao, f.vencida, f.pago]), [
    [400, "2026-11-21", "fechada", true, 600],
    [500, "2026-12-21", "fechada", false, 0],
  ]);
});

// ── O pagamento que saiu da conta e o cartão ainda não mostra ──────────────────────────────────────────────────────
Deno.test("comPagamentosEmTransito: o que saiu da conta e o cartão ainda não mostra entra como pagamento; o que já tem par, não", () => {
  const linhas = comPagamentosEmTransito(EXTRATO_ANTIGO, [{ transaction_date: "2026-11-23", amount: 400 }, { transaction_date: "2026-11-20", amount: "600.00" }], HOJE);
  assertEquals(linhas.length, EXTRATO_ANTIGO.length + 1);
  assertEquals(linhas[linhas.length - 1], {
    transaction_date: "2026-11-23", amount: 400, transaction_type: "credit", description: PAGAMENTO_EM_TRANSITO,
    bill_id: null, dismissed_kind: null, import_batch_id: null,
  });
  assertEquals(somaEmTransito(linhas), 400);
  assertEquals(faturasDoCartao("C6", linhas as LinhaDoCartao[], HOJE).faturas.map((f) => [f.valor, f.vencimento, f.vencida]), [[500, "2026-12-21", false]]);
  // sem nada em trânsito devolve a MESMA lista (a tela e os testes antigos não mudam)
  assertEquals(comPagamentosEmTransito(EXTRATO_ANTIGO, [], HOJE) === EXTRATO_ANTIGO, true);
  assertEquals(comPagamentosEmTransito(EXTRATO_ANTIGO, [{ transaction_date: "2026-11-20", amount: 600 }], HOJE) === EXTRATO_ANTIGO, true);
  assertEquals(somaEmTransito(EXTRATO_ANTIGO), 0);
});

Deno.test("comPagamentosEmTransito: só o recente conta; o par pode estar no mesmo dia, na véspera ou até 3 dias depois", () => {
  const E = EXTRATO_ANTIGO;
  assertEquals(comPagamentosEmTransito(E, [{ transaction_date: "2026-11-19", amount: 123 }, { transaction_date: "2026-07-28", amount: 6370.91 }], HOJE) === E, true);
  assertEquals(somaEmTransito(comPagamentosEmTransito(E, [{ transaction_date: "2026-11-21", amount: 50 }], HOJE)), 50);
  const vespera = [...E, pagamento("2026-11-22", 77)];
  assertEquals(comPagamentosEmTransito(vespera, [{ transaction_date: "2026-11-23", amount: 77 }], HOJE) === vespera, true);
  const depois = [...E, pagamento("2026-11-24", 88)];
  assertEquals(comPagamentosEmTransito(depois, [{ transaction_date: "2026-11-21", amount: 88 }], HOJE) === depois, true);
  // dois pagamentos iguais pela conta e um só no cartão: o segundo está em trânsito
  assertEquals(somaEmTransito(comPagamentosEmTransito(vespera, [{ transaction_date: "2026-11-23", amount: 77 }, { transaction_date: "2026-11-23", amount: 77 }], HOJE)), 77);
  // o mesmo dia tem preferência sobre a véspera: o de 22/11 casa com o cartão de 22/11 e o de 23/11 fica em trânsito
  // (se a véspera viesse primeiro, o de 23/11 tomaria o par do de 22/11 — os dois teriam "par" e nada entraria)
  const doisDias = [...E, pagamento("2026-11-22", 90)];
  assertEquals(somaEmTransito(comPagamentosEmTransito(doisDias, [{ transaction_date: "2026-11-22", amount: 90 }, { transaction_date: "2026-11-23", amount: 90 }], HOJE)), 90);
  assertEquals(comPagamentosEmTransito(E, [{ transaction_date: "2026-11-25", amount: 10 }, { transaction_date: "2026-11-23", amount: 0 }], HOJE) === E, true);
  // crédito que não é pagamento (estorno) não serve de par
  const estorno = [...E, pagamento("2026-11-23", 45, C6, "Crédito de MERCADOLIVRE")];
  assertEquals(somaEmTransito(comPagamentosEmTransito(estorno, [{ transaction_date: "2026-11-23", amount: 45 }], HOJE)), 45);
});

Deno.test("cartaoDoPagamento: de qual cartão é a saída da conta (ou de nenhum)", () => {
  const cartoes = [{ conexao: C6, rotulo: "C6 - Conta PJ HBR" }, { conexao: NU, rotulo: "Nubank PJ HBR" }];
  const d = (description: string, counterparty_name: string | null, bank_connection_id: string | null) =>
    cartaoDoPagamento({ bank_connection_id, transaction_date: HOJE, amount: 1, description, counterparty_name }, cartoes);
  assertEquals(d("PGTO FAT CARTAO C6", null, C6), C6);
  assertEquals(d("PGTO FATURA CARTAO C6", "BANCO C6 S.A.", C6), C6);
  assertEquals(d("Pagamento de fatura", null, NU), NU); // sem emissor escrito: o cartão da mesma conexão
  assertEquals(d("Pix enviado para NU PAGAMENTOS S/A", "NU PAGAMENTOS S.A. - INSTITUICAO DE PAGAMENTO", C6), NU); // sai do C6, paga o Nubank
  assertEquals(d("Fatura de cartão", null, C6), C6);
  assertEquals(d("TRANSF ENVIADA PIX", "NU PAGAMENTOS S.A.", C6), NU); // Pix cujo favorecido é o emissor
  // o que NÃO é pagamento de fatura
  assertEquals(d("DEBITO DE CARTAO", null, C6), null); // compra no débito
  assertEquals(d("Pix enviado para JOAO DA SILVA", "JOAO DA SILVA", C6), null);
  assertEquals(d("Compra NUBANK STORE", null, C6), null);
  assertEquals(d("Pagamento de fatura", null, "conexao-ip"), null); // conta sem cartão conhecido
  assertEquals(d("Pagamento de fatura", null, null), null);
  // emissor escrito mas dois cartões dele (ou nenhum): não dá para saber qual
  const doC6 = { bank_connection_id: C6, transaction_date: HOJE, amount: 1, description: "PGTO FAT CARTAO C6" };
  assertEquals(cartaoDoPagamento(doC6, [{ conexao: "a", rotulo: "C6 PJ" }, { conexao: "b", rotulo: "C6 PF" }]), null);
  assertEquals(cartaoDoPagamento(doC6, [{ conexao: NU, rotulo: "Nubank PJ HBR" }]), null);
});

Deno.test("nomeDoCartao: o primeiro nome do rótulo da conexão", () => {
  assertEquals([nomeDoCartao("C6 - Conta PJ HBR"), nomeDoCartao("Nubank PJ HBR"), nomeDoCartao("  Inter  "), nomeDoCartao(""), nomeDoCartao(null)],
    ["C6", "Nubank", "Inter", "Cartão", "Cartão"]);
});

// ── A conta pelo calendário do banco ────────────────────────────────────────────────────────────────────────────────
/** C6: fecha dia 19, vence dia 25. A última fatura que o banco informou fechou em 19/10 (R$ 1.000). */
const DO_C6: FaturaInformada[] = [
  { fechamento: "2026-08-19", vencimento: "2026-08-25", total: 800 },
  { fechamento: "2026-09-19", vencimento: "2026-09-25", total: 900 },
  { fechamento: "2026-10-19", vencimento: "2026-10-25", total: "1000.00" },
];
/** Quitou a de outubro em 20/10, comprou R$ 500 até fechar em 19/11 e R$ 150 depois. */
const EXTRATO_C6: LinhaLida[] = [
  pagamento("2026-10-20", 1000), compra("2026-10-25", 300), compra("2026-11-10", 200), compra("2026-11-21", 150),
];
/** Nubank: fecha dia 3, vence dia 10 (uma vez no dia 13: fim de semana). A de novembro o banco já publicou (R$ 500). */
const DO_NUBANK: FaturaInformada[] = [
  { fechamento: "2026-09-03", vencimento: "2026-09-10", total: 700 },
  { fechamento: "2026-10-03", vencimento: "2026-10-13", total: 600 },
  { fechamento: "2026-11-03", vencimento: "2026-11-10", total: 500 },
];
const EXTRATO_NUBANK: LinhaLida[] = [pagamento("2026-11-03", 500, NU), compra("2026-11-05", 250, null, NU)];

Deno.test("faturasPeloBanco: o banco ainda não publicou a que fechou — data do calendário dele, valor pelo saldo", () => {
  const r = faturasPeloBanco("C6", EXTRATO_C6, DO_C6, HOJE);
  assertEquals(r.calendario, { diaDeFechamento: 19, diaDeVencimento: 25 });
  assertEquals([r.ancora, r.fechamentosSemOBanco], [{ fechamento: "2026-10-19", vencimento: "2026-10-25", total: 1000 }, 1]);
  assertEquals(r.faturas, [
    // 1.000 (a de outubro) + 500 cobrados − 1.000 pagos no ciclo = 500, vence 25/11
    { conta: "C6", valor: 500, total: 500, pago: 0, vencimento: "2026-11-25", fechamento: "2026-11-19", situacao: "fechada", vencida: false, origem: "extrato" },
    { conta: "C6", valor: 150, total: 150, pago: 0, vencimento: "2026-12-25", fechamento: "2026-12-19", situacao: "aberta", vencida: false, origem: "extrato" },
  ]);
});

Deno.test("faturasPeloBanco: o que foi pago depois de fechar abate a fechada; o que sobra adianta a aberta; coberta continua na lista até vencer", () => {
  const parte = faturasPeloBanco("C6", [...EXTRATO_C6, pagamento("2026-11-23", 400)], DO_C6, HOJE).faturas;
  assertEquals(parte.map((f) => [f.situacao, f.valor, f.total, f.pago]), [["fechada", 100, 500, 400], ["aberta", 150, 150, 0]]);

  const tudo = faturasPeloBanco("C6", [...EXTRATO_C6, pagamento("2026-11-23", 600)], DO_C6, HOJE).faturas;
  // coberta: falta 0, mas aparece (vence amanhã) com o total e o que foi pago; os R$ 100 a mais adiantam a aberta
  assertEquals(tudo.map((f) => [f.situacao, f.valor, f.total, f.pago, f.vencida]), [["fechada", 0, 500, 600, false], ["aberta", 50, 150, 100, false]]);
  // 6 dias depois do vencimento a coberta sai da lista
  assertEquals(faturasPeloBanco("C6", [...EXTRATO_C6, pagamento("2026-11-23", 600)], DO_C6, "2026-12-01").faturas.map((f) => f.situacao), ["aberta"]);

  // pagou adiantado mais do que gastou: no fechamento o saldo é crédito — nada em aberto, e o crédito abate a aberta
  const credito = faturasPeloBanco("C6", [...EXTRATO_C6, pagamento("2026-11-15", 620)], DO_C6, HOJE).faturas;
  assertEquals(credito.map((f) => [f.situacao, f.valor, f.total, f.pago]), [["fechada", 0, 0, 0], ["aberta", 30, 150, 120]]);
});

Deno.test("faturasPeloBanco: só é 'vencida' depois de 3 dias de folga (fim de semana e feriado empurram o vencimento)", () => {
  const na = (hoje: string) => faturasPeloBanco("C6", EXTRATO_C6, DO_C6, hoje).faturas.find((f) => f.situacao === "fechada")!;
  assertEquals([na("2026-11-25").vencida, na("2026-11-28").vencida, na("2026-11-29").vencida], [false, false, true]);
  assertEquals(na("2026-11-29").valor, 500); // vencida e sem pagamento: continua na lista
});

Deno.test("faturasPeloBanco: a última do banco é a que fechou — total do banco; o pagamento feito no dia do fechamento paga essa fatura", () => {
  const r = faturasPeloBanco("Nubank", EXTRATO_NUBANK, DO_NUBANK, "2026-11-08");
  assertEquals(r.calendario, { diaDeFechamento: 3, diaDeVencimento: 10 });
  assertEquals(r.fechamentosSemOBanco, 0);
  assertEquals(r.faturas, [
    { conta: "Nubank", valor: 0, total: 500, pago: 500, vencimento: "2026-11-10", fechamento: "2026-11-03", situacao: "fechada", vencida: false, origem: "banco" },
    { conta: "Nubank", valor: 250, total: 250, pago: 0, vencimento: "2026-12-10", fechamento: "2026-12-03", situacao: "aberta", vencida: false, origem: "extrato" },
  ]);
  // pagamento PARCIAL no dia do fechamento também é dela (medido: C6 de 18/04/2026, R$ 753,60 no dia + 200 + 4.070,40 =
  // os R$ 5.024,00 da fatura; descartar o do dia deixava a fatura quitada como "vencida" por 21 dias)
  const parcial = faturasPeloBanco("Nubank", [pagamento("2026-11-03", 480, NU), compra("2026-11-05", 250, null, NU)], DO_NUBANK, "2026-11-08").faturas;
  assertEquals(parcial.map((f) => [f.situacao, f.valor, f.pago]), [["fechada", 20, 480], ["aberta", 250, 0]]);
  const quitada = [pagamento("2026-11-03", 100, NU), pagamento("2026-11-05", 150, NU), pagamento("2026-11-07", 250, NU)];
  assertEquals(faturasPeloBanco("Nubank", quitada, DO_NUBANK, "2026-11-20").faturas, []); // paga e já vencida há mais de 5 dias: sai
  // em 24/11 a de novembro (paga, vencida há mais de 5 dias) já saiu; fica a aberta
  assertEquals(faturasPeloBanco("Nubank", EXTRATO_NUBANK, DO_NUBANK, HOJE).faturas.map((f) => [f.situacao, f.valor, f.vencimento]), [["aberta", 250, "2026-12-10"]]);
});

Deno.test("faturasPeloBanco: parcela com data futura entra na aberta só até o próximo fechamento; pagamento repetido conta uma vez", () => {
  const linhas = [...EXTRATO_C6, compra("2026-12-10", 80), compra("2027-01-10", 80),
    pagamento("2026-11-23", 100, C6, "Inclusao de Pagamento Ciclo Corrente"), pagamento("2026-11-23", 100)];
  assertEquals(faturasPeloBanco("C6", linhas, DO_C6, HOJE).faturas.map((f) => [f.situacao, f.valor, f.total, f.pago]),
    [["fechada", 400, 500, 100], ["aberta", 230, 230, 0]]);
  // estorno abate o ciclo em que cai; compra marcada como duplicata não conta
  const comEstorno = [...EXTRATO_C6, pagamento("2026-11-12", 60, C6, "Crédito de LOJA"), { ...compra("2026-11-13", 999), dismissed_kind: "duplicata" }];
  assertEquals(faturasPeloBanco("C6", comEstorno, DO_C6, HOJE).faturas[0].total, 440);
});

Deno.test("faturasPeloBanco: sem fatura do banco, com fatura sem data/total, ou com a última velha demais — não estima", () => {
  assertEquals(faturasPeloBanco("C6", EXTRATO_C6, [], HOJE), { faturas: [], calendario: null, ancora: null, fechamentosSemOBanco: 0 });
  const ruins = [{ fechamento: "", vencimento: "2026-10-25", total: 10 }, { fechamento: "2026-10-19", vencimento: "25/10", total: 10 },
    { fechamento: "2026-10-19", vencimento: "2026-10-25", total: null as unknown as number }, { fechamento: "2026-10-19", vencimento: "2026-10-25", total: "abc" },
    { fechamento: "2026-12-19", vencimento: "2026-12-25", total: 10 }]; // a do futuro não é âncora
  assertEquals(faturasPeloBanco("C6", EXTRATO_C6, ruins, HOJE).ancora, null);
  // o banco não publica há 3 fechamentos: a conta não se sustenta
  const velha = faturasPeloBanco("C6", EXTRATO_C6, DO_C6.slice(0, 1), HOJE);
  assertEquals([velha.faturas, velha.fechamentosSemOBanco, velha.ancora?.fechamento], [[], 3, "2026-08-19"]);
  // no dia do fechamento a fatura já fechou (o que tem a data do dia é da seguinte); na véspera ainda está aberta
  assertEquals(faturasPeloBanco("C6", EXTRATO_C6, DO_C6, "2026-11-19").faturas.map((f) => [f.situacao, f.fechamento, f.valor]),
    [["fechada", "2026-11-19", 500], ["aberta", "2026-12-19", 150]]);
  assertEquals(faturasPeloBanco("C6", EXTRATO_C6, DO_C6, "2026-11-18").faturas.map((f) => [f.situacao, f.fechamento, f.valor]),
    [["aberta", "2026-11-19", 500]]);
});

Deno.test("faturasPeloBanco: o que tem data NO dia do fechamento é da fatura seguinte (como o banco faz)", () => {
  // compra no dia em que a última fatura do banco fechou: o total do banco não a contém — é da seguinte
  const noDiaDaAncora = faturasPeloBanco("C6", [...EXTRATO_C6, compra("2026-10-19", 70)], DO_C6, HOJE).faturas;
  assertEquals(noDiaDaAncora.map((f) => [f.situacao, f.total]), [["fechada", 570], ["aberta", 150]]);
  // compra e estorno no dia do fechamento projetado (19/11): saem da que fechou e entram na aberta
  const noDia = faturasPeloBanco("C6", [...EXTRATO_C6, compra("2026-11-19", 90), pagamento("2026-11-19", 15, C6, "Crédito de LOJA")], DO_C6, HOJE).faturas;
  assertEquals(noDia.map((f) => [f.situacao, f.total]), [["fechada", 500], ["aberta", 225]]);
  // pagamento no dia do fechamento projetado paga a que fechou
  const pagoNoDia = faturasPeloBanco("C6", [...EXTRATO_C6, pagamento("2026-11-19", 500)], DO_C6, HOJE).faturas;
  assertEquals(pagoNoDia.map((f) => [f.situacao, f.valor, f.total, f.pago]), [["fechada", 0, 500, 500], ["aberta", 150, 150, 0]]);
});

Deno.test("faturasPeloBanco: o vencimento é a mediana DE BAIXO das 4 últimas (o banco só adia; dizer um dia depois custa multa)", () => {
  const adiadas: FaturaInformada[] = [
    { fechamento: "2026-07-03", vencimento: "2026-07-10", total: 1 }, { fechamento: "2026-08-03", vencimento: "2026-08-10", total: 1 },
    { fechamento: "2026-09-03", vencimento: "2026-09-11", total: 1 }, { fechamento: "2026-10-03", vencimento: "2026-10-13", total: 1 },
    { fechamento: "2026-11-03", vencimento: "2026-11-12", total: 1 },
  ];
  // as 4 últimas vencem 10, 11, 12 e 13: a mediana arredondada daria 12; a de baixo dá 11
  assertEquals(faturasPeloBanco("Nubank", [], adiadas, HOJE).calendario, { diaDeFechamento: 3, diaDeVencimento: 11 });
  assertEquals(faturasPeloBanco("Nubank", [], adiadas.slice(0, 2), "2026-08-20").calendario, { diaDeFechamento: 3, diaDeVencimento: 10 });
});

Deno.test("semParcelaRepetida: a parcela pendente que já tem a mesma lançada sai; compra comum de mesmo nome e valor fica", () => {
  const l = (data: string, valor: number, descricao: string, situacao: string, tipo = "debit") => ({
    ...compra(data, valor, null, NU), description: descricao, transaction_type: tipo, tx_status: situacao,
  });
  const linhas = [
    l("2026-10-03", 89.63, "Petz Itajai 3/3", "POSTED"), l("2026-10-17", 89.63, "Petz Itajai 3/3", "PENDING"), // a cópia que ficou para trás
    l("2026-12-04", 779.94, "Compensados Fernandes 2/3", "PENDING"), // parcela futura de verdade: fica
    l("2026-09-28", 17, "POSTO PAULINHO NAVEGANTES", "POSTED"), l("2026-10-26", 17, "POSTO PAULINHO NAVEGANTES", "PENDING"), // outra compra: fica
    l("2026-09-29", 50, "Inclusao de Pagamento Ciclo Corrente", "POSTED", "credit"), l("2026-10-25", 50, "Inclusao de Pagamento Ciclo Corrente", "PENDING", "credit"),
    l("2026-10-03", 62.9, "Mercado*Mercadolivre 2/2", "POSTED"), l("2026-10-17", 62.9, "Mercado*Mercadolivre 2/2", "PENDING"), l("2026-10-18", 62.9, "Mercado*Mercadolivre 2/2", "PENDING"),
  ];
  const ficou = semParcelaRepetida(linhas);
  // uma lançada cancela UMA pendente: das duas pendentes do Mercadolivre, fica a segunda
  assertEquals(ficou.map((x) => `${x.transaction_date} ${x.description}`), [
    "2026-10-03 Petz Itajai 3/3", "2026-12-04 Compensados Fernandes 2/3", "2026-09-28 POSTO PAULINHO NAVEGANTES", "2026-10-26 POSTO PAULINHO NAVEGANTES",
    "2026-09-29 Inclusao de Pagamento Ciclo Corrente", "2026-10-25 Inclusao de Pagamento Ciclo Corrente",
    "2026-10-03 Mercado*Mercadolivre 2/2", "2026-10-18 Mercado*Mercadolivre 2/2",
  ]);
  // sem situação informada (a tela não lê) nada muda — a MESMA lista
  assertEquals(semParcelaRepetida(EXTRATO_C6) === EXTRATO_C6, true);
  // e a conta usa: a cópia pendente não soma de novo
  const doNubank = [l("2026-11-04", 100, "Loja 2/3", "POSTED"), l("2026-11-20", 100, "Loja 2/3", "PENDING")];
  assertEquals(faturasPeloBanco("Nubank", doNubank, DO_NUBANK, HOJE).faturas.find((f) => f.situacao === "aberta")!.total, 100);
});

// ── As faturas de todos os cartões ─────────────────────────────────────────────────────────────────────────────────
const lidas = (lista: FaturaInformada[], conexao: string): FaturaLida[] => lista.map((f) => ({ ...f, bank_connection_id: conexao }));
const DO_BANCO = [...lidas(DO_C6, C6), ...lidas(DO_NUBANK, NU)];

Deno.test("cartoesDoExtrato: as faturas em ordem de vencimento, o pagamento da véspera lido da conta, e o que fica de fora com aviso", () => {
  const extrato = [...EXTRATO_C6, ...EXTRATO_NUBANK];
  const semConta = cartoesDoExtrato(extrato, [], ROTULOS, DO_BANCO, HOJE);
  assertEquals(semConta.faturas.map((f) => [f.cartao, f.situacao, f.valor, f.vencimento, f.origem]), [
    ["C6", "fechada", 500, "2026-11-25", "extrato"],
    ["Nubank", "aberta", 250, "2026-12-10", "extrato"],
    ["C6", "aberta", 150, "2026-12-25", "extrato"],
  ]);
  assertEquals([semConta.emTransito, semConta.avisos], [0, []]);

  const debitos = [
    debito("2026-11-23", 400), // paga parte do que falta do C6
    debito("2026-11-23", 999, { description: "Pix enviado para FORNECEDOR", counterparty_name: "FORNECEDOR LTDA" }), // não é fatura
    debito("2026-11-23", 400, { dismissed_kind: "duplicata" }), // cópia marcada: não conta de novo
  ];
  const r = cartoesDoExtrato(extrato, debitos, ROTULOS, DO_BANCO, HOJE);
  assertEquals(r.faturas.map((f) => [f.cartao, f.situacao, f.valor, f.pago]), [["C6", "fechada", 100, 400], ["Nubank", "aberta", 250, 0], ["C6", "aberta", 150, 0]]);
  assertEquals(r.emTransito, 400);

  // cartão em uso sem fatura do banco, e cartão com a última fatura velha demais: de fora, com o motivo
  const semBanco = cartoesDoExtrato(extrato, [], ROTULOS, lidas(DO_C6.slice(0, 1), C6), HOJE);
  assertEquals(semBanco.faturas, []);
  assertEquals(semBanco.avisos, [
    "Cartão C6: o banco não informa fatura desde a que fechou em 19/08; ficou de fora.",
    "Cartão Nubank: ainda não tenho as faturas do banco; ficou de fora.",
  ]);
  // cartão parado há mais de 60 dias some sem aviso; linha sem conexão é ignorada
  const parado = [compra("2026-06-01", 100, "x", "conexao-velha"), { ...compra("2026-11-03", 100), bank_connection_id: null }];
  assertEquals(cartoesDoExtrato(parado, [], ROTULOS, DO_BANCO, HOJE), { faturas: [], avisos: [], emTransito: 0 });
});

/** Banco de mentira: responde por tabela e filtro, em páginas de 1.000, e conta as leituras. */
function banco(opcoes: { chave?: unknown; linhas?: LinhaLida[]; debitos?: DebitoLido[]; doBanco?: FaturaLida[]; erro?: string } = {}) {
  const leituras: string[] = [];
  const admin = {
    from(tabela: string) {
      const filtros: Qualquer = {};
      const q: Qualquer = {
        select: () => q,
        eq: (coluna: string, valor: unknown) => { filtros[coluna] = valor; return q; },
        gte: () => q,
        order: () => q,
        maybeSingle: () => {
          leituras.push(`${tabela}:${filtros.key}`);
          return Promise.resolve({ data: opcoes.chave !== undefined ? { value: opcoes.chave } : null, error: null });
        },
        range: (de: number, ate: number) => {
          const qual = tabela === "cartao_faturas_do_banco" ? "faturas" : String(filtros.source_type);
          leituras.push(`${tabela}:${qual}:${de}`);
          if (opcoes.erro === qual) return Promise.resolve({ data: null, error: { message: "statement timeout", code: "57014" } });
          const todas = qual === "faturas" ? (opcoes.doBanco ?? []) : qual === "credit_card" ? (opcoes.linhas ?? []) : (opcoes.debitos ?? []);
          return Promise.resolve({ data: todas.slice(de, ate + 1), error: null });
        },
        then: (ok: (v: unknown) => unknown) => {
          leituras.push(tabela);
          return Promise.resolve({ data: [...ROTULOS].map(([id, label]) => ({ id, label })), error: opcoes.erro === "conexoes" ? { message: "sem permissão" } : null }).then(ok);
        },
      };
      return q;
    },
  };
  return { admin, leituras };
}

Deno.test("lerCartoes: lê o extrato do cartão, as saídas recentes da conta, as faturas do banco e os rótulos", async () => {
  const b = banco({ linhas: EXTRATO_C6, debitos: [debito("2026-11-23", 400)], doBanco: lidas(DO_C6, C6) });
  const r = await lerCartoes(b.admin, HOJE);
  assertEquals(r.faturas.map((f) => [f.cartao, f.situacao, f.valor, f.vencimento]), [["C6", "fechada", 100, "2026-11-25"], ["C6", "aberta", 150, "2026-12-25"]]);
  assertEquals(r.emTransito, 400);
  assertEquals(b.leituras, [`app_settings:${CHAVE_DOS_CARTOES}`, "bank_transactions:credit_card:0", "bank_transactions:bank:0",
    "cartao_faturas_do_banco:faturas:0", "bank_connections"]);
});

Deno.test("lerCartoes: mais de 1.000 linhas vêm em páginas (extrato cortado mudaria a conta calado)", async () => {
  const muitas = [...Array.from({ length: 1500 }, (_, i) => compra("2026-07-01", 1 + i / 100, "antiga")), ...EXTRATO_C6];
  const b = banco({ linhas: muitas, doBanco: lidas(DO_C6, C6) });
  const r = await lerCartoes(b.admin, HOJE);
  assertEquals(b.leituras.filter((l) => l.startsWith("bank_transactions:credit_card")), ["bank_transactions:credit_card:0", "bank_transactions:credit_card:1000"]);
  assertEquals(r.faturas[0].valor, 500); // as compras antigas, de antes da última fatura do banco, não entram na conta
});

Deno.test("lerCartoes: chave desligada ou sem cartão = vazio sem ler o resto; erro de leitura LANÇA (não vira 'sem fatura')", async () => {
  for (const chave of ["desligado", '"desligado"', " Desligado "]) {
    const b = banco({ chave, linhas: EXTRATO_C6, doBanco: lidas(DO_C6, C6) });
    assertEquals(await lerCartoes(b.admin, HOJE), { faturas: [], avisos: [], emTransito: 0 });
    assertEquals(b.leituras.length, 1);
  }
  const semCartao = banco({ chave: "ligado" });
  assertEquals(await lerCartoes(semCartao.admin, HOJE), { faturas: [], avisos: [], emTransito: 0 });
  assertEquals(semCartao.leituras.length, 2);
  for (const erro of ["credit_card", "bank", "faturas", "conexoes"]) {
    await assertRejects(() => lerCartoes(banco({ linhas: EXTRATO_C6, doBanco: lidas(DO_C6, C6), erro }).admin, HOJE));
  }
});
