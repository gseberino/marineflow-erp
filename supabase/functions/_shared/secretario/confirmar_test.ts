// A confirmação do *lote* aberta como pendência do assistente (secretário, Passo 5): o mesmo mecanismo dos lembretes
// de revisão — pendência de risco alto com validade, a sessão apontando para ela (é assim que o "sim <PIN>" casa),
// a anterior cancelada quando é o mesmo pedido (outro lote) ou guardada para voltar depois quando é outro assunto
// (27/10/2026), o histórico e a pergunta ativa registrada.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { abrirConfirmacaoDoSecretario } from "./confirmar.ts";

function falsoAdmin(p: { falhaNoInsert?: boolean; anteriorViva?: boolean; anterior?: { action_name: string; payload: unknown } } = {}) {
  const anterior = p.anterior ?? { action_name: "enviar_lembrete_de_revisao", payload: { os: "OS-00073" } };
  const linhas: Record<string, Record<string, unknown>> = {
    "pend-velha": { title: "Enviar lembrete", session_id: "s-1", status: p.anteriorViva ? "pending" : "approved", ...anterior },
    "pend-nova": { status: "pending", action_name: "aprovar_lote_da_papelada", payload: { lote_id: "l-2", ids: ["b"], numeros: [2] } },
  };
  const gravado: Record<string, unknown[]> = {};
  const atualizacoes: Array<{ tabela: string; valores: Record<string, unknown>; filtros: Array<[string, unknown]> }> = [];
  const admin = {
    from(tabela: string) {
      return {
        select() {
          return { eq: (_c: string, v: string) => ({ maybeSingle: () => Promise.resolve({ data: linhas[v] ?? null, error: null }) }) };
        },
        insert(x: unknown) {
          (gravado[tabela] ??= []).push(x);
          const r = tabela === "ai_operator_pending_actions"
            ? (p.falhaNoInsert ? { data: null, error: { code: "23514" } } : { data: { id: "pend-nova" }, error: null })
            : { data: null, error: null };
          const q = { select: () => ({ single: () => Promise.resolve(r) }), then: (ok: (v: unknown) => unknown) => Promise.resolve(r).then(ok) };
          return q;
        },
        update(valores: Record<string, unknown>) {
          const filtros: Array<[string, unknown]> = [];
          atualizacoes.push({ tabela, valores, filtros });
          const q: Record<string, unknown> = {
            eq: (c: string, v: unknown) => (filtros.push([c, v]), q),
            select: () => Promise.resolve({
              data: tabela === "ai_operator_pending_actions" && p.anteriorViva ? [{ title: "Enviar lembrete", action_name: "enviar_lembrete_de_revisao", session_id: "s-1" }] : [],
              error: null,
            }),
            then: (ok: (v: unknown) => unknown) => Promise.resolve({ data: null, error: null }).then(ok),
          };
          return q;
        },
      };
    },
  };
  return { admin, gravado, atualizacoes };
}

const PENDENCIA = {
  action_name: "aprovar_lote_da_papelada", risk_level: "high" as const, risk_reason: "Cria despesas em lote.",
  title: "Aprovar o lote da papelada: 24 itens, R$ 2.670,92 em despesas", summary: "…", payload: { lote_id: "l-1", ids: ["a"], numeros: [1] }, minutos: 720,
};

Deno.test("abre a pendência (alta, 12 h), aponta a sessão para ela, grava o histórico e registra a pergunta ativa", async () => {
  const f = falsoAdmin();
  const envios: Array<{ texto: string; registro: unknown; p: unknown }> = [];
  const agora = new Date("2026-10-16T21:00:00Z");
  const id = await abrirConfirmacaoDoSecretario(f.admin, {
    sessionId: "s-1", metadata: { pending_options: null }, userId: "u-dono", phone: "5547999990000", pedido: "lote", texto: "Lote da semana…",
    pendencia: PENDENCIA, ligada: true, agora,
    enviar: (_a, _f, texto, registro, p) => (envios.push({ texto, registro, p }), Promise.resolve("wa-1")),
  });
  assertEquals(id, "pend-nova");
  const pend = f.gravado["ai_operator_pending_actions"][0] as Record<string, unknown>;
  assertEquals([pend.action_name, pend.risk_level, pend.status, pend.session_id, pend.requested_by_user_id], ["aprovar_lote_da_papelada", "high", "pending", "s-1", "u-dono"]);
  assertEquals(pend.expires_at, "2026-10-17T09:00:00.000Z");
  const sessao = f.atualizacoes.find((a) => a.tabela === "ai_operator_sessions")!;
  assertEquals(sessao.valores.metadata, { pending_options: null, pending_confirm_action_id: "pend-nova", pin_attempts: 0, pendencia_herdada: false });
  assertEquals((f.gravado["ai_operator_messages"][0] as Array<{ role: string; content: string }>).map((m) => [m.role, m.content]), [["user", "lote"], ["assistant", "Lote da semana…"]]);
  assertEquals(envios.length, 1);
  assertEquals(envios[0].registro, { acao: "registrar", tipo: "confirmacao", referencia_id: "pend-nova", titulo: PENDENCIA.title });
  assertEquals(envios[0].p, { ligada: true });
  assert(f.gravado["ai_operator_audit"]?.length === 1);
});

Deno.test("outro lote no lugar do anterior: o anterior vivo é cancelado e o dono é avisado no mesmo texto", async () => {
  const f = falsoAdmin({ anteriorViva: true, anterior: { action_name: "aprovar_lote_da_papelada", payload: { lote_id: "l-1", ids: ["a"], numeros: [1] } } });
  const envios: string[] = [];
  await abrirConfirmacaoDoSecretario(f.admin, {
    sessionId: "s-1", metadata: { pending_confirm_action_id: "pend-velha" }, userId: "u-dono", phone: "5547999990000", pedido: "lote sem 3",
    texto: "Lote da semana, sem o item 3…", pendencia: PENDENCIA, ligada: false,
    enviar: (_a, _f, texto) => (envios.push(texto), Promise.resolve(null)),
  });
  const cancelada = f.atualizacoes.find((a) => a.tabela === "ai_operator_pending_actions")!;
  assertEquals(cancelada.valores.status, "rejected");
  assertEquals(cancelada.filtros, [["id", "pend-velha"], ["status", "pending"]]);
  assertStringIncludes(envios[0], "(O pedido anterior — Enviar lembrete — foi cancelado: vale só este.)");
});

Deno.test("outro assunto antes do sim (um lembrete): não é cancelado, fica guardado e o aviso diz que volta", async () => {
  const f = falsoAdmin({ anteriorViva: true });
  const envios: string[] = [];
  await abrirConfirmacaoDoSecretario(f.admin, {
    sessionId: "s-1", metadata: { pending_confirm_action_id: "pend-velha" }, userId: "u-dono", phone: "5547999990000", pedido: "lote",
    texto: "Lote da semana…", pendencia: PENDENCIA, ligada: false,
    enviar: (_a, _f, texto) => (envios.push(texto), Promise.resolve(null)),
  });
  assertEquals(f.atualizacoes.some((a) => a.tabela === "ai_operator_pending_actions"), false, "nada cancelado");
  const sessao = f.atualizacoes.find((a) => a.tabela === "ai_operator_sessions")!;
  assertEquals((sessao.valores.metadata as Record<string, unknown>).pendencias_guardadas, ["pend-velha"]);
  assertStringIncludes(envios[0], "(O pedido anterior — Enviar lembrete — continua esperando: depois deste eu pergunto dele de novo.)");
});

Deno.test("a pendência não abriu: o dono recebe o texto e o aviso, e a sessão não aponta para nada novo", async () => {
  const f = falsoAdmin({ falhaNoInsert: true });
  const envios: string[] = [];
  const id = await abrirConfirmacaoDoSecretario(f.admin, {
    sessionId: "s-1", metadata: {}, userId: "u-dono", phone: "5547999990000", pedido: "lote", texto: "Lote da semana…",
    pendencia: PENDENCIA, ligada: true, enviar: (_a, _f, texto) => (envios.push(texto), Promise.resolve(null)),
  });
  assertEquals(id, null);
  assertStringIncludes(envios[0], "Não consegui abrir a confirmação agora");
  assertEquals(f.atualizacoes.filter((a) => a.tabela === "ai_operator_sessions").length, 0);
});
