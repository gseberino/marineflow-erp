import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { despesasPendentesDoMes, faturamentoPorCliente, GRUPOS_DO_RESULTADO, notaDoMes } from "./mes.ts";

const fmt0 = (v: number) => `R$ ${Math.round(v).toLocaleString("pt-BR")}`;

// Fila de saídas pendentes de 01 a 15/10/2026 (SELECT de 15/10), agregada por grupo e categoria:
// 35 itens; 27 (R$ 11.143,82) nos grupos do resultado e 8 em nao_operacional (R$ 4.951,02).
function filaReal() {
  const fila: Array<{ suggested_amount: number | string | null; dre_group: string | null; suggested_category: string | null }> = [];
  const add = (n: number, total: number, dre_group: string | null, suggested_category: string) => {
    // n itens que somam `total` (o último leva o arredondamento).
    const cada = Math.floor((total / n) * 100) / 100;
    for (let i = 0; i < n; i++) {
      const v = i === n - 1 ? Math.round((total - cada * (n - 1)) * 100) / 100 : cada;
      fila.push({ suggested_amount: v.toFixed(2), dre_group, suggested_category });
    }
  };
  add(1, 493.00, "custo_direto", "Alimentação de campo");
  add(2, 610.00, "custo_direto", "Diárias de freelancers");
  add(1, 898.81, "despesa_operacional", "Contabilidade e assessoria");
  add(1, 800.00, "despesa_operacional", "Gasto Pessoal Sócio - Descontar PL");
  add(13, 5946.96, "despesa_operacional", "Outras despesas");
  add(5, 1900.00, "despesa_operacional", "Pró-labore");
  add(1, 249.00, "despesa_operacional", "Telefonia e internet");
  add(3, 246.05, "financeiro", "Juros e encargos");
  add(1, 1500.00, "nao_operacional", "Aplicação financeira");
  add(1, 371.73, "nao_operacional", "Empréstimo e financiamento");
  add(6, 3079.29, "nao_operacional", "Pagamento de fatura de cartão");
  return fila;
}

Deno.test("despesasPendentesDoMes: o 15/10 real — 27 despesas, R$ 11.143,82 (fora as não operacionais)", () => {
  const fila = filaReal();
  assertEquals(fila.length, 35);
  const r = despesasPendentesDoMes(fila, new Map());
  assertEquals(r.n, 27);
  assertEquals(Math.round(r.soma * 100) / 100, 11143.82);
});

Deno.test("despesasPendentesDoMes: sem grupo na fila, vale o grupo da categoria", () => {
  const r = despesasPendentesDoMes([
    { suggested_amount: 100, dre_group: null, suggested_category: "Combustível e deslocamento" },
    { suggested_amount: 50, dre_group: null, suggested_category: "Pagamento de fatura de cartão" },
    { suggested_amount: 30, dre_group: null, suggested_category: null },
  ], new Map([["Combustível e deslocamento", "custo_direto"], ["Pagamento de fatura de cartão", "nao_operacional"]]));
  assertEquals(r, { n: 1, soma: 100 });
  assertEquals([...GRUPOS_DO_RESULTADO], ["custo_direto", "despesa_operacional", "financeiro"]);
});

Deno.test("notaDoMes: despesas a conferir e entradas sem receita — o resultado real é menor", () => {
  assertEquals(
    notaDoMes({ despesasPendentes: { n: 27, soma: 11143.82 }, entradasSemReceita: { n: 2, soma: 7283 } }, fmt0),
    " (faltam conferir 27 despesas do mês, R$ 11.144 — o resultado real é menor; 2 entradas do banco, R$ 7.283, ainda sem receita lançada)",
  );
});

Deno.test("notaDoMes: só despesas; só entradas; nada pendente", () => {
  assertEquals(
    notaDoMes({ despesasPendentes: { n: 1, soma: 80 }, entradasSemReceita: { n: 0, soma: 0 } }, fmt0),
    " (falta conferir 1 despesa do mês, R$ 80 — o resultado real é menor)",
  );
  assertEquals(
    notaDoMes({ despesasPendentes: { n: 0, soma: 0 }, entradasSemReceita: { n: 1, soma: 783 } }, fmt0),
    " (1 entrada do banco, R$ 783, ainda sem receita lançada — o resultado pode ser maior)",
  );
  assertEquals(
    notaDoMes({ despesasPendentes: { n: 0, soma: 0 }, entradasSemReceita: { n: 3, soma: 900 } }, fmt0),
    " (3 entradas do banco, R$ 900, ainda sem receita lançada — o resultado pode ser maior)",
  );
  assertEquals(notaDoMes({ despesasPendentes: { n: 0, soma: 0 }, entradasSemReceita: { n: 0, soma: 0 } }, fmt0), "");
});

// Recebíveis emitidos de 01 a 15/10/2026 (SELECT de 15/10): a mesma base da "receita" do mês (R$ 38.729).
const RECEBIVEIS = [
  { amount: "16890.00", status: "pending", client_id: "0a39", nome: "Marcelo Marco Bertoldi" },
  { amount: "7600.00", status: "paid", client_id: "259c", nome: "Nelson" },
  { amount: "5600.00", status: "paid", client_id: "510a", nome: "Cliente Final" },
  { amount: "2900.00", status: "pending", client_id: "259c", nome: "Nelson" },
  { amount: "2869.50", status: "paid", client_id: "5b53", nome: "Giancarlo Ribeiro dos Santos" },
  { amount: "2869.50", status: "pending", client_id: "5b53", nome: "Giancarlo Ribeiro dos Santos" },
];

Deno.test("faturamentoPorCliente: o 15/10 real — Marcelo, Nelson e Giancarlo, sem 'concentrado'", () => {
  assertEquals(faturamentoPorCliente(RECEBIVEIS), "🏆 Faturamento do mês por cliente: Marcelo 44% · Nelson 27% · Giancarlo 15%");
});

Deno.test("faturamentoPorCliente: um cliente só não vira linha; cancelado não entra", () => {
  assertEquals(faturamentoPorCliente([RECEBIVEIS[1], RECEBIVEIS[3]]), null);
  assertEquals(faturamentoPorCliente([RECEBIVEIS[1], { ...RECEBIVEIS[0], status: "cancelled" }]), null);
  assertEquals(faturamentoPorCliente([]), null);
});

Deno.test("faturamentoPorCliente: 'concentrado' só com o 1º em 50% ou mais", () => {
  assertEquals(
    faturamentoPorCliente([
      { amount: 600, status: "paid", client_id: "a", nome: "Ana Souza" },
      { amount: 400, status: "pending", client_id: "b", nome: "Beto" },
    ]),
    "🏆 Faturamento do mês por cliente: Ana 60% · Beto 40% — concentrado",
  );
});
