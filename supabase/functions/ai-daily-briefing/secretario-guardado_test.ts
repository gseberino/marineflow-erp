// (16/10/2026) A manhã e a tarde com o que o portão guardou, F1 e F5 — as partes puras. O que se protege:
//   · SEM guardado a manhã é a de antes, byte a byte (o mesmo texto de montarDosDados sem o parâmetro);
//   · com guardado o bloco entra logo depois da abertura/"Na rua", cabe em 1.000 caracteres (encurta por último) e o
//     contato que já é item com letra vai junto, sem linha;
//   · domingo/feriado: "1 coisa ficou de ontem";
//   · F1: quem escreveu hoje e está há 4 h sem resposta (o caso Giancarlo, 13/10), fora genérico, fornecedor e quem já
//     tem letra; os acordados primeiro;
//   · F5: a linha do vigia só com o último mês pronto = o mês passado ou mais novo.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type GuardadoLido, montarDosDados } from "./secretario.ts";
import { nomeSemLetra, semRespostaDesdeHoje } from "./secretario-tarde-regras.ts";
import { candidatoDeConversa, soAgradecimentoDesdeAResposta } from "./secretario-candidatos.ts";
import { mesPassado, ultimoMesPronto, vigiaValeNaRevisao } from "./secretario-tarde-coleta.ts";
import { META_DE_CARACTERES } from "./secretario-texto.ts";
import { AGORA_1510, coleta1510, deHoje1510, HOJE_1510 } from "./secretario-fixture.ts";
import { REGRAS_PADRAO } from "../_shared/uma-voz/portao.ts";
import type { AvisoGuardado } from "../_shared/uma-voz/guardado.ts";

const ESCRITORIO = { propostas: { saidas: 46, entradas: 4, transferencias: 1, outras: 0 }, alertas: 15, regras: 103, debitosSemLoja: 6, entradas: null };

function aviso(o: Partial<AvisoGuardado>): AvisoGuardado {
  return {
    id: "x", fonte: "conexao", assunto: "sistema", destino: "proxima_fixa", motivo: "destino", texto: null, dados: {},
    registrado_em: "2026-10-14T21:00:00Z", dia: "2026-10-14", mensagem: "manha", reaberto: 0, ...o,
  };
}

function manha(guardado?: GuardadoLido | null, hoje = HOJE_1510) {
  return montarDosDados({
    hoje, agora: AGORA_1510, coleta: coleta1510(), historico: [], naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(),
    escritorio: ESCRITORIO, guardado,
  });
}

Deno.test("manhã sem guardado = a de antes, byte a byte", () => {
  const antes = montarDosDados({ hoje: HOJE_1510, agora: AGORA_1510, coleta: coleta1510(), historico: [], naRua: { total: 21026, n: 5 }, deHoje: deHoje1510(), escritorio: ESCRITORIO });
  for (const g of [undefined, null, { modo: "sombra" as const, avisos: [], resolvidos: new Set<string>(), regras: REGRAS_PADRAO }]) {
    const m = manha(g);
    assertEquals(m.texto, antes.texto);
    assertEquals(m.guardado ?? null, null);
  }
});

Deno.test("manhã com guardado: o bloco depois do 'Na rua', abaixo de 1.000 caracteres; o contato com letra vai junto sem linha", () => {
  const avisos = [
    aviso({ id: "a1", fonte: "conexao", dados: { desde: "2026-10-14T23:10:00Z", ate: "2026-10-15T00:30:00Z" } }),
    // o Jorge G. é o item B da manhã de 15/10: o aviso do mesmo contato vai junto, sem linha própria
    aviso({ id: "a2", fonte: "acompanhar", assunto: `contato:${coleta1510().conversas.find((c) => c.contato.startsWith("Jorge"))!.phone}`, dados: { contato: "Jorge", mensagem_em: "2026-10-14T17:53:00Z" } }),
    aviso({ id: "a3", fonte: "promessa", assunto: "contato:5547900000123", dados: { contato: "Eng. Rafael B. (Dometic)", promessa: "Claro, te passo agora!" } }),
  ];
  const m = manha({ modo: "sombra", avisos, resolvidos: new Set(["a3"]), regras: REGRAS_PADRAO });
  const linhas = m.texto.split("\n");
  assertEquals(linhas[0], "Bom dia! Quinta, 15/10. Hoje 3 coisas pedem você.");
  assertEquals(linhas[1], "Na rua: R$ 21.026,00 vencidos (5).");
  assertEquals(linhas[2], "Guardei 1 aviso para não te interromper: o WhatsApp ficou fora das 20:10 às 21:30.");
  assert(m.texto.length <= META_DE_CARACTERES, `${m.texto.length}`);
  assertEquals(m.guardado?.plano.mostrados, ["a1", "a2"]);
  assertEquals(m.guardado?.plano.resolvidos, ["a3"], "D8: a promessa já cumprida some");
});

Deno.test("domingo com guardado: '1 coisa ficou de ontem'", () => {
  const m = manha({ modo: "sombra", avisos: [aviso({ id: "a1", fonte: "promessa", dados: { contato: "Jorge", promessa: "segunda te ligo" } })], resolvidos: new Set(), regras: REGRAS_PADRAO }, "2026-10-18");
  assertEquals(m.texto, 'Bom dia! Domingo. 1 coisa ficou de ontem: promessa sua a Jorge: "segunda te ligo". *lista* se quiser ver.');
});

Deno.test("F1: Giancarlo 13/10 (10:31, sem resposta às 17:30) entra; genérico, fornecedor, respondido e quem tem letra não", () => {
  const agora = new Date("2026-10-13T20:30:00Z");
  const esperando = [
    { phone: "5547900000555", contato: "Giancarlo S.", categoria: "cliente", last_inbound_at: "2026-10-13T13:33:00Z", last_outbound_at: "2026-10-12T20:00:00Z" },
    { phone: "5547900000666", contato: "Cliente Final", categoria: "cliente", last_inbound_at: "2026-10-13T12:00:00Z", last_outbound_at: null },
    { phone: "5547900000777", contato: "Benjamin", categoria: "fornecedor", last_inbound_at: "2026-10-13T12:00:00Z", last_outbound_at: null },
    { phone: "5547900000888", contato: "Jorge", categoria: "cliente", last_inbound_at: "2026-10-13T19:00:00Z", last_outbound_at: null },
    { phone: "5547900000999", contato: "Nelson", categoria: "cliente", last_inbound_at: "2026-10-13T12:00:00Z", last_outbound_at: null },
  ];
  const recebidas = [
    { phone_normalized: "5547900000555", occurred_at: "2026-10-13T13:31:00Z" }, { phone_normalized: "5547900000555", occurred_at: "2026-10-13T13:33:00Z" },
    { phone_normalized: "5547900000666", occurred_at: "2026-10-13T12:00:00Z" }, { phone_normalized: "5547900000777", occurred_at: "2026-10-13T12:00:00Z" },
    // o Jorge escreveu às 16:00 (1h30): ainda não são 4 h
    { phone_normalized: "5547900000888", occurred_at: "2026-10-13T19:00:00Z" },
    { phone_normalized: "5547900000999", occurred_at: "2026-10-13T12:00:00Z" },
  ];
  const r = semRespostaDesdeHoje({ esperando, recebidas, agora, horas: 4, comLetra: new Set(["5547900000999"]), acordados: new Map() });
  assertEquals(r, [{ phone: "5547900000555", nome: "Giancarlo S.", desde: "10:31", acordei: null }]);
  // o acordado de hoje vem primeiro, mesmo sendo lead e com menos de 4 h
  const a = semRespostaDesdeHoje({ esperando, recebidas, agora, horas: 4, comLetra: new Set(), acordados: new Map([["5547900000888", "2026-10-13T19:30:00Z"]]) });
  assertEquals(a.map((x) => [x.nome, x.acordei]), [["Jorge", "16:30"], ["Nelson", null], ["Giancarlo S.", null]]);
  // horas = 0: só os acordados
  assertEquals(semRespostaDesdeHoje({ esperando, recebidas, agora, horas: 0, comLetra: new Set(), acordados: new Map() }), []);
  // sem as recebidas (leitura falhou): usa a última de hoje
  assertEquals(semRespostaDesdeHoje({ esperando, recebidas: null, agora, horas: 4, comLetra: new Set(["5547900000999"]), acordados: new Map() })[0].desde, "10:33");
});

Deno.test("F5: o vigia só com o último mês pronto recente (em outubro, setembro; julho não)", () => {
  assertEquals(mesPassado("2026-10-19"), "2026-09");
  assertEquals(mesPassado("2026-01-05"), "2025-12");
  const julho = { meses: [{ mes: "2026-07", pronto: true }, { mes: "2026-08", pronto: false }, { mes: "2026-09", pronto: false }] };
  assertEquals(ultimoMesPronto(julho), "2026-07");
  assertEquals(vigiaValeNaRevisao(julho, "2026-10-19"), false);
  assertEquals(vigiaValeNaRevisao({ meses: [{ mes: "2026-09", pronto: true }] }, "2026-10-19"), true);
  assertEquals(vigiaValeNaRevisao({}, "2026-10-19"), false);
  assertEquals(vigiaValeNaRevisao(null, "2026-10-19"), false);
  assertStringIncludes(String(ultimoMesPronto({ meses: [{ mes: "2026-09-01", pronto: true }] })), "2026-09");
});

Deno.test("F1: o nome curto da linha sem letra (o primeiro nome e a inicial do último)", () => {
  assertEquals(nomeSemLetra("Giancarlo Ribeiro dos Santos"), "Giancarlo S.");
  assertEquals(nomeSemLetra("Marcelo Marco Bertoldi"), "Marcelo B.");
  assertEquals(nomeSemLetra("Jorge Girardon"), "Jorge Girardon");
  assertEquals(nomeSemLetra("  Nelson  "), "Nelson");
  assertEquals(nomeSemLetra("Eng.⁰ Rafael Borges DOMETIC"), "Eng.⁰ D.");
});

// (16/10/2026, correção do coordenador) Agradecimento não é "sem resposta": o caso real de 15/10 (Nelson).
Deno.test("F1: quem só agradeceu hoje não entra; agradecimento com pergunta ou pedido entra", () => {
  const agora = new Date("2026-10-15T20:30:00Z");
  const esperando = [
    { phone: "5547900005678", contato: "Nelson", categoria: "cliente", last_inbound_at: "2026-10-15T10:55:24Z", last_outbound_at: "2026-10-15T10:50:00Z" },
    { phone: "5547900000780", contato: "Jorge Girardon", categoria: "cliente", last_inbound_at: "2026-10-15T10:56:36Z", last_outbound_at: "2026-10-15T10:53:00Z" },
    { phone: "5547900000111", contato: "Ana", categoria: "cliente", last_inbound_at: "2026-10-15T12:00:00Z", last_outbound_at: null },
  ];
  const recebidas = [
    { phone_normalized: "5547900005678", occurred_at: "2026-10-15T10:55:24Z", body: "Bom dia Gustavo! Ótimo 👍" },
    { phone_normalized: "5547900000780", occurred_at: "2026-10-15T10:55:57Z", body: "🎤 Ah, beleza. Então tá bom. Eu tô pensando em deixar a segunda-feira ali" },
    { phone_normalized: "5547900000111", occurred_at: "2026-10-15T12:00:00Z", body: "Obrigado, e quanto fica?" },
  ];
  const r = semRespostaDesdeHoje({ esperando, recebidas, agora, horas: 4, comLetra: new Set(), acordados: new Map() });
  assertEquals(r.map((x) => x.nome), ["Jorge Girardon", "Ana"]);
  // sem as recebidas lidas: a última mensagem decide
  const s = semRespostaDesdeHoje({ esperando: [{ ...esperando[0], last_body: "Bom dia Gustavo! Ótimo 👍" }], recebidas: null, agora, horas: 4, comLetra: new Set(), acordados: new Map() });
  assertEquals(s, []);
});

Deno.test("manhã: a conversa cuja última mensagem é só agradecimento fica na lista com o porquê", () => {
  const agora = new Date("2026-10-16T10:30:00Z");
  const base = {
    phone: "5547900005678", contato: "Nelson", categoria: "cliente" as const, last_inbound_at: "2026-10-15T10:55:24Z",
    client_id: "c-nelson", diasComMensagemSua: 1, last_outbound_at: "2026-10-15T10:50:00Z",
  };
  const so = candidatoDeConversa({ ...base, last_body: "Bom dia Gustavo! Ótimo 👍", recebidas: [{ body: "Bom dia Gustavo! Ótimo 👍", em: "2026-10-15T10:55:24Z" }] }, agora, 0);
  assertEquals([so.elegivel, so.porqueNaoSobe], [false, "Ficou na lista: a última mensagem parece só um agradecimento."]);
  const pede = candidatoDeConversa({ ...base, last_body: "Obrigado, e quanto fica?", recebidas: [{ body: "Obrigado, e quanto fica?", em: "2026-10-15T10:55:24Z" }] }, agora, 0);
  assertEquals([pede.tipo, pede.elegivel], ["cliente_sem_resposta", true]);
  // um pedido sem resposta seguido de "Bom dia" (o "cutucão") continua subindo
  const cutucao = candidatoDeConversa({
    ...base, last_body: "Bom dia",
    recebidas: [{ body: "Bom dia", em: "2026-10-15T10:55:24Z" }, { body: "ok, me manda o orçamento", em: "2026-10-14T12:00:00Z" }],
    last_outbound_at: "2026-10-13T12:00:00Z",
  }, agora, 0);
  assertEquals(cutucao.elegivel, true);
  assertEquals(soAgradecimentoDesdeAResposta({ last_body: "ok", recebidas: [], last_outbound_at: null }), true);
});
