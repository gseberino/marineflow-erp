import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  autorDaConsulta, codigoDoCmp, COMPLETAR_COMPROVANTE, comprovantesJaLancados, comprovantesParecidos, comprovanteTools,
  conferirComprovantes, dataDaConsulta, fluxoQueFalou, gravadoComEfeito, numeroDaOsDita, primeiroAberto,
  textoDaDespesaCobradaComCmpAberto, textoDaDespesaComCmpAberto, textoDaDespesaDoCmpNaoSai, textoDaDespesaInternaDoCmp,
  textoDaDespesaJaLancada, textoDoAberto, textoDoJaLancado, valorDoCompletar,
} from "./comprovantes.ts";
import { ehLeituraPeloNome, ESCRITAS_VERIFICADAS_DA_REDE, rodaDiretoPelaRede, SO_PELA_REDE } from "../perfil-operacao.ts";
import { allTools } from "./index.ts";
import { criarHandler } from "../../../comprovantes-whatsapp/handler.ts";
import type { DependenciasDoFluxo } from "../../comprovantes/fluxo.ts";

/* Comprovantes pela conversa do assistente (F2, 11/10/2026). A tool só lê; as funções do banco
   (comprovantes_consultar e comprovantes_parecidos) são dublês aqui, com as formas da spec. */

const sem = (s: unknown) => String(s).replace(/\u00a0/g, " ");
const tool = comprovanteTools.find((t) => t.name === "consultar_comprovantes")!;

/** Client falso: grava as chamadas de rpc e devolve o que cada função mandar. */
function cliente(respostas: Record<string, { data?: unknown; error?: unknown } | Error>) {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const c = {
    rpc(fn: string, args: Record<string, unknown>) {
      chamadas.push({ fn, args });
      const r = respostas[fn];
      if (r instanceof Error) return Promise.reject(r);
      return Promise.resolve({ data: r?.data ?? null, error: r?.error ?? null });
    },
    from(t: string) {
      // nenhuma leitura de tabela: sem usuário, a consulta não cai mais no dono (revisão de 11/10/2026)
      throw new Error(`leitura inesperada de ${t}`);
    },
  };
  return { c, chamadas };
}

const ctxDe = (c: unknown, extra: Record<string, unknown> = {}) =>
  ({ sb: c, admin: c, userId: "u-dono", userRole: "admin", jwt: "", appOrigin: "", settings: {}, ...extra }) as never;

Deno.test("consultar_comprovantes: só leitura, só admin, na rede (roda direto) e não no perfil", () => {
  assertEquals(tool.risk, "low");
  assertEquals(tool.roles, ["admin"]);
  assertEquals(ehLeituraPeloNome(tool.name), true);
  assertEquals(rodaDiretoPelaRede(tool), true);
  assertEquals(SO_PELA_REDE.has(tool.name), true);
  assertEquals(allTools.some((t) => t.name === tool.name), true, "não registrada em tools/index.ts");
});

Deno.test("consultar_comprovantes: manda os filtros normalizados e o autor; devolve o que veio", async () => {
  const volta = { itens: [{ codigo: "CMP-00124", situacao: "gravado", valor: "62.00" }], total: 1 };
  const { c, chamadas } = cliente({ comprovantes_consultar: { data: volta } });
  const r = await tool.execute(
    { codigo: "cmp 124", situacao: "gravado", desde: "01/10/2026", ate: "2026-10-11", valor: "62,5", os_id: "os-1" },
    ctxDe(c),
  );
  assertEquals(r, volta);
  assertEquals(chamadas, [{
    fn: "comprovantes_consultar",
    args: { p: { autor: "u-dono", codigo: "CMP-00124", situacao: "gravado", desde: "2026-10-01", ate: "2026-10-11", os_id: "os-1", valor: 62.5 } },
  }]);
});

Deno.test("consultar_comprovantes: erro do banco vira error dizendo que a consulta falhou (nunca 'nenhum')", async () => {
  const { c } = cliente({ comprovantes_consultar: { error: { message: "function does not exist" } } });
  const r = await tool.execute({}, ctxDe(c)) as { error?: string };
  assertStringIncludes(String(r.error), "consulta falhou");
});

Deno.test("consultar_comprovantes: quem não é admin, ou filtro ilegível, não chega ao banco", async () => {
  const { c, chamadas } = cliente({});
  const naoAdmin = await tool.execute({}, ctxDe(c, { userRole: "financial" })) as { error?: string };
  assertStringIncludes(String(naoAdmin.error), "administrador");
  for (const args of [{ codigo: "abc" }, { numero: -1 }, { situacao: "qualquer" }, { desde: "semana passada" }, { valor: 0 }]) {
    const r = await tool.execute(args, ctxDe(c)) as { error?: string };
    assertEquals(typeof r.error, "string", JSON.stringify(args));
  }
  assertEquals(chamadas.length, 0);
});

Deno.test("F3: as situações da conciliação com o extrato estão no enum, na descrição e chegam ao banco", async () => {
  const situacao = (tool.input_schema as { properties: { situacao: { enum: string[]; description: string } } }).properties.situacao;
  for (const s of ["aguardando_banco", "conciliado", "abandonado"]) {
    assertEquals(situacao.enum.includes(s), true, s);
    assertStringIncludes(situacao.description, `${s} =`);
    const { c, chamadas } = cliente({ comprovantes_consultar: { data: { itens: [], total: 0 } } });
    await tool.execute({ situacao: s }, ctxDe(c));
    assertEquals((chamadas[0].args.p as Record<string, unknown>).situacao, s);
  }
  assertStringIncludes(situacao.description, "45 no crédito");
});

Deno.test("codigoDoCmp e dataDaConsulta: como o dono fala", () => {
  assertEquals(codigoDoCmp("CMP-00124"), "CMP-00124");
  assertEquals(codigoDoCmp("cmp 124"), "CMP-00124");
  assertEquals(codigoDoCmp("124"), "CMP-00124");
  assertEquals(codigoDoCmp("os 124"), null);
  const agora = new Date("2026-10-11T15:00:00Z");
  assertEquals(dataDaConsulta("hoje", agora), "2026-10-11");
  assertEquals(dataDaConsulta("ontem", agora), "2026-10-10");
  assertEquals(dataDaConsulta("10/10", agora), "2026-10-10");
  assertEquals(dataDaConsulta("10/10/26", agora), "2026-10-10");
  assertEquals(dataDaConsulta("amanhã", agora), null);
});

// ─── comprovantes_parecidos: o que as travas de caixa.ts e so-ops.ts usam ────────────────────

const PARECIDOS = {
  abertos: [{ codigo: "CMP-00124", numero: 124, valor: "62.00", data: "2026-10-10", fornecedor: "Auto Posto Exemplo" }],
  gravados: [{ codigo: "CMP-00123", numero: 123, valor: "62.00", data: "2026-10-10", os_id: null, efeitos: ["caixa"] }],
};

Deno.test("comprovantesParecidos: valor, data, OS e autor vão à função; a forma volta filtrada", async () => {
  const { c, chamadas } = cliente({ comprovantes_parecidos: { data: PARECIDOS } });
  const r = await comprovantesParecidos({ admin: c, userId: "u-dono" }, { valor: 62, data: "2026-10-10", osId: "os-1" });
  assertEquals(r, PARECIDOS);
  assertEquals(chamadas[0], { fn: "comprovantes_parecidos", args: { p_valor: 62, p_data: "2026-10-10", p_os: "os-1", p_autor: "u-dono" } });
});

Deno.test("comprovantesParecidos: sem usuário não consulta (nunca cai no dono); data não ISO vai nula", async () => {
  const { c, chamadas } = cliente({ comprovantes_parecidos: { data: PARECIDOS } });
  assertEquals(autorDaConsulta({}), null);
  assertEquals(await comprovantesParecidos({ admin: c }, { valor: 62, data: null, osId: null }), null);
  assertEquals(chamadas.length, 0);
  await comprovantesParecidos({ admin: c, userId: "u-dono" }, { valor: 62, data: null, osId: null });
  // Sem data dita vai nula: o banco olha os CMPs recebidos nos últimos 3 dias.
  assertEquals(chamadas[0].args.p_data, null);
  await comprovantesParecidos({ admin: c, userId: "u-dono" }, { valor: 62, data: "ontem", osId: null });
  assertEquals(chamadas[1].args.p_data, null, "data que não é AAAA-MM-DD não vai ao banco");
});

Deno.test("comprovantesParecidos: erro, função ausente ou exceção = null (quem chama segue como antes)", async () => {
  for (const resposta of [{ error: { code: "PGRST202", message: "x" } }, new Error("rede")]) {
    const { c } = cliente({ comprovantes_parecidos: resposta });
    assertEquals(await comprovantesParecidos({ admin: c, userId: "u" }, { valor: 62, data: null, osId: null }), null);
  }
  const { c, chamadas } = cliente({});
  assertEquals(await comprovantesParecidos({ admin: c, userId: "u" }, { valor: 0, data: null, osId: null }), null);
  assertEquals(chamadas.length, 0, "valor zero nem consulta");
});

Deno.test("gravadoComEfeito e primeiroAberto: só o efeito do mesmo tipo conta", () => {
  assertEquals(gravadoComEfeito(PARECIDOS, ["caixa"])?.codigo, "CMP-00123");
  assertEquals(gravadoComEfeito(PARECIDOS, ["anotar", "anexar_anotacao"]), null);
  assertEquals(gravadoComEfeito(null, ["caixa"]), null);
  assertEquals(primeiroAberto(PARECIDOS)?.codigo, "CMP-00124");
  assertEquals(primeiroAberto({ abertos: [], gravados: [] }), null);
});

Deno.test("textos das travas: uma linha, o código, valor e data que o dono reconhece", () => {
  const g = PARECIDOS.gravados[0];
  const a = PARECIDOS.abertos[0];
  assertEquals(sem(textoDoJaLancado(g)), "⚠️ Já lançado pelo CMP-00123 (R$ 62,00 em 10/10). Nada foi lançado de novo.");
  assertEquals(sem(textoDoAberto(a)), "Atenção: há o CMP-00124 aberto com R$ 62,00 em 10/10. Se for o mesmo gasto, responda *não* e depois *cmp 124*.");
  assertEquals(sem(textoDaDespesaJaLancada(g)), "Já lançado pelo CMP-00123 (R$ 62,00 em 10/10) nesta OS.");
  assertEquals(
    sem(textoDaDespesaComCmpAberto(a)),
    "Há o CMP-00124 aberto com R$ 62,00 em 10/10; completar o CMP? Responda *cmp 124*. Se for outro gasto, peça de novo dizendo 'mesmo assim'.",
  );
  for (const t of [textoDoJaLancado(g), textoDoAberto(a), textoDaDespesaJaLancada(g), textoDaDespesaComCmpAberto(a)]) {
    assertEquals(t.includes("\n"), false);
  }
  // Sem o número, o "cmp N" sai do código.
  assertStringIncludes(textoDoAberto({ codigo: "CMP-00007", valor: 10, data: "2026-10-01" }), "*cmp 7*");
});

// ─── conferirComprovantes: a trava de caixa.ts e so-ops.ts (revisão de 11/10/2026) ───────────

const LIGADA = { comprovante_fluxo: "dono", comprovante_conversa: "on" };
const EFEITOS = ["caixa"] as const;

Deno.test("conferirComprovantes: admin com a conversa ligada vê o gravado e o aberto (com código)", async () => {
  const { c, chamadas } = cliente({ comprovantes_parecidos: { data: PARECIDOS } });
  const r = await conferirComprovantes({ admin: c, userId: "u-dono", userRole: "admin", settings: LIGADA }, { valor: 62, data: null, osId: null, efeitos: EFEITOS });
  assertEquals(r.gravado !== true && r.gravado?.codigo, "CMP-00123");
  assertEquals(r.aberto?.codigo, "CMP-00124");
  assertEquals(chamadas.map((x) => x.fn), ["comprovantes_parecidos"]);
});

// Revisão dos ajustes do dono (11/10/2026): o custo interno do CMP não trava a despesa cobrada — só avisa.
Deno.test("conferirComprovantes: 'avisar' devolve o CMP com o efeito (só o admin, e só sem gravado que trava)", async () => {
  const interno = { abertos: [], gravados: [{ codigo: "CMP-00125", numero: 125, valor: "62.00", data: "2026-10-10", os_id: "os-1", efeitos: ["despesa_os"] }] };
  const { c } = cliente({ comprovantes_parecidos: { data: interno } });
  const r = await conferirComprovantes({ admin: c, userId: "u-dono", userRole: "admin", settings: LIGADA },
    { valor: 62, data: null, osId: "os-1", efeitos: ["anexar_despesa"], avisar: ["despesa_os"] });
  assertEquals(r.gravado, null);
  assertEquals(r.avisado?.codigo, "CMP-00125");
  const { c: c2 } = cliente({ comprovantes_parecidos: { data: interno } });
  const r2 = await conferirComprovantes({ admin: c2, userId: "u-dono", userRole: "admin", settings: LIGADA },
    { valor: 62, data: null, osId: "os-1", efeitos: ["anexar_despesa", "despesa_os"], avisar: ["despesa_os"] });
  assertEquals(r2.gravado !== true && r2.gravado?.codigo, "CMP-00125");
  assertEquals(r2.avisado, null);
  const g = interno.gravados[0];
  assertEquals(
    sem(textoDaDespesaInternaDoCmp(g)),
    "O CMP-00125 (R$ 62,00 em 10/10) é só custo interno desta OS (não aparece para o cliente); lancei a despesa cobrada do cliente. " +
      "No Lucro por OS a compra conta uma vez só.",
  );
  assertStringIncludes(sem(textoDaDespesaCobradaComCmpAberto(PARECIDOS.abertos[0])), "*cmp 124*");
  assertEquals(textoDaDespesaDoCmpNaoSai("CMP-00124"),
    "Essa despesa é o custo interno do CMP-00124 (comprovante): não apago por aqui. Para tirá-la, cancele o comprovante: *cancelar cmp 124 motivo*.");
  for (const t of [textoDaDespesaInternaDoCmp(g), textoDaDespesaCobradaComCmpAberto(PARECIDOS.abertos[0]), textoDaDespesaDoCmpNaoSai("CMP-00124")]) {
    assertEquals(t.includes("\n"), false);
    assertEquals(/cobrar do cliente\?/i.test(t), false);
  }
});

Deno.test("conferirComprovantes: conversa desligada ou em sombra — o aberto não conta (o gravado sim)", async () => {
  for (const settings of [{}, { comprovante_fluxo: "sombra", comprovante_conversa: "on" }, { comprovante_fluxo: "dono", comprovante_conversa: "off" }] as Array<Record<string, string>>) {
    const { c } = cliente({ comprovantes_parecidos: { data: PARECIDOS } });
    const r = await conferirComprovantes({ admin: c, userId: "u-dono", userRole: "admin", settings }, { valor: 62, data: null, osId: null, efeitos: EFEITOS });
    assertEquals(r.aberto, null, JSON.stringify(settings));
    assertEquals(r.gravado !== true && r.gravado?.codigo, "CMP-00123");
  }
});

Deno.test("conferirComprovantes: financeiro usa comprovantes_ja_lancados — só o booleano, nunca o aberto", async () => {
  const { c, chamadas } = cliente({ comprovantes_ja_lancados: { data: { ja_lancado: true, aberto: true } } });
  const r = await conferirComprovantes({ admin: c, userId: "u-fin", userRole: "financial", settings: LIGADA }, { valor: 62.004, data: "2026-10-10", osId: "os-1", efeitos: EFEITOS });
  assertEquals(r, { gravado: true, aberto: null });
  assertEquals(chamadas, [{
    fn: "comprovantes_ja_lancados",
    args: { p_valor: 62, p_data: "2026-10-10", p_os: "os-1", p_efeitos: ["caixa"], p_autor: "u-fin" },
  }]);
  assertEquals(textoDoJaLancado(true), "⚠️ Esse gasto já foi lançado por um comprovante do dono. Nada foi lançado de novo.");
  assertEquals(textoDaDespesaJaLancada(true), "Esse gasto já foi lançado nesta OS por um comprovante do dono.");
});

Deno.test("conferirComprovantes: sem usuário, valor zero ou falha da consulta = nada (segue como antes)", async () => {
  const { c, chamadas } = cliente({ comprovantes_parecidos: { data: PARECIDOS } });
  assertEquals(await conferirComprovantes({ admin: c, settings: LIGADA }, { valor: 62, data: null, osId: null, efeitos: EFEITOS }), { gravado: null, aberto: null });
  assertEquals(await conferirComprovantes({ admin: c, userId: "u", userRole: "admin", settings: LIGADA }, { valor: 0, data: null, osId: null, efeitos: EFEITOS }), { gravado: null, aberto: null });
  assertEquals(chamadas.length, 0);
  for (const resposta of [{ error: { code: "PGRST202", message: "x" } }, new Error("rede")]) {
    const { c: c2 } = cliente({ comprovantes_ja_lancados: resposta });
    assertEquals(await comprovantesJaLancados({ admin: c2, userId: "u-fin" }, { valor: 62, data: null, osId: null, efeitos: EFEITOS }), null);
    assertEquals(await conferirComprovantes({ admin: c2, userId: "u-fin", userRole: "financial", settings: LIGADA }, { valor: 62, data: null, osId: null, efeitos: EFEITOS }), { gravado: null, aberto: null });
  }
});

// ─── completar_comprovante (11/10/2026 — spec-assistente-opera-cmp.md, A) ───────────────────

const completarTool = comprovanteTools.find((t) => t.name === COMPLETAR_COMPROVANTE)!;
const DONO_ID = "0d0d0d0d-0000-4000-8000-000000000001";
const DONO_FONE = "5547999990000";
const URL_DA_EDGE = "https://ref.supabase.co/functions/v1/comprovantes-whatsapp";

/** Banco mínimo da tool: só o dono (app_users) — a tool não lê mais nada; quem grava é a edge. */
function bancoDoDono(dono: { id: string; phone_normalized: string } | null = { id: DONO_ID, phone_normalized: DONO_FONE }) {
  const q: Record<string, unknown> = {};
  for (const m of ["select", "eq", "not", "order", "limit"]) q[m] = () => q;
  q.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: dono ? [dono] : [], error: null }).then(ok);
  return {
    from: (t: string) => {
      if (t !== "app_users") throw new Error(`leitura inesperada de ${t}`);
      return q;
    },
    rpc: () => {
      throw new Error("a tool não chama função do banco");
    },
  };
}

const ctxDoDono = (extra: Record<string, unknown> = {}) => {
  const admin = bancoDoDono();
  return { sb: admin, admin, userId: DONO_ID, userRole: "admin", jwt: "", appOrigin: "", settings: LIGADA, ...extra } as never;
};

/** Troca o fetch global (a tool chama a edge pela rede) e devolve as chamadas; restaura no fim. */
async function comFetch<T>(resposta: (url: string, init?: RequestInit) => Promise<Response> | Response, corpo: (chamadas: Array<{ url: string; init?: RequestInit; json: Record<string, unknown> }>) => Promise<T>): Promise<T> {
  const chamadas: Array<{ url: string; init?: RequestInit; json: Record<string, unknown> }> = [];
  const original = globalThis.fetch;
  const url0 = Deno.env.get("SUPABASE_URL");
  const chave0 = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  Deno.env.set("SUPABASE_URL", "https://ref.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico-de-teste");
  globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    chamadas.push({ url, init, json: init?.body ? JSON.parse(String(init.body)) : {} });
    return Promise.resolve(resposta(url, init));
  }) as typeof fetch;
  try {
    return await corpo(chamadas);
  } finally {
    globalThis.fetch = original;
    if (url0 === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", url0);
    if (chave0 === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", chave0);
  }
}

const respostaDaEdge = (corpo: unknown, status = 200) => () => new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });
const ENVIADA = {
  ok: true, codigo: "CMP-00001", aplicados: ["categoria", "valor"], ignorados: [], passo: "para_que", enviada: true, ocupado: false, ocupado_por: null,
  anotado: ["categoria Combustível e deslocamento", "valor R$ 235,97 (no comprovante: R$ 204,87)"], recusado: null,
  cmp: {
    valor: "235.97", data: "2026-10-11", destino: null, os: null, categoria: "Combustível e deslocamento", forma: null, quem_pagou: null, tipo_na_os: null,
    observacao: "o do cartão",
  },
};

Deno.test("completar_comprovante: escrita low só do admin, na rede e roda direto (verificada); registrada em allTools", () => {
  assertEquals(completarTool.risk, "low");
  assertEquals(completarTool.roles, ["admin"]);
  assertEquals(SO_PELA_REDE.has(COMPLETAR_COMPROVANTE), true);
  assertEquals(ehLeituraPeloNome(COMPLETAR_COMPROVANTE), false);
  assertEquals(rodaDiretoPelaRede(completarTool), true);
  assertEquals(allTools.some((t) => t.name === COMPLETAR_COMPROVANTE), true);
  assertEquals((completarTool.input_schema as { required: string[] }).required, ["cmp"]);
  // registrada ≠ ensinada: a descrição diz o que ela NÃO faz
  assertStringIncludes(completarTool.description, "NÃO grava nada no financeiro");
  assertStringIncludes(completarTool.description, "só o *sim* dele");
  // 12/10/2026: a observação fica guardada e o pedido é tudo ou nada
  assertStringIncludes(completarTool.description, "a observação fica guardada no CMP");
  assertStringIncludes(completarTool.description, "Pode mandar só a observação");
  assertStringIncludes(completarTool.description, "É tudo ou nada");
  const obs = (completarTool.input_schema as { properties: Record<string, { description: string }> }).properties.observacao.description;
  assertStringIncludes(obs, "até 200 caracteres");
  assertStringIncludes(obs, "Obrigatória quando o valor muda e o CMP ainda não tem observação");
  // o porquê da escrita verificada diz a RPC única, o tudo ou nada e a observação
  const porque = ESCRITAS_VERIFICADAS_DA_REDE[COMPLETAR_COMPROVANTE];
  assertStringIncludes(porque, "inclusive a observação");
  assertStringIncludes(porque, "comprovante_completar (numa transação só, tudo ou nada");
  assertStringIncludes(porque, "só o *sim* dele grava");
});

Deno.test("despesa de campo (13/10/2026): as descrições dizem que combustível, alimentação e pedágio numa OS já são despesa — peça ou despesa só se o dono disse", () => {
  assertStringIncludes(
    completarTool.description,
    "Combustível, alimentação e pedágio numa OS o sistema já trata como despesa da OS (custo interno) sem perguntar: mande peça ou despesa só se o dono disse.",
  );
  // logo depois da lista do que se passa (a frase vem depois da categoria)
  assert(completarTool.description.indexOf("combustível, almoço, pedágio…)") < completarTool.description.indexOf("Combustível, alimentação e pedágio numa OS"));
  const tipo = (completarTool.input_schema as { properties: Record<string, { description: string }> }).properties.tipo_na_os.description;
  assertEquals(tipo, "Na OS: peça/material ou despesa (custo interno). Só se o dono disse: combustível, alimentação e pedágio já são despesa pela categoria.");
  assertStringIncludes(tool.description, "(tipo_na_os: a despesa é custo interno");
  assertStringIncludes(tool.description, "; combustível, alimentação e pedágio numa OS são despesa pela categoria, sem perguntar");
  // o que já estava continua: só o dono grava, nada no financeiro
  assertStringIncludes(completarTool.description, "NÃO grava nada no financeiro");
});

Deno.test("completar_comprovante: só o admin, só o dono, com a conversa ligada e com algo a completar — senão nem chama a edge", async () => {
  await comFetch(respostaDaEdge(ENVIADA), async (chamadas) => {
    const casos: Array<[string, Record<string, unknown>, Record<string, unknown>, string]> = [
      ["financeiro", { cmp: "1", valor: 10 }, { userRole: "financial" }, "administrador"],
      ["conversa desligada", { cmp: "1", valor: 10 }, { settings: {} }, "desligada"],
      ["outro admin (não é o dono)", { cmp: "1", valor: 10 }, { userId: "outro-admin" }, "Só o dono"],
      ["sem dono", { cmp: "1", valor: 10 }, { admin: bancoDoDono(null) }, "Só o dono"],
      ["só o cmp", { cmp: "1" }, {}, "Diga o que completar"],
      ["observação em branco", { cmp: "1", observacao: "  \n " }, {}, "observação"],
      ["cmp ilegível", { cmp: "os 1", valor: 10 }, {}, "Não entendi o comprovante"],
      ["valor ilegível", { cmp: "1", valor: "duzentos" }, {}, "Não entendi o valor"],
      ["valor zero", { cmp: "1", valor: 0 }, {}, "Não entendi o valor"],
      ["data ilegível", { cmp: "1", data: "31/02" }, {}, "Não entendi a data"],
      ["OS ilegível", { cmp: "1", os: "do Brisa" }, {}, "Não entendi a OS"],
      ["OS e destino que não combinam", { cmp: "1", os: "112", destino: "estoque" }, {}, "destino e os não combinam"],
      ["forma fora do enum", { cmp: "1", forma: "cartao" }, {}, "forma aceita só"],
    ];
    for (const [caso, args, ctx, erro] of casos) {
      const r = await completarTool.execute(args, ctxDoDono(ctx)) as { error?: string };
      assertStringIncludes(String(r.error), erro, caso);
    }
    assertEquals(chamadas.length, 0, "nenhuma chamada à edge");
  });
});

Deno.test("completar_comprovante: normaliza o que o dono disse e manda à porta interna da edge (IA pensa, sistema preenche)", async () => {
  await comFetch(respostaDaEdge(ENVIADA), async (chamadas) => {
    await completarTool.execute({
      cmp: "CMP-00001", valor: "R$ 235,97", data: "ontem", os: "ORÇ-00112", tipo_na_os: "despesa", categoria: " combustível\n",
      forma: "credito", quem_pagou: "tecnico", tecnico: "Roberto", observacao: "cupom sem o gasto\ncomplementar; vale o do cartão",
    }, ctxDoDono());
    assertEquals(chamadas.length, 1);
    assertEquals(chamadas[0].url, URL_DA_EDGE);
    assertEquals(chamadas[0].init?.method, "POST");
    assertEquals((chamadas[0].init?.headers as Record<string, string>).Authorization, "Bearer chave-de-servico-de-teste");
    const ontem = dataDaConsulta("ontem");
    assertEquals(chamadas[0].json, {
      acao: "completar", phone: DONO_FONE, autor: DONO_ID, cmp: 1, valor: "235.97", data: ontem, os: 112, destino: "os",
      tipo_na_os: "despesa", forma: "credito", quem_pagou: "tecnico", categoria: "combustível", tecnico: "Roberto",
      observacao: "cupom sem o gasto complementar; vale o do cartão",
    });
    // o número do modelo (235.97) e "235,97" dão o mesmo; "cmp 1" e "1" também; destino "os" sem número não é erro
    await completarTool.execute({ cmp: "cmp 1", valor: 235.97, destino: "os" }, ctxDoDono());
    assertEquals(chamadas[1].json, { acao: "completar", phone: DONO_FONE, autor: DONO_ID, cmp: 1, valor: "235.97", destino: "os" });
    assertEquals(valorDoCompletar("235,97"), "235.97");
    assertEquals(valorDoCompletar(1234.5), "1234.50");
    assertEquals(valorDoCompletar("1.234,56"), "1234.56");
    assertEquals(numeroDaOsDita("OS-00112"), 112);
    assertEquals(numeroDaOsDita(112), 112);
    assertEquals(numeroDaOsDita("ORÇ 112"), 112);
  });
});

// A (12/10/2026): a observação fica guardada no CMP — sozinha também é pedido.
Deno.test("completar_comprovante: só a observação chama a edge (ela fica guardada no CMP); o CMP como ficou traz a observação", async () => {
  await comFetch(respostaDaEdge({ ...ENVIADA, aplicados: ["obs"], anotado: ["a observação"] }), async (chamadas) => {
    const r = await completarTool.execute({ cmp: "1", observacao: " complemento de R$ 31,10\nsem cupom " }, ctxDoDono()) as Record<string, unknown>;
    assertEquals(chamadas.length, 1);
    assertEquals(chamadas[0].json, {
      acao: "completar", phone: DONO_FONE, autor: DONO_ID, cmp: 1, observacao: "complemento de R$ 31,10 sem cupom",
    });
    assertEquals(r.ok, true);
    assertEquals(r.anotado, ["a observação"]);
    assertEquals((r.como_ficou as { observacao?: unknown }).observacao, "o do cartão");
  });
});

Deno.test("completar_comprovante: os 4 desfechos — falou ao dono (só aqui ja_falou_ao_dono), ocupado, envio que falhou e as recusas", async () => {
  // 1) o fluxo mandou a pergunta: o turno termina nela
  await comFetch(respostaDaEdge(ENVIADA), async () => {
    const r = await completarTool.execute({ cmp: "1", valor: 235.97, categoria: "combustível", observacao: "o do cartão" }, ctxDoDono()) as Record<string, unknown>;
    assertEquals(r.ok, true);
    assertEquals(r.cmp, "CMP-00001");
    assertEquals(r.ja_falou_ao_dono, true);
    assertEquals(r.anotado, ENVIADA.anotado);
    assertEquals(r.proximo_passo, "para_que");
    assertStringIncludes(String(r.instruction), "Não repita a pergunta nem o resumo e não peça o sim");
    assertEquals(sem(r.texto_ao_dono),
      "Anotei no CMP-00001: categoria Combustível e deslocamento, valor R$ 235,97 (no comprovante: R$ 204,87). A próxima pergunta dele foi para o seu WhatsApp; só o seu *sim* ao resumo grava.");
    assertEquals(fluxoQueFalou(COMPLETAR_COMPROVANTE, r), { codigo: "CMP-00001" });
  });
  // 2) ocupado: anotou, a pergunta vai depois
  await comFetch(respostaDaEdge({ ...ENVIADA, enviada: false, ocupado: true, ocupado_por: "Enviar PDF", passo: null }), async () => {
    const r = await completarTool.execute({ cmp: "1", categoria: "combustível" }, ctxDoDono()) as Record<string, unknown>;
    assertEquals(r.ja_falou_ao_dono, false);
    assertEquals(r.instruction, 'Diga numa linha: "Anotei no CMP-00001. A pergunta dele vai depois que você responder: Enviar PDF."');
    assertEquals(fluxoQueFalou(COMPLETAR_COMPROVANTE, r), null);
  });
  // 3) o envio falhou
  await comFetch(respostaDaEdge({ ...ENVIADA, enviada: false, passo: "para_que" }), async () => {
    const r = await completarTool.execute({ cmp: "1", categoria: "combustível" }, ctxDoDono()) as Record<string, unknown>;
    assertEquals(r.ja_falou_ao_dono, false);
    assertEquals(r.instruction, 'Diga numa linha: "Anotei no CMP-00001, mas a pergunta dele não saiu agora: mande *cmp 1* para vê-la."');
  });
  // 4) as recusas viram o texto da tabela 2.2.6
  const recusas: Array<[Record<string, unknown>, string]> = [
    [{ ok: false, motivo: "nao_e_o_dono" }, "Só o dono completa os comprovantes dele."],
    [{ ok: false, motivo: "desligada" }, "A conversa dos comprovantes está desligada: não há como completar o CMP por aqui."],
    [{ ok: false, motivo: "modo_de_teste" }, "O WhatsApp está em modo de teste: a pergunta do CMP iria para o número de teste. Não completei."],
    [{ ok: false, motivo: "nao_existe" }, "Não achei o CMP-00001."],
    [{ ok: false, motivo: "ja_gravado", codigo: "CMP-00001" }, "O CMP-00001 já foi gravado: para mudar, o dono manda *cancelar cmp 1 motivo* e o arquivo de novo."],
    [{ ok: false, motivo: "ja_cancelado", codigo: "CMP-00001" }, "O CMP-00001 foi cancelado."],
    [{ ok: false, motivo: "fora_da_conversa", codigo: "CMP-00001" },
      "O CMP-00001 ainda não está na conversa (o arquivo pode estar sendo lido): não anotei nada. Tente de novo daqui a pouco."],
    [{ ok: false, motivo: "observacao_obrigatoria", valor_lido: "204.87" },
      "O valor R$ 235,97 é diferente do lido no comprovante (R$ 204,87). Passe em observacao o porquê, como o dono disse; se ele não disse, pergunte."],
    [{ ok: false, motivo: "data_futura" }, "A data não pode ser futura."],
    // 12/10/2026: tudo ou nada — a recusa de um campo desfaz o resto
    [{ ok: true, codigo: "CMP-00001", aplicados: [], ignorados: [], anotado: [], enviada: false, recusado: { campo: "os", motivo: "os_nao_existe", texto: "OS-00999 (não achei essa OS)" } },
      "Não usei OS-00999 (não achei essa OS): nada foi anotado no CMP-00001 (é tudo ou nada: nem o resto do que você passou). " +
      "Corrija ou tire esse campo e chame de novo."],
  ];
  for (const [edge, erro] of recusas) {
    await comFetch(respostaDaEdge(edge), async () => {
      const r = await completarTool.execute({ cmp: "1", valor: 235.97 }, ctxDoDono()) as { error?: string; ja_falou_ao_dono?: boolean };
      assertEquals(sem(r.error), erro);
      assertEquals(r.ja_falou_ao_dono, undefined);
    });
  }
  // recusado com algo anotado: ok, com a linha "Não usei" (a mensagem do fluxo também diz)
  await comFetch(respostaDaEdge({ ...ENVIADA, recusado: { campo: "os", motivo: "os_nao_existe", texto: "OS-00999 (não achei essa OS)" } }), async () => {
    const r = await completarTool.execute({ cmp: "1", categoria: "almoço", os: "999" }, ctxDoDono()) as Record<string, unknown>;
    assertEquals(r.ok, true);
    assertEquals(r.nao_usei, "OS-00999 (não achei essa OS)");
    assertEquals(r.ja_falou_ao_dono, true);
  });
  // nada anotado, mas algo ignorado (o passo dele não chegou): nunca "já estava assim" (revisão de 11/10/2026)
  const soIgnorado = { ...ENVIADA, aplicados: [], anotado: [], ignorados: ["tipo_na_os", "destino"] };
  await comFetch(respostaDaEdge(soIgnorado), async () => {
    const r = await completarTool.execute({ cmp: "1", destino: "os", tipo_na_os: "despesa" }, ctxDoDono()) as Record<string, unknown>;
    assertEquals(r.ja_falou_ao_dono, true);
    assert(String(r.texto_ao_dono).startsWith("Ainda não anotei nada no CMP-00001 (o sistema pergunta na sequência)."), String(r.texto_ao_dono));
  });
  await comFetch(respostaDaEdge({ ...soIgnorado, enviada: false, passo: null }), async () => {
    const r = await completarTool.execute({ cmp: "1", destino: "os", tipo_na_os: "despesa" }, ctxDoDono()) as Record<string, unknown>;
    assertEquals(String(r.instruction).includes("já estava assim"), false, String(r.instruction));
  });
});

Deno.test("completar_comprovante: HTTP ≠ 200, rede ou tempo esgotado → 'não chame de novo'", async () => {
  for (const resposta of [respostaDaEdge({ ok: false, erro: "x" }, 500), respostaDaEdge({ ok: false, motivo: "entrada_invalida" }, 422), () => Promise.reject(new DOMException("tempo", "TimeoutError"))]) {
    await comFetch(resposta as () => Promise<Response>, async () => {
      const r = await completarTool.execute({ cmp: "1", valor: 235.97, observacao: "x" }, ctxDoDono()) as { error?: string };
      assertStringIncludes(String(r.error), "Não chame de novo");
      assertStringIncludes(String(r.error), "consultar_comprovantes");
    });
  }
});

Deno.test("fluxoQueFalou: só esta tool e só com ja_falou_ao_dono === true", () => {
  assertEquals(fluxoQueFalou(COMPLETAR_COMPROVANTE, { ja_falou_ao_dono: true, cmp: "CMP-00001" }), { codigo: "CMP-00001" });
  assertEquals(fluxoQueFalou(COMPLETAR_COMPROVANTE, { ja_falou_ao_dono: false, cmp: "CMP-00001" }), null);
  assertEquals(fluxoQueFalou(COMPLETAR_COMPROVANTE, { ja_falou_ao_dono: "true" }), null);
  assertEquals(fluxoQueFalou(COMPLETAR_COMPROVANTE, { error: "x" }), null);
  assertEquals(fluxoQueFalou(COMPLETAR_COMPROVANTE, null), null);
  assertEquals(fluxoQueFalou("consultar_comprovantes", { ja_falou_ao_dono: true, cmp: "CMP-00001" }), null);
});

// ─── o caso real, de ponta a ponta: a frase do dono → a tool → a edge → o fluxo ──────────────
// A edge roda de verdade (criarHandler + completar/responder), contra um banco SIMULADO do CMP-00001
// que segue as regras das RPCs (passo seguinte, pergunta única por telefone, o sim só com a mensagem
// do dono). O que se prova: a tool não grava nada; o fluxo pergunta "Para quê?"; o dono responde 8 e
// 3; o resumo mostra R$ 235,97 (no comprovante: R$ 204,87) e a categoria Combustível; nada é gravado
// antes do "sim"; o "sim" grava.

function bancoSimuladoDoCmp00001() {
  const cmp = {
    id: "22222222-0000-4000-8000-000000000001", codigo: "CMP-00001", numero: 1, phone_normalized: DONO_FONE, situacao: "aguardando_vez", modo: "dono",
    gravado_em: null as string | null, tipo: "nfce", valor: 204.87, valor_confirmado: 204.87, data_confirmada: "2026-10-11", destino: null as string | null,
    destino_os_id: null, categoria: null as string | null, forma_confirmada: null as string | null, quem_pagou: null, tipo_na_os: null, resumo_versao: 0,
    observacao: null as string | null,
  };
  const OPCOES_PARA_QUE = [
    { n: 1, rotulo: "OS-00112 · Brisa", valor: "os:o1" }, { n: 2, rotulo: "OS-00118 · Dona V", valor: "os:o2" }, { n: 3, rotulo: "OS-00120 · Madu", valor: "os:o3" },
    { n: 4, rotulo: "OS-00121 · Bora", valor: "os:o4" }, { n: 5, rotulo: "OS-00122 · Lua", valor: "os:o5" }, { n: 6, rotulo: "Estoque", valor: "estoque" },
    { n: 7, rotulo: "Insumo", valor: "insumo" }, { n: 8, rotulo: "Empresa (sem OS)", valor: "empresa" }, { n: 9, rotulo: "Pessoal", valor: "pessoal" },
  ];
  const OPCOES_FORMA = ["pix", "debito", "credito", "dinheiro", "boleto", "transferencia"]
    .map((v, i) => ({ n: i + 1, rotulo: ["Pix", "Débito", "Crédito", "Dinheiro", "Boleto", "Transferência"][i], valor: v }));
  const CATEGORIAS = ["Combustível e deslocamento", "Alimentação de campo", "Outras despesas"];
  type Pergunta = { id: string; passo: string; opcoes: Array<{ n: number; rotulo: string; valor: string }>; status: string; enviada: boolean; versao: number };
  const perguntas: Pergunta[] = [];
  const rpcsChamadas: string[] = [];
  let gravacoes = 0;
  const mensagens = [
    { id: "m-1", texto: "8" }, { id: "m-2", texto: "3" }, { id: "m-3", texto: "sim" },
  ].map((m) => ({ id: `11111111-0000-4000-8000-00000000000${m.id.slice(2)}`, wa_message_id: `WA-${m.id}`, phone_normalized: DONO_FONE, message_type: "text", direction: "inbound", occurred_at: "2026-10-11T23:00:00Z", raw_payload: {} }));

  const passoSeguinte = () => !cmp.destino ? "para_que" : !cmp.forma_confirmada ? "como_pagou" : !cmp.categoria ? "categoria" : "confirmar";
  const opcoes = (passo: string) => passo === "para_que" ? OPCOES_PARA_QUE : passo === "como_pagou" ? OPCOES_FORMA : [];
  const resumo = () => ({
    id: cmp.id, codigo: cmp.codigo, numero: cmp.numero, situacao: cmp.situacao, tipo: cmp.tipo, valor: cmp.valor_confirmado.toFixed(2),
    valor_lido: cmp.valor.toFixed(2), valor_confianca: "alta", data: cmp.data_confirmada, data_origem: "leitura", hora: "18:13:00",
    forma: cmp.forma_confirmada, fornecedor: "Auto Posto Exemplo", fornecedor_origem: "cadastro", cnpj: null, destino: cmp.destino, os: null,
    tipo_na_os: null, quem_pagou: null, pagador_nome: null, categoria: cmp.categoria, pendencias: [], gravado_em: cmp.gravado_em,
    observacao: cmp.observacao,
  });
  const aberta = () => perguntas.find((p) => p.status === "aberta") ?? null;
  const abrir = () => {
    const velha = aberta();
    if (velha) velha.status = "substituida";
    const passo = passoSeguinte();
    const p: Pergunta = { id: `44444444-0000-4000-8000-00000000010${perguntas.length}`, passo, opcoes: opcoes(passo), status: "aberta", enviada: false, versao: cmp.resumo_versao };
    perguntas.push(p);
    cmp.situacao = passo === "confirmar" ? "aguardando_sim" : "perguntando";
    return {
      pergunta_id: p.id, dedupe_key: `cmp:p:${p.id}`, cmp: resumo(), passo, opcoes: p.opcoes, posicao: 1, total: 1, primeira_do_lote: null,
      retomada: false, avisos: [], versao: p.versao, pasta: "COMPROVANTES/2026/2026-10",
      plano: passo === "confirmar" ? { efeitos: [{ tipo: "anotar", forma: cmp.forma_confirmada, categoria: cmp.categoria }], avisos: [] } : null,
    };
  };
  const rpcs: Record<string, (a: Record<string, any>) => unknown> = {
    comprovante_comando: ({ p }) => {
      if (p.comando === "cmp") return { resultado: "pergunta", pergunta: abrir() };
      let corrigido: Record<string, unknown> | null = null;
      if (p.campo === "categoria") {
        if (!CATEGORIAS.includes(p.categoria)) return { resultado: "invalida", codigo: cmp.codigo, motivo: "categoria_nao_achada" };
        cmp.categoria = p.categoria;
        corrigido = { campo: "categoria", valor: p.categoria };
      } else if (p.campo === "valor") {
        cmp.valor_confirmado = Number(p.valor);
        corrigido = { campo: "valor", valor: p.valor };
      } else if (p.campo === "obs") {
        cmp.observacao = p.observacao ?? null;
        corrigido = { campo: "obs", valor: cmp.observacao };
      } else if (p.campo === "os") {
        return { resultado: "invalida", codigo: cmp.codigo, motivo: "os_nao_existe" };
      } else throw new Error(`campo inesperado: ${p.campo}`);
      cmp.resumo_versao++;
      return { resultado: "pergunta", codigo: cmp.codigo, corrigido, pergunta: abrir() };
    },
    // A RPC única (12/10/2026): as recusas antes de escrever, as correções na ordem fixa pelo comando
    // e TUDO OU NADA — a recusa no meio devolve o CMP e as perguntas ao retrato de antes do bloco.
    comprovante_completar: ({ p }) => {
      if (p.phone !== DONO_FONE || p.autor !== DONO_ID) return { resultado: "nao_e_o_dono" };
      if (p.cmp !== cmp.numero) return { resultado: "nao_existe" };
      if (cmp.gravado_em) return { resultado: "ja_gravado", codigo: cmp.codigo };
      const lido = cmp.valor.toFixed(2);
      if (p.valor && Math.abs(Number(p.valor) - cmp.valor) > 0.01 && Math.abs(Number(p.valor) - cmp.valor_confirmado) > 0.01 && !p.observacao && !cmp.observacao) {
        return { resultado: "observacao_obrigatoria", codigo: cmp.codigo, valor_lido: lido };
      }
      const retrato = { cmp: { ...cmp }, perguntas: perguntas.map((x) => ({ ...x })) };
      const aplicados: string[] = [];
      const itens: Array<Record<string, unknown>> = [];
      let pergunta: unknown = null;
      const pedidos: Array<[string, Record<string, unknown>]> = [];
      if (p.categoria && p.categoria !== cmp.categoria) pedidos.push(["categoria", { categoria: p.categoria }]);
      if (p.os) pedidos.push(["os", { numero: p.os }]);
      if (p.valor && Math.abs(Number(p.valor) - cmp.valor_confirmado) > 0.001) pedidos.push(["valor", { valor: p.valor }]);
      if (p.observacao && p.observacao !== cmp.observacao) pedidos.push(["obs", { observacao: p.observacao }]);
      for (const [campo, extra] of pedidos) {
        const r = rpcs.comprovante_comando({ p: { phone: p.phone, message_id: null, comando: "corrigir", cmp: p.cmp, campo, ...extra } }) as Record<string, any>;
        if (r.resultado !== "pergunta") {
          Object.assign(cmp, retrato.cmp);
          perguntas.splice(0, perguntas.length, ...retrato.perguntas);
          return {
            resultado: "recusado", id: cmp.id, codigo: cmp.codigo, valor_lido: lido, aplicados: [], ja_estava: [],
            ignorados: pedidos.map(([c]) => c).filter((c) => c !== campo), itens: [], recusado: { campo, motivo: r.motivo, passo: null },
            pergunta: null, ocupado: false, ocupado_por: null, desconhecido: null,
          };
        }
        aplicados.push(campo);
        itens.push({ campo, valor: r.corrigido.valor, ...(campo === "valor" ? { lido } : {}) });
        pergunta = r.pergunta;
      }
      return {
        resultado: "ok", id: cmp.id, codigo: cmp.codigo, valor_lido: lido, aplicados, ja_estava: [], ignorados: [], itens, recusado: null,
        pergunta, ocupado: false, ocupado_por: null, desconhecido: null,
      };
    },
    comprovante_responder: ({ p }) => {
      const w = perguntas.find((x) => x.id === p.pergunta_id)!;
      const i = p.interpretacao;
      const val = i.tipo === "opcao" ? w.opcoes.find((o) => o.n === i.n)?.valor : i.valor;
      if (w.passo === "confirmar") {
        // o sim só vale com a mensagem do dono (o banco recusa o sim sem mensagem)
        if (i.tipo !== "sim" || !p.message_id) return { resultado: "invalida", cmp: resumo(), motivo: "resposta_anterior_a_pergunta", proxima: null };
        gravacoes++;
        cmp.gravado_em = "2026-10-11T23:05:00Z";
        cmp.situacao = "gravado";
        w.status = "respondida";
        return { resultado: "gravado", cmp: resumo(), proxima: null, gravacao: { situacao: "gravado", efeitos: [], avisos: [], mensagens: [], mes: null }, motivo: null };
      }
      if (w.passo === "para_que") cmp.destino = String(val);
      else if (w.passo === "como_pagou") cmp.forma_confirmada = String(val);
      else throw new Error(`passo inesperado: ${w.passo}`);
      cmp.resumo_versao++;
      w.status = "respondida";
      const proxima = abrir();
      return { resultado: proxima.passo === "confirmar" ? "resumo" : "proximo", cmp: resumo(), proxima, motivo: null };
    },
    pergunta_marcar_enviada: ({ p_id }) => {
      const w = perguntas.find((x) => x.id === p_id);
      if (w) w.enviada = true;
      return null;
    },
    pergunta_rotear: () => {
      const a = aberta();
      return {
        conversa: true, dono: true, citada: null, pendencia: null, cmp_em_contexto: null,
        ativa: a
          ? { id: a.id, origem: "comprovante", tipo: "pergunta", referencia_id: cmp.id, referencia_codigo: cmp.codigo, passo: a.passo, opcoes: a.opcoes, wa_message_id: "WA-P", aberta_em: "2026-10-11T22:50:00Z", enviada_em: a.enviada ? "2026-10-11T22:50:01Z" : null }
          : null,
      };
    },
    comprovante_destino_do_arquivo: () => null,
  };
  const tabelas: Record<string, Array<Record<string, unknown>>> = {
    app_users: [{ id: DONO_ID, phone_normalized: DONO_FONE, role: "admin", active: true, ai_whatsapp_enabled: true, created_at: "2025-01-01" }],
    app_settings: [{ key: "comprovante_fluxo", value: "dono" }, { key: "comprovante_conversa", value: "on" }],
    comprovantes: [cmp as unknown as Record<string, unknown>],
    whatsapp_messages: mensagens,
    ai_operator_messages: [],
  };
  const admin = {
    rpc(nome: string, args: Record<string, any>) {
      rpcsChamadas.push(nome);
      const f = rpcs[nome];
      if (!f) return Promise.resolve({ data: null, error: { code: "PGRST202", message: `sem dublê para ${nome}` } });
      try {
        return Promise.resolve({ data: f(args), error: null });
      } catch (e) {
        return Promise.reject(e);
      }
    },
    from(tabela: string) {
      let linhas = [...(tabelas[tabela] ?? [])];
      const q: Record<string, any> = {
        select: () => q,
        eq: (c: string, v: unknown) => { linhas = linhas.filter((l) => l[c] === v); return q; },
        in: (c: string, vs: unknown[]) => { linhas = linhas.filter((l) => vs.includes(l[c])); return q; },
        not: (c: string) => { linhas = linhas.filter((l) => l[c] != null); return q; },
        order: () => q,
        limit: (n: number) => { linhas = linhas.slice(0, n); return q; },
        maybeSingle: () => Promise.resolve({ data: linhas[0] ? { ...linhas[0] } : null, error: null }),
        insert: (novas: unknown) => {
          (tabelas[tabela] ??= []).push(...(Array.isArray(novas) ? novas : [novas]) as Array<Record<string, unknown>>);
          return Promise.resolve({ data: null, error: null });
        },
        update: () => ({ eq: () => Promise.resolve({ data: null, error: null }) }),
        then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: linhas, error: null }).then(ok),
      };
      return q;
    },
  };
  return { admin, cmp, perguntas, rpcsChamadas, mensagens, gravacoes: () => gravacoes };
}

Deno.test("o caso real de 11/10 de ponta a ponta: 'pode registrar pelo valor do cartão, é combustível' → a tool → o fluxo pergunta; o resumo traz R$ 235,97 e Combustível; nada grava antes do SIM", async () => {
  const banco = bancoSimuladoDoCmp00001();
  const aoDono: Array<{ message: string; dedupe_key: string }> = [];
  const fundo: Promise<unknown>[] = [];
  const deps: DependenciasDoFluxo = {
    admin: banco.admin,
    whatsapp: null,
    dropbox: () => Promise.resolve(null),
    fetch: ((url: string, init?: RequestInit) => {
      if (String(url).endsWith("/functions/v1/whatsapp-send")) aoDono.push(JSON.parse(String(init?.body)));
      return Promise.resolve(new Response(JSON.stringify({ success: true, messageId: `WA-OUT-${aoDono.length}` }), { status: 200 }));
    }) as typeof fetch,
    agora: () => new Date("2026-10-11T22:47:00Z"),
    log: () => {},
    supabaseUrl: "https://ref.supabase.co",
    serviceRoleKey: "chave-de-servico-de-teste",
    internalSecret: "x",
    waitUntil: (p) => fundo.push(p),
    sessaoDoWhatsApp: () => Promise.resolve("sessao-1"),
  };
  const edge = criarHandler(() => deps);
  const ctx = { sb: banco.admin, admin: banco.admin, userId: DONO_ID, userRole: "admin", jwt: "", appOrigin: "", settings: LIGADA } as never;

  // 1) o modelo passa à tool só o que o dono disse (a tool vai à edge de verdade)
  const r = await comFetch((url, init) => url === URL_DA_EDGE ? edge(new Request(url, init)) : new Response("{}", { status: 404 }), () =>
    completarTool.execute({
      cmp: "CMP-00001", valor: 235.97, categoria: "combustível",
      observacao: "cupom sem o gasto complementar de R$ 31,10; vale o valor do cartão",
    }, ctx)) as Record<string, unknown>;
  assertEquals(r.ok, true);
  assertEquals(r.ja_falou_ao_dono, true);
  assertEquals(fluxoQueFalou(COMPLETAR_COMPROVANTE, r), { codigo: "CMP-00001" });
  assertEquals(banco.cmp.valor_confirmado, 235.97);
  assertEquals(banco.cmp.categoria, "Combustível e deslocamento");
  // 12/10/2026: a observação fica guardada no CMP, por UMA chamada à RPC única
  assertEquals(banco.cmp.observacao, "cupom sem o gasto complementar de R$ 31,10; vale o valor do cartão");
  assertEquals(banco.rpcsChamadas.filter((n) => n === "comprovante_completar").length, 1);
  assertEquals(banco.rpcsChamadas.filter((n) => n === "comprovante_comando" || n === "comprovante_responder").length, 0);
  assertEquals(banco.gravacoes(), 0);
  assertEquals(banco.cmp.gravado_em, null);
  // UMA mensagem do fluxo: "anotei…", a observação e o "Para quê?" com as 9 opções; só a última pergunta foi enviada
  assertEquals(aoDono.length, 1);
  const primeira = sem(aoDono[0].message);
  assert(
    primeira.startsWith(
      "CMP-00001: anotei o que você disse na conversa: categoria Combustível e deslocamento, valor R$ 235,97 (no comprovante: R$ 204,87). " +
        "Observação: cupom sem o gasto complementar de R$ 31,10; vale o valor do cartão.",
    ),
    primeira,
  );
  assertStringIncludes(primeira, "Para quê?\n1 OS-00112 · Brisa");
  assertStringIncludes(primeira, "9 Pessoal");
  assertEquals(banco.perguntas.map((p) => [p.status, p.enviada]), [["substituida", false], ["substituida", false], ["aberta", true]]);

  // 2) o dono segue no fluxo: "8" (Empresa) → "Como foi pago?"; "3" (Crédito) → o resumo
  const responde = async (i: number, texto: string) =>
    await (await edge(new Request(URL_DA_EDGE, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer chave-de-servico-de-teste" },
      body: JSON.stringify({ acao: "responder", message_id: banco.mensagens[i].id, phone: DONO_FONE, texto, citado: null, destino: "comprovante" }),
    }))).json();
  const chaveAntes = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico-de-teste");
  try {
    assertEquals(await responde(0, "8"), { tratada: true, resultado: "proximo" });
    assertStringIncludes(aoDono[1].message, "Como foi pago?\n1 Pix\n2 Débito\n3 Crédito");
    assertEquals(await responde(1, "3"), { tratada: true, resultado: "resumo" });
    const resumo = sem(aoDono[2].message);
    assertStringIncludes(resumo, "CMP-00001 · confira antes de gravar:");
    assertStringIncludes(resumo, "• R$ 235,97 (no comprovante: R$ 204,87) em 11/10");
    assertStringIncludes(resumo, "• Para: empresa (sem OS) · Combustível e deslocamento");
    // a observação faz parte do que o sim aprova (vai à descrição do lançamento)
    assertStringIncludes(resumo, "\n• Observação: cupom sem o gasto complementar de R$ 31,10; vale o valor do cartão\n");
    assertStringIncludes(resumo, "Responda *sim* para gravar ou *não* para corrigir.");
    // até aqui: nada gravado (o resumo espera o sim do dono)
    assertEquals(banco.gravacoes(), 0);
    assertEquals(banco.cmp.gravado_em, null);
    assertEquals(banco.cmp.situacao, "aguardando_sim");

    // 3) o "sim" do dono grava
    assertEquals(await responde(2, "sim"), { tratada: true, resultado: "gravado" });
    assertEquals(banco.gravacoes(), 1);
    assert(aoDono[3].message.startsWith("CMP-00001 gravado"), aoDono[3].message);
    await Promise.all(fundo);
  } finally {
    if (chaveAntes === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", chaveAntes);
  }
  // a tool e o fluxo nunca responderam o resumo por conta própria
  assertEquals(banco.rpcsChamadas.filter((n) => n === "comprovante_responder").length, 3);
});

// 12/10/2026 (spec-observacao-atomica-prefixo.md, 3): a correção do assistente é tudo ou nada. Uma
// OS que não existe no meio do pedido não deixa a categoria nem o valor anotados, nada vai ao dono e
// a tool pede para corrigir ou tirar o campo.
Deno.test("tudo ou nada de ponta a ponta: a OS inexistente no meio → nada anotado no CMP-00001, nenhuma mensagem, a tool diz 'é tudo ou nada'", async () => {
  const banco = bancoSimuladoDoCmp00001();
  const aoDono: unknown[] = [];
  const deps: DependenciasDoFluxo = {
    admin: banco.admin,
    whatsapp: null,
    dropbox: () => Promise.resolve(null),
    fetch: ((url: string, init?: RequestInit) => {
      if (String(url).endsWith("/functions/v1/whatsapp-send")) aoDono.push(JSON.parse(String(init?.body)));
      return Promise.resolve(new Response(JSON.stringify({ success: true, messageId: "WA-OUT-1" }), { status: 200 }));
    }) as typeof fetch,
    agora: () => new Date("2026-10-11T22:47:00Z"),
    log: () => {},
    supabaseUrl: "https://ref.supabase.co",
    serviceRoleKey: "chave-de-servico-de-teste",
    internalSecret: "x",
    waitUntil: () => {},
    sessaoDoWhatsApp: () => Promise.resolve("sessao-1"),
  };
  const edge = criarHandler(() => deps);
  const ctx = { sb: banco.admin, admin: banco.admin, userId: DONO_ID, userRole: "admin", jwt: "", appOrigin: "", settings: LIGADA } as never;
  const r = await comFetch((url, init) => url === URL_DA_EDGE ? edge(new Request(url, init)) : new Response("{}", { status: 404 }), () =>
    completarTool.execute({ cmp: "1", categoria: "combustível", os: "OS-00999", valor: 235.97, observacao: "o do cartão" }, ctx)) as Record<string, unknown>;
  assertEquals(
    sem(r.error),
    "Não usei OS-00999 (não achei essa OS): nada foi anotado no CMP-00001 (é tudo ou nada: nem o resto do que você passou). " +
      "Corrija ou tire esse campo e chame de novo.",
  );
  assertEquals(r.ja_falou_ao_dono, undefined);
  // o CMP ficou como estava: nem a categoria (aplicada antes da OS) nem o valor nem a observação
  assertEquals([banco.cmp.categoria, banco.cmp.valor_confirmado, banco.cmp.observacao, banco.cmp.resumo_versao], [null, 204.87, null, 0]);
  assertEquals(banco.perguntas.length, 0);
  assertEquals(aoDono.length, 0);
});
