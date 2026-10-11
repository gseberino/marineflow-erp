import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseMinutes, soOpsTools } from "./so-ops.ts";

/* Duração chega como o técnico fala, não como formulário aceita. Errar aqui grava
   hora errada na OS e o erro vira dinheiro: hora cobrável entra no total. */
Deno.test("parseMinutes: entende como se fala hora no campo", () => {
  // horas cheias
  assertEquals(parseMinutes("2h"), 120);
  assertEquals(parseMinutes("2hs"), 120);
  assertEquals(parseMinutes("2horas"), 120);
  // hora com minuto — as duas grafias que aparecem
  assertEquals(parseMinutes("1h30"), 90);
  assertEquals(parseMinutes("1h30min"), 90);
  assertEquals(parseMinutes("1:30"), 90);
  // meia hora escrita como fração
  assertEquals(parseMinutes("1,5h"), 90);
  assertEquals(parseMinutes("1.5h"), 90);
  // minutos
  assertEquals(parseMinutes("45min"), 45);
  assertEquals(parseMinutes("45m"), 45);
  assertEquals(parseMinutes("90"), 90);
  // com espaços e maiúscula
  assertEquals(parseMinutes(" 2 H "), 120);
  // número direto
  assertEquals(parseMinutes(30), 30);
});

Deno.test("parseMinutes: recusa o que não dá para afirmar", () => {
  // Devolver null faz a tool PERGUNTAR em vez de gravar um chute — hora inventada
  // vira cobrança indevida.
  assertEquals(parseMinutes("um pouco"), null);
  assertEquals(parseMinutes(""), null);
  assertEquals(parseMinutes(null), null);
  assertEquals(parseMinutes(undefined), null);
  assertEquals(parseMinutes(0), null);
  assertEquals(parseMinutes(-5), null);
  assertEquals(parseMinutes("a tarde toda"), null);
});

// ─── Comprovantes (F2, 11/10/2026): despesa da OS não entra em dobro ─────────────────────────
// add_service_order_expense executa SEM "sim" (risco low): a trava mora no execute. Ajustes do dono:
// o comprovante nunca aparece para o cliente — só o que é lançado à mão ou pelo assistente. CMP que
// comprovou a despesa que já está na OS (anexar_despesa) → recusa; CMP que gravou o custo INTERNO
// (despesa_os) → a despesa COBRADA lança e diz que o CMP é só interno (a por conta da casa recusa); CMP
// aberto do mesmo valor (só com a conversa ligada) → a cobrada lança e diz que o CMP vai só comprová-la;
// a por conta da casa pede para completar o CMP, a não ser que o dono diga "mesmo assim".
// comprovantes_parecidos (admin) e comprovantes_ja_lancados (financeiro, só o booleano) são dublês com a
// forma da spec.

const sem = (s: unknown) => String(s).replace(/\u00a0/g, " ");
const despesa = soOpsTools.find((t) => t.name === "add_service_order_expense")!;

/** A conversa dos comprovantes ligada: só assim um CMP aberto segura a despesa. */
const LIGADA = { comprovante_fluxo: "dono", comprovante_conversa: "on" };

function ctxDaOs(
  parecidos: Record<string, unknown> | Error,
  opcoes: {
    cargo?: string; userId?: string; settings?: Record<string, string>; jaLancados?: Record<string, unknown>;
    despesas?: Record<string, Record<string, unknown>>;
  } = {},
) {
  const chamadas: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const rpc = (fn: string, args: Record<string, unknown>) => {
    chamadas.push({ fn, args });
    if (fn === "comprovantes_parecidos") {
      return parecidos instanceof Error ? Promise.reject(parecidos) : Promise.resolve({ data: parecidos, error: null });
    }
    if (fn === "comprovantes_ja_lancados") return Promise.resolve({ data: opcoes.jaLancados ?? null, error: null });
    return Promise.resolve({ data: { id: "desp-1", grand_total: 1062 }, error: null });
  };
  // remove_service_order_expense lê a origem da despesa antes de apagar
  const from = (tabela: string) => ({
    select: () => ({
      eq: (_col: string, id: string) => ({
        maybeSingle: () => {
          chamadas.push({ fn: `from:${tabela}`, args: { id } });
          return Promise.resolve({ data: opcoes.despesas?.[id] ?? null, error: null });
        },
      }),
    }),
  });
  const c = { rpc, from };
  return {
    ctx: {
      sb: c, admin: c, userId: opcoes.userId ?? "u-dono", userRole: opcoes.cargo ?? "admin", jwt: "", appOrigin: "",
      settings: opcoes.settings ?? LIGADA,
    } as never,
    chamadas,
  };
}

const PEDIDO = { service_order_id: "os-112", description: "gasolina", amount: 62, expense_date: "2026-10-10" };

const COM_CMP = (efeito: string) => ({
  abertos: [], gravados: [{ codigo: "CMP-00123", numero: 123, valor: "62.00", data: "2026-10-10", os_id: "os-112", efeitos: [efeito] }],
});

Deno.test("despesa da OS: CMP que comprovou a despesa que já está na OS → recusa, sem so_expense_add", async () => {
  for (const pedido of [PEDIDO, { ...PEDIDO, billable: false }]) {
    const { ctx, chamadas } = ctxDaOs(COM_CMP("anexar_despesa"));
    const r = await despesa.execute(pedido, ctx) as { error?: string; nada_registrado?: boolean };
    assertEquals(sem(r.error), "Já lançado pelo CMP-00123 (R$ 62,00 em 10/10) nesta OS.");
    assertEquals(r.nada_registrado, true);
    assertEquals(chamadas.map((c) => c.fn), ["comprovantes_parecidos"]);
    assertEquals(chamadas[0].args, { p_valor: 62, p_data: "2026-10-10", p_os: "os-112", p_autor: "u-dono" });
  }
});

// Revisão dos ajustes do dono (11/10/2026): o cupom que virou custo interno não impede cobrar o cliente.
Deno.test("despesa da OS: CMP com o custo interno → a cobrada lança e diz que o CMP é só interno; a por conta da casa recusa", async () => {
  const cobrada = ctxDaOs(COM_CMP("despesa_os"));
  const r = await despesa.execute(PEDIDO, cobrada.ctx) as { ok?: boolean; faturavel?: boolean; aviso?: string };
  assertEquals(r.ok, true);
  assertEquals(r.faturavel, true);
  assertEquals(cobrada.chamadas.map((c) => c.fn), ["comprovantes_parecidos", "so_expense_add"]);
  assertEquals(cobrada.chamadas[1].args.p_billable, true);
  assertEquals(
    sem(r.aviso),
    "O CMP-00123 (R$ 62,00 em 10/10) é só custo interno desta OS (não aparece para o cliente); lancei a despesa cobrada do cliente. " +
      "No Lucro por OS a compra conta uma vez só.",
  );
  const casa = ctxDaOs(COM_CMP("despesa_os"));
  const rc = await despesa.execute({ ...PEDIDO, billable: false, mesmo_assim: true }, casa.ctx) as { error?: string; nada_registrado?: boolean };
  assertEquals(sem(rc.error), "Já lançado pelo CMP-00123 (R$ 62,00 em 10/10) nesta OS.");
  assertEquals(rc.nada_registrado, true);
  assertEquals(casa.chamadas.some((c) => c.fn === "so_expense_add"), false);
});

Deno.test("despesa da OS: CMP aberto → a cobrada lança (o CMP só comprova); a por conta da casa pergunta, com mesmo_assim grava", async () => {
  const aberto = { abertos: [{ codigo: "CMP-00124", numero: 124, valor: "62.00", data: "2026-10-10" }], gravados: [] };
  const cobrada = ctxDaOs(aberto);
  const rc = await despesa.execute(PEDIDO, cobrada.ctx) as { ok?: boolean; aviso?: string };
  assertEquals(rc.ok, true);
  assertEquals(cobrada.chamadas.map((c) => c.fn), ["comprovantes_parecidos", "so_expense_add"]);
  assertEquals(
    sem(rc.aviso),
    "O CMP-00124 (R$ 62,00 em 10/10) ainda está aberto: ele só comprova, não cobra o cliente. Lancei esta despesa para o cliente; " +
      "quando você responder *cmp 124*, o comprovante comprova esta, sem lançar outra.",
  );

  const sem1 = ctxDaOs(aberto);
  const r = await despesa.execute({ ...PEDIDO, billable: false }, sem1.ctx) as { error?: string };
  assertEquals(
    sem(r.error),
    "Há o CMP-00124 aberto com R$ 62,00 em 10/10; completar o CMP? Responda *cmp 124*. Se for outro gasto, peça de novo dizendo 'mesmo assim'.",
  );
  assertEquals(sem1.chamadas.some((c) => c.fn === "so_expense_add"), false);

  const com = ctxDaOs(aberto);
  const ok = await despesa.execute({ ...PEDIDO, billable: false, mesmo_assim: true }, com.ctx) as { ok?: boolean; despesa_id?: string };
  assertEquals(ok.ok, true);
  assertEquals(com.chamadas.map((c) => c.fn), ["comprovantes_parecidos", "so_expense_add"]);
  assertEquals("mesmo_assim" in com.chamadas[1].args, false, "o argumento não vai à função do banco");
});

Deno.test("despesa da OS: mesmo_assim não fura o CMP já gravado; consulta que falha segue como antes", async () => {
  const gravado = ctxDaOs(COM_CMP("anexar_despesa"));
  const r = await despesa.execute({ ...PEDIDO, mesmo_assim: true }, gravado.ctx) as { error?: string };
  assertStringIncludes(String(r.error), "CMP-00123");
  // Gravado de outro tipo (só Caixa) não é despesa da OS: grava.
  const outro = ctxDaOs({ abertos: [], gravados: [{ codigo: "CMP-00123", valor: "62.00", data: "2026-10-10", efeitos: ["caixa"] }] });
  assertEquals((await despesa.execute(PEDIDO, outro.ctx) as { ok?: boolean }).ok, true);
  const falha = ctxDaOs(new Error("rede"));
  assertEquals((await despesa.execute(PEDIDO, falha.ctx) as { ok?: boolean }).ok, true);
  assertEquals(falha.chamadas.map((c) => c.fn), ["comprovantes_parecidos", "so_expense_add"]);
});

Deno.test("despesa da OS: sem expense_date ISO, a consulta vai sem data (o banco olha os últimos 3 dias)", async () => {
  const { ctx, chamadas } = ctxDaOs({ abertos: [], gravados: [] });
  await despesa.execute({ service_order_id: "os-112", description: "pedágio", amount: 12.5 }, ctx);
  assertEquals(chamadas[0].args.p_data, null);
  assertEquals(chamadas[1].args.p_expense_date, null, "so_expense_add continua recebendo o que veio");
});

// Revisão de 11/10/2026: com a conversa desligada (ou em sombra), *cmp N* não faz nada — o CMP
// aberto não segura a despesa; o financeiro não vê o CMP do dono, só que um já lançou o gasto.
Deno.test("despesa da OS: conversa desligada ou em sombra, CMP aberto não segura (grava como antes)", async () => {
  const aberto = { abertos: [{ codigo: "CMP-00124", numero: 124, valor: "62.00", data: "2026-10-10" }], gravados: [] };
  for (const settings of [{}, { comprovante_fluxo: "sombra", comprovante_conversa: "on" }, { comprovante_fluxo: "dono", comprovante_conversa: "off" }] as Array<Record<string, string>>) {
    const { ctx, chamadas } = ctxDaOs(aberto, { settings });
    assertEquals((await despesa.execute(PEDIDO, ctx) as { ok?: boolean }).ok, true, JSON.stringify(settings));
    assertEquals(chamadas.map((c) => c.fn), ["comprovantes_parecidos", "so_expense_add"]);
  }
});

Deno.test("despesa da OS pelo financeiro: CMP gravado → recusa SEM código nem valor; aberto não segura", async () => {
  const ja = ctxDaOs({ abertos: [], gravados: [] }, { cargo: "financial", userId: "u-fin", jaLancados: { ja_lancado: true, aberto: false } });
  const r = await despesa.execute(PEDIDO, ja.ctx) as { error?: string; nada_registrado?: boolean };
  assertEquals(r.error, "Esse gasto já foi lançado nesta OS por um comprovante do dono.");
  assertEquals(r.nada_registrado, true);
  assertEquals(ja.chamadas.map((c) => c.fn), ["comprovantes_ja_lancados"], "o financeiro nunca chama comprovantes_parecidos");
  // a cobrada só esbarra no CMP que comprovou a despesa já lançada; a por conta da casa, também no custo interno
  assertEquals(ja.chamadas[0].args, {
    p_valor: 62, p_data: "2026-10-10", p_os: "os-112", p_efeitos: ["anexar_despesa"], p_autor: "u-fin",
  });
  const casa = ctxDaOs({ abertos: [], gravados: [] }, { cargo: "financial", userId: "u-fin", jaLancados: { ja_lancado: true, aberto: false } });
  await despesa.execute({ ...PEDIDO, billable: false }, casa.ctx);
  assertEquals(casa.chamadas[0].args.p_efeitos, ["anexar_despesa", "despesa_os"]);
  const aberto = ctxDaOs({ abertos: [], gravados: [] }, { cargo: "financial", userId: "u-fin", jaLancados: { ja_lancado: false, aberto: true } });
  assertEquals((await despesa.execute(PEDIDO, aberto.ctx) as { ok?: boolean }).ok, true);
  assertEquals(aberto.chamadas.map((c) => c.fn), ["comprovantes_ja_lancados", "so_expense_add"]);
});

// Revisão dos ajustes do dono (11/10/2026): a tela trava editar/excluir a despesa que nasceu de CMP; o
// assistente também — ela sai cancelando o comprovante (o banco também recusa, por gatilho).
Deno.test("remover despesa da OS: a que nasceu de comprovante não sai por aqui; a lançada à mão sai", async () => {
  const remover = soOpsTools.find((t) => t.name === "remove_service_order_expense")!;
  const doCmp = ctxDaOs({ abertos: [], gravados: [] }, { despesas: { "desp-cmp": { origem_codigo: "CMP-00124" } } });
  const r = await remover.execute({ expense_id: "desp-cmp" }, doCmp.ctx) as { error?: string; nada_removido?: boolean };
  assertEquals(r.error, "Essa despesa é o custo interno do CMP-00124 (comprovante): não apago por aqui. Para tirá-la, cancele o comprovante: *cancelar cmp 124 motivo*.");
  assertEquals(r.nada_removido, true);
  assertEquals(doCmp.chamadas.some((c) => c.fn === "so_expense_remove"), false);
  const manual = ctxDaOs({ abertos: [], gravados: [] }, { despesas: { "desp-1": { origem_codigo: null } } });
  const ok = await remover.execute({ expense_id: "desp-1" }, manual.ctx) as { ok?: boolean };
  assertEquals(ok.ok, true);
  assertEquals(manual.chamadas.map((c) => c.fn), ["from:service_order_expenses", "so_expense_remove"]);
});
