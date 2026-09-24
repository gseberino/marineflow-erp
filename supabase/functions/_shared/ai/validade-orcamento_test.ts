// A validade padrão do orçamento vem da configuração da empresa — de mais nenhum lugar.
//
// Queixa do dono (24/09/2026): "a validade padrão é 3 dias, mas sempre saiu 15 automático,
// eu nunca consegui deixar isso padrão para 3 dias". Ele estava certo: havia três respostas
// concorrentes para a mesma pergunta — a configuração, um `?? 30` fixo no construtor de
// orçamento do assistente, e o DEFAULT 15 da coluna, que valia sempre que o insert omitia
// o campo.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { validadePadraoDoOrcamento, VALIDADE_PADRAO_DE_RESERVA } from "./validade-orcamento.ts";

/** Um supabase de mentira que devolve o que app_settings teria. */
// deno-lint-ignore no-explicit-any
function bancoCom(valor: string | null | undefined): any {
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

Deno.test("usa o que a empresa configurou", async () => {
  // O caso do dono: 3 dias na tela de configurações.
  assertEquals(await validadePadraoDoOrcamento(bancoCom("3")), 3);
});

Deno.test("valor pedido de propósito vence a configuração", async () => {
  // "este orçamento vale 7 dias" é decisão para aquele caso.
  assertEquals(await validadePadraoDoOrcamento(bancoCom("3"), 7), 7);
});

Deno.test("configuração ausente cai na reserva, não em 30", async () => {
  // 30 era o número fixo que o assistente usava; ele não volta por esta porta.
  assertEquals(await validadePadraoDoOrcamento(bancoCom(undefined)), VALIDADE_PADRAO_DE_RESERVA);
  assertEquals(VALIDADE_PADRAO_DE_RESERVA, 15);
});

Deno.test("configuração ilegível não impede criar o orçamento", async () => {
  for (const lixo of ["", "abc", "0", "-5"]) {
    assertEquals(await validadePadraoDoOrcamento(bancoCom(lixo)), VALIDADE_PADRAO_DE_RESERVA);
  }
});

Deno.test("banco fora do ar não derruba a criação", async () => {
  // deno-lint-ignore no-explicit-any
  const quebrado: any = { from() { throw new Error("sem conexão"); } };
  assertEquals(await validadePadraoDoOrcamento(quebrado), VALIDADE_PADRAO_DE_RESERVA);
});

Deno.test("valor pedido inválido é ignorado e vale a configuração", async () => {
  for (const ruim of [0, -1, Number.NaN]) {
    assertEquals(await validadePadraoDoOrcamento(bancoCom("3"), ruim), 3);
  }
});
