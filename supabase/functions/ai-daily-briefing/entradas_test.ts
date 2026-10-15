import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { linhasDasEntradas, separarEntradas, type EntradaDoBanco, type PagamentoSemExtrato } from "./entradas.ts";

const moeda = (v: number) =>
  `R$ ${v.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

// Fixture copiada do SELECT de 15/10/2026: créditos do banco não conciliados (todos source_type
// 'bank', dismissed_at nulo) e os pagamentos confirmados sem linha do extrato dos últimos 60 dias.
const ENTRADAS: EntradaDoBanco[] = [
  { id: "d9445777", transaction_date: "2026-10-05", amount: "7600.00", description: "Pix recebido de NELSON A B SOUZA" },
  { id: "75746706", transaction_date: "2026-10-09", amount: "6500.00", description: "Pix recebido de JEAN CARLOS DALMARCO" },
  { id: "f9cd743c", transaction_date: "2026-10-13", amount: "2869.50", description: "Pix recebido c6 de JEANINE GAMBORGI RAMOS" },
  { id: "16e364db", transaction_date: "2026-04-10", amount: "1000.00", description: "65.010.587 CRISLAINE REGINA CIOLI" },
  { id: "f76f20fa", transaction_date: "2026-10-05", amount: "783.00", description: "MP MOTORHOMES RVS ESTACIONAMENTO LTDA" },
  { id: "59777142", transaction_date: "2026-03-20", amount: "11.40", description: "AXK4J38-ARTERIS LITORAL SUL  BR101 1574" },
  { id: "34cc3028", transaction_date: "2026-02-20", amount: "11.40", description: "AXK4J38-ARTERIS LITORAL SUL  BR101 1574" },
  { id: "14bce45c", transaction_date: "2025-11-25", amount: "11.40", description: "AXK4J38-ARTERIS LITORAL SUL  BR101 793 S" },
  { id: "c40b8d03", transaction_date: "2025-09-19", amount: "11.40", description: "AXK4J38-ARTERIS LITORAL SUL  BR101 793 N" },
  { id: "eb1c966c", transaction_date: "2026-04-23", amount: "0.35", description: "CHEQUE ESPECIAL" },
];
const PAGAMENTOS: PagamentoSemExtrato[] = [
  { id: "9623c9f2", amount: "2869.50", payment_date: "2026-10-13", rotulo: "Sinal — ORÇ-00100 (Giancarlo Ribeiro dos Santos)", forma: "pix" },
  { id: "ea8dab63", amount: "5600.00", payment_date: "2026-10-09", rotulo: "Sinal — ORÇ-00110 (Cliente Final)", forma: "pix" },
  { id: "6bff3c68", amount: "7600.00", payment_date: "2026-10-05", rotulo: "Sinal — ORÇ-00112 (Nelson)", forma: "pix" },
  { id: "aefdf37f", amount: "1080.00", payment_date: "2026-09-08", rotulo: "Sinal — ORÇ-00094 (José)", forma: "cash" },
];
const HOJE = "2026-10-15";
const soma = (l: EntradaDoBanco[]) => Math.round(l.reduce((s, e) => s + Number(e.amount), 0) * 100) / 100;

Deno.test("separarEntradas: o 15/10 real — 2 do mês, 2 sinais já lançados, 6 antigas", () => {
  const s = separarEntradas(ENTRADAS, PAGAMENTOS, HOJE);
  assertEquals(s.doMes.map((e) => Number(e.amount)), [6500, 783]);
  assertEquals(s.sinais.map((x) => [Number(x.entrada.amount), x.rotulo]), [
    [7600, "Sinal — ORÇ-00112 (Nelson)"],
    [2869.5, "Sinal — ORÇ-00100 (Giancarlo Ribeiro dos Santos)"],
  ]);
  assertEquals(s.antigas.length, 6);
  assertEquals(soma(s.antigas), 1045.95);
  // Nada some: as 10 entradas (R$ 18.798,45) estão nas três listas.
  assertEquals(soma([...s.doMes, ...s.sinais.map((x) => x.entrada), ...s.antigas]), 18798.45);
});

Deno.test("separarEntradas: pagamento a 8 dias não casa; a 7 casa", () => {
  const e: EntradaDoBanco[] = [{ id: "a", transaction_date: "2026-10-13", amount: 500, description: "Pix" }];
  assertEquals(separarEntradas(e, [{ id: "p", amount: 500, payment_date: "2026-10-05", rotulo: "Sinal" }], HOJE).sinais.length, 0);
  assertEquals(separarEntradas(e, [{ id: "p", amount: 500, payment_date: "2026-10-06", rotulo: "Sinal" }], HOJE).sinais.length, 1);
});

Deno.test("separarEntradas: diferença de R$ 1,01 não casa; de R$ 1,00 casa", () => {
  const e: EntradaDoBanco[] = [{ id: "a", transaction_date: "2026-10-13", amount: "500.00", description: "Pix" }];
  assertEquals(separarEntradas(e, [{ id: "p", amount: "501.01", payment_date: "2026-10-13", rotulo: "Sinal" }], HOJE).sinais.length, 0);
  assertEquals(separarEntradas(e, [{ id: "p", amount: "501.00", payment_date: "2026-10-13", rotulo: "Sinal" }], HOJE).sinais.length, 1);
});

Deno.test("separarEntradas: um pagamento não casa duas entradas iguais", () => {
  const e: EntradaDoBanco[] = [
    { id: "a", transaction_date: "2026-10-05", amount: 7600, description: "Pix A" },
    { id: "b", transaction_date: "2026-10-05", amount: 7600, description: "Pix B" },
  ];
  const s = separarEntradas(e, [{ id: "p", amount: 7600, payment_date: "2026-10-05", rotulo: "Sinal" }], HOJE);
  assertEquals(s.sinais.length, 1);
  assertEquals(s.doMes.length, 1);
});

Deno.test("separarEntradas: pagamento em dinheiro nunca casa um Pix (revisão de 15/10)", () => {
  // O sinal da ORÇ-00094 (José, R$ 1.080) foi pago em dinheiro: um Pix de R$ 1.080 dois dias depois,
  // de outra pessoa, é dinheiro por identificar — não pode sumir na linha do escritório.
  const e: EntradaDoBanco[] = [{ id: "a", transaction_date: "2026-10-10", amount: "1080.00", description: "Pix recebido de FULANO" }];
  const emDinheiro: PagamentoSemExtrato = { id: "p", amount: "1080.00", payment_date: "2026-10-08", rotulo: "Sinal — ORÇ-00094 (José)", forma: "cash" };
  const s = separarEntradas(e, [emDinheiro], HOJE);
  assertEquals(s.sinais.length, 0);
  assertEquals(s.doMes.map((x) => x.id), ["a"]);
  // O mesmo pagamento por Pix casa (e sem a forma, como antes, também).
  assertEquals(separarEntradas(e, [{ ...emDinheiro, forma: "pix" }], HOJE).sinais.length, 1);
  assertEquals(separarEntradas(e, [{ ...emDinheiro, forma: undefined }], HOJE).sinais.length, 1);
});

Deno.test("linhasDasEntradas: pagamento que não é sinal não é chamado de sinal (revisão de 15/10)", () => {
  const s = separarEntradas(
    [{ id: "a", transaction_date: "2026-10-13", amount: "16890.00", description: "Pix recebido de MARCELO" },
      { id: "b", transaction_date: "2026-10-05", amount: "7600.00", description: "Pix recebido de NELSON A B SOUZA" }],
    [{ id: "p1", amount: "16890.00", payment_date: "2026-10-13", rotulo: "À vista — OS-00038 (Marcelo Marco Bertoldi)", forma: "pix" },
      { id: "p2", amount: "7600.00", payment_date: "2026-10-05", rotulo: "Sinal — ORÇ-00112 (Nelson)", forma: "pix" }],
    HOJE,
  );
  assertEquals(linhasDasEntradas(s, moeda, new Map(), HOJE), [
    "🏦 Escritório: 2 pagamentos já lançados para ligar ao extrato, não aprovar como receita nova (R$ 24.490,00)",
  ]);
});

Deno.test("separarEntradas: R$ 9,99 do mês vai para centavos; R$ 10,00 do mês fica no mês", () => {
  const s = separarEntradas([
    { id: "a", transaction_date: "2026-10-14", amount: "9.99", description: "x" },
    { id: "b", transaction_date: "2026-10-14", amount: "10.00", description: "y" },
    { id: "c", transaction_date: "2026-09-30", amount: "900.00", description: "setembro" },
  ], [], HOJE);
  assertEquals(s.doMes.map((e) => e.id), ["b"]);
  assertEquals(s.antigas.map((e) => e.id).sort(), ["a", "c"]);
});

Deno.test("linhasDasEntradas: o 15/10 real vira o cabeçalho do mês, 2 itens e a linha do escritório", () => {
  const s = separarEntradas(ENTRADAS, PAGAMENTOS, HOJE);
  const l = linhasDasEntradas(s, moeda, new Map(), HOJE);
  assertEquals(l, [
    "🏦 Entradas do banco sem identificação (outubro): *2* (R$ 7.283,00)",
    "   • R$ 6.500,00 — Pix recebido de JEAN CARLOS DALMARCO",
    "   • R$ 783,00 — MP MOTORHOMES RVS ESTACIONAMENTO LTDA",
    "   Escritório: 2 sinais já lançados para ligar ao extrato, não aprovar como receita nova (R$ 10.469,50) · 6 antigas ou de centavos (R$ 1.045,95)",
  ]);
});

Deno.test("linhasDasEntradas: o palpite do motor aparece no item do mês", () => {
  const s = separarEntradas(ENTRADAS, PAGAMENTOS, HOJE);
  const l = linhasDasEntradas(s, moeda, new Map([["75746706", "Saldo — OS-00120 (Jean) · 80%"]]), HOJE);
  assertEquals(l[1], "   • R$ 6.500,00 — parece ser Saldo — OS-00120 (Jean) · 80%");
});

Deno.test("linhasDasEntradas: sem entrada do mês, só a linha do escritório com o 🏦; singular certo", () => {
  const s = separarEntradas([
    { id: "a", transaction_date: "2026-10-05", amount: 7600, description: "Pix" },
    { id: "b", transaction_date: "2026-03-20", amount: 11.4, description: "pedágio" },
  ], [{ id: "p", amount: 7600, payment_date: "2026-10-05", rotulo: "Sinal" }], HOJE);
  const l = linhasDasEntradas(s, moeda, new Map(), HOJE);
  assertEquals(l, [
    "🏦 Escritório: 1 sinal já lançado para ligar ao extrato, não aprovar como receita nova (R$ 7.600,00) · 1 antiga ou de centavos (R$ 11,40)",
  ]);
});

Deno.test("linhasDasEntradas: nada pendente, nenhuma linha; mais de 3 do mês mostra só 3", () => {
  assertEquals(linhasDasEntradas(separarEntradas([], [], HOJE), moeda, new Map(), HOJE), []);
  const cinco = Array.from({ length: 5 }, (_, i) => ({ id: `e${i}`, transaction_date: "2026-10-10", amount: 100 + i, description: `Pix ${i}` }));
  const l = linhasDasEntradas(separarEntradas(cinco, [], HOJE), moeda, new Map(), HOJE);
  assertStringIncludes(l[0], "*5*");
  assertEquals(l.filter((x) => x.startsWith("   •")).length, 3);
  assert(!l.some((x) => x.includes("Escritório")));
});
