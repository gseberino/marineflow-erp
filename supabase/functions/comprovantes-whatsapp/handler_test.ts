// As portas da comprovantes-whatsapp (verify_jwt = false: a conferência é toda por dentro).
// O que se protege: requisição sem a chave certa não monta cliente nem toca o banco, e cada porta
// só alcança as próprias ações (o webhook não dispara o vigia; o cron não chama o receber).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { criarHandler } from "./handler.ts";
import type { DependenciasDoFluxo } from "../_shared/comprovantes/fluxo.ts";

const URL_FN = "https://exemplo.supabase.co/functions/v1/comprovantes-whatsapp";
/** O ambiente é do processo inteiro (outros testes mexem nele): cada teste ajusta o seu. */
function ambiente() {
  Deno.env.set("CRON_SECRET", "segredo-do-cron-de-teste");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico-de-teste");
}

function montador() {
  ambiente();
  let montou = 0;
  const rpcs: string[] = [];
  const deps = {
    admin: {
      rpc: (nome: string) => {
        rpcs.push(nome);
        if (nome === "comprovantes_vigia_lote") return Promise.resolve({ data: { expurgados: 0 }, error: null });
        return Promise.resolve({ data: null, error: null });
      },
      from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { value: "off" }, error: null }) }) }) }),
      storage: { from: () => ({}) },
    },
    whatsapp: null,
    dropbox: () => Promise.resolve(null),
    fetch: (() => Promise.reject(new Error("sem rede no teste"))) as typeof fetch,
    agora: () => new Date(),
    log: () => {},
    supabaseUrl: "https://exemplo.supabase.co",
    serviceRoleKey: "chave-de-servico-de-teste",
    internalSecret: "x",
  } as unknown as DependenciasDoFluxo;
  return {
    handler: criarHandler(() => { montou++; return deps; }),
    montou: () => montou,
    rpcs,
  };
}

const post = (corpo: unknown, headers: Record<string, string> = {}) =>
  new Request(URL_FN, { method: "POST", body: JSON.stringify(corpo), headers: { "Content-Type": "application/json", ...headers } });

Deno.test("sem chave nenhuma: 401 e nenhum cliente montado", async () => {
  const m = montador();
  const res = await m.handler(post({ acao: "receber" }));
  assertEquals(res.status, 401);
  assertEquals(m.montou(), 0);
});

Deno.test("chave anônima/qualquer Bearer: 401", async () => {
  const m = montador();
  const res = await m.handler(post({ acao: "receber" }, { Authorization: "Bearer chave-anonima-publica" }));
  assertEquals(res.status, 401);
  assertEquals(m.montou(), 0);
});

Deno.test("x-cron-secret errado: 401, mesmo com a chave de serviço junto", async () => {
  const m = montador();
  const res = await m.handler(post({ acao: "vigiar" }, { "x-cron-secret": "chute", Authorization: "Bearer chave-de-servico-de-teste" }));
  assertEquals(res.status, 401);
  assertEquals(m.montou(), 0);
});

Deno.test("porta do cron não chama o receber; porta interna não dispara o vigia", async () => {
  const m = montador();
  const r1 = await m.handler(post({ acao: "receber" }, { "x-cron-secret": "segredo-do-cron-de-teste" }));
  assertEquals(r1.status, 400);
  const r2 = await m.handler(post({ acao: "vigiar" }, { Authorization: "Bearer chave-de-servico-de-teste" }));
  assertEquals(r2.status, 400);
  const r3 = await m.handler(post({ acao: "outra" }, { "x-cron-secret": "segredo-do-cron-de-teste" }));
  assertEquals(r3.status, 400);
  assertEquals(m.montou(), 0);
});

Deno.test("GET autenticado: 405", async () => {
  const m = montador();
  const res = await m.handler(new Request(URL_FN, { method: "GET", headers: { "x-cron-secret": "segredo-do-cron-de-teste" } }));
  assertEquals(res.status, 405);
});

Deno.test("porta interna com receber inválido: 422 sem tocar o banco", async () => {
  const m = montador();
  const res = await m.handler(post({ acao: "receber", message_id: "x" }, { Authorization: "Bearer chave-de-servico-de-teste" }));
  assertEquals(res.status, 422);
  assertEquals(await res.json(), { aceito: false, motivo: "entrada_invalida" });
  assertEquals(m.rpcs.length, 0);
});

Deno.test("porta do cron: entrega exige job_id uuid; vigiar responde a contagem; repescar com off = 409", async () => {
  const m = montador();
  const cron = { "x-cron-secret": "segredo-do-cron-de-teste" };
  assertEquals((await m.handler(post({ acao: "entrega", job_id: "x" }, cron))).status, 400);
  const v = await m.handler(post({ acao: "vigiar" }, cron));
  assertEquals(v.status, 200);
  assertEquals(await v.json(), {
    ok: true, baixados: 0, entregues: 0, reenfileirados: 0, dropbox: 0, apagados: 0, avisos: 0, expurgados: 0, sem_desfecho: 0, encaminhados: 0,
    movidos: 0, indices: 0, cnpj: 0, perguntas: 0,
  });
  const r = await m.handler(post({ acao: "repescar", desde: "2026-10-01T00:00:00Z", limite: 20 }, cron));
  assertEquals(r.status, 409);
  assertEquals(await r.json(), { ok: false, motivo: "modo_off" });
});

Deno.test("CRON_SECRET ausente: recusa tudo pela porta do cron (fail-closed)", async () => {
  const m = montador();
  Deno.env.delete("CRON_SECRET");
  try {
    const res = await m.handler(post({ acao: "vigiar" }, { "x-cron-secret": "segredo-do-cron-de-teste" }));
    assertEquals(res.status, 500);
    assertEquals(m.montou(), 0);
  } finally {
    ambiente();
  }
});

// ─── F2: as ações da conversa (só a porta interna) ────────────────────────────────────────

Deno.test("F2: responder/pendentes/desempatar/retomar só pela porta interna; o cron não alcança", async () => {
  const m = montador();
  for (const acao of ["responder", "pendentes", "desempatar", "retomar"]) {
    const r = await m.handler(post({ acao }, { "x-cron-secret": "segredo-do-cron-de-teste" }));
    assertEquals(r.status, 400, acao);
  }
  for (const acao of ["responder", "pendentes", "desempatar", "retomar"]) {
    const r = await m.handler(post({ acao }, { Authorization: "Bearer chave-anonima-publica" }));
    assertEquals(r.status, 401, acao);
  }
  assertEquals(m.montou(), 0);
});

Deno.test("F2: entrada inválida no responder = 422 sem tocar o banco; pendentes/desempatar inválidos não enviam nada", async () => {
  const m = montador();
  const interna = { Authorization: "Bearer chave-de-servico-de-teste" };
  const r = await m.handler(post({ acao: "responder", message_id: "x", phone: "5547999990000", texto: "1" }, interna));
  assertEquals(r.status, 422);
  assertEquals(await r.json(), { tratada: false, motivo: "entrada_invalida" });
  const p = await m.handler(post({ acao: "pendentes", message_id: "x", phone: "1" }, interna));
  assertEquals(await p.json(), { enviada: false, itens: 0 });
  const d = await m.handler(post({ acao: "desempatar", message_id: "x", phone: "1" }, interna));
  assertEquals(await d.json(), { enviada: false });
  // retomar (revisão de 11/10/2026): telefone inválido não pergunta nada
  const t = await m.handler(post({ acao: "retomar", phone: "1" }, interna));
  assertEquals(await t.json(), { perguntou: false });
  assertEquals(m.rpcs.length, 0);
});

// ─── o assistente opera o CMP (11/10/2026): a ação completar ─────────────────────────────

Deno.test("completar: só pela porta interna (a tool completar_comprovante); o cron e a chave anônima não alcançam", async () => {
  const m = montador();
  assertEquals((await m.handler(post({ acao: "completar" }, { "x-cron-secret": "segredo-do-cron-de-teste" }))).status, 400);
  assertEquals((await m.handler(post({ acao: "completar" }, { Authorization: "Bearer chave-anonima-publica" }))).status, 401);
  assertEquals(m.montou(), 0);
  // pela porta interna a ação existe: entrada inválida = 422, sem tocar o banco
  const r = await m.handler(post({ acao: "completar", phone: "1", autor: "x", cmp: 1 }, { Authorization: "Bearer chave-de-servico-de-teste" }));
  assertEquals(r.status, 422);
  assertEquals(await r.json(), { ok: false, motivo: "entrada_invalida", aplicados: [], ignorados: [], enviada: false });
  assertEquals(m.rpcs.length, 0);
});
