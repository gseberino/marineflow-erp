import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { linhaDasPropostas, linhaDoOrcamento, linhaSeHouver, nomeDeContato, tentativasAte } from "./linhas.ts";

const moeda = (v: number) =>
  `R$ ${v.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

// Fila pendente de 15/10/2026 por tipo (SELECT): 46 saídas R$ 16.992,26 · 4 entradas R$ 17.752,50 ·
// 1 transferência R$ 300,00 · 15 alertas do vigilante (anomaly, que não são proposta de lançamento).
function filaReal() {
  const fila: Array<{ kind: string; suggested_amount: number | string | null }> = [];
  const add = (n: number, total: number, kind: string) => {
    const cada = Math.floor((total / n) * 100) / 100;
    for (let i = 0; i < n; i++) {
      fila.push({ kind, suggested_amount: (i === n - 1 ? Math.round((total - cada * (n - 1)) * 100) / 100 : cada).toFixed(2) });
    }
  };
  add(46, 16992.26, "create_payable");
  add(4, 17752.50, "create_receivable");
  add(1, 300.00, "internal_transfer");
  add(15, 7975.94, "anomaly");
  return fila;
}

Deno.test("linhaDasPropostas: o 15/10 real — saídas, entradas e transferência separadas", () => {
  assertEquals(
    linhaDasPropostas(filaReal(), moeda),
    "🧾 Propostas de lançamento esperando você: *51* — 46 saídas (R$ 16.992,26) · 4 entradas (R$ 17.752,50) · 1 transferência (R$ 300,00)",
  );
});

Deno.test("linhaDasPropostas: só saídas; tipo desconhecido vira 'outras'; só alertas = sem linha", () => {
  assertEquals(
    linhaDasPropostas([{ kind: "create_payable", suggested_amount: "10.00" }], moeda),
    "🧾 Propostas de lançamento esperando você: *1* — 1 saída (R$ 10,00)",
  );
  assertEquals(
    linhaDasPropostas([
      { kind: "create_payable", suggested_amount: 10 },
      { kind: "create_payable", suggested_amount: 5 },
      { kind: "split_payment", suggested_amount: 7 },
    ], moeda),
    "🧾 Propostas de lançamento esperando você: *3* — 2 saídas (R$ 15,00) · 1 outra (R$ 7,00)",
  );
  assertEquals(linhaDasPropostas([{ kind: "anomaly", suggested_amount: 99 }], moeda), null);
  assertEquals(linhaDasPropostas([], moeda), null);
});

Deno.test("linhaSeHouver: zero não ocupa linha", () => {
  assertEquals(linhaSeHouver("📅 Agendamentos hoje", 0), null);
  assertEquals(linhaSeHouver("📅 Agendamentos hoje", null), null);
  assertEquals(linhaSeHouver("📅 Agendamentos hoje", 2), "📅 Agendamentos hoje: *2*");
  assertEquals(linhaSeHouver("✅ Aprovações da IA pendentes", 1), "✅ Aprovações da IA pendentes: *1*");
});

Deno.test("nomeDeContato: o nome real da Climatec vira uma linha só", () => {
  const climatec = "Climatec Refrigeração — seu conforto em boas mãos!\n\nClimatec Refrigeraç\nEsc";
  const n = nomeDeContato(climatec);
  assertEquals(n, "Climatec Refrigeração — seu conforto em…");
  assertEquals(n.includes("\n"), false);
  assertEquals(nomeDeContato("  Jorge   Girardon "), "Jorge Girardon");
  assertEquals(nomeDeContato(null), "");
  assertEquals(nomeDeContato("x".repeat(40)), "x".repeat(40));
});

Deno.test("linhaDoOrcamento: número, cliente e barco", () => {
  assertEquals(
    linhaDoOrcamento({ numero: "ORÇ-00095", cliente: "MP MOTOR HOMES", barco: "Industrailer Scania", valor: 14461, dias: 8, expired: false, expiringSoon: false }, moeda),
    "   • ORÇ-00095 · MP MOTOR HOMES (Industrailer Scania) — R$ 14.461,00 · parado 8d",
  );
  assertEquals(
    linhaDoOrcamento({ numero: "ORÇ-00111", cliente: "Cliente Final", barco: "Motorhome", valor: 4254.69, dias: 1, expired: true, expiringSoon: false }, moeda),
    "   • ORÇ-00111 · Cliente Final (Motorhome) — R$ 4.254,69 · parado 1d · ⚠️ expirado",
  );
  assertEquals(
    linhaDoOrcamento({ numero: "ORÇ-00120", cliente: "Ana", barco: null, valor: 100, dias: 3, expired: false, expiringSoon: true }, moeda),
    "   • ORÇ-00120 · Ana — R$ 100,00 · parado 3d · ⏳ expira em breve",
  );
});

Deno.test("tentativasAte: o resumo das 07:30 tenta até as 09:00; nunca menos que 3", () => {
  // 07:30 de Brasília: 10 tentativas, de 10 em 10 min (o intervalo real da fila) — 07:35 … 09:05.
  assertEquals(tentativasAte("09:00", new Date("2026-10-15T10:30:00Z")), 10);
  assertEquals(tentativasAte("09:00", new Date("2026-10-15T10:30:08Z")), 10); // o carimbo real da fila (07:30:08)
  assertEquals(tentativasAte("09:00", new Date("2026-10-15T11:58:00Z")), 3); // 08:58
  assertEquals(tentativasAte("09:00", new Date("2026-10-15T13:00:00Z")), 3); // 10:00
});
