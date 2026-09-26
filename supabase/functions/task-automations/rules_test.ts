import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import {
  RULES, isRuleEnabled, ruleById, ruleIdFromKey, entityIdFromKey, keyOf, fmtBRL, fmtDate, dueAt,
  isManualDismissal, dismissCooldownDays, businessDaysBetween, vencimentoDoOrcamento, notaDoVencimento,
} from "./rules.ts";

Deno.test("isManualDismissal: conclusão MANUAL recente bloqueia recriação", () => {
  const cutoff = "2026-07-17T00:00:00Z";
  // humano concluiu ontem → bloqueia
  assertEquals(isManualDismissal(
    { status: "done", completed_by: "user-1", completed_at: "2026-07-23T10:00:00Z", updated_at: null }, cutoff), true);
  // auto-resolução (completed_by null) → NÃO bloqueia (condição sumiu; se voltar é novo)
  assertEquals(isManualDismissal(
    { status: "done", completed_by: null, completed_at: "2026-07-23T10:00:00Z", updated_at: null }, cutoff), false);
  // conclusão manual ANTIGA (antes do cutoff) → não bloqueia mais
  assertEquals(isManualDismissal(
    { status: "done", completed_by: "user-1", completed_at: "2026-07-10T10:00:00Z", updated_at: null }, cutoff), false);
  // cancelada recentemente → bloqueia (dispensa explícita)
  assertEquals(isManualDismissal(
    { status: "cancelled", completed_by: null, completed_at: null, updated_at: "2026-07-23T10:00:00Z" }, cutoff), true);
  // viva não entra (função só recebe done/cancelled, mas por segurança)
  assertEquals(isManualDismissal(
    { status: "pending", completed_by: null, completed_at: null, updated_at: "2026-07-23T10:00:00Z" }, cutoff), false);
});

Deno.test("dismissCooldownDays: default 7, override por setting", () => {
  assertEquals(dismissCooldownDays({}), 7);
  assertEquals(dismissCooldownDays({ task_rule_dismiss_cooldown_days: "3" }), 3);
  assertEquals(dismissCooldownDays({ task_rule_dismiss_cooldown_days: "0" }), 0);
  assertEquals(dismissCooldownDays({ task_rule_dismiss_cooldown_days: "lixo" }), 7);
});

Deno.test("keyOf/entityIdFromKey/ruleIdFromKey: ida e volta", () => {
  const k = keyOf("r3", "recv", "abc-123");
  assertEquals(k, "r3:recv:abc-123");
  assertEquals(ruleIdFromKey(k), "r3");
  assertEquals(entityIdFromKey(k), "abc-123");
  assertEquals(ruleIdFromKey(keyOf("r2", "so", "x", "2026-W30")), "r2");
});

Deno.test("isRuleEnabled: default quando setting ausente, override quando presente", () => {
  const r1 = ruleById("r1")!;
  assertEquals(isRuleEnabled({}, r1), true);
  assertEquals(isRuleEnabled({ task_rule_r1_enabled: "false" }, r1), false);
  assertEquals(isRuleEnabled({ task_rule_r1_enabled: "true" }, r1), true);
});

Deno.test("todas as regras têm id único e formato rN", () => {
  const ids = RULES.map((r) => r.id);
  assertEquals(new Set(ids).size, ids.length);
  for (const id of ids) {
    if (!/^r\d+$/.test(id)) throw new Error(`id inválido: ${id}`);
  }
});

Deno.test("fmtBRL/fmtDate/dueAt: formatos estáveis", () => {
  assertEquals(fmtDate("2026-07-30"), "30/07/2026");
  assertEquals(dueAt("2026-07-30"), "2026-07-30T11:00:00Z");
  // fmtBRL usa NBSP entre R$ e o número — comparar sem depender do espaço exato
  assertEquals(fmtBRL(1234.5).replace(/\s/g, ""), "R$1.234,50");
});

Deno.test("isResolved: recebível pago resolve, pendente não (mock de db)", async () => {
  const r3 = ruleById("r3")!;
  const mkDb = (row: unknown) => ({
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row }) }) }),
    }),
  });
  assertEquals(
    await r3.isResolved(mkDb({ status: "paid", balance_amount: 0 }), { automation_key: "r3:recv:x" }),
    "Pagamento registrado",
  );
  assertEquals(
    await r3.isResolved(mkDb({ status: "pending", balance_amount: 100 }), { automation_key: "r3:recv:x" }),
    null,
  );
  assertEquals(
    await r3.isResolved(mkDb(null), { automation_key: "r3:recv:x" }),
    "Recebível não existe mais",
  );
});

Deno.test("isResolved r1: OS agendada ou status mudado resolve", async () => {
  const r1 = ruleById("r1")!;
  const mkDb = (row: unknown) => ({
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row }) }) }),
    }),
  });
  assertEquals(
    await r1.isResolved(mkDb({ status: "approved", scheduled_start_at: "2026-07-30T12:00:00Z" }), { automation_key: "r1:so:x" }),
    "OS foi agendada",
  );
  assertEquals(
    await r1.isResolved(mkDb({ status: "cancelled", scheduled_start_at: null }), { automation_key: "r1:so:x" }),
    "OS mudou para cancelled",
  );
  assertEquals(
    await r1.isResolved(mkDb({ status: "approved", scheduled_start_at: null }), { automation_key: "r1:so:x" }),
    null,
  );
});

// R16 é a rede do aviso de compra da aprovação: se estes testes falharem, a tarefa
// pode ficar viva para item que já chegou (ruído) ou morrer com item ainda faltando
// (a OS para sem ninguém saber).
Deno.test("isResolved r16: reserva e OC aberta contam; falta real mantém a tarefa", async () => {
  const r16 = ruleById("r16")!;

  // O mock distingue as tabelas porque a regra consulta quatro em sequência.
  const mkDb = (opts: {
    so?: unknown;
    parts?: unknown[];
    avail?: unknown[];
    poItems?: unknown[];
  }) => ({
    from: (table: string) => {
      if (table === "service_orders") {
        return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: opts.so }) }) }) };
      }
      if (table === "service_order_parts") {
        return { select: () => ({ eq: async () => ({ data: opts.parts ?? [] }) }) };
      }
      if (table === "product_availability") {
        return { select: () => ({ in: async () => ({ data: opts.avail ?? [] }) }) };
      }
      // purchase_order_items: dois .in() encadeados (produto e status da OC)
      return {
        select: () => ({ in: () => ({ in: async () => ({ data: opts.poItems ?? [] }) }) }),
      };
    },
  });

  const so = { status: "approved" };
  const parts = [{ product_id: "p1", quantity: 6 }];

  // físico cobre e nada está reservado → resolvida
  assertEquals(
    await r16.isResolved(
      mkDb({ so, parts, avail: [{ id: "p1", stock_quantity: 10, reserved_quantity: 0 }] }),
      { automation_key: "r16:so:x" },
    ),
    "Compra resolvida (em estoque ou já pedida)",
  );

  // físico existe mas está TODO reservado para outras OS → segue faltando
  assertEquals(
    await r16.isResolved(
      mkDb({ so, parts, avail: [{ id: "p1", stock_quantity: 10, reserved_quantity: 10 }] }),
      { automation_key: "r16:so:x" },
    ),
    null,
  );

  // sem estoque, mas já pedido em OC aberta → resolvida (está a caminho)
  assertEquals(
    await r16.isResolved(
      mkDb({
        so, parts,
        avail: [{ id: "p1", stock_quantity: 0, reserved_quantity: 0 }],
        poItems: [{ product_id: "p1", quantity: 6, received_qty: 0 }],
      }),
      { automation_key: "r16:so:x" },
    ),
    "Compra resolvida (em estoque ou já pedida)",
  );

  // OC parcialmente recebida não cobre o resto → segue faltando
  assertEquals(
    await r16.isResolved(
      mkDb({
        so, parts,
        avail: [{ id: "p1", stock_quantity: 0, reserved_quantity: 0 }],
        poItems: [{ product_id: "p1", quantity: 6, received_qty: 4 }],
      }),
      { automation_key: "r16:so:x" },
    ),
    null,
  );

  // OS saiu do ciclo de execução → não faz sentido comprar
  assertEquals(
    await r16.isResolved(mkDb({ so: { status: "cancelled" } }), { automation_key: "r16:so:x" }),
    "OS mudou para cancelled",
  );
  assertEquals(
    await r16.isResolved(mkDb({ so: undefined }), { automation_key: "r16:so:x" }),
    "OS não existe mais",
  );

  // peças removidas da OS
  assertEquals(
    await r16.isResolved(mkDb({ so, parts: [] }), { automation_key: "r16:so:x" }),
    "OS não tem mais peças lançadas",
  );
});

Deno.test("businessDaysBetween: ignora fim de semana (espelha a tela)", () => {
  // sexta 24/07/2026 -> segunda 27/07 = 1 dia útil (não 3)
  assertEquals(businessDaysBetween("2026-07-24T10:00:00Z", new Date("2026-07-27T10:00:00Z")), 1);
  // segunda 20/07 -> sexta 24/07 = 4
  assertEquals(businessDaysBetween("2026-07-20T09:00:00Z", new Date("2026-07-24T09:00:00Z")), 4);
  assertEquals(businessDaysBetween("data inválida", new Date()), 0);
});

Deno.test("isResolved r17: preço registrado ou cotação fechada resolve", async () => {
  const r17 = ruleById("r17")!;
  const mkDb = (row: unknown) => ({
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row }) }) }),
    }),
  });

  // ninguém respondeu ainda → tarefa continua
  assertEquals(
    await r17.isResolved(mkDb({ status: "open", quote_responses: [] }), { automation_key: "r17:quote:x" }),
    null,
  );
  // resposta SEM preço não conta como resposta (ex.: "bom dia, vou ver")
  assertEquals(
    await r17.isResolved(mkDb({ status: "open", quote_responses: [{ unit_price: null }] }), { automation_key: "r17:quote:x" }),
    null,
  );
  assertEquals(
    await r17.isResolved(mkDb({ status: "open", quote_responses: [{ unit_price: 120 }] }), { automation_key: "r17:quote:x" }),
    "Fornecedor respondeu",
  );
  assertEquals(
    await r17.isResolved(mkDb({ status: "closed", quote_responses: [] }), { automation_key: "r17:quote:x" }),
    "Cotação fechada",
  );
  assertEquals(
    await r17.isResolved(mkDb(null), { automation_key: "r17:quote:x" }),
    "Cotação não existe mais",
  );
});

// R18 existe por um caso real: três cotações ficaram 11 dias marcadas como enviadas
// sem que nenhuma mensagem tivesse saído, e a R17 cobrava resposta de fornecedor que
// nunca foi perguntado. A tarefa só se resolve quando o envio de fato acontece.
Deno.test("isResolved r18: só o envio registrado resolve a tarefa", async () => {
  const r18 = ruleById("r18")!;
  const mkDb = (row: unknown) => ({
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row }) }) }),
    }),
  });

  // escolhido mas não enviado → a pendência é nossa e continua
  assertEquals(
    await r18.isResolved(mkDb({ status: "open", quote_request_sends: [] }), { automation_key: "r18:quote:x" }),
    null,
  );
  assertEquals(
    await r18.isResolved(mkDb({ status: "open", quote_request_sends: [{ id: "s1" }] }), { automation_key: "r18:quote:x" }),
    "Cotação enviada",
  );
  // fechar a cotação também encerra: não faz sentido cobrar envio do que foi resolvido
  assertEquals(
    await r18.isResolved(mkDb({ status: "closed", quote_request_sends: [] }), { automation_key: "r18:quote:x" }),
    "Cotação fechada",
  );
  assertEquals(
    await r18.isResolved(mkDb(null), { automation_key: "r18:quote:x" }),
    "Cotação não existe mais",
  );
});

// r6 cobrava "resposta" de OS concluída e paga: o quote_status 'sent' ficava parado (a assinatura
// pelo link muda o status, não o quote_status) e a tarefa não fechava nunca (ORÇ-00070, 03/08).
Deno.test("isResolved r6: só orçamento em rascunho não convertido mantém a tarefa", async () => {
  const r6 = ruleById("r6")!;
  const mkDb = (row: unknown) => ({
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: row }) }) }),
    }),
  });
  const k = { automation_key: "r6:quote:x" };
  assertEquals(await r6.isResolved(mkDb({ quote_status: "sent", status: "draft", converted_to_os_at: null }), k), null);
  assertEquals(await r6.isResolved(mkDb({ quote_status: "awaiting_approval", status: "draft", converted_to_os_at: null }), k), null);
  assertEquals(await r6.isResolved(mkDb({ quote_status: "sent", status: "completed", converted_to_os_at: null }), k), "Deixou de ser orçamento (completed)");
  assertEquals(await r6.isResolved(mkDb({ quote_status: "sent", status: "cancelled", converted_to_os_at: null }), k), "Deixou de ser orçamento (cancelled)");
  assertEquals(await r6.isResolved(mkDb({ quote_status: "sent", status: "draft", converted_to_os_at: "2026-09-01T00:00:00Z" }), k), "Orçamento convertido em OS");
  assertEquals(await r6.isResolved(mkDb({ quote_status: "rejected", status: "draft", converted_to_os_at: null }), k), "Orçamento mudou para rejected");
});

Deno.test("find r6: filtra rascunho não convertido no próprio banco", async () => {
  const r6 = ruleById("r6")!;
  const filtros: string[] = [];
  const q: any = {
    select: () => q,
    in: (c: string, v: unknown) => { filtros.push(`in:${c}:${JSON.stringify(v)}`); return q; },
    eq: (c: string, v: unknown) => { filtros.push(`eq:${c}:${v}`); return q; },
    is: (c: string, v: unknown) => { filtros.push(`is:${c}:${v}`); return q; },
    lt: (c: string) => { filtros.push(`lt:${c}`); return q; },
    limit: async () => ({ data: [] }),
  };
  await r6.find({ from: () => q } as any);
  assertEquals(filtros.includes("eq:status:draft"), true, filtros.join(" "));
  assertEquals(filtros.includes("is:converted_to_os_at:null"), true, filtros.join(" "));
});

// ── R19: orçamento vencido vira AVISO (decisão do dono, 26/09/2026) ──────────────────────
// A rotina quote-reminders rejeitava sozinha orçamentos com 7 dias de criação, inclusive os
// aprovados aguardando sinal (R$ 133 mil em 23-24/09). Estes testes seguram as três coisas que
// importam: o dia do vencimento é o mesmo "até" do PDF (calendário de Brasília), aguardando
// sinal nunca entra, e renovar a validade fecha a tarefa.

/**
 * Banco de mentira que APLICA os filtros sobre as linhas, em vez de ignorá-los: assim o teste
 * prova o que o find pede ao banco (um .in() sem 'awaiting_deposit', um .eq('status','draft')),
 * e não só o que ele faz com a resposta.
 */
// deno-lint-ignore no-explicit-any
function bancoDeOrcamentos(linhas: any[], validadePadrao?: string) {
  return {
    from(tabela: string) {
      if (tabela === "app_settings") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: async () => ({ data: validadePadrao === undefined ? null : { value: validadePadrao } }),
            }),
          }),
        };
      }
      let rows = [...linhas];
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { rows = rows.filter((r) => r[c] === v); return q; },
        is: (c: string, v: unknown) => { rows = rows.filter((r) => (r[c] ?? null) === v); return q; },
        in: (c: string, v: unknown[]) => { rows = rows.filter((r) => v.includes(r[c])); return q; },
        limit: async () => ({ data: rows, error: null }),
        maybeSingle: async () => ({ data: rows[0] ?? null, error: null }),
      };
      return q;
    },
  };
}

const orcamento = (over: Record<string, unknown>) => ({
  id: "o-1",
  service_order_number: "ORÇ-00100",
  client_id: "c-1",
  grand_total: 12500,
  status: "draft",
  quote_status: "sent",
  converted_to_os_at: null,
  created_at: "2026-01-10T15:00:00Z",
  quote_validity_days: 3,
  quote_validity_date: null,
  clients: { name: "Marina Azul" },
  ...over,
});

Deno.test("vencimentoDoOrcamento: vira o dia pelo calendário de Brasília, não pelo UTC", () => {
  // Criado às 23h30 de 19/09 em Brasília = 02h30 UTC de 20/09. Com 3 dias, o PDF imprime
  // "até 22/09" — contar pelo dia UTC daria 23/09 e o aviso sairia um dia atrasado.
  const o = { created_at: "2026-09-20T02:30:00Z", quote_validity_days: 3 };
  // 23h de 22/09 em Brasília (02h UTC de 23/09): ainda é o último dia, não venceu.
  assertEquals(vencimentoDoOrcamento(o, {}, new Date("2026-09-23T02:00:00Z")), null);
  // 00h30 de 23/09 em Brasília (03h30 UTC): venceu, e venceu no dia 22.
  assertEquals(vencimentoDoOrcamento(o, {}, new Date("2026-09-23T03:30:00Z")), "2026-09-22");
  // Meio-dia do último dia: vale.
  assertEquals(vencimentoDoOrcamento(o, {}, new Date("2026-09-22T15:00:00Z")), null);
});

Deno.test("vencimentoDoOrcamento: orçamento → padrão da empresa → 15; data fixa vence tudo", () => {
  const agora = new Date("2026-09-26T15:00:00Z");
  const base = { created_at: "2026-09-10T15:00:00Z" };
  // do próprio orçamento: 10/09 + 3 = 13/09
  assertEquals(vencimentoDoOrcamento({ ...base, quote_validity_days: 3 }, { quote_validity_days: "30" }, agora), "2026-09-13");
  // sem a do orçamento, a da empresa: 10/09 + 5 = 15/09
  assertEquals(vencimentoDoOrcamento({ ...base, quote_validity_days: null }, { quote_validity_days: "5" }, agora), "2026-09-15");
  // sem nenhuma, 15 dias: 25/09, vencido no dia 26
  assertEquals(vencimentoDoOrcamento({ ...base, quote_validity_days: null }, {}, agora), "2026-09-25");
  // data fixa (coluna date) é o próprio último dia
  assertEquals(vencimentoDoOrcamento({ ...base, quote_validity_days: 3, quote_validity_date: "2026-09-30" }, {}, agora), null);
  assertEquals(vencimentoDoOrcamento({ ...base, quote_validity_days: 90, quote_validity_date: "2026-09-20" }, {}, agora), "2026-09-20");
});

Deno.test("find r19: só enviado/aguardando aprovação vencido; aguardando sinal NUNCA", async () => {
  const r19 = ruleById("r19")!;
  const agoraISO = new Date().toISOString();
  const db = bancoDeOrcamentos([
    orcamento({ id: "vencido-enviado" }),
    orcamento({ id: "vencido-aguardando", quote_status: "awaiting_approval", clients: null }),
    // aprovado, aguardando sinal: o cliente já disse sim (o caso do ORÇ-00095)
    orcamento({ id: "aguardando-sinal", quote_status: "awaiting_deposit" }),
    orcamento({ id: "no-prazo", created_at: agoraISO, quote_validity_days: 15 }),
    orcamento({ id: "virou-os", status: "approved" }),
    orcamento({ id: "convertido", converted_to_os_at: "2026-01-12T10:00:00Z" }),
    orcamento({ id: "rejeitado", quote_status: "rejected" }),
    orcamento({ id: "rascunho", quote_status: "draft" }),
  ], "3");
  const tarefas = await r19.find(db);
  assertEquals(tarefas.map((t) => t.related_entity_id).sort(), ["vencido-aguardando", "vencido-enviado"]);

  const t = tarefas.find((x) => x.related_entity_id === "vencido-enviado")!;
  // 10/01 + 3 dias = último dia 13/01: é essa data que vai na chave e no título
  assertEquals(t.automation_key, "r19:quote:vencido-enviado:2026-01-13");
  assertEquals(t.title, "Orçamento ORÇ-00100 venceu em 13/01 — renovar ou rejeitar? (Marina Azul)");
  assertEquals(t.related_entity_type, "service_order");
  assertEquals(t.assignee, "admin");
  assertEquals(entityIdFromKey(t.automation_key), "vencido-enviado");
  // sem cliente, o título não termina com "()"
  assertEquals(tarefas.find((x) => x.related_entity_id === "vencido-aguardando")!.title.endsWith("rejeitar?"), true);
});

Deno.test("find r19: o aviso sai à meia-noite de Brasília, não às 21h (FakeTime)", async () => {
  const r19 = ruleById("r19")!;
  // Criado às 23h30 de 19/09 em Brasília, válido por 3 dias: vale até 22/09.
  const db = () => bancoDeOrcamentos([orcamento({ id: "x", created_at: "2026-09-20T02:30:00Z" })], "15");
  const relogio = new FakeTime(new Date("2026-09-23T02:00:00Z")); // 23h de 22/09 em Brasília
  try {
    assertEquals((await r19.find(db())).length, 0);
    relogio.tick(90 * 60 * 1000); // 00h30 de 23/09 em Brasília
    const [t] = await r19.find(db());
    assertEquals(t.automation_key, "r19:quote:x:2026-09-22");
    // prazo às 08h do dia de Brasília (11h UTC), não do dia UTC
    assertEquals(t.due_at, "2026-09-23T11:00:00Z");
    // a nota conta da emissão pelo dia de Brasília (19/09), não pelo UTC (20/09): para valer
    // mais 3 dias a partir de 23/09 (até 26/09), são 7 dias contados de 19/09
    assertEquals(
      t.notes!.includes("A validade conta da emissão (19/09), não de hoje: para valer até 26/09 " +
        "(3 dias a partir de hoje, 23/09), ponha 7 dias."),
      true,
      t.notes ?? "",
    );
  } finally {
    relogio.restore();
  }
});

// A nota da R19 mandava "aumentar a validade" sem dizer que ela conta da EMISSÃO (D13). Quem
// renovasse um orçamento de 3 dias emitido em 24/09 pondo "3 dias" em 28/09 o deixaria vencido
// do mesmo jeito (vale até 27/09), e a tarefa não fecharia. A nota agora traz a conta pronta.
Deno.test("notaDoVencimento: diz a emissão e dá o número de dias que renova de verdade", () => {
  const o = { created_at: "2026-09-24T15:00:00Z", quote_validity_days: 3, grand_total: 12500 };
  const agora = new Date("2026-09-28T15:00:00Z"); // 28/09 em Brasília; venceu em 27/09
  const nota = notaDoVencimento(o, {}, agora);
  assertEquals(
    nota,
    "Valia até 27/09/2026 (" + fmtBRL(12500) + "). O orçamento NÃO foi rejeitado. " +
      "Para renovar, aumente a validade no orçamento (esta tarefa fecha sozinha). " +
      "A validade conta da emissão (24/09), não de hoje: para valer até 01/10 " +
      "(3 dias a partir de hoje, 28/09), ponha 7 dias. " +
      "Se o cliente desistiu, marque como rejeitado. Nada foi enviado ao cliente.",
  );
  // seguir a nota renova MESMO: com 7 dias o último dia é 01/10 e deixa de estar vencido
  const renovado = { ...o, quote_validity_days: 7 };
  assertEquals(vencimentoDoOrcamento(renovado, {}, agora), null);
  assertEquals(vencimentoDoOrcamento(renovado, {}, new Date("2026-10-02T15:00:00Z")), "2026-10-01");
});

Deno.test("notaDoVencimento: sem validade própria usa a da empresa; vira mês e ano", () => {
  // Emitido 30/12/2026 sem validade própria; empresa = 5 → valia até 04/01/2027.
  const o = { created_at: "2026-12-30T15:00:00Z", quote_validity_days: null, grand_total: 100 };
  const nota = notaDoVencimento(o, { quote_validity_days: "5" }, new Date("2027-01-06T15:00:00Z"));
  assertEquals(nota.startsWith("Valia até 04/01/2027 "), true, nota);
  // 06/01 + 5 = 11/01; de 30/12 até 11/01 são 12 dias
  assertEquals(nota.includes("emissão (30/12), não de hoje: para valer até 11/01 (5 dias a partir de hoje, 06/01), ponha 12 dias."), true, nota);
});

Deno.test("notaDoVencimento: com data fixa, manda trocar a data (dias não a alteram)", () => {
  const o = { created_at: "2026-09-10T15:00:00Z", quote_validity_days: 90, quote_validity_date: "2026-09-20", grand_total: 1 };
  const nota = notaDoVencimento(o, {}, new Date("2026-09-26T15:00:00Z"));
  assertEquals(nota.startsWith("Valia até 20/09/2026 "), true, nota);
  assertEquals(nota.includes("data fixa"), true, nota);
  assertEquals(nota.includes("ponha"), false, nota);
});

Deno.test("find r19: renovar e vencer de novo gera chave nova", async () => {
  const r19 = ruleById("r19")!;
  const [antes] = await r19.find(bancoDeOrcamentos([orcamento({ quote_validity_days: 3 })]));
  const [depois] = await r19.find(bancoDeOrcamentos([orcamento({ quote_validity_days: 10 })]));
  assertEquals(antes.automation_key, "r19:quote:o-1:2026-01-13");
  assertEquals(depois.automation_key, "r19:quote:o-1:2026-01-20");
});

Deno.test("isResolved r19: renovado resolve; decisão tomada resolve; vencido segue", async () => {
  const r19 = ruleById("r19")!;
  const k = { automation_key: "r19:quote:o-1:2026-01-13" };
  const res = (over: Record<string, unknown>) => r19.isResolved(bancoDeOrcamentos([orcamento(over)]), k);

  // nada mudou: segue vencido no mesmo dia → a tarefa continua
  assertEquals(await res({}), null);
  assertEquals(await res({ quote_status: "awaiting_approval" }), null);
  // renovou a validade (a tarefa fecha sozinha)
  assertEquals((await res({ quote_validity_days: 36500 }))?.startsWith("Validade renovada até "), true);
  assertEquals(await res({ quote_validity_date: "2999-12-31" }), "Validade renovada até 31/12/2999");
  // mexeu na validade mas continua vencido: fecha esta, a nova sai com a data certa
  assertEquals(await res({ quote_validity_days: 5 }), "Validade alterada (agora até 15/01/2026)");
  // o dono decidiu, ou o cliente aprovou
  assertEquals(await res({ quote_status: "rejected" }), "Orçamento mudou para rejected");
  assertEquals(await res({ quote_status: "awaiting_deposit" }), "Orçamento mudou para awaiting_deposit");
  assertEquals(await res({ converted_to_os_at: "2026-01-12T10:00:00Z" }), "Orçamento convertido em OS");
  assertEquals(await res({ status: "approved" }), "Deixou de ser orçamento (approved)");
  assertEquals(await r19.isResolved(bancoDeOrcamentos([]), k), "Orçamento não existe mais");
});

Deno.test("isResolved r19: sem validade no orçamento, usa o padrão da empresa", async () => {
  const r19 = ruleById("r19")!;
  // 10/01 + 3 (empresa) = 13/01, igual à chave → segue vencido
  const k = { automation_key: "r19:quote:o-1:2026-01-13" };
  assertEquals(await r19.isResolved(bancoDeOrcamentos([orcamento({ quote_validity_days: null })], "3"), k), null);
  // a empresa passou a 15 dias: último dia agora é 25/01, ainda vencido, mas outra data
  assertEquals(
    await r19.isResolved(bancoDeOrcamentos([orcamento({ quote_validity_days: null })], "15"), k),
    "Validade alterada (agora até 25/01/2026)",
  );
});
