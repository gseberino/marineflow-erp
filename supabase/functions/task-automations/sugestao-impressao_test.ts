// A sugestão de imprimir as vias de amanhã na hora da ficha das 19:30 (20/11/2026): quando vai, quando não vai, o texto e a
// chave. O pedido que ela sugere ("imprime as vias de amanhã") é provado em _shared/ai/atalho-impressao_test.ts.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CHAVE_DO_INTERRUPTOR,
  linhaDaSugestao,
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
