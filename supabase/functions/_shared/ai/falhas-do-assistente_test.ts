// A conta das falhas do assistente (Retorno rápido, F0a-2). O que se protege: uma linha por hora no
// log (o que torna `occurrences` uma contagem), a virada da hora, e a leitura que falha não vira "zero".
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ClaudeApiError } from "./anthropic.ts";
import { classeDoErro } from "./classe-do-erro.ts";
import {
  contextoDaHora,
  contextoDaRotina,
  contextosDaUltimaHora,
  falhasDeRotinaDesde,
  falhasNaUltimaHora,
  PADRAO_DO_CONTEXTO_DE_ROTINA,
  registrarFalhaDeRotina,
  registrarFalhaDoAssistente,
  ROTULO_DA_ROTINA,
  rotinaDoContexto,
  somaDeFalhas,
  somaPorRotina,
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
    select: (c?: string) => { filtros.select = c; return consulta; },
    like: (c: string, v: unknown) => { filtros[`like:${c}`] = v; return consulta; },
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

// ─── Rotina de IA que falha calada (pacote 1, V2, 24/11/2026) ─────────────────────────────────────────
// O que se protege: uma linha por rotina e por DIA DE BRASÍLIA (o que torna `occurrences` a contagem do
// dia), o registro que nunca derruba quem chamou, e a leitura que falha não vira "nenhuma falha".

Deno.test("contextoDaRotina: uma linha por rotina e dia, no dia de Brasília", () => {
  // 23h30 de 24/11 em Brasília (já 25/11 em UTC): ainda é o dia 24
  assertEquals(contextoDaRotina("triagem_email", new Date("2026-11-25T02:30:00.000Z")), "rotina-ia:triagem_email@2026-11-24");
  // 00h30 UTC de 25/11 = 21h30 de 24/11 em Brasília
  assertEquals(contextoDaRotina("triagem_email", new Date("2026-11-25T00:30:00.000Z")), "rotina-ia:triagem_email@2026-11-24");
  // a virada é à meia-noite de Brasília (03:00 UTC)
  assertEquals(contextoDaRotina("triagem_email", new Date("2026-11-25T03:00:00.000Z")), "rotina-ia:triagem_email@2026-11-25");
  assertEquals(contextoDaRotina("casar_fornecedor", new Date("2026-11-24T15:00:00.000Z")), "rotina-ia:casar_fornecedor@2026-11-24");
});

Deno.test("registrarFalhaDeRotina: grava o contexto do dia, a rotina como ação e a classe do erro", async () => {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      return Promise.resolve({ error: null });
    },
  };
  const agora = new Date("2026-11-24T13:00:00.000Z");
  await registrarFalhaDeRotina(admin, { rotina: "triagem_email", mensagem: classeDoErro(new ClaudeApiError(402, "OpenRouter 402 (créditos insuficientes na conta): {}")), agora });
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].fn, "log_app_error");
  assertEquals(chamadas[0].args.p_source, "edge");
  assertEquals(chamadas[0].args.p_context, "rotina-ia:triagem_email@2026-11-24");
  assertEquals(chamadas[0].args.p_action, "triagem_email");
  assertEquals(chamadas[0].args.p_level, "error");
  assertEquals(chamadas[0].args.p_message, "HTTP 402 (sem crédito)");
  assertEquals(chamadas[0].args.p_details, {});
  // a falha sem texto ainda conta (logEdgeError descartaria a mensagem vazia)
  await registrarFalhaDeRotina(admin, { rotina: "casar_fornecedor", mensagem: "  ", agora });
  assertEquals(chamadas.length, 2);
  assertEquals(chamadas[1].args.p_context, "rotina-ia:casar_fornecedor@2026-11-24");
  assertEquals(chamadas[1].args.p_message, "falha sem mensagem de erro");
});

// (Acabamento da leva A do pacote 1, 24/11/2026) O registro gravava o texto cru do erro, e o erro do provedor pode
// devolver um trecho do e-mail ou da mensagem enviada para ler. O que se protege aqui, no último passo antes do banco:
// mesmo que uma rotina passe o texto cru por engano, o que é gravado é uma frase da lista fechada.
Deno.test("registrarFalhaDeRotina: texto cru de erro não é gravado: vira 'erro não classificado', e nada dele vai para o log", async () => {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const admin = { rpc: (fn: string, args: Record<string, unknown>) => { chamadas.push({ fn, args }); return Promise.resolve({ error: null }); } };
  const agora = new Date("2026-11-24T13:00:00.000Z");
  const deFora = 'De: Maria Segredo <maria.segredo@cliente-inventado.com.br> Assunto: Proposta do veleiro Albatroz. A senha do portão é 4471.';
  const erro = new ClaudeApiError(403, `OpenRouter 403: {"error":{"code":403,"metadata":{"flagged_input":${JSON.stringify(deFora)}}}}`);
  const crus: unknown[] = [
    String(erro), String(erro).slice(0, 300), erro.message, deFora, `HTTP 403 (recusado pelo provedor) ${deFora}`,
    // quem errar o tipo e passar o erro em si, ou um objeto, também não grava o texto
    erro, { message: deFora }, [deFora],
  ];
  for (const cru of crus) {
    // deno-lint-ignore no-explicit-any
    await registrarFalhaDeRotina(admin, { rotina: "triagem_email", mensagem: cru as any, agora });
  }
  assertEquals(chamadas.length, crus.length);
  assertEquals(chamadas.map((c) => c.args.p_message), [
    "erro não classificado", "erro não classificado", "erro não classificado", "erro não classificado", "erro não classificado",
    "falha sem mensagem de erro", "falha sem mensagem de erro", "falha sem mensagem de erro",
  ]);
  const tudo = JSON.stringify(chamadas);
  for (const trecho of ["Maria", "Segredo", "maria.segredo", "cliente-inventado", "Albatroz", "4471", "senha", "flagged_input", "OpenRouter"]) {
    assert(!tudo.includes(trecho), `"${trecho}" foi para o registro`);
  }
  // E não há por onde mandar a pilha do erro (que começa pela mensagem): um `erro` passado junto é ignorado.
  // deno-lint-ignore no-explicit-any
  await registrarFalhaDeRotina(admin, { rotina: "triagem_email", mensagem: "HTTP 403 (recusado pelo provedor)", erro, agora } as any);
  const ultimo = chamadas.at(-1)!.args;
  assertEquals([ultimo.p_message, ultimo.p_details], ["HTTP 403 (recusado pelo provedor)", {}]);
  assert(!JSON.stringify(ultimo).includes("Albatroz"));
});

Deno.test("registrarFalhaDeRotina: o banco fora do ar não derruba a rotina", async () => {
  const admin = { rpc: () => Promise.reject(new Error("sem banco")) };
  await registrarFalhaDeRotina(admin, { rotina: "triagem_email", mensagem: "x" });
});

Deno.test("rotinaDoContexto: só as rotinas conhecidas, no formato do registro", () => {
  assertEquals(rotinaDoContexto("rotina-ia:triagem_email@2026-11-24"), "triagem_email");
  assertEquals(rotinaDoContexto("rotina-ia:followup@2026-11-24"), "followup");
  for (const fora of ["rotina-ia:outra_coisa@2026-11-24", "rotina-ia:triagem_email", "ai-agent@2026-11-05T16", "rotina-ia:constructor@2026-11-24", "", null, undefined]) {
    assertEquals(rotinaDoContexto(fora), null, String(fora));
  }
  // o padrão do LIKE casa o que o registro grava
  assertEquals(PADRAO_DO_CONTEXTO_DE_ROTINA, "rotina-ia:%");
  assertEquals(contextoDaRotina("triagem_email", AGORA).startsWith(PADRAO_DO_CONTEXTO_DE_ROTINA.slice(0, -1)), true);
  // toda rotina tem o nome que o dono lê
  assertEquals(ROTULO_DA_ROTINA.triagem_email, "triagem de e-mail");
  assertEquals(ROTULO_DA_ROTINA.casar_fornecedor, "leitura do prazo do fornecedor");
});

Deno.test("somaPorRotina: soma os dias e os textos de erro da mesma rotina; contexto desconhecido não entra", () => {
  assertEquals(somaPorRotina([
    { context: "rotina-ia:casar_fornecedor@2026-11-24", occurrences: 1 },
    { context: "rotina-ia:triagem_email@2026-11-23", occurrences: 8 },
    { context: "rotina-ia:triagem_email@2026-11-24", occurrences: 3 },
    { context: "rotina-ia:triagem_email@2026-11-24", occurrences: 1 }, // outro texto de erro no mesmo dia
    { context: "rotina-ia:nao_existe@2026-11-24", occurrences: 50 },
    { context: "email-imap", occurrences: 4 },
    { context: null, occurrences: 2 },
    { context: "rotina-ia:followup@2026-11-24", occurrences: null },
  ]), [{ rotina: "triagem_email", vezes: 12 }, { rotina: "casar_fornecedor", vezes: 1 }]);
  assertEquals(somaPorRotina([]), []);
  assertEquals(somaPorRotina(null), []);
});

Deno.test("falhasDeRotinaDesde: lê só o erro aberto das rotinas, visto desde a hora pedida", async () => {
  const desde = new Date("2026-11-23T10:30:00.000Z"); // 07:30 de 23/11 em Brasília
  const { admin, filtros } = bancoDoLog({
    data: [{ context: "rotina-ia:triagem_email@2026-11-23", occurrences: 9 }, { context: "rotina-ia:triagem_email@2026-11-24", occurrences: 3 }],
    error: null,
  });
  assertEquals(await falhasDeRotinaDesde(admin, desde), [{ rotina: "triagem_email", vezes: 12 }]);
  assertEquals(filtros.select, "context, occurrences");
  assertEquals(filtros["like:context"], "rotina-ia:%");
  assertEquals(filtros["eq:level"], "error");
  assertEquals(filtros["is:resolved_at"], null);
  assertEquals(filtros["gte:last_seen_at"], "2026-11-23T10:30:00.000Z");
  assertEquals(await falhasDeRotinaDesde(bancoDoLog({ data: [], error: null }).admin, desde), []);
});

Deno.test("falhasDeRotinaDesde: leitura que falha é null, nunca 'nenhuma falha'", async () => {
  const desde = new Date("2026-11-23T10:30:00.000Z");
  assertEquals(await falhasDeRotinaDesde(bancoDoLog({ data: null, error: { message: "x" } }).admin, desde), null);
  assertEquals(await falhasDeRotinaDesde(bancoDoLog("lanca").admin, desde), null);
});
