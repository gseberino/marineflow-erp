import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { avisoDeItemFisico } from "./service-orders.ts";

const avisa = (nome: string) => avisoDeItemFisico(nome) !== null;

Deno.test("avisa quando uma peça identificável entra como texto livre", () => {
  // O caso real que originou a regra (orçamento do Rodrigo, 07/08/2026): o conector entrou
  // por add_material_to_order e foi parar na lista de Serviços.
  assertEquals(avisa("Conector para cabo de dados Starlink"), true);
  assertEquals(avisa("Conector de cabo de dados Starlink"), true);
  assertEquals(avisa("Bateria 12V 100Ah"), true);
  assertEquals(avisa("Disjuntor bipolar 40A"), true);
  assertEquals(avisa("Inversor MultiPlus-II 12/3000"), true);
  assertEquals(avisa("Porta fusível MIDI"), true);
});

Deno.test("não avisa em cobrança não-física nem em conjunto estimado", () => {
  assertEquals(avisa("Materiais e Insumos de Instalação"), false);
  assertEquals(avisa("Deslocamento técnico"), false);
  assertEquals(avisa("Frete"), false);
  assertEquals(avisa("Taxa de emergência"), false);
  assertEquals(avisa("Mão de obra de instalação"), false);
  assertEquals(avisa("Materiais elétricos diversos"), false);
});

Deno.test("palavra de conjunto vence a de item físico — evita falso positivo", () => {
  // "cabo" aparece, mas é claramente um conjunto estimado: não deve travar o fluxo.
  assertEquals(avisa("Materiais diversos: cabos, conectores e terminais"), false);
  assertEquals(avisa("Kit de cabos de alimentação"), false);
  assertEquals(avisa("Serviço de passagem de cabo"), false);
});

Deno.test("é indiferente a acento e caixa", () => {
  assertEquals(avisa("FUSÍVEL 50A"), true);
  assertEquals(avisa("fusivel 50a"), true);
  assertEquals(avisa("Lâmpada de farol"), true);
  assertEquals(avisa("lampada de farol"), true);
});

Deno.test("nome sem indício algum não gera aviso", () => {
  assertEquals(avisa("Ajuste combinado com o cliente"), false);
  assertEquals(avisa(""), false);
});

Deno.test("o aviso diz o que fazer, não só que está errado", () => {
  const aviso = avisoDeItemFisico("Conector para cabo de dados Starlink")!;
  // Sem o caminho de correção, o agente sabe que errou e não sabe sair disso.
  assertEquals(aviso.includes("create_product"), true);
  assertEquals(aviso.includes("add_service_order_item"), true);
  assertEquals(aviso.includes("remove_service_order_item"), true);
});
