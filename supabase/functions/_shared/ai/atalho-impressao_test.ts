// Run: deno test supabase/functions/_shared/ai/atalho-impressao_test.ts
//
// O atalho sem modelo da IMPRESSÃO (17/11/2026): "imprime o orçamento 86" e afins vão direto à impressora; qualquer
// coisa a mais (cópias, cor, nome de pessoa, dois documentos) segue para o modelo, que entende o resto.
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { lerPedidoDeImpressao, lerPedidoDePdf, textoDoAtalhoPdf } from "./atalho-pdf.ts";

Deno.test("imprimir: as formas comuns", () => {
  assertEquals(lerPedidoDeImpressao("imprime o orçamento 86"), { documento: "86", tipo: "orcamento", destino: "impressora" });
  assertEquals(lerPedidoDeImpressao("Imprimir OS 136"), { documento: "136", tipo: "os", destino: "impressora" });
  assertEquals(lerPedidoDeImpressao("imprime o ORÇ-00086 por favor"), { documento: "86", tipo: "orcamento", destino: "impressora" });
  assertEquals(lerPedidoDeImpressao("imprime 86"), { documento: "86", destino: "impressora" });
  assertEquals(lerPedidoDeImpressao("imprime a via do técnico da 136"), { documento: "136", tipo: "os", via: "tecnico", destino: "impressora" });
  assertEquals(lerPedidoDeImpressao("imprime a via da OS 136"), { documento: "136", tipo: "os", via: "tecnico", destino: "impressora" });
  assertEquals(lerPedidoDeImpressao("imprime as vias de hoje"), { documento: "hoje", via: "tecnico", destino: "impressora" });
  assertEquals(lerPedidoDeImpressao("Imprime as vias de hoje!"), { documento: "hoje", via: "tecnico", destino: "impressora" });
  assertEquals(lerPedidoDeImpressao("imprime o último orçamento"), { documento: "ultimo", tipo: "orcamento", destino: "impressora" });
});

Deno.test("imprimir: as vias de amanhã (20/11/2026, a sugestão das 19:30) e o negrito copiado da sugestão", () => {
  const amanha = { documento: "amanha", via: "tecnico" as const, destino: "impressora" as const };
  assertEquals(lerPedidoDeImpressao("imprime as vias de amanhã"), amanha);
  assertEquals(lerPedidoDeImpressao("Imprime as vias de amanha!"), amanha);
  assertEquals(lerPedidoDeImpressao("*imprime as vias de amanhã*"), amanha);
  assertEquals(lerPedidoDeImpressao("pode imprimir as vias de amanhã"), amanha);
  assertEquals(lerPedidoDeImpressao("*imprime as vias de hoje*"), { documento: "hoje", via: "tecnico", destino: "impressora" });
  for (const t of ["imprime o de amanhã", "imprime as vias de hoje e de amanhã", "imprime o 86 amanhã", "imprime as vias de amanhã do Alex"]) {
    assertEquals(lerPedidoDeImpressao(t), null, t);
  }
});

Deno.test("imprimir: o que vai para o modelo", () => {
  for (const t of [
    "imprime 2 cópias do 86",
    "imprime o 86 colorido",
    "imprime a via do Alex da 136",
    "imprime o 86 e o 87",
    "imprime o de hoje",
    "imprime o orçamento",
    "me manda o pdf do 86",
    "a impressora está sem papel?",
    "imprime o orçamento da via 136",
  ]) {
    assertEquals(lerPedidoDeImpressao(t), null, t);
  }
});

Deno.test("o atalho do PDF não muda: 'imprime' não vira pedido de PDF", () => {
  assertEquals(lerPedidoDePdf("imprime o pdf do 86"), null);
  assertEquals(lerPedidoDePdf("me manda o pdf do 86"), { documento: "86" });
});

Deno.test("texto do atalho da impressão: a frase da tool, ou o motivo", () => {
  const pedido = { documento: "86", destino: "impressora" as const };
  assertEquals(textoDoAtalhoPdf({ ok: true, frase: "🖨️ Impresso: o Orçamento ORÇ-00086." }, pedido), "🖨️ Impresso: o Orçamento ORÇ-00086.");
  assertEquals(
    textoDoAtalhoPdf({ error: "Não dá para imprimir agora: o PC do escritório está fora do ar desde 06:50." }, pedido),
    "Não consegui imprimir: o PC do escritório está fora do ar desde 06:50.",
  );
  assertStringIncludes(textoDoAtalhoPdf({ error: "x", opcoes: ["ORÇ-00086", "OS-00086"] }, pedido), "imprime ORÇ-00086");
  // sem o pedido de impressão, o texto do PDF de sempre
  assertStringIncludes(textoDoAtalhoPdf({ error: "falhou" }), "Não consegui mandar o PDF");
});
