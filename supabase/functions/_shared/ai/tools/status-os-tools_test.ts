// Status de OS nas tools (11/10/2026). O prompt já ensinava a lista certa (service-order-status.ts),
// mas update_service_order_status oferecia pending/waiting_parts/waiting_approval/reopened — que o
// CHECK service_orders_status_check recusa (23514) — e não oferecia awaiting_parts/awaiting_client:
// o assistente não conseguia pôr uma OS em "Aguardando peças" nem "Aguardando cliente". Na listagem,
// "aguardando peças" virava waiting_parts e devolvia 0 OS quando havia 2; status desconhecido ia cru
// para o filtro e respondia "nenhuma OS" sem erro. A ficha 360 escondia as OS em awaiting_client.
import { assertEquals, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { filtroDaListagem, serviceOrderTools, TEXTO_CONCLUIR_PELO_ANDAMENTO, TEXTO_PAROU_PELO_ANDAMENTO } from "./service-orders.ts";
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
function osFalsa(
  statusAtual: string,
  porta: Record<string, unknown> | null = null,
  opcoes: { leitura?: string; cargo?: string; atual?: Record<string, unknown>; semPorta?: boolean } = {},
) {
  const atual = opcoes.atual ?? { service_order_number: "OS-00104" };
  const updates: Record<string, unknown>[] = [];
  const rpcs: Array<{ nome: string; params: Record<string, unknown> }> = [];
  let leituras = 0;
  let chamouSequencia = false;
  const from = () => {
    let upd: Record<string, unknown> | null = null;
    const b: Record<string, unknown> = {};
    for (const m of ["select", "eq", "maybeSingle", "single"]) b[m] = () => b;
    b.update = (p: Record<string, unknown>) => { upd = p; updates.push(p); return b; };
    b.then = (ok: (v: unknown) => unknown) => {
      if (!upd) leituras++;
      const data = upd ? { id: "so1", ...upd } : { status: statusAtual, ...atual };
      return Promise.resolve({ data, error: null }).then(ok);
    };
    return b;
  };
  // A porta única de status (Fase 2, P4): o que ela responde, e cada chamada gravada. opcoes.semPorta: a porta completa
  // ainda não está no banco (PGRST202) — o PLANO B de _shared/porta-ausente.ts.
  const sb = {
    from,
    rpc: (nome: string, params: Record<string, unknown>) => {
      rpcs.push({ nome, params });
      if (opcoes.semPorta) return Promise.resolve({ data: null, error: { code: "PGRST202", message: "Could not find the function" } });
      return Promise.resolve({ data: porta ?? { ok: true, mudou: true, de: statusAtual, para: params.p_para, texto: "OS-00104: mudou." }, error: null });
    },
  };
  // agenda_config.modo_leitura (revisão da Fase 2: em andamento → aguardando depende dela); sem a opção, a tabela falta.
  // admin.rpc é a sequência next_document_number (main, 28/10/2026): a conversão não pode puxar número novo.
  const admin = {
    rpc: () => { chamouSequencia = true; return Promise.resolve({ data: 120, error: null }); },
    from: (t: string) => {
      const b: Record<string, unknown> = {};
      b.select = () => b;
      b.maybeSingle = () => Promise.resolve(t === "agenda_config" && opcoes.leitura
        ? { data: { modo_leitura: opcoes.leitura }, error: null }
        : { data: null, error: { code: "42P01" } });
      return b;
    },
  };
  return {
    ctx: { sb, admin, settings: {}, userId: "u-dono", userRole: opcoes.cargo ?? "admin" } as never,
    updates, rpcs, leituras: () => leituras, chamouSequencia: () => chamouSequencia,
  };
}

// Teste do main (28/10/2026, "Assistente converte ORÇ em OS mantendo o número, como a tela"), trazido para o caminho da
// agenda: com a porta completa a conversão é dela (teste "Fase 3: a conversão do orçamento…" abaixo); sem ela, o PLANO B
// faz o UPDATE com o mesmo número, o valor orçado guardado e sem puxar a sequência.
Deno.test("conversão ORÇ→OS mantém o número (como a tela) e guarda o valor orçado — sem puxar a sequência", async () => {
  const orc = osFalsa("draft", null, { semPorta: true, atual: { service_order_number: "ORÇ-00042", converted_to_os_at: null, grand_total: 4200, original_quote_amount: null } });
  const r = await mudarStatus.execute({ id: "so1", status: "approved" }, orc.ctx) as Record<string, any>;
  assertEquals(r.ok, true);
  assertEquals(orc.updates.length, 1);
  const u = orc.updates[0];
  assertEquals(u.status, "approved");
  assertEquals(u.service_order_number, "OS-00042");
  assertEquals(u.original_quote_amount, 4200);
  assertEquals(typeof u.converted_to_os_at, "string");
  assertEquals(orc.chamouSequencia(), false, "número novo da sequência desencontrava a OS do orçamento enviado");

  // Valor orçado já guardado não é sobrescrito.
  const comOrcado = osFalsa("draft", null, { semPorta: true, atual: { service_order_number: "ORÇ-00043", converted_to_os_at: null, grand_total: 5000, original_quote_amount: 4800 } });
  await mudarStatus.execute({ id: "so1", status: "scheduled" }, comOrcado.ctx);
  assertEquals("original_quote_amount" in comOrcado.updates[0], false);

  // Pela porta, nem UPDATE nem sequência: a porta troca só o prefixo.
  const pelaPorta = osFalsa("draft", { ok: true, mudou: true, de: "draft", para: "approved", convertido: true, numero: "OS-00042" },
    { atual: { service_order_number: "ORÇ-00042" } });
  await mudarStatus.execute({ id: "so1", status: "approved" }, pelaPorta.ctx);
  assertEquals([pelaPorta.updates.length, pelaPorta.chamouSequencia()], [0, false]);
});

// FASE 3 (P3): concluir deixou de ser recusa — o execute devolve a instrução de os_registrar_andamento (a releitura e o
// *grava* do dono) e nada é lido nem escrito. Cancelar continua recusado.
Deno.test("D7: preValidar recusa cancelar (manda para cancel_service_order); concluir passa (o execute devolve a instrução)", () => {
  assertEquals(mudarStatus.preValidar!({ id: "so1", status: "completed" }, {} as never), null);
  const cancelar = mudarStatus.preValidar!({ id: "so1", status: "cancelled", cancellation_reason: "desistiu" }, {} as never)!;
  assertMatch(cancelar.error, /cancel_service_order/);
  assertMatch(cancelar.error, /estorna estoque, cobranças e pagamentos/);
  assertEquals(mudarStatus.preValidar!({ id: "so1", status: "awaiting_parts" }, {} as never), null);
  assertEquals(mudarStatus.preValidar!({ id: "so1", status: "in_progress" }, {} as never), null);
});

Deno.test("D7: execute repete a recusa de cancelar (no perfil a tool é low e roda sem o preValidar) e não toca no banco", async () => {
  const os = osFalsa("in_progress");
  const r = await mudarStatus.execute({ id: "so1", status: "cancelled" }, os.ctx) as Record<string, any>;
  assertMatch(String(r.error), /cancel_service_order/);
  assertEquals([os.updates, os.rpcs, os.leituras()], [[], [], 0]);
});

Deno.test("Fase 3: completed devolve a instrução de concluir pelo andamento (não erro) e não toca no banco", async () => {
  const os = osFalsa("in_progress");
  const r = await mudarStatus.execute({ id: "so1", status: "completed" }, os.ctx) as Record<string, any>;
  assertEquals(r, { instrucao: TEXTO_CONCLUIR_PELO_ANDAMENTO, caminho: "os_registrar_andamento" });
  assertEquals(TEXTO_CONCLUIR_PELO_ANDAMENTO,
    "Para concluir, use os_registrar_andamento com evento concluiu e o trecho do dono: o dono confirma com *grava*.");
  assertEquals([os.updates, os.rpcs, os.leituras()], [[], [], 0]);
});

Deno.test("D7: faturar OS que não foi concluída é recusado; concluída fatura pela porta (Fase 3: via assistente, sem UPDATE)", async () => {
  const emAndamento = osFalsa("in_progress");
  const r = await mudarStatus.execute({ id: "so1", status: "invoiced" }, emAndamento.ctx) as Record<string, any>;
  assertMatch(String(r.error), /Faturar vem depois de concluir/);
  assertMatch(String(r.error), /Em andamento/);
  assertMatch(String(r.error), /os_registrar_andamento com evento concluiu/);
  assertEquals([emAndamento.updates, emAndamento.rpcs], [[], []]);

  const concluida = osFalsa("completed", { ok: true, mudou: true, de: "completed", para: "invoiced", texto: "Lenine (OS-00104): faturada." });
  const ok = await mudarStatus.execute({ id: "so1", status: "invoiced" }, concluida.ctx) as Record<string, any>;
  assertEquals([ok.ok, ok.mensagem, ok.status_da_os], [true, "Lenine (OS-00104): faturada.", "Faturada"]);
  assertEquals(concluida.updates, []);
  assertEquals(concluida.rpcs, [{ nome: "os_transicionar_status",
    params: { p_os: "so1", p_para: "invoiced", p_via: "assistente", p_check_out: null, p_autor: "u-dono" } }]);
  // faturar é só do administrador: o 42501 da porta volta como erro com a frase dela
  const semDireito = osFalsa("completed");
  (semDireito.ctx as any).sb.rpc = () => Promise.resolve({ data: null, error: { code: "42501", message: "Faturar e reabrir são com o administrador." } });
  const r3 = await mudarStatus.execute({ id: "so1", status: "invoiced" }, semDireito.ctx) as Record<string, any>;
  assertEquals(r3.error, "Faturar e reabrir são com o administrador.");
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

  const recusa = osFalsa("scheduled", { ok: false, mudou: false, de: "scheduled", para: "scheduled",
    texto: "A OS está agendada: para tirar da agenda, desmarque o dia." });
  const r2 = await mudarStatus.execute({ id: "so1", status: "open" }, recusa.ctx) as Record<string, any>;
  assertEquals(r2.error, "A OS está agendada: para tirar da agenda, desmarque o dia.");
  assertEquals(recusa.updates, []);
});

// Revisão da Fase 2: em andamento → aguardando peças/cliente. A porta só aceita com via dono e o motivo; com a agenda
// de produção ligada o caminho é os_registrar_andamento; desligada, é aqui, com o motivo dito pelo administrador.
Deno.test("revisão: em andamento → aguardando com a agenda de produção ligada aponta os_registrar_andamento, nada chamado", async () => {
  for (const leitura of ["sombra", "ligado"]) {
    const os = osFalsa("in_progress", null, { leitura });
    const r = await mudarStatus.execute({ id: "so1", status: "awaiting_parts", motivo: "falta a peça" }, os.ctx) as Record<string, any>;
    assertEquals(r.error, TEXTO_PAROU_PELO_ANDAMENTO, leitura);
    assertEquals(r.caminho, "os_registrar_andamento", leitura);
    assertEquals([os.rpcs, os.updates], [[], []], leitura);
  }
});

Deno.test("revisão: em andamento → aguardando com a agenda desligada: o motivo do administrador vai à porta com via dono", async () => {
  const os = osFalsa("in_progress", { ok: true, mudou: true, de: "in_progress", para: "awaiting_parts", texto: "Nelson (OS-00112): de em andamento para aguardando peças — falta a peça." },
    { leitura: "desligado" });
  const r = await mudarStatus.execute({ id: "so1", status: "awaiting_parts", motivo: "  falta a peça " }, os.ctx) as Record<string, any>;
  assertEquals(r.ok, true);
  assertEquals(os.rpcs, [{ nome: "os_transicionar_status", params: { p_os: "so1", p_para: "awaiting_parts", p_via: "dono", p_autor: "u-dono", p_motivo: "falta a peça" } }]);
  assertEquals(r.status_da_os, "Aguardando peças");
  // a tabela da agenda que ainda não existe (produção hoje) é o mesmo que desligada
  const semTabela = osFalsa("in_progress", null, {});
  await mudarStatus.execute({ id: "so1", status: "awaiting_client", motivo: "o cliente pediu para esperar" }, semTabela.ctx);
  assertEquals(semTabela.rpcs.map((c) => c.params.p_via), ["dono"]);
});

Deno.test("revisão: em andamento → aguardando sem motivo, ou por quem não é o administrador: recusa com o caminho, nada chamado", async () => {
  const sem = osFalsa("in_progress", null, { leitura: "desligado" });
  const r = await mudarStatus.execute({ id: "so1", status: "awaiting_parts" }, sem.ctx) as Record<string, any>;
  assertMatch(String(r.error), /passe em motivo o porquê que o dono disse/);
  assertEquals(sem.rpcs, []);
  const tec = osFalsa("in_progress", null, { leitura: "desligado", cargo: "technician" });
  const r2 = await mudarStatus.execute({ id: "so1", status: "awaiting_parts", motivo: "falta a peça" }, tec.ctx) as Record<string, any>;
  assertMatch(String(r2.error), /só o administrador/);
  assertEquals(tec.rpcs, []);
  // os outros caminhos seguem pela via assistente (agendada → aguardando peças, por exemplo)
  const ag = osFalsa("scheduled", null, { leitura: "ligado" });
  await mudarStatus.execute({ id: "so1", status: "awaiting_parts" }, ag.ctx);
  assertEquals(ag.rpcs.map((c) => c.params.p_via), ["assistente"]);
});

Deno.test("revisão: a descrição traça a fronteira com os_registrar_andamento e o esquema aceita o motivo", () => {
  assertMatch(mudarStatus.description, /os_registrar_andamento/);
  assertEquals(typeof (mudarStatus.input_schema as any).properties.motivo, "object");
});

// Fase 3 (P3): a conversão do orçamento vai pela porta (via assistente) e o número troca SÓ o prefixo — acabou o número
// novo de next_document_number (NOVO-agenda-15). Sem a porta da Fase 3 no banco, o caminho de antes da tela, que também
// mantém o número (o plano B).
Deno.test("Fase 3: a conversão do orçamento (draft → OS) é da porta: o número troca só o prefixo, nenhum UPDATE", async () => {
  const orc = osFalsa("draft", { ok: true, mudou: true, de: "draft", para: "approved", convertido: true, numero: "OS-00104",
    numero_antes: "ORÇ-00104", texto: "Orçamento ORÇ-00104 virou a OS-00104 (aprovada)." });
  const r = await mudarStatus.execute({ id: "so1", status: "approved" }, orc.ctx) as Record<string, any>;
  assertEquals([r.ok, r.convertido, r.mensagem], [true, true, "Orçamento ORÇ-00104 virou a OS-00104 (aprovada)."]);
  assertEquals(r.service_order, { id: "so1", service_order_number: "OS-00104", status: "approved" });
  assertEquals(orc.updates, []);
  assertEquals(orc.rpcs, [{ nome: "os_transicionar_status",
    params: { p_os: "so1", p_para: "approved", p_via: "assistente", p_check_out: null, p_autor: "u-dono" } }]);
});

Deno.test("Fase 3: PLANO B — sem a porta completa (PGRST202), a conversão do caminho de antes mantém o número", async () => {
  const orc = osFalsa("draft");
  const atual = { status: "draft", converted_to_os_at: null, service_order_number: "ORÇ-00120", grand_total: 500, original_quote_amount: null,
    check_in_at: null, check_out_at: null };
  const updates: Record<string, unknown>[] = [];
  const b: Record<string, unknown> = {};
  let upd: Record<string, unknown> | null = null;
  for (const m of ["select", "eq"]) b[m] = () => b;
  b.update = (p: Record<string, unknown>) => { upd = p; updates.push(p); return b; };
  b.maybeSingle = () => Promise.resolve({ data: upd ? null : { ...atual, service_order_number: "ORÇ-00120" }, error: null });
  b.single = () => Promise.resolve({ data: { id: "so1", ...atual, ...(upd ?? {}) }, error: null });
  (orc.ctx as any).sb = {
    from: () => b,
    rpc: () => Promise.resolve({ data: null, error: { code: "PGRST202", message: "Could not find the function" } }),
  };
  const r = await mudarStatus.execute({ id: "so1", status: "approved" }, orc.ctx) as Record<string, any>;
  assertEquals([r.ok, r.convertido, r.service_order.service_order_number], [true, true, "OS-00120"]);
  assertEquals(updates.length, 1);
  assertEquals([updates[0].status, updates[0].service_order_number, updates[0].original_quote_amount], ["approved", "OS-00120", 500]);
});

Deno.test("D7: a descrição diz o que a tool NÃO faz, e o enum continua sendo a lista do banco", () => {
  assertMatch(mudarStatus.description, /NÃO conclui/);
  assertMatch(mudarStatus.description, /os_registrar_andamento, evento concluiu/);
  assertMatch(mudarStatus.description, /NÃO cancela/);
  assertMatch(mudarStatus.description, /cancel_service_order/);
  assertEquals(ordenado((mudarStatus.input_schema as any).properties.status.enum), ordenado(STATUS_OS));
});
