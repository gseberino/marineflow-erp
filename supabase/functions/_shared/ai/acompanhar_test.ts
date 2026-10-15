// Regras do vigia acompanhar-conversas (06/10/2026). O que se protege: só avisa quando a última
// mensagem é do contato e passou o intervalo; não repete antes do intervalo; teto de 3 por dia;
// prazo vencido encerra; lembrete e promessa avisam uma vez na hora; só no horário comercial; o
// texto pede ao assistente para ler, sugerir e chamar send_whatsapp_message.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type Acompanhamento, decidir, horaDeAvisar, janelaDoEncerramento, tempoEsperando, textoDoAviso } from "./acompanhar.ts";
import { conversaEncerradaPeloContato, MOTIVO_CONTATO_ENCERROU } from "../whatsapp/contato-encerrou.ts";

// Terça 06/10/2026, 14:00 em Brasília.
const AGORA = new Date("2026-10-06T17:00:00.000Z");
const horasAtras = (h: number) => new Date(AGORA.getTime() - h * 3600_000).toISOString();

const base: Acompanhamento = {
  id: "a1", phone_normalized: "5547999990000", contato: "Miguel", modo: "acompanhar", intervalo_min: 120,
  ate: "2026-10-13T20:00:00.000Z", lembrar_em: null, promessa: null, ultimo_aviso_em: null,
  avisos_dia: null, avisos_no_dia: 0, created_at: horasAtras(48),
};
const esperando = (h: number) => ({ ultimaRecebida: { em: horasAtras(h), texto: "E o radar, chega quando?" }, ultimaEnviadaEm: horasAtras(h + 1) });

Deno.test("avisa quando ele espera há mais que o intervalo; não avisa se a HBR respondeu ou se é cedo", () => {
  assertEquals(decidir(base, esperando(3), AGORA), { acao: "avisar" });
  assertEquals(decidir(base, esperando(1), AGORA), { acao: "esperar" }, "menos que 2h");
  assertEquals(decidir(base, { ultimaRecebida: { em: horasAtras(5), texto: "?" }, ultimaEnviadaEm: horasAtras(4) }, AGORA), { acao: "esperar" }, "a HBR respondeu depois");
  assertEquals(decidir(base, { ultimaRecebida: null, ultimaEnviadaEm: null }, AGORA), { acao: "esperar" });
});

Deno.test("não repete antes do intervalo, teto de 3 por dia, prazo vencido encerra", () => {
  assertEquals(decidir({ ...base, ultimo_aviso_em: horasAtras(1) }, esperando(5), AGORA), { acao: "esperar" });
  assertEquals(decidir({ ...base, ultimo_aviso_em: horasAtras(3) }, esperando(5), AGORA), { acao: "avisar" });
  assertEquals(decidir({ ...base, avisos_dia: "2026-10-06", avisos_no_dia: 3 }, esperando(5), AGORA), { acao: "esperar" });
  assertEquals(decidir({ ...base, avisos_dia: "2026-10-05", avisos_no_dia: 3 }, esperando(5), AGORA), { acao: "avisar" }, "o teto é por dia");
  assertEquals(decidir({ ...base, ate: horasAtras(1) }, esperando(5), AGORA), { acao: "encerrar", motivo: "prazo" });
});

Deno.test("lembrete e promessa: avisam quando chega a hora, mesmo sem mensagem pendente", () => {
  const lembrete: Acompanhamento = { ...base, modo: "lembrar_em", lembrar_em: horasAtras(0.1) };
  assertEquals(decidir(lembrete, { ultimaRecebida: null, ultimaEnviadaEm: null }, AGORA), { acao: "avisar" });
  assertEquals(decidir({ ...lembrete, lembrar_em: horasAtras(-1) }, esperando(5), AGORA), { acao: "esperar" });
  const promessa: Acompanhamento = { ...base, modo: "promessa", lembrar_em: horasAtras(0.5), promessa: "Amanhã te mando o orçamento" };
  assertEquals(decidir(promessa, { ultimaRecebida: null, ultimaEnviadaEm: horasAtras(20) }, AGORA), { acao: "avisar" });
});

Deno.test("horário de avisar: 8h–20h seg–sáb", () => {
  assert(horaDeAvisar(AGORA));
  assert(!horaDeAvisar(new Date("2026-10-06T23:30:00.000Z")), "20:30");
  assert(!horaDeAvisar(new Date("2026-10-11T15:00:00.000Z")), "domingo");
  assert(!horaDeAvisar(new Date("2026-10-07T10:00:00.000Z")), "07:00");
});

Deno.test("o texto do aviso pede para ler, sugerir e chamar send_whatsapp_message", () => {
  const t = textoDoAviso(base, esperando(3), AGORA, "+55 (47) 99999-0000");
  assert(t.startsWith("🤖 Acompanhamento"));
  assertStringIncludes(t, "Miguel (+55 (47) 99999-0000) está esperando resposta");
  assertStringIncludes(t, 'há 3h: "E o radar, chega quando?"');
  assertStringIncludes(t, "get_whatsapp_conversation (phone 5547999990000");
  assertStringIncludes(t, "send_whatsapp_message com to_phone 5547999990000");
  const p = textoDoAviso({ ...base, modo: "promessa", promessa: "Amanhã te mando o orçamento" }, esperando(3), AGORA, "+55 (47) 99999-0000");
  assertStringIncludes(p, 'você escreveu a Miguel (+55 (47) 99999-0000): "Amanhã te mando o orçamento"');
  assertEquals(tempoEsperando(horasAtras(0.5), AGORA), "30 min");
  assertEquals(tempoEsperando(horasAtras(72), AGORA), "3 dias");
});

// "Fechou com outra" encerra o acompanhamento (15/10/2026). Caso real do Miguel: o acompanhamento
// nasceu em 06/10 13:47; em 07/10 às 14:15 ele escreveu que fechou com outra empresa, às 14:58
// "Sim, já fechei" — e o vigia avisou o dono mais 7 vezes (08 a 10/10) até o dono encerrar à mão.
Deno.test("contato que fechou com outra empresa: encerra, em qualquer modo, com o motivo", () => {
  const miguel: Acompanhamento = {
    ...base, id: "8830f06c-8972-44f9-9d08-bf4adfcc1527", phone_normalized: "351966776422",
    ate: "2026-10-13T16:47:20.319Z", created_at: "2026-10-06T16:47:20.375Z",
  };
  const AS_1430 = new Date("2026-10-07T17:30:00.000Z"); // 07/10 14:30 em Brasília, a rodada seguinte
  // As recebidas, da mais recente para a mais antiga (como o vigia lê).
  const recebidas = ["[conteúdo vazio]", "André você demora muito pra responder e por isso acabei fechando com outra empresa. Obrigado"];
  const estado = {
    ultimaRecebida: { em: "2026-10-07T17:23:03.261Z", texto: "[conteúdo vazio]" },
    ultimaEnviadaEm: "2026-10-07T16:45:00.000Z",
    encerrouPeloContato: conversaEncerradaPeloContato(recebidas),
  };
  assertEquals(decidir(miguel, estado, AS_1430), { acao: "encerrar", motivo: MOTIVO_CONTATO_ENCERROU });
  // Antes da regra, o mesmo estado esperava e, passado o intervalo, avisava.
  const semMarca = { ...estado, encerrouPeloContato: undefined };
  assertEquals(decidir(miguel, semMarca, AS_1430), { acao: "esperar" });
  assertEquals(decidir(miguel, semMarca, new Date("2026-10-08T12:00:00.000Z")), { acao: "avisar" });
  // Promessa e lembrete também: não há o que cumprir para quem já fechou com outra.
  const promessa: Acompanhamento = { ...miguel, modo: "promessa", lembrar_em: horasAtras(1), promessa: "Amanhã te mando o orçamento" };
  assertEquals(decidir(promessa, estado, AGORA), { acao: "encerrar", motivo: MOTIVO_CONTATO_ENCERROU });
  // "Sim, já fechei" sozinho é ambíguo: não encerra.
  assertEquals(conversaEncerradaPeloContato(["Sim, já fechei"]), false);
});

Deno.test("janela do encerramento: 7 dias, mas nunca antes do acompanhamento nascer", () => {
  const agora = new Date("2026-10-07T17:30:00.000Z");
  // Criado há 1 dia: só vale o que ele disse depois disso.
  assertEquals(janelaDoEncerramento({ created_at: "2026-10-06T16:47:20.375Z" }, agora), "2026-10-06T16:47:20.375Z");
  // Criado há 20 dias: só os últimos 7.
  assertEquals(janelaDoEncerramento({ created_at: "2026-09-17T12:00:00.000Z" }, agora), "2026-09-30T17:30:00.000Z");
  // Data ilegível: os últimos 7 dias.
  assertEquals(janelaDoEncerramento({ created_at: "" }, agora), "2026-09-30T17:30:00.000Z");
});
