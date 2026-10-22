import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { exemplarDe, exemplaresParaPrompt } from "./exemplars.ts";
import { renderizarItem } from "./item-render.ts";

Deno.test("exemplar de cobrança traz o par ruim→bom e o porquê", () => {
  const e = exemplarDe("cobranca")!;
  assertEquals(e.bom.includes("Pix") || e.bom.includes("parcela"), true);
  assertEquals(e.porque.toLowerCase().includes("opç") || e.porque.toLowerCase().includes("empatia"), true);
});

Deno.test("bloco de exemplares para prompt é compacto e cobre os 3 tipos", () => {
  const b = exemplaresParaPrompt();
  assertEquals(b.includes("Cotação"), true);
  assertEquals(b.includes("Cobrança"), true);
  assertEquals(b.includes("Follow-up"), true);
});

Deno.test("exemplos ao cliente usam o tipo da unidade, nunca 'seu barco' (dono, 22/10/2026)", () => {
  const b = exemplaresParaPrompt();
  assertEquals(/seu barco/i.test(b.replace(/nunca "seu barco"/, "")), false);
  // Variados de propósito: um motorhome e uma lancha, pelo menos.
  assertEquals(b.includes("seu motorhome"), true);
  assertEquals(b.includes("sua lancha"), true);
  // E o texto que acompanha diz de onde vem o tipo.
  assertEquals(b.includes("TIPO da unidade"), true);
  assertEquals(b.includes("sua embarcação ou veículo"), true);
});

Deno.test("renderizarItem: fornecedor recebe técnico (nome + SKU)", () => {
  assertEquals(renderizarItem({ nome: "MPPT 100/50", sku: "SKU-9" }, "fornecedor"), "MPPT 100/50 (SKU-9)");
});

Deno.test("renderizarItem: cliente recebe linguagem simples", () => {
  assertEquals(renderizarItem({ nome: "MPPT 100/50" }, "cliente"), "controlador solar");
  assertEquals(renderizarItem({ nome: "MultiPlus-II 12/3000" }, "cliente"), "inversor/carregador");
  assertEquals(renderizarItem({ nome: "SmartShunt 300A" }, "cliente"), "monitor de bateria");
});

Deno.test("renderizarItem: item sem termo conhecido perde só o número de modelo p/ cliente", () => {
  assertEquals(renderizarItem({ nome: "Disjuntor 220/50 Bipolar" }, "cliente"), "Disjuntor Bipolar");
});
