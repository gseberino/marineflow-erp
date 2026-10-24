// Agenda de Produção, Fase 2 (P5, 24/10/2026): a my_agenda e o panorama leem o PLANO com a agenda automática ligada
// (v_agenda_dia: quem vai, em que turno, o dia n de N), e a janela antiga fora de 'ligado'. O que se protege: em
// sombra/desligado nada muda (nem v_agenda_dia é lida); em ligado a OS do dia é a do plano da pessoa (pelo payee, com
// ou sem ser técnica da OS), o técnico só vê o próprio dia, e leitura que falha sobe (nunca "nada no dia").
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { agendaTools, osDoDiaPeloPlano } from "./agenda.ts";
import { agendaDeHojePeloPlano, overviewTools } from "./overview.ts";

type Linha = Record<string, unknown>;

/** Um PostgREST de mentira: filtra eq/in sobre as linhas, registra o que foi lido; `falhar` = tabelas com erro. */
function banco(tabelas: Record<string, Linha[]>, falhar: string[] = []) {
  const lidas: string[] = [];
  const cliente = {
    lidas,
    from(t: string) {
      lidas.push(t);
      let linhas = [...(tabelas[t] ?? [])];
      const q: Record<string, unknown> = {
        select: () => q,
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => l[c] === v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(l[c]))), q),
        neq: () => q, lt: () => q, or: () => q, gte: () => q, not: () => q,
        order: () => q,
        limit: () => q,
        maybeSingle: () => Promise.resolve(falhar.includes(t) ? { data: null, error: { code: "XX000" } } : { data: linhas[0] ?? null, error: null }),
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) =>
          Promise.resolve(falhar.includes(t) ? { data: null, error: { code: "XX000", message: `falhou ${t}` } } : { data: linhas, error: null }).then(ok, erro),
      };
      return q;
    },
    rpc: () => Promise.resolve({ data: [], error: null }),
  };
  return cliente;
}

const DONO = "u-dono";
const ROBERTO = "u-roberto";
const DIA = "2026-11-04";
// a carteira de 29/10 publicada (supabase/tests/agenda_fase2_leituras.sql): qua 04/11
const V_AGENDA_DIA: Linha[] = [
  {
    dia: DIA, service_order_id: "o-69", numero: "OS-00069", cliente_curto: "Vanderlei", unidade: "Lancha", tipo: "execucao", reserva: false,
    condicao: null, primeiro_inicio: "2026-11-04T11:00:00+00:00", ultimo_fim: "2026-11-04T20:00:00+00:00", dia_n: 2, dias_total: 3,
    pessoas: [{ payee_id: "p-roberto", nome: "Roberto", eh_dono: false, turnos: ["manha", "tarde"], presenca: "turno" }],
  },
  {
    dia: DIA, service_order_id: "o-74", numero: "OS-00074", cliente_curto: "Lenine", unidade: "Veleiro", tipo: "execucao", reserva: false,
    condicao: null, primeiro_inicio: "2026-11-04T11:00:00+00:00", ultimo_fim: "2026-11-04T15:00:00+00:00", dia_n: 1, dias_total: 4,
    pessoas: [
      { payee_id: "p-dono", nome: "Gustavo", eh_dono: true, turnos: ["manha"], presenca: "abertura" },
      { payee_id: "p-joao", nome: "João", eh_dono: false, turnos: ["manha"], presenca: "turno" },
    ],
  },
  {
    dia: DIA, service_order_id: "o-104", numero: "OS-00104", cliente_curto: "Flávio", unidade: "Itapoã", tipo: "reserva", reserva: true,
    condicao: null, primeiro_inicio: "2026-11-04T16:00:00+00:00", ultimo_fim: "2026-11-04T20:00:00+00:00", dia_n: null, dias_total: null,
    pessoas: [{ payee_id: "p-joao", nome: "João", eh_dono: false, turnos: ["tarde"], presenca: "turno" }],
  },
];
const TABELAS = (modo: string): Record<string, Linha[]> => ({
  agenda_config: [{ modo_proposta: modo }],
  v_agenda_dia: V_AGENDA_DIA,
  payees: [
    { id: "p-dono", app_user_id: DONO, active: true },
    { id: "p-roberto", app_user_id: ROBERTO, active: true },
    { id: "p-joao", app_user_id: null, active: true },
  ],
  service_orders: [{ id: "o-69", status: "scheduled" }, { id: "o-74", status: "scheduled" }, { id: "o-104", status: "awaiting_parts" }],
  agenda_tasks: [],
  service_order_technicians: [{ service_order_id: "o-74", user_id: ROBERTO }],
  receivables: [],
  payables: [],
});

Deno.test("osDoDiaPeloPlano: o dono pelo payee sócio — a abertura do Lenine, com o turno e o dia n de N", async () => {
  const sb = banco(TABELAS("ligado"));
  assertEquals(await osDoDiaPeloPlano(sb, { targetId: DONO, userId: DONO, userRole: "admin", day: DIA }), [{
    id: "o-74", numero: "OS-00074", status: "scheduled", inicio: "2026-11-04T11:00:00+00:00", fim: "2026-11-04T15:00:00+00:00",
    cliente: "Lenine", embarcacao: "Veleiro", fonte: "plano", turnos: ["manha"], presenca: "abertura", dia: "1 de 4",
  }]);
});

Deno.test("osDoDiaPeloPlano: o Roberto pelo plano (não pelo vínculo de técnico) — o Vanderlei o dia todo, o Lenine não", async () => {
  const sb = banco(TABELAS("ligado"));
  const r = await osDoDiaPeloPlano(sb, { targetId: ROBERTO, userId: DONO, userRole: "admin", day: DIA });
  assertEquals(r.map((o) => [o.numero, o.turnos, o.dia]), [["OS-00069", ["manha", "tarde"], "2 de 3"]]);
});

Deno.test("osDoDiaPeloPlano: o técnico vê o próprio dia (a RLS da view filtra) e nunca o de outro login", async () => {
  // o banco do técnico: a view já vem só com as linhas dele (RLS), e payees é fechada
  const doTecnico = banco({ ...TABELAS("ligado"), v_agenda_dia: [V_AGENDA_DIA[0]], payees: [] });
  const r = await osDoDiaPeloPlano(doTecnico, { targetId: ROBERTO, userId: ROBERTO, userRole: "technician", day: DIA });
  assertEquals(r.map((o) => o.numero), ["OS-00069"]);
  assertEquals(doTecnico.lidas.includes("payees"), false, "o técnico não lê payees");
  assertEquals(await osDoDiaPeloPlano(doTecnico, { targetId: DONO, userId: ROBERTO, userRole: "technician", day: DIA }), []);
});

Deno.test("osDoDiaPeloPlano: login sem payee ligado = nada no plano; reserva diz que é reserva; leitura que falha sobe", async () => {
  const sb = banco({ ...TABELAS("ligado"), payees: [{ id: "p-joao", app_user_id: "u-joao", active: true }] });
  const joao = await osDoDiaPeloPlano(sb, { targetId: "u-joao", userId: DONO, userRole: "admin", day: DIA });
  assertEquals(joao.map((o) => [o.numero, o.reserva ?? false, o.turnos]), [["OS-00074", false, ["manha"]], ["OS-00104", true, ["tarde"]]]);
  assertEquals(await osDoDiaPeloPlano(sb, { targetId: "u-ninguem", userId: DONO, userRole: "admin", day: DIA }), []);
  await assertRejects(() => osDoDiaPeloPlano(banco(TABELAS("ligado"), ["v_agenda_dia"]), { targetId: DONO, userId: DONO, userRole: "admin", day: DIA }));
  await assertRejects(() => osDoDiaPeloPlano(banco(TABELAS("ligado"), ["payees"]), { targetId: DONO, userId: DONO, userRole: "admin", day: DIA }));
});

const myAgenda = agendaTools.find((t) => t.name === "my_agenda")!;
const ctx = (sb: unknown, userId = DONO, userRole = "admin") =>
  ({ sb, admin: sb, userId, userRole, jwt: "", appOrigin: "", settings: {} }) as never;

Deno.test("my_agenda: com a agenda automática ligada, os_do_dia é o plano da pessoa; em sombra/desligado nem lê o plano", async () => {
  const ligado = banco(TABELAS("ligado"));
  const r = await myAgenda.execute({ date: DIA }, ctx(ligado)) as Record<string, unknown>;
  assertEquals((r.os_do_dia as Array<Record<string, unknown>>).map((o) => o.numero), ["OS-00074"]);
  assert(ligado.lidas.includes("v_agenda_dia"));
  assert(!ligado.lidas.includes("service_order_technicians"), "em ligado o vínculo de técnico não decide o dia");
  for (const modo of ["sombra", "desligado", "qualquer"]) {
    const b = banco(TABELAS(modo));
    await myAgenda.execute({ date: DIA }, ctx(b));
    assert(!b.lidas.includes("v_agenda_dia"), modo);
    assert(b.lidas.includes("service_order_technicians"), modo);
  }
  // o modo que não dá para ler = o caminho de antes
  const semConfig = banco(TABELAS("ligado"), ["agenda_config"]);
  await myAgenda.execute({ date: DIA }, ctx(semConfig));
  assert(!semConfig.lidas.includes("v_agenda_dia"));
});

const panorama = overviewTools.find((t) => t.name === "get_situation_overview")!;

Deno.test("panorama: com a agenda automática ligada, a agenda de hoje é o plano (quem vai, o dia n de N, a reserva)", async () => {
  const r = await agendaDeHojePeloPlano(banco(TABELAS("ligado")), DIA);
  assertEquals(r.fonte, "plano");
  assertEquals(r.quantidade, 3);
  assertEquals((r.itens as Array<Record<string, unknown>>)[1], {
    numero: "OS-00074", cliente: "Lenine", inicio: "2026-11-04T11:00:00+00:00", fim: "2026-11-04T15:00:00+00:00", dia: "1 de 4",
    quem: [{ nome: "você", turnos: ["manha"], presenca: "abertura" }, { nome: "João", turnos: ["manha"] }],
  });
  assertEquals((r.itens as Array<Record<string, unknown>>)[2].reserva, true);
  await assertRejects(() => agendaDeHojePeloPlano(banco(TABELAS("ligado"), ["v_agenda_dia"]), DIA));
});

Deno.test("panorama: o bloco agenda_hoje lê o plano só em 'ligado'; erro do plano vira { erro } (nunca 'nada hoje')", async () => {
  const ligado = banco(TABELAS("ligado"));
  const r = await panorama.execute({}, ctx(ligado)) as Record<string, Record<string, unknown>>;
  assertEquals(r.agenda_hoje.fonte, "plano");
  assert(ligado.lidas.includes("v_agenda_dia"));
  const sombra = banco(TABELAS("sombra"));
  const s = await panorama.execute({}, ctx(sombra)) as Record<string, Record<string, unknown>>;
  assertEquals(s.agenda_hoje.fonte, undefined);
  assert(!sombra.lidas.includes("v_agenda_dia"));
  const falha = banco(TABELAS("ligado"), ["v_agenda_dia"]);
  const f = await panorama.execute({}, ctx(falha)) as Record<string, Record<string, unknown>>;
  assert(typeof f.agenda_hoje.erro === "string", JSON.stringify(f.agenda_hoje));
});
