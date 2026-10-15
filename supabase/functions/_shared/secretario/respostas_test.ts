import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ehPacote,
  type ItemGravado,
  textoDaAcao,
  textoDaLista,
  textoDaVolta,
  textoDoDetalhe,
  textoDoPacote,
  textoDoPorque,
  textoNaoAchei,
} from "./respostas.ts";

const HOJE = "2026-10-15";

function item(letra: string, extra: Partial<ItemGravado> = {}): ItemGravado {
  return {
    letra, principal: true, posicao: "lista", ordem: 0, familia: "cobranca", tipo: "cobranca_fora_do_marco", secao: "dinheiro",
    referencia: `recv:${letra}`, nome: `Cliente ${letra}`, titulo: `*Cliente ${letra}*: algo`, recomendacao: null,
    motivo: "Ficou na lista: abaixo de R$ 1 mil.", pedido: null,
    detalhe: { curto: `Cliente ${letra}: curto`, fatos: [["Saldo", "R$ 756,00"]], faco: null },
    acao: null, adiado_ate: null, ...extra,
  };
}

const DIA: ItemGravado[] = [
  item("A", { posicao: "manha", ordem: 0, tipo: "cobranca_grande", acao: "feito" }),
  item("B", { posicao: "manha", ordem: 1, familia: "cliente", tipo: "cliente_sem_resposta", secao: "clientes", acao: "adiado", adiado_ate: "2026-10-16" }),
  item("C", { posicao: "manha", ordem: 2, familia: "os", tipo: "os_esperando_compra", secao: "obras" }),
  item("D", { ordem: 3 }),
  item("F", { ordem: 4, familia: "orcamento", tipo: "orcamento_na_lista", secao: "clientes" }),
  item("G", { ordem: 5, familia: "os", tipo: "os_parada", secao: "obras", acao: "tirado" }),
  item("H", { ordem: 6, familia: "contato", tipo: "contato_sem_cadastro", secao: "contatos" }),
  item("J", { ordem: 7, familia: "contato", tipo: "fornecedor", secao: "contatos" }),
  // outro item do mesmo assunto de D: não aparece como linha própria
  item("D", { ordem: 3, principal: false, detalhe: { curto: "não pode aparecer" } }),
];

Deno.test("lista: seções em ordem, contatos numa linha, a situação dos de manhã e como responder", () => {
  const t = textoDaLista(DIA, null, HOJE, { semLetra: 2 });
  const linhas = t.split("\n");
  assertEquals(linhas[0], "Guardado hoje cedo:");
  assert(t.indexOf("Dinheiro") < t.indexOf("Clientes e orçamentos") && t.indexOf("Clientes e orçamentos") < t.indexOf("Obras"));
  assertStringIncludes(t, "D. Cliente D: curto");
  assertStringIncludes(t, "G. Cliente G: curto (tirado)");
  assertStringIncludes(t, "Contatos esperando resposta: 1 sem cadastro e 1 fornecedor. *lista contatos*");
  assertStringIncludes(t, "…e mais 2 sem letra");
  assertStringIncludes(t, "De manhã: A feito · B adiado até amanhã · C sem resposta sua");
  assertStringIncludes(t, "*D feito*");
  assert(!t.includes("não pode aparecer"), "o item do mesmo assunto não vira linha própria");
  assert(!t.includes("H. "), "contato só em *lista contatos*");
});

Deno.test("lista: o que veio junto aparece como 'também' (nome curto); o contato que parece pedir preço é nomeado", () => {
  const dia: ItemGravado[] = [
    item("G", { ordem: 3, familia: "cliente", tipo: "cliente_sem_resposta", secao: "clientes", detalhe: { curto: "Flávio da Igreja: escreveu há 7 dias, sem resposta" } }),
    item("G", { ordem: 3, principal: false, familia: "os", tipo: "os_parada", secao: "obras", detalhe: { curto: "x", rotulo: "OS-00104 (Flávio da Igreja, parada desde 03/10)" } }),
    item("R", { ordem: 9, familia: "contato", tipo: "contato_pedindo_preco", secao: "contatos", nome: "Cesar" }),
    item("T", { ordem: 10, familia: "contato", tipo: "contato_sem_cadastro", secao: "contatos" }),
  ];
  const t = textoDaLista(dia, null, HOJE);
  assertStringIncludes(t, "G. Flávio da Igreja: escreveu há 7 dias, sem resposta · também: OS-00104 (Flávio da Igreja, parada desde 03/10)");
  assertStringIncludes(t, "Contatos esperando resposta: 2 sem cadastro (R. Cesar parece pedir preço ou orçamento). *lista contatos*");
});

Deno.test("lista contatos: um a um; lista vazia diz que não há nada", () => {
  const t = textoDaLista(DIA, "contatos", HOJE);
  assertEquals(t.split("\n"), [
    "Guardado hoje cedo — contatos:",
    "H. Cliente H: curto",
    "J. Cliente J: curto",
    "Responda a letra, *H feito*, *H amanhã* ou *H não*. *tudo* mostra o resumo completo antigo.",
  ]);
  assert(!t.includes("De manhã:"));
  assertStringIncludes(textoDaLista([], null, HOJE), "Nada guardado hoje.");
  assertStringIncludes(textoDaLista([], "obras", HOJE), "Nada guardado em obras hoje.");
});

Deno.test("detalhe: fatos, também, quantas manhãs, a última resposta e o *X* do cartão", () => {
  const p = item("A", {
    posicao: "manha", recomendacao: "Recomendo um lembrete educado hoje.", pedido: "Prepare…",
    detalhe: { fatos: [["Cliente", "Marcelo Marco Bertoldi"], ["Saldo", "R$ 16.890,00"]], faco: "te mostro o lembrete pronto", curto: "x" },
  });
  const outro = item("A", { principal: false, detalhe: { curto: "Marcelo: escreveu há 17 h, sem resposta" } });
  const t = textoDoDetalhe([outro, p], [
    { dia: "2026-10-13", posicao: "manha", acao: "ignorado", acao_em: "2026-10-14T10:30:00Z", adiado_ate: null },
    { dia: "2026-10-14", posicao: "manha", acao: "nao", acao_em: "2026-10-14T13:00:00Z", adiado_ate: null },
  ], HOJE);
  const linhas = t.split("\n");
  assertEquals(linhas[0], "A. Cliente A");
  assertStringIncludes(t, "Cliente: Marcelo Marco Bertoldi");
  assertStringIncludes(t, "Também: Marcelo: escreveu há 17 h, sem resposta");
  assertStringIncludes(t, "De manhã antes: 2 vezes em 30 dias (última em 14/10).");
  assertStringIncludes(t, "Sua última resposta: você disse não em 14/10.");
  assertStringIncludes(t, "*A* = te mostro o lembrete pronto");
  assertStringIncludes(textoDoDetalhe([p], [], HOJE), "É a primeira vez de manhã");
});

function rascunho(numero: string, cliente: string, barco: string, valor: string, montado: string, principal: boolean, ordem = 0): ItemGravado {
  return item("A", {
    principal, posicao: "manha", ordem, familia: "orcamento", tipo: "orcamento_nao_enviado", secao: "clientes",
    referencia: `os:${numero}`, nome: principal ? "3 orçamentos não enviados: ORÇ-00117, ORÇ-00116, ORÇ-00118" : `${numero} ${cliente}`,
    recomendacao: principal ? "Recomendo revisar e enviar, começando pelo maior." : "Recomendo revisar e enviar.",
    pedido: `me manda o pdf do ${numero}`,
    detalhe: {
      fatos: [["Orçamento", numero], ["Cliente", cliente], ["Barco", barco], ["Valor", valor], ["Montado em", montado]],
      faco: principal ? "te mostro os 3" : "te mando o PDF", curto: "x",
    },
  });
}

const PACOTE: ItemGravado[] = [
  rascunho("ORÇ-00116", "Santo Inacio", "S.I. 7.8 AUTO", "R$ 70.050,00", "09/10/2026", false),
  rascunho("ORÇ-00117", "EVERTON CARLOS PINHEIRO", "Sprinter", "R$ 120.020,00", "13/10/2026", true),
  rascunho("ORÇ-00118", "Cliente Final", "Trailer Darlan", "R$ 21.333,70", "13/10/2026", false),
];

Deno.test("pacote dos não enviados: a letra lista cada um e ensina a pedir o PDF (nada vai ao cliente)", () => {
  assert(ehPacote(PACOTE));
  assert(!ehPacote([PACOTE[1]]), "um só não é pacote");
  assert(!ehPacote([item("A"), item("A", { principal: false })]), "grupo de cliente não é pacote");
  assertEquals(textoDoPacote(PACOTE).split("\n"), [
    "A. 3 orçamentos montados e ainda não enviados:",
    "• ORÇ-00117 (EVERTON CARLOS PINHEIRO, Sprinter), R$ 120.020,00, montado em 13/10",
    "• ORÇ-00116 (Santo Inacio, S.I. 7.8 AUTO), R$ 70.050,00, montado em 09/10",
    "• ORÇ-00118 (Cliente Final, Trailer Darlan), R$ 21.333,70, montado em 13/10",
    "Para conferir um deles, peça o PDF (ex.: *pdf 117*): ele vem para você, não para o cliente.",
    "*A feito* = já enviei · *A espera* = até segunda",
  ]);
  // o *detalhe* do pacote: a mesma lista, o histórico e a recomendação
  const d = textoDoDetalhe(PACOTE, [], HOJE);
  assertStringIncludes(d, "• ORÇ-00116 (Santo Inacio, S.I. 7.8 AUTO), R$ 70.050,00, montado em 09/10");
  assertStringIncludes(d, "É a primeira vez de manhã");
  assertStringIncludes(d, "Recomendo revisar e enviar, começando pelo maior.");
  assert(!d.includes("Também:"), "o pacote não vira 'Também'");
});

Deno.test("por que o X: o motivo gravado", () => {
  assertEquals(textoDoPorque(item("D")), "D. Ficou na lista: abaixo de R$ 1 mil.");
});

Deno.test("ações: feito (e o da cobrança grande), não, tira, adiado; letra que não existe", () => {
  assertStringIncludes(textoDaAcao({ resultado: "feito", acao: "feito", item: { nome: "João", tipo: "cobranca_marco" } }, "B", HOJE),
    "Só volta de manhã se aparecer fato novo");
  assertStringIncludes(textoDaAcao({ resultado: "feito", acao: "feito", item: { nome: "Marcelo", tipo: "cobranca_grande" } }, "A", HOJE),
    "volta amanhã cedo se ainda não tiver entrado");
  assertStringIncludes(textoDaAcao({ resultado: "feito", acao: "nao", item: {} }, "C", HOJE), "*volta C* desfaz");
  assertStringIncludes(textoDaAcao({ resultado: "feito", acao: "tirado", item: { nome: "Flávio" } }, "G", HOJE), "Tirei G (Flávio)");
  assertStringIncludes(textoDaAcao({ resultado: "feito", acao: "adiado", ate: "2026-10-19", item: {} }, "D", HOJE), "fica para segunda (19/10)");
  assertEquals(textoDaAcao({ resultado: "nao_achei" }, "Z", HOJE), textoNaoAchei("Z"));
  assertEquals(textoDaAcao(null, "Z", HOJE), textoNaoAchei("Z"));
  assertStringIncludes(textoDaAcao({ resultado: "invalido" }, "Z", HOJE), "Não consegui anotar");
});

Deno.test("volta: desfeito, sem ação, não achei pela letra e pelo nome", () => {
  assertStringIncludes(textoDaVolta({ resultado: "voltou", desfeita: "tirado", item: { nome: "Flávio da Igreja" } }, { letra: null, nome: "flavio" }, HOJE),
    "Desfeito (tirado): Flávio da Igreja volta a poder subir de manhã.");
  assertEquals(textoDaVolta({ resultado: "sem_acao" }, { letra: "B", nome: null }, HOJE), "O item B não tinha nada anotado.");
  assertEquals(textoDaVolta({ resultado: "nao_achei" }, { letra: "B", nome: null }, HOJE), textoNaoAchei("B"));
  assertStringIncludes(textoDaVolta({ resultado: "nao_achei" }, { letra: null, nome: "flavio" }, HOJE), '"flavio" nos últimos 30 dias');
});
