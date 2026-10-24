// Status de OS nas tools (11/10/2026). O prompt já ensinava a lista certa (service-order-status.ts),
// mas update_service_order_status oferecia pending/waiting_parts/waiting_approval/reopened — que o
// CHECK service_orders_status_check recusa (23514) — e não oferecia awaiting_parts/awaiting_client:
// o assistente não conseguia pôr uma OS em "Aguardando peças" nem "Aguardando cliente". Na listagem,
// "aguardando peças" virava waiting_parts e devolvia 0 OS quando havia 2; status desconhecido ia cru
// para o filtro e respondia "nenhuma OS" sem erro. A ficha 360 escondia as OS em awaiting_client.
import { assertEquals, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { filtroDaListagem, serviceOrderTools } from "./service-orders.ts";
import { entity360Tools } from "./entity-360.ts";
import { STATUS_OS } from "../../service-order-status.ts";

const ordenado = (xs: readonly string[]) => [...xs].sort();

Deno.test("update_service_order_status oferece exatamente os status que o banco aceita", () => {
  const t = serviceOrderTools.find((x) => x.name === "update_service_order_status")!;
  const status = (t.input_schema as any).properties.status;
  assertEquals(ordenado(status.enum), ordenado(STATUS_OS));
  for (const s of STATUS_OS) assertMatch(status.description, new RegExp(`'${s}'=`));
});

Deno.test("listagem: 'aguardando peças' e 'aguardando cliente' viram os status do banco", () => {
  assertEquals(filtroDaListagem({ status: "aguardando peças" }).status, "awaiting_parts");
  assertEquals(filtroDaListagem({ status: "aguardando pecas" }).status, "awaiting_parts");
  assertEquals(filtroDaListagem({ status: "aguardando cliente" }).status, "awaiting_client");
  assertEquals(filtroDaListagem({ status: "Aberta" }).status, "open");
  assertEquals(filtroDaListagem({ status: "awaiting_parts" }).status, "awaiting_parts");
});

Deno.test("listagem: 'aguardando aprovação' é situação do orçamento, não status da OS", () => {
  const f = filtroDaListagem({ status: "aguardando aprovação" });
  assertEquals(f.situacao, "awaiting_approval");
  assertEquals(f.fase, "orcamento");
  assertEquals(f.status, undefined);
});

Deno.test("listagem: nenhum status resolvido fica fora da lista do banco", () => {
  for (const frase of ["aberto", "aprovado", "agendado", "em andamento", "em execução", "concluído", "cancelado", "faturado", "aguardando peças", "aguardando cliente", "orçamento"]) {
    const st = filtroDaListagem({ status: frase }).status;
    assertEquals((STATUS_OS as readonly string[]).includes(String(st)), true, `${frase} → ${st}`);
  }
  // Os valores mortos não são mais "traduzidos": seguem crus e o execute recusa (teste abaixo).
  assertEquals(filtroDaListagem({ status: "pendente" }).status, "pendente");
  assertEquals(filtroDaListagem({ status: "reaberto" }).status, "reaberto");
});

Deno.test("listagem: status que não existe vira erro, não 'nenhuma OS'", async () => {
  let consultou = false;
  const sb = { from: () => { consultou = true; throw new Error("não deveria consultar"); } };
  const listar = serviceOrderTools.find((t) => t.name === "list_service_orders")!;
  const r = await listar.execute({ status: "reaberto" }, { sb } as never) as Record<string, any>;
  assertMatch(String(r.error), /Status inválido: reaberto/);
  assertMatch(String(r.error), /awaiting_client/);
  assertEquals(consultou, false);
});

Deno.test("listagem: rótulo de awaiting_parts/awaiting_client sai em português", async () => {
  const linhas = ["awaiting_parts", "awaiting_client"].map((status, i) => ({
    id: `os-${i}`, service_order_number: `OS-0000${i}`, status, quote_status: null, grand_total: 10,
    payment_status: null, scheduled_start_at: null, created_at: "2026-10-01", clients: { name: "C" }, vessels: { name: "B" },
  }));
  const b: Record<string, unknown> = {};
  for (const m of ["select", "order", "limit", "eq", "neq"]) b[m] = () => b;
  b.then = (ok: (v: unknown) => unknown) => Promise.resolve({ data: linhas, error: null, count: 2 }).then(ok);
  const listar = serviceOrderTools.find((t) => t.name === "list_service_orders")!;
  const r = await listar.execute({}, { sb: { from: () => b } } as never) as Record<string, any>;
  assertEquals(r.results.map((x: any) => x.status), ["Aguardando peças", "Aguardando cliente"]);
});

Deno.test("ficha 360: OS aguardando cliente conta como em andamento", async () => {
  // Cliente falso mínimo: a ficha lê várias tabelas; só service_orders importa aqui.
  const vazio = (data: unknown) => {
    const result = { data, error: null };
    const p: any = new Proxy({}, {
      get(_t, prop) {
        if (prop === "then") return (ok: (v: unknown) => unknown) => Promise.resolve(result).then(ok);
        if (prop === "maybeSingle" || prop === "single") return () => Promise.resolve(result);
        return () => p;
      },
    });
    return p;
  };
  const oss = [
    { id: "1", service_order_number: "OS-1", status: "awaiting_client", quote_status: null, grand_total: 100, created_at: "2026-10-01", updated_at: "2026-10-01", scheduled_start_at: null },
    { id: "2", service_order_number: "OS-2", status: "awaiting_parts", quote_status: null, grand_total: 100, created_at: "2026-10-01", updated_at: "2026-10-01", scheduled_start_at: null },
  ];
  const sb = {
    from: (t: string) => {
      if (t === "clients") return vazio({ id: "c1", name: "Cliente" });
      if (t === "service_orders") return vazio(oss);
      return vazio([]);
    },
    rpc: () => Promise.resolve({ data: [], error: null }),
  };
  const ficha = entity360Tools.find((t) => t.name === "get_client_360")!;
  const r = await ficha.execute({ client_id: "c1" }, { sb, admin: sb, userRole: "admin", userId: "u1" } as never) as Record<string, any>;
  assertEquals(r.os_em_andamento.map((o: any) => o.numero), ["OS-1", "OS-2"]);
});

// ───────── D7 (Agenda de Produção, Fase 0, 23/10/2026): o assistente não conclui nem cancela por fora ─────────
// update_service_order_status fazia um UPDATE cru: concluir por ela deixava a OS "Concluída" sem a
// saída (check_out_at) e sem as cobranças da conclusão que a tela lança; cancelar pulava o estorno
// de estoque, cobranças e pagamentos do cancel_service_order. Agora recusa e indica o caminho.

const mudarStatus = serviceOrderTools.find((t) => t.name === "update_service_order_status")!;

/** service_orders falso: a leitura do status atual e o update, gravados. Sem .catch, como o real. */
function osFalsa(statusAtual: string, porta: Record<string, unknown> | null = null) {
  const updates: Record<string, unknown>[] = [];
  const rpcs: Array<{ nome: string; params: Record<string, unknown> }> = [];
  let leituras = 0;
  const from = () => {
    let upd: Record<string, unknown> | null = null;
    const b: Record<string, unknown> = {};
    for (const m of ["select", "eq", "maybeSingle", "single"]) b[m] = () => b;
    b.update = (p: Record<string, unknown>) => { upd = p; updates.push(p); return b; };
    b.then = (ok: (v: unknown) => unknown) => {
      if (!upd) leituras++;
      const data = upd ? { id: "so1", ...upd } : { status: statusAtual, service_order_number: "OS-00104" };
      return Promise.resolve({ data, error: null }).then(ok);
    };
    return b;
  };
  // A porta única de status (Fase 2, P4): o que ela responde, e cada chamada gravada.
  const sb = {
    from,
    rpc: (nome: string, params: Record<string, unknown>) => {
      rpcs.push({ nome, params });
      return Promise.resolve({ data: porta ?? { ok: true, mudou: true, de: statusAtual, para: params.p_para, texto: "OS-00104: mudou." }, error: null });
    },
  };
  const admin = { rpc: () => Promise.resolve({ data: 120, error: null }) };
  return { ctx: { sb, admin, settings: {}, userId: "u-dono" } as never, updates, rpcs, leituras: () => leituras };
}

Deno.test("D7: preValidar recusa concluir (manda para a tela) e cancelar (manda para cancel_service_order)", () => {
  const concluir = mudarStatus.preValidar!({ id: "so1", status: "completed" }, {} as never)!;
  assertMatch(concluir.error, /Concluir a OS é pela tela \(abra a OS e use Concluir\)/);
  assertMatch(concluir.error, /grava a saída e lança as cobranças da conclusão/);
  const cancelar = mudarStatus.preValidar!({ id: "so1", status: "cancelled", cancellation_reason: "desistiu" }, {} as never)!;
  assertMatch(cancelar.error, /cancel_service_order/);
  assertMatch(cancelar.error, /estorna estoque, cobranças e pagamentos/);
  assertEquals(mudarStatus.preValidar!({ id: "so1", status: "awaiting_parts" }, {} as never), null);
  assertEquals(mudarStatus.preValidar!({ id: "so1", status: "in_progress" }, {} as never), null);
});

Deno.test("D7: execute repete a recusa (no perfil a tool é low e roda sem o preValidar) e não toca no banco", async () => {
  for (const status of ["completed", "cancelled"]) {
    const os = osFalsa("in_progress");
    const r = await mudarStatus.execute({ id: "so1", status }, os.ctx) as Record<string, any>;
    assertMatch(String(r.error), status === "completed" ? /pela tela/ : /cancel_service_order/);
    assertEquals(os.updates, [], status);
    assertEquals(os.leituras(), 0, `${status}: recusa antes de ler`);
  }
});

Deno.test("D7: faturar OS que não foi concluída é recusado; concluída pode faturar", async () => {
  const emAndamento = osFalsa("in_progress");
  const r = await mudarStatus.execute({ id: "so1", status: "invoiced" }, emAndamento.ctx) as Record<string, any>;
  assertMatch(String(r.error), /Faturar vem depois de concluir/);
  assertMatch(String(r.error), /Em andamento/);
  assertEquals(emAndamento.updates, []);

  const concluida = osFalsa("completed");
  const ok = await mudarStatus.execute({ id: "so1", status: "invoiced" }, concluida.ctx) as Record<string, any>;
  assertEquals(ok.ok, true);
  assertEquals(concluida.updates, [{ status: "invoiced" }]);
});

// Fase 2 (P4, 24/10/2026): os status de agenda vão pela porta única do banco (os_transicionar_status, via
// 'assistente'), nunca por UPDATE — em andamento não regride, aguardando peças só sai com o material na mão.
Deno.test("P4: os status de agenda passam pela porta (via assistente, com quem pediu) e nenhum UPDATE é feito", async () => {
  for (const status of ["awaiting_parts", "awaiting_client", "in_progress", "scheduled", "open", "approved"]) {
    const os = osFalsa("scheduled");
    const r = await mudarStatus.execute({ id: "so1", status }, os.ctx) as Record<string, any>;
    assertEquals(r.ok, true, status);
    assertEquals(os.updates, [], status);
    assertEquals(os.rpcs, [{ nome: "os_transicionar_status", params: { p_os: "so1", p_para: status, p_via: "assistente", p_autor: "u-dono" } }], status);
    assertEquals(r.service_order.status, status, status);
  }
});

Deno.test("P4: a porta que não muda nada (em andamento não volta) responde com a frase dela; a recusa vira erro", async () => {
  const fica = osFalsa("in_progress", { ok: true, mudou: false, de: "in_progress", para: "in_progress", texto: "A OS já começou: não volta para agendada." });
  const r = await mudarStatus.execute({ id: "so1", status: "scheduled" }, fica.ctx) as Record<string, any>;
  assertEquals(r.ok, true);
  assertEquals(r.mudou, false);
  assertEquals(r.mensagem, "A OS já começou: não volta para agendada.");
  assertEquals(r.status_da_os, "Em andamento");
  assertEquals(fica.updates, []);

  const recusa = osFalsa("in_progress", { ok: false, mudou: false, de: "in_progress", para: "in_progress",
    texto: "A OS já começou: só volta a aguardar quando você diz que parou e por quê." });
  const r2 = await mudarStatus.execute({ id: "so1", status: "awaiting_parts" }, recusa.ctx) as Record<string, any>;
  assertEquals(r2.error, "A OS já começou: só volta a aguardar quando você diz que parou e por quê.");
  assertEquals(recusa.updates, []);
});

Deno.test("P4: a conversão do orçamento (draft → OS) segue como antes: o UPDATE com o número novo, sem a porta", async () => {
  const orc = osFalsa("draft");
  const r = await mudarStatus.execute({ id: "so1", status: "approved" }, orc.ctx) as Record<string, any>;
  assertEquals(r.ok, true);
  assertEquals(orc.rpcs, []);
  assertEquals(orc.updates.length, 1);
  assertEquals(orc.updates[0].status, "approved");
  assertEquals(orc.updates[0].service_order_number, "OS-00120");
});

Deno.test("D7: a descrição diz o que a tool NÃO faz, e o enum continua sendo a lista do banco", () => {
  assertMatch(mudarStatus.description, /NÃO conclui/);
  assertMatch(mudarStatus.description, /NÃO cancela/);
  assertMatch(mudarStatus.description, /cancel_service_order/);
  assertEquals(ordenado((mudarStatus.input_schema as any).properties.status.enum), ordenado(STATUS_OS));
});
