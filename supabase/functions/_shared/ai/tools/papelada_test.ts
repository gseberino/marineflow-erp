// A tool do "sim" do lote (secretário, Passo 5): só o admin, só com a chave ligada, confere e trava no banco, chama A
// MESMA aprovação de hoje (aprovar_propostas_de_lancamento) com os ids que ainda conferem, e o relatório vem do banco.
// E ela não vai para o modelo: está no mapa de execução das pendências, fora de allTools.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { allTools, toolsByName } from "./index.ts";
import { financeRulesTools } from "./finance-rules.ts";
import { aprovacaoDeSempre, aprovarLoteDaPapelada, NOME_DA_TOOL_DO_LOTE } from "./papelada.ts";
import type { ToolCtx, ToolDef } from "./registry.ts";
import { filtrarPorCanal } from "../channel-scope.ts";

const LOTE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";

function falsoCtx(chave: string | null, rpcs: Record<string, (p: Record<string, unknown>) => unknown>, papel = "admin") {
  const chamadas: Array<{ nome: string; p: Record<string, unknown> }> = [];
  const admin = {
    from(tabela: string) {
      const linhas: Record<string, unknown>[] = tabela === "app_settings"
        ? (chave === null ? [] : [{ key: "papelada_lote", value: chave }])
        : tabela === "papelada_lote" ? [{ id: LOTE, itens: [{ n: 1, titulo: "Eliane U." }, { n: 2, titulo: "Fatura C6" }] }] : [];
      const q: Record<string, unknown> = {
        select: () => q,
        eq: () => q,
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
      };
      return q;
    },
    rpc(nome: string, args: { p: Record<string, unknown> }) {
      chamadas.push({ nome, p: args.p });
      return Promise.resolve({ data: rpcs[nome] ? rpcs[nome](args.p) : null, error: null });
    },
  };
  const ctx = { sb: admin, admin, userId: "u-dono", userRole: papel, jwt: "", appOrigin: "", settings: {} } as unknown as ToolCtx;
  return { ctx, chamadas };
}

/** A aprovação de sempre, de mentira: registra com o que foi chamada. */
function aprovacaoFalsa(resposta: unknown = { ok: true, aprovadas: 1, falhas: [] }) {
  const chamadas: unknown[] = [];
  const t = { ...aprovacaoDeSempre(), execute: (args: unknown) => (chamadas.push(args), Promise.resolve(resposta)) } as ToolDef;
  return { t, chamadas };
}

const RPCS_OK = {
  papelada_lote_conferir: () => ({ ok: true, validos: [A], fora: [{ n: 2, id: B, codigo: "mudou" }] }),
  papelada_lote_resultado: () => ({
    ok: true, itens: [{ n: 1, id: A, situacao: "entrou" }, { n: 2, id: B, situacao: "fora", motivo: "mudou" }], entrou: 1, falhou: 0, fora: 1, valor_entrou: 493,
  }),
};

Deno.test("a porta de escrita é a MESMA da aprovação item a item (aprovar_propostas_de_lancamento)", () => {
  const original = financeRulesTools.find((t) => t.name === "aprovar_propostas_de_lancamento");
  assert(original);
  assertEquals(aprovacaoDeSempre(), original);
  assertEquals(aprovacaoDeSempre().risk, "high");
});

Deno.test("a tool do lote só existe para a pendência: no mapa de execução, fora da lista do modelo (painel e WhatsApp)", () => {
  assert(toolsByName[NOME_DA_TOOL_DO_LOTE]);
  assertEquals(toolsByName[NOME_DA_TOOL_DO_LOTE].risk, "high");
  assertEquals(toolsByName[NOME_DA_TOOL_DO_LOTE].roles, ["admin"]);
  assertEquals(allTools.some((t) => t.name === NOME_DA_TOOL_DO_LOTE), false);
  assertEquals(filtrarPorCanal(allTools, "whatsapp").some((t) => t.name === NOME_DA_TOOL_DO_LOTE), false);
  // as de antes continuam no mapa
  assert(toolsByName["aprovar_propostas_de_lancamento"]);
});

Deno.test("só o admin, e só com a chave ligada: nada é conferido nem aprovado antes disso", async () => {
  for (const [chave, papel, erro] of [["ligado", "financial", "Só o dono"], ["sombra", "admin", "em ensaio"], [null, "admin", "em ensaio"]] as const) {
    const { ctx, chamadas } = falsoCtx(chave, RPCS_OK, papel);
    const ap = aprovacaoFalsa();
    const r = await aprovarLoteDaPapelada({ lote_id: LOTE, ids: [A, B] }, ctx, ap.t);
    assertStringIncludes(String(r.error), erro);
    assertEquals(chamadas.length, 0);
    assertEquals(ap.chamadas.length, 0);
  }
});

Deno.test("o 'sim': confere e trava (aplicar), aprova SÓ os que conferem pela aprovação de sempre, o relatório vem do banco", async () => {
  const { ctx, chamadas } = falsoCtx("ligado", RPCS_OK);
  const ap = aprovacaoFalsa({ ok: false, aprovadas: 1, falhas: [] });
  const r = await aprovarLoteDaPapelada({ lote_id: LOTE, ids: [A, B] }, ctx, ap.t);
  assertEquals(chamadas.map((c) => c.nome), ["papelada_lote_conferir", "papelada_lote_resultado"]);
  assertEquals(chamadas[0].p, { lote_id: LOTE, ids: [A, B], aplicar: true, app_user_id: "u-dono" });
  assertEquals(ap.chamadas, [{ ids: [A] }]);
  assertEquals(chamadas[1].p, { lote_id: LOTE, resposta: { ok: false, aprovadas: 1, falhas: [] } });
  assertEquals([r.ok, r.entrou, r.fora], [true, 1, 1]);
  assertEquals(r.aviso, "Entraram 1 de 2 (despesas: R$ 493,00). Não entraram 1: 2. Fatura C6 (mudou desde que montei o lote).");
});

Deno.test("a conferência recusa (lote já aplicado, sombra, vencido): nada é aprovado", async () => {
  const { ctx } = falsoCtx("ligado", { papelada_lote_conferir: () => ({ ok: false, erro: "lote_aplicado" }) });
  const ap = aprovacaoFalsa();
  const r = await aprovarLoteDaPapelada({ lote_id: LOTE, ids: [A] }, ctx, ap.t);
  assertEquals(r.error, "Esse lote já foi aprovado. O próximo sai na sexta, às 17:30.");
  assertEquals(ap.chamadas.length, 0);
});

Deno.test("a aprovação de sempre cai no meio: o resultado é lido do banco do mesmo jeito (o lote não fica travado)", async () => {
  const { ctx, chamadas } = falsoCtx("ligado", RPCS_OK);
  const t = { ...aprovacaoDeSempre(), execute: () => Promise.reject(new Error("rede caiu")) } as ToolDef;
  const r = await aprovarLoteDaPapelada({ lote_id: LOTE, ids: [A] }, ctx, t);
  assertEquals(chamadas.map((c) => c.nome), ["papelada_lote_conferir", "papelada_lote_resultado"]);
  assertEquals(chamadas[1].p.resposta, { error: "rede caiu" });
  assertEquals(r.ok, true);
});

Deno.test("pedido torto (sem lote ou sem ids válidos): recusa sem tocar no banco", async () => {
  const { ctx, chamadas } = falsoCtx("ligado", RPCS_OK);
  assertStringIncludes(String((await aprovarLoteDaPapelada({ lote_id: "x", ids: [A] }, ctx, aprovacaoFalsa().t)).error), "incompleto");
  assertStringIncludes(String((await aprovarLoteDaPapelada({ lote_id: LOTE, ids: ["nao-e-uuid"] }, ctx, aprovacaoFalsa().t)).error), "incompleto");
  assertEquals(chamadas.length, 0);
});

Deno.test("de ponta a ponta com a aprovação DE VERDADE: no WhatsApp (sem JWT) vai ao finance-review approve com o segredo e o dono", async () => {
  const antes = { url: Deno.env.get("SUPABASE_URL"), segredo: Deno.env.get("CRON_SECRET") };
  Deno.env.set("SUPABASE_URL", "https://projeto-de-teste.supabase.co");
  Deno.env.set("CRON_SECRET", "segredo-de-teste");
  const fetchDeVerdade = globalThis.fetch;
  const enviados: Array<{ url: string; headers: Record<string, string>; corpo: Record<string, unknown> }> = [];
  globalThis.fetch = ((url: string, init: RequestInit) => {
    enviados.push({ url: String(url), headers: init.headers as Record<string, string>, corpo: JSON.parse(String(init.body)) });
    return Promise.resolve(new Response(JSON.stringify({ ok: true, aprovadas: 1, falhas: [] }), { status: 200 }));
  }) as typeof fetch;
  try {
    const { ctx } = falsoCtx("ligado", RPCS_OK);
    // a leitura das propostas que a aprovação de sempre faz (só saídas: nenhuma "parece pagar")
    // deno-lint-ignore no-explicit-any
    (ctx as any).sb = {
      from: () => {
        const q: Record<string, unknown> = {
          select: () => q,
          in: () => Promise.resolve({ data: [{ id: A, kind: "create_payable", title: "Despesa: x", bank_transaction_id: "t", suggested_client_id: null, suggested_amount: 1, suggested_date: "2026-10-10" }], error: null }),
        };
        return q;
      },
    };
    const r = await aprovarLoteDaPapelada({ lote_id: LOTE, ids: [A, B] }, ctx);
    assertEquals(r.ok, true);
    assertEquals(enviados.length, 1);
    assertEquals(enviados[0].url, "https://projeto-de-teste.supabase.co/functions/v1/finance-review");
    assertEquals(enviados[0].headers["x-cron-secret"], "segredo-de-teste");
    assertEquals(enviados[0].corpo, { action: "approve", ids: [A], overrides: {}, acting_user_id: "u-dono" });
  } finally {
    globalThis.fetch = fetchDeVerdade;
    if (antes.url) Deno.env.set("SUPABASE_URL", antes.url); else Deno.env.delete("SUPABASE_URL");
    if (antes.segredo) Deno.env.set("CRON_SECRET", antes.segredo); else Deno.env.delete("CRON_SECRET");
  }
});
