// O cartão do retorno (F2, P8.6): a ferramenta da pendência, com banco falso. Frases e telefones inventados.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type EnviarDitado,
  executarCartao,
  NOME_DA_TOOL_DO_CARTAO,
  omitirResultadosDoRetorno,
  resumirRespostaDoCaso,
  responderCaso,
  retornoSoPelaPendencia,
  riscoDoEnvioLivre,
} from "./retorno.ts";
import { allTools, toolsByName } from "./index.ts";
import { textoDoSim } from "../agent.ts";
import type { ToolCtx } from "./registry.ts";

type Chamada = { fn: string; args: Record<string, unknown> };

function ctx(resposta: unknown, erro: unknown = null): { c: ToolCtx; chamadas: Chamada[] } {
  const chamadas: Chamada[] = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      if (fn === "retorno_cartao_executar") return Promise.resolve({ data: resposta, error: erro });
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  return { c: { admin, sb: admin, userId: "dono", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx, chamadas };
}

const DITADO = { item_id: "i-1", phone: "5547900009502", texto: "Pode buscar amanhã", dedupe_key: "retorno:c:ditado:h" };

Deno.test("a ferramenta fica fora da lista do modelo e dentro do mapa de execução", () => {
  assertEquals(allTools.some((t) => t.name === NOME_DA_TOOL_DO_CARTAO), false);
  assertEquals(toolsByName[NOME_DA_TOOL_DO_CARTAO]?.risk, "high");
  assertEquals(toolsByName[NOME_DA_TOOL_DO_CARTAO]?.roles, ["admin"]);
  assertEquals(Object.keys(retornoSoPelaPendencia[0].input_schema.properties as object), ["cartao_id"]);
});

Deno.test("um ditado sai pelo telefone do banco, e depois o item é fechado; telefone em args é ignorado", async () => {
  const { c, chamadas } = ctx({ ok: true, aviso: "Vai sair 1: Paulo.", ditados: [DITADO], vai_sair: 1 });
  const enviados: unknown[][] = [];
  const enviar: EnviarDitado = (...a) => {
    enviados.push(a);
    return Promise.resolve({ ok: true, messageId: "wa-1" });
  };
  const r = await executarCartao({ cartao_id: "c-1", to_phone: "5547999999999", phone: "5547999999999" }, c, enviar);
  assertEquals(enviados, [["5547900009502", "Pode buscar amanhã", "", "retorno:c:ditado:h", "dono"]]);
  assertEquals(chamadas.map((x) => x.fn), ["retorno_cartao_executar", "retorno_item_enviado"]);
  assertEquals(chamadas[1].args, { p_item: "i-1", p_ok: true, p_wa_id: "wa-1" });
  assertEquals(r, { ok: true, aviso: "Vai sair 1: Paulo.", so_texto: true });
});

Deno.test("envio que falha aparece no aviso e devolve o item", async () => {
  const { c, chamadas } = ctx({ ok: true, aviso: "Vai sair 1: Paulo.", ditados: [DITADO] });
  const r = await executarCartao({ cartao_id: "c-1" }, c, () => Promise.resolve({ error: "HTTP 500" }));
  assertEquals(r.aviso, "Vai sair 1: Paulo. Um ditado não saiu: responda pelo celular.");
  assertEquals(chamadas[1].args, { p_item: "i-1", p_ok: false, p_wa_id: null });
  const lanca = await executarCartao({ cartao_id: "c-1" }, ctx({ ok: true, ditados: [DITADO] }).c, () => Promise.reject(new Error("rede")));
  assertEquals(lanca.aviso, "Um ditado não saiu: responda pelo celular.");
});

Deno.test("sem ditado, nada é enviado; erro do banco e cartão decidido viram erro, sem envio", async () => {
  let envios = 0;
  const conta: EnviarDitado = () => {
    envios++;
    return Promise.resolve({ ok: true });
  };
  assertEquals((await executarCartao({ cartao_id: "c-1" }, ctx({ ok: true, aviso: "Vai sair 1: Rodrigo.", ditados: [] }).c, conta)).so_texto, true);
  assertEquals(await executarCartao({ cartao_id: "c-1" }, ctx(null, { code: "57014" }).c, conta), { error: "Não consegui executar o cartão agora." });
  assertEquals(await executarCartao({ cartao_id: "c-1" }, ctx({ ok: false, aviso: "Esse cartão já foi decidido." }).c, conta), { error: "Esse cartão já foi decidido." });
  assertEquals(await executarCartao({}, ctx({ ok: true }).c, conta), { error: "Não consegui executar o cartão agora." });
  assertEquals(envios, 0);
});

Deno.test("o sim do cartão não diz executado: traz só o aviso", () => {
  const t = textoDoSim("Cartão do retorno", { ok: true, aviso: "Vai sair 2: Rodrigo, Paulo.", so_texto: true });
  assertEquals(t, "Vai sair 2: Rodrigo, Paulo.");
  assert(!t.includes("executado"));
  assert(textoDoSim("Outra", { ok: true }).includes("executado"));
});

// ─── O ditado amarrado ao caso (P9.5) ─────────────────────────────────────────────────────────────────────────────────

const ABERTURA = "a-1";
const FONE = "5547900009220";
const DESTINO = { item_id: "i-1", abertura_id: ABERTURA, phone: FONE, rotulo: "Paulo", ok: true, texto: null };
const RETRATO = { abertura_id: ABERTURA, phone: FONE };

function ctxDoCaso(destino: unknown, erro: unknown = null) {
  const chamadas: Chamada[] = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      if (fn === "retorno_destino_do_item") return Promise.resolve({ data: destino, error: erro });
      if (fn === "retorno_ver_caso_para_modelo") return Promise.resolve({ data: destino, error: erro });
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  return { c: { admin, sb: admin, userId: "dono", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx, chamadas };
}

Deno.test("retorno_ler_caso: envelope de terceiro, dado mascarado, e o envio livre sobe de risco", async () => {
  const { c } = ctxDoCaso({ n: 2, rotulo: "Paulo", os: "OS-1", recebidas: [{ hora: "10:05", texto: "meu cpf é 123.456.789-09" }], fatos: {} });
  const r = await toolsByName.retorno_ler_caso.execute({ n: 2 }, c) as Record<string, any>;
  assert(r.aviso.startsWith("DADO DE TERCEIRO"));
  assertEquals(r.caso.recebidas[0].texto, "meu cpf é [dado]");
  assertEquals(c.sessaoAmarrada, true);
  assertEquals(await toolsByName.retorno_ler_caso.execute({ n: 2 }, ctxDoCaso({ erro: "Não há cartão aberto." }).c), { error: "Não há cartão aberto." });
});

Deno.test("retorno_responder_caso: sem campo de telefone; quem manda é o retrato, nunca o argumento", async () => {
  assertEquals(Object.keys(toolsByName.retorno_responder_caso.input_schema.properties as object).sort(), ["n", "texto"]);
  assertEquals(toolsByName.retorno_responder_caso.risk, "high");
  const { c, chamadas } = ctxDoCaso(DESTINO);
  const enviados: unknown[][] = [];
  const enviar: EnviarDitado = (...a) => {
    enviados.push(a);
    return Promise.resolve({ ok: true, messageId: "wa-1" });
  };
  const r = await responderCaso({ n: 2, texto: "Chega quinta", to_phone: "5547999999999", _retrato: RETRATO }, c, enviar);
  assertEquals(enviados[0][0], FONE);
  assertEquals(r, { ok: true, aviso: "Mandei a Paulo.", so_texto: true });
  assertEquals(chamadas.at(-1)?.fn, "retorno_caso_respondido");
});

Deno.test("retorno_responder_caso: sem retrato, cartão que mudou ou canal bloqueado recusam, sem envio", async () => {
  let envios = 0;
  const enviar: EnviarDitado = () => {
    envios++;
    return Promise.resolve({ ok: true });
  };
  const mudou = { error: "O cartão mudou: mande *retorno* e dite de novo." };
  assertEquals(await responderCaso({ n: 2, texto: "x" }, ctxDoCaso(DESTINO).c, enviar), mudou);
  assertEquals(await responderCaso({ n: 2, texto: "x", _retrato: RETRATO }, ctxDoCaso({ ...DESTINO, abertura_id: "a-2" }).c, enviar), mudou);
  assertEquals(await responderCaso({ n: 2, texto: "x", _retrato: RETRATO }, ctxDoCaso({ ...DESTINO, phone: "5547900009999" }).c, enviar), mudou);
  assertEquals(await responderCaso({ n: 2, texto: "x", _retrato: RETRATO }, ctxDoCaso({ erro: "Não há cartão aberto." }).c, enviar), mudou);
  const bloqueado = await responderCaso({ n: 2, texto: "x", _retrato: RETRATO }, ctxDoCaso({ ...DESTINO, ok: false, texto: "o 2 pediu para não receber mensagem automática" }).c, enviar);
  assertEquals(bloqueado, { error: "o 2 pediu para não receber mensagem automática" });
  assertEquals(envios, 0);
});

Deno.test("o resumo mostra para quem, os 4 dígitos e o texto; sem caso, recusa", async () => {
  const { c } = ctxDoCaso(DESTINO);
  assertEquals(await resumirRespostaDoCaso(c.admin, { n: 2, texto: "Chega quinta" }, "dono"), 'Para: *Paulo* (WhatsApp ••9220, o contato do caso)\nTexto: "Chega quinta"');
  assertEquals(await resumirRespostaDoCaso(ctxDoCaso({ erro: "Não há cartão aberto." }).c.admin, { n: 2 }, "dono"), "⚠️ Não há cartão aberto. Nada foi registrado.");
});

Deno.test("o resultado de retorno_ler_caso não fica na conversa, nem pela ferramenta_extra", () => {
  const linhas = [
    { role: "assistant", tool_calls: [{ id: "t1", function: { name: "retorno_ler_caso", arguments: '{"n":1}' } }] },
    { role: "tool", tool_call_id: "t1", content: "FRASE-MARCADA" },
    { role: "assistant", tool_calls: [{ id: "t2", function: { name: "ferramenta_extra", arguments: '{"nome":"retorno_ler_caso"}' } }] },
    { role: "tool", tool_call_id: "t2", content: "FRASE-MARCADA" },
    { role: "assistant", tool_calls: [{ id: "t3", function: { name: "get_service_order", arguments: "{}" } }] },
    { role: "tool", tool_call_id: "t3", content: "fica" },
  ];
  const r = omitirResultadosDoRetorno(linhas);
  assertEquals(r[1].content, '{"omitido":true}');
  assertEquals(r[3].content, '{"omitido":true}');
  assertEquals(r[5].content, "fica");
  assert(!JSON.stringify(r).includes("FRASE-MARCADA"));
});

Deno.test("com sessão amarrada, o envio livre pede PIN; sem ela, como sempre", () => {
  assertEquals(riscoDoEnvioLivre("send_whatsapp_message", "medium", true), "high");
  assertEquals(riscoDoEnvioLivre("send_whatsapp_message", "medium", false), "medium");
  assertEquals(riscoDoEnvioLivre("send_whatsapp_message", "medium", undefined), "medium");
  assertEquals(riscoDoEnvioLivre("get_service_order", "low", true), "low");
});
