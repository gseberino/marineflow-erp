import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cancelarPendenciaSubstituida,
  decidirPendenciaHerdada,
  formatOptionsAsNumberedText,
  notaDeConfirmacao,
  parseConfirmationReply,
  parseOptionReply,
  pendenciaParaHerdar,
  resolveOptionAsUserText,
  resolveOrCreateWhatsAppSession,
  textoDaPendenciaReapresentada,
} from "./whatsapp-channel.ts";

// ─── Pendência que atravessa a troca de conversa (27/09/2026) ────────────────────────────
// A conversa acaba com 4h sem mensagem; a pendência vale 24h. O "Nao" do dono, 18h depois,
// caiu numa conversa nova sem a pendência e foi para o modelo como frase solta.

const AGORA = new Date("2026-09-27T15:30:00.000Z");
const PENDENCIA_VIVA = { id: "p1", status: "pending", expires_at: "2026-09-27T21:26:28.000Z" };

/** Banco mínimo: sessões e pendências, com filtro por eq e registro do insert. */
function bancoDoCanal(opcoes: { sessoes?: Record<string, unknown>[]; pendencias?: Record<string, unknown>[] } = {}) {
  const inseridas: Record<string, unknown>[] = [];
  const tabelas: Record<string, Record<string, unknown>[]> = {
    ai_operator_sessions: opcoes.sessoes ?? [],
    ai_operator_pending_actions: opcoes.pendencias ?? [],
  };
  const admin = {
    from(nome: string) {
      let linhas = [...(tabelas[nome] ?? [])];
      const q: any = {
        select: () => q,
        eq: (c: string, v: unknown) => { linhas = linhas.filter((l) => l[c] === v); return q; },
        order: () => q,
        limit: () => q,
        maybeSingle: () => Promise.resolve({ data: linhas[0] ?? null, error: null }),
        insert: (linha: Record<string, unknown>) => {
          inseridas.push(linha);
          return { select: () => ({ single: () => Promise.resolve({ data: { id: "nova" }, error: null }) }) };
        },
      };
      return q;
    },
  };
  return { admin, inseridas };
}

Deno.test("pendenciaParaHerdar: a pendência viva passa, com as tentativas de PIN já gastas", async () => {
  const { admin } = bancoDoCanal({ pendencias: [PENDENCIA_VIVA] });
  assertEquals(await pendenciaParaHerdar(admin, { pending_confirm_action_id: "p1", pin_attempts: 2 }, AGORA), {
    pending_confirm_action_id: "p1",
    pin_attempts: 2,
    pendencia_herdada: true,
  });
});

Deno.test("pendenciaParaHerdar: decidida, vencida, inexistente ou sem pendência não passa", async () => {
  const { admin } = bancoDoCanal({
    pendencias: [
      { id: "decidida", status: "rejected", expires_at: PENDENCIA_VIVA.expires_at },
      { id: "vencida", status: "pending", expires_at: "2026-09-27T15:00:00.000Z" },
    ],
  });
  assertEquals(await pendenciaParaHerdar(admin, { pending_confirm_action_id: "decidida" }, AGORA), null);
  assertEquals(await pendenciaParaHerdar(admin, { pending_confirm_action_id: "vencida" }, AGORA), null);
  assertEquals(await pendenciaParaHerdar(admin, { pending_confirm_action_id: "sumiu" }, AGORA), null);
  assertEquals(await pendenciaParaHerdar(admin, { pending_confirm_action_id: null }, AGORA), null);
  assertEquals(await pendenciaParaHerdar(admin, null, AGORA), null);
});

Deno.test("sessão nova depois de 4h leva a pendência viva da anterior", async () => {
  const antiga = {
    id: "s-antiga", channel: "whatsapp", external_thread_key: "5547999990000", status: "open",
    last_activity_at: "2026-09-26T21:26:33.000Z",
    metadata: { pending_confirm_action_id: "p1", pin_attempts: 0 },
  };
  const { admin, inseridas } = bancoDoCanal({ sessoes: [antiga], pendencias: [{ ...PENDENCIA_VIVA, expires_at: "2999-01-01T00:00:00.000Z" }] });
  assertEquals(await resolveOrCreateWhatsAppSession(admin, "5547999990000", "u1"), "nova");
  assertEquals(inseridas[0].metadata, { pending_confirm_action_id: "p1", pin_attempts: 0, pendencia_herdada: true });
});

Deno.test("sessão nova sem pendência viva nasce como sempre (sem metadata)", async () => {
  const antiga = {
    id: "s-antiga", channel: "whatsapp", external_thread_key: "5547999990000", status: "open",
    last_activity_at: "2026-09-26T21:26:33.000Z",
    metadata: { pending_confirm_action_id: null },
  };
  const { admin, inseridas } = bancoDoCanal({ sessoes: [antiga] });
  await resolveOrCreateWhatsAppSession(admin, "5547999990000", "u1");
  assertEquals("metadata" in inseridas[0], false);
});

Deno.test("sessão ativa há menos de 4h é reusada — nada a herdar", async () => {
  const recente = {
    id: "s-recente", channel: "whatsapp", external_thread_key: "5547999990000", status: "open",
    last_activity_at: new Date(Date.now() - 60_000).toISOString(),
    metadata: { pending_confirm_action_id: "p1" },
  };
  const { admin, inseridas } = bancoDoCanal({ sessoes: [recente] });
  assertEquals(await resolveOrCreateWhatsAppSession(admin, "5547999990000", "u1"), "s-recente");
  assertEquals(inseridas.length, 0);
});

Deno.test("pendência herdada: 'não' e 'sim <PIN>' resolvem; aprovação sem PIN reapresenta", () => {
  assertEquals(decidirPendenciaHerdada(parseConfirmationReply("Nao")!), "resolver");
  assertEquals(decidirPendenciaHerdada(parseConfirmationReply("sim 4321")!), "resolver");
  // O resumo das 07:30 chega pelo mesmo número: um "ok" a ele não executa o pedido da véspera.
  for (const t of ["sim", "ok", "1", "s"]) assertEquals(decidirPendenciaHerdada(parseConfirmationReply(t)!), "reapresentar", t);
});

Deno.test("reapresentação diz de quando é o pedido, o que é e como responder", () => {
  const t = textoDaPendenciaReapresentada({
    title: "Enviar orçamento/OS ao cliente (WhatsApp)",
    summary: "Cliente: *Cliente Final*",
    risk_level: "high",
    created_at: "2026-09-26T21:26:28.000Z",
  });
  assertStringIncludes(t, "26/09");
  assertStringIncludes(t, "18:26");
  assertStringIncludes(t, "Enviar orçamento/OS ao cliente");
  assertStringIncludes(t, "Cliente Final");
  assertStringIncludes(t, "sim <SEU PIN>");
  assert(!textoDaPendenciaReapresentada({ title: "X", risk_level: "low" }).includes("PIN"));
});

Deno.test("nota de confirmação: PIN só no risco alto", () => {
  assertStringIncludes(notaDeConfirmacao("high"), "sim <SEU PIN>");
  assertStringIncludes(notaDeConfirmacao("medium"), "Responda *sim* para aprovar");
});

Deno.test("parseConfirmationReply: reconhece aprovação sem PIN", () => {
  assertEquals(parseConfirmationReply("sim"), { decision: "approve", pin: undefined });
  assertEquals(parseConfirmationReply("Sim"), { decision: "approve", pin: undefined });
  assertEquals(parseConfirmationReply("1"), { decision: "approve", pin: undefined });
  assertEquals(parseConfirmationReply("ok"), { decision: "approve", pin: undefined });
});

Deno.test("parseConfirmationReply: reconhece aprovação com PIN", () => {
  assertEquals(parseConfirmationReply("sim 4321"), { decision: "approve", pin: "4321" });
  assertEquals(parseConfirmationReply("SIM 0000"), { decision: "approve", pin: "0000" });
});

Deno.test("parseConfirmationReply: ignora um 2º token que não parece PIN", () => {
  assertEquals(parseConfirmationReply("sim por favor"), { decision: "approve", pin: undefined });
});

Deno.test("parseConfirmationReply: reconhece rejeição", () => {
  assertEquals(parseConfirmationReply("não"), { decision: "reject" });
  assertEquals(parseConfirmationReply("nao"), { decision: "reject" });
  assertEquals(parseConfirmationReply("2"), { decision: "reject" });
  assertEquals(parseConfirmationReply("cancelar"), { decision: "reject" });
});

Deno.test("parseConfirmationReply: texto comum não é confirmação", () => {
  assertEquals(parseConfirmationReply("quantas OS abertas temos?"), null);
  assertEquals(parseConfirmationReply(""), null);
});

Deno.test("parseOptionReply: aceita número dentro do intervalo", () => {
  assertEquals(parseOptionReply("2", 3), 2);
  assertEquals(parseOptionReply(" 1 ", 3), 1);
});

Deno.test("parseOptionReply: rejeita fora do intervalo ou não-numérico", () => {
  assertEquals(parseOptionReply("0", 3), null);
  assertEquals(parseOptionReply("4", 3), null);
  assertEquals(parseOptionReply("abc", 3), null);
  assertEquals(parseOptionReply("1.5", 3), null);
});

Deno.test("formatOptionsAsNumberedText: numera a partir de 1", () => {
  const text = formatOptionsAsNumberedText("Qual cliente?", [
    { label: "João Silva", value: "uuid-1" },
    { label: "Maria Souza", value: "uuid-2" },
  ]);
  assertEquals(text, "Qual cliente?\n1) João Silva\n2) Maria Souza");
});

Deno.test("resolveOptionAsUserText: UUID vira 'label (id: valor)'", () => {
  assertEquals(
    resolveOptionAsUserText({ label: "João Silva — (47) 99999-0000", value: "550e8400-e29b-41d4-a716-446655440000" }),
    "João Silva — (47) 99999-0000 (id: 550e8400-e29b-41d4-a716-446655440000)",
  );
});

Deno.test("resolveOptionAsUserText: __refine__ vira pedido de mais detalhes", () => {
  assertEquals(resolveOptionAsUserText({ label: "🔍 Refinar busca", value: "__refine__" }), "Quero refinar a busca — me peça mais detalhes para encontrar o registro correto.");
});

Deno.test("resolveOptionAsUserText: valor não-UUID vira só o label", () => {
  assertEquals(resolveOptionAsUserText({ label: "Sim", value: "sim" }), "Sim");
});

// ─── Uma pendência por conversa (05/10/2026) ─────────────────────────────────────────────
function bancoDePendencias(viva: boolean) {
  const gravado: { update?: Record<string, unknown>; filtros: unknown[][]; auditoria?: Record<string, unknown> } = { filtros: [] };
  const admin = {
    from(tabela: string) {
      if (tabela === "ai_operator_audit") {
        return { insert: (linha: Record<string, unknown>) => { gravado.auditoria = linha; return Promise.resolve({ error: null }); } };
      }
      const b: Record<string, unknown> = {};
      b.update = (v: Record<string, unknown>) => { gravado.update = v; return b; };
      b.eq = (...a: unknown[]) => { gravado.filtros.push(a); return b; };
      b.select = () => Promise.resolve({ data: viva ? [{ title: "Enviar orçamento/OS ao cliente (WhatsApp)", action_name: "send_service_order_link", session_id: "s1" }] : [], error: null });
      return b;
    },
  };
  return { admin, gravado };
}

Deno.test("pendência nova cancela a anterior que ainda esperava, avisa e audita", async () => {
  const { admin, gravado } = bancoDePendencias(true);
  const aviso = await cancelarPendenciaSubstituida(admin, { pending_confirm_action_id: "velha" }, { pending_confirm_action_id: "nova" }, "u1");
  assertEquals(gravado.update?.status, "rejected");
  assertEquals(gravado.filtros, [["id", "velha"], ["status", "pending"]], "só cancela se ainda estava pendente");
  assertEquals(gravado.auditoria?.event_type, "superseded:send_service_order_link");
  assertEquals(gravado.auditoria?.event_category, "data");
  assertEquals(gravado.auditoria?.actor_kind, "system");
  assertEquals(aviso, "\n\n(O pedido anterior — Enviar orçamento/OS ao cliente (WhatsApp) — foi cancelado: vale só este.)");
});

Deno.test("sem troca de pendência, ou anterior já decidida: não mexe em nada", async () => {
  for (const [antes, depois] of [
    [{}, { pending_confirm_action_id: "nova" }],
    [{ pending_confirm_action_id: "mesma" }, { pending_confirm_action_id: "mesma" }],
    [{ pending_confirm_action_id: "velha" }, { pending_confirm_action_id: null }],
  ] as const) {
    const { admin, gravado } = bancoDePendencias(true);
    assertEquals(await cancelarPendenciaSubstituida(admin, antes, depois, "u1"), "");
    assertEquals(gravado.update, undefined);
  }
  const { admin, gravado } = bancoDePendencias(false);
  assertEquals(await cancelarPendenciaSubstituida(admin, { pending_confirm_action_id: "velha" }, { pending_confirm_action_id: "nova" }, "u1"), "");
  assertEquals(gravado.auditoria, undefined, "já decidida: sem auditoria nem aviso");
});
