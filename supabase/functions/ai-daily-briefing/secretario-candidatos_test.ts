import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ASSUNTO_NAO_ENVIADOS,
  candidatoDeCobranca,
  candidatoDeConversa,
  candidatoDeOrcamento,
  candidatoDeOs,
  candidatosDoDia,
  type ConversaCrua,
  ehClienteGenerico,
  manhaAnterior,
  type CobrancaCrua,
  type OrcamentoCru,
  type OsCrua,
  valorAbertoPorCliente,
} from "./secretario-candidatos.ts";
import { AGORA_1510, coleta1510, HOJE_1510 } from "./secretario-fixture.ts";

const HOJE = HOJE_1510;

function cob(extra: Partial<CobrancaCrua>): CobrancaCrua {
  return { id: "r1", client_id: "c1", cliente: "Marcelo Marco Bertoldi", descricao: "À vista — OS-00038", vencimento: "2026-10-13", saldo: 16890, os_numero: "OS-00038", barco: "Aria", ...extra };
}

Deno.test("cobrança grande: sobe todo dia (fora da repetição), com o lembrete pronto", () => {
  const c = candidatoDeCobranca(cob({}), HOJE);
  assertEquals([c.tipo, c.elegivel, c.todoDia, c.secao], ["cobranca_grande", true, true, "dinheiro"]);
  assertEquals(c.titulo, "*Marcelo Marco Bertoldi* (Aria, OS-00038): R$ 16.890,00 venceu terça (13/10) e não entrou.");
  assertEquals(c.assunto, "cliente:c1");
  assertEquals(c.referencia, "recv:r1");
  assertEquals(c.fato, "16890.00|2026-10-13|grande");
  assertStringIncludes(c.pedido!, "peça o meu sim antes de enviar");
  assertStringIncludes(c.motivo, "*{L} espera*");
});

Deno.test("cobrança de R$ 1 mil+: só nos marcos 1º–3º e 7º–9º dia; o marco entra no fato", () => {
  const d2 = candidatoDeCobranca(cob({ saldo: 1710, vencimento: "2026-10-13" }), HOJE);
  assertEquals([d2.tipo, d2.elegivel, d2.todoDia], ["cobranca_marco", true, false]);
  assertEquals(d2.recomendacao, "Recomendo um lembrete educado hoje.");
  const d5 = candidatoDeCobranca(cob({ saldo: 1710, vencimento: "2026-10-10" }), HOJE);
  assertEquals([d5.tipo, d5.elegivel], ["cobranca_fora_do_marco", false]);
  assertStringIncludes(d5.porqueNaoSobe!, "5º dia de atraso");
  const d8 = candidatoDeCobranca(cob({ saldo: 1710, vencimento: "2026-10-07" }), HOJE);
  assertEquals([d8.tipo, d8.elegivel], ["cobranca_marco", true]);
  assertEquals(d8.recomendacao, "Recomendo ligar hoje.");
  assert(d2.fato.endsWith("|m1") && d8.fato.endsWith("|m7"), "o 7º dia é fato novo");
  const pequena = candidatoDeCobranca(cob({ saldo: 756, vencimento: "2026-10-13" }), HOJE);
  assertEquals([pequena.tipo, pequena.porqueNaoSobe], ["cobranca_fora_do_marco", "Ficou na lista: abaixo de R$ 1 mil."]);
  const antiga = candidatoDeCobranca(cob({ saldo: 1650, vencimento: "2026-07-22" }), HOJE);
  assertEquals(antiga.tipo, "cobranca_antiga");
  assertStringIncludes(antiga.porqueNaoSobe!, "revisão do mês");
  assertEquals(candidatoDeCobranca(cob({ vencimento: "2026-10-14" }), HOJE).titulo.includes("venceu ontem"), true);
});

function conv(extra: Partial<ConversaCrua>): ConversaCrua {
  return {
    phone: "5547900000001", contato: "Jorge Girardon", categoria: "cliente", client_id: "c-jorge",
    last_inbound_at: "2026-10-14T20:10:00Z", last_body: "🎤 Oi Gustavo", recebidas: [{ body: "🎤 Oi Gustavo", em: "2026-10-14T20:10:00Z" }],
    diasComMensagemSua: 1, ...extra,
  };
}

Deno.test("cliente sem resposta há mais de 12 h sobe; áudio vira 'resumo o áudio'; o fato é a última mensagem", () => {
  const c = candidatoDeConversa(conv({}), AGORA_1510, 0);
  assertEquals([c.tipo, c.elegivel, c.familia, c.secao], ["cliente_sem_resposta", true, "cliente", "clientes"]);
  assertEquals(c.titulo, "*Jorge Girardon* mandou áudio ontem às 17:10 e está há 14 h sem resposta.");
  assertEquals(c.faco, "resumo o áudio e preparo a resposta");
  assertEquals(c.fato, "2026-10-14T20:10:00.000Z");
  assertEquals(c.assunto, "cliente:c-jorge");
});

Deno.test("cliente com menos de 12 h, conversa de todo dia, fornecedor e contato sem pedir preço ficam na lista", () => {
  const recente = candidatoDeConversa(conv({ last_inbound_at: "2026-10-15T06:00:00Z" }), AGORA_1510, 0);
  assertEquals([recente.tipo, recente.elegivel], ["cliente_recente", false]);
  assertStringIncludes(recente.porqueNaoSobe!, "a manhã espera 12 h");
  const todoDia = candidatoDeConversa(conv({ diasComMensagemSua: 5 }), AGORA_1510, 0);
  assertEquals([todoDia.tipo, todoDia.porqueNaoSobe], ["cliente_recente", "Ficou na lista: vocês conversam quase todo dia."]);
  const forn = candidatoDeConversa(conv({ categoria: "fornecedor", contato: "SR Contabilidade" }), AGORA_1510, 0);
  assertEquals([forn.tipo, forn.elegivel, forn.secao], ["fornecedor", false, "contatos"]);
  assertStringIncludes(forn.curto, "(fornecedor)");
  const contato = candidatoDeConversa(conv({ categoria: "contato", client_id: null, last_body: "Pois é, tá feinho" }), AGORA_1510, 0);
  assertEquals([contato.tipo, contato.elegivel, contato.assunto], ["contato_sem_cadastro", false, "fone:5547900000001"]);
});

Deno.test("contato sem cadastro que PARECE pedir preço sobe (o texto diz 'parece'); pressa = se perde hoje", () => {
  const msg = "Quanto fica o orçamento das baterias? Preciso fechar hoje";
  const c = candidatoDeConversa(conv({
    categoria: "contato", client_id: null, contato: "5547900000006", last_body: msg,
    last_inbound_at: "2026-10-14T13:00:00Z", recebidas: [{ body: msg, em: "2026-10-14T13:00:00Z" }],
  }), AGORA_1510, 0);
  assertEquals([c.tipo, c.elegivel, c.perdeHoje], ["contato_pedindo_preco", true, true]);
  assertStringIncludes(c.titulo, "parece pedir preço ou orçamento");
  assertStringIncludes(c.titulo, "Parece ter pressa");
  assertStringIncludes(c.motivo, "Pode se perder hoje: fala em \"hoje\" ou \"urgente\".");
});

function orc(extra: Partial<OrcamentoCru>): OrcamentoCru {
  return {
    id: "q1", numero: "ORÇ-00117", quote_status: "draft", valor: 120020, client_id: "c-everton", cliente: "EVERTON CARLOS PINHEIRO",
    barco: "Sprinter", criado_em: "2026-10-13T12:00:00Z", mexido_em: "2026-10-14T12:00:00Z", fim_validade: null, ...extra,
  };
}

Deno.test("orçamento montado e não enviado (R$ 5 mil+, parado desde ontem) sobe e abre pelo PDF", () => {
  const c = candidatoDeOrcamento(orc({}), HOJE)!;
  assertEquals([c.tipo, c.elegivel], ["orcamento_nao_enviado", true]);
  assertEquals(c.titulo, "*ORÇ-00117* (EVERTON CARLOS PINHEIRO, Sprinter), R$ 120.020,00: montado em 13/10 e não enviado.");
  assertEquals(c.pedido, "me manda o pdf do ORÇ-00117");
  // os não enviados são UM assunto só (o pacote da manhã), não o do cliente
  assertEquals(c.assunto, ASSUNTO_NAO_ENVIADOS);
  const hoje = candidatoDeOrcamento(orc({ mexido_em: "2026-10-15T09:00:00Z" }), HOJE)!;
  assertEquals([hoje.tipo, hoje.porqueNaoSobe], ["orcamento_na_lista", "Ficou na lista: mexido hoje (ainda em montagem)."]);
  assertEquals(hoje.assunto, "cliente:c-everton");
  assertEquals(candidatoDeOrcamento(orc({ criado_em: "2026-08-13T12:00:00Z" }), HOJE), null, "rascunho de agosto é abandonado");
  const pequeno = candidatoDeOrcamento(orc({ valor: 453.4 }), HOJE)!;
  assertEquals([pequeno.tipo, pequeno.porqueNaoSobe, pequeno.assunto], ["orcamento_na_lista", "Ficou na lista: abaixo de R$ 5 mil.", "cliente:c-everton"]);
});

Deno.test("orçamento enviado: parado 7+ dias ou validade em até 3 dias; vence hoje = se perde hoje", () => {
  const sinal = candidatoDeOrcamento(orc({ quote_status: "awaiting_deposit", valor: 14461, mexido_em: "2026-10-06T12:00:00Z" }), HOJE)!;
  assertEquals([sinal.tipo, sinal.elegivel], ["orcamento_parado", true]);
  assertStringIncludes(sinal.titulo, "aprovado, e o sinal não veio desde 06/10 (9 dias)");
  assertEquals(sinal.recomendacao, "Recomendo lembrar o sinal hoje.");
  const vence = candidatoDeOrcamento(orc({ quote_status: "sent", valor: 6000, mexido_em: "2026-10-14T12:00:00Z", fim_validade: "2026-10-17" }), HOJE)!;
  assertEquals([vence.tipo, vence.perdeHoje], ["orcamento_vencendo", false]);
  const hoje = candidatoDeOrcamento(orc({ quote_status: "sent", valor: 6000, mexido_em: "2026-10-14T12:00:00Z", fim_validade: HOJE }), HOJE)!;
  assertEquals([hoje.tipo, hoje.perdeHoje], ["orcamento_vencendo", true]);
  assertStringIncludes(hoje.titulo, "a validade termina hoje");
  const novo = candidatoDeOrcamento(orc({ quote_status: "sent", valor: 6000, mexido_em: "2026-10-12T12:00:00Z", fim_validade: "2026-10-25" }), HOJE)!;
  assertEquals([novo.tipo, novo.porqueNaoSobe], ["orcamento_na_lista", "Ficou na lista: parado há 3 dias (a manhã mostra a partir de 7)."]);
  const vencido = candidatoDeOrcamento(orc({ quote_status: "awaiting_approval", valor: 4254.69, mexido_em: "2026-10-13T12:00:00Z", fim_validade: "2026-10-03" }), HOJE)!;
  assertStringIncludes(vencido.curto, "validade vencida em 03/10");
  // "sem aprovação" (o que o banco sabe), não "sem resposta" (a conversa pode estar andando)
  const parado = candidatoDeOrcamento(orc({ quote_status: "sent", valor: 6000, mexido_em: "2026-10-05T12:00:00Z", fim_validade: "2026-10-30" }), HOJE)!;
  assertEquals(parado.titulo, "*ORÇ-00117* (EVERTON CARLOS PINHEIRO, Sprinter), R$ 6.000,00: enviado e sem aprovação há 10 dias.");
});

Deno.test("orçamento de cliente que disse que fechou com outra: fica na lista, com o porquê; rascunho mandado mostra a data", () => {
  const miguel = candidatoDeOrcamento(orc({
    numero: "ORÇ-00113", quote_status: "sent", valor: 105603.9, cliente: "Miguel", mexido_em: "2026-10-05T18:46:00Z", fim_validade: "2026-10-30",
    cliente_encerrou_em: "2026-10-07T17:15:54Z",
  }), "2026-10-13")!;
  assertEquals([miguel.tipo, miguel.elegivel, miguel.assunto], ["orcamento_na_lista", false, "cliente:c-everton"]);
  assertEquals(miguel.porqueNaoSobe, "Ficou na lista: o cliente escreveu em 07/10 que fechou com outra empresa ou desistiu. Se foi isso, marque o orçamento como recusado.");
  assertStringIncludes(miguel.curto, "o cliente disse em 07/10 que fechou com outra ou desistiu");
  const mandado = candidatoDeOrcamento(orc({ quote_status: "sent", enviado_em: "2026-10-09T20:48:19Z", mexido_em: "2026-10-09T20:48:19Z", fim_validade: "2026-10-12" }), HOJE)!;
  assertEquals(mandado.tipo, "orcamento_na_lista");
  assertEquals(mandado.fatos.find(([r]) => r === "Mandado pelo WhatsApp em")?.[1], "09/10/2026 (no sistema ainda está como rascunho)");
  assertEquals(mandado.porqueNaoSobe, "Ficou na lista: validade vencida em 12/10 e parado há 6 dias (a manhã mostra a partir de 7).");
});

function os(extra: Partial<OsCrua>): OsCrua {
  return {
    id: "o1", numero: "OS-00104", status: "awaiting_parts", valor: 2760, client_id: "c-flavio", cliente: "Flávio da Igreja", barco: "Itapoã",
    mexido_em: "2026-10-03T12:00:00Z", agendada_em: null, sinal_pago: 2070,
    tarefa_compra: { titulo: "Comprar 1 item — OS-00104 (Flávio da Igreja)", criada_em: "2026-10-03T12:00:00Z" }, cobrancas_vivas: 1, ...extra,
  };
}

Deno.test("OS esperando compra (sinal pago ou serviço marcado): 'parece', e a alternativa é o *feito*", () => {
  const c = candidatoDeOs(os({}), HOJE)!;
  assertEquals([c.tipo, c.elegivel, c.comandoAlternativo, c.alternativa], ["os_esperando_compra", true, "feito", "já comprei"]);
  assertEquals(c.titulo, "*OS-00104* (Flávio da Igreja, Itapoã): parece esperar a compra de 1 item (sinal de R$ 2.070,00 já pago). Sem a peça o serviço não anda.");
  assertStringIncludes(c.motivo, "É dedução pela tarefa");
  assertEquals(c.fato, "Comprar 1 item — OS-00104 (Flávio da Igreja)|awaiting_parts");
  // dedução diz "parece" em todo lugar, inclusive no "logo abaixo" e na lista
  assertEquals(c.rotulo, "OS-00104 (Flávio da Igreja, parece esperar compra)");
  assertStringIncludes(c.curto, "parece esperar compra");
  const hoje = candidatoDeOs(os({ sinal_pago: 0, agendada_em: "2026-10-15T12:00:00Z" }), HOJE)!;
  assertEquals([hoje.tipo, hoje.perdeHoje], ["os_esperando_compra", true]);
  // sem sinal e sem serviço marcado: não é "esperando o dono"; parada há 12 dias = lista
  const semSinal = candidatoDeOs(os({ sinal_pago: 0 }), HOJE)!;
  assertEquals([semSinal.tipo, semSinal.elegivel], ["os_parada", false]);
});

Deno.test("OS concluída sem cobrança sobe; com cobrança, de valor zero ou ativa e andando, nada", () => {
  const c = candidatoDeOs(os({ status: "completed", tarefa_compra: null, cobrancas_vivas: 0, valor: 3000 }), HOJE)!;
  assertEquals([c.tipo, c.elegivel], ["os_sem_cobranca", true]);
  assertStringIncludes(c.titulo, "concluída e sem cobrança lançada (R$ 3.000,00)");
  assertEquals(candidatoDeOs(os({ status: "completed", tarefa_compra: null, cobrancas_vivas: 1 }), HOJE), null);
  assertEquals(candidatoDeOs(os({ status: "completed", tarefa_compra: null, cobrancas_vivas: 0, valor: 0 }), HOJE), null);
  assertEquals(candidatoDeOs(os({ tarefa_compra: null, mexido_em: "2026-10-12T12:00:00Z" }), HOJE), null);
});

Deno.test("valor aberto do cliente (orçamento ou OS ativa) entra na ordem do cliente sem resposta", () => {
  const v = valorAbertoPorCliente(coleta1510());
  assertEquals(v.get("c-giancarlo"), 5739);
  assertEquals(v.get("c-flavio"), 2760);
  assertEquals(v.get("c-marcelo"), undefined, "OS concluída não conta");
  assertEquals(v.get("c-final"), undefined, "cadastro genérico não empresta valor a uma conversa");
});

// ─── (23/10/2026) D11a: a OS que espera o cliente ─────────────────────────────────────────────────
// A carteira de 23/10/2026: OS-00032 e OS-00033 (Kalmar, 30 e 24 dias) e OS-00076 (Rodrigo, 76 dias) estão em
// awaiting_client e a manhã não as via (a lista de "ativas" do Secretário não tinha o status).
Deno.test("D11a: awaiting_client vira os_parada com 'esperando o cliente desde', só na lista", () => {
  const c = candidatoDeOs(os({
    id: "o-32", numero: "OS-00032", status: "awaiting_client", valor: 12500, client_id: "c-kalmar", cliente: "KALMAR PERSONAL BOATS",
    barco: "CAT-33-PAMPLONA", tipo_unidade: "Lancha", mexido_em: "2026-09-23T12:18:49Z", sinal_pago: 0, tarefa_compra: null,
  }), "2026-10-23")!;
  // o tipo continua os_parada: o CHECK resumo_itens_tipo_chk é lista fechada
  assertEquals([c.tipo, c.familia, c.secao, c.elegivel, c.perdeHoje], ["os_parada", "os", "obras", false, false]);
  assertEquals(c.titulo, "*OS-00032* (KALMAR PERSONAL BOATS, CAT-33-PAMPLONA): esperando o cliente desde 23/09.");
  assertEquals(c.curto, "OS-00032 KALMAR PERSONAL BOATS (CAT-33-PAMPLONA): esperando o cliente desde 23/09");
  assertEquals(c.rotulo, "OS-00032 (KALMAR PERSON…, esperando o cliente desde 23/09)");
  // o "também" da lista corta em 60: o rótulo cabe inteiro, com a data
  assert(c.rotulo.length <= 60, `${c.rotulo.length}`);
  assertEquals(c.motivo, "Esperando o cliente há 30 dias.");
  assertEquals(c.porqueNaoSobe, "Ficou na lista: esperando o cliente há 30 dias.");
  assertStringIncludes(c.pedido!, "o que estamos esperando do cliente");
  assertEquals(c.fatos.at(-1), ["Esperando o cliente desde", "23/09/2026"]);
  assertEquals(c.fato, "awaiting_client|2026-09-23");
  assert(!/parada/.test(c.titulo + c.curto + c.rotulo), "nada de 'parada' para quem espera o cliente");
});

Deno.test("D11a: esperando o cliente não é 'esperando compra'; com menos de 10 dias, nada (como a parada)", () => {
  // tarefa de compra viva e sinal pago: quem trava é o cliente (a R16 também não cobra compra de awaiting_client)
  const comCompra = candidatoDeOs(os({ status: "awaiting_client", mexido_em: "2026-09-29T22:12:54Z" }), HOJE)!;
  assertEquals([comCompra.tipo, comCompra.elegivel], ["os_parada", false]);
  assertStringIncludes(comCompra.titulo, "esperando o cliente desde 29/09");
  assertEquals(candidatoDeOs(os({ status: "awaiting_client", tarefa_compra: null, mexido_em: "2026-10-10T12:00:00Z" }), HOJE), null);
  // a parada de sempre não muda
  const parada = candidatoDeOs(os({ status: "open", tarefa_compra: null, sinal_pago: 0 }), HOJE)!;
  assertEquals([parada.titulo, parada.rotulo], ["*OS-00104* (Flávio da Igreja, Itapoã): parada desde 03/10.", "OS-00104 (Flávio da Igreja, parada desde 03/10)"]);
});

Deno.test("D11a: o valor aberto do cliente conta a OS que espera o cliente", () => {
  const c = coleta1510();
  c.oss.push({
    id: "o-32", numero: "OS-00032", status: "awaiting_client", valor: 12500, client_id: "c-kalmar", cliente: "KALMAR PERSONAL BOATS", barco: "CAT-33-PAMPLONA",
    mexido_em: "2026-09-23T12:18:49Z", agendada_em: null, sinal_pago: 0, tarefa_compra: null, cobrancas_vivas: 0,
  });
  assertEquals(valorAbertoPorCliente(c).get("c-kalmar"), 12500);
  // e ela entra na lista do dia (a manhã a enxerga), sem subir
  const x = candidatosDoDia(c, AGORA_1510, HOJE).find((k) => k.referencia === "os:o-32")!;
  assertEquals([x.tipo, x.elegivel], ["os_parada", false]);
});

Deno.test("cadastro genérico ('Cliente Final', 'Consumidor Final') não é assunto: cada item vale por si", () => {
  assert(ehClienteGenerico("Cliente Final") && ehClienteGenerico("CONSUMIDOR FINAL") && !ehClienteGenerico("Cliente Fiel"));
  const q = candidatoDeOrcamento(orc({ id: "q-103", numero: "ORÇ-00103", quote_status: "awaiting_approval", client_id: "c-final", cliente: "Cliente Final", valor: 58310.05, mexido_em: "2026-09-23T12:00:00Z", fim_validade: "2026-10-18" }), HOJE)!;
  assertEquals(q.assunto, "os:q-103");
  assertEquals(candidatoDeOs(os({ id: "o-110", client_id: "c-final", cliente: "Cliente Final", tarefa_compra: null }), HOJE)!.assunto, "os:o-110");
  assertEquals(candidatoDeCobranca(cob({ client_id: "c-final", cliente: "Cliente Final" }), HOJE).assunto, "recv:r1");
  assertEquals(candidatoDeConversa(conv({ client_id: "c-final", contato: "Cliente Final" }), AGORA_1510, 0).assunto, "fone:5547900000001");
});

Deno.test("pressa: 'amanhã' escrito ontem é hoje; 'hoje'/'urgente' nas últimas 24 h também", () => {
  const amanha = candidatoDeConversa(conv({ recebidas: [{ body: "Tu quer que eu leve o motorhome amanhã?", em: "2026-10-14T17:53:05Z" }] }), AGORA_1510, 0);
  assertEquals(amanha.perdeHoje, true);
  assertStringIncludes(amanha.titulo, 'Parece ter pressa (escreveu ontem "amanhã", que é hoje).');
  // "amanhã" escrito hoje cedo é amanhã mesmo
  const deHoje = candidatoDeConversa(conv({ last_inbound_at: "2026-10-14T20:10:00Z", recebidas: [{ body: "passo aí amanhã", em: "2026-10-15T09:00:00Z" }] }), AGORA_1510, 0);
  assertEquals(deHoje.perdeHoje, false);
});

Deno.test("pedir preço é pedido de verdade, não vendedor falando de preço", () => {
  const contato = (body: string) => candidatoDeConversa(conv({
    categoria: "contato", client_id: null, contato: "x", last_inbound_at: "2026-10-14T13:00:00Z", recebidas: [{ body, em: "2026-10-14T13:00:00Z" }],
  }), AGORA_1510, 0).tipo;
  for (const pede of ["Pode me passar o orçamento por favor", "Favor orçar a instalação de 2 baterias", "Quanto fica pra trocar?", "Qual o valor?", "Preciso de um orçamento", "quero fechar"]) {
    assertEquals(contato(pede), "contato_pedindo_preco", pede);
  }
  for (const fala of ["Pode mas ai será o preço de tabela, já consigo buscar uma proposta diferenciada", "tem muita diferença de preços entre a 288 e 628 ?", "Vi teu pix no orçamento"]) {
    assertEquals(contato(fala), "contato_sem_cadastro", fala);
  }
});

Deno.test("15/10: todos os candidatos do dia (o rascunho de agosto e as OS andando ou concluídas com cobrança ficam de fora)", () => {
  const cs = candidatosDoDia(coleta1510(), AGORA_1510, HOJE);
  // 5 cobranças + 7 conversas + 7 orçamentos (sem o de agosto) + 3 OS (OS-00104 e OS-00069 paradas, OS-00112 esperando compra)
  assertEquals(cs.length, 5 + 7 + 7 + 3);
  assert(!cs.some((c) => c.nome.startsWith("ORÇ-00078")));
  assertEquals(cs.filter((c) => c.elegivel).map((c) => c.referencia).sort(), [
    "fone:5511900000002", "fone:5547900000001", "fone:5547900000003", "fone:5547900000004",
    "os:o-112", "os:q-117", "os:q-118", "os:q-95", "recv:r-joao", "recv:r-marcelo",
  ]);
  // a OS-00104 sem tarefa aberta às 07:30 é "parada" (lista), não "esperando compra"
  assertEquals(cs.find((c) => c.referencia === "os:o-104")!.tipo, "os_parada");
});

Deno.test("pedido de orçamento depois da última manhã, sem resposta: se perde hoje, mesmo antes das 12 h (decisão do dono, 15/10)", () => {
  const pede = "Pode me passar o orçamento por favor";
  // contato sem cadastro que pediu às 06:50 de hoje
  const cedo = candidatoDeConversa(conv({
    categoria: "contato", client_id: null, contato: "Cesar", last_body: pede, last_inbound_at: "2026-10-15T09:50:00Z",
    recebidas: [{ body: pede, em: "2026-10-15T09:50:00Z" }],
  }), AGORA_1510, 0);
  assertEquals([cedo.tipo, cedo.elegivel, cedo.perdeHoje, cedo.soPeloPedido, cedo.porqueNaoSobe], ["contato_pedindo_preco", true, true, true, null]);
  assertStringIncludes(cedo.motivo, "Pode se perder hoje: o pedido chegou depois da última manhã e ninguém respondeu.");
  // cliente que pediu há 5 h: sobe (a regra comum espera 12 h) e o texto diz "parece"
  const cli = candidatoDeConversa(conv({
    last_body: "Quanto fica pra trocar a bomba?", last_inbound_at: "2026-10-15T05:30:00Z",
    recebidas: [{ body: "Quanto fica pra trocar a bomba?", em: "2026-10-15T05:30:00Z" }],
  }), AGORA_1510, 0);
  assertEquals([cli.tipo, cli.elegivel, cli.perdeHoje, cli.porqueNaoSobe], ["cliente_sem_resposta", true, true, null]);
  assertStringIncludes(cli.titulo, "e está há 5 h sem resposta. A mensagem parece pedir preço ou orçamento.");
  assertStringIncludes(cli.motivo, "Subiu porque é cliente, a mensagem parece pedir preço ou orçamento e está há 5 h sem resposta.");
  // pressa e pedido: a pressa explica (e não é "só pelo pedido")
  const comPressa = candidatoDeConversa(conv({ recebidas: [{ body: "Qual o valor? Preciso pra hoje", em: "2026-10-15T05:30:00Z" }], last_inbound_at: "2026-10-15T05:30:00Z" }), AGORA_1510, 0);
  assertEquals([comPressa.perdeHoje, comPressa.soPeloPedido], [true, false]);
  assert(!comPressa.motivo.includes("o pedido chegou depois da última manhã"));
});

Deno.test("pedido de antes da última manhã, fornecedor ou conversa de todo dia: a regra comum", () => {
  // 13/10: antes da manhã de 14/10 — passou de 12 h e sobe, mas não se perde hoje
  const velho = candidatoDeConversa(conv({
    categoria: "contato", client_id: null, contato: "x", last_inbound_at: "2026-10-13T15:00:00Z", recebidas: [{ body: "Qual o valor?", em: "2026-10-13T15:00:00Z" }],
  }), AGORA_1510, 0);
  assertEquals([velho.tipo, velho.perdeHoje, velho.soPeloPedido], ["contato_pedindo_preco", false, false]);
  // 14/10 às 07:00 de Brasília (antes da manhã de 14/10, que já o mostrou): não é do dia
  const antesDaManha = candidatoDeConversa(conv({
    categoria: "contato", client_id: null, contato: "x", last_inbound_at: "2026-10-14T10:00:00Z", recebidas: [{ body: "Qual o valor?", em: "2026-10-14T10:00:00Z" }],
  }), AGORA_1510, 0);
  assertEquals(antesDaManha.perdeHoje, false);
  const forn = candidatoDeConversa(conv({ categoria: "fornecedor", last_inbound_at: "2026-10-15T05:30:00Z", recebidas: [{ body: "Qual o valor?", em: "2026-10-15T05:30:00Z" }] }), AGORA_1510, 0);
  assertEquals([forn.tipo, forn.elegivel, forn.perdeHoje], ["fornecedor", false, false]);
  const todoDia = candidatoDeConversa(conv({ diasComMensagemSua: 5, last_inbound_at: "2026-10-15T05:30:00Z", recebidas: [{ body: "Qual o valor?", em: "2026-10-15T05:30:00Z" }] }), AGORA_1510, 0);
  assertEquals([todoDia.tipo, todoDia.elegivel, todoDia.perdeHoje], ["cliente_recente", false, false]);
});

Deno.test("a última manhã: o dia útil anterior (domingo e feriado só têm uma linha)", () => {
  assertEquals(manhaAnterior("2026-10-16"), "2026-10-15");
  // segunda: o sábado
  assertEquals(manhaAnterior("2026-10-19"), "2026-10-17");
  // terça depois de Finados (segunda, 02/11): o sábado 31/10
  assertEquals(manhaAnterior("2026-11-03"), "2026-10-31");
  // na segunda, o pedido de sábado à tarde ainda é do dia
  const segunda = new Date("2026-10-19T10:30:00Z");
  const sab = candidatoDeConversa(conv({
    categoria: "contato", client_id: null, contato: "x", last_inbound_at: "2026-10-17T18:00:00Z", recebidas: [{ body: "Qual o valor?", em: "2026-10-17T18:00:00Z" }],
  }), segunda, 0);
  assertEquals(sab.perdeHoje, true);
});

Deno.test("16/10 (manhã-sombra real): o fornecedor Jaison, que fechou com 'Perfeito, vou dar sequencia', não sobe", () => {
  // as mensagens dele depois da manhã de 15/10 (o dono respondeu às 14:32 "pode seguir")
  const recebidas = [
    { body: "Perfeito, vou dar sequencia", em: "2026-10-15T17:33:00Z" },
    { body: "Ainda vai entrar na produção e leva em torno de 3 a 5 dias uteis, você me dando o OK já envio para produção", em: "2026-10-15T17:05:00Z" },
    { body: "O PIX pode ser feito após a expedição finalizar e passar o valor do frete", em: "2026-10-15T17:03:00Z" },
    { body: "Chegasse a analisar a proposta?", em: "2026-10-15T16:54:00Z" },
  ];
  const c = candidatoDeConversa(conv({
    categoria: "contato", client_id: null, contato: "Jaison Consultor de Vendas Zendel", phone: "5547900000099",
    last_inbound_at: "2026-10-15T17:33:00Z", last_body: "Perfeito, vou dar sequencia", last_outbound_at: "2026-10-15T17:32:00Z",
    recebidas, diasComMensagemSua: 2,
  }), new Date("2026-10-16T10:30:00Z"), 0);
  // sem o "passar o valor do frete" como pedido, ele volta a ser o contato que não pede preço (o "vou dar sequencia"
  // também o tiraria: soAgradecimentoDesdeAResposta)
  assertEquals([c.tipo, c.elegivel, c.perdeHoje], ["contato_sem_cadastro", false, false]);
});

// Decisão 6 do dono (22/10/2026): o *detalhe* mostra o tipo ("Motorhome: Overland Vegini"), não "Embarcação ou
// veículo". Título, curto e ordem dos fatos não mudam.
Deno.test("fato da unidade: o tipo como rótulo; sem tipo (ou nome igual ao tipo), o termo geral", () => {
  const unidade = (fatos: Array<[string, string]>) => fatos.find(([r]) => !["Cliente", "OS", "Orçamento", "Valor", "Cobrança", "Saldo", "Venceu em"].includes(r));

  const joao = candidatoDeCobranca(cob({ cliente: "João Luiz Hang", os_numero: "OS-00051", barco: "Overland Vegini", tipo_unidade: "Motorhome" }), HOJE);
  assertEquals(joao.fatos.slice(0, 3), [["Cliente", "João Luiz Hang"], ["Motorhome", "Overland Vegini"], ["OS", "OS-00051"]]);
  assertEquals(joao.unidade, "Motorhome Overland Vegini");
  // o título continua só com o nome (sem mudar a manhã)
  assertStringIncludes(joao.titulo, "*João Luiz Hang* (Overland Vegini, OS-00051)");

  const semTipo = candidatoDeCobranca(cob({}), HOJE);
  assertEquals(unidade(semTipo.fatos), ["Embarcação ou veículo", "Aria"]);
  assertEquals(semTipo.unidade, "Aria");

  // 11 cadastros chamados só "Motorhome": nunca "Motorhome: Motorhome"
  const soTipo = candidatoDeOrcamento(orc({ barco: "Motorhome", tipo_unidade: "Motorhome" }), HOJE)!;
  assertEquals(unidade(soTipo.fatos), ["Embarcação ou veículo", "Motorhome"]);
  assertEquals(soTipo.unidade, "Motorhome");

  // "Trailer Darlan" do tipo Trailer: o tipo não sai duas vezes
  const darlan = candidatoDeOrcamento(orc({ numero: "ORÇ-00118", barco: "Trailer Darlan", tipo_unidade: "Trailer" }), HOJE)!;
  assertEquals(darlan.fatos.slice(0, 4), [["Orçamento", "ORÇ-00118"], ["Cliente", "EVERTON CARLOS PINHEIRO"], ["Trailer", "Darlan"], ["Valor", "R$ 120.020,00"]]);
  assertEquals(darlan.unidade, "Trailer Darlan");
  assertEquals(darlan.titulo, "*ORÇ-00118* (EVERTON CARLOS PINHEIRO, Trailer Darlan), R$ 120.020,00: montado em 13/10 e não enviado.");

  const lancha = candidatoDeOs(os({ barco: "Itapoã", tipo_unidade: "Lancha" }), HOJE)!;
  assertEquals(lancha.fatos.slice(0, 4), [["OS", "OS-00104"], ["Cliente", "Flávio da Igreja"], ["Lancha", "Itapoã"], ["Valor", "R$ 2.760,00"]]);
  assertEquals(lancha.unidade, "Lancha Itapoã");

  // sem unidade: nenhum fato da unidade, e a unidade fica null
  const sem = candidatoDeOs(os({ barco: null, tipo_unidade: "Lancha" }), HOJE)!;
  assertEquals(sem.fatos.slice(0, 3), [["OS", "OS-00104"], ["Cliente", "Flávio da Igreja"], ["Valor", "R$ 2.760,00"]]);
  assertEquals(sem.unidade, null);
});
