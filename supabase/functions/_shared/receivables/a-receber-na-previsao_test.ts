// O que a previsão de caixa conta como entrada de cada conta a receber (cobrança, fatia 6 — 27/11/2026). Os casos são
// os do dado real de 27/11: Nelson (Pix maior que a conta), César (parcial), MP (entrada só com o cliente, conta de 125
// dias), Lírio (125 dias sem nada no banco).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aReceberNaPrevisao, DIAS_SEM_DATA, type ContaParaAPrevisao } from "./a-receber-na-previsao.ts";
import type { EntradaEsperando } from "./dinheiro-esperando.ts";

const HOJE = "2026-11-27";
const conta = (id: string, client_id: string | null, due_date: string, saldo: number): ContaParaAPrevisao => ({ id, client_id, due_date, saldo });
const entrada = (clienteId: string, valor: number, contaId: string | null = null): EntradaEsperando => ({
  clienteId, valor, data: "2026-11-13", titulo: "Pix", contaId, pelaConta: !!contaId,
});
const deUma = (r: ReturnType<typeof aReceberNaPrevisao>, id: string) => r.contas.find((c) => c.id === id)!;

Deno.test("sem nada no Extrato e sem conta antiga: entra o saldo inteiro, nada à parte", () => {
  const r = aReceberNaPrevisao([conta("a", "c1", "2026-11-11", 3292), conta("b", "c1", "2026-12-19", 628.9)], [], HOJE);
  assertEquals(r.contas.map((c) => c.aReceber), [3292, 628.9]);
  assertEquals([r.noBanco, r.antigas], [{ total: 0, contas: 0 }, { total: 0, contas: 0 }]);
});

Deno.test("entrada que aponta a conta e é maior que ela (Nelson: Pix de 2.800 contra 2.110,06): a conta sai inteira e a sobra cobre a próxima conta dele", () => {
  const r = aReceberNaPrevisao(
    [conta("n1", "nelson", "2026-11-14", 2110.06), conta("n2", "nelson", "2026-12-20", 1000)],
    [entrada("nelson", 2800, "n1")], HOJE,
  );
  assertEquals(deUma(r, "n1").aReceber, 0);
  assertEquals(deUma(r, "n1").noBanco, 2110.06);
  // a sobra (689,94) é do cliente: cobre a próxima conta dele
  assertEquals(deUma(r, "n2").noBanco, 689.94);
  assertEquals(deUma(r, "n2").aReceber, 310.06);
  assertEquals(r.noBanco, { total: 2800, contas: 2 });
});

Deno.test("entrada parcial só com o cliente (César: 5.000 de 8.574,60): cobre a mais antiga primeiro e o resto entra", () => {
  const r = aReceberNaPrevisao(
    [conta("c2", "cesar", "2026-11-20", 396), conta("c1", "cesar", "2026-11-17", 8178.6)],
    [entrada("cesar", 5000)], HOJE,
  );
  assertEquals(deUma(r, "c1").noBanco, 5000);
  assertEquals(deUma(r, "c1").aReceber, 3178.6);
  assertEquals(deUma(r, "c2").aReceber, 396);
});

Deno.test(`vencida há mais de ${DIAS_SEM_DATA} dias sai das entradas e vai à parte; com o dinheiro no banco, conta só como no banco`, () => {
  const r = aReceberNaPrevisao(
    [conta("l", "lirio", "2026-07-22", 756), conta("m", "mp", "2026-07-22", 1650), conta("j", "hang", "2026-10-13", 1710)],
    [entrada("mp", 22283)], HOJE,
  );
  assertEquals(deUma(r, "l"), { id: "l", client_id: "lirio", due_date: "2026-07-22", saldo: 756, noBanco: 0, antiga: true, aReceber: 0 });
  assertEquals([deUma(r, "m").aReceber, deUma(r, "m").noBanco, deUma(r, "m").antiga], [0, 1650, true]);
  assertEquals(deUma(r, "j").aReceber, 1710);
  assertEquals(r.antigas, { total: 756, contas: 1 });
  assertEquals(r.noBanco, { total: 1650, contas: 1 });
});

Deno.test("o limite dos 90 dias: vencida há exatamente 90 dias ainda entra; há 91, não", () => {
  const r = aReceberNaPrevisao([conta("x", "c", "2026-08-29", 100), conta("y", "c", "2026-08-28", 100)], [], HOJE);
  assertEquals([deUma(r, "x").aReceber, deUma(r, "y").aReceber], [100, 0]);
});

Deno.test("entrada que aponta conta fora da lista (vence depois da janela) não cobre outra conta do cliente", () => {
  const r = aReceberNaPrevisao([conta("a", "c1", "2026-11-20", 500)], [entrada("c1", 500, "fora-da-janela")], HOJE);
  assertEquals(deUma(r, "a").aReceber, 500);
  assertEquals(r.noBanco.total, 0);
});

Deno.test("dinheiro de um cliente não cobre conta de outro nem conta sem cliente", () => {
  const r = aReceberNaPrevisao([conta("a", "c2", "2026-11-20", 500), conta("b", null, "2026-11-20", 300)], [entrada("c1", 900)], HOJE);
  assertEquals(r.contas.map((c) => c.aReceber), [500, 300]);
});

Deno.test("centavos: várias entradas pequenas somam sem erro de vírgula", () => {
  const r = aReceberNaPrevisao([conta("a", "c", "2026-11-20", 0.3)], [entrada("c", 0.1), entrada("c", 0.2)], HOJE);
  assertEquals([deUma(r, "a").aReceber, deUma(r, "a").noBanco, r.noBanco.total], [0, 0.3, 0.3]);
});
