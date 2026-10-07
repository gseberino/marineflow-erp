import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { embarcacoesComPlano, secaoDeRevisoes, type PlanoDoResumo } from "./revisoes.ts";

const moeda = (v: number) => `R$ ${v.toFixed(2).replace(".", ",")}`;
const HOJE = "2026-10-07";

const plano = (over: Partial<PlanoDoResumo>): PlanoDoResumo => ({
  plan_id: "p1", vessel_id: "v1", vessel_name: "Mar Azul", client_name: "Carlos", name: "Revisão de motor",
  estimated_value: 1200, next_due_on: "2026-10-20", dias_para_vencer: 13, situacao: "na_janela", ...over,
});

Deno.test("sem plano e sem lembrete esperando: a seção não aparece", () => {
  const r = secaoDeRevisoes([], [], 0, moeda, HOJE);
  assertEquals(r.linhas, []);
  assertEquals(r.sugestao, null);
  assertEquals(r.acao, null);
});

Deno.test("plano em dia, longe do vencimento: nada a dizer", () => {
  const r = secaoDeRevisoes([plano({ dias_para_vencer: 90, next_due_on: "2027-01-05", situacao: "em_dia" })], [], 0, moeda, HOJE);
  assertEquals(r.linhas, []);
});

Deno.test("vencendo em 30 dias: até 3 linhas com embarcação, plano, data e valor; total do mês", () => {
  const planos = [
    plano({ plan_id: "a", next_due_on: "2026-10-20", dias_para_vencer: 13 }),
    plano({ plan_id: "b", vessel_name: "Vento Sul", name: "Baterias", next_due_on: "2026-10-10", dias_para_vencer: 3, estimated_value: 800 }),
    plano({ plan_id: "c", next_due_on: "2026-10-28", dias_para_vencer: 21, estimated_value: null }),
    plano({ plan_id: "d", next_due_on: "2026-11-05", dias_para_vencer: 29, estimated_value: 500 }),
  ];
  const r = secaoDeRevisoes(planos, [], 0, moeda, HOJE);
  assertStringIncludes(r.linhas.join("\n"), "Vencendo em 30 dias: *4*");
  // ordem por vencimento: Vento Sul (10/10) primeiro
  assertStringIncludes(r.linhas[3], "Vento Sul — Baterias · 10/10 · R$ 800,00");
  assert(!r.linhas.some((l) => l.includes("05/11")), "só os 3 primeiros");
  assert(r.linhas.some((l) => l.includes("e mais 1")));
  // previsto do mês: só outubro (1200 + 800 + 0); novembro fica de fora
  assert(r.linhas.some((l) => l.includes("Previsto em revisões neste mês: R$ 2000,00")));
  assertEquals(r.acao, "   • *Revisões do mês*");
  assertStringIncludes(r.sugestao!, "Vento Sul");
});

Deno.test("vencida vira a sugestão do dia, e adiada não entra em nada", () => {
  const planos = [
    plano({ plan_id: "a", situacao: "vencida", next_due_on: "2026-09-01", dias_para_vencer: -36 }),
    plano({ plan_id: "b", situacao: "adiada", next_due_on: "2026-10-15", dias_para_vencer: 8, vessel_name: "Adiado" }),
  ];
  const r = secaoDeRevisoes(planos, [], 0, moeda, HOJE);
  const texto = r.linhas.join("\n");
  assertStringIncludes(texto, "Vencidas: *1*");
  assertStringIncludes(texto, "venceu 01/09");
  assert(!texto.includes("Adiado"), "adiada não aparece");
  assertStringIncludes(r.sugestao!, "revisão vencida do *Mar Azul*");
});

Deno.test("quem respondeu nas últimas 24h aparece com o texto; resposta de plano fora da lista é ignorada", () => {
  const r = secaoDeRevisoes([plano({ dias_para_vencer: 90, situacao: "em_dia", next_due_on: "2027-01-05" })],
    [{ plan_id: "p1", texto: "pode ser dia 15" }, { plan_id: "outro", texto: "x" }], 0, moeda, HOJE);
  const texto = r.linhas.join("\n");
  assertStringIncludes(texto, "Responderam ao lembrete (24h): *1*");
  assertStringIncludes(texto, 'Carlos (Mar Azul): "pode ser dia 15"');
});

Deno.test("lembretes esperando o sim aparecem mesmo sem nada vencendo", () => {
  const r = secaoDeRevisoes([], [], 2, moeda, HOJE);
  assertStringIncludes(r.linhas.join("\n"), "Lembretes esperando o seu *sim*: *2*");
  assertEquals(r.acao, null);
});

Deno.test("embarcações com plano saem da heurística dos 12 meses", () => {
  const s = embarcacoesComPlano([plano({ vessel_id: "v1" }), plano({ vessel_id: "v2" })]);
  assert(s.has("v1") && s.has("v2") && !s.has("v3"));
});
