// Diárias pela conversa: o que se fixa aqui é a parte que interpreta a fala (quem, que dia, inteiro/
// meio/falta, qual OS), o que vai para a confirmação e o que é mandado às funções do banco.
// O dia em si — valor gravado, um por pessoa, saldo — é das funções do banco
// (supabase/tests/diarias_conta_corrente.sql).
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/diarias_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  dataDoDito, datasDoIntervalo, diaCurto, diariasTools, numeroDito, pagamentoQueSeDivide, paramsDoCadastro, periodoDito, reembolsosDitos,
  resolverDiaria, resolverPagamento, resumirAcerto, resumirCadastro, resumirDiaria, resumirDivisaoDoPagamento, resumirEnvioAoFreelancer,
  resumirPagamento, textoDaDivisao, resolverLote, resumirLote, textoDaFilaSemIdentidade,
} from "./diarias.ts";
import { buildPendingSummary } from "../agent.ts";

/** Banco falso: só o que as tools leem. `simulacao` é o que cadastrar_freelancer devolve simulando. */
type Opcoes = {
  diaLancado?: boolean; cargo?: string; semTelefone?: boolean; semAcerto?: boolean; acertoReaberto?: boolean;
  pendencias?: Record<string, unknown>[];
  simulacao?: { data?: unknown; error?: { message: string } };
  /** Agenda de Produção, Fase 2 (P4): o que agenda_os_do_dia devolve (o plano da pessoa no dia), ou o erro dela. */
  plano?: unknown[]; erroDoPlano?: string;
  /** Fase 3 (P4): o que agenda_diaria_da_agenda devolve (a diária que a agenda lançou), ou o erro dela. */
  daAgenda?: { data?: unknown; error?: { code?: string; message: string } };
  /** PÓS-MERGE (B): o plano e a diária da agenda DIA A DIA (o lote pergunta um dia de cada vez); vale sobre plano/daAgenda. */
  planoPorDia?: Record<string, unknown[]>; daAgendaPorDia?: Record<string, unknown>;
};
function admin(opcoes: Opcoes = {}) {
  const tabelas: Record<string, any[]> = {
    work_profiles: [
      { id: "wp-rob", payee_id: "p-rob", valor_diaria: 160, vigencia_inicio: "2026-08-23", vigencia_fim: null, modo_pagamento: "diaria",
        payees: { id: "p-rob", name: "Roberto Daniel Rodrigues Correa", active: true } },
      { id: "wp-mic", payee_id: "p-mic", valor_diaria: 130, vigencia_inicio: "2026-08-23", vigencia_fim: null, modo_pagamento: "diaria",
        payees: { id: "p-mic", name: "Mickael Fernando Gonzaga", active: true } },
      { id: "wp-fel", payee_id: "p-fel", valor_diaria: 150, vigencia_inicio: "2026-01-01", vigencia_fim: null, modo_pagamento: "diaria",
        payees: { id: "p-fel", name: "Felipe Antunes", active: false } },
    ],
    work_shifts: opcoes.diaLancado
      ? [{ id: "ws-1", work_profile_id: "wp-rob", data: "2026-09-24", fracao: 0.5, valor_diaria: 160, valor_dia: 80 }]
      : [],
    service_orders: [{ id: "os60", service_order_number: "OS-00060" }, { id: "os61", service_order_number: "OS-00061" }],
    payees: [
      { id: "s-gus", name: "Gustavo Seberino da Silva", kind: "socio", active: true, app_user_id: "u-dono" },
      { id: "s-out", name: "Outro Sócio", kind: "socio", active: true, app_user_id: null },
    ],
    app_users: [{ id: "u-dono", phone_normalized: opcoes.semTelefone ? null : "5547999990000" }],
    ai_operator_pending_actions: opcoes.pendencias ?? [],
    acertos_diarias: opcoes.semAcerto ? [] : [
      { id: "ac-1", numero: 1, favorecido_id: "p-rob", de: "2026-09-01", ate: "2026-09-15", saldo_anterior: 0, dias: 10,
        trabalhado: 1600, pago_no_periodo: 600, valor_do_acerto: 1000, status: opcoes.acertoReaberto ? "reaberto" : "fechado" },
    ],
  };
  const consulta = (nome: string) => {
    const q: any = {
      _rows: [...(tabelas[nome] ?? [])],
      select() { return q; }, limit() { return q; }, order() { return q; },
      eq(coluna: string, valor: unknown) { q._rows = q._rows.filter((r: any) => r[coluna] === valor); return q; },
      in(coluna: string, valores: unknown[]) { q._rows = q._rows.filter((r: any) => valores.includes(r[coluna])); return q; },
      not(coluna: string, _op: string, _v: unknown) { q._rows = q._rows.filter((r: any) => r[coluna] != null); return q; },
      ilike(_c: string, padrao: string) {
        const alvo = padrao.replaceAll("%", "");
        q._rows = q._rows.filter((r: any) => String(r.service_order_number ?? "").includes(alvo));
        return q;
      },
      maybeSingle() { return Promise.resolve({ data: q._rows[0] ?? null, error: null }); },
      then(res: any) { return Promise.resolve({ data: q._rows, error: null }).then(res); },
    };
    return q;
  };
  const simuladas: Record<string, unknown>[] = [];
  const rpc = (n: string, a: Record<string, unknown>) => {
    simuladas.push({ n, ...a });
    if (n === "agenda_os_do_dia") {
      return Promise.resolve(opcoes.erroDoPlano
        ? { data: null, error: { message: opcoes.erroDoPlano } }
        : { data: opcoes.planoPorDia ? (opcoes.planoPorDia[String(a.p_dia)] ?? []) : opcoes.plano ?? [], error: null });
    }
    if (n === "log_app_error") return Promise.resolve({ data: null, error: null });
    if (n === "agenda_diaria_da_agenda") {
      if (opcoes.daAgendaPorDia) return Promise.resolve({ data: opcoes.daAgendaPorDia[String(a.p_dia)] ?? { lancada: false }, error: null });
      return Promise.resolve({ data: opcoes.daAgenda?.data ?? { lancada: false }, error: opcoes.daAgenda?.error ?? null });
    }
    return Promise.resolve({ data: opcoes.simulacao?.data ?? null, error: opcoes.simulacao?.error ?? null });
  };
  return { from: consulta, rpc, simuladas };
}

type Chamada = { n: string; a: Record<string, unknown> };
function ctx(opcoes: Opcoes = {}) {
  const chamadas: Chamada[] = [];
  const rpc = (n: string, a: Record<string, unknown>) => {
    chamadas.push({ n, a });
    if (n === "registrar_diaria") return Promise.resolve({ data: { ok: true, acao: "criado", message: "Roberto · qui 24/09 · faltou · R$ 0,00 — registrado." }, error: null });
    if (n === "conta_corrente_freelancer") return Promise.resolve({ data: { saldo_final: 290, estado: "deve", dias: 12, trabalhado: 1820, pago: 1530, linhas: [] }, error: null });
    if (n === "registrar_diarias_em_lote") return Promise.resolve({ data: { ok: true, quantos: (a.p_dias as unknown[]).length }, error: null });
    if (n === "apagar_diaria") return Promise.resolve({ data: { ok: true, apagado: {}, message: "Diária de Roberto em qui 24/09 apagada." }, error: null });
    if (n === "resumo_freelancers") return Promise.resolve({ data: { pessoas: [{ nome: "Roberto", dias: 12, trabalhado: 1980, pago: 1530, saldo_final: 450, estado: "deve" }] }, error: null });
    if (n === "cadastrar_freelancer") return Promise.resolve({ data: { ok: true, acao: "criado", message: "João Marcelo cadastrado: diária de R$ 150,00 desde ter 29/09." }, error: null });
    if (n === "anotar_transacao") return Promise.resolve({ data: { ok: true, aplicada: false, message: "Anotado. Quando a transação chegar do banco, ela já entra classificada." }, error: null });
    if (n === "lancar_no_caixa") return Promise.resolve({ data: { ok: true, message: "Lançado: R$ 50,00." }, error: null });
    if (n === "fechar_acerto_diarias") return Promise.resolve({ data: { ok: true, numero: 2, valor_do_acerto: 290, message: "Acerto nº 0002 fechado: … Os dias até 01/10 ficam travados." }, error: null });
    if (n === "reabrir_acerto_diarias") return Promise.resolve({ data: { ok: true, message: "Acerto nº 0001 de Roberto reaberto." }, error: null });
    return Promise.resolve({ data: null, error: { message: `rpc inesperada ${n}` } });
  };
  return {
    c: { sb: { rpc }, admin: admin(opcoes), userId: "u-dono", userRole: (opcoes.cargo ?? "admin") as any, jwt: "", appOrigin: "", settings: {} },
    chamadas,
  };
}
const tool = (nome: string) => diariasTools.find((t) => t.name === nome)!;

Deno.test("nove ferramentas: as que gravam ou mandam a terceiro pedem confirmação, consultar e o PDF para si não; todas só para gestor", () => {
  assertEquals(diariasTools.map((t) => t.name).sort(), [
    "cadastrar_freelancer", "consultar_freelancer", "dividir_pagamento_freelancer", "enviar_acerto_ao_freelancer", "enviar_extrato_freelancer",
    "fechar_acerto_freelancer", "reabrir_acerto_freelancer", "registrar_diaria", "registrar_pagamento_freelancer",
  ]);
  for (const n of ["fechar_acerto_freelancer", "reabrir_acerto_freelancer", "enviar_acerto_ao_freelancer", "dividir_pagamento_freelancer"]) assertEquals(tool(n).risk, "medium");
  assertEquals(tool("registrar_diaria").risk, "medium");
  assertEquals(tool("cadastrar_freelancer").risk, "medium");
  assertEquals(tool("registrar_pagamento_freelancer").risk, "medium");
  assertEquals(tool("consultar_freelancer").risk, "low");
  assertEquals(tool("enviar_extrato_freelancer").risk, "low");
  assertEquals((tool("registrar_pagamento_freelancer").input_schema as any).required, ["freelancer", "valor", "forma"]);
  for (const t of diariasTools) assertEquals(t.roles, ["admin", "financial"]);
  assertEquals((tool("registrar_diaria").input_schema as any).required, ["freelancer"]);
  assertEquals((tool("cadastrar_freelancer").input_schema as any).required, ["nome", "valor_diaria"]);
  // "manter" (07/10/2026): só extras/descontos do dia já lançado.
  // F5 (27/10): "faltou" não se lança mais; F3: vários trechos em "dias".
  assertEquals((tool("registrar_diaria").input_schema as any).properties.jornada.enum, ["inteiro", "meio", "apagar", "manter"]);
  assertEquals((tool("registrar_diaria").input_schema as any).properties.dias.items.properties.jornada.enum, ["inteiro", "meio", "manter"]);
});

Deno.test("a descrição separa diária de pagamento, de hora de OS e de 'apagar'", () => {
  const d = tool("registrar_diaria").description;
  assertStringIncludes(d, "Dia que ele NÃO trabalhou não se lança");
  assertStringIncludes(d, "UMA chamada com dias=[");
  assertStringIncludes(d, "sem perguntar 'lanço?' antes");
  assertStringIncludes(d, "lancar_no_caixa");
  assertStringIncludes(d, "log_service_order_hours");
  assertStringIncludes(d, "ENGANO");
});

Deno.test("resolver: o nome acha só quem tem diária e está ativo; a data e a OS como se fala", async () => {
  const { c } = ctx();
  const p = await resolverDiaria(c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "inteiro", os: "60 e 61" });
  if ("error" in p) throw new Error(p.error);
  assertEquals(p.freelancer.id, "p-rob");
  assertEquals(p.data, "2026-09-24");
  assertEquals(p.os.map((o) => o.id), ["os60", "os61"]);

  const inativo = await resolverDiaria(c as never, { freelancer: "felipe", jornada: "inteiro" });
  assertStringIncludes(String((inativo as { error: string }).error), "Os que têm diária: Roberto Daniel Rodrigues Correa, Mickael Fernando Gonzaga");

  const dataRuim = await resolverDiaria(c as never, { freelancer: "mickael", data: "semana que vem", jornada: "meio" });
  assertStringIncludes(String((dataRuim as { error: string }).error), "Não entendi a data");
});

Deno.test("'o Roberto não veio hoje': falta não se lança (F5, 27/10) — explica e não chama o banco", async () => {
  const { c, chamadas } = ctx();
  const r = await tool("registrar_diaria").execute({ freelancer: "Roberto", jornada: "faltou" }, c as never) as { error?: string };
  assertStringIncludes(String(r.error), "Dia sem trabalho não se lança");
  assertEquals(chamadas.length, 0);
  assertStringIncludes(String(tool("registrar_diaria").preValidar!({ freelancer: "roberto", jornada: "faltou" }, {} as never)?.error), "Nada foi registrado");
  assertStringIncludes(String(tool("registrar_diaria").preValidar!({ freelancer: "roberto", dias: [{ data: "21/09", jornada: "faltou" }] }, {} as never)?.error), "não se lança");
});

// PÓS-MERGE (A, 28/10/2026): os textos que a tool devolve também seguem a regra nova — a recusa diz para onde vai o fato
// (a OS do plano é os_registrar_andamento; o engano é apagar), e nem o "sim" do apagar nem a pergunta do "manter" falam
// de "faltou" como se ainda se lançasse.
Deno.test("pós-merge (A): a recusa da falta aponta o andamento e o apagar; o \"sim\" do apagar e o manter não falam de falta", async () => {
  const r = await tool("registrar_diaria").execute({ freelancer: "Roberto", jornada: "faltou" }, ctx().c as never) as { error?: string };
  assertStringIncludes(String(r.error), "os_registrar_andamento");
  assertStringIncludes(String(r.error), "apagar");
  const apagar = String(await resumirDiaria(ctx({ diaLancado: true }).c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "apagar" }));
  assertEquals(apagar.includes("faltou"), false, apagar);
  const manter = await resolverDiaria(ctx().c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "manter", extras: 10 });
  assertEquals(String((manter as { error: string }).error).includes("falta"), false, String((manter as { error: string }).error));
});

Deno.test("dia comum: grava pela função do banco, sem OS e com quem pediu; a resposta traz o saldo", async () => {
  const { c, chamadas } = ctx();
  const r = await tool("registrar_diaria").execute({ freelancer: "Roberto", jornada: "inteiro" }, c as never) as Record<string, unknown>;
  const reg = chamadas.find((x) => x.n === "registrar_diaria")!;
  assertEquals([reg.a.p_favorecido_id, reg.a.p_jornada, reg.a.p_os_ids, reg.a.p_valor_diaria, reg.a.p_origem, reg.a.p_autor],
    ["p-rob", "inteiro", null, null, "agente", "u-dono"]);
  assertStringIncludes(String(r.aviso).replace(/\u00a0/g, " "), "Saldo com Roberto Daniel Rodrigues Correa: R$ 290,00 (você deve a ele)");
});

Deno.test("'apagar' só apaga o dia que existe; sem dia lançado, avisa e não chama o banco", async () => {
  const comDia = ctx({ diaLancado: true });
  const r = await tool("registrar_diaria").execute({ freelancer: "roberto", data: "24/09/2026", jornada: "apagar" }, comDia.c as never) as Record<string, unknown>;
  assertEquals(comDia.chamadas.map((x) => x.n), ["apagar_diaria"]);
  assertEquals(comDia.chamadas[0].a.p_diaria_id, "ws-1");
  assertStringIncludes(String(r.aviso), "apagada");

  const semDia = ctx();
  const r2 = await tool("registrar_diaria").execute({ freelancer: "roberto", data: "24/09/2026", jornada: "apagar" }, semDia.c as never) as { error?: string };
  assertStringIncludes(String(r2.error), "Não há dia lançado");
  assertEquals(semDia.chamadas.length, 0);
});

Deno.test("técnico e vendedor não registram nem consultam", async () => {
  for (const cargo of ["technician", "seller"]) {
    const { c, chamadas } = ctx({ cargo });
    const r1 = await tool("registrar_diaria").execute({ freelancer: "roberto", jornada: "inteiro" }, c as never) as { error?: string };
    const r2 = await tool("consultar_freelancer").execute({ freelancer: "roberto" }, c as never) as { error?: string };
    assertEquals(typeof r1.error, "string");
    assertEquals(typeof r2.error, "string");
    assertEquals(chamadas.length, 0);
  }
});

Deno.test("a confirmação mostra o dia resolvido, a divisão entre OS e o que já estava lançado", async () => {
  const novo = String(await resumirDiaria(ctx().c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "inteiro", os: "60, 61" })).replace(/ /g, " ");
  // O número já vem com o prefixo do banco ("OS-00060"): nada de "OS OS-" (11/10/2026).
  assertStringIncludes(novo, "*Roberto Daniel Rodrigues Correa* · qui 24/09 · *dia inteiro* · R$ 160,00 · OS-00060, OS-00061");
  assertEquals(novo.includes("OS OS-"), false);
  assertStringIncludes(novo, "partes iguais");

  const corrigir = String(await resumirDiaria(ctx({ diaLancado: true }).c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "inteiro" })).replace(/ /g, " ");
  assertStringIncludes(corrigir, "Hoje está lançado: meio período (R$ 80,00) — vai ser corrigido, não duplicado.");

  const apagar = String(await resumirDiaria(ctx({ diaLancado: true }).c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "apagar" })).replace(/ /g, " ");
  assertStringIncludes(apagar, "Apagar o dia de *Roberto Daniel Rodrigues Correa* · qui 24/09 (meio período, R$ 80,00)");
});

Deno.test("jornada inválida é recusada antes de virar pendência", () => {
  const r = tool("registrar_diaria").preValidar!({ freelancer: "roberto", jornada: "folga" }, {} as never);
  assertStringIncludes(String(r?.error), "não existe");
  assertEquals(tool("registrar_diaria").preValidar!({ freelancer: "roberto", jornada: "meio" }, {} as never), null);
});

// Extras e descontos do dia (07/10/2026): os mesmos campos do "Registrar dia" da tela.
Deno.test("'diária inteira mais 50 de almoço': extras vão para a função do banco e para a confirmação", async () => {
  const { c, chamadas } = ctx();
  const args = { freelancer: "roberto", data: "24/09/2026", jornada: "inteiro", extras: 50, observacao: "almoço" };
  const resumo = String(await resumirDiaria(c as never, args)).replace(/ /g, " ");
  assertStringIncludes(resumo, "*dia inteiro* · R$ 210,00");
  assertStringIncludes(resumo, "Extras: *R$ 50,00*");
  await tool("registrar_diaria").execute(args, c as never);
  const reg = chamadas.find((x) => x.n === "registrar_diaria")!;
  assertEquals(reg.a.p_extras, 50);
  assertEquals(reg.a.p_descontos, null);
  assertEquals(reg.a.p_observacao, "almoço");
});

Deno.test("'desconta 30 da diária de ontem': jornada 'manter' vira a do dia lançado; sem dia, pergunta", async () => {
  const comDia = ctx({ diaLancado: true });
  const args = { freelancer: "roberto", data: "24/09/2026", jornada: "manter", descontos: 30 };
  const resumo = String(await resumirDiaria(comDia.c as never, args)).replace(/ /g, " ");
  assertStringIncludes(resumo, "*meio período* · R$ 50,00");
  assertStringIncludes(resumo, "Descontos: R$ 0,00 → *R$ 30,00*");
  await tool("registrar_diaria").execute(args, comDia.c as never);
  const reg = comDia.chamadas.find((x) => x.n === "registrar_diaria")!;
  assertEquals(reg.a.p_jornada, "meio");
  assertEquals(reg.a.p_descontos, 30);
  assertEquals(reg.a.p_extras, null);

  const semDia = ctx();
  const r = await tool("registrar_diaria").execute(args, semDia.c as never) as { error?: string };
  assertStringIncludes(String(r.error), "Não há dia lançado");
  assertEquals(semDia.chamadas.length, 0);
  assertStringIncludes(String(tool("registrar_diaria").preValidar!({ freelancer: "roberto", jornada: "manter", data_ate: "hoje" }, {} as never)?.error), "um dia de cada vez");
  const ruim = await resolverDiaria(comDia.c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "manter", descontos: "trinta" });
  assertStringIncludes(String((ruim as { error: string }).error), "descontos");
});

Deno.test("'quanto o Roberto tem de extra este mês?': consultar soma extras e descontos do período", async () => {
  const { c } = ctx();
  const linhas = [
    { tipo: "dia", data: "2026-10-01", fracao: 1, trabalhado: 210, extras: 50, descontos: 0, os: [] },
    { tipo: "dia", data: "2026-10-02", fracao: 1, trabalhado: 130, extras: 0, descontos: 30, os: [] },
    { tipo: "pagamento", data: "2026-10-03", pago: 100, conta: "C6" },
  ];
  const comLinhas = { ...c, sb: { rpc: () => Promise.resolve({ data: { saldo_final: 240, estado: "deve", dias: 2, trabalhado: 340, pago: 100, saldo_anterior: 0, linhas }, error: null }) } };
  const r = await tool("consultar_freelancer").execute({ freelancer: "roberto", periodo: "este_mes" }, comLinhas as never) as Record<string, any>;
  assertEquals(r.extras_no_periodo, 50);
  assertEquals(r.descontos_no_periodo, 30);
  assertEquals(r.ultimos_lancamentos[0].extras, 50);
});

Deno.test("consultar: sem nome, todos pelo resumo; com nome, a conta corrente dele", async () => {
  const todos = ctx();
  const r1 = await tool("consultar_freelancer").execute({}, todos.c as never) as { pessoas: unknown[] };
  assertEquals(todos.chamadas[0].n, "resumo_freelancers");
  assertEquals(r1.pessoas.length, 1);

  const um = ctx();
  const r2 = await tool("consultar_freelancer").execute({ freelancer: "mickael", periodo: "este_mes" }, um.c as never) as Record<string, unknown>;
  assertEquals(um.chamadas[0].n, "conta_corrente_freelancer");
  assertEquals(um.chamadas[0].a.p_favorecido_id, "p-mic");
  assertEquals([um.chamadas[0].a.p_de, um.chamadas[0].a.p_atalho], [null, "este_mes"]);
  assertEquals(r2.situacao, "você deve a ele");

  // "o que falta pagar" vai como atalho para o banco; datas ditas vão como De/Até.
  const aberto = ctx();
  await tool("consultar_freelancer").execute({ periodo: "em_aberto" }, aberto.c as never);
  assertEquals(aberto.chamadas[0].a, { p_de: null, p_ate: null, p_atalho: "em_aberto", p_autor: "u-dono" });
});

Deno.test("período dito: atalhos, datas e o que vira pergunta; dia curto em Brasília", () => {
  const agora = new Date("2026-10-06T15:00:00Z"); // terça
  assertEquals(periodoDito({ periodo: "mes_passado" }, agora), { p_de: null, p_ate: null, p_atalho: "mes_anterior" });
  assertEquals(periodoDito({}, agora), { p_de: null, p_ate: null, p_atalho: null });
  assertEquals(periodoDito({ periodo: "desde_ultimo_pagamento" }, agora), { p_de: null, p_ate: null, p_atalho: "desde_ultimo_pagamento" });
  assertEquals(periodoDito({ de: "14/09/2026", ate: "27/09/2026", periodo: "em_aberto" }, agora), { p_de: "2026-09-14", p_ate: "2026-09-27", p_atalho: null });
  assertEquals(periodoDito({ de: "segunda" }, agora), { p_de: "2026-10-05", p_ate: null, p_atalho: null });
  assertStringIncludes(String((periodoDito({ de: "27/09/2026", ate: "14/09/2026" }, agora) as { error: string }).error), "invertido");
  assertStringIncludes(String((periodoDito({ periodo: "quinzena" }, agora) as { error: string }).error), "não existe");
  assertEquals(diaCurto("2026-09-24"), "qui 24/09");
});

// ── Pagamento a freelancer pelo WhatsApp (06/10/2026) ──

Deno.test("pagamento: Pix vira anotação (espera o banco), dinheiro sai do Caixa, bolso é do sócio que fala", async () => {
  const pix = ctx();
  const r = await tool("registrar_pagamento_freelancer").execute({ freelancer: "roberto", valor: 100, forma: "pix" }, pix.c as never) as Record<string, unknown>;
  const an = pix.chamadas.find((x) => x.n === "anotar_transacao")!.a;
  assertEquals([an.p_sentido, an.p_valor, an.p_favorecido_id, an.p_categoria, an.p_data], ["saida", 100, "p-rob", "Diárias de freelancers", null]);
  assertStringIncludes(String(r.aviso), "Anotado");
  assertStringIncludes(String(r.aviso), "Saldo com Roberto");

  const din = ctx();
  await tool("registrar_pagamento_freelancer").execute({ freelancer: "mickael", valor: "50,00", forma: "dinheiro", data: "ontem" }, din.c as never);
  const cx = din.chamadas.find((x) => x.n === "lancar_no_caixa")!.a;
  assertEquals([cx.p_pago_por, cx.p_valor, cx.p_favorecido_id, cx.p_socio_id], ["caixa", 50, "p-mic", null]);
  assertEquals(typeof cx.p_data, "string");

  const bolso = ctx();
  await tool("registrar_pagamento_freelancer").execute({ freelancer: "roberto", valor: 80, forma: "bolso_do_socio" }, bolso.c as never);
  const sx = bolso.chamadas.find((x) => x.n === "lancar_no_caixa")!.a;
  assertEquals([sx.p_pago_por, sx.p_socio_id, sx.p_favorecido_id], ["socio", "s-gus", "p-rob"]);
});

Deno.test("pagamento: sem valor ou forma é pergunta antes da pendência; futuro e técnico recusados", async () => {
  assertStringIncludes(String(tool("registrar_pagamento_freelancer").preValidar!({ freelancer: "roberto", forma: "pix" }, {} as never)?.error), "valor");
  assertStringIncludes(String(tool("registrar_pagamento_freelancer").preValidar!({ freelancer: "roberto", valor: 10 }, {} as never)?.error), "Como foi pago");
  const futuro = await resolverPagamento(ctx().c as never, { freelancer: "roberto", valor: 10, forma: "pix", data: "31/12/2099" });
  assertStringIncludes(String((futuro as { error: string }).error), "futuro");
  const tec = ctx({ cargo: "technician" });
  const r = await tool("registrar_pagamento_freelancer").execute({ freelancer: "roberto", valor: 10, forma: "pix" }, tec.c as never) as { error?: string };
  assertEquals(typeof r.error, "string");
  assertEquals(tec.chamadas.length, 0);
});

Deno.test("pagamento: a confirmação diz quanto, como, o saldo antes e depois, e o aviso do Pix repetido", async () => {
  const txt = String(await resumirPagamento(ctx({ simulacao: { data: { saldo_final: 1090 } } }).c as never,
    { freelancer: "roberto", valor: 100, forma: "pix", observacao: "adiantamento" })).replace(/ /g, " ");
  assertStringIncludes(txt, "Pagamento a *Roberto Daniel Rodrigues Correa*: *R$ 100,00* por Pix");
  assertStringIncludes(txt, "Saldo com ele: R$ 1.090,00 → R$ 990,00");
  assertStringIncludes(txt, "Descrição: adiantamento · Diárias de freelancers");
  assertStringIncludes(txt, "Se você já lançou este mesmo Pix, responda não");
});

// 15/10/2026: o cartão saía "*R$ 500,00* em do bolso do sócio" — o rótulo já começava com "do".
Deno.test("pagamento: a forma sai inteira na confirmação (bolso do sócio e dinheiro do Caixa)", async () => {
  const bolso = String(await resumirPagamento(ctx({ simulacao: { data: { saldo_final: 1090 } } }).c as never,
    { freelancer: "roberto", valor: 500, forma: "bolso_do_socio" })).replace(/ /g, " ");
  assertStringIncludes(bolso, "*R$ 500,00* pago do bolso do sócio ·");
  assertEquals(bolso.includes("em do bolso"), false);
  const dinheiro = String(await resumirPagamento(ctx({ simulacao: { data: { saldo_final: 1090 } } }).c as never,
    { freelancer: "roberto", valor: 50, forma: "dinheiro" })).replace(/ /g, " ");
  assertStringIncludes(dinheiro, "*R$ 50,00* em dinheiro do Caixa ·");
});

// ── Extrato em PDF pelo WhatsApp (06/10/2026) ──

Deno.test("extrato em PDF: período ruim e falta de WhatsApp viram resposta antes de gerar qualquer coisa", async () => {
  const ruim = ctx();
  const r1 = await tool("enviar_extrato_freelancer").execute({ freelancer: "roberto", periodo: "quinzena" }, ruim.c as never) as { error?: string };
  assertStringIncludes(String(r1.error), "não existe");
  const semFone = ctx({ semTelefone: true });
  const r2 = await tool("enviar_extrato_freelancer").execute({ freelancer: "roberto" }, semFone.c as never) as { error?: string };
  assertStringIncludes(String(r2.error), "WhatsApp cadastrado");
  assertEquals(semFone.chamadas.length, 0);
  const tec = ctx({ cargo: "technician" });
  const r3 = await tool("enviar_extrato_freelancer").execute({ freelancer: "roberto" }, tec.c as never) as { error?: string };
  assertEquals(typeof r3.error, "string");
});

// ── Vários dias ("faltou desde 19/09", "a semana toda", "de segunda até hoje") — pedido do dono, 29/09 ──

Deno.test("dia da semana é o mais recente até hoje; o intervalo pula sábado e domingo, salvo pedido", () => {
  const terca = new Date("2026-09-29T15:00:00Z");
  assertEquals(dataDoDito("segunda", terca), "2026-09-28");
  assertEquals(dataDoDito("terça", terca), "2026-09-29");
  assertEquals(dataDoDito("sexta-feira", terca), "2026-09-25");
  assertEquals(dataDoDito("domingo", terca), "2026-09-27");
  assertEquals(dataDoDito("19/09/2026", terca), "2026-09-19");
  // 19/09/2026 foi sábado: "desde 19/09" em dias úteis começa na segunda, 21.
  assertEquals(datasDoIntervalo("2026-09-19", "2026-09-29"), ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-28", "2026-09-29"]);
  assertEquals(datasDoIntervalo("2026-09-19", "2026-09-21", true), ["2026-09-19", "2026-09-20", "2026-09-21"]);
  assertEquals(datasDoIntervalo("2026-09-26", "2026-09-27"), []);
});

Deno.test("resolver com data_ate: lista os dias; invertido, futuro, grande demais e apagar em lote viram pergunta", async () => {
  const { c } = ctx();
  const p = await resolverDiaria(c as never, { freelancer: "mickael", jornada: "inteiro", data: "19/09/2026", data_ate: "25/09/2026" });
  if ("error" in p) throw new Error(p.error);
  assertEquals(p.intervalo, true);
  assertEquals(p.datas, ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25"]);

  const erro = async (a: Record<string, unknown>) => String(((await resolverDiaria(c as never, { freelancer: "mickael", jornada: "inteiro", ...a })) as { error?: string }).error);
  assertStringIncludes(await erro({ data: "25/09/2026", data_ate: "19/09/2026" }), "invertido");
  assertStringIncludes(await erro({ data: "25/09/2026", data_ate: "31/12/2099" }), "futuro");
  assertStringIncludes(await erro({ data: "01/01/2026", data_ate: "30/06/2026" }), "grande demais");
  assertStringIncludes(await erro({ data: "26/09/2026", data_ate: "27/09/2026" }), "Nenhum dia útil");
  assertStringIncludes(await erro({ jornada: "apagar", data: "21/09/2026", data_ate: "25/09/2026" }), "um dia de cada vez");
});

Deno.test("vários dias: registra só os que faltam — o dia já lançado no meio fica como está", async () => {
  const { c, chamadas } = ctx({ diaLancado: true }); // 24/09 já tem meio período do Roberto
  const r = await tool("registrar_diaria").execute(
    { freelancer: "roberto", jornada: "inteiro", data: "21/09/2026", data_ate: "25/09/2026" }, c as never) as Record<string, any>;
  const registradas = chamadas.filter((x) => x.n === "registrar_diaria").map((x) => x.a.p_data);
  assertEquals(registradas, ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-25"]);
  assertEquals(r.registrados, registradas);
  assertStringIncludes(String(r.aviso), "4 dia(s) registrado(s): 21/09, 22/09, 23/09, 25/09.");
  assertStringIncludes(String(r.aviso), "Já lançados, mantidos: 24/09 (meio período).");
});

Deno.test("vários dias: a confirmação lista os dias, o total e o que fica como está", async () => {
  const txt = String(await resumirDiaria(ctx({ diaLancado: true }).c as never,
    { freelancer: "roberto", jornada: "inteiro", data: "21/09/2026", data_ate: "25/09/2026" })).replace(/\u00a0/g, " ");
  assertStringIncludes(txt, "*Roberto Daniel Rodrigues Correa* · *dia inteiro* · 4 dia(s) de seg 21/09 a sex 25/09 (só dias úteis) · R$ 160,00 cada, R$ 640,00 no total");
  assertStringIncludes(txt, "Dias: 21/09, 22/09, 23/09, 25/09");
  assertStringIncludes(txt, "Já lançados, ficam como estão: 24/09 (meio período).");
});

Deno.test("jornada 'apagar' com data_ate é recusada antes de virar pendência", () => {
  const r = tool("registrar_diaria").preValidar!({ freelancer: "roberto", jornada: "apagar", data: "21/09", data_ate: "25/09" }, {} as never);
  assertStringIncludes(String(r?.error), "um dia de cada vez");
});

// ── Valor dito para o dia ("na quarta foram 130") — pedido do dono, 01/10/2026 ──

Deno.test("valor dito: vai para o banco só nesse dia, aparece na confirmação; apagar ignora o valor", async () => {
  assertEquals(numeroDito(130), 130);
  assertEquals(numeroDito("130,00"), 130);
  assertEquals(numeroDito("R$ 1.300,50"), 1300.5);
  assertEquals(numeroDito("cento e trinta"), null);

  const { c, chamadas } = ctx();
  await tool("registrar_diaria").execute({ freelancer: "mickael", data: "24/09/2026", jornada: "inteiro", valor_diaria: 150 }, c as never);
  assertEquals(chamadas.find((x) => x.n === "registrar_diaria")!.a.p_valor_diaria, 150);

  const txt = String(await resumirDiaria(ctx().c as never, { freelancer: "mickael", data: "24/09/2026", jornada: "inteiro", valor_diaria: "150" })).replace(/ /g, " ");
  assertStringIncludes(txt, "*dia inteiro* · R$ 150,00");
  assertStringIncludes(txt, "Diária desse dia: R$ 150,00 (a do cadastro é R$ 130,00).");

  const apagar = await resolverDiaria(c as never, { freelancer: "mickael", jornada: "apagar", valor_diaria: 150 });
  if ("error" in apagar) throw new Error(apagar.error);
  assertEquals(apagar.valorDiaria, null);
  const ruim = await resolverDiaria(c as never, { freelancer: "mickael", jornada: "inteiro", valor_diaria: "muito" });
  assertStringIncludes(String((ruim as { error: string }).error), "valor do dia");
});

// ── Freelancer novo (o João Marcelo no lugar do Mickael) — pedido do dono, 01/10/2026 ──

Deno.test("cadastro: monta só o que a pessoa disse; sem nome ou sem valor é pergunta antes da pendência", () => {
  const quinta = new Date("2026-10-01T15:00:00Z");
  const p = paramsDoCadastro({ nome: " João Marcelo ", valor_diaria: "150", desde: "terça", chave_pix: "freefiregokdarix@gmail.com" }, quinta);
  if ("error" in p) throw new Error(p.error);
  assertEquals(p, {
    p_nome: "João Marcelo", p_valor_diaria: 150, p_desde: "2026-09-29",
    p_chave_pix: "freefiregokdarix@gmail.com", p_tipo_chave: null,
    p_documento: null, p_telefone: null, p_observacao: null,
  });
  assertStringIncludes(String((paramsDoCadastro({ valor_diaria: 150 }) as { error: string }).error), "nome");
  assertStringIncludes(String((paramsDoCadastro({ nome: "João" }) as { error: string }).error), "valor da diária de João");
  assertStringIncludes(String((paramsDoCadastro({ nome: "João", valor_diaria: 150, tipo_chave: "pix" }) as { error: string }).error), "não existe");

  const recusa = tool("cadastrar_freelancer").preValidar!({ nome: "João" }, {} as never);
  assertStringIncludes(String(recusa?.error), "valor da diária");
  assertEquals(tool("cadastrar_freelancer").preValidar!({ nome: "João", valor_diaria: 150 }, {} as never), null);
});

Deno.test("cadastro: grava pela função do banco, com quem pediu e sem simular; técnico não cadastra", async () => {
  const { c, chamadas } = ctx();
  const r = await tool("cadastrar_freelancer").execute(
    { nome: "João Marcelo", valor_diaria: 150, chave_pix: "freefiregokdarix@gmail.com", tipo_chave: "email" }, c as never) as Record<string, unknown>;
  assertEquals(chamadas.length, 1);
  assertEquals(chamadas[0].n, "cadastrar_freelancer");
  assertEquals(chamadas[0].a.p_simular, false);
  assertEquals(chamadas[0].a.p_autor, "u-dono");
  assertEquals(chamadas[0].a.p_tipo_chave, "email");
  assertStringIncludes(String(r.aviso), "João Marcelo cadastrado");

  const tec = ctx({ cargo: "technician" });
  const r2 = await tool("cadastrar_freelancer").execute({ nome: "João", valor_diaria: 150 }, tec.c as never) as { error?: string };
  assertEquals(typeof r2.error, "string");
  assertEquals(tec.chamadas.length, 0);
});

Deno.test("cadastro: a confirmação é a função do banco simulando — cadastro novo, existente e recusa", async () => {
  const novo = ctx({ simulacao: { data: { acao: "criado", nome: "João Marcelo", chave_pix: "freefiregokdarix@gmail.com", tipo_chave: "email", regra: "sem_cpf" } } });
  const txt = String(await resumirCadastro(novo.c as never, { nome: "João Marcelo", valor_diaria: 150, desde: "29/09/2026", chave_pix: "freefiregokdarix@gmail.com" })).replace(/ /g, " ");
  assertStringIncludes(txt, "Cadastrar freelancer: *João Marcelo* · diária de R$ 150,00 · desde ter 29/09");
  assertStringIncludes(txt, "Pix (e-mail): freefiregokdarix@gmail.com");
  assertStringIncludes(txt, "Sem CPF: os Pix para ele vão pedir a sua confirmação");
  const sim = (novo.c.admin as any).simuladas[0];
  assertEquals([sim.n, sim.p_simular, sim.p_autor], ["cadastrar_freelancer", true, null]);

  const existente = ctx({ simulacao: { data: { acao: "diaria_no_cadastro_existente", nome: "José da Silva", regra: "criada" } } });
  const txt2 = String(await resumirCadastro(existente.c as never, { nome: "jose da silva", valor_diaria: 120, cpf: "123.456.789-09" }));
  assertStringIncludes(txt2, "Já existe o favorecido *José da Silva*, sem diária");
  assertStringIncludes(txt2, "Pix para o CPF dele vão entrar sozinhos");

  const recusa = ctx({ simulacao: { error: { message: "P0001: Roberto já tem diária cadastrada (veja em Financeiro › Diárias)." } } });
  const txt3 = String(await resumirCadastro(recusa.c as never, { nome: "Roberto", valor_diaria: 160 }));
  assertStringIncludes(txt3, "⚠️ Roberto já tem diária cadastrada (veja em Financeiro › Diárias). — o sistema vai recusar.");
});

// ── Acerto (fechar ao pagar), recibo e conferência do freelancer (06/10/2026) ──

Deno.test("acerto: fechar chama a função do banco com quem pediu; a confirmação é a simulação dela", async () => {
  const { c, chamadas } = ctx();
  const r = await tool("fechar_acerto_freelancer").execute({ freelancer: "roberto", ate: "01/10/2026" }, c as never) as Record<string, unknown>;
  assertEquals(chamadas[0].n, "fechar_acerto_diarias");
  assertEquals([chamadas[0].a.p_favorecido_id, chamadas[0].a.p_ate, chamadas[0].a.p_simular, chamadas[0].a.p_autor], ["p-rob", "2026-10-01", false, "u-dono"]);
  assertStringIncludes(String(r.aviso), "travados");

  const txt = String(await resumirAcerto(ctx({ simulacao: { data: {
    ok: true, travas: [], de: "2026-09-16", ate: "2026-10-01", dias: 2.5, trabalhado: 400, saldo_anterior: 0, pago_no_periodo: 100,
    valor_do_acerto: 300, pix: { id: "px", data: "2026-10-02", valor: 300 },
  } } }).c as never, { freelancer: "roberto" })).replace(/\u00a0/g, " ");
  assertStringIncludes(txt, "Recibo de *Roberto Daniel Rodrigues Correa*: serviços de 16/09 a 01/10");
  assertStringIncludes(txt, "2,5 diária(s) = R$ 400,00 · já recebido R$ 100,00");
  assertStringIncludes(txt, "*Pix de 02/10 que quita: R$ 300,00*");

  // F2 (27/10): com trava, a confirmação diz todas as frases do banco e que vai recusar
  const travado = String(await resumirAcerto(ctx({ simulacao: { data: {
    ok: false, travas: ["Falta o CPF de Roberto no cadastro.", "Pix de 10/10 (R$ 510,00) está na fila: aprove antes do recibo."],
  } } }).c as never, { freelancer: "roberto" }));
  assertStringIncludes(travado, "• Falta o CPF de Roberto no cadastro.");
  assertStringIncludes(travado, "• Pix de 10/10 (R$ 510,00) está na fila: aprove antes do recibo.");
  assertStringIncludes(travado, "o sistema vai recusar");

  const recusa = String(await resumirAcerto(ctx({ simulacao: { error: { message: "P0001: Nada a fechar: o acerto nº 0001 de Roberto já vai até 15/09." } } }).c as never, { freelancer: "roberto" }));
  assertStringIncludes(recusa, "⚠️ Nada a fechar");
});

// ── F2b: o reembolso do técnico (comprovante pago por ele) nas Diárias (11/10/2026) ──

Deno.test("F2b consultar: o reembolso é a favor dele (com o código do CMP), não pagamento; o total vem à parte dos dias", async () => {
  const { c } = ctx();
  const linhas = [
    { tipo: "dia", data: "2026-10-01", fracao: 1, trabalhado: 300, extras: 0, descontos: 0, os: [] },
    { tipo: "reembolso", data: "2026-10-05", trabalhado: 62, pago: 0, conta: "CMP-00124", descricao: "Reembolso CMP-00124 · AutoZone", categoria: "Peças e materiais", os: [] },
    { tipo: "pagamento", data: "2026-10-06", pago: 100, conta: "C6" },
  ];
  const conta = { saldo_final: 262, estado: "deve", dias: 1, trabalhado: 300, reembolsos: 62, pago: 100, saldo_anterior: 0, linhas };
  const comLinhas = { ...c, sb: { rpc: () => Promise.resolve({ data: conta, error: null }) } };
  const r = await tool("consultar_freelancer").execute({ freelancer: "roberto", periodo: "em_aberto" }, comLinhas as never) as Record<string, any>;
  assertEquals([r.trabalhado, r.reembolsos, r.pago, r.saldo], [300, 62, 100, 262]);
  assertEquals(r.ultimos_lancamentos[1], {
    data: "2026-10-05", tipo: "reembolso de despesa paga pelo técnico", valor: 62, codigo: "CMP-00124", descricao: "Reembolso CMP-00124 · AutoZone",
  });
  assertEquals(r.ultimos_lancamentos[2], { data: "2026-10-06", pagamento: 100, de_onde: "C6" });
  // os extras do período continuam só dos dias
  assertEquals([r.extras_no_periodo, r.descontos_no_periodo], [0, 0]);
  // banco de antes da F2b (sem a chave): reembolsos 0
  const antes = { ...c, sb: { rpc: () => Promise.resolve({ data: { ...conta, reembolsos: undefined, linhas: [] }, error: null }) } };
  assertEquals((await tool("consultar_freelancer").execute({ freelancer: "roberto" }, antes as never) as Record<string, any>).reembolsos, 0);
  // todos: só quem tem reembolso ganha a chave
  const todos = { ...c, sb: { rpc: () => Promise.resolve({ data: { pessoas: [
    { nome: "Roberto", dias: 1, trabalhado: 300, reembolsos: 62, pago: 100, saldo_final: 262, estado: "deve" },
    { nome: "Mickael", dias: 2, trabalhado: 260, reembolsos: 0, pago: 260, saldo_final: 0, estado: "quitado" },
  ] }, error: null }) } };
  const rt = await tool("consultar_freelancer").execute({}, todos as never) as { pessoas: Array<Record<string, unknown>> };
  assertEquals(rt.pessoas[0].reembolsos, 62);
  assertEquals("reembolsos" in rt.pessoas[1], false);
  assertStringIncludes(tool("consultar_freelancer").description, "reembolsos = reembolso de despesas pagas pelo técnico");
  // resposta 6 do dono: o extra de almoço é quando ele traz o próprio; a mesma despesa não entra também como extra
  assertStringIncludes(tool("consultar_freelancer").description, "o extra de almoço é quando ele traz o próprio");
  assertStringIncludes((tool("registrar_diaria").input_schema as any).properties.extras.description, "o almoço quando ele traz o próprio");
});

Deno.test("F2b acerto: a confirmação diz os reembolsos (antes dos vales) só quando há", async () => {
  const simular = (reembolsos: number | undefined) => ctx({ simulacao: { data: {
    ok: true, travas: [], de: "2026-09-16", ate: "2026-10-01", dias: 1, trabalhado: 300, saldo_anterior: 0, reembolsos, pago_no_periodo: 100,
    valor_do_acerto: 262, pix: { id: "px", data: "2026-10-02", valor: 262 },
  } } }).c;
  const com = String(await resumirAcerto(simular(62) as never, { freelancer: "roberto" })).replace(/ /g, " ");
  assertStringIncludes(com, "1 diária(s) = R$ 300,00 · reembolso de despesas pagas pelo técnico R$ 62,00 · já recebido R$ 100,00");
  assertStringIncludes(com, "*Pix de 02/10 que quita: R$ 262,00*");
  for (const sem of [0, undefined]) {
    const txt = String(await resumirAcerto(simular(sem) as never, { freelancer: "roberto" })).replace(/ /g, " ");
    assertStringIncludes(txt, "1 diária(s) = R$ 300,00 · já recebido R$ 100,00");
    assertEquals(txt.includes("reembolso"), false);
  }
});

Deno.test("acerto: reabrir pede motivo antes da pendência e reabre o último", async () => {
  assertStringIncludes(String(tool("reabrir_acerto_freelancer").preValidar!({ freelancer: "roberto" }, {} as never)?.error), "motivo");
  const { c, chamadas } = ctx();
  const r = await tool("reabrir_acerto_freelancer").execute({ freelancer: "roberto", motivo: "dia 10 errado" }, c as never) as Record<string, unknown>;
  assertEquals(chamadas[0].n, "reabrir_acerto_diarias");
  assertEquals([chamadas[0].a.p_acerto_id, chamadas[0].a.p_motivo], ["ac-1", "dia 10 errado"]);
  assertStringIncludes(String(r.aviso), "reaberto");
});

Deno.test("acerto ao freelancer: sem telefone, sem acerto ou acerto reaberto não manda nada", async () => {
  const semFone = ctx();
  const r1 = await tool("enviar_acerto_ao_freelancer").execute({ freelancer: "roberto" }, semFone.c as never) as { error?: string };
  assertStringIncludes(String(r1.error), "não tem telefone no cadastro");
  const semAcerto = ctx({ semAcerto: true });
  const r2 = await tool("enviar_acerto_ao_freelancer").execute({ freelancer: "roberto" }, semAcerto.c as never) as { error?: string };
  assertStringIncludes(String(r2.error), "ainda não tem acerto fechado");
  const reaberto = ctx({ acertoReaberto: true });
  const r3 = await tool("enviar_acerto_ao_freelancer").execute({ freelancer: "roberto", numero: "1" }, reaberto.c as never) as { error?: string };
  assertStringIncludes(String(r3.error), "está reaberto");
  const txt = String(await resumirEnvioAoFreelancer(ctx().c as never, { freelancer: "roberto" })).replace(/\u00a0/g, " ");
  assertStringIncludes(txt, "recibo nº 0001");
  assertStringIncludes(txt, "SEM TELEFONE NO CADASTRO");
  assertStringIncludes(txt, "responder OK");
});

// ── Resposta 4 do dono (11/10/2026): o pagamento ao técnico dividido entre diárias e reembolso ──

const PROPOSTA = {
  favorecido: { id: "p-rob", nome: "Roberto" }, valor: 500,
  em_aberto: [
    { id: "r-124", codigo: "CMP-00124", data: "2026-09-16", valor: 62, categoria: "Combustível e deslocamento", descricao: "AutoZone", acerto: 1 },
    { id: "r-130", codigo: "CMP-00130", data: "2026-10-02", valor: 30, categoria: "Outras despesas", descricao: null, acerto: null },
    { id: "r-131", codigo: "CMP-00131", data: "2026-10-05", valor: 15, categoria: "Alimentação de campo", descricao: null, acerto: null },
  ],
  propostos: ["r-124", "r-130"], reembolsos: 92, diarias: 408,
  partes: [{ categoria: "Diárias de freelancers", valor: 408 }, { categoria: "Combustível e deslocamento", valor: 62 }, { categoria: "Outras despesas", valor: 30 }],
};

/** ctx com a proposta no banco (admin) e as RPCs da divisão (sb). */
function ctxDaDivisao(linhas: Array<Record<string, unknown>> = []) {
  const base = ctx({ simulacao: { data: PROPOSTA } });
  const chamadas: Chamada[] = [];
  const rpc = (n: string, a: Record<string, unknown>) => {
    chamadas.push({ n, a });
    if (n === "registrar_pagamento_do_freelancer") {
      return Promise.resolve({ data: { ok: true, forma: a.p_forma, message: "Pix anotado. Divido quando a linha do banco for aprovada: Diárias R$ 408,00 · Reembolso de despesas pagas pelo técnico R$ 92,00." }, error: null });
    }
    if (n === "dividir_pagamento_do_freelancer") {
      return Promise.resolve({ data: { ok: true, message: "Pagamento dividido: Diárias R$ 408,00 · Reembolso de despesas pagas pelo técnico R$ 92,00." }, error: null });
    }
    if (n === "conta_corrente_freelancer") return Promise.resolve({ data: { saldo_final: 0, estado: "quitado", linhas }, error: null });
    if (n === "anotar_transacao") return Promise.resolve({ data: { ok: true, message: "Anotado." }, error: null });
    return Promise.resolve({ data: null, error: { message: `rpc inesperada ${n}` } });
  };
  return { c: { ...base.c, sb: { rpc } }, chamadas };
}

Deno.test("divisão: o que a pessoa diz dos reembolsos (proposta, sem reembolso, os CMPs)", () => {
  assertEquals(reembolsosDitos(undefined), { modo: "proposta" });
  assertEquals(reembolsosDitos("proposta"), { modo: "proposta" });
  assertEquals(reembolsosDitos("sem reembolso"), { modo: "nenhum" });
  assertEquals(reembolsosDitos("nenhum"), { modo: "nenhum" });
  assertEquals(reembolsosDitos("CMP-00124, cmp 130"), { modo: "codigos", codigos: ["CMP-00124", "CMP-00130"] });
  assertEquals(reembolsosDitos(["124", "CMP-00124"]), { modo: "codigos", codigos: ["CMP-00124"] });
  assertStringIncludes(String((reembolsosDitos("o do posto") as { error: string }).error), "Não entendi os reembolsos");
  assertStringIncludes(String(tool("registrar_pagamento_freelancer").preValidar!({ freelancer: "roberto", valor: 10, forma: "pix", reembolsos: "xyz" }, {} as never)?.error), "Não entendi");
});

Deno.test("divisão: a confirmação do pagamento mostra a proposta (diárias × reembolso, os CMPs e o que fica em aberto)", async () => {
  const { c } = ctxDaDivisao();
  const txt = String(await resumirPagamento(c as never, { freelancer: "roberto", valor: 500, forma: "pix" })).replace(/ /g, " ");
  assertStringIncludes(txt, "Divido: Diárias R$ 408,00 · Reembolso de despesas pagas pelo técnico R$ 92,00 (CMP-00124, CMP-00130). Ficam em aberto: CMP-00131. Para não dividir: diga \"sem reembolso\".");
  const sem = String(await resumirPagamento(c as never, { freelancer: "roberto", valor: 500, forma: "pix", reembolsos: "sem reembolso" })).replace(/ /g, " ");
  assertStringIncludes(sem, "Sem dividir: tudo em Diárias (há reembolso de despesa paga pelo técnico em aberto: CMP-00124, CMP-00130, CMP-00131).");
  const so131 = String(await resumirPagamento(c as never, { freelancer: "roberto", valor: 500, forma: "pix", reembolsos: "CMP-00131" })).replace(/ /g, " ");
  assertStringIncludes(so131, "Divido: Diárias R$ 485,00 · Reembolso de despesas pagas pelo técnico R$ 15,00 (CMP-00131).");
  const outro = String(await resumirPagamento(c as never, { freelancer: "roberto", valor: 500, forma: "pix", reembolsos: "CMP-00999" }));
  assertStringIncludes(outro, "⚠️ CMP-00999 não é reembolso em aberto de Roberto");
  const passa = String(await resumirPagamento(c as never, { freelancer: "roberto", valor: 50, forma: "pix", reembolsos: "CMP-00124" })).replace(/ /g, " ");
  assertStringIncludes(passa, "passam do valor do pagamento");
  // sem reembolso em aberto: a confirmação de antes (nada de divisão)
  assertEquals(textoDaDivisao({ emAberto: [], escolhidos: [], diarias: 100, reembolsos: 0 }), null);
});

Deno.test("divisão: registrar com reembolso vai a registrar_pagamento_do_freelancer (forma, a data como foi dita, os ids); 'sem reembolso' é o caminho de antes", async () => {
  const pix = ctxDaDivisao();
  const r = await tool("registrar_pagamento_freelancer").execute({ freelancer: "roberto", valor: 500, forma: "pix" }, pix.c as never) as Record<string, unknown>;
  const reg = pix.chamadas.find((x) => x.n === "registrar_pagamento_do_freelancer")!.a;
  assertEquals([reg.p_favorecido_id, reg.p_valor, reg.p_forma, reg.p_reembolsos, reg.p_socio_id, reg.p_autor], ["p-rob", 500, "pix", ["r-124", "r-130"], null, "u-dono"]);
  // revisão dos ajustes: sem a data dita, o Pix vai sem ela (a anotação espera a linha de D-3 a D+7; com
  // "hoje" fixo a janela era D±1 e o Pix de anteontem não casava)
  assertEquals(reg.p_data, null, "sem data dita, o Pix vai sem data");
  const ontem = ctxDaDivisao();
  await tool("registrar_pagamento_freelancer").execute({ freelancer: "roberto", valor: 500, forma: "pix", data: "ontem" }, ontem.c as never);
  assertEquals(/^\d{4}-\d{2}-\d{2}$/.test(String(ontem.chamadas.find((x) => x.n === "registrar_pagamento_do_freelancer")!.a.p_data)), true,
    "a data dita vai como foi dita");
  assertEquals(pix.chamadas.some((x) => x.n === "anotar_transacao"), false);
  assertStringIncludes(String(r.aviso), "Divido quando a linha do banco for aprovada");

  const bolso = ctxDaDivisao();
  await tool("registrar_pagamento_freelancer").execute({ freelancer: "roberto", valor: 500, forma: "bolso_do_socio", reembolsos: "CMP-00131" }, bolso.c as never);
  const b = bolso.chamadas.find((x) => x.n === "registrar_pagamento_do_freelancer")!.a;
  assertEquals([b.p_forma, b.p_socio_id, b.p_reembolsos], ["socio", "s-gus", ["r-131"]]);

  const semDividir = ctxDaDivisao();
  await tool("registrar_pagamento_freelancer").execute({ freelancer: "roberto", valor: 500, forma: "pix", reembolsos: "sem reembolso" }, semDividir.c as never);
  assertEquals(semDividir.chamadas.map((x) => x.n).includes("registrar_pagamento_do_freelancer"), false);
  assertEquals(semDividir.chamadas.find((x) => x.n === "anotar_transacao")!.a.p_categoria, "Diárias de freelancers");

  // CMP que não é dele: nada gravado
  const errado = ctxDaDivisao();
  const re = await tool("registrar_pagamento_freelancer").execute({ freelancer: "roberto", valor: 500, forma: "pix", reembolsos: "CMP-00999" }, errado.c as never) as { error?: string };
  assertStringIncludes(String(re.error), "não é reembolso em aberto");
  assertEquals(errado.chamadas.filter((x) => x.n !== "conta_corrente_freelancer").length, 0);
});

const PIX_DO_BANCO = { tipo: "pagamento", id: "pay-1", data: "2026-10-09", pago: 500, conta: "C6 - Conta PJ HBR", categoria: "Diárias de freelancers", aguardando: false, descricao: "Pix Roberto" };

Deno.test("dividir_pagamento_freelancer: acha o Pix do banco, divide pela proposta; vários pedem qual; Caixa e anotado não se dividem", async () => {
  // o critério da tela: lançamento das Diárias numa linha do banco
  assertEquals(pagamentoQueSeDivide(PIX_DO_BANCO)?.id, "pay-1");
  assertEquals(pagamentoQueSeDivide({ ...PIX_DO_BANCO, conta: "Caixa (dinheiro)" }), null);
  assertEquals(pagamentoQueSeDivide({ ...PIX_DO_BANCO, aguardando: true }), null);
  assertEquals(pagamentoQueSeDivide({ ...PIX_DO_BANCO, conta: "Bolso de Gustavo" }), null);
  assertEquals(pagamentoQueSeDivide({ ...PIX_DO_BANCO, categoria: "Outras despesas" }), null);
  assertEquals(pagamentoQueSeDivide({ ...PIX_DO_BANCO, categoria: "Combustível e deslocamento", descricao: "Pix (inclui reembolso de despesas pagas pelo técnico: R$ 92,00)" })?.dividido, true);

  const um = ctxDaDivisao([PIX_DO_BANCO, { ...PIX_DO_BANCO, id: "pay-cx", conta: "Caixa (dinheiro)" }]);
  const r = await tool("dividir_pagamento_freelancer").execute({ freelancer: "roberto" }, um.c as never) as Record<string, unknown>;
  const d = um.chamadas.find((x) => x.n === "dividir_pagamento_do_freelancer")!.a;
  assertEquals([d.p_payable_id, d.p_reembolsos, d.p_autor], ["pay-1", ["r-124", "r-130"], "u-dono"]);
  assertStringIncludes(String(r.aviso), "Pagamento dividido");
  // "sem reembolso" junta de volta (lista vazia)
  const juntar = ctxDaDivisao([PIX_DO_BANCO]);
  await tool("dividir_pagamento_freelancer").execute({ freelancer: "roberto", reembolsos: "sem reembolso" }, juntar.c as never);
  assertEquals(juntar.chamadas.find((x) => x.n === "dividir_pagamento_do_freelancer")!.a.p_reembolsos, []);

  const varios = ctxDaDivisao([PIX_DO_BANCO, { ...PIX_DO_BANCO, id: "pay-2", data: "2026-10-02", pago: 300 }]);
  const rv = await tool("dividir_pagamento_freelancer").execute({ freelancer: "roberto" }, varios.c as never) as { error?: string };
  assertStringIncludes(String(rv.error).replace(/ /g, " "), "Qual pagamento de Roberto Daniel Rodrigues Correa: sex 09/10 R$ 500,00; sex 02/10 R$ 300,00? Diga o dia ou o valor.");
  assertEquals(varios.chamadas.some((x) => x.n === "dividir_pagamento_do_freelancer"), false);
  // o valor dito escolhe
  await tool("dividir_pagamento_freelancer").execute({ freelancer: "roberto", valor: 300 }, varios.c as never);
  assertEquals(varios.chamadas.find((x) => x.n === "dividir_pagamento_do_freelancer")!.a.p_payable_id, "pay-2");

  const nenhum = ctxDaDivisao([{ ...PIX_DO_BANCO, conta: "Caixa (dinheiro)" }]);
  const rn = await tool("dividir_pagamento_freelancer").execute({ freelancer: "roberto" }, nenhum.c as never) as { error?: string };
  assertStringIncludes(String(rn.error), "Não achei pagamento de diárias de Roberto Daniel Rodrigues Correa que veio do banco");

  // a confirmação: qual pagamento e como fica
  const txt = String(await resumirDivisaoDoPagamento(um.c as never, { freelancer: "roberto" })).replace(/ /g, " ");
  assertStringIncludes(txt, "Dividir o pagamento de *Roberto Daniel Rodrigues Correa*: R$ 500,00 · sex 09/10 · C6 - Conta PJ HBR");
  assertStringIncludes(txt, "Diárias R$ 408,00 · Reembolso de despesas pagas pelo técnico R$ 92,00 (CMP-00124, CMP-00130).");
  // o "sim" pelo WhatsApp: o resumo do agent.ts é ESTE (antes caía no genérico e o dono confirmava sem ver
  // a divisão). O agent chama só com o cliente service-role — que aqui faz as duas vezes.
  const doAgente = ctxDaDivisao([PIX_DO_BANCO]);
  const soAdmin = {
    ...doAgente.c.admin,
    rpc: (n: string, a: Record<string, unknown>) =>
      n === "proposta_de_divisao_do_pagamento" ? doAgente.c.admin.rpc(n, a) : doAgente.c.sb.rpc(n, a),
  };
  const resumo = String(await buildPendingSummary(soAdmin, "dividir_pagamento_freelancer", { freelancer: "roberto" },
    { userId: "u-dono", userRole: "admin" })).replace(/ /g, " ");
  assertStringIncludes(resumo, "Dividir o pagamento de *Roberto Daniel Rodrigues Correa*: R$ 500,00 · sex 09/10 · C6 - Conta PJ HBR");
  assertStringIncludes(resumo, "Diárias R$ 408,00 · Reembolso de despesas pagas pelo técnico R$ 92,00 (CMP-00124, CMP-00130).");
  assertEquals(doAgente.chamadas.find((x) => x.n === "conta_corrente_freelancer")?.a.p_autor, "u-dono");
  // técnico não divide
  const tec = ctxDaDivisao([PIX_DO_BANCO]);
  const rt = await tool("dividir_pagamento_freelancer").execute({ freelancer: "roberto" }, { ...tec.c, userRole: "technician" } as never) as { error?: string };
  assertEquals(typeof rt.error, "string");
  assertEquals(tec.chamadas.length, 0);
});

// ─── Agenda de Produção, Fase 2 (P4): a diária sugere a OS do plano ───────────────────────────────────
// Com a agenda automática ligada, agenda_os_do_dia diz em que OS a pessoa estava no plano naquele dia. Sem OS dita, a
// diária vai nela (e o "sim" diz "pelo plano"); com OS dita diferente, o "sim" mostra a divergência. Sem plano (agenda
// fora de ligado: o banco devolve []), tudo como antes. A leitura que falha não inventa OS: segue sem sugestão e vai
// para app_error_logs.
const PLANO_DO_DIA = [{ os: "os69", numero: "OS-00069", cliente_curto: "Vanderlei", turnos: ["manha", "tarde"], tipo: "execucao", reserva: false }];

Deno.test("plano: sem OS dita, a diária do dia vai na OS do plano daquela pessoa (agenda_os_do_dia com o favorecido e o dia)", async () => {
  const { c, chamadas } = ctx({ plano: PLANO_DO_DIA });
  await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" }, c as never);
  const reg = chamadas.find((x) => x.n === "registrar_diaria")!;
  assertEquals(reg.a.p_os_ids, ["os69"]);
  const pedido = (c.admin as any).simuladas.find((s: any) => s.n === "agenda_os_do_dia");
  assertEquals([pedido.p_payee, pedido.p_dia], ["p-rob", "2026-09-24"]);
});

Deno.test("plano: o \"sim\" diz a OS e o cliente, pelo plano", async () => {
  const txt = String(await resumirDiaria(ctx({ plano: PLANO_DO_DIA }).c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "inteiro" }))
    .replace(/ /g, " ");
  assertStringIncludes(txt, "*Roberto Daniel Rodrigues Correa* · qui 24/09 · *dia inteiro* · R$ 160,00 · OS-00069 (Vanderlei), pelo plano");
  assertEquals(txt.includes("Pelo plano,"), false);
});

Deno.test("plano: OS dita diferente do plano → a divergência vai no \"sim\" e vale a OS dita", async () => {
  const txt = String(await resumirDiaria(ctx({ plano: PLANO_DO_DIA }).c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "inteiro", os: "60" }))
    .replace(/ /g, " ");
  assertStringIncludes(txt, "R$ 160,00 · OS-00060");
  assertStringIncludes(txt, "Pelo plano, Roberto Daniel Rodrigues Correa estava na OS-00069 (Vanderlei) nesse dia; vai na OS-00060, como você disse.");
  const { c, chamadas } = ctx({ plano: PLANO_DO_DIA });
  await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro", os: "60" }, c as never);
  assertEquals(chamadas.find((x) => x.n === "registrar_diaria")!.a.p_os_ids, ["os60"]);
});

Deno.test("plano: a OS dita que É a do plano não vira divergência; duas OS no dia vão as duas", async () => {
  const igual = String(await resumirDiaria(ctx({ plano: [{ ...PLANO_DO_DIA[0], os: "os60", numero: "OS-00060" }] }).c as never,
    { freelancer: "roberto", data: "24/09/2026", jornada: "inteiro", os: "60" }));
  assertEquals(igual.includes("Pelo plano,"), false);
  const duas = [{ ...PLANO_DO_DIA[0], turnos: ["manha"] }, { os: "os60", numero: "OS-00060", cliente_curto: "Lenine", turnos: ["tarde"], tipo: "execucao", reserva: false }];
  const { c, chamadas } = ctx({ plano: duas });
  await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" }, c as never);
  assertEquals(chamadas.find((x) => x.n === "registrar_diaria")!.a.p_os_ids, ["os69", "os60"]);
});

Deno.test("plano (revisão da Fase 2): meia diária com duas OS no plano não vai nas duas — fica sem OS e o \"sim\" pergunta qual", async () => {
  const duas = [{ ...PLANO_DO_DIA[0], turnos: ["manha"] }, { os: "os60", numero: "OS-00060", cliente_curto: "Lenine", turnos: ["tarde"], tipo: "execucao", reserva: false }];
  const { c, chamadas } = ctx({ plano: duas });
  await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "meio" }, c as never);
  assertEquals(chamadas.find((x) => x.n === "registrar_diaria")!.a.p_os_ids, null, "nunca as duas: o valor se dividiria");
  const txt = String(await resumirDiaria(ctx({ plano: duas }).c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "meio" }))
    .replace(/ /g, " ");
  assertStringIncludes(txt, "Pelo plano, Roberto Daniel Rodrigues Correa estava na OS-00069 (Vanderlei) de manhã e na OS-00060 (Lenine) à tarde: a meia diária é de qual? Diga a OS; sem ela, a diária fica sem OS.");
  assertEquals(txt.includes("se divide em partes iguais"), false);
  assertEquals(txt.includes(", pelo plano"), false);
  // com a OS dita, vale ela (e não há pergunta)
  const dita = String(await resumirDiaria(ctx({ plano: duas }).c as never, { freelancer: "roberto", data: "24/09/2026", jornada: "meio", os: "60" }));
  assertEquals(dita.includes("a meia diária é de qual?"), false);
  // meia diária com UMA OS no plano continua indo nela
  const uma = ctx({ plano: [{ ...PLANO_DO_DIA[0], turnos: ["manha"] }] });
  await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "meio" }, uma.c as never);
  assertEquals(uma.chamadas.find((x) => x.n === "registrar_diaria")!.a.p_os_ids, ["os69"]);
});

Deno.test("plano: sem plano (agenda fora de ligado), falta, intervalo e reserva ficam como antes", async () => {
  const semPlano = ctx();
  await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" }, semPlano.c as never);
  assertEquals(semPlano.chamadas.find((x) => x.n === "registrar_diaria")!.a.p_os_ids, null);
  // Falta (main, Diárias fase 1b, 27/10/2026): dia não trabalhado não se lança — a tool recusa antes de gravar e de ler o plano.
  const falta = ctx({ plano: PLANO_DO_DIA });
  const rFalta = await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "faltou" }, falta.c as never) as { error?: string };
  assertEquals(typeof rFalta.error, "string");
  assertEquals(falta.chamadas.some((x) => x.n === "registrar_diaria"), false);
  assertEquals((falta.c.admin as any).simuladas.some((s: any) => s.n === "agenda_os_do_dia"), false);
  const reserva = ctx({ plano: [{ ...PLANO_DO_DIA[0], reserva: true }] });
  await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" }, reserva.c as never);
  assertEquals(reserva.chamadas.find((x) => x.n === "registrar_diaria")!.a.p_os_ids, null);
  const p = await resolverDiaria(ctx({ plano: PLANO_DO_DIA }).c as never, { freelancer: "roberto", data: "21/09/2026", data_ate: "24/09/2026", jornada: "inteiro" });
  if ("error" in p) throw new Error(p.error);
  assertEquals(p.os, []);
});

Deno.test("plano: a leitura do plano que falha não inventa OS — segue como antes e vai para app_error_logs", async () => {
  const { c, chamadas } = ctx({ erroDoPlano: "function agenda_os_do_dia does not exist" });
  await tool("registrar_diaria").execute({ freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" }, c as never);
  assertEquals(chamadas.find((x) => x.n === "registrar_diaria")!.a.p_os_ids, null);
  const log = (c.admin as any).simuladas.find((s: any) => s.n === "log_app_error");
  assertEquals([log.p_context, log.p_action, log.p_level], ["agenda", "diaria:plano", "warn"]);
});

// ── Agenda de Produção, Fase 3 (P4, 24/10/2026): o "sim" diz quando foi a agenda que lançou a diária ──────────
Deno.test("agenda P4: a diária que a agenda lançou aparece no resumo do sim, com a palavra que corrige", async () => {
  const texto = "A agenda já lançou essa diária às 17:12 (corrige com *diária Roberto meia*).";
  const { c } = ctx({ daAgenda: { data: { lancada: true, texto } } });
  const r = await resumirDiaria(c as never, { freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" });
  assertStringIncludes(r!, texto);
  const pedido = (c.admin as any).simuladas.find((s: any) => s.n === "agenda_diaria_da_agenda");
  assertEquals([pedido.p_payee, pedido.p_dia], ["p-rob", "2026-09-24"]);
  // sem diária da agenda, nada muda no resumo
  const semNada = await resumirDiaria(ctx().c as never, { freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" });
  assertEquals(semNada!.includes("A agenda já lançou"), false);
});

Deno.test("agenda P4: a função ainda não aplicada não muda o resumo nem registra erro; outro erro registra (warn) e não inventa linha", async () => {
  const ausente = ctx({ daAgenda: { error: { code: "PGRST202", message: "Could not find the function agenda_diaria_da_agenda" } } });
  const r1 = await resumirDiaria(ausente.c as never, { freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" });
  assertEquals(r1!.includes("A agenda já lançou"), false);
  assertEquals((ausente.c.admin as any).simuladas.some((s: any) => s.n === "log_app_error"), false);
  const quebrou = ctx({ daAgenda: { error: { code: "57014", message: "statement timeout" } } });
  const r2 = await resumirDiaria(quebrou.c as never, { freelancer: "Roberto", data: "24/09/2026", jornada: "inteiro" });
  assertEquals(r2!.includes("A agenda já lançou"), false);
  const log = (quebrou.c.admin as any).simuladas.find((s: any) => s.n === "log_app_error");
  assertEquals([log.p_context, log.p_action, log.p_level], ["agenda", "diaria:da_agenda", "warn"]);
});

// ── F3 (27/10/2026): a semana numa confirmação só; PDF só depois do "sim"; Pix sem identidade ──

Deno.test("lote: trechos de jornadas diferentes viram UMA confirmação, com o total e cada trecho", async () => {
  const txt = String(await resumirDiaria(ctx().c as never, { freelancer: "roberto", dias: [
    { data: "21/09/2026", data_ate: "24/09/2026", jornada: "inteiro" },
    { data: "25/09/2026", jornada: "meio", observacao: "lancha do Marcelo" },
    { data: "26/09/2026", jornada: "inteiro", extras: 20 },
  ] })).replace(/\u00a0/g, " ");
  assertStringIncludes(txt, "Registrar diárias de *Roberto Daniel Rodrigues Correa*: 6 dia(s) · R$ 900,00");
  assertStringIncludes(txt, "• seg 21/09 a qui 24/09 (4 dias, só dias úteis) · dia inteiro · R$ 160,00 cada");
  assertStringIncludes(txt, "• sex 25/09 · meio período · R$ 80,00 · lancha do Marcelo");
  assertStringIncludes(txt, "• sáb 26/09 · dia inteiro · R$ 180,00 (extras R$ 20,00)");
});

Deno.test("lote: dia já lançado num intervalo fica; dito sozinho, corrige; dia repetido e apagar viram pergunta", async () => {
  const txt = String(await resumirLote(ctx({ diaLancado: true }).c as never, { freelancer: "roberto", dias: [
    { data: "21/09/2026", data_ate: "25/09/2026", jornada: "inteiro" },
  ] })).replace(/\u00a0/g, " ");
  assertStringIncludes(txt, "Já lançados, ficam como estão: 24/09 (meio período).");
  const corrige = String(await resumirLote(ctx({ diaLancado: true }).c as never, { freelancer: "roberto", dias: [
    { data: "24/09/2026", jornada: "inteiro" }, { data: "25/09/2026", jornada: "meio" },
  ] })).replace(/\u00a0/g, " ");
  assertStringIncludes(corrige, "vão ser corrigidos (não duplicados): 24/09 (era meio período, R$ 80,00)");
  const repetido = await resolverLote(ctx().c as never, { freelancer: "roberto", dias: [
    { data: "21/09/2026", data_ate: "25/09/2026", jornada: "inteiro" }, { data: "23/09/2026", jornada: "meio" },
  ] });
  assertStringIncludes(String((repetido as { error: string }).error), "aparece em dois trechos");
  const apagar = await resolverLote(ctx().c as never, { freelancer: "roberto", dias: [{ data: "21/09/2026", jornada: "apagar" }] });
  assertStringIncludes(String((apagar as { error: string }).error), "Apagar é um dia de cada vez");
});

Deno.test("lote: grava numa chamada só (registrar_diarias_em_lote) só os dias que entram, e diz o saldo", async () => {
  const { c, chamadas } = ctx({ diaLancado: true });
  const r = await tool("registrar_diaria").execute({ freelancer: "roberto", dias: [
    { data: "21/09/2026", data_ate: "25/09/2026", jornada: "inteiro" }, { data: "26/09/2026", jornada: "meio" },
  ] }, c as never) as Record<string, any>;
  const lote = chamadas.filter((x) => x.n === "registrar_diarias_em_lote");
  assertEquals(lote.length, 1);
  assertEquals(chamadas.filter((x) => x.n === "registrar_diaria").length, 0);
  assertEquals((lote[0].a.p_dias as any[]).map((d) => [d.data, d.jornada]),
    [["2026-09-21", "inteiro"], ["2026-09-22", "inteiro"], ["2026-09-23", "inteiro"], ["2026-09-25", "inteiro"], ["2026-09-26", "meio"]]);
  assertEquals("item" in (lote[0].a.p_dias as any[])[0], false, "só os campos do banco");
  assertEquals(lote[0].a.p_autor, "u-dono");
  assertStringIncludes(String(r.aviso), "5 dia(s) registrado(s): 21/09, 22/09, 23/09, 25/09, 26/09.");
  assertStringIncludes(String(r.aviso), "Já lançados, mantidos: 24/09 (meio período).");
  assertStringIncludes(String(r.aviso), "Saldo com Roberto");
});

// ── PÓS-MERGE (B, 28/10/2026): a diária em lote faz, dia a dia, o que a diária de um dia faz com a agenda ────────────
// O lote (dias=[…], do main) gravava sem a OS do plano e sem dizer "a agenda já lançou essa diária" (Fase 2, P4; Fase 3,
// P4). Agora cada dia que entra pergunta o plano DAQUELE dia (também os dias de um intervalo do lote): sem OS dita, vai na
// OS do plano; meia diária com duas OS no plano fica sem OS e o "sim" pergunta qual; OS dita diferente do plano vira a
// divergência no "sim". E cada dia já lançado que a agenda lançou ganha a linha da agenda, com a palavra que corrige.
const VANDERLEI = { os: "os69", numero: "OS-00069", cliente_curto: "Vanderlei", turnos: ["manha", "tarde"], tipo: "execucao", reserva: false };
const LENINE = { os: "os60", numero: "OS-00060", cliente_curto: "Lenine", turnos: ["manha", "tarde"], tipo: "execucao", reserva: false };

Deno.test("lote (pós-merge B): sem OS dita, cada dia vai na OS do plano DAQUELE dia — também dentro de um intervalo", async () => {
  const planoPorDia = { "2026-09-21": [VANDERLEI], "2026-09-22": [VANDERLEI], "2026-09-23": [LENINE] };
  const args = { freelancer: "roberto", dias: [
    { data: "21/09/2026", data_ate: "23/09/2026", jornada: "inteiro" }, { data: "25/09/2026", jornada: "inteiro" },
  ] };
  const { c, chamadas } = ctx({ planoPorDia });
  await tool("registrar_diaria").execute(args, c as never);
  const lote = chamadas.find((x) => x.n === "registrar_diarias_em_lote")!;
  assertEquals((lote.a.p_dias as any[]).map((d) => [d.data, d.os_ids]),
    [["2026-09-21", ["os69"]], ["2026-09-22", ["os69"]], ["2026-09-23", ["os60"]], ["2026-09-25", null]]);
  const pedidos = (c.admin as any).simuladas.filter((s: any) => s.n === "agenda_os_do_dia").map((s: any) => s.p_dia).sort();
  assertEquals(pedidos, ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-25"]);
  const txt = String(await resumirLote(ctx({ planoPorDia }).c as never, args)).replace(/ /g, " ");
  assertStringIncludes(txt, "• seg 21/09 a qua 23/09 (3 dias, só dias úteis) · dia inteiro · R$ 160,00 cada · pelo plano: 21/09, 22/09 OS-00069 (Vanderlei); 23/09 OS-00060 (Lenine)");
  assertEquals(txt.endsWith("\n• sex 25/09 · dia inteiro · R$ 160,00"), true, "o dia sem plano vai sem OS");
  // um trecho só com a mesma OS todos os dias: a linha diz a OS uma vez
  const igual = String(await resumirLote(ctx({ plano: [VANDERLEI] }).c as never, { freelancer: "roberto", dias: [
    { data: "21/09/2026", data_ate: "22/09/2026", jornada: "inteiro" },
  ] })).replace(/ /g, " ");
  assertStringIncludes(igual, "dia inteiro · R$ 160,00 cada · OS-00069 (Vanderlei), pelo plano");
});

Deno.test("lote (pós-merge B): meia diária com duas OS no plano fica sem OS e pergunta; OS dita diferente vira divergência; manter não lê o plano", async () => {
  const duas = [{ ...VANDERLEI, turnos: ["manha"] }, { ...LENINE, turnos: ["tarde"] }];
  const planoPorDia = { "2026-09-21": duas, "2026-09-22": [VANDERLEI] };
  const args = { freelancer: "roberto", dias: [{ data: "21/09/2026", jornada: "meio" }, { data: "22/09/2026", jornada: "inteiro", os: "60" }] };
  const { c, chamadas } = ctx({ planoPorDia });
  await tool("registrar_diaria").execute(args, c as never);
  assertEquals((chamadas.find((x) => x.n === "registrar_diarias_em_lote")!.a.p_dias as any[]).map((d) => [d.data, d.os_ids]),
    [["2026-09-21", null], ["2026-09-22", ["os60"]]]);
  const txt = String(await resumirLote(ctx({ planoPorDia }).c as never, args)).replace(/ /g, " ");
  assertStringIncludes(txt, "seg 21/09: Pelo plano, Roberto Daniel Rodrigues Correa estava na OS-00069 (Vanderlei) de manhã e na OS-00060 (Lenine) à tarde: a meia diária é de qual? Diga a OS; sem ela, a diária fica sem OS.");
  assertStringIncludes(txt, "ter 22/09: Pelo plano, Roberto Daniel Rodrigues Correa estava na OS-00069 (Vanderlei) nesse dia; vai na OS-00060, como você disse.");
  assertEquals(txt.includes("se divide em partes iguais"), false);
  // duas OS no plano num dia inteiro: vão as duas, e o "sim" diz que o valor se divide
  const inteiro = String(await resumirLote(ctx({ planoPorDia }).c as never, { freelancer: "roberto", dias: [{ data: "21/09/2026", jornada: "inteiro" }] }));
  assertStringIncludes(inteiro, "O valor do dia se divide em partes iguais entre as OS.");
  // manter (só extras do dia já lançado) não lê o plano, como no caminho de um dia
  const manter = ctx({ diaLancado: true, plano: [VANDERLEI] });
  await resumirLote(manter.c as never, { freelancer: "roberto", dias: [{ data: "24/09/2026", jornada: "manter", extras: 10 }] });
  assertEquals((manter.c.admin as any).simuladas.some((s: any) => s.n === "agenda_os_do_dia"), false);
});

Deno.test("lote (pós-merge B): o \"sim\" diz, dia a dia, a diária que a agenda já lançou (e só pergunta pelos dias já lançados)", async () => {
  const texto = "A agenda já lançou essa diária às 17:12 (corrige com *diária Roberto meia*).";
  const { c } = ctx({ diaLancado: true, daAgendaPorDia: { "2026-09-24": { lancada: true, texto } } });
  const txt = String(await resumirLote(c as never, { freelancer: "roberto", dias: [
    { data: "24/09/2026", jornada: "inteiro" }, { data: "25/09/2026", jornada: "meio" },
  ] }));
  assertStringIncludes(txt, `qui 24/09: ${texto}`);
  const perguntados = (c.admin as any).simuladas.filter((s: any) => s.n === "agenda_diaria_da_agenda").map((s: any) => [s.p_payee, s.p_dia]);
  assertEquals(perguntados, [["p-rob", "2026-09-24"]]);
  // o dia lançado que fica como está (intervalo) também diz que foi a agenda
  const mantido = String(await resumirLote(ctx({ diaLancado: true, daAgendaPorDia: { "2026-09-24": { lancada: true, texto } } }).c as never,
    { freelancer: "roberto", dias: [{ data: "21/09/2026", data_ate: "25/09/2026", jornada: "inteiro" }] }));
  assertStringIncludes(mantido, `qui 24/09: ${texto}`);
  // sem diária da agenda, nenhuma linha
  const nada = String(await resumirLote(ctx({ diaLancado: true }).c as never, { freelancer: "roberto", dias: [{ data: "24/09/2026", jornada: "inteiro" }] }));
  assertEquals(nada.includes("A agenda já lançou"), false);
});

Deno.test("PDF só depois do sim: com lançamento da pessoa esperando, extrato e recibo não saem", async () => {
  const pendencias = [{ id: "pa1", status: "pending", action_name: "registrar_diaria", payload: { freelancer: "Roberto" }, expires_at: "2999-01-01T00:00:00Z" }];
  const { c, chamadas } = ctx({ pendencias });
  const r = await tool("enviar_extrato_freelancer").execute({ freelancer: "roberto" }, c as never) as { error?: string };
  assertStringIncludes(String(r.error), "esperando o seu \"sim\": o PDF sai depois que você confirmar");
  assertEquals(chamadas.length, 0);
  const r2 = await tool("enviar_acerto_ao_freelancer").execute({ freelancer: "roberto" }, c as never) as { error?: string };
  assertStringIncludes(String(r2.error), "Não mandei nada");
  // pendência de OUTRA pessoa, ou vencida, não trava
  const outra = ctx({ pendencias: [{ ...pendencias[0], payload: { freelancer: "João" } }, { ...pendencias[0], id: "pa2", expires_at: "2000-01-01T00:00:00Z" }] });
  const r3 = await tool("enviar_acerto_ao_freelancer").execute({ freelancer: "roberto" }, outra.c as never) as { error?: string };
  assertEquals(String(r3.error ?? "").includes("esperando"), false);
});

Deno.test("Pix na fila em outro nome: não afirma que é de outra pessoa; diz o que fazer", () => {
  const t = textoDaFilaSemIdentidade({ freelancer: { id: "p-joa", nome: "João Marcelo", perfis: [] }, valor: 310 }, "JOAO MARCELO RODRIGUES CORREA").replace(/\u00a0/g, " ");
  assertEquals(/é de outro/.test(t), false);
  assertStringIncludes(t, "já desconta no saldo dele");
  assertStringIncludes(t, "o nome do extrato não identifica a pessoa");
  assertStringIncludes(t, "aprove-a na fila como diária dele: a anotação sai sozinha");
  assertStringIncludes(t, "ponha o CPF dele no cadastro");
});
