// (21/10/2026) Vendedor não sobe de manhã — a mesma regra do "me acorde se" (pareceVendedor,
// _shared/secretario/palavras.ts), aplicada SÓ a contato sem cadastro de cliente (lead ou "Cliente Final"). Casos REAIS
// (SELECT em produção, 21/10): o "Jaison Consultor de Vendas Zendel", B da manhã-sombra de 16/10, e a "Ketelyn Consultora
// empresarial" de 20/10. E o que não pode mudar: o Cesar que pediu orçamento em 14/10 (ainda sem cadastro), o Josemar
// Santos de 20/10 (lead, acordado às 10:30), o cliente cadastrado e o fornecedor. No fechamento a regra NÃO se repete: o
// acorde já a aplica antes de acordar e o fechamento lembra todo acordado do dia sem resposta (spec uma voz §6.3-2).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type Candidato, candidatoDeConversa, type ConversaCrua } from "./secretario-candidatos.ts";
import { semRespostaDesdeHoje } from "./secretario-tarde-regras.ts";
import { disparosDaConversa } from "../_shared/uma-voz/acorde.ts";
import { itensParaGravar } from "./secretario.ts";
import { selecionar } from "./secretario-selecao.ts";
import { type ItemGravado, textoDaLista } from "../_shared/secretario/respostas.ts";
import type { Secao } from "../_shared/secretario/tipos.ts";

const VENDEDOR = "Ficou na lista: parece vendedor ou consultor oferecendo algo.";

function conv(extra: Partial<ConversaCrua>): ConversaCrua {
  return {
    phone: "5547900000001", contato: "x", categoria: "contato", client_id: null,
    last_inbound_at: "2026-10-20T14:17:05Z", last_body: null, recebidas: [], diasComMensagemSua: 0, last_outbound_at: null, ...extra,
  };
}

const MANHA_2110 = new Date("2026-10-21T10:30:00Z"); // 07:30 de Brasília
const MANHA_1610 = new Date("2026-10-16T10:30:00Z");
const KETELYN = "Oii Sou a Ketelyn, Consultora Empresarial da Vivo. Eu to entrando em contato com voce hoje, por que eu identifiquei que o seu contrato com a Tim, esta chegando ao fim, e *nesse período tem um reajuste automático no valor*. Eu tenho aqui ofertas para voce pagar menos com mais benefícios. Posso te enviar um orçamento pra voce analisar sem compromisso?";

Deno.test("manhã: a oferta da operadora em duas mensagens (o 'orçamento pra você' parece pedido de preço) fica na lista", () => {
  // a mesma Ketelyn de 20/10, com a oferta e o "orçamento" separados: hoje o 2º pedaço sobe como pedido do dia
  const c = candidatoDeConversa(conv({
    phone: "5544997659082", contato: "Ketelyn", last_inbound_at: "2026-10-20T14:18:00Z",
    last_body: "Posso te enviar um orçamento pra você analisar sem compromisso?",
    recebidas: [
      { body: "Posso te enviar um orçamento pra você analisar sem compromisso?", em: "2026-10-20T14:18:00Z" },
      { body: "Oii Sou a Ketelyn, Consultora Empresarial da Vivo. Tenho aqui ofertas para você pagar menos com mais benefícios.", em: "2026-10-20T14:17:05Z" },
    ],
  }), MANHA_2110, 0);
  // (22/10/2026) e o tipo gravado é "contato_sem_cadastro": a *lista* nomeia todo "contato_pedindo_preco" como quem
  // "parece pedir preço ou orçamento" (_shared/secretario/respostas.ts, textoDaLista)
  assertEquals([c.tipo, c.elegivel, c.perdeHoje, c.soPeloPedido, c.porqueNaoSobe], ["contato_sem_cadastro", false, false, false, VENDEDOR]);
});

Deno.test("manhã: o nome que diz que vende segura o pedido de fechar com pressa (o representante Jaison)", () => {
  const c = candidatoDeConversa(conv({
    phone: "5547991838918", contato: "Jaison Consultor de Vendas Zendel", last_inbound_at: "2026-10-15T17:40:00Z",
    last_body: "Gustavo, vamos fechar o pedido hoje?", last_outbound_at: "2026-10-15T17:32:24Z", diasComMensagemSua: 2,
    recebidas: [{ body: "Gustavo, vamos fechar o pedido hoje?", em: "2026-10-15T17:40:00Z" }],
  }), MANHA_1610, 0);
  assertEquals([c.tipo, c.elegivel, c.perdeHoje, c.porqueNaoSobe], ["contato_sem_cadastro", false, false, VENDEDOR]);
});

/** A manhã até a resposta *lista*: seleciona, grava (itensParaGravar) e lê como o WhatsApp lê. */
function respostaDaLista(candidatos: Candidato[], hoje: string, max?: number): string {
  const itens: ItemGravado[] = itensParaGravar(selecionar(candidatos, [], hoje, max)).map((i) => ({
    ...i, secao: i.secao as Secao, acao: null, adiado_ate: null,
  }));
  return textoDaLista(itens, null, hoje);
}

// (22/10/2026) achado do revisor (2ª rodada): o vendedor que saiu da manhã continuava gravado como
// "contato_pedindo_preco", e a *lista* o nomeava como possível cliente novo ("Z. Ketelyn parece pedir preço ou
// orçamento"). O lead de verdade continua nomeado.
Deno.test("lista: o vendedor tirado da manhã não aparece como quem 'parece pedir preço'; o lead de verdade sim", () => {
  const ketelyn = candidatoDeConversa(conv({
    phone: "5544997659082", contato: "Ketelyn", last_inbound_at: "2026-10-20T14:18:00Z",
    last_body: "Posso te enviar um orçamento pra você analisar sem compromisso?",
    recebidas: [
      { body: "Posso te enviar um orçamento pra você analisar sem compromisso?", em: "2026-10-20T14:18:00Z" },
      { body: "Oii Sou a Ketelyn, Consultora Empresarial da Vivo. Tenho aqui ofertas para você pagar menos com mais benefícios.", em: "2026-10-20T14:17:05Z" },
    ],
  }), MANHA_2110, 0);
  // uma lead que pediu preço na véspera, depois da última manhã (sobe como "se perde hoje")
  const marcia = candidatoDeConversa(conv({
    phone: "5547900000777", contato: "Marcia", last_inbound_at: "2026-10-20T19:00:00Z",
    last_body: "Boa tarde! Quanto fica a revisão do gerador do meu barco?",
    recebidas: [{ body: "Boa tarde! Quanto fica a revisão do gerador do meu barco?", em: "2026-10-20T19:00:00Z" }],
  }), MANHA_2110, 0);
  const t = respostaDaLista([ketelyn, marcia], "2026-10-21");
  assertEquals(t.split("\n").filter((l) => l.startsWith("Contatos") || l.startsWith("De manhã")), [
    "Contatos esperando resposta: 1 sem cadastro. *lista contatos*",
    "De manhã: A sem resposta sua",
  ]);
  // nada sobe (domingo): a lead fica na lista e é nomeada; a vendedora não
  const d = respostaDaLista([ketelyn, marcia], "2026-10-21", 0);
  assertEquals(d.split("\n").find((l) => l.startsWith("Contatos")),
    "Contatos esperando resposta: 2 sem cadastro (A. Marcia parece pedir preço ou orçamento). *lista contatos*");
  // o representante Jaison com "vamos fechar o pedido hoje" (16/10)
  const jaison = candidatoDeConversa(conv({
    phone: "5547991838918", contato: "Jaison Consultor de Vendas Zendel", last_inbound_at: "2026-10-15T17:40:00Z",
    last_body: "Gustavo, vamos fechar o pedido hoje?", last_outbound_at: "2026-10-15T17:32:24Z", diasComMensagemSua: 2,
    recebidas: [{ body: "Gustavo, vamos fechar o pedido hoje?", em: "2026-10-15T17:40:00Z" }],
  }), MANHA_1610, 0);
  assertEquals(respostaDaLista([jaison], "2026-10-16").split("\n").find((l) => l.startsWith("Contatos")),
    "Contatos esperando resposta: 1 sem cadastro. *lista contatos*");
});

Deno.test("manhã: os casos reais ficam na lista com o porquê de verdade (Jaison 16/10, Ketelyn 21/10)", () => {
  // Jaison às 07:30 de 16/10: as recebidas desde a resposta de 15/10 14:32 e as de antes na semana (SELECT de 21/10)
  const jaison = candidatoDeConversa(conv({
    phone: "5547991838918", contato: "Jaison Consultor de Vendas Zendel", last_inbound_at: "2026-10-15T17:33:15Z",
    last_body: "Perfeito, vou dar sequencia", last_outbound_at: "2026-10-15T17:32:24Z", diasComMensagemSua: 4,
    recebidas: [
      { body: "Perfeito, vou dar sequencia", em: "2026-10-15T17:33:15Z" },
      { body: "Ainda vai entrar na produção e leva em torno de 3 a 5 dias uteis, você me dando o OK já envio para produção", em: "2026-10-15T17:05:32Z" },
      { body: "O PIX pode ser feito após a expedição finalizar e passar o valor do frete", em: "2026-10-15T17:03:58Z" },
      { body: "Chegasse a analisar a proposta?", em: "2026-10-15T16:54:28Z" },
    ],
  }), MANHA_1610, 0);
  assertEquals([jaison.elegivel, jaison.porqueNaoSobe], [false, VENDEDOR]);
  // Ketelyn às 07:30 de 21/10: a mensagem inteira (o "orçamento pra você" passa dos 120 caracteres que a regra de preço lê)
  const ketelyn = candidatoDeConversa(conv({
    phone: "5544997659082", contato: "Ketelyn Consultora empresarial", last_body: KETELYN,
    recebidas: [{ body: KETELYN, em: "2026-10-20T14:17:05Z" }],
  }), MANHA_2110, 0);
  assertEquals([ketelyn.elegivel, ketelyn.porqueNaoSobe], [false, VENDEDOR]);
});

Deno.test("manhã: cliente de verdade continua subindo (Cesar sem cadastro em 14/10, cliente cadastrado, 'Cliente Final')", () => {
  // o Cesar pediu às 12:23 de 14/10, ainda sem cadastro (o "César – Palazzo" nasceu em 15/10 às 12:15)
  const cesar = candidatoDeConversa(conv({
    phone: "5511930320910", contato: "Cesar", last_inbound_at: "2026-10-14T15:23:00Z", last_body: "Pode me passar o orçamento por favor",
    recebidas: [{ body: "Pode me passar o orçamento por favor", em: "2026-10-14T15:23:00Z" }],
  }), new Date("2026-10-15T10:30:00Z"), 0);
  assertEquals([cesar.tipo, cesar.elegivel, cesar.perdeHoje, cesar.porqueNaoSobe], ["contato_pedindo_preco", true, true, null]);
  // cliente cadastrado nunca é vendedor aqui, nem com "corretor" no nome nem falando de consórcio
  const cadastrado = candidatoDeConversa(conv({
    contato: "Rodrigo Corretor de Imóveis", categoria: "cliente", client_id: "c-rodrigo", last_inbound_at: "2026-10-20T12:00:00Z",
    last_body: "Comprei o barco por consórcio. Quanto fica a revisão do gerador?",
    recebidas: [{ body: "Comprei o barco por consórcio. Quanto fica a revisão do gerador?", em: "2026-10-20T12:00:00Z" }],
  }), MANHA_2110, 0);
  assertEquals([cadastrado.tipo, cadastrado.elegivel, cadastrado.porqueNaoSobe], ["cliente_sem_resposta", true, null]);
  // "Cliente Final" é como lead: a oferta da operadora fica na lista
  const generico = candidatoDeConversa(conv({
    contato: "Cliente Final", categoria: "cliente", client_id: "c-final", last_inbound_at: "2026-10-20T12:00:00Z",
    last_body: KETELYN, recebidas: [{ body: KETELYN, em: "2026-10-20T12:00:00Z" }],
  }), MANHA_2110, 0);
  assertEquals([generico.elegivel, generico.porqueNaoSobe], [false, VENDEDOR]);
  // fornecedor continua com a regra dele
  const forn = candidatoDeConversa(conv({ contato: "Regis Takeo Mazzaro - Vendas Solmais", categoria: "fornecedor", recebidas: [{ body: "Qual o valor?", em: "2026-10-20T12:00:00Z" }] }), MANHA_2110, 0);
  assertEquals(forn.porqueNaoSobe, "Ficou na lista: fornecedor (nunca de manhã).");
});

Deno.test("manhã: o lead Josemar (20/10) não é vendedor — a regra não muda o porquê dele", () => {
  const recebidas = [
    { body: "Nosso CEO gostou do seu perfil e pediu para conversar contigo sobre o desafio", em: "2026-10-20T12:58:52Z" },
    { body: "Você teria disponibilidade de falarmos hoje?", em: "2026-10-20T12:58:51Z" },
    { body: "Olá, bom dia!", em: "2026-10-20T12:58:49Z" },
    { body: "Agora a tarde?", em: "2026-10-15T16:52:51Z" },
    { body: "Podemos agendar uma ligação breve para falarmos?", em: "2026-10-15T16:52:40Z" },
    { body: "Gostaria de saber se você tem interesse em ouvir uma proposta", em: "2026-10-15T14:56:42Z" },
    { body: "Sou Josemar da NX Boats", em: "2026-10-15T14:55:07Z" },
  ];
  const c = candidatoDeConversa(conv({
    phone: "5581983163181", contato: "Josemar Santos", last_inbound_at: "2026-10-20T12:58:52Z", last_body: recebidas[0].body,
    last_outbound_at: "2026-10-15T16:52:07Z", diasComMensagemSua: 1, recebidas,
  }), MANHA_2110, 0);
  assertEquals([c.tipo, c.porqueNaoSobe], ["contato_sem_cadastro", "Ficou na lista: contato sem cadastro que não fala de preço, orçamento ou fechar."]);
});

Deno.test("fechamento: quem o acorde acordou continua lembrado, mesmo com 'consórcio' antes da resposta (o lead Carlos)", () => {
  // achado do revisor (21/10): na segunda o lead conta que comprou a lancha pelo consórcio e a HBR responde; na quarta
  // pede com pressa, o acorde (que só olha o de HOJE sem resposta) acorda o dono às 09:40 — e às 17:30, ainda sem
  // resposta, o fechamento tem que lembrá-lo. Antes do conserto a regra do vendedor sobre a SEMANA o tirava da linha.
  const fone = "5547988887777";
  const seg = { body: "Boa tarde! Comprei a lancha pelo consórcio e quero fazer a parte elétrica com vocês", em: "2026-10-19T17:00:00Z" };
  const qua = { body: "Gustavo, preciso do orçamento hoje, é urgente", em: "2026-10-21T12:00:00Z" };
  const saida = "2026-10-19T18:00:00Z"; // a HBR respondeu na segunda às 15:00
  const acordeEm = new Date("2026-10-21T12:40:00Z"); // 09:40
  const d = disparosDaConversa({
    phone: fone, nome: "Carlos", cliente: false, fornecedor: false, client_id: null, ultimaSaidaEm: saida, recebidas: [qua, seg], diasComMensagemSua: 1,
  }, acordeEm, 30);
  assertEquals(d.map((x) => x.tipo), ["pressa"]);
  const acordados = new Map([[fone, acordeEm.toISOString()]]);
  const esperando = [{ phone: fone, contato: "Carlos", categoria: "contato", last_inbound_at: qua.em, last_outbound_at: saida, last_body: qua.body }];
  const agora = new Date("2026-10-21T20:30:00Z"); // 17:30
  const r = semRespostaDesdeHoje({
    esperando, agora, horas: 4, comLetra: new Set(), acordados,
    recebidas: [{ phone_normalized: fone, occurred_at: qua.em, body: qua.body }, { phone_normalized: fone, occurred_at: seg.em, body: seg.body }],
  });
  assertEquals(r, [{ phone: fone, nome: "Carlos", desde: "09:00", acordei: "09:40" }]);
  // sem as recebidas lidas (só a última mensagem), o mesmo
  const s = semRespostaDesdeHoje({ esperando, recebidas: null, agora, horas: 4, comLetra: new Set(), acordados });
  assertEquals(s.map((x) => [x.nome, x.acordei]), [["Carlos", "09:40"]]);
});

Deno.test("fechamento: o vendedor não chega à linha porque o acorde não o acorda; o lead Josemar acordado e o cliente ficam", () => {
  const esperando = [
    { phone: "5581983163181", contato: "Josemar Santos", categoria: "contato", last_inbound_at: "2026-10-20T12:58:52Z", last_outbound_at: "2026-10-15T16:52:07Z" },
    { phone: "5544997659082", contato: "Ketelyn Consultora empresarial", categoria: "contato", last_inbound_at: "2026-10-20T14:17:05Z", last_outbound_at: null },
    { phone: "5544997071091", contato: "Allana Marques", categoria: "contato", last_inbound_at: "2026-10-20T15:00:00Z", last_outbound_at: null },
    { phone: "5547900000555", contato: "Rodrigo Corretor de Imóveis", categoria: "cliente", last_inbound_at: "2026-10-20T13:00:00Z", last_outbound_at: null },
  ];
  const recebidas = [
    { phone_normalized: "5581983163181", occurred_at: "2026-10-20T12:58:51Z", body: "Você teria disponibilidade de falarmos hoje?" },
    { phone_normalized: "5544997659082", occurred_at: "2026-10-20T14:17:05Z", body: KETELYN },
    { phone_normalized: "5544997071091", occurred_at: "2026-10-20T15:00:00Z", body: "Oii Sou a Allana, Consultora Empresarial da Vivo. Posso te enviar uma proposta hoje?" },
    { phone_normalized: "5547900000555", occurred_at: "2026-10-20T13:00:00Z", body: "Quanto fica a revisão do gerador?" },
  ];
  // o portão é quem barra o vendedor: a Ketelyn (pelo nome) e a Allana (pela oferta de hoje) não acordam ninguém
  const acordados = new Map([["5581983163181", "2026-10-20T13:30:16Z"]]); // o único acorde de contato de 20/10 (SELECT em avisos_do_dono)
  for (const i of [1, 2]) {
    const w = esperando[i];
    const d = disparosDaConversa({
      phone: w.phone, nome: w.contato, cliente: false, fornecedor: false, client_id: null, ultimaSaidaEm: null,
      recebidas: [{ em: recebidas[i].occurred_at, body: recebidas[i].body }], diasComMensagemSua: 0,
    }, new Date(Date.parse(recebidas[i].occurred_at) + 45 * 60_000), 30);
    assertEquals(d, []);
  }
  const agora = new Date("2026-10-20T20:30:00Z"); // 17:30 de 20/10
  const r = semRespostaDesdeHoje({ esperando, recebidas, agora, horas: 4, comLetra: new Set(), acordados });
  assertEquals(r.map((x) => [x.nome, x.acordei]), [["Josemar Santos", "10:30"], ["Rodrigo I.", null]]);
  const s = semRespostaDesdeHoje({
    esperando: esperando.map((w, i) => ({ ...w, last_body: recebidas[i].body })), recebidas: null, agora, horas: 4, comLetra: new Set(), acordados,
  });
  assertEquals(s.map((x) => x.nome), ["Josemar Santos", "Rodrigo I."]);
});

Deno.test("manhã: o lead que falou 'consórcio' ANTES da resposta da HBR e hoje pede orçamento com pressa sobe (o lead Carlos)", () => {
  // segunda: "Comprei a lancha pelo consórcio…"; a HBR responde às 15:00; quarta 09:00: "pode me passar o orçamento hoje?"
  const c = candidatoDeConversa(conv({
    phone: "5547900000077", contato: "Carlos", last_inbound_at: "2026-10-21T12:00:00Z",
    last_body: "Gustavo, pode me passar o orçamento hoje? É urgente", last_outbound_at: "2026-10-19T18:00:00Z",
    recebidas: [
      { body: "Gustavo, pode me passar o orçamento hoje? É urgente", em: "2026-10-21T12:00:00Z" },
      { body: "Comprei a lancha pelo consórcio e quero fazer a parte elétrica com vocês", em: "2026-10-19T14:00:00Z" },
    ],
  }), new Date("2026-10-22T10:30:00Z"), 0);
  assertEquals([c.elegivel, c.tipo], [true, "contato_pedindo_preco"]);
  // e o vendedor que insiste DEPOIS da resposta continua fora (a oferta está nas mensagens novas)
  const k = candidatoDeConversa(conv({
    phone: "5544997659082", contato: "Ketelyn", last_inbound_at: "2026-10-21T12:00:00Z", last_body: KETELYN,
    last_outbound_at: "2026-10-20T18:00:00Z", recebidas: [{ body: KETELYN, em: "2026-10-21T12:00:00Z" }],
  }), new Date("2026-10-22T10:30:00Z"), 0);
  assertEquals([k.elegivel, k.porqueNaoSobe], [false, VENDEDOR]);
});
