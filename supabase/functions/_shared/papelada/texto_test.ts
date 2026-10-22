// Os textos do lote (secretário, Passo 5): a linha da sexta, o detalhe numerado, o recorte, a sombra, o resultado —
// sem jargão e com os números de quem montou.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { ItemDeFora, ItemDoLote } from "./lote.ts";
import {
  lerFormatoDaPapelada, linhaDoLote, linhaDoItem, motivoDaConferencia, resumoDeFora, textoDoErroDoLote, textoDoLote,
  textoDoResultado, tituloDaConfirmacao,
} from "./texto.ts";

const imp = { kind: "create_payable", valor: 0, categoria: null, data: null, regra: null, vinculo: false };
const item = (n: number, grupo: ItemDoLote["grupo"], titulo: string, valor: number, categoria: string | null, codigo: ItemDoLote["codigo"], motivo: string): ItemDoLote =>
  ({ n, id: `id-${n}`, grupo, titulo, valor, categoria, codigo, motivo, impressao: imp });
const ITENS: ItemDoLote[] = [
  item(1, "despesa", "Eliane U.", 493, "Alimentação de campo", "anotacao", "você anotou em 06/10"),
  item(2, "despesa", "Fatura C6", 400, "Pagamento de fatura de cartão", "categoria", "15 de 15 sem troca"),
  item(3, "transferencia", "Para a outra conta da HBR", 300, "Transferência entre contas", "transferencia", "dinheiro entre contas da HBR"),
  item(4, "aviso", "Unifique Telecomunicacoes parou de aparecer (último em 09/09)", 164.05, null, "aviso_parou", "só para saber"),
  item(5, "aviso", "Banco C6: R$ 1.560,81 acima do normal (~R$ 300,00)", 1560.81, null, "aviso_lancado", "o pagamento já está lançado"),
];
const fora = (codigo: ItemDeFora["codigo"], valor = 10, grupo: ItemDeFora["grupo"] = "despesa"): ItemDeFora => ({ id: codigo + valor, grupo, titulo: "x", valor, codigo, motivo: "" });
const FORA: ItemDeFora[] = [
  fora("sinal_ja_lancado", 7600, "entrada"), fora("sinal_ja_lancado", 2869.5, "entrada"), fora("sem_cliente", 6500, "entrada"),
  fora("sem_loja"), fora("sem_loja"), fora("sem_categoria"), fora("duplicidade", 100, "aviso"), fora("contradiz"), fora("acima_do_limite", 2099.29),
];
const LOTE = { itens: ITENS, fora: FORA, total: 893, minutos: 15 };

Deno.test("a chave: só sombra e ligado valem; o resto é desligado", () => {
  assertEquals([lerFormatoDaPapelada("sombra"), lerFormatoDaPapelada(" LIGADO "), lerFormatoDaPapelada('"sombra"')], ["sombra", "ligado", "sombra"]);
  assertEquals([lerFormatoDaPapelada(undefined), lerFormatoDaPapelada("on"), lerFormatoDaPapelada("")], ["desligado", "desligado", "desligado"]);
});

Deno.test("a linha da sexta: itens prontos, grupos, o total das despesas, o que precisa do dono e os minutos", () => {
  assertEquals(linhaDoLote(LOTE),
    "Escritório da semana: 5 itens prontos para um sim só (2 despesas, R$ 893,00; 1 transferência; 2 avisos) e 9 que precisam de você; uns 15 min. *lote*");
  assertEquals(linhaDoLote({ itens: [], fora: [], total: 0, minutos: 0 }), null);
  assertEquals(linhaDoLote({ itens: [], fora: FORA.slice(0, 1), total: 0, minutos: 5 }),
    "Escritório da semana: nada pronto para um sim só; 1 item precisa de você; uns 5 min. *escritório*");
});

Deno.test("o detalhe: numerado, motivo em cada linha, o resumo de fora, como aprovar; nada de jargão", () => {
  const t = textoDoLote(LOTE, { quando: "sexta, 16/10", formato: "ligado", regrasGuardadas: 103 });
  assertStringIncludes(t, "Lote da semana (sexta, 16/10): 5 itens prontos para um sim só. Só registra o que já saiu do banco; nenhum dinheiro se move.");
  assertStringIncludes(t, "Despesas: 2, R$ 893,00\n1. Eliane U., R$ 493,00 — Alimentação de campo (você anotou em 06/10)\n2. Fatura C6, R$ 400,00 (15 de 15 sem troca)");
  assertStringIncludes(t, "3. Para a outra conta da HBR, R$ 300,00");
  assertStringIncludes(t, "5. Banco C6: R$ 1.560,81 acima do normal (~R$ 300,00) (já lançado)");
  assertStringIncludes(t, "2 entradas que parecem sinais já lançados (R$ 10.469,50)");
  assertStringIncludes(t, "103 regras sugeridas ficam guardadas até você decidir");
  assertStringIncludes(t, "Para aprovar os 5: *sim <seu PIN>*. Para tirar algum: *lote sem 3, 7* ou *lote sem avisos*.");
  for (const proibida of ["concilia", "pendência", "pendencia", "ferramenta"]) assert(!t.toLowerCase().includes(proibida), proibida);
});

Deno.test("o recorte e o que saiu desde a montagem; a sombra não pede o sim", () => {
  const t = textoDoLote(LOTE, {
    quando: "sexta, 16/10", formato: "ligado", escolhidos: ITENS.filter((i) => i.grupo !== "aviso"), recorte: "sem avisos",
    saiuAgora: [{ n: 2, codigo: "mudou" }],
  });
  assertStringIncludes(t, "Lote da semana (sexta, 16/10), sem avisos: 2 itens prontos");
  assertStringIncludes(t, "Saíram desde que montei: 2 (mudou desde que montei o lote).");
  assert(!t.includes("2. Fatura C6"));
  assertStringIncludes(t, "Para aprovar os 2:");
  const s = textoDoLote(LOTE, { formato: "sombra" });
  assertStringIncludes(s, "(Ensaio: o lote está guardado para comparar; ainda não aprovo nada por aqui.)");
  assert(!s.includes("sim <seu PIN>"));
});

Deno.test("o resultado do 'sim': quantos entraram, o valor, e o porquê de cada um que não entrou", () => {
  const titulos = new Map(ITENS.map((i) => [i.n, i.titulo]));
  assertEquals(textoDoResultado({ itens: ITENS.map((i) => ({ n: i.n, id: i.id, situacao: "entrou" })), entrou: 5, falhou: 0, fora: 0, valor_entrou: 893 }, titulos),
    "Entraram 5 de 5 (despesas: R$ 893,00). Para desfazer alguma despesa, é pelo Extrato ou me pedindo.");
  const r = textoDoResultado({
    itens: [
      { n: 1, id: "id-1", situacao: "entrou" }, { n: 2, id: "id-2", situacao: "fora", motivo: "mudou" },
      { n: 3, id: "id-3", situacao: "falhou", motivo: "acima do limite de lote" }, { n: 4, id: "id-4", situacao: "incompleto" },
    ],
    entrou: 1, falhou: 2, fora: 1, valor_entrou: 493,
  }, titulos);
  assertStringIncludes(r, "Entraram 1 de 4 (despesas: R$ 493,00). Não entraram 3: 2. Fatura C6 (mudou desde que montei o lote); 3. Para a outra conta da HBR (acima do limite de lote); 4. Unifique");
  assertStringIncludes(r, "ficou pela metade");
});

Deno.test("pedaços: título da confirmação, motivos e erros em palavras", () => {
  assertEquals(tituloDaConfirmacao(ITENS), "Aprovar o lote da papelada: 5 itens, R$ 893,00 em despesas");
  assertEquals(motivoDaConferencia("ja_decidido_approved"), "você já aprovou");
  assertEquals(textoDoErroDoLote("sombra"), "O lote está em ensaio: ainda não aprovo nada por aqui.");
  assertStringIncludes(textoDoErroDoLote("sem_lote"), "O próximo sai na sexta, às 17:30");
  assertEquals(linhaDoItem(ITENS[3]), "4. Unifique Telecomunicacoes parou de aparecer (último em 09/09)");
  assertStringIncludes(resumoDeFora(FORA)!, "Ficaram de fora 9, com você no *escritório*:");
  assertEquals(resumoDeFora([]), null);
  // (21/10/2026) quem troca a categoria não está "sem histórico": o resumo diz cada um
  assertEquals(resumoDeFora([fora("sem_historico"), fora("troca_categoria"), fora("troca_categoria", 20)]),
    "Ficaram de fora 3, com você no *escritório*: 2 em que você já trocou a categoria; 1 ainda sem histórico.");
  // (22/10/2026) categoria com 1 a 4 decisões, todas mantidas ("Aplicação financeira" 3 de 3, "Retirada de sócio" 1 de 1):
  // tem histórico, só é pouco — o resumo não pode dizer "ainda sem histórico" (achado do revisor, 2ª rodada)
  assertEquals(resumoDeFora([fora("pouco_historico"), fora("pouco_historico", 20), fora("sem_historico"), fora("troca_categoria")]),
    "Ficaram de fora 4, com você no *escritório*: 1 em que você já trocou a categoria; 2 com pouco histórico; 1 ainda sem histórico.");
  assertEquals(resumoDeFora([fora("pouco_historico")]), "Ficaram de fora 1, com você no *escritório*: 1 com pouco histórico.");
});
