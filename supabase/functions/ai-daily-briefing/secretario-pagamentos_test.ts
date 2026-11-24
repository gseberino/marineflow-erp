// Pagamentos da semana na manhã (24/11/2026): sem a fila o texto é o de antes, byte a byte; com ela, o bloco entra no
// fim, antes da sugestão de imprimir.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { montarDosDados } from "./secretario.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";
import { linhaDasVencidas, pagamentosDaResposta } from "../_shared/pagamentos/semana.ts";

const base = () => ({
  hoje: HOJE_1510, agora: AGORA_1510, coleta: coleta1510(), historico: [],
  naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(),
  escritorio: { propostas: null, alertas: null, regras: null, debitosSemLoja: null, entradas: null },
});

// 15/10/2026 é quinta: não é a 1ª manhã útil da semana, então a manhã leva só a linha das vencidas
const fila = (contas: unknown[]) => pagamentosDaResposta({
  hoje: HOJE_1510, ate: "2026-10-18", saldo_no_banco: 1000, saldo_em: "2026-10-15T09:00:00+00:00",
  contas, soma: 0, vencido: { n: 0, total: 0 }, reembolsos: { n: 0, total: 0 },
});
const vencida = { id: "c1", nome: "Unifique", valor: 117.18, vencimento: "2026-10-10", vencida: true, grupo: 2, a_definir: false };
const aVencer = { id: "c2", nome: "Kamell", valor: 50, vencimento: "2026-10-16", vencida: false, grupo: 3, a_definir: false };

Deno.test("montarDosDados: sem pagamentos, com null ou sem conta vencida o texto é o de antes, byte a byte", () => {
  const antes = montarDosDados(base()).texto;
  assertEquals(montarDosDados({ ...base(), pagamentos: null }).texto, antes);
  assertEquals(montarDosDados({ ...base(), pagamentos: fila([]) }).texto, antes);
  assertEquals(montarDosDados({ ...base(), pagamentos: fila([aVencer]) }).texto, antes);
});

Deno.test("montarDosDados: com conta vencida a manhã ganha a linha no fim, antes da sugestão de imprimir", () => {
  const antes = montarDosDados(base()).texto;
  const p = fila([vencida, aVencer]);
  const linha = linhaDasVencidas(p)!;
  assertEquals(linha, "A pagar vencido: Unifique, R$ 117,18 (venceu 10/10).");
  assertEquals(montarDosDados({ ...base(), pagamentos: p }).texto, `${antes}\n\n${linha}`);
  assertEquals(
    montarDosDados({ ...base(), pagamentos: p, viasParaImprimir: 2 }).texto,
    `${antes}\n\n${linha}\n🖨️ Quer as 2 vias de hoje no papel? Responda: *imprime as vias de hoje*`,
  );
});
