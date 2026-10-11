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
// add_service_order_expense executa SEM "sim" (risco low): a trava mora no execute. CMP gravado
// com a despesa nesta OS → recusa; CMP aberto do mesmo valor (só com a conversa ligada) → pede para
// completar o CMP, a não ser que o dono diga "mesmo assim". comprovantes_parecidos (admin) e
// comprovantes_ja_lancados (financeiro, só o booleano) são dublês com a forma da spec.

const sem = (s: unknown) => String(s).replace(/\u00a0/g, " ");
const despesa = soOpsTools.find((t) => t.name === "add_service_order_expense")!;

/** A conversa dos comprovantes ligada: só assim um CMP aberto segura a despesa. */
const LIGADA = { comprovante_fluxo: "dono", comprovante_conversa: "on" };

function ctxDaOs(
  parecidos: Record<string, unknown> | Error,
  opcoes: { cargo?: string; userId?: string; settings?: Record<string, string>; jaLancados?: Record<string, unknown> } = {},
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
  const c = { rpc };
  return {
    ctx: {
      sb: c, admin: c, userId: opcoes.userId ?? "u-dono", userRole: opcoes.cargo ?? "admin", jwt: "", appOrigin: "",
      settings: opcoes.settings ?? LIGADA,
    } as never,
    chamadas,
  };
}

const PEDIDO = { service_order_id: "os-112", description: "gasolina", amount: 62, expense_date: "2026-10-10" };

Deno.test("despesa da OS: CMP gravado com a despesa nesta OS → recusa, sem so_expense_add", async () => {
  for (const efeito of ["despesa_os", "anexar_despesa"]) {
    const { ctx, chamadas } = ctxDaOs({ abertos: [], gravados: [{ codigo: "CMP-00123", numero: 123, valor: "62.00", data: "2026-10-10", os_id: "os-112", efeitos: [efeito] }] });
    const r = await despesa.execute(PEDIDO, ctx) as { error?: string; nada_registrado?: boolean };
    assertEquals(sem(r.error), "Já lançado pelo CMP-00123 (R$ 62,00 em 10/10) nesta OS.");
    assertEquals(r.nada_registrado, true);
    assertEquals(chamadas.map((c) => c.fn), ["comprovantes_parecidos"]);
    assertEquals(chamadas[0].args, { p_valor: 62, p_data: "2026-10-10", p_os: "os-112", p_autor: "u-dono" });
  }
});

Deno.test("despesa da OS: CMP aberto sem mesmo_assim → pergunta; com mesmo_assim → grava", async () => {
  const aberto = { abertos: [{ codigo: "CMP-00124", numero: 124, valor: "62.00", data: "2026-10-10" }], gravados: [] };
  const sem1 = ctxDaOs(aberto);
  const r = await despesa.execute(PEDIDO, sem1.ctx) as { error?: string };
  assertEquals(
    sem(r.error),
    "Há o CMP-00124 aberto com R$ 62,00 em 10/10; completar o CMP? Responda *cmp 124*. Se for outro gasto, peça de novo dizendo 'mesmo assim'.",
  );
  assertEquals(sem1.chamadas.some((c) => c.fn === "so_expense_add"), false);

  const com = ctxDaOs(aberto);
  const ok = await despesa.execute({ ...PEDIDO, mesmo_assim: true }, com.ctx) as { ok?: boolean; despesa_id?: string };
  assertEquals(ok.ok, true);
  assertEquals(com.chamadas.map((c) => c.fn), ["comprovantes_parecidos", "so_expense_add"]);
  assertEquals("mesmo_assim" in com.chamadas[1].args, false, "o argumento não vai à função do banco");
});

Deno.test("despesa da OS: mesmo_assim não fura o CMP já gravado; consulta que falha segue como antes", async () => {
  const gravado = ctxDaOs({ abertos: [], gravados: [{ codigo: "CMP-00123", valor: "62.00", data: "2026-10-10", efeitos: ["despesa_os"] }] });
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
  assertEquals(ja.chamadas[0].args, {
    p_valor: 62, p_data: "2026-10-10", p_os: "os-112", p_efeitos: ["despesa_os", "anexar_despesa"], p_autor: "u-fin",
  });
  const aberto = ctxDaOs({ abertos: [], gravados: [] }, { cargo: "financial", userId: "u-fin", jaLancados: { ja_lancado: false, aberto: true } });
  assertEquals((await despesa.execute(PEDIDO, aberto.ctx) as { ok?: boolean }).ok, true);
  assertEquals(aberto.chamadas.map((c) => c.fn), ["comprovantes_ja_lancados", "so_expense_add"]);
});
