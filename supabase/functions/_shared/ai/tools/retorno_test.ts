// O cartão do retorno (F2, P8.6): a ferramenta da pendência, com banco falso. Frases e telefones inventados.
import { assert, assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import {
  cadastrarUnidadeDoCaso,
  dependenciasReais,
  type DepsDoCartao,
  type EnviarDitado,
  executarCartao,
  NOME_DA_TOOL_DO_CARTAO,
  omitirResultadosDoRetorno,
  orcarCaso,
  orcarEEnviar,
  planoDaProposta,
  type PlanoDaProposta,
  resumirPropostaDoCaso,
  resumirRespostaDoCaso,
  responderCaso,
  retornoSoPelaPendencia,
  resumirUnidadeDoCaso,
  riscoDoEnvioLivre,
} from "./retorno.ts";
import { allTools, toolsByName } from "./index.ts";
import { textoDoSim } from "../agent.ts";
import { rodaDiretoPelaRede } from "../perfil-operacao.ts";
import { isAutonomyGranted } from "../autonomy-policy.ts";
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

Deno.test("ler o caso roda direto pelo perfil enxuto do admin: não pede sim no meio do ditado", () => {
  assertEquals(rodaDiretoPelaRede(toolsByName.retorno_ler_caso), true);
});

// ─── Orçamento pelo cartão (F3, P8.1) ───────────────────────────────────────────────────────────────────────────────────

/** Admin falso por rota: rotas[fn] é o data; __erro simula .error; lançar simula rede. */
function fluxo(rotas: Record<string, unknown> = {}) {
  const chamadas: Chamada[] = [];
  const admin = {
    rpc: (fn: string, args: Record<string, unknown>) => {
      chamadas.push({ fn, args });
      const v = rotas[fn];
      if (typeof v === "function") return Promise.resolve((v as (a: unknown) => unknown)(args));
      if (v && typeof v === "object" && "__erro" in (v as Record<string, unknown>)) return Promise.resolve({ data: null, error: { message: (v as { __erro: string }).__erro } });
      return Promise.resolve({ data: v === undefined ? { ok: true } : v, error: null });
    },
    from: (tabela: string) => {
      const linhas = (rotas[`tabela:${tabela}`] as Array<Record<string, unknown>> | undefined) ?? [];
      const q: Record<string, unknown> = {
        select: () => q, eq: () => q, gt: () => q, order: () => q, limit: () => q, range: () => q, in: () => q,
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: linhas, error: null }).then(ok),
      };
      return q;
    },
  };
  const c = { admin, sb: admin, userId: "dono", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx;
  return { c, chamadas, nomes: () => chamadas.map((x) => x.fn) };
}

const TEXTO_LEGENDA = "Ana, segue o orçamento das baterias. Ele vale até terça (15/12). Se tiver dúvida ou quiser ajustar algo, é só responder por aqui.";
const CONTEXTO_LEGENDA = {
  audiencia: "cliente" as const,
  datas_permitidas: ["terça (15/12)", "15/12"],
  horas_permitidas: [] as string[],
  nome_permitido: "Ana",
  nomes_de_outros: [] as string[],
  os_permitidas: [] as string[],
  textos_do_cliente: ["FRASE-MARCADA do cliente"],
  trechos_do_modelo: [", segue o orçamento ", ". Ele vale até ", ". Se tiver dúvida ou quiser ajustar algo, é só responder por aqui."],
  marcas: { tem_proposta: true, tem_topo: false, cliente_ouviu: false, conferida: false },
};
const LEGENDA = { texto: TEXTO_LEGENDA, contexto: CONTEXTO_LEGENDA, validade_data: "2026-12-15" };
const PRE_OK = {
  ok: true, acao: "orcar", previa_id: "pv-1", abertura_id: "a-1", rotulo: "Ana", chave8: "12345678", total: 8040, validade_data: "2026-12-15", numero: null,
  legenda: LEGENDA,
  args: { client_id: "c-1", vessel_id: "v-1", title: "Baterias", items: [{ product_id: "p-1", quantity: 2, unit_price: 2300, keyword: "Bateria" }], labor: [{ service_id: null, description: "Instalação", price: 3440, quantity: 1, billing_unit: "unit" }], payment_conditions: null, origem: "retorno_previa" },
};
const ORC = (extra: Record<string, unknown> = {}) => ({ item_id: "i-1", n: 1, previa_id: "pv-1", acao: "orcar" as const, service_order_id: null, numero: null, rotulo: "Ana", ...extra });

function depsFalsos(c: { chamadas: Chamada[] }, opcoes: { orcamento?: Record<string, unknown>; envio?: Record<string, unknown>; envioLanca?: boolean } = {}) {
  const montados: Array<{ args: Record<string, unknown>; opcoes: unknown }> = [];
  const enviados: Array<Record<string, unknown>> = [];
  let validadeNoEnvio: string | undefined;
  const deps: DepsDoCartao = {
    montarOrcamento: ((args: Record<string, unknown>, _ctx: ToolCtx, o: unknown) => {
      c.chamadas.push({ fn: "montar", args });
      montados.push({ args, opcoes: o });
      return Promise.resolve(opcoes.orcamento ?? { ok: true, orcamento: "ORÇ-00151", service_order_id: "os-1", total: 8040 });
    }) as DepsDoCartao["montarOrcamento"],
    enviarPdf: (args: Record<string, unknown>, ctx: ToolCtx) => {
      c.chamadas.push({ fn: "enviar_pdf", args });
      enviados.push(args);
      validadeNoEnvio = ctx.validadeDoCartao;
      if (opcoes.envioLanca) return Promise.reject(new Error("rede"));
      return Promise.resolve(opcoes.envio ?? { ok: true, destino_chave8: "87654321" });
    },
  };
  return { deps, montados, enviados, validadeNoEnvio: () => validadeNoEnvio };
}

/** Ao meio-dia em Brasília: dentro da janela de 8h às 20h. */
const MEIO_DIA = "2026-12-09T15:00:00.000Z";
const NOITE = "2026-12-09T23:00:00.000Z"; // 20h em Brasília: já fora da janela
async function comRelogio<T>(iso: string, fn: () => Promise<T>): Promise<T> {
  const t = new FakeTime(iso);
  try {
    return await fn();
  } finally {
    t.restore();
  }
}

Deno.test("executarCartao: preparar, montar, orc_criado, enviar, pdf e item_enviado, nessa ordem", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_cartao_executar: { ok: true, aviso: "", ditados: [], orcamentos: [ORC()] }, retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f);
    const r = await executarCartao({ cartao_id: "c-1" }, f.c, undefined, d.deps);
    assertEquals(f.nomes(), ["retorno_cartao_executar", "retorno_previa_preparar", "montar", "retorno_previa_orc_criado", "enviar_pdf", "retorno_previa_pdf", "retorno_item_enviado"]);
    assertEquals(f.chamadas[1].args, { p_previa: "pv-1", p_item: "i-1", p_autor: "dono", p_so: null });
    assertEquals(d.montados[0].opcoes, { origem: { valor: "retorno_previa", chave8: "12345678" } });
    assertEquals(d.enviados[0].custom_message, TEXTO_LEGENDA);
    assertEquals(d.enviados[0].formato, "pdf");
    assertEquals(d.validadeNoEnvio(), "2026-12-15");
    assertEquals(f.chamadas[5].args.p_chave, "87654321");
    assertEquals(f.chamadas[6].args, { p_item: "i-1", p_ok: true, p_wa_id: null });
    assertEquals(r, { ok: true, aviso: "Orçamento ORÇ-00151 criado e PDF enviado a Ana.", so_texto: true });
  });
});

Deno.test("pre.ok falso não chama montar, e o aviso diz quem e por quê; sem número, usa o rótulo", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const recusa = { ok: false, motivo: "caso_fechado", frase: "já não está aberto; não criei nada", rotulo: "Ana" };
    const f = fluxo({ retorno_cartao_executar: { ok: true, orcamentos: [ORC()] }, retorno_previa_preparar: recusa });
    const d = depsFalsos(f);
    const r = await executarCartao({ cartao_id: "c-1" }, f.c, undefined, d.deps);
    assertEquals(r.aviso, "o 1 já não está aberto; não criei nada");
    assertEquals(f.nomes().includes("montar"), false);
    // sem n: nunca "undefined"
    const g = fluxo({ retorno_previa_preparar: recusa });
    const dg = depsFalsos(g);
    const avisos = await orcarEEnviar(ORC({ n: null }), g.c, dg.deps);
    assertEquals(avisos, ["o caso de Ana já não está aberto; não criei nada"]);
  });
});

Deno.test("ja_existe: não chama send, avisa e marca o caiu com orc_existe", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f, { orcamento: { ja_existe: "ORÇ-00140", error: "x" } });
    const a = await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(f.nomes().includes("enviar_pdf"), false);
    assertEquals(f.chamadas.at(-1)?.fn, "retorno_previa_caiu");
    assertEquals(f.chamadas.at(-1)?.args, { p_previa: "pv-1", p_item: "i-1", p_motivo: "orc_existe" });
    assertEquals(a, ["o 1: já existe o ORÇ-00140 de hoje; não criei outro"]);
  });
});

Deno.test("so.error: não chama send, solta o item e diz que nada saiu", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f, { orcamento: { error: "Produto da proposta não existe mais." } });
    const a = await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(f.nomes().includes("enviar_pdf"), false);
    assertEquals(f.chamadas.at(-1)?.fn, "retorno_previa_soltar");
    assertEquals(f.chamadas.at(-1)?.args, { p_item: "i-1" });
    assertEquals(a, ["o 1: não consegui criar o orçamento; nada saiu"]);
  });
});

Deno.test("fora da janela não chama montar, e o item é solto; sem_enviar não passa pela janela", async () => {
  await comRelogio(NOITE, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f);
    const a = await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(f.nomes().includes("montar"), false);
    assertEquals(f.chamadas.at(-1)?.fn, "retorno_previa_soltar");
    assertEquals(a, ["o 1: fora do horário de envio; não criei nada. Mande *retorno* a partir das 8h"]);

    const g = fluxo({ retorno_previa_preparar: PRE_OK });
    const dg = depsFalsos(g);
    const b = await orcarEEnviar(ORC({ sem_enviar: true }), g.c, dg.deps);
    assertEquals(g.nomes(), ["retorno_previa_preparar", "montar", "retorno_previa_orc_criado", "retorno_previa_soltar"]);
    assertEquals(b, ["Rascunho ORÇ-00151 criado, nada foi ao cliente."]);
  });
});

Deno.test("legenda reprovada no validador não chama send, e o aviso diz que o ORÇ ficou", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: { ...PRE_OK, legenda: { ...LEGENDA, contexto: { ...CONTEXTO_LEGENDA, audiencia: "equipe" } } } });
    const d = depsFalsos(f);
    const a = await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(f.nomes().includes("enviar_pdf"), false);
    assertEquals(a, ["o 1: legenda recusada; orçamento ORÇ-00151 criado, nada saiu"]);
    assertEquals(f.chamadas.at(-1)?.fn, "retorno_previa_soltar");
  });
});

Deno.test("total divergente além de R$ 0,01 por linha não chama send e traz os dois valores", async () => {
  await comRelogio(MEIO_DIA, async () => {
    // 2 linhas (1 peça, 1 serviço): tolerância 0,02
    const preDeTresLinhas = { ...PRE_OK, args: { ...PRE_OK.args, items: [...PRE_OK.args.items, ...PRE_OK.args.items] } };
    const f = fluxo({ retorno_previa_preparar: preDeTresLinhas });
    const d = depsFalsos(f, { orcamento: { ok: true, orcamento: "ORÇ-00151", service_order_id: "os-1", total: 8040.02 } });
    await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(f.nomes().includes("enviar_pdf"), true, "0,02 em 3 linhas passa");

    const g = fluxo({ retorno_previa_preparar: preDeTresLinhas });
    const dg = depsFalsos(g, { orcamento: { ok: true, orcamento: "ORÇ-00151", service_order_id: "os-1", total: 8040.04 } });
    const a = await orcarEEnviar(ORC(), g.c, dg.deps);
    assertEquals(g.nomes().includes("enviar_pdf"), false);
    assertStringIncludes(a[0], "o 1: o ORÇ-00151 ficou com R$ 8.040,04 e a proposta dizia R$ 8.040; confira na tela. Nada foi ao cliente.");
    assertEquals(g.chamadas.at(-1)?.fn, "retorno_previa_soltar");
  });
});

Deno.test("PDF que falha: avisa, solta o item e não chama retorno_item_enviado; p_ok falso", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f, { envio: { error: "provedor fora" } });
    const a = await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(f.chamadas.find((x) => x.fn === "retorno_previa_pdf")?.args.p_ok, false);
    assertEquals(f.nomes().includes("retorno_item_enviado"), false);
    assertEquals(f.chamadas.at(-1)?.fn, "retorno_previa_soltar");
    assertEquals(a, ["o 1: orçamento ORÇ-00151 criado, mas o PDF não saiu (provedor fora); responda pelo celular"]);
  });
});

Deno.test("PDF deduplicado fecha com p_ok verdadeiro e diz que já tinha ido; aviso_validade vai ao dono", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f, { envio: { ok: true, deduplicated: true, destino_chave8: "87654321" } });
    const a = await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(f.chamadas.find((x) => x.fn === "retorno_item_enviado")?.args.p_ok, true);
    assertEquals(a, ["PDF do ORÇ-00151 já tinha ido a Ana hoje; não reenviei."]);

    const g = fluxo({ retorno_previa_preparar: PRE_OK });
    const dg = depsFalsos(g, { envio: { ok: true, destino_chave8: "1", aviso_validade: "Não consegui gravar a validade." } });
    const b = await orcarEEnviar(ORC(), g.c, dg.deps);
    assertEquals(b[1], "o 1: Não consegui gravar a validade.");
  });
});

Deno.test("ctx.validadeDoCartao fica limpa depois do envio, mesmo com exceção", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f);
    await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(f.c.validadeDoCartao, undefined);

    const g = fluxo({ retorno_previa_preparar: PRE_OK });
    const dg = depsFalsos(g, { envioLanca: true });
    await assertRejects(() => orcarEEnviar(ORC(), g.c, dg.deps));
    assertEquals(g.c.validadeDoCartao, undefined);
  });
});

Deno.test("RPC com .error não segue adiante e o próximo item roda; a falha fica no log", async () => {
  await comRelogio(MEIO_DIA, async () => {
    let n = 0;
    const f = fluxo({
      retorno_cartao_executar: { ok: true, orcamentos: [ORC(), ORC({ item_id: "i-2", n: 2 })] },
      retorno_previa_preparar: () => (++n === 1 ? { data: null, error: { message: "57014" } } : { data: PRE_OK, error: null }),
    });
    const d = depsFalsos(f);
    const r = await executarCartao({ cartao_id: "c-1" }, f.c, undefined, d.deps);
    assertEquals(d.montados.length, 1);
    assertStringIncludes(String(r.aviso), "o 1: não consegui terminar; confira na tela");
    assertStringIncludes(String(r.aviso), "Orçamento ORÇ-00151 criado");
    assertEquals(f.nomes().includes("log_app_error"), true);
  });
});

Deno.test("3 orçamentos com o tempo estourado: o 3 ficou para depois, e o item é solto", async () => {
  const t = new FakeTime(MEIO_DIA);
  try {
    const f = fluxo({ retorno_cartao_executar: { ok: true, orcamentos: [ORC(), ORC({ item_id: "i-2", n: 2 }), ORC({ item_id: "i-3", n: 3 })] }, retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f);
    const original = d.deps.montarOrcamento;
    let vez = 0;
    d.deps.montarOrcamento = ((...a: Parameters<typeof original>) => {
      if (++vez === 2) t.tick(91_000);
      return original(...a);
    }) as typeof original;
    const r = await executarCartao({ cartao_id: "c-1" }, f.c, undefined, d.deps);
    assertEquals(vez, 2);
    assertStringIncludes(String(r.aviso), "o 3 ficou para depois: *retorno*");
    assertEquals(f.chamadas.at(-1), { fn: "retorno_previa_soltar", args: { p_item: "i-3" } });
  } finally {
    t.restore();
  }
});

Deno.test("só com orçamentos, o aviso traz a frase de cada um, e nunca texto do cliente nem a data do cartão à vista", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_cartao_executar: { ok: true, orcamentos: [ORC(), ORC({ item_id: "i-2", n: 2 })] }, retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f);
    const r = await executarCartao({ cartao_id: "c-1" }, f.c, undefined, d.deps);
    assertEquals(r.aviso, "Orçamento ORÇ-00151 criado e PDF enviado a Ana. Orçamento ORÇ-00151 criado e PDF enviado a Ana.");
    assert(!String(r.aviso).includes("FRASE-MARCADA"));
  });
});

Deno.test("pdf de rascunho: acao pdf passa o p_so ao preparo, não monta, e envia o ORÇ do cartão", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const pdf = { ...PRE_OK, acao: "pdf", numero: "ORÇ-00140", args: undefined, previa_id: null };
    const f = fluxo({ retorno_previa_preparar: pdf });
    const d = depsFalsos(f);
    const a = await orcarEEnviar(ORC({ acao: "pdf", service_order_id: "os-9", numero: "ORÇ-00140", previa_id: null }), f.c, d.deps);
    assertEquals(f.chamadas[0].args.p_so, "os-9");
    assertEquals(f.nomes().includes("montar"), false);
    assertEquals(f.nomes().includes("retorno_previa_orc_criado"), false);
    assertEquals(d.enviados[0].service_order_id, "os-9");
    assertEquals(a, ["PDF do ORÇ-00140 enviado a Ana."]);
  });
});

Deno.test("contato do caso: a frase com os 4 dígitos chega ao aviso final (teste 7 da P6.3)", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const frase = "não saiu, porque o WhatsApp do cadastro (••4321) não é o número do caso: corrija o cadastro ou mande pelo celular; não criei nada";
    const f = fluxo({ retorno_cartao_executar: { ok: true, orcamentos: [ORC()] }, retorno_previa_preparar: { ok: false, motivo: "contato_diferente", frase, rotulo: "Ana" } });
    const d = depsFalsos(f);
    const r = await executarCartao({ cartao_id: "c-1" }, f.c, undefined, d.deps);
    assertStringIncludes(String(r.aviso), "o 1 não saiu, porque o WhatsApp do cadastro (••4321) não é o número do caso");
  });
});

Deno.test("sem_enviar vale só para aquela execução, nunca entra no preparo; depois dele o item é solto", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f);
    await orcarEEnviar(ORC({ sem_enviar: true }), f.c, d.deps);
    assertEquals("p_sem_enviar" in f.chamadas[0].args, false);
    assertEquals(f.chamadas.at(-1)?.fn, "retorno_previa_soltar");
    assertEquals(f.chamadas.some((x) => x.fn === "retorno_item_enviado"), false);
  });
});

Deno.test("dependenciasReais acha send_service_order_link", () => {
  const d = dependenciasReais();
  assertEquals(typeof d.enviarPdf, "function");
  assertEquals(typeof d.montarOrcamento, "function");
});

// ─── O ditado do orçamento (F3, P8.2) ───────────────────────────────────────────────────────────────────────────────────

const LINHAS_VER = [
  { linha: 1, tipo: "peca", product_id: "p-c", service_id: null, nome: "Controlador MPPT 60A", quantidade: 1, preco: 1200, fonte: "catalogo", em: null, rotulo: "preço de catálogo, sem data", estado: "ok", motivo: null },
  { linha: 2, tipo: "servico", product_id: null, service_id: "s-1", nome: "Instalação elétrica", quantidade: 1, preco: 1500, fonte: "praticado_cliente", em: "2026-08-12", rotulo: "praticado em 12/08/26", estado: "ok", motivo: null },
  { linha: 3, tipo: "peca", product_id: "p-b", service_id: null, nome: "Bateria LiFePO4 100Ah", quantidade: 2, preco: 2300, fonte: "praticado_cliente", em: "2026-08-12", rotulo: "praticado em 12/08/26", estado: "ok", motivo: null },
  { linha: 4, tipo: "peca", product_id: "p-k", service_id: null, nome: "Cabos e terminais", quantidade: 1, preco: 320, fonte: "orcado_cliente", em: "2026-08-12", rotulo: "orçado em 12/08/26 (não aprovado)", estado: "ok", motivo: null },
];
const VER = (extra: Record<string, unknown> = {}) => ({
  n: 1, rotulo: "Ana", titulo: "Troca do controlador", total: 7120, hash: "h-efetivo", linhas: LINHAS_VER, abertura_id: "a-1", phone: "5547900001234",
  client_id: "c-1", vessel_id: "v-1", unidade_nome: "Brisa", unidades: [], previa_id: "pv-1", ditado_ligado: true, cliente_generico: false, validade: "terça (15/12)", ...extra,
});
const DESTINO_OK = { item_id: "i-1", abertura_id: "a-1", phone: "5547900001234", rotulo: "Ana", ok: true, texto: null };

function rotasDoDitado(extra: Record<string, unknown> = {}) {
  return {
    retorno_previa_ver: VER(),
    retorno_destino_do_item: DESTINO_OK,
    retorno_previa_precos: (a: Record<string, unknown>) => ({
      data: (a.p_itens as Array<Record<string, unknown>>).map((i) => ({ chave: i.chave, preco: 99, fonte: "catalogo", em: null, rotulo: "preço de catálogo, sem data" })),
      error: null,
    }),
    search_products_trgm: [],
    ...extra,
  };
}

Deno.test("resumo literal do exemplo, com o título", async () => {
  const f = fluxo(rotasDoDitado());
  const r = await resumirPropostaDoCaso(f.c.admin, {
    n: 1, titulo: "Troca do controlador", condicao_pagamento: "50% de sinal",
    trocas: [{ linha: 1, preco: 1320 }, { linha: 2, preco: 1800 }],
  }, "dono");
  assertEquals(r, [
    "Proposta de *Ana* · Brisa (WhatsApp ••1234, o contato do caso) · 4 itens · R$ 8.040",
    "Título no PDF: Troca do controlador",
    "1. Controlador MPPT 60A · 1 × R$ 1.320 · você disse",
    "2. Instalação elétrica · 1 × R$ 1.800 · você disse",
    "3. Bateria LiFePO4 100Ah · 2 × R$ 2.300 · praticado em 12/08/26",
    "4. Cabos e terminais · 1 × R$ 320 · orçado em 12/08/26 (não aprovado)",
    "Vale até terça (15/12), contado do envio.",
    "Condição: 50% de sinal",
    "*sim <PIN>* cria o orçamento e manda o PDF a Ana · ou diga o que mudar",
    "*não* cancela o ditado inteiro. Para só criar, diga *cria sem mandar*.",
  ].join("\n"));
  assertEquals(f.chamadas[0].fn, "retorno_destino_do_item");
});

Deno.test("com sem_enviar, o rodapé diz que não manda e some a última linha", async () => {
  const f = fluxo(rotasDoDitado());
  const r = await resumirPropostaDoCaso(f.c.admin, { n: 1, sem_enviar: true }, "dono");
  assert(r.includes("*sim <PIN>* cria o orçamento e não manda nada"));
  assertEquals(r.includes("cancela o ditado"), false);
});

Deno.test("resumo sem título ditado não mostra a linha do título; 1 item no singular", async () => {
  const f = fluxo(rotasDoDitado({ retorno_previa_ver: VER({ linhas: [LINHAS_VER[0]] }) }));
  const r = await resumirPropostaDoCaso(f.c.admin, { n: 1 }, "dono");
  assertEquals(r.includes("Título no PDF"), false);
  assert(r.split("\n")[0].includes("· 1 item ·"));
});

Deno.test("resumo: recusa da F2 pelo destino, sem chamar o plano; n inválido não chega ao banco", async () => {
  const f = fluxo(rotasDoDitado({ retorno_destino_do_item: { ...DESTINO_OK, ok: false, texto: "o 1 pediu para não receber mensagem automática" } }));
  assertEquals(await resumirPropostaDoCaso(f.c.admin, { n: 1 }, "dono"), "⚠️ o 1 pediu para não receber mensagem automática");
  assertEquals(f.nomes(), ["retorno_destino_do_item"]);

  const g = fluxo(rotasDoDitado());
  assertEquals(await resumirPropostaDoCaso(g.c.admin, { n: "x" }, "dono"), "⚠️ Não há caso x no cartão.");
  assertEquals(g.nomes(), []);
});

Deno.test("planoDaProposta: troca de preço marca dito, remoção tira, quantidade troca", async () => {
  const f = fluxo(rotasDoDitado());
  const p = await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 1, preco: 1320, quantidade: 2 }], remover: [4] }, "dono") as PlanoDaProposta;
  assertEquals(p.linhas.length, 3);
  assertEquals(p.linhas.map((l) => l.linha), [1, 2, 3]);
  assertEquals(p.linhas[0].dito, true);
  assertEquals(p.linhas[0].fonte, "dito");
  assertEquals(p.linhas[0].em, null);
  assertEquals(p.linhas[0].preco, 1320);
  assertEquals(p.linhas[0].quantidade, 2);
  assertEquals(p.linhas[0].rotulo, "você disse");
  assertEquals(p.linhas[0].product_id, "p-c");
  assertEquals(p.linhas[1].dito, false);
  assertEquals(p.total, r2(2 * 1320 + 1500 + 2 * 2300));
  assertEquals(p.previa_id, "pv-1");
  assertEquals(p.previa_hash, "h-efetivo");
  assertEquals(p.client_id, "c-1");
  assertEquals(p.vessel_id, "v-1");
  assertEquals(p.provisorios, []);
});

Deno.test("planoDaProposta: preço zero fica provisório, com motivo preco_invalido", async () => {
  const f = fluxo(rotasDoDitado());
  const p = await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 1, preco: 0 }] }, "dono") as PlanoDaProposta;
  assertEquals(p.linhas[0].estado, "provisorio");
  assertEquals(p.linhas[0].motivo, "preco_invalido");
  assertEquals(p.linhas[0].preco, null);
  assertEquals(p.provisorios[0], { linha: 1, nome: "Controlador MPPT 60A", motivo: "preco_invalido" });
});

Deno.test("planoDaProposta: quantidade zero ou negativa recusa", async () => {
  const f = fluxo(rotasDoDitado());
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 2, quantidade: 0 }] }, "dono"), { recusa: "⚠️ Quantidade inválida na linha 2." });
});

Deno.test("planoDaProposta: linha nova sem nome recusa, peça ou serviço", async () => {
  const f = fluxo(rotasDoDitado());
  const frase = { recusa: "⚠️ Uma linha nova veio sem nome: diga o que é." };
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, novas: [{ nome: "   ", preco: 10 }] }, "dono"), frase);
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, mao_de_obra: [{ nome: "" }] }, "dono"), frase);
});

Deno.test("planoDaProposta: linha que não existe recusa; remover todas recusa com sem nenhum item", async () => {
  const f = fluxo(rotasDoDitado());
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 9, preco: 10 }] }, "dono"), { recusa: "⚠️ A proposta não tem a linha 9." });
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, remover: [9] }, "dono"), { recusa: "⚠️ A proposta não tem a linha 9." });
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, remover: [1, 2, 3, 4] }, "dono"), { recusa: "⚠️ O orçamento ficaria sem nenhum item: diga o que entra." });
});

const CATALOGO_NOVO = { id: "p-novo", name: "Controlador MPPT 100A", sku: null, cost_price: 900, sale_price: 2000 };

Deno.test("troca com nome em peça: resolverItens, product_id antigo some, na mesma posição; o preço antigo nunca aparece", async () => {
  const f = fluxo(rotasDoDitado({ search_products_trgm: [CATALOGO_NOVO] }));
  const p = await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 1, nome: "Controlador MPPT 100A" }] }, "dono") as PlanoDaProposta;
  assertEquals(p.linhas[0].product_id, "p-novo");
  assertEquals(p.linhas[0].nome, "Controlador MPPT 100A");
  assertEquals(p.linhas[0].preco, 99);
  assertEquals(p.linhas[0].fonte, "catalogo");
  assertEquals(p.linhas[0].dito, false);
  assert(!JSON.stringify(p.linhas[0]).includes("p-c"));
  // resolverItens não recebeu unit_price: só identifica o produto
  assertEquals(f.chamadas.filter((x) => x.fn === "retorno_previa_precos").length, 1);
});

Deno.test("nome igual ao atual, com acento e maiúscula diferentes, não vira troca", async () => {
  const f = fluxo(rotasDoDitado());
  const p = await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 2, nome: "INSTALACAO ELETRICA", preco: 1800 }] }, "dono") as PlanoDaProposta;
  assertEquals(p.linhas[1].service_id, "s-1");
  assertEquals(p.linhas[1].dito, true);
  assertEquals(f.nomes().includes("search_products_trgm"), false);
});

Deno.test("assumido traz nome_pedido e 'você disse' no resumo; provisório com preço dito fica sem_catalogo; sem preço dito recusa", async () => {
  const parcial = { id: "p-x", name: "Controlador MPPT 60A Blue", sku: null, cost_price: 1, sale_price: 2 };
  const f = fluxo(rotasDoDitado({ search_products_trgm: [parcial] }));
  const assumido = await planoDaProposta(f.c.admin, { n: 1, novas: [{ nome: "controlador 60A marca nova", preco: 1320 }] }, "dono") as PlanoDaProposta;
  const nova = assumido.linhas.at(-1)!;
  assertEquals(nova.estado, "assumido");
  assertEquals(nova.nome_pedido, "controlador 60A marca nova");
  assertEquals(nova.nome, "Controlador MPPT 60A Blue");
  const resumo = await resumirPropostaDoCaso(f.c.admin, { n: 1, novas: [{ nome: "controlador 60A marca nova", preco: 1320 }] }, "dono");
  assertStringIncludes(resumo, '5. Controlador MPPT 60A Blue (você disse "controlador 60A marca nova", confira) · 1 × R$ 1.320 · você disse');

  const g = fluxo(rotasDoDitado());
  const semCatalogo = await planoDaProposta(g.c.admin, { n: 1, novas: [{ nome: "Cabo especial 35 mm", preco: 320 }] }, "dono") as PlanoDaProposta;
  assertEquals(semCatalogo.linhas.at(-1)!.estado, "assumido");
  assertEquals(semCatalogo.linhas.at(-1)!.motivo, "sem_catalogo");
  assertStringIncludes(await resumirPropostaDoCaso(g.c.admin, { n: 1, novas: [{ nome: "Cabo especial 35 mm", preco: 320 }] }, "dono"), "5. Cabo especial 35 mm (não está no catálogo: entra como produto pendente) · 1 × R$ 320 · você disse");

  const h = fluxo(rotasDoDitado());
  const semPreco = await planoDaProposta(h.c.admin, { n: 1, novas: [{ nome: "Cabo especial 35 mm" }] }, "dono") as PlanoDaProposta;
  assertEquals(semPreco.provisorios[0].motivo, "sem_preco");
  assertEquals(await resumirPropostaDoCaso(h.c.admin, { n: 1, novas: [{ nome: "Cabo especial 35 mm" }] }, "dono"), "⚠️ Falta preço em Cabo especial 35 mm: dite o valor.");
});

Deno.test("troca com nome em serviço zera o service_id, e a linha fica na mesma posição", async () => {
  const f = fluxo(rotasDoDitado({ "tabela:services": [] }));
  const p = await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 2, nome: "Instalação com içamento", preco: 2200 }] }, "dono") as PlanoDaProposta;
  assertEquals(p.linhas[1].nome, "Instalação com içamento");
  assertEquals(p.linhas[1].service_id, undefined);
  assertEquals(p.linhas[1].preco, 2200);
  assertEquals(p.linhas[1].dito, true);
});

Deno.test("Serviço a descrever com só preço continua provisório e recusa; com nome e preço, resolve", async () => {
  const descrever = { linha: 1, tipo: "servico", product_id: null, service_id: null, nome: "Serviço a descrever", quantidade: 1, preco: null, fonte: "sem_preco", em: null, rotulo: "sem preço", estado: "provisorio", motivo: "nome_com_dado_de_outro" };
  const rotas = rotasDoDitado({ retorno_previa_ver: VER({ linhas: [descrever] }), "tabela:services": [] });
  const f = fluxo(rotas);
  const p = await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 1, preco: 500 }] }, "dono") as PlanoDaProposta;
  assertEquals(p.linhas[0].estado, "provisorio");
  assertEquals(p.linhas[0].preco, null);
  assertEquals(await resumirPropostaDoCaso(f.c.admin, { n: 1, trocas: [{ linha: 1, preco: 500 }] }, "dono"), "⚠️ Falta dizer o que é o serviço da linha 1: diga o nome e o preço juntos.");

  const g = fluxo(rotas);
  const ok = await planoDaProposta(g.c.admin, { n: 1, trocas: [{ linha: 1, nome: "Revisão do motor", preco: 500 }] }, "dono") as PlanoDaProposta;
  assertEquals(ok.provisorios, []);
  assertEquals(ok.linhas[0].preco, 500);
  assertEquals(ok.linhas[0].nome, "Revisão do motor");
});

Deno.test("inativo com só preço não adianta: só troca com nome ou remover", async () => {
  const inativo = { ...LINHAS_VER[0], estado: "provisorio", motivo: "inativo", preco: null };
  const rotas = rotasDoDitado({ retorno_previa_ver: VER({ linhas: [inativo] }) });
  const f = fluxo(rotas);
  assertEquals(await resumirPropostaDoCaso(f.c.admin, { n: 1, trocas: [{ linha: 1, preco: 500 }] }, "dono"), "⚠️ Controlador MPPT 60A está fora de linha no cadastro: troque ou tire.");
});

Deno.test("linha nova sem preço chama retorno_previa_precos uma vez só; preco_venda 0 de assumido dá provisório", async () => {
  const f = fluxo(rotasDoDitado({ search_products_trgm: [CATALOGO_NOVO], "tabela:services": [] }));
  await planoDaProposta(f.c.admin, { n: 1, novas: [{ nome: "Controlador MPPT 100A" }], mao_de_obra: [{ nome: "Calibração" }] }, "dono");
  assertEquals(f.chamadas.filter((x) => x.fn === "retorno_previa_precos").length, 1);
  const itens = f.chamadas.find((x) => x.fn === "retorno_previa_precos")!.args.p_itens as Array<Record<string, unknown>>;
  assertEquals(itens.map((i) => [i.tipo, i.product_id, i.service_id, i.nome]), [["peca", "p-novo", undefined, undefined], ["servico", undefined, undefined, "Calibração"]]);

  const zero = { ...CATALOGO_NOVO, sale_price: 0, name: "Controlador MPPT 100A" };
  const g = fluxo(rotasDoDitado({
    search_products_trgm: [zero],
    retorno_previa_precos: (a: Record<string, unknown>) => ({ data: (a.p_itens as Array<Record<string, unknown>>).map((i) => ({ chave: i.chave, preco: null, fonte: "sem_preco", em: null, rotulo: "sem preço" })), error: null }),
  }));
  const p = await planoDaProposta(g.c.admin, { n: 1, novas: [{ nome: "Controlador MPPT 100A" }] }, "dono") as PlanoDaProposta;
  assertEquals(p.linhas.at(-1)!.estado, "provisorio");
  assertEquals(p.linhas.at(-1)!.motivo, "sem_preco");
  assertEquals(p.linhas.at(-1)!.preco, null);
});

Deno.test("RPC de preço com erro recusa, e orçado aparece como orçado no resumo", async () => {
  const f = fluxo(rotasDoDitado({ search_products_trgm: [CATALOGO_NOVO], retorno_previa_precos: { __erro: "falhou" } }));
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, novas: [{ nome: "Controlador MPPT 100A" }] }, "dono"), { recusa: "⚠️ Não consegui conferir os preços agora. Nada foi registrado; tente de novo." });

  const orcado = fluxo(rotasDoDitado({
    search_products_trgm: [CATALOGO_NOVO],
    retorno_previa_precos: (a: Record<string, unknown>) => ({ data: (a.p_itens as Array<Record<string, unknown>>).map((i) => ({ chave: i.chave, preco: 2000, fonte: "orcado_outro", em: "2026-08-12", rotulo: "orçado a outro cliente em 12/08/26 (não aprovado)" })), error: null }),
  }));
  const r = await resumirPropostaDoCaso(orcado.c.admin, { n: 1, novas: [{ nome: "Controlador MPPT 100A" }] }, "dono");
  assertStringIncludes(r, "orçado a outro cliente em 12/08/26 (não aprovado)");
});

Deno.test("título: com valor, documento, telefone ou acima de 120 letras recusa", async () => {
  const f = fluxo(rotasDoDitado());
  const frase = { recusa: "⚠️ O título não pode ter valor, documento ou telefone, nem passar de 120 letras: diga de outro jeito." };
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, titulo: "Troca por R$ 500" }, "dono"), frase);
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, titulo: "Cliente 123.456.789-09" }, "dono"), frase);
  assertEquals(await planoDaProposta(f.c.admin, { n: 1, titulo: "x".repeat(121) }, "dono"), frase);
  const ok = await planoDaProposta(f.c.admin, { n: 1, titulo: "Troca do controlador novo" }, "dono") as PlanoDaProposta;
  assertEquals(ok.titulo, "Troca do controlador novo");
  const semArg = await planoDaProposta(f.c.admin, { n: 1 }, "dono") as PlanoDaProposta;
  assertEquals(semArg.titulo, "Troca do controlador");
});

Deno.test("hash muda quando o plano muda, e ignora unidade_nome e validade", async () => {
  const f = fluxo(rotasDoDitado());
  const a = await planoDaProposta(f.c.admin, { n: 1 }, "dono") as PlanoDaProposta;
  const b = await planoDaProposta(f.c.admin, { n: 1, trocas: [{ linha: 1, preco: 1320 }] }, "dono") as PlanoDaProposta;
  assert(a.hash !== b.hash);
  const g = fluxo(rotasDoDitado({ retorno_previa_ver: VER({ unidade_nome: "Outra", validade: "quinta (17/12)" }) }));
  const c = await planoDaProposta(g.c.admin, { n: 1 }, "dono") as PlanoDaProposta;
  assertEquals(a.hash, c.hash);
});

Deno.test("cada frase de recusa de planoDaProposta sai em {recusa}, numa linha", async () => {
  const f = (v: unknown) => fluxo(rotasDoDitado({ retorno_previa_ver: v })).c.admin;
  assertEquals(await planoDaProposta(f({ erro: "sem_cartao" }), { n: 3 }, "dono"), { recusa: "⚠️ Não há caso 3 no cartão." });
  assertEquals(await planoDaProposta(f({ erro: "sem_caso" }), { n: 3 }, "dono"), { recusa: "⚠️ Não há caso 3 no cartão." });
  assertEquals(await planoDaProposta(f({ erro: "nao_e_o_dono" }), { n: 3 }, "dono"), { recusa: "⚠️ Só o dono pode fazer isso." });
  assertEquals(await planoDaProposta(f(VER({ ditado_ligado: false })), { n: 1 }, "dono"), { recusa: "⚠️ O ditado do orçamento está desligado." });
  assertEquals(await planoDaProposta(f(VER({ client_id: null })), { n: 1 }, "dono"), { recusa: "⚠️ Esse caso ainda não tem cadastro completo." });
  assertEquals(await planoDaProposta(f(VER({ linhas: [], previa_id: null })), { n: 1 }, "dono"), { recusa: "⚠️ O orçamento ficaria sem nenhum item: diga o que entra." });
  assertEquals(await planoDaProposta(f(VER({ linhas: [] })), { n: 1, condicao_pagamento: "x".repeat(301) }, "dono"), { recusa: "⚠️ A condição de pagamento passou de 300 letras: diga mais curto." });
});

Deno.test("unidade: 2 ou mais sem unidade recusa e lista os números; unidade 2 usa a segunda; 9 recusa; 0 unidades pede cadastrar", async () => {
  const unidades = [{ numero: 1, vessel_id: "v-1", nome: "Brisa" }, { numero: 2, vessel_id: "v-2", nome: "Netuno" }];
  const semEscolha = fluxo(rotasDoDitado({ retorno_previa_ver: VER({ unidades, vessel_id: null, unidade_nome: null }) }));
  assertEquals(await planoDaProposta(semEscolha.c.admin, { n: 1 }, "dono"), { recusa: "⚠️ Qual unidade? 1. Brisa · 2. Netuno. Mande *1 C* ou diga o número." });

  const f = fluxo(rotasDoDitado({ retorno_previa_ver: VER({ unidades, vessel_id: null, unidade_nome: null }) }));
  const r = await planoDaProposta(f.c.admin, { n: 1, unidade: 2 }, "dono") as PlanoDaProposta;
  assertEquals(r.vessel_id, "v-2");
  assertEquals(r.unidade_nome, "Netuno");
  assertStringIncludes(await resumirPropostaDoCaso(f.c.admin, { n: 1, unidade: 2 }, "dono"), "Proposta de *Ana* · Netuno (");

  const g = fluxo(rotasDoDitado({ retorno_previa_ver: VER({ unidades, vessel_id: null, unidade_nome: null }) }));
  assertEquals(await planoDaProposta(g.c.admin, { n: 1, unidade: 9 }, "dono"), { recusa: "⚠️ Esse cliente não tem a unidade 9." });

  const h = fluxo(rotasDoDitado({ retorno_previa_ver: VER({ unidades: [], vessel_id: null, unidade_nome: null }) }));
  assertEquals(await planoDaProposta(h.c.admin, { n: 7 }, "dono"), { recusa: "⚠️ Falta cadastrar a unidade: diga o nome e o tipo (cadastra a lancha Brisa no 7) ou crie no app, e dite de novo." });

  // cliente com 1 unidade ignora o campo
  const uma = fluxo(rotasDoDitado());
  const p = await planoDaProposta(uma.c.admin, { n: 1, unidade: 9 }, "dono") as PlanoDaProposta;
  assertEquals(p.vessel_id, "v-1");
});

Deno.test("as ferramentas novas: sem telefone nem cliente nos campos, e sem nome de unidade; risco e papéis", () => {
  const orcar = toolsByName.retorno_orcar_caso;
  const campos = Object.keys(orcar.input_schema.properties as object).sort();
  assertEquals(campos, ["condicao_pagamento", "mao_de_obra", "n", "novas", "remover", "sem_enviar", "titulo", "trocas", "unidade"]);
  const chaves = (o: unknown): string[] => o && typeof o === "object" ? Object.entries(o as Record<string, unknown>).flatMap(([k, v]) => k === "properties" ? Object.entries(v as Record<string, unknown>).flatMap(([p, d]) => [p, ...chaves(d)]) : chaves(v)) : [];
  assert(!chaves(orcar.input_schema).some((k) => /phone|telefone|client/i.test(k)), "campo de telefone ou de cliente");
  assertEquals(orcar.risk, "high");
  assertEquals(orcar.roles, ["admin"]);
  const unidade = toolsByName.retorno_cadastrar_unidade;
  assertEquals(Object.keys(unidade.input_schema.properties as object).sort(), ["n", "nome", "registro", "tipo"]);
  assertEquals(unidade.risk, "medium");
  assertEquals(unidade.roles, ["admin"]);
  assertEquals(toolsByName.consultar_proposta_do_caso.risk, "low");
  assertEquals(rodaDiretoPelaRede(toolsByName.consultar_proposta_do_caso), true);
  assertEquals(rodaDiretoPelaRede(orcar), false);
  assertEquals(rodaDiretoPelaRede(unidade), false);
});

Deno.test("consultar_proposta_do_caso devolve só o que o modelo pode ver, sem telefone, ids nem rótulo do cliente", async () => {
  const unidades = [{ numero: 1, vessel_id: "v-1", nome: "Brisa" }, { numero: 2, vessel_id: "v-2", nome: "Netuno" }];
  const f = fluxo(rotasDoDitado({ retorno_previa_ver: VER({ unidades }) }));
  const r = await toolsByName.consultar_proposta_do_caso.execute({ n: 1 }, f.c) as Record<string, unknown>;
  assertEquals(Object.keys(r).sort(), ["linhas", "n", "titulo", "total", "unidades"]);
  assertEquals((r.unidades as unknown[])[1], { numero: 2, nome: "Netuno" });
  assertEquals(Object.keys((r.linhas as Array<Record<string, unknown>>)[0]).sort(), ["estado", "linha", "nome", "preco", "quantidade", "rotulo", "tipo"]);
  const json = JSON.stringify(r);
  assert(!json.includes("5547900001234"));
  assert(!json.includes("v-1"));
  assert(!json.includes("p-c"));
  assert(!json.includes("Ana"));
  assert(/\.rpc\(\s*"retorno_previa_ver"/.test(String(toolsByName.consultar_proposta_do_caso.execute)));
  assertEquals(await toolsByName.consultar_proposta_do_caso.execute({ n: 1 }, fluxo({ retorno_previa_ver: { erro: "sem_caso" } }).c), { error: "Não há caso 1 no cartão." });
});

const PLANO_GUARDADO: PlanoDaProposta = {
  previa_id: "pv-1", abertura_id: "a-1", rotulo: "Ana", phone: "5547900001234", client_id: "c-1", vessel_id: "v-1", unidade_nome: "Brisa", validade: "terça (15/12)",
  titulo: "Troca", condicao: null, sem_enviar: false, total: 1320, hash: "h-plano", previa_hash: "h-efetivo", provisorios: [],
  linhas: [{ linha: 1, tipo: "peca", product_id: "p-c", nome: "Controlador", quantidade: 1, preco: 1320, fonte: "dito", em: null, rotulo: "você disse", estado: "ok", dito: true }],
};
const RETRATO_OK = { abertura_id: "a-1", phone: "5547900001234", previa_id: "pv-1", previa_hash: "h-efetivo", plano: PLANO_GUARDADO };

Deno.test("execute do ditado: sem retrato ou com a base mudada recusa, com a frase certa; desligado diz desligado", async () => {
  const f = fluxo({});
  const d = depsFalsos(f);
  assertEquals(await orcarCaso({ n: 1 }, f.c, d.deps), { error: "O cartão mudou: mande *retorno* e dite de novo." });
  assertEquals(f.nomes(), []);

  const m = fluxo({ retorno_previa_retrato: { ok: false, motivo: "mudou" } });
  assertEquals(await orcarCaso({ n: 1, _retrato: RETRATO_OK }, m.c, depsFalsos(m).deps), { error: "O cartão mudou: mande *retorno* e dite de novo." });

  const dl = fluxo({ retorno_previa_retrato: { ok: false, motivo: "desligado" } });
  assertEquals(await orcarCaso({ n: 1, _retrato: RETRATO_OK }, dl.c, depsFalsos(dl).deps), { error: "O ditado do orçamento está desligado. Nada foi criado." });

  const prov = fluxo({ retorno_previa_retrato: { ok: true, item_id: "i-1", n: 1 } });
  const plano = { ...PLANO_GUARDADO, provisorios: [{ linha: 1, nome: "Cabo", motivo: "sem_preco" }] };
  assertEquals(await orcarCaso({ n: 1, _retrato: { ...RETRATO_OK, plano } }, prov.c, depsFalsos(prov).deps), { error: "Falta completar Cabo: nada foi criado." });
});

Deno.test("execute do ditado: cartão caído não recusa, usa o plano guardado e cria e manda", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_retrato: { ok: true, item_id: null, n: null }, retorno_previa_aplicar: { previa_id: "pv-2", hash: "h2" }, retorno_previa_preparar: { ...PRE_OK, previa_id: "pv-2" } });
    const d = depsFalsos(f);
    const r = await orcarCaso({ n: 1, _retrato: RETRATO_OK }, f.c, d.deps);
    assertEquals(f.chamadas[1].fn, "retorno_previa_aplicar");
    assertEquals(f.chamadas[1].args.p_previa, "pv-1");
    assertEquals(f.chamadas[1].args.p_item, null);
    assertEquals(f.chamadas[2].args.p_previa, "pv-2");
    assertEquals(f.chamadas[2].args.p_item, null);
    assertEquals(d.montados.length, 1);
    assertEquals(d.enviados.length, 1);
    assertEquals(r.so_texto, true);
    assertStringIncludes(String(r.aviso), "PDF enviado a Ana");
  });
});

Deno.test("execute do ditado: de noite aplica o plano com p_item e não chama montar", async () => {
  await comRelogio(NOITE, async () => {
    const f = fluxo({ retorno_previa_retrato: { ok: true, item_id: "i-1", n: 1 }, retorno_previa_aplicar: { previa_id: "pv-1", hash: "h" } });
    const d = depsFalsos(f);
    const r = await orcarCaso({ n: 1, _retrato: RETRATO_OK }, f.c, d.deps);
    assertEquals(f.nomes(), ["retorno_previa_retrato", "retorno_previa_aplicar"]);
    assertEquals(f.chamadas[1].args.p_item, "i-1");
    assertEquals(r, { ok: true, aviso: "Guardei as linhas na proposta. Mande *retorno* a partir das 8h e o *sim <PIN>* cria e manda.", so_texto: true });
  });
});

Deno.test("execute do ditado com sem_enviar: cria, não manda, e passa pelo caminho de dia e de noite", async () => {
  await comRelogio(NOITE, async () => {
    const plano = { ...PLANO_GUARDADO, sem_enviar: true };
    const f = fluxo({ retorno_previa_retrato: { ok: true, item_id: "i-1", n: 1 }, retorno_previa_aplicar: { previa_id: "pv-1", hash: "h" }, retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f);
    const r = await orcarCaso({ n: 1, _retrato: { ...RETRATO_OK, plano } }, f.c, d.deps);
    assertEquals(d.enviados.length, 0);
    assertEquals(d.montados.length, 1);
    assertEquals(r.aviso, "Rascunho ORÇ-00151 criado, nada foi ao cliente.");
  });
});

Deno.test("retrato do ditado leva o plano; sem plano, null", async () => {
  const f = fluxo(rotasDoDitado());
  const r = await toolsByName.retorno_orcar_caso.retratoDaPendencia!({ n: 1 }, f.c) as Record<string, unknown>;
  assertEquals(r.abertura_id, "a-1");
  assertEquals(r.phone, "5547900001234");
  assertEquals(r.previa_id, "pv-1");
  assertEquals(r.previa_hash, "h-efetivo");
  assertEquals((r.plano as PlanoDaProposta).linhas.length, 4);
  assertEquals(await toolsByName.retorno_orcar_caso.retratoDaPendencia!({ n: 1, trocas: [{ linha: 9 }] }, fluxo(rotasDoDitado()).c), null);
});

// ─── Unidade do caso ────────────────────────────────────────────────────────────────────────────────────────────────────

const VER_SEM_UNIDADE = VER({ vessel_id: null, unidade_nome: null, unidades: [], linhas: [], previa_id: null });

Deno.test("resumo da unidade: nome, tipo, cliente e n; recusa sem cliente, Cliente Final, com unidade e com tipo fora da lista", async () => {
  const f = (v: unknown) => fluxo({ retorno_previa_ver: v }).c.admin;
  assertEquals(await resumirUnidadeDoCaso(f(VER_SEM_UNIDADE), { n: 2, nome: "Brisa", tipo: "lancha" }, "dono"), "Cadastrar *Brisa* (Lancha) para *Ana*, o caso 2 do cartão. *sim* confirma.");
  assertEquals(await resumirUnidadeDoCaso(f(VER_SEM_UNIDADE), { n: 2, nome: "Ducato", tipo: "van" }, "dono"), "Cadastrar *Ducato* (Motorhome) para *Ana*, o caso 2 do cartão. *sim* confirma.");
  assertEquals(await resumirUnidadeDoCaso(f(VER({ ...VER_SEM_UNIDADE, client_id: null })), { n: 2, nome: "Brisa", tipo: "lancha" }, "dono"), "⚠️ Esse caso ainda não tem cadastro completo.");
  assertEquals(await resumirUnidadeDoCaso(f(VER({ ...VER_SEM_UNIDADE, cliente_generico: true })), { n: 2, nome: "Brisa", tipo: "lancha" }, "dono"), "⚠️ Esse caso está no Cliente Final: crie no app.");
  assertEquals(await resumirUnidadeDoCaso(f(VER({ vessel_id: "v-1" })), { n: 2, nome: "Brisa", tipo: "lancha" }, "dono"), "⚠️ Esse cliente já tem unidade: crie outra no app.");
  assertEquals(await resumirUnidadeDoCaso(f(VER_SEM_UNIDADE), { n: 2, nome: "Brisa", tipo: "avião" }, "dono"), "⚠️ Não conheço o tipo avião: diga lancha, veleiro, motorhome ou outro da lista.");
  assertEquals(await resumirUnidadeDoCaso(f(VER_SEM_UNIDADE), { n: 2, nome: "Brisa", tipo: "" }, "dono"), "⚠️ Não conheço esse tipo: diga lancha, veleiro, motorhome ou outro da lista.");
  assertEquals(await resumirUnidadeDoCaso(f(VER({ ditado_ligado: false })), { n: 2, nome: "Brisa", tipo: "lancha" }, "dono"), "⚠️ O ditado do orçamento está desligado.");
  assertEquals(await resumirUnidadeDoCaso(f({ erro: "sem_caso" }), { n: 2, nome: "Brisa", tipo: "lancha" }, "dono"), "⚠️ Não há caso 2 no cartão.");
});

Deno.test("execute da unidade: grava o client_id do retrato, nunca de argumento; ja_cadastrada não insere; sem retrato recusa", async () => {
  const inseridas: Record<string, unknown>[] = [];
  const consulta = (linhas: Record<string, unknown>[]) => {
    const q: Record<string, unknown> = {
      select: () => q, eq: () => q, order: () => q, range: () => q,
      maybeSingle: () => Promise.resolve({ data: { previa_ditado_ligado: true }, error: null }),
      then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: linhas, error: null }).then(ok),
      insert: (l: Record<string, unknown>) => {
        inseridas.push(l);
        return { select: () => ({ single: () => Promise.resolve({ data: { id: "v-novo", ...l }, error: null }) }) };
      },
    };
    return q;
  };
  const ctxUnidade = (linhas: Record<string, unknown>[] = []) => {
    const admin = { from: () => consulta(linhas), rpc: () => Promise.resolve({ data: {}, error: null }) };
    return { admin, sb: admin, userId: "dono", userRole: "admin", jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx;
  };
  const RETRATO_UN = { abertura_id: "a-1", client_id: "c-do-caso", rotulo: "Ana" };
  const r = await cadastrarUnidadeDoCaso({ n: 2, nome: "Brisa", tipo: "lancha", client_id: "c-do-modelo", _retrato: RETRATO_UN }, ctxUnidade());
  assertEquals(inseridas[0].client_id, "c-do-caso");
  assertEquals(inseridas[0].asset_type, "Lancha");
  assertEquals(r, { ok: true, aviso: "Unidade Brisa cadastrada para Ana. Mande *retorno*.", so_texto: true });

  inseridas.length = 0;
  const repetida = [{ id: "v-1", name: "Brisa", client_id: "c-do-caso", hull_id_or_registration: null, active: true }];
  const j = await cadastrarUnidadeDoCaso({ n: 2, nome: "Brisa", tipo: "lancha", _retrato: RETRATO_UN }, ctxUnidade(repetida));
  assertEquals(inseridas, []);
  assertStringIncludes(String((j as { aviso?: string }).aviso), "Já existe unidade");

  assertEquals(await cadastrarUnidadeDoCaso({ n: 2, nome: "Brisa", tipo: "lancha" }, ctxUnidade()), { error: "O cartão mudou: mande *retorno* e dite de novo." });
});

Deno.test("retrato da unidade: abertura e cliente do caso, nunca do modelo", async () => {
  const f = fluxo({ retorno_previa_ver: VER_SEM_UNIDADE });
  assertEquals(await toolsByName.retorno_cadastrar_unidade.retratoDaPendencia!({ n: 2, client_id: "c-do-modelo" }, f.c), { abertura_id: "a-1", client_id: "c-1", rotulo: "Ana" });
});

// ─── Guardas ligadas na P8 ──────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("riscoDoEnvioLivre sobe send_whatsapp_message e create_quote_from_items só com amarra; isAutonomyGranted recusa em high", () => {
  assertEquals(riscoDoEnvioLivre("create_quote_from_items", "low", true), "high");
  assertEquals(riscoDoEnvioLivre("create_quote_from_items", "low", false), "low");
  assertEquals(riscoDoEnvioLivre("create_quote_from_items", "low", undefined), "low");
  assertEquals(isAutonomyGranted("create_quote_from_items", "high", { ai_autonomy_create_quote_from_items: "auto" }), false);
  assertEquals(isAutonomyGranted("create_quote_from_items", "low", {}), true);
  assertEquals(isAutonomyGranted("retorno_orcar_caso", "high", { ai_autonomy_retorno_orcar_caso: "auto" }), false);
  assertEquals(isAutonomyGranted("retorno_cadastrar_unidade", "medium", { ai_autonomy_retorno_cadastrar_unidade: "auto" }), false);
});

Deno.test("retorno_ler_caso: amarra sai da devolutiva e fica no contexto", async () => {
  const { c } = ctxDoCaso({ n: 2, recebidas: [], fatos: {}, amarra: { client_id: "c-1", vessel_id: "v-1" } });
  const r = await toolsByName.retorno_ler_caso.execute({ n: 2 }, c) as Record<string, any>;
  assertEquals("amarra" in r.caso, false);
  assertEquals(c.casoAmarrado, { client_id: "c-1", vessel_id: "v-1" });
});

const r2 = (n: number) => Math.round(n * 100) / 100;


// ─── Revisão da F3 ──────────────────────────────────────────────────────────────────────────────────────────────────────

Deno.test("retorno_ler_caso marca a sessão do turno, não a do cartão", async () => {
  const { c, chamadas } = ctxDoCaso({ n: 2, recebidas: [], fatos: {} });
  c.sessaoId = "sessao-do-turno";
  await toolsByName.retorno_ler_caso.execute({ n: 2 }, c);
  assertEquals(chamadas.find((x) => x.fn === "retorno_ver_caso_para_modelo")?.args, { p_n: 2, p_autor: "dono", p_sessao: "sessao-do-turno" });
  const sem = ctxDoCaso({ n: 2, recebidas: [], fatos: {} });
  await toolsByName.retorno_ler_caso.execute({ n: 2 }, sem.c);
  assertEquals(sem.chamadas.find((x) => x.fn === "retorno_ver_caso_para_modelo")?.args.p_sessao, null);
});

Deno.test("create_service_order de orçamento sobe a risco alto só com a sessão amarrada; OS numerada segue como sempre", () => {
  assertEquals(riscoDoEnvioLivre("create_service_order", "low", true, {}), "high");
  assertEquals(riscoDoEnvioLivre("create_service_order", "low", true, { status: "draft" }), "high");
  assertEquals(riscoDoEnvioLivre("create_service_order", "low", true, { status: "in_progress" }), "low");
  assertEquals(riscoDoEnvioLivre("create_service_order", "low", false, {}), "low");
  assertEquals(riscoDoEnvioLivre("create_service_order", "low", undefined, { status: "draft" }), "low");
  assertEquals(isAutonomyGranted("create_service_order", "high", { ai_autonomy_create_service_order: "auto" }), false);
});

Deno.test("PDF de rascunho: as frases de falha não dizem que o orçamento foi criado agora", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const pdf = { ...PRE_OK, acao: "pdf", numero: "ORÇ-00140", args: undefined, previa_id: null };
    const orc = ORC({ acao: "pdf", service_order_id: "os-9", numero: "ORÇ-00140", previa_id: null });
    const f = fluxo({ retorno_previa_preparar: pdf });
    const d = depsFalsos(f, { envio: { error: "provedor fora" } });
    assertEquals(await orcarEEnviar(orc, f.c, d.deps), ["o 1: o PDF do ORÇ-00140 não saiu (provedor fora); responda pelo celular"]);

    const g = fluxo({ retorno_previa_preparar: { ...pdf, legenda: { ...LEGENDA, contexto: { ...CONTEXTO_LEGENDA, audiencia: "equipe" } } } });
    const dg = depsFalsos(g);
    assertEquals(await orcarEEnviar(orc, g.c, dg.deps), ["o 1: legenda recusada; o PDF do ORÇ-00140 não saiu"]);
  });
});

Deno.test("WhatsApp em modo de teste: o dono sabe que foi ao número de teste, e o caso fica aberto", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f, { envio: { ok: true, destino_chave8: "87654321", desviado_para_teste: true } });
    const a = await orcarEEnviar(ORC(), f.c, d.deps);
    assertEquals(a, ["o 1: orçamento ORÇ-00151 criado, mas o PDF foi ao número de teste, não ao cliente"]);
    assertEquals(f.nomes().includes("retorno_previa_pdf"), false);
    assertEquals(f.nomes().includes("retorno_item_enviado"), false);
    assertEquals(f.chamadas.at(-1)?.fn, "retorno_previa_soltar");
  });
});

// ─── Retorno F4 (P12.1, P12.3): orcarEEnviar com item do parceiro (C13) ─────────────────────────────────────────────────

const TEXTO_P16 = "Oi, Carla! Segue o orçamento do motorhome de João, válido até 15/01.";
const LEGENDA_P16 = {
  texto: TEXTO_P16,
  contexto: {
    audiencia: "parceiro" as const, datas_permitidas: ["15/01"], horas_permitidas: [] as string[], nome_permitido: "Carla",
    nomes_de_outros: [] as string[], nomes_da_lista: ["João"], papel_do_parceiro: "contratante", os_permitidas: [] as string[],
    textos_do_cliente: [] as string[], trechos_do_modelo: ["Oi, ", "! Segue o orçamento do ", " de ", ", válido até ", "."],
    marcas: { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false },
  },
  validade_data: "2027-01-15",
};
const PRE_PARCEIRO = { ...PRE_OK, rotulo: "MP (Carla)", parceiro_id: "pa-1", pedido_id: "pe-1", legenda: LEGENDA_P16, args: { ...PRE_OK.args, origem: "retorno_parceiro" } };
const PRE_PARCEIRO_CLIENTE = { ...PRE_PARCEIRO, legenda: LEGENDA };
const RPCS_DO_PARCEIRO = {
  preparar: "parceiro_previa_preparar", soltar: "parceiro_previa_soltar", enviado: "parceiro_item_enviado",
  caiu: "parceiro_previa_caiu", pdf: "parceiro_previa_pdf",
};
const OPC_PARCEIRO = {
  rpcs: RPCS_DO_PARCEIRO, destino: "parceiro" as const, parceiro_id: "pa-1", pedido_id: "pe-1", soltar_sem_enviar: false,
  frase_sem_enviar: "o 1: ficou em rascunho; o PDF ao parceiro só sai depois do aviso e de 24 h; peça de novo depois disso",
};
const OPC_CLIENTE = { ...OPC_PARCEIRO, destino: "cliente" as const };

Deno.test("F4: os cinco nomes do parceiro, e nenhum retorno_previa_* da F3 fora o orc_criado; o preparar com p_pedido e p_destino", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ parceiro_previa_preparar: PRE_PARCEIRO, parceiro_vinculo_do_pedido: { ok: true, interessado_id: "oi-1", papel: "contratante" } });
    const d = depsFalsos(f);
    const a = await orcarEEnviar(ORC(), f.c, d.deps, OPC_PARCEIRO);
    assertEquals(f.nomes(), ["parceiro_previa_preparar", "montar", "retorno_previa_orc_criado", "parceiro_vinculo_do_pedido", "enviar_pdf", "parceiro_previa_pdf", "parceiro_item_enviado"]);
    assertEquals(f.chamadas[0].args, { p_pedido: "pe-1", p_previa: "pv-1", p_item: "i-1", p_autor: "dono", p_so: null, p_destino: "parceiro" });
    assertEquals(d.montados[0].opcoes, { origem: { valor: "retorno_parceiro", chave8: "12345678", parceiro_id: "pa-1" } });
    assertEquals(f.chamadas[3].args, { p_pedido: "pe-1", p_so: "os-1", p_autor: "dono", p_destino: "parceiro" });
    assertEquals(d.enviados[0].destino, "parceiro");
    assertEquals(d.enviados[0].custom_message, TEXTO_P16);
    assertEquals(f.chamadas[6].args, { p_item: "i-1", p_ok: true, p_wa_id: null });
    assertEquals(a, ["Orçamento ORÇ-00151 criado e PDF enviado a MP (Carla)."]);
  });
});

Deno.test("F4: o vínculo nasce também com destino cliente, antes do envio, e a legenda ao cliente passa no validador do cliente", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ parceiro_previa_preparar: PRE_PARCEIRO_CLIENTE, parceiro_vinculo_do_pedido: { ok: true, interessado_id: "oi-1", papel: "indicou" } });
    const d = depsFalsos(f);
    const a = await orcarEEnviar(ORC(), f.c, d.deps, OPC_CLIENTE);
    assertEquals(f.chamadas[0].args.p_destino, "cliente");
    const ordem = f.nomes();
    assert(ordem.indexOf("parceiro_vinculo_do_pedido") < ordem.indexOf("enviar_pdf"), ordem.join(" > "));
    assertEquals(f.chamadas.find((x) => x.fn === "parceiro_vinculo_do_pedido")?.args.p_destino, "cliente");
    assertEquals("destino" in d.enviados[0], false, "ao cliente, o envio de sempre");
    assertEquals(a, ["Orçamento ORÇ-00151 criado e PDF enviado a MP (Carla)."]);
  });
});

Deno.test("F4: ramo pdf — o vínculo logo depois do preparar, sem montar", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const pdf = { ...PRE_PARCEIRO, acao: "pdf", numero: "ORÇ-00140", args: undefined, previa_id: null };
    const f = fluxo({ parceiro_previa_preparar: pdf, parceiro_vinculo_do_pedido: { ok: true } });
    const d = depsFalsos(f);
    await orcarEEnviar(ORC({ acao: "pdf", service_order_id: "os-9", numero: "ORÇ-00140", previa_id: null }), f.c, d.deps, OPC_PARCEIRO);
    assertEquals(f.nomes().slice(0, 3), ["parceiro_previa_preparar", "parceiro_vinculo_do_pedido", "enviar_pdf"]);
    assertEquals(f.chamadas[1].args.p_so, "os-9");
  });
});

Deno.test("F4: vínculo recusado — nada sai, o item é solto pelo parceiro e o dono ouve a frase", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ parceiro_previa_preparar: PRE_PARCEIRO, parceiro_vinculo_do_pedido: { ok: false, motivo: "os_fora", frase: "o rascunho é de outro cliente; nada saiu" } });
    const d = depsFalsos(f);
    const a = await orcarEEnviar(ORC(), f.c, d.deps, OPC_PARCEIRO);
    assertEquals(f.nomes().includes("enviar_pdf"), false);
    assertEquals(f.chamadas.at(-1), { fn: "parceiro_previa_soltar", args: { p_item: "i-1" } });
    assertEquals(a, ["o 1: o rascunho é de outro cliente; nada saiu"]);
  });
});

Deno.test("F4: sem_enviar com soltar_sem_enviar falso — o vínculo nasce, a frase do parceiro vai ao dono e nada é solto", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ parceiro_previa_preparar: PRE_PARCEIRO, parceiro_vinculo_do_pedido: { ok: true } });
    const d = depsFalsos(f);
    const a = await orcarEEnviar(ORC({ sem_enviar: true }), f.c, d.deps, OPC_PARCEIRO);
    assertEquals(f.nomes(), ["parceiro_previa_preparar", "montar", "retorno_previa_orc_criado", "parceiro_vinculo_do_pedido"]);
    assertEquals(a, [OPC_PARCEIRO.frase_sem_enviar]);
    // com o padrão (F3), o sem_enviar continua soltando
    const g = fluxo({ parceiro_previa_preparar: PRE_PARCEIRO, parceiro_vinculo_do_pedido: { ok: true } });
    const dg = depsFalsos(g);
    await orcarEEnviar(ORC({ sem_enviar: true }), g.c, dg.deps, { ...OPC_PARCEIRO, soltar_sem_enviar: undefined, frase_sem_enviar: undefined });
    assertEquals(g.chamadas.at(-1)?.fn, "parceiro_previa_soltar");
  });
});

Deno.test("F4: ja_existe chama parceiro_previa_caiu; PDF que falha solta pelo parceiro", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ parceiro_previa_preparar: PRE_PARCEIRO });
    const d = depsFalsos(f, { orcamento: { ja_existe: "ORÇ-00140", error: "x" } });
    await orcarEEnviar(ORC(), f.c, d.deps, OPC_PARCEIRO);
    assertEquals(f.chamadas.at(-1), { fn: "parceiro_previa_caiu", args: { p_previa: "pv-1", p_item: "i-1", p_motivo: "orc_existe" } });

    const g = fluxo({ parceiro_previa_preparar: PRE_PARCEIRO, parceiro_vinculo_do_pedido: { ok: true } });
    const dg = depsFalsos(g, { envio: { error: "provedor fora" } });
    await orcarEEnviar(ORC(), g.c, dg.deps, OPC_PARCEIRO);
    assertEquals(g.chamadas.find((x) => x.fn === "parceiro_previa_pdf")?.args.p_ok, false);
    assertEquals(g.chamadas.at(-1)?.fn, "parceiro_previa_soltar");
    assertEquals(g.nomes().some((n) => n.startsWith("retorno_previa_") && n !== "retorno_previa_orc_criado"), false);
  });
});

Deno.test("F4: a legenda ao parceiro reprovada no validador do parceiro não sai (nunca passa pelo do cliente)", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const comValor = { ...LEGENDA_P16, texto: "Oi, Carla! Segue o orçamento do motorhome de João, R$ 8.040, válido até 15/01." };
    const f = fluxo({ parceiro_previa_preparar: { ...PRE_PARCEIRO, legenda: comValor }, parceiro_vinculo_do_pedido: { ok: true } });
    const d = depsFalsos(f);
    const a = await orcarEEnviar(ORC(), f.c, d.deps, OPC_PARCEIRO);
    assertEquals(f.nomes().includes("enviar_pdf"), false);
    assertEquals(a, ["o 1: legenda recusada; orçamento ORÇ-00151 criado, nada saiu"]);
    assertEquals(f.chamadas.at(-1)?.fn, "parceiro_previa_soltar");
  });
});

Deno.test("F4: opcoes ausente é igual ao de hoje, byte a byte", async () => {
  await comRelogio(MEIO_DIA, async () => {
    const f = fluxo({ retorno_previa_preparar: PRE_OK });
    const d = depsFalsos(f);
    const g = fluxo({ retorno_previa_preparar: PRE_OK });
    const dg = depsFalsos(g);
    assertEquals(await orcarEEnviar(ORC(), f.c, d.deps), await orcarEEnviar(ORC(), g.c, dg.deps, undefined));
    assertEquals(JSON.stringify(f.chamadas), JSON.stringify(g.chamadas));
    assertEquals(f.chamadas[0].args, { p_previa: "pv-1", p_item: "i-1", p_autor: "dono", p_so: null });
    assertEquals(JSON.stringify(d.montados), JSON.stringify(dg.montados));
    assertEquals(JSON.stringify(d.enviados), JSON.stringify(dg.enviados));
    assertEquals(f.nomes().some((n) => n.startsWith("parceiro_")), false);
  });
});
