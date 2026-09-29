// Diárias pela conversa: o que se fixa aqui é a parte que interpreta a fala (quem, que dia, inteiro/
// meio/falta, qual OS), o que vai para a confirmação e o que é mandado às funções do banco.
// O dia em si — valor gravado, um por pessoa, saldo — é das funções do banco
// (supabase/tests/diarias_conta_corrente.sql).
// Rodar com:
//   deno test --allow-all supabase/functions/_shared/ai/tools/diarias_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { diaCurto, diariasTools, intervaloDito, resolverDiaria, resumirDiaria } from "./diarias.ts";

/** Banco falso: só o que as tools leem. */
function admin(opcoes: { diaLancado?: boolean } = {}) {
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
  };
  const consulta = (nome: string) => {
    const q: any = {
      _rows: [...(tabelas[nome] ?? [])],
      select() { return q; }, limit() { return q; },
      eq(coluna: string, valor: unknown) { q._rows = q._rows.filter((r: any) => r[coluna] === valor); return q; },
      in(coluna: string, valores: unknown[]) { q._rows = q._rows.filter((r: any) => valores.includes(r[coluna])); return q; },
      not(coluna: string, _op: string, _v: unknown) { q._rows = q._rows.filter((r: any) => r[coluna] != null); return q; },
      ilike(_c: string, padrao: string) {
        const alvo = padrao.replaceAll("%", "");
        q._rows = q._rows.filter((r: any) => String(r.service_order_number ?? "").includes(alvo));
        return q;
      },
      then(res: any) { return Promise.resolve({ data: q._rows, error: null }).then(res); },
    };
    return q;
  };
  return { from: consulta };
}

type Chamada = { n: string; a: Record<string, unknown> };
function ctx(opcoes: { diaLancado?: boolean; cargo?: string } = {}) {
  const chamadas: Chamada[] = [];
  const rpc = (n: string, a: Record<string, unknown>) => {
    chamadas.push({ n, a });
    if (n === "registrar_diaria") return Promise.resolve({ data: { ok: true, acao: "criado", message: "Roberto · qui 24/09 · faltou · R$ 0,00 — registrado." }, error: null });
    if (n === "conta_corrente_freelancer") return Promise.resolve({ data: { saldo_final: 290, estado: "deve", dias: 12, trabalhado: 1820, pago: 1530, linhas: [] }, error: null });
    if (n === "apagar_diaria") return Promise.resolve({ data: { ok: true, apagado: {}, message: "Diária de Roberto em qui 24/09 apagada." }, error: null });
    if (n === "resumo_freelancers") return Promise.resolve({ data: { pessoas: [{ nome: "Roberto", dias: 12, trabalhado: 1980, pago: 1530, saldo_final: 450, estado: "deve" }] }, error: null });
    return Promise.resolve({ data: null, error: { message: `rpc inesperada ${n}` } });
  };
  return {
    c: { sb: { rpc }, admin: admin(opcoes), userId: "u-dono", userRole: (opcoes.cargo ?? "admin") as any, jwt: "", appOrigin: "", settings: {} },
    chamadas,
  };
}
const tool = (nome: string) => diariasTools.find((t) => t.name === nome)!;

Deno.test("duas ferramentas: registrar pede confirmação, consultar só lê; as duas só para gestor", () => {
  assertEquals(diariasTools.map((t) => t.name).sort(), ["consultar_freelancer", "registrar_diaria"]);
  assertEquals(tool("registrar_diaria").risk, "medium");
  assertEquals(tool("consultar_freelancer").risk, "low");
  for (const t of diariasTools) assertEquals(t.roles, ["admin", "financial"]);
  assertEquals((tool("registrar_diaria").input_schema as any).required, ["freelancer", "jornada"]);
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
  assertEquals(typeof um.chamadas[0].a.p_de, "string");
  assertEquals(r2.situacao, "você deve a ele");
});

Deno.test("período dito e dia curto, em Brasília", () => {
  const agora = new Date("2026-09-29T15:00:00Z");
  assertEquals(intervaloDito("este_mes", agora), { de: "2026-09-01", ate: "2026-09-30" });
  assertEquals(intervaloDito("mes_passado", new Date("2026-01-10T15:00:00Z")), { de: "2025-12-01", ate: "2025-12-31" });
  assertEquals(intervaloDito("tudo", agora), { de: null, ate: null });
  assertEquals(diaCurto("2026-09-24"), "qui 24/09");
});
