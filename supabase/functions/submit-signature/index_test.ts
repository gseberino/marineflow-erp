// A assinatura do cliente e o status da OS pela porta (Agenda de Produção, Fase 3, P3 — 24/10/2026; NOVO-agenda-13 e 23).
//
// Até aqui o status configurado (signature_status_after) ia no mesmo UPDATE da assinatura: 'completed' concluía sem a
// saída e sem as cobranças; 'approved' (o de produção) aprovava o orçamento sem converter (a ORÇ-00070) e voltava a OS em
// andamento para aprovada. Agora a assinatura grava só os campos dela e o status vai pela porta (via 'assinatura', sem
// autor). Os testes, com o supabase falso (sem rede):
//   · a porta é chamada com a via 'assinatura' e p_check_out (só a da Fase 3 serve) e o status que ela devolve é o que fica;
//   · a porta que recusa, o erro e a exceção não derrubam nada: vão ao app_error_logs e o status fica o de antes;
//   · PLANO B: sem a porta completa (PGRST202), o caminho de antes da porta — a conversão mantendo o número;
//   · no index.ts, o UPDATE da assinatura não leva mais status, e o status vem depois de a assinatura estar gravada.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { statusDepoisDaAssinatura } from "./status-da-assinatura.ts";

type Resposta = { data: unknown; error: unknown } | "lanca";

function adminFalso(porta: Resposta, os: Record<string, unknown> = {}) {
  const rpcs: Array<{ nome: string; params: Record<string, unknown> }> = [];
  const updates: Record<string, unknown>[] = [];
  const atual = { status: "draft", converted_to_os_at: null, service_order_number: "ORÇ-00119", grand_total: 9608.96,
    original_quote_amount: null, check_in_at: null, check_out_at: null, ...os };
  const admin = {
    rpc(nome: string, params: Record<string, unknown>) {
      rpcs.push({ nome, params });
      if (nome === "log_app_error") return Promise.resolve({ data: null, error: null });
      if (porta === "lanca") throw new Error("rede caiu");
      return Promise.resolve(porta);
    },
    from(tabela: string) {
      if (tabela !== "service_orders") throw new Error(`tabela inesperada: ${tabela}`);
      let upd: Record<string, unknown> | null = null;
      const b: Record<string, unknown> = {};
      for (const m of ["select", "eq"]) b[m] = () => b;
      b.update = (p: Record<string, unknown>) => { upd = p; updates.push(p); return b; };
      b.maybeSingle = () => Promise.resolve({ data: atual, error: null });
      b.single = () => Promise.resolve({ data: { id: "os-1", ...atual, ...(upd ?? {}) }, error: null });
      return b;
    },
  };
  return { admin, rpcs, updates, logs: () => rpcs.filter((r) => r.nome === "log_app_error") };
}

const OS = { id: "os-1", status: "draft", service_order_number: "ORÇ-00119" };

Deno.test("a porta é chamada com via 'assinatura', sem autor e com p_check_out; o status é o que ela devolve", async () => {
  const f = adminFalso({ data: { ok: true, mudou: true, de: "draft", para: "approved", convertido: true, numero: "OS-00119",
    texto: "Orçamento ORÇ-00119 virou a OS-00119 (aprovada)." }, error: null });
  const r = await statusDepoisDaAssinatura(f.admin, OS, "approved");
  assertEquals(f.rpcs.filter((c) => c.nome === "os_transicionar_status"), [{ nome: "os_transicionar_status",
    params: { p_os: "os-1", p_para: "approved", p_via: "assinatura", p_check_out: null } }]);
  assertEquals(r, { status: "approved", mudou: true, texto: "Orçamento ORÇ-00119 virou a OS-00119 (aprovada).", caminho: "porta" });
  assertEquals(f.updates, []);
  assertEquals(f.logs(), []);
});

Deno.test("a OS em andamento não volta para aprovada: a porta não muda e o status fica o dela", async () => {
  const f = adminFalso({ data: { ok: true, mudou: false, de: "in_progress", para: "in_progress",
    texto: "A OS já começou: não volta para aprovada." }, error: null });
  const r = await statusDepoisDaAssinatura(f.admin, { ...OS, status: "in_progress" }, "approved");
  assertEquals([r.status, r.mudou, r.caminho], ["in_progress", false, "porta"]);
  assertEquals(f.updates, []);
});

Deno.test("a porta que recusa (ok = false) não derruba a assinatura: vai ao registro e o status fica", async () => {
  const f = adminFalso({ data: { ok: false, mudou: false, de: "completed", para: "completed",
    texto: "A OS-00074 está concluída: a agenda não muda o status dela." }, error: null });
  const r = await statusDepoisDaAssinatura(f.admin, { id: "os-1", status: "completed", service_order_number: "OS-00074" }, "approved");
  assertEquals([r.status, r.mudou, r.caminho], ["completed", false, "recusa"]);
  assertEquals(f.logs().length, 1);
  assertStringIncludes(String(f.logs()[0].params.p_message), "OS-00074");
  assertEquals(f.logs()[0].params.p_context, "submit-signature");
});

Deno.test("erro de banco e exceção também não derrubam: o registro e o status de antes", async () => {
  for (const porta of [{ data: null, error: { code: "XX000", message: "deu ruim" } }, "lanca"] as const) {
    const f = adminFalso(porta);
    const r = await statusDepoisDaAssinatura(f.admin, OS, "approved");
    assertEquals([r.status, r.mudou, r.caminho], ["draft", false, "erro"]);
    assertEquals(f.logs().length, 1);
    assertEquals(f.updates, []);
  }
});

Deno.test("PLANO B: sem a porta completa (PGRST202), o caminho de antes — a conversão troca só o prefixo", async () => {
  const f = adminFalso({ data: null, error: { code: "PGRST202", message: "Could not find the function" } });
  const r = await statusDepoisDaAssinatura(f.admin, OS, "approved");
  assertEquals([r.status, r.mudou, r.caminho], ["approved", true, "sem_a_porta"]);
  assertEquals(f.updates.length, 1);
  assertEquals([f.updates[0].status, f.updates[0].service_order_number], ["approved", "OS-00119"]);
  assert(typeof f.updates[0].converted_to_os_at === "string");
  assertEquals(f.logs(), []);
});

Deno.test("index.ts: o UPDATE da assinatura não leva o status, e o status vem depois da assinatura gravada", async () => {
  const fonte = (await Deno.readTextFile(new URL("./index.ts", import.meta.url))).replace(/\r\n/g, "\n");
  const insere = fonte.indexOf(".from('service_order_signatures')\n      .insert(");
  const atualiza = fonte.indexOf("client_signature_url: signatureUrl,");
  const status = fonte.indexOf("await statusDepoisDaAssinatura(admin, order, statusPedido)");
  assert(insere > 0 && atualiza > insere && status > atualiza, "a ordem é: assinatura, campos dela, status pela porta");
  const update = fonte.slice(fonte.lastIndexOf(".update({", atualiza), fonte.indexOf("})", atualiza));
  assertEquals(/\bstatus\s*:/.test(update), false, "o UPDATE da assinatura não pode levar status");
  assertStringIncludes(fonte, "new_status: newStatus,");
});
