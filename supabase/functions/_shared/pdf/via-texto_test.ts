// Limpeza de texto da via do técnico (porte da via v2, F1): cobrança (4A), nota do material, título curto, pedido.
// Dado sintético. Os casos de cobrança moram em via-cobranca-casos.ts (a F2 roda a mesma lista no Postgres).
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ehCobranca,
  limparPedido,
  limparRuido,
  normalizar,
  notaDoMaterial,
  semValores,
  tituloCurto,
  tituloDoServico,
} from "./via-texto.ts";
import { CASOS_DE_COBRANCA } from "./via-cobranca-casos.ts";

for (const c of CASOS_DE_COBRANCA) {
  Deno.test(`cobrança (4A): ${c.caso}`, () => {
    assertEquals(ehCobranca(c.nome), c.cobranca, c.nome);
  });
}

Deno.test("cobrança: a lista de casos cobre os dois lados e não repete nome", () => {
  assert(CASOS_DE_COBRANCA.some((c) => c.cobranca));
  assert(CASOS_DE_COBRANCA.some((c) => !c.cobranca));
  assertEquals(new Set(CASOS_DE_COBRANCA.map((c) => c.nome)).size, CASOS_DE_COBRANCA.length);
});

Deno.test("nota do material: o recado interno do sistema não vai ao papel; a nota escrita por gente vai", () => {
  assertEquals(notaDoMaterial("Cadastrado pelo orçamento — confirmar preço e completar cadastro fiscal."), null);
  assertEquals(notaDoMaterial("Convertido de linha de serviço em 18/09. Valor provisório."), null);
  assertEquals(notaDoMaterial("Aguardando cotação do fornecedor"), null);
  assertEquals(notaDoMaterial("Levar o cabo vermelho, o preto está no barco"), "Levar o cabo vermelho, o preto está no barco");
  // a linha com R$ sai; o resto da nota fica
  assertEquals(notaDoMaterial("Usar o do estoque\nCusto R$ 120,00"), "Usar o do estoque");
  assertEquals(notaDoMaterial(null), null);
  assertEquals(notaDoMaterial("  "), null);
});

Deno.test("semValores: toda linha com R$ sai", () => {
  assertEquals(semValores("Trocar o inversor\nValor: R$ 900,00\nTestar"), "Trocar o inversor\nTestar");
  assertEquals(semValores(null), "");
});

Deno.test("título curto: corta no travessão com 12 letras antes; o resto guarda o separador", () => {
  const t = tituloCurto("Retirada e reinstalação do carregador — inclui frete de ida e volta");
  assertEquals(t.titulo, "Retirada e reinstalação do carregador");
  assert(t.resto.startsWith(" — inclui frete"), t.resto);
  // poucas letras antes do travessão: não corta
  assertEquals(tituloCurto("Kit 3 — Sistema de energia").titulo, "Kit 3 — Sistema de energia");
  // longo sem separador: corta na primeira vírgula depois de 25 caracteres
  const longo = tituloCurto("Instalação do sistema de monitoramento do banco de baterias, com shunt, display e configuração");
  assertEquals(longo.titulo, "Instalação do sistema de monitoramento do banco de baterias");
  assertEquals(tituloDoServico(""), "Serviço");
});

Deno.test("limparRuido: tira preço, cortesia, horas e 'Mão de obra —' do nome", () => {
  assertEquals(limparRuido("Instalação de LED (R$ 1.200,00 a confirmar)"), "Instalação de LED");
  assertEquals(limparRuido("Revisão do gerador — cortesia"), "Revisão do gerador");
  assertEquals(limparRuido("Mão de obra — troca do disjuntor 2,5 HH"), "Troca do disjuntor");
  assertEquals(limparRuido("Fornecimento e instalação de bomba"), "Instalação de bomba");
  assertEquals(limparRuido(null), "");
});

Deno.test("limparPedido: junta linha quebrada no meio da frase, tira garantia, 'sem custo' e a marca de fusão", () => {
  assertEquals(
    limparPedido("[OS-00100] Trocar o inversor que\nesquenta muito.\nA garantia limita-se a 90 dias.\n1) Revisar o banco, sem custo"),
    "Trocar o inversor que esquenta muito.\n1) Revisar o banco",
  );
  assertEquals(limparPedido("Valor: R$ 3.000"), "");
});

Deno.test("normalizar: sem acento e em minúsculas", () => {
  assertEquals(normalizar("Lítio ÇÃO"), "litio cao");
  assertEquals(normalizar(null), "");
});
