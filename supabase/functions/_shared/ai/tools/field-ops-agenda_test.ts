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

/** O .or() esperado para "a janela ainda não acabou em `de`", escrito à mão: confere as colunas. */
const orEsperado = (de: string) =>
  `scheduled_end_at.gte.${de},and(scheduled_end_at.is.null,scheduled_start_at.gte.${de})`;

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

// ───────── schedule_service_order (D8 / D8b) ─────────

Deno.test("schedule_service_order: OS aguardando peça ganha a data e NÃO volta a Agendada (com técnico)", async () => {
  const { sb, porTabela } = bancoFalso({ service_orders: osComStatus("awaiting_parts") });
  const r = await agendar.execute(
    { service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00", technician_user_id: "t1" },
    { sb } as never,
  ) as Record<string, any>;
  assertEquals(r.ok, true);
  const [upd] = payloadDoUpdate(porTabela);
  assertEquals(upd.scheduled_start_at, "2026-10-27T08:00:00-03:00");
  assertEquals("status" in upd, false, "não pode mandar status: regrediria awaiting_parts");
  assertEquals(r.status_da_os, "Aguardando peças");
  assertMatch(String(r.nota_status), /continua Aguardando peças/);
});

Deno.test("schedule_service_order: OS em andamento também não regride", async () => {
  const { sb, porTabela } = bancoFalso({ service_orders: osComStatus("in_progress") });
  await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00", technician_user_id: "t1" }, { sb } as never);
  assertEquals("status" in payloadDoUpdate(porTabela)[0], false);
});

Deno.test("schedule_service_order: OS aberta vira Agendada COM técnico e vincula o técnico", async () => {
  const { sb, porTabela } = bancoFalso({ service_orders: osComStatus("open") });
  const r = await agendar.execute(
    { service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00", technician_user_id: "t1" },
    { sb } as never,
  ) as Record<string, any>;
  assertEquals(payloadDoUpdate(porTabela)[0].status, "scheduled");
  const upsert = (porTabela.service_order_technicians ?? []).flatMap((c) => args(c, "upsert"));
  assertEquals(upsert[0][0], { service_order_id: "so1", user_id: "t1" });
  assertEquals(r.status_da_os, "Agendada");
  assertEquals(r.aviso_tecnico, undefined);
});

Deno.test("schedule_service_order: OS aberta vira Agendada SEM técnico (o status não depende dele)", async () => {
  const { sb, porTabela } = bancoFalso({ service_orders: osComStatus("open") });
  const r = await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00" }, { sb } as never) as Record<string, any>;
  const [upd] = payloadDoUpdate(porTabela);
  assertEquals(upd.status, "scheduled");
  // Hora sem fuso é hora de Brasília (fuso.ts), como antes.
  assertEquals(upd.scheduled_start_at, "2026-10-27T08:00:00-03:00");
  assertEquals(porTabela.service_order_technicians, undefined, "sem técnico não há vínculo a gravar");
  assertEquals(r.ok, true);
});

Deno.test("schedule_service_order: aprovada vira Agendada; orçamento ganha a data sem mudar de status", async () => {
  const a = bancoFalso({ service_orders: osComStatus("approved") });
  await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00" }, { sb: a.sb } as never);
  assertEquals(payloadDoUpdate(a.porTabela)[0].status, "scheduled");
  const d = bancoFalso({ service_orders: osComStatus("draft", "ORÇ-00083") });
  await agendar.execute({ service_order_id: "so1", scheduled_start_at: "2026-10-27T08:00:00-03:00" }, { sb: d.sb } as never);
  assertEquals("status" in payloadDoUpdate(d.porTabela)[0], false);
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
