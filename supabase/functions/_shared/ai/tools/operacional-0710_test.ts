// Frente operacional (07/10/2026): laudo da OS, via do técnico, tarefa que se repete e caixa de
// sugestões da agenda pelo assistente. Banco falso que filtra de verdade e grava em memória, para
// conferir o que foi parar em cada coluna — o mesmo que a tela grava.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { serviceOrderTools } from "./service-orders.ts";
import { acharServico, fieldOpsTools, horarioDito, situacaoDita } from "./field-ops.ts";
import { agendaTools, descreverRepeticao, montarRecorrencia, prioridadeDaTarefa, statusDaTarefa } from "./agenda.ts";
import { agendaSugestaoTools, filtrarSugestoes } from "./agenda-sugestoes.ts";
import { expandOccurrences, parseRRule } from "../../recurrence.ts";

// ─── Banco falso ─────────────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;
type Filtro = (l: Linha) => boolean;

function condicaoDoOr(expr: string): Filtro {
  const partes = expr.split(",").map((p) => {
    const [col, op, ...resto] = p.split(".");
    const val = resto.join(".");
    if (op === "is" && val === "null") return (l: Linha) => l[col] == null;
    if (op === "eq") return (l: Linha) => String(l[col]) === val;
    if (op === "gte") return (l: Linha) => l[col] != null && String(l[col]) >= val;
    return () => false;
  });
  return (l) => partes.some((f) => f(l));
}

function bancoFalso(tabelas: Record<string, Linha[]>, falhas: Record<string, string> = {}) {
  const gravacoes: Array<{ op: string; tabela: string; valor?: unknown }> = [];
  let seq = 0;
  function consulta(tabela: string) {
    const filtros: Filtro[] = [];
    let op: "select" | "update" | "insert" | "delete" = "select";
    // deno-lint-ignore no-explicit-any
    let valor: any = null;
    let unico: "single" | "maybe" | null = null;
    let devolve = false;
    const linhas = () => (tabelas[tabela] ??= []);
    const executar = () => {
      const erro = falhas[`${op}:${tabela}`];
      if (erro) return { data: null, error: { message: erro } };
      let resultado: Linha[];
      if (op === "insert") {
        const novas = (Array.isArray(valor) ? valor : [valor]).map((v: Linha) => ({ id: `${tabela}-novo-${++seq}`, ...v }));
        linhas().push(...novas);
        gravacoes.push({ op, tabela, valor });
        resultado = novas;
      } else {
        const alvo = linhas().filter((l) => filtros.every((f) => f(l)));
        if (op === "update") { alvo.forEach((l) => Object.assign(l, valor)); gravacoes.push({ op, tabela, valor }); }
        if (op === "delete") { tabelas[tabela] = linhas().filter((l) => !alvo.includes(l)); gravacoes.push({ op, tabela, valor: alvo.map((l) => l.id) }); }
        resultado = alvo.map((l) => ({ ...l }));
      }
      if (unico) return { data: resultado[0] ?? null, error: null };
      return { data: op === "select" || devolve ? resultado : null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => { if (op !== "select") devolve = true; return q; },
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      neq: (c: string, v: unknown) => { filtros.push((l) => l[c] !== v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      is: (c: string, v: unknown) => { filtros.push((l) => (v === null ? l[c] == null : l[c] === v)); return q; },
      gte: (c: string, v: string) => { filtros.push((l) => l[c] != null && String(l[c]) >= v); return q; },
      or: (expr: string) => { filtros.push(condicaoDoOr(expr)); return q; },
      order: () => q, limit: () => q, range: () => q,
      update: (v: unknown) => { op = "update"; valor = v; return q; },
      insert: (v: unknown) => { op = "insert"; valor = v; return q; },
      delete: () => { op = "delete"; return q; },
      single: () => { unico = "single"; return Promise.resolve(executar()); },
      maybeSingle: () => { unico = "maybe"; return Promise.resolve(executar()); },
      // deno-lint-ignore no-explicit-any
      then: (ok: any, ko: any) => Promise.resolve(executar()).then(ok, ko),
    };
    return q;
  }
  const db = { from: consulta, rpc: () => Promise.resolve({ data: [], error: null }), gravacoes, tabelas };
  return db;
}
const ctxCom = (db: unknown, userRole = "admin", userId = "dono-1") =>
  ({ sb: db, admin: db, userId, userRole, jwt: "", appOrigin: "", settings: {} }) as never;
const tool = (lista: { name: string }[], nome: string) => lista.find((t) => t.name === nome)! as (typeof serviceOrderTools)[number];

const OS_112 = { id: "11111111-1111-4111-8111-111111111112", service_order_number: "OS-00112", status: "in_progress", share_token: null, updated_at: null, diagnosis: "texto antigo", technician_notes: "nota antiga", internal_notes: null, check_in_at: null, check_out_at: null };

// ─── 1. Laudo da OS ──────────────────────────────────────────────────────────────────────────
Deno.test("laudo: diagnóstico pelo NÚMERO da OS grava o campo da tela e devolve o texto substituído", async () => {
  const db = bancoFalso({ service_orders: [{ ...OS_112 }] });
  const r = await tool(serviceOrderTools, "update_service_order_notes").execute(
    { os: "OS-00112", diagnosis: "Bateria sulfatada, banco com 40%", customer_visible_report: "Sistema testado com carga total." },
    ctxCom(db),
  ) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.service_orders[0].diagnosis, "Bateria sulfatada, banco com 40%");
  assertEquals(db.tabelas.service_orders[0].customer_visible_report, "Sistema testado com carga total.");
  assertEquals(r.texto_anterior_substituido, { diagnosis: "texto antigo" });
});

Deno.test("laudo: append acrescenta embaixo; técnico grava laudo mas não observação de impressão", async () => {
  const db = bancoFalso({ service_orders: [{ ...OS_112 }] });
  const t = tool(serviceOrderTools, "update_service_order_notes");
  const r = await t.execute({ os: "OS-00112", technician_notes: "Faltou o cabo.", mode: "append" }, ctxCom(db, "technician")) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.service_orders[0].technician_notes, "nota antiga\nFaltou o cabo.");
  const recusa = await t.execute({ os: "OS-00112", extra_notes: "Garantia de 90 dias" }, ctxCom(db, "technician")) as any;
  assertStringIncludes(recusa.error, "escritório");
  assertEquals(db.tabelas.service_orders[0].extra_notes, undefined);
});

Deno.test("laudo: OS faturada não edita (a tela trava) e leitura que falha diz que falhou", async () => {
  const faturada = bancoFalso({ service_orders: [{ ...OS_112, status: "invoiced" }] });
  const r = await tool(serviceOrderTools, "update_service_order_notes").execute({ os: "OS-00112", diagnosis: "x" }, ctxCom(faturada)) as any;
  assertStringIncludes(r.error, "faturada");
  const quebrado = bancoFalso({ service_orders: [{ ...OS_112 }] }, { "select:service_orders": "timeout" });
  const r2 = await tool(serviceOrderTools, "update_service_order_notes").execute({ os: "OS-00112", diagnosis: "x" }, ctxCom(quebrado)) as any;
  assertStringIncludes(r2.error, "timeout");
  assertEquals(quebrado.gravacoes.length, 0);
});

// ─── 2. Via do técnico ───────────────────────────────────────────────────────────────────────
const SERVICOS = () => [
  { id: "s1", service_order_id: OS_112.id, name_snapshot: "Instalação do conversor DC-DC", field_status: "a_fazer", field_status_note: null },
  { id: "s2", service_order_id: OS_112.id, name_snapshot: "Parametrização do inversor", field_status: "a_fazer", field_status_note: null },
  { id: "s3", service_order_id: OS_112.id, name_snapshot: "Troca da bomba de porão", field_status: "nao_feito", field_status_note: "sem peça" },
];

Deno.test("via: situação dita e horário dito viram o valor certo", () => {
  assertEquals(situacaoDita("feito"), "feito");
  assertEquals(situacaoDita("não foi feita"), "nao_feito");
  assertEquals(situacaoDita("ficou parcial"), "parcial");
  assertEquals(situacaoDita("aguardando peça"), "aguarda_peca");
  assertEquals(situacaoDita("só levantar"), "so_levantar");
  assertEquals(situacaoDita("talvez"), null);
  const agora = new Date("2026-10-07T20:00:00Z"); // 17h em Brasília
  assertEquals(horarioDito("8h", agora), { iso: "2026-10-07T11:00:00.000Z" });
  assertEquals(horarioDito("08:30", agora), { iso: "2026-10-07T11:30:00.000Z" });
  assertEquals(horarioDito("ontem 17h", agora), { iso: "2026-10-06T20:00:00.000Z" });
  assertEquals(horarioDito("2026-10-06T07:30", agora), { iso: "2026-10-06T10:30:00.000Z" });
  assertStringIncludes((horarioDito("19h", agora) as any).error, "ainda não chegou");
  assertEquals(horarioDito(null, agora), null);
});

Deno.test("via: acha o serviço pelo pedaço do nome e pergunta quando serve para mais de um", () => {
  const linhas = SERVICOS();
  assertEquals((acharServico(linhas, "DC-DC") as any).linha.id, "s1");
  assertEquals((acharServico(linhas, "parametrização") as any).linha.id, "s2");
  assertEquals((acharServico(linhas, "troca da bomba") as any).linha.id, "s3");
  assertEquals((acharServico(linhas, "do") as any).opcoes?.length, 2);
  assertEquals(acharServico(linhas, "pintura"), null);
});

Deno.test("via: feito limpa o motivo, parcial grava o motivo, chegada/saída e relato como a tela", async () => {
  const db = bancoFalso({ service_orders: [{ ...OS_112 }], service_order_services: SERVICOS() });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute({
    os: "OS-00112",
    servicos: [
      { servico: "DC-DC", situacao: "feito" },
      { servico: "parametrização", situacao: "parcial", motivo: "falta o cabo" },
    ],
    chegada: "2026-10-06T08:00", saida: "2026-10-06T17:00",
    relato: "Banco antigo com sulfatação",
  }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  const [s1, s2, s3] = db.tabelas.service_order_services;
  assertEquals([s1.field_status, s1.field_status_note], ["feito", null]);
  assertEquals([s2.field_status, s2.field_status_note], ["parcial", "falta o cabo"]);
  assertEquals(s3.field_status, "nao_feito"); // não citado, não muda
  const os = db.tabelas.service_orders[0];
  assertEquals(os.check_in_at, "2026-10-06T11:00:00.000Z");
  assertEquals(os.check_out_at, "2026-10-06T20:00:00.000Z");
  assertStringIncludes(os.technician_notes, "nota antiga\n\n[Via lançada em");
  assertStringIncludes(os.technician_notes, "O que encontrei / pendente / vigiar: Banco antigo com sulfatação");
  assertEquals(r.ainda_nao_feitos.map((x: any) => x.servico), ["Parametrização do inversor", "Troca da bomba de porão"]);
  assertEquals(os.status, "in_progress"); // a via não conclui a OS
});

Deno.test("via: 'todos como feitos' marca todos; não feito sem motivo pergunta e não grava nada", async () => {
  const db = bancoFalso({ service_orders: [{ ...OS_112 }], service_order_services: SERVICOS() });
  const t = tool(fieldOpsTools, "update_service_order_via");
  const recusa = await t.execute({ os: "OS-00112", servicos: [{ servico: "DC-DC", situacao: "feito" }, { servico: "bomba", situacao: "não feito" }] }, ctxCom(db)) as any;
  assertStringIncludes(recusa.error, "qual o motivo");
  assertEquals(db.gravacoes.length, 0);
  const ambigua = await t.execute({ os: "OS-00112", servicos: [{ servico: "do", situacao: "feito" }] }, ctxCom(db)) as any;
  assertStringIncludes(ambigua.error, "mais de um");
  assertEquals(db.gravacoes.length, 0);
  const r = await t.execute({ os: "OS-00112", todos: "feitos" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.service_order_services.map((s) => s.field_status), ["feito", "feito", "feito"]);
  assertEquals(db.tabelas.service_order_services[2].field_status_note, null);
  assertEquals(r.ainda_nao_feitos, []);
});

Deno.test("via: leitura dos serviços que falha diz que falhou; saída antes da chegada é recusada", async () => {
  const quebrado = bancoFalso({ service_orders: [{ ...OS_112 }], service_order_services: SERVICOS() }, { "select:service_order_services": "conexão caiu" });
  const r = await tool(fieldOpsTools, "update_service_order_via").execute({ os: "OS-00112", todos: "feito" }, ctxCom(quebrado)) as any;
  assertStringIncludes(r.error, "conexão caiu");
  const db = bancoFalso({ service_orders: [{ ...OS_112 }], service_order_services: SERVICOS() });
  const r2 = await tool(fieldOpsTools, "update_service_order_via").execute({ os: "OS-00112", chegada: "2026-10-06T17:00", saida: "2026-10-06T08:00" }, ctxCom(db)) as any;
  assertStringIncludes(r2.error, "antes da chegada");
  assertEquals(db.gravacoes.length, 0);
});

Deno.test("check-in com hora dita grava a hora dita e corrige a que já estava", async () => {
  const db = bancoFalso({ service_orders: [{ ...OS_112, status: "scheduled", check_in_at: "2026-10-06T14:00:00.000Z" }] });
  const t = tool(fieldOpsTools, "check_in_service_order");
  const semHora = await t.execute({ os: "OS-00112" }, ctxCom(db)) as any;
  assertEquals(semHora.ja_feito, true);
  const r = await t.execute({ os: "OS-00112", horario: "2026-10-06T08:00" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.service_orders[0].check_in_at, "2026-10-06T11:00:00.000Z");
  assertEquals(r.corrigido_de, "2026-10-06T14:00:00.000Z");
  const out = await tool(fieldOpsTools, "check_out_service_order").execute({ os: "OS-00112", horario: "2026-10-06T07:00" }, ctxCom(db)) as any;
  assertStringIncludes(out.error, "antes da chegada");
});

// ─── 3. Tarefa que se repete ─────────────────────────────────────────────────────────────────
const QUARTA_10H = new Date("2026-10-07T13:00:00Z"); // quarta-feira, 10h em Brasília

Deno.test("repetição: 'toda segunda às 8h' → próxima segunda 8h e BYDAY=MO; o motor gera as segundas", () => {
  const r = montarRecorrencia({ repetir: "semanal", dias_da_semana: ["segunda"] }, "2026-10-07T08:00:00-03:00", QUARTA_10H) as any;
  assertEquals(r.rrule, "FREQ=WEEKLY;BYDAY=MO");
  assertEquals(r.ancora, "2026-10-12T11:00:00.000Z");
  assertEquals(r.descricao, "toda segunda");
  const proximas = expandOccurrences(r.rrule, new Date(r.ancora), QUARTA_10H, new Date("2026-11-01T00:00:00Z"));
  assertEquals(proximas.map((d) => d.toISOString()), ["2026-10-19T11:00:00.000Z", "2026-10-26T11:00:00.000Z"]);
});

Deno.test("repetição: 'todo dia 5' anda para o próximo dia 5; 'a cada 15 dias'; às 22h o BYDAY é o de UTC", () => {
  const dia5 = montarRecorrencia({ repetir: "mensal", dia_do_mes: 5 }, null, QUARTA_10H) as any;
  assertEquals(dia5.rrule, "FREQ=MONTHLY");
  assertEquals(dia5.ancora, "2026-11-05T11:00:00.000Z");
  const quinze = montarRecorrencia({ repetir_a_cada: 15, repetir: "diaria" }, null, QUARTA_10H) as any;
  assertEquals(quinze.rrule, "FREQ=DAILY;INTERVAL=15");
  assertEquals(quinze.descricao, "a cada 15 dias");
  // Hoje 08:00 já passou às 10h: a primeira vez não nasce atrasada.
  assertEquals(quinze.ancora, "2026-10-22T11:00:00.000Z");
  const noite = montarRecorrencia({ repetir: "semanal", dias_da_semana: ["seg"] }, "2026-10-12T22:00:00-03:00", QUARTA_10H) as any;
  assertEquals(noite.rrule, "FREQ=WEEKLY;BYDAY=TU"); // 22h de segunda = 01h de terça em UTC
  assertEquals(descreverRepeticao(noite.rrule, noite.ancora), "toda segunda");
  const ate = montarRecorrencia({ repetir: "semanal", repetir_ate: "2026-12-31" }, "2026-10-09T09:00:00-03:00", QUARTA_10H) as any;
  assertEquals(ate.rrule, "FREQ=WEEKLY;UNTIL=20261231");
  assert(parseRRule(ate.rrule)?.until);
  assertStringIncludes((montarRecorrencia({ repetir: "anual" }, null, QUARTA_10H) as any).error, "ano");
  assertStringIncludes((montarRecorrencia({ repetir: "semanal", dias_da_semana: ["funday"] }, null, QUARTA_10H) as any).error, "não é dia");
});

Deno.test("status e prioridade: português vira o valor; o resto é recusado", () => {
  assertEquals(statusDaTarefa("concluída"), "done");
  assertEquals(statusDaTarefa("em andamento"), "in_progress");
  assertEquals(prioridadeDaTarefa("alta"), "high");
  assertStringIncludes((statusDaTarefa("arquivada") as any).error, "não existe");
  assertStringIncludes((prioridadeDaTarefa("máxima") as any).error, "não existe");
});

Deno.test("create_task com repetição grava a regra e a primeira vez; vínculo fora do CHECK é recusado", async () => {
  const db = bancoFalso({ agenda_tasks: [] });
  const t = tool(agendaTools, "create_task");
  const r = await t.execute({ title: "Conferir o extrato", repetir: "mensal", dia_do_mes: 5, due_at: "2026-10-05T09:00" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  const criada = db.tabelas.agenda_tasks[0];
  assertEquals(criada.rrule, "FREQ=MONTHLY");
  assert(new Date(criada.due_at) > new Date(), "a primeira vez nasceu no passado");
  assertEquals(new Date(new Date(criada.due_at).getTime() - 3 * 3600_000).getUTCDate(), 5);
  const recusa = await t.execute({ title: "x", related_entity_type: "fornecedor" }, ctxCom(db)) as any;
  assertStringIncludes(recusa.error, "não existe");
  assertEquals(db.tabelas.agenda_tasks.length, 1);
});

Deno.test("update_task: parar de repetir pela ocorrência muda a MÃE e tira as próximas pendentes", async () => {
  const futuro = new Date(Date.now() + 5 * 86_400_000).toISOString();
  const passado = new Date(Date.now() - 5 * 86_400_000).toISOString();
  const db = bancoFalso({
    agenda_tasks: [
      { id: "mae", title: "Conferir o extrato", kind: "task", status: "pending", is_private: false, due_at: passado, rrule: "FREQ=MONTHLY", recurrence_parent_id: null, checklist: [] },
      { id: "filha-futura", title: "Conferir o extrato", kind: "task", status: "pending", is_private: false, due_at: futuro, rrule: null, recurrence_parent_id: "mae", checklist: [] },
      { id: "filha-feita", title: "Conferir o extrato", kind: "task", status: "done", is_private: false, due_at: passado, rrule: null, recurrence_parent_id: "mae", checklist: [] },
    ],
  });
  const r = await tool(agendaTools, "update_task").execute({ id: "filha-futura", parar_de_repetir: true }, ctxCom(db)) as any;
  // A filha pedida é apagada junto com as outras futuras: a resposta vem da leitura feita antes.
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.repete, "não se repete mais");
  assertEquals(db.tabelas.agenda_tasks.find((t) => t.id === "mae")!.rrule, null);
  assertEquals(db.tabelas.agenda_tasks.map((t) => t.id).sort(), ["filha-feita", "mae"]);
});

Deno.test("update_task: checklist substitui mantendo o feito, campo inventado não vai ao banco, status validado", async () => {
  const db = bancoFalso({
    agenda_tasks: [{ id: "t1", title: "Revisar", kind: "task", status: "pending", is_private: false, rrule: null, recurrence_parent_id: null, checklist: [{ text: "Baterias", done: true }] }],
  });
  const t = tool(agendaTools, "update_task");
  const r = await t.execute({ id: "t1", checklist: ["Baterias", "Inversor"], campo_inventado: "x", status: "concluída" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  const tarefa = db.tabelas.agenda_tasks[0];
  assertEquals(tarefa.checklist, [{ text: "Baterias", done: true }, { text: "Inversor", done: false }]);
  assertEquals(tarefa.campo_inventado, undefined);
  assertEquals(tarefa.status, "done");
  assertEquals(tarefa.completed_by, "dono-1");
  const recusa = await t.execute({ id: "t1", status: "arquivada" }, ctxCom(db)) as any;
  assertStringIncludes(recusa.error, "não existe");
  const quebrado = bancoFalso({ agenda_tasks: [] }, { "select:agenda_tasks": "sem rede" });
  const r3 = await t.execute({ id: "t1", title: "y" }, ctxCom(quebrado)) as any;
  assertStringIncludes(r3.error, "sem rede");
});

// ─── 4. Caixa de sugestões ───────────────────────────────────────────────────────────────────
const SUGESTOES = () => [
  { id: "g1", title: "Ligar para o Miguel sobre o orçamento", kind: "task", suggested_due_at: "2026-10-08T12:00:00Z", suggested_start_at: null, priority: "normal", evidence: "te ligo amanhã", confidence: 0.9, detector: "promise", origin: "whatsapp", contact_label: "Miguel", related_entity_type: "client", related_entity_id: "c-miguel", client_id: "c-miguel", target_user_id: null, status: "pending", created_at: new Date().toISOString() },
  { id: "g2", title: "Cobrar fornecedor de tinta", kind: "task", suggested_due_at: null, suggested_start_at: null, priority: "high", evidence: "a tinta chega quando?", confidence: 0.7, detector: "followup", origin: "whatsapp", contact_label: "Tintas Sul", related_entity_type: null, related_entity_id: null, client_id: null, target_user_id: null, status: "pending", created_at: new Date().toISOString() },
  { id: "g3", title: "Ligar para o Miguel Souza", kind: "task", suggested_due_at: null, suggested_start_at: null, priority: "normal", evidence: "x", confidence: 0.5, detector: "promise", origin: "whatsapp", contact_label: "Miguel Souza", related_entity_type: null, related_entity_id: null, client_id: null, target_user_id: "outra-pessoa", status: "pending", created_at: new Date().toISOString() },
];

Deno.test("sugestões: lista as pendentes; quem não é admin não vê as de outra pessoa; leitura que falha diz", async () => {
  const db = bancoFalso({ agenda_suggestions: SUGESTOES() });
  const t = tool(agendaSugestaoTools, "list_agenda_suggestions");
  const admin = await t.execute({}, ctxCom(db)) as any;
  assertEquals(admin.total_pendentes, 3);
  const tecnico = await t.execute({}, ctxCom(db, "technician", "tec-1")) as any;
  assertEquals(tecnico.sugestoes.map((s: any) => s.id), ["g1", "g2"]);
  const quebrado = bancoFalso({ agenda_suggestions: SUGESTOES() }, { "select:agenda_suggestions": "fora do ar" });
  const r = await t.execute({}, ctxCom(quebrado)) as any;
  assertStringIncludes(r.error, "fora do ar");
  assertEquals(filtrarSugestoes(SUGESTOES(), "fornecedor de tinta").map((s) => s.id), ["g2"]);
});

Deno.test("sugestões: aceitar com ajuste de data cria a tarefa como a tela e marca a sugestão; ambígua pergunta", async () => {
  const db = bancoFalso({ agenda_suggestions: SUGESTOES(), agenda_tasks: [] });
  const t = tool(agendaSugestaoTools, "accept_agenda_suggestions");
  const ambigua = await t.execute({ busca: "Miguel" }, ctxCom(db)) as any;
  assertStringIncludes(ambigua.error, "Qual delas");
  assertEquals(db.tabelas.agenda_tasks.length, 0);
  const r = await t.execute({ busca: "Miguel orçamento", quando: "2026-10-08T10:00" }, ctxCom(db)) as any;
  assert(r.ok, JSON.stringify(r));
  const tarefa = db.tabelas.agenda_tasks[0];
  assertEquals(tarefa.due_at, "2026-10-08T13:00:00.000Z");
  assertEquals([tarefa.source, tarefa.assignee_user_id, tarefa.related_entity_type, tarefa.client_id], ["ai", "dono-1", "client", "c-miguel"]);
  assertStringIncludes(tarefa.notes, 'conversa com Miguel\n"te ligo amanhã"');
  const sug = db.tabelas.agenda_suggestions.find((s) => s.id === "g1")!;
  assertEquals([sug.status, sug.created_task_id, sug.resolved_by], ["accepted", tarefa.id, "dono-1"]);
  // Aceitar de novo não cria outra tarefa: a sugestão já não está pendente.
  const deNovo = await t.execute({ ids: ["g1"] }, ctxCom(db)) as any;
  assertStringIncludes(deNovo.error, "não está");
  assertEquals(db.tabelas.agenda_tasks.length, 1);
});

Deno.test("sugestões: se marcar a sugestão falhar, a tarefa criada sai (nada de órfã)", async () => {
  const db = bancoFalso({ agenda_suggestions: SUGESTOES(), agenda_tasks: [] }, { "update:agenda_suggestions": "bloqueado" });
  const r = await tool(agendaSugestaoTools, "accept_agenda_suggestions").execute({ ids: ["g2"] }, ctxCom(db)) as any;
  assertStringIncludes(r.error, "bloqueado");
  assertEquals(db.tabelas.agenda_tasks.length, 0);
});

Deno.test("sugestões: descartar com motivo e aceitar todas de hoje", async () => {
  const db = bancoFalso({ agenda_suggestions: SUGESTOES(), agenda_tasks: [] });
  const d = await tool(agendaSugestaoTools, "dismiss_agenda_suggestions").execute({ busca: "fornecedor de tinta", motivo: "já resolvido" }, ctxCom(db)) as any;
  assert(d.ok, JSON.stringify(d));
  const g2 = db.tabelas.agenda_suggestions.find((s) => s.id === "g2")!;
  assertEquals([g2.status, g2.dismiss_reason], ["dismissed", "já resolvido"]);
  const todas = await tool(agendaSugestaoTools, "accept_agenda_suggestions").execute({ todas_de_hoje: true }, ctxCom(db)) as any;
  assertEquals(todas.aceitas, 2);
  assertEquals(db.tabelas.agenda_suggestions.filter((s) => s.status === "pending").length, 0);
});
