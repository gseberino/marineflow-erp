// A conta das falhas do assistente (Retorno rápido, F0a-2). O que se protege: uma linha por hora no
// log (o que torna `occurrences` uma contagem), a virada da hora, e a leitura que falha não vira "zero".
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  contextoDaHora,
  contextosDaUltimaHora,
  falhasNaUltimaHora,
  registrarFalhaDoAssistente,
  somaDeFalhas,
} from "./falhas-do-assistente.ts";

const AGORA = new Date("2026-11-05T16:20:00.000Z");

Deno.test("contextoDaHora: uma linha por hora, em UTC", () => {
  assertEquals(contextoDaHora(AGORA), "ai-agent@2026-11-05T16");
  assertEquals(contextoDaHora(new Date("2026-11-05T16:59:59.999Z")), "ai-agent@2026-11-05T16");
  assertEquals(contextoDaHora(new Date("2026-11-05T17:00:00.000Z")), "ai-agent@2026-11-05T17");
});

Deno.test("contextosDaUltimaHora: a corrente e a anterior, mesmo na virada do dia", () => {
  assertEquals(contextosDaUltimaHora(AGORA), ["ai-agent@2026-11-05T16", "ai-agent@2026-11-05T15"]);
  assertEquals(contextosDaUltimaHora(new Date("2026-11-06T00:10:00.000Z")), ["ai-agent@2026-11-06T00", "ai-agent@2026-11-05T23"]);
});

Deno.test("registrarFalhaDoAssistente: grava com o contexto da hora e o lugar da falha", async () => {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      return Promise.resolve({ error: null });
    },
  };
  await registrarFalhaDoAssistente(admin, { onde: "turno_whatsapp", mensagem: "sem resposta", agora: AGORA });
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].fn, "log_app_error");
  assertEquals(chamadas[0].args.p_context, "ai-agent@2026-11-05T16");
  assertEquals(chamadas[0].args.p_action, "turno_whatsapp");
  assertEquals(chamadas[0].args.p_level, "error");
});

Deno.test("registrarFalhaDoAssistente: o banco fora do ar não derruba quem chamou", async () => {
  const admin = { rpc: () => Promise.reject(new Error("sem banco")) };
  await registrarFalhaDoAssistente(admin, { onde: "handler", mensagem: "x", agora: AGORA });
});

Deno.test("somaDeFalhas: soma as ocorrências e aceita vazio", () => {
  assertEquals(somaDeFalhas([{ occurrences: 2 }, { occurrences: 1 }]), 3);
  assertEquals(somaDeFalhas([{ occurrences: null }, {}]), 0);
  assertEquals(somaDeFalhas([]), 0);
  assertEquals(somaDeFalhas(null), 0);
});

function bancoDoLog(resposta: { data?: unknown; error?: unknown } | "lanca") {
  const filtros: Record<string, unknown> = {};
  const consulta = {
    select: () => consulta,
    in: (c: string, v: unknown) => { filtros[`in:${c}`] = v; return consulta; },
    eq: (c: string, v: unknown) => { filtros[`eq:${c}`] = v; return consulta; },
    is: (c: string, v: unknown) => { filtros[`is:${c}`] = v; return consulta; },
    gte: (c: string, v: unknown) => {
      filtros[`gte:${c}`] = v;
      if (resposta === "lanca") throw new Error("sem banco");
      return Promise.resolve(resposta);
    },
  };
  return { admin: { from: () => consulta }, filtros };
}

Deno.test("falhasNaUltimaHora: soma só o erro aberto das duas horas, visto na última hora", async () => {
  const { admin, filtros } = bancoDoLog({ data: [{ occurrences: 2 }, { occurrences: 2 }], error: null });
  assertEquals(await falhasNaUltimaHora(admin, AGORA), 4);
  assertEquals(filtros["in:context"], ["ai-agent@2026-11-05T16", "ai-agent@2026-11-05T15"]);
  assertEquals(filtros["eq:level"], "error");
  assertEquals(filtros["is:resolved_at"], null);
  assertEquals(filtros["gte:last_seen_at"], "2026-11-05T15:20:00.000Z");
});

Deno.test("falhasNaUltimaHora: sem linha nenhuma é zero", async () => {
  assertEquals(await falhasNaUltimaHora(bancoDoLog({ data: [], error: null }).admin, AGORA), 0);
});

Deno.test("falhasNaUltimaHora: leitura que falha é null, nunca zero", async () => {
  assertEquals(await falhasNaUltimaHora(bancoDoLog({ data: null, error: { message: "x" } }).admin, AGORA), null);
  assertEquals(await falhasNaUltimaHora(bancoDoLog("lanca").admin, AGORA), null);
});
