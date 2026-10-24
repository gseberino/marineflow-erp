import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import {
  RULES, isRuleEnabled, ruleById, ruleIdFromKey, entityIdFromKey, keyOf, fmtBRL, fmtDate, dueAt,
  isManualDismissal, dismissCooldownDays, businessDaysBetween, vencimentoDoOrcamento, notaDoVencimento,
  cobrancaMinima, dispensaSemFatoNovo, paraAgendar, paraComprar, FILTRO_PARA_AGENDAR, FILTRO_PARA_COMPRAR,
} from "./rules.ts";
import { STATUS_OS } from "../_shared/service-order-status.ts";

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
//
// Até 15/10/2026 o find contava pela RPC (que enxerga material de texto livre) e o isResolved
// recalculava só pelas peças do catálogo. A OS-00104 (aguardando peças, 0 peças, 1 material de
// texto livre: a conversão da geladeira para 12V) nascia e morria a cada 15 min: 1.142 tarefas
// fechadas sozinhas, "OS não tem mais peças lançadas". Agora as duas pontas usam a mesma conta.
// (Reserva e OC aberta já são descontadas pela RPC; a paridade com a tela está em
// supabase/tests/purchase_needs_parity.sql.)
Deno.test("isResolved r16: a mesma conta do find (RPC); material de texto livre mantém a tarefa", async () => {
  const r16 = ruleById("r16")!;
  const OS_00104 = "63f93bbe-4bc7-46d0-b85e-dd434d4038c0";

  const chamadas: unknown[] = [];
  // Qualquer tabela além de service_orders quebra o teste: a conta é toda da RPC.
  const mkDb = (opts: { so?: unknown; faltas?: unknown; erro?: unknown }) => ({
    from: (table: string) => {
      if (table !== "service_orders") throw new Error(`não devia ler ${table}`);
      return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: opts.so }) }) }) };
    },
    rpc: async (nome: string, args: unknown) => {
      chamadas.push({ nome, args });
      return { data: opts.erro ? null : opts.faltas, error: opts.erro ?? null };
    },
  });

  // O caso real: OS-00104 aguardando peças, nenhuma peça do catálogo, a RPC diz 1 falta.
  assertEquals(
    await r16.isResolved(
      mkDb({ so: { status: "awaiting_parts" }, faltas: { [OS_00104]: 1 } }),
      { automation_key: `r16:so:${OS_00104}` },
    ),
    null,
  );
  assertEquals(chamadas.at(-1), { nome: "count_purchase_shortages", args: { p_so_ids: [OS_00104] } });

  // A RPC não traz a OS (em estoque, reservado para ela ou já pedido em OC) → resolvida.
  assertEquals(
    await r16.isResolved(mkDb({ so: { status: "approved" }, faltas: {} }), { automation_key: "r16:so:x" }),
    "Compra resolvida (em estoque ou já pedida)",
  );
  assertEquals(
    await r16.isResolved(mkDb({ so: { status: "approved" }, faltas: null }), { automation_key: "r16:so:x" }),
    "Compra resolvida (em estoque ou já pedida)",
  );
  assertEquals(
    await r16.isResolved(mkDb({ so: { status: "approved" }, faltas: { outra: 2 } }), { automation_key: "r16:so:x" }),
    "Compra resolvida (em estoque ou já pedida)",
  );

  // OS saiu do ciclo de execução → não faz sentido comprar (e nem pergunta à RPC)
  const antes = chamadas.length;
  assertEquals(
    await r16.isResolved(mkDb({ so: { status: "completed" } }), { automation_key: "r16:so:x" }),
    "OS mudou para completed",
  );
  assertEquals(
    await r16.isResolved(mkDb({ so: { status: "cancelled" } }), { automation_key: "r16:so:x" }),
    "OS mudou para cancelled",
  );
  assertEquals(
    await r16.isResolved(mkDb({ so: undefined }), { automation_key: "r16:so:x" }),
    "OS não existe mais",
  );
  assertEquals(chamadas.length, antes);

  // Erro na RPC não vira "resolvida": lança, e o motor mantém a tarefa viva.
  let lancou = false;
  try {
    await r16.isResolved(mkDb({ so: { status: "approved" }, erro: { code: "57014", message: "timeout" } }), { automation_key: "r16:so:x" });
  } catch {
    lancou = true;
  }
  assertEquals(lancou, true);
});

Deno.test("dispensaSemFatoNovo: concluída à mão não volta enquanto falta a mesma coisa", () => {
  const titulo = "Comprar 4 itens — OS-00112 (Nelson)";
  // O dono concluiu à mão (há qualquer tempo): mesma falta = mesma tarefa → não recria.
  assertEquals(dispensaSemFatoNovo({ status: "done", completed_by: "user-1", title: titulo }, titulo), true);
  assertEquals(dispensaSemFatoNovo({ status: "cancelled", completed_by: null, title: titulo }, titulo), true);
  // Mudou o número de itens (ou o cliente): é fato novo → recria.
  assertEquals(dispensaSemFatoNovo({ status: "done", completed_by: "user-1", title: titulo }, "Comprar 5 itens — OS-00112 (Nelson)"), false);
  // Fechada sozinha (completed_by nulo): a condição tinha sumido; se voltou, é nova.
  assertEquals(dispensaSemFatoNovo({ status: "done", completed_by: null, title: titulo }, titulo), false);
  assertEquals(dispensaSemFatoNovo({ status: "pending", completed_by: null, title: titulo }, titulo), false);
  // Só a R16 volta só com fato novo.
  assertEquals(ruleById("r16")!.voltaSoComFatoNovo, true);
  assertEquals(RULES.filter((r) => r.voltaSoComFatoNovo).map((r) => r.id), ["r16"]);
});

// O motor (index.ts sobe o servidor ao ser importado): pelo texto da fonte.
Deno.test("motor: lê só as fechadas À MÃO, com o título, e dispensa sem fato novo", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const bloco = fonte.slice(fonte.indexOf("let candidates = await rule.find(db);"), fonte.indexOf("for (const c of candidates) {"));
  // As 1.142 fechadas sozinhas da OS-00104 passavam do teto de 1.000 linhas do PostgREST.
  assertEquals(bloco.includes('.or("status.eq.cancelled,completed_by.not.is.null")'), true);
  assertEquals(bloco.includes('.select("automation_key, title, status, completed_by, completed_at, updated_at")'), true);
  assertEquals(bloco.includes("if (rule.voltaSoComFatoNovo) {"), true);
  assertEquals(bloco.includes("dispensaSemFatoNovo(r, titulo, mudou)"), true);
  assertEquals(bloco.includes("await rule.mudouDesde(db, r.automation_key, new Date(desde).toISOString())"), true);
  assertEquals(bloco.includes("if (closedErr) throw closedErr;"), true);
});

// Revisão de 15/10/2026: o título da R16 só traz a contagem. Concluída à mão com "Comprar 1 item" e,
// depois, um item NOVO entra na OS com a mesma contagem: a tarefa tem de voltar.
Deno.test("dispensaSemFatoNovo: título igual com item novo na OS depois do fechamento recria", () => {
  const titulo = "Comprar 1 item — OS-00104 (Cliente)";
  const aMao = { status: "done", completed_by: "user-1", title: titulo };
  assertEquals(dispensaSemFatoNovo(aMao, titulo, false), true);
  assertEquals(dispensaSemFatoNovo(aMao, titulo, true), false);
});

Deno.test("r16.mudouDesde: peça ou material lançado/mudado depois do fechamento é fato novo", async () => {
  const r16 = ruleById("r16")!;
  const OS = "96c4af97-44e5-4b4c-89df-8de5caf2ef7f";
  const desde = "2026-08-16T02:22:29.877Z";
  const pedidos: Array<{ tabela: string; eq: unknown[]; or?: string; gt?: unknown[] }> = [];
  // `erro` em todas as tabelas, ou só nas de `errosPorTabela`.
  const mkDb = (linhas: Record<string, unknown[]>, erro?: unknown, errosPorTabela: Record<string, unknown> = {}) => ({
    from: (tabela: string) => ({
      select: () => ({
        eq: (...eq: unknown[]) => {
          const fim = (filtro: { or?: string; gt?: unknown[] }) => ({
            limit: async () => {
              pedidos.push({ tabela, eq, ...filtro });
              const e = erro ?? errosPorTabela[tabela];
              return { data: e ? null : (linhas[tabela] ?? []), error: e ?? null };
            },
          });
          return { or: (or: string) => fim({ or }), gt: (...gt: unknown[]) => fim({ gt }) };
        },
      }),
    }),
  });
  // OS-00051 depois de 16/08/2026 (SELECT de 15/10): nenhuma peça nem material mudou → sem fato
  // novo, a dispensa vale (as recriações de 23/08 e 12/09 com o mesmo título não voltariam).
  assertEquals(await r16.mudouDesde!(mkDb({}), `r16:so:${OS}`, desde), false);
  assertEquals(pedidos.map((p) => p.tabela).sort(), ["os_material", "service_order_parts", "service_order_services"]);
  assertEquals(pedidos[0].eq, ["service_order_id", OS]);
  assertEquals(pedidos[0].or, `created_at.gt.${desde},updated_at.gt.${desde}`);
  // os_material (Agenda de Produção, Fase 1, P2): só a linha mudada DEPOIS do fechamento.
  const material = pedidos.find((p) => p.tabela === "os_material")!;
  assertEquals(material.eq, ["service_order_id", OS]);
  assertEquals(material.gt, ["atualizado_em", desde]);
  // Material de texto livre novo (a falta da OS-00104 era um) ou peça nova → fato novo.
  assertEquals(await r16.mudouDesde!(mkDb({ service_order_services: [{ id: "m1" }] }), `r16:so:${OS}`, desde), true);
  assertEquals(await r16.mudouDesde!(mkDb({ service_order_parts: [{ id: "p1" }] }), `r16:so:${OS}`, desde), true);
  // O que o dono disse da linha mudou depois do fechamento ("não chegou, compro de novo"; a quantidade
  // subiu e derrubou o "na mão") → fato novo.
  assertEquals(await r16.mudouDesde!(mkDb({ os_material: [{ id: "om1" }] }), `r16:so:${OS}`, desde), true);
  // Sem a tabela (migration 160300 não aplicada) ou com erro só nela: lança, não decide às cegas.
  let lancouMaterial = false;
  try {
    await r16.mudouDesde!(mkDb({}, undefined, { os_material: { code: "PGRST205", message: "sem os_material" } }), `r16:so:${OS}`, desde);
  } catch {
    lancouMaterial = true;
  }
  assertEquals(lancouMaterial, true);
  // Erro na leitura não decide sozinho: lança (o motor falha a regra na rodada).
  let lancou = false;
  try {
    await r16.mudouDesde!(mkDb({}, { code: "57014", message: "timeout" }), `r16:so:${OS}`, desde);
  } catch {
    lancou = true;
  }
  assertEquals(lancou, true);
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

// Nenhuma tela edita quote_validity_date (MF-AUD-016: só a conversão de orçamento externo a
// grava). A nota mandava "troque essa data" sem dizer onde — o dono procuraria um campo que
// não existe. Agora diz que a data foi gravada fora da tela e que renovar é ajuste técnico.
Deno.test("notaDoVencimento: com data fixa, diz que ela não se troca pela tela (e não dá conta de dias)", () => {
  const o = { created_at: "2026-09-10T15:00:00Z", quote_validity_days: 90, quote_validity_date: "2026-09-20", grand_total: 1 };
  const nota = notaDoVencimento(o, {}, new Date("2026-09-26T15:00:00Z"));
  assertEquals(nota.startsWith("Valia até 20/09/2026 "), true, nota);
  assertEquals(nota.includes("DATA FIXA, gravada fora da tela do orçamento"), true, nota);
  assertEquals(nota.includes("não há campo na tela para trocá-la"), true, nota);
  assertEquals(nota.includes("ajuste técnico"), true, nota);
  assertEquals(nota.includes("ponha"), false, nota);
  assertEquals(nota.includes("troque essa data"), false, nota);
});

// Sem data fixa e sem emissão legível, a nota dizia "é uma data fixa" — não era.
Deno.test("notaDoVencimento: sem emissão legível NÃO é chamado de data fixa", () => {
  for (const created_at of [null, "", "lixo"]) {
    const nota = notaDoVencimento({ created_at, quote_validity_days: 3, grand_total: 1 }, {}, new Date("2026-09-26T15:00:00Z"));
    assertEquals(nota.toLowerCase().includes("data fixa"), false, nota);
    assertEquals(nota.includes("não tem data de emissão legível"), true, nota);
    assertEquals(nota.includes("ponha"), false, nota);
  }
  // data fixa que não existe (31/02) também não é data fixa: sem emissão, cai no mesmo caso
  const nota = notaDoVencimento({ created_at: null, quote_validity_date: "2026-02-31", grand_total: 1 }, {});
  assertEquals(nota.includes("não tem data de emissão legível"), true, nota);
});

// Sem teto, validade 1e9 fazia a soma de datas lançar RangeError DENTRO do find: o motor
// registrava a falha da regra e nenhum orçamento vencido era avisado (26/09/2026).
Deno.test("find r19: validade 1e9 num orçamento não cala os outros; ele usa a da empresa", async () => {
  const r19 = ruleById("r19")!;
  const tarefas = await r19.find(bancoDeOrcamentos([
    orcamento({ id: "gigante", quote_validity_days: 1e9 }),
    orcamento({ id: "maximo", quote_validity_days: 2147483647 }),
    orcamento({ id: "normal" }),
  ], "3"));
  assertEquals(tarefas.map((t) => t.related_entity_id).sort(), ["gigante", "maximo", "normal"]);
  // 1e9 passa a vez ao padrão da empresa (3): 10/01 + 3 = 13/01
  assertEquals(tarefas.find((t) => t.related_entity_id === "gigante")!.automation_key, "r19:quote:gigante:2026-01-13");
});

Deno.test("find r19: um orçamento que faz a conta lançar fica sem aviso, os outros não", async () => {
  const r19 = ruleById("r19")!;
  // Qualquer dado que a conta não aceite: aqui, uma coluna cuja leitura lança.
  const corrompido = orcamento({ id: "corrompido" });
  Object.defineProperty(corrompido, "quote_validity_days", {
    get() { throw new RangeError("Invalid time value"); },
  });
  const erroOriginal = console.error;
  const registrados: unknown[][] = [];
  console.error = (...args: unknown[]) => { registrados.push(args); };
  try {
    const tarefas = await r19.find(bancoDeOrcamentos([orcamento({ id: "antes" }), corrompido, orcamento({ id: "depois" })], "3"));
    assertEquals(tarefas.map((t) => t.related_entity_id).sort(), ["antes", "depois"]);
  } finally {
    console.error = erroOriginal;
  }
  // registrado com o id, para alguém consertar o dado
  assertEquals(registrados.length, 1);
  assertEquals(String(registrados[0][0]).includes("corrompido"), true, String(registrados[0][0]));
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
  assertEquals((await res({ quote_validity_days: 3650 }))?.startsWith("Validade renovada até "), true);
  // acima do teto (3650) não é renovação: o número não serve e vale o padrão (15, sem empresa)
  assertEquals(await res({ quote_validity_days: 36500 }), "Validade alterada (agora até 25/01/2026)");
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

Deno.test("R15: confirmado só vale para o horário que o cliente confirmou (remarcou → vale de novo pedir)", async () => {
  const { confirmadoParaAData } = await import("./rules.ts");
  assertEquals(confirmadoParaAData("2026-10-02T12:00:00+00:00", "2026-10-02T12:00:00.000Z"), true);
  assertEquals(confirmadoParaAData("2026-10-02T12:00:00+00:00", "2026-10-03T12:00:00.000Z"), false);
  assertEquals(confirmadoParaAData(null, "2026-10-02T12:00:00.000Z"), false);
});

// Cobrança pequena não vira tarefa (06/10/2026): saldo de R$ 20 virava "URGENTE: cliente em atraso".
/** Banco de mentira por tabela: receivables devolve a lista; app_settings devolve o mínimo. */
function bancoDeCobranca(contas: unknown[], minimo?: string) {
  return {
    from(tabela: string) {
      const q: Record<string, unknown> = {};
      for (const m of ["select", "eq", "in", "lt", "lte", "gt", "gte", "order", "limit", "not", "is"]) q[m] = () => q;
      q.maybeSingle = async () => ({ data: tabela === "app_settings" ? (minimo === undefined ? null : { value: minimo }) : contas[0] ?? null });
      q.then = (ok: (r: unknown) => unknown) => Promise.resolve({ data: tabela === "receivables" ? contas : [], error: null }).then(ok);
      return q;
    },
  };
}

Deno.test("cobrancaMinima: o piso da régua (collection_min_amount); sem chave ou inválido = sem corte", async () => {
  assertEquals(await cobrancaMinima(bancoDeCobranca([], "200")), 200);
  assertEquals(await cobrancaMinima(bancoDeCobranca([], "120,5")), 120.5);
  assertEquals(await cobrancaMinima(bancoDeCobranca([])), 0);
  assertEquals(await cobrancaMinima(bancoDeCobranca([], "0")), 0);
  assertEquals(await cobrancaMinima(bancoDeCobranca([], "abc")), 0);
});

Deno.test("r3/r4: conta com saldo abaixo do mínimo não vira tarefa (saldo vazio usa o valor cheio)", async () => {
  const contas = [
    { id: "a", description: "Saldo pequeno", amount: 900, balance_amount: 20, due_date: "2026-10-08", client_id: "c", clients: { name: "X" } },
    { id: "b", description: "Saldo grande", amount: 900, balance_amount: 600, due_date: "2026-10-08", client_id: "c", clients: { name: "X" } },
    { id: "c", description: "Sem saldo gravado", amount: 300, balance_amount: null, due_date: "2026-10-08", client_id: "c", clients: { name: "X" } },
  ];
  for (const id of ["r3", "r4"]) {
    // deno-lint-ignore no-explicit-any
    const tarefas = await ruleById(id)!.find(bancoDeCobranca(contas, "200") as any);
    assertEquals(tarefas.map((t: { automation_key: string }) => t.automation_key), [`${id}:recv:b`, `${id}:recv:c`]);
    // mínimo 0 = cobra tudo, como antes
    // deno-lint-ignore no-explicit-any
    assertEquals((await ruleById(id)!.find(bancoDeCobranca(contas, "0") as any)).length, 3);
  }
});

Deno.test("isResolved r3: tarefa aberta de conta que ficou abaixo do mínimo se fecha sozinha", async () => {
  const r3 = ruleById("r3")!;
  assertEquals(
    // deno-lint-ignore no-explicit-any
    await r3.isResolved(bancoDeCobranca([{ status: "partially_paid", amount: 900, balance_amount: 20 }], "200") as any, { automation_key: "r3:recv:x" }),
    "Saldo abaixo do mínimo de cobrança",
  );
});

// ── "OS OS-" (12/10/2026): o número da OS já traz o prefixo ("OS-00060", "ORÇ-00112"). O título
// da tarefa e o lembrete ao técnico levam o número como vem, sem "OS " na frente.
// deno-lint-ignore no-explicit-any
function bancoDeOs(linhas: any[]) {
  return {
    from() {
      // deno-lint-ignore no-explicit-any
      const q: any = {};
      for (const m of ["select", "eq", "is", "lt", "lte", "gt", "gte", "in", "order", "or"]) q[m] = () => q;
      q.limit = async () => ({ data: linhas, error: null });
      return q;
    },
  };
}

Deno.test("find r1, r2 e r15: o título leva o número da OS como vem, sem 'OS OS-'", async () => {
  const daqui = new Date(Date.now() + 24 * 3600000).toISOString();
  const os = {
    id: "so-60", service_order_number: "OS-00060", client_id: "c-1", status: "approved",
    updated_at: "2026-10-01T12:00:00Z", scheduled_start_at: daqui, client_confirmed_for: null,
    clients: { name: "Marina Azul", phone: "5547999990000", whatsapp: null, opt_out_whatsapp: false },
  };
  // A R1 aplica o predicado (paraAgendar) sobre o que o banco devolveu: aqui, a OS sem data.
  const [t1] = await ruleById("r1")!.find(bancoDeOs([{ ...os, scheduled_start_at: null }]));
  const [t2] = await ruleById("r2")!.find(bancoDeOs([os]));
  const [t15] = await ruleById("r15")!.find(bancoDeOs([os]));
  assertEquals(t1.title, "Agendar OS-00060 — Marina Azul");
  assertEquals(t2.title.startsWith("Verificar OS-00060 parada há "), true, t2.title);
  assertEquals(t15.title.startsWith("Confirmar com Marina Azul a OS-00060 ("), true, t15.title);
  for (const t of [t1, t2, t15]) assertEquals(t.title.includes("OS OS-"), false, t.title);
  // o orçamento segue com o prefixo dele
  const [orc] = await ruleById("r1")!.find(bancoDeOs([{ ...os, scheduled_start_at: null, service_order_number: "ORÇ-00112" }]));
  assertEquals(orc.title, "Agendar ORÇ-00112 — Marina Azul");
});

Deno.test("textoDoLembreteDaOs (r10): 'você tem a OS-00060', com e sem barco", async () => {
  const { textoDoLembreteDaOs } = await import("./rules.ts");
  assertEquals(
    textoDoLembreteDaOs({ quando: "amanhã", hora: "09:00", numero: "OS-00060", cliente: "Marina Azul", barco: "Netuno" }),
    "🔧 Lembrete: amanhã às 09:00 você tem a OS-00060 — Marina Azul (Netuno).",
  );
  assertEquals(
    textoDoLembreteDaOs({ quando: "hoje", hora: "07:30", numero: "OS-00061", cliente: null, barco: null }),
    "🔧 Lembrete: hoje às 07:30 você tem a OS-00061 — cliente.",
  );
  // Com o tipo (decisão 9, 21/10/2026): o técnico sabe se vai a um barco ou a um motorhome.
  assertEquals(
    textoDoLembreteDaOs({ quando: "amanhã", hora: "09:00", numero: "OS-00062", cliente: "Rodrigo", barco: "Iveco Daily", tipo: "Motorhome" }),
    "🔧 Lembrete: amanhã às 09:00 você tem a OS-00062 — Rodrigo (Motorhome Iveco Daily).",
  );
  assertEquals(
    textoDoLembreteDaOs({ quando: "hoje", hora: "07:30", numero: "OS-00063", cliente: "Ana", barco: "Motorhome", tipo: "Motorhome" }),
    "🔧 Lembrete: hoje às 07:30 você tem a OS-00063 — Ana (Motorhome).",
  );
});

// ── Agenda de Produção, Fase 0 (23/10/2026): R1 e R16 veem 'open' e o ORÇ aprovado; R7 respeita a
// OS encerrada; R9 e R13 aposentadas. A carteira abaixo é a real de 23/10 (SELECT f05), só com as
// colunas que as regras leem.
// deno-lint-ignore no-explicit-any
const linhaDaCarteira = (id: string, numero: string, status: string, quote_status: string | null, cliente: string, extra: Record<string, unknown> = {}): any => ({
  id, service_order_number: numero, status, quote_status, client_id: `cli-${numero}`, merged_into_id: null,
  scheduled_start_at: null, updated_at: "2026-10-13T12:00:00Z", clients: { name: cliente }, ...extra,
});
const ID = {
  os69: "dd0bff69-0578-4b06-95fe-5bb460e1d8ac", os74: "10926157-c872-4ab8-9767-dcd96d4cd7ae",
  os100: "0e46d117-ed74-4de1-9334-446da509637b", os96: "4c54607f-84ea-4a9e-b7ea-c53dc905eb87",
  orc83: "8cb61f00-c85d-489d-9ab8-1cfb7a54db4f", orc95: "92165492-234f-4f16-802e-0ecb13f752b6",
  os104: "63f93bbe-4bc7-46d0-b85e-dd434d4038c0", os112: "232c453b-3bc9-4eab-a84c-b0d1209d16eb",
  os32: "dc2b2ae3-1ef7-48fd-b4ff-a5391e2b4ea6", os76: "120c289e-b22e-4006-a772-adb760632c6c",
};
const CARTEIRA = [
  linhaDaCarteira(ID.os69, "OS-00069", "open", "approved", "Vanderlei Andrade"),
  linhaDaCarteira(ID.os74, "OS-00074", "open", "approved", "LENINE LORI BROCCA"),
  linhaDaCarteira(ID.os100, "OS-00100", "open", "approved", "Giancarlo Ribeiro dos Santos"),
  // aprovada com o quote_status 'rejected' (assim está no banco): a R1 olha o status da OS
  linhaDaCarteira(ID.os96, "OS-00096", "approved", "rejected", "Rodrigo"),
  linhaDaCarteira(ID.orc83, "ORÇ-00083", "draft", "approved", "ROBSON"),
  // aguardando sinal: fica fora das duas (já tem R6/R19)
  linhaDaCarteira(ID.orc95, "ORÇ-00095", "draft", "awaiting_deposit", "MP MOTOR HOMES"),
  linhaDaCarteira(ID.os104, "OS-00104", "awaiting_parts", "approved", "Flávio da Igreja", { scheduled_start_at: "2026-10-06T09:00:00Z" }),
  linhaDaCarteira(ID.os112, "OS-00112", "awaiting_parts", "sent", "Nelson"),
  linhaDaCarteira(ID.os32, "OS-00032", "awaiting_client", "approved", "KALMAR PERSONAL BOATS"),
  linhaDaCarteira(ID.os76, "OS-00076", "awaiting_client", "draft", "Rodrigo"),
  // agrupado em outro (não existe hoje; o predicado recusa mesmo assim)
  linhaDaCarteira("orc-agrupado", "ORÇ-00999", "draft", "approved", "Fulano", { merged_into_id: "orc-destino" }),
];
// count_purchase_shortages na carteira de 23/10 (f06/f14). A OS-00076 e o ORÇ-00095 têm falta, mas
// estão fora do recorte da R16 (aguardando cliente / aguardando sinal).
const FALTAS: Record<string, number> = { [ID.os69]: 4, [ID.orc83]: 2, [ID.os112]: 4, [ID.os104]: 1, [ID.os76]: 1, [ID.orc95]: 3 };

/**
 * Banco de mentira da carteira: `.eq('id', x)` filtra (para o isResolved), `.or()`/`.is()`/`.lt()` são
 * só anotados (o predicado da regra é que filtra). A prova de que o filtro do banco diz o mesmo que o
 * predicado é o teste da matriz, logo abaixo.
 */
function bancoDaCarteira(linhas: unknown[], faltas: Record<string, number> = {}, erro?: unknown) {
  const pedidos: string[] = [];
  const rpcs: Array<{ nome: string; ids: string[] }> = [];
  return {
    pedidos, rpcs,
    from(tabela: string) {
      if (tabela !== "service_orders") throw new Error(`não devia ler ${tabela}`);
      // deno-lint-ignore no-explicit-any
      let rows = [...linhas] as any[];
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: (s: string) => { pedidos.push(`select:${s}`); return q; },
        or: (f: string) => { pedidos.push(`or:${f}`); return q; },
        is: (c: string, v: unknown) => { pedidos.push(`is:${c}:${v}`); return q; },
        lt: (c: string) => { pedidos.push(`lt:${c}`); return q; },
        eq: (c: string, v: unknown) => { rows = rows.filter((r) => r[c] === v); return q; },
        limit: async () => ({ data: erro ? null : rows, error: erro ?? null }),
        maybeSingle: async () => ({ data: erro ? null : rows[0] ?? null, error: erro ?? null }),
      };
      return q;
    },
    rpc: async (nome: string, args: { p_so_ids: string[] }) => {
      rpcs.push({ nome, ids: args.p_so_ids });
      return { data: Object.fromEntries(args.p_so_ids.filter((id) => faltas[id]).map((id) => [id, faltas[id]])), error: null };
    },
  };
}

/** Divide por vírgula fora de parênteses (a gramática do `.or()` do PostgREST). */
function partesDoFiltro(s: string): string[] {
  const out: string[] = [];
  let nivel = 0, ini = 0;
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "(") nivel++;
    else if (s[i] === ")") nivel--;
    else if (s[i] === "," && nivel === 0) { out.push(s.slice(ini, i)); ini = i + 1; }
  }
  out.push(s.slice(ini));
  return out;
}

/** Avalia uma condição do PostgREST sobre a linha (só o que as regras usam: eq, in, is.null, and()). */
function avaliaCondicao(c: string, l: Record<string, unknown>): boolean {
  if (c.startsWith("and(")) return partesDoFiltro(c.slice(4, -1)).every((p) => avaliaCondicao(p, l));
  const [col, op, ...resto] = c.split(".");
  const val = resto.join(".");
  const v = l[col] ?? null;
  if (op === "eq") return v === val;
  if (op === "is" && val === "null") return v === null;
  if (op === "in") return val.slice(1, -1).split(",").includes(String(v));
  throw new Error(`operador não previsto no teste: ${c}`);
}

Deno.test("R1/R16: o filtro do banco e o predicado dizem a mesma coisa em todas as combinações", () => {
  // O find pede ao banco o recorte (.or + .is merged_into_id null) e o isResolved relê pelo predicado.
  // Se os dois divergirem em alguma linha, a tarefa dela oscila (nasce e morre a cada 15 min).
  const quotes = [null, "draft", "sent", "awaiting_approval", "awaiting_deposit", "approved", "rejected"];
  let combinacoes = 0;
  for (const status of STATUS_OS) {
    for (const quote_status of quotes) {
      for (const merged_into_id of [null, "outro"]) {
        for (const scheduled_start_at of [null, "2026-10-30T12:00:00Z"]) {
          const l = { status, quote_status, merged_into_id, scheduled_start_at };
          const noBanco = (filtro: string) => l.merged_into_id === null && partesDoFiltro(filtro).some((p) => avaliaCondicao(p, l));
          assertEquals(noBanco(FILTRO_PARA_AGENDAR), paraAgendar(l) !== null, `agendar ${JSON.stringify(l)}`);
          assertEquals(noBanco(FILTRO_PARA_COMPRAR), paraComprar(l) !== null, `comprar ${JSON.stringify(l)}`);
          combinacoes++;
        }
      }
    }
  }
  assertEquals(combinacoes, STATUS_OS.length * quotes.length * 4);
  // O texto que vai ao PostgREST, fixado (sem vírgula em valor: não precisa de orContem).
  assertEquals(FILTRO_PARA_AGENDAR, "and(status.in.(approved,open),scheduled_start_at.is.null),and(status.eq.draft,quote_status.eq.approved)");
  assertEquals(FILTRO_PARA_COMPRAR, "status.in.(approved,open,scheduled,in_progress,awaiting_parts),and(status.eq.draft,quote_status.eq.approved)");
});

Deno.test("paraAgendar/paraComprar: 'os', 'orc' ou nada", () => {
  assertEquals(paraAgendar({ status: "open" }), "os");
  assertEquals(paraAgendar({ status: "approved", scheduled_start_at: "2026-10-30T12:00:00Z" }), null);
  assertEquals(paraAgendar({ status: "scheduled" }), null);
  assertEquals(paraAgendar({ status: "draft", quote_status: "approved" }), "orc");
  // No orçamento a data não decide: o que falta é o sinal.
  assertEquals(paraAgendar({ status: "draft", quote_status: "approved", scheduled_start_at: "2026-10-30T12:00:00Z" }), "orc");
  assertEquals(paraAgendar({ status: "draft", quote_status: "awaiting_deposit" }), null);
  assertEquals(paraAgendar({ status: "draft", quote_status: "approved", merged_into_id: "x" }), null);
  assertEquals(paraComprar({ status: "open" }), "os");
  assertEquals(paraComprar({ status: "awaiting_parts" }), "os");
  assertEquals(paraComprar({ status: "awaiting_client" }), null);
  assertEquals(paraComprar({ status: "completed" }), null);
  assertEquals(paraComprar({ status: "draft", quote_status: "approved" }), "orc");
  assertEquals(paraComprar({ status: "draft", quote_status: "sent" }), null);
});

Deno.test("find r1: carteira real de 23/10 → 4 r1:so e 1 r1:orc, com os títulos", async () => {
  const db = bancoDaCarteira(CARTEIRA);
  const tarefas = await ruleById("r1")!.find(db);
  assertEquals(tarefas.map((t) => [t.automation_key, t.title]).sort(), [
    [`r1:orc:${ID.orc83}`, "ORÇ-00083 aprovado sem sinal — receber o sinal e converter para agendar (ROBSON)"],
    [`r1:so:${ID.os100}`, "Agendar OS-00100 — Giancarlo Ribeiro dos Santos"],
    [`r1:so:${ID.os74}`, "Agendar OS-00074 — LENINE LORI BROCCA"],
    [`r1:so:${ID.os96}`, "Agendar OS-00096 — Rodrigo"],
    [`r1:so:${ID.os69}`, "Agendar OS-00069 — Vanderlei Andrade"],
  ].sort());
  for (const t of tarefas) {
    assertEquals(t.related_entity_type, "service_order"); // o CHECK de agenda_tasks já aceita; nada de tipo novo
    assertEquals(entityIdFromKey(t.automation_key), t.related_entity_id);
    assertEquals([t.priority, t.assignee], ["high", "admin"]);
  }
  // O que vai ao banco: o recorte, sem agrupado, com a carência de 24 h.
  assertEquals(db.pedidos.includes(`or:${FILTRO_PARA_AGENDAR}`), true, db.pedidos.join(" | "));
  assertEquals(db.pedidos.includes("is:merged_into_id:null"), true, db.pedidos.join(" | "));
  assertEquals(db.pedidos.includes("lt:updated_at"), true, db.pedidos.join(" | "));
  // O .select() do PostgREST não é validado: sem estas colunas o predicado leria undefined e a regra
  // não criaria nada, calada.
  const select = db.pedidos.find((p) => p.startsWith("select:"))!;
  for (const c of ["status", "quote_status", "merged_into_id", "scheduled_start_at", "clients(name)"]) {
    assertEquals(select.includes(c), true, `${c} fora do select: ${select}`);
  }
  // Erro de leitura não vira "nada a agendar".
  let lancou = false;
  try { await ruleById("r1")!.find(bancoDaCarteira(CARTEIRA, {}, { code: "57014", message: "timeout" })); } catch { lancou = true; }
  assertEquals(lancou, true);
});

Deno.test("anti-oscilação r1: cada candidato do find, relido pelo isResolved, continua vivo", async () => {
  const r1 = ruleById("r1")!;
  const tarefas = await r1.find(bancoDaCarteira(CARTEIRA));
  assertEquals(tarefas.length, 5);
  for (const t of tarefas) assertEquals(await r1.isResolved(bancoDaCarteira(CARTEIRA), t), null, t.automation_key);
});

Deno.test("isResolved r1 orc: converteu, rejeitou, cancelou ou agrupou resolve; ganhar data não", async () => {
  const r1 = ruleById("r1")!;
  const k = { automation_key: `r1:orc:${ID.orc83}` };
  const res = (extra: Record<string, unknown>) =>
    r1.isResolved(bancoDaCarteira([linhaDaCarteira(ID.orc83, "ORÇ-00083", "draft", "approved", "ROBSON", extra)]), k);
  assertEquals(await res({}), null);
  assertEquals(await res({ scheduled_start_at: "2026-10-30T12:00:00Z" }), null);
  // Converteu (sinal pago): esta fecha e a r1:so nasce na rodada seguinte à carência.
  assertEquals(await res({ status: "open" }), "Orçamento virou OS (Aberta)");
  assertEquals(await res({ status: "approved" }), "Orçamento virou OS (Aprovada)");
  assertEquals(await res({ quote_status: "rejected" }), "Orçamento mudou para rejected");
  assertEquals(await res({ status: "cancelled" }), "Orçamento cancelado");
  assertEquals(await res({ status: "cancelled", merged_into_id: "orc-destino" }), "Orçamento agrupado em outro");
  assertEquals(await r1.isResolved(bancoDaCarteira([]), k), "Orçamento não existe mais");
});

Deno.test("isResolved r1 so: 'open' sem data continua; agendou ou mudou resolve; erro lança", async () => {
  const r1 = ruleById("r1")!;
  const k = { automation_key: `r1:so:${ID.os69}` };
  const res = (extra: Record<string, unknown>) =>
    r1.isResolved(bancoDaCarteira([linhaDaCarteira(ID.os69, "OS-00069", "open", "approved", "Vanderlei Andrade", extra)]), k);
  assertEquals(await res({}), null);
  assertEquals(await res({ scheduled_start_at: "2026-10-30T12:00:00Z" }), "OS foi agendada");
  assertEquals(await res({ status: "scheduled", scheduled_start_at: "2026-10-30T12:00:00Z" }), "OS foi agendada");
  assertEquals(await res({ status: "in_progress" }), "OS mudou para in_progress");
  assertEquals(await r1.isResolved(bancoDaCarteira([]), k), "OS não existe mais");
  // Erro de leitura não pode virar "não existe mais" (a tarefa sumiria com a OS parada).
  let lancou = false;
  try { await r1.isResolved(bancoDaCarteira([], {}, { code: "57014", message: "timeout" }), k); } catch { lancou = true; }
  assertEquals(lancou, true);
});

Deno.test("find r16: inclui 'open' e o ORÇ aprovado; aguardando cliente e aguardando sinal ficam fora", async () => {
  const db = bancoDaCarteira(CARTEIRA, FALTAS);
  const tarefas = await ruleById("r16")!.find(db);
  assertEquals(tarefas.map((t) => [t.automation_key, t.title, t.priority]).sort(), [
    [`r16:so:${ID.os104}`, "Comprar 1 item — OS-00104 (Flávio da Igreja)", "urgent"],
    [`r16:so:${ID.os112}`, "Comprar 4 itens — OS-00112 (Nelson)", "urgent"],
    [`r16:so:${ID.orc83}`, "Comprar 2 itens — ORÇ-00083 (ROBSON)", "high"],
    [`r16:so:${ID.os69}`, "Comprar 4 itens — OS-00069 (Vanderlei Andrade)", "high"],
  ].sort());
  // A RPC só recebe o recorte: nem o aguardando sinal, nem o aguardando cliente, nem o agrupado.
  assertEquals(db.rpcs.length, 1);
  assertEquals(db.rpcs[0].nome, "count_purchase_shortages");
  assertEquals([...db.rpcs[0].ids].sort(), [ID.os69, ID.os74, ID.os100, ID.os96, ID.orc83, ID.os104, ID.os112].sort());
  assertEquals(db.pedidos.includes(`or:${FILTRO_PARA_COMPRAR}`), true, db.pedidos.join(" | "));
  assertEquals(db.pedidos.includes("is:merged_into_id:null"), true, db.pedidos.join(" | "));
  const select = db.pedidos.find((p) => p.startsWith("select:"))!;
  for (const c of ["status", "quote_status", "merged_into_id"]) assertEquals(select.includes(c), true, `${c} fora do select: ${select}`);
  let lancou = false;
  try { await ruleById("r16")!.find(bancoDaCarteira(CARTEIRA, FALTAS, { code: "57014", message: "timeout" })); } catch { lancou = true; }
  assertEquals(lancou, true);
});

Deno.test("anti-oscilação r16: cada candidato do find, relido pelo isResolved, continua vivo", async () => {
  const r16 = ruleById("r16")!;
  const tarefas = await r16.find(bancoDaCarteira(CARTEIRA, FALTAS));
  assertEquals(tarefas.length, 4);
  for (const t of tarefas) assertEquals(await r16.isResolved(bancoDaCarteira(CARTEIRA, FALTAS), t), null, t.automation_key);
});

Deno.test("isResolved r16: orçamento aprovado com falta não resolve; se deixar de ser aprovado, resolve", async () => {
  const r16 = ruleById("r16")!;
  const k = { automation_key: `r16:so:${ID.orc83}` };
  const banco = (extra: Record<string, unknown>) =>
    bancoDaCarteira([linhaDaCarteira(ID.orc83, "ORÇ-00083", "draft", "approved", "ROBSON", extra)], FALTAS);
  // Antes, todo 'draft' resolvia: com o ORÇ aprovado no find, a tarefa oscilaria.
  assertEquals(await r16.isResolved(banco({}), k), null);
  // Converteu e a falta segue: a mesma tarefa (mesma chave) continua.
  assertEquals(await r16.isResolved(banco({ status: "open" }), k), null);
  const semRpc = banco({ quote_status: "sent" });
  assertEquals(await r16.isResolved(semRpc, k), "Orçamento mudou para sent");
  assertEquals(semRpc.rpcs.length, 0);
  assertEquals(await r16.isResolved(banco({ status: "cancelled", merged_into_id: "orc-destino" }), k), "Orçamento agrupado em outro");
  // Comprou (ou pediu em OC): a RPC deixa de trazer o orçamento.
  assertEquals(await r16.isResolved(bancoDaCarteira([linhaDaCarteira(ID.orc83, "ORÇ-00083", "draft", "approved", "ROBSON")], {}), k),
    "Compra resolvida (em estoque ou já pedida)");
});

/** Banco de mentira das OCs: `.eq('id', x)` e `.in('status', ...)` filtram; o embed da OS vem pronto em cada linha. */
function bancoDeOcs(linhas: unknown[], erro?: unknown) {
  const selects: string[] = [];
  return {
    selects,
    from(tabela: string) {
      if (tabela !== "purchase_orders") throw new Error(`não devia ler ${tabela}`);
      // deno-lint-ignore no-explicit-any
      let rows = [...linhas] as any[];
      // deno-lint-ignore no-explicit-any
      const q: any = {
        select: (s: string) => { selects.push(s); return q; },
        in: (c: string, v: unknown[]) => { rows = rows.filter((r) => v.includes(r[c])); return q; },
        eq: (c: string, v: unknown) => { rows = rows.filter((r) => r[c] === v); return q; },
        limit: async () => ({ data: erro ? null : rows, error: erro ?? null }),
        maybeSingle: async () => ({ data: erro ? null : rows[0] ?? null, error: erro ?? null }),
      };
      return q;
    },
  };
}

// OC-00001 (Mercado Pago): 'sent', prevista para 04/08, OS-00073 faturada — cobrada pela R7 desde 23/08.
const OC_00001 = "121e9ddc-859a-491e-a855-7360ba4b7717";
const oc = (id: string, os: string | null, extra: Record<string, unknown> = {}) => ({
  id, po_number: `OC-${id}`, status: "sent", expected_date: "2026-08-04", created_at: "2026-07-31T12:00:00Z",
  suppliers: { name: "MERCADO PAGO INSTITUICAO DE PAGAMENTO LTDA" },
  service_orders: os ? { status: os } : null, ...extra,
});

Deno.test("find r7: OC de OS concluída, faturada ou cancelada não é cobrada", async () => {
  const db = bancoDeOcs([
    oc(OC_00001, "invoiced"),
    oc("oc-concluida", "completed"),
    oc("oc-cancelada", "cancelled"),
    oc("oc-os-viva", "awaiting_parts"),
    oc("oc-sem-os", null),
    oc("oc-no-prazo", "awaiting_parts", { expected_date: "2999-01-01" }),
    oc("oc-recebida", "awaiting_parts", { status: "received" }),
  ]);
  const tarefas = await ruleById("r7")!.find(db);
  assertEquals(tarefas.map((t) => t.automation_key).sort(), ["r7:po:oc-os-viva", "r7:po:oc-sem-os"]);
  // A FK com nome (a única de purchase_orders para service_orders).
  assertEquals(db.selects[0].includes("service_orders!purchase_orders_service_order_id_fkey(status)"), true, db.selects[0]);
  let lancou = false;
  try { await ruleById("r7")!.find(bancoDeOcs([], { code: "PGRST201", message: "ambíguo" })); } catch { lancou = true; }
  assertEquals(lancou, true);
});

Deno.test("isResolved r7: a OS da OC encerrou → resolve; OS viva segue; erro lança", async () => {
  const r7 = ruleById("r7")!;
  const k = (id: string) => ({ automation_key: `r7:po:${id}` });
  // A tarefa viva da OC-00001 (de 23/08) fecha sozinha no 1º ciclo.
  assertEquals(await r7.isResolved(bancoDeOcs([oc(OC_00001, "invoiced")]), k(OC_00001)), "A OS da OC foi faturada");
  assertEquals(await r7.isResolved(bancoDeOcs([oc("x", "completed")]), k("x")), "A OS da OC foi concluída");
  assertEquals(await r7.isResolved(bancoDeOcs([oc("x", "cancelled")]), k("x")), "A OS da OC foi cancelada");
  assertEquals(await r7.isResolved(bancoDeOcs([oc("x", "awaiting_parts")]), k("x")), null);
  assertEquals(await r7.isResolved(bancoDeOcs([oc("x", null)]), k("x")), null);
  assertEquals(await r7.isResolved(bancoDeOcs([oc("x", "invoiced", { status: "received" })]), k("x")), "OC recebida");
  assertEquals(await r7.isResolved(bancoDeOcs([]), k("x")), "OC não existe mais");
  let lancou = false;
  try { await r7.isResolved(bancoDeOcs([], { code: "57014", message: "timeout" }), k("x")); } catch { lancou = true; }
  assertEquals(lancou, true);
});

// d13 (23/10/2026): o motor não manda nada a cliente. O index.ts sobe o servidor ao ser importado:
// pelo texto da fonte, como o teste do motor acima.
Deno.test("motor: R9 e R13 aposentadas; o responsável vem de responsavel.ts", async () => {
  const fonte = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  for (const proibido of [
    "task_rule_r9_enabled", "task_rule_r13_enabled", "runClientReminders", "runPostServiceSurvey",
    "agenda-r9", "agenda-r13", "reminder_sent_at",
  ]) {
    assertEquals(fonte.includes(proibido), false, `index.ts ainda tem ${proibido}`);
  }
  // Agenda de Produção, Fase 1 (P2): o passo do material entra no resumo, e nada que fale com cliente.
  assertEquals(fonte.includes("const summary = { identidade, fios, agenda_material: agendaMaterial, rules, r10, reminders, recurrence };"), true);
  assertEquals(fonte.includes('import { resolveAssignee } from "./responsavel.ts";'), true);
  assertEquals(/async function resolveAssignee/.test(fonte), false);
});
