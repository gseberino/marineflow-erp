// Uma regra só para "este número de dias de validade serve?".
//
// Até 26/09/2026 o PDF e a R19 (validadeDoOrcamento) aceitavam -1 e 2.5, enquanto o
// assistente (validadePadraoDoOrcamento) já exigia número positivo. Estes testes seguram a
// regra e provam que as duas portas respondem igual para a mesma sujeira.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  diasDeValidade,
  primeiraValidade,
  VALIDADE_MAXIMA_EM_DIAS,
  VALIDADE_PADRAO_DE_RESERVA,
  validadeGravavel,
} from "./dias-de-validade.ts";
import { ultimoDiaDaValidade, validadeDoOrcamento } from "./pdf/documento.ts";
import { validadePadraoDoOrcamento } from "./ai/validade-orcamento.ts";

// Sem teto, 1e9 dias passavam e somar isso à emissão dava uma data que o JavaScript não
// representa: `toISOString` lançava RangeError e a R19 caía inteira (26/09/2026).
Deno.test("diasDeValidade: teto de 3650 dias; acima disso não serve", () => {
  assertEquals(VALIDADE_MAXIMA_EM_DIAS, 3650);
  assertEquals(diasDeValidade(3650), 3650);
  assertEquals(diasDeValidade("3650.9"), 3650);
  for (const gigante of [3651, "3651", 1e9, 2147483647, "1e9", Number.MAX_SAFE_INTEGER]) {
    assertEquals(diasDeValidade(gigante), null, `aceitou ${String(gigante)}`);
  }
  // o nível gigante passa a vez, como o 0 e o -1
  assertEquals(primeiraValidade(1e9, "3"), 3);
});

Deno.test("ultimoDiaDaValidade: 1e9 e 2147483647 não lançam; valem os dias da empresa", () => {
  const o = (dias: unknown) => ({ created_at: "2026-09-24T15:00:00Z", quote_validity_days: dias });
  // 24/09 + 3 (empresa) = 27/09 — antes: RangeError: Invalid time value
  assertEquals(ultimoDiaDaValidade(o(1e9), { quote_validity_days: "3" }), "2026-09-27");
  assertEquals(ultimoDiaDaValidade(o(2147483647), { quote_validity_days: "3" }), "2026-09-27");
  // empresa gigante também passa a vez: sobra o 15
  assertEquals(ultimoDiaDaValidade(o(null), { quote_validity_days: "1000000000" }), "2026-10-09");
});

Deno.test("validadeGravavel: só grava inteiro de 1 a 3650, exatamente como digitado", () => {
  assertEquals(validadeGravavel("3"), 3);
  assertEquals(validadeGravavel(30), 30);
  assertEquals(validadeGravavel(" 7 "), 7);
  assertEquals(validadeGravavel("3650"), 3650);
  // 2.5 não vira 2 na hora de gravar: quem digitou decide
  for (const ruim of ["2.5", 2.5, "-1", -1, "0", 0, "", "  ", "lixo", "3651", 1e9, null, undefined, true]) {
    assertEquals(validadeGravavel(ruim), null, `gravaria ${String(ruim)}`);
  }
});

Deno.test("validadeDoOrcamento: data fixa válida vira mode 'date' (com os dias junto); lixo cai nos dias", () => {
  const empresa = { quote_validity_days: "3" };
  assertEquals(validadeDoOrcamento(7, empresa, "2026-10-10"), { mode: "date", date: "2026-10-10", days: 7 });
  // começo de timestamp também serve
  assertEquals(validadeDoOrcamento(null, empresa, "2026-10-10T00:00:00"), { mode: "date", date: "2026-10-10", days: 3 });
  // dia que não existe, texto, vazio e não-string não são data fixa
  for (const ruim of ["2026-02-31", "2026-13-01", "10/10/2026", "", "lixo", null, undefined, 20261010]) {
    assertEquals(validadeDoOrcamento(7, empresa, ruim), { mode: "days", days: 7 }, `aceitou ${String(ruim)}`);
  }
});

Deno.test("ultimoDiaDaValidade: data fixa inválida não vira o último dia", () => {
  const o = { created_at: "2026-09-24T15:00:00Z", quote_validity_days: 3 };
  assertEquals(ultimoDiaDaValidade({ ...o, quote_validity_date: "2026-10-10" }, {}), "2026-10-10");
  // antes o filtro era só a forma aaaa-mm-dd: 31/02 passava e a R19 o tomava por último dia
  assertEquals(ultimoDiaDaValidade({ ...o, quote_validity_date: "2026-02-31" }, {}), "2026-09-27");
});

Deno.test("diasDeValidade: só inteiro de pelo menos 1 dia serve", () => {
  assertEquals(diasDeValidade(7), 7);
  assertEquals(diasDeValidade("3"), 3);
  assertEquals(diasDeValidade(" 10 "), 10);
  // fração arredonda para baixo, como o assistente já fazia
  assertEquals(diasDeValidade("2.5"), 2);
  assertEquals(diasDeValidade(2.5), 2);
  // o que não serve devolve null (quem chama passa ao próximo nível)
  for (const ruim of [-1, "-1", 0, "0", 0.5, "0.5", "lixo", "2,5", "", "  ", null, undefined, NaN, Infinity, true, {}]) {
    assertEquals(diasDeValidade(ruim), null, `aceitou ${String(ruim)}`);
  }
});

Deno.test("primeiraValidade: o primeiro nível que serve; nenhum → 15", () => {
  assertEquals(primeiraValidade(7, "3"), 7);
  assertEquals(primeiraValidade(-1, "3"), 3);
  assertEquals(primeiraValidade(0, "lixo", "5"), 5);
  assertEquals(primeiraValidade(null, undefined), VALIDADE_PADRAO_DE_RESERVA);
  assertEquals(primeiraValidade(), 15);
});

Deno.test("validadeDoOrcamento: -1, 0, '2.5', 'lixo' e null no orçamento", () => {
  const empresa = { quote_validity_days: "3" };
  // inválido no orçamento passa a vez para o padrão da empresa
  assertEquals(validadeDoOrcamento(-1, empresa), { mode: "days", days: 3 });
  assertEquals(validadeDoOrcamento(0, empresa), { mode: "days", days: 3 });
  assertEquals(validadeDoOrcamento("lixo", empresa), { mode: "days", days: 3 });
  assertEquals(validadeDoOrcamento(null, empresa), { mode: "days", days: 3 });
  // fração vira inteiro, não "Válido por 2.5 dias"
  assertEquals(validadeDoOrcamento("2.5", empresa), { mode: "days", days: 2 });
});

Deno.test("validadeDoOrcamento: -1, 0, '2.5', 'lixo' e null no padrão da empresa", () => {
  assertEquals(validadeDoOrcamento(null, { quote_validity_days: "-1" }), { mode: "days", days: 15 });
  assertEquals(validadeDoOrcamento(null, { quote_validity_days: "0" }), { mode: "days", days: 15 });
  assertEquals(validadeDoOrcamento(null, { quote_validity_days: "2.5" }), { mode: "days", days: 2 });
  assertEquals(validadeDoOrcamento(null, { quote_validity_days: "lixo" }), { mode: "days", days: 15 });
  assertEquals(validadeDoOrcamento(null, { quote_validity_days: null }), { mode: "days", days: 15 });
  assertEquals(validadeDoOrcamento(-1, { quote_validity_days: -1 }), { mode: "days", days: 15 });
});

Deno.test("R19: validade -1 no orçamento não o dá por vencido na emissão", () => {
  // Emitido 24/09 (Brasília). Com -1 aceito, o último dia seria 23/09 — vencido desde
  // antes de nascer. Agora -1 passa a vez para a empresa (3): vale até 27/09.
  const o = { created_at: "2026-09-24T15:00:00Z", quote_validity_days: -1 };
  assertEquals(ultimoDiaDaValidade(o, { quote_validity_days: "3" }), "2026-09-27");
});

/** Um supabase de mentira que devolve o que app_settings teria. */
// deno-lint-ignore no-explicit-any
function bancoCom(valor: unknown): any {
  return {
    from() {
      const q = {
        select: () => q,
        eq: () => q,
        maybeSingle: () => Promise.resolve({ data: valor === undefined ? null : { value: valor } }),
      };
      return q;
    },
  };
}

Deno.test("o assistente (ao criar) e o PDF (ao imprimir) respondem igual para a mesma sujeira", async () => {
  const valores: unknown[] = [-1, 0, 0.5, "2.5", 2.5, "lixo", null, undefined, "", "7", 30];
  for (const empresa of valores) {
    // sem valor pedido: só a configuração da empresa decide
    assertEquals(
      await validadePadraoDoOrcamento(bancoCom(empresa)),
      validadeDoOrcamento(null, { quote_validity_days: empresa }).days,
      `empresa=${String(empresa)}`,
    );
    for (const doOrcamento of valores) {
      // valor pedido (assistente) = validade do orçamento (PDF): vence a empresa se servir
      assertEquals(
        await validadePadraoDoOrcamento(bancoCom(empresa), doOrcamento as number),
        validadeDoOrcamento(doOrcamento, { quote_validity_days: empresa }).days,
        `orçamento=${String(doOrcamento)} empresa=${String(empresa)}`,
      );
    }
  }
});
