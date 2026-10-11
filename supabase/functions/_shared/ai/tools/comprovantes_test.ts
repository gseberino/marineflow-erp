import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  autorDaConsulta, codigoDoCmp, comprovantesJaLancados, comprovantesParecidos, comprovanteTools, conferirComprovantes,
  dataDaConsulta, gravadoComEfeito, primeiroAberto, textoDaDespesaCobradaComCmpAberto, textoDaDespesaComCmpAberto,
  textoDaDespesaDoCmpNaoSai, textoDaDespesaInternaDoCmp, textoDaDespesaJaLancada, textoDoAberto, textoDoJaLancado,
} from "./comprovantes.ts";
import { ehLeituraPeloNome, rodaDiretoPelaRede, SO_PELA_REDE } from "../perfil-operacao.ts";
import { allTools } from "./index.ts";

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
