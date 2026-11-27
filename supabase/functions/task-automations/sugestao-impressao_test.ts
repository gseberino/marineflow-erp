// A sugestão de imprimir as vias de amanhã na hora da ficha da véspera (20/11/2026): quando vai, quando não vai, o texto e a
// chave. O pedido que ela sugere ("imprime as vias de amanhã") é provado em _shared/ai/atalho-impressao_test.ts.
// (27/11/2026) A hora é a de agenda_config.equipe_hora_ficha; sem conseguir ler, vale 19:30 (os testes de cima usam essa reserva).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CHAVE_DO_INTERRUPTOR,
  janelaDaSugestao,
  linhaDaSugestao,
  minutosDaHora,
  ORIGEM_DA_SUGESTAO,
  type PecasDaSugestao,
  sugerirImpressaoDaVespera,
  textoDaSugestaoDaVespera,
} from "./sugestao-impressao.ts";
import { lerPedidoDeImpressao } from "../_shared/ai/atalho-pdf.ts";
import { diaSeguinte } from "../_shared/impressao/agenda.ts";

// qui 19/11/2026 19:30 em Brasília = 22:30 UTC
const AS_1930 = new Date("2026-11-19T22:30:05Z");

function pecas(over: Partial<PecasDaSugestao> = {}, fila: Array<Record<string, unknown>> = [], dias: string[] = []): PecasDaSugestao {
  return {
    // null = a hora da ficha não pôde ser lida: vale a reserva, 19:30
    horaDaFicha: async () => null,
    desligada: async () => false,
    impressoraNoAr: async () => true,
    osDoDia: async (_db, dia) => {
      dias.push(dia);
      return dia === "2026-11-20" ? ["os129", "os135"] : [];
    },
    dono: async () => ({ id: "u1", phone: "5547999990000" }),
    enfileirar: async (_db, linha) => {
      if (fila.some((l) => l.dedupe_key === linha.dedupe_key)) return "ja_foi";
      fila.push(linha);
      return "ok";
    },
    ...over,
  };
}

Deno.test("o texto: singular, plural, e nada sem via; o comando sugerido é o que o atalho lê", () => {
  assertEquals(textoDaSugestaoDaVespera(1), "🖨️ Quer imprimir a via de amanhã? Responda: *imprime as vias de amanhã*");
  assertEquals(textoDaSugestaoDaVespera(3), "🖨️ Quer imprimir as 3 vias de amanhã? Responda: *imprime as vias de amanhã*");
  assertEquals(textoDaSugestaoDaVespera(0), null);
  assertEquals(lerPedidoDeImpressao("imprime as vias de amanhã"), { documento: "amanha", via: "tecnico", destino: "impressora" });
});

Deno.test("às 19:30 com vias amanhã: uma linha ao dono, com o N, a chave da véspera e tentativas só até as 20h", async () => {
  const fila: Array<Record<string, unknown>> = [];
  const dias: string[] = [];
  const r = await sugerirImpressaoDaVespera({}, AS_1930, pecas({}, fila, dias));
  assertEquals(r, { enviada: 2 });
  assertEquals(dias, ["2026-11-20"]);
  assertEquals(fila.length, 1);
  assertEquals(fila[0].phone_normalized, "5547999990000");
  assertEquals(fila[0].message, "🖨️ Quer imprimir as 2 vias de amanhã? Responda: *imprime as vias de amanhã*");
  assertEquals(fila[0].source, ORIGEM_DA_SUGESTAO);
  assertEquals(fila[0].dedupe_key, "impressao_sugestao:2026-11-20");
  // 19:30 → 20:00: a 1ª na próxima volta e as outras de 10 em 10 min (3)
  assertEquals(fila[0].max_attempts, 3);
});

Deno.test("o tique seguinte (19:45) não repete: a chave da véspera já está na fila", async () => {
  const fila: Array<Record<string, unknown>> = [];
  await sugerirImpressaoDaVespera({}, AS_1930, pecas({}, fila));
  const r = await sugerirImpressaoDaVespera({}, new Date("2026-11-19T22:45:05Z"), pecas({}, fila));
  assertEquals(r, { pulou: "ja_foi" });
  assertEquals(fila.length, 1);
});

Deno.test("fora das 19:30–20:00 de Brasília nada é lido nem mandado (o dia é o de Brasília, não o de UTC)", async () => {
  let leu = false;
  const p = pecas({ osDoDia: async () => { leu = true; return ["os1"]; } });
  for (const t of ["2026-11-19T22:29:59Z", "2026-11-19T23:00:00Z", "2026-11-19T10:30:00Z", "2026-11-20T01:30:00Z"]) {
    assertEquals(await sugerirImpressaoDaVespera({}, new Date(t), p), { pulou: "fora_da_hora" }, t);
  }
  assertEquals(leu, false);
});

Deno.test("sem vias, interruptor 'off', impressora fora ou sem dono: não manda", async () => {
  const fila: Array<Record<string, unknown>> = [];
  assertEquals(await sugerirImpressaoDaVespera({}, AS_1930, pecas({ osDoDia: async () => [] }, fila)), { pulou: "sem_vias" });
  assertEquals(await sugerirImpressaoDaVespera({}, AS_1930, pecas({ desligada: async () => true }, fila)), { pulou: "desligada" });
  assertEquals(await sugerirImpressaoDaVespera({}, AS_1930, pecas({ impressoraNoAr: async () => false }, fila)), { pulou: "impressora" });
  assertEquals(await sugerirImpressaoDaVespera({}, AS_1930, pecas({ dono: async () => null }, fila)), { pulou: "sem_dono" });
  assertEquals(fila.length, 0);
});

Deno.test("erro de leitura não lança: vira { erro } e uma linha em app_error_logs", async () => {
  const logs: unknown[] = [];
  const db = { rpc: (f: string, v: unknown) => { if (f === "log_app_error") logs.push(v); return Promise.resolve({ error: null }); } };
  const r = await sugerirImpressaoDaVespera(db, AS_1930, pecas({ osDoDia: async () => { throw new Error("não consegui ler a agenda (x)"); } }));
  assertEquals(r, { erro: "não consegui ler a agenda (x)" });
  assertEquals(logs.length, 1);
});

Deno.test("o interruptor e as peças: a chave lida é a da véspera; o dia seguinte vira mês e ano", () => {
  assertEquals(CHAVE_DO_INTERRUPTOR, "impressao_sugestao_vespera");
  assertEquals(diaSeguinte("2026-11-30"), "2026-12-01");
  assertEquals(diaSeguinte("2026-12-31"), "2027-01-01");
  assertEquals(diaSeguinte("2028-02-28"), "2028-02-29");
  assertEquals(linhaDaSugestao({ phone: "1", texto: "t", amanha: "2026-12-01", agora: AS_1930 }).dedupe_key, "impressao_sugestao:2026-12-01");
});

// ── (27/11/2026) a hora segue a ficha (agenda_config.equipe_hora_ficha) ──────────────────────────────────────────────────────

Deno.test("a hora lida e a janela: do tique da ficha ao seguinte, nunca depois das 20h; sem hora, 19:30", () => {
  assertEquals(minutosDaHora("17:45:00"), 17 * 60 + 45);
  assertEquals(minutosDaHora("19:30"), 19 * 60 + 30);
  assertEquals(minutosDaHora(" 07:30:00 "), 7 * 60 + 30);
  for (const lixo of [null, undefined, "", "abc", "25:00:00", "10:75:00", 1745]) assertEquals(minutosDaHora(lixo), null, String(lixo));
  assertEquals(janelaDaSugestao(17 * 60 + 45), { de: 17 * 60 + 45, ate: 18 * 60 + 15 });
  assertEquals(janelaDaSugestao(null), { de: 19 * 60 + 30, ate: 20 * 60 });
  // ficha às 19:45: só o tique dela cabe antes das 20h; às 20:00 ou depois, janela vazia (nada à noite)
  assertEquals(janelaDaSugestao(19 * 60 + 45), { de: 19 * 60 + 45, ate: 20 * 60 });
  assertEquals(janelaDaSugestao(20 * 60).de >= janelaDaSugestao(20 * 60).ate, true);
});

Deno.test("com a ficha às 17:45: sugere no tique das 17:45, não repete às 18:00, e não sugere às 17:30, 18:15 nem 19:30", async () => {
  // qui 19/11/2026: 17:45 em Brasília = 20:45 UTC
  const hora = { horaDaFicha: async () => 17 * 60 + 45 };
  const fila: Array<Record<string, unknown>> = [];
  const dias: string[] = [];
  assertEquals(await sugerirImpressaoDaVespera({}, new Date("2026-11-19T20:30:05Z"), pecas(hora, fila, dias)), { pulou: "fora_da_hora" });
  assertEquals(dias, []);
  assertEquals(await sugerirImpressaoDaVespera({}, new Date("2026-11-19T20:45:05Z"), pecas(hora, fila, dias)), { enviada: 2 });
  assertEquals(dias, ["2026-11-20"]);
  assertEquals(fila.length, 1);
  assertEquals(fila[0].dedupe_key, "impressao_sugestao:2026-11-20");
  // 17:45 → 20:00: a 1ª na próxima volta e as outras de 10 em 10 min
  assertEquals(fila[0].max_attempts, 13);
  assertEquals(await sugerirImpressaoDaVespera({}, new Date("2026-11-19T21:00:05Z"), pecas(hora, fila, dias)), { pulou: "ja_foi" });
  assertEquals(await sugerirImpressaoDaVespera({}, new Date("2026-11-19T21:15:05Z"), pecas(hora, fila, dias)), { pulou: "fora_da_hora" });
  assertEquals(await sugerirImpressaoDaVespera({}, AS_1930, pecas(hora, fila, dias)), { pulou: "fora_da_hora" });
  assertEquals(fila.length, 1);
});

Deno.test("de madrugada e à noite nem a hora da ficha é lida; no resto do dia só ela", async () => {
  let leuHora = 0, leuResto = 0;
  const p = pecas({
    horaDaFicha: async () => { leuHora++; return 17 * 60 + 45; },
    desligada: async () => { leuResto++; return false; },
  });
  // 05:59 e 20:00 de Brasília (08:59 e 23:00 UTC); 22:30 de Brasília (01:30 UTC do dia seguinte)
  for (const t of ["2026-11-19T08:59:59Z", "2026-11-19T23:00:00Z", "2026-11-20T01:30:00Z"]) {
    assertEquals(await sugerirImpressaoDaVespera({}, new Date(t), p), { pulou: "fora_da_hora" }, t);
  }
  assertEquals(leuHora, 0);
  // 10:00 de Brasília: lê a hora, vê que não é a dela e para
  assertEquals(await sugerirImpressaoDaVespera({}, new Date("2026-11-19T13:00:00Z"), p), { pulou: "fora_da_hora" });
  assertEquals([leuHora, leuResto], [1, 0]);
});

Deno.test("a hora da ficha que não pôde ser lida não derruba a sugestão: sai às 19:30; erro lançado vira { erro }", async () => {
  const fila: Array<Record<string, unknown>> = [];
  assertEquals(await sugerirImpressaoDaVespera({}, AS_1930, pecas({ horaDaFicha: async () => null }, fila)), { enviada: 2 });
  const logs: unknown[] = [];
  const db = { rpc: (f: string, v: unknown) => { if (f === "log_app_error") logs.push(v); return Promise.resolve({ error: null }); } };
  const r = await sugerirImpressaoDaVespera(db, AS_1930, pecas({ horaDaFicha: async () => { throw new Error("agenda_config fora do ar"); } }));
  assertEquals(r, { erro: "agenda_config fora do ar" });
  assertEquals(logs.length, 1);
});
