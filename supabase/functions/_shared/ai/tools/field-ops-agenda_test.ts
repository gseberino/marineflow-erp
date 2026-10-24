// Agenda de Produção, Fase 0, pacote P2 (23/10/2026): as tools de agenda do assistente leem o dia
// de BRASÍLIA e a OS que atravessa o dia, e agendar pelo assistente nunca regride status nem quebra
// no vínculo do técnico.
//
//   · D4  — OS de vários dias só aparecia no dia em que começa (my_agenda, list_team_agenda,
//           check_technician_availability);
//   · D5  — a sobrecarga somava a janela corrida: uma OS de 72 h avisava "72h ocupadas";
//   · D6  — check_technician_availability montava o dia em UTC (depois das 21 h, "hoje" era amanhã)
//           e dayOverloadNotice usava T00:00:00Z;
//   · D8  — schedule_service_order forçava 'scheduled' com técnico, por cima de awaiting_parts e
//           in_progress, e sem técnico não agendava a OS aberta;
//   · D8b — `.upsert(...).catch(() => null)`: o builder do PostgREST NÃO tem .catch, a linha lançava
//           TypeError com a data e o status já gravados, e o técnico nunca era vinculado.
//
// O banco falso daqui imita o real no que importa: o builder só tem `.then` (nenhum .catch nem
// .finally), e cada chamada fica gravada para conferir o FILTRO montado — o PostgREST não valida
// coluna dentro do .or(), então uma coluna errada viraria "agenda vazia" sem erro nenhum.
import { assertEquals, assertMatch, assertRejects, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { fieldOpsTools } from "./field-ops.ts";
import { agendaTools, dayOverloadNotice } from "./agenda.ts";

type Chamada = { metodo: string; args: unknown[] };
type Resultado = { data: unknown; error: unknown };
type Responder = (chamadas: Chamada[]) => Resultado;

const METODOS = [
  "select", "eq", "neq", "in", "lt", "lte", "gt", "gte", "or", "is", "not", "order", "limit", "range",
  "update", "upsert", "insert", "delete", "maybeSingle", "single",
];

/** Banco falso: um builder por from(), com as chamadas gravadas. Sem .catch, como o real. */
function bancoFalso(tabelas: Record<string, Responder>, rpcs: Record<string, (p: any) => Resultado> = {}) {
  const porTabela: Record<string, Chamada[][]> = {};
  const rpcsChamadas: Array<{ nome: string; params: any }> = [];
  const builders: Record<string, unknown>[] = [];
  const sb = {
    from(tabela: string) {
      const chamadas: Chamada[] = [];
      (porTabela[tabela] ??= []).push(chamadas);
      const b: Record<string, unknown> = {};
      for (const m of METODOS) {
        b[m] = (...args: unknown[]) => {
          chamadas.push({ metodo: m, args });
          return b;
        };
      }
      b.then = (ok: (v: Resultado) => unknown, falha?: (e: unknown) => unknown) => {
        const responder = tabelas[tabela] ?? (() => ({ data: [], error: null }));
        return Promise.resolve().then(() => responder(chamadas)).then(ok, falha);
      };
      builders.push(b);
      return b;
    },
    rpc(nome: string, params: any) {
      rpcsChamadas.push({ nome, params });
      const r = rpcs[nome];
      return Promise.resolve(r ? r(params) : { data: [], error: null });
    },
  };
  return { sb, porTabela, rpcsChamadas, builders };
}

const tem = (chamadas: Chamada[], metodo: string) => chamadas.some((c) => c.metodo === metodo);
const args = (chamadas: Chamada[], metodo: string) => chamadas.filter((c) => c.metodo === metodo).map((c) => c.args);

/** O .or() esperado para "a janela ainda não acabou em `de`", escrito à mão: confere as colunas.
 *  O fim é exclusivo (gt): a OS que termina à 00:00 não toca o dia seguinte (revisão de 23/10). */
const orEsperado = (de: string) =>
  `scheduled_end_at.gt.${de},and(scheduled_end_at.is.null,scheduled_start_at.gte.${de})`;

const agendar = serviceOrderTools.find((t) => t.name === "schedule_service_order")!;
const disponibilidade = fieldOpsTools.find((t) => t.name === "check_technician_availability")!;
const minhaAgenda = agendaTools.find((t) => t.name === "my_agenda")!;
const agendaDaEquipe = agendaTools.find((t) => t.name === "list_team_agenda")!;

/** service_orders do schedule_service_order: a leitura do status e o update. */
function osComStatus(status: string, numero = "OS-00104"): Responder {
  return (chamadas) => {
    const upd = args(chamadas, "update")[0]?.[0] as Record<string, unknown> | undefined;
    if (upd) return { data: { id: "so1", service_order_number: numero, status, ...upd }, error: null };
    return { data: { status, service_order_number: numero }, error: null };
  };
}

const payloadDoUpdate = (porTabela: Record<string, Chamada[][]>) =>
  (porTabela.service_orders ?? []).flatMap((c) => args(c, "update")).map((a) => a[0] as Record<string, unknown>);

/** A porta única de status (Fase 2, P4): o que ela responde ao agendar. */
const porta = (de: string, para: string, mudou: boolean, texto = "x") =>
  ({ os_transicionar_status: () => ({ data: { ok: true, mudou, de, para, texto }, error: null }) });
const chamadasDaPorta = (rpcs: Array<{ nome: string; params: any }>) => rpcs.filter((r) => r.nome === "os_transicionar_status").map((r) => r.params);

// ───────── schedule_service_order (D8 / D8b; Fase 2, P4: o status pela porta) ─────────

Deno.test("schedule_service_order: OS aguardando peça ganha a data e NÃO volta a Agendada (a porta diz por quê)", async () => {
  const { sb, porTabela, rpcsChamadas } = bancoFalso({ service_orders: osComStatus("awaiting_parts") },
    porta("awaiting_parts", "awaiting_parts", false, "Ainda falta \"Cabo\" na mão: a OS continua aguardando peças."));
  const r = await agendar.execute(
    { service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00", technician_user_id: "t1" },
    { sb } as never,
  ) as Record<string, any>;
  assertEquals(r.ok, true);
  const [upd] = payloadDoUpdate(porTabela);
  assertEquals(upd.scheduled_start_at, "2026-10-27T08:00:00-03:00");
  assertEquals("status" in upd, false, "não pode mandar status: quem decide é a porta");
  assertEquals(chamadasDaPorta(rpcsChamadas), [{ p_os: "so1", p_para: "scheduled", p_via: "assistente", p_autor: null }]);
  assertEquals(r.status_da_os, "Aguardando peças");
  assertEquals(r.nota_status, "A data foi gravada e o status ficou Aguardando peças: Ainda falta \"Cabo\" na mão: a OS continua aguardando peças.");
});

Deno.test("schedule_service_order: OS em andamento também não regride", async () => {
  const { sb, porTabela } = bancoFalso({ service_orders: osComStatus("in_progress") },
    porta("in_progress", "in_progress", false, "A OS já começou: não volta para agendada."));
  const r = await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00", technician_user_id: "t1" }, { sb } as never) as Record<string, any>;
  assertEquals("status" in payloadDoUpdate(porTabela)[0], false);
  assertMatch(String(r.nota_status), /A OS já começou/);
});

Deno.test("schedule_service_order: OS aberta vira Agendada (pela porta) COM técnico e vincula o técnico", async () => {
  const { sb, porTabela } = bancoFalso({ service_orders: osComStatus("open") }, porta("open", "scheduled", true));
  const r = await agendar.execute(
    { service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00", technician_user_id: "t1" },
    { sb, userId: "u-dono" } as never,
  ) as Record<string, any>;
  assertEquals("status" in payloadDoUpdate(porTabela)[0], false);
  const upsert = (porTabela.service_order_technicians ?? []).flatMap((c) => args(c, "upsert"));
  assertEquals(upsert[0][0], { service_order_id: "so1", user_id: "t1" });
  assertEquals(r.status_da_os, "Agendada");
  assertEquals(r.service_order.status, "scheduled");
  assertEquals(r.nota_status, undefined);
  assertEquals(r.aviso_tecnico, undefined);
});

Deno.test("schedule_service_order: OS aberta vira Agendada SEM técnico (o status não depende dele)", async () => {
  const { sb, porTabela, rpcsChamadas } = bancoFalso({ service_orders: osComStatus("open") }, porta("open", "scheduled", true));
  const r = await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00" }, { sb } as never) as Record<string, any>;
  const [upd] = payloadDoUpdate(porTabela);
  assertEquals("status" in upd, false);
  // Hora sem fuso é hora de Brasília (fuso.ts), como antes.
  assertEquals(upd.scheduled_start_at, "2026-10-27T08:00:00-03:00");
  assertEquals(porTabela.service_order_technicians, undefined, "sem técnico não há vínculo a gravar");
  assertEquals(chamadasDaPorta(rpcsChamadas).length, 1);
  assertEquals(r.ok, true);
  assertEquals(r.status_da_os, "Agendada");
});

Deno.test("schedule_service_order: aprovada vira Agendada; orçamento ganha a data e a porta recusa o status (fica orçamento)", async () => {
  const a = bancoFalso({ service_orders: osComStatus("approved") }, porta("approved", "scheduled", true));
  const ra = await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00" }, { sb: a.sb } as never) as Record<string, any>;
  assertEquals(ra.status_da_os, "Agendada");
  const d = bancoFalso({ service_orders: osComStatus("draft", "ORÇ-00083") },
    { os_transicionar_status: () => ({ data: { ok: false, mudou: false, de: "draft", para: "draft", texto: "Isso ainda é orçamento: converta antes." }, error: null }) });
  const rd = await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00" }, { sb: d.sb } as never) as Record<string, any>;
  assertEquals("status" in payloadDoUpdate(d.porTabela)[0], false);
  assertEquals(rd.status_da_os, "Orçamento");
  assertMatch(String(rd.nota_status), /converta antes/);
});

Deno.test("schedule_service_order: erro da porta → diz que a data ficou e o status não (nunca 'agendada' calado)", async () => {
  const { sb } = bancoFalso({ service_orders: osComStatus("open") },
    { os_transicionar_status: () => ({ data: null, error: { message: "Você não pode mudar o status desta OS." } }) });
  const r = await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00" }, { sb } as never) as Record<string, any>;
  assertEquals(r.ok, false);
  assertEquals(r.error, "A data foi gravada, mas o status da OS-00104 não mudou: Você não pode mudar o status desta OS.");
});

Deno.test("schedule_service_order com a agenda automática ligada: vira o rascunho do pedido (a releitura), nenhum update nem porta", async () => {
  const releitura = "Entendi assim, confere?\n• Marco na agenda: Flávio (OS-00104), qui 29/10, Roberto o dia todo.\nResponda *grava* ou corrija o que estiver errado.";
  const { sb, porTabela, rpcsChamadas } = bancoFalso({
    service_orders: osComStatus("open"),
    agenda_config: () => ({ data: { modo_proposta: "ligado" }, error: null }),
  }, { agenda_rascunho_marcar: () => ({ data: { ok: true, item: "Marco na agenda: …", releitura }, error: null }) });
  const r = await agendar.execute(
    { service_order_id: "so1", scheduled_start_at: "2026-10-29T08:00:00-03:00", quando: "quinta", trecho: "marca o Flávio pra quinta" },
    { sb, userId: "u-dono", canal: "whatsapp" } as never,
  ) as Record<string, any>;
  assertEquals(payloadDoUpdate(porTabela), []);
  assertEquals(chamadasDaPorta(rpcsChamadas), []);
  assertEquals(rpcsChamadas.filter((c) => c.nome === "agenda_rascunho_marcar").map((c) => c.params), [{
    p_autor: "u-dono", p_canal: "whatsapp", p_os: "so1", p_quando: "quinta", p_ate: null, p_pessoa: null, p_trecho: "marca o Flávio pra quinta",
  }]);
  assertEquals(r.ok, true);
  assertEquals(r.texto, releitura);
  assertMatch(String(r.instrucao), /Só o \*grava\* dele grava/);
});

Deno.test("schedule_service_order ligado sem o dia dito: o dia do ISO vai como dd/mm, sem trecho (o banco pede as palavras do dono)", async () => {
  const { sb, rpcsChamadas } = bancoFalso({
    service_orders: osComStatus("open"),
    agenda_config: () => ({ data: { modo_proposta: "ligado" }, error: null }),
  }, { agenda_rascunho_marcar: () => ({ data: { ok: false, motivo: "sem_trecho", pergunta: "Me diga com as suas palavras o que você quer na agenda." }, error: null }) });
  const r = await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-29T08:00:00-03:00", scheduled_end_at: "2026-10-30T17:00:00-03:00" },
    { sb, userId: "u-dono" } as never) as Record<string, any>;
  const p = rpcsChamadas.find((c) => c.nome === "agenda_rascunho_marcar")!.params;
  assertEquals([p.p_quando, p.p_ate, p.p_trecho, p.p_canal], ["29/10", "30/10", null, "whatsapp"]);
  assertEquals(r.ok, false);
  assertEquals(r.pergunta, "Me diga com as suas palavras o que você quer na agenda.");
});

Deno.test("schedule_service_order: OS concluída é recusada e nada é gravado", async () => {
  for (const status of ["completed", "invoiced", "cancelled"]) {
    const { sb, porTabela, rpcsChamadas } = bancoFalso({ service_orders: osComStatus(status) });
    const r = await agendar.execute(
      { service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00", scheduled_end_at: "2026-10-27T12:00:00-03:00", technician_user_id: "t1" },
      { sb } as never,
    ) as Record<string, any>;
    assertMatch(String(r.error), /OS encerrada não se agenda/, status);
    assertEquals(payloadDoUpdate(porTabela), [], status);
    assertEquals(rpcsChamadas.length, 0, `${status}: nem a checagem de conflito roda`);
  }
});

Deno.test("schedule_service_order: OS que não existe vira erro, não update às cegas", async () => {
  const { sb, porTabela } = bancoFalso({ service_orders: () => ({ data: null, error: null }) });
  const r = await agendar.execute({ service_order_id: "x", scheduled_start_at: "2026-10-27T08:00:00-03:00" }, { sb } as never) as Record<string, any>;
  assertMatch(String(r.error), /não encontrada/);
  assertEquals(payloadDoUpdate(porTabela), []);
});

Deno.test("schedule_service_order: erro ao vincular o técnico vira aviso_tecnico, sem TypeError (builder sem .catch)", async () => {
  const { sb, builders } = bancoFalso({
    service_orders: osComStatus("open"),
    service_order_technicians: () => ({ data: null, error: { message: "permission denied for table service_order_technicians" } }),
  });
  const r = await agendar.execute(
    { service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00", technician_user_id: "t1" },
    { sb } as never,
  ) as Record<string, any>;
  // O banco falso é como o real: o builder não tem .catch — o código antigo lançava aqui.
  assertEquals(builders.every((b) => typeof b.catch === "undefined"), true);
  assertEquals(r.ok, true);
  assertMatch(String(r.aviso_tecnico), /técnico não ficou vinculado/);
  assertStringIncludes(String(r.aviso_tecnico), "permission denied");
});

// ───────── check_technician_availability (D4 / D6) ─────────

Deno.test("check_technician_availability às 22:30 de Brasília, sem date: consulta o dia de Brasília", async () => {
  // 23/10/2026 22:30 em Brasília = 24/10 01:30 UTC. O código antigo lia o dia "2026-10-24".
  const relogio = new FakeTime(new Date("2026-10-24T01:30:00Z"));
  try {
    const { sb, porTabela } = bancoFalso({
      service_order_technicians: () => ({ data: [{ service_order_id: "so1" }], error: null }),
      service_orders: () => ({ data: [], error: null }),
    });
    const r = await disponibilidade.execute({ technician_user_id: "t1" }, { sb } as never) as Record<string, any>;
    assertEquals(r.dia, "2026-10-23");
    for (const tabela of ["agenda_tasks", "service_orders"]) {
      const c = porTabela[tabela][0];
      assertEquals(args(c, "lt"), [["scheduled_start_at", "2026-10-24T03:00:00.000Z"]], tabela);
      assertEquals(args(c, "or"), [[orEsperado("2026-10-23T03:00:00.000Z")]], tabela);
      // Sai o filtro antigo, só pelo início dentro do dia (e sem fuso).
      assertEquals(tem(c, "gte") || tem(c, "lte"), false, tabela);
    }
  } finally {
    relogio.restore();
  }
});

Deno.test("check_technician_availability sem date usa o dia do horário proposto ('amanhã 14h' é amanhã)", async () => {
  const relogio = new FakeTime(new Date("2026-10-23T15:00:00Z"));
  try {
    const { sb, porTabela } = bancoFalso({});
    const r = await disponibilidade.execute({ technician_user_id: "t1", proposed_start: "2026-10-24T14:00:00" }, { sb } as never) as Record<string, any>;
    assertEquals(r.dia, "2026-10-24");
    assertEquals(args(porTabela.agenda_tasks[0], "lt"), [["scheduled_start_at", "2026-10-25T03:00:00.000Z"]]);
  } finally {
    relogio.restore();
  }
});

Deno.test("check_technician_availability: OS de 3 dias aparece no 2º dia, e o conflito com ela é só informativo", async () => {
  const os3dias = {
    id: "so1", service_order_number: "OS-00104", status: "scheduled", clients: { name: "Nelson" },
    scheduled_start_at: "2026-10-06T09:00:00.000Z", // 06/10 06:00 em Brasília
    scheduled_end_at: "2026-10-08T21:00:00.000Z", //   08/10 18:00 em Brasília
  };
  const { sb, porTabela } = bancoFalso({
    service_order_technicians: () => ({ data: [{ service_order_id: "so1" }], error: null }),
    service_orders: () => ({ data: [os3dias], error: null }),
  });
  const r = await disponibilidade.execute(
    { technician_user_id: "t1", date: "2026-10-07", proposed_start: "2026-10-07T14:00:00" },
    { sb } as never,
  ) as Record<string, any>;
  // A leitura do 2º dia pede a interseção com 07/10 (o banco real devolve a OS por isso).
  const c = porTabela.service_orders[0];
  assertEquals(args(c, "lt"), [["scheduled_start_at", "2026-10-08T03:00:00.000Z"]]);
  assertEquals(args(c, "or"), [[orEsperado("2026-10-07T03:00:00.000Z")]]);
  assertEquals(r.total, 1);
  assertEquals(r.compromissos[0].varios_dias, true);
  // A janela corrida não diz se ele está lá às 14 h: nem "livre" nem "ocupado" — pergunta.
  assertEquals(r.conflito, null);
  assertEquals(r.livre, null);
  assertEquals(r.os_de_varios_dias_no_horario, ["OS-00104 — Nelson"]);
  assertMatch(String(r.aviso), /pergunte a quem administra/);
});

Deno.test("check_technician_availability: compromisso do próprio dia que bate continua conflito (livre = false)", async () => {
  const { sb } = bancoFalso({
    agenda_tasks: () => ({
      data: [{ id: "k1", title: "Visita Lenine", scheduled_start_at: "2026-10-07T16:00:00.000Z", scheduled_end_at: "2026-10-07T18:00:00.000Z", status: "pending", location: null }],
      error: null,
    }),
  });
  const r = await disponibilidade.execute(
    { technician_user_id: "t1", date: "2026-10-07", proposed_start: "2026-10-07T14:00:00-03:00" },
    { sb } as never,
  ) as Record<string, any>;
  assertEquals(r.conflito?.titulo, "Visita Lenine");
  assertEquals(r.livre, false);
  assertEquals(r.aviso, undefined);
});

Deno.test("check_technician_availability: leitura que falha sobe, não vira 'livre'", async () => {
  for (const tabela of ["agenda_tasks", "service_order_technicians", "service_orders"]) {
    const { sb } = bancoFalso({
      service_order_technicians: () => ({ data: [{ service_order_id: "so1" }], error: null }),
      [tabela]: () => ({ data: null, error: new Error(`falhou ${tabela}`) }),
    });
    await assertRejects(
      () => disponibilidade.execute({ technician_user_id: "t1", date: "2026-10-07", proposed_start: "2026-10-07T14:00:00-03:00" }, { sb } as never),
      Error,
      `falhou ${tabela}`,
    );
  }
});

// ───────── my_agenda e list_team_agenda (D4) ─────────

Deno.test("my_agenda lê a OS por interseção com o dia (a que começou antes também entra)", async () => {
  const { sb, porTabela } = bancoFalso({
    service_order_technicians: () => ({ data: [{ service_order_id: "so1" }], error: null }),
  });
  await minhaAgenda.execute({ date: "2026-10-07" }, { sb, userId: "u1", userRole: "technician" } as never);
  const c = porTabela.service_orders[0];
  assertEquals(args(c, "lt"), [["scheduled_start_at", "2026-10-08T03:00:00.000Z"]]);
  assertEquals(args(c, "or"), [[orEsperado("2026-10-07T03:00:00.000Z")]]);
  assertEquals(tem(c, "gte"), false);
});

Deno.test("list_team_agenda lê a OS por interseção com o dia e devolve o fim", async () => {
  const { sb, porTabela } = bancoFalso({
    app_users: () => ({ data: [{ id: "t1", full_name: "Roberto", role: "technician" }], error: null }),
    service_orders: () => ({
      data: [{
        id: "so1", service_order_number: "OS-00104", scheduled_start_at: "2026-10-06T09:00:00.000Z", scheduled_end_at: "2026-10-08T21:00:00.000Z",
        clients: { name: "Nelson" }, service_order_technicians: [{ user_id: "t1" }],
      }],
      error: null,
    }),
  });
  const r = await agendaDaEquipe.execute({ date: "2026-10-07" }, { sb, userId: "u1", userRole: "admin" } as never) as Record<string, any>;
  const c = porTabela.service_orders[0];
  assertEquals(args(c, "lt"), [["scheduled_start_at", "2026-10-08T03:00:00.000Z"]]);
  assertEquals(args(c, "or"), [[orEsperado("2026-10-07T03:00:00.000Z")]]);
  assertEquals(r.por_pessoa[0].os[0].fim, "2026-10-08T21:00:00.000Z");
});

// ───────── list_team_agenda: nenhuma OS some (revisão de 23/10/2026) ─────────
// Só havia entrada para app_users ATIVO e nenhum balde para OS sem técnico: a OS-00104 (Roberto, login
// inativo) e a OS agendada sem responsável (D2) sumiam da "agenda da equipe" pelo assistente.

Deno.test("list_team_agenda: o técnico de login inativo ganha entrada com o nome do embed, e a OS sem técnico vai para os_sem_responsavel", async () => {
  const { sb, porTabela } = bancoFalso({
    // Só o admin está ativo; o Roberto (t-roberto) está com o login inativo.
    app_users: () => ({ data: [{ id: "u-gustavo", full_name: "Gustavo", role: "admin" }], error: null }),
    service_orders: () => ({
      data: [
        {
          id: "so104", service_order_number: "OS-00104", scheduled_start_at: "2026-10-06T09:00:00.000Z", scheduled_end_at: "2026-10-08T21:00:00.000Z",
          clients: { name: "Nelson" },
          service_order_technicians: [{ user_id: "t-roberto", app_users: { full_name: "Roberto", role: "technician" } }],
        },
        {
          id: "so120", service_order_number: "OS-00120", scheduled_start_at: "2026-10-07T11:00:00.000Z", scheduled_end_at: "2026-10-07T14:00:00.000Z",
          clients: { name: "César" }, service_order_technicians: [],
        },
        {
          // sem o nome (RLS de app_users para quem não é admin): entra genérico, mas entra
          id: "so121", service_order_number: "OS-00121", scheduled_start_at: "2026-10-07T12:00:00.000Z", scheduled_end_at: "2026-10-07T15:00:00.000Z",
          clients: { name: "Marcelo" }, service_order_technicians: [{ user_id: "t-mickael", app_users: null }],
        },
      ],
      error: null,
    }),
  });
  const r = await agendaDaEquipe.execute({ date: "2026-10-07" }, { sb, userId: "u-gustavo", userRole: "admin" } as never) as Record<string, any>;
  assertEquals(
    r.por_pessoa.map((p: any) => [p.pessoa, p.user_id, p.cargo, p.os.map((o: any) => o.numero)]),
    [
      ["Roberto", "t-roberto", "technician", ["OS-00104"]],
      ["Técnico sem nome", "t-mickael", null, ["OS-00121"]],
    ],
  );
  assertEquals(r.os_sem_responsavel, [{ numero: "OS-00120", cliente: "César", inicio: "2026-10-07T11:00:00.000Z", fim: "2026-10-07T14:00:00.000Z" }]);
  // O nome vem do embed: a leitura pede app_users dentro de service_order_technicians.
  assertStringIncludes(String(args(porTabela.service_orders[0], "select")[0][0]), "service_order_technicians(user_id, app_users(full_name, role))");
});

Deno.test("list_team_agenda: OS do técnico ATIVO não ganha entrada repetida", async () => {
  const { sb } = bancoFalso({
    app_users: () => ({ data: [{ id: "t1", full_name: "Roberto", role: "technician" }], error: null }),
    service_orders: () => ({
      data: [{
        id: "so1", service_order_number: "OS-00104", scheduled_start_at: "2026-10-06T09:00:00.000Z", scheduled_end_at: "2026-10-08T21:00:00.000Z",
        clients: { name: "Nelson" }, service_order_technicians: [{ user_id: "t1", app_users: { full_name: "Roberto", role: "technician" } }],
      }],
      error: null,
    }),
  });
  const r = await agendaDaEquipe.execute({ date: "2026-10-07" }, { sb, userId: "t1", userRole: "admin" } as never) as Record<string, any>;
  assertEquals(r.por_pessoa.length, 1);
  assertEquals(r.os_sem_responsavel, []);
});

// ───────── my_agenda e list_team_agenda: leitura que falha sobe (revisão de 23/10/2026) ─────────
// Engolido, o erro do PostgREST virava "nenhuma OS no dia" — o mesmo defeito que check_technician_availability
// já não tem.

const falha = (msg: string): Responder => () => ({ data: null, error: { message: msg } });

for (const tabela of ["agenda_tasks", "service_order_technicians", "service_orders"]) {
  Deno.test(`my_agenda: erro em ${tabela} lança (não vira "dia livre")`, async () => {
    const { sb } = bancoFalso({
      service_order_technicians: () => ({ data: [{ service_order_id: "so1" }], error: null }),
      [tabela]: falha(`falha em ${tabela}`),
    });
    await assertRejects(
      () => minhaAgenda.execute({ date: "2026-10-07" }, { sb, userId: "u1", userRole: "technician" } as never),
    );
  });
}

// NOVO-agenda-08 (Agenda de Produção, Fase 1, P5, 24/10/2026): os vencimentos do dia (admin e financeiro) também.
// Engolido, o erro virava "a receber hoje: nada" — e o 5º bloco da agenda de produção lê a mesma regra.
for (const tabela of ["receivables", "payables"]) {
  for (const cargo of ["admin", "financial"]) {
    Deno.test(`my_agenda (${cargo}): erro em ${tabela} lança (não vira "nada a receber/pagar hoje")`, async () => {
      const { sb } = bancoFalso({ [tabela]: falha(`falha em ${tabela}`) });
      await assertRejects(
        () => minhaAgenda.execute({ date: "2026-10-23" }, { sb, userId: "u1", userRole: cargo } as never),
      );
    });
  }
}

Deno.test("my_agenda (admin): sem erro, os vencimentos do dia continuam saindo com o saldo", async () => {
  const { sb } = bancoFalso({
    receivables: () => ({ data: [{ id: "r1", amount: 500, balance_amount: 200, due_date: "2026-10-23", clients: { name: "Nelson" } }], error: null }),
    payables: () => ({ data: [{ id: "p1", amount: 312.4, balance_amount: null, due_date: "2026-10-23", supplier_name: "Celesc" }], error: null }),
  });
  const r = await minhaAgenda.execute({ date: "2026-10-23" }, { sb, userId: "u1", userRole: "admin" } as never) as Record<string, any>;
  assertEquals(r.vencimentos_do_dia, {
    a_receber: [{ cliente: "Nelson", valor: 200 }],
    a_pagar: [{ fornecedor: "Celesc", valor: 312.4 }],
  });
});

for (const tabela of ["app_users", "agenda_tasks", "service_orders"]) {
  Deno.test(`list_team_agenda: erro em ${tabela} lança (não vira "equipe sem nada")`, async () => {
    const { sb } = bancoFalso({ [tabela]: falha(`falha em ${tabela}`) });
    await assertRejects(
      () => agendaDaEquipe.execute({ date: "2026-10-07" }, { sb, userId: "u1", userRole: "admin" } as never),
    );
  });
}

// ───────── dayOverloadNotice (D5 / D6) ─────────

Deno.test("dayOverloadNotice: agendar uma OS de 72 h num dia vazio não avisa (conta no máximo a jornada)", async () => {
  const { sb } = bancoFalso({}, { get_agenda_conflicts: () => ({ data: [], error: null }) });
  const aviso = await dayOverloadNotice(sb, "t1", "2026-10-06T06:00:00-03:00", "2026-10-09T06:00:00-03:00");
  assertEquals(aviso, null);
});

Deno.test("dayOverloadNotice: dois compromissos de 5 h no mesmo dia avisam (10 h > 8 h)", async () => {
  const { sb } = bancoFalso({}, {
    get_agenda_conflicts: () => ({
      data: [{ source: "task", label: "Visita", starts_at: "2026-10-07T12:00:00.000Z", ends_at: "2026-10-07T17:00:00.000Z" }],
      error: null,
    }),
  });
  const aviso = await dayOverloadNotice(sb, "t1", "2026-10-07T14:00:00-03:00", "2026-10-07T19:00:00-03:00");
  assertMatch(String(aviso), /10\.0h ocupadas/);
});

Deno.test("dayOverloadNotice: o dia é o de Brasília (às 22 h ainda é hoje), não o de UTC", async () => {
  const { sb, rpcsChamadas } = bancoFalso({}, { get_agenda_conflicts: () => ({ data: [], error: null }) });
  await dayOverloadNotice(sb, "t1", "2026-10-23T22:00:00-03:00", "2026-10-23T23:00:00-03:00");
  assertEquals(rpcsChamadas[0].params.p_start, "2026-10-23T03:00:00.000Z");
  assertEquals(rpcsChamadas[0].params.p_end, "2026-10-24T03:00:00.000Z");
});
