import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { aindaMudo, temMidiaPedivel, repescar, DESISTIR_APOS } from "./logica.ts";
// PAUSA_MS e ESPERA_APOS_FALHA_MS são exercitados pelos testes de ritmo abaixo.

// O que estes testes protegem é o Evolution, não o resultado.
//
// Ele roda no PC do dono, atrás do túnel, e cada tentativa o faz decifrar uma mídia. Já
// ficou 4h30 fora do ar em 24/09/2026. Se a janela de duas semanas passou — ou se ele
// caiu — todas as tentativas seguintes falham; insistir quarenta vezes transforma um job
// silencioso numa carga inútil em cima de um serviço já em apuros.

const semPausa = () => Promise.resolve();

Deno.test("desiste depois de falhas seguidas, em vez de varrer a lista inteira", async () => {
  const alvos = Array.from({ length: 40 }, (_, i) => ({ id: `m${i}` }));
  let chamadas = 0;
  const r = await repescar(alvos, async () => { chamadas++; return { ok: false }; }, semPausa);

  assertEquals(r.parouCedo, true);
  assertEquals(chamadas, DESISTIR_APOS, "parou na quinta, não na quadragésima");
  assertEquals(r.transcritos, 0);
});

Deno.test("falha isolada no meio não interrompe o resto", async () => {
  const alvos = Array.from({ length: 10 }, (_, i) => ({ id: `m${i}` }));
  // Uma falha a cada três: o contador de seguidas tem que ZERAR no sucesso seguinte.
  const r = await repescar(alvos, async (id) => ({ ok: Number(id.slice(1)) % 3 !== 0 }), semPausa);

  assertEquals(r.parouCedo, false);
  assertEquals(r.tentativas, 10);
  assertEquals(r.transcritos, 6);
  assertEquals(r.falhas, 4);
});

Deno.test("exceção conta como falha e não derruba a execução", async () => {
  const alvos = [{ id: "a" }, { id: "b" }, { id: "c" }];
  const r = await repescar(alvos, async (id) => {
    if (id === "b") throw new Error("Evolution fora do ar");
    return { ok: true };
  }, semPausa);

  assertEquals(r.transcritos, 2);
  assertEquals(r.falhas, 1);
  assertEquals(r.parouCedo, false);
});

Deno.test("lista vazia não chama nada", async () => {
  let chamou = false;
  const r = await repescar([], async () => { chamou = true; return { ok: true }; }, semPausa);
  assertEquals(chamou, false);
  assertEquals(r.tentativas, 0);
});

Deno.test("só entra na fila o áudio que ainda está mudo", () => {
  assertEquals(aindaMudo("[audio]"), true);
  assertEquals(aindaMudo(""), true);
  assertEquals(aindaMudo(null), true);
  // Já transcrito: o marcador 🎤 vem junto com o texto, e não pode ser retranscrito.
  assertEquals(aindaMudo("🎤 e o orçamento?"), false);
  assertEquals(aindaMudo("bom dia"), false);
});

Deno.test("sem a chave da mídia não há o que pedir ao Evolution", () => {
  assert(temMidiaPedivel({ raw_payload: { data: { key: { id: "ABC123" } } } }));
  assertEquals(temMidiaPedivel({ raw_payload: { data: { key: {} } } }), false);
  assertEquals(temMidiaPedivel({ raw_payload: {} }), false);
  assertEquals(temMidiaPedivel({}), false);
});

Deno.test("há pausa entre as tentativas — o ritmo lento é intencional", async () => {
  const pausas: number[] = [];
  await repescar(
    [{ id: "a" }, { id: "b" }],
    async () => ({ ok: true }),
    async (ms) => { pausas.push(ms); },
  );
  assertEquals(pausas.length, 2);
  // 1,5s (40/min) fez o Groq recusar no backfill de 25/09; 4s mantém ~15/min.
  assert(pausas.every((p) => p >= 4000), "ritmo rápido demais faz o Groq recusar por limite de taxa");
});

Deno.test("depois de falhar, espera MAIS — limite de taxa passa com tempo", async () => {
  const pausas: number[] = [];
  await repescar(
    [{ id: "a" }, { id: "b" }, { id: "c" }],
    async (id) => ({ ok: id !== "b" }),
    async (ms) => { pausas.push(ms); },
  );
  // Sucesso, falha, sucesso → a do meio tem que ser a longa.
  assertEquals(pausas.length, 3);
  assert(pausas[1] > pausas[0], "a espera após falha precisa ser maior que a pausa normal");
  assert(pausas[1] >= 15000);
});
