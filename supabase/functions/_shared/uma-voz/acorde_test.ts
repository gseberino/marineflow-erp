// "Me acorde se" (secretário, Passo 4, P4.2, 16/10/2026) — o detector e o texto, com as mensagens REAIS de 02–15/10
// (SELECT em whatsapp_messages; telefones de mentira). O que se protege (spec §3.2): Miguel 07/10 09:02 acorda às
// 09:45 com a proposta pronta e o cartão; 05/10 08:28 acorda sem cartão (janela da manhã); a vendedora da Vivo (20/10/2026:
// não acorda mais — pareceVendedor); respondido em 25 min não; fornecedor não; "se aprovado" não; mensagem de ontem não;
// o mesmo contato com duas mensagens = um disparo de pressa; a desistência dispara na hora (D2 decide o destino);
// D11 não acorda duas vezes sobre a mesma mensagem.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  avisoDoCliente, type ConversaDoAcorde, disparosDaConversa, gatilhoDaMensagem, legendaDoPdf, maiorOrcamento,
  mensagemNovaEFatoNovo, normalizar, type OrcamentoAberto, propostaPronta, textoDaNfe, textoDoAcordeDeCliente,
  quedaDerrubouAManha, textoDoCertificado, textoDoGolpe, textoDoSistema, trechoDoGatilho,
} from "./acorde.ts";
import { REGRAS_PADRAO } from "./portao.ts";

const br = (dia: string, hm: string) => new Date(`2026-10-${dia}T${hm}:00-03:00`).toISOString();

const MIGUEL_0902 =
  "🎤 Olá, Gustavo. Vamos deixar isto da câmera para depois, porque eu preciso de fechar a solução completa hoje, ou consigo, ou com outras hipóteses que eu tenho. Você não comentou o áudio que eu lhe falei, sobre embarcações que você já fez, um histórico da vossa";
const MIGUEL_1415 = "André você demora muito pra responder e por isso acabei fechando com outra empresa. Obrigado";

function conversa(o: Partial<ConversaDoAcorde> & { recebidas: ConversaDoAcorde["recebidas"] }): ConversaDoAcorde {
  return {
    phone: "351900000422", nome: "Miguel", cliente: true, fornecedor: false, client_id: "c-miguel",
    ultimaSaidaEm: br("06", "17:06"), diasComMensagemSua: 1, ...o,
  };
}

// os orçamentos do Miguel em 07/10 (valores, custos e validade do banco: ORÇ-00113 criado 04/10, 3 dias)
const ORCS: OrcamentoAberto[] = [
  { id: "orc-113", numero: "ORÇ-00113", valor: 105603.90, status: "awaiting_approval", mexido_em: br("05", "15:46"), sinal: 103301.32, validade: "2026-10-07" },
  { id: "orc-103", numero: "ORÇ-00103", valor: 58310.05, status: "awaiting_approval", mexido_em: br("23", "20:19").replace("2026-10-23", "2026-09-23"), sinal: 54660.05, validade: "2026-10-18" },
];

Deno.test("palavras: normalizar não corta e guarda o '?'; gatilho por tipo de contato", () => {
  assertEquals(normalizar("🎤 Você consegue HOJE?"), "voce consegue hoje ?");
  assertEquals(gatilhoDaMensagem(MIGUEL_0902, true), "fechar_hoje");
  assertEquals(gatilhoDaMensagem("Tudo bem? Podemos conversar hoje?", true), "pressa");
  assertEquals(gatilhoDaMensagem(MIGUEL_1415, true), "desistencia");
  // lead: pressa precisa de pedido
  assertEquals(gatilhoDaMensagem("Tem disponibilidade hoje pela manhã ou início da tarde pra trocar o filtro?", false), "pressa");
  assertEquals(gatilhoDaMensagem("Hoje, temos os seguintes tamanhos disponíveis:\n- 500x350 = *R$1.900,00*", false), null, "fornecedor sem vínculo oferecendo");
  assertEquals(gatilhoDaMensagem("Bom Dia, Gustavo. Sobre o serviço na Iveco que falamos. Esta aprovado, favor seguir com os reparos.", false), "fechar");
  assertEquals(gatilhoDaMensagem("Transdutor 10 pinos para furuno fish finder (fcv-228)\nSe aprovado,  serviço vai ser feito aqui na oficina", false), null, "condicional");
  assertEquals(gatilhoDaMensagem("[audio]", true), null);
  assertEquals(gatilhoDaMensagem("Fechar o pedido somente do cerbo?", false), null, "falar de fechar não é querer fechar");
  // a vendedora da Vivo: "hoje" + "?" num lead — a palavra está lá (o disparo não sai: pareceVendedor, 20/10/2026)
  assertEquals(gatilhoDaMensagem("Oii Sou a Allana, Consultora Empresarial da Vivo. Eu to entrando em contato com voce hoje, por que eu identifiquei que o seu contrato com a TIM, esta chegando ao fim, e nesse período *vai haver reajuste automático de valor*. Eu tenho aqui ofertas para voce pag?", false), "pressa");
});

Deno.test("trecho: a frase com a palavra, até 160 caracteres, sem o 🎤", () => {
  assertEquals(trechoDoGatilho(MIGUEL_0902, "fechar_hoje"),
    "Vamos deixar isto da câmera para depois, porque eu preciso de fechar a solução completa hoje, ou consigo, ou com outras hipóteses que eu tenho.");
  assertEquals(trechoDoGatilho(MIGUEL_1415, "desistencia"), MIGUEL_1415.split(". ")[0] + ".");
  assert(trechoDoGatilho("x ".repeat(200), "pressa").length <= 160);
});

Deno.test("Miguel 07/10: 09:02 sem resposta → às 09:30 ainda não (28 min); às 09:45 dispara (43 min)", () => {
  const c = conversa({ recebidas: [{ em: br("06", "17:12"), body: "🎤 Gustavo, ok, eu entendi perfeitamente…" }, { em: br("07", "09:02"), body: MIGUEL_0902 }] });
  assertEquals(disparosDaConversa(c, new Date(br("07", "09:30")), 30), []);
  const d = disparosDaConversa(c, new Date(br("07", "09:45")), 30);
  assertEquals(d.length, 1);
  assertEquals([d[0].tipo, d[0].gatilho, d[0].esperaMin, d[0].audio], ["pressa", "fechar_hoje", 43, true]);
  assertEquals(d[0].mensagem.em, br("07", "09:02"));
});

Deno.test("Miguel 07/10 14:15: a desistência dispara na hora; a pressa da manhã é a MESMA espera (mesma mensagem)", () => {
  const c = conversa({ recebidas: [{ em: br("07", "09:02"), body: MIGUEL_0902 }, { em: br("07", "14:15"), body: MIGUEL_1415 }, { em: br("07", "14:58"), body: "Sim, já fechei" }] });
  const d = disparosDaConversa(c, new Date(br("07", "15:00")), 30);
  assertEquals(d.map((x) => [x.tipo, x.mensagem.em]), [["pressa", br("07", "09:02")], ["desistencia", br("07", "14:15")]]);
});

Deno.test("fica de fora: respondido, fornecedor, conversa de todo dia, mensagem de ontem, ainda dentro dos 30 min", () => {
  const lead = { cliente: false, client_id: null, nome: "Contato" };
  const msg = { em: br("06", "15:50"), body: "🎤 Eu entrego na rua, né? Eu tenho avan para entregar, né? Só que hoje eu não estou na cidade, né?" };
  // respondido aos 25 min (16:15): a saída é DEPOIS da mensagem
  assertEquals(disparosDaConversa(conversa({ ...lead, recebidas: [msg], ultimaSaidaEm: br("06", "16:15") }), new Date(br("06", "16:30")), 30), []);
  // sem resposta, depois de 30 min, dispara
  assertEquals(disparosDaConversa(conversa({ ...lead, recebidas: [msg], ultimaSaidaEm: null }), new Date(br("06", "16:30")), 30).length, 1);
  assertEquals(disparosDaConversa(conversa({ ...lead, fornecedor: true, recebidas: [msg], ultimaSaidaEm: null }), new Date(br("06", "16:30")), 30), []);
  assertEquals(disparosDaConversa(conversa({ ...lead, diasComMensagemSua: 4, recebidas: [msg], ultimaSaidaEm: null }), new Date(br("06", "16:30")), 30), [],
    "conversa de todo dia: a pressa sozinha não acorda");
  // 02/10 20:04 (fora da janela) visto às 08:00 de 03/10: é de ontem, a manhã já mostra
  const ontem = { em: br("02", "20:04"), body: "🎤 … que hoje em dia …?" };
  assertEquals(disparosDaConversa(conversa({ recebidas: [ontem] }), new Date(br("03", "08:00")), 30), []);
  assertEquals(disparosDaConversa(conversa({ recebidas: [{ em: br("07", "09:30"), body: MIGUEL_0902 }] }), new Date(br("07", "09:45")), 30), [], "15 min");
  // a espera é configurável (voz_unica_regras.acorde_espera_min)
  assertEquals(disparosDaConversa(conversa({ recebidas: [{ em: br("07", "09:30"), body: MIGUEL_0902 }] }), new Date(br("07", "09:45")), 10).length, 1);
});

// (20/10/2026) O falso positivo de 20/10 (e o de 02/10): contato SEM cadastro de cliente que se apresenta vendendo não
// acorda — pelo nome do contato ou pelo texto de hoje. O cliente cadastrado não passa pela regra; os leads reais do período
// (Josemar 20/10 09:58, o filtro de 09/10) continuam acordando.
Deno.test("vendedor sem cadastro não acorda (Ketelyn 20/10, Allana 02/10); cliente cadastrado e leads reais acordam", () => {
  const ketelyn = "Oii Sou a Ketelyn, Consultora Empresarial da Vivo. Eu to entrando em contato com voce hoje, por que eu identifiquei que o seu contrato com a Tim, esta chegando ao fim, e *nesse período tem um reajuste automático no valor*. Eu tenho aqui ofertas para voce pagar menos com mais benefícios. Posso te enviar um orçamento pra voce analisar sem compromisso?";
  const agora = new Date(br("20", "12:00"));
  const lead = { cliente: false, client_id: null, ultimaSaidaEm: null };
  assertEquals(gatilhoDaMensagem(ketelyn, false), "pressa", "a palavra continua lá");
  assertEquals(disparosDaConversa(conversa({ ...lead, nome: "Ketelyn Consultora empresarial", recebidas: [{ em: br("20", "11:17"), body: ketelyn }] }), agora, 30), []);
  assertEquals(disparosDaConversa(conversa({ ...lead, nome: "Ketelyn", recebidas: [{ em: br("20", "11:17"), body: ketelyn }] }), agora, 30), [], "só o texto já diz");
  assertEquals(disparosDaConversa(conversa({ ...lead, nome: "Allana Marques", recebidas: [{ em: br("20", "11:17"), body: ketelyn.replace("Ketelyn", "Allana") }] }), agora, 30), []);
  // o lead de verdade
  const josemar = disparosDaConversa(conversa({ ...lead, nome: "Josemar Santos", recebidas: [{ em: br("20", "09:58"), body: "Você teria disponibilidade de falarmos hoje?" }] }), new Date(br("20", "10:30")), 30);
  assertEquals(josemar.map((d) => [d.tipo, d.gatilho, d.esperaMin]), [["pressa", "pressa", 32]]);
  assertEquals(disparosDaConversa(conversa({ ...lead, nome: "Paulo  Chave Digital", recebidas: [{ em: br("09", "08:28"), body: "Tem disponibilidade hoje pela manhã ou início da tarde pra trocar o filtro?" }] }), new Date(br("09", "09:00")), 30).length, 1);
  // cliente cadastrado com "consultor" no nome do contato: a regra não vale para ele
  assertEquals(disparosDaConversa(conversa({ nome: "Miguel Consultor", recebidas: [{ em: br("07", "09:02"), body: MIGUEL_0902 }] }), new Date(br("07", "09:45")), 30).length, 1);
});

Deno.test("o mesmo contato com duas mensagens com a palavra = um disparo (a primeira desde a última resposta)", () => {
  const c = conversa({ ultimaSaidaEm: br("01", "18:00"), recebidas: [{ em: br("02", "12:10"), body: "🎤 Gustavo, você consegue me enviar um orçamento hoje ainda?" }, { em: br("02", "15:00"), body: "Consegue hoje?" }] });
  const d = disparosDaConversa(c, new Date(br("02", "16:00")), 30);
  assertEquals(d.length, 1);
  assertEquals(d[0].mensagem.em, br("02", "12:10"));
});

Deno.test("texto do acorde: Miguel 07/10 às 09:45 com a proposta pronta, o sinal, a validade, o telefone e o cartão", () => {
  const c = conversa({ recebidas: [{ em: br("07", "09:02"), body: MIGUEL_0902 }] });
  const agora = new Date(br("07", "09:45"));
  const [d] = disparosDaConversa(c, agora, 30);
  const a = textoDoAcordeDeCliente({ nome: "Miguel", disparo: d, orcamentos: ORCS, telefone: "+351900000422", podeCartao: true, agora });
  assertEquals(a.texto, [
    '*Miguel quer fechar hoje.* Áudio às 09:02: "Vamos deixar isto da câmera para depois, porque eu preciso de fechar a solução completa hoje, ou consigo, ou com outras hipóteses que eu tenho." Está há 43 min sem resposta.',
    "Proposta pronta: *ORÇ-00113*, R$ 105.603,90 (sinal de R$ 103.301,32 na aprovação; validade até 07/10). Também aberto: ORÇ-00103, R$ 58.310,05.",
    "Ligue agora: +351900000422",
    '*sim <seu PIN>* = mando o PDF do ORÇ-00113 com: "Miguel, segue a proposta completa (ORÇ-00113). Se estiver de acordo, confirmo o início com o sinal." · *não* = deixo com você',
  ].join("\n"));
  assertEquals(a.cartao, { service_order_id: "orc-113", numero: "ORÇ-00113", legenda: legendaDoPdf("Miguel", "ORÇ-00113") });
  // sem "pedido de sim/não" no texto: letras e palavras, nunca 1/2
  assert(!/\b1\b.*\b2\b/.test(a.texto.split("\n")[3]));
});

Deno.test("cartão só com o dono livre, depois das 09:30 e com orçamento; desistência nunca tem cartão", () => {
  const c = conversa({ ultimaSaidaEm: br("04", "18:00"), recebidas: [{ em: br("05", "08:28"), body: "Tudo bem? Podemos conversar hoje?" }] });
  const cedo = new Date(br("05", "08:58"));
  const [d] = disparosDaConversa(c, cedo, 30);
  const semCartao = textoDoAcordeDeCliente({ nome: "Miguel", disparo: d, orcamentos: ORCS, telefone: "+351900000422", podeCartao: true, agora: cedo });
  assertEquals(semCartao.cartao, null, "08:58 = janela da manhã");
  assert(!semCartao.texto.includes("*sim"));
  assertStringIncludes(semCartao.texto, "*Miguel pede para hoje.* Mensagem às 08:28");
  const tarde = new Date(br("05", "10:00"));
  assertEquals(textoDoAcordeDeCliente({ nome: "Miguel", disparo: d, orcamentos: ORCS, telefone: null, podeCartao: false, agora: tarde }).cartao, null, "dono ocupado");
  const semOrc = textoDoAcordeDeCliente({ nome: "Lead", disparo: d, orcamentos: [], telefone: "+5547900007900", podeCartao: true, agora: tarde });
  assertEquals(semOrc.cartao, null);
  assertStringIncludes(semOrc.texto, "Sem orçamento aberto no sistema.");
  assert(!semOrc.texto.includes("Ligue agora: null"));
  const des = disparosDaConversa(conversa({ recebidas: [{ em: br("07", "14:15"), body: MIGUEL_1415 }] }), new Date(br("07", "14:30")), 30)[0];
  const t = textoDoAcordeDeCliente({ nome: "Miguel", disparo: des, orcamentos: ORCS, telefone: "+351900000422", podeCartao: true, agora: new Date(br("07", "14:30")) });
  assertEquals(t.cartao, null);
  assertStringIncludes(t.texto, "*Miguel disse que fechou com outra empresa ou desistiu.*");
  assertStringIncludes(t.texto, "Estava em aberto: *ORÇ-00113*, R$ 105.603,90");
  assertStringIncludes(t.texto, "Ligue agora: +351900000422");
});

Deno.test("proposta pronta: a enviada mexida por último; sem enviada, o rascunho; validade vencida aparece", () => {
  assertEquals(propostaPronta(ORCS)?.numero, "ORÇ-00113");
  const rasc: OrcamentoAberto = { id: "r", numero: "ORÇ-00200", valor: 9000, status: "draft", mexido_em: br("08", "10:00"), sinal: null, validade: null };
  assertEquals(propostaPronta([...ORCS, rasc])?.numero, "ORÇ-00113", "rascunho perde para enviado");
  assertEquals(propostaPronta([rasc])?.numero, "ORÇ-00200");
  assertEquals(maiorOrcamento(ORCS), 105603.90);
  const c = conversa({ recebidas: [{ em: br("09", "09:00"), body: "preciso fechar hoje" }] });
  const [d] = disparosDaConversa(c, new Date(br("09", "10:00")), 30);
  assertStringIncludes(textoDoAcordeDeCliente({ nome: "Miguel", disparo: d, orcamentos: ORCS.slice(0, 1), telefone: null, podeCartao: false, agora: new Date(br("09", "10:00")) }).texto,
    "validade vencida em 07/10");
});

Deno.test("aviso ao portão: chave por espera; desistência pela D2 (R$ 5 mil+ acorda como fato novo; sem orçamento, próxima fixa)", () => {
  const c = conversa({ recebidas: [{ em: br("07", "09:02"), body: MIGUEL_0902 }, { em: br("07", "14:15"), body: MIGUEL_1415 }] });
  const [p, des] = disparosDaConversa(c, new Date(br("07", "14:30")), 30);
  const acorde = { texto: "t", cartao: null };
  const ap = avisoDoCliente({ conversa: c, disparo: p, orcamentos: ORCS, acorde, regras: REGRAS_PADRAO, novoFato: false });
  assertEquals([ap.fonte, ap.chave, ap.assunto, ap.destino, ap.novo_fato], ["cliente", `cliente:351900000422:${br("07", "09:02")}`, "contato:351900000422", "acorde", false]);
  assertEquals(ap.dados?.mensagem_em, br("07", "09:02"));
  const ad = avisoDoCliente({ conversa: c, disparo: des, orcamentos: ORCS, acorde, regras: REGRAS_PADRAO, novoFato: false });
  assertEquals([ad.chave.split(":")[0], ad.destino, ad.novo_fato], ["desistencia", "acorde", true]);
  const semOrc = avisoDoCliente({ conversa: c, disparo: des, orcamentos: [], acorde, regras: REGRAS_PADRAO, novoFato: true });
  assertEquals([semOrc.destino, semOrc.novo_fato], ["proxima_fixa", false]);
  const pequeno = avisoDoCliente({ conversa: c, disparo: des, orcamentos: [{ ...ORCS[0], valor: 4000 }], acorde, regras: REGRAS_PADRAO, novoFato: false });
  assertEquals(pequeno.destino, "proxima_fixa", "orçamento abaixo de R$ 5 mil");
  const comCartao = avisoDoCliente({ conversa: c, disparo: p, orcamentos: ORCS, acorde: { texto: "t", cartao: { service_order_id: "orc-113", numero: "ORÇ-00113", legenda: "L" } }, regras: REGRAS_PADRAO, novoFato: true });
  assertEquals(comCartao.dados?.cartao, { acao: "send_service_order_link", formato: "pdf", service_order_id: "orc-113", numero: "ORÇ-00113", legenda: "L" });
});

Deno.test("D11: mensagem nova = fato novo; a mesma mensagem que já acordou hoje, não; regra desligada, nunca", () => {
  const m = br("07", "09:02");
  assertEquals(mensagemNovaEFatoNovo(REGRAS_PADRAO, m, []), true);
  assertEquals(mensagemNovaEFatoNovo(REGRAS_PADRAO, m, [{ dados: { mensagem_em: "2026-10-07T12:02:00.000Z" } }]), false, "o detector já acordou sobre ela");
  assertEquals(mensagemNovaEFatoNovo(REGRAS_PADRAO, m, [{ dados: { mensagem_em: br("06", "17:12") } }]), true, "o acorde das 08:00 era sobre a de ontem");
  assertEquals(mensagemNovaEFatoNovo({ mensagem_nova_e_fato_novo: false }, m, []), false);
  assertEquals(mensagemNovaEFatoNovo(REGRAS_PADRAO, null, []), false);
});

Deno.test("os outros acordes: golpe, certificado, NF-e e sistema — sem emoji, com o que fazer", () => {
  assertEquals(textoDoGolpe({ conta: "financeiro@hbr", remetente: "atendimento@envios.adv", assunto: "Intimação" }),
    '*Parece golpe no e-mail financeiro@hbr:* atendimento@envios.adv, "Intimação". Não pague nem mude dados bancários sem confirmar por telefone. Não volto a avisar deste remetente.');
  assertEquals(textoDoCertificado(5, "2026-10-26"), "*O certificado A1 vence em 5 dias (26/10):* sem ele nenhuma NF-e sai. Renove na Contora.");
  assertEquals(textoDoCertificado(-1, "2026-10-20"), "*O certificado A1 venceu em 20/10:* sem ele nenhuma NF-e sai. Renove na Contora.");
  assertEquals(textoDaNfe({ numero: 321, cliente: "MP MOTOR HOMES", valor: 1650, motivo: "Rejeição 539: duplicidade de NF-e", os: "OS-00095" }),
    "*A NF-e nº 321 (MP MOTOR HOMES, R$ 1.650,00) foi rejeitada.* Rejeição 539: duplicidade de NF-e. Reemita pela OS-00095.");
  assertEquals(textoDoSistema({ desde: "2026-10-13T15:45:00Z", ate: "2026-10-13T17:05:00Z", manhaNaoChegou: false }), "O WhatsApp ficou fora das 12:45 às 14:05.");
  assertStringIncludes(textoDoSistema({ desde: "2026-10-13T05:45:00Z", ate: "2026-10-13T11:45:00Z", manhaNaoChegou: true }), "A manhã de hoje não chegou");
  for (const t of [textoDoGolpe({ conta: "a", remetente: "b", assunto: null }), textoDoCertificado(3, "2026-10-20")]) {
    assert(!/[\p{Extended_Pictographic}]/u.test(t), "sem emoji de painel");
  }
});

Deno.test("a queda derrubou a manhã: começou antes das 07:30 e acabou depois das 09:05", () => {
  assert(quedaDerrubouAManha("2026-10-13T05:45:00Z", "2026-10-13T12:10:00Z"), "02:45 → 09:10");
  assert(!quedaDerrubouAManha("2026-10-13T05:45:00Z", "2026-10-13T11:45:00Z"), "02:45 → 08:45: a fila ainda entrega");
  assert(!quedaDerrubouAManha("2026-10-13T15:45:00Z", "2026-10-13T17:05:00Z"), "12:45 → 14:05");
  assert(!quedaDerrubouAManha("x", "y"));
});

// Ensaio de 16/10: em 07/10 o dono tinha escrito ao Miguel em 4 dos 7 dias anteriores ("conversa de todo dia"). Com a
// exclusão geral, o caso que motivou o "me acorde se" não acordaria. A exclusão vale só para a pressa sem "fechar".
Deno.test("conversa de todo dia: 'quero fechar hoje' e a desistência acordam; o 'hoje' solto não", () => {
  const diario = conversa({ diasComMensagemSua: 4, recebidas: [{ em: br("07", "09:02"), body: MIGUEL_0902 }] });
  assertEquals(disparosDaConversa(diario, new Date(br("07", "09:45")), 30).map((d) => d.gatilho), ["fechar_hoje"]);
  const desistiu = conversa({ diasComMensagemSua: 6, recebidas: [{ em: br("07", "14:15"), body: MIGUEL_1415 }] });
  assertEquals(disparosDaConversa(desistiu, new Date(br("07", "14:30")), 30).map((d) => d.tipo), ["desistencia"]);
  const soHoje = conversa({ diasComMensagemSua: 4, ultimaSaidaEm: br("04", "18:00"), recebidas: [{ em: br("05", "08:28"), body: "Tudo bem? Podemos conversar hoje?" }] });
  assertEquals(disparosDaConversa(soHoje, new Date(br("05", "09:00")), 30), []);
});
