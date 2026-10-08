// Planos de manutenção pelo assistente (07/10/2026). Banco falso que filtra de verdade, grava em
// memória e registra as chamadas de RPC — para conferir o que vai para cada coluna e para cada
// função do banco (as mesmas que a tela usa), o caminho feliz, a recusa e a leitura que falha.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  casaComCriterio,
  criterioPeloNome,
  dataDoServicoDita,
  dataFuturaDita,
  planosManutencaoTools,
  resumirLembreteDeRevisao,
  toqueParaAgora,
} from "./planos-manutencao.ts";
import { CHAVE_DO_RETRATO } from "./registry.ts";
import { eventosDaProposta, proporCampanha, proporToques } from "../../revisao/rodada.ts";
import { hojeEmBrasilia, somarDias } from "../../revisao/texto.ts";
import { payloadDaProposta, perguntaAoDono, referenciaParaOAssistente } from "../../revisao/lembretes.ts";

// ─── Banco falso ─────────────────────────────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
type Linha = Record<string, any>;
type Filtro = (l: Linha) => boolean;

function bancoFalso(tabelas: Record<string, Linha[]>, opcoes: { falhas?: Record<string, string>; rpc?: Record<string, unknown> } = {}) {
  const falhas = opcoes.falhas ?? {};
  const gravacoes: Array<{ op: string; tabela: string; valor?: unknown }> = [];
  const rpcs: Array<{ nome: string; args: Linha }> = [];
  let seq = 0;
  function consulta(tabela: string) {
    const filtros: Filtro[] = [];
    let op: "select" | "update" | "insert" = "select";
    // deno-lint-ignore no-explicit-any
    let valor: any = null;
    let unico = false;
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
        resultado = alvo.map((l) => ({ ...l }));
      }
      if (unico) return { data: resultado[0] ?? null, error: null };
      return { data: op === "select" || devolve ? resultado : null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: () => { if (op !== "select") devolve = true; return q; },
      eq: (c: string, v: unknown) => { filtros.push((l) => l[c] === v); return q; },
      in: (c: string, vs: unknown[]) => { filtros.push((l) => vs.includes(l[c])); return q; },
      lte: (c: string, v: string) => { filtros.push((l) => l[c] != null && String(l[c]) <= v); return q; },
      gte: (c: string, v: string) => { filtros.push((l) => l[c] != null && String(l[c]) >= v); return q; },
      lt: (c: string, v: string) => { filtros.push((l) => l[c] != null && String(l[c]) < v); return q; },
      not: (c: string, _op: string, _v: unknown) => { filtros.push((l) => l[c] != null); return q; },
      ilike: (c: string, p: string) => {
        const t = p.replace(/%/g, "").toLowerCase();
        filtros.push((l) => String(l[c] ?? "").toLowerCase().includes(t));
        return q;
      },
      order: () => q, limit: () => q,
      update: (v: unknown) => { op = "update"; valor = v; return q; },
      insert: (v: unknown) => { op = "insert"; valor = v; return q; },
      single: () => { unico = true; return Promise.resolve(executar()); },
      maybeSingle: () => { unico = true; return Promise.resolve(executar()); },
      // deno-lint-ignore no-explicit-any
      then: (ok: any, ko: any) => Promise.resolve(executar()).then(ok, ko),
    };
    return q;
  }
  const rpc = (nome: string, args: Linha) => {
    rpcs.push({ nome, args });
    const r = opcoes.rpc?.[nome];
    if (r && typeof r === "object" && "erro_do_banco" in (r as Linha)) return Promise.resolve({ data: null, error: { message: (r as Linha).erro_do_banco } });
    return Promise.resolve({ data: r ?? { ok: true }, error: null });
  };
  return { from: consulta, rpc, gravacoes, rpcs, tabelas };
}
const ctxCom = (db: unknown, userRole = "admin", userId = "dono-1") =>
  ({ sb: db, admin: db, userId, userRole, jwt: "", appOrigin: "", settings: {} }) as never;
const tool = (nome: string) => planosManutencaoTools.find((t) => t.name === nome)!;

// ─── Dados ───────────────────────────────────────────────────────────────────────────────────
const MAR_AZUL = { id: "11111111-1111-4111-8111-111111111111", name: "Mar Azul", client_id: "c-carlos", active: true, battery_bank_summary: "4x AGM 105Ah", inverter_charger_summary: null, engine_brand: null, engine_model: null, engine_type: null, clients: { name: "Carlos Souza" } };
const MAR_BRAVO = { id: "22222222-2222-4222-8222-222222222222", name: "Mar Bravo", client_id: "c-ana", active: true, clients: { name: "Ana" } };
const PLANO_ID = "33333333-3333-4333-8333-333333333333";
const OS_ID = "44444444-4444-4444-8444-444444444444";

const hoje = hojeEmBrasilia();
const linhaDaView = (o: Linha = {}) => ({
  plan_id: PLANO_ID, vessel_id: MAR_AZUL.id, vessel_name: "Mar Azul", client_id: "c-carlos", client_name: "Carlos Souza",
  client_phone: "(47) 99915-9654", opt_out: false, plan_name: "Revisão das baterias", name: "Revisão das baterias",
  scope: null, estimated_value: 1500, interval_months: 12, last_service_at: "2025-10-28", last_service_order_id: null,
  next_due_on: somarDias(hoje, 21), window_opens_on: hoje, snoozed_until: null, dias_para_vencer: 21, situacao: "na_janela",
  tem_os_agendada: false, os_agendada_numero: null, ultimo_toque: null, respondeu_no_ciclo: false,
  client_reminder_enabled: true, ...o,
});
const plano = (o: Linha = {}) => ({ id: PLANO_ID, name: "Revisão das baterias", vessel_id: MAR_AZUL.id, active: true, vessels: { name: "Mar Azul" }, ...o });

// ─── Regras puras ───────────────────────────────────────────────────────────────────────────
Deno.test("critério: o nome do plano sugere sistema e palavras; as palavras estreitam o sistema", () => {
  assertEquals(criterioPeloNome("Revisão das baterias"), { service_system: "eletrico_dc", match_keywords: ["bateria"] });
  assertEquals(criterioPeloNome("Revisão do motor"), { service_system: "mecanico", match_keywords: ["motor", "oleo"] });
  assertEquals(criterioPeloNome("Inversor/carregador"), { service_system: null, match_keywords: ["inversor", "carregador"] });
  assertEquals(criterioPeloNome("Revisão anual"), { service_system: null, match_keywords: [] });
  const baterias = criterioPeloNome("baterias");
  const conversor = [{ service_order_id: "o", name_snapshot: "Instalação de conversor DC-DC", service_system: "eletrico_dc", service_verb: "instalacao" }];
  assertEquals(casaComCriterio(baterias, conversor, []), false, "serviço DC sem 'bateria' não zera o plano das baterias");
  assertEquals(casaComCriterio(baterias, conversor, [{ service_order_id: "o", nome: "Bateria AGM 105Ah" }]), true, "a peça conta");
  assertEquals(casaComCriterio(baterias, [{ ...conversor[0], name_snapshot: "Troca de baterias" }], []), true);
  assertEquals(casaComCriterio({ service_system: null, match_keywords: [] }, [], []), true, "sem critério: qualquer OS");
  assertEquals(casaComCriterio({ service_system: "mecanico", match_keywords: [] }, conversor, []), false);
});

Deno.test("datas ditas: serviço no passado, adiamento no futuro", () => {
  const agora = new Date("2026-10-07T15:00:00Z");
  assertEquals(dataDoServicoDita("01/10/2026", agora), { iso: "2026-10-01" });
  assertEquals(dataDoServicoDita("15/10", agora), { iso: "2025-10-15" }, "dd/mm que ainda não chegou é do ano passado");
  assertEquals(dataDoServicoDita("ontem", agora), { iso: "2026-10-06" });
  assertStringIncludes((dataDoServicoDita("15/10/2026", agora) as { error: string }).error, "ainda não chegou");
  assertEquals(dataDoServicoDita("", agora), null);
  assertEquals(dataFuturaDita("mês que vem", agora), { iso: "2026-11-01" });
  assertEquals(dataFuturaDita("2026-12-15", agora), { iso: "2026-12-15" });
  assertStringIncludes((dataFuturaDita("2026-10-01", agora) as { error: string }).error, "não é depois de hoje");
  assertStringIncludes((dataFuturaDita("quando der", agora) as { error: string }).error, "Não entendi");
  assertEquals(toqueParaAgora({ dias_para_vencer: 10, ultimo_toque: null }), { toque: 1 });
  assertEquals(toqueParaAgora({ dias_para_vencer: -3, ultimo_toque: null }), { toque: 3 }, "vencido sem nada enviado: o texto de 'venceu'");
  assertEquals(toqueParaAgora({ dias_para_vencer: 5, ultimo_toque: 1 }), { toque: 2 });
  assertStringIncludes((toqueParaAgora({ dias_para_vencer: -20, ultimo_toque: 3 }) as { error: string }).error, "3 lembretes");
});

// ─── list_maintenance_plans ─────────────────────────────────────────────────────────────────
Deno.test("listar: filtra 'vencendo_30', soma a receita; técnico não vê valor; leitura que falha diz que falhou", async () => {
  const db = bancoFalso({
    v_maintenance_plans_due: [
      linhaDaView(),
      linhaDaView({ plan_id: "p2", plan_name: "Revisão do motor", dias_para_vencer: 90, situacao: "em_dia", estimated_value: 2000 }),
      linhaDaView({ plan_id: "p3", vessel_name: "Brisa", client_name: "Ana", dias_para_vencer: 3, estimated_value: 500 }),
    ],
  });
  const r = await tool("list_maintenance_plans").execute({ situacao: "vencendo_30" }, ctxCom(db)) as Linha;
  assertEquals(r.count, 2);
  assertEquals(r.receita_prevista.replace(/\s/g, " "), "R$ 2.000,00");
  assertEquals(r.planos.map((p: Linha) => p.plano_id), [PLANO_ID, "p3"]);
  const porBarco = await tool("list_maintenance_plans").execute({ embarcacao: "brisa" }, ctxCom(db)) as Linha;
  assertEquals(porBarco.count, 1);
  const tecnico = await tool("list_maintenance_plans").execute({}, ctxCom(db, "technician")) as Linha;
  assertEquals("receita_prevista" in tecnico, false);
  assertEquals("valor_estimado" in tecnico.planos[0], false);
  const quebrado = bancoFalso({}, { falhas: { "select:v_maintenance_plans_due": "timeout" } });
  const e = await tool("list_maintenance_plans").execute({}, ctxCom(quebrado)) as Linha;
  assertStringIncludes(e.error, "timeout");
});

// ─── create_maintenance_plan ────────────────────────────────────────────────────────────────
Deno.test("criar: embarcação pelo nome, critério pelo nome do plano e último serviço achado na OS", async () => {
  const db = bancoFalso({
    vessels: [MAR_AZUL, MAR_BRAVO],
    maintenance_plans: [],
    service_orders: [
      { id: OS_ID, vessel_id: MAR_AZUL.id, service_order_number: "OS-00112", status: "completed", check_out_at: "2025-10-29T01:30:00Z", scheduled_end_at: null, updated_at: "2025-11-02T10:00:00Z" },
      { id: "os-outra", vessel_id: MAR_AZUL.id, service_order_number: "OS-00130", status: "completed", check_out_at: "2026-03-10T15:00:00Z", scheduled_end_at: null, updated_at: null },
    ],
    service_order_services: [
      { service_order_id: OS_ID, name_snapshot: "Troca do banco de baterias", service_system: "eletrico_dc", service_verb: "substituicao", line_total: 800 },
      { service_order_id: "os-outra", name_snapshot: "Instalação de conversor DC-DC", service_system: "eletrico_dc", service_verb: "instalacao", line_total: 400 },
    ],
    service_order_parts: [],
    v_maintenance_plans_due: [],
  });
  const r = await tool("create_maintenance_plan").execute(
    { embarcacao: "mar azul", nome: "Revisão das baterias", intervalo_meses: 12, valor_estimado: 1500 },
    ctxCom(db),
  ) as Linha;
  assert(r.ok, JSON.stringify(r));
  const criado = db.tabelas.maintenance_plans[0];
  assertEquals(criado.vessel_id, MAR_AZUL.id);
  assertEquals(criado.service_system, "eletrico_dc");
  assertEquals(criado.match_keywords, ["bateria"]);
  // 01h30 UTC de 29/10 = 22h30 de 28/10 em Brasília; a OS do conversor (mais nova) não conta.
  assertEquals(criado.last_service_at, "2025-10-28");
  assertEquals(criado.last_service_order_id, OS_ID);
  assertEquals(criado.source, "manual");
  assertEquals(criado.created_by, "dono-1");
  assertEquals(criado.client_reminder_enabled, true);
  assertStringIncludes(r.message, "OS-00112");
});

Deno.test("criar: nome parecido pergunta, plano repetido recusa, leitura que falha diz que falhou", async () => {
  const db = bancoFalso({ vessels: [MAR_AZUL, MAR_BRAVO], maintenance_plans: [plano()] });
  const ambiguo = await tool("create_maintenance_plan").execute({ embarcacao: "Mar", nome: "Revisão do motor", intervalo_meses: 12 }, ctxCom(db)) as Linha;
  assertStringIncludes(ambiguo.error, "mais de uma");
  assertEquals(ambiguo.opcoes.sort(), ["Mar Azul", "Mar Bravo"]);
  const repetido = await tool("create_maintenance_plan").execute({ embarcacao: "Mar Azul", nome: "revisão das baterias", intervalo_meses: 12 }, ctxCom(db)) as Linha;
  assertStringIncludes(repetido.error, "já tem o plano");
  assertEquals(db.gravacoes.length, 0);
  const quebrado = bancoFalso({ vessels: [MAR_AZUL] }, { falhas: { "select:vessels": "conexão perdida" } });
  const e = await tool("create_maintenance_plan").execute({ embarcacao: "Mar Azul", nome: "X", intervalo_meses: 12 }, ctxCom(quebrado)) as Linha;
  assertStringIncludes(e.error, "conexão perdida");
  assertEquals(tool("create_maintenance_plan").preValidar!({ embarcacao: "Mar Azul", nome: "X", intervalo_meses: 0 }, ctxCom(db))?.error, "O intervalo tem de ser de 1 a 60 meses.");
  assertEquals((await tool("create_maintenance_plan").execute({ embarcacao: "Mar Azul", nome: "X", intervalo_meses: 12 }, ctxCom(db, "technician")) as Linha).error, "Cargo não autorizado para criar plano de manutenção.");
});

// ─── update_maintenance_plan ────────────────────────────────────────────────────────────────
Deno.test("alterar: desliga o lembrete e muda o valor, devolvendo o antes e depois", async () => {
  const db = bancoFalso({ vessels: [MAR_AZUL], maintenance_plans: [plano({ estimated_value: 1500, client_reminder_enabled: true })] });
  const r = await tool("update_maintenance_plan").execute({ embarcacao: "Mar Azul", lembrete_ao_cliente: false, valor_estimado: 1800 }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.tabelas.maintenance_plans[0].client_reminder_enabled, false);
  assertEquals(r.mudou.estimated_value, { antes: 1500, depois: 1800 });
  const nada = await tool("update_maintenance_plan").execute({ embarcacao: "Mar Azul" }, ctxCom(db)) as Linha;
  assertStringIncludes(nada.error, "o que mudar");
});

// ─── register_plan_service / snooze ─────────────────────────────────────────────────────────
Deno.test("serviço feito: a MESMA função da tela, com a OS pelo número, a data dita e quem fez", async () => {
  const db = bancoFalso(
    { vessels: [MAR_AZUL], maintenance_plans: [plano()], service_orders: [{ id: OS_ID, service_order_number: "OS-00112", status: "completed", share_token: null, updated_at: null }] },
    { rpc: { registrar_servico_do_plano: { ok: true, message: "Serviço registrado." } } },
  );
  const r = await tool("register_plan_service").execute({ embarcacao: "Mar Azul", data: "01/10/2026", os: "OS-00112" }, ctxCom(db, "admin", "dono-1")) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.rpcs, [{ nome: "registrar_servico_do_plano", args: { p_plano: PLANO_ID, p_data: "2026-10-01", p_os: OS_ID, p_autor: "dono-1" } }]);
  // Erro do banco (ex.: OS de outra embarcação) volta como erro.
  const db2 = bancoFalso({ vessels: [MAR_AZUL], maintenance_plans: [plano()] }, { rpc: { registrar_servico_do_plano: { erro_do_banco: "A OS-00112 é de outra embarcação." } } });
  const e = await tool("register_plan_service").execute({ plano: PLANO_ID }, ctxCom(db2)) as Linha;
  assertEquals(e.error, "A OS-00112 é de outra embarcação.");
  assertEquals(db2.rpcs[0].args.p_data, null, "sem data: o banco usa hoje de Brasília");
});

Deno.test("adiar: data dita vira AAAA-MM-DD e vai para adiar_plano; data passada recusa sem chamar o banco", async () => {
  const db = bancoFalso({ vessels: [MAR_AZUL], maintenance_plans: [plano()] }, { rpc: { adiar_plano: { ok: true, message: "adiado" } } });
  const r = await tool("snooze_maintenance_plan").execute({ embarcacao: "Mar Azul", ate: "2099-12-15", motivo: "cliente viajando" }, ctxCom(db)) as Linha;
  assert(r.ok);
  assertEquals(db.rpcs[0], { nome: "adiar_plano", args: { p_plano: PLANO_ID, p_ate: "2099-12-15", p_motivo: "cliente viajando", p_autor: "dono-1" } });
  const passado = await tool("snooze_maintenance_plan").execute({ embarcacao: "Mar Azul", ate: "2020-01-01" }, ctxCom(db)) as Linha;
  assertStringIncludes(passado.error, "não é depois de hoje");
  assertEquals(db.rpcs.length, 1);
});

// ─── Lembrete ao cliente ────────────────────────────────────────────────────────────────────
function bancoDoLembrete(view: Linha = {}, rpc: Record<string, unknown> = {}) {
  return bancoFalso({
    vessels: [MAR_AZUL],
    maintenance_plans: [plano()],
    v_maintenance_plans_due: [linhaDaView(view)],
    clients: [{ id: "c-carlos", name: "Carlos Souza", display_name: null, type: "individual" }],
    service_order_services: [],
  }, { rpc });
}

Deno.test("lembrete agora: o retrato guarda o texto que o dono viu, e é ELE que vai ao RPC", async () => {
  const db = bancoDoLembrete({}, { enviar_lembrete_de_revisao: { ok: true, enviado: true, message: "Lembrete na fila.", cliente: "Carlos Souza" } });
  const t = tool("send_maintenance_reminder_now");
  const retrato = await t.retratoDaPendencia!({ embarcacao: "Mar Azul" }, ctxCom(db)) as Linha;
  assertEquals(retrato.planos, [PLANO_ID]);
  assertEquals(retrato.toque, 1);
  assertStringIncludes(retrato.texto, "Oi, Carlos! Aqui é da HBR Marine. A revisão das baterias da Mar Azul vence dia");
  assertStringIncludes(retrato.texto, "responda PARAR.");
  const resumo = await resumirLembreteDeRevisao(db, "send_maintenance_reminder_now", { embarcacao: "Mar Azul" });
  assertStringIncludes(resumo!, retrato.texto);
  assertStringIncludes(resumo!, "+55 (47) 99915-9654");
  assertStringIncludes(resumo!, "1º lembrete");

  const r = await t.execute({ embarcacao: "Mar Azul", [CHAVE_DO_RETRATO]: { ...retrato, texto: "TEXTO APROVADO" } }, ctxCom(db)) as Linha;
  assert(r.ok, JSON.stringify(r));
  assertEquals(db.rpcs[0], {
    nome: "enviar_lembrete_de_revisao",
    args: { p_planos: [PLANO_ID], p_toque: 1, p_texto: "TEXTO APROVADO", p_autor: "dono-1", p_embarcacao: null },
  });
});

Deno.test("lembrete agora: opt-out e lembrete desligado recusam antes de virar pedido; vendedor não manda", async () => {
  const optOut = bancoDoLembrete({ opt_out: true });
  assertEquals(await tool("send_maintenance_reminder_now").retratoDaPendencia!({ embarcacao: "Mar Azul" }, ctxCom(optOut)), null);
  const resumo = await resumirLembreteDeRevisao(optOut, "send_maintenance_reminder_now", { embarcacao: "Mar Azul" });
  assert(resumo!.startsWith("⚠️") && resumo!.includes("pediu para não receber"), resumo!);
  const desligado = bancoDoLembrete({ client_reminder_enabled: false });
  const r = await tool("send_maintenance_reminder_now").execute({ embarcacao: "Mar Azul" }, ctxCom(desligado)) as Linha;
  assertStringIncludes(r.error, "desligado");
  assertEquals(desligado.rpcs.length, 0);
  assertStringIncludes(tool("send_maintenance_reminder_now").preValidar!({ embarcacao: "Mar Azul" }, ctxCom(desligado, "seller"))!.error, "administrador ou financeiro");
});

Deno.test("enviar_lembrete_de_revisao: executa o RPC com quem aprovou; pulado e erro do banco viram erro", async () => {
  const t = tool("enviar_lembrete_de_revisao");
  const ok = bancoDoLembrete({}, { enviar_lembrete_de_revisao: { ok: true, enviado: true, teste: true, enviado_para: "o número de TESTE (5547...)", message: "Lembrete na fila (modo de teste)." } });
  const r = await t.execute({ planos: [PLANO_ID], toque: 2, texto: "Carlos, só lembrando…" }, ctxCom(ok, "financial", "fin-1")) as Linha;
  assert(r.ok);
  assertEquals(r.enviado_para, "o número de TESTE (5547...)");
  assertEquals(ok.rpcs[0].args, { p_planos: [PLANO_ID], p_toque: 2, p_texto: "Carlos, só lembrando…", p_autor: "fin-1", p_embarcacao: null });

  const pulado = bancoDoLembrete({}, { enviar_lembrete_de_revisao: { enviado: false, pulado: "os_agendada", error: "Não mandei: já há OS aberta/agendada para a Mar Azul." } });
  const p = await t.execute({ planos: [PLANO_ID], toque: 1, texto: "x" }, ctxCom(pulado)) as Linha;
  assertStringIncludes(p.error, "Não mandei");
  assertEquals(p.pulado, "os_agendada");

  const erro = bancoDoLembrete({}, { enviar_lembrete_de_revisao: { erro_do_banco: "Só administrador ou financeiro manda lembrete de revisão ao cliente." } });
  assertStringIncludes((await t.execute({ planos: [PLANO_ID], toque: 1, texto: "x" }, ctxCom(erro)) as Linha).error, "Só administrador");

  // Campanha sem plano: a embarcação pelo nome vira o id para o RPC.
  const camp = bancoDoLembrete({}, { enviar_lembrete_de_revisao: { ok: true } });
  await t.execute({ planos: [], toque: 0, texto: "Oi!", embarcacao: "Mar Azul" }, ctxCom(camp));
  assertEquals(camp.rpcs[0].args.p_embarcacao, MAR_AZUL.id);

  assertStringIncludes(t.preValidar!({ planos: [PLANO_ID], toque: 1, texto: "  " }, ctxCom(ok))!.error, "vazio");
  assertStringIncludes(t.preValidar!({ planos: [PLANO_ID], toque: 1, texto: "x" }, ctxCom(ok, "technician"))!.error, "administrador ou financeiro");

  const resumo = await resumirLembreteDeRevisao(ok, "enviar_lembrete_de_revisao", { planos: [PLANO_ID], toque: 2, texto: "Carlos, só lembrando…" });
  assertStringIncludes(resumo!, "Para: *Carlos Souza* — WhatsApp +55 (47) 99915-9654");
  assertStringIncludes(resumo!, "2º lembrete");
  assertStringIncludes(resumo!, 'Mensagem: "Carlos, só lembrando…"');
});

// ─── suggest_maintenance_plans ──────────────────────────────────────────────────────────────
Deno.test("sugerir: propõe baterias pela última OS (com valor) e pula o que já tem plano", async () => {
  const db = bancoFalso({
    vessels: [{ ...MAR_AZUL, engine_brand: "Volvo", engine_model: "D6" }],
    maintenance_plans: [{ vessel_id: MAR_AZUL.id, name: "Revisão do motor", service_system: "mecanico", match_keywords: ["motor"], active: true }],
    service_orders: [{ id: OS_ID, vessel_id: MAR_AZUL.id, service_order_number: "OS-00112", status: "invoiced", check_out_at: "2025-10-28T15:00:00Z", scheduled_end_at: null, updated_at: null }],
    service_order_services: [{ service_order_id: OS_ID, name_snapshot: "Troca do banco de baterias", service_system: "eletrico_dc", service_verb: "substituicao", line_total: 800 }],
    service_order_parts: [{ service_order_id: OS_ID, line_total_sale: 4000, products: { name: "Bateria AGM 105Ah" } }],
  });
  const r = await tool("suggest_maintenance_plans").execute({}, ctxCom(db)) as Linha;
  assertEquals(r.propostas.map((p: Linha) => p.nome), ["Revisão das baterias"]);
  const p = r.propostas[0];
  assertEquals(p.ultimo_servico_em, "28/10/2025");
  assertEquals(p.os_do_ultimo_servico, "OS-00112");
  assertEquals(p.valor_estimado, 800);
  assertEquals(p.sistema, "eletrico_dc");
  assertEquals(p.origem, "sugerido");
  assertEquals(db.gravacoes.length, 0, "só leitura");
  const quebrado = bancoFalso({}, { falhas: { "select:service_orders": "timeout" } });
  assertStringIncludes((await tool("suggest_maintenance_plans").execute({}, ctxCom(quebrado)) as Linha).error, "timeout");
});

// ─── maintenance_reminder_metrics ───────────────────────────────────────────────────────────
Deno.test("métricas: um envio com dois planos conta UMA vez; OS até 30 dias depois é agendamento", async () => {
  const envio = "2026-09-01T12:00:00Z";
  const db = bancoFalso({
    maintenance_plan_events: [
      { plan_id: "p1", vessel_id: "v1", client_id: "c1", due_on: "2026-09-22", tipo: "reminder_proposed", toque: 1, detalhe: {}, created_at: "2026-09-01T11:00:00Z" },
      { plan_id: "p1", vessel_id: "v1", client_id: "c1", due_on: "2026-09-22", tipo: "reminder_sent", toque: 1, detalhe: { fila_id: "f1" }, created_at: envio },
      { plan_id: "p2", vessel_id: "v1", client_id: "c1", due_on: "2026-09-30", tipo: "reminder_sent", toque: 1, detalhe: { fila_id: "f1" }, created_at: envio },
      { plan_id: "p1", vessel_id: "v1", client_id: "c1", due_on: "2026-09-22", tipo: "client_replied", toque: null, detalhe: { intencao: "sim", envio_em: envio }, created_at: "2026-09-01T13:00:00Z" },
      { plan_id: "p2", vessel_id: "v1", client_id: "c1", due_on: "2026-09-30", tipo: "client_replied", toque: null, detalhe: { intencao: "sim", envio_em: envio }, created_at: "2026-09-01T13:00:00Z" },
      { plan_id: "p1", vessel_id: "v1", client_id: "c1", due_on: "2026-09-22", tipo: "serviced", toque: null, detalhe: { data: "2026-09-25" }, created_at: "2026-09-25T20:00:00Z" },
      { plan_id: "p9", vessel_id: "v9", client_id: "c9", due_on: "2026-09-22", tipo: "client_replied", toque: null, detalhe: { intencao: "parar", envio_em: "2026-09-02T12:00:00Z" }, created_at: "2026-09-03T13:00:00Z" },
    ],
    ai_operator_pending_actions: [
      { action_name: "enviar_lembrete_de_revisao", status: "executed", created_at: "2026-09-01T11:00:00Z" },
      { action_name: "enviar_lembrete_de_revisao", status: "rejected", created_at: "2026-09-01T11:00:00Z" },
    ],
    service_orders: [
      { id: "os1", vessel_id: "v1", status: "scheduled", created_at: "2026-09-05T12:00:00Z", grand_total: 2400 },
      { id: "os2", vessel_id: "v1", status: "draft", created_at: "2026-09-04T12:00:00Z", grand_total: 999 },
    ],
  });
  const r = await tool("maintenance_reminder_metrics").execute({ de: "2026-09-01", ate: "2026-09-30" }, ctxCom(db)) as Linha;
  assertEquals(r.propostos, 1);
  assertEquals(r.enviados, 1);
  assertEquals(r.respostas, 2);
  assertEquals(r.parar, 1);
  assertEquals(r.aprovados, 1);
  assertEquals(r.recusados, 1);
  assertEquals(r.agendamentos, 1);
  assertEquals(r.receita_das_os.replace(/\s/g, " "), "R$ 2.400,00");
  assertEquals(r.atraso_medio_dias, 3);
  const quebrado = bancoFalso({}, { falhas: { "select:maintenance_plan_events": "timeout" } });
  assertStringIncludes((await tool("maintenance_reminder_metrics").execute({}, ctxCom(quebrado)) as Linha).error, "timeout");
});

// ─── A rodada da edge (toques e campanha) ───────────────────────────────────────────────────
Deno.test("rodada: o toque devido vira proposta com o texto pronto; opt-out vira pulado", async () => {
  const db = bancoFalso({
    v_maintenance_plans_due: [
      linhaDaView(),
      linhaDaView({ plan_id: "p-opt", client_id: "c-ana", client_name: "Ana", vessel_name: "Brisa", opt_out: true }),
    ],
    maintenance_plan_events: [],
    clients: [{ id: "c-carlos", name: "Carlos Souza", display_name: null, type: "individual" }],
    service_order_services: [],
  });
  const r = await proporToques(db, hoje);
  assertEquals(r.propostas.length, 1);
  assertEquals(r.propostas[0].titulo, "Lembrete de revisão para Carlos Souza (Mar Azul)");
  assertEquals(r.propostas[0].telefone, "5547999159654");
  assertStringIncludes(r.propostas[0].texto, "Oi, Carlos!");
  assertEquals(r.pulados.map((p) => [p.plano.plan_id, p.motivo]), [["p-opt", "opt_out"]]);
  // A pergunta ao dono: para quem, o número inteiro, o texto exato, e como responder.
  const pergunta = perguntaAoDono(r.propostas[0], false, 2);
  assertStringIncludes(pergunta, "Lembretes de revisão para aprovar hoje: 2.");
  assertStringIncludes(pergunta, "Posso mandar este lembrete para Carlos Souza (Mar Azul)?");
  assertStringIncludes(pergunta, "+55 (47) 99915-9654");
  assertStringIncludes(pergunta, `Mensagem: "${r.propostas[0].texto}"`);
  assertStringIncludes(perguntaAoDono(r.propostas[0], true, 1), "Modo de teste ligado");
  assertEquals(payloadDaProposta(r.propostas[0]), { planos: [PLANO_ID], toque: 1, texto: r.propostas[0].texto });
  assertEquals(referenciaParaOAssistente(r.propostas[0]), `[lembrete de revisão — enviar_lembrete_de_revisao: planos=${PLANO_ID}; toque=1]`);
  assertEquals(eventosDaProposta(r.propostas[0], "pend-1"), [{
    plan_id: PLANO_ID, vessel_id: MAR_AZUL.id, client_id: "c-carlos", due_on: r.propostas[0].planos[0].next_due_on,
    tipo: "reminder_proposed", toque: 1, detalhe: { pendencia_id: "pend-1", texto: r.propostas[0].texto },
  }]);
  const quebrado = bancoFalso({}, { falhas: { "select:v_maintenance_plans_due": "timeout" } });
  let erro = "";
  try { await proporToques(quebrado, hoje); } catch (e) { erro = String(e); }
  assertStringIncludes(erro, "timeout");
});

Deno.test("campanha: atendido, sem plano na temporada, sem OS aberta, não tocado no ano — e só de 15/09 a 31/10", async () => {
  const tabelas = () => ({
    service_orders: [
      { vessel_id: "v-ok", client_id: "c-ok", status: "completed", check_out_at: "2025-12-01T15:00:00Z" },
      { vessel_id: "v-aberta", client_id: "c-aberta", status: "completed", check_out_at: "2025-12-01T15:00:00Z" },
      { vessel_id: "v-aberta", client_id: "c-aberta", status: "scheduled", check_out_at: null },
      { vessel_id: "v-recente", client_id: "c-recente", status: "completed", check_out_at: "2026-09-20T15:00:00Z" },
      { vessel_id: "v-plano", client_id: "c-plano", status: "completed", check_out_at: "2025-12-01T15:00:00Z" },
      { vessel_id: "v-ja", client_id: "c-ja", status: "completed", check_out_at: "2025-12-01T15:00:00Z" },
      { vessel_id: "v-opt", client_id: "c-opt", status: "completed", check_out_at: "2025-12-01T15:00:00Z" },
    ],
    maintenance_plan_events: [{ client_id: "c-ja", tipo: "campaign_proposed", created_at: "2026-09-16T12:00:00Z" }],
    vessels: ["ok", "aberta", "recente", "plano", "ja", "opt"].map((k) => ({ id: `v-${k}`, name: `Barco ${k}`, client_id: `c-${k}`, active: true })),
    clients: ["ok", "plano", "ja", "opt"].map((k) => ({
      id: `c-${k}`, name: `Cliente ${k}`, display_name: null, type: "individual", opt_out_whatsapp: k === "opt", whatsapp: "47999159654", phone: null, active: true,
    })),
  });
  const planos = [linhaDaView({ client_id: "c-plano", next_due_on: "2026-11-15" })] as never;
  const r = await proporCampanha(bancoFalso(tabelas()), "2026-10-07", planos);
  assertEquals(r.map((p) => p.client_id), ["c-ok"]);
  assertEquals(r[0].toque, 0);
  assertEquals(r[0].planos, []);
  assertEquals(r[0].vessel_id, "v-ok");
  assertStringIncludes(r[0].texto, "parte elétrica da Barco ok conferida ainda em outubro");
  assertEquals(eventosDaProposta(r[0], "pend-9")[0].tipo, "campaign_proposed");
  assertEquals(await proporCampanha(bancoFalso(tabelas()), "2026-11-03", planos), []);
});
