// Diárias pela conversa: o que se fixa aqui é a parte que interpreta a fala (quem, que dia, inteiro/
// meio/falta, qual OS), o que vai para a confirmação e o que é mandado às funções do banco.
// O dia em si — valor gravado, um por pessoa, saldo — é das funções do banco
// (supabase/tests/diarias_conta_corrente.sql).
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/diarias_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  dataDoDito, datasDoIntervalo, diaCurto, diariasTools, numeroDito, paramsDoCadastro, periodoDito, resolverDiaria,
  resolverPagamento, resumirAcerto, resumirCadastro, resumirDiaria, resumirEnvioAoFreelancer, resumirPagamento,
} from "./diarias.ts";

/** Banco falso: só o que as tools leem. `simulacao` é o que cadastrar_freelancer devolve simulando. */
type Opcoes = {
  diaLancado?: boolean; cargo?: string; semTelefone?: boolean; semAcerto?: boolean; acertoReaberto?: boolean;
  simulacao?: { data?: unknown; error?: { message: string } };
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

Deno.test("oito ferramentas: as que gravam ou mandam a terceiro pedem confirmação, consultar e o PDF para si não; todas só para gestor", () => {
  assertEquals(diariasTools.map((t) => t.name).sort(), [
    "cadastrar_freelancer", "consultar_freelancer", "enviar_acerto_ao_freelancer", "enviar_extrato_freelancer", "fechar_acerto_freelancer",
    "reabrir_acerto_freelancer", "registrar_diaria", "registrar_pagamento_freelancer",
  ]);
  for (const n of ["fechar_acerto_freelancer", "reabrir_acerto_freelancer", "enviar_acerto_ao_freelancer"]) assertEquals(tool(n).risk, "medium");
  assertEquals(tool("registrar_diaria").risk, "medium");
  assertEquals(tool("cadastrar_freelancer").risk, "medium");
  assertEquals(tool("registrar_pagamento_freelancer").risk, "medium");
  assertEquals(tool("consultar_freelancer").risk, "low");
  assertEquals(tool("enviar_extrato_freelancer").risk, "low");
  assertEquals((tool("registrar_pagamento_freelancer").input_schema as any).required, ["freelancer", "valor", "forma"]);
  for (const t of diariasTools) assertEquals(t.roles, ["admin", "financial"]);
  assertEquals((tool("registrar_diaria").input_schema as any).required, ["freelancer", "jornada"]);
  assertEquals((tool("cadastrar_freelancer").input_schema as any).required, ["nome", "valor_diaria"]);
  assertEquals((tool("registrar_diaria").input_schema as any).properties.jornada.enum, ["inteiro", "meio", "faltou", "apagar"]);
});

Deno.test("a descrição separa diária de pagamento, de hora de OS e de 'apagar'", () => {
  const d = tool("registrar_diaria").description;
  assertStringIncludes(d, "'faltou' grava a ausência");
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

Deno.test("'o Roberto não veio hoje': grava a falta pela função do banco, sem OS e com quem pediu", async () => {
  const { c, chamadas } = ctx();
  const r = await tool("registrar_diaria").execute({ freelancer: "Roberto", jornada: "faltou" }, c as never) as Record<string, unknown>;
  const reg = chamadas.find((x) => x.n === "registrar_diaria")!;
  assertEquals(reg.a.p_favorecido_id, "p-rob");
  assertEquals(reg.a.p_jornada, "faltou");
  assertEquals(reg.a.p_os_ids, null);
  assertEquals(reg.a.p_valor_diaria, null);
  assertEquals(reg.a.p_origem, "agente");
  assertEquals(reg.a.p_autor, "u-dono");
  // A confirmação depois do "sim" traz o que foi gravado E o saldo com a pessoa.
  assertStringIncludes(String(r.aviso), "faltou");
  assertStringIncludes(String(r.aviso).replace(/ /g, " "), "Saldo com Roberto Daniel Rodrigues Correa: R$ 290,00 (você deve a ele)");
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
  assertStringIncludes(novo, "*Roberto Daniel Rodrigues Correa* · qui 24/09 · *dia inteiro* · R$ 160,00 · OS OS-00060, OS-00061");
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
  const p = await resolverDiaria(c as never, { freelancer: "mickael", jornada: "faltou", data: "19/09/2026", data_ate: "25/09/2026" });
  if ("error" in p) throw new Error(p.error);
  assertEquals(p.intervalo, true);
  assertEquals(p.datas, ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25"]);

  const erro = async (a: Record<string, unknown>) => String(((await resolverDiaria(c as never, { freelancer: "mickael", jornada: "faltou", ...a })) as { error?: string }).error);
  assertStringIncludes(await erro({ data: "25/09/2026", data_ate: "19/09/2026" }), "invertido");
  assertStringIncludes(await erro({ data: "25/09/2026", data_ate: "31/12/2099" }), "futuro");
  assertStringIncludes(await erro({ data: "01/01/2026", data_ate: "30/06/2026" }), "grande demais");
  assertStringIncludes(await erro({ data: "26/09/2026", data_ate: "27/09/2026" }), "Nenhum dia útil");
  assertStringIncludes(await erro({ jornada: "apagar", data: "21/09/2026", data_ate: "25/09/2026" }), "um dia de cada vez");
});

Deno.test("vários dias: registra só os que faltam — o dia já lançado no meio fica como está", async () => {
  const { c, chamadas } = ctx({ diaLancado: true }); // 24/09 já tem meio período do Roberto
  const r = await tool("registrar_diaria").execute(
    { freelancer: "roberto", jornada: "faltou", data: "21/09/2026", data_ate: "25/09/2026" }, c as never) as Record<string, any>;
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

Deno.test("valor dito: vai para o banco só nesse dia, aparece na confirmação; falta ignora o valor", async () => {
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

  const falta = await resolverDiaria(c as never, { freelancer: "mickael", jornada: "faltou", valor_diaria: 150 });
  if ("error" in falta) throw new Error(falta.error);
  assertEquals(falta.valorDiaria, null);
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
    de: "2026-09-16", ate: "2026-10-01", dias: 2.5, trabalhado: 400, saldo_anterior: 0, pago_no_periodo: 100, valor_do_acerto: 300, pago_aguardando_banco: 100,
  } } }).c as never, { freelancer: "roberto" })).replace(/\u00a0/g, " ");
  assertStringIncludes(txt, "Fechar acerto de *Roberto Daniel Rodrigues Correa*: 16/09 a 01/10");
  assertStringIncludes(txt, "2,5 diária(s) = R$ 400,00 · vales já pagos R$ 100,00");
  assertStringIncludes(txt, "*A pagar neste acerto: R$ 300,00*");
  assertStringIncludes(txt, "Pix lançados à mão");

  const recusa = String(await resumirAcerto(ctx({ simulacao: { error: { message: "P0001: Nada a fechar: o acerto nº 0001 de Roberto já vai até 15/09." } } }).c as never, { freelancer: "roberto" }));
  assertStringIncludes(recusa, "⚠️ Nada a fechar");
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
