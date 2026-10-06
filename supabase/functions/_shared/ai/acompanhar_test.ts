// Regras do vigia acompanhar-conversas (06/10/2026). O que se protege: só avisa quando a última
// mensagem é do contato e passou o intervalo; não repete antes do intervalo; teto de 3 por dia;
// prazo vencido encerra; lembrete e promessa avisam uma vez na hora; só no horário comercial; o
// texto pede ao assistente para ler, sugerir e chamar send_whatsapp_message.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type Acompanhamento, decidir, horaDeAvisar, tempoEsperando, textoDoAviso } from "./acompanhar.ts";

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
